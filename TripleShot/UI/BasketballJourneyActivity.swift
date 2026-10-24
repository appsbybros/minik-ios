import Foundation

// Port of ui/BasketballJourneyActivity.kt (Android 6c38131), statement by statement (spec 25 sections 4.3,
// 4.4, 6.2, 7.3, 8.1-8.11): the Daily Court Journey (brief, list, game, result pages) and the app's Settings page, every
// view built in code as in Kotlin, the game page driving an embedded TripleShotTeamCourtView in practice mode.
//
// - Restylers: onCreate installs FamilySkyUi.watch and TripleShotControls.watch on the decor view like Android, so the
//   card X ("fixed-close"), the game Back/Pause/Help buttons (converted by title into 52x52 close/pause/help icons,
//   not moved because of the "game-controls" tag) and the sky faces look as on the device.
// - Persistence: SharedPreferences "basketball_journey" (step, stars, day, receipts, saved, savedStep, sound), the
//   same file BasketballAudio reads for `sound`. `saved` is Android's JSONArray text ("[3.25,0]").
// - Beep: AToneGenerator(STREAM_MUSIC, 25).startTone(TONE_PROP_ACK, 65): the AOSP tone sequencer port (one 1200 Hz
//   beep cut at 65 ms).
// - Settings: "More Minik apps & games" is FamilyBridge.showMoreApps with the family adult gate (FamilyAdultGate.open);
//   rate / share / feedback go through the fixed "8 × 7 = ?" gate (answer "56"). The App Store id of Triple Shot is
//   not known yet and the family catalogue's "tripleshot" entry has no iOS link, so the Android intents are kept:
//   AIntent maps the own Play listing to the App Store rating prompt (Rate) and rewrites it to the catalogue landing
//   page in the shared text (Share); mailto: opens the mail app (Feedback).
// - Not ported (QA only, DESIGN 3): `qa` (BuildConfig.DEBUG && intent "qaCapture"), the "basketball_journey_qa" file
//   and the `qaLocale` override; production is qa == false.
// - Quirks kept: the portrait panel height follows the HUD text (the court re-measures when the shot meter line
//   appears); the Pause icon stays "play" when Help resumes a paused game; the break controls fade 3 s after each
//   possession restart and are INVISIBLE (untouchable, space kept) until the next restart; `start()` keeps Android's
//   `require(step >= 0)` (BasketballPractice) for a corrupt negative savedStep; the status bar keeps the theme's
//   light-bar appearance (AndroidKit's Android 15+ edge-to-edge window; DESIGN 12 lists no deviation).
// - iOS-only (DESIGN 2.8 / 12.3): while the game's break controls are hidden, Android's only way out is the system
//   Back key (save + brief). Here a tap on the game panel (HUD / progress bar column) while they are INVISIBLE shows
//   them again (showBreakControls), which makes the existing Back control reachable; nothing else changes.

final class BasketballJourneyActivity: AActivity {
    // Kotlin: `getSharedPreferences(if (qa) "basketball_journey_qa" else "basketball_journey", 0)`.
    private lazy var prefs: ASharedPreferences = getSharedPreferences("basketball_journey", 0)
    /// Kotlin `he`: `configuration.locales[0].language in listOf("he", "iw")` (the qaLocale branch is QA only).
    private var he: Bool { return ["he", "iw"].contains(resources.configuration.locales[0].language) }
    private func tr(en: String, hebrew: String) -> String { return he ? hebrew : en }
    private(set) var practice: BasketballPractice? = nil
    private(set) var court: TripleShotTeamCourtView? = nil
    private var breakControls: ALinearLayout? = nil
    private func showBreakControls() {
        guard let controls = breakControls else { return }
        controls.animate().cancel(); controls.visibility = AView.VISIBLE; controls.alpha = 1
        controlsGeneration += 1
        let token = controlsGeneration
        controls.postDelayed({ [weak self, weak controls] in
            guard let self = self, let controls = controls else { return }
            if token == self.controlsGeneration && self.page == "game" && !self.paused {
                controls.animate().alpha(0).setDuration(300).withEndAction({ [weak controls] in controls?.visibility = AView.INVISIBLE }).start()
            }
        }, 3000)
    }
    private var controlsGeneration = 0
    private var page = "brief"; private var hud: ATextView? = nil; private var bar: AProgressBar? = nil
    private var resumed = false; private var ready = false; private var paused = false; private var generation = 0
    private var tone: AToneGenerator? = nil
    private let ink = argbInt(0xff243850); private let blue = argbInt(0xffb9ebf4); private let gold = argbInt(0xffffd578)
    private func dp(v: Int) -> Int { return (v.toFloat() * resources.displayMetrics.density).toInt() }

