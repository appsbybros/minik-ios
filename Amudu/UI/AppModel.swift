import SwiftUI
import UIKit
import StoreKit

/// One player line of the private-room lobby (Android `lobby()` since 2026-11: a portrait, the name, and either the
/// house player's quality stars or the human's shared points and readiness).
struct LobbyPlayer: Identifiable {
    let id: String
    let character: String
    let title: String
    let bot: Bool
    /// House players: accuracy, power, speed, catch and jump.
    let qualities: [Int]
    /// Humans: "Points: N · colour" or "Progress not shared".
    let progress: String
    /// Other humans: "Ready ✓" or "Waiting for Ready"; empty for the player and house players.
    let readiness: String
}

struct LobbyState {
    let code: String
    let players: [LobbyPlayer]
    let host: Bool
    /// Android `uid in ready`.
    let ready: Bool
    /// Android `players.size >= 2`: the host's Start is enabled.
    let canStart: Bool
    /// The humans who have not confirmed (the host's Start asks before starting without them).
    let unready: [String]
    /// Android "{0} players here · {1} free places. At least 2 players are required to start a game."
    let capacityNote: String
    /// Android `lobby(..., gameConfig)`: the room's rule set is shown under the code.
    let mode: String?
    let onReady: @MainActor () -> Void
    let onStart: @MainActor () -> Void
}

struct ResultRow: Identifiable {
    let id: String
    let character: String
    let name: String
    let score: String
    let winner: Bool
}

struct HuddleProposal: Identifiable, Equatable {
    let id: String
    let name: String
    let votes: Int
    /// Android `votes[localId] == id`: the player's own vote is marked " ✓".
    let mine: Bool
}

/// Android `showHuddle()` (2026-11): who is being named, their current nickname, the countdown and the proposals.
struct HuddleState: Equatable {
    var serial: Int
    var naming: String
    var current: String?
    var suffixes: [String]
    var seconds: Int
    var proposals: [HuddleProposal]
}

/// Android `showScores()`: one row per player, fewest penalties first.
struct StatusRow: Identifiable, Equatable {
    let id: String
    let character: String
    let name: String
    let score: String
}

/// Android `showReturnVote()`.
struct ReturnVoteState: Equatable {
    let title: String
    var seconds: Int
    let canVote: Bool
    var voted: Bool
}

/// Android `journeyResult()`.
struct JourneyOutcome {
    let won: Bool
    let stage: SpudStage
    let successes: Int
    let goal: Int
    let gained: Int
    let next: Int
    /// Android `won && next == old`: a replay of a completed challenge ("Replay complete · your progress is unchanged.").
    let replay: Bool
}

/// Android `journeyResult()` of a settings lesson (`config.practiceLesson` set): no points, repeat or return.
struct LessonOutcome {
    let won: Bool
    let topic: String
    let step: Int
    let mode: ThrowMode
    let ball: BallKind
    let conditions: PracticeConditions
    let ground: Bool
}

/// The text handed to the system share sheet (Android `Intent.createChooser`).
struct ShareText: Identifiable {
    let id = UUID()
    let text: String
}

/// Android `AmuduActivity`: screens, saved settings, the local/online game lifecycle, the daily skill journey and the
/// settings lessons, colour ranks, private family leagues, dialogs, sounds and speech. Ads, purchases and code
/// redemption are not part of the iOS app; the family "More Minik apps & games" card is (the shared Family module),
/// without its ad-break promotion and reminder.
@MainActor final class AppModel: ObservableObject {
    enum Screen: Equatable {
        case home
        case setup
        case help
        case connecting
        case lobby
        case game
        case result
        case journey
        case journeyResult
        case lessonHub
        case lesson
        case lessonResult
        case support
        case rank
        case privacy
        case league
    }

    /// UserDefaults keys: the Android preference names with the `amudu.` prefix of this app.
    private enum Keys {
        static let avatar = "amudu.avatar"
        static let name = "amudu.name"
        static let scene = "amudu.scene"
        static let ball = "amudu.ball"
        static let freeze = "amudu.freeze"
        static let count = "amudu.count"
        static let turns = "amudu.turns"
        static let house = "amudu.house"
        static let daylight = "amudu.daylight"
        static let throwMode = "amudu.throwMode"
        static let allowGroundHit = "amudu.allowGroundHit"
        static let wind = "amudu.wind"
        static let room = "amudu.room"
        static let saved = "amudu.saved"
        static let savedOwn = "amudu.savedOwn"
        static let savedLeague = "amudu.savedLeague"
        static let ruleSet = "amudu.ruleSet"
        static let colourPoints = "amudu.colourPoints"
        static let rankReceipts = "amudu.rankReceipts"
        static let skillJourney = "amudu.skillJourney"
        static let practiceSaved = "amudu.practiceSaved"
        static let journeyControl = "amudu.journeyControl"
        static let journeyBall = "amudu.journeyBall"
        static let receptionZoomOwn = "amudu.receptionZoomOwn"
        static let receptionZoomOthers = "amudu.receptionZoomOthers"
        static let gameSounds = "amudu.gameSounds"
        static let battleOrientation = "amudu.battleOrientation"
        /// Android `family_menu_sections` preferences: one open/closed flag per home section title.
        static let menuSection = "amudu.menuSection."

        static func ruleConfig(_ r: RuleSet) -> String { return "amudu.ruleConfig_" + r.rawValue }
        static func ruleHouse(_ r: RuleSet) -> String { return "amudu.ruleHouse_" + r.rawValue }
    }

    static let turnChoices = [10, 20, 35, 50, 0]
    static let secondsChoices = [20, 30, 45, 60, 0]
    /// The public page of the game (Android shares its Play listing; the iOS listing has no link yet).
    static let storeLink = "https://miniklearn.com/apps/amodu/"

    @Published var screen: Screen = .home {
        didSet {
            // Android `page()` asks for portrait; the result page keeps the game's orientation.
            if screen != .game && screen != .result { ScreenOrientation.apply(ScreenOrientation.page) }
        }
    }
    @Published var toast: String?
    @Published private(set) var avatar: String
    @Published private(set) var playerName: String
    @Published var scene: ArenaScene
    @Published var ball: BallKind
    @Published var freeze: FreezeRule
    @Published var count: Int
    @Published var turns: Int
    @Published var daylight: Daylight
    @Published var throwMode: ThrowMode
    @Published var allowGroundHit: Bool
    @Published var nicknameAnswer: NicknameAnswer = .choices
    @Published var wind: Wind
    @Published var rules: RuleSet
    @Published var requireCall = false
    @Published var stepsAfterCall = 0
    @Published var actionSeconds = 30
    @Published private(set) var house: [String]
    /// Android `setupPurpose`: 0 a game, 1 creating a family league, 2 opening a league round.
    @Published private(set) var setupPurpose = 0
    @Published var environmentOpen = false
    @Published var advancedOpen = false
    @Published var connectingInfo = ""
    /// Where the connecting page's back arrow leads (Android: home, or the league for a league round).
    @Published private(set) var connectingLeague = false
    @Published private(set) var lobbyState: LobbyState?
    /// Android `button(Ready).setOnClickListener { isEnabled = false; onReady() }` until the lobby is rebuilt.
    @Published var lobbyReadyPressed = false
    @Published private(set) var results: [ResultRow] = []
    @Published private(set) var resultHeading = ""
    @Published private(set) var resultTitle = ""
    @Published private(set) var resultLeague = false
    @Published private(set) var pauseVisible = false
    @Published private(set) var huddle: HuddleState?
    @Published var huddleInput = ""
    @Published private(set) var statusRows: [StatusRow]?
    @Published private(set) var statusExplanation = ""
    @Published private(set) var returnVote: ReturnVoteState?
    @Published private(set) var savedRoom: String?
    @Published private(set) var hasSavedGame = false
    @Published private(set) var hasPracticeSaved = false
    @Published private(set) var gameView: ArenaView?
    @Published private(set) var sceneLoading = false
    @Published private(set) var rankPoints = 0
    @Published private(set) var journeyStep = 0
    @Published private(set) var journeyOutcome: JourneyOutcome?
    @Published private(set) var lessonTopic = ""
    @Published private(set) var lessonOutcome: LessonOutcome?
    @Published private(set) var sections: [String: Bool] = [:]
    /// The SPUD dialogs (Android `GameDialogBuilder`), the newest last.
    @Published private(set) var dialogs: [SpudDialogRequest] = []
    @Published private(set) var dialogInput = ""
    @Published private(set) var gateVisible = false
    @Published var gateInput = ""
    @Published private(set) var gateQuestion = ""
    @Published private(set) var gateError = false
    @Published var shareSheet: ShareText?
    /// Android `speechReady` (and `view.speechAvailable`): a voice exists for the app language.
    @Published private(set) var speechReady: Bool
    /// Changes when the lag diagnosis starts or stops, so Settings & feedback redraws its button.
    @Published private(set) var lagTick = 0
    @Published var receptionZoomOwn: Bool {
        didSet { defaults.set(receptionZoomOwn, forKey: Keys.receptionZoomOwn) }
    }
    @Published var receptionZoomOthers: Bool {
        didSet { defaults.set(receptionZoomOthers, forKey: Keys.receptionZoomOthers) }
    }
    @Published var gameSounds: Bool {
        didSet { defaults.set(gameSounds, forKey: Keys.gameSounds) }
    }

