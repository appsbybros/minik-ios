import StoreKit
import SwiftUI
import UIKit

/// Port of Android SplashActivity.kt: menu flow (home sections, Play menu, wall battles, house
/// players, the daily paint journey), tutorial, persistence, cups, colour ranks, online rooms,
/// pause and lifecycle. Ads, purchases, code redemption and the family-services module (more apps,
/// family reminders) are not part of the iOS build.
enum SplashScreen: Equatable {
    case home, settings, subjects, support, parentZone, progress, ranks, play, wallOptions, journey, journeyResult, join, house, lobby, results, game
}

struct ResultPlayerRow: Identifiable {
    let id: String
    let character: String
    let name: String
    let score: Int
    let ink: UInt32
    /// Solo results: 0, 1, 2 wear gold, silver and bronze (-1 otherwise).
    var rank = -1
}

struct ResultTeamPanel: Identifiable {
    let id: Int
    let name: String
    let subtitle: String
    let color: UInt32
    let ink: UInt32
    let rows: [ResultPlayerRow]
}

struct ResultsModel {
    let title: String
    let teams: [ResultTeamPanel]
    let rows: [ResultPlayerRow]
    /// The wall-battle or team-score note.
    let note: String?
    let correctLine: String
    /// "Your answer still counts when a throw misses." (not in Paint walls).
    let countsLine: String?
    let onlineCup: Bool
    let nextRound: Bool
    let cupLine: String?
    let cupStandings: String?
    let nextBattle: Bool
    let playAgain: Bool
}

/// Android `challengePage(step)`.
struct JourneyPageModel {
    let opponent: String
    let header: String
    let stageLine: String
    let stageColor: UInt32
    let bonusLine: String
    let title: String
    let goal: String
    let drillGoal: String?
    let introduction: String
    let qualities: String
    let step: Int
    let stage: Int
    let steps: [String]
}

/// Android `challengeResults(e, r)`.
struct JourneyResultModel {
    let title: String
    let won: Bool
    let kind: String
    let progress: String
    let score: String?
    let button: String
    let nextStep: Int
}

struct LobbyPlayer: Identifiable, Equatable {
    let id: String
    let name: String
    let character: String
}

/// Android `lobby(code, players, readyIds, house, limit, teams, hosted, self, ...)`.
struct LobbyModel {
    let code: String
    let humans: [LobbyPlayer]
    let readyIds: Set<String>
    var house: [String]
    let limit: Int
    let teams: Bool
    let hosted: Bool
    let selfId: String
}

struct ToastMessage: Identifiable, Equatable {
    let id = UUID()
    let text: String
    let long: Bool
}

struct ParentGateModel: Equatable {
    let a: Int
    let b: Int
}

struct ShareText: Identifiable {
    let id = UUID()
    let text: String
}

@MainActor
final class SplashController: ObservableObject {
    @Published private(set) var screen: SplashScreen = .home {
        didSet {
            // Android `page()` asks for portrait; a battle uses the game orientation.
            if screen != .game { SplashOrientation.apply(SplashOrientation.page) }
        }
    }
    @Published var toast: ToastMessage?
    @Published var pausePresented = false
    /// Android `leaveCupScreen()`: the Save / Don't save / Cancel choice for a cup.
    @Published private(set) var cupExitPresented = false
    @Published var gate: ParentGateModel?
    @Published var gateAnswer = ""
    @Published private(set) var results: ResultsModel?
    @Published private(set) var journey: JourneyPageModel?
    @Published private(set) var journeyResult: JourneyResultModel?
    @Published private(set) var lobbyModel: LobbyModel?
    @Published private(set) var standings = ""
    @Published private(set) var settings = PlayerSettings()
    @Published private(set) var selected = "miniko"
    @Published private(set) var format = 0
    @Published private(set) var count = 6
    @Published private(set) var selectedHouse: [String] = []
    @Published private(set) var upcomingCount: Int?
    @Published private(set) var upcomingArena: Arena?
    @Published private(set) var upcomingRounds = 1
    /// Android `playMode`: the Play page's game mode (0 single, 1 2 x 2, 2 3 x 3, 3 and 4 Paint walls
    /// 2 x 2 and 3 x 3; the Pro edition allows up to 7), saved with the arena and the number of rounds.
    @Published private(set) var playMode = 0
    @Published private(set) var hitEffect: HitEffect = .cosmetic
    @Published var gameSounds = true {
        didSet {
            SplashPrefs.setBool(gameSounds, "gameSounds")
            sounds.enabled = gameSounds
        }
    }
    @Published var roomCode = ""
    @Published var shareVisible = false
    @Published var shareInput = ""
    @Published var feedbackVisible = false
    @Published var feedbackInput = ""
    @Published var shareSheet: ShareText?

    private(set) var gameView: SplashArenaView?
    let art = ArtStore.shared
    private let sounds = SplashSounds()
    private let music = MenuMusic(announceLaunch: true)
    private let speech = SplashSpeech()
    private let localStore = LocalBattleStore()
    private(set) var hebrew = false
    private var topic: Topic = .math
    private var learningSession = false
    private var parentPage = false
    private var chosenRoster: [String]?
    private(set) var cupLength = 3
    private var battleReady = false
    private var foreground = false
    private(set) var wallBattle = false
    private var cupRound = 0
    private var cupScores: [String: Int] = [:]
    private var cup = false
    private var atHome = false
    private var cupRoster: [Member]?
    private var network: OnlineSession?
    private var gateAction: (() -> Void)?
    private var lobbyReady: (() -> Void)?
    private var lobbyChange: (([String]) -> Void)?
    private var lobbyRemove: ((String) -> Void)?
    private var lobbyStart: ((Bool) -> Void)?
    private(set) var houseCupGame = false
    private(set) var joinCupGame = false
    private var lifecyclePaused = false
    private var memoryObserver: NSObjectProtocol?
    /// Android DEBUG-only QA exhibitions; never enabled on iOS.
    private let qa = false
    /// App Store captures only (SplashScreenshot): a seeded battle in which the player is a house player too.
    private var storeDemo = false

    /// The public page of the game (Android shares its Play listing; the iOS listing has no link yet).
    static let storeLink = "https://miniklearn.com/apps/minik-splash/"

