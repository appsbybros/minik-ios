import SwiftUI
import WebKit

/// Android `home()` after `FamilyMenu.organize`: the title, the points-and-colour hero beside the ball, the motto, then
/// four sections; "Privacy policy" and "More Minik apps & games" are in Advanced. "Ads & purchases" is not part of the
/// iOS app. `FamilyMoreFrame`'s "More below" cue shows under the menu while more lies below.
struct HomeScreen: View {
    @ObservedObject var model: AppModel
    @FocusState private var nameFocused: Bool

    var body: some View {
        let learn = model.tr("Start & learn", "מתחילים ולומדים")
        let play = model.tr("Play", "משחקים")
        let saved = model.tr("Saved games", "משחקים שמורים")
        let advanced = model.tr("Advanced", "מתקדם")
        return AmuduPage(GameText.title(), background: model.art.scene(model.scene), scrollCue: true) {
            hero
            AmuduLabel(model.tr("Call. Catch. Freeze. Laugh.", "קוראים. תופסים. עוצרים. צוחקים."), size: 18, color: 0xff9bffe4)
            MenuSection(learn, color: MenuColors.learn, open: model.sectionOpen(learn, true), toggle: { model.toggleSection(learn, true) }) {
                SectionButton(model.tr("How to play", "איך משחקים"), color: MenuColors.learn) { model.openHelp() }
                SectionButton(model.tr("Daily skill journey", "אתגר יומי"), color: MenuColors.learn) { model.openJourney() }
                SectionButton(model.tr("Your colors & progress", "הצבעים וההתקדמות שלכם"), color: MenuColors.learn) { model.openRank() }
                profile
            }
            MenuSection(play, color: MenuColors.play, open: model.sectionOpen(play, true), toggle: { model.toggleSection(play, true) }) {
                // Android `FamilyButtonAlignment.opticalOffset`: in Hebrew the two lines sit 1.5 dp lower and higher.
                SectionButton(model.tr("Create game", "יצירת משחק"), color: MenuColors.play, offset: model.hebrew ? 1.5 : 0) { model.openSetup() }
                SectionButton(model.tr("Join by code", "הצטרפות עם קוד"), color: MenuColors.play) { model.requestJoin() }
                SectionButton(model.tr("Family league", "ליגה משפחתית"), color: MenuColors.play, offset: model.hebrew ? -1.5 : 0) {
                    model.openLeagueFromHome()
                }
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
                if model.hasPrivacyPolicy {
                    SectionButton(model.tr("Privacy policy", "מדיניות פרטיות"), color: MenuColors.advanced) { model.openPrivacy() }
                }
                MenuLink(title: FamilyMessages.text("More Minik apps & games", "עוד אפליקציות ומשחקי מיניק")) { model.moreApps() }
            }
        }
    }