    let art: ArtStore
    let audio: GameAudio
    private let stopCalls: HebrewStopCalls
    private(set) var online: OnlineRoom?
    private(set) var league: FamilyLeague?
    private let defaults: UserDefaults
    private var localId = "p0"
    private var huddleTimer: Timer?
    private var dialogTimer: Timer?
    private var toastToken = 0
    private var isForeground = true
    private var gateAnswer = 0
    private var gatePrevious = -1
    private var gateAction: (@MainActor () -> Void)?
    /// Android `activeLeagueRound` / `localLeagueId`.
    private var activeLeagueRound = false
    private var localLeagueId = ""
    /// Android `dismissedHuddle`: the huddle the player closed is not reopened.
    private var dismissedHuddle = -1
    private var pauseDialogID: UUID?
    private var lobbyWaitDialogID: UUID?
    private var nicknameWordsID: UUID?

    var hebrew: Bool { return AppText.language == "he" }

    init() {
        art = ArtStore()
        audio = GameAudio()
        stopCalls = HebrewStopCalls()
        let d = UserDefaults.standard
        defaults = d
        // Android `FamilyButtonAlignment.useFullRaisedFace(true)`: SPUD centres button lettering on the whole raised face.
        FamilyKit.Lettering.fullRaisedFace = true
        let storedAvatar = d.string(forKey: Keys.avatar) ?? "miniko"
        avatar = AmuduCharacters.exists(storedAvatar) ? storedAvatar : "miniko"
        playerName = d.string(forKey: Keys.name) ?? ""
        scene = ArenaScene(rawValue: d.string(forKey: Keys.scene) ?? "PARK") ?? .park
        ball = BallKind(rawValue: d.string(forKey: Keys.ball) ?? "FOAM") ?? .foam
        // Android (2026-11): the honor rule is no longer offered; every game freezes in place.
        freeze = .freeze
        let storedCount = (d.object(forKey: Keys.count) as? Int) ?? 6
        count = min(max(storedCount, 2), 10)
        let storedTurns = (d.object(forKey: Keys.turns) as? Int) ?? 0
        turns = [0, 10, 20, 35, 50].contains(storedTurns) ? storedTurns : 0
        daylight = Daylight(rawValue: d.string(forKey: Keys.daylight) ?? "NOON") ?? .noon
        throwMode = ThrowMode(rawValue: d.string(forKey: Keys.throwMode) ?? "EASY") ?? .easy
        wind = Wind(rawValue: d.string(forKey: Keys.wind) ?? "SLOW") ?? .slow
        allowGroundHit = (d.object(forKey: Keys.allowGroundHit) as? Bool) ?? false
        // Android (2026-11): no house player is preselected.
        house = AppModel.validHouse(d.stringArray(forKey: Keys.house) ?? [])
        // Android: earlier players keep the nickname game; a first English launch starts with SPUD letters.
        let firstRules = d.object(forKey: Keys.scene) != nil ? "NICKNAMES" : (AppText.language == "en" ? "SPUD" : "NICKNAMES")
        rules = RuleSet(rawValue: d.string(forKey: Keys.ruleSet) ?? firstRules) ?? .nicknames
        savedRoom = d.string(forKey: Keys.room)
        hasSavedGame = d.string(forKey: Keys.saved) != nil
        hasPracticeSaved = d.string(forKey: Keys.practiceSaved) != nil
        rankPoints = d.integer(forKey: Keys.colourPoints)
        receptionZoomOwn = (d.object(forKey: Keys.receptionZoomOwn) as? Bool) ?? true
        receptionZoomOthers = (d.object(forKey: Keys.receptionZoomOthers) as? Bool) ?? true
        gameSounds = (d.object(forKey: Keys.gameSounds) as? Bool) ?? true
        speechReady = GameAudio.voiceAvailable()
        loadRulePreferences(rules)
        // Android `FamilyMessages.get(this).setLanguage(AppText.language)`.
        FamilyMessages.shared.languageOverride = AppText.language
    }

    private static func validHouse(_ ids: [String]) -> [String] {
        var out: [String] = []
        for id in ids where AmuduCharacters.exists(id) && !out.contains(id) { out.append(id) }
        return out
    }

    func tr(_ en: String, _ he: String) -> String {
        return GameText.t(en, he, hebrew: hebrew)
    }

    /// Android `learn(key)`: the lesson copy, with the light lesson's own title and body from `EnvironmentCopy`.
    func learn(_ key: String) -> String {
        switch key {
        case "title_light": return EnvironmentCopy.get("light_title")
        case "body_light": return EnvironmentCopy.get("light_body")
        default: return LearningCopy.get(key)
        }
    }

    /// Android `Toast.LENGTH_LONG`.
    func status(_ s: String) {
        toastToken += 1
        let token = toastToken
        toast = s
        _ = afterDelay(3.5) { [weak self] in
            guard let self, self.toastToken == token else { return }
            self.toast = nil
        }
    }

    /// Android `sound(kind)`: effects follow the Game sounds switch.
    func sound(_ kind: String) {
        if gameSounds { audio.play(kind) }
    }

    /// Android `speak(s, english, queued)`: nothing is spoken without a voice for the app language.
    private func speak(_ s: String, english: Bool = false, queued: Bool = false) {
        if speechReady { audio.speak(s, english: english, queued: queued) }
    }

    // MARK: Dialogs (Android `GameDialogBuilder` + `SpudDialogStyle`)

    @discardableResult
    func showDialog(_ request: SpudDialogRequest, input: String = "") -> UUID {
        if request.field != nil { dialogInput = input }
        dialogs.append(request)
        return request.id
    }

    func dismissDialog(_ id: UUID?) {
        guard let id else { return }
        dialogs.removeAll { $0.id == id }
    }

    /// The × or a tap outside: the dialog closes and its cancel path runs.
    func closeDialog(_ id: UUID, cancel: Bool) {
        guard let request = dialogs.first(where: { $0.id == id }) else { return }
        dialogs.removeAll { $0.id == id }
        if cancel { request.onClose?() }
    }

    func runDialogAction(_ id: UUID, _ action: SpudDialogAction) {
        guard dialogs.contains(where: { $0.id == id }) else { return }
        dialogs.removeAll { $0.id == id }
        action.run()
    }

    func chooseDialogItem(_ id: UUID, _ index: Int) {
        guard let request = dialogs.first(where: { $0.id == id }) else { return }
        dialogs.removeAll { $0.id == id }
        request.onItem?(index)
    }

    func setDialogInput(_ value: String, limit: Int?) {
        if let limit, value.utf16.count > limit {
            dialogInput = String(decoding: Array(value.utf16.prefix(limit)), as: UTF16.self)
        } else {
            dialogInput = value
        }
    }

    // MARK: Home

    func home() {
        league?.hide()
        setupPurpose = 0
        dismissDialog(lobbyWaitDialogID)
        lobbyWaitDialogID = nil
        saveLocal()
        gameView?.stop()
        stopCalls.stop()
        gameView = nil
        online?.close()
        online = nil
        pauseVisible = false
        pauseDialogID = nil
        sceneLoading = false
        hideHuddle()
        dismissRulesDialog()
        dialogs.removeAll()
        savedRoom = defaults.string(forKey: Keys.room)
        hasSavedGame = defaults.string(forKey: Keys.saved) != nil
        hasPracticeSaved = defaults.string(forKey: Keys.practiceSaved) != nil
        rankPoints = defaults.integer(forKey: Keys.colourPoints)
        screen = .home
    }

    /// Android `FamilyMenu.section`: a home section remembers whether it is open (the first two start open).
    func sectionOpen(_ title: String, _ expanded: Bool) -> Bool {
        if let known = sections[title] { return known }
        return (defaults.object(forKey: Keys.menuSection + title) as? Bool) ?? expanded
    }

    func toggleSection(_ title: String, _ expanded: Bool) {
        let open = !sectionOpen(title, expanded)
        sections[title] = open
        defaults.set(open, forKey: Keys.menuSection + title)
    }

    /// Android: the EditText keeps at most 22 characters and every change is saved.
    func updateName(_ value: String) {
        var text = value
        if text.utf16.count > 22 { text = String(decoding: Array(text.utf16.prefix(22)), as: UTF16.self) }
        playerName = text
        defaults.set(text, forKey: Keys.name)
    }

    func shiftAvatar(_ d: Int) {
        let ids = AmuduCharacters.ids
        let index = ids.firstIndex(of: avatar) ?? -1
        avatar = ids[Kotlin.floorMod(index + d, ids.count)]
        defaults.set(avatar, forKey: Keys.avatar)
    }

    private func validName() -> Bool {
        if Words.validName(playerName) { return true }
        status(tr("Enter a name with letters, spaces or numbers (up to 22 characters).", "כתבו שם באותיות, רווחים או מספרים (עד 22 תווים)."))
        return false
    }

    /// Android `setup()`: the player's own avatar is never a house player, and the room keeps a place for each chosen
    /// house player and the player.
    func openSetup() {
        house.removeAll { $0 == avatar }
        count = max(count, min(house.count + 1, 10))
        league?.hide()
        environmentOpen = false
        advancedOpen = false
        screen = .setup
    }

    func openHelp() {
        screen = .help
    }

    func openRank() {
        rankPoints = defaults.integer(forKey: Keys.colourPoints)
        screen = .rank
    }