    override func onCreate(_ savedInstanceState: ABundle?) {
        super.onCreate(savedInstanceState)
        if prefs.getInt("stageSchema", 1) < 2 {
            // Steps saved with 20 stages per cycle keep their cycle and stage on the longer list.
            func migrate(n: Int) -> Int { return n / 20 * BasketballJourney.stages.count + n % 20 }
            prefs.edit().putInt("step", migrate(n: prefs.getInt("step", 0))).putInt("savedStep", migrate(n: prefs.getInt("savedStep", 0))).putInt("stageSchema", 2).apply()
        }
        BasketballSoundscape.scene(activity: self, value: .MENU)
        FamilySkyUi.watch(root: window.decorView)
        TripleShotControls.watch(root: window.decorView)
        // QA text and direction use qaLocale directly. Never mutate process-wide resources:
        // doing so leaks the last test language into subsequently opened activities.
        window.decorView.layoutDirection = he ? AView.LAYOUT_DIRECTION_RTL : AView.LAYOUT_DIRECTION_LTR
        AWindowCompat.setDecorFitsSystemWindows(window, true)
        window.statusBarColor = ink
        if intent.getStringExtra("page") == "settings" { settings() } else { brief() }
        onBackPressedDispatcher.addCallback(self, AOnBackPressedCallback(true) { [weak self] _ in
            guard let self = self else { return }
            if self.page == "game" { self.save(); self.brief() } else if self.page == "list" { self.brief() } else { self.finish() }
        })
    }

    override func onResume() { super.onResume(); resumed = true; if page == "game" && ready && !paused { restartPossession() } }
    override func onPause() { resumed = false; save(); court?.clearForQuestion(); tone?.release(); tone = nil; super.onPause() }
    override func onDestroy() { generation += 1; court?.practiceAction = nil; court?.clearForQuestion(); tone?.release(); super.onDestroy() }
    override func onConfigurationChanged(_ newConfig: AConfiguration) { super.onConfigurationChanged(newConfig); court?.requestLayout() }

    private func content(view: AView) {
        let frame = AFrameLayout(); frame.setBackgroundColor(ink); frame.addView(view, AFrameLayout.LayoutParams(-1, -1))
        AViewCompat.setOnApplyWindowInsetsListener(frame) { v, insets in
            let bars = insets.getInsets(AWindowInsetsCompat.Types.systemBars() | AWindowInsetsCompat.Types.displayCutout())
            v.setPadding(bars.left, bars.top, bars.right, bars.bottom)
            return insets
        }
        setContentView(frame); AViewCompat.requestApplyInsets(frame)
    }

    private func shape(color: Int) -> FamilySkyDrawable {
        let face = FamilySkyDrawable(); face.setColor(color); face.cornerRadius = dp(v: 22).toFloat()
        return face
    }

    private func label(s: String, size: Float = 18) -> ATextView {
        let view = ATextView(); view.text = s; view.textSize = size; view.setTextColor(ink); view.gravity = AGravity.CENTER
        view.setPadding(dp(v: 10), dp(v: 8), dp(v: 10), dp(v: 8))
        return view
    }

    private func button(s: String, action: @escaping () -> Void) -> TripleShotButton {
        let view = TripleShotButton(); view.text = s; view.isAllCaps = false; view.textSize = 16; view.setTextColor(ink)
        view.minHeight = dp(v: 52); view.background = shape(color: blue); view.setPadding(dp(v: 10), dp(v: 8), dp(v: 10), dp(v: 8))
        view.setOnClickListener { _ in action() }
        return view
    }

