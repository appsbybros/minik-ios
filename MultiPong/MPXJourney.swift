import SwiftUI
import StoreKit

/// The journey screen's result card (Android CrossJourneyActivity.result).
struct MPXJourneyResult: Equatable {
    var win: Bool
    var title: String
    var score: String
    /// A won team match celebrates the local player's team (TeamVictoryView).
    var celebrate: [String]
}

/// Android cross/CrossJourneyActivity.kt (MinikCrossPong 5c1aa4d): the daily skill journey (brief, list, practice and its
/// result), the team game with house players, and the Settings page (sounds, menu music, ball assistance, rate / share /
/// feedback behind a grown-up question).
@MainActor final class CrossJourneyModel: ObservableObject {
    enum Page { case brief, list, teams, settings, game }
    @Published private(set) var page: Page = .brief
    @Published private(set) var court: CrossScene?
    @Published private(set) var hud = ""
    @Published private(set) var paused = false
    @Published var result: MPXJourneyResult?
    @Published var twoOpponents: Bool
    @Published var ids: [String]
    /// A short message (Android Toast).
    @Published var notice: String?
    @Published var help: String?
    @Published var gateOpen = false
    @Published var shareText: String?
    @Published var actionCamera: Bool { didSet { preferences.crossActionCamera = actionCamera; court?.fullScreen = actionCamera } }
    private(set) var practice: CrossPractice?
    private(set) var match: CrossEngine?
    private var lesson = false, handled = false, matchEndingSince: TimeInterval?, foreground = true
    private var gated: (() -> Void)?
    let preferences: MPPreferences
    let hebrew: Bool
    private let audio: MPAudio
    private let onClose: () -> Void
    private let onOnlineTeams: (Int) -> Void

    init(page: Page, players: Int, preferences: MPPreferences, hebrew: Bool, audio: MPAudio, onClose: @escaping () -> Void, onOnlineTeams: @escaping (Int) -> Void) {
        self.preferences = preferences; self.hebrew = hebrew; self.audio = audio; self.onClose = onClose; self.onOnlineTeams = onOnlineTeams
        let avatar = MPRoster.find(preferences.identity?.characterId ?? "")?.id ?? "miniko"
        ids = Array(([avatar] + MPRoster.all.map { $0.id }.filter { $0 != avatar }).prefix(4))
        twoOpponents = players != 3
        actionCamera = preferences.crossActionCamera
        switch page {
        case .teams: teams()
        case .settings: settings()
        default: brief()
        }
    }
    func tr(_ en: String, _ he: String) -> String { MPText.t(en, he, hebrew) }
    var current: CrossEngine? { practice?.engine ?? match }

    // ---- pages ---------------------------------------------------------------------------------------------------------------
    private func leaveGame() { court?.setActive(false); court = nil; practice = nil; match = nil; paused = false }
    func brief() { leaveGame(); page = .brief }
    func journeyList() { leaveGame(); page = .list }
    func teams() { leaveGame(); page = .teams }
    func settings() { leaveGame(); page = .settings }
    var step: Int { preferences.journeyStep }
    var stage: CrossStage { CrossJourney.stage(step) }
    var briefBot: MPHousePlayer { stage.bot(step / 30, exclude: [ids[0]]) }
    var savedPractice: Bool { preferences.savedPractice != nil }
    var savedMatch: Bool { preferences.savedTeamMatch != nil }