    /// Android `parentGate { supportPage() }`.
    func openSettings() {
        parentGate { [weak self] in self?.screen = .support }
    }

    func requestJoin() {
        if validName() { joinDialog() }
    }

    /// Android `joinDialog(initialCode, error)`: the room code dialog, reopened with the code and the reason when
    /// joining failed.
    func joinDialog(_ initialCode: String = "", _ error: String? = nil) {
        let field = SpudDialogField(placeholder: tr("Six-character code", "קוד בן שישה תווים"), keyboard: .asciiCapable,
                                    capitalization: .characters)
        let request = SpudDialogStyle.make(title: tr("Join a private room", "הצטרפות לחדר פרטי"), message: error, field: field,
                                           positive: (tr("Join", "הצטרפות"), { [weak self] in self?.join() }),
                                           negative: (tr("Cancel", "ביטול"), {}))
        showDialog(request, input: initialCode)
    }

    func returnToRoom(_ code: String) {
        if validName() { openRoom(code) }
    }

    private func join() {
        let code = Kotlin.trim(dialogInput).uppercased()
        let upper: ClosedRange<Unicode.Scalar> = "A"..."Z"
        let digits: ClosedRange<Unicode.Scalar> = "2"..."9"
        let valid = code.unicodeScalars.count == 6 && code.unicodeScalars.allSatisfy { upper.contains($0) || digits.contains($0) }
        if valid {
            openRoom(code)
        } else {
            status(tr("Enter the six-character room code.", "הזינו קוד חדר בן שישה תווים."))
        }
    }

    /// Android `resumeSavedMatch()`: the saved match continues as the same player, and a saved league round still
    /// records its result in that league.
    func continueSaved() {
        localLeagueId = defaults.string(forKey: Keys.savedLeague) ?? ""
        activeLeagueRound = !Kotlin.isBlank(localLeagueId)
        restore(Keys.saved, uid: defaults.string(forKey: Keys.savedOwn) ?? "p0")
    }

    func continuePractice() {
        activeLeagueRound = false
        localLeagueId = ""
        restore(Keys.practiceSaved, uid: "p0")
    }

    private func restore(_ key: String, uid: String) {
        guard let json = defaults.string(forKey: key),
              let data = json.data(using: .utf8),
              let wrapper = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
              let engine = try? AmuduCodec.create(AmuduCodec.node(wrapper["checkpoint"]), order: wrapper["order"] as? [String]) else {
            status(tr("Saved game could not be restored.", "לא ניתן לשחזר את המשחק."))
            return
        }
        present(engine, uid: uid, network: nil)
    }

    /// Android "More Minik apps & games": the family card, its links behind the grown-up gate.
    func moreApps() {
        FamilyMessages.shared.showMoreApps(gate: { [weak self] action in self?.parentGate(action) })
    }

    // MARK: Grown-up gate (Android `FamilyAdultGate.open` with `SpudDialogStyle.apply(adult = true)`)

    func parentGate(_ action: @escaping @MainActor () -> Void) {
        // Android `FamilyAdultGate.nextQuestion`: x in 4...9, y in 3...8, never the previous product twice in a row.
        var a = 0
        var b = 0
        repeat {
            a = 4 + Int.random(in: 0..<6)
            b = 3 + Int.random(in: 0..<6)
        } while a * b == gatePrevious
        gatePrevious = a * b
        gateAnswer = a * b
        gateQuestion = "\u{2066}\(a) × \(b) = ?\u{2069}"
        gateInput = ""
        gateError = false
        gateAction = action
        gateVisible = true
    }

    /// Android: a wrong answer keeps the gate open with "Try again." on the field.
    func confirmGate() {
        if FamilyMessages.answer(gateInput) == gateAnswer {
            let action = gateAction
            gateAction = nil
            gateVisible = false
            action?()
        } else {
            gateError = true
        }
    }

    func cancelGate() {
        gateAction = nil
        gateVisible = false
    }

    // MARK: Settings & feedback (Android `supportPage`)

    func rateApp() {
        // Android opens the store listing; iOS asks the App Store for its own rating prompt.
        guard let scene = UIApplication.shared.connectedScenes.compactMap({ $0 as? UIWindowScene })
            .first(where: { $0.activationState == .foregroundActive }) else { return }
        AppStore.requestReview(in: scene)
    }

    func openShare() {
        let field = SpudDialogField(placeholder: "", minLines: 3)
        let request = SpudDialogStyle.make(title: tr("Your message", "ההודעה שלכם"), field: field,
                                           positive: (tr("Choose an app", "בחירת אפליקציה"), { [weak self] in
                                               guard let self else { return }
                                               self.shareSheet = ShareText(text: self.dialogInput)
                                           }),
                                           negative: (tr("Cancel", "ביטול"), {}))
        showDialog(request, input: tr("Come play with me! ", "בואו לשחק איתי! ") + AppModel.storeLink)
    }

    func openFeedback() {
        let field = SpudDialogField(placeholder: tr("What should we improve?", "מה כדאי לשפר?"), minLines: 4)
        let request = SpudDialogStyle.make(title: tr("Your feedback", "המשוב שלכם"), field: field,
                                           positive: (tr("Choose an app", "בחירת אפליקציה"), { [weak self] in self?.sendFeedback() }),
                                           negative: (tr("Cancel", "ביטול"), {}))
        showDialog(request)
    }

    private func sendFeedback() {
        let text = dialogInput
        if Kotlin.isBlank(text) { return }
        var mail = URLComponents()
        mail.scheme = "mailto"
        mail.path = "appsbybros.dev@gmail.com"
        mail.queryItems = [URLQueryItem(name: "subject", value: "Game feedback"),
                           URLQueryItem(name: "body", value: text + "\n\n" + AppModel.storeLink)]
        guard let url = mail.url else { return }
        openExternal(url)
    }

    func openExternal(_ url: URL) {
        UIApplication.shared.open(url) { [weak self] opened in
            MainActor.assumeIsolated {
                guard let self, !opened else { return }
                self.status(self.tr("No app is available to open this link.", "אין אפליקציה זמינה לפתיחת הקישור."))
            }
        }
    }

    /// Android "Diagnose online lag" / "Stop lag diagnosis · id": a ten-minute opt-in, confirmed in a dialog.
    var lagButtonTitle: String {
        _ = lagTick
        return LagDiagnostics.active ? tr("Stop lag diagnosis", "עצירת בדיקת השהיות") + " · " + LagDiagnostics.id
            : tr("Diagnose online lag", "בדיקת השהיות ברשת")
    }

    func lagDiagnosis() {
        if LagDiagnostics.active {
            LagDiagnostics.stop()
            lagTick += 1
            return
        }
        let request = SpudDialogStyle.make(
            title: tr("Temporary lag diagnosis", "בדיקת השהיות זמנית"),
            message: tr("For 10 minutes, send aggregate frame and connection timings, app version, phone model and language to our Firebase support log. No names, camera images, audio or gameplay recordings are collected. Join an online game after starting. You can stop at any time. Reports are removed during support cleanup; stopping ends collection.",
                        "במשך 10 דקות נשלח ליומן התמיכה ב-Firebase נתוני תזמון מצטברים של התצוגה והחיבור, גרסת אפליקציה, דגם טלפון ושפה. לא נאספים שמות, תמונות מצלמה, קול או הקלטות משחק. אחרי ההפעלה הצטרפו למשחק מקוון. אפשר לעצור בכל עת. הדוחות מוסרים בניקוי התמיכה; עצירה מסיימת את האיסוף."),
            positive: (tr("Start 10-minute diagnosis", "התחלת בדיקה ל-10 דקות"), { [weak self] in
                LagDiagnostics.start()
                self?.lagTick += 1
            }),
            negative: (tr("Cancel", "ביטול"), {}))
        showDialog(request)
    }

    // MARK: Privacy policy (Android `privacyPage()`)

    /// Android `assets/privacy/<language>.html`. The iOS bundle carries the page as `privacy-<language>.html` only
    /// once the owner supplies the iOS wording (Android's describes Google Play, AdMob and Android storage); until then
    /// the home menu offers no Privacy policy button.
    static func privacyPolicy() -> String? {
        let code = AppText.supported.contains(AppText.language) ? AppText.language : "en"
        guard let url = Bundle.main.url(forResource: "privacy-" + code, withExtension: "html"),
              let text = try? String(contentsOf: url, encoding: .utf8) else { return nil }
        return text
    }

    var hasPrivacyPolicy: Bool { return AppModel.privacyPolicy() != nil }

    func openPrivacy() {
        screen = .privacy
    }

    /// Android: a link in the policy opens outside the app only after the grown-up gate.
    func openPolicyLink(_ url: URL) {
        parentGate { [weak self] in self?.openExternal(url) }
    }

    // MARK: Colour ranks

    /// Android `recordRank`: every match pays its rank points once (receipts per match and player), practice never.
    private func recordRank(_ e: AmuduEngine, _ uid: String) {
        if e.practice != nil { return }
        guard let a = e.actor(uid) else { return }
        var receipts = jsonObject(defaults.string(forKey: Keys.rankReceipts))
        let key = e.id + ":" + uid
        let won = e.result?.winners.contains(uid) == true && e.turn > 1
        let earned = a.rankEarned + (won ? 15 : 0)
        let old = AmuduCodec.number(receipts[key]).map { Kotlin.toInt($0) } ?? 0
        if earned > old {
            receipts[key] = earned
            let total = defaults.integer(forKey: Keys.colourPoints) + earned - old
            defaults.set(total, forKey: Keys.colourPoints)
            if let text = jsonText(receipts) { defaults.set(text, forKey: Keys.rankReceipts) }
            rankPoints = total
        }
    }

