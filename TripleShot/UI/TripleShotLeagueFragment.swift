import Foundation

// Port of `ui/TripleShotLeagueFragment.kt` (Android 6c38131), statement by statement (spec 17-teamfrag 4.14).
//
// The page is built in code exactly as the Kotlin builds it. Its effective look comes from the restylers the activity
// installs, as on the Android device: TripleShotControls.watch turns the "Back" / "Back to table" button into the
// 52 dp red X placed at the top END of the column; FamilySkyUi / FamilyFormStyle give the name field its white form
// face and flatten the standings rows to 8 dp rounded rectangles; FamilySkyDrawable maps the pale palette colours.
//
// No iOS-only control is needed: every path Android offers through system Back (`leaveLeague()`) is also reachable
// on screen (the X; on the next-season form the X returns to the table, whose X then runs `leaveLeague()`). The Kotlin
// OnBackPressedCallback is kept.
//
// The hero card (`hero`) clips its art to the rounded background like Android's clipToOutline with
// ViewOutlineProvider.BACKGROUND (AndroidKit AOutlineClippedFrameLayout). The quality ratings shown under every
// roster share one stored choice (preferences "tripleshot_league_ui", key "qualities", default shown).
//
// Swift memory note: Kotlin's local functions and lambdas are stored in the views they rebuild (colour row, slots,
// size and duration buttons). Swift closures retain what they capture, so those local functions reach the fragment
// and the views they rebuild through weak references (otherwise every visit of the page would leak its view tree).
// Behaviour is unchanged.

/** An offline house-team season, deliberately separate from online shooting rooms. */
final class TripleShotLeagueFragment: AFragment {
    private var body: ALinearLayout!
    private var store: TripleShotLeagueStore!
    private var he: Bool { return ["he", "iw"].contains(resources.configuration.locales[0].language) }
    private func tr(en: String, hebrew: String) -> String { return he ? hebrew : en }
    private func dp(n: Int) -> Int { return (n.toFloat() * resources.displayMetrics.density).toInt() }
    private let ink = argbInt(0xff17243c)
    private func background(color: Int, radius: Int = 22) -> FamilySkyDrawable {
        let drawable = FamilySkyDrawable(panel: color == AColor.WHITE || color == argbInt(0xfff5f7fd) || color == argbInt(0xfff6f8ff))
        drawable.setColor(color); drawable.cornerRadius = Float(dp(n: radius))
        return drawable
    }

    override func onCreateView(_ inflater: ALayoutInflater, _ container: AViewGroup?, _ savedInstanceState: ABundle?) -> AView? {
        store = TripleShotLeagueStore(context: requireContext())
        // Gameplay is edge-to-edge; the following menu must restore readable safe areas too.
        let window = requireActivity().window
        AWindowCompat.setDecorFitsSystemWindows(window, false)
        window.statusBarColor = argbInt(0xff101d34); window.navigationBarColor = argbInt(0xff101d34)
        let controller = AWindowCompat.getInsetsController(window, window.decorView)
        controller.isAppearanceLightStatusBars = false; controller.isAppearanceLightNavigationBars = false
        controller.show(AWindowInsetsCompat.systemBars())

        let scroll = AScrollView(); scroll.isFillViewport = true; scroll.setBackgroundColor(argbInt(0xff101d34))
        AViewCompat.setOnApplyWindowInsetsListener(scroll) { v, insets in
            let bars = insets.getInsetsIgnoringVisibility(AWindowInsetsCompat.systemBars() | AWindowInsetsCompat.displayCutout())
            v.setPadding(bars.left, bars.top, bars.right, bars.bottom); return insets
        }
        let frame = FamilyReadingPanel(); scroll.addView(frame)
        body = ALinearLayout(); body.orientation = ALinearLayout.VERTICAL; body.setPadding(dp(n: 18), dp(n: 16), dp(n: 18), dp(n: 30))
        frame.addView(body, AFrameLayout.LayoutParams(min(resources.displayMetrics.widthPixels, dp(n: 760)), -2, AGravity.CENTER_HORIZONTAL))
        render(); scroll.post { [weak scroll] in if let scroll = scroll { AViewCompat.requestApplyInsets(scroll) } }; return scroll
    }