    private func card(title: String) -> ALinearLayout {
        BasketballSoundscape.scene(activity: self, value: .MENU)
        generation += 1; court?.practiceAction = nil; court?.clearForQuestion(); court = nil; hud = nil; bar = nil
        let root = AFrameLayout()
        root.background = AGradientDrawable(AGradientDrawable.Orientation.TL_BR, [argbInt(0xffcef2eb), argbInt(0xffffdfaf), argbInt(0xffccd9ff)])
        let sc = AScrollView(); sc.isFillViewport = true; let wrap = FamilyReadingPanel()
        let body = ALinearLayout(); body.orientation = ALinearLayout.VERTICAL
        body.setPadding(dp(v: 18), dp(v: 18), dp(v: 18), dp(v: 24)); body.background = shape(color: argbInt(0xfaffffff))
        let closeRow = ALinearLayout(); closeRow.gravity = AGravity.END | AGravity.CENTER_VERTICAL
        closeRow.setPadding(dp(v: 4), dp(v: 4), dp(v: 4), dp(v: 10))
        closeRow.setPadding(0, dp(v: 1), 0, dp(v: 8))
        let close = button(s: tr(en: "Back", hebrew: "חזרה")) { [weak self] in
            guard let self = self else { return }
            if self.page == "list" { self.brief() } else { self.finish() }
        }
        TripleShotControls.icon(button: close, kind: "close", label: tr(en: "Back", hebrew: "חזרה")); close.setTag("fixed-close")
        closeRow.addView(close, ALinearLayout.LayoutParams(dp(v: 52), dp(v: 52)))
        body.addView(closeRow); body.addView(label(s: title, size: 26))
        // The 680 dp width for sw >= 600 is dead: FamilyReadingPanel.onMeasure overwrites lp.width (kept as on Android).
        let bodyParams = AFrameLayout.LayoutParams(resources.configuration.smallestScreenWidthDp >= 600 ? dp(v: 680) : -1, -2,
                                                   AGravity.TOP | AGravity.CENTER_HORIZONTAL)
        bodyParams.setMargins(dp(v: 14), 0, dp(v: 14), dp(v: 20))
        wrap.addView(body, bodyParams)
        sc.addView(wrap); root.addView(sc); content(view: root); return body
    }

    private func action(body: ALinearLayout, s: String, block: @escaping () -> Void) {
        let view = button(s: s, action: block)
        let params = ALinearLayout.LayoutParams(-1, -2); params.topMargin = dp(v: 10)
        body.addView(view, params)
    }

    private func name(s: BasketballStage) -> String { return he ? s.he : s.en }

    func brief() {
        page = "brief"; practice = nil; let n = prefs.getInt("step", 0); let s = BasketballJourney.stage(step: n)
        let body = card(title: tr(en: "Your daily court journey", hebrew: "אתגר יומי"))
        body.addView(label(s: tr(en: "A little practice each day. Your first completed stage earns a daily bonus. Play more whenever you like. Missing a day never erases progress.", hebrew: "קצת אימון בכל יום. השלב הראשון שתשלימו מזכה בבונוס יומי. אפשר להמשיך מתי שרוצים. יום ללא משחק אינו מוחק התקדמות."), size: 16))
        body.addView(label(s: "\u{2066}\(n % BasketballJourney.stages.count + 1) / \(BasketballJourney.stages.count)\u{2069} \u{00B7} " + tr(en: "Cycle", hebrew: "מסלול") + " \(n / BasketballJourney.stages.count + 1)", size: 17)); body.addView(label(s: name(s: s), size: 25))
        body.addView(label(s: tr(en: "First learn without rushing. Later stages combine skills and add defenders. We choose teammates and opponents by the qualities this skill needs.", hebrew: "קודם לומדים בלי למהר. בהמשך משלבים מיומנויות ומוסיפים שומרים. בוחרים חברי קבוצה ויריבים לפי הכישורים שהמיומנות הזאת דורשת."), size: 16))
        body.addView(label(s: s.helping ? tr(en: "Helpful partners start strong. Later cycles bring less skilled helpers, so your own timing matters more.", hebrew: "השותפים מתחילים עם כישורים חזקים. במסלולים הבאים העזרה פחות מיומנת והתזמון שלכם חשוב יותר.") : tr(en: "Defensive practice starts against a gentle ball handler. Later cycles bring quicker, more skilled opponents.", hebrew: "אימון ההגנה מתחיל מול יריב עדין. במסלולים הבאים פוגשים יריבים זריזים ומיומנים יותר."), size: 16))
        for goal in s.goals { body.addView(label(s: instruction(skill: goal.skill), size: 16)) }
        action(body: body, s: tr(en: "Start challenge", hebrew: "מתחילים באתגר")) { [weak self] in self?.start(step: n) }
        if prefs.contains("saved") {
            action(body: body, s: tr(en: "Resume practice", hebrew: "המשך אימון")) { [weak self] in
                guard let self = self else { return }
                // `runCatching { JSONArray(prefs.getString("saved", "[]")) -> [getDouble(i)] }.getOrDefault(emptyList())`
                let values: [Double]
                do {
                    guard let json = self.prefs.getString("saved", "[]") else { throw AJSONException(message: "null") }
                    let a = try AJSONArray(json)
                    values = try kuntil(0, a.length()).map { try a.getDouble($0) }
                } catch {
                    values = []
                }
                self.start(step: self.prefs.getInt("savedStep", n), counts: values)
            }
        }
        action(body: body, s: tr(en: "Your journey", hebrew: "המסע שלכם")) { [weak self] in self?.list() }
        body.setPadding(body.paddingLeft, body.paddingTop, body.paddingRight, 0)
        body.addView(label(s: tr(en: "Practice stars", hebrew: "כוכבי אימון") + ": \(prefs.getInt("stars", 0))", size: 18), ALinearLayout.LayoutParams(-1, dp(v: 88)))
    }

