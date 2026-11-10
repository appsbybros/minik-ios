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
    /// Android 47ad0c9: the menu music plays on the journey's pages and pauses for its games (MPController.syncMusic).
    @Published private(set) var page: Page = .brief { didSet { if page != oldValue { musicChanged?() } } }
    var musicChanged: (() -> Void)?
    @Published private(set) var court: CrossScene?
    @Published private(set) var hud = ""
    /// The HUD's parts (Android 1fc4bc2 / dd94c09 CrossJourneyActivity.refresh): the title and (practice) the controls and score
    /// lines are centred; the tip below them follows the reading direction's start edge.
    @Published private(set) var hudTitle = ""
    @Published private(set) var hudScore: String?
    @Published private(set) var hudTip = ""
    @Published private(set) var paused = false
    @Published var result: MPXJourneyResult?
    /// Android 1fc4bc2: switching between one and two opponents remembers the lineup of the old size and restores the new one's.
    @Published var twoOpponents: Bool {
        didSet { if twoOpponents != oldValue { rememberTeamRoster(twoOpponents: oldValue); restoreTeamRoster() } }
    }
    @Published var ids: [String]
    /// A short message (Android Toast).
    @Published var notice: String?
    @Published var help: String?
    /// The help card's title: the current stage (Android 7254ab2 guideDialog).
    @Published private(set) var helpTitle = ""
    @Published var gateOpen = false
    @Published var shareText: String?
    /// Android `cross/close_camera` (a9140c3), shared with the other cross courts; off by default.
    @Published var actionCamera: Bool { didSet { preferences.crossCloseCamera = actionCamera; court?.fullScreen = actionCamera } }
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
        actionCamera = preferences.crossCloseCamera
        restoreTeamRoster()
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

    /// Android 7254ab2: a serving stage is titled by its task, "Serve to the marked court".
    func stageTitle(_ s: CrossStage) -> String { s.skill == .serve ? MPText.issue("Serve to the marked court") : tr(s.en, s.he) }
    /// Android c93e760 `controls()`: the journey always plays at Beginner ("Controls: Beginner"), on the brief, the HUD and Help.
    func controls() -> String { tr("Controls: ", "רמת השליטה: ") + MPControlChoice.title(CrossControl.beginner.choice, hebrew: hebrew) }
    /// Android c93e760: the instructions describe the assisted practice gestures (CrossPracticeGuide); the partner/opponent
    /// line of the brief (`role`) is gone.
    func instruction(_ s: CrossStage) -> String { CrossPracticeGuide.instruction(s, hebrew) }
    /// Android d376d64 MatchSceneLayout(fixedPortraitStatusLines): in portrait the HUD keeps three lines (team match) or four
    /// (practice), so a changing hint never resizes and shifts the table.
    var hudLines: Int { practice == nil ? 3 : 4 }

    // ---- practice and team match -----------------------------------------------------------------------------------------
    func startJourney(_ step: Int) { play(CrossPractice(step: step, avatar: ids[0])) }
    func startChallenge() { lesson = false; startJourney(step) }
    /// Android 7254ab2: one endless playground, for the current stage (serving, paint, or practice without a limit).
    func endless() { play(CrossPractice(step: step, avatar: ids[0], open: true)) }
    var endlessTitle: String {
        switch stage.skill {
        case .serve: return tr("Endless serving playground", "מגרש הגשות בלי הגבלה")
        case .paint: return tr("Endless paint playground", "מגרש צבעים בלי הגבלה")
        default: return MPText.issue("Practice without a limit")
        }
    }
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
        rememberTeamRoster()
        return true
    }
    /// Android 1fc4bc2 CrossJourneyActivity.restoreTeamRoster: the teammate and opponents saved for this size (`teamRoster4` with
    /// two opponents, `teamRoster3` with one), known characters only, then the roster order; never the player's own character;
    /// each once; three places.
    func restoreTeamRoster() {
        let avatar = ids[0]
        let saved = preferences.teamRoster(twoOpponents ? 4 : 3).split(separator: ",", omittingEmptySubsequences: false).compactMap { MPRoster.find(String($0))?.id }
        var candidates: [String] = []
        for id in saved + MPRoster.all.map({ $0.id }) where id != avatar && !candidates.contains(id) { candidates.append(id) }
        ids = [avatar] + candidates.prefix(3)
    }
    /// Android 1fc4bc2 rememberTeamRoster: places 1–3 (teammate, first and second opponent), for the current size.
    func rememberTeamRoster(twoOpponents two: Bool? = nil) {
        preferences.setTeamRoster((two ?? twoOpponents) ? 4 : 3, ids.dropFirst().joined(separator: ","))
    }
    /// `seed` and `firstServer` are for App Store captures only (MPStoreScreenshot); players get a fresh seed and serve first.
    /// Android 1fc4bc2 "Start team match" first remembers the lineup.
    func startTeamMatch(seed: Int64? = nil, firstServer: Int = 0) {
        rememberTeamRoster()
        startMatch(twoOpponents ? [ids[0], ids[2], ids[1], ids[3]] : [ids[0], ids[2], ids[1]], seed: seed, firstServer: firstServer)
    }
    private func startMatch(_ order: [String], seed: Int64? = nil, firstServer: Int = 0) {
        let seats = order.enumerated().map { item -> CrossSeat in
            let c = MPRoster.find(item.element) ?? MPRoster.all[0]
            return CrossSeat(index: item.offset, kind: item.offset == 0 ? .local : .house, id: "seat\(item.offset)", name: c.name(hebrew: hebrew),
                             bot: item.offset == 0 ? nil : c.profile, characterId: item.element)
        }
        practice = nil
        match = CrossEngine(seats: seats, control: .beginner, target: 7, seed: seed ?? MPClock.now, firstServer: firstServer,
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
    /// Android 7254ab2: the help card names the stage and explains only it. Android 47ad0c9: it has only its close (X) control.
    /// Android c93e760: the controls line comes first.
    func showHelp() {
        pause(true)
        let stage = practice?.stage ?? CrossJourney.stages[8]
        helpTitle = stageTitle(stage)
        help = controls() + "\n\n" + instruction(stage)
    }
    func closeHelp() { help = nil; pause(false) }
    /// Android 47ad0c9 CrossCourt.toggleCamera: no toast any more.
    func toggleCamera() { actionCamera.toggle() }
    private func refresh() {
        guard page == .game, let e = current else { return }
        let p = practice
        let title = p.map { stageTitle($0.stage) } ?? tr("Team match", "משחק קבוצתי")
        let score: String
        if let p {
            // The endless paint playground has no clock (Android 7254ab2). Android 651245f: the fraction never breaks (no-break spaces).
            if p.stage.skill == .paint { score = (p.open ? "" : "\(Int(p.remaining))s · ") + "\(Int(p.paint.coverage(0) * 100))% : \(Int(p.paint.coverage(1) * 100))%" }
            else if p.open { score = "★ \(p.successes)" }
            else { score = "\u{2066}\(p.successes)\u{00a0}/\u{00a0}\(p.goal)\u{2069} · ♥ \(3 - p.mistakes)" }
        } else { score = "\(e.referee.score(0)) : \(e.referee.score(1))" }
        let tip: String
        if p == nil, let outcome = CrossText.teamOutcome(e, local: 0, hebrew) { tip = outcome }
        else if isPaused { tip = tr("Paused", "מושהה") }
        // Serving practice keeps serving guidance after the serve (Android 7254ab2; d376d64 "the highlighted side").
        else if p?.stage.skill == .serve { tip = MPText.issue(e.referee.mayServe(0) ? "Tap the highlighted side to serve" : "Watch where your serve lands") }
        // Android 971e958: wait for the teammate's high pass to bounce, then swipe up through it.
        else if e.receivingSet { tip = CrossText.receivingSetTip(e, hebrew) }
        // Android d376d64: R.string.tap_opponent_side_to_serve.
        else if e.referee.mayServe(0) { tip = MPText.issue("Tap an opponent’s side to serve") }
        // Android c93e760: a practice explains its own gesture (tap the gold target first in an aiming lesson).
        else if let p { tip = CrossPracticeGuide.tip(p, hebrew) }
        else { tip = CrossText.setTip(e, hebrew) ?? tr("Choose your target. Move your paddle to the ball.", "בחרו יעד. הזיזו את המחבט לכדור.") }
        // Android c93e760: a practice's second line names its controls before the score.
        let middle: String? = p == nil ? nil : controls() + " · \u{2066}" + score + "\u{2069}"
        let line = middle.map { title + "\n" + $0 + "\n" + tip } ?? title + "\n" + tip
        if hud != line {
            hud = line
            if hudTitle != title { hudTitle = title }
            if hudScore != middle { hudScore = middle }
            if hudTip != tip { hudTip = tip }
        }
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
        // Android c93e760 / 651245f: an isolated fraction with no-break spaces.
        if let p { score = "\u{2066}\(p.successes)\u{00a0}/\u{00a0}\(p.goal)\u{2069}" }
        else if let e = match { score = "\(e.referee.score(0)) : \(e.referee.score(1))" } else { score = "" }
        let title = win && p != nil ? MPText.issue("Challenge completed!") : (win ? tr("You won!", "ניצחתם!") : tr("Let's try again", "מנסים שוב"))
        result = MPXJourneyResult(win: win, title: title, score: score, celebrate: celebrate)
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
    /// Android navigateBack: a game returns to its page (team pages for team play); the journey map returns to the Daily brief
    /// (7254ab2); any other page closes the journey.
    func back() {
        if page == .game {
            let wasTeam = match != nil || lesson
            save()
            if wasTeam { teams() } else { brief() }
        } else if page == .list { brief() } else { close() }
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
    /// Android 47ad0c9 `adult { … }` (FamilyAdultGate): the shared, randomized grown-up question before leaving the app, as in
    /// the other Minik apps (ParentalGateView), instead of the fixed "8 × 7 = ?".
    func grownUp(_ action: @escaping () -> Void) { gated = action; gateOpen = true }
    func gateUnlocked() {
        let action = gated
        gated = nil
        gateOpen = false
        // The sheet closes first; the action may present another sheet (share) or leave the app.
        Task { @MainActor in try? await Task.sleep(nanoseconds: 400_000_000); action?() }
    }
    func gateCancelled() { gateOpen = false; gated = nil }
    /// Android 47ad0c9 ModernAudio: turning "Game sounds" off stops the cue that is playing.
    func setGameSounds(_ on: Bool) {
        preferences.journeySound = on
        if !on { audio.stopEffects() }
        objectWillChange.send()
    }
    /// Android PongMenuMusic (47ad0c9): turning the menu music off pauses it at once.
    func setMenuMusic(_ on: Bool) {
        preferences.menuMusic = on
        objectWillChange.send()
        musicChanged?()
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
        // Android 47ad0c9: the stage help has only its close (X) control.
        .overlay { if let help = model.help { MPXGuideCard(title: model.helpTitle, message: help) { model.closeHelp() } } }
        .sheet(isPresented: Binding(get: { model.gateOpen }, set: { if !$0 { model.gateCancelled() } })) {
            ParentalGateView(onCancel: { model.gateCancelled() }, onUnlock: { model.gateUnlocked() }).preferredColorScheme(.light)
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
    /// Android 7254ab2 journey colours: Start green, Your journey blue, the endless playground yellow, Back to menu pink.
    static let green = Color(red: 0x8b / 255, green: 0xd4 / 255, blue: 0xae / 255)
    static let blue = Color(red: 0xb8 / 255, green: 0xd9 / 255, blue: 1)
    static let yellow = Color(red: 1, green: 0xdc / 255, blue: 0x70 / 255)
    /// Headings stay centred; paragraphs follow the reading direction's start edge (Android 7254ab2).
    private func text(_ value: String, _ size: CGFloat = 17, bold: Bool = false, center: Bool? = nil) -> some View {
        let centred = center ?? bold
        return Text(value).font(.system(size: size, weight: bold ? .bold : .regular)).multilineTextAlignment(centred ? .center : .leading)
            .frame(maxWidth: .infinity, alignment: centred ? .center : .leading).padding(.vertical, 8).padding(.horizontal, 4)
    }
    private func button(_ title: String, primary: Bool = false, fill: Color? = nil, ink: Color = MPXMenu.deepInk, _ action: @escaping () -> Void) -> some View {
        Button(action: action) {
            // Android 6fcb446 PongButton: word labels one size larger (17 → 18).
            Text(title).font(.system(size: 18, weight: .semibold)).foregroundStyle(ink).multilineTextAlignment(.center)
                .frame(maxWidth: .infinity, minHeight: 52).padding(.horizontal, 12)
                // Android 47ad0c9 PongButton: green and mint actions have the #58BD8C face.
                .background(fill.map { $0 == MPXJourneyView.green || $0 == MPXMenu.mint ? MPStyle.green : $0 } ?? MPStyle.green, in: RoundedRectangle(cornerRadius: 20))
        // Android e7f3f27: PongSpacing.ACTION_TOP_DP (16) above every action, on every screen size (was 9).
        }.buttonStyle(.plain).padding(.top, MPSpacing.actionTop)
    }
    @ViewBuilder private var brief: some View {
        let n = model.step, s = model.stage, bot = model.briefBot
        text(tr("A little practice each day. Your first completed stage of the day earns a bonus. Play more whenever you like; missing a day never erases progress.",
                "קצת אימון בכל יום. השלב הראשון שתשלימו ביום מזכה בבונוס. אפשר להמשיך לשחק מתי שרוצים; יום ללא משחק אינו מוחק התקדמות."), 15)
        text("\u{2066}\(n % 30 + 1) / 30\u{2069} · " + tr("Cycle", "מסלול") + " \(n / 30 + 1)", 18, bold: true)
        text(model.stageTitle(s), 24, bold: true)
        MPXPortrait(character: bot.id).frame(height: 130)
        text(bot.name(hebrew: model.hebrew), 20, bold: true)
        // Android c93e760: the controls line replaces the partner/opponent line.
        text(model.controls(), 16, bold: true)
        text(model.instruction(s), 17)
        text(s.skill == .paint ? tr("90 seconds · Capture more area to win", "90 שניות · כובשים יותר שטח כדי לנצח")
             : tr("Goal: \(s.goal(n / 30)) · Three misses before a retry", "מטרה: \(s.goal(n / 30)) · אחרי שלוש החטאות מנסים שוב"), 18, bold: true)
        if s.streak { text(tr("Keep a streak: a miss resets the counter.", "שומרים על רצף: החטאה מאפסת את המונה.")) }
        button(tr("Start challenge", "מתחילים באתגר"), primary: true) { model.startChallenge() }
        // Android 7254ab2: the team match resumes from the team page; one endless playground for the current stage.
        if model.savedPractice { button(tr("Resume practice", "המשך אימון"), primary: true) { model.resumePractice() } }
        button(tr("Your journey", "המסע שלכם"), fill: MPXJourneyView.blue) { model.journeyList() }
        button(model.endlessTitle, fill: MPXJourneyView.yellow) { model.endless() }
        Text(tr("Practice stars", "כוכבי אימון") + ": \(model.preferences.journeyStars)").font(.system(size: 16)).multilineTextAlignment(.center)
            .frame(maxWidth: .infinity, minHeight: 56).padding(.top, 12)
    }
    @ViewBuilder private var list: some View {
        let current = model.step % 30
        ForEach(Array(CrossJourney.stages.enumerated()), id: \.offset) { item in
            let mark: String = item.offset < current ? "✓" : (item.offset == current ? "★" : "○")
            let name: String = tr(item.element.en, item.element.he)
            text("\(mark) \(item.offset + 1). \(name)")
        }
        // Android 7254ab2: no bottom Back; the header arrow returns to the Daily brief.
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
        if model.savedMatch { button(tr("Resume team match", "המשך משחק קבוצתי")) { model.resumeMatch() } }
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
        Toggle(isOn: Binding(get: { model.preferences.journeySound }, set: { model.setGameSounds($0) })) {
            Text(tr("Game sounds", "צלילי המשחק")).font(.system(size: 18))
        }.frame(minHeight: 56)
        text(tr("Paddle swings, ball contacts and celebrations in team games and daily practice.", "הנפות מחבט, פגיעות בכדור וחגיגות במשחקי קבוצה ובאימון היומי."), 14)
        Toggle(isOn: Binding(get: { model.preferences.menuMusic }, set: { model.setMenuMusic($0) })) {
            Text(tr("Menu music", "מוזיקה בתפריט")).font(.system(size: 17))
        }.frame(minHeight: 56)
        MPXReceptionSettings(preferences: model.preferences, hebrew: model.hebrew)
        // Android 7254ab2: pink, yellow and orange actions.
        button(tr("Rate this app", "דירוג האפליקציה"), fill: Color(red: 1, green: 0x5b / 255, blue: 0xa6 / 255)) { model.grownUp { model.rate() } }
        button(tr("Share this app", "שיתוף האפליקציה"), fill: MPXJourneyView.yellow) { model.grownUp { model.share() } }
        button(tr("Send feedback", "שליחת משוב"), fill: Color(red: 1, green: 0xb9 / 255, blue: 0x6e / 255)) { model.grownUp { model.feedback() } }
    }
    private var game: some View {
        MPXMatchLayout(tools: 4) {
            MPXTool(symbol: MPText.rtl ? "arrow.right" : "arrow.left", label: tr("Back", "חזרה"), fill: MPXMenu.mint, tint: MPXMenu.deepInk) { model.back() }
            MPXTool(symbol: model.paused ? "play.fill" : "pause.fill", label: model.paused ? tr("Continue", "המשך") : tr("Pause", "השהיה"), fill: MPXMenu.mint, tint: MPXMenu.deepInk) { model.togglePause() }
            MPXTool(symbol: "questionmark", label: tr("Help", "עזרה"), fill: MPXMenu.mint, tint: MPXMenu.deepInk) { model.showHelp() }
            MPXTool(symbol: "camera.viewfinder", label: tr("Switch camera view", "החלפת תצוגת מצלמה"), fill: MPXMenu.mint, tint: MPXMenu.deepInk) { model.toggleCamera() }
        } status: { wide in
            hudView(wide: wide)
        } court: {
            if let court = model.court {
                MPXCourt(scene: court, label: tr("Three or four player table tennis court. Your arm of the table is at the bottom. Send the ball to any other player.", "מגרש טניס שולחן לשלושה או ארבעה שחקנים. הזרוע שלכם בשולחן נמצאת למטה. שלחו את הכדור לכל שחקן אחר."))
                    // Android PongOrientationHint (7254ab2).
                    .background(MPXLandscapeTipProbe(id: ObjectIdentifier(court), active: { true }) { hint = $0 })
            }
        }
    }
    /// Android CrossJourneyActivity hud (1fc4bc2, d376d64, dd94c09): white 16 pt bold text on its dark rounded panel. The title and
    /// the controls/score line are centred, the tip follows the start edge; in portrait the panel is exactly `hudLines` lines tall
    /// (Android fixedPortraitStatusLines: min = max lines), in landscape at most 12 lines. A team match draws its title 4 pt higher
    /// (a draw-only shift: the line metrics, the hint's wrapping and the court do not move).
    private func hudView(wide: Bool) -> some View {
        let lineHeight = UIFont.systemFont(ofSize: 16, weight: .bold).lineHeight
        let fixed = CGFloat(model.hudLines) * lineHeight
        let head = model.hudScore == nil ? 1 : 2
        return VStack(spacing: 0) {
            Text(model.hudTitle).multilineTextAlignment(.center).frame(maxWidth: .infinity)
                .offset(y: model.hudScore == nil ? -4 : 0)
            if let score = model.hudScore { Text(score).multilineTextAlignment(.center).frame(maxWidth: .infinity) }
            Text(model.hudTip).multilineTextAlignment(.leading).lineLimit(max(1, (wide ? 12 : model.hudLines) - head))
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .font(.system(size: 16, weight: .bold)).foregroundStyle(.white)
        .frame(maxWidth: .infinity, minHeight: wide ? nil : fixed, maxHeight: wide ? nil : fixed)
        // Like Android's TextView, the lines may draw into the panel's padding (the raised title) but not beyond it.
        .padding(.horizontal, 8).padding(.vertical, 6).clipped().background(MPXMenu.hud, in: RoundedRectangle(cornerRadius: 14))
        .padding(.horizontal, 4)
        .accessibilityElement(children: .combine).accessibilityAddTraits(.updatesFrequently)
    }
    /// Android 7254ab2: a rounded, bounded card that scrolls when it does not fit; Back to menu is pink with white text.
    private func resultCard(_ result: MPXJourneyResult) -> some View {
        let card = VStack(spacing: 10) {
            if !result.celebrate.isEmpty { MPXTeamVictory(characters: result.celebrate).frame(height: 210) }
            Text(result.title).font(.system(size: 24, weight: .bold)).multilineTextAlignment(.center)
            Text(result.score).font(.system(size: 22, weight: .bold)).environment(\.layoutDirection, .leftToRight)
            button(result.win ? tr("Continue", "המשך") : tr("Try again", "מנסים שוב"), primary: true) { model.resultContinue() }
            button(tr("Back to menu", "חזרה לתפריט"), fill: MPXMenu.pink, ink: .white) { model.resultMenu() }
        }
        .padding(.horizontal, 22).padding(.vertical, 16)
        return ZStack {
            Color.black.opacity(0.18).ignoresSafeArea()
            ViewThatFits(in: .vertical) {
                card
                ScrollView { card }
            }
            .background(MPXMenu.panel, in: RoundedRectangle(cornerRadius: 24))
            .clipShape(RoundedRectangle(cornerRadius: 24))
            .frame(maxWidth: 520).padding(16)
        }
    }
}
