import SwiftUI

/// Android `home()` after `FamilyMenu.organize`: the title, ball and motto, then four sections. "More Minik apps"
/// and "Ads & purchases" are not part of the iOS app.
struct HomeScreen: View {
    @ObservedObject var model: AppModel

    var body: some View {
        let learn = model.tr("Start & learn", "מתחילים ולומדים")
        let play = model.tr("Play", "משחקים")
        let saved = model.tr("Saved games", "משחקים שמורים")
        let advanced = model.tr("Advanced", "מתקדם")
        return AmuduPage(GameText.title(), background: model.art.scene(model.scene)) {
            Image(uiImage: model.art.ball(.neon))
                .resizable()
                .scaledToFit()
                .frame(height: 110)
                .frame(maxWidth: .infinity)
            AmuduLabel(model.tr("Call. Catch. Freeze. Laugh.", "קוראים. תופסים. עוצרים. צוחקים."), size: 18, color: 0xff9bffe4)
            MenuSection(learn, color: MenuColors.learn, open: model.sectionOpen(learn, true), toggle: { model.toggleSection(learn, true) }) {
                SectionButton(model.tr("How to play", "איך משחקים"), color: MenuColors.learn) { model.openHelp() }
                SectionButton(model.tr("Daily skill journey", "מסע המיומנויות היומי"), color: MenuColors.learn) { model.openJourney() }
                SectionButton(model.tr("Your colors & progress", "הצבעים וההתקדמות שלכם"), color: MenuColors.learn) { model.openRank() }
                profile
            }
            MenuSection(play, color: MenuColors.play, open: model.sectionOpen(play, true), toggle: { model.toggleSection(play, true) }) {
                SectionButton(model.tr("Create game", "יצירת משחק"), color: MenuColors.play) { model.openSetup() }
                SectionButton(model.tr("Join by code", "הצטרפות עם קוד"), color: MenuColors.play) { model.requestJoin() }
            }
            if model.hasSavedGame || model.savedRoom != nil {
                MenuSection(saved, color: MenuColors.saved, open: model.sectionOpen(saved, false), toggle: { model.toggleSection(saved, false) }) {
                    if model.hasSavedGame {
                        SectionButton(model.tr("Continue saved game", "המשך משחק שמור"), color: MenuColors.saved) { model.continueSaved() }
                    }
                    if let code = model.savedRoom {
                        SectionButton(model.tr("Return to room (\(code))", "חזרה לחדר (\(code))"), color: MenuColors.saved) { model.returnToRoom(code) }
                    }
                }
            }
            MenuSection(advanced, color: MenuColors.advanced, open: model.sectionOpen(advanced, false), toggle: { model.toggleSection(advanced, false) }) {
                SectionButton(model.tr("Settings & feedback", "הגדרות ומשוב"), color: MenuColors.advanced) { model.openSettings() }
            }
        }
        .alert(model.tr("Join a private room", "הצטרפות לחדר פרטי"), isPresented: $model.joinVisible) {
            TextField(model.tr("Six-character code", "קוד בן שישה תווים"), text: $model.joinInput)
                .textInputAutocapitalization(.characters)
                .autocorrectionDisabled()
            Button(model.tr("Join", "הצטרפות")) { model.join() }
            Button(model.tr("Cancel", "ביטול"), role: .cancel) {}
        }
        .alert(model.tr("For a grown-up", "למבוגר אחראי"), isPresented: $model.gateVisible) {
            TextField("", text: $model.gateInput)
                .keyboardType(.numberPad)
            Button(model.tr("Continue", "המשך")) { model.confirmGate() }
            Button(model.tr("Cancel", "ביטול"), role: .cancel) { model.cancelGate() }
        } message: {
            Text(model.gateQuestion)
        }
    }