    /// Android (2026-11): the total points and colour (16 sp in the colour, with a dark shadow) beside the ball picture.
    private var hero: some View {
        let rank = ProgressRanks.at(model.rankPoints)
        return HStack(spacing: 0) {
            Text(model.tr("Total points: ", "ניקוד מצטבר: ") + String(model.rankPoints) + "\n" + model.tr("Color: ", "צבע: ") + model.tr(rank.en, rank.he))
                .font(.system(size: 16, weight: .bold))
                .foregroundColor(Color(argb: rank.color))
                .shadow(color: .black, radius: 2)
                .multilineTextAlignment(.leading)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, 9)
                .padding(.vertical, 7)
                .frame(maxWidth: .infinity, alignment: .leading)
            Image(uiImage: model.art.ball(.neon))
                .resizable()
                .scaledToFit()
                .frame(height: 110)
                .frame(maxWidth: .infinity)
        }
    }

    /// The name, avatar and avatar name (Android moves them into the first section, on its pale panel: light texts take
    /// the menu ink and the name field is `FamilyFormStyle`'s white input; since 2026-11 the avatar name is plain ink).
    private var profile: some View {
        VStack(spacing: 0) {
            AmuduLabel(model.tr("Your name", "השם שלכם"), size: 18, color: MenuColors.ink)
            TextField("", text: Binding(get: { model.playerName }, set: { model.updateName($0) }),
                      prompt: Text(model.tr("Your name", "השם שלכם")).foregroundColor(Color(argb: SkyInk.hint)))
                .font(.system(size: 18))
                .foregroundColor(Color(argb: SkyInk.input))
                .multilineTextAlignment(.center)
                .textInputAutocapitalization(.words)
                .autocorrectionDisabled()
                .submitLabel(.done)
                .focused($nameFocused)
                .padding(.horizontal, 12)
                .frame(height: 55)
                .background(InputFace(focused: nameFocused))
            Rectangle()
                .fill(Color(argb: 0xffa8f7df))
                .frame(height: 3)
            AmuduParagraph(model.tr("Used only when you play with friends in a private room.", "ישמש רק במשחק עם חברים בחדר פרטי."), size: 14, color: MenuColors.ink)
            avatarRow
            AmuduLabel(AmuduCharacters.get(model.avatar).name(hebrew: model.hebrew), size: 16, color: 0xff17384d)
                .padding(.top, 10)
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

/// Android `setup()` (2026-11): rule mode, room capacity, arena and ball pictures, the environment and advanced-rule
/// groups, house players (at most one per free place), then Start / Open private room — or, for a family league, its
/// creation or a new round.
struct SetupScreen: View {
    @ObservedObject var model: AppModel

    var body: some View {
        let purpose = model.setupPurpose
        return AmuduPage(model.tr("Create your game", "יוצרים משחק"), background: model.art.scene(model.scene),
                         back: { if purpose != 0 { model.leaguePage() } else { model.home() } }) {
            ChoiceMenu(title: RuleText["mode"], items: RuleSet.allCases.map { RuleText.mode($0) },
                       selected: RuleSet.allCases.firstIndex(of: model.rules) ?? 0) { i in
                model.selectRules(RuleSet.allCases[i])
            }
            AmuduParagraph(RuleText["rulesHint"], size: 15, color: 0xffd0e4ee)
            if purpose == 0 {
                ChoiceMenu(title: model.tr("Room capacity", "מספר מקומות בחדר"), items: (2...10).map { String($0) }, selected: model.count - 2) { i in
                    model.setCapacity(i + 2)
                }
            }
            AmuduParagraph(model.capacityNote, size: 16, color: 0xffa8f7df)
            FieldTitle(model.tr("Arena", "זירה"))
            PictureChoices(options: ArenaScene.allCases.map { PictureOption(id: $0.rawValue, name: model.tr($0.en, $0.he), image: model.art.scene($0)) },
                           selected: model.scene.rawValue, arena: true) { id in
                model.scene = ArenaScene(rawValue: id) ?? .park
                model.persist()
            }
            FieldTitle(model.tr("Ball", "כדור"))
            PictureChoices(options: BallKind.allCases.map { PictureOption(id: $0.rawValue, name: model.tr($0.en, $0.he), image: model.art.ballPreview($0)) },
                           selected: model.ball.rawValue, arena: false) { id in
                model.ball = BallKind(rawValue: id) ?? .foam
                model.persist()
            }
            GroupToggle(title: RuleText["environment"], expanded: model.environmentOpen, first: true) { model.environmentOpen.toggle() }
            if model.environmentOpen {
                environment
                    .padding(.bottom, 12)
            }
            GroupToggle(title: RuleText["advanced"], expanded: model.advancedOpen, first: false) { model.advancedOpen.toggle() }
            if model.advancedOpen {
                advanced
                    .padding(.bottom, 12)
            }
            if purpose != 2 {
                FieldTitle(model.tr("House players · choose your team of friends", "שחקני הבית · בוחרים עם מי לשחק"))
                ForEach(AmuduCharacters.all, id: \.id) { c in
                    characterRow(c)
                }
            }
            if purpose != 0 {
                AmuduButton(purpose == 1 ? model.tr("Create a family league", "יצירת ליגה משפחתית") : model.tr("Open league round", "פתיחת משחק בליגה")) {
                    model.setupLeagueAction()
                }
                .padding(.top, 24)
            } else {
                AmuduButton(model.tr("Start", "התחלה")) { model.startFromSetup() }
                    .padding(.top, 24)
                AmuduButton(model.tr("Open private room", "פתיחת חדר פרטי"), color: 0xffb7dcff) { model.openPrivateRoom() }
            }
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
            if model.rules == .nicknames {
                ChoiceMenu(title: model.tr("Answering nicknames", "איך עונים לכינויים"),
                           items: [model.tr("Choose from nicknames", "בחירה מתוך כינויים"), model.tr("Show the correct nickname", "הצגת הכינוי הנכון"),
                                   model.tr("Type the nickname", "הקלדת הכינוי")],
                           selected: NicknameAnswer.allCases.firstIndex(of: model.nicknameAnswer) ?? 0) { i in
                    model.nicknameAnswer = NicknameAnswer.allCases[i]
                    model.persist()
                }
            }
            ChoiceMenu(title: RuleText["time"], items: AppModel.secondsChoices.map { $0 == 0 ? RuleText["noLimit"] : "\($0) s" },
                       selected: AppModel.secondsChoices.firstIndex(of: model.actionSeconds) ?? -1) { i in
                model.actionSeconds = AppModel.secondsChoices[i]
                model.persist()
            }
            AmuduParagraph(EnvironmentCopy.get("timer"), size: 14, color: 0xffd0e4ee)
            ChoiceMenu(title: RuleText["callRule"], items: [RuleText["optional"], RuleText["required"]], selected: model.requireCall ? 1 : 0) { i in
                model.requireCall = i == 1
                model.persist()
            }
            ChoiceMenu(title: RuleText["steps"], items: [RuleText["none"], "1", "2", "3", "4"], selected: model.stepsAfterCall) { i in
                model.stepsAfterCall = i
                model.persist()
            }
            ChoiceMenu(title: model.tr("Throw mode", "מצב זריקה"), items: ThrowMode.allCases.map { model.tr($0.en, $0.he) },
                       selected: ThrowMode.allCases.firstIndex(of: model.throwMode) ?? 0) { i in
                model.throwMode = ThrowMode.allCases[i]
                model.persist()
            }
            ChoiceMenu(title: model.tr("Ground contact before a hit", "נגיעה בקרקע לפני פגיעה"),
                       items: [EnvironmentCopy.get("Not allowed"), EnvironmentCopy.get("Allowed")], selected: model.allowGroundHit ? 1 : 0) { i in
                model.allowGroundHit = i == 1
                model.persist()
            }
            ChoiceMenu(title: model.tr("Turn limit", "תורים במשחק"), items: ["10", "20", "35", "50", RuleText["noLimit"]],
                       selected: AppModel.turnChoices.firstIndex(of: model.turns) ?? 4) { i in
                model.turns = AppModel.turnChoices[i]
                model.persist()
            }
        }
    }

    /// Android (2026-11): the portrait and the check box on one line, the five ratings (with Jump) indented below.
    private func characterRow(_ c: AmuduCharacter) -> some View {
        let isAvatar = c.id == model.avatar
        let title = c.name(hebrew: model.hebrew) + (isAvatar ? model.tr(" · Your avatar", " · הדמות שלכם") : "")
        let q = c.qualities
        let ratings: [(String, Int)] = [(model.tr("Accuracy", "דיוק"), q.accuracy), (model.tr("Power", "עוצמה"), q.power),
                                        (model.tr("Speed", "מהירות"), q.speed), (model.tr("Catch", "תפיסה"), q.catching),
                                        (model.tr("Jump", "קפיצה"), q.jumping)]
        return VStack(spacing: 0) {
            HStack(alignment: .center, spacing: 0) {
                Image(uiImage: model.art.portrait(c.id))
                    .resizable()
                    .scaledToFit()
                    .frame(width: 54, height: 78)
                HouseCheck(title: title, checked: model.house.contains(c.id), enabled: model.houseEnabled(c.id)) { selected in
                    model.setHouse(c.id, selected)
                }
            }
            VStack(spacing: 0) {
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
            .padding(.leading, 54)
        }
        .padding(.vertical, 7)
    }
}

/// Android `help()` (2026-11): the journey, the settings lessons and the rules.
struct HelpScreen: View {
    @ObservedObject var model: AppModel

    var body: some View {
        AmuduPage(model.tr("How to play", "איך משחקים"), background: model.art.scene(model.scene), back: { model.home() }) {
            AmuduButton(model.tr("Learn by playing", "לומדים תוך כדי משחק")) { model.openJourney() }
            AmuduButton(model.learn("settings_title"), color: 0xffb8d9ff) { model.openLessonHub() }
            AmuduParagraph(model.tr("Turn your phone to play in landscape, or tap ↻ during a game. Your chosen orientation is remembered for the next game.",
                                    "סובבו את הטלפון למשחק לרוחב, או געו ב־↻ בזמן המשחק. הכיוון שבחרתם נשמר למשחק הבא."), size: 17)
            AmuduParagraph(RuleText["rulesHint"], size: 17)
            AmuduParagraph(model.tr("Tap Catch as the ball arrives: you have half a second. Jump over low balls or duck under high balls. Low balls are hardest to catch; high balls are a little harder than centre throws. Skill, speed and facing still matter.",
                                    "לחצו תפיסה כשהכדור מגיע: יש לכם חצי שנייה. קפצו מעל כדור נמוך או התכופפו מתחת לכדור גבוה. כדור נמוך הכי קשה לתפוס; כדור גבוה קצת קשה יותר מכדור למרכז הגוף. המיומנות, המהירות וכיוון העמידה עדיין משפיעים."), size: 17)
            AmuduLabel(RuleText["nicknames"], size: 21, color: 0xffa8f7df)
            AmuduParagraph(RuleText["nickHelp"], size: 17)
            AmuduLabel(RuleText["spud"], size: 21, color: 0xffa8f7df)
            AmuduParagraph(RuleText["spudHelp"], size: 17)
            AmuduParagraph(model.tr("Drag to run · Time your catch\nJump low balls · Duck high balls", "גררו לריצה · תזמנו את התפיסה\nקפצו מעל כדור נמוך · התכופפו מתחת לגבוה"), size: 17)
            AmuduParagraph(model.learn("general_calls"), size: 17)
            AmuduParagraph(model.learn("general_stop"), size: 17)
            AmuduParagraph(model.tr("Easy: tap the exact spot to throw. Standard: choose a player, then tap when the moving dot is where you want to hit. Farther targets move faster. Pro: swipe from your ball to control direction, power and height. Ground contact is a separate rule for everyone; it is off by default.",
                                    "קל: געו במקום המדויק כדי לזרוק. סטנדרטי: בחרו שחקן וגעו כשהנקודה הנעה נמצאת במקום שבו רוצים לפגוע. ככל שהמטרה רחוקה הנקודה מהירה יותר. מקצועי: החליקו מהכדור לשליטה בכיוון, בעוצמה ובגובה. נגיעה בקרקע היא כלל נפרד לכולם, ואסורה כברירת מחדל."), size: 17)
            AmuduParagraph(model.learn("burst_rule"), size: 17)
            AmuduParagraph(RuleText["timerHint"], size: 17)
            AmuduParagraph(RuleText["idleHelp"], size: 17)
            AmuduLabel(RuleText["steps"] + " · 0–4", size: 18)
        }
    }
}

/// Android `practiceOptions(col, step, topic)`: the control difficulty, the ball (with its note), the conditions or the
/// ground rule of an environment lesson, the conditions summary, the brief, the goal and the start button. The control
/// and ball are remembered (`journeyControl`, `journeyBall`); conditions and the ground rule are chosen per visit.
struct PracticeOptions: View {
    @ObservedObject var model: AppModel
    let step: Int
    let topic: String
    @State private var mode: ThrowMode
    @State private var chosen: BallKind
    @State private var conditions: PracticeConditions
    @State private var ground = false

    /// `control` and `ballChoice` are the saved `journeyControl` and `journeyBall` (read by the caller's body).
    init(model: AppModel, step: Int, topic: String, control: ThrowMode, ballChoice: String) {
        self.model = model
        self.step = step
        self.topic = topic
        _mode = State(initialValue: control)
        _chosen = State(initialValue: PracticeCurriculum.ball(step, ballChoice, topic))
        let initial: PracticeConditions
        switch topic {
        case "wind": initial = .wind
        case "light": initial = .breezeEvening
        case "gravity": initial = .space
        default: initial = topic.isEmpty ? PracticeCurriculum.conditions(step) : .calm
        }
        _conditions = State(initialValue: initial)
    }

    private var stage: SpudStage {
        return ["ground", "paint"].contains(topic) ? SpudStage("lesson_tag", "Hit the target", "פוגעים במטרה", .tag) : SpudJourney.stage(step)
    }

    var body: some View {
        let s = stage
        let modes = ThrowMode.allCases
        let allowed = PracticeCurriculum.balls(step, topic)
        return VStack(spacing: 0) {
            ChoiceMenu(title: model.tr("Control difficulty", "רמת שליטה"), items: modes.map { model.tr($0.en, $0.he) },
                       selected: modes.firstIndex(of: mode) ?? 0, learning: true) { i in
                mode = modes[i]
                model.setJourneyControl(mode)
            }
            if topic != "paint" {
                ChoiceMenu(title: model.tr("Ball", "כדור"), items: allowed.map { model.tr($0.en, $0.he) },
                           selected: allowed.firstIndex(of: chosen) ?? 0, learning: true) { i in
                    let value = allowed[i].rawValue
                    chosen = PracticeCurriculum.ball(step, value, topic)
                    model.setJourneyBall(value)
                }
                AmuduParagraph(model.learn("ball_" + chosen.rawValue.lowercased()), size: 16, color: 0xffacf4dc)
            }
            if s.skill == .rebound {
                AmuduParagraph(model.learn("no_balloon_rebound"), size: 16)
            }
            if ["wind", "gravity", "light"].contains(topic) {
                ChoiceMenu(title: model.learn("conditions"), items: PracticeConditions.allCases.map { model.conditionText($0) },
                           selected: PracticeConditions.allCases.firstIndex(of: conditions) ?? 0, learning: true) { i in
                    conditions = PracticeConditions.allCases[i]
                }
            }
            if topic == "ground" {
                ChoiceMenu(title: model.learn("ground_title"), items: [model.learn("ground_forbidden"), model.learn("ground_allowed")],
                           selected: ground ? 1 : 0, learning: true) { i in
                    ground = i == 1
                }
            }
            AmuduParagraph(model.conditionText(conditions) + (s.skill == .tag ? " · " + model.learn(ground ? "ground_allowed" : "ground_forbidden") : ""), size: 16)
            AmuduParagraph(model.tr(PracticeGuidance.brief(s, mode, false), PracticeGuidance.brief(s, mode, true)), size: 18)
            AmuduParagraph(topic.isEmpty
                           ? model.tr("Goal: \(s.goal(step / SpudJourney.size)) successes · three hearts · no countdown",
                                      "היעד: \(s.goal(step / SpudJourney.size)) הצלחות · שלושה לבבות · בלי שעון")
                           : model.learn("lesson_goal"), size: 16)
            AmuduButton(topic.isEmpty ? model.tr("Start challenge", "התחלת האתגר") : model.learn("try_it")) {
                model.launchPractice(step, mode, chosen, conditions, topic, ground)
            }
            .padding(.top, 16)
        }
    }
}

/// Android `journeyPage(step)` (2026-11): the challenge, its partner or opponent, the practice options, today's bonus
/// and the challenge map (completed challenges can be replayed with other choices).
struct JourneyScreen: View {
    @ObservedObject var model: AppModel

    var body: some View {
        let safe = model.journeyStep
        let p = model.journeyProgress()
        let d = SpudPractice(safe)
        let s = d.stage
        let bot = s.bot(d.cycle, [model.avatar])
        let size = SpudJourney.size
        let cycle = safe / size
        let female = ["mia", "kyra", "gaya", "amber", "june"].contains(bot.id)
        let role = (model.hebrew && female) ? (s.defence ? "יריבה לאימון:" : "שותפה לאימון:") : model.learn(s.defence ? "opponent" : "partner")
        return AmuduPage(model.tr("Daily skill journey", "אתגר יומי"), background: model.art.scene(model.scene), back: { model.home() }) {
            AmuduLabel(model.tr("Challenge \(safe % size + 1) of \(size) · Cycle \(d.cycle + 1)", "אתגר \(safe % size + 1) מתוך \(size) · מסלול \(d.cycle + 1)"), size: 18)
            AmuduLabel(model.tr(s.en, s.he), size: 24)
            Image(uiImage: model.art.portrait(bot.id))
                .resizable()
                .scaledToFit()
                .frame(height: 98)
                .frame(maxWidth: .infinity)
            AmuduLabel(role + " " + bot.name(hebrew: model.hebrew), size: 18, color: 0xffffdf70)
            AmuduParagraph(model.learn("one_completion"), size: 16)
            PracticeOptions(model: model, step: safe, topic: "", control: model.journeyControl, ballChoice: model.journeyBall)
                .id("journey-\(safe)")
            if model.hasPracticeSaved {
                AmuduButton(model.tr("Continue your practice", "המשך האימון")) { model.continuePractice() }
            }
            AmuduParagraph(Kotlin.less(p.bonusDay, AppModel.today()) ? model.learn("bonus") : model.learn("bonus_done"), size: 16)
            AmuduLabel(model.tr("Challenge map", "מפת האתגרים"), size: 22)
                .padding(.top, 15)
                .padding(.bottom, 1)
            AmuduParagraph(model.learn("replay_hint"), size: 16)
            ForEach(Array(SpudJourney.stages.enumerated()), id: \.offset) { i, stage in
                mapRow(index: cycle * size + i, stage: stage, progress: p)
            }
            if cycle > 0 {
                AmuduButton(model.learn("earlier_cycle"), color: 0xffb8d9ff) { model.openJourney((cycle - 1) * size) }
            }
            if cycle < p.completed / size {
                AmuduButton(model.learn("current_challenge"), color: 0xffb8d9ff) { model.openJourney(p.completed) }
            }
        }
    }

    /// One line of the challenge map: ✓ done, → current; unlocked lines are gold and open that challenge.
    @ViewBuilder private func mapRow(index: Int, stage: SpudStage, progress p: SpudProgress) -> some View {
        let done = p.done(index)
        let unlocked = done || index == p.completed
        let conditions = PracticeCurriculum.conditions(index)
        let mark = done ? "✓ " : (index == p.completed ? "→ " : "")
        let text = mark + model.tr(stage.en, stage.he) + (conditions == .calm ? "" : "\n" + model.conditionText(conditions))
        let line = Text(text)
            .font(.system(size: 17, weight: .bold))
            .foregroundColor(Color(argb: unlocked ? 0xffffdf70 : 0xffffffff))
            .multilineTextAlignment(.center)
            .fixedSize(horizontal: false, vertical: true)
            .padding(.horizontal, 9)
            .padding(.vertical, 10)
            .frame(maxWidth: .infinity, minHeight: 48)
        if unlocked {
            Button { model.openJourney(index) } label: { line.contentShape(Rectangle()) }
                .buttonStyle(.plain)
                .accessibilityLabel(text + " · " + model.learn("open_challenge"))
        } else {
            line
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
                AmuduLabel(o.replay ? model.learn("replay_done")
                           : (o.won ? model.tr("Progress saved · +\(o.gained) points", "ההתקדמות נשמרה · +\(o.gained) נקודות")
                              : model.tr("Your progress is safe. Take your time and try again.", "ההתקדמות שלכם נשמרת. קחו את הזמן ונסו שוב.")), size: 18)
                AmuduButton(o.won ? model.tr("Next challenge", "האתגר הבא") : model.tr("Try again", "לנסות שוב")) { model.openJourney(o.next) }
                    .padding(.top, 12)
            }
            AmuduButton(model.tr("Main menu", "תפריט ראשי"), color: 0xffe91e63, ink: 0xffffffff) { model.home() }
                .padding(.top, 16)
        }
    }
}

/// Android `lessonHub()`: one button per settings lesson.
struct LessonHubScreen: View {
    @ObservedObject var model: AppModel

    var body: some View {
        AmuduPage(model.learn("settings_title"), background: model.art.scene(model.scene), back: { model.openHelp() }) {
            AmuduParagraph(model.learn("settings_intro"))
            ForEach(PracticeCurriculum.topics, id: \.self) { topic in
                AmuduButton(model.learn("title_" + topic), color: 0xffb8d9ff) { model.openLesson(topic) }
            }
        }
    }
}

/// Android `lessonPage(topic)`: the lesson text, then either the match rules explained or a free practice.
struct LessonScreen: View {
    @ObservedObject var model: AppModel

    var body: some View {
        let topic = model.lessonTopic
        return AmuduPage(model.learn("title_" + topic), background: model.art.scene(model.scene), back: { model.openLessonHub() }) {
            AmuduParagraph(model.learn("body_" + topic), size: 18)
            if topic == "paint" {
                AmuduParagraph(model.learn("burst_rule"), size: 16)
            }
            if topic == "rules" {
                ForEach(["nicknames", "stop_rule", "steps", "timer", "light"], id: \.self) { key in
                    AmuduLabel(model.learn("title_" + key), size: 20, color: 0xffffd65a)
                    AmuduParagraph(model.learn("body_" + key), size: 17)
                }
            } else {
                AmuduParagraph(model.learn("lesson_no_points"), size: 16, color: 0xffacf4dc)
                PracticeOptions(model: model, step: PracticeCurriculum.step(topic), topic: topic, control: model.journeyControl,
                                ballChoice: model.journeyBall)
                    .id("lesson-" + topic)
            }
        }
    }
}

/// Android `journeyResult()` of a lesson: no points; try again with the same choices, or back to the lesson.
struct LessonResultScreen: View {
    @ObservedObject var model: AppModel

    var body: some View {
        let o = model.lessonOutcome
        let topic = o?.topic ?? ""
        return AmuduPage(model.learn(o?.won == true ? "lesson_complete" : "repeat"), background: model.art.scene(model.scene),
                         back: { model.openLesson(topic) }) {
            AmuduLabel(model.learn("title_" + topic), size: 24)
            AmuduParagraph(model.learn("lesson_no_points"))
            AmuduButton(model.learn("repeat")) { model.repeatLesson() }
            AmuduButton(model.learn("return_lesson"), color: 0xffb8d9ff) { model.openLesson(topic) }
        }
    }
}

/// Android `supportPage()` (behind the grown-up gate): rate, share, feedback, the optional lag diagnosis, ball-approach
/// zoom and game sounds.
struct SupportScreen: View {
    @ObservedObject var model: AppModel
    @State private var zoomOpen = false

    var body: some View {
        AmuduPage(model.tr("Settings & feedback", "הגדרות ומשוב"), background: model.art.scene(model.scene), back: { model.home() }) {
            Color.clear.frame(height: 24)
            AmuduButton(model.tr("Rate the app", "דירוג האפליקציה"), color: 0xffffd65a) { model.rateApp() }
            AmuduButton(model.tr("Share the game", "שיתוף המשחק"), color: 0xffff5b67) { model.openShare() }
            AmuduButton(model.tr("Send feedback", "שליחת משוב"), color: 0xffff5ba6) { model.openFeedback() }
            AmuduButton(model.lagButtonTitle, color: 0xffa6dcff) { model.lagDiagnosis() }
            AmuduButton(model.tr("Ball approach zoom", "מיקוד המצלמה בכדור"), color: 0xffdfcfff) { zoomOpen.toggle() }
            if zoomOpen {
                VStack(spacing: 0) {
                    AmuduParagraph(model.tr("A closer view as the ball approaches. Game speed stays the same.", "מבט מקרוב כשהכדור מתקרב. מהירות המשחק נשארת ללא שינוי."), size: 16)
                    SettingSwitch(title: model.tr("Zoom when the ball approaches me", "מיקוד המצלמה כשהכדור מגיע אליי"), isOn: $model.receptionZoomOwn)
                    SettingSwitch(title: model.tr("Follow another human's approach zoom", "מיקוד המצלמה כששחקן אחר מקבל את הכדור"), isOn: $model.receptionZoomOthers)
                }
            }
            SettingSwitch(title: model.tr("Game sounds", "צלילי המשחק"), isOn: $model.gameSounds, minHeight: 52)
        }
        .sheet(item: $model.shareSheet) { item in
            ActivityView(text: item.text)
        }
    }
}

/// Android `rankPage()`: the total and every colour rank with its threshold (flat labels with 8 dp corners, as
/// `FamilyFormStyle` leaves them).
struct RankScreen: View {
    @ObservedObject var model: AppModel

    var body: some View {
        AmuduPage(model.tr("Your colors & progress", "הצבעים וההתקדמות שלכם"), background: model.art.scene(model.scene), back: { model.home() }) {
            AmuduLabel(model.tr("Total points: ", "ניקוד מצטבר: ") + String(model.rankPoints), size: 24)
            AmuduParagraph(model.tr("Earn 5 points for a catch or a successful tag, and 15 for winning a completed game. Your color is saved across sessions.",
                                    "צברו 5 נקודות על תפיסה או פגיעה מוצלחת, ו־15 על ניצחון במשחק שהסתיים. הצבע נשמר בין משחקים."), size: 16)
            ForEach(ProgressRanks.all, id: \.threshold) { r in
                AmuduLabel(model.tr(r.en, r.he) + " · " + String(r.threshold), size: 18, color: r.ink)
                    .frame(height: 48)
                    .background(RoundedRectangle(cornerRadius: 8).fill(Color(argb: r.color)))
                    .padding(.top, 8)
            }
        }
    }
}

/// Android `privacyPage()`: the policy in the app language, in a web view without JavaScript or file access, 76% of the
/// screen high; https and mailto links open outside the app after the grown-up gate.
struct PrivacyScreen: View {
    @ObservedObject var model: AppModel

    var body: some View {
        GeometryReader { geo in
            AmuduPage(model.tr("Privacy policy", "מדיניות פרטיות"), background: model.art.scene(model.scene), back: { model.home() }) {
                PolicyWebView(html: AppModel.privacyPolicy() ?? "", open: { url in model.openPolicyLink(url) })
                    .frame(height: geo.size.height * 0.76)
            }
            .frame(width: geo.size.width, height: geo.size.height)
        }
    }
}

struct PolicyWebView: UIViewRepresentable {
    let html: String
    let open: @MainActor (URL) -> Void

    final class Coordinator: NSObject, WKNavigationDelegate {
        var open: @MainActor (URL) -> Void

        init(open: @escaping @MainActor (URL) -> Void) {
            self.open = open
        }

        func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction,
                     decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
            guard navigationAction.navigationType == .linkActivated, let url = navigationAction.request.url else {
                decisionHandler(.allow)
                return
            }
            if url.scheme == "https" || url.scheme == "mailto" {
                let action = open
                MainActor.assumeIsolated { action(url) }
            }
            decisionHandler(.cancel)
        }
    }

    func makeCoordinator() -> Coordinator {
        return Coordinator(open: open)
    }

    func makeUIView(context: Context) -> WKWebView {
        let configuration = WKWebViewConfiguration()
        configuration.defaultWebpagePreferences.allowsContentJavaScript = false
        let view = WKWebView(frame: .zero, configuration: configuration)
        view.navigationDelegate = context.coordinator
        view.loadHTMLString(html, baseURL: nil)
        return view
    }

    func updateUIView(_ uiView: WKWebView, context: Context) {}
}

/// Android `openRoom()` / `openLeagueRoom()` connecting page.
struct ConnectingScreen: View {
    @ObservedObject var model: AppModel

    var body: some View {
        AmuduPage(model.tr("Connecting…", "מתחברים…"), background: model.art.scene(model.scene), back: { model.connectingBack() }) {
            if model.connectingLeague {
                AmuduParagraph(model.connectingInfo)
            } else {
                AmuduLabel(model.connectingInfo)
            }
        }
    }
}

/// Android `lobby()` (2026-11): each player with a portrait and either quality stars (house players) or shared points
/// and readiness (humans); Ready for guests, Start for the host, and how many places are free.
struct LobbyScreen: View {
    @ObservedObject var model: AppModel

    var body: some View {
        AmuduPage(model.tr("Your private game", "המשחק הפרטי שלכם"), background: model.art.scene(model.scene), back: { model.leaveLobby() }) {
            if let state = model.lobbyState {
                AmuduLabel(state.code, size: 32, color: 0xffa2fff1)
                AmuduButton(model.tr("Copy code", "העתקת הקוד"), color: 0xffc4e5ff) { model.copyCode(state.code) }
                if let mode = state.mode {
                    AmuduLabel(mode, size: 18, color: 0xffa8f7df)
                }
                ForEach(state.players) { player in
                    row(player)
                }
                if !state.host && !state.ready {
                    AmuduButton(model.tr("Ready", "מוכנים"), enabled: !model.lobbyReadyPressed) { model.lobbyReady() }
                }
                if !state.host && state.ready {
                    AmuduLabel(model.tr("Ready ✓", "מוכנים ✓"), size: 18, color: 0xffa8f7df)
                }
                if state.host {
                    AmuduButton(model.tr("Start", "התחלה"), enabled: state.canStart) { model.lobbyStart() }
                        .padding(.top, 12)
                }
                AmuduParagraph(state.capacityNote, size: 16)
            }
        }
    }

    private func row(_ p: LobbyPlayer) -> some View {
        HStack(spacing: 0) {
            Image(uiImage: model.art.portrait(p.character))
                .resizable()
                .scaledToFit()
                .frame(width: 52, height: 68)
            VStack(alignment: .leading, spacing: 0) {
                AmuduParagraph(p.title, size: 18)
                if p.bot {
                    QualityStrip(values: p.qualities)
                        .frame(width: 175, height: 30)
                } else {
                    AmuduParagraph(p.progress, size: 16, color: 0xffc9eaff)
                    if !p.readiness.isEmpty {
                        AmuduParagraph(p.readiness, size: 15)
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.vertical, 7)
    }
}

/// Android `result()` (2026-11): "What a game!" after ten minutes or more (else "Game ended"), the winners, the players
/// in as many 220 dp columns as fit in landscape (at most three), and the way back (to the league after a league round).
struct ResultScreen: View {
    @ObservedObject var model: AppModel

    var body: some View {
        GeometryReader { geo in
            let landscape = geo.size.width > geo.size.height
            let column = ReadingPanel.width(available: geo.size.width, window: geo.size) - 40
            let count = landscape ? min(max(Int(column / 220), 1), 3) : 1
            let columns = Array(repeating: GridItem(.flexible(), spacing: 8), count: count)
            AmuduPage(model.resultHeading, background: model.art.scene(model.scene), back: { model.leaveResult() }) {
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
                                .offset(y: model.hebrew ? -2 : 0)
                        }
                        .padding(.horizontal, 8)
                        .padding(.vertical, 5)
                        .frame(height: 75)
                        .background(SkySurface(color: row.winner ? 0xb53c7b75 : 0xa51b3e59, radius: 18))
                    }
                }
                .padding(.vertical, 5)
                AmuduButton(model.resultLeague ? model.tr("Back to league", "חזרה לליגה") : model.tr("Main menu", "תפריט ראשי"), color: 0xffa6dcff) {
                    model.leaveResult()
                }
            }
        }
    }
}
