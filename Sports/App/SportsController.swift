import StoreKit
import SwiftUI
import UIKit

enum SportsScreen: Equatable {
    case home, journey, journeyList, journeyResult, setup, avatars, settings, support, tutorial, tournament
    case online, publicTournaments, lobby, result, parentZone, privacy, game
}

struct SportsToast: Identifiable, Equatable {
    let id = UUID()
    let text: String
}

struct SportsShare: Identifiable {
    let id = UUID()
    let text: String
}

/// Android `journeyResult(e)`.
struct JourneyResultModel: Equatable {
    let won: Bool
    let title: String
    let stage: String
    let progress: String
    let message: String
    let earned: Int
    let step: Int
}

/// Android `lobby(code, members, ready, host, link)`.
struct SportsLobbyModel: Equatable {
    let code: String
    let members: [Participant]
    let ready: Set<String>
    let host: Bool
    let uid: String
}

struct PublicEntry: Equatable {
    let code: String
    let rounds: Int
    let count: String
}

/// Port of Android SportsActivity.kt: the pages, settings, local and journey matches, the local
/// cup, private rooms and public tournaments, pause/save, results and the parent zone. Ads,
/// purchases and the family services module are not part of this iOS port.
@MainActor
final class SportsController: ObservableObject, SportsOnlineHost {
    let sport = SportsLaunch.sport
    let art = SportsArt.shared
    @Published private(set) var screen: SportsScreen = .home
    @Published var toast: SportsToast?
    @Published var pausePresented = false
    @Published var gatePresented = false
    @Published var gateAnswer = ""
    @Published var shareSheet: SportsShare?
    @Published private(set) var revision = 0

    @Published private(set) var mode: Control = .beginner
    @Published private(set) var avatar = "miniko"
    @Published private(set) var opponent = "minik"
    @Published private(set) var arena = "beach"
    @Published private(set) var teamSize = 2
    @Published private(set) var serveMode: Control = .beginner
    @Published private(set) var ballStyle = "classic"
    @Published private(set) var ownColor = "aqua"
    @Published private(set) var rivalColor = "gold"
    @Published private(set) var teamMates = ["june", "comet"]
    @Published private(set) var opponents = ["minik", "mia", "gaya"]
    @Published private(set) var answerMode: AnswerMode = .serves
    @Published private(set) var serveQuestions: ServeQuestions = .fullTime
    @Published private(set) var answerSeconds = 15
    @Published private(set) var questionsEnabled = true
    @Published var onlineRounds = 1
    @Published var roomCode = ""
    @Published var receptionOpen = false

    @Published private(set) var journeyStep = 0
    @Published private(set) var journeyResultModel: JourneyResultModel?
    @Published private(set) var lobbyModel: SportsLobbyModel?
    @Published private(set) var publicEntries: [PublicEntry] = []
    @Published private(set) var resultWorld: SportsEngine?
    private(set) var resultId = ""

    private(set) var view: SportsView?
    private(set) var engine: SportsEngine?
    private(set) var online: SportsOnline?
    private var cup: Node?
    private(set) var playingCup = false
    private var nonce: Int64 = 0
    private var paused = false
    private var lifecyclePaused = false
    private var gateAction: (() -> Void)?
    private let sounds = SportsSounds()
    private let music = SportsMusic()
    private var memoryObserver: NSObjectProtocol?
    private let qa = SportsLaunch.qa

    /// The public page shared on iOS until the App Store listing exists (Android shares its Play listing).
    static let storeLink = "https://miniklearn.com"

    var hebrew: Bool { return AppText.language == "he" }
    var appName: String { return sport == .squash ? "Minik Squash" : "Minik Beach Volley" }

