import Foundation
import Combine

struct ModernPongResult: Codable, Equatable { var playerPoints: Int; var opponentPoints: Int; var won: Bool }
/// `cross`: the local 3/4-player match and its guide (Android CrossActivity). `journey`: the daily skill journey, the team game
/// with house players and Settings (CrossJourneyActivity). `teams`: online team rooms (CrossOnlineTeamsActivity).
enum MPRoute { case menu, lobby, game, guide, result, cross, journey, teams }
/// A card of the cross guide (Android CrossActivity.showGuideCard).
struct CrossTourCard: Equatable {
    var title: String; var message: String; var phase: CrossTutorial.Phase; var canGoBack: Bool
    /// The team and scoring cards offer the team game (Android 5c1aa4d, R.string.guide_team_practice).
    var teamPractice = false
}
/// The local cross match's result (Android CrossActivity.showResult).
struct CrossLocalResult: Equatable { var title: String; var lines: [String]; var won: Bool }

/// Multi Ping Pong's screen state and flows: Android PlayActivity (home, forms, rooms, tournaments), PrivateMatchActivity (a
/// room fixture on the classic or the cross table) and CrossActivity (the local cross match and its guide), MinikCrossPong
/// 828c6fc. The Simple experience keeps the classic single-player game and guide.
@MainActor final class MPController: ObservableObject {
    let experience: ModernPongExperience, preferences: MPPreferences, audio = MPAudio(), ads: MPAds
    @Published var route = MPRoute.menu { didSet { syncMusic() } }
    /// Android CrossJourneyActivity and CrossOnlineTeamsActivity, opened over the home (or the local cross match).
    @Published var journey: CrossJourneyModel?
    @Published var teams: CrossTeamsModel?
    /// A short message (Android Toast).
    @Published var toast: String?
    /// Back from an unfinished tournament asks whether to keep it (Android confirmTournamentExit).
    @Published var tournamentExitPrompt = false
    private var journeyReturn = MPRoute.menu, teamsReturn = MPRoute.menu
    /// Android PongMenuMusic: the quiet menu remix on the home and room screens.
    private let menuMusic = MPXMenuMusic()
    @Published var scene: MPScene?
    @Published var crossScene: CrossScene?
    @Published var session: MPSession?
    @Published var fixture: MPFixture?
    @Published var identity: MPIdentity?
    @Published var rooms: [MPSession] = []
    /// Android VictoryConfetti: a new value starts one brief, noninteractive celebration.
    @Published var celebration: UUID?
    @Published var busy = false
    @Published var error: String?
    @Published var errorTitle: String?
    @Published var connected = false
    @Published var connecting = false
    /// Android `LocalizedActivity.hebrew` (`AppText.language == "he"`); `start(hebrew:)` sets it again from the view.
    @Published var hebrew = MPText.language == "he"
    @Published var level: MPLevel
    @Published var target: Int
    @Published var playerIndex = 0
    @Published var childScore = 0
    @Published var opponentScore = 0
    @Published var status = ""
    @Published var result: ModernPongResult?
    @Published var tutorialStep = MPTutorialStep.serveMiddle
    @Published var tutorialPhase = MPTutorialPhase.explanation
    @Published var tutorialSuccess = false
    /// "Don't show the guide automatically" (Android `hide_tutorial`). Saved as soon as it changes.
    @Published var skipGuide: Bool { didSet { preferences.skipGuide = skipGuide } }
    @Published var paused = false
    @Published var practice = false
    @Published var practiceLevel: MPLevel
    /// Cross court status line and header (Android CrossActivity / PrivateMatchActivity).
    @Published var crossStatus = ""
    @Published var crossHeader = ""
    @Published var crossPaused = false
    /// Android `cross/action_camera` (5c1aa4d): the landscape action camera of the local cross court, remembered.
    @Published var actionCamera: Bool { didSet { preferences.crossActionCamera = actionCamera; if crossMatch == nil { crossScene?.fullScreen = actionCamera } } }
    @Published var tourCard: CrossTourCard?
    @Published var crossResult: CrossLocalResult?
    @Published var crossTourActive = false
    private var repo: any MPRepository, subscriptions: [MPSubscription] = [], link: MPMatchLink?
    private var presenceSubscription: MPSubscription?, acquiringPresence = false
    private var foreground = true, started = false, closing = false
    /// Android PlayActivity `opened`: matches whose court already opened once; re-entering a saved game opens its controls.
    private var opened = Set<String>(), firstSnapshot = true, lobbyPrevious: MPSession?
    /// Android RoomStartGate: an observer update during a start/Ready transaction is checked again at completion.
    private var gatePending = false, gateLatest: MPSession?
    private var liveID = "", handledResults = Set<String>(), renderAt: Int64 = 0, activityAt: Int64 = 0, demoGesture = false
    /// Android ModernActivity opens the guide before its local match unless hidden. `resumeAfterGuide` remembers that match
    /// (its practice flag) so "To the game" continues it.
    private var guideOffered = false, resumeAfterGuide: Bool?
    private var completion: (ModernPongResult?) -> Void
    private var crossMatch: CrossMatch?, crossLink: CrossLink?, crossSounds: CrossSoundPolicy?, crossOutcome: CrossRallyOutcome?
    private var crossStage: ObjectIdentifier?, crossWarning = "", crossAudioOn = false
    /// The local cross match's engine, or the guide's engine while a lesson plays.
    private var localCross: CrossEngine?
    private var tour: CrossTutorial?, savedGame: CrossEngine?, finishedShown = false
    private static let practiceLevelKey = "modern.pong.practice.level"
    /// CI smoke launches pass `-MinikOfflineSmoke YES`; they must never reach production Firebase.
    static var offlineSmoke: Bool { UserDefaults.standard.bool(forKey: "MinikOfflineSmoke") }
    init(experience: ModernPongExperience, preferences: MPPreferences = .init(), repository: (any MPRepository)? = nil, onClose: @escaping (ModernPongResult?) -> Void) {
        self.experience = experience; self.preferences = preferences; completion = onClose; ads = .init(preferences: preferences, experience: experience)
        level = preferences.control; target = preferences.control.target(preferences.target); skipGuide = preferences.skipGuide; identity = preferences.identity
        actionCamera = preferences.crossActionCamera
        // Android's local level defaults to Beginner (ModernActivity getInt("difficulty", 4)).
        let savedPractice = preferences.defaults.object(forKey: MPController.practiceLevelKey) as? Int
        practiceLevel = savedPractice.flatMap { MPLevel(rawValue: $0) } ?? .beginner
        if let repository { repo = repository }
        else if MPController.offlineSmoke { repo = MPLocalRepository() }
        else {
            // Without this app's GoogleService-Info.plist (or with a plist for another app) `configured()` is nil and every room
            // lives on this phone with house players, as Android does while its package is not registered.
            #if MINIK_PING_PONG && canImport(FirebaseDatabase) && canImport(FirebaseAuth)
            repo = experience.online ? (MPFirebaseRepository.configured() as (any MPRepository)?) ?? MPLocalRepository() : MPLocalRepository()
            #else
            repo = MPLocalRepository()
            #endif
        }
    }
    var online: Bool { repo.online }
    var selectedPlayer: MPHousePlayer { MPRoster.all[playerIndex % MPRoster.all.count] }
    var userID: String { repo.uid }
    /// Android `tr(en, he)` = `AppText.t(en, he, hebrew)`: Hebrew, or the app language's catalog text, or English.
    func text(_ english: String, _ hebrew: String) -> String { MPText.t(english, hebrew, self.hebrew) }
    func start(hebrew: Bool, removeAds: Bool) async {
        self.hebrew = hebrew; guard !started else { return }; started = true
        // Android PlayActivity.onResume: the menu music starts with the home screen (route and lifecycle changes follow).
        syncMusic()
        ads.start(removeAds: removeAds)
        ads.willPresent = { [weak self] in self?.audio.stop() }
        guard experience.online else { return }
        connecting = true; defer { connecting = false }
        do {
            let uid = try await repo.connect()
            if identity?.id != uid {
                let old = identity; identity = try await repo.profile(index: 0, hebrew: hebrew, avatar: old?.avatar ?? 0, character: old?.characterId ?? "miniko")
                preferences.identity = identity
            }
            connected = true; try await refreshRooms()
        } catch { show(error) }
    }
    func retryOnline(removeAds: Bool) async { guard !connecting else { return }; started = false; await start(hebrew: hebrew, removeAds: removeAds) }
    func perform(_ operation: @escaping () async throws -> Void) async {
        guard !busy else { return }; busy = true; defer { busy = false }
        do { try await operation() } catch { show(error) }
    }
    /// Android PlayActivity.error: the open-game limit has its own dialog; everything else one of a few plain explanations.
    private func show(_ issue: Error) {
        errorTitle = nil
        if let e = issue as? MPError {
            switch e {
            case .limit:
                errorTitle = text("Open-game limit reached", "הגעתם למספר המשחקים המרבי")
                error = text("You can keep up to three open friendly games and three open tournaments. To create another game, open Your games and choose Finish on one of them. You can also resume a saved game.",
                             "אפשר לשמור עד שלושה משחקי ידידות פתוחים ושלושה טורנירים פתוחים. כדי ליצור משחק נוסף, פתחו את המשחקים שלכם ובחרו סיום באחד מהם. אפשר גם להמשיך משחק שמור.")
            case .missing: error = text("No online game or tournament exists with this code. Check the code with its creator.", "לא נמצא משחק או טורניר מקוון עם הקוד הזה. בדקו את הקוד עם מי שיצר אותו.")
            case .left: error = text("You have left this tournament.", "עזבתם את הטורניר הזה.")
            default: error = text("This action could not be completed. Check the code or connection and try again.", "לא ניתן להשלים את הפעולה. בדקו את הקוד או את החיבור ונסו שוב.")
            }
            return
        }
        if issue.localizedDescription.lowercased().contains("permission") {
            error = text("Online play is temporarily unavailable. Please try again later.", "המשחק המקוון אינו זמין כרגע. נסו שוב מאוחר יותר.")
        } else {
            error = text("This action could not be completed. Check the code or connection and try again.", "לא ניתן להשלים את הפעולה. בדקו את הקוד או את החיבור ונסו שוב.")
        }
    }
    func saveControls() { preferences.control = level; target = level.target(target); preferences.target = target }
    func profile(index: Int, avatar: Int, character: String) async {
        await perform {
            self.identity = try await self.repo.profile(index: index, hebrew: self.hebrew, avatar: avatar, character: character)
            self.preferences.identity = self.identity
        }
    }
    /// Android RoomPolicy: three open games and three open tournaments.
    func hasSpace(_ kind: MPSessionKind) -> Bool { rooms.filter { $0.kind == kind && $0.state != "FINISHED" }.count < 3 }
    /// Android PlayActivity.create: a room with only its host; house players are chosen on the room screen.
    func create(_ kind: MPSessionKind, capacity: Int, legs: Int, winPoints: Int, target: Int, format: MPTournamentFormat,
                tableSize: Int, gameMode: MPGameMode, advance: Int) async {
        saveControls()
        if !hasSpace(kind) { show(MPError.limit); return }
        await perform {
            guard let identity = self.identity else { throw MPError.configuration }
            let s = MPSession(code: MPRules.code(), kind: kind, host: identity, capacity: capacity, legs: legs, winPoints: winPoints,
                              difficulty: self.level.rawValue, target: target, format: format, tableSize: tableSize, gameMode: gameMode, advance: advance)
            let created = try await self.repo.create(s)
            self.enter(created)
        }
    }
    /// Android PlayActivity.join: a code of the form's room type; online rooms only.
    func join(_ kind: MPSessionKind, _ raw: String) async {
        guard online else {
            errorTitle = nil
            error = text("Online rooms are not available in this version yet.", "חדרים מקוונים עדיין לא זמינים בגרסה הזו.")
            return
        }
        await perform {
            guard let identity = self.identity else { throw MPError.configuration }
            let code = try MPRules.normalize(raw)
            guard let old = try await self.repo.get(kind, code) else { throw MPError.missing }
            if old.departed[identity.id] == true { throw MPError.left }
            if old.participants[identity.id] != nil { self.enter(old); return }
            guard self.hasSpace(kind) else { throw MPError.limit }
            try await self.repo.reserve(kind, code)
            let s = try await self.repo.mutate(kind, code) { try MPRules.join($0, identity) }
            self.enter(s); self.audio.play("connected")
        }
    }
    func enter(_ s: MPSession) {
        closeObservers(); closing = false
        firstSnapshot = true; lobbyPrevious = nil; gatePending = false; gateLatest = nil
        session = s; route = .lobby; result = nil; fixture = nil; scene = nil; clearCross(); celebration = nil
        subscriptions.append(repo.observe(s.kind, s.code) { [weak self] value in
            guard let self, !self.closing else { return }
            switch value {
            case .success(let room): self.receive(room)
            case .failure(let error):
                if error as? MPError == .missing { self.roomGone(s) } else { self.show(error) }
            }
        })
        if session?.id == s.id { syncLobbyPresence(session ?? s) }
        preferences.remember(session ?? s); rooms = preferences.rooms
        refreshIdentity(session ?? s)
    }
    /// Android PlayActivity.openRoom: an online room shows this player's current nickname and avatar.
    private func refreshIdentity(_ s: MPSession) {
        guard online, let me = identity?.safe(), let p = s.participants[repo.uid], p.bot == nil, s.human(repo.uid), p.identity != me else { return }
        let uid = repo.uid
        Task { [weak self] in
            guard let self else { return }
            _ = try? await self.repo.mutate(s.kind, s.code) { room in
                guard let mine = room.participants[uid], mine.bot == nil, room.human(uid), mine.identity != me else { return room }
                var n = room; n.participants[uid]?.identity = me; return n
            }
        }
    }
    private func roomGone(_ s: MPSession) {
        preferences.removed(s); closeObservers(); session = nil; scene = nil; clearCross(); fixture = nil; rooms = preferences.rooms; route = .menu
    }
    /// Android LobbyEvents: compare durable events, not render calls or presence-token churn.
    private func lobbyCues(_ s: MPSession) -> (join: Bool, ready: Bool) {
        let previous = lobbyPrevious
        lobbyPrevious = s
        guard let old = previous, old.code == s.code else { return (false, false) }
        let uid = repo.uid
        let join = s.participants.keys.contains { $0 != uid && s.human($0) && old.participants[$0] == nil }
        let ready = s.matches.values.contains { m in
            m.contains(uid) && !m.terminal && m.players.contains { peer in
                let before = old.matches[m.id]
                return peer != uid && s.human(peer) && ((m.ready[peer] == true && before?.ready[peer] != true) ||
                    (m.phase == .playing && before?.phase != .playing && before?.ready[peer] != true))
            }
        }
        return (join, ready)
    }
    private func receive(_ s: MPSession) {
        let uid = repo.uid
        if !s.human(uid) {
            // Android: a player who is no longer a member (left, removed) leaves the room screen and forgets the room.
            preferences.removed(s); closeObservers(); session = nil; scene = nil; clearCross(); fixture = nil; rooms = preferences.rooms
            if route != .menu { route = .menu }
            return
        }
        let cues = lobbyCues(s)
        if cues.join { audio.play("connected") }; if cues.ready { audio.play("player_ready") }
        if firstSnapshot {
            // Re-entering a saved game opens its controls, not the court automatically.
            for m in s.matches.values where m.contains(uid) && m.phase == .playing { opened.insert(m.id) }
            firstSnapshot = false
        }
        session = s; link?.update(s); crossLink?.update(s); preferences.remember(s); rooms = preferences.rooms
        // Android PlayActivity.completed: a room completed while it is shown celebrates the winner once.
        if route == .lobby, s.complete, MPCompletionText.won(s, uid), preferences.firstCelebration(s) { celebration = UUID() }
        if route == .game, let current = fixture, let m = s.matches[current.id] {
            if m.phase == .finished {
                fixture = m
                let points = m.a == uid ? (m.scoreA, m.scoreB) : (m.scoreB, m.scoreA)
                finish(id: m.id, value: .init(playerPoints: points.0, opponentPoints: points.1, won: m.winner == uid))
                return
            }
            // Android PrivateMatchActivity closes when its fixture is no longer playing (a departure cancelled it).
            if m.phase != .playing { leaveCourt() }
        }
        if route == .lobby { maybeStart(s) }
        if route != .game && foreground, let latest = session { syncLobbyPresence(latest) }
    }
    /// Android PlayActivity.maybeStart: a full friendly room starts; a newly PLAYING fixture of this player opens its court once;
    /// the host of a house-player friendly table is Ready by pressing Start; a fixture whose humans are all Ready starts.
    private func maybeStart(_ s: MPSession) {
        guard foreground, !closing, route == .lobby, session?.id == s.id else { return }
        let uid = repo.uid
        gateLatest = s
        if s.kind == .friendly && s.state == "WAITING" && s.participants.count == s.capacity && s.host == uid && !gatePending {
            transition(s) { try MPRules.start($0, actor: uid) }
            return
        }
        if let playable = s.matches.values.sorted(by: { $0.id < $1.id }).first(where: { $0.contains(uid) && $0.phase == .playing }), !opened.contains(playable.id) {
            opened.insert(playable.id); launch(s, playable); return
        }
        if gatePending { return }
        if MPRules.friendlyHouseReady(s, actor: uid) != s { transition(s) { MPRules.friendlyHouseReady($0, actor: uid) }; return }
        if let next = s.matches.values.sorted(by: { $0.id < $1.id }).first(where: { $0.contains(uid) && MPRules.startReady(s, match: $0.id) != s }) {
            let id = next.id
            transition(s) { MPRules.startReady($0, match: id) }
        }
    }
    private func transition(_ s: MPSession, _ change: @escaping (MPSession) throws -> MPSession) {
        gatePending = true; gateLatest = nil
        let kind = s.kind, code = s.code
        Task { [weak self] in
            guard let self else { return }
            var updated: MPSession?
            do { updated = try await self.repo.mutate(kind, code, change) }
            catch {
                // Android roomActionFailed: only the room still shown is affected.
                if self.session?.code == code {
                    if error as? MPError == .missing { self.roomGone(s) } else if !self.closing { self.show(error) }
                }
            }
            self.gatePending = false
            let latest = self.gateLatest
            self.gateLatest = nil
            // Firebase may notify observers before completing the transaction: after a success, revisit the newest observed room.
            if updated != nil, let next = latest ?? updated, self.foreground, !self.closing, self.session?.code == code { self.maybeStart(next) }
        }
    }
    private func change(_ action: @escaping (MPSession) throws -> MPSession) async {
        guard let s = session else { return }
        await perform { _ = try await self.repo.mutate(s.kind, s.code, action) }
    }
    /// A friendly table's house player (Android "Start" with a chosen opponent, or "Add house player" on a seat).
    func addFriendlyHouse(_ player: MPHousePlayer, seat: Int? = nil) async {
        let uid = repo.uid, bot = MPRules.housePlayer(player)
        await change { room in
            let free = seat ?? room.freeSeats().first
            return try MPRules.addFriendlyHousePlayer(room, actor: uid, bot: bot, seat: room.tableSize > 2 ? free : nil)
        }
    }
    /// A tournament's house player; characters may repeat ("Kyra 2").
    func addHouse(_ player: MPHousePlayer) async {
        let uid = repo.uid, bot = MPRules.housePlayer(player)
        // Android 5c1aa4d: checked again against the latest room; a full or started room stays as it is.
        await change { room in
            if room.state != "WAITING" || room.host != uid || room.participants.count >= room.capacity || room.participants[bot.id] != nil { return room }
            return try MPRules.addBot(room, actor: uid, bot: bot)
        }
    }
    func fillWithHouse() async {
        let uid = repo.uid
        await change { room in
            if room.state != "WAITING" || room.host != uid { return room }
            return try MPRules.fillWithBots(room, actor: uid)
        }
    }
    /// Android 5c1aa4d: a fixture whose only human is this player starts with "Start" (Ready on its own).
    func startHouseMatch(_ match: MPFixture) async {
        let uid = repo.uid
        await change { try MPRules.ready($0, match: match.id, uid: uid, value: true) }
    }
    /// Host removes a house player before the start (Android PlayActivity).
    func removeHouse(_ id: String) async {
        let uid = repo.uid
        await change { try MPRules.removeHouse($0, actor: uid, id: id) }
    }
    func removeAllHouse() async {
        let uid = repo.uid
        await change { try MPRules.removeAllHouse($0, actor: uid) }
    }
    func chooseSeat(_ seat: Int) async {
        let uid = repo.uid
        await change { try MPRules.chooseSeat($0, actor: uid, seat: seat) }
    }
    func startTournament() async {
        let uid = repo.uid
        await change { try MPRules.start($0, actor: uid) }
    }
    func ready(_ match: MPFixture) async {
        guard let s = session else { return }
        let uid = repo.uid
        if match.phase == .playing { opened.insert(match.id); launch(s, match); return }
        await change { try MPRules.ready($0, match: match.id, uid: uid, value: match.ready[uid] != true) }
    }
    /// Android leaveFriendly(delete = false): back home, the room stays in Your games.
    func saveForLater() {
        guard let s = session else { return }
        closing = true; closeObservers(); preferences.remember(s)
        session = nil; scene = nil; clearCross(); fixture = nil; rooms = preferences.rooms; route = .menu
        closing = false
    }
    func leave(delete: Bool) async {
        guard let s = session else { return }
        await perform {
            self.closing = true; self.closeObservers()
            do { try await self.repo.leave(s, delete: delete); self.preferences.closed(s); self.rooms = self.preferences.rooms; self.session = nil; self.scene = nil; self.clearCross(); self.route = .menu }
            catch { self.enter(s); throw error }
        }
    }
    func refreshRooms() async throws {
        // Android PlayActivity.refreshRooms: cleanup and listing failures are only logged; a room that cannot be read is skipped.
        // Keep local history until a successful server read confirms deletion.
        try? await repo.cleanup()
        let known: [(MPSessionKind, String)] = (try? await repo.openRooms()) ?? []
        var keys = Set<String>()
        for (kind, code) in known + preferences.rooms.map({ ($0.kind, $0.code) }) {
            let id = kind.path + "/" + code; guard keys.insert(id).inserted else { continue }
            let read: MPSession?
            do { read = try await repo.get(kind, code) } catch { continue }
            if let s = read, s.human(repo.uid) { preferences.remember(s) }
            else if let old = preferences.rooms.first(where: { $0.id == id }) { preferences.removed(old) }
        }
        rooms = preferences.rooms
    }
    /// Android "Done" on a completed room (and Back from it): the result is dismissed, never kept as history; a local copy is
    /// removed.
    func dismissCompleted() {
        guard let s = session else { return }
        celebration = nil; preferences.dismissResult(s); closeObservers(); (repo as? MPLocalRepository)?.remove(s)
        session = nil; scene = nil; clearCross(); fixture = nil; result = nil; rooms = preferences.rooms; route = .menu
    }
    /// Android PrivateMatchActivity result dialog: a completed round robin or friendly room is dismissed; a completed knockout
    /// first shows its bracket; an unfinished room continues on its screen (a table's final duel, the next round).
    func closeResult() {
        celebration = nil
        guard let s = session else { result = nil; route = .menu; return }
        if s.complete && !s.knockout { dismissCompleted(); return }
        scene = nil; clearCross(); fixture = nil; result = nil
        route = .lobby
        maybeStart(s)
        if foreground { syncLobbyPresence(s) }
    }
    private func launch(_ s: MPSession, _ match: MPFixture) {
        link?.close(); link = nil; crossLink?.close(); crossLink = nil
        practice = false; paused = false; fixture = match; liveID = match.id; celebration = nil; crossWarning = ""
        acquirePresence(s)
        if MPCrossFixture.usesCross(match) { launchCross(s, match); return }
        clearCross()
        let opponent = s.participants[match.a == repo.uid ? match.b : match.a], networked = opponent?.bot == nil
        // Android PrivateMatchActivity (828c6fc): the authority serves first; a house-player fixture alternates serves; a
        // two-player tie-break is decided by its first point.
        let engine = MPEngine(level: MPLevel.control(s.difficulty), target: s.target, bot: opponent?.bot, networked: networked,
                              first: s.authority(match) == repo.uid ? .child : .minik, seed: UInt64(bitPattern: match.seed),
                              alternateServe: !networked, suddenDeath: match.goal == .tiebreak)
        install(engine); scene?.remoteCharacter = opponent?.identity.characterId; scene?.remoteIcon = MPNames.icons[max(0, opponent?.identity.avatar ?? 0) % MPNames.icons.count]
        let link = MPMatchLink(repo: repo, session: s, record: match, engine: engine, preferences: preferences) { [weak self] in self?.show($0) }
        self.link = link; link.active = foreground; route = .game; link.open()
    }
    /// Android PrivateMatchActivity.crossSession: a 3/4-player (or three-way tie-break) fixture on the shared cross table, one
    /// authority, every human paused together.
    private func launchCross(_ s: MPSession, _ m: MPFixture) {
        scene = nil
        let seats = CrossLink.seats(s, m, uid: repo.uid)
        let match = CrossMatch(roster: seats, control: CrossControl.fromChoice(s.difficulty), target: MPCrossFixture.target(s, m), seed: m.seed,
                               networked: seats.contains { $0.kind == .remote }, firstServer: CrossLink.firstServer(m),
                               mode: MPCrossFixture.mode(s), goal: MPCrossFixture.goal(s, m))
        match.paused = true
        let court = CrossScene(engine: match.engine)
        court.step = { [weak match] dt in
            guard let match else { return }
            match.advance(dt)
        }
        court.onFrame = { [weak self] in self?.crossFrame() }
        court.preferences = preferences
        // Android PrivateMatchActivity reads the old `cross_local/full_screen` (default off) and offers no camera button.
        court.fullScreen = preferences.crossFullScreen
        crossMatch = match; crossScene = court; crossStage = nil; crossOutcome = nil; crossAudioOn = false
        localCross = nil; tour = nil; tourCard = nil; crossResult = nil
        syncStage(s, m)
        let id = m.id, prefs = preferences
        let link = CrossLink(repo: repo, session: s, record: m, match: match, nextSequence: { prefs.sequence(id) },
                             message: { [weak self] issue in self?.crossIssue(issue) })
        link.active = foreground
        crossLink = link
        route = .game
        link.open()
        court.setActive(foreground)
        crossStatus = ""; crossHeader = ""
    }
    private func crossIssue(_ issue: CrossLinkIssue) {
        switch issue {
        case .version: crossWarning = text("This match needs the same app version on every phone.", "המשחק הזה צריך את אותה גרסת אפליקציה בכל הטלפונים.")
        case .interrupted: crossWarning = text("Connection interrupted. Reopen this match to resume.", "החיבור נקטע. פתחו שוב את המשחק כדי להמשיך.")
        case .failed: crossWarning = text("Connection interrupted. Reopen this match to resume.", "החיבור נקטע. פתחו שוב את המשחק כדי להמשיך.")
        // Android passes the link's English message through unchanged.
        case .reception: crossWarning = "Ball assistance could not be shared. The match uses normal speed until it connects."
        }
    }
    /// Names in fixture (roster) order.
    private func crossNames(_ s: MPSession, _ m: MPFixture) -> [String] {
        m.players.map { $0 == repo.uid ? text("You", "אתם") : (s.participants[$0]?.name(hebrew: hebrew) ?? "?") }
    }
    /// Android PrivateMatchActivity.matchStage: the knockout stage of this fixture, marked as a tie-break or final duel.
    func matchStage(_ s: MPSession, _ m: MPFixture) -> String {
        guard let round = s.rounds.keys.sorted().first(where: { r in MPKnockout.fixtures(s, r).contains { $0.id == m.id } }),
              let players = s.rounds[round]?.players.count else { return MPKnockout.stage(s, hebrew: hebrew) }
        let stage = s.grouped ? MPGroupTournament.stage(players, s.tableSize, hebrew: hebrew, advance: MPKnockout.perTable(s)) : MPKnockout.stage(players: players, hebrew: hebrew)
        if m.goal == .tiebreak { return stage + " · " + text("Tie-break", "שובר שוויון") }
        if MPRules.isDuel(m) { return stage + " · " + text("Final duel", "קרב גמר") }
        return stage
    }
    /// A new table stage (elimination shrinks it): the court, its names/avatars and the sound policy follow.
    private func syncStage(_ s: MPSession, _ m: MPFixture) {
        guard let match = crossMatch, let court = crossScene else { return }
        let current = ObjectIdentifier(match.engine)
        if crossStage == current { return }
        crossStage = current
        if court.engine !== match.engine { court.engine = match.engine }
        let names = crossNames(s, m)
        court.names = match.active.map { $0 >= 0 && $0 < names.count ? names[$0] : "?" }
        var icons: [Int: String] = [:]
        for (i, f) in match.active.enumerated() where f >= 0 && f < m.players.count {
            if let p = s.participants[m.players[f]], p.bot == nil { icons[i] = MPNames.icons[min(5, max(0, p.identity.avatar))] }
        }
        court.avatarIcons = icons
        crossSounds = CrossSoundPolicy(localSeat: match.engine.localSeat)
    }
    private func crossFrame() {
        guard let match = crossMatch, let court = crossScene else { return }
        let events = match.drainEvents()
        if let s = session, let m = fixture { syncStage(s, m) }
        for event in events {
            if let policy = crossSounds { for cue in policy.cues(event) { audio.play(cue.sound) } }
            if case let .rally(outcome) = event { crossOutcome = outcome; court.showOutcome(outcome) }
        }
        crossLink?.frame(events)
        updateCrossPause()
        let now = MPClock.now
        guard now - renderAt >= 100, let s = session, let m = fixture else { return }
        renderAt = now
        crossHeader = (s.knockout ? matchStage(s, m) + " · " : "") + MPControlChoice.title(s.difficulty, hebrew: hebrew)
        if crossLink?.ready != true {
            crossStatus = text("Waiting for every player to connect. Everyone must keep the match open.", "ממתינים שכל השחקנים יתחברו. כולם צריכים להשאיר את המשחק פתוח.")
        } else if !crossWarning.isEmpty { crossStatus = crossWarning }
        else if match.finished { crossStatus = text("Saving result…", "שומרים תוצאה…") }
        else { crossStatus = CrossText.matchStatus(match, names: crossNames(s, m), last: crossOutcome, hebrew: hebrew) }
    }
    private func updateCrossPause() {
        guard let match = crossMatch else { return }
        let playing = fixture.flatMap { session?.matches[$0.id]?.phase } == .playing
        let enabled = foreground && crossLink?.ready == true && playing
        match.paused = !enabled
        if enabled != crossAudioOn { crossAudioOn = enabled; if !enabled { audio.stop() } }
        if route == .game && foreground && enabled && !match.finished && MPClock.now - activityAt >= 1000 { activityAt = MPClock.now }
    }
    /// The court of a room fixture is left for its room screen; the fixture keeps PLAYING and pauses for the others.
    private func leaveCourt() {
        link?.close(); link = nil; crossLink?.close(); crossLink = nil
        scene?.setActive(false); scene = nil; clearCross()
        route = .lobby
        releasePresence()
        if let s = session { syncLobbyPresence(s) }
    }
    private func clearCross() {
        crossLink?.close(); crossLink = nil
        crossScene?.setActive(false); crossScene = nil
        crossMatch = nil; crossStage = nil; crossSounds = nil; crossOutcome = nil; crossStatus = ""; crossHeader = ""
        localCross = nil; tour = nil; savedGame = nil; tourCard = nil; crossResult = nil; crossTourActive = false
    }
    func startSingle(practice: Bool = false) {
        // Like Android ModernActivity: the guide opens before this screen's first local match unless "Don't show the guide
        // automatically" is on. "To the game" then starts the requested match.
        if !practice && !skipGuide && !guideOffered && route != .guide {
            guideOffered = true; guide(); resumeAfterGuide = practice; return
        }
        audio.stop(); saveControls(); closeObservers(); session = nil; fixture = nil; result = nil; celebration = nil; liveID = UUID().uuidString
        clearCross()
        self.practice = practice; paused = false
        preferences.defaults.set(practiceLevel.rawValue, forKey: MPController.practiceLevelKey)
        install(MPEngine(level: practice ? practiceLevel : level, target: target, bot: selectedPlayer.profile, houseControls: !practice)); route = .game
    }
    private func install(_ engine: MPEngine) {
        let scene = MPScene(engine: engine); self.scene = scene
        scene.onFrame = { [weak self] events in self?.frame(events) }; scene.setActive(foreground)
        childScore = engine.score.child; opponentScore = engine.score.minik; activityAt = MPClock.now
    }
    private func frame(_ events: [MPEvent]) {
        guard let scene else { return }; let engine = scene.engine, now = MPClock.now
        if let link { engine.paused = !link.ready; link.frame(events) }
        audio.events(events)
        if route == .guide { tutorialFrame(); return }
        if now - renderAt >= 100 {
            renderAt = now; childScore = engine.score.child; opponentScore = engine.score.minik
            // Display-only hint; the engine's wire status stays one of Android's GameStatus names.
            if link != nil && link?.ready != true { status = "WAITING" }
            else if engine.score.winner != nil && link != nil { status = "SAVING" }
            else if engine.automaticContact && engine.childReturnOpen { status = "AUTO_HINT" }
            else { status = engine.status }
        }
        if route == .game && foreground && !engine.paused && now - activityAt >= 1000 { ads.active(now - activityAt); activityAt = now }
        if link == nil, let winner = engine.score.winner, route == .game, session == nil { finish(id: liveID, value: .init(playerPoints: engine.score.child, opponentPoints: engine.score.minik, won: winner == .child)) }
    }
    /// Classic room status (Android PrivateMatchActivity 828c6fc): waiting, saving, serve, return or playing against `other`.
    func classicRoomStatus(_ other: String) -> String {
        guard let engine = scene?.engine else { return "" }
        if status == "WAITING" { return text("Waiting for connection. Both players must keep the match open.", "ממתינים לחיבור. שני השחקנים צריכים להשאיר את המשחק פתוח.") }
        if engine.score.winner != nil { return text("Saving result…", "שומרים תוצאה…") }
        if engine.awaitingServe { return text("Your serve · playing \(other)", "ההגשה שלכם · מול \(other)") }
        if engine.childReturnOpen {
            return engine.automaticContact ? text("Move the paddle to the ball · automatic hit", "הזיזו את המחבט לכדור · חבטה אוטומטית") : text("Return the ball", "החזירו את הכדור")
        }
        return text("Playing \(other)", "משחקים מול \(other)")
    }
    private func finish(id: String, value: ModernPongResult) {
        guard handledResults.insert(id).inserted else { return }
        scene?.setActive(false); link?.close(); link = nil
        crossScene?.setActive(false); crossLink?.close(); crossLink = nil; crossMatch?.paused = true
        audio.stop()
        result = value
        // Android no longer saves a completed result to a history without an explicit choice.
        ads.completed(id) { [weak self] in
            guard let self else { return }
            if self.experience.closesAfterMatch { self.closeObservers(); self.completion(value); return }
            self.route = .result
            // Android VictoryConfetti: a completed room celebrates its winner once; a knockout table celebrates going through;
            // a won fixture whose final duel is still to come does not celebrate yet.
            let celebrate: Bool
            if let s = self.session, let m = self.fixture {
                if s.complete { celebrate = MPCompletionText.won(s, self.repo.uid) && self.preferences.firstCelebration(s) }
                else if s.knockout { celebrate = MPKnockout.goesThrough(s, s.matches[m.id] ?? m, self.repo.uid) }
                else { celebrate = value.won && s.matches[MPRules.duelId(m.id)] == nil }
            } else { celebrate = value.won }
            if celebrate { self.celebration = UUID() }
        }
    }
    func back() {
        switch route {
        case .result:
            audio.stop()
            if session != nil { closeResult(); return }
            goHome()
        case .lobby:
            audio.stop()
            if let s = session, s.kind == .tournament, !s.complete, s.human(repo.uid) {
                // Android 5c1aa4d confirmTournamentExit: Save keeps it for later; Don't save deletes or leaves it.
                tournamentExitPrompt = true
                return
            }
            if let s = session, s.complete { dismissCompleted(); return }
            goHome()
        case .game:
            audio.stop(); scene?.setActive(false)
            if session != nil { leaveCourt(); return }
            goHome()
        case .cross:
            if tour != nil { endTour(); return }
            audio.stop()
            goHome()
        case .journey:
            journey?.back()
        case .teams:
            teams?.back()
        case .guide:
            audio.stop()
            preferences.skipGuide = skipGuide; scene = nil
            // Android navigateBack from a guide opened before a match ends the guide and continues that match.
            if let resume = resumeAfterGuide { resumeAfterGuide = nil; startSingle(practice: resume); return }
            route = .menu
        case .menu:
            goHome()
        }
    }
    private func goHome() {
        celebration = nil; closeObservers(); scene?.setActive(false); scene = nil; clearCross(); session = nil; fixture = nil; result = nil; route = .menu
        rooms = preferences.rooms
        if experience.closesAfterMatch { completion(nil) }
    }
    func close() { foreground = false; audio.stop(); menuMusic.stop(); scene?.setActive(false); crossScene?.setActive(false); journey?.lifecycle(active: false); teams?.lifecycle(active: false); closeObservers() }
    /// Android PlayActivity onResume/onPause: the menu music plays on the home and room screens only.
    func syncMusic() {
        menuMusic.set(experience == .full && foreground && (route == .menu || route == .lobby) && preferences.menuMusic)
    }
    func lifecycle(active: Bool) {
        guard foreground != active else { return }; foreground = active
        defer { syncMusic() }
        if route == .journey { journey?.lifecycle(active: active); return }
        if route == .teams { teams?.lifecycle(active: active); return }
        if !active {
            audio.stop(); scene?.setActive(false)
            if route == .cross { pauseLocalCross() } else { crossScene?.setActive(false); crossMatch?.paused = true }
            closeObservers()
        } else if let s = session {
            let wasGame = route == .game
            scene?.setActive(false); closing = false
            if wasGame {
                // Android PrivateMatchActivity.onResume reconnects: the court opens again from the latest checkpoint.
                if let id = fixture?.id { opened.remove(id) }
                scene = nil; clearCross(); route = .lobby
            }
            // Android onStop/onStart: the room is detached and reopened with its full observer; changes made while away play no cue.
            firstSnapshot = false; lobbyPrevious = nil; gatePending = false; gateLatest = nil
            subscriptions.append(repo.observe(s.kind, s.code) { [weak self] value in
                guard let self, !self.closing else { return }
                switch value {
                case .success(let room): self.receive(room)
                case .failure(let error):
                    if error as? MPError == .missing { self.roomGone(s) } else { self.show(error) }
                }
            })
            syncLobbyPresence(session ?? s)
        } else if route == .cross {
            crossScene?.setActive(localCross?.paused == false && tourCard == nil)
        } else { scene?.setActive(route == .game && !paused || route == .guide && tutorialPhase != .explanation && tutorialPhase != .feedback) }
        audio.guideMusic(active && route == .guide && tutorialPhase != .attempt)
        activityAt = MPClock.now
    }
    private func acquirePresence(_ s: MPSession) {
        // Set the guard before calling the local repository, which notifies synchronously (Android syncLobbyPresence).
        guard presenceSubscription == nil, !acquiringPresence else { return }
        acquiringPresence = true
        let subscription = repo.presence(s.kind, s.code)
        acquiringPresence = false
        if presenceSubscription == nil { presenceSubscription = subscription } else { subscription.close() }
    }
    private func releasePresence() {
        let previous = presenceSubscription
        presenceSubscription = nil
        previous?.close()
    }
    /// Android PlayActivity.syncLobbyPresence (7f5dd0a): outside the court, presence is held only while this player has no PLAYING
    /// match, so a lobby visit never keeps the other court running. iOS uses one presence for lobby and court, so a court that is
    /// about to launch keeps it rather than dropping and reopening it.
    private func syncLobbyPresence(_ s: MPSession) {
        guard route != .game else { return }
        if s.needsLobbyPresence(repo.uid) { acquirePresence(s) } else { releasePresence() }
    }
    private func closeObservers() {
        link?.close(); link = nil; crossLink?.close(); crossLink = nil
        let current = subscriptions
        subscriptions = []
        current.forEach { $0.close() }
        releasePresence()
    }
    func togglePause() {
        if session != nil { back(); return }
        paused.toggle(); scene?.setActive(!paused && foreground); activityAt = MPClock.now; if paused { audio.stop() }
    }
    /// App Store captures only (StoreScreenshotScene): opens one screen at launch, offline.
    func applyStoreScreenshotScene() {
        switch StoreScreenshotScene.name ?? "" {
        case "pong.play": openCross(learn: false)
        case "pong.guide": openCross(learn: true)
        case "pong.rival": playerIndex = MPRoster.all.firstIndex { $0.id == "kyra" } ?? 0
        default: break
        }
    }