    private func list() {
        page = "list"; let body = card(title: tr(en: "Your journey", hebrew: "המסע שלכם")); let current = prefs.getInt("step", 0)
        for (i, s) in BasketballJourney.stages.enumerated() {
            let prefix = i < current % BasketballJourney.stages.count ? "\u{2713}" : i == current % BasketballJourney.stages.count ? "\u{2605}" : "\u{25CB}"
            body.addView(label(s: "\(prefix) \(i + 1). \(name(s: s))"))
            if i < current % BasketballJourney.stages.count {
                let params = ALinearLayout.LayoutParams(-1, dp(v: 56)); params.topMargin = dp(v: 16); params.bottomMargin = dp(v: 16)
                body.addView(button(s: tr(en: "Practise again", hebrew: "מתאמנים שוב")) { [weak self] in self?.start(step: current / BasketballJourney.stages.count * BasketballJourney.stages.count + i) }, params)
            }
        }
    }

    private func instruction(skill: BasketballSkill) -> String {
        switch skill {
        case .MOVE: return tr(en: "Swipe to dribble. Move through the court while keeping the ball; only your own movement counts.", hebrew: "החליקו כדי לכדרר. זוזו במגרש כשהכדור אצלכם; רק התנועה שלכם נספרת.")
        case .PASS: return tr(en: "Tap a teammate to pass. Wait until the ball arrives. Control follows the receiver, so you can pass back.", hebrew: "הקישו על חבר קבוצה כדי למסור. חכו שהכדור יגיע. השליטה עוברת למקבל ואפשר למסור בחזרה.")
        case .RELEASE: return tr(en: "With the ball, hold still on the court. Release when the shot meter reaches 65% or more. Moving cancels the shot.", hebrew: "כשהכדור אצלכם, לחצו בלי לזוז על המגרש. שחררו כשהמד מגיע ל־65% לפחות. תנועה מבטלת את הזריקה.")
        case .BASKET: return tr(en: "Dribble closer for an easier shot. Hold, then release at a strong meter. Only baskets from your own shots count.", hebrew: "כדררו קרוב יותר לזריקה נוחה. לחצו ושחררו כשהמד גבוה. רק סלים מהזריקות שלכם נספרים.")
        case .SWITCH: return tr(en: "While the opponents have the ball, tap another teammate to switch defender. Follow the ball together.", hebrew: "כשהכדור אצל היריבים, הקישו על חבר קבוצה אחר כדי להחליף שומר. עקבו יחד אחרי הכדור.")
        case .STEAL: return tr(en: "Swipe close to the ball handler, then tap the court to try a steal or block. A clean catch counts; keep trying without rushing.", hebrew: "החליקו קרוב למחזיק הכדור ואז הקישו במגרש כדי לנסות לחטוף או לחסום. רק חטיפה מוצלחת נספרת; אפשר לנסות בנחת.")
        case .SCREEN: return tr(en: "With the ball, hold a teammate to ask for a screen. Wait for the teammate to reach and block the defender, then move into the space.", hebrew: "כשהכדור אצלכם, לחצו לחיצה ארוכה על חבר קבוצה כדי לבקש חסימה. חכו שיגיע ויחסום את השומר ואז נועו לשטח שהתפנה.")
        case .CROSSOVER: return tr(en: "With the ball, swipe left, right, left (or the reverse). The ball changes hands; stay in control of your movement.", hebrew: "כשהכדור אצלכם, החליקו שמאלה, ימינה, שמאלה — או להפך. הכדור מחליף ידיים ואתם ממשיכים לשלוט בתנועה.")
        case .BEHIND_BACK: return tr(en: "Make two left-right-left moves in quick succession. The second hand change goes behind your back. Move into the space you create.", hebrew: "בצעו פעמיים ברצף שמאלה–ימינה–שמאלה. בהחלפה השנייה הכדור עובר מאחורי הגב. נועו לשטח שהתפנה.")
        case .SPIN: return tr(en: "With the ball, draw a small circle on the court to spin. Near a guard, it may create space. A quick repeat improves your chance, but never guarantees escape.", hebrew: "כשהכדור אצלכם, ציירו עיגול קטן על המגרש כדי להסתובב. ליד שומר זה עשוי לפנות מקום. ניסיון נוסף מיד אחר כך משפר את הסיכוי, אך לא מבטיח הצלחה.")
        case .ALLEY: return tr(en: "With the ball, double-tap a teammate for an alley-oop. An open passing lane helps. Only a completed team finish counts.", hebrew: "כשהכדור אצלכם, הקישו פעמיים על חבר קבוצה לאלי־אופ. נתיב מסירה פנוי עוזר. רק סיום קבוצתי מוצלח נספר.")
        }
    }

