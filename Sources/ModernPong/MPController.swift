import Foundation
import Combine
import os

struct ModernPongResult: Codable, Equatable { var playerPoints: Int; var opponentPoints: Int; var won: Bool }
/// `journey`: Android PongJourneyActivity (daily journey, team play, settings, online teams).
/// `createTournament`: Android PlayActivity's separate "Create tournament" page (2026-10).
/// `createFriendly`: Android PlayActivity.friendlyOptions (305914e): the friendly setup as its own page.
/// `colorChallenge`: Android ColorChallengeActivity (6feaac5).
enum MPRoute { case menu, lobby, game, guide, result, journey, createTournament, createFriendly, colorChallenge }

@MainActor final class MPController: ObservableObject {
    let experience: ModernPongExperience, preferences: MPPreferences, audio = MPAudio(), ads: MPAds
    /// Android PongJourneyActivity's pages; Back from its first page returns to this menu.
    let journey = MPJourneyController()
    @Published var route = MPRoute.menu { didSet { syncMenuMusic(); checkPromotion() } }
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
    /// Android's open-game limit has its own dialog title ("Open-game limit reached").
    @Published var errorTitle: String?
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
    /// Android `showServeDoubleBounceTip`: "two bounces on their side win you the point" replaces the point line.
    @Published var serveTip = false
    /// Android `PongRanking`: colour ranks with durable receipts. `rankRevision` repaints the screens after a change.
    let ranking: MPRanking
    @Published var rankRevision = 0
    /// Android ColorChallengeActivity `trialControl`: Starter (1) until the player picks another allowed control.
    @Published var challengeControl = 1
    /// Android `ColorChallengeActivity.celebrate`: the colour just earned, shown once over the menu or challenge screen.
    @Published var promotion: Int?
    /// Android `MatchResultDialog`: the result screen's headline, cards and actions.
    @Published var matchResult: MPMatchResult?
    /// Android PlayActivity.showMatchLoading (f0f27c4): "Loading…" while a friendly game against a house player starts.
    @Published var loading = false
    /// Android createForm `arena_FRIENDLY` / `arena_TOURNAMENT` selectors.
    @Published var friendlyArena: MPArena { didSet { preferences.setArena(friendlyArena, for: .friendly) } }
    @Published var tournamentArena: MPArena { didSet { preferences.setArena(tournamentArena, for: .tournament) } }
    /// Android PrivateMatchActivity.remoteRank: the online opponent's published colour, once known.
    @Published var remoteRank: MPRankBadge?
    private static let log = Logger(subsystem: "com.appsbybros.minik.pingpong", category: "ModernPong")
    /// Only a connection attempt the player asked for ("Retry online connection") reports a failure in a dialog.
    private var announceConnectionFailure = false
    /// When the in-match warning was last raised; it fades from the status line once problems stop.
    private var warningAt: Int64 = 0
    /// `mainRepo` is the app's repository (Firebase, or local without it); `repo` is the open room's, which is the local
    /// one for a Color Challenge (Android `PongServices.local`).
    private let mainRepo: any MPRepository
    private var repo: any MPRepository, subscriptions: [MPSubscription] = [], link: MPMatchLink?
    private var localStore: MPLocalRepository?
    private var rankWatch: MPSubscription?, watchedRank = ""
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
        ranking = MPRanking(preferences.defaults); friendlyArena = preferences.arena(.friendly); tournamentArena = preferences.arena(.tournament)
        // Android's local level defaults to Beginner (ModernActivity getInt("difficulty", 4)).
        let savedPractice = preferences.defaults.object(forKey: MPController.practiceLevelKey) as? Int
        practiceLevel = savedPractice.flatMap { MPLevel(rawValue: $0) } ?? .beginner
        let main: any MPRepository
        if let repository { main = repository }
        else if MPController.offlineSmoke { main = MPLocalRepository() }
        else {
            #if MINIK_PING_PONG && canImport(FirebaseDatabase) && canImport(FirebaseAuth)
            main = experience.online ? (MPFirebaseRepository.configured() as (any MPRepository)?) ?? MPLocalRepository() : MPLocalRepository()
            #else
            main = MPLocalRepository()
            #endif
        }
        mainRepo = main; repo = main
        journey.onExit = { [weak self] in self?.route = .menu }
        // The header shows the journey page's own title.
        journeyWatch = journey.objectWillChange.sink { [weak self] _ in self?.objectWillChange.send() }
    }
    private var journeyWatch: AnyCancellable?
    var online: Bool { mainRepo.online }
    /// Android `PongServices.local`: one local store shared with local rooms (UserDefaults keeps one copy).
    private var localRooms: MPLocalRepository {
        if let local = mainRepo as? MPLocalRepository { return local }
        if let localStore { return localStore }
        let local = MPLocalRepository(defaults: preferences.defaults); localStore = local; return local
    }
    /// A Color Challenge room: a registered local qualification match (Android `ranking.trial(s) != null`).
    func challenge(_ s: MPSession) -> Bool { ranking.trial(s) != nil }
    /// Android PlayActivity.hasSpace: at most three open rooms of each kind.
    func hasSpace(_ kind: MPSessionKind) -> Bool { rooms.filter { $0.kind == kind && !$0.complete }.count < 3 }
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
            let uid = try await mainRepo.connect()
            if identity?.id != uid {
                let old = identity; identity = try await mainRepo.profile(index: 0, hebrew: hebrew, avatar: old?.avatar ?? 0, character: old?.characterId ?? "miniko")
                preferences.identity = identity
            }
            // Android PlayActivity.prepare: the player's colour is shared once the profile is claimed.
            connected = true; mainRepo.publishRank(ranking.badge); try await refreshRooms()
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
        errorTitle = nil
        if let e = issue as? MPError {
            switch e {
            case .code: error = text("To join a friend, enter their six-character room code. To start your own game, choose Create game.", "כדי להצטרף לחבר, הזינו את הקוד בן ששת התווים שקיבלתם ממנו. כדי לפתוח משחק משלכם, בחרו ביצירת משחק.")
            case .full: error = text(e.rawValue, "המשחק כבר התחיל או שאין מקום פנוי.")
            case .limit:
                // Android PlayActivity.error("OPEN_LIMIT") dialog (2026-10 text).
                errorTitle = text("Open-game limit reached", "הגעתם למספר המשחקים המרבי")
                error = text("You can keep up to three open friendly games and three open tournaments. To create another game, open Saved games and finish one of them. You can also resume a saved game.", "אפשר לשמור עד שלושה משחקי ידידות פתוחים ושלושה טורנירים פתוחים. כדי ליצור משחק נוסף, פתחו את המשחקים השמורים וסיימו אחד מהם. אפשר גם להמשיך משחק שמור.")
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
            self.identity = try await self.mainRepo.profile(index: index, hebrew: self.hebrew, avatar: avatar, character: character)
            self.preferences.identity = self.identity
            self.mainRepo.publishRank(self.ranking.badge)
        }
    }
    func create(_ kind: MPSessionKind, capacity: Int = 2, legs: Int = 1, winPoints: Int = 3, format: MPTournamentFormat = .roundRobin, house: MPHousePlayer?) async {
        saveControls()
        let localHouseMatch = house != nil && kind == .friendly && (online || !connected)
        // Android PlayActivity.create: a fourth open room of a kind is refused before anything is created.
        if experience == .full && !localHouseMatch && !hasSpace(kind) { show(MPError.limit); return }
        let arena = kind == .tournament ? tournamentArena : friendlyArena
        if experience == .simple { startSingle(); return }
        // Owner report 2026-10: a friendly game against a house player is local play. With Firebase it no
        // longer opens an online room, so it never waits for, or reports, the internet. Builds without Firebase
        // keep their local room ("Your games").
        if house != nil, kind == .friendly, online || !connected { startSingle(); return }
        await perform {
            guard let identity = self.identity else { throw MPError.configuration }
            var s = MPSession(code: MPRules.code(), kind: kind, host: identity, capacity: capacity, legs: legs, winPoints: winPoints, difficulty: self.level.rawValue, target: self.target, format: format, arena: arena.wire)
            if let house { s = try MPRules.add(s, actor: identity.id, player: house, hebrew: self.hebrew) }
            s = try await self.mainRepo.create(s); self.enter(s)
        }
    }
    func join(_ raw: String) async {
        await perform {
            guard self.online, let identity = self.identity else { throw MPError.configuration }; let code = try MPRules.normalize(raw)
            for kind in MPSessionKind.allCases {
                let found = try await self.mainRepo.get(kind, code)
                if let old = found {
                    _ = try MPRules.join(old, identity); try await self.mainRepo.reserve(kind, code)
                    let s = try await self.mainRepo.mutate(kind, code) { try MPRules.join($0, identity) }; self.enter(s); self.audio.play("connected"); return
                }
            }; throw MPError.missing
        }
    }
    /// `local`: the room lives in the local store (a Color Challenge), whatever the app's repository is.
    func enter(_ s: MPSession, local: Bool = false) {
        closeObservers(); repo = local ? localRooms : mainRepo
        closing = false; pausedMatchID = ""; observedRoster = Set(s.roster); observedReady = Set(s.matches.values.flatMap { $0.ready.keys })
        session = s; route = .lobby; result = nil; matchResult = nil; fixture = nil; scene = nil; celebration = nil; remoteRank = nil
        let trial = challenge(s)
        subscriptions.append(repo.observe(s.kind, s.code) { [weak self] value in
            guard let self, !self.closing else { return }
            switch value {
            case .success(let s): self.receive(s)
            case .failure(let error):
                if error as? MPError == .missing {
                    self.preferences.removed(s); self.closeObservers(); self.session = nil; self.scene = nil; self.rooms = self.preferences.rooms
                    if trial { self.ranking.clearActiveTrial(); self.rankRevision += 1; self.route = .colorChallenge } else { self.route = .menu }
                }
                else { self.show(error) }
            }
        })
        syncLobbyPresence(s)
        // A Color Challenge room is never listed in Saved games (Android keeps it out of RoomBook).
        if !trial { preferences.remember(s); rooms = preferences.rooms }
    }
    private func receive(_ s: MPSession) {
        let joined = Set(s.roster).subtracting(observedRoster).contains { s.human($0) && $0 != repo.uid }
        let readiness = Set(s.matches.values.flatMap { $0.ready.filter { $0.value }.keys }), otherReady = readiness.subtracting(observedReady).contains { $0 != repo.uid }
        if joined { audio.play("connected") }; if otherReady { audio.play("player_ready") }
        observedRoster = Set(s.roster); observedReady = readiness
        session = s; link?.update(s)
        if !challenge(s) { preferences.remember(s); rooms = preferences.rooms }
        rankSession(s)
        // Android PlayActivity.completed: a room completed while it is shown celebrates the winner once, with applause.
        if route == .lobby, s.complete, MPCompletionText.won(s, repo.uid), preferences.firstCelebration(s) { celebrateRoom() }
        if !handlingStart, s.kind == .friendly, s.state == "WAITING", s.host == repo.uid, s.roster.count == s.capacity {
            handlingStart = true
            if s.participants.values.contains(where: { $0.bot != nil }) { loading = true }
            let uid = repo.uid
            Task {
                defer { handlingStart = false }
                do {
                    let active = try await repo.mutate(s.kind, s.code) { try MPRules.start($0, actor: uid) }
                    if active.participants.values.contains(where: { $0.bot != nil }), let match = active.matches.values.first {
                        _ = try await repo.mutate(s.kind, s.code) { try MPRules.ready($0, match: match.id, uid: uid, value: true) }
                    }
                } catch { loading = false; show(error) }
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
        try await mainRepo.cleanup()
        let known = try await mainRepo.openRooms(); var keys = Set<String>()
        for (kind, code) in known + preferences.rooms.map({ ($0.kind, $0.code) }) {
            let id = kind.path + "/" + code; guard keys.insert(id).inserted else { continue }
            if let s = try await mainRepo.get(kind, code), s.human(mainRepo.uid), !challenge(s) { preferences.remember(s) }
            else if let old = preferences.rooms.first(where: { $0.id == id }) { preferences.removed(old) }
        }; rooms = preferences.rooms
    }
    /// Android "Done" on a completed room (and Back from it): the result is dismissed, never kept as history;
    /// a local copy is removed.
    func dismissCompleted() {
        guard let s = session else { return }
        let trial = challenge(s)
        celebration = nil; preferences.dismissResult(s); closeObservers(); (repo as? MPLocalRepository)?.remove(s)
        session = nil; scene = nil; fixture = nil; result = nil; matchResult = nil; rooms = preferences.rooms; route = trial ? .colorChallenge : .menu
    }
    /// Android PrivateMatchActivity.closeResult (6feaac5, f0f27c4): a Color Challenge returns to its screen and its local
    /// room is removed; a completed friendly game is dismissed; a tournament (finished or not) returns to its room,
    /// where a completed one shows its podium and celebrates the winner once.
    func closeResult() {
        celebration = nil
        guard let s = session else { return }
        if challenge(s) {
            closeObservers(); localRooms.remove(s); session = nil; scene = nil; fixture = nil; result = nil; matchResult = nil
            rankRevision += 1; route = .colorChallenge; return
        }
        if s.complete && s.kind == .friendly { dismissCompleted(); return }
        if s.kind == .tournament {
            route = .lobby; matchResult = nil
            if s.complete, MPCompletionText.won(s, repo.uid), preferences.firstCelebration(s) { celebrateRoom() }
            return
        }
        closeObservers(); scene = nil; session = nil; fixture = nil; matchResult = nil; route = .menu
    }
    /// The result's "Play again": a local match restarts; a friendly room is replaced by a fresh one with the same
    /// arena, controls, points and house player (Android PlayActivity.replayOptions / startReplay).
    func playAgainFromResult() {
        guard let s = session, s.kind == .friendly, let m = fixture else { playAgain(); return }
        let uid = repo.uid, bot = s.participants[m.a == uid ? m.b : m.a]?.bot
        preferences.dismissResult(s); (repo as? MPLocalRepository)?.remove(s); closeObservers()
        session = nil; scene = nil; fixture = nil; result = nil; matchResult = nil; celebration = nil; rooms = preferences.rooms
        loading = true; route = .lobby
        Task {
            await perform {
                defer { self.loading = false }
                guard let identity = self.identity else { throw MPError.configuration }
                var n = MPSession(code: MPRules.code(), kind: .friendly, host: identity, difficulty: s.difficulty, target: s.target, arena: s.arena)
                if let bot { n = try MPRules.addFriendlyHousePlayer(n, actor: identity.id, player: MPRules.housePlayer(bot)) }
                n = try await self.mainRepo.create(n); self.enter(n)
            }
            loading = false
            if self.session == nil && self.route == .lobby { self.route = .menu }
        }
    }
    /// Android PlayActivity.completed: confetti and, with sounds on, applause.
    private func celebrateRoom() {
        celebration = UUID()
        if MPJourneyController.soundsOn { audio.play("minik_claps") }
    }
    /// Android `PongRanking.session` after every room update; the colour is republished when anything changed.
    private func rankSession(_ s: MPSession) {
        guard experience == .full else { return }
        if ranking.session(s, uid: repo.uid, online: repo.online, opponentBadge: remoteRank) {
            rankRevision += 1
            if repo.online { repo.publishRank(ranking.badge) }
        }
    }
    /// Android `ColorChallengeActivity.celebrate`, on the menu and the challenge screen: once per earned colour, with a
    /// random rank cue (Silver and Gold always the big win).
    func checkPromotion() {
        guard experience == .full, promotion == nil, route == .menu || route == .colorChallenge, let level = ranking.promotion() else { return }
        ranking.acknowledgePromotion(); promotion = level; rankRevision += 1
        if MPJourneyController.soundsOn { audio.play(MPRankCue.celebration(level: level)) }
    }
    /// Android PrivateMatchActivity: the opponent's colour on the court and the score (a human's published colour,
    /// the challenged colour in a Color Challenge, otherwise the second team colour).
    private func opponentColor(_ s: MPSession, _ opponent: MPParticipant?) -> UInt32 {
        if opponent?.bot == nil { return MPRanks.all[min(max(remoteRank?.level ?? 0, 0), MPRanks.lastIndex)].color }
        return ranking.trial(s).map { MPRanks.all[$0].color } ?? MPTeamColors.fill(1)
    }
    var opponentRankColor: UInt32 {
        guard let s = session, let m = fixture else { return MPTeamColors.fill(1) }
        return opponentColor(s, s.participants[m.a == repo.uid ? m.b : m.a])
    }
    /// Android PrivateMatchActivity.shownName: a Champion is introduced by its colour.
    func shownName(_ s: MPSession, _ p: MPParticipant) -> String {
        if let target = ranking.trial(s), ranking.champion(s), p.bot != nil { let rank = MPRanks.all[target]; return text("\(rank.en) Champion", "אלוף הצבע \(rank.he)") }
        return p.name(hebrew: hebrew)
    }
    // MARK: Color Challenge (Android ColorChallengeActivity)
    func openColorChallenge() { audio.stop(); rankRevision += 1; route = .colorChallenge }
    /// Android `ColorChallengeActivity.start`: a local friendly room on the Park arena to 11 points, registered as the
    /// trial, the house player's Start as Ready, then straight into the match.
    func startChallenge(bot: MPBot, target: Int, champion: Bool) {
        let state = ranking.state
        guard !busy, state.eligible, state.next == target else { return }
        // Android c9f5fa6: a completed part of the qualification cannot be started again.
        if champion && state.championWins >= state.requirement.champions { return }
        if !champion && (state.requirement.streak ? state.streak : state.botWins) >= state.requirement.bots { return }
        let choices = [1, 0, 3].filter { MPRankPromotion.allowedControl(target, $0) }
        let control = choices.contains(challengeControl) ? challengeControl : choices[0]
        let local = localRooms, uid = local.uid, character = identity?.characterId ?? "miniko"
        let me = MPIdentity(id: uid, name: identity?.name ?? MPNames.candidate(0, hebrew: hebrew, character: character), avatar: identity?.avatar ?? 0, characterId: character)
        var s = MPSession(code: MPRules.code(), kind: .friendly, host: me, difficulty: control, target: 11, arena: MPArena.park.wire)
        do {
            s = try MPRules.addFriendlyHousePlayer(s, actor: uid, player: MPRules.housePlayer(bot))
            s = try MPRules.start(s, actor: uid)
        } catch { show(error); return }
        guard let match = s.matches.values.first else { return }
        busy = true
        let created = local.store(s)
        ranking.registerTrial(created, target: target, champion: champion)
        let presence = local.presence(created.kind, created.code)
        Task {
            defer { busy = false }
            do {
                let ready = try await local.mutate(created.kind, created.code) { MPRules.startReady(MPRules.friendlyHouseReady($0, actor: uid), match: match.id) }
                presence.close(); enter(ready, local: true)
            } catch {
                presence.close(); rankRevision += 1
                self.error = text("Could not start. Please try again.", "לא ניתן להתחיל. נסו שוב.")
            }
        }
    }
    /// Android "Resume match": the paused qualification match continues from its checkpoint.
    func resumeChallenge() {
        guard let code = ranking.activeTrialCode else { return }
        Task {
            if let s = try? await localRooms.get(.friendly, code) { enter(s, local: true) }
            else { ranking.clearActiveTrial(); rankRevision += 1 }
        }
    }
    /// Android "Forfeit match": an unfinished streak resets; points and completed wins stay.
    func forfeitChallenge() {
        let code = ranking.activeTrialCode
        ranking.abandonTrial(); rankRevision += 1
        guard let code else { return }
        Task { if let s = try? await localRooms.get(.friendly, code) { localRooms.remove(s) }; rankRevision += 1 }
    }
    /// Android PlayActivity.friendlyOptions: the friendly setup page, after the open-game limit check.
    func openFriendlyOptions() {
        guard hasSpace(.friendly) else { show(MPError.limit); return }
        route = .createFriendly
    }
    private func launch(_ s: MPSession, _ match: MPFixture) {
        link?.close(); practice = false; paused = false; pausedMatchID = ""; fixture = match; liveID = match.id; celebration = nil; gameWarning = nil; pointWinner = nil; serveTip = false
        loading = false; matchResult = nil; route = .game; acquirePresence(s)
        let opponent = s.participants[match.a == repo.uid ? match.b : match.a], networked = opponent?.bot == nil
        // Android `ControlChoice.difficulty`: the retired intermediate level 2 plays Standard; 1 is Starter.
        // A Champion trial strengthens the house player (Android `championLevel`).
        let engine = MPEngine(level: MPLevel.control(s.difficulty), target: s.target, bot: opponent?.bot, networked: networked,
                              first: match.a == repo.uid ? .child : .minik, seed: UInt64(bitPattern: match.seed),
                              championLevel: ranking.champion(s) ? (ranking.trial(s) ?? -1) : -1)
        install(engine); scene?.remoteCharacter = opponent?.identity.characterId; scene?.remoteIcon = MPNames.icons[(opponent?.identity.avatar ?? 0) % MPNames.icons.count]
        // Android PrivateMatchActivity.buildGameUi: the room's arena, the player's avatar and both colour ranks.
        scene?.selectedArena = MPArena.read(s.arena)
        scene?.localCharacterId = s.participants[repo.uid]?.identity.characterId ?? ""
        scene?.localRankColor = ranking.rank.uiColor
        // Android `remoteHumanName`: an online opponent's name tag (a Champion is introduced by its colour).
        scene?.remoteName = opponent.flatMap { $0.bot == nil || ranking.champion(s) ? shownName(s, $0) : nil }
        if let opponent, opponent.bot == nil, watchedRank != opponent.id {
            watchedRank = opponent.id; rankWatch?.close()
            rankWatch = repo.rank(opponent.id) { [weak self] badge in
                guard let self else { return }
                self.remoteRank = badge; self.ranking.rememberOpponent(opponent.id, badge)
                self.scene?.remoteRankColor = MPRanks.all[badge.level].uiColor
                if let latest = self.session { self.rankSession(latest) }
            }
        }
        scene?.remoteRankColor = MPColor.ui(opponentColor(s, opponent))
        let link = MPMatchLink(repo: repo, session: s, record: match, engine: engine, preferences: preferences) { [weak self] in self?.show($0) }
        self.link = link; link.active = foreground; route = .game; link.open()
    }
    func startSingle(practice: Bool = false) {
        // Like Android ModernActivity: the guide opens before this screen's first local match unless
        // "Don't show the guide automatically" is on. "To the game" then starts the requested match.
        if !practice && !skipGuide && !guideOffered && route != .guide {
            guideOffered = true; guide(); resumeAfterGuide = practice; return
        }
        audio.stop(); saveControls(); closeObservers(); repo = mainRepo; session = nil; fixture = nil; result = nil; matchResult = nil; celebration = nil; liveID = UUID().uuidString
        self.practice = practice; paused = false; gameWarning = nil; pointWinner = nil; serveTip = false; loading = false
        preferences.defaults.set(practiceLevel.rawValue, forKey: MPController.practiceLevelKey)
        install(MPEngine(level: practice ? practiceLevel : level, target: target, bot: selectedPlayer.profile, houseControls: !practice))
        // Android ModernActivity: the court's arena (the friendly setup's choice; Beach by default, Android's intent
        // default), the player's avatar and colour. Simple hosts do not bundle the arena art and keep the original court.
        if experience == .full {
            scene?.selectedArena = practice ? .beach : friendlyArena
            scene?.localCharacterId = identity?.characterId ?? "miniko"
            scene?.localRankColor = ranking.rank.uiColor
        }
        route = .game
    }
    private func install(_ engine: MPEngine) {
        let scene = MPScene(engine: engine); self.scene = scene; scene.hebrew = hebrew
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
            serveTip = !engine.paused && engine.showServeDoubleBounceTip
            if link != nil && link?.ready != true { status = "WAITING" }
            else if engine.automaticContact && engine.childReturnOpen { status = "AUTO_HINT" }
            else if engine.status == "OUT_FAULT" && engine.lastResolution?.fault == .firstBounceOut { status = "SHORT_FAULT" }
            else { status = engine.status }
            pointWinner = engine.lastResolution?.winner
            if gameWarning != nil && now - warningAt > 6000 { gameWarning = nil }
        }
        if route == .game && foreground && !engine.paused && now - activityAt >= 1000 { ads.active(now - activityAt); activityAt = now }
        // The final point stays on the table for a moment (its reason and "You won the match!") before the result, and
        // Android 920caca waits until the loose ball has come to rest (`settlingBall`).
        if link == nil, let winner = engine.score.winner, route == .game, engine.winnerAge >= 1.2, !engine.settlingBall {
            // Android ModernActivity: `PongRanking.localResult("modern/<completionId>", …)` with the court's control.
            if experience == .full, !handledResults.contains(liveID), ranking.localResult("modern/" + liveID, won: winner == .child, bot: engine.bot ?? MPRoster.all[0].profile, control: engine.level.rawValue) { rankRevision += 1 }
            finish(id: liveID, value: .init(playerPoints: engine.score.child, opponentPoints: engine.score.minik, won: winner == .child))
        }
    }
    /// Android MatchResultDialog contents for a room match (PrivateMatchActivity) or a local match.
    private func resultPanel(_ value: ModernPongResult) -> MPMatchResult {
        if let s = session, let m = fixture, let a = s.participants[m.a], let b = s.participants[m.b] {
            let uid = repo.uid, won = m.winner == uid, trial = ranking.trial(s)
            let title = s.complete ? MPCompletionText.headline(s, uid, hebrew: hebrew)
                : won && s.knockout ? MPKnockout.advanceText(s, m, hebrew: hebrew)
                : won ? text("You won this match!", "ניצחתם במשחק!") : text("Match finished", "המשחק הסתיים")
            func avatar(_ p: MPParticipant) -> String { p.bot?.characterId ?? (p.identity.characterId.isEmpty ? "miniko" : p.identity.characterId) }
            let action = trial != nil ? text("Back to Color Challenge", "חזרה לאתגר הצבע") : s.kind == .tournament ? text("Back to tournament", "חזרה לטורניר") : text("Back to menu", "חזרה לתפריט")
            return MPMatchResult(title: title, first: .init(name: shownName(s, a), avatar: avatar(a), score: m.scoreA), second: .init(name: shownName(s, b), avatar: avatar(b), score: m.scoreB),
                                 winner: m.winner == m.a ? 0 : 1, action: action, localPlayer: m.a == uid ? 0 : 1,
                                 opponentColorOverride: trial.map { MPRanks.all[$0].color }, again: s.kind == .friendly && trial == nil)
        }
        let me = identity?.name ?? text("You", "אתם"), mine = identity?.characterId ?? "miniko"
        return MPMatchResult(title: value.won ? text("You won!", "ניצחתם!") : text("Good game!", "משחק טוב!"),
                             first: .init(name: me, avatar: mine.isEmpty ? "miniko" : mine, score: value.playerPoints),
                             second: .init(name: selectedPlayer.name(hebrew: hebrew), avatar: selectedPlayer.id, score: value.opponentPoints),
                             winner: value.won ? 0 : 1, action: text("Back to menu", "חזרה לתפריט"), again: true)
    }
    private func finish(id: String, value: ModernPongResult) {
        guard handledResults.insert(id).inserted else { return }; scene?.setActive(false); link?.close(); link = nil; result = value
        matchResult = resultPanel(value)
        // Android ModernActivity no longer saves a completed result to a history without an explicit choice.
        ads.completed(id) { [weak self] in
            guard let self else { return }
            // Simple hosts (Math) count the finished match now, but the child first sees the result screen and
            // leaves it with Back or Play again. Closing at once felt like a crash (owner report 2026-10).
            if self.experience.closesAfterMatch { self.completion(value) }
            self.route = .result
            // Android VictoryConfetti after the ad: every won match; a completed room celebrates its winner once.
            // Android 78ed219: a completed tournament celebrates on its podium, not over the result.
            let celebrate: Bool
            if let s = self.session, s.complete, s.kind == .tournament { celebrate = false }
            else if let s = self.session, s.complete { celebrate = MPCompletionText.won(s, self.repo.uid) && self.preferences.firstCelebration(s) }
            else { celebrate = value.won }
            if celebrate { self.celebration = UUID() }
        }
    }
    func back() {
        if route == .journey { journey.back(); return }
        if route == .createTournament || route == .createFriendly || route == .colorChallenge { route = .menu; return }
        // Android c9f5fa6: Back from a friendly room whose game never started leaves it (deletes it), as Cancel did.
        if route == .lobby, let s = session, s.kind == .friendly, !s.matches.values.contains(where: { $0.phase == .playing || $0.phase == .finished }) {
            Task { await leave(delete: true) }; return
        }
        // Android: leaving an unfinished tournament's room asks whether to keep it.
        if route == .lobby, let s = session, s.kind == .tournament, !s.complete { tournamentExitPrompt = true; return }
        audio.stop(); scene?.setActive(false)
        if route == .result && session != nil { closeResult(); return }
        // A local match's result returns to the Ping Pong menu; a Simple host is left from there.
        if route == .result { celebration = nil; scene = nil; result = nil; matchResult = nil; gameWarning = nil; pointWinner = nil; route = .menu; return }
        if route == .lobby, let s = session, s.complete { dismissCompleted(); return }
        // Android: Back from a qualification match returns to Color Challenge, where it can be resumed or forfeited.
        if route == .game, let s = session, challenge(s) { closeObservers(); session = nil; scene = nil; fixture = nil; rankRevision += 1; route = .colorChallenge; return }
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
        audio.menuMusic(experience == .full && foreground && (route == .menu || route == .lobby || route == .createTournament || route == .createFriendly) && MPJourneyController.musicOn)
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
        // Android PlayActivity.onStop: leaving the app dismisses a completed tournament's room.
        if !active, route == .lobby, let s = session, s.complete, s.kind == .tournament { dismissCompleted() }
        if !active { audio.stop(); scene?.setActive(false); closeObservers() }
        else if let s = session {
            let wasGame = route == .game; scene?.setActive(false); closing = false
            if wasGame && challenge(s) { session = nil; scene = nil; fixture = nil; rankRevision += 1; route = .colorChallenge; activityAt = MPClock.now; return }
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
    private func closeObservers() {
        link?.close(); link = nil; subscriptions.forEach { $0.close() }; subscriptions = []; presenceSubscription?.close(); presenceSubscription = nil
        rankWatch?.close(); rankWatch = nil; watchedRank = ""
    }
    func togglePause() {
        if session != nil { back(); return }
        paused.toggle(); scene?.setActive(!paused && foreground); activityAt = MPClock.now; if paused { audio.stop() }
    }
    /// App Store captures only (StoreScreenshotScene): opens one screen at launch, offline.
    func applyStoreScreenshotScene() {
        switch StoreScreenshotScene.name ?? "" {
        case "pong.play": startSingle(practice: true)
        case "pong.guide": guide(); tutorialStep = .autoReturn; tutorialStart(demo: true)
        // The house-player carousel now lives on the friendly setup page (Android friendlyOptions).
        case "pong.rival": playerIndex = MPRoster.all.firstIndex { $0.id == "kyra" } ?? 0; route = .createFriendly
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
        // Android ModernTutorial.newEngine: the spin lessons expect their spin (`expectedSpin`); the court knows the lesson.
        install(MPEngine(level: tutorialStep.level, target: 7, houseControls: false, exercise: tutorialStep.exercise, seed: 42, expectedSpin: tutorialStep.expectedSpin))
        scene?.tutorialStep = tutorialStep
        scene?.guidePoint = tutorialStep.serve ? tutorialStep.servePoint : nil; scene?.guideDirection = tutorialStep.serve || tutorialStep.spin ? nil : tutorialStep.aim
    }
    private func tutorialFrame() {
        guard let engine = scene?.engine else { return }
        if !tutorialStep.serve && !tutorialStep.spin { scene?.guidePoint = engine.flight?.receiver == true ? engine.ball : nil }
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
            // Android ModernTutorial.demonstrate (2026-10): spin lessons complete a Pro gesture; the Beginner and tap
            // lessons tap; the aimed lessons move to the ball and make a Standard swipe (Vec(aim, -0.9)).
            if let stroke = tutorialStep.demoStroke { engine.completeGesture(stroke) }
            else if tutorialStep.swipeDirection == nil { engine.touch(point); engine.endTouch() }
            else { engine.prepareGesture(point); engine.standardSwipe(.init(tutorialStep.demoAim, -0.9)); engine.endTouch() }
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