    // ---- journey, team games and online team rooms (Android CrossJourneyActivity, CrossOnlineTeamsActivity) ---------------------
    /// Opens the journey page (`teams` with `players` 3 or 4), over the current screen.
    func openJourney(_ page: CrossJourneyModel.Page, players: Int = 4) {
        audio.stop()
        if route == .cross { pauseLocalCross() }
        if route != .journey && route != .teams { journeyReturn = route }
        journey = CrossJourneyModel(page: page, players: players, preferences: preferences, hebrew: hebrew, audio: audio,
                                    onClose: { [weak self] in self?.closeJourney() }, onOnlineTeams: { [weak self] n in self?.openTeams(players: n) })
        route = .journey
    }
    private func closeJourney() {
        journey = nil
        route = journeyReturn
        if route == .cross { crossScene?.setActive(false) }
        rooms = preferences.rooms
    }
    func openTeams(players: Int) {
        audio.stop()
        if route == .cross { pauseLocalCross() }
        if route == .journey { journey?.lifecycle(active: false) }
        teamsReturn = route == .journey ? .journey : (route == .teams ? teamsReturn : route)
        teams = CrossTeamsModel(players: players, preferences: preferences, hebrew: hebrew, audio: audio, onClose: { [weak self] in self?.closeTeams() })
        route = .teams
    }
    private func closeTeams() {
        teams = nil
        route = teamsReturn
        if route == .journey { journey?.lifecycle(active: foreground) }
    }
    /// The tour's "Learn team play" action (Android guide_team_practice): the team game page over the local match.
    func tourTeamPractice() {
        endTour()
        openJourney(.teams)
    }
    /// Android toggleCamera on the local court: the landscape action camera or every player in view.
    func toggleActionCamera() {
        actionCamera.toggle()
        toast = hebrew ? (actionCamera ? "מצלמת פעולה" : "כל השחקנים במסך") : (actionCamera ? "Action camera" : "Fit all players")
    }
    /// Android confirmTournamentExit: Save keeps the tournament for later; Don't save deletes it (no other connected player) or
    /// leaves it.
    func keepTournament() { tournamentExitPrompt = false; saveForLater() }
    func discardTournament() {
        tournamentExitPrompt = false
        guard let s = session else { return }
        let delete = MPRules.canDelete(s, actor: repo.uid)
        Task { await leave(delete: delete) }
    }