    private func jsonObject(_ text: String?) -> [String: Any] {
        guard let text, let data = text.data(using: .utf8) else { return [:] }
        return ((try? JSONSerialization.jsonObject(with: data)) as? [String: Any]) ?? [:]
    }

    private func jsonText(_ value: Any) -> String? {
        guard JSONSerialization.isValidJSONObject(value), let data = try? JSONSerialization.data(withJSONObject: value) else { return nil }
        return String(data: data, encoding: .utf8)
    }

    // MARK: Daily skill journey and lessons

    /// Android `LocalDate.now().toString()`.
    static func today() -> String {
        let f = DateFormatter()
        f.calendar = Calendar(identifier: .gregorian)
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = TimeZone.current
        f.dateFormat = "yyyy-MM-dd"
        return f.string(from: Date())
    }

    /// Android `journeyProgress()`: a progress saved before the 40-challenge catalogue (`catalogue` < 2) is migrated
    /// once — the original mastery and points are kept, new challenges are not given away — and saved again.
    func journeyProgress() -> SpudProgress {
        var j = jsonObject(defaults.string(forKey: Keys.skillJourney))
        let completed = max(AmuduCodec.number(j["completed"]).map { Kotlin.toInt($0) } ?? 0, 0)
        let points = AmuduCodec.number(j["points"]).map { Kotlin.toInt($0) } ?? 0
        let bonusDay = (j["bonusDay"] as? String) ?? ""
        let receipts = AmuduCodec.items(j["receipts"]).map { AmuduCodec.text($0) }
        let catalogue = AmuduCodec.number(j["catalogue"]).map { Kotlin.toInt($0) } ?? 1
        if catalogue < 2 {
            let migrated = SpudProgress.migrate(completed: completed, points: points, bonusDay: bonusDay, receipts: receipts)
            j["catalogue"] = 2
            j["completed"] = migrated.completed
            j["mastered"] = Array(migrated.mastered)
            if let text = jsonText(j) { defaults.set(text, forKey: Keys.skillJourney) }
            return migrated
        }
        let mastered = Set(AmuduCodec.items(j["mastered"]).map { AmuduCodec.text($0) })
        return SpudProgress(completed: completed, points: points, bonusDay: bonusDay, receipts: receipts, mastered: mastered)
    }

    /// Android `journeyPage(step = progress.completed)`: only the current challenge or a completed one can be opened.
    func openJourney(_ step: Int? = nil) {
        gameView?.stop()
        let p = journeyProgress()
        let wanted = step ?? p.completed
        journeyStep = (wanted >= 0 && (wanted == p.completed || p.done(wanted))) ? wanted : p.completed
        hasPracticeSaved = defaults.string(forKey: Keys.practiceSaved) != nil
        screen = .journey
    }

    /// Android `lessonHub()`.
    func openLessonHub() {
        screen = .lessonHub
    }

    /// Android `lessonPage(topic)`.
    func openLesson(_ topic: String) {
        lessonTopic = topic
        screen = .lesson
    }

    /// Android `conditionText(c)`: light (☀, ☀↓ or ☾), wind (≋ or ≋≋) and Andromeda, joined with " · ".
    func conditionText(_ c: PracticeConditions) -> String {
        let windText: String
        switch c.wind {
        case .none: windText = ""
        case .slow: windText = "≋ " + tr(c.wind.en, c.wind.he)
        case .fast: windText = "≋≋ " + tr(c.wind.en, c.wind.he)
        }
        let sign: String
        switch c.daylight {
        case .evening: sign = "☀↓ "
        case .night: sign = "☾ "
        default: sign = "☀ "
        }
        let light = sign + tr(c.daylight.en, c.daylight.he)
        let space = c.scene == .andromeda ? tr(c.scene.en, c.scene.he) : ""
        return [light, windText, space].filter { !$0.isEmpty }.joined(separator: " · ")
    }

    /// Android `getString("journeyControl", "EASY")`.
    var journeyControl: ThrowMode {
        return ThrowMode.allCases.first { $0.rawValue == (defaults.string(forKey: Keys.journeyControl) ?? "EASY") } ?? .easy
    }

    func setJourneyControl(_ mode: ThrowMode) {
        defaults.set(mode.rawValue, forKey: Keys.journeyControl)
    }

    /// Android `getString("journeyBall", "AUTO")`.
    var journeyBall: String {
        return defaults.string(forKey: Keys.journeyBall) ?? "AUTO"
    }

    func setJourneyBall(_ name: String) {
        defaults.set(name, forKey: Keys.journeyBall)
    }

    /// Android `startJourney(step)`: the saved control and ball, and the challenge's own conditions.
    func startJourney(_ step: Int) {
        launchPractice(step, journeyControl, PracticeCurriculum.ball(step, journeyBall), PracticeCurriculum.conditions(step), "", false)
    }

    /// Android `launchPractice(step, mode, ball, conditions, topic, ground)`: the player with the challenge's partners or
    /// throwers on a 16 m court (`PracticeCurriculum.config`).
    func launchPractice(_ step: Int, _ mode: ThrowMode, _ ball: BallKind, _ conditions: PracticeConditions, _ topic: String = "",
                        _ ground: Bool = false) {
        activeLeagueRound = false
        localLeagueId = ""
        let d = SpudPractice(step, 1, topic)
        var used: Set<String> = [avatar]
        var members = [Member("p0", avatar, AmuduCharacters.get(avatar).name(hebrew: hebrew), bot: false, hebrew: hebrew)]
        for i in 0..<d.stage.bots {
            let bot = d.stage.bot(d.cycle, used)
            used.insert(bot.id)
            members.append(Member("p\(i + 1)", bot.id, bot.name(hebrew: hebrew), bot: true, hebrew: hebrew))
        }
        online?.close()
        online = nil
        let seed = Int64(Date().timeIntervalSince1970 * 1000)
        guard let cfg = try? PracticeCurriculum.config(step, mode, ball, conditions, members.count, topic, ground),
              let engine = try? AmuduEngine(members: members, config: cfg, seed: seed) else { return }
        present(engine, uid: "p0", network: nil)
    }

    private func journeyResult(_ e: AmuduEngine, _ r: Outcome) {
        guard let d = e.practice else { return }
        let won = r.winners.contains(localId)
        let topic = e.config.practiceLesson
        if !topic.isEmpty {
            let conditions = PracticeConditions.allCases.first {
                $0.scene == e.config.scene && $0.wind == e.config.wind && $0.daylight == e.config.daylight
            } ?? .calm
            lessonOutcome = LessonOutcome(won: won, topic: topic, step: d.step, mode: e.config.throwMode, ball: e.config.ball,
                                          conditions: conditions, ground: e.config.allowGroundHit)
            screen = .lessonResult
            return
        }
        let old = journeyProgress()
        let next = old.finish(r.id, d.step, won, AppModel.today())
        if next != old {
            let j: [String: Any] = ["catalogue": 2, "mastered": Array(next.mastered), "completed": next.completed, "points": next.points,
                                    "bonusDay": next.bonusDay, "receipts": next.receipts]
            if let text = jsonText(j) { defaults.set(text, forKey: Keys.skillJourney) }
            let total = defaults.integer(forKey: Keys.colourPoints) + next.points - old.points
            defaults.set(total, forKey: Keys.colourPoints)
            rankPoints = total
        }
        let following: Int
        if won && d.step == old.completed {
            following = next.completed
        } else if won {
            following = d.step + 1
        } else {
            following = d.step
        }
        journeyOutcome = JourneyOutcome(won: won, stage: d.stage, successes: d.successes, goal: d.goal, gained: next.points - old.points,
                                        next: following, replay: won && next == old)
        screen = .journeyResult
    }

    func repeatLesson() {
        guard let o = lessonOutcome else { return }
        launchPractice(o.step, o.mode, o.ball, o.conditions, o.topic, o.ground)
    }

    // MARK: Setup

    private func config(_ n: Int? = nil) -> GameConfig? {
        return try? GameConfig(scene: scene, ball: ball, freezeRule: .freeze, participants: n ?? count, turns: turns, width: 28.0,
                               depth: 18.0, daylight: daylight, throwMode: throwMode, wind: wind, rules: rules,
                               requireCall: requireCall, stepsAfterCall: stepsAfterCall, actionSeconds: actionSeconds,
                               stepLengthFraction: 0.5 / 18.0, nicknameAnswer: nicknameAnswer, allowGroundHit: allowGroundHit)
    }

    /// Android `persist()`: the shared settings plus this rule set's own configuration and house players.
    func persist() {
        defaults.set(rules.rawValue, forKey: Keys.ruleSet)
        if let cfg = config(), let text = jsonText(AmuduCodec.config(cfg)) { defaults.set(text, forKey: Keys.ruleConfig(rules)) }
        defaults.set(house, forKey: Keys.ruleHouse(rules))
        defaults.set(scene.rawValue, forKey: Keys.scene)
        defaults.set(ball.rawValue, forKey: Keys.ball)
        defaults.set(freeze.rawValue, forKey: Keys.freeze)
        defaults.set(count, forKey: Keys.count)
        defaults.set(turns, forKey: Keys.turns)
        defaults.set(house, forKey: Keys.house)
        defaults.set(daylight.rawValue, forKey: Keys.daylight)
        defaults.set(throwMode.rawValue, forKey: Keys.throwMode)
        defaults.set(allowGroundHit, forKey: Keys.allowGroundHit)
        defaults.set(wind.rawValue, forKey: Keys.wind)
    }