    private func text(value: String, size: Float = 18, color: Int = AColor.WHITE) -> ATextView {
        let t = ATextView()
        t.text = value; t.textSize = size; t.setTextColor(color); t.setPadding(0, dp(n: 7), 0, dp(n: 7)); if size >= 23 { t.setTypeface(t.typeface, ATypeface.BOLD) }
        return t
    }

    private func button(title: String, color: Int = argbInt(0xff89deff), action: @escaping () -> Void) -> TripleShotButton {
        let b = TripleShotButton()
        b.text = title; b.textSize = 18; b.isAllCaps = false; b.minHeight = dp(n: 56); b.cornerRadius = dp(n: 18); FamilyMenu.style(v: b, color: color); b.setTextColor(ink); b.setOnClickListener { _ in action() }
        return b
    }

    private func card() -> ALinearLayout {
        let panel = ALinearLayout()
        panel.orientation = ALinearLayout.VERTICAL; panel.setPadding(dp(n: 16), dp(n: 14), dp(n: 16), dp(n: 14)); panel.background = background(color: argbInt(0xfff5f7fd))
        let lp = ALinearLayout.LayoutParams(-1, -2); lp.topMargin = dp(n: 14)
        body.addView(panel, lp)
        return panel
    }

    private func render() {
        body.removeAllViews(); body.addView(button(title: tr(en: "Back", hebrew: "חזרה"), color: argbInt(0xffd9e5f6)) { [weak self] in self?.leaveLeague() })

        let season: TripleShotLeague.Season?
        do { season = try store.load() } catch { body.addView(text(value: tr(en: "Your saved league could not be opened. It has been kept safely; please contact support.", hebrew: "לא ניתן לפתוח את הליגה השמורה. היא נשמרה ללא שינוי; פנו לתמיכה."))); return }
        if let season = season { self.season(s: season) } else { setup() }
    }

    private func leaveLeague() { (parentFragment as? TripleShotHostFragment)?.backToHome() }

    private func hero(season: Bool, subtitle: String) {
        let frame = AOutlineClippedFrameLayout(); frame.minimumHeight = dp(n: 235); frame.clipToOutline = true; frame.background = background(color: argbInt(0xff142940))
        let image = AImageView(); image.setImageResource(season ? R.drawable.league_season_art : R.drawable.league_setup_art); image.scaleType = AImageView.ScaleType.CENTER_CROP; image.setAlpha(Float(0.4)); image.importantForAccessibility = AView.IMPORTANT_FOR_ACCESSIBILITY_NO
        frame.addView(image, AFrameLayout.LayoutParams(-1, -1))
        let words = ALinearLayout(); words.orientation = ALinearLayout.VERTICAL; words.gravity = AGravity.CENTER_VERTICAL; words.setPadding(dp(n: 14), dp(n: 16), dp(n: 14), dp(n: 18))
        let title = text(value: tr(en: "Court Stars League", hebrew: "ליגת כוכבי המגרש"), size: 28); title.gravity = AGravity.CENTER; title.textAlignment = AView.TEXT_ALIGNMENT_CENTER
        words.addView(title, ALinearLayout.LayoutParams(-1, -2))
        let line = text(value: subtitle, size: 17); line.gravity = AGravity.START; line.textAlignment = AView.TEXT_ALIGNMENT_VIEW_START; line.setShadowLayer(dp(n: 2).toFloat(), 0, dp(n: 1).toFloat(), AColor.BLACK)
        let lineLp = ALinearLayout.LayoutParams(-1, -2); lineLp.topMargin = dp(n: 8)
        words.addView(line, lineLp)
        frame.addView(words, AFrameLayout.LayoutParams(-1, -2, AGravity.TOP))
        let frameLp = ALinearLayout.LayoutParams(-1, dp(n: 260)); frameLp.bottomMargin = dp(n: 6)
        body.addView(frame, frameLp)
    }