    init() {
        AppText.configure(Locale.preferredLanguages.first ?? "en")
        avatar = SportsPrefs.string("avatar") ?? "miniko"
        opponent = SportsPrefs.string("opponent") ?? "minik"
        mode = Control(rawValue: SportsPrefs.string("control") ?? "BEGINNER") ?? .beginner
        teamSize = min(max(SportsPrefs.int("teamSize", 2), 2), 3)
        arena = SportsPrefs.string("arena") ?? "beach"
        answerMode = AnswerMode(rawValue: SportsPrefs.string("answerMode") ?? "SERVES") ?? .serves
        serveQuestions = ServeQuestions(rawValue: SportsPrefs.string("serveQuestions") ?? "FULL_TIME") ?? .fullTime
        let seconds = SportsPrefs.int("answerSeconds", 15)
        answerSeconds = [5, 10, 15, 30].contains(seconds) ? seconds : 15
        questionsEnabled = SportsPrefs.bool("questionsEnabled", true)
        serveMode = Control(rawValue: SportsPrefs.string("serveControl") ?? mode.name) ?? mode
        let ball = SportsPrefs.string("ballStyle") ?? "classic"
        ballStyle = VolleyPalette.ballIds.contains(ball) ? ball : "classic"
        ownColor = SportsPrefs.string("ownColor") ?? "aqua"
        rivalColor = SportsPrefs.string("rivalColor") ?? "gold"
        for i in teamMates.indices { teamMates[i] = SportsPrefs.string("teammate\(i)") ?? teamMates[i] }
        for i in opponents.indices { opponents[i] = SportsPrefs.string("opponent\(i)") ?? opponents[i] }
        sounds.enabled = soundsOn
        memoryObserver = NotificationCenter.default.addObserver(forName: UIApplication.didReceiveMemoryWarningNotification, object: nil, queue: .main) { _ in
            Task { @MainActor in SportsArt.shared.purge() }
        }
        home()
    }

    func tr(_ en: String, _ he: String) -> String { return SportsText.t(en, he, hebrew) }

    /// Android `message(s)`: a long toast.
    func message(_ text: String) { toast = SportsToast(text: text) }

    func points() -> Int { return SportsPrefs.int("colourPoints", 0) }

    var soundsOn: Bool { return SportsPrefs.bool("sounds", true) }

    func setSounds(_ on: Bool) {
        SportsPrefs.setBool(on, "sounds")
        sounds.enabled = on
        if on { menuMusic() } else { music.setMenu(false) }
        revision += 1
    }

    // MARK: Pages

    /// Android `page(title, back)`: stops a shown match, clears the result and plays the menu music.
    private func page(_ next: SportsScreen) {
        view?.running = false
        view?.teardown()
        view = nil
        resultWorld = nil
        pausePresented = false
        screen = next
        revision += 1
        menuMusic()
    }

    private func menuMusic() {
        if !soundsOn || qa || screen == .game || paused {
            music.setMenu(false)
            return
        }
        music.setMenu(true)
    }

    func sectionOpen(_ title: String, _ index: Int) -> Bool {
        return SportsPrefs.bool(title, index < 2, file: "family_menu_sections")
    }

    func toggleSection(_ title: String, _ index: Int) {
        SportsPrefs.setBool(!sectionOpen(title, index), title, file: "family_menu_sections")
        revision += 1
    }

    var hasSaved: Bool { return SportsPrefs.contains("saved") }
    var hasPracticeSaved: Bool { return SportsPrefs.contains("practiceSaved") }
    var savedRoom: String? { return SportsPrefs.string("room") }

    func home() {
        playingCup = false
        online?.close()
        online = nil
        engine = nil
        page(.home)
    }

    func continueSaved() {
        guard let node = NodeJSON.node(SportsPrefs.string("saved")), let e = try? SportsCodec.decode(node) else {
            message(tr("Could not restore this match.", "לא ניתן לשחזר את המשחק."))
            return
        }
        present(e, "you", nil)
    }

    // MARK: Daily skill journey

    var journeyCompleted: Int { return SportsPrefs.int("journeyStep", 0) }

    func journeyPage(_ requested: Int? = nil) {
        let completed = journeyCompleted
        journeyStep = min(max(requested ?? completed, 0), completed)
        page(.journey)
        engine = nil
    }

    func journeyList() { page(.journeyList) }

    func continuePractice() {
        guard let node = NodeJSON.node(SportsPrefs.string("practiceSaved")), let e = try? SportsCodec.decode(node) else {
            message(tr("Could not restore this match.", "לא ניתן לשחזר את המשחק."))
            return
        }
        present(e, "you", nil)
    }