    init() {
        AppText.configure(Locale.preferredLanguages.first ?? "en")
        hebrew = AppText.language == "he"
        // Android `FamilyMessages.get(this).setLanguage(AppText.language)`.
        FamilyMessages.shared.languageOverride = AppText.language
        if let node = NodeJSON.node(SplashPrefs.string("playerSettings") ?? "{}") { settings = WorldCodec.settings(node) }
        // Every battle has a court now (Android 2026-10-15).
        settings.court = true
        hitEffect = HitEffect(rawValue: SplashPrefs.string("hitEffect") ?? "COSMETIC") ?? .cosmetic
        selectedHouse = SplashPrefs.stringSet("housePlayers")
        selected = SplashPrefs.string("character") ?? (SplashLaunch.proEdition ? "mia" : "miniko")
        format = min(max(SplashPrefs.int("format", 0), 0), 2)
        loadPlayChoices()
        count = min(max(SplashPrefs.int("count", 6), 2), 6)
        topic = Topic(rawValue: SplashPrefs.string("topic") ?? "MATH") ?? .math
        gameSounds = SplashPrefs.bool("gameSounds", true)
        sounds.enabled = gameSounds
        memoryObserver = NotificationCenter.default.addObserver(forName: UIApplication.didReceiveMemoryWarningNotification, object: nil, queue: .main) { _ in
            Task { @MainActor in ArtStore.shared.purge() }
        }
        home()
    }

    func tr(_ en: String, _ he: String) -> String { return AppText.t(en, he, hebrew: hebrew) }

    func showToast(_ text: String, long: Bool = false) {
        toast = ToastMessage(text: text, long: long)
    }

    /// Android `message(text)`: a long toast.
    private func message(_ text: String) {
        showToast(text, long: true)
    }

    // MARK: Pages

    private func showPage(_ next: SplashScreen) {
        atHome = false
        gameView?.teardown()
        gameView = nil
        music.setMenu(true)
        pausePresented = false
        cupExitPresented = false
        screen = next
    }

    func home() {
        if let v = gameView {
            recordRank(v.engine, v.localId)
            if network == nil && !qa { localStore.save(v.engine, cupRound: cupRound, cupScores: cupScores, cup: cup, cupLength: cupLength) }
        }
        gameView?.stop()
        network?.close()
        network = nil
        cup = false
        learningSession = false
        parentPage = false
        upcomingCount = nil
        loadPlayChoices()
        format = SplashController.format(playMode)
        showPage(.home)
        atHome = true
    }

    /// Android: the saved Play choices ("playArena", "playRounds", "playMode") and the Paint walls flag.
    private func loadPlayChoices() {
        let arena = SplashPrefs.int("playArena", settings.arena.ordinal)
        upcomingArena = arena >= 0 && arena < Arena.allCases.count ? Arena.allCases[arena] : nil
        let rounds = SplashPrefs.int("playRounds", 1)
        upcomingRounds = [1, 3, 5].contains(rounds) ? rounds : 1
        playMode = min(max(SplashPrefs.int("playMode", 0), 0), SplashLaunch.proEdition ? 7 : 4)
        wallBattle = playMode >= (SplashLaunch.proEdition ? 6 : 3)
    }

    /// Android `format = when(playMode) { 0 -> 0; 3, 6 -> 1; 4, 7 -> 2; else -> playMode }`.
    private static func format(_ mode: Int) -> Int {
        switch mode {
        case 0: return 0
        case 3, 6: return 1
        case 4, 7: return 2
        default: return mode
        }
    }

    /// Android `FamilyMenu.section`: open state per title ("family_menu_sections"); the first two start open.
    func sectionOpen(_ title: String, _ index: Int) -> Bool {
        return SplashPrefs.bool(title, index < 2, file: "family_menu_sections")
    }

    func toggleSection(_ title: String, _ index: Int) {
        objectWillChange.send()
        SplashPrefs.setBool(!sectionOpen(title, index), title, file: "family_menu_sections")
    }

    var hasSavedBattle: Bool { return localStore.hasBattle() }
    var hasSavedCup: Bool { return SplashPrefs.string("cupState") != nil }
    var savedRoom: String? { return SplashPrefs.onlineRoom }
    var teacherId: String { return SplashLaunch.proEdition ? "mia" : "minik" }

    func openSettings() { showPage(.settings) }

    func openSubjects() { showPage(.subjects) }

    func openSupport() { showPage(.support) }

    func openParentZone() {
        showPage(.parentZone)
        parentPage = true
    }

    func openProgress() { showPage(.progress) }
    func openRanks() { showPage(.ranks) }

    /// Android `avatarPicker.shift(delta)`.
    func shiftCharacter(_ delta: Int) {
        let ids = Characters.all.map { $0.id }
        let index = ids.firstIndex(of: selected) ?? -1
        selected = ids[((index + delta) % ids.count + ids.count) % ids.count]
        SplashPrefs.setString(selected, "character")
    }

    // MARK: Colour ranks

    func rankPoints() -> Int { return SplashPrefs.int("colourPoints", 0) }

    /// Android `recordRank`: every battle pays its points once (receipts per battle and player).
    private func recordRank(_ e: SplashEngine, _ id: String) {
        if e.config.challenge != nil { return }
        if e.practice || qa { return }
        guard let a = e.actor(id) else { return }
        let key = e.matchId + ":" + id
        var ledger = NodeJSON.node(SplashPrefs.string("rankReceipts") ?? "{}") ?? [:]
        let earned = SplashRanks.earned(a)
        let previous = KotlinNumber.int(ledger.num(key))
        if earned <= previous { return }
        ledger[key] = earned
        SplashPrefs.setInt(rankPoints() + earned - previous, "colourPoints")
        SplashPrefs.setString(NodeJSON.string(ledger), "rankReceipts")
    }

    // MARK: Settings

    private func saveSettings(_ value: PlayerSettings) {
        settings = value
        SplashPrefs.setString(NodeJSON.string(WorldCodec.settings(value)), "playerSettings")
    }

    func setDifficulty(_ index: Int) {
        var next = settings
        next.difficulty = Difficulty.allCases[min(max(index, 0), Difficulty.allCases.count - 1)]
        saveSettings(next)
    }

    func setWalk(_ index: Int) {
        var next = settings
        next.walk = WalkMode.allCases[min(max(index, 0), WalkMode.allCases.count - 1)]
        saveSettings(next)
    }

    func setThrowing(_ index: Int) {
        var next = settings
        next.throwing = ThrowMode.allCases[min(max(index, 0), ThrowMode.allCases.count - 1)]
        saveSettings(next)
    }