    /// The name, avatar and colour rank (Android moves them into the first section).
    private var profile: some View {
        let rank = ProgressRanks.at(model.rankPoints)
        return VStack(spacing: 0) {
            AmuduLabel(model.tr("Your name", "השם שלכם"), size: 18, color: 0xffb8f3dc)
            TextField("", text: Binding(get: { model.playerName }, set: { model.updateName($0) }),
                      prompt: Text(model.tr("Your name", "השם שלכם")).foregroundColor(Color(argb: 0xffbbd6de)))
                .font(.system(size: 18))
                .foregroundColor(.white)
                .multilineTextAlignment(.center)
                .textInputAutocapitalization(.words)
                .autocorrectionDisabled()
                .submitLabel(.done)
                .padding(.horizontal, 12)
                .frame(height: 55)
                .background(RoundedRectangle(cornerRadius: 18).fill(Color(argb: 0x55335167)))
            Rectangle()
                .fill(Color(argb: 0xffa8f7df))
                .frame(height: 3)
            AmuduLabel(model.tr("Used only when you play with friends in a private room.", "ישמש רק במשחק עם חברים בחדר פרטי."), size: 14, color: 0xffc4dfe8)
            avatarRow
            AmuduLabel(AmuduCharacters.get(model.avatar).name(hebrew: model.hebrew) + " · " + String(model.rankPoints), size: 16, color: rank.ink)
                .background(RoundedRectangle(cornerRadius: 18).fill(Color(argb: rank.color)))
                .padding(.bottom, 18)
        }
    }

    /// The avatar row stays left-to-right in every language (Android forces LTR here).
    private var avatarRow: some View {
        HStack(spacing: 0) {
            AvatarArrow(right: false) { model.shiftAvatar(-1) }
                .padding(.leading, 8)
                .padding(.trailing, 12)
            Image(uiImage: model.art.portrait(model.avatar))
                .resizable()
                .scaledToFit()
                .frame(maxWidth: .infinity)
                .frame(height: 126)
                .contentShape(Rectangle())
                .simultaneousGesture(DragGesture(minimumDistance: 20).onEnded { value in
                    let dx = value.translation.width
                    let dy = value.translation.height
                    if abs(dx) > 35 && abs(dx) > abs(dy) { model.shiftAvatar(dx < 0 ? 1 : -1) }
                })
            AvatarArrow(right: true) { model.shiftAvatar(1) }
                .padding(.leading, 12)
                .padding(.trailing, 8)
        }
        .environment(\.layoutDirection, .leftToRight)
    }
}

/// Android `setup()`: rule mode, players, arena and ball pictures, the environment and advanced-rule groups, house
/// players.
struct SetupScreen: View {
    @ObservedObject var model: AppModel

    var body: some View {
        AmuduPage(model.tr("Create your game", "יוצרים משחק"), background: model.art.scene(model.scene)) {
            ChoiceMenu(title: RuleText["mode"], items: RuleSet.allCases.map { RuleText.mode($0) },
                       selected: RuleSet.allCases.firstIndex(of: model.rules) ?? 0) { i in
                model.selectRules(RuleSet.allCases[i])
            }
            AmuduLabel(RuleText["rulesHint"], size: 15, color: 0xffd0e4ee)
            ChoiceMenu(title: model.tr("Number of players", "מספר שחקנים"), items: (2...10).map { String($0) }, selected: model.count - 2) { i in
                model.count = i + 2
                model.persist()
            }
            FieldTitle(model.tr("Arena", "זירה"))
            PictureChoices(options: ArenaScene.allCases.map { PictureOption(id: $0.rawValue, name: model.tr($0.en, $0.he), image: model.art.scene($0)) },
                           selected: model.scene.rawValue, arena: true) { id in
                model.scene = ArenaScene(rawValue: id) ?? .park
                model.persist()
            }
            FieldTitle(model.tr("Ball", "כדור"))
            PictureChoices(options: BallKind.allCases.map { PictureOption(id: $0.rawValue, name: model.tr($0.en, $0.he), image: model.art.ball($0)) },
                           selected: model.ball.rawValue, arena: false) { id in
                model.ball = BallKind(rawValue: id) ?? .foam
                model.persist()
            }
            GroupToggle(title: RuleText["environment"], expanded: model.environmentOpen) { model.environmentOpen.toggle() }
            if model.environmentOpen { environment }
            GroupToggle(title: RuleText["advanced"], expanded: model.advancedOpen) { model.advancedOpen.toggle() }
            if model.advancedOpen { advanced }
            FieldTitle(model.tr("House players · choose your team of friends", "שחקני הבית · בוחרים עם מי לשחק"))
            ForEach(AmuduCharacters.all, id: \.id) { c in
                characterRow(c)
            }
            AmuduButton(model.tr("Start", "התחלה")) { model.startLocal() }
            AmuduButton(model.tr("Open private room", "פתיחת חדר פרטי"), color: 0xffb7dcff) { model.openPrivateRoom() }
            AmuduButton(model.tr("Back", "חזרה"), color: 0xffdfcfff) { model.home() }
        }
    }