    func role(_ s: CrossStage) -> String {
        s.cooperative ? tr("Your partner starts with the best qualities for this skill. Later cycles use less precise partners, while every feed stays reachable.",
                           "השותף מתחיל עם הכישורים הטובים ביותר למיומנות הזאת. במסלולים הבאים השותפים פחות מדויקים, אבל כל מסירה נשארת בהישג יד.")
            : tr("Start against a gentler opponent. Later cycles increase the qualities that matter for this challenge. Your teammate still helps you.",
                 "מתחילים מול יריב עדין יותר. במסלולים הבאים מתחזקים הכישורים החשובים לאתגר הזה. חבר הקבוצה עדיין עוזר לכם.")
    }
    func instruction(_ s: CrossStage) -> String {
        switch s.skill {
        case .serve: return tr("Tap the golden court to serve there. The ball must bounce on your court first, then on the called court.", "הקישו על השולחן הזהוב כדי להגיש אליו. הכדור חייב לקפוץ קודם בצד שלכם, ואז בשולחן המסומן.")
        case .returning, .defend: return tr("Drag your paddle to the incoming ball after its bounce. Tap another court to choose your next direction. Each return counts only when it lands safely.", "גררו את המחבט לכדור הנכנס אחרי הקפיצה. הקישו על שולחן אחר כדי לבחור את הכיוון הבא. החזרה נספרת רק כשהכדור נוחת בבטחה.")
        case .aim: return tr("Tap the golden island to aim, then drag your paddle to the ball. Hit the island with a real return.", "הקישו על האי הזהוב כדי לכוון, ואז גררו את המחבט לכדור. פגעו באי בהחזרה אמיתית.")
        case .backhand: return tr("The feeder sends to your left. Tap the golden target, then meet the ball on the left of your court for a backhand.", "המוסר שולח לצד שמאל שלכם. הקישו על היעד הזהוב, ואז פגשו את הכדור בצד שמאל לחבטת גב כף היד.")
        case .forehand: return tr("The feeder sends to your right. Tap the golden target, then meet the ball on the right for a forehand.", "המוסר שולח לצד ימין שלכם. הקישו על היעד הזהוב, ואז פגשו את הכדור בצד ימין לחבטת כף היד.")
        case .shape: return tr("Paint the shape in order. Tap the next golden circle, then return the ball into it. A painted circle cannot count twice.", "צבעו את הצורה לפי הסדר. הקישו על העיגול הזהוב הבא, ואז החזירו אליו את הכדור. עיגול שכבר נצבע אינו נספר פעמיים.")
        case .pass: return tr("Tap your teammate's court, then move your paddle to the incoming ball. Send one friendly pass before your team returns to an opponent.", "הקישו על השולחן של חבר הקבוצה, ואז הזיזו את המחבט לכדור הנכנס. מותרת מסירה קבוצתית אחת לפני שמחזירים ליריב.")
        case .set: return CrossText.setHelp(hebrew)
        case .smash: return tr("Your teammate raises the ball. After it bounces on your court, swipe through it toward an opponent. A timed swipe makes a faster smash; waiting or tapping is not enough.", "חבר הקבוצה מרים לכם את הכדור. אחרי שהוא קופץ בצד שלכם, החליקו דרכו לכיוון יריב. החלקה בזמן יוצרת הנחתה מהירה; המתנה או הקשה אינן מספיקות.")
        case .paint: return tr("A 90-second team paint battle. Only rally returns paint; serves never paint. Paint more of the opposing team's courts. Make at least three returns yourself.", "קרב צבע קבוצתי של 90 שניות. רק החזרות במהלך חילופים צובעות; הגשות אינן צובעות. צבעו יותר מהשולחנות של היריבים והחזירו לפחות שלושה כדורים בעצמכם.")
        }
    }

