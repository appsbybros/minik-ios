import SwiftUI
import UIKit
import StoreKit

struct LobbyLine: Identifiable {
    let id: String
    let text: String
}

struct LobbyState {
    let code: String
    let lines: [LobbyLine]
    let host: Bool
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
}

struct HuddleState: Equatable {
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
}

struct RosterEntry: Identifiable {
    let id: String
    let name: String
}

/// The text handed to the system share sheet (Android `Intent.createChooser`).
struct ShareText: Identifiable {
    let id = UUID()
    let text: String
}

/// Android `AmuduActivity`: screens, saved settings, the local/online game lifecycle, the daily skill journey, colour
/// ranks, dialogs, sounds and speech. Ads, purchases and code redemption are not part of the iOS app; the family
/// "More Minik apps & games" card is (the shared Family module), without its ad-break promotion and reminder.
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
        case support
        case rank
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
        static let wind = "amudu.wind"
        static let room = "amudu.room"
        static let saved = "amudu.saved"
        static let ruleSet = "amudu.ruleSet"
        static let colourPoints = "amudu.colourPoints"
        static let rankReceipts = "amudu.rankReceipts"
        static let skillJourney = "amudu.skillJourney"
        static let practiceSaved = "amudu.practiceSaved"
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
    @Published var wind: Wind
    @Published var rules: RuleSet
    @Published var requireCall = false
    @Published var stepsAfterCall = 0
    @Published var actionSeconds = 30
    @Published private(set) var house: [String]
    @Published var environmentOpen = false
    @Published var advancedOpen = false
    @Published var connectingInfo = ""
    @Published private(set) var lobbyState: LobbyState?
    @Published private(set) var results: [ResultRow] = []
    @Published private(set) var resultTitle = ""
    @Published var pauseVisible = false
    @Published private(set) var pauseMessage = ""
    @Published var nicknameVisible = false
    @Published var nicknameInput = ""
    @Published var sayVisible = false
    @Published var rosterVisible = false
    @Published private(set) var rosterCandidates: [RosterEntry] = []
    @Published var joinVisible = false
    @Published var joinInput = ""
    @Published private(set) var huddle: HuddleState?
    @Published var huddleInput = ""
    @Published var wordListVisible = false
    @Published private(set) var statusRows: [StatusRow]?
    @Published private(set) var returnVote: ReturnVoteState?
    @Published private(set) var savedRoom: String?
    @Published private(set) var hasSavedGame = false
    @Published private(set) var hasPracticeSaved = false
    @Published private(set) var gameView: ArenaView?
    @Published private(set) var sceneLoading = false
    @Published private(set) var rankPoints = 0
    @Published private(set) var journeyStep = 0
    @Published private(set) var journeyOutcome: JourneyOutcome?
    @Published private(set) var sections: [String: Bool] = [:]
    @Published var gateVisible = false
    @Published var gateInput = ""
    @Published private(set) var gateQuestion = ""
    @Published var shareVisible = false
    @Published var shareInput = ""
    @Published var feedbackVisible = false
    @Published var feedbackInput = ""
    @Published var shareSheet: ShareText?
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
    private let defaults: UserDefaults
    private var localId = "p0"
    private var nicknameTarget = ""
    private var huddleTimer: Timer?
    private var dialogTimer: Timer?
    private var toastToken = 0
    private var isForeground = true
    private var gateAnswer = 0
    private var gateAction: (@MainActor () -> Void)?

    var hebrew: Bool { return AppText.language == "he" }

    init() {
        art = ArtStore()
        audio = GameAudio()
        stopCalls = HebrewStopCalls()
        let d = UserDefaults.standard
        defaults = d
        let storedAvatar = d.string(forKey: Keys.avatar) ?? "miniko"
        avatar = AmuduCharacters.exists(storedAvatar) ? storedAvatar : "miniko"
        playerName = d.string(forKey: Keys.name) ?? ""
        scene = ArenaScene(rawValue: d.string(forKey: Keys.scene) ?? "PARK") ?? .park
        ball = BallKind(rawValue: d.string(forKey: Keys.ball) ?? "FOAM") ?? .foam
        freeze = FreezeRule(rawValue: d.string(forKey: Keys.freeze) ?? "FREEZE") ?? .freeze
        let storedCount = (d.object(forKey: Keys.count) as? Int) ?? 6
        count = min(max(storedCount, 2), 10)
        let storedTurns = (d.object(forKey: Keys.turns) as? Int) ?? 0
        turns = [0, 10, 20, 35, 50].contains(storedTurns) ? storedTurns : 0
        daylight = Daylight(rawValue: d.string(forKey: Keys.daylight) ?? "NOON") ?? .noon
        throwMode = ThrowMode(rawValue: d.string(forKey: Keys.throwMode) ?? "STANDARD") ?? .standard
        wind = Wind(rawValue: d.string(forKey: Keys.wind) ?? "NONE") ?? Wind.none
        house = AppModel.validHouse(d.stringArray(forKey: Keys.house) ?? ["minik", "kyra", "flare"])
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

    // MARK: Home

    func home() {
        saveLocal()
        gameView?.stop()
        stopCalls.stop()
        gameView = nil
        online?.close()
        online = nil
        pauseVisible = false
        nicknameVisible = false
        sayVisible = false
        rosterVisible = false
        sceneLoading = false
        hideHuddle()
        dismissRulesDialog()
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

    func openSetup() {
        house.removeAll { $0 == avatar }
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
        if validName() {
            joinInput = ""
            joinVisible = true
        }
    }

    func returnToRoom(_ code: String) {
        if validName() { openRoom(code) }
    }

    func join() {
        let code = Kotlin.trim(joinInput).uppercased()
        let upper: ClosedRange<Unicode.Scalar> = "A"..."Z"
        let digits: ClosedRange<Unicode.Scalar> = "2"..."9"
        let valid = code.unicodeScalars.count == 6 && code.unicodeScalars.allSatisfy { upper.contains($0) || digits.contains($0) }
        if valid {
            openRoom(code)
        } else {
            status(tr("Enter the six-character room code.", "הזינו קוד חדר בן שישה תווים."))
        }
    }

    func continueSaved() {
        restore(Keys.saved)
    }

    func continuePractice() {
        restore(Keys.practiceSaved)
    }

    private func restore(_ key: String) {
        guard let json = defaults.string(forKey: key),
              let data = json.data(using: .utf8),
              let wrapper = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
              let engine = try? AmuduCodec.create(AmuduCodec.node(wrapper["checkpoint"]), order: wrapper["order"] as? [String]) else {
            status(tr("Saved game could not be restored.", "לא ניתן לשחזר את המשחק."))
            return
        }
        present(engine, uid: "p0", network: nil)
    }

    /// Android "More Minik apps & games": the family card, its links behind the grown-up gate.
    func moreApps() {
        FamilyMessages.shared.showMoreApps(gate: { [weak self] action in self?.parentGate(action) })
    }

    // MARK: Grown-up gate (Android `parentGate`)

    func parentGate(_ action: @escaping @MainActor () -> Void) {
        let a = Int.random(in: 4...9)
        let b = Int.random(in: 3...8)
        gateAnswer = a * b
        gateQuestion = "\u{2066}\(a) × \(b) = ?\u{2069}"
        gateInput = ""
        gateAction = action
        gateVisible = true
    }

    func confirmGate() {
        let action = gateAction
        gateAction = nil
        if Int(Kotlin.trim(gateInput)) == gateAnswer {
            action?()
        } else {
            status(tr("Try again.", "נסו שוב."))
        }
    }

    func cancelGate() {
        gateAction = nil
    }

    // MARK: Settings & feedback (Android `supportPage`)

    func rateApp() {
        // Android opens the store listing; iOS asks the App Store for its own rating prompt.
        guard let scene = UIApplication.shared.connectedScenes.compactMap({ $0 as? UIWindowScene })
            .first(where: { $0.activationState == .foregroundActive }) else { return }
        AppStore.requestReview(in: scene)
    }

    func openShare() {
        shareInput = tr("Come play with me! ", "בואו לשחק איתי! ") + AppModel.storeLink
        shareVisible = true
    }

    func shareMessage() {
        shareSheet = ShareText(text: shareInput)
    }

    func openFeedback() {
        feedbackInput = ""
        feedbackVisible = true
    }

    func sendFeedback() {
        if Kotlin.isBlank(feedbackInput) { return }
        var mail = URLComponents()
        mail.scheme = "mailto"
        mail.path = "appsbybros.dev@gmail.com"
        mail.queryItems = [URLQueryItem(name: "subject", value: "Game feedback"),
                           URLQueryItem(name: "body", value: feedbackInput + "\n\n" + AppModel.storeLink)]
        guard let url = mail.url else { return }
        UIApplication.shared.open(url) { [weak self] opened in
            MainActor.assumeIsolated {
                guard let self, !opened else { return }
                self.status(self.tr("No app is available to open this link.", "אין אפליקציה זמינה לפתיחת הקישור."))
            }
        }
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

    // MARK: Daily skill journey

    /// Android `LocalDate.now().toString()`.
    static func today() -> String {
        let f = DateFormatter()
        f.calendar = Calendar(identifier: .gregorian)
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = TimeZone.current
        f.dateFormat = "yyyy-MM-dd"
        return f.string(from: Date())
    }

    func journeyProgress() -> SpudProgress {
        let j = jsonObject(defaults.string(forKey: Keys.skillJourney))
        let completed = max(AmuduCodec.number(j["completed"]).map { Kotlin.toInt($0) } ?? 0, 0)
        let points = AmuduCodec.number(j["points"]).map { Kotlin.toInt($0) } ?? 0
        let bonusDay = (j["bonusDay"] as? String) ?? ""
        let receipts = AmuduCodec.items(j["receipts"]).map { AmuduCodec.text($0) }
        return SpudProgress(completed: completed, points: points, bonusDay: bonusDay, receipts: receipts)
    }

    /// Android `journeyPage(step = progress.completed)`.
    func openJourney(_ step: Int? = nil) {
        gameView?.stop()
        journeyStep = step ?? journeyProgress().completed
        hasPracticeSaved = defaults.string(forKey: Keys.practiceSaved) != nil
        screen = .journey
    }

    /// Android `startJourney(step)`: the player with the challenge's partners or throwers on a 16 m park court.
    func startJourney(_ step: Int) {
        let d = SpudPractice(step)
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
        guard let cfg = try? GameConfig(scene: .park, ball: .foam, participants: members.count, width: 16.0, depth: 16.0, rules: .spud,
                                        actionSeconds: 0, challengeStep: step),
              let engine = try? AmuduEngine(members: members, config: cfg, seed: seed) else { return }
        present(engine, uid: "p0", network: nil)
    }

    private func journeyResult(_ e: AmuduEngine, _ r: Outcome) {
        guard let d = e.practice else { return }
        let won = r.winners.contains(localId)
        let old = journeyProgress()
        let next = old.finish(r.id, d.step, won, AppModel.today())
        if next != old {
            let j: [String: Any] = ["completed": next.completed, "points": next.points, "bonusDay": next.bonusDay, "receipts": next.receipts]
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
        journeyOutcome = JourneyOutcome(won: won, stage: d.stage, successes: d.successes, goal: d.goal, gained: next.points - old.points, next: following)
        screen = .journeyResult
    }

    // MARK: Setup

    private func config(_ n: Int? = nil) -> GameConfig? {
        return try? GameConfig(scene: scene, ball: ball, freezeRule: freeze, participants: n ?? count, turns: turns, width: 28.0, depth: 18.0,
                               daylight: daylight, throwMode: throwMode, wind: wind, rules: rules, requireCall: requireCall,
                               stepsAfterCall: stepsAfterCall, actionSeconds: actionSeconds, stepLengthFraction: 0.5 / 18.0)
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
        if let c {
            scene = c.scene
            ball = c.ball
            freeze = c.freezeRule
            count = c.participants
            turns = c.turns
            daylight = c.daylight
            throwMode = c.throwMode
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
        environmentOpen = false
        advancedOpen = false
    }

    func setHouse(_ id: String, _ selected: Bool) {
        if selected {
            if !house.contains(id) { house.append(id) }
        } else {
            house.removeAll { $0 == id }
        }
        persist()
    }

    func startLocal() {
        persist()
        var roster = [Member("p0", avatar, AmuduCharacters.get(avatar).name(hebrew: hebrew), bot: false, hebrew: hebrew)]
        let chosen = Array(AmuduCharacters.availableBots(humans: [roster[0]], requested: house, fillTo: count - 1).prefix(max(count - 1, 0)))
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
        if house.count >= count {
            status(tr("Leave a place for yourself.", "השאירו מקום לעצמכם."))
        } else {
            openRoom(nil)
        }
    }

    // MARK: Game

    func present(_ e: AmuduEngine, uid: String, network: OnlineRoom?) {
        ScreenOrientation.apply(ScreenOrientation.battle(defaults.string(forKey: Keys.battleOrientation)))
        gameView?.stop()
        localId = uid
        e.paused = false
        pauseVisible = false
        nicknameVisible = false
        sayVisible = false
        rosterVisible = false
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
            if view.engine.config.rules == .spud || a.suffixes.isEmpty {
                view.command(.select(target: a.member.id))
            } else {
                self.nicknameTarget = a.member.id
                self.nicknameInput = ""
                self.nicknameVisible = true
            }
        }
        view.onRoster = { [weak self, weak view] in
            guard let self, let view else { return }
            self.rosterCandidates = view.engine.activeActors.filter { $0.member.id != uid }.map {
                RosterEntry(id: $0.member.id, name: $0.fullName(hebrew: self.hebrew))
            }
            self.rosterVisible = true
        }
        view.onSay = { [weak self] in self?.sayVisible = true }
        gameView = view
        network?.attach(view)
        screen = .game
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

    var sayPhrases: [String] {
        return hebrew ? Words.phrasesHe : Words.phrasesEn.map { AppText.t($0) }
    }

    var funnyWords: [String] {
        return hebrew ? Words.he : Words.en
    }

    func say(_ index: Int) {
        gameView?.command(.say(index: index))
    }

    func callWithNickname() {
        nicknameVisible = false
        gameView?.command(.select(target: nicknameTarget, typedName: nicknameInput))
    }

    /// Android roster dialog: choosing a player works like tapping them.
    func choose(_ id: String) {
        guard let v = gameView, let a = v.engine.actor(id) else { return }
        v.onChoose?(a)
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
            audio.speak(english ? AmuduCharacters.get(a.member.character).en : a.fullName(hebrew: hebrew), english: english)
        case "renamed":
            if e.actor != localId {
                let name = gameView?.engine.actor(e.actor)?.fullName(hebrew: hebrew) ?? e.text
                status(tr("Remember: ", "זכרו: ") + name)
                audio.speak(name)
            }
        case "freeze":
            if let recorded {
                audio.stopSpeech()
                stopCalls.play(recorded)
            } else {
                audio.speak(RuleText.call(gameView?.engine.config.rules ?? .nicknames), english: AppText.language == "hi")
            }
        case "say":
            let i = Int(e.text) ?? 0
            let list = hebrew ? Words.phrasesHe : Words.phrasesEn
            audio.speak(AppText.t(i >= 0 && i < list.count ? list[i] : ""))
        default:
            break
        }
    }

    private func result(_ r: Outcome) {
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
        pauseVisible = false
        rosterVisible = false
        if e.practice != nil {
            journeyResult(e, r)
            return
        }
        resultTitle = e.config.rules == .spud ? RuleText["lastStanding"] : tr("Fewest penalties wins", "מנצחים עם הכי מעט נקודות חובה")
        let ordered = Kotlin.stableSorted(e.actors) { $0.penalties < $1.penalties }
        results = ordered.map { a in
            ResultRow(id: a.member.id, character: a.member.character, name: RuleText.name(a, localId), score: RuleText.score(a, e.config.rules),
                      winner: r.winners.contains(a.member.id))
        }
        screen = .result
    }

    /// Android `back()`: the last active human of a room pauses it for everyone; a local game pauses and is saved.
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
        pauseMessage = (online == nil || v.engine.sharedPause) ? tr("Your game is paused.", "המשחק מושהה.")
            : tr("The game continues for the others.", "המשחק ממשיך אצל האחרים.")
        pauseVisible = true
    }

    func resumeFromPause() {
        pauseVisible = false
        guard let v = gameView else { return }
        online?.setPaused(false)
        v.engine.paused = false
        v.start()
    }

    func finishFromPause() {
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

    /// Android `showScores()`: after a penalty, everyone sees the players and scores until the next turn starts.
    func showScores() {
        guard let v = gameView else { return }
        let e = v.engine
        if e.phase != .resolve || statusRows != nil || returnVote != nil || huddle != nil { return }
        let ordered = Kotlin.stableSorted(e.actors) { $0.penalties < $1.penalties }
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

    func showHuddle() {
        guard let e = gameView?.engine, e.phase == .huddle, huddle == nil else { return }
        // The nickname target and anyone watching see only the neutral pause in the arena.
        if e.huddleTarget == localId || e.actor(localId)?.active != true { return }
        huddleInput = Words.suggestion(Int.random(in: 0...5), hebrew: hebrew)
        huddle = HuddleState(seconds: 0, proposals: [])
        refreshHuddle()
        huddleTimer?.invalidate()
        huddleTimer = Timer.scheduledTimer(withTimeInterval: 0.35, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self else { return }
                self.refreshHuddle()
            }
        }
    }

    private func refreshHuddle() {
        guard let e = gameView?.engine, e.phase == .huddle else {
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
        let list = proposals.map { p in HuddleProposal(id: p.0, name: p.1, votes: votes.values.filter { $0 == p.0 }.count) }
        let next = HuddleState(seconds: seconds, proposals: list)
        if huddle != next { huddle = next }
    }

    private func hideHuddle() {
        huddleTimer?.invalidate()
        huddleTimer = nil
        if huddle != nil { huddle = nil }
        wordListVisible = false
    }

    func limitHuddleInput(_ value: String) {
        if value.utf16.count > 24 { huddleInput = String(decoding: Array(value.utf16.prefix(24)), as: UTF16.self) }
    }

    func suggestNickname() {
        guard let e = gameView?.engine else { return }
        let text = huddleInput
        if !Words.validSuggestion(text) {
            status(tr("Write one word using letters and optional numbers, up to 24 characters.", "כתבו מילה אחת באותיות, ואפשר גם מספרים, עד 24 תווים."))
            return
        }
        if let room = online {
            room.propose(text)
        } else {
            e.propose(localId, text)
        }
        refreshHuddle()
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
        online?.close()
        connectingInfo = tr("Connecting to your private room.", "מתחברים לחדר הפרטי.")
        screen = .connecting
        let identity = Member("", avatar, Kotlin.trim(playerName), bot: false, hebrew: hebrew)
        let net = OnlineRoom(model: self, identity: identity, config: config() ?? GameConfig.defaults, house: house)
        online = net
        net.open(join: code) { [weak self] text in
            guard let self else { return }
            self.connectingInfo = text
            self.status(text)
        }
    }

    func lobby(code: String, players: [Member], ready: Set<String>, uid: String, host: Bool,
               onReady: @escaping @MainActor () -> Void, onStart: @escaping @MainActor () -> Void, gameConfig: GameConfig? = nil) {
        defaults.set(code, forKey: Keys.room)
        savedRoom = code
        var lines: [LobbyLine] = []
        for m in players {
            var text = m.displayName(hebrew: hebrew)
            if m.id == uid { text += tr(" · You", " · אתם") }
            text += ready.contains(m.id) ? " ✓" : tr(" · Not ready", " · עדיין לא מוכנים")
            lines.append(LobbyLine(id: m.id, text: text))
        }
        lobbyState = LobbyState(code: code, lines: lines, host: host, mode: gameConfig.map { RuleText.mode($0.rules) }, onReady: onReady,
                                onStart: onStart)
        if screen != .lobby { screen = .lobby }
    }

    func copyCode(_ code: String) {
        UIPasteboard.general.string = code
        status(tr("Code copied.", "הקוד הועתק."))
    }
}