    func setBalloons(_ index: Int) {
        var next = settings
        next.balloons = BalloonMode.allCases[min(max(index, 0), BalloonMode.allCases.count - 1)]
        saveSettings(next)
    }

    /// Tapping a subject moves it to the other list; at least one stays chosen.
    func tapSubject(_ topic: Topic, chosen: Bool) {
        var next = settings.subjects
        if chosen { next.remove(topic) } else { next.insert(topic) }
        if next.isEmpty {
            showToast(tr("Choose at least one subject.", "בחרו לפחות נושא אחד."))
            return
        }
        var updated = settings
        updated.subjects = next
        saveSettings(updated)
    }

    /// Dropping a subject on a list (Android drag-and-drop transfer).
    func dropSubject(_ topic: Topic, intoChosen: Bool) {
        var next = settings.subjects
        if intoChosen { next.insert(topic) } else { next.remove(topic) }
        if next.isEmpty {
            showToast(tr("Choose at least one subject.", "בחרו לפחות נושא אחד."))
            return
        }
        var updated = settings
        updated.subjects = next
        saveSettings(updated)
    }

    // MARK: Support (Android `supportPage`)

    func rateApp() {
        // Android opens the store listing; iOS asks the App Store for its own rating prompt.
        guard let scene = UIApplication.shared.connectedScenes.compactMap({ $0 as? UIWindowScene })
            .first(where: { $0.activationState == .foregroundActive }) else { return }
        AppStore.requestReview(in: scene)
    }

    func openShare() {
        shareInput = tr("Come play with me! ", "בואו לשחק איתי! ") + SplashController.storeLink
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
        if feedbackInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { return }
        var mail = URLComponents()
        mail.scheme = "mailto"
        mail.path = "appsbybros.dev@gmail.com"
        mail.queryItems = [URLQueryItem(name: "subject", value: "Game feedback"),
                           URLQueryItem(name: "body", value: feedbackInput + "\n\n" + SplashController.storeLink)]
        guard let url = mail.url else { return }
        UIApplication.shared.open(url) { [weak self] opened in
            MainActor.assumeIsolated {
                guard let self, !opened else { return }
                self.message(self.tr("No app is available to open this link.", "אין אפליקציה זמינה לפתיחת הקישור."))
            }
        }
    }

    /// Android "More Minik apps & games": the family card, its links behind the parent gate.
    func moreApps() {
        FamilyMessages.shared.showMoreApps(gate: { [weak self] action in self?.requestParentGate(action) })
    }

    // MARK: Parent gate

    func requestParentGate(_ action: @escaping () -> Void) {
        gateAnswer = ""
        gateAction = action
        gate = ParentGateModel(a: Int.random(in: 4...9), b: Int.random(in: 3...8))
    }

    func confirmGate(_ model: ParentGateModel) {
        let action = gateAction
        let answer = gateAnswer.trimmingCharacters(in: .whitespaces)
        gate = nil
        gateAction = nil
        if Int(answer) == model.a * model.b {
            action?()
        } else {
            showToast(tr("Please try again.", "נסו שוב."))
        }
    }

    func cancelGate() {
        gate = nil
        gateAction = nil
    }

    // MARK: Play menu

    /// Android `seats()`: the chosen player count, else the format's.
    func seats() -> Int {
        if let upcoming = upcomingCount { return upcoming }
        return format == 1 ? 4 : (format == 2 ? 6 : count)
    }

    private var matchSettings: PlayerSettings {
        var s = settings
        s.arena = upcomingArena ?? settings.arena
        s.court = true
        return s
    }

    /// Android `MAX_HOUSE_PLAYERS`.
    static let maxHousePlayers = 6

    /// Android `playMenu()`: arena, game mode (Paint walls adds the hit rule) and number of rounds, saved
    /// for the next visit; then Create room, Join room or House players only.
    func playMenu() {
        // Solo rooms use the roster picker/lobby rather than an inaccessible saved player count.
        if playMode == 0 { upcomingCount = SplashController.maxHousePlayers }
        showPage(.play)
    }

    /// Android: the hit rule shows for the Paint walls modes.
    var hitOptionsVisible: Bool { return playMode >= (SplashLaunch.proEdition ? 6 : 3) }

    func setPlayMode(_ mode: Int) {
        playMode = mode
        SplashPrefs.setInt(mode, "playMode")
        wallBattle = mode >= 3
        switch mode {
        case 0: format = 0
        case 3: format = 1
        case 4: format = 2
        default: format = mode
        }
        upcomingCount = mode == 0 ? SplashController.maxHousePlayers : (format + 1) * 2
    }

    func continueBattle() {
        guard let saved = localStore.load() else { return }
        cup = saved.cup
        cupLength = saved.cupLength
        cupRound = saved.round
        cupScores = saved.scores
        cupRoster = saved.cup ? saved.engine.members : nil
        present(saved.engine, localId: "p0")
    }

    func continueCup() {
        guard let text = SplashPrefs.string("cupState") else { return }
        restoreCup(text)
    }

    func setUpcomingArena(_ index: Int) {
        let i = min(max(index, 0), Arena.allCases.count - 1)
        upcomingArena = Arena.allCases[i]
        SplashPrefs.setInt(i, "playArena")
    }

    func setRounds(_ index: Int) {
        upcomingRounds = [1, 3, 5][min(max(index, 0), 2)]
        cupLength = upcomingRounds
        SplashPrefs.setInt(upcomingRounds, "playRounds")
    }

    func wallOptions() {
        wallBattle = true
        upcomingCount = seats() >= 5 ? 6 : 4
        upcomingRounds = 1
        showPage(.wallOptions)
    }

    func setWallPlayers(_ index: Int) {
        upcomingCount = index == 0 ? 4 : 6
    }

    func setHitEffect(_ index: Int) {
        hitEffect = HitEffect.allCases[min(max(index, 0), HitEffect.allCases.count - 1)]
        SplashPrefs.setString(hitEffect.name, "hitEffect")
    }

    private func gameOptions(_ cupGame: Bool) {
        upcomingRounds = cupGame ? max(cupLength, 3) : 1
        playMenu()
    }

    func joinPage(_ cupGame: Bool) {
        joinCupGame = cupGame
        roomCode = ""
        showPage(.join)
    }

    func joinBack() { playMenu() }