    // ---- local cross match and its guide (Android CrossActivity) ------------------------------------------------------------
    var crossControl: CrossControl { CrossControl.fromChoice(preferences.control.rawValue) }
    /// Android "Learn how to play with Minik": the cross table's tour, then a local match with house players.
    func openCross(learn: Bool) {
        audio.stop(); closeObservers(); session = nil; fixture = nil; result = nil; celebration = nil; scene = nil
        clearCross()
        installLocalCross(newCrossEngine())
        route = .cross
        if learn || !preferences.crossGuideSeen { startTour() }
    }
    private func myName() -> String { identity?.name ?? MPNames.candidate(0, hebrew: hebrew, character: identity?.characterId ?? "miniko") }
    private func newCrossEngine() -> CrossEngine {
        let me = CrossSeat(index: 0, kind: .local, id: "local", name: myName(), characterId: identity?.characterId ?? "", avatar: identity?.avatar ?? 0)
        let ids = Array(preferences.crossOpponents.prefix(preferences.crossPlayers - 1))
        let others = ids.enumerated().map { item -> CrossSeat in
            let c = MPRoster.find(item.element) ?? MPRoster.all[0]
            return CrossSeat(index: item.offset + 1, kind: .house, id: "bot_" + c.id, name: c.name(hebrew: hebrew), bot: c.profile, characterId: c.id)
        }
        return CrossEngine(seats: [me] + others, control: crossControl, target: preferences.crossTarget, seed: Int64.random(in: 1...Int64.max))
    }
    private func localNames(_ e: CrossEngine) -> [String] { e.seats.map { $0.kind == .local ? text("You", "אתם") : $0.name } }
    private func installLocalCross(_ engine: CrossEngine) {
        localCross = engine
        // Android CrossActivity keeps finishedShown: a match finished before the guide does not show its result again.
        crossSounds = CrossSoundPolicy(localSeat: engine.localSeat); crossOutcome = nil; finishedShown = engine.referee.winner != nil; crossResult = nil
        let court: CrossScene
        if let existing = crossScene, crossMatch == nil { court = existing; court.engine = engine }
        else {
            court = CrossScene(engine: engine)
            court.onFrame = { [weak self] in self?.localCrossFrame() }
            crossScene = court
        }
        court.step = nil
        court.names = localNames(engine); court.tutorialTarget = nil; court.acceptsInput = true; court.avatarIcons = [:]
        court.preferences = preferences
        court.fullScreen = actionCamera
        engine.paused = false; crossPaused = false
        court.setActive(foreground)
        crossStatus = CrossText.status(engine, names: localNames(engine), last: nil, hebrew: hebrew)
        activityAt = MPClock.now
    }
    private func localCrossFrame() {
        guard let engine = localCross, let court = crossScene else { return }
        tour?.update()
        let events = engine.drainEvents()
        for event in events {
            if let policy = crossSounds { for cue in policy.cues(event) { audio.play(cue.sound) } }
            if case let .rally(outcome) = event { crossOutcome = outcome; court.showOutcome(outcome) }
        }
        if let t = tour, t.changed { t.changed = false; showTourCard() }
        refreshLocalCross()
    }
    private func refreshLocalCross() {
        guard let engine = localCross else { return }
        let now = MPClock.now
        if now - renderAt >= 100 {
            renderAt = now
            crossStatus = tour.map { $0.statusText(hebrew) } ?? CrossText.status(engine, names: localNames(engine), last: crossOutcome, hebrew: hebrew)
        }
        if crossPaused != engine.paused { crossPaused = engine.paused }
        if tour == nil, engine.referee.winner != nil, !finishedShown {
            finishedShown = true
            let shown = engine
            Task { [weak self] in
                try? await Task.sleep(nanoseconds: 900_000_000)
                guard let self, self.route == .cross, self.localCross === shown, shown.referee.winner != nil, self.tour == nil else { return }
                self.showLocalCrossResult(shown)
            }
        }
    }
    private func showLocalCrossResult(_ engine: CrossEngine) {
        let names = localNames(engine), ref = engine.referee
        let faults = ref.faults
        let order = ref.scores.enumerated().sorted { a, b in
            if a.element != b.element { return a.element > b.element }
            if faults[a.offset] != faults[b.offset] { return faults[a.offset] < faults[b.offset] }
            return a.offset < b.offset
        }
        let won = ref.winner != nil && ref.winner == engine.localSeat
        let winner = ref.winner ?? 0
        let winnerName = winner < names.count ? names[winner] : ""
        let title = won ? text("You win! 🎉", "ניצחתם! 🎉") : text("\(winnerName) wins", "ניצחון ל־\(winnerName)")
        let lines = order.enumerated().map { item -> String in
            let seat = item.element.offset
            return "\(item.offset + 1). \(seat < names.count ? names[seat] : "") — \(item.element.element)"
        }
        crossResult = CrossLocalResult(title: title, lines: lines, won: won)
        if won { celebration = UUID() }
    }
    private func pauseLocalCross() {
        guard let engine = localCross else { return }
        engine.paused = true; crossScene?.setActive(false); audio.stop(); engine.discardEvents(); crossPaused = true
        crossStatus = tour.map { $0.statusText(hebrew) } ?? CrossText.status(engine, names: localNames(engine), last: crossOutcome, hebrew: hebrew)
    }
    private func resumeLocalCross() {
        guard let engine = localCross else { return }
        engine.discardEvents(); engine.paused = false; crossScene?.setActive(foreground); crossPaused = false
    }
    func toggleCrossPause() {
        guard route == .cross, tourCard == nil, let engine = localCross else { return }
        if engine.paused { resumeLocalCross() } else { pauseLocalCross() }
    }
    func restartCross() {
        guard tour == nil else { return }
        audio.stop(); crossResult = nil; celebration = nil
        installLocalCross(newCrossEngine())
    }
    /// Android CrossActivity settings: "Apply & start new match".
    func applyCrossSettings(players: Int, control: MPLevel, target: Int, opponents: [String]) {
        preferences.crossPlayers = players; preferences.crossTarget = target
        var order = opponents
        for id in preferences.crossOpponents where !order.contains(id) { order.append(id) }
        preferences.crossOpponents = order
        level = control; saveControls()
        restartCross()
    }
    /// Settings open: the guide ends and the match pauses (Android showSettings).
    func crossSettingsOpened() -> Bool {
        if tour != nil { endTour() }
        let wasPaused = localCross?.paused ?? true
        pauseLocalCross()
        return wasPaused
    }
    func crossSettingsCancelled(wasPaused: Bool) { if !wasPaused { resumeLocalCross() } }
    func closeCrossResult(playAgain: Bool) {
        crossResult = nil; celebration = nil
        if playAgain { restartCross() } else { back() }
    }
    func startTour() {
        if tour == nil {
            savedGame = localCross
            if let engine = localCross { engine.paused = true; engine.discardEvents() }
            crossScene?.setActive(false); audio.stop()
        }
        crossResult = nil
        let names = localCross.map { localNames($0) } ?? [text("You", "אתם")]
        tour = CrossTutorial(players: preferences.crossPlayers, control: crossControl, names: names, hebrew: hebrew)
        crossTourActive = true
        showTourCard()
    }
    private func showTourCard() {
        guard let t = tour else { tourCard = nil; return }
        if t.phase == .demo || t.phase == .attempt { tourCard = nil; useTourEngine(); return }
        crossScene?.setActive(false)
        let card = t.card(hebrew)
        tourCard = CrossTourCard(title: card.title, message: card.message, phase: t.phase, canGoBack: t.canGoBack,
                                 teamPractice: t.phase == .info && (t.lesson.kind == .team || t.lesson.kind == .scoring))
        crossStatus = t.statusText(hebrew)
    }
    private func useTourEngine() {
        guard let t = tour, let court = crossScene else { return }
        localCross = t.engine
        crossSounds = CrossSoundPolicy(localSeat: t.engine.localSeat)
        court.engine = t.engine; court.names = t.names; court.tutorialTarget = t.highlight; court.acceptsInput = t.acceptsInput
        t.engine.paused = false; crossPaused = false
        court.setActive(foreground)
        crossStatus = t.statusText(hebrew)
    }
    func tourNext() {
        guard let t = tour else { return }
        if t.next() { showTourCard() } else { endTour() }
    }
    func tourBack() { tour?.back(); showTourCard() }
    func tourShow() { tour?.demo(); showTourCard() }
    func tourTry() { tour?.practice(); showTourCard() }
    func endTour() {
        tourCard = nil; preferences.crossGuideSeen = true; tour = nil; crossTourActive = false
        let game = savedGame ?? newCrossEngine()
        savedGame = nil
        installLocalCross(game)
    }