    private var environment: some View {
        VStack(spacing: 0) {
            ChoiceMenu(title: model.tr("Time of day", "שעה ביום"), items: Daylight.allCases.map { model.tr($0.en, $0.he) },
                       selected: Daylight.allCases.firstIndex(of: model.daylight) ?? 0) { i in
                model.daylight = Daylight.allCases[i]
                model.persist()
            }
            ChoiceMenu(title: model.tr("Wind", "רוח"), items: Wind.allCases.map { model.tr($0.en, $0.he) },
                       selected: Wind.allCases.firstIndex(of: model.wind) ?? 0) { i in
                model.wind = Wind.allCases[i]
                model.persist()
            }
        }
    }

    private var advanced: some View {
        VStack(spacing: 0) {
            ChoiceMenu(title: RuleText["time"], items: AppModel.secondsChoices.map { $0 == 0 ? RuleText["noLimit"] : "\($0) s" },
                       selected: AppModel.secondsChoices.firstIndex(of: model.actionSeconds) ?? -1) { i in
                model.actionSeconds = AppModel.secondsChoices[i]
                model.persist()
            }
            AmuduLabel(RuleText["timerHint"], size: 14, color: 0xffd0e4ee)
            ChoiceMenu(title: RuleText["callRule"], items: [RuleText["optional"], RuleText["required"]], selected: model.requireCall ? 1 : 0) { i in
                model.requireCall = i == 1
                model.persist()
            }
            ChoiceMenu(title: RuleText["steps"], items: [RuleText["none"], "1", "2", "3", "4"], selected: model.stepsAfterCall) { i in
                model.stepsAfterCall = i
                model.persist()
            }
            ChoiceMenu(title: RuleText["afterCall"],
                       items: [model.tr("Freeze in place", "עוצרים במקום"), model.tr("Honor rule · moving adds a penalty", "חוק הכבוד · זזים ומקבלים נקודת חובה")],
                       selected: FreezeRule.allCases.firstIndex(of: model.freeze) ?? 0) { i in
                model.freeze = FreezeRule.allCases[i]
                model.persist()
            }
            ChoiceMenu(title: model.tr("Throw mode", "מצב זריקה"), items: ThrowMode.allCases.map { model.tr($0.en, $0.he) },
                       selected: ThrowMode.allCases.firstIndex(of: model.throwMode) ?? 0) { i in
                model.throwMode = ThrowMode.allCases[i]
                model.persist()
            }
            ChoiceMenu(title: model.tr("Turn limit", "תורים במשחק"), items: ["10", "20", "35", "50", RuleText["noLimit"]],
                       selected: AppModel.turnChoices.firstIndex(of: model.turns) ?? 4) { i in
                model.turns = AppModel.turnChoices[i]
                model.persist()
            }
        }
    }