    func joinRoom() {
        let code = roomCode.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        if OnlineSession.isRoomCode(code) {
            connectOnline(code)
        } else {
            message(tr("Enter the six-character room code.", "כתבו את קוד החדר בן ששת התווים."))
        }
    }

    // MARK: House players

    func selectionMessage(_ humans: Int, _ house: Int, _ limit: Int) -> String {
        if humans + house >= limit { return tr("Maximum players selected", "נבחר מספר השחקנים המרבי") }
        return tr("Players: \(humans + house) / \(limit)", "שחקנים: \(humans + house) / \(limit)")
    }

    /// Android `checkRoster`: explains a roster problem, otherwise starts (never with a larger group).
    private func checkRoster(_ humans: Int, _ house: Int, _ limit: Int, _ teams: Bool, _ onValid: (Bool) -> Void) {
        if teams && humans + house != limit {
            message(tr("Choose all players for this team game.", "בחרו את כל השחקנים למשחק הקבוצתי."))
            return
        }
        switch LobbyPlan.problem(humans, house, limit, teams) {
        case "limit"?:
            message(tr("A battle supports at most six players. Remove a house player or a connected friend.",
                       "בקרב יכולים להשתתף עד שישה שחקנים. הסירו שחקן בית או חבר מחובר."))
        case "minimum"?:
            message(tr("Choose at least one opponent.", "בחרו לפחות יריב אחד."))
        case "teams"?:
            message(tr("Team battles need four or six players. Adjust the roster before starting.",
                       "קרב קבוצתי דורש ארבעה או שישה שחקנים. עדכנו את ההרכב לפני ההתחלה."))
        case "selected"?:
            message(tr("Remove a selected player before choosing another.", "הסירו שחקן שנבחר לפני בחירת שחקן אחר."))
        default:
            onValid(false)
        }
    }

    /// Android `houseGame`: "Choose players" (portrait), every card starting unchecked.
    func houseGame(_ cupGame: Bool) {
        // Choose participants for this battle; no hidden preselected roster.
        selectedHouse = []
        houseCupGame = cupGame
        showPage(.house)
    }

    func houseChanged(_ chosen: [String]) {
        selectedHouse = chosen
    }

    /// Android: Start is enabled once a solo battle has an opponent, or a team game has every player.
    var houseStartEnabled: Bool {
        return !selectedHouse.isEmpty && (format == 0 || selectedHouse.count + 1 == seats())
    }

    func houseBack() { playMenu() }

    func houseStart() {
        let total = 1 + selectedHouse.count
        if (format != 0 || wallBattle) && total != seats() {
            message(tr("Choose all players for this team game.", "בחרו את כל השחקנים למשחק הקבוצתי."))
            return
        }
        checkRoster(1, selectedHouse.count, seats(), format != 0 || wallBattle) { _ in
            chosenRoster = selectedHouse
            cup = houseCupGame
            cupRound = 0
            cupScores.removeAll()
            cupRoster = nil
            SplashPrefs.setStringSet(selectedHouse, "housePlayers")
            SplashPrefs.setString(nil, "cupState")
            startGame(false)
        }
    }

    // MARK: Daily paint journey

    /// Android `challengeProgress()`: the saved journey, migrated once to the 30-step order (schema 2).
    func challengeProgress() -> ChallengeProgress {
        var n = NodeJSON.node(SplashPrefs.string("paintJourney") ?? "{}") ?? [:]
        let receipts = n.list("receipts").map { NodeValue.text($0) }
        if KotlinNumber.int(n.num("schema")) < 2 {
            let old = max(KotlinNumber.int(n.num("completed")), 0)
            n["completed"] = SplashDrills.migrateCompleted(old)
            n["schema"] = 2
            SplashPrefs.setString(NodeJSON.string(n), "paintJourney")
        }
        return ChallengeProgress(completed: max(KotlinNumber.int(n.num("completed")), 0), points: KotlinNumber.int(n.num("points")),
                                 lastBonusDay: n.str("bonusDay"), receipts: receipts)
    }