    func startJourney(_ step: Int) {
        online?.close()
        online = nil
        playingCup = false
        let d = SportsJourney.stage(sport, step)
        var used: [String] = [avatar]
        func house(_ id: String, _ team: Int) -> Participant {
            let c = d.bot(step / 30, sport, Set(used))
            used.append(c.id)
            return Participant(id, c.id, team, true)
        }
        let you = Participant("you", avatar, 0, false, tr("You", "אתם"), points())
        let members = sport == .squash ? [you, house("coach", 1)] : [you, house("coach", 1), house("teammate", 0), house("other", 1)]
        var c = config()
        c.teamSize = 2
        c.tutorial = false
        c.questionsEnabled = false
        c.challengeStep = step
        c.control = sport == .squash && d.skill != .move ? .beginner : .standard
        c.serveControl = .beginner
        present(SportsEngine(c, members, matchId: UUID().uuidString.lowercased()), "you", nil)
    }

    private func journeyResult(_ e: SportsEngine) {
        guard let d = e.practice else { return }
        SportsPrefs.remove("practiceSaved")
        var earned = 0
        var receipts = SportsPrefs.stringSet("journeyReceipts")
        let completed = journeyCompleted
        if d.won && d.step == completed && !receipts.contains(e.matchId) {
            let today = SportsController.today()
            let bonus = today > (SportsPrefs.string("journeyDay") ?? "")
            earned = 40 + min(d.cycle, 10) * 10 + (bonus ? 30 : 0)
            receipts.append(e.matchId)
            SportsPrefs.setInt(completed + 1, "journeyStep")
            SportsPrefs.setInt(points() + earned, "colourPoints")
            SportsPrefs.setStringSet(Array(receipts.suffix(128)), "journeyReceipts")
            if bonus { SportsPrefs.setString(today, "journeyDay") }
        }
        journeyResultModel = JourneyResultModel(won: d.won,
                                                title: d.won ? tr("Challenge complete!", "האתגר הושלם!") : tr("Let's try again", "מנסים שוב"),
                                                stage: tr(d.stage.en, d.stage.he), progress: "\(d.successes) / \(d.goal)",
                                                message: d.won ? tr("Wonderful practice. You learned another court skill!", "תרגול נהדר. למדתם עוד מיומנות במגרש!")
                                                    : tr("Every try teaches you something. Your progress is safe.", "כל ניסיון מלמד משהו. ההתקדמות שלכם נשמרת."),
                                                earned: earned, step: d.step)
        page(.journeyResult)
    }