    /// The helpers and opponents of start() (inline in Kotlin; a function here so the parity tests can check the picks):
    /// `used = mutableSetOf("woman_dark")`, then `(1 until teamSize)` helper picks and `(0 until teamSize)` opponent
    /// picks, each pick's id added to `used`.
    static func lineup(stage: BasketballStage, cycle: Int) -> (helpers: [String], opponents: [String]) {
        var used: Set<String> = ["woman_dark"]
        let helpers = kuntil(1, stage.teamSize).map { _ -> String in
            let bot = stage.bot(cycle: cycle, excluded: used, helper: true); used.insert(bot.id); return bot.id
        }
        let opponents = kuntil(0, stage.teamSize).map { _ -> String in
            let bot = stage.bot(cycle: cycle, excluded: used, helper: false); used.insert(bot.id); return bot.id
        }
        return (helpers: helpers, opponents: opponents)
    }

    func start(step: Int, counts: [Double] = []) {
        BasketballSoundscape.scene(activity: self, value: .COURT)
        generation += 1; let token = generation; practice = BasketballPractice(step: step, restored: counts); page = "game"; paused = false; ready = false
        let p = practice!; let stage = p.stage
        let lineup = BasketballJourneyActivity.lineup(stage: stage, cycle: p.cycle)
        let helpers = lineup.helpers
        let opponents = lineup.opponents
        let panel = ALinearLayout(); panel.orientation = ALinearLayout.VERTICAL; panel.setBackgroundColor(ink)
        let controls = ALinearLayout(); controls.setTag("game-controls"); breakControls = controls
        let entries: [(first: String, second: () -> Void)] = [
            (first: tr(en: "Back", hebrew: "חזרה"), second: { [weak self] in
                guard let self = self else { return }
                self.save(); self.brief()
            }),
            (first: tr(en: "Pause", hebrew: "השהיה"), second: { [weak self, weak controls] in
                guard let self = self else { return }
                self.paused = !self.paused
                if let it = controls?.getChildAt(1) as? AButton {
                    TripleShotControls.icon(button: it, kind: self.paused ? "play" : "pause",
                                            label: self.paused ? self.tr(en: "Continue", hebrew: "המשך") : self.tr(en: "Pause", hebrew: "השהיה"))
                }
                if self.paused { self.court?.clearForQuestion() } else { self.restartPossession() }
                self.refresh()
            }),
            (first: tr(en: "Help", hebrew: "עזרה"), second: { [weak self] in
                guard let self = self else { return }
                self.paused = true; self.court?.clearForQuestion()
                AAlertDialog.Builder(self)
                    .setMessage(self.instruction(skill: p.active ?? stage.goals.last!.skill))
                    .setPositiveButton(self.tr(en: "Continue", hebrew: "המשך"), { [weak self] _, _ in
                        guard let self = self else { return }
                        self.paused = false; self.restartPossession()
                    })
                    .setOnCancelListener({ [weak self] _ in
                        guard let self = self else { return }
                        self.paused = false; self.restartPossession()
                    })
                    .show()
            })
        ]
        for (name, fn) in entries {
            let view = button(s: name, action: fn); view.textSize = 14; view.maxLines = 1; view.setPadding(dp(v: 6), dp(v: 8), dp(v: 6), dp(v: 8))
            controls.addView(view, ALinearLayout.LayoutParams(0, -2, 1))
        }
        controls.gravity = AGravity.CENTER
        panel.addView(controls)
        hud = label(s: "", size: 16); hud!.setTextColor(AColor.WHITE); panel.addView(hud!)
        bar = AProgressBar(nil, android.R.attr.progressBarStyleHorizontal); bar!.max = 1000; bar!.progressTintList = AColorStateList.valueOf(gold)
        panel.addView(bar!, ALinearLayout.LayoutParams(-1, dp(v: 8)))
        // iOS-only (see the file header): a tap on the panel while the break controls are hidden shows them again.
        panel.setOnClickListener { [weak self] _ in
            guard let self = self, let hidden = self.breakControls, hidden.visibility == AView.INVISIBLE else { return }
            self.showBreakControls()
        }
        let c = TripleShotTeamCourtView(); court = c; c.setCourtStyle(style: TripleShotCourtCatalog.find(id: "sunset_pulse"))
        c.configure(teamSize: stage.teamSize, humanCharacterId: "woman_dark", teammateCharacterIds: helpers,
                    opponentCharacterIds: opponents, seed: 991 + step.toLong())
        c.practiceQuiet = stage.quiet; c.practiceAction = { [weak self, weak c] skill, amount in
            guard let self = self else { return }
            if self.resumed && self.ready && !self.paused && self.page == "game" {
                let changed = p.event(skill: skill, amount: amount)
                if skill == p.active || changed {
                    self.save()
                    if amount >= 1 && skill != BasketballSkill.MOVE && self.prefs.getBoolean("sound", true) {
                        if self.tone == nil { self.tone = AToneGenerator(AAudioManager.STREAM_MUSIC, 25) }
                        self.tone?.startTone(AToneGenerator.TONE_PROP_ACK, 65)
                    }
                }
                if changed {
                    c?.post { [weak self] in
                        guard let self = self else { return }
                        if token == self.generation { if p.won { self.complete() } else { self.restartPossession(); self.refresh() } }
                    }
                } else {
                    self.refresh()
                }
            }
        }
        c.setListener(listener: CourtListener(
            possessionChanged: { [weak self, weak c] team in
                if stage.quiet {
                    let defense = [BasketballSkill.STEAL, BasketballSkill.SWITCH].contains { $0 == p.active }
                    if (team == TripleShotTeamCourtView.Team.OPPONENT) != defense {
                        c?.postDelayed({
                            guard let self = self else { return }
                            if token == self.generation && self.resumed && !self.paused && self.page == "game" { self.restartPossession() }
                        }, 900)
                    }
                }
            },
            shotQuality: { [weak self] percent, visible in
                guard let self = self else { return }
                if visible { self.hud?.text = self.tr(en: "Release meter", hebrew: "מד שחרור") + ": \(percent)%" } else { self.refresh() }
            },
            deadBall: { [weak self, weak c] _ in
                c?.postDelayed({
                    guard let self = self else { return }
                    if token == self.generation && !self.paused && self.resumed && self.page == "game" { self.restartPossession() }
                }, 800)
            }
        ))
        let scroll = AScrollView(); scroll.addView(panel)
        let root = GameRoot(host: self, scroll: scroll, c: c)
        content(view: root); refresh()
        c.whenWorldReady(action: { [weak self] in
            guard let self = self else { return }
            if token == self.generation { self.ready = true; if self.resumed && !self.paused { self.restartPossession() } }
        })
    }