    /// Android `LocalDate.now().toString()`.
    private func today() -> String {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone.current
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: Date())
    }

    private func kindTitle(_ kind: ChallengeKind) -> String {
        return hebrew ? kind.he : AppText.t(kind.en)
    }

    func challengePage(_ step: Int? = nil) {
        var p = challengeProgress()
        if let step = step { p.completed = step }
        let opponent = p.kind.partner(p.chapter, [selected])
        let stage = p.completed % ChallengeKind.allCases.count
        let total = ChallengeKind.allCases.count
        let points = rankPoints()
        let bonus = p.lastBonusDay.javaPrecedes(today())
            ? tr("Your first success today earns 30 bonus points. Keep your progress, even after a break.",
                 "ההצלחה הראשונה היום מזכה ב־30 נקודות בונוס. ההתקדמות נשמרת גם אחרי הפסקה.")
            : tr("Today's bonus is yours. Keep playing to finish this cycle!", "הבונוס היומי כבר שלכם. אפשר להמשיך ולהשלים את המסלול!")
        var drillGoal: String? = nil
        if let d = p.kind.drill {
            let goal = d.goal(p.chapter)
            drillGoal = hebrew ? "יעד: \(goal) הצלחות. שלוש פגיעות או החטאות מחזירות לניסיון חדש, בלי לאבד נקודות."
                : AppText.t("Goal: \(goal) successes. Three hits or misses start a fresh try without losing points.")
        }
        let q = opponent.qualities
        let qualities = tr("Precision", "דיוק") + " " + String(repeating: "★", count: max(q.precision, 0)) + " · " + tr("Reflexes", "זריזות תגובה") + " "
            + String(repeating: "★", count: max(q.reflexes, 0))
        let steps = SplashDrills.journey.enumerated().map { pair -> String in
            let mark = pair.offset < stage ? "✓ " : (pair.offset == stage ? "→ " : "")
            return mark + kindTitle(pair.element)
        }
        journey = JourneyPageModel(opponent: opponent.id,
                                   header: opponent.name(hebrew) + " · " + tr("Cycle \(p.chapter + 1)", "מסלול \(p.chapter + 1)"),
                                   stageLine: tr("Challenge \(stage + 1) of \(total) · \(points) points", "אתגר \(stage + 1) מתוך \(total) · \(points) נקודות"),
                                   stageColor: SplashRanks.at(points).color, bonusLine: bonus, title: kindTitle(p.kind),
                                   goal: AppText.t(p.kind.goal(hebrew)), drillGoal: drillGoal, introduction: AppText.t(p.kind.introduction(hebrew)),
                                   qualities: qualities, step: p.completed, stage: stage, steps: steps)
        showPage(.journey)
    }

    func startChallenge(_ step: Int) {
        let progress = ChallengeProgress(completed: step)
        let kind = progress.kind
        let chapter = progress.chapter
        let difficulty: Difficulty = chapter < 3 ? .easy : (chapter < 7 ? .standard : .pro)
        var cfg = SplashConfig()
        cfg.width = kind.hasWall ? 26.0 : 20.0
        cfg.depth = kind.hasWall ? 14.0 : 20.0
        cfg.difficulty = difficulty
        cfg.challenge = kind
        cfg.chapter = chapter
        cfg.challengeStep = step
        cfg.target = 4 + min(chapter, 5)
        cfg.duration = kind.untimed ? 3600.0 : (kind == .race ? 180.0 : 120.0)
        var options = settings
        options.difficulty = difficulty
        options.court = true
        options.balloons = .onePlace
        options.arena = kind.drill != nil ? .beach : settings.arena
        var used: Set<String> = [selected]
        var members = [Member("p0", selected, team: 0, bot: false, hebrew: hebrew, settings: options)]
        // Kotlin `(1..bots)`: empty when there are no throwers.
        for i in stride(from: 1, through: kind.drill?.bots ?? 1, by: 1) {
            let bot = kind.partner(chapter, used)
            used.insert(bot.id)
            members.append(Member("p\(i)", bot.id, team: kind.cooperative ? 0 : 1, bot: true, hebrew: hebrew, settings: options))
        }
        cup = false
        wallBattle = false
        guard SplashEngine.validRoster(members, .solo) else { return }
        let e = SplashEngine(members: members, seed: SplashClock.currentTimeMillis(), config: cfg, hebrew: hebrew, profiles: ["p0": learningProfile()])
        if e.paintSession.active {
            e.actor("p0")?.position = V(cfg.width * 0.37, cfg.depth * 0.55)
            e.actor("p1")?.position = V(cfg.width * 0.70, cfg.depth * 0.5)
        }
        present(e, localId: "p0")
    }

    private func challengeResults(_ e: SplashEngine, _ r: MatchResult) {
        guard let challenge = e.config.challenge else { return }
        let won = r.winners.contains("p0")
        let old = challengeProgress()
        let next = old.finish(r.id, e.config.challengeStep, won, today(), challenge)
        if next != old {
            let json: Node = ["schema": 2, "completed": next.completed, "points": next.points, "bonusDay": next.lastBonusDay, "receipts": next.receipts]
            SplashPrefs.setString(NodeJSON.string(json), "paintJourney")
            SplashPrefs.setInt(rankPoints() + next.points - old.points, "colourPoints")
        }
        let gained = next.points - old.points
        var score: String? = nil
        if e.paintSession.active {
            score = tr("You: \(e.paintSession.score(0)) · Rival: \(e.paintSession.score(1))", "אתם: \(e.paintSession.score(0)) · היריב: \(e.paintSession.score(1))")
        }
        journeyResult = JourneyResultModel(
            title: won ? tr("Challenge complete!", "האתגר הושלם!") : tr("Try another splash!", "מנסים עוד זריקה!"),
            won: won, kind: kindTitle(challenge),
            progress: won ? tr("Progress saved · +\(gained) journey points", "ההתקדמות נשמרה · +\(gained) נקודות מסע")
                : tr("Your progress is safe. Take your time and try again.", "ההתקדמות שלכם נשמרת. קחו את הזמן ונסו שוב."),
            score: score, button: won ? tr("Next challenge", "האתגר הבא") : tr("Try again", "לנסות שוב"),
            nextStep: won ? next.completed : e.config.challengeStep)
        showPage(.journeyResult)
    }

    // MARK: Learning profile

    func learningProfile() -> LearningProfile {
        let p = LearningProfile()
        guard let json = NodeJSON.node(SplashPrefs.string("learning") ?? "{}") else { return p }
        for skill in Skill.allCases {
            guard let a = json[skill.name] as? [String: Any] else { continue }
            p.skills[skill] = SkillState(level: KotlinNumber.int(a.num("level")), streak: KotlinNumber.int(a.num("streak")),
                                         independent: KotlinNumber.int(a.num("independent")),
                                         assisted: KotlinNumber.int(a.num("assisted")),
                                         wrong: KotlinNumber.int(a.num("wrong")), reviewed: KotlinNumber.int(a.num("reviewed")))
        }
        return p
    }

    private func saveProfile(_ p: LearningProfile) {
        if qa { return } // Automated exhibitions must never train the human learning profile.
        SplashPrefs.setString(NodeJSON.string(WorldCodec.profile(p)), "learning")
    }

    // MARK: Battles

    private func roster(_ tutorial: Bool) -> [Member] {
        if tutorial {
            return [Member("p0", selected, team: 0, bot: false, name: Characters.get(selected).name(hebrew), hebrew: hebrew, settings: settings),
                    Member("p1", teacherId, team: 1, bot: false, name: Characters.get(teacherId).name(hebrew), hebrew: hebrew, settings: settings)]
        }
        if cup, let saved = cupRoster { return saved }
        let n = seats()
        var chosen: [SplashCharacter]? = nil
        if let ids = chosenRoster {
            var unique: [String] = []
            for id in ids where id != selected && !unique.contains(id) { unique.append(id) }
            chosen = unique.map { Characters.get($0) }
        }
        let ordered = [Characters.get(selected)] + (chosen ?? Characters.all.filter { $0.id != selected }.shuffled())
        let size = chosen.map { $0.count + 1 } ?? n
        let match = matchSettings
        var members: [Member] = []
        for (i, c) in ordered.prefix(size).enumerated() {
            members.append(Member("p\(i)", c.id, team: i < size / 2 ? 0 : 1, bot: i != 0 || qa || storeDemo, name: c.name(hebrew), hebrew: hebrew,
                                  settings: i == 0 ? match : PlayerSettings.bots([match])))
        }
        return members
    }

    func startGame(_ tutorial: Bool) {
        let wall = wallBattle && !tutorial
        var cfg = SplashConfig()
        cfg.width = 40.0
        cfg.depth = 24.0
        cfg.duration = wallBattle ? 300.0 : 180.0
        cfg.difficulty = settings.difficulty
        cfg.wallBattle = wall
        cfg.hitEffect = hitEffect
        let members = roster(tutorial)
        let mode: GameMode = (tutorial || (format == 0 && !wallBattle)) ? .solo : .teams
        guard SplashEngine.validRoster(members, mode) else {
            message(tr("This cup could not be restored.", "לא ניתן לשחזר את הגביע הזה."))
            return
        }
        let seed = storeDemo ? SplashScreenshot.seed : SplashClock.currentTimeMillis()
        let e = SplashEngine(members: members, mode: mode, topic: .math, seed: seed, config: cfg,
                             hebrew: hebrew, profiles: ["p0": learningProfile()])
        if cup && !tutorial { cupRoster = e.members }
        e.practice = tutorial
        if tutorial {
            e.actor("p0")?.position = V(5.4, 8.4)
            e.actor("p1")?.position = V(6.8, 3.7)
            e.resetPracticeQuestion("p0")
        }
        present(e, localId: "p0", tutorial: tutorial)
    }

    func present(_ e: SplashEngine, localId: String, tutorial: Bool = false, online: OnlineSession? = nil) {
        gameView?.stop()
        battleReady = false
        let announceNewMatch = e.time == 0.0 // Capture before an online replica advances during loading.
        network = online
        learningSession = tutorial
        music.setMenu(false)
        art.prepareMotion(e.members.map { $0.character })
        gameView?.teardown()
        let v = SplashArenaView(engine: e, localId: localId, art: art, onExit: { [weak self] in
            self?.pauseMenu()
        }, onFinish: { [weak self] r in
            guard let self = self else { return }
            if let a = e.actor(localId) { self.saveProfile(a.profile) }
            self.showResults(r, e)
        }, onSpeak: { [weak self] text in
            self?.speech.speak(text)
        })
        gameView = v
        v.rankPoints = rankPoints()
        // Android SCREEN_ORIENTATION_FULL_SENSOR; the camera panel's Portrait / Landscape turns it.
        SplashOrientation.apply(SplashOrientation.game(0))
        v.onRotate = { [weak v] in
            guard let v = v else { return }
            SplashOrientation.apply(SplashOrientation.rotated(landscape: v.bounds.width > v.bounds.height))
        }
        v.onControlSettings = { [weak self] s in
            guard let self = self else { return }
            if tutorial {
                var next = self.settings
                next.walk = s.walk
                next.throwing = s.throwing
                self.saveSettings(next)
            } else {
                self.saveSettings(s)
            }
        }
        if tutorial {
            v.beginTutorial()
            v.tutorialCompleted = { [weak self, weak v] in
                guard let self = self, let v = v else { return }
                if let a = e.actor(localId) { self.saveProfile(a.profile) }
                SplashPrefs.setBool(true, "tutorialDone")
                Task { @MainActor [weak self, weak v] in
                    guard let self = self, let v = v, self.gameView === v else { return }
                    v.stop()
                    self.home()
                }
            }
        }
        // The engine calls back outside the controller; the board itself honours "Game sounds".
        let board = sounds
        e.onEvent = { type, id in
            if id == localId || type == "hit" || type == "finish" { board.play(type) }
        }
        pausePresented = false
        cupExitPresented = false
        screen = .game
        // The battle starts once the arena's first frame has replaced the loading screen.
        v.stop()
        v.showLoading(avatar: selected) { [weak self, weak v] in
            guard let self = self, let v = v, self.gameView === v else { return }
            self.battleReady = true
            if announceNewMatch { self.music.matchStarted(e.matchId, enabled: self.gameSounds) }
            if self.foreground && !self.pausePresented { v.start() }
        }
        online?.attach(v)
        // Android `FamilyLandscapeHint`: a portrait battle suggests landscape once, 0.9 s in (a toast that
        // never covers or moves the HUD).
        Task { @MainActor [weak self, weak v] in
            try? await Task.sleep(nanoseconds: 900_000_000)
            guard let self = self, let v = v, self.gameView === v, v.window != nil, v.bounds.height > v.bounds.width else { return }
            self.message(FamilyMessages.text("For a wider view, play in landscape.", "לתצוגה רחבה יותר, שחקו במצב אופקי."))
        }
    }

    func pauseMenu() {
        if learningSession {
            gameView?.stop()
            home()
            return
        }
        if pausePresented { return }
        gameView?.stop()
        network?.background()
        pausePresented = true
    }

    func continueFromPause() {
        pausePresented = false
        network?.foreground()
        gameView?.start()
    }

    func returnFromPause() {
        pausePresented = false
        if let v = gameView, let a = v.engine.actor(v.localId) { saveProfile(a.profile) }
        home()
    }

    private func displayName(_ a: SplashActor) -> String {
        if a.member.id == (network?.uid ?? "p0") {
            return tr("You", "אתם") + " · " + Characters.get(a.member.character).name(hebrew)
        }
        if a.member.bot { return Characters.get(a.member.character).name(hebrew) }
        return a.member.name
    }

    private func row(_ a: SplashActor, _ ink: UInt32) -> ResultPlayerRow {
        return ResultPlayerRow(id: a.member.id, character: a.member.character, name: displayName(a), score: a.score, ink: ink)
    }

    private func showResults(_ r: MatchResult, _ e: SplashEngine) {
        network?.finishMatch(r)
        if e.practice || learningSession {
            home()
            return
        }
        if e.config.challenge == nil { recordRank(e, network?.uid ?? "p0") }
        gameView?.stop()
        if network == nil && !qa { localStore.clear() }
        if e.config.challenge != nil {
            challengeResults(e, r)
            return
        }
        let title: String
        if r.draw {
            title = tr("A colorful draw!", "תיקו צבעוני!")
        } else if r.winners.contains(network?.uid ?? "p0") {
            title = tr("You won!", "ניצחתם!")
        } else {
            title = tr("Battle complete", "הקרב הסתיים")
        }
        var teams: [ResultTeamPanel] = []
        var rows: [ResultPlayerRow] = []
        if e.mode == .teams {
            let order = [0, 1].stableSorted { a, b in
                let sa = a < r.teamScores.count ? r.teamScores[a] : 0
                let sb = b < r.teamScores.count ? r.teamScores[b] : 0
                return sa > sb
            }
            for team in order {
                let style = Teams.style(team)
                let won = !r.draw && r.winners.contains { e.actor($0)?.member.team == team }
                let state: String
                if won {
                    state = tr("Winners!", "המנצחים!")
                } else if r.draw {
                    state = tr("Draw", "תיקו")
                } else {
                    state = tr("Great teamwork", "עבודת צוות נהדרת")
                }
                let score = team < r.teamScores.count ? r.teamScores[team] : 0
                let subtitle = state + " · " + tr("Team score: ", "ניקוד קבוצתי: ") + "\(score)"
                let members = e.actors.filter { $0.member.team == team }.stableSorted { $0.score > $1.score }
                teams.append(ResultTeamPanel(id: team, name: style.name(hebrew), subtitle: subtitle, color: style.color, ink: style.ink,
                                             rows: members.map { row($0, style.ink) }))
            }
        } else {
            // Gold, silver and bronze for the first three.
            rows = e.actors.stableSorted { $0.score > $1.score }.enumerated().map { pair in
                var line = row(pair.element, SplashPalette.white)
                line.rank = pair.offset
                return line
            }
        }
        var note: String? = nil
        if e.config.wallBattle {
            note = tr("Team score is the percentage of the opposing wall painted.", "ניקוד הקבוצה הוא אחוז הקיר הנגדי שנצבע.")
        } else if e.mode == .teams {
            note = tr("Team scores count hits and wrong-answer penalties.", "ניקוד הקבוצה כולל פגיעות והפחתות על תשובות שגויות.")
        }
        let me = e.actor(network?.uid ?? "p0") ?? e.actors[0]
        let correct = me.answers.filter { $0.correct }.count
        let correctLine = tr("Correct answers: \(correct) · Hits: \(me.hits)", "תשובות נכונות: \(correct) · פגיעות: \(me.hits)")
        let countsLine: String? = e.config.wallBattle ? nil : tr("Your answer still counts when a throw misses.", "תשובה נכונה נחשבת גם כשהזריקה מחטיאה.")
        var onlineCup = false
        var nextRound = false
        if let session = network {
            if session.isCup() {
                onlineCup = true
                standings = session.standingsText()
                session.standingsChanged = { [weak self, weak session] in
                    guard let self = self, let session = session else { return }
                    self.standings = session.standingsText()
                }
            }
            nextRound = session.hasNextRound()
        }
        var cupLine: String? = nil
        var cupStandings: String? = nil
        var nextBattle = false
        var playAgain = false
        if cup {
            for a in e.actors { cupScores[a.member.id] = (cupScores[a.member.id] ?? 0) + a.score }
            cupRound += 1
            saveCup()
            cupLine = tr("Cup · round \(cupRound) / \(cupLength)", "גביע · סיבוב \(cupRound) / \(cupLength)")
            let ranked = e.actors.stableSorted { (cupScores[$0.member.id] ?? 0) > (cupScores[$1.member.id] ?? 0) }
            cupStandings = ranked.map { Characters.get($0.member.character).name(hebrew) + "  " + "\(cupScores[$0.member.id] ?? 0)" }.joined(separator: "\n")
            nextBattle = cupRound < cupLength
        } else if network == nil {
            playAgain = true
        }
        results = ResultsModel(title: title, teams: teams, rows: rows, note: note, correctLine: correctLine, countsLine: countsLine,
                               onlineCup: onlineCup, nextRound: nextRound, cupLine: cupLine, cupStandings: cupStandings,
                               nextBattle: nextBattle, playAgain: playAgain)
        showPage(.results)
    }

    // MARK: Leaving a cup (Android `leaveCupScreen`)

    /// Results "Main menu" and the room's "Back": a local or online cup asks Save / Don't save / Cancel.
    func leaveCupScreen() {
        if network?.isCup() != true && !cup {
            home()
            return
        }
        cupExitPresented = true
    }

    /// Save keeps the cup to continue later (an online room keeps its "Return to" bookmark).
    func cupExitSave() {
        cupExitPresented = false
        if network == nil && cup { saveCup() }
        home()
    }

    /// Don't save forgets the cup on this device: an online room loses this device's bookmark (the
    /// shared room continues for the others); a local cup and its saved battle are deleted.
    func cupExitDiscard() {
        cupExitPresented = false
        if let session = network {
            session.close()
            network = nil
            SplashPrefs.onlineRoom = nil
        } else {
            cup = false
            cupRoster = nil
            SplashPrefs.setString(nil, "cupState")
            localStore.clear()
        }
        home()
    }

    func cupExitCancel() {
        cupExitPresented = false
    }

    func resultsNextRound() { network?.nextRound() }
    func resultsNextBattle() { startGame(false) }
    func resultsPlayAgain() { startGame(false) }

    private func saveCup() {
        if cupRound >= cupLength {
            SplashPrefs.setString(nil, "cupState")
            return
        }
        let n: Node = ["length": cupLength, "round": cupRound, "scores": cupScores, "selected": selected, "format": format, "count": count,
                       "topic": topic.name, "roster": (cupRoster ?? []).map { WorldCodec.member($0) }]
        SplashPrefs.setString(NodeJSON.string(n), "cupState")
    }

    private func restoreCup(_ text: String) {
        let failure = tr("This cup could not be restored.", "לא ניתן לשחזר את הגביע הזה.")
        guard let n = NodeJSON.node(text), let round = NodeValue.number(n["round"]), let scoresNode = n["scores"] as? [String: Any],
              let savedSelected = n["selected"] as? String, let savedFormat = NodeValue.number(n["format"]),
              let savedCount = NodeValue.number(n["count"]), let savedTopic = Topic(rawValue: n.str("topic")) else {
            message(failure)
            return
        }
        var restoredRoster: [Member]? = nil
        if let list = n["roster"] as? [Any] {
            restoredRoster = list.map { item -> Member in
                let m = NodeValue.node(item)
                return WorldCodec.member(m.str("id"), m)
            }
        }
        let restoredFormat = min(max(KotlinNumber.int(savedFormat), 0), 2)
        if let members = restoredRoster, !SplashEngine.validRoster(members, restoredFormat == 0 && !wallBattle ? .solo : .teams) {
            message(failure)
            return
        }
        cup = true
        cupLength = KotlinNumber.int(n.num("length", 3))
        cupRound = KotlinNumber.int(round)
        cupRoster = restoredRoster
        var scores: [String: Int] = [:]
        for (key, value) in scoresNode { scores[key] = KotlinNumber.int(NodeValue.number(value) ?? 0) }
        cupScores = scores
        selected = savedSelected
        format = restoredFormat
        count = min(max(KotlinNumber.int(savedCount), 2), 6)
        topic = savedTopic
        startGame(false)
    }

    // MARK: Online

    func connectOnline(_ code: String?, rounds: Int = 1) {
        network?.close()
        network = nil
        let emulator = SplashLaunch.qaOnline
        if !emulator && code == nil && rounds > 3 {
            message(tr("Five-battle online cups need a service update. Choose one or three battles, or play five with house players.",
                       "גביע מקוון של חמישה קרבות דורש עדכון שירות. בחרו קרב אחד או שלושה, או שחקו חמישה עם שחקני הבית."))
            return
        }
        if !emulator && !SplashDatabaseFactory.productionAvailable {
            message(tr("Online play is not available yet. You can play with house players.", "המשחק עם חברים ברשת עדיין אינו זמין. אפשר לשחק עם שחקני הבית."))
            return
        }
        let session = OnlineSession(controller: self, host: emulator ? "127.0.0.1" : "", character: selected, hebrew: hebrew,
                                    mode: format == 0 ? .solo : .teams, topic: .math, rounds: rounds, maxPlayers: seats(),
                                    playerSettings: matchSettings,
                                    battleConfig: OnlineSession.roomConfig(wallBattle: wallBattle, hitEffect: hitEffect))
        network = session
        do {
            try session.open(code) { [weak self] state in self?.message(state) }
        } catch {
            NSLog("SplashOnline: Connection setup failed: %@", String(describing: error))
            message(tr("Could not connect. Please try again.", "לא ניתן להתחבר. נסו שוב."))
        }
    }

    func createRoom() { connectOnline(nil, rounds: upcomingRounds) }

    func returnToRoom(_ saved: String) { connectOnline(saved) }

    func lobby(code: String, players: [Member], readyIds: Set<String>, house: [String], limit: Int, teams: Bool, hosted: Bool, selfId: String,
               ready: @escaping () -> Void, change: @escaping ([String]) -> Void, remove: @escaping (String) -> Void,
               start: @escaping (Bool) -> Void) {
        let humans = players.filter { !$0.bot }.map { LobbyPlayer(id: $0.id, name: $0.name, character: $0.character) }
        lobbyModel = LobbyModel(code: code, humans: humans, readyIds: readyIds, house: house, limit: limit, teams: teams, hosted: hosted, selfId: selfId)
        lobbyReady = ready
        lobbyChange = change
        lobbyRemove = remove
        lobbyStart = start
        if screen != .lobby { showPage(.lobby) }
    }

    func lobbyMarkReady() { lobbyReady?() }

    func lobbyRemovePlayer(_ id: String) { lobbyRemove?(id) }

    func lobbyChangeHouse(_ chosen: [String]) {
        lobbyModel?.house = chosen
        lobbyChange?(chosen)
    }

    func lobbyStartGame() {
        guard let model = lobbyModel else { return }
        checkRoster(model.humans.count, model.house.count, model.limit, model.teams) { increase in
            lobbyStart?(increase)
        }
    }

    func copyCode(_ code: String) {
        UIPasteboard.general.string = code
        message(tr("Code copied", "הקוד הועתק"))
    }

    // MARK: Lifecycle (Android onPause / onResume)

    func scenePhaseChanged(active: Bool) {
        if active {
            lifecyclePaused = false
            onResume()
        } else if !lifecyclePaused {
            lifecyclePaused = true
            onPause()
        }
    }

    private func onPause() {
        foreground = false
        if let v = gameView {
            if let a = v.engine.actor(v.localId) { saveProfile(a.profile) }
            recordRank(v.engine, v.localId)
            if network == nil && !qa { localStore.save(v.engine, cupRound: cupRound, cupScores: cupScores, cup: cup, cupLength: cupLength) }
        }
        music.setForeground(false)
        sounds.setPaused(true)
        gameView?.stop()
        speech.stop()
        network?.background()
    }

    private func onResume() {
        foreground = true
        music.setForeground(true)
        music.setMenu(gameView == nil)
        sounds.setPaused(false)
        if !pausePresented {
            if battleReady { gameView?.start() }
            network?.foreground()
        }
    }
}