    private func deleteLeague(s: TripleShotLeague.Season) {
        let box = ALinearLayout(); box.orientation = ALinearLayout.VERTICAL; box.setPadding(dp(n: 24), dp(n: 22), dp(n: 24), dp(n: 24))
        let question = text(value: tr(en: "Are you sure you want to delete this league?", hebrew: "למחוק את הליגה הזאת?"), size: 23, color: ink); question.gravity = AGravity.CENTER
        box.addView(question)
        let no = button(title: tr(en: "No, cancel", hebrew: "לא, ביטול"), color: argbInt(0xffe91e63)) {}
        let yes = button(title: tr(en: "Yes, delete", hebrew: "כן, למחוק"), color: FamilyMenu.LEARN) {}
        (yes.background as? AGradientDrawable)?.setStroke(dp(n: 2), argbInt(0xffe91e63))
        let noLp = ALinearLayout.LayoutParams(-1, -2); noLp.topMargin = dp(n: 22)
        box.addView(no, noLp)
        let yesLp = ALinearLayout.LayoutParams(-1, -2); yesLp.topMargin = dp(n: 16)
        box.addView(yes, yesLp)
        let dialog = AAlertDialog.Builder(requireContext()).setView(box).create()
        no.setOnClickListener { [weak dialog] _ in dialog?.dismiss() }
        yes.setOnClickListener { [weak self, weak dialog] _ in
            guard let self = self else { return }
            self.store.discard(id: s.id); dialog?.dismiss(); self.render()
        }
        dialog.setOnShowListener { [weak self, weak dialog] _ in
            guard let self = self, let dialog = dialog else { return }
            FamilySkyUi.dialog(dialog: dialog); dialog.window?.setLayout(min(self.dp(n: 440), self.resources.displayMetrics.widthPixels - self.dp(n: 40)), -2)
        }
        dialog.show()
    }

    override func onViewCreated(_ view: AView, _ state: ABundle?) {
        super.onViewCreated(view, state)
        requireActivity().onBackPressedDispatcher.addCallback(viewLifecycleOwner, AOnBackPressedCallback(true) { [weak self] _ in self?.leaveLeague() })
    }

    private var uiPrefs: ASharedPreferences { return requireContext().getSharedPreferences("tripleshot_league_ui", 0) }