    private func restartPossession() {
        if !resumed || !ready || paused || page != "game" { return }
        guard let active = practice?.active else { return }
        showBreakControls()
        court?.startPossession(team: [BasketballSkill.STEAL, BasketballSkill.SWITCH].contains(active)
            ? TripleShotTeamCourtView.Team.OPPONENT : TripleShotTeamCourtView.Team.HUMAN)
    }

    private func refresh() {
        guard let p = practice else { return }
        if page != "game" || p.won { return }
        let i = p.index
        hud?.text = (paused ? tr(en: "Paused", hebrew: "מושהה") : name(s: p.stage)) + " \u{00B7} \u{2066}\(p.progress(i: i).toInt()) / \(p.goal(i: i))\u{2069}\n" + instruction(skill: p.active!)
        bar?.progress = (p.progress(i: i) / p.goal(i: i).toDouble() * 1000).toInt()
    }

    private func save() {
        // `practice?.takeIf { !it.won }?.let { putString("saved", JSONArray(it.snapshot()).toString()).putInt("savedStep", it.step) }`
        if let it = practice, !it.won {
            prefs.edit().putString("saved", AJSONArray(it.snapshot().map { $0 as Any? }).toString()).putInt("savedStep", it.step).apply()
        }
    }

    private func complete() {
        guard let p = practice else { return }
        if !p.won || page != "game" { return }
        page = "result"
        if p.step == prefs.getInt("step", 0) {
            let key = "\(p.cycle)/\(p.stage.id)"
            // `prefs.getStringSet("receipts", emptySet())!!.toMutableSet()`
            var receipts = KLinkedSet(prefs.getStringSet("receipts", [])!)
            if receipts.add(key) {
                let day = ASimpleDateFormat("yyyy-MM-dd", ALocale.ROOT).format(ADate())
                let bonus = prefs.getString("day", "") == day ? 0 : 30
                prefs.edit().putStringSet("receipts", receipts.elements).putString("day", day)
                    .putInt("stars", prefs.getInt("stars", 0) + 40 + bonus + p.cycle * 10).putInt("step", p.step + 1).remove("saved").apply()
            }
        } else {
            prefs.edit().remove("saved").apply()
        }
        let body = card(title: tr(en: "Well played!", hebrew: "כל הכבוד!")); body.addView(label(s: "\u{2605} \u{2605} \u{2605}", size: 44)); body.addView(label(s: name(s: p.stage), size: 25))
        body.addView(label(s: tr(en: "You practised a real basketball skill. Your next challenge is ready.", hebrew: "התאמנתם במיומנות כדורסל אמיתית. האתגר הבא מחכה לכם.")))
        action(body: body, s: tr(en: "Next challenge", hebrew: "האתגר הבא")) { [weak self] in self?.brief() }
        action(body: body, s: tr(en: "Practise again", hebrew: "מתאמנים שוב")) { [weak self] in self?.start(step: p.step) }
    }