    /// Android `loadRulePreferences`: each rule set remembers its own settings; SPUD starts with a required call and
    /// four steps.
    private func loadRulePreferences(_ value: RuleSet) {
        let saved = jsonObject(defaults.string(forKey: Keys.ruleConfig(value)))
        var c: GameConfig?
        if !saved.isEmpty { c = try? AmuduCodec.readConfig(saved) }
        requireCall = c?.requireCall ?? (value == .spud)
        stepsAfterCall = c?.stepsAfterCall ?? (value == .spud ? 4 : 0)
        actionSeconds = c?.actionSeconds ?? 30
        nicknameAnswer = c?.nicknameAnswer ?? .choices
        if let c {
            scene = c.scene
            ball = c.ball
            freeze = c.freezeRule
            count = c.participants
            turns = c.turns
            daylight = c.daylight
            throwMode = c.throwMode
            allowGroundHit = c.allowGroundHit
            wind = c.wind
        }
        if let ids = defaults.stringArray(forKey: Keys.ruleHouse(value)) { house = AppModel.validHouse(ids) }
    }

    /// Android rule-mode choice: save the current rules, switch, load the other set's settings and rebuild the page
    /// (its groups start closed again).
    func selectRules(_ value: RuleSet) {
        persist()
        rules = value
        loadRulePreferences(value)
        persist()
        house.removeAll { $0 == avatar }
        count = max(count, min(house.count + 1, 10))
        environmentOpen = false
        advancedOpen = false
    }

    /// Android "Room capacity": fewer places drop the last chosen house players.
    func setCapacity(_ n: Int) {
        count = n
        while house.count > count - 1, !house.isEmpty { house.removeLast() }
        persist()
    }

    /// Android `updateCapacity()`: "You + {0} house players · {1} places for friends".
    var capacityNote: String {
        let selected = house.filter { $0 != avatar }.count
        let free = count - selected - 1
        return tr("You + {0} house players · {1} places for friends", "אתם + {0} שחקני בית · {1} מקומות לחברים")
            .replacingOccurrences(of: "{0}", with: String(selected)).replacingOccurrences(of: "{1}", with: String(free))
    }

    /// Android: a house player can be added only while the room has a free place; never while opening a league round.
    func houseEnabled(_ id: String) -> Bool {
        if id == avatar { return false }
        let free = count - house.filter { $0 != avatar }.count - 1
        return setupPurpose != 2 && (house.contains(id) || free > 0)
    }

    func setHouse(_ id: String, _ selected: Bool) {
        if selected {
            if house.contains(id) { return }
            if house.count >= count - 1 { return }
            house.append(id)
        } else {
            house.removeAll { $0 == id }
        }
        persist()
    }

    /// Android "Start": at least one house player is needed.
    func startFromSetup() {
        if house.isEmpty {
            status(tr("Choose at least one house player.", "בחרו לפחות שחקן בית אחד."))
        } else {
            startLocal()
        }
    }

    /// Android `startLocal()`: the player and exactly the chosen house players.
    func startLocal() {
        persist()
        activeLeagueRound = false
        localLeagueId = ""
        var roster = [Member("p0", avatar, AmuduCharacters.get(avatar).name(hebrew: hebrew), bot: false, hebrew: hebrew)]
        let chosen = Array(AmuduCharacters.availableBots(humans: [roster[0]], requested: house, fillTo: 0).prefix(house.count))
        for (i, id) in chosen.enumerated() {
            roster.append(Member("house\(i)", id, AmuduCharacters.get(id).name(hebrew: hebrew), bot: true, hebrew: hebrew))
        }
        online?.close()
        online = nil
        let seed = Int64(Date().timeIntervalSince1970 * 1000)
        guard let cfg = config(roster.count), let engine = try? AmuduEngine(members: roster, config: cfg, seed: seed) else { return }
        present(engine, uid: "p0", network: nil)
    }

    func openPrivateRoom() {
        if !validName() { return }
        if house.count >= count - 1 {
            status(tr("Leave at least one place for a friend: remove a house player or increase room capacity (maximum 10).",
                      "השאירו לפחות מקום אחד לחבר: הסירו שחקן בית או הגדילו את מספר המקומות (עד 10)."))
        } else {
            openRoom(nil)
        }
    }

    /// Android setup's league action: "Create a family league" (purpose 1) or "Open league round" (purpose 2).
    func setupLeagueAction() {
        if !validName() { return }
        persist()
        guard let cfg = config(10) else { return }
        if setupPurpose == 1 {
            league?.create(cfg, house, leagueIdentity())
        } else {
            league?.start(cfg)
        }
    }

    // MARK: Game

    func present(_ e: AmuduEngine, uid: String, network: OnlineRoom?) {
        dismissDialog(lobbyWaitDialogID)
        lobbyWaitDialogID = nil
        ScreenOrientation.apply(ScreenOrientation.battle(defaults.string(forKey: Keys.battleOrientation)))
        gameView?.stop()
        dismissedHuddle = -1
        localId = uid
        e.paused = false
        dismissDialog(pauseDialogID)
        pauseDialogID = nil
        pauseVisible = false
        hideHuddle()
        dismissRulesDialog()
        let view = ArenaView(engine: e, ownId: uid, art: art, hebrew: hebrew)
        view.rankPoints = defaults.integer(forKey: Keys.colourPoints)
        view.receptionZoomEnabled = receptionZoomOwn
        view.followHumanZoomEnabled = receptionZoomOthers
        view.onRotate = { [weak self, weak view] in
            guard let self, let view else { return }
            let next = view.bounds.width > view.bounds.height ? "portrait" : "landscape"
            self.defaults.set(next, forKey: Keys.battleOrientation)
            ScreenOrientation.apply(ScreenOrientation.battle(next))
        }
        view.onBack = { [weak self] in self?.back() }
        view.onResult = { [weak self] r in self?.result(r) }
        view.onHuddle = { [weak self] in self?.showHuddle() }
        view.onReturnVote = { [weak self] in self?.showReturnVote() }
        view.onStatus = { [weak self] in self?.showScores() }
        view.onEvent = { [weak self] ev in self?.event(ev) }
        view.onChoose = { [weak self, weak view] a in
            guard let self, let view else { return }
            self.choosePlayer(a, view, uid)
        }
        view.onRoster = { [weak self, weak view] in
            guard let self, let view else { return }
            let candidates = view.engine.activeActors.filter { $0.member.id != uid }
            let request = SpudDialogStyle.make(title: self.tr("Choose a player", "בחירת שחקן"),
                                               items: candidates.map { $0.fullName(hebrew: self.hebrew) },
                                               onItem: { [weak view] i in
                                                   guard let view, i < candidates.count else { return }
                                                   view.onChoose?(candidates[i])
                                               },
                                               negative: (self.tr("Back", "חזרה"), {}))
            self.showDialog(request)
        }
        // Android (2026-11): phrases are offered only while speech works.
        view.speechAvailable = speechReady
        view.onSay = { [weak self, weak view] in
            guard let self, self.speechReady else { return }
            let request = SpudDialogStyle.make(title: self.tr("Say something", "אומרים משהו"), items: self.sayPhrases,
                                               onItem: { [weak view] i in view?.command(.say(index: i)) })
            self.showDialog(request)
        }
        gameView = view
        network?.attach(view)
        screen = .game
        // Android `FamilyLandscapeHint.show` (matches only since 2026-11): a passing reminder when a game opens in
        // portrait; it never covers the HUD for long or moves it.
        if e.practice == nil {
            _ = afterDelay(0.9) { [weak self, weak view] in
                guard let self, let view, self.gameView === view, self.screen == .game, view.window != nil,
                      view.bounds.height > view.bounds.width else { return }
                self.status(FamilyMessages.text("For a wider view, play in landscape.", "לתצוגה רחבה יותר, שחקו במצב אופקי."))
            }
        }
        if e.practice != nil {
            // Android shows a spinner until the world's first frame, then starts the practice.
            sceneLoading = true
            view.onFirstFrame = { [weak self, weak view] in
                guard let self, let view, self.gameView === view else { return }
                self.sceneLoading = false
                view.sceneReady = true
                if self.isForeground && !self.pauseVisible { view.start() }
            }
        } else {
            sceneLoading = false
            view.start()
        }
    }