    private func roster(row: ALinearLayout, ids: [String], color: Int, own: Bool = false) {
        let strip = ALinearLayout(); strip.gravity = AGravity.CENTER_HORIZONTAL
        var qualities: [AView] = []
        for id in ids {
            guard let profile = TripleShotCharacterRoster.find(id: id) else { continue }
            let item = ALinearLayout(); item.orientation = ALinearLayout.VERTICAL; item.gravity = AGravity.CENTER_HORIZONTAL; item.setPadding(dp(n: 4), dp(n: 10), dp(n: 4), dp(n: 10))
            let portrait = AImageView()
            if let res = TripleShotCharacterVisualCatalog.previewResId(characterId: id) { portrait.setImageResource(res) }
            portrait.scaleType = AImageView.ScaleType.FIT_CENTER; portrait.contentDescription = profile.displayName
            let portraitLp = ALinearLayout.LayoutParams(-1, dp(n: 112)); portraitLp.bottomMargin = dp(n: 10)
            item.addView(portrait, portraitLp)
            let caption = text(value: profile.displayName, size: 17, color: ink); caption.gravity = AGravity.CENTER
            item.addView(caption, ALinearLayout.LayoutParams(-1, -2))
            let q = ALinearLayout(); q.orientation = ALinearLayout.VERTICAL
            let r = profile.ratings
            let ratings: [(String, String, Int)] = [("Inside", "מקרוב", r.inside), ("Mid-range", "מרחוק", r.midRange), ("Three-point", "שלשות", r.threePoint), ("Speed", "מהירות", r.speed), ("Strength", "כוח", r.strength), ("Height", "גובה", r.height), ("Block", "חסימה", r.blocking), ("Steal", "חטיפה", r.stealing), ("Handling", "שליטה", r.ballHandling), ("Dunk", "הטבעה", r.dunking), ("Defence", "הגנה", r.defense), ("Agility", "זריזות", r.agility), ("Offence", "התקפה", r.offense), ("Weight", "משקל", r.weight), ("Jump", "קפיצה", r.jumping)]
            for (en, h, value) in ratings {
                let name = text(value: tr(en: en, hebrew: h), size: 13, color: ink); name.gravity = AGravity.CENTER; name.setPadding(0, dp(n: 5), 0, 0)
                q.addView(name, ALinearLayout.LayoutParams(-1, -2))
                let n = ((value + 19) / 20).coerceIn(1, 5)
                let stars = text(value: String(repeating: "\u{2605}", count: n) + String(repeating: "\u{2606}", count: 5 - n), size: 14, color: argbInt(0xff795300))
                stars.gravity = AGravity.CENTER; stars.setPadding(0, 0, 0, dp(n: 3)); stars.contentDescription = tr(en: "\(value) out of 100", hebrew: "\(value) מתוך 100")
                q.addView(stars, ALinearLayout.LayoutParams(-1, -2))
            }
            item.addView(q); qualities.append(q)
            strip.addView(item, ALinearLayout.LayoutParams(0, -2, 1))
        }
        let stripLp = ALinearLayout.LayoutParams(-1, -2); stripLp.topMargin = dp(n: 10)
        row.addView(strip, stripLp)
        // One stored choice applies to every roster on this screen, including the next opponent.
        for q in qualities { q.setTag("league-qualities"); q.visibility = uiPrefs.getBoolean("qualities", true) ? AView.VISIBLE : AView.GONE }
        if own {
            let link = text(value: "", size: 16, color: argbInt(0xff225a97)); link.gravity = AGravity.CENTER; link.minHeight = dp(n: 48); link.paintFlags = link.paintFlags | APaint.UNDERLINE_TEXT_FLAG
            let weakLink = WeakRef(link)
            let owner = WeakRef(self)
            func label() {
                guard let page = owner.value, let link = weakLink.value else { return }
                link.text = page.uiPrefs.getBoolean("qualities", true) ? page.tr(en: "Hide qualities", hebrew: "הסתרת כישורים") : page.tr(en: "Show qualities", hebrew: "הצגת כישורים")
            }
            label()
            link.setOnClickListener { _ in
                guard let page = owner.value else { return }
                let show = !page.uiPrefs.getBoolean("qualities", true); page.uiPrefs.edit().putBoolean("qualities", show).apply()
                func visit(v: AView) {
                    if (v.getTag() as? String) == "league-qualities" { v.visibility = show ? AView.VISIBLE : AView.GONE }
                    if let g = v as? AViewGroup { for i in kuntil(0, g.childCount) { visit(v: g.getChildAt(i)!) } }
                }
                visit(v: page.body); label()
            }
            let linkLp = ALinearLayout.LayoutParams(-1, -2); linkLp.topMargin = dp(n: 8)
            row.addView(link, linkLp)
        }
    }

    /// A weak reference the local functions of `setup` capture instead of the fragment or a view they rebuild.
    private final class WeakRef<T: AnyObject> {
        weak var value: T?
        init(_ value: T) { self.value = value }
    }