    private func settings() {
        page = "settings"; let body = card(title: tr(en: "Settings", hebrew: "הגדרות"))
        action(body: body, s: tr(en: "More Minik apps & games", hebrew: "עוד אפליקציות ומשחקי מיניק")) { [weak self] in
            guard let self = self else { return }
            // `FamilyMessages.get(this).showMoreApps(this) { approved -> FamilyAdultGate.open(this, approved) }`
            FamilyBridge.showMoreApps(a: self) { [weak self] approved in
                guard let self = self else { return }
                FamilyBridge.adultGate(a: self, approved: approved)
            }
        }
        let sounds = ASwitch(); sounds.text = tr(en: "Game sounds", hebrew: "צלילי משחק"); sounds.textSize = 18; sounds.setTextColor(ink)
        sounds.minHeight = dp(v: 56); sounds.isChecked = prefs.getBoolean("sound", true)
        sounds.setOnCheckedChangeListener { [weak self] _, on in self?.prefs.edit().putBoolean("sound", on).apply(); BasketballSoundscape.refresh() }
        body.addView(sounds)
        action(body: body, s: tr(en: "Rate this app", hebrew: "דירוג האפליקציה")) { [weak self] in
            self?.adult(action: { [weak self] in
                guard let self = self else { return }
                self.external(i: AIntent(AIntent.ACTION_VIEW, AUri.parse("https://play.google.com/store/apps/details?id=\(self.packageName)")))
            })
        }
        action(body: body, s: tr(en: "Share this app", hebrew: "שיתוף האפליקציה")) { [weak self] in
            self?.adult(action: { [weak self] in
                guard let self = self else { return }
                let send = AIntent(AIntent.ACTION_SEND); send.type = "text/plain"
                send.putExtra(AIntent.EXTRA_TEXT, "https://play.google.com/store/apps/details?id=\(self.packageName)")
                self.external(i: AIntent.createChooser(send, self.tr(en: "Share", hebrew: "שיתוף")))
            })
        }
        action(body: body, s: tr(en: "Send feedback", hebrew: "שליחת משוב")) { [weak self] in
            self?.adult(action: { [weak self] in
                guard let self = self else { return }
                self.external(i: AIntent(AIntent.ACTION_SENDTO, AUri.parse("mailto:appsbybros.dev@gmail.com")).putExtra(AIntent.EXTRA_SUBJECT, "TripleShot feedback"))
            })
        }
        let colors = [FamilyMenu.PLAY, argbInt(0xffffe082), argbInt(0xffffb779)]
        // `(0 until childCount).map { getChildAt(it) }.filterIsInstance<Button>().takeLast(3)`: Rate, Share, Feedback.
        let buttons = kuntil(0, body.childCount).compactMap { body.getChildAt($0) as? AButton }
        for (i, b) in buttons.suffix(3).enumerated() { FamilyMenu.style(v: b, color: colors[i]) }
    }