    /// Android `view.onChoose`: SPUD and players without a nickname are called directly; otherwise the room's
    /// nickname answer applies — automatic (the right nickname, shown), a choice among the nicknames in play, or typed.
    private func choosePlayer(_ a: GameActor, _ view: ArenaView, _ uid: String) {
        let e = view.engine
        if e.config.rules == .spud || a.suffixes.isEmpty {
            view.command(.select(target: a.member.id))
            return
        }
        switch e.config.nicknameAnswer {
        case .automatic:
            let name = a.fullName(hebrew: hebrew)
            view.command(.select(target: a.member.id, typedName: name))
            status(name)
        case .choices:
            var names: [String] = []
            for other in e.activeActors where other.member.id != uid {
                let name = other.fullName(hebrew: hebrew)
                if !names.contains(name) { names.append(name) }
            }
            names = Kotlin.stableSorted(names) { Kotlin.less($0, $1) }
            let target = a.member.id
            let request = SpudDialogStyle.make(title: tr("Choose the nickname", "בחירת הכינוי"), items: names,
                                               onItem: { [weak view] i in
                                                   guard let view, i < names.count else { return }
                                                   view.command(.select(target: target, typedName: names[i]))
                                               })
            showDialog(request)
        case .typed:
            let target = a.member.id
            let field = SpudDialogField(placeholder: tr("Type the nickname", "כתבו את הכינוי"), capitalization: .never)
            let request = SpudDialogStyle.make(title: tr("Type the nickname", "כתבו את הכינוי"),
                                               message: tr("An incorrect nickname adds one penalty.", "כינוי שגוי מוסיף נקודת חובה אחת."),
                                               field: field,
                                               positive: (tr("Call", "קריאה"), { [weak self, weak view] in
                                                   guard let self, let view else { return }
                                                   view.command(.select(target: target, typedName: self.dialogInput))
                                               }))
            showDialog(request)
        }
    }

    var sayPhrases: [String] {
        return hebrew ? Words.phrasesHe : Words.phrasesEn.map { AppText.t($0) }
    }

    var funnyWords: [String] {
        return hebrew ? Words.he : Words.en
    }

    private func event(_ e: GameEvent) {
        if let v = gameView {
            recordRank(v.engine, localId)
            v.rankPoints = rankPoints
        }
        var recorded: StopCallVoice?
        if e.kind == "freeze", gameView?.engine.config.rules != .spud {
            recorded = StopCallVoice.forCaller(AppText.language, gameView?.engine.actor(e.actor)?.member.character)
        }
        if recorded == nil && gameSounds { audio.play(e.kind) }
        switch e.kind {
        case "call":
            guard let engine = gameView?.engine, let a = engine.actor(engine.called) else { return }
            let english = hebrew && a.member.bot && a.suffixes.isEmpty && (a.member.character == "mia" || a.member.character == "gaya")
            speak(english ? AmuduCharacters.get(a.member.character).en : a.fullName(hebrew: hebrew), english: english)
        case "renamed":
            if e.actor != localId {
                let name = gameView?.engine.actor(e.actor)?.fullName(hebrew: hebrew) ?? e.text
                status(tr("Remember: ", "זכרו: ") + name)
                speak(name)
            }
        case "freeze":
            if let recorded {
                audio.stopSpeech()
                stopCalls.play(recorded)
            } else {
                speak(RuleText.call(gameView?.engine.config.rules ?? .nicknames), english: AppText.language == "hi")
            }
        case "say":
            let i = Int(e.text) ?? 0
            let list = hebrew ? Words.phrasesHe : Words.phrasesEn
            speak(AppText.t(i >= 0 && i < list.count ? list[i] : ""), queued: true)
        default:
            break
        }
    }

    private func result(_ r: Outcome) {
        online?.resultsVisible()
        dismissRulesDialog()
        guard let v = gameView else { return }
        let e = v.engine
        recordRank(e, localId)
        v.stop()
        gameView = nil
        sceneLoading = false
        if e.practice != nil {
            defaults.removeObject(forKey: Keys.practiceSaved)
            hasPracticeSaved = false
        } else {
            defaults.removeObject(forKey: Keys.saved)
            hasSavedGame = false
        }
        hideHuddle()
        dismissDialog(pauseDialogID)
        pauseDialogID = nil
        pauseVisible = false
        if e.practice == nil && online == nil && !Kotlin.isBlank(localLeagueId) {
            FamilyLeague.recordLocal(self, localLeagueId, e)
        }
        if e.practice != nil {
            journeyResult(e, r)
            return
        }
        resultHeading = r.elapsed >= 600 ? tr("What a game!", "איזה משחק!") : tr("Game ended", "המשחק הסתיים")
        let winnerNames = r.winners.compactMap { id in e.actor(id).map { RuleText.name($0, localId) } }.joined(separator: ", ")
        resultTitle = (r.winners.count == 1 ? tr("Winner: ", "המנצח/ת: ") : tr("Winners: ", "המנצחים: ")) + winnerNames
        resultLeague = activeLeagueRound
        let ordered = Kotlin.stableSorted(e.actors) { $0.penalties < $1.penalties }
        results = ordered.map { a in
            ResultRow(id: a.member.id, character: a.member.character, name: RuleText.name(a, localId), score: RuleText.score(a, e.config.rules),
                      winner: r.winners.contains(a.member.id))
        }
        screen = .result
    }

    /// Android result page: back to the league after a league round, otherwise to the main menu.
    func leaveResult() {
        if resultLeague { leaguePage() } else { home() }
    }

    /// Android `back()` in a game: the last active human of a room pauses it for everyone; a local game pauses and is
    /// saved. The break dialog offers to return, or to finish (or, for a guest who cannot finish the room, to exit).
    func back() {
        guard let v = gameView else {
            if screen != .home { home() }
            return
        }
        if let room = online, v.engine.activeHumans <= 1 { room.setPaused(true) }
        if online == nil {
            v.engine.paused = true
            v.stop()
            saveLocal()
        }
        let practice = v.engine.practice != nil
        let lesson = !v.engine.config.practiceLesson.isEmpty
        let message: String
        if lesson {
            message = learn("lesson_paused")
        } else if practice {
            message = tr("Your challenge is paused.", "האתגר מושהה.")
        } else if online == nil || v.engine.sharedPause {
            message = tr("Your game is paused.", "המשחק מושהה.")
        } else {
            message = tr("The game continues for the others.", "המשחק ממשיך אצל האחרים.")
        }
        let canFinish = online == nil || online?.canFinishGame() == true
        let positive: (String, @MainActor () -> Void)
        if canFinish {
            let title = lesson ? learn("finish_lesson") : (practice ? tr("Finish challenge", "סיום האתגר") : tr("Finish game", "סיום המשחק"))
            positive = (title, { [weak self] in self?.finishFromPause() })
        } else {
            positive = (tr("Exit", "יציאה"), { [weak self] in self?.home() })
        }
        let resume: @MainActor () -> Void = { [weak self] in self?.resumeFromPause() }
        let request = SpudDialogStyle.make(title: tr("Take a break", "זמן להפסקה"), message: message, positive: positive,
                                           negative: (practice ? tr("Return to practice", "חזרה לאימון") : tr("Return to game", "חזרה למשחק"), resume),
                                           keepBack: true, onCancel: resume)
        dismissDialog(pauseDialogID)
        pauseDialogID = showDialog(request)
        pauseVisible = true
    }

    func resumeFromPause() {
        dismissDialog(pauseDialogID)
        pauseDialogID = nil
        pauseVisible = false
        guard let v = gameView else { return }
        online?.setPaused(false)
        v.engine.paused = false
        v.start()
    }

    func finishFromPause() {
        dismissDialog(pauseDialogID)
        pauseDialogID = nil
        pauseVisible = false
        guard let v = gameView else { return }
        if let practice = v.engine.practice, let me = v.engine.actor(localId) {
            _ = practice.command(v.engine, me, .end)
        } else if let room = online {
            room.endGame()
        } else {
            v.engine.finish()
        }
        v.engine.paused = false
        v.start()
    }

    /// Android `saveLocal()`: a local match also keeps who the player is and the league its result belongs to.
    private func saveLocal() {
        guard let v = gameView else { return }
        recordRank(v.engine, localId)
        guard online == nil, v.engine.result == nil else { return }
        let wrapper: [String: Any] = ["checkpoint": AmuduCodec.checkpoint(v.engine), "order": v.engine.actors.map { $0.member.id }]
        guard let json = jsonText(wrapper) else { return }
        if v.engine.practice != nil {
            defaults.set(json, forKey: Keys.practiceSaved)
            hasPracticeSaved = true
        } else {
            defaults.set(localId, forKey: Keys.savedOwn)
            defaults.set(localLeagueId, forKey: Keys.savedLeague)
            defaults.set(json, forKey: Keys.saved)
            hasSavedGame = true
        }
    }

    func scenePhaseChanged(_ phase: ScenePhase) {
        switch phase {
        case .active:
            if isForeground { return }
            isForeground = true
            online?.foreground()
            if !pauseVisible, let v = gameView {
                v.engine.paused = false
                v.start()
            }
        case .inactive, .background:
            if !isForeground { return }
            isForeground = false
            saveLocal()
            gameView?.stop()
            online?.background()
            audio.stopSpeech()
            stopCalls.stop()
        @unknown default:
            break
        }
    }

    // MARK: Status and return-vote dialogs (Android `rulesDialog`)

    /// Android `showScores()`: after a penalty, everyone sees what happened and the players and scores until the next
    /// turn starts.
    func showScores() {
        guard let v = gameView else { return }
        let e = v.engine
        if e.phase != .resolve || statusRows != nil || returnVote != nil || huddle != nil { return }
        let ordered = Kotlin.stableSorted(e.actors) { $0.penalties < $1.penalties }
        statusExplanation = v.outcomeExplanation()
        statusRows = ordered.map { a in
            StatusRow(id: a.member.id, character: a.member.character,
                      name: RuleText.name(a, localId) + (!a.active ? " · " + RuleText["watching"] : ""),
                      score: RuleText.score(a, e.config.rules))
        }
        startDialogTimer(0.15)
    }