    // ---- practice and team match -----------------------------------------------------------------------------------------
    func startJourney(_ step: Int) { play(CrossPractice(step: step, avatar: ids[0])) }
    func startChallenge() { lesson = false; startJourney(step) }
    func endlessServes() { play(CrossPractice(step: 0, avatar: ids[0], open: true)) }
    /// Android uses step 2 (the "Golden islands" stage) for this playground.
    func endlessPaint() { play(CrossPractice(step: 2, avatar: ids[0], open: true)) }
    func learnTeams() { lesson = true; startJourney(7) }
    func onlineTeams() { onOnlineTeams(twoOpponents ? 4 : 3) }
    func resumePractice() {
        guard let raw = preferences.savedPractice, let w = CrossJSON.decode(raw), let p = try? CrossPractice.restore(w) else { return }
        play(p)
    }
    func resumeMatch() { if let raw = preferences.savedTeamMatch { _ = restoreMatch(raw) } }
    private func play(_ p: CrossPractice) { practice = p; match = nil; gamePage() }
    /// One of `ids` per place: 0 you, 1 your teammate, 2 and 3 the opponents. A character can take only one place.
    @discardableResult func choose(_ place: Int, _ id: String) -> Bool {
        guard place > 0, place < ids.count else { return false }
        if ids.enumerated().contains(where: { $0.offset != place && $0.element == id }) {
            notice = tr("Choose a different character for each place", "בחרו דמות אחרת לכל מקום")
            return false
        }
        ids[place] = id
        return true
    }
    func startTeamMatch() {
        startMatch(twoOpponents ? [ids[0], ids[2], ids[1], ids[3]] : [ids[0], ids[2], ids[1]])
    }
    private func startMatch(_ order: [String]) {
        let seats = order.enumerated().map { item -> CrossSeat in
            let c = MPRoster.find(item.element) ?? MPRoster.all[0]
            return CrossSeat(index: item.offset, kind: item.offset == 0 ? .local : .house, id: "seat\(item.offset)", name: c.name(hebrew: hebrew),
                             bot: item.offset == 0 ? nil : c.profile, characterId: item.element)
        }
        practice = nil
        match = CrossEngine(seats: seats, control: .beginner, target: 7, seed: MPClock.now,
                            teams: CrossTeams(order.indices.map { $0 == 0 || $0 == 2 ? 0 : 1 }), tapTargets: true)
        gamePage()
    }
    private func gamePage() {
        guard let engine = current else { return }
        page = .game; handled = false; matchEndingSince = nil; result = nil
        court?.setActive(false)
        let scene = CrossScene(engine: engine)
        scene.preferences = preferences
        scene.playCue = { [weak self] cue in self?.audio.play(cue.sound) }
        scene.names = engine.seats.map { $0.index == 0 ? tr("You", "אתם") : (MPRoster.find($0.characterId) ?? MPRoster.all[0]).name(hebrew: hebrew) }
        scene.fullScreen = actionCamera
        scene.practice = practice
        scene.acceptsInput = !isPaused
        scene.step = { [weak self] dt in self?.stepGame(dt) }
        scene.onFrame = { [weak self] in self?.refresh() }
        court = scene
        refresh()
        scene.setActive(foreground && !isPaused)
    }
    private func stepGame(_ dt: Double) {
        if let p = practice {
            p.start(); p.advance(dt)
            if let court {
                if court.engine !== p.engine { court.engine = p.engine }
                court.practice = p
                court.tutorialTarget = p.stage.aimed || p.stage.skill == .serve ? p.receiver : nil
            }
        } else if let e = match {
            e.advance(dt)
            for event in e.drainEvents() { if case let .rally(outcome) = event { court?.showOutcome(outcome) } }
        }
    }
    private var isPaused: Bool { practice?.paused ?? match?.paused ?? false }
    func togglePause() { pause(!isPaused) }
    func pause(_ on: Bool) {
        practice?.paused = on; match?.paused = on
        court?.acceptsInput = !on
        court?.setActive(!on && foreground)
        refresh()
    }
    func showHelp() {
        pause(true)
        help = instruction(practice?.stage ?? CrossJourney.stages[8]) + "\n\n" + CrossText.setHelp(hebrew)
    }
    func closeHelp() { help = nil; pause(false) }
    func toggleCamera() {
        actionCamera.toggle()
        notice = hebrew ? (actionCamera ? "מצלמת פעולה" : "כל השחקנים במסך") : (actionCamera ? "Action camera" : "Fit all players")
    }
    private func refresh() {
        guard page == .game, let e = current else { return }
        let p = practice
        let title = p.map { tr($0.stage.en, $0.stage.he) } ?? tr("Team match", "משחק קבוצתי")
        let score: String
        if let p {
            if p.stage.skill == .paint { score = "\(Int(p.remaining))s · \(Int(p.paint.coverage(0) * 100))% : \(Int(p.paint.coverage(1) * 100))%" }
            else if p.open { score = "★ \(p.successes)" }
            else { score = "\u{2066}\(p.successes) / \(p.goal)\u{2069} · ♥ \(3 - p.mistakes)" }
        } else { score = "\(e.referee.score(0)) : \(e.referee.score(1))" }
        let tip: String
        if p == nil, let outcome = CrossText.teamOutcome(e, local: 0, hebrew) { tip = outcome }
        else if isPaused { tip = tr("Paused", "מושהה") }
        else if e.receivingSet { tip = tr("Swipe now to smash!", "החליקו עכשיו להנחתה!") }
        else if e.referee.mayServe(0) { tip = tr("Tap the called court to serve", "הקישו על השולחן המסומן להגשה") }
        else { tip = CrossText.setTip(e, hebrew) ?? tr("Choose your target. Move your paddle to the ball.", "בחרו יעד. הזיזו את המחבט לכדור.") }
        let line = p == nil ? title + "\n" + tip : title + "\n\u{2066}" + score + "\u{2069}\n" + tip
        if hud != line { hud = line }
        if paused != isPaused { paused = isPaused }
        let now = ProcessInfo.processInfo.systemUptime
        if e.referee.winner != nil && matchEndingSince == nil { matchEndingSince = now }
        let tailSeen = e.referee.winner != nil && now - (matchEndingSince ?? now) >= 1.65
        if !handled && (p?.ended == true || tailSeen) {
            handled = true
            court?.setActive(false)
            Task { @MainActor [weak self] in self?.showResult() }
        }
    }
    private static func today() -> String {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: Date())
    }
    private func showResult() {
        let p = practice
        let win: Bool
        if let p { win = p.won }
        else if let e = match, let winner = e.referee.winner { win = e.teams?.same(winner, 0) == true }
        else { win = false }
        if let p {
            preferences.savedPractice = nil
            if win && !p.open && p.step == preferences.journeyStep {
                let receipt = "\(p.cycle)/\(p.stage.id)"
                var all = preferences.journeyReceipts
                if !all.contains(receipt) {
                    all.append(receipt)
                    let today = CrossJourneyModel.today()
                    let bonus = preferences.journeyDay == today ? 0 : 30
                    preferences.journeyReceipts = all; preferences.journeyDay = today; preferences.journeyStep = p.step + 1
                    preferences.journeyStars = preferences.journeyStars + 40 + p.cycle * 10 + bonus
                }
            }
        } else { preferences.savedTeamMatch = nil }
        var celebrate: [String] = []
        if win {
            if preferences.journeySound { audio.play(CrossCue.applause.sound) }
            if p == nil, let e = match { celebrate = e.seats.filter { e.teams?.same($0.index, 0) == true }.map { $0.characterId } }
        }
        let score: String
        if let p { score = "\(p.successes) / \(p.goal)" }
        else if let e = match { score = "\(e.referee.score(0)) : \(e.referee.score(1))" } else { score = "" }
        result = MPXJourneyResult(win: win, title: win ? tr("You won!", "ניצחתם!") : tr("Let's try again", "מנסים שוב"), score: score, celebrate: celebrate)
    }
    func resultContinue() {
        guard let r = result else { return }
        result = nil
        guard let p = practice else { teams(); return }
        if !r.win { play(CrossPractice(step: p.step, avatar: ids[0])) }
        else if lesson && p.step < 9 { startJourney(p.step + 1) }
        else if lesson { lesson = false; teams() }
        else { brief() }
    }
    func resultMenu() { result = nil; close() }

    // ---- navigation and saving -------------------------------------------------------------------------------------------
    /// Android navigateBack: a game returns to its page (team pages for team play); any other page closes the journey.
    func back() {
        if page == .game {
            let wasTeam = match != nil || lesson
            save()
            if wasTeam { teams() } else { brief() }
        } else { close() }
    }
    func close() { save(); leaveGame(); onClose() }
    func lifecycle(active: Bool) {
        foreground = active
        if !active { save(); court?.setActive(false); audio.stop() }
        else if page == .game && !isPaused && result == nil { court?.setActive(true) }
    }
    private func save() {
        if let p = practice, !p.ended { preferences.savedPractice = CrossJSON.encode(p.save()) }
        if let e = match, e.referee.winner == nil {
            preferences.savedTeamMatch = CrossJSON.encode(["ids": e.seats.map { $0.characterId }, "engine": e.exportState().wire()])
        }
    }
    private func restoreMatch(_ raw: String) -> Bool {
        guard let w = CrossJSON.decode(raw) else { return false }
        let order = CrossWire.entries(w["ids"]).compactMap { $0 as? String }
        guard order.count >= 3, let state = try? CrossState.read(MPCodec.map(w["engine"])) else { return false }
        startMatch(order)
        guard let engine = match, (try? engine.restoreState(state)) != nil else { teams(); return false }
        refresh()
        return true
    }

    // ---- settings ------------------------------------------------------------------------------------------------------------
    /// Android `adult { … }`: "8 × 7 = ?" before leaving the app.
    func grownUp(_ action: @escaping () -> Void) { gated = action; gateOpen = true }
    func answerGate(_ text: String) {
        gateOpen = false
        let action = gated
        gated = nil
        if text.trimmingCharacters(in: .whitespaces) == "56" { action?() } else { notice = tr("Try again", "נסו שוב") }
    }
    func rate() {
        // Android opens the store listing; iOS asks the App Store for its own rating prompt.
        guard let scene = UIApplication.shared.connectedScenes.compactMap({ $0 as? UIWindowScene }).first(where: { $0.activationState == .foregroundActive }) else { return }
        AppStore.requestReview(in: scene)
    }
    func share() { shareText = "https://miniklearn.com/apps/multiplayer-ping-pong/" }
    func feedback() {
        var mail = URLComponents()
        mail.scheme = "mailto"; mail.path = "appsbybros.dev@gmail.com"
        mail.queryItems = [URLQueryItem(name: "subject", value: "Multiplayer Ping Pong feedback")]
        guard let url = mail.url else { return }
        let failed = tr("No suitable app is installed", "לא מותקנת אפליקציה מתאימה")
        UIApplication.shared.open(url) { [weak self] opened in
            MainActor.assumeIsolated { if !opened { self?.notice = failed } }
        }
    }
}