    private func adult(action: @escaping () -> Void) {
        let field = AEditText(); field.hint = "8 \u{00D7} 7 = ?"; field.textDirection = AView.TEXT_DIRECTION_LTR
        field.layoutDirection = AView.LAYOUT_DIRECTION_LTR; field.inputType = AInputType.TYPE_CLASS_NUMBER; field.setTextColor(ink)
        field.setHintTextColor(argbInt(0xff556477))
        AAlertDialog.Builder(self).setTitle(tr(en: "For grown-ups", hebrew: "למבוגרים")).setView(field)
            .setPositiveButton(tr(en: "Continue", hebrew: "המשך"), { _, _ in if field.text.ktrim() == "56" { action() } })
            .setNegativeButton(res: android.R.string.cancel, nil).show()
    }

    private func external(i: AIntent) {
        do {
            try startActivity(i)
        } catch is AActivityNotFoundException {
            AToast.makeText(self, tr(en: "No suitable app is installed", hebrew: "לא מותקנת אפליקציה מתאימה"), AToast.LENGTH_LONG).show()
        } catch {
            // Kotlin catches only ActivityNotFoundException; anything else is an uncaught exception.
            preconditionFailure("\(error)")
        }
    }

    // MARK: - Kotlin object expressions of start()

    /// `object : TripleShotTeamCourtView.Listener { ... }`: the bodies are start()'s closures (they capture its locals).
    private final class CourtListener: TripleShotTeamCourtView.Listener {
        private let possessionChanged: (TripleShotTeamCourtView.Team) -> Void
        private let shotQuality: (Int, Bool) -> Void
        private let deadBall: (TripleShotTeamCourtView.Team) -> Void

        init(possessionChanged: @escaping (TripleShotTeamCourtView.Team) -> Void,
             shotQuality: @escaping (Int, Bool) -> Void,
             deadBall: @escaping (TripleShotTeamCourtView.Team) -> Void) {
            self.possessionChanged = possessionChanged
            self.shotQuality = shotQuality
            self.deadBall = deadBall
        }

        func onTeamBasket(team: TripleShotTeamCourtView.Team, points: Int) {}
        func onPossessionChanged(team: TripleShotTeamCourtView.Team) { possessionChanged(team) }
        func onStatus(message: String, team: TripleShotTeamCourtView.Team?) {}
        func onShotQuality(percent: Int, visible: Bool) { shotQuality(percent, visible) }
        func onDeadBall(defaultNextTeam: TripleShotTeamCourtView.Team) { deadBall(defaultNextTeam) }
    }

    /// `object : ViewGroup(this) { ... }`: the panel (in its ScrollView) and the court. Absolute coordinates, so the
    /// panel is on the physical left in RTL too. Landscape (width > height): the panel column is
    /// `min(dp(230), width / 3)` wide and full height, the court fills the rest; portrait: the panel is full width and
    /// at most a third of the height (its content height), the court below it.
    private final class GameRoot: AViewGroup {
        private weak var host: BasketballJourneyActivity?
        private let scroll: AScrollView
        private let c: TripleShotTeamCourtView

        init(host: BasketballJourneyActivity, scroll: AScrollView, c: TripleShotTeamCourtView) {
            self.host = host
            self.scroll = scroll
            self.c = c
            super.init()
            setBackgroundColor(host.ink); addView(scroll); addView(c)
        }

        required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

        override func onMeasure(_ w: Int, _ h: Int) {
            let width = AMeasureSpec.getSize(w); let height = AMeasureSpec.getSize(h); let wide = width > height
            let sw = wide ? (host?.dp(v: 230) ?? 0).coerceAtMost(width / 3) : width
            scroll.measure(AMeasureSpec.makeMeasureSpec(sw, AMeasureSpec.EXACTLY),
                           AMeasureSpec.makeMeasureSpec(wide ? height : height / 3, AMeasureSpec.AT_MOST))
            c.measure(AMeasureSpec.makeMeasureSpec(wide ? width - sw : width, AMeasureSpec.EXACTLY),
                      AMeasureSpec.makeMeasureSpec(wide ? height : height - scroll.measuredHeight, AMeasureSpec.EXACTLY)); setMeasuredDimension(width, height)
        }

        override func onLayout(_ changed: Bool, _ l: Int, _ t: Int, _ r: Int, _ b: Int) {
            if width > height {
                scroll.layout(0, 0, scroll.measuredWidth, height); c.layout(scroll.measuredWidth, 0, width, height)
            } else {
                scroll.layout(0, 0, width, scroll.measuredHeight); c.layout(0, scroll.measuredHeight, width, height)
            }
        }
    }
}