    private func characterRow(_ c: AmuduCharacter) -> some View {
        let isAvatar = c.id == model.avatar
        let title = c.name(hebrew: model.hebrew) + (isAvatar ? model.tr(" · Your avatar", " · הדמות שלכם") : "")
        let q = c.qualities
        let ratings: [(String, Int)] = [(model.tr("Accuracy", "דיוק"), q.accuracy), (model.tr("Power", "עוצמה"), q.power),
                                        (model.tr("Speed", "מהירות"), q.speed), (model.tr("Catch", "תפיסה"), q.catching)]
        return HStack(alignment: .center, spacing: 0) {
            Image(uiImage: model.art.portrait(c.id))
                .resizable()
                .scaledToFit()
                .frame(width: 54, height: 78)
            VStack(spacing: 0) {
                HouseCheck(title: title, checked: model.house.contains(c.id), enabled: !isAvatar) { selected in
                    model.setHouse(c.id, selected)
                }
                ForEach(0..<ratings.count, id: \.self) { i in
                    HStack(spacing: 0) {
                        Text(ratings[i].0)
                            .font(.system(size: 17, weight: .bold))
                            .foregroundColor(Color(argb: 0xffffe49a))
                            .padding(.horizontal, 9)
                            .padding(.vertical, 4)
                            .frame(maxWidth: .infinity, alignment: .leading)
                        SkillStars(value: ratings[i].1)
                            .frame(width: 116, height: 29)
                    }
                }
            }
        }
        .padding(.vertical, 7)
    }
}

/// Android `help()`.
struct HelpScreen: View {
    @ObservedObject var model: AppModel

    var body: some View {
        AmuduPage(model.tr("How to play", "איך משחקים"), background: model.art.scene(model.scene)) {
            AmuduButton(model.tr("Learn by playing", "לומדים תוך כדי משחק")) { model.openJourney(0) }
            AmuduLabel(model.tr("Turn your phone to play in landscape, or tap ↻ during a game. Your chosen orientation is remembered for the next game.",
                                "סובבו את הטלפון למשחק לרוחב, או געו ב־↻ בזמן המשחק. הכיוון שבחרתם נשמר למשחק הבא."), size: 17)
            AmuduLabel(RuleText["rulesHint"], size: 17)
            AmuduLabel(RuleText["nicknames"], size: 21, color: 0xffa8f7df)
            AmuduLabel(RuleText["nickHelp"], size: 17)
            AmuduLabel(RuleText["spud"], size: 21, color: 0xffa8f7df)
            AmuduLabel(RuleText["spudHelp"], size: 17)
            // Android passes "\\n" here (a visible backslash and n); iOS shows the line break the game screen uses.
            AmuduLabel(model.tr("Drag to run · Tap / hold to catch\nDouble-tap to duck", "גררו כדי לרוץ · נגיעה או לחיצה לתפיסה\nנגיעה כפולה להתכופפות"), size: 17)
            AmuduLabel(model.tr("Start in a circle. Tap a player, then swipe upward from your held ball. Faster means higher; the ball travels toward the circle center. Names are spoken aloud. After a successful catch, everyone stays where they are: call someone even far away.",
                                "מתחילים במעגל. געו בשחקן והחליקו כלפי מעלה מהכדור שביד. מהר יותר פירושו גבוה יותר; הכדור נזרק למרכז המעגל. השם נקרא בקול. אחרי תפיסה מוצלחת כולם נשארים במקומם: אפשר לקרוא גם למי שרחוק."), size: 17)
            AmuduLabel(model.tr("Tap a player to aim, then swipe from your ball. Standard: too slow drops short; too fast can fly over their head. The ball must not touch the ground first. Easy: lower throws and ground bounces are allowed. Wind changes the flight.",
                                "געו בשחקן כדי לכוון והחליקו מהכדור. במצב רגיל: לאט מדי ייפול קרוב, ומהר מדי עלול לעבור מעל הראש. אסור שהכדור יפגע קודם בקרקע. במצב קל הזריקה נמוכה ומותרת קפיצה מהקרקע. הרוח משנה את המסלול."), size: 17)
            AmuduLabel(RuleText["timerHint"], size: 17)
            AmuduLabel(RuleText["idleHelp"], size: 17)
            AmuduLabel(RuleText["steps"] + " · 0–4", size: 18)
            AmuduButton(model.tr("Back", "חזרה")) { model.home() }
        }
    }
}