    /// Android `java.time.LocalDate.now().toString()`.
    private static func today() -> String {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone.current
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: Date())
    }

    // MARK: Support

    func openSupport() { page(.support) }

    func rateApp() {
        // Android opens the store listing; iOS asks the App Store for its own rating prompt.
        guard let scene = UIApplication.shared.connectedScenes.compactMap({ $0 as? UIWindowScene })
            .first(where: { $0.activationState == .foregroundActive }) else { return }
        AppStore.requestReview(in: scene)
    }

    func shareApp() {
        shareSheet = SportsShare(text: appName + "\n" + SportsController.storeLink)
    }

    func sendFeedback() {
        var mail = URLComponents()
        mail.scheme = "mailto"
        mail.path = "appsbybros.dev@gmail.com"
        mail.queryItems = [URLQueryItem(name: "subject", value: appName + " feedback")]
        guard let url = mail.url else { return }
        UIApplication.shared.open(url) { [weak self] opened in
            MainActor.assumeIsolated {
                guard let self, !opened else { return }
                self.message(self.tr("No app can open this yet.", "אין כרגע יישום מתאים לפתיחה."))
            }
        }
    }

    // MARK: Settings

    /// Android `config(tutorial)`.
    private func config(_ tutorial: Bool = false) -> SportsConfig {
        var c = SportsConfig()
        c.sport = sport
        c.teamSize = teamSize
        c.target = tutorial ? 11 : (qa ? SportsLaunch.qaTarget : (sport == .squash ? 11 : 15))
        c.arena = sport == .squash ? "squash" : arena
        c.control = mode
        c.seed = Int(SportsClock.currentTimeMillis() % Int64(Int32.max))
        c.tutorial = tutorial
        c.answerMode = answerMode
        c.serveQuestions = serveQuestions
        c.answerSeconds = answerSeconds
        c.questionsEnabled = questionsEnabled
        c.serveControl = serveMode
        c.ballStyle = ballStyle
        c.teamColors = [ownColor, rivalColor]
        c.houseRoster = Array(teamMates.prefix(teamSize - 1)) + Array(opponents.prefix(teamSize))
        return c
    }

    private func saveSettings() {
        SportsPrefs.setString(serveMode.name, "serveControl")
        SportsPrefs.setString(ballStyle, "ballStyle")
        SportsPrefs.setString(ownColor, "ownColor")
        SportsPrefs.setString(rivalColor, "rivalColor")
        for (i, v) in teamMates.enumerated() { SportsPrefs.setString(v, "teammate\(i)") }
        for (i, v) in opponents.enumerated() { SportsPrefs.setString(v, "opponent\(i)") }
        SportsPrefs.setString(avatar, "avatar")
        SportsPrefs.setString(opponent, "opponent")
        SportsPrefs.setString(mode.name, "control")
        SportsPrefs.setInt(teamSize, "teamSize")
        SportsPrefs.setString(arena, "arena")
        SportsPrefs.setString(answerMode.name, "answerMode")
        SportsPrefs.setString(serveQuestions.name, "serveQuestions")
        SportsPrefs.setInt(answerSeconds, "answerSeconds")
        SportsPrefs.setBool(questionsEnabled, "questionsEnabled")
    }

    /// Changing Control also resets Serve control (Android `mode = it; serveMode = it`).
    func setMode(_ c: Control) {
        mode = c
        serveMode = c
        saveSettings()
    }

    func setServeMode(_ c: Control) {
        serveMode = c
        saveSettings()
    }

    func setTeamSize(_ n: Int) {
        teamSize = n
        saveSettings()
    }

    func setArena(_ id: String) {
        arena = id
        saveSettings()
    }

    func setBallStyle(_ id: String) {
        ballStyle = id
        saveSettings()
    }

    func setOwnColor(_ id: String) {
        ownColor = id
        if rivalColor == id { rivalColor = VolleyPalette.teamIds.first { $0 != id } ?? "gold" }
        saveSettings()
        // Android re-runs settings() here, which collapses the reception assistance group.
        if screen == .settings { receptionOpen = false }
    }

    func setRivalColor(_ id: String) {
        rivalColor = id
        saveSettings()
    }

    func setAvatar(_ id: String) {
        avatar = id
        saveSettings()
    }

    func setOpponent(_ id: String) {
        opponent = id
        saveSettings()
    }

    func setTeamMate(_ i: Int, _ id: String) {
        teamMates[i] = id
        saveSettings()
    }

    func setOpponentAt(_ i: Int, _ id: String) {
        opponents[i] = id
        saveSettings()
    }

    func setAnswerMode(_ m: AnswerMode) {
        answerMode = m
        saveSettings()
    }

    func setServeQuestions(_ q: ServeQuestions) {
        serveQuestions = q
        saveSettings()
    }

    func setAnswerSeconds(_ s: Int) {
        answerSeconds = s
        saveSettings()
    }

    func setPlayWithoutQuestions(_ on: Bool) {
        questionsEnabled = !on
        saveSettings()
    }

    func receptionValue(_ key: String) -> Bool { return SportsPrefs.bool(key, true) }

    func setReception(_ key: String, _ on: Bool) {
        SportsPrefs.setBool(on, key)
        revision += 1
    }

    /// Android `receptionSlow()`.
    func receptionSlow() -> Bool { return SportsPrefs.bool("receptionSlow", true) }

    func controlName(_ c: Control) -> String {
        switch c {
        case .beginner: return tr("Beginner", "מתחילים")
        case .standard: return tr("Standard", "רגיל")
        case .pro: return tr("Pro", "מקצועני")
        }
    }

    func teamName(_ id: String) -> String {
        switch id {
        case "berry": return tr("Berry Stars", "כוכבי פטל")
        case "gold": return tr("Golden Suns", "שמשות זהב")
        default: return tr("Aqua Waves", "גלי טורקיז")
        }
    }

    func ballName(_ id: String) -> String {
        switch id {
        case "berry": return tr("Berry", "פטל")
        case "pink": return tr("Pink", "ורוד")
        case "blue": return tr("Bright blue", "כחול זוהר")
        case "cyan": return tr("Cyan", "טורקיז")
        case "green": return tr("Green", "ירוק")
        case "lime": return tr("Yellow-green", "צהוב ירוק")
        case "slate": return tr("Blue-gray", "כחול אפור")
        case "midnight": return tr("Blue-black", "כחול שחור")
        case "rainbow": return tr("Rainbow", "קשת בענן")
        default: return tr("Classic", "קלאסי")
        }
    }

    func controlHelp() -> String {
        if sport == .squash {
            return tr("Beginner: your player runs to the ball. Tap a wall target as the ball arrives (about half a second of timing help). Standard: move yourself, then tap the wall to aim. A floor shot is a fault. Pro: move into reach and swipe the ball itself; direction and speed are yours.",
                      "מתחילים: הדמות רצה לכדור. הקישו על יעד בקיר כשהכדור מגיע, עם עזרה של כחצי שנייה בתזמון. רגיל: זזים בעצמכם ואז מקישים על הקיר לכיוון. חבטה לרצפה היא עבירה. מקצועני: מגיעים לכדור ומחליקים על הכדור עצמו; הכיוון והמהירות בידיכם.")
        }
        return tr("Beginner: move into reach for automatic contact, including high balls. Standard: drag to move, then tap a court target at contact. Tap your player for a smart pass. Double-tap to spike a high ball or set a low ball (first two touches). On the third low ball, Standard cannot spike. Tap the net while close to jump and block. Pro: swipe from the ball; direction and speed control the shot. Swipe up for a high set, down for an overhead hit, or double-tap a high ball to spike. Pro shots can go out or into the net.",
                  "מתחילים: מגיעים לכדור והחבטה אוטומטית, גם בכדור גבוה. רגיל: גררו לתנועה ואז הקישו בזמן על יעד במגרש. הקשה על הדמות בוחרת מסירה חכמה. הקשה כפולה מנחיתה כדור גבוה או מרימה כדור נמוך בשתי הנגיעות הראשונות. בנגיעה השלישית אי אפשר להנחית כדור נמוך במצב רגיל. התקרבו לרשת והקישו עליה כדי לקפוץ ולחסום. מקצועני: החליקו מהכדור; הכיוון והמהירות קובעים. למעלה להרמה, למטה לחבטה עילית, או הקשה כפולה להנחתת כדור גבוה. אפשר להחטיא לחוץ או לרשת.")
    }

    func setup() { page(.setup) }
    func avatars() { page(.avatars) }
    /// Android rebuilds the page with the reception assistance group collapsed.
    func settings() {
        receptionOpen = false
        page(.settings)
    }
    func tutorialIntro() { page(.tutorial) }

    // MARK: Matches

    private func roster(_ demo: Bool = false) -> [Participant] {
        var result = [Participant("you", avatar, 0, demo, tr("You", "אתם"), points())]
        if sport == .squash {
            result.append(Participant("house-0", opponent, 1, true))
        } else {
            for (i, c) in teamMates.prefix(teamSize - 1).enumerated() { result.append(Participant("teammate-\(i)", c, 0, true)) }
            for (i, c) in opponents.prefix(teamSize).enumerated() {
                result.append(Participant("opponent-\(i)", playingCup && i == 0 ? opponent : c, 1, true))
            }
        }
        return result
    }

    func startLocal(tutorial: Bool = false, demo: Bool = false) {
        online?.close()
        online = nil
        let c = config(tutorial)
        let members = tutorial && sport == .squash
            ? [Participant("you", avatar, 0, false, tr("You", "אתם"), points()), Participant("house-0", "minik", 1, true)]
            : roster(demo)
        guard SportsEngine.validRoster(members, c) else { return }
        let e = SportsEngine(c, members, matchId: UUID().uuidString.lowercased())
        if !tutorial {
            if let p = e.profiles["you"], let node = NodeJSON.node(SportsPrefs.string("learning") ?? "{}") { SportsCodec.profile(p, node) }
            e.newQuestion()
        }
        present(e, "you", nil)
    }

    func present(_ e: SportsEngine, _ id: String, _ link: SportsOnline?) {
        view?.teardown()
        resultWorld = nil
        engine = e
        let v = SportsView(engine: e, localId: id, hebrew: hebrew, send: { [weak self, weak e] kind, x, y, power in
            guard let self = self, let e = e else { return }
            if let link = link {
                link.command(kind, x, y, power)
            } else {
                self.nonce += 1
                e.command(id, String(self.nonce), kind, x, y, power)
            }
        }, onEvent: { [weak self, weak e] ev in
            guard let self = self, let e = e else { return }
            self.gameSound(ev, e, id)
        }, onFinish: { [weak self, weak e] in
            guard let self = self, let e = e else { return }
            self.record(e, id)
            self.result(e, id)
        })
        v.receptionZoom = SportsPrefs.bool("receptionZoom", true)
        v.receptionFollow = SportsPrefs.bool("receptionFollow", true)
        if link == nil { e.receptionSlowEnabled[id] = receptionSlow() }
        v.authority = link?.authority ?? true
        view = v
        pausePresented = false
        screen = .game
        revision += 1
        music.setMenu(false)
        link?.view = v
    }

    private func gameSound(_ ev: GameEvent, _ e: SportsEngine, _ id: String) {
        switch ev.type {
        case "swing": sound("minik_kick2")
        case "hit": sound(e.config.sport == .volley || ev.player == id ? "minik_kick" : "minik_kick2")
        case "finished": if e.winner == e.player(id)?.member.team { sound("success_in_a_raw_sound") }
        case "bounce", "wall": sound("ball_hit")
        case "correct": sound("success_sound")
        case "point": sound(e.teamOf(ev.player) == e.player(id)?.member.team ? "success_sound" : "failure_sound")
        default: break // Android's "game_start" serve sound has no file.
        }
    }

    /// Android `sound(name)`.
    func sound(_ name: String) {
        if paused || !soundsOn { return }
        sounds.play(name)
    }

    /// Android tutorial "Next"/"Finish".
    func tutorialNext() {
        guard let e = engine else { return }
        let last = sport == .volley ? 7 : 4
        if e.tutorialStage < last {
            e.tutorialStage += 1
            revision += 1
        } else {
            e.finishTutorial()
            home()
        }
    }

    func tutorialPrevious() {
        guard let e = engine else { return }
        e.tutorialStage = max(e.tutorialStage - 1, 0)
        revision += 1
    }

    var tutorialLast: Bool {
        guard let e = engine else { return false }
        return e.tutorialStage == (sport == .volley ? 7 : 4)
    }

    /// Android `pauseMenu()`.
    func pauseMenu() {
        guard let e = engine else { return }
        view?.cancelTouches()
        view?.running = false
        e.paused = online == nil
        if e.config.tutorial {
            home()
            return
        }
        record(e, online?.uid ?? "you")
        pausePresented = true
    }

    func resumeFromPause() {
        pausePresented = false
        guard let e = engine else { return }
        e.paused = false
        view?.running = true
        view?.setNeedsDisplay()
    }

    func saveForLater() {
        pausePresented = false
        if let e = engine, online == nil, let text = SportsCodec.text(SportsCodec.encode(e)) {
            SportsPrefs.setString(text, e.practice != nil ? "practiceSaved" : "saved")
        }
        home()
    }

    func finishFromPause() {
        pausePresented = false
        if let e = engine { SportsPrefs.remove(e.practice != nil ? "practiceSaved" : "saved") }
        home()
    }

    /// Android `record(e, id)`: the learning profile and the colour points, once per match.
    private func record(_ e: SportsEngine, _ id: String) {
        if e.config.tutorial || e.practice != nil || qa { return }
        if let p = e.profiles[id], let text = SportsCodec.text(SportsCodec.profile(p)) { SportsPrefs.setString(text, "learning") }
        let key = e.matchId + ":" + id
        var receipts = NodeJSON.node(SportsPrefs.string("rankReceipts") ?? "{}") ?? [:]
        let old = receipts.optInt(key)
        let earned = e.earned(id)
        if earned > old {
            receipts[key] = earned
            SportsPrefs.setInt(points() + earned - old, "colourPoints")
            if let text = NodeJSON.string(receipts) { SportsPrefs.setString(text, "rankReceipts") }
        }
    }

    /// Android `result(e, id)`.
    private func result(_ e: SportsEngine, _ id: String) {
        if engine !== e { return }
        if e.practice != nil {
            journeyResult(e)
            return
        }
        SportsPrefs.remove("saved")
        online?.finish(e)
        if cup != nil && playingCup { recordCup(e) }
        page(.result)
        resultWorld = e
        resultId = id
    }

    func refreshOnlineResult() {
        if resultWorld != nil { revision += 1 }
    }

    func learningProfile() -> LearningProfile {
        let profile = LearningProfile()
        if let node = NodeJSON.node(SportsPrefs.string("learning") ?? "{}") { SportsCodec.profile(profile, node) }
        return profile
    }

    // MARK: Local cup (Android `tournament()`)

    var cupState: Node? {
        if cup == nil, let text = SportsPrefs.string("cup") { cup = NodeJSON.node(text) }
        return cup
    }

    static let cupOpponents = ["minik", "mia", "kyra"]

    func tournament() { page(.tournament) }

    func startCup() {
        cup = ["round": 0, "wins": 0, "losses": 0, "results": [String]()]
        persistCup()
        tournament()
    }

    func playCupMatch() {
        guard let c = cupState else { return }
        let round = c.optInt("round")
        guard round < SportsController.cupOpponents.count else { return }
        opponent = SportsController.cupOpponents[round]
        playingCup = true
        startLocal()
    }

    func finishCup() {
        cup = nil
        SportsPrefs.remove("cup")
        home()
    }

    private func recordCup(_ e: SportsEngine) {
        guard var c = cup else { return }
        var ids = (c["ids"] as? [Any])?.map { NodeValue.text($0) } ?? []
        if ids.contains(e.matchId) { return }
        ids.append(e.matchId)
        c["ids"] = ids
        c["round"] = c.optInt("round") + 1
        let k = e.winner == 0 ? "wins" : "losses"
        c[k] = c.optInt(k) + 1
        var results = (c["results"] as? [Any])?.map { NodeValue.text($0) } ?? []
        results.append("\(e.scores[0]) : \(e.scores[1])")
        c["results"] = results
        cup = c
        persistCup()
    }

    private func persistCup() {
        if let c = cup, let text = NodeJSON.string(c) { SportsPrefs.setString(text, "cup") }
    }

    // MARK: Online (Android `onlinePage`, `connect`, `publicTournaments`, `lobby`)

    /// Android builds a new, empty room-code field every time.
    func onlinePage() {
        roomCode = ""
        page(.online)
    }

    func connect(_ code: String?, publicCup: Bool = false) {
        online?.close()
        let link = SportsOnline(host: self, config: config(), avatar: avatar, points: points(),
                                rounds: publicCup ? max(onlineRounds, 3) : onlineRounds, publicCup: publicCup)
        online = link
        link.open(code)
    }

    func publicTournaments(_ entries: [(String, Int, String)]) {
        publicEntries = entries.map { PublicEntry(code: $0.0, rounds: $0.1, count: $0.2) }
        page(.publicTournaments)
    }

    func lobby(_ code: String, _ members: [Participant], _ ready: Set<String>, _ host: Bool, _ link: SportsOnline) {
        lobbyModel = SportsLobbyModel(code: code, members: members, ready: ready, host: host, uid: link.uid)
        page(.lobby)
        SportsPrefs.setString(code, "room")
    }

    func copyCode(_ code: String) {
        UIPasteboard.general.string = code
        message(tr("Code copied", "הקוד הועתק"))
    }

    func lobbyReady() { online?.ready() }
    func lobbyStart() { online?.start() }

    func onlineError(_ text: String) { message(text) }

    // MARK: Parent gate and zone

    /// Android `parentGate(action)`: "For a grown-up: 8 × 7 = ?".
    func parentGate(_ action: @escaping () -> Void) {
        gateAnswer = ""
        gateAction = action
        gatePresented = true
    }

    func confirmGate() {
        let action = gateAction
        gatePresented = false
        gateAction = nil
        if gateAnswer.trimmingCharacters(in: .whitespaces) == "56" {
            action?()
        } else {
            message(tr("Please try again.", "נסו שוב."))
        }
    }

    func cancelGate() {
        gatePresented = false
        gateAction = nil
    }

    func parentZone() { page(.parentZone) }
    func privacyPage() { page(.privacy) }

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
        paused = true
        music.setForeground(false)
        view?.cancelTouches()
        view?.running = false
        if let e = engine, online == nil, !e.config.tutorial, e.phase != .finished {
            e.paused = true
            record(e, "you")
            if let text = SportsCodec.text(SportsCodec.encode(e)) { SportsPrefs.setString(text, e.practice != nil ? "practiceSaved" : "saved") }
        }
        online?.setForeground(false)
        sounds.setPaused(true)
    }

    private func onResume() {
        paused = false
        if let v = view, !pausePresented {
            engine?.paused = false
            v.running = true
            v.setNeedsDisplay()
        }
        online?.setForeground(true)
        music.setForeground(true)
        menuMusic()
        sounds.setPaused(false)
    }
}