/// The journey screens.
@MainActor struct MPXJourneyView: View {
    @ObservedObject var model: CrossJourneyModel
    @State private var answer = ""
    @State private var pickerPlace: Int?
    @State private var hint: String?
    private func tr(_ en: String, _ he: String) -> String { model.tr(en, he) }
    var body: some View {
        ZStack {
            MPXSunsetBackground().ignoresSafeArea()
            if model.page == .game { game } else { page }
            if let result = model.result { resultCard(result) }
            if let text = model.notice ?? hint {
                VStack { Spacer(); Text(text).font(.callout.bold()).foregroundStyle(.white).multilineTextAlignment(.center).padding(12)
                    .background(Color.black.opacity(0.75), in: Capsule()).padding(.bottom, 36) }
                    .allowsHitTesting(false)
                    .task(id: text) {
                        try? await Task.sleep(nanoseconds: 2_200_000_000)
                        if model.notice == text { model.notice = nil }
                        if hint == text { hint = nil }
                    }
            }
        }
        .foregroundStyle(MPXMenu.deepInk)
        .alert(tr("Help", "עזרה"), isPresented: Binding(get: { model.help != nil }, set: { if !$0 { model.closeHelp() } })) {
            Button(tr("Continue", "המשך")) { model.closeHelp() }
        } message: { Text(model.help ?? "") }
        .alert(tr("For grown-ups", "למבוגרים"), isPresented: $model.gateOpen) {
            TextField("8 × 7 = ?", text: $answer).keyboardType(.numberPad)
            Button(tr("Continue", "המשך")) { model.answerGate(answer); answer = "" }
            Button(tr("Cancel", "ביטול"), role: .cancel) { answer = "" }
        }
        .sheet(isPresented: Binding(get: { model.shareText != nil }, set: { if !$0 { model.shareText = nil } })) {
            MPXShareSheet(text: model.shareText ?? "")
        }
        .sheet(isPresented: Binding(get: { pickerPlace != nil }, set: { if !$0 { pickerPlace = nil } })) { characterPicker }
    }
    private var title: String {
        switch model.page {
        case .brief: return tr("Daily skill journey", "אתגר יומי")
        case .list: return tr("Your journey", "המסע שלכם")
        case .teams: return tr("Team game with house players", "משחק קבוצתי עם שחקני בית")
        case .settings: return tr("Settings", "הגדרות")
        case .game: return ""
        }
    }
    private var page: some View {
        VStack(spacing: 0) {
            ZStack {
                Text(title).font(.system(size: 21, weight: .bold)).foregroundStyle(.white).multilineTextAlignment(.center).padding(.horizontal, 58)
                HStack {
                    Button { model.back() } label: {
                        Image(systemName: MPText.rtl ? "arrow.right" : "arrow.left").font(.system(size: 27, weight: .heavy)).frame(width: 48, height: 48)
                    }.foregroundStyle(MPStyle.pink).accessibilityLabel(tr("Back", "חזרה"))
                    Spacer()
                }
            }.frame(minHeight: 60).padding(.horizontal, 8).background(MPStyle.bar, in: RoundedRectangle(cornerRadius: 15)).padding(.horizontal, 8).padding(.top, 4)
            ScrollView {
                VStack(spacing: 9) {
                    switch model.page {
                    case .brief: brief
                    case .list: list
                    case .teams: teams
                    case .settings: settings
                    case .game: EmptyView()
                    }
                }
                .padding(.horizontal, 18).padding(.top, 16).padding(.bottom, 24)
                .background(MPXMenu.panel, in: RoundedRectangle(cornerRadius: 28))
                .frame(maxWidth: 620).padding(12).frame(maxWidth: .infinity)
            }
        }
    }
    private func text(_ value: String, _ size: CGFloat = 17, bold: Bool = false) -> some View {
        Text(value).font(.system(size: size, weight: bold ? .bold : .regular)).multilineTextAlignment(.center).frame(maxWidth: .infinity).padding(.vertical, 8).padding(.horizontal, 4)
    }
    private func button(_ title: String, primary: Bool = false, fill: Color? = nil, ink: Color = MPXMenu.deepInk, _ action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title).font(.system(size: 17, weight: .semibold)).foregroundStyle(ink).multilineTextAlignment(.center)
                .frame(maxWidth: .infinity, minHeight: 52).padding(.horizontal, 12)
                .background(fill ?? (primary ? MPXMenu.gold : MPXMenu.mint), in: RoundedRectangle(cornerRadius: 20))
        }.buttonStyle(.plain).padding(.top, 9)
    }
    @ViewBuilder private var brief: some View {
        let n = model.step, s = model.stage, bot = model.briefBot
        text(tr("A little practice each day. Your first completed stage of the day earns a bonus. Play more whenever you like; missing a day never erases progress.",
                "קצת אימון בכל יום. השלב הראשון שתשלימו ביום מזכה בבונוס. אפשר להמשיך לשחק מתי שרוצים; יום ללא משחק אינו מוחק התקדמות."), 15)
        text("\u{2066}\(n % 30 + 1) / 30\u{2069} · " + tr("Cycle", "מסלול") + " \(n / 30 + 1)", 18, bold: true)
        text(tr(s.en, s.he), 24, bold: true)
        MPXPortrait(character: bot.id).frame(height: 130)
        text(bot.name(hebrew: model.hebrew), 20, bold: true)
        text(model.role(s))
        text(model.instruction(s), 17)
        text(s.skill == .paint ? tr("90 seconds · Capture more area to win", "90 שניות · כובשים יותר שטח כדי לנצח")
             : tr("Goal: \(s.goal(n / 30)) · Three misses before a retry", "מטרה: \(s.goal(n / 30)) · אחרי שלוש החטאות מנסים שוב"), 18, bold: true)
        if s.streak { text(tr("Keep a streak: a miss resets the counter.", "שומרים על רצף: החטאה מאפסת את המונה.")) }
        button(tr("Start challenge", "מתחילים באתגר"), primary: true) { model.startChallenge() }
        if model.savedPractice { button(tr("Resume practice", "המשך אימון")) { model.resumePractice() } }
        if model.savedMatch { button(tr("Resume team match", "המשך משחק קבוצתי")) { model.resumeMatch() } }
        button(tr("Your journey", "המסע שלכם")) { model.journeyList() }
        button(tr("Endless serving playground", "מגרש הגשות בלי הגבלה")) { model.endlessServes() }
        button(tr("Endless paint playground", "מגרש צבעים בלי הגבלה")) { model.endlessPaint() }
        text(tr("Practice stars", "כוכבי אימון") + ": \(model.preferences.journeyStars)", 15)
    }
    @ViewBuilder private var list: some View {
        let current = model.step % 30
        ForEach(Array(CrossJourney.stages.enumerated()), id: \.offset) { item in
            let mark: String = item.offset < current ? "✓" : (item.offset == current ? "★" : "○")
            let name: String = tr(item.element.en, item.element.he)
            text("\(mark) \(item.offset + 1). \(name)")
        }
        button(tr("Back", "חזרה")) { model.brief() }
    }
    @ViewBuilder private var teams: some View {
        text(tr("You and a chosen house teammate against one or two house opponents.", "אתם וחבר קבוצה לבחירתכם מול יריב בית אחד או שניים."))
        Toggle(isOn: $model.twoOpponents) { Text(tr("Two opponents", "שני יריבים")).font(.system(size: 18)) }.frame(minHeight: 56)
        ForEach(1...3, id: \.self) { place in
            if place < 3 || model.twoOpponents {
                let role = place == 1 ? tr("Your teammate", "חבר הקבוצה שלכם") : tr("Opponent", "יריב") + " \(place - 1)"
                let c = CrossScene.seatColors[place == 1 ? 0 : 1]
                button(role + ": " + (MPRoster.find(model.ids[place]) ?? MPRoster.all[0]).name(hebrew: model.hebrew),
                       fill: Color(red: c.0 / 255, green: c.1 / 255, blue: c.2 / 255), ink: .white) { pickerPlace = place }
            }
        }
        text(tr("One friendly pass, then send to the other team. Double-tap to set. Swipe a raised ball to smash. First team to seven points wins.",
                "מסירה קבוצתית אחת, ואז מחזירים לקבוצה השנייה. מקישים פעמיים להרמה. מחליקים דרך כדור מורם להנחתה. הקבוצה הראשונה עם שבע נקודות מנצחת."))
        button(tr("Start team match", "מתחילים במשחק קבוצתי"), primary: true) { model.startTeamMatch() }
        MPXLink(title: tr("How teams work", "איך משחקים בקבוצה")) { model.learnTeams() }.padding(.top, 12)
        MPXLink(title: tr("Online team game", "משחק קבוצתי ברשת")) { model.onlineTeams() }.padding(.top, 12)
    }
    private var characterPicker: some View {
        NavigationStack {
            ScrollView {
                LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 3), spacing: 12) {
                    ForEach(MPRoster.all) { player in
                        Button {
                            if let place = pickerPlace, model.choose(place, player.id) { pickerPlace = nil } else { pickerPlace = nil }
                        } label: {
                            VStack { MPXPortrait(character: player.id).frame(height: 96); Text(player.name(hebrew: model.hebrew)).font(.caption.bold()).foregroundStyle(MPXMenu.deepInk) }
                                .padding(6).frame(maxWidth: .infinity)
                                .background(Color(red: 0xe5 / 255, green: 0xf7 / 255, blue: 0xf1 / 255), in: RoundedRectangle(cornerRadius: 18))
                        }.buttonStyle(.plain)
                    }
                }.padding(16)
            }
            .background(Color.white)
            .navigationTitle(tr("Choose a player", "בחירת שחקן")).navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button(tr("Cancel", "ביטול")) { pickerPlace = nil } } }
        }
        .environment(\.layoutDirection, MPText.rtl ? .rightToLeft : .leftToRight)
    }
    @ViewBuilder private var settings: some View {
        Toggle(isOn: Binding(get: { model.preferences.journeySound }, set: { model.preferences.journeySound = $0; model.objectWillChange.send() })) {
            Text(tr("Game sounds", "צלילי המשחק")).font(.system(size: 18))
        }.frame(minHeight: 56)
        text(tr("Paddle swings, ball contacts and celebrations in team games and daily practice.", "הנפות מחבט, פגיעות בכדור וחגיגות במשחקי קבוצה ובאימון היומי."), 14)
        Toggle(isOn: Binding(get: { model.preferences.menuMusic }, set: { model.preferences.menuMusic = $0; model.objectWillChange.send() })) {
            Text(tr("Menu music", "מוזיקה בתפריט")).font(.system(size: 17))
        }.frame(minHeight: 56)
        MPXReceptionSettings(preferences: model.preferences, hebrew: model.hebrew)
        button(tr("Rate this app", "דירוג האפליקציה")) { model.grownUp { model.rate() } }
        button(tr("Share this app", "שיתוף האפליקציה")) { model.grownUp { model.share() } }
        button(tr("Send feedback", "שליחת משוב")) { model.grownUp { model.feedback() } }
    }
    private var game: some View {
        MPXMatchLayout(tools: 4) {
            MPXTool(symbol: MPText.rtl ? "arrow.right" : "arrow.left", label: tr("Back", "חזרה"), fill: MPXMenu.mint, tint: MPXMenu.deepInk) { model.back() }
            MPXTool(symbol: model.paused ? "play.fill" : "pause.fill", label: model.paused ? tr("Continue", "המשך") : tr("Pause", "השהיה"), fill: MPXMenu.mint, tint: MPXMenu.deepInk) { model.togglePause() }
            MPXTool(symbol: "questionmark", label: tr("Help", "עזרה"), fill: MPXMenu.mint, tint: MPXMenu.deepInk) { model.showHelp() }
            MPXTool(symbol: "camera.viewfinder", label: tr("Switch camera view", "החלפת תצוגת מצלמה"), fill: MPXMenu.mint, tint: MPXMenu.deepInk) { model.toggleCamera() }
        } status: { wide in
            Text(model.hud).font(.system(size: 16, weight: .bold)).foregroundStyle(.white).multilineTextAlignment(.center).lineLimit(wide ? 12 : 4)
                .frame(maxWidth: .infinity).padding(.horizontal, 8).padding(.vertical, 6).background(MPXMenu.hud, in: RoundedRectangle(cornerRadius: 14))
                .padding(.horizontal, 4).accessibilityAddTraits(.updatesFrequently)
        } court: {
            if let court = model.court {
                MPXCourt(scene: court, label: tr("Three or four player table tennis court. Your arm of the table is at the bottom. Send the ball to any other player.", "מגרש טניס שולחן לשלושה או ארבעה שחקנים. הזרוע שלכם בשולחן נמצאת למטה. שלחו את הכדור לכל שחקן אחר."))
                    .background(GeometryReader { geo in Color.clear.task(id: ObjectIdentifier(court)) {
                        // FamilyLandscapeHint: a portrait court suggests landscape once.
                        try? await Task.sleep(nanoseconds: 900_000_000)
                        if geo.size.height > geo.size.width { hint = FamilyMessages.text("For a wider view, play in landscape.", "לתצוגה רחבה יותר, שחקו במצב אופקי.") }
                    } })
            }
        }
    }
    private func resultCard(_ result: MPXJourneyResult) -> some View {
        ZStack {
            Color.black.opacity(0.18).ignoresSafeArea()
            VStack(spacing: 10) {
                if !result.celebrate.isEmpty { MPXTeamVictory(characters: result.celebrate).frame(height: 210) }
                Text(result.title).font(.system(size: 24, weight: .bold)).multilineTextAlignment(.center)
                Text(result.score).font(.system(size: 22, weight: .bold)).environment(\.layoutDirection, .leftToRight)
                button(result.win ? tr("Continue", "המשך") : tr("Try again", "מנסים שוב"), primary: true) { model.resultContinue() }
                button(tr("Back to menu", "חזרה לתפריט")) { model.resultMenu() }
            }
            .padding(.horizontal, 22).padding(.vertical, 16)
            .background(MPXMenu.panel, in: RoundedRectangle(cornerRadius: 24))
            .frame(maxWidth: 480).padding(20)
        }
    }
}