/// Android `journeyPage(step)`: the challenge, its partner or opponent, the goal, today's bonus and the 30 stages.
struct JourneyScreen: View {
    @ObservedObject var model: AppModel

    var body: some View {
        let step = model.journeyStep
        let d = SpudPractice(step)
        let s = d.stage
        let progress = model.journeyProgress()
        let bot = s.bot(d.cycle, [model.avatar])
        let current = step % 30
        return AmuduPage(model.tr("Daily skill journey", "מסע המיומנויות היומי"), background: model.art.scene(model.scene)) {
            AmuduLabel(model.tr("Challenge \(step % 30 + 1) of 30 · Cycle \(d.cycle + 1)", "אתגר \(step % 30 + 1) מתוך 30 · מסלול \(d.cycle + 1)"), size: 18)
            Image(uiImage: model.art.portrait(bot.id))
                .resizable()
                .scaledToFit()
                .frame(height: 145)
                .frame(maxWidth: .infinity)
            AmuduLabel(bot.name(hebrew: model.hebrew), size: 21, color: 0xffffdf70)
            AmuduLabel(model.tr(s.en, s.he), size: 26)
            AmuduLabel(model.tr(s.brief(false), s.brief(true)), size: 18)
            AmuduLabel(model.tr(s.role(false), s.role(true)), size: 17, color: 0xffacf4dc)
            AmuduLabel(model.tr("Goal: \(d.goal) successes · three hearts · no countdown", "היעד: \(d.goal) הצלחות · שלושה לבבות · בלי שעון"), size: 18)
            if Kotlin.less(progress.bonusDay, AppModel.today()) {
                AmuduLabel(model.tr("Your first success today earns 30 bonus points. Missing a day never resets your progress.",
                                    "ההצלחה הראשונה היום מזכה ב־30 נקודות בונוס. גם אם מפספסים יום, ההתקדמות נשמרת."), size: 16)
            } else {
                AmuduLabel(model.tr("Today's bonus is yours. Keep practicing if you like!", "הבונוס היומי כבר שלכם. אפשר להמשיך להתאמן בכיף!"), size: 16)
            }
            if model.hasPracticeSaved {
                AmuduButton(model.tr("Continue your practice", "המשך האימון")) { model.continuePractice() }
            }
            AmuduButton(model.tr("Start challenge", "התחלת אתגר")) { model.startJourney(step) }
            ForEach(Array(SpudJourney.stages.enumerated()), id: \.offset) { i, stage in
                let mark = i < current ? "✓ " : (i == current ? "→ " : "")
                AmuduLabel(mark + model.tr(stage.en, stage.he), size: 16, color: i == current ? 0xffffdf70 : 0xffffffff)
            }
            AmuduButton(model.tr("Back", "חזרה")) { model.home() }
        }
    }
}

/// Android `journeyResult()`.
struct JourneyResultScreen: View {
    @ObservedObject var model: AppModel

