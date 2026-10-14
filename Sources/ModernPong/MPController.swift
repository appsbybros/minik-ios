import Foundation
import Combine
import os

struct ModernPongResult: Codable, Equatable { var playerPoints: Int; var opponentPoints: Int; var won: Bool }
/// `journey`: Android PongJourneyActivity (daily journey, team play, settings, online teams).
/// `createTournament`: Android PlayActivity's separate "Create tournament" page (2026-10).
enum MPRoute { case menu, lobby, game, guide, result, journey, createTournament }

@MainActor final class MPController: ObservableObject {
    let experience: ModernPongExperience, preferences: MPPreferences, audio = MPAudio(), ads: MPAds
    /// Android PongJourneyActivity's pages; Back from its first page returns to this menu.
    let journey = MPJourneyController()
    @Published var route = MPRoute.menu { didSet { syncMenuMusic() } }
    /// Android PlayActivity.confirmTournamentExit: Back from an unfinished tournament asks Save / Don't save / Cancel.
    @Published var tournamentExitPrompt = false
    @Published var scene: MPScene?
    @Published var session: MPSession?
    @Published var fixture: MPFixture?
    @Published var identity: MPIdentity?
    @Published var rooms: [MPSession] = []
    /// Android VictoryConfetti: a new value starts one brief, noninteractive celebration.
    @Published var celebration: UUID?
    @Published var busy = false
    @Published var error: String?
    @Published var connected = false
    @Published var connecting = false
    @Published var hebrew = false
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
    /// Owner report 2026-10: a problem while a match is on screen is a short status line (Android
    /// PrivateMatchActivity), never a dialog over the court.
    @Published var gameWarning: String?
    /// Who won the point that just ended (local or authoritative matches), for the status line.
    @Published var pointWinner: MPSide?
    private static let log = Logger(subsystem: "com.appsbybros.minik.pingpong", category: "ModernPong")
    /// Only a connection attempt the player asked for ("Retry online connection") reports a failure in a dialog.
    private var announceConnectionFailure = false
    /// When the in-match warning was last raised; it fades from the status line once problems stop.
    private var warningAt: Int64 = 0
    private var repo: any MPRepository, subscriptions: [MPSubscription] = [], link: MPMatchLink?
    private var presenceSubscription: MPSubscription?
    private var foreground = true, started = false, handlingReady = false, handlingStart = false, observedRoster = Set<String>(), observedReady = Set<String>()
    private var liveID = "", pausedMatchID = "", handledResults = Set<String>(), renderAt: Int64 = 0, activityAt: Int64 = 0, demoGesture = false, closing = false
    /// Android ModernActivity opens the guide before its local match unless hidden. `resumeAfterGuide`
    /// remembers that match (its practice flag) so "To the game" continues it.
    private var guideOffered = false, resumeAfterGuide: Bool?
    private var completion: (ModernPongResult?) -> Void
    private static let practiceLevelKey = "modern.pong.practice.level"
    /// CI smoke launches pass `-MinikOfflineSmoke YES`; they must never reach production Firebase.
    static var offlineSmoke: Bool { UserDefaults.standard.bool(forKey: "MinikOfflineSmoke") }
    init(experience: ModernPongExperience, preferences: MPPreferences = .init(), repository: (any MPRepository)? = nil, onClose: @escaping (ModernPongResult?) -> Void) {
        self.experience = experience; self.preferences = preferences; completion = onClose; ads = .init(preferences: preferences, experience: experience)
        level = preferences.control; target = preferences.control.target(preferences.target); skipGuide = preferences.skipGuide; identity = preferences.identity
        // Android's local level defaults to Beginner (ModernActivity getInt("difficulty", 4)).
        let savedPractice = preferences.defaults.object(forKey: MPController.practiceLevelKey) as? Int
        practiceLevel = savedPractice.flatMap { MPLevel(rawValue: $0) } ?? .beginner
        if let repository { repo = repository }
        else if MPController.offlineSmoke { repo = MPLocalRepository() }
        else {
            #if MINIK_PING_PONG && canImport(FirebaseDatabase) && canImport(FirebaseAuth)
            repo = experience.online ? (MPFirebaseRepository.configured() as (any MPRepository)?) ?? MPLocalRepository() : MPLocalRepository()
            #else
            repo = MPLocalRepository()
            #endif
        }
        journey.onExit = { [weak self] in self?.route = .menu }
        // The header shows the journey page's own title.
        journeyWatch = journey.objectWillChange.sink { [weak self] _ in self?.objectWillChange.send() }
    }
    private var journeyWatch: AnyCancellable?
    var online: Bool { repo.online }
    var selectedPlayer: MPHousePlayer { MPRoster.all[playerIndex % MPRoster.all.count] }
    func text(_ english: String, _ hebrew: String) -> String { self.hebrew ? hebrew : english }
    func start(hebrew: Bool, removeAds: Bool) async {
        self.hebrew = hebrew; guard !started else { return }; started = true
        syncMenuMusic()
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
        } catch {
            // Starting without internet is normal: house players stay playable and the menu offers a retry
            // (owner report 2026-10: no connection dialog while playing locally).
            Self.log.error("Modern Pong online start failed: \(String(describing: error), privacy: .public)")
            if announceConnectionFailure { show(error) }
        }
        announceConnectionFailure = false
    }
    func retryOnline(removeAds: Bool) async {
        guard !connecting else { return }; started = false; announceConnectionFailure = true
        await start(hebrew: hebrew, removeAds: removeAds)
    }
    func perform(_ operation: @escaping () async throws -> Void) async {
        guard !busy else { return }; busy = true; defer { busy = false }
        do { try await operation() } catch { show(error) }
    }
    private func show(_ issue: Error) {
        Self.log.error("Modern Pong issue: \(String(describing: issue), privacy: .public)")
        // Owner report 2026-10-14: "Connection problem" showed while the child played the house players of a
        // tournament. Those players run on this device; the room only needs the server to start the match and
        // to save its result, which the match link retries ("Saving the result…" stays up until it is saved).
        if route == .game && link?.housePlayersOnly == true { return }
        if route == .game {
            // Owner report 2026-10: never interrupt a match with a dialog. The status line explains it and the
            // match link keeps retrying (Android PrivateMatchActivity shows the same kind of line).
            gameWarning = issue as? MPError == .configuration
                ? text("This match needs the same app version on both devices.", "המשחק הזה דורש את אותה גרסת אפליקציה בשני המכשירים.")
                : text("Connection problem. Trying again…", "יש בעיה בחיבור. מנסים שוב…")
            warningAt = MPClock.now
            return
        }
        if let e = issue as? MPError {
            switch e {
            case .code: error = text(e.rawValue, "הזינו קוד בן שישה תווים.")
            case .full: error = text(e.rawValue, "המשחק כבר התחיל או שאין מקום פנוי.")
            case .limit: error = text(e.rawValue, "אפשר לפתוח עד שלושה משחקים ושלושה טורנירים.")
            case .missing: error = text(e.rawValue, "לא נמצא משחק או טורניר עם הקוד הזה.")
            case .duplicate: error = text(e.rawValue, "הבחירה כבר תפוסה. נסו אפשרות אחרת.")
            case .roster: error = text(e.rawValue, "מלאו את רשימת השחקנים לפני ההתחלה.")
            default: error = text(e.rawValue, "לא ניתן להשלים את הפעולה כרגע. נסו שוב.")
            }
        } else { error = text("Online play is not available right now. Check the internet connection and try again.", "המשחק המקוון אינו זמין כרגע. בדקו את החיבור לאינטרנט ונסו שוב.") }
    }
    func saveControls() { preferences.control = level; target = level.target(target); preferences.target = target }
    func profile(index: Int, avatar: Int, character: String) async {
        await perform {
            self.identity = try await self.repo.profile(index: index, hebrew: self.hebrew, avatar: avatar, character: character)
            self.preferences.identity = self.identity
        }
    }
    func create(_ kind: MPSessionKind, capacity: Int = 2, legs: Int = 1, winPoints: Int = 3, format: MPTournamentFormat = .roundRobin, house: MPHousePlayer?) async {
        saveControls()
        if experience == .simple { startSingle(); return }
        // Owner report 2026-10: a friendly game against a house player is local play. With Firebase it no
        // longer opens an online room, so it never waits for, or reports, the internet. Builds without Firebase
        // keep their local room ("Your games").
        if house != nil, kind == .friendly, online || !connected { startSingle(); return }
        await perform {
            guard let identity = self.identity else { throw MPError.configuration }
            var s = MPSession(code: MPRules.code(), kind: kind, host: identity, capacity: capacity, legs: legs, winPoints: winPoints, difficulty: self.level.rawValue, target: self.target, format: format)
            if let house { s = try MPRules.add(s, actor: identity.id, player: house, hebrew: self.hebrew) }
            s = try await self.repo.create(s); self.enter(s)
        }
    }
    func join(_ raw: String) async {
        await perform {
            guard self.online, let identity = self.identity else { throw MPError.configuration }; let code = try MPRules.normalize(raw)
            for kind in MPSessionKind.allCases {
                let found = try await self.repo.get(kind, code)
                if let old = found {
                    _ = try MPRules.join(old, identity); try await self.repo.reserve(kind, code)
                    let s = try await self.repo.mutate(kind, code) { try MPRules.join($0, identity) }; self.enter(s); self.audio.play("connected"); return
                }
            }; throw MPError.missing
        }
    }
    func enter(_ s: MPSession) {
        closeObservers(); closing = false; pausedMatchID = ""; observedRoster = Set(s.roster); observedReady = Set(s.matches.values.flatMap { $0.ready.keys })
        session = s; route = .lobby; result = nil; fixture = nil; scene = nil; celebration = nil
        subscriptions.append(repo.observe(s.kind, s.code) { [weak self] value in
            guard let self, !self.closing else { return }
            switch value {
            case .success(let s): self.receive(s)
            case .failure(let error):
                if error as? MPError == .missing { self.preferences.removed(s); self.closeObservers(); self.session = nil; self.scene = nil; self.rooms = self.preferences.rooms; self.route = .menu }
                else { self.show(error) }
            }
        })
        syncLobbyPresence(s)
        preferences.remember(s); rooms = preferences.rooms
    }
    private func receive(_ s: MPSession) {
        let joined = Set(s.roster).subtracting(observedRoster).contains { s.human($0) && $0 != repo.uid }
        let readiness = Set(s.matches.values.flatMap { $0.ready.filter { $0.value }.keys }), otherReady = readiness.subtracting(observedReady).contains { $0 != repo.uid }
        if joined { audio.play("connected") }; if otherReady { audio.play("player_ready") }
        observedRoster = Set(s.roster); observedReady = readiness
        session = s; link?.update(s); preferences.remember(s); rooms = preferences.rooms
        // Android PlayActivity.completed: a room completed while it is shown celebrates the winner once.
        if route == .lobby, s.complete, MPCompletionText.won(s, repo.uid), preferences.firstCelebration(s) { celebration = UUID() }
        if !handlingStart, s.kind == .friendly, s.state == "WAITING", s.host == repo.uid, s.roster.count == s.capacity {
            handlingStart = true
            let uid = repo.uid
            Task {
                defer { handlingStart = false }
                do {
                    let active = try await repo.mutate(s.kind, s.code) { try MPRules.start($0, actor: uid) }
                    if active.participants.values.contains(where: { $0.bot != nil }), let match = active.matches.values.first {
                        _ = try await repo.mutate(s.kind, s.code) { try MPRules.ready($0, match: match.id, uid: uid, value: true) }
                    }
                } catch { show(error) }
            }
        }
        if let fixture, let m = s.matches[fixture.id], m.phase == .finished {
            self.fixture = m
            let points = m.a == repo.uid ? (m.scoreA, m.scoreB) : (m.scoreB, m.scoreA)
            finish(id: m.id, value: .init(playerPoints: points.0, opponentPoints: points.1, won: m.winner == repo.uid)); return
        }
        if route != .game, let playing = s.matches.values.sorted(by: { $0.id < $1.id }).first(where: { $0.phase == .playing && $0.contains(repo.uid) }) {
            if foreground && route == .lobby && playing.id != pausedMatchID { launch(s, playing) } else { syncLobbyPresence(s) }; return
        }
        if route != .game && foreground { syncLobbyPresence(s) }
        if !handlingReady {
            let ready = s.matches.values.sorted { $0.id < $1.id }.first { MPRules.startReady(s, match: $0.id) != s }
            if let ready, ready.contains(repo.uid) || s.host == repo.uid {
                handlingReady = true
                Task { defer { handlingReady = false }; do { _ = try await repo.mutate(s.kind, s.code) { MPRules.startReady($0, match: ready.id) } } catch { show(error) } }
            }
        }
    }
    func addHouse(_ player: MPHousePlayer) async {
        guard let s = session else { return }; let uid = repo.uid, he = hebrew
        await perform { _ = try await self.repo.mutate(s.kind, s.code) { try MPRules.add($0, actor: uid, player: player, hebrew: he) } }
    }
    /// Host removes a house player from a tournament that has not started (Android PlayActivity).
    func removeHouse(_ id: String) async {
        guard let s = session else { return }; let uid = repo.uid
        await perform { _ = try await self.repo.mutate(s.kind, s.code) { try MPRules.removeHouse($0, actor: uid, id: id) } }
    }
    func startTournament() async {
        guard let s = session else { return }; let uid = repo.uid
        await perform { _ = try await self.repo.mutate(s.kind, s.code) { try MPRules.start($0, actor: uid) } }
    }
    func ready(_ match: MPFixture) async {
        guard let s = session else { return }; let uid = repo.uid
        await perform {
            if match.phase == .playing { self.launch(s, match); return }
            _ = try await self.repo.mutate(s.kind, s.code) { try MPRules.ready($0, match: match.id, uid: uid, value: match.ready[uid] != true) }
        }
    }
    var userID: String { repo.uid }
    func leave(delete: Bool) async {
        guard let s = session else { return }
        await perform {
            self.closing = true; self.closeObservers()
            do { try await self.repo.leave(s, delete: delete); self.preferences.removed(s); self.rooms = self.preferences.rooms; self.session = nil; self.scene = nil; self.route = .menu }
            catch { self.enter(s); throw error }
        }
    }
    func refreshRooms() async throws {
        // Keep local history until a successful server read confirms deletion.
        try await repo.cleanup()
        let known = try await repo.openRooms(); var keys = Set<String>()
        for (kind, code) in known + preferences.rooms.map({ ($0.kind, $0.code) }) {
            let id = kind.path + "/" + code; guard keys.insert(id).inserted else { continue }
            if let s = try await repo.get(kind, code), s.human(repo.uid) { preferences.remember(s) }
            else if let old = preferences.rooms.first(where: { $0.id == id }) { preferences.removed(old) }
        }; rooms = preferences.rooms
    }
    /// Android "Done" on a completed room (and Back from it): the result is dismissed, never kept as history;
    /// a local copy is removed.
    func dismissCompleted() {
        guard let s = session else { return }
        celebration = nil; preferences.dismissResult(s); closeObservers(); (repo as? MPLocalRepository)?.remove(s)
        session = nil; scene = nil; fixture = nil; result = nil; rooms = preferences.rooms; route = .menu
    }
    /// Android PrivateMatchActivity result dialog: a completed round robin or friendly room is dismissed;
    /// a completed knockout first shows its bracket; an unfinished tournament continues in its room.
    func closeResult() {
        celebration = nil
        guard let s = session else { return }
        if s.complete && !s.knockout { dismissCompleted(); return }
        if s.kind == .tournament { route = .lobby; return }
        closeObservers(); scene = nil; session = nil; fixture = nil; route = .menu
    }
    private func launch(_ s: MPSession, _ match: MPFixture) {
        link?.close(); practice = false; paused = false; pausedMatchID = ""; fixture = match; liveID = match.id; celebration = nil; gameWarning = nil; pointWinner = nil; route = .game; acquirePresence(s)
        let opponent = s.participants[match.a == repo.uid ? match.b : match.a], networked = opponent?.bot == nil
        // Android `ControlChoice.difficulty`: older intermediate room levels (1, 2) play with Standard input.
        let engine = MPEngine(level: MPLevel.control(s.difficulty), target: s.target, bot: opponent?.bot, networked: networked,
                              first: match.a == repo.uid ? .child : .minik, seed: UInt64(bitPattern: match.seed))
        install(engine); scene?.remoteCharacter = opponent?.identity.characterId; scene?.remoteIcon = MPNames.icons[(opponent?.identity.avatar ?? 0) % MPNames.icons.count]
        let link = MPMatchLink(repo: repo, session: s, record: match, engine: engine, preferences: preferences) { [weak self] in self?.show($0) }
        self.link = link; link.active = foreground; route = .game; link.open()
    }
    func startSingle(practice: Bool = false) {
        // Like Android ModernActivity: the guide opens before this screen's first local match unless
        // "Don't show the guide automatically" is on. "To the game" then starts the requested match.
        if !practice && !skipGuide && !guideOffered && route != .guide {
            guideOffered = true; guide(); resumeAfterGuide = practice; return
        }
        audio.stop(); saveControls(); closeObservers(); session = nil; fixture = nil; result = nil; celebration = nil; liveID = UUID().uuidString
        self.practice = practice; paused = false; gameWarning = nil; pointWinner = nil
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
            // Display-only hints; the engine's wire status stays one of Android's GameStatus names.
            // "SHORT_FAULT": the ball bounced on its hitter's own side. It used to read "landed outside" while
            // the ball was visibly on the table (owner report 2026-10).
            if link != nil && link?.ready != true { status = "WAITING" }
            else if engine.automaticContact && engine.childReturnOpen { status = "AUTO_HINT" }
            else if engine.status == "OUT_FAULT" && engine.lastResolution?.fault == .firstBounceOut { status = "SHORT_FAULT" }
            else { status = engine.status }
            pointWinner = engine.lastResolution?.winner
            if gameWarning != nil && now - warningAt > 6000 { gameWarning = nil }
        }
        if route == .game && foreground && !engine.paused && now - activityAt >= 1000 { ads.active(now - activityAt); activityAt = now }
        // The final point stays on the table for a moment (its reason and "You won the match!") before the result.
        if link == nil, let winner = engine.score.winner, route == .game, engine.winnerAge >= 1.2 { finish(id: liveID, value: .init(playerPoints: engine.score.child, opponentPoints: engine.score.minik, won: winner == .child)) }
    }
    private func finish(id: String, value: ModernPongResult) {
        guard handledResults.insert(id).inserted else { return }; scene?.setActive(false); link?.close(); link = nil; result = value
        // Android ModernActivity no longer saves a completed result to a history without an explicit choice.
        ads.completed(id) { [weak self] in
            guard let self else { return }
            // Simple hosts (Math) count the finished match now, but the child first sees the result screen and
            // leaves it with Back or Play again. Closing at once felt like a crash (owner report 2026-10).
            if self.experience.closesAfterMatch { self.completion(value) }
            self.route = .result
            // Android VictoryConfetti after the ad: every won match; a completed room celebrates its winner once.
            let celebrate: Bool
            if let s = self.session, s.complete { celebrate = MPCompletionText.won(s, self.repo.uid) && self.preferences.firstCelebration(s) }
            else { celebrate = value.won }
            if celebrate { self.celebration = UUID() }
        }
    }
    func back() {
        if route == .journey { journey.back(); return }
        if route == .createTournament { route = .menu; return }
        // Android: leaving an unfinished tournament's room asks whether to keep it.
        if route == .lobby, let s = session, s.kind == .tournament, !s.complete { tournamentExitPrompt = true; return }
        audio.stop(); scene?.setActive(false)
        if route == .result && session != nil { closeResult(); return }
        // A local match's result returns to the Ping Pong menu; a Simple host is left from there.
        if route == .result { celebration = nil; scene = nil; result = nil; gameWarning = nil; pointWinner = nil; route = .menu; return }
        if route == .lobby, let s = session, s.complete { dismissCompleted(); return }
        if route == .game && session != nil { pausedMatchID = fixture?.id ?? ""; link?.close(); link = nil; route = .lobby; presenceSubscription?.close(); presenceSubscription = nil; return }
        if route == .guide {
            preferences.skipGuide = skipGuide; scene = nil
            // Android navigateBack from a guide opened before a match ends the guide and continues that match.
            if let resume = resumeAfterGuide { resumeAfterGuide = nil; startSingle(practice: resume); return }
            route = .menu; return
        }
        celebration = nil; closeObservers(); scene = nil; session = nil; fixture = nil; route = .menu
        if experience.closesAfterMatch { completion(nil) }
    }
    /// Android PongMenuMusic: a quiet remix on the menu and room screens only, while the app is in front and the
    /// "Menu music" setting is on. Matches, the guide and the journey stay without it.
    func syncMenuMusic() {
        audio.menuMusic(experience == .full && foreground && (route == .menu || route == .lobby || route == .createTournament) && MPJourneyController.musicOn)
    }
    func openJourney(_ page: MPJourneyController.Page) {
        audio.stop(); journey.open(page, identity: identity, hebrew: hebrew); route = .journey
    }
    /// Android `tournamentOptions`: the tournament's settings on their own page.
    func openTournamentOptions() { route = .createTournament }
    /// "Save" keeps the tournament in Saved tournaments; the room is left open for the other players.
    func saveTournamentAndLeave() {
        tournamentExitPrompt = false
        if let s = session { preferences.remember(s); rooms = preferences.rooms }
        closeObservers(); scene = nil; session = nil; fixture = nil; route = .menu
    }
    /// "Don't save": delete a tournament this player may delete, otherwise leave it for the others.
    func discardTournament() async {
        tournamentExitPrompt = false
        guard let s = session else { return }
        await leave(delete: MPRules.canDelete(s, actor: repo.uid))
    }
    /// Android PlayActivity.leaveFriendly(delete = false): "Save for later" keeps the game listed.
    func saveFriendlyForLater() {
        if let s = session { preferences.remember(s); rooms = preferences.rooms }
        closeObservers(); scene = nil; session = nil; fixture = nil; route = .menu
    }
    /// Android matchRow "Start" for a match whose only human is this player: readiness alone starts it.
    func startHouseMatch(_ match: MPFixture) async {
        guard let s = session else { return }; let uid = repo.uid
        await perform { _ = try await self.repo.mutate(s.kind, s.code) { try MPRules.ready($0, match: match.id, uid: uid, value: true) } }
    }
    /// Result screen "Play again" after a local match: the same opponent, controls and points to win.
    func playAgain() { celebration = nil; startSingle(practice: practice) }
    func close() { foreground = false; audio.stop(); audio.menuMusic(false); journey.lifecycle(active: false); scene?.setActive(false); closeObservers() }
    func lifecycle(active: Bool) {
        guard foreground != active else { return }; foreground = active
        journey.lifecycle(active: active); syncMenuMusic()
        if !active { audio.stop(); scene?.setActive(false); closeObservers() }
        else if let s = session {
            let wasGame = route == .game; scene?.setActive(false); closing = false
            if wasGame { route = .lobby; pausedMatchID = "" }
            subscriptions.append(repo.observe(s.kind, s.code) { [weak self] value in if case .success(let s) = value { self?.receive(s) } })
            syncLobbyPresence(s)
        } else { scene?.setActive(route == .game && !paused || route == .guide && tutorialPhase != .explanation && tutorialPhase != .feedback) }
        audio.guideMusic(active && route == .guide && tutorialPhase != .attempt)
        activityAt = MPClock.now
    }
    private func acquirePresence(_ s: MPSession) { if presenceSubscription == nil { presenceSubscription = repo.presence(s.kind, s.code) } }
    /// Android PlayActivity.syncLobbyPresence (7f5dd0a): outside the court, presence is held only while this player
    /// has no PLAYING match, so a lobby visit never keeps the other court running. iOS uses one presence for lobby and
    /// court, so a court that is about to launch keeps it rather than dropping and reopening it.
    private func syncLobbyPresence(_ s: MPSession) {
        guard route != .game else { return }
        if s.needsLobbyPresence(repo.uid) { acquirePresence(s) } else { presenceSubscription?.close(); presenceSubscription = nil }
    }
    private func closeObservers() { link?.close(); link = nil; subscriptions.forEach { $0.close() }; subscriptions = []; presenceSubscription?.close(); presenceSubscription = nil }
    func togglePause() {
        if session != nil { back(); return }
        paused.toggle(); scene?.setActive(!paused && foreground); activityAt = MPClock.now; if paused { audio.stop() }
    }
    /// App Store captures only (StoreScreenshotScene): opens one screen at launch, offline.
    func applyStoreScreenshotScene() {
        switch StoreScreenshotScene.name ?? "" {
        case "pong.play": startSingle(practice: true)
        case "pong.guide": guide(); tutorialStep = .autoReturn; tutorialStart(demo: true)
        case "pong.rival": playerIndex = MPRoster.all.firstIndex { $0.id == "kyra" } ?? 0
        default: break
        }
    }
    func guide() {
        closeObservers(); session = nil; fixture = nil; resumeAfterGuide = nil; celebration = nil
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