    func closeScores() {
        statusRows = nil
    }

    /// Android `showReturnVote()`: a spectator asked to return; active humans vote while play is paused.
    func showReturnVote() {
        guard let v = gameView else { return }
        let e = v.engine
        if e.phase != .returnVote { return }
        statusRows = nil
        hideHuddle()
        guard let target = e.actor(e.returnTarget) else { return }
        let mine = e.actor(localId)
        returnVote = ReturnVoteState(title: RuleText.format(RuleText["returnVote"], RuleText.name(target, localId)),
                                     seconds: max(Kotlin.toInt(ceil(e.returnDeadline - e.time)), 0),
                                     canVote: mine?.active == true && mine?.member.bot == false, voted: e.returnVotes[localId] != nil)
        startDialogTimer(0.25)
    }

    func castReturnVote(_ yes: Bool) {
        guard let v = gameView else { return }
        v.command(.returnVote(serial: v.engine.returnSerial, yes: yes))
        refreshRulesDialog()
    }

    private func startDialogTimer(_ interval: Double) {
        dialogTimer?.invalidate()
        dialogTimer = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.refreshRulesDialog()
            }
        }
    }

    private func refreshRulesDialog() {
        guard let e = gameView?.engine else {
            dismissRulesDialog()
            return
        }
        if statusRows != nil && e.phase != .resolve { statusRows = nil }
        if var vote = returnVote {
            if e.phase != .returnVote {
                returnVote = nil
            } else {
                vote.seconds = max(Kotlin.toInt(ceil(e.returnDeadline - e.time)), 0)
                vote.voted = e.returnVotes[localId] != nil
                if vote != returnVote { returnVote = vote }
            }
        }
        if statusRows == nil && returnVote == nil {
            dialogTimer?.invalidate()
            dialogTimer = nil
        }
    }

    private func dismissRulesDialog() {
        dialogTimer?.invalidate()
        dialogTimer = nil
        statusRows = nil
        returnVote = nil
    }

    // MARK: Nickname huddle

    /// Android `showHuddle()` (2026-11): the voters see who is being named, suggest new words and vote (and may change
    /// their vote). The dialog can be closed; that huddle then stays closed.
    func showHuddle() {
        guard let e = gameView?.engine, e.phase == .huddle, huddle == nil, dismissedHuddle != e.huddleSerial else { return }
        dismissDialog(nicknameWordsID)
        nicknameWordsID = nil
        // The nickname target and anyone watching see only the neutral pause in the arena.
        if e.huddleTarget == localId || e.actor(localId)?.active != true { return }
        guard let target = e.actor(e.huddleTarget) else { return }
        huddleInput = ""
        huddle = HuddleState(serial: e.huddleSerial, naming: target.member.displayName(hebrew: hebrew),
                             current: target.suffixes.isEmpty ? nil : target.fullName(hebrew: hebrew), suffixes: target.suffixes,
                             seconds: 0, proposals: [])
        refreshHuddle()
        huddleTimer?.invalidate()
        huddleTimer = Timer.scheduledTimer(withTimeInterval: 0.2, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self else { return }
                self.refreshHuddle()
            }
        }
    }

    /// Android `refreshOnlineHuddle()`.
    func refreshOnlineHuddle() {
        if gameView?.engine.phase == .huddle { showHuddle() }
    }

    private func refreshHuddle() {
        guard let e = gameView?.engine, e.phase == .huddle, var next = huddle, e.huddleSerial == next.serial else {
            hideHuddle()
            return
        }
        let seconds: Int
        var proposals: [(String, String)] = []
        let votes: [String: String]
        if let room = online {
            seconds = room.huddleRemainingSeconds()
            let map = room.huddleSuggestions
            for key in map.keys.sorted(by: Kotlin.less) {
                if let value = map[key] { proposals.append((key, value)) }
            }
            votes = room.huddleVotes
        } else {
            seconds = max(Kotlin.toInt(ceil(e.huddleDeadline - e.time)), 0)
            for entry in e.suggestions.entries { proposals.append((entry.key, entry.value)) }
            votes = e.votes.dictionary
        }
        next.seconds = seconds
        next.proposals = proposals.map { p in
            HuddleProposal(id: p.0, name: p.1, votes: votes.values.filter { $0 == p.0 }.count, mine: votes[localId] == p.0)
        }
        if huddle != next { huddle = next }
    }

    private func hideHuddle() {
        huddleTimer?.invalidate()
        huddleTimer = nil
        if huddle != nil { huddle = nil }
        dismissDialog(nicknameWordsID)
        nicknameWordsID = nil
    }

    /// The huddle's × (Android `setOnDismissListener { dismissedHuddle = serial }`).
    func closeHuddle() {
        if let serial = huddle?.serial { dismissedHuddle = serial }
        hideHuddle()
    }

    func limitHuddleInput(_ value: String) {
        if value.utf16.count > 24 { huddleInput = String(decoding: Array(value.utf16.prefix(24)), as: UTF16.self) }
    }

    /// Android: Suggest is enabled for one valid word that nobody has proposed yet.
    var canSuggestNickname: Bool {
        let word = Kotlin.trim(huddleInput)
        guard Words.validSuggestion(word) else { return false }
        let key = Words.normalize(word)
        return !(huddle?.proposals ?? []).contains { Words.normalize($0.name) == key }
    }

    /// Android "New nickname: " + (suffixes + word).
    var huddlePreview: String? {
        let word = Kotlin.trim(huddleInput)
        if Kotlin.isBlank(word) { return nil }
        return tr("New nickname: ", "הכינוי החדש: ") + ((huddle?.suffixes ?? []) + [word]).joined(separator: " ")
    }

    func suggestNickname() {
        guard let e = gameView?.engine, canSuggestNickname else { return }
        let word = huddleInput
        if let room = online {
            room.propose(word)
        } else {
            e.propose(localId, word)
        }
        huddleInput = ""
        refreshHuddle()
    }

    /// Android "Funny-word list": the words nobody has proposed yet.
    func showFunnyWords() {
        let used = Set((huddle?.proposals ?? []).map { Words.normalize($0.name) })
        let words = funnyWords.filter { !used.contains(Words.normalize($0)) }
        dismissDialog(nicknameWordsID)
        let request = SpudDialogStyle.make(title: "", items: words, onItem: { [weak self] i in
            guard let self, i < words.count else { return }
            self.huddleInput = words[i]
        })
        nicknameWordsID = showDialog(request)
    }

    func voteFor(_ id: String) {
        guard let e = gameView?.engine else { return }
        if let room = online {
            room.vote(id)
        } else {
            e.vote(localId, id)
        }
        refreshHuddle()
    }

    // MARK: Private rooms

    private func openRoom(_ code: String?) {
        activeLeagueRound = false
        localLeagueId = ""
        online?.close()
        connectingInfo = tr("Connecting to your private room.", "מתחברים לחדר הפרטי.")
        connectingLeague = false
        screen = .connecting
        let identity = Member("", avatar, Kotlin.trim(playerName), bot: false, hebrew: hebrew, points: rankPoints)
        let net = OnlineRoom(model: self, identity: identity, config: config() ?? GameConfig.defaults, house: house)
        online = net
        net.onOpenFailed = { [weak self, weak net] text in
            guard let self, let net, self.online === net else { return }
            net.close(leave: false)
            self.online = nil
            if let code {
                self.home()
                self.joinDialog(code, text)
            } else {
                self.openSetup()
                self.status(text)
            }
        }
        net.open(join: code) { [weak self] text in
            guard let self else { return }
            self.connectingInfo = text
            self.status(text)
        }
    }

    /// Android `lobby()` (2026-11): one line per player with a portrait, the house players' quality stars or the
    /// humans' shared progress and readiness; Ready for guests; the host's Start asks before leaving out unready players.
    func lobby(code: String, players: [Member], ready: Set<String>, uid: String, host: Bool,
               onReady: @escaping @MainActor () -> Void, onStart: @escaping @MainActor () -> Void, gameConfig: GameConfig? = nil) {
        // A changed roster/readiness invalidates the old confirmation and its captured players.
        dismissDialog(lobbyWaitDialogID)
        lobbyWaitDialogID = nil
        defaults.set(code, forKey: Keys.room)
        savedRoom = code
        var lines: [LobbyPlayer] = []
        for m in players {
            var title = m.displayName(hebrew: hebrew)
            if m.id == uid { title += tr(" · You", " · אתם") }
            if !m.bot && ready.contains(m.id) { title += " ✓" }
            var qualities: [Int] = []
            var progress = ""
            var readiness = ""
            if m.bot {
                let q = AmuduCharacters.get(m.character).qualities
                qualities = [q.accuracy, q.power, q.speed, q.catching, q.jumping]
            } else {
                let points: Int? = m.id == uid ? rankPoints : m.points
                if let points {
                    let rank = ProgressRanks.at(points)
                    progress = tr("Points: ", "ניקוד: ") + String(points) + " · " + tr(rank.en, rank.he)
                } else {
                    progress = tr("Progress not shared", "ההתקדמות לא שותפה")
                }
                if m.id != uid {
                    readiness = ready.contains(m.id) ? tr("Ready ✓", "מוכנים ✓") : tr("Waiting for Ready", "ממתינים לאישור מוכנות")
                }
            }
            lines.append(LobbyPlayer(id: m.id, character: m.character, title: title, bot: m.bot, qualities: qualities,
                                     progress: progress, readiness: readiness))
        }
        let unready = players.filter { !$0.bot && $0.id != uid && !ready.contains($0.id) }.map { $0.displayName(hebrew: hebrew) }
        let capacity = gameConfig?.participants ?? count
        let note = tr("{0} players here · {1} free places. At least 2 players are required to start a game.",
                      "{0} שחקנים כאן · {1} מקומות פנויים. צריך לפחות 2 שחקנים כדי להתחיל משחק.")
            .replacingOccurrences(of: "{0}", with: String(players.count))
            .replacingOccurrences(of: "{1}", with: String(max(capacity - players.count, 0)))
        lobbyReadyPressed = false
        lobbyState = LobbyState(code: code, players: lines, host: host, ready: ready.contains(uid), canStart: players.count >= 2,
                                unready: unready, capacityNote: note, mode: gameConfig.map { RuleText.mode($0.rules) },
                                onReady: onReady, onStart: onStart)
        if screen != .lobby { screen = .lobby }
    }

    func lobbyReady() {
        guard let state = lobbyState, !lobbyReadyPressed else { return }
        lobbyReadyPressed = true
        state.onReady()
    }

    /// Android host Start: with unready players, "Waiting for players" asks whether to start without them.
    func lobbyStart() {
        guard let state = lobbyState, state.canStart else { return }
        if state.unready.isEmpty {
            state.onStart()
            return
        }
        if lobbyWaitDialogID != nil, dialogs.contains(where: { $0.id == lobbyWaitDialogID }) { return }
        let request = SpudDialogStyle.make(title: tr("Waiting for players", "ממתינים לשחקנים"),
                                           message: state.unready.joined(separator: ", ") + "\n" +
                                               tr("These players have not confirmed. Start without them?", "השחקנים האלה עדיין לא אישרו מוכנות. להתחיל בלעדיהם?"),
                                           positive: (tr("Start anyway", "להתחיל בלעדיהם"), { [weak self] in self?.online?.startWithoutUnready() }),
                                           negative: (tr("Wait", "נחכה"), {}))
        lobbyWaitDialogID = showDialog(request)
    }

    /// Android lobby back: leave the lobby and return to the setup page.
    func leaveLobby() {
        if let room = online {
            room.leaveLobby { [weak self] in
                self?.online = nil
                self?.openSetup()
            }
        } else {
            openSetup()
        }
    }

    /// Android `removedFromLobby(code)`.
    func removedFromLobby(_ code: String) {
        forgetRoom(code)
        online?.close(leave: false)
        online = nil
        openSetup()
        status(tr("The host started without you. Join the next game when you are ready.", "המארח התחיל בלעדיכם. אפשר להצטרף למשחק הבא כשתהיו מוכנים."))
    }

    /// Android `forgetRoom(code)`: "Return to room" disappears once that room is gone.
    func forgetRoom(_ code: String) {
        if defaults.string(forKey: Keys.room) == code {
            defaults.removeObject(forKey: Keys.room)
            savedRoom = nil
        }
    }

    /// Android `expiredRoom(code)`: a room that ended returns home, unless its results are on screen.
    func expiredRoom(_ code: String) {
        let showingResults = online?.hasShownResult() == true
        forgetRoom(code)
        online?.close(leave: false)
        online = nil
        if !showingResults {
            gameView?.stop()
            gameView = nil
            home()
            status(tr("This room has ended. Create a new game.", "החדר הסתיים. אפשר ליצור משחק חדש."))
        }
    }

    /// Android `offlineRoom(e, uid, code, leagueId)`: the remaining players continue locally; a league round still records
    /// its result in the league.
    func offlineRoom(_ e: AmuduEngine, uid: String, code: String, leagueId: String) {
        forgetRoom(code)
        online = nil
        localLeagueId = leagueId
        if activeLeagueRound { league?.clearActive() }
        present(e, uid: uid, network: nil)
    }

    func copyCode(_ code: String) {
        UIPasteboard.general.string = code
        status(tr("Code copied.", "הקוד הועתק."))
    }

    // MARK: Family league (Android `leaguePage`, `leagueSetup`, `openLeagueRoom`)

    /// Android `leagueIdentity()`.
    func leagueIdentity() -> Member {
        return Member("", avatar, Kotlin.trim(playerName), bot: false, hebrew: hebrew, points: rankPoints)
    }

    /// Android home "Family league".
    func openLeagueFromHome() {
        if validName() { leaguePage() }
    }

    /// Android `leaguePage()`: the family-league page (`FamilyLeagueScreen`; loading until the league answers).
    func leaguePage() {
        gameView?.stop()
        gameView = nil
        online?.close()
        online = nil
        if league == nil {
            let created = FamilyLeague(model: self)
            created.onShow = { [weak self] in self?.screen = .league }
            league = created
        }
        screen = .league
        league?.open()
    }

    /// Android `leagueSetup(create)`: the setup page for a new league (its rules and house players) or for a round (the
    /// league's saved rules and house players).
    func leagueSetup(_ create: Bool) {
        setupPurpose = create ? 1 : 2
        count = 10
        if !create, let league, let c = league.config() {
            scene = c.scene
            ball = c.ball
            freeze = c.freezeRule
            daylight = c.daylight
            wind = c.wind
            throwMode = c.throwMode
            allowGroundHit = c.allowGroundHit
            rules = c.rules
            turns = c.turns
            requireCall = c.requireCall
            stepsAfterCall = c.stepsAfterCall
            actionSeconds = c.actionSeconds
            nicknameAnswer = c.nicknameAnswer
            count = 10
            house = league.botIds
        }
        openSetup()
    }

    /// Android `openLeagueRoom(code, id, create, roundConfig)`.
    func openLeagueRoom(_ code: String, _ id: String, _ create: Bool, _ roundConfig: GameConfig? = nil) {
        activeLeagueRound = true
        localLeagueId = ""
        online?.close()
        connectingInfo = tr("Connecting to your private room.", "מתחברים לחדר הפרטי.")
        connectingLeague = true
        screen = .connecting
        let cfg = roundConfig ?? league?.config() ?? config(10) ?? GameConfig.defaults
        let net = OnlineRoom(model: self, identity: leagueIdentity(), config: cfg, house: league?.botIds ?? [], leagueId: id, fixedCode: code)
        online = net
        net.onOpenFailed = { [weak self, weak net] text in
            guard let self, let net, self.online === net else { return }
            net.close(leave: false)
            self.online = nil
            self.leaguePage()
            self.status(text)
        }
        net.open(join: create ? nil : code) { [weak self] text in
            guard let self else { return }
            self.connectingInfo = text
            self.status(text)
        }
    }

    /// Android `leagueRoomCreated()`.
    func leagueRoomCreated() {
        league?.roomCreated()
    }

    func connectingBack() {
        if connectingLeague { leaguePage() } else { home() }
    }
}