    private func setup(previous: TripleShotLeague.Season? = nil) {
        // Weak references for the local functions stored in the views they rebuild (see the file header).
        let owner = WeakRef(self)
        hero(season: false, subtitle: tr(en: "Choose your colours. Build your squad. Take on seven house teams in 14 games\u{2014}at your own pace. You control one player; your teammates are bots. House-team matches are simulated after each round.", hebrew: "בוחרים צבע, מרכיבים קבוצה ומתחרים בשבע קבוצות בית ב\u{05BE}14 משחקים, בקצב שלכם. אתם שולטים בשחקן אחד וחברי הקבוצה הם בוטים. משחקים בין קבוצות הבית מחושבים בסוף כל מחזור."))
        let panel = card(); panel.addView(text(value: tr(en: "Your team", hebrew: "הקבוצה שלכם"), size: 24, color: ink))
        // `previous?.teams?.first()`: Kotlin first() throws on an empty list, hence `first!` inside the optional chains.
        let name = AEditText()
        name.setSingleLine(); name.setText(previous?.teams.first!.name ?? tr(en: "Sky Comets", hebrew: "שביטי השמיים")); name.hint = tr(en: "Team name", hebrew: "שם הקבוצה"); name.setTextColor(ink); name.setHintTextColor(argbInt(0xff607087)); name.filters = [ALengthFilter(24)]; name.minHeight = dp(n: 52); panel.addView(name)
        var color = previous?.teams.first!.color ?? TripleShotLeague.palette.first!
        let colourTitleLp = ALinearLayout.LayoutParams(-1, -2); colourTitleLp.topMargin = dp(n: 18); colourTitleLp.bottomMargin = dp(n: 8)
        panel.addView(text(value: tr(en: "Team colour", hebrew: "צבע הקבוצה"), size: 18, color: ink), colourTitleLp)
        let colours = ALinearLayout(); let coloursLp = ALinearLayout.LayoutParams(-1, -2); coloursLp.bottomMargin = dp(n: 18); panel.addView(colours, coloursLp)
        let weakColours = WeakRef(colours)
        func colors() {
            guard let page = owner.value, let colours = weakColours.value else { return }
            colours.removeAllViews()
            for (i, c) in TripleShotLeague.palette.enumerated() {
                let swatch = page.button(title: c == color ? "\u{2713}" : "\u{25CF}", color: c) { color = c; colors() }
                swatch.contentDescription = page.tr(en: "Team colour \(i + 1)", hebrew: "צבע קבוצה \(i + 1)"); swatch.minWidth = 0; swatch.minimumWidth = 0; swatch.setPadding(0, 0, 0, 0)
                let lp = ALinearLayout.LayoutParams(0, page.dp(n: 54), 1); lp.marginStart = page.dp(n: 3); lp.marginEnd = page.dp(n: 3)
                colours.addView(swatch, lp)
            }
        }
        colors()
        let available = TripleShotCharacterRoster.humanSelectable().filter { TripleShotCharacterVisualCatalog.hasVisuals(characterId: $0.id) }
        var selected = previous?.teams.first!.roster ?? Array(available.prefix(3)).map { $0.id }
        while selected.count < 3 {
            // `available.first { it.id !in selected }.id` (NoSuchElementException when none, like Kotlin).
            let missing = available.first { !selected.contains($0.id) }!.id
            selected.append(missing)
        }
        var size = previous?.teams.first!.roster.count ?? 2
        let sizeButton = button(title: "") { }; panel.addView(sizeButton)
        var duration = previous?.matchSeconds ?? 0
        let times = [0, 120, 180, 300]
        let durationButton = button(title: "") {}
        let weakDurationButton = WeakRef(durationButton)
        func durationLabel() {
            guard let page = owner.value, let durationButton = weakDurationButton.value else { return }
            durationButton.text = duration == 0 ? page.tr(en: "Match length: first to 11", hebrew: "משך המשחק: הראשונים ל\u{05BE}11") : page.tr(en: "Match length: \(duration / 60) minutes", hebrew: "משך המשחק: \(duration / 60) דקות")
        }
        durationLabel(); durationButton.setOnClickListener { _ in duration = times[((times.firstIndex(of: duration) ?? -1) + 1) % times.count]; durationLabel() }
        let durationLp = ALinearLayout.LayoutParams(-1, -2); durationLp.topMargin = dp(n: 14); durationLp.bottomMargin = dp(n: 14)
        panel.addView(durationButton, durationLp)
        panel.addView(text(value: tr(en: "Timed games: when time runs out, the higher score wins. A tie continues until the next basket.", hebrew: "במשחק לפי זמן, הניקוד הגבוה בסיום מנצח. בשוויון ממשיכים עד הסל הבא."), size: 15, color: ink))
        let slots = ALinearLayout(); slots.orientation = ALinearLayout.VERTICAL; panel.addView(slots)
        let weakSlots = WeakRef(slots)
        let weakSizeButton = WeakRef(sizeButton)
        func drawSlots() {
            guard let page = owner.value, let slots = weakSlots.value, let sizeButton = weakSizeButton.value else { return }
            slots.removeAllViews(); sizeButton.text = page.tr(en: "\(size) players \u{00B7} tap to change", hebrew: "\(size) שחקנים \u{00B7} לחצו לשינוי")
            for index in kuntil(0, size) {
                let line = ALinearLayout(); line.gravity = AGravity.CENTER_VERTICAL
                let pic = AImageView(); if let res = TripleShotCharacterVisualCatalog.previewResId(characterId: selected[index]) { pic.setImageResource(res) }; pic.scaleType = AImageView.ScaleType.FIT_CENTER; line.addView(pic, ALinearLayout.LayoutParams(page.dp(n: 84), page.dp(n: 90)))
                let label = (index == 0 ? page.tr(en: "You", hebrew: "אתם") : page.tr(en: "Teammate", hebrew: "חבר קבוצה")) + " \u{00B7} " + TripleShotCharacterRoster.find(id: selected[index])!.displayName
                line.addView(page.button(title: label, color: argbInt(0xffe0e9fa)) {
                    // Kotlin `TripleShotCharacterPickerDialog.show(this, ...)`: `this` is the fragment.
                    guard let fragment = owner.value else { return }
                    TripleShotCharacterPickerDialog.show(fragment: fragment, mode: index == 0 ? TripleShotCharacterPickerDialog.Mode.HUMAN : TripleShotCharacterPickerDialog.Mode.BOT, profiles: available, currentId: selected[index], canSelect: { p in p.id == selected[index] || !Array(selected.prefix(size)).contains(p.id) }) { profile in selected[index] = profile.id; drawSlots() }
                }, ALinearLayout.LayoutParams(0, -2, 1))
                let lineLp = ALinearLayout.LayoutParams(-1, -2); lineLp.topMargin = page.dp(n: 12); lineLp.bottomMargin = page.dp(n: 14)
                slots.addView(line, lineLp)
            }
        }
        sizeButton.setOnClickListener { _ in
            size = size == 2 ? 3 : 2
            if size == 3 && Array(selected.prefix(2)).contains(selected[2]) {
                let replacement = available.first { !Array(selected.prefix(2)).contains($0.id) }!.id
                selected[2] = replacement
            }
            drawSlots()
        }; drawSlots()
        panel.addView(button(title: tr(en: "Start my season", hebrew: "מתחילים עונה"), color: argbInt(0xffffd778)) {
            guard let page = owner.value else { return }
            let clean = TripleShotLeague.cleanName(raw: name.text); if clean.kotlinIsBlank { name.error = page.tr(en: "Choose a team name", hebrew: "בחרו שם לקבוצה"); return }
            let names = page.he ? ["ברקי הזהב", "דרקוני הירח", "גלי הטורקיז", "כוכבי האש", "זאבי הלילה", "כנפי הקשת", "אריות השמש"] : ["Golden Bolts", "Moon Dragons", "Tidal Waves", "Fire Stars", "Night Wolves", "Rainbow Wings", "Sun Lions"]
            // `runCatching { store.create(...) }.onSuccess { render() }.onFailure { Toast }`
            let created: Bool
            do { _ = try page.store.create(name: clean, color: color, roster: Array(selected.prefix(size)), houseNames: names, matchSeconds: duration); created = true } catch { created = false }
            if created { page.render() } else { AToast.makeText(page.requireContext(), page.tr(en: "Could not save your team. Please try again.", hebrew: "לא ניתן לשמור את הקבוצה. נסו שוב."), AToast.LENGTH_LONG).show() }
        })
    }

