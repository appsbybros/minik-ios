import Foundation
import Combine

struct ModernPongResult: Codable, Equatable { var playerPoints: Int; var opponentPoints: Int; var won: Bool }
/// `cross`: the local 3/4-player match and its guide (Android CrossActivity). `journey`: the daily skill journey, the team game
/// with house players and Settings (CrossJourneyActivity). `teams`: online team rooms (CrossOnlineTeamsActivity).
enum MPRoute { case menu, lobby, game, guide, result, cross, journey, teams }
/// A card of the cross guide (Android CrossActivity.showGuideCard).
struct CrossTourCard: Equatable {
    var title: String; var message: String; var phase: CrossTutorial.Phase; var canGoBack: Bool
    /// Android d0bed3b: the last card has no Next (`canGoNext`); the bottom row shows only the navigation that exists.
    var canGoNext = true
    /// The team and scoring cards offer the team game (Android 5c1aa4d, R.string.guide_team_practice).
    var teamPractice = false
}
/// The local cross match's result (Android CrossActivity.showResult).
struct CrossLocalResult: Equatable { var title: String; var rows: [MPXResultRow]; var won: Bool }
/// Android 47ad0c9 CrossActivity.showHelp: the help for the current lesson or control level, closed with its X.
struct CrossHelpCard: Equatable { var title: String; var message: String; var resume: Bool }
/// Android 83b050d / 9adf1f1 `confirmRoomExit`: the room the question is about and which explanation it shows (chosen when it
/// opens): the room was never saved; Exit without saving discards only the changes since the save; or (an online room whose
/// save cannot be restored by a lobby rollback) the earlier saved entry is kept while shared play continues.
struct MPRoomExitPrompt: Equatable {
    enum Message: Equatable { case neverSaved, discardsChanges, keepsEarlierEntry }
    var roomId: String
    var message: Message
}

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
    /// Android 83b050d / 9adf1f1 `confirmRoomExit`: Back from a room that was never saved, or changed since its save, asks Save and
    /// exit / Exit without saving / Stay. Its message is chosen when it opens.
    @Published var roomExitPrompt: MPRoomExitPrompt?
    /// Android 5375378 `showMatchLoading` / `launchingMatch`: the "Loading…" page replaces the room (or the menu, during a
    /// rematch) until the match opens or the room screen detaches.
    @Published var loadingMatch = false
    /// Android 1fc4bc2 `reviewRestoredRoster`: a new friendly room filled from the saved lineup waits for the host's Start.
    /// iOS fix (2026-11-10): the wait belongs to the room the lineup was restored into (`reviewRestoredRoom`), so it never holds
    /// back another room opened afterwards (Android keeps one flag for the screen).
    var reviewRestoredRoster: Bool { reviewRestoredRoom != nil && reviewRestoredRoom == session?.id }
    @Published private var reviewRestoredRoom: String?
    /// Android 1fc4bc2: the seat lobby scrolls to its top when its last seat is taken (a new value each time).
    @Published var lobbyScrollTop: UUID?
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
    /// Android `cross/close_camera` (a9140c3): the close camera ("Action camera") of the local cross court, remembered; off by default.
    @Published var actionCamera: Bool { didSet { preferences.crossCloseCamera = actionCamera; if crossMatch == nil { crossScene?.fullScreen = actionCamera } } }
    @Published var tourCard: CrossTourCard?
    @Published var crossHelp: CrossHelpCard?
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
    /// Android PrivateMatchActivity `openingDuel` (1fc4bc2, b0cdeb3): a finished table is opening its final duel.
    private var openingDuel = false
    /// Android PlayActivity `roomEpoch` (incremented by `detach`, iOS `closeObservers`), `exiting`, and 83b050d
    /// `playedSinceRoomOpen` (a match of this room was opened and left since the room was opened).
    private var roomEpoch = 0, exiting = false, playedSinceRoomOpen = false
    /// Android 1fc4bc2 `fullRosterSeenAt` (uptime ms; 0 until a full seat lobby is shown) and `rosterStartPosted`.
    private var fullRosterSeenAt: Int64 = 0, rosterStartPosted = false
    /// The local cross match's engine, or the guide's engine while a lesson plays.
    private var localCross: CrossEngine?
    private var tour: CrossTutorial?, savedGame: CrossEngine?, finishedShown = false
    /// Android CrossActivity `learn`: the local match was opened from "Learn how to play"; Back from it returns to the guide.
    private var crossLearn = false
    private static let practiceLevelKey = "modern.pong.practice.level"
    /// CI smoke launches pass `-MinikOfflineSmoke YES`; they must never reach production Firebase.
    static var offlineSmoke: Bool { UserDefaults.standard.bool(forKey: "MinikOfflineSmoke") }
    init(experience: ModernPongExperience, preferences: MPPreferences = .init(), repository: (any MPRepository)? = nil, onClose: @escaping (ModernPongResult?) -> Void) {
        // App Store captures only (MPStoreScreenshot): start from a fresh install's settings.
        MPStoreScreenshot.prepare()
        self.experience = experience; self.preferences = preferences; completion = onClose; ads = .init(preferences: preferences, experience: experience)
        level = preferences.control; target = preferences.control.target(preferences.target); skipGuide = preferences.skipGuide; identity = preferences.identity
        actionCamera = preferences.crossCloseCamera
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
        // Android 47ad0c9 ModernAudio / LobbyAudio: "Game sounds" off silences every cue and stops the one that is playing.
        audio.soundsEnabled = { [preferences] in preferences.journeySound }
        // Android 83b050d PlayActivity.onCreate: the rooms saved automatically before explicit saves become explicit saves, once;
        // a completed local room with an explicit save is kept by the refresh.
        let local = repo as? MPLocalRepository
        local?.keepCompleted = { [preferences] in preferences.hasExplicitSave($0) }
        preferences.migrateExplicitSaves(local)
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
    /// Android 7254ab2 home: "New friendly game" / "New tournament" open their setup page only when there is room for one more.
    func openLimitReached(_ kind: MPSessionKind) -> Bool {
        if hasSpace(kind) { return false }
        show(MPError.limit)
        return true
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
            // Android 1fc4bc2: a new friendly table is filled from the lineup saved for its size, then waits for Start.
            let ready = try await self.restoreFriendlyRoster(created)
            self.enter(ready)
        }
    }
    /// Android 1fc4bc2 `rememberFriendlyRoster`: when this host (the only human) starts a friendly table, its house characters are
    /// saved for tables of that size, clockwise from the host (seats tableSize − 1, tableSize − 2, …).
    /// iOS fix (2026-11-10): only 3/4-seat tables. Android also saves `friendlyRoster2`, but a restored lineup waits for the seat
    /// lobby's Start, which the 2-seat table does not have (it chooses its opponent and starts with its own Start).
    private func rememberFriendlyRoster(_ s: MPSession) {
        guard s.kind == .friendly, s.host == repo.uid, s.participants.values.filter({ $0.bot == nil }).count == 1, s.tableSize >= 3 else { return }
        let seats = s.seating()
        let order = (1..<s.tableSize).compactMap { n -> String? in
            let seat = (s.tableSize - n) % s.tableSize
            return seats.first(where: { $0.value == seat }).flatMap { s.participants[$0.key]?.bot?.characterId }
        }
        preferences.setFriendlyRoster(s.tableSize, order.joined(separator: ","))
    }
    /// Android 1fc4bc2 `restoreFriendlyRoster`: the saved characters (known ones, each once, at most tableSize − 1) take the seats
    /// clockwise from the host in one transaction; the room then waits for the host's Start (`reviewRestoredRoster`).
    /// iOS fix (2026-11-10): a 2-seat table is never filled from a lineup (it has no seat lobby, so nothing could start it), and a
    /// `friendlyRoster2` that Android's rule saved earlier is cleared.
    private func restoreFriendlyRoster(_ s: MPSession) async throws -> MPSession {
        reviewRestoredRoom = nil
        guard s.kind == .friendly else { return s }
        if s.tableSize < 3 {
            if !preferences.friendlyRoster(s.tableSize).isEmpty { preferences.setFriendlyRoster(s.tableSize, "") }
            return s
        }
        var seen = Set<String>()
        let saved = preferences.friendlyRoster(s.tableSize).split(separator: ",", omittingEmptySubsequences: false)
            .compactMap { MPRoster.find(String($0)) }.filter { seen.insert($0.id).inserted }
        let players = Array(saved.prefix(max(0, s.tableSize - 1)))
        if players.isEmpty { return s }
        let uid = repo.uid, size = s.tableSize
        let ready = try await repo.mutate(s.kind, s.code) { old in
            var next = old
            for (i, player) in players.enumerated() {
                next = try MPRules.addFriendlyHousePlayer(next, actor: uid, bot: MPRules.housePlayer(player), seat: (size - i - 1) % size)
            }
            return next
        }
        reviewRestoredRoom = ready.id
        return ready
    }
    /// Android 1fc4bc2 seat lobby "Start" under a restored lineup: the review ends and the table starts at once.
    func startRestoredRoster() {
        guard let s = session else { return }
        reviewRestoredRoom = nil
        fullRosterSeenAt = MPController.uptime - 700
        maybeStart(s)
    }
    /// Android `SystemClock.uptimeMillis()`.
    static var uptime: Int64 { Int64(ProcessInfo.processInfo.systemUptime * 1000) }
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
        // Android openRoom: another room starts without its played flag (83b050d); `detach` clears the roster pause.
        if session?.id != s.id { playedSinceRoomOpen = false }
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
            // Re-entering a saved game opens its controls, not the court automatically (Android 452d82c: a watched final too).
            for m in s.matches.values where (m.contains(uid) || MPRules.spectatedDuel(s, m, uid: uid)) && m.phase == .playing { opened.insert(m.id) }
            firstSnapshot = false
        }
        session = s; link?.update(s); crossLink?.update(s); preferences.remember(s); rooms = preferences.rooms
        // Android PlayActivity.completed: a room completed while it is shown celebrates the winner once.
        if route == .lobby { celebrateCompletion(s) }
        if route == .game, let current = fixture, let m = s.matches[current.id] {
            if m.phase == .finished {
                // Android 1fc4bc2 / b0cdeb3 PrivateMatchActivity.updateSession: a finished table whose final duel this player plays
                // (or, as the friendly host, watches) opens that duel instead of the table's result.
                if let duel = MPRules.duelOf(s, m), !duel.terminal, duel.contains(uid) || MPRules.spectatedDuel(s, duel, uid: uid) {
                    crossMatch?.paused = true; crossScene?.setActive(false)
                    openDuel(s, table: m.id, duel)
                    return
                }
                fixture = m
                let points = m.a == uid ? (m.scoreA, m.scoreB) : (m.scoreB, m.scoreA)
                finish(id: m.id, value: .init(playerPoints: points.0, opponentPoints: points.1, won: m.winner == uid))
                return
            }
            // Android PrivateMatchActivity closes when its fixture is no longer playing (a departure cancelled it).
            if m.phase != .playing { leaveCourt() }
        }
        if route == .lobby { maybeStart(s) }
        // Android renderRoom runs after maybeStart unless a match is loading or launching.
        if route == .lobby && !loadingMatch, let latest = session { roomShown(latest) }
        if route != .game && foreground, let latest = session { syncLobbyPresence(latest) }
    }
    /// Android 1fc4bc2 renderRoom: once the host's 3/4-seat lobby shows every seat taken (and no restored lineup waits for
    /// Start), it scrolls to the top and the full table stays visible for 700 ms (counted from its first drawing) before the
    /// game starts; the timer is fenced by the room epoch, so a closed room never starts.
    private func roomShown(_ s: MPSession) {
        guard s.kind == .friendly, s.state == "WAITING", s.tableSize >= 3, s.freeSeats().isEmpty, s.host == repo.uid,
              !reviewRestoredRoster, fullRosterSeenAt == 0, !rosterStartPosted else { return }
        rosterStartPosted = true
        let epoch = roomEpoch
        lobbyScrollTop = UUID()
        Task { @MainActor [weak self] in
            // The next main-loop turn, after SwiftUI has drawn this roster (Android OnPreDrawListener).
            await Task.yield()
            guard let self, self.foreground, self.roomEpoch == epoch else { return }
            self.fullRosterSeenAt = MPController.uptime
            try? await Task.sleep(nanoseconds: 700_000_000)
            guard self.foreground, self.roomEpoch == epoch else { return }
            self.rosterStartPosted = false
            if let room = self.session { self.maybeStart(room) }
        }
    }
    /// Android PlayActivity.maybeStart: a full friendly room starts; a newly PLAYING fixture of this player opens its court once;
    /// the host of a house-player friendly table is Ready by pressing Start; a fixture whose humans are all Ready starts.
    private func maybeStart(_ s: MPSession) {
        // Android 83b050d: nothing starts while the room's exit question is open.
        guard foreground, !closing, !exiting, roomExitPrompt == nil, route == .lobby, session?.id == s.id else { return }
        let uid = repo.uid
        gateLatest = s
        if s.kind == .friendly && s.state == "WAITING" && s.participants.count == s.capacity && s.host == uid && !gatePending {
            // Android 1fc4bc2: a restored lineup waits for Start; a full 3/4-seat table is shown for 700 ms first.
            if reviewRestoredRoster { return }
            if s.tableSize >= 3 && (fullRosterSeenAt == 0 || MPController.uptime - fullRosterSeenAt < 700) { return }
            rememberFriendlyRoster(s)
            transition(s) { try MPRules.start($0, actor: uid) }
            return
        }
        if s.participants.count < s.capacity { fullRosterSeenAt = 0 }
        // Android 1fc4bc2: the friendly host's watched final opens like the host's own fixture.
        if let playable = s.matches.values.sorted(by: { $0.id < $1.id }).first(where: { ($0.contains(uid) || MPRules.spectatedDuel(s, $0, uid: uid)) && $0.phase == .playing }),
           !opened.contains(playable.id) {
            opened.insert(playable.id); launch(s, playable); return
        }
        if gatePending { return }
        if MPRules.friendlyHouseReady(s, actor: uid) != s { transition(s) { MPRules.friendlyHouseReady($0, actor: uid) }; return }
        if let next = s.matches.values.sorted(by: { $0.id < $1.id }).first(where: { $0.contains(uid) && MPRules.startReady(s, match: $0.id) != s }) {
            let id = next.id
            transition(s) { MPRules.startReady($0, match: id) }
        }
    }
    /// Android PrivateMatchActivity.updateSession (1fc4bc2, b0cdeb3): the watching host starts the house players' duel; a player
    /// of the duel is Ready first and then starts it, in two transactions (Ready must exist on the server before Start validates
    /// it; combining both in one transaction removes Ready and is correctly denied by the rules). The duel's court then replaces
    /// the table's; its ID counts as opened, so Back from it does not open it again (Android 452d82c `returnedMatch`).
    private func openDuel(_ s: MPSession, table: String, _ duel: MPFixture) {
        guard !openingDuel, foreground else { return }
        openingDuel = true
        let uid = repo.uid, id = duel.id, kind = s.kind, code = s.code
        let watching = MPRules.spectatedDuel(s, duel, uid: uid)
        Task { [weak self] in
            guard let self else { return }
            do {
                let updated: MPSession
                if watching {
                    updated = try await self.repo.mutate(kind, code) { MPRules.startSpectatedDuel($0, id: id, actor: uid) }
                } else {
                    _ = try await self.repo.mutate(kind, code) { try MPRules.ready($0, match: id, uid: uid, value: true) }
                    guard self.foreground, self.route == .game, self.fixture?.id == table else { self.openingDuel = false; return }
                    updated = try await self.repo.mutate(kind, code) { MPRules.startReady($0, match: id) }
                }
                self.openingDuel = false
                guard self.foreground, self.route == .game, self.fixture?.id == table, let started = updated.matches[id], started.phase == .playing else { return }
                self.opened.insert(id)
                self.launch(updated, started)
            } catch {
                self.openingDuel = false
                self.crossIssue(.failed(error.localizedDescription))
            }
        }
    }
    /// iOS fix (2026-11-10): this player must still choose Ready themselves in a started friendly room: a fixture of theirs that is
    /// neither playing nor over lacks their Ready, and Start's house-player Ready (`friendlyHouseReady`) does not give it, because
    /// another human sits at the table (or the fixture was started before). Android 5375378 keeps "Loading…" over the room then,
    /// so its host could only save, leave and reopen the room.
    func awaitsOwnReady(_ s: MPSession) -> Bool {
        let uid = repo.uid
        guard s.kind == .friendly, s.state == "ACTIVE", MPRules.friendlyHouseReady(s, actor: uid) == s else { return false }
        return s.matches.values.contains { $0.contains(uid) && !$0.terminal && $0.phase != .playing && $0.ready[uid] != true }
    }
    private func transition(_ s: MPSession, _ change: @escaping (MPSession) throws -> MPSession) {
        // Android 5375378: a friendly table with house players shows "Loading…" while it starts.
        // iOS fix (2026-11-10): not when the change leaves this player's own Ready still to choose (another human sits at the
        // table): the Loading page would hide the room's Ready button until the match opens, and the match needs that Ready.
        if s.kind == .friendly && s.participants.values.contains(where: { $0.bot != nil }),
           !((try? change(s)).map { awaitsOwnReady($0) } ?? false) { loadingMatch = true }
        gatePending = true; gateLatest = nil
        let kind = s.kind, code = s.code
        Task { [weak self] in
            guard let self else { return }
            var updated: MPSession?
            do { updated = try await self.repo.mutate(kind, code, change) }
            catch {
                // Android roomActionFailed: only the room still shown is affected; it is drawn again with the error.
                if self.session?.code == code {
                    if error as? MPError == .missing { self.roomGone(s) }
                    else if !self.closing && !self.exiting {
                        self.loadingMatch = false
                        if let room = self.session, self.route == .lobby { self.roomShown(room) }
                        self.show(error)
                    }
                }
            }
            self.gatePending = false
            let latest = self.gateLatest
            self.gateLatest = nil
            // iOS fix (2026-11-10): the room as it now stands still needs this player's own Ready (the transaction met a newer room
            // than the one predicted above): the Loading page ends, so the room and its Ready button show again.
            if updated != nil, self.loadingMatch, self.session?.code == code, let room = latest ?? updated, self.awaitsOwnReady(room) {
                self.loadingMatch = false
            }
            // Firebase may notify observers before completing the transaction: after a success, revisit the newest observed room.
            if updated != nil, let next = latest ?? updated, self.foreground, !self.closing, self.session?.code == code { self.maybeStart(next) }
        }
    }
    /// Android PlayActivity.change; `loading` first shows "Loading…" (5375378 showMatchLoading). A failure in the room still shown
    /// ends the loading page (Android roomActionFailed).
    private func change(loading: Bool = false, _ action: @escaping (MPSession) throws -> MPSession) async {
        guard let s = session else { return }
        await perform {
            if loading { self.loadingMatch = true }
            do { _ = try await self.repo.mutate(s.kind, s.code, action) }
            catch {
                if self.session?.id == s.id { self.loadingMatch = false }
                throw error
            }
        }
    }
    /// A friendly table's house player: Android "Start" with a chosen opponent at a classic table (it shows "Loading…" at once,
    /// 5375378), or "Add house player" on the highest free seat (1fc4bc2 `freeSeats().maxOrNull()`).
    func addFriendlyHouse(_ player: MPHousePlayer, seat: Int? = nil) async {
        let uid = repo.uid, bot = MPRules.housePlayer(player)
        let table = session?.tableSize ?? 2
        await change(loading: table <= 2) { room in
            let free = seat ?? room.freeSeats().max()
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
    /// Android 1fc4bc2 "Watch final duel": the friendly host starts the house players' final duel and watches it live.
    func watchDuel(_ match: MPFixture) async {
        let uid = repo.uid
        await change { MPRules.startSpectatedDuel($0, id: match.id, actor: uid) }
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
    /// Android leaveFriendly(delete = false), "Save for later": since 83b050d the explicit save of `saveRoomAndExit`.
    func saveForLater() {
        guard let s = session else { return }
        saveRoomAndExit(s)
    }
    /// Android 83b050d navigateBack from a room: an explicitly saved room that has not changed since its save is left at once;
    /// otherwise Back asks Save and exit / Exit without saving / Stay. A local room compares its stored state and live
    /// checkpoints with its save; an online room compares the room (`SaveComparison.same`) and whether one of its matches was
    /// played since the room was opened.
    private func roomBack(_ s: MPSession) {
        if exiting { return }
        let previous = preferences.explicitSave(s)
        let changed: Bool
        if let local = repo as? MPLocalRepository { changed = local.hasUnsavedChanges(s) }
        else if let previous { changed = !MPSaveComparison.same(previous, s) || playedSinceRoomOpen }
        else { changed = true }
        if previous != nil && !changed { leaveRoomScreen() } else { confirmRoomExit(s) }
    }
    /// Android 83b050d leaveRoomScreen: back home; a completed room without an explicit save is dismissed (and a local copy
    /// removed).
    private func leaveRoomScreen() {
        let finished = session.flatMap { $0.complete && !preferences.hasExplicitSave($0) ? $0 : nil }
        closing = true; closeObservers()
        if let finished { preferences.dismissResult(finished); (repo as? MPLocalRepository)?.remove(finished) }
        celebration = nil; session = nil; scene = nil; clearCross(); fixture = nil; result = nil; rooms = preferences.rooms; route = .menu
        closing = false
    }
    /// Android 83b050d / 9adf1f1 confirmRoomExit: the question opens once, with the explanation for this room.
    private func confirmRoomExit(_ s: MPSession) {
        guard roomExitPrompt == nil else { return }
        let message: MPRoomExitPrompt.Message
        if let previous = preferences.explicitSave(s) {
            message = online && !MPSavedLobbyRollback.available(previous, s, uid: repo.uid) ? .keepsEarlierEntry : .discardsChanges
        } else { message = .neverSaved }
        roomExitPrompt = MPRoomExitPrompt(roomId: s.id, message: message)
    }
    /// The question's three actions act only on the room it was asked about, as it is now (Android `room ?: s`).
    func roomExitSave() {
        guard let prompt = roomExitPrompt else { return }
        roomExitPrompt = nil
        if let s = session, s.id == prompt.roomId { saveRoomAndExit(s) }
    }
    func roomExitDiscard() {
        guard let prompt = roomExitPrompt else { return }
        roomExitPrompt = nil
        if let s = session, s.id == prompt.roomId { discardRoomChanges(s) }
    }
    func roomExitStay() { roomExitPrompt = nil }
    /// Android 83b050d saveRoomAndExit: a local room keeps a separate checkpoint (its room and live match states), then the room
    /// is saved explicitly and the screen closes.
    private func saveRoomAndExit(_ s: MPSession) {
        if exiting { return }
        do {
            try (repo as? MPLocalRepository)?.saveCheckpoint(s)
            try preferences.saveExplicitly(s)
            leaveRoomScreen()
        } catch { show(error) }
    }
    /// Android 83b050d / 9adf1f1 discardRoomChanges: a room never saved is finished (friendly) or left / deleted (tournament);
    /// a local room returns to its saved checkpoint; an online lobby edited only by its host before the start gets its saved
    /// house players back in one transaction (peers who joined meanwhile stay); started online play is never rewound, and the
    /// earlier save is kept. A failure reopens the room and explains.
    private func discardRoomChanges(_ s: MPSession) {
        if exiting { return }
        guard let previous = preferences.explicitSave(s) else {
            let delete = s.kind == .friendly ? true : MPRules.canDelete(s, actor: repo.uid)
            Task { await leave(delete: delete) }
            return
        }
        let local = repo as? MPLocalRepository, uid = repo.uid
        exiting = true; closing = true; closeObservers()
        Task { [weak self] in
            guard let self else { return }
            do {
                let restored: MPSession
                if let local { restored = try local.restoreSavedCheckpoint(s) }
                else if MPSavedLobbyRollback.available(previous, s, uid: uid) {
                    restored = try await self.repo.mutate(s.kind, s.code) { try MPSavedLobbyRollback.restore(previous, edited: s, latest: $0, uid: uid) }
                } else { restored = previous }
                try self.preferences.saveExplicitly(restored)
                self.exiting = false; self.closing = false
                self.celebration = nil; self.session = nil; self.scene = nil; self.clearCross(); self.fixture = nil; self.result = nil
                self.rooms = self.preferences.rooms; self.route = .menu
            } catch {
                self.exiting = false
                self.enter(s)
                self.show(error)
            }
        }
    }
    func leave(delete: Bool) async {
        guard let s = session, !exiting else { return }
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
    /// Android PrivateMatchActivity result dialog (47ad0c9): a completed friendly room is dismissed; a tournament fixture goes
    /// "Back to tournament", whose screen shows the next round or, once complete, "Tournament finished" with its winner.
    /// Android 5375378: "Play again" (`replay`) on a completed friendly game whose other players are all house players starts the
    /// rematch (`startReplay`).
    func closeResult(replay: Bool = false) {
        celebration = nil
        guard let s = session else { result = nil; route = .menu; return }
        if s.complete && s.kind == .friendly {
            dismissCompleted()
            if replay { startReplay(s) }
            return
        }
        // Android 83b050d onActivityResult: a match of this room was played since it was opened.
        playedSinceRoomOpen = true
        scene = nil; clearCross(); fixture = nil; result = nil
        route = .lobby
        loadingMatch = false
        celebrateCompletion(s)
        maybeStart(s)
        if route == .lobby && !loadingMatch, let latest = session { roomShown(latest) }
        if foreground { syncLobbyPresence(s) }
    }
    /// Android 5375378 / 1fc4bc2 PlayActivity.startReplay: "Loading…", then the same settings, players and seats in a new room
    /// under a new code. The room is created with its host alone and the house players are restored in a second write (the
    /// Firebase rules accept a new room only with its host), then it opens like any room.
    private func startReplay(_ old: MPSession) {
        reviewRestoredRoom = nil
        loadingMatch = true
        Task { [weak self] in
            guard let self else { return }
            do {
                let uid = try await self.repo.connect()
                guard MPFriendlyRematch.available(old, uid: uid) else { self.loadingMatch = false; return }
                let fresh = try MPFriendlyRematch.create(old, uid: uid, code: MPRules.code(), now: MPClock.now)
                var hostOnly = fresh
                hostOnly.participants = fresh.participants.filter { $0.key == uid }
                hostOnly.seats = fresh.seats.filter { $0.key == uid }
                let created = try await self.repo.create(hostOnly)
                let restored = try await self.repo.mutate(created.kind, created.code) { room in
                    var next = room
                    next.participants = fresh.participants; next.seats = fresh.seats
                    return next
                }
                self.loadingMatch = false
                self.enter(restored)
            } catch {
                self.loadingMatch = false
                self.show(error)
            }
        }
    }
    /// Android PlayActivity.completed / tournament (47ad0c9): a completed room won by this player celebrates once, while its
    /// screen is shown; a finished tournament adds the applause.
    private func celebrateCompletion(_ s: MPSession) {
        guard route == .lobby, s.complete, MPCompletionText.won(s, repo.uid), preferences.firstCelebration(s) else { return }
        celebration = UUID()
        if s.kind == .tournament { audio.play(CrossCue.applause.sound) }
    }
    private func launch(_ s: MPSession, _ match: MPFixture) {
        // Android 5375378 launch shows "Loading…" until its match screen covers the room; here the court replaces the room at
        // once, and the room returns without it (Android: returning reopens the room, whose `detach` ends the loading page).
        loadingMatch = false
        link?.close(); link = nil; crossLink?.close(); crossLink = nil
        practice = false; paused = false; fixture = match; liveID = match.id; celebration = nil; crossWarning = ""
        acquirePresence(s)
        if MPCrossFixture.usesCross(match) || MPRules.spectatedDuel(s, match, uid: repo.uid) { launchCross(s, match); return }
        clearCross()
        let opponent = s.participants[match.a == repo.uid ? match.b : match.a], networked = opponent?.bot == nil
        // Android PrivateMatchActivity (828c6fc): the authority serves first; a house-player fixture alternates serves; a
        // two-player tie-break is decided by its first point.
        let engine = MPEngine(level: MPLevel.control(s.difficulty), target: s.target, bot: opponent?.bot, networked: networked,
                              first: s.authority(match) == repo.uid ? .child : .minik, seed: UInt64(bitPattern: match.seed),
                              alternateServe: !networked, suddenDeath: match.goal == .tiebreak)
        install(engine, character: s.participants[repo.uid]?.identity.characterId); scene?.remoteCharacter = opponent?.identity.characterId; scene?.remoteIcon = MPNames.icons[max(0, opponent?.identity.avatar ?? 0) % MPNames.icons.count]
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
        // Android a9140c3 PrivateMatchActivity reads `cross/close_camera` (default off) and offers no camera button.
        court.fullScreen = preferences.crossCloseCamera
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
        // Android passes the link's English message through unchanged; iOS (2026-11-10, owner decision) translates it.
        case .reception: crossWarning = text("Ball assistance could not be shared. The match uses normal speed until it connects.",
                                             "לא ניתן היה לשתף את העזרה בקבלת הכדור. המשחק נמשך במהירות רגילה עד שהחיבור יחזור.")
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
        else {
            // Android 1fc4bc2: the watching host is told it is the final duel.
            let watching = MPRules.spectatedDuel(s, m, uid: repo.uid) ? text("Watching the final duel. ", "צופים בקרב הגמר. ") : ""
            crossStatus = watching + CrossText.matchStatus(match, names: crossNames(s, m), last: crossOutcome, hebrew: hebrew)
        }
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
        // Android 83b050d onActivityResult (`returnedMatch`): a match of this room was played since it was opened.
        playedSinceRoomOpen = true
        loadingMatch = false
        route = .lobby
        releasePresence()
        if let s = session { syncLobbyPresence(s) }
    }
    private func clearCross() {
        crossLink?.close(); crossLink = nil
        crossScene?.setActive(false); crossScene = nil
        crossMatch = nil; crossStage = nil; crossSounds = nil; crossOutcome = nil; crossStatus = ""; crossHeader = ""
        localCross = nil; tour = nil; savedGame = nil; tourCard = nil; crossResult = nil; crossTourActive = false; crossHelp = nil
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
    /// Android 7254ab2: outside the guide, the classic court shows the player's own full avatar (Miniko for an icon avatar).
    private func install(_ engine: MPEngine, tutorial: Bool = false, character: String? = nil) {
        let scene = MPScene(engine: engine); self.scene = scene
        scene.tutorial = tutorial
        scene.localCharacterId = character ?? identity?.characterId ?? "miniko"
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
                // Android 47ad0c9: a completed room celebrates on its own screen (tournament finished), not on this result.
                if s.complete { celebrate = false }
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
            // Android 83b050d navigateBack: every room (friendly or tournament, open or completed) leaves at once only when its
            // explicit save is unchanged; otherwise Back asks Save and exit / Exit without saving / Stay.
            if let s = session { roomBack(s); return }
            goHome()
        case .game:
            audio.stop(); scene?.setActive(false)
            if session != nil { leaveCourt(); return }
            goHome()
        case .cross:
            // Android 47ad0c9 navigateBack: a lesson's demonstration or practice returns to its card; a card's Back leaves the
            // guide (its dialog's cancel); a match opened from "Learn how to play" returns to the guide. Android d0bed3b: only
            // when there is a card before (`canGoBack`); otherwise the learning screen closes.
            if let t = tour {
                if tourCard == nil && t.canGoBack { t.back(); showTourCard() } else { exitLearning() }
                return
            }
            if crossLearn { startTour(); return }
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
    /// Android PongMenuMusic (47ad0c9): one player for the home, room and journey pages (not their games), keeping its place
    /// between them; it pauses at once when the menu music is turned off.
    func syncMusic() {
        let journeyPage = route == .journey && journey != nil && journey?.page != .game
        menuMusic.set(experience == .full && foreground && (route == .menu || route == .lobby || journeyPage) && preferences.menuMusic)
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
    /// Android PlayActivity.detach: also ends the loading page, starts a new room epoch and clears the full-roster pause
    /// (5375378, 1fc4bc2).
    private func closeObservers() {
        loadingMatch = false; roomEpoch &+= 1; fullRosterSeenAt = 0; rosterStartPosted = false
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
    /// App Store captures only (StoreScreenshotScene, MPStoreScreenshot): opens one screen at launch, offline, with house
    /// players and a fixed seed. Each capture starts from a fresh install, so the rally skips the first-visit tour.
    /// `multi.avatar` (the profile editor's avatar choice) is opened by the home view; `home` needs nothing.
    func applyStoreScreenshotScene() {
        switch StoreScreenshotScene.name ?? "" {
        case "pong.play":
            preferences.crossGuideSeen = true
            openCross(learn: false, seed: MPStoreScreenshot.seed)
        case "pong.guide": openCross(learn: true, seed: MPStoreScreenshot.seed)
        case "pong.rival": playerIndex = MPRoster.all.firstIndex { $0.id == "kyra" } ?? 0
        case "multi.teams":
            // The local 2-on-2 team match with house players (Android CrossJourneyActivity "Start team match"); an
            // opponent serves first, so the rally is under way when the capture is taken.
            openJourney(.teams, players: 4)
            journey?.startTeamMatch(seed: MPStoreScreenshot.seed, firstServer: 1)
        case "multi.journey": openJourney(.brief)
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
        journey?.musicChanged = { [weak self] in self?.syncMusic() }
        route = .journey
    }
    private func closeJourney() {
        journey = nil
        route = journeyReturn
        syncMusic()
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
        syncMusic()
    }
    /// The tour's "Learn team play" action (Android guide_team_practice): the team game page over the local match.
    func tourTeamPractice() {
        endTour()
        openJourney(.teams)
    }
    /// Android toggleCamera on the local court (47ad0c9, a9140c3): the close camera or the whole court, in either orientation. The
    /// button shows the next camera instead of a toast.
    func toggleActionCamera() { actionCamera.toggle() }

    // ---- local cross match and its guide (Android CrossActivity) ------------------------------------------------------------
    var crossControl: CrossControl { CrossControl.fromChoice(preferences.control.rawValue) }
    /// Android "Learn how to play with Minik": the cross table's tour, then a local match with house players.
    func openCross(learn: Bool, seed: Int64? = nil) {
        audio.stop(); closeObservers(); session = nil; fixture = nil; result = nil; celebration = nil; scene = nil
        clearCross()
        crossLearn = learn
        installLocalCross(newCrossEngine(seed: seed))
        route = .cross
        if learn || !preferences.crossGuideSeen { startTour() }
    }
    private func myName() -> String { identity?.name ?? MPNames.candidate(0, hebrew: hebrew, character: identity?.characterId ?? "miniko") }
    private func newCrossEngine(seed: Int64? = nil) -> CrossEngine {
        let me = CrossSeat(index: 0, kind: .local, id: "local", name: myName(), characterId: identity?.characterId ?? "", avatar: identity?.avatar ?? 0)
        let ids = Array(preferences.crossOpponents.prefix(preferences.crossPlayers - 1))
        let others = ids.enumerated().map { item -> CrossSeat in
            let c = MPRoster.find(item.element) ?? MPRoster.all[0]
            return CrossSeat(index: item.offset + 1, kind: .house, id: "bot_" + c.id, name: c.name(hebrew: hebrew), bot: c.profile, characterId: c.id)
        }
        return CrossEngine(seats: [me] + others, control: crossControl, target: preferences.crossTarget, seed: seed ?? Int64.random(in: 1...Int64.max))
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
        // Android 1dbfe33: a house character's win is told in agreement with the character (MatchResultWords).
        let house = winner < engine.seats.count && engine.seats[winner].kind == .house ? engine.seats[winner].characterId : nil
        let title = won ? MPResultWords.youWon() : MPResultWords.winner(winnerName, houseCharacter: house)
        // Android 47ad0c9: each name in its seat colour.
        let rows = order.map { MPXResultRow(name: $0.offset < names.count ? names[$0.offset] : "", score: $0.element, winner: $0.offset == winner,
                                            color: MPXSeatColor.argb($0.offset)) }
        crossResult = CrossLocalResult(title: title, rows: rows, won: won)
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
        guard route == .cross, tourCard == nil, crossHelp == nil, let engine = localCross else { return }
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
        tourCard = CrossTourCard(title: card.title, message: card.message, phase: t.phase, canGoBack: t.canGoBack, canGoNext: t.canGoNext,
                                 teamPractice: t.phase == .info && (t.lesson.kind == .team || t.lesson.kind == .scoring))
        // Android d0bed3b: reaching the last card (no Next) marks the guide as seen (`guide_seen`).
        if !t.canGoNext { preferences.crossGuideSeen = true }
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
    /// Android d0bed3b: Next is offered only while there is a next card, so it never ends the guide.
    func tourNext() {
        guard let t = tour else { return }
        if t.next() { showTourCard() }
    }
    /// Android 47ad0c9: Back on the first card leaves the guide, like its close (X) control. Android d0bed3b: the card offers Back
    /// only when there is a card before it.
    func tourBack() {
        guard let t = tour else { return }
        if t.canGoBack { t.back(); showTourCard() } else { exitLearning() }
    }
    /// The guide's close (X) control (Android `guideDialog(…) { finish() }`): the learning screen closes at once.
    func exitLearning() {
        audio.stop()
        goHome()
    }
    /// Android CrossActivity.showHelp (47ad0c9): the match pauses and the help shows the current lesson's card, or how to play
    /// at the chosen control level; its X resumes a match that was running.
    func showCrossHelp() {
        let running = localCross?.paused == false
        pauseLocalCross()
        let message: String
        if let t = tour { message = t.card(hebrew).message }
        else {
            let level: String
            switch crossControl {
            // Android d0bed3b: a serve may also tap another player's court (courtTap2026 in the catalog).
            case .beginner: level = text("Serve: tap another player’s court to aim there, or tap your side and drag left or right. Return: move your paddle into the ball's path; it hits automatically.",
                                         "הגשה: הקישו בצד של שחקן אחר כדי לכוון לשם, או הקישו בצד שלכם וגררו לשמאל או לימין. החזרה: הזיזו את המחבט למסלול הכדור; החבטה אוטומטית.")
            // Android b0cdeb3: the Starter level's help.
            case .starter: level = text("Move into reach, then tap or swipe early to aim. Starter gives you a longer return window.",
                                        "זזים אל הכדור, ואז מקישים או מחליקים מוקדם כדי לכוון. בשליטה נינוחה יש יותר זמן להחזרה.")
            case .standard: level = text("Serve: tap another player’s court, or tap your side and swipe to aim. Return: when the ball reaches your paddle, tap the target court or swipe sideways.",
                                         "הגשה: הקישו בצד של שחקן אחר, או הקישו בצד שלכם והחליקו כדי לכוון. החזרה: כשהכדור מגיע למחבט, הקישו בצד שאליו תרצו לכוון או החליקו הצידה.")
            case .pro: level = text("Swipe up through the ball. Aim with the swipe direction; a faster swipe adds power.",
                                    "החליקו למעלה דרך הכדור. כיוון ההחלקה מכוון את החבטה ומהירותה קובעת את העוצמה.")
            }
            message = text("Keep the ball on the table and send it to another player's colored arm. ", "השאירו את הכדור על השולחן ושלחו אותו לזרוע הצבעונית של שחקן אחר. ") + level
        }
        crossHelp = CrossHelpCard(title: text("Help", "עזרה"), message: message, resume: running)
    }
    func closeCrossHelp() {
        guard let help = crossHelp else { return }
        crossHelp = nil
        if help.resume && route == .cross && tourCard == nil { resumeLocalCross() }
    }
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
        install(MPEngine(level: tutorialStep.level, target: 7, houseControls: false, exercise: tutorialStep.exercise, seed: 42), tutorial: true)
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