// MARK: App Store screenshots

extension AppModel {
    /// App Store captures only (SpudScreenshot): opens one screen at launch. Matches are local, seeded and offline
    /// (house players only), and nothing is saved: rank points shown on a page are staged in memory.
    func applyStoreScreenshotScene() {
        guard let scene = SpudScreenshot.value(after: "spud"), screen == .home, gameView == nil else { return }
        switch scene {
        case "home": rankPoints = 260
        case "park": playStoreMatch(.park, .foam, .noon)
        case "beach": playStoreMatch(.beach, .beach, .evening)
        case "andromeda": playStoreMatch(.andromeda, .neon, .noon)
        case "night": playStoreMatch(.park, .neon, .night)
        case "setup": openSetup()
        case "journey": openJourney(0)
        case "colors":
            rankPoints = 340
            screen = .rank
        default: break
        }
    }

    /// A six-player SPUD match against the house players. The player throws the ball up and calls Minik's name, so
    /// the capture shows the others running while Minik goes for the catch.
    private func playStoreMatch(_ arena: ArenaScene, _ kind: BallKind, _ light: Daylight) {
        scene = arena
        ball = kind
        daylight = light
        rules = .spud
        requireCall = true
        stepsAfterCall = 4
        freeze = .freeze
        throwMode = .standard
        wind = Wind.none
        turns = 20
        count = 6
        var roster = [Member("p0", avatar, AmuduCharacters.get(avatar).name(hebrew: hebrew), bot: false, hebrew: hebrew)]
        let picks = AmuduCharacters.availableBots(humans: [roster[0]], requested: ["minik", "mia", "kyra", "gaya", "flare"], fillTo: count - 1)
        for (i, id) in picks.prefix(count - 1).enumerated() {
            roster.append(Member("house\(i)", id, AmuduCharacters.get(id).name(hebrew: hebrew), bot: true, hebrew: hebrew))
        }
        guard roster.count == count, let cfg = config(roster.count),
              let engine = try? AmuduEngine(members: roster, config: cfg, seed: SpudScreenshot.seed) else { return }
        present(engine, uid: "p0", network: nil)
        if SpudScreenshot.wantsLandscape { ScreenOrientation.apply(.landscapeRight) }
        _ = afterDelay(1.5) { [weak self] in
            guard let view = self?.gameView, view.engine.phase == .circle else { return }
            view.command(.select(target: "house0"))
            view.command(.toss(power: 0.72, drift: 0.35))
        }
    }
}