    private func season(s: TripleShotLeague.Season) {
        let mine = s.teams[0]; let table = TripleShotLeague.standings(season: s); let rank = (table.firstIndex { $0.team.id == 0 } ?? -1) + 1
        hero(season: true, subtitle: mine.name + "\n" + tr(en: "Season \(s.number) \u{00B7} \(s.played)/14 games \u{00B7} Place \(rank)", hebrew: "עונה \(s.number) \u{00B7} \(s.played)/14 משחקים \u{00B7} מקום \(rank)"))
        roster(row: card(), ids: mine.roster, color: mine.color, own: true)
        let next = s.next()
        if let next = next {
            let opponent = s.teams[next.home == 0 ? next.away : next.home]; let panel = card()
            panel.addView(text(value: tr(en: "Next up: \(opponent.name)", hebrew: "המשחק הבא: \(opponent.name)"), size: 23, color: ink)); roster(row: panel, ids: opponent.roster, color: opponent.color)
            panel.addView(text(value: tr(en: "Round \(next.round + 1) \u{00B7} \(s.matchSeconds == 0 ? "First to 11" : "Timed match"). Finishing the game updates the table. Leaving early keeps this fixture available.", hebrew: "מחזור \(next.round + 1) \u{00B7} \(s.matchSeconds == 0 ? "הראשונים ל\u{05BE}11 מנצחים" : "משחק לפי זמן"). סיום המשחק מעדכן את הטבלה. יציאה מוקדמת משאירה את המשחק זמין."), size: 16, color: ink))
            if s.matchSeconds > 0 { panel.addView(text(value: tr(en: "Timed match: \(s.matchSeconds / 60) minutes", hebrew: "משחק לפי זמן: \(s.matchSeconds / 60) דקות"), size: 18, color: ink)) }
            panel.addView(button(title: tr(en: "Play league match", hebrew: "משחק ליגה"), color: mine.color) { [weak self] in
                (self?.parentFragment as? TripleShotHostFragment)?.startGame(config: TripleShotGameConfig(playerName: mine.name, gameType: GameType.TEAM_MATCH, selectedCategories: KLinkedSet(), botMatch: true, playerCharacterId: mine.roster[0], teamSize: mine.roster.count, teammateCharacterIds: Array(mine.roster.dropFirst(1)), opponentCharacterIds: opponent.roster, seed: s.seed &+ Int64(next.round), timeLimitSeconds: s.matchSeconds, leagueSeasonId: s.id, leagueFixtureKey: next.key, teamName: mine.name, opponentTeamName: opponent.name, teamColor: mine.color, opponentTeamColor: opponent.color))
            }, { let lp = ALinearLayout.LayoutParams(-1, -2); lp.topMargin = dp(n: 20); lp.bottomMargin = dp(n: 12); return lp }())
        } else {
            let panel = card(); panel.addView(text(value: rank == 1 ? tr(en: "League champions!", hebrew: "אלופי הליגה!") : tr(en: "Season complete! Place \(rank)", hebrew: "העונה הושלמה! מקום \(rank)"), size: 25, color: ink))
            panel.addView(button(title: tr(en: "Build the next season", hebrew: "בונים את העונה הבאה"), color: argbInt(0xffffd778)) { [weak self] in
                guard let self = self else { return }
                self.body.removeAllViews(); self.body.addView(self.button(title: self.tr(en: "Back to table", hebrew: "חזרה לטבלה")) { [weak self] in self?.render() }); self.setup(previous: s)
            })
        }
        let standings = card(); let tableTitle = text(value: tr(en: "League table", hebrew: "טבלת הליגה"), size: 24, color: ink); tableTitle.gravity = AGravity.CENTER; standings.addView(tableTitle)
        standings.addView(text(value: tr(en: "3 points per win \u{00B7} ties: basket difference, then baskets scored", hebrew: "3 נקודות לניצחון \u{00B7} בשוויון: הפרש סלים ואז סלים שנקלעו"), size: 14, color: ink))
        for (i, r) in table.enumerated() {
            let row = text(value: "\(i + 1). \(r.team.name)\n" + tr(en: "\(r.points) pts \u{00B7} \(r.wins)/\(r.played) wins \u{00B7} \(r.scored):\(r.conceded)", hebrew: "\(r.points) נק\u{05F3} \u{00B7} \(r.wins)/\(r.played) ניצחונות \u{00B7} \(r.scored):\(r.conceded)"), size: 17, color: ink)
            row.setPadding(dp(n: 12), dp(n: 10), dp(n: 12), dp(n: 10)); row.background = background(color: r.team.id == 0 ? mine.color : AColor.WHITE, radius: 14)
            let lp = ALinearLayout.LayoutParams(-1, -2); lp.topMargin = dp(n: 6)
            standings.addView(row, lp)
        }
        let deleteLp = ALinearLayout.LayoutParams(-1, -2); deleteLp.topMargin = dp(n: 24); deleteLp.bottomMargin = dp(n: 16)
        body.addView(button(title: tr(en: "Delete league", hebrew: "מחיקת הליגה"), color: argbInt(0xffe91e63)) { [weak self] in self?.deleteLeague(s: s) }, deleteLp)
    }
}