// MARK: App Store screenshots

extension SplashController {
    /// App Store captures only (SplashScreenshot): opens one screen at launch. Battles are local, seeded and offline, with
    /// house players only (the player's own avatar plays as one too, like Android's qaDemo exhibitions); the points a page
    /// shows are staged in this capture's settings, which the next capture removes (SplashScreenshot.prepare).
    func applyStoreScreenshotScene() {
        guard let name = SplashScreenshot.name, screen == .home, gameView == nil else { return }
        let scene = name == "home" ? "home" : (SplashScreenshot.value(after: "splash") ?? "")
        switch scene {
        case "home":
            SplashPrefs.setInt(260, "colourPoints")
            objectWillChange.send()
        case "beach":
            storeBattle(.beach, format: 0, wall: false, you: "miniko", house: ["minik", "mia", "kyra", "gaya", "flare"])
        case "teams":
            storeBattle(.park, format: 2, wall: false, you: "kyra", house: ["comet", "june", "minik", "mia", "amber"])
        case "andromeda":
            storeBattle(.andromeda, format: 0, wall: false, you: "mia", house: ["minik", "comet", "gaya", "june", "flare"])
        case "paint":
            storeBattle(.beach, format: 1, wall: true, you: "miniko", house: ["minik", "kyra", "mia"])
        case "play":
            // The new Play page with every option showing: Paint walls 2 x 2 adds the hit rule.
            setUpcomingArena(Arena.beach.ordinal)
            setPlayMode(3)
            playMenu()
        default:
            break
        }
    }

    /// A seeded single battle (`format` 0 solo, 1 two teams of two, 2 two teams of three; `wall` Paint walls) caught while
    /// the house players answer and throw. The arena turns landscape-right when the capture asks for it.
    private func storeBattle(_ arena: Arena, format f: Int, wall: Bool, you: String, house: [String]) {
        storeDemo = true
        selected = you
        upcomingArena = arena
        format = f
        wallBattle = wall
        upcomingCount = house.count + 1
        upcomingRounds = 1
        cup = false
        cupRound = 0
        cupScores.removeAll()
        cupRoster = nil
        chosenRoster = house
        startGame(false)
        if SplashScreenshot.wantsLandscape { SplashOrientation.apply(.landscapeRight) }
    }
}