    // ---- classic guide (Simple experience) ----------------------------------------------------------------------------------
    func guide() {
        closeObservers(); session = nil; fixture = nil; resumeAfterGuide = nil; celebration = nil; clearCross()
        tutorialStep = .serveMiddle; tutorialPhase = .explanation; scene = nil; route = .guide; audio.guideMusic(foreground)
    }
    func tutorialStart(demo: Bool) {
        tutorialPhase = demo ? .demonstration : .attempt; tutorialSuccess = false; demoGesture = false
        audio.guideMusic(demo && foreground)
        install(MPEngine(level: tutorialStep.level, target: 7, houseControls: false, exercise: tutorialStep.exercise, seed: 42))
        scene?.guidePoint = tutorialStep.serve ? tutorialStep.servePoint : nil; scene?.guideDirection = tutorialStep.serve ? nil : tutorialStep.aim
    }
    private func tutorialFrame() {
        guard let engine = scene?.engine else { return }
        if !tutorialStep.serve { scene?.guidePoint = engine.flight?.receiver == true ? engine.ball : nil }
        if let success = engine.trainingResult {
            // Android ModernTutorial: a demonstration returns to the lesson card; only the child's own try is
            // judged. Owner report 2026-10-14: "Well done!" showed after Minik's demo, before the child had hit.
            if tutorialPhase == .demonstration { tutorialPhase = .explanation }
            else { tutorialSuccess = success; tutorialPhase = .feedback }
            scene?.setActive(false); audio.guideMusic(foreground); return
        }
        guard tutorialPhase == .demonstration else { return }
        if tutorialStep.serve && engine.awaitingServe && engine.trainingTime > 0.7 { engine.touch(tutorialStep.servePoint); engine.endTouch() }
        else if !tutorialStep.serve, let flight = engine.flight, flight.striker == .minik, flight.receiver, flight.position.y >= 0.78, !demoGesture {
            demoGesture = true; let point = flight.position
            engine.touch(point)
            // Beginner demo: place the paddle and lift the finger; the paddle hits by itself.
            // Aimed lessons use Android's demonstrated sideways distance and swipe speed.
            if let direction = tutorialStep.swipeDirection {
                engine.touch(.init(point.x + direction * tutorialStep.demoDistance, point.y - 0.075), movement: .init(direction * 1.8, -1.7), down: false)
                engine.endTouch()
            }
            else if tutorialStep == .autoReturn || tutorialStep == .middleAny { engine.endTouch() }
        }
    }
    func tutorialNext() {
        if let next = MPTutorialStep(rawValue: tutorialStep.rawValue + 1) { tutorialStep = next; tutorialPhase = .explanation; scene = nil }
        else { guideToGame() }
    }
    func guideToGame() {
        preferences.skipGuide = skipGuide
        // Continue the match that opened the guide automatically; otherwise play Minik, as before.
        if let resume = resumeAfterGuide { resumeAfterGuide = nil; guideOffered = true; startSingle(practice: resume); return }
        playerIndex = 0; guideOffered = true; startSingle(practice: experience == .full)
    }
}