    var body: some View {
        let won = model.journeyOutcome?.won ?? false
        return AmuduPage(won ? model.tr("Challenge complete!", "האתגר הושלם!") : model.tr("Let's try again", "מנסים שוב"),
                         background: model.art.scene(model.scene)) {
            if let o = model.journeyOutcome {
                if o.won {
                    JourneyCelebration()
                        .frame(height: 160)
                        .frame(maxWidth: .infinity)
                }
                AmuduLabel(model.tr(o.stage.en, o.stage.he), size: 24)
                AmuduLabel(model.tr("\(o.successes)/\(o.goal) successes", "\(o.successes)/\(o.goal) הצלחות"), size: 22, color: 0xffffdf70)
                AmuduLabel(o.won ? model.tr("Progress saved · +\(o.gained) points", "ההתקדמות נשמרה · +\(o.gained) נקודות")
                           : model.tr("Your progress is safe. Take your time and try again.", "ההתקדמות שלכם נשמרת. קחו את הזמן ונסו שוב."), size: 18)
                AmuduButton(o.won ? model.tr("Next challenge", "האתגר הבא") : model.tr("Try again", "לנסות שוב")) { model.openJourney(o.next) }
            }
            AmuduButton(model.tr("Main menu", "תפריט ראשי")) { model.home() }
        }
    }
}

/// Android `supportPage()` (behind the grown-up gate): rate, share, feedback, ball-approach zoom and game sounds.
struct SupportScreen: View {
    @ObservedObject var model: AppModel
    @State private var zoomOpen = false

    var body: some View {
        AmuduPage(model.tr("Settings & feedback", "הגדרות ומשוב"), background: model.art.scene(model.scene)) {
            AmuduButton(model.tr("Rate the app", "דירוג האפליקציה")) { model.rateApp() }
            AmuduButton(model.tr("Share the game", "שיתוף המשחק")) { model.openShare() }
            AmuduButton(model.tr("Send feedback", "שליחת משוב")) { model.openFeedback() }
            AmuduButton(model.tr("Ball approach zoom", "התקרבות המצלמה לכדור"), color: 0xffdfcfff) { zoomOpen.toggle() }
            if zoomOpen {
                VStack(spacing: 0) {
                    AmuduLabel(model.tr("A closer view as the ball approaches. Game speed stays the same.", "מבט מקרוב כשהכדור מתקרב. מהירות המשחק נשארת ללא שינוי."), size: 16)
                    SettingSwitch(title: model.tr("Zoom when the ball approaches me", "התקרבות כשהכדור מגיע אליי"), isOn: $model.receptionZoomOwn)
                    SettingSwitch(title: model.tr("Follow another human's approach zoom", "מעקב אחר התקרבות לשחקן אנושי אחר"), isOn: $model.receptionZoomOthers)
                }
            }
            SettingSwitch(title: model.tr("Game sounds", "צלילי המשחק"), isOn: $model.gameSounds, minHeight: 52)
            AmuduButton(model.tr("Back", "חזרה")) { model.home() }
        }
        .alert(model.tr("Your message", "ההודעה שלכם"), isPresented: $model.shareVisible) {
            TextField("", text: $model.shareInput)
            Button(model.tr("Choose an app", "בחירת אפליקציה")) { model.shareMessage() }
            Button(model.tr("Cancel", "ביטול"), role: .cancel) {}
        }
        .alert(model.tr("Your feedback", "המשוב שלכם"), isPresented: $model.feedbackVisible) {
            TextField(model.tr("What should we improve?", "מה כדאי לשפר?"), text: $model.feedbackInput)
            Button(model.tr("Choose an app", "בחירת אפליקציה")) { model.sendFeedback() }
            Button(model.tr("Cancel", "ביטול"), role: .cancel) {}
        }
        .sheet(item: $model.shareSheet) { item in
            ActivityView(text: item.text)
        }
    }
}

/// Android `rankPage()`: the total and every colour rank with its threshold.
struct RankScreen: View {
    @ObservedObject var model: AppModel

    var body: some View {
        AmuduPage(model.tr("Your colors & progress", "הצבעים וההתקדמות שלכם"), background: model.art.scene(model.scene)) {
            AmuduLabel(model.tr("Total points: ", "ניקוד מצטבר: ") + String(model.rankPoints), size: 24)
            AmuduLabel(model.tr("Earn 5 points for a catch or a successful tag, and 15 for winning a completed game. Your color is saved across sessions.",
                                "צברו 5 נקודות על תפיסה או פגיעה מוצלחת, ו־15 על ניצחון במשחק שהסתיים. הצבע נשמר בין משחקים."), size: 16)
            ForEach(ProgressRanks.all, id: \.threshold) { r in
                AmuduLabel(model.tr(r.en, r.he) + " · " + String(r.threshold), size: 18, color: r.ink)
                    .frame(height: 48)
                    .background(RoundedRectangle(cornerRadius: 18).fill(Color(argb: r.color)))
                    .padding(.top, 8)
            }
            AmuduButton(model.tr("Back", "חזרה")) { model.home() }
        }
    }
}

/// Android `openRoom()` connecting page.
struct ConnectingScreen: View {
    @ObservedObject var model: AppModel

    var body: some View {
        AmuduPage(model.tr("Connecting…", "מתחברים…"), background: model.art.scene(model.scene)) {
            AmuduLabel(model.connectingInfo)
            AmuduButton(model.tr("Back", "חזרה")) { model.home() }
        }
    }
}

/// Android `lobby()`.
struct LobbyScreen: View {
    @ObservedObject var model: AppModel

    var body: some View {
        AmuduPage(model.tr("Your private game", "המשחק הפרטי שלכם"), background: model.art.scene(model.scene)) {
            if let state = model.lobbyState {
                AmuduLabel(state.code, size: 32, color: 0xffa2fff1)
                AmuduButton(model.tr("Copy code", "העתקת הקוד"), color: 0xffc4e5ff) { model.copyCode(state.code) }
                if let mode = state.mode {
                    AmuduLabel(mode, size: 18, color: 0xffa8f7df)
                }
                ForEach(state.lines) { line in
                    AmuduLabel(line.text, size: 18)
                }
                AmuduButton(model.tr("Ready", "מוכנים")) { state.onReady() }
                if state.host {
                    AmuduButton(model.tr("Start", "התחלה"), color: 0xffc4e5ff) { state.onStart() }
                }
                AmuduLabel(model.tr("Friends join by code. At least two players are needed; empty places can stay empty.", "חברים מצטרפים עם הקוד. צריך לפחות שני שחקנים; מקומות ריקים יכולים להישאר ריקים."), size: 14)
            }
            AmuduButton(model.tr("Back", "חזרה"), color: 0xffe2d3ff) { model.home() }
        }
    }
}

/// Android `result()`: three columns in landscape, one in portrait.
struct ResultScreen: View {
    @ObservedObject var model: AppModel

    var body: some View {
        GeometryReader { geo in
            let columns = Array(repeating: GridItem(.flexible(), spacing: 8), count: geo.size.width > geo.size.height ? 3 : 1)
            AmuduPage(model.tr("What a game!", "איזה משחק!"), background: model.art.scene(model.scene)) {
                AmuduLabel(model.resultTitle, size: 18, color: 0xffacffe7)
                LazyVGrid(columns: columns, spacing: 10) {
                    ForEach(model.results) { row in
                        HStack(spacing: 0) {
                            Image(uiImage: model.art.portrait(row.character))
                                .resizable()
                                .scaledToFit()
                                .frame(width: 55, height: 65)
                            AmuduLabel(row.name, size: 16)
                            AmuduLabel(row.score, size: 22, color: 0xffffe487)
                                .fixedSize()
                        }
                        .padding(.horizontal, 8)
                        .padding(.vertical, 5)
                        .frame(height: 75)
                        .background(RoundedRectangle(cornerRadius: 18).fill(Color(argb: row.winner ? 0xb53c7b75 : 0xa51b3e59)))
                    }
                }
                .padding(.vertical, 5)
                AmuduButton(model.tr("Main menu", "תפריט ראשי")) { model.home() }
            }
        }
    }
}
