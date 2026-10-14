import Foundation

/// Why the cross link could not follow or write the match (Android CrossLink `message` strings).
enum CrossLinkIssue: Equatable {
    /// "This match needs the same app version on every phone."
    case version
    /// "Connection interrupted. Reopen this match to resume."
    case interrupted
    case failed(String)
    /// "Ball assistance could not be shared. The match uses normal speed until it connects." (5c1aa4d)
    case reception
}

/// Android cross/CrossLink.kt (MinikCrossPong 5c1aa4d). Online play of one 3/4-player fixture (CROSS_DESIGN §8): the classic
/// match link for N seats in the shared world frame, no mirroring. Seat i is `record.players[i]`. The authority (smallest human
/// uid) runs the referee and the house players, applies every other human's completed strikes once (gated per sender) and writes
/// protocol-2 checkpoints and, once, the result. Every other human publishes each of its own committed strikes and follows the
/// checkpoints. `ready` is false while any human of the fixture is away; the controller then pauses the match, so nobody faults
/// silently.
@MainActor final class CrossLink {
    static let protocolVersion = CrossState.protocolVersion
    /// A follower keeps its own hit this long while no checkpoint acknowledges it.
    static let ackWait: Int64 = 850
    static let period: Int64 = 2000
    static let retry: Int64 = 1500
    private static let bufferLimit = 64
    let match: CrossMatch
    /// The current table stage (an elimination match swaps it as players drop out).
    var engine: CrossEngine { match.engine }
    private let repo: any MPRepository
    private var session: MPSession
    private let record: MPFixture
    private let nextSequence: () -> Int64
    private let message: (CrossLinkIssue) -> Void
    private let clock: () -> Int64
    private let authorityId: String
    private let authority: Bool
    private let humans: [String]
    private let remotes: [String]
    private let seatOf: [String: Int]
    private var subscriptions: [MPSubscription] = []
    private var gate = MPSequenceGate()
    private var buffered: [String: MPWire] = [:]
    private var revision: Int64 = 0
    /// Every human's shared "slow motion for my return" choice (uid → slow); the authority drives the shared clock from it.
    private var receptionOptions: [String: Bool] = [:]
    private var loaded = false
    private var ended = false
    private var busy = false
    private var pending: MPWire?
    private var lastCheckpoint: Int64 = 0
    private var lastRally = -1
    private var lastStage = -1
    private var lastPhase: CrossRallyPhase?
    private var wasReady = false
    /// A strike the engine already held when this link opened was this phone's to publish before.
    private var published: Int
    private var latestLocalSequence: Int64 = 0
    private var latestLocalAt: Int64 = 0
    private var saving = false
    private var finalCheckpointQueued = false
    private var finalCheckpointSaved = false
    private var lastSaveAttempt: Int64 = 0
    var networkAvailable = true
    var active = false
    /// Play may run: loaded, on screen, online and every human of the fixture connected.
    var ready: Bool { loaded && active && networkAvailable && humans.allSatisfy { session.connected($0) } }
    private var playing: Bool { session.matches[record.id]?.phase == .playing }
    var isAuthority: Bool { authority }

    init(repo: any MPRepository, session: MPSession, record: MPFixture, match: CrossMatch, nextSequence: @escaping () -> Int64,
         message: @escaping (CrossLinkIssue) -> Void, clock: @escaping () -> Int64 = { MPClock.now }) {
        self.repo = repo; self.session = session; self.record = record; self.match = match
        self.nextSequence = nextSequence; self.message = message; self.clock = clock
        let authorityId = session.authority(record)
        self.authorityId = authorityId
        authority = authorityId == repo.uid
        let humanIds = record.players.filter { session.participants[$0]?.bot == nil }
        humans = humanIds
        remotes = humanIds.filter { $0 != repo.uid }
        var seats: [String: Int] = [:]
        for (i, id) in record.players.enumerated() where seats[id] == nil { seats[id] = i }
        seatOf = seats
        published = match.localStrikeID
        match.authoritative = authorityId == repo.uid
    }
    func open() {
        subscriptions.append(repo.receptionPreferences(Set(humans), { [weak self] values in self?.receptionOptions = values; self?.applyReception() },
                                                       { [weak self] _ in self?.message(.reception) }))
        subscriptions.append(repo.connection { [weak self] connected in self?.networkAvailable = connected })
        subscriptions.append(repo.watchLive(record.id, actions: false, { [weak self] w in self?.received(w) },
                                            { [weak self] error in self?.message(.failed(error.localizedDescription)) }))
        if authority && !remotes.isEmpty {
            subscriptions.append(repo.watchLive(record.id, actions: true, { [weak self] w in self?.receivedAction(w) },
                                                { [weak self] error in self?.message(.failed(error.localizedDescription)) }))
        }
    }
    private func received(_ w: MPWire) {
        if ended { return }
        if w.isEmpty {
            if authority && !loaded { loaded = true; checkpoint(); drainBuffered() }
            return
        }
        let seq = MPCodec.number(w, "revision")
        if seq <= revision { return }
        revision = seq
        if CrossWire.number(w, "protocol", 1) != Int64(CrossLink.protocolVersion) { message(.version); return }
        // Only the fixture's authority writes checkpoints.
        let writer = CrossWire.text(w, "authority")
        if !writer.isEmpty && writer != authorityId { return }
        let seen = MPCodec.map(w["seen"]).mapValues { ($0 as? NSNumber)?.int64Value ?? 0 }
        if authority {
            if loaded { return }
            // Restored once and silently (no contact is replayed); an engine already ahead of it (reopened before its last write
            // landed) keeps its own state, so scores never go back.
            do {
                let state = try CrossMatchState.read(MPCodec.map(w["engine"]))
                if ahead(state) { try match.restoreState(state) }
            } catch { message(.failed(error.localizedDescription)) }
            gate.restore(seen)
        } else {
            // Keep an immediate local hit until the authority acknowledges it.
            if latestLocalSequence > (seen[repo.uid] ?? 0) && clock() - latestLocalAt < CrossLink.ackWait { return }
            do {
                let state = try CrossMatchState.read(MPCodec.map(w["engine"]))
                try match.restoreState(state, preserveInput: loaded)
            } catch {
                message(.failed(error.localizedDescription))
                if !loaded { return }
            }
        }
        loaded = true
        drainBuffered()
    }
    private func receivedAction(_ w: MPWire) {
        let sender = CrossWire.text(w, "sender")
        if ended || !remotes.contains(sender) { return }
        if loaded { remoteAction(w) }
        else if buffered.count < CrossLink.bufferLimit { buffered["\(sender)/\(CrossWire.number(w, "sequence"))"] = w }
    }
    /// Strikes in play order: one human's return may answer another's, whatever their own sequence numbers.
    private func drainBuffered() {
        let work = buffered.values.sorted { MPRepositoryOrder.before($0, $1) }
        buffered.removeAll()
        work.forEach { remoteAction($0) }
    }
    /// Authority: another human's completed strike, for that human's own seat only.
    private func remoteAction(_ w: MPWire) {
        let sender = CrossWire.text(w, "sender")
        guard let seat = seatOf[sender] else { return }
        if !gate.accept(sender, CrossWire.number(w, "sequence")) { return }
        if CrossWire.number(w, "protocol", 1) != Int64(CrossLink.protocolVersion) { message(.version) }
        else if CrossWire.number(w, "seat", -1) == Int64(seat) {
            let strike = CrossStrike.read(MPCodec.map(w["strike"]))
            match.applyRemoteStrike(stage: CrossWire.int(w, "stage", 0), fixtureSeat: seat, strike,
                                    rallyId: CrossWire.int(w, "rallyId", -1), hitIndex: CrossWire.int(w, "hitIndex", -1))
        }
        checkpoint() // Acknowledges stale or invalid actions without applying them again.
    }
    /// Authority: the slow-motion assistance runs only once every human's choice is known; each seat follows its own player's.
    private func applyReception() {
        if !authority { return }
        engine.reception.enabled = humans.allSatisfy { receptionOptions[$0] != nil }
        for (uid, fixture) in seatOf { if let seat = match.stageSeat(fixture) { engine.reception.slow[seat] = receptionOptions[uid] ?? true } }
    }
    func update(_ s: MPSession) {
        session = s
        if !playing { pending = nil }
    }
    /// Once per frame with the drained match events.
    func frame(_ events: [CrossEvent]) {
        if ended || !loaded || !playing { return }
        applyReception()
        let now = clock()
        if !authority {
            // Each committed strike goes out once. One repeated after the authority refused it is a new strike.
            if let strike = match.localStrike(), match.localStrikeID != published {
                published = match.localStrikeID
                publish(strike, now: now)
            }
            return
        }
        let referee = engine.referee
        let live = ready
        // A pause or resume is checkpointed too: a reopened phone resumes from exactly where play stopped.
        if events.contains(where: { checkpointed($0) }) || referee.rallyId != lastRally || referee.phase != lastPhase || match.stage != lastStage ||
            live != wasReady || (live && now - lastCheckpoint >= (engine.reception.enabled && !engine.ballState.stopped ? 100 : CrossLink.period)) { checkpoint() }
        lastRally = referee.rallyId; lastPhase = referee.phase; lastStage = match.stage; wasReady = live
        if !match.finished { return }
        if !finalCheckpointQueued { checkpoint() }
        // Rules stop live writes once the result is final: the last recovery checkpoint is committed first.
        if finalCheckpointSaved && !busy && pending == nil && !saving && now - lastSaveAttempt > CrossLink.retry {
            saving = true; lastSaveAttempt = now
            let scores = match.scores(), order = match.placementIds(record.players)
            let actor = repo.uid, id = record.id, kind = session.kind, code = session.code
            // Held strongly, like the Kotlin callback: the result is saved even if the owner releases the link meanwhile.
            Task {
                do { _ = try await self.repo.mutate(kind, code) { try MPRules.finish($0, match: id, actor: actor, scores: scores, placement: order) } }
                catch { self.saving = false; self.message(.failed(error.localizedDescription)) }
            }
        }
    }
    /// A remote seat's strike was checkpointed when it was applied.
    private func checkpointed(_ e: CrossEvent) -> Bool {
        switch e {
        case .rally, .eliminated, .stage: return true
        case let .contact(seat, _, _, _): return engine.kind(seat) != .remote
        case let .served(seat): return engine.kind(seat) != .remote
        default: return false
        }
    }
    private func publish(_ strike: CrossStrike, now: Int64) {
        let seq = nextSequence()
        latestLocalSequence = seq; latestLocalAt = now
        // "seat" is this player's roster seat (the rules check it); the strike carries its stage seat and "stage" the table.
        guard let own = match.localSeat else { return }
        let body: MPWire = ["protocol": CrossLink.protocolVersion, "kind": session.kind.path, "code": session.code, "seat": own,
                            "stage": match.stage, "rallyId": strike.rallyId, "hitIndex": strike.hitIndex, "clientAt": now, "strike": strike.wire()]
        let id = record.id
        // Held strongly, like the Kotlin callback: a strike published just before close() still goes out.
        Task {
            do { try await self.repo.action(id, seq, body) } catch { self.message(.interrupted) }
        }
    }
    func checkpoint() {
        if !authority || !loaded || ended || saving || !playing { return }
        if match.finished {
            if finalCheckpointQueued { return }
            finalCheckpointQueued = true
        }
        lastCheckpoint = clock()
        let seen: MPWire = gate.snapshot().mapValues { $0 as Any }
        let body: MPWire = ["protocol": CrossLink.protocolVersion, "kind": session.kind.path, "code": session.code,
                            "engine": match.exportState().wire(), "seen": seen, "clientAt": lastCheckpoint]
        if busy { pending = body; return }
        write(body)
    }
    private func write(_ body: MPWire) {
        busy = true
        let id = record.id
        let final = CrossWire.flag(MPCodec.map(MPCodec.map(body["engine"])["match"]), "finished")
        // Held strongly, like the Kotlin callback: close() writes a last checkpoint and the owner releases the link at once.
        Task {
            do {
                try await self.repo.checkpoint(id, body)
                if final { self.finalCheckpointSaved = true }
            } catch {
                if final { self.finalCheckpointQueued = false }
                self.message(.failed(error.localizedDescription))
            }
            self.busy = false
            let next = self.pending
            self.pending = nil
            if let next, !self.saving, self.playing { self.write(next) }
        }
    }
    /// A stored checkpoint ahead of this (reopened) authority: a later stage, or the same stage further on.
    private func ahead(_ s: CrossMatchState) -> Bool {
        if s.stage > match.stage { return true }
        guard s.stage == match.stage else { return false }
        if s.finished && !match.finished { return true }
        let theirs = s.engine.referee, ours = engine.referee.exportState()
        let left = (theirs.rallyId, theirs.ralliesPlayed, theirs.hits, theirs.phase.ordinal)
        let right = (ours.rallyId, ours.ralliesPlayed, ours.hits, ours.phase.ordinal)
        return left > right
    }
    func close() {
        checkpoint()
        active = false; ended = true
        subscriptions.forEach { $0.close() }
        subscriptions = []
    }
    /// Engine seats in fixture order: this phone's player local, the other humans remote, house players house.
    static func seats(_ session: MPSession, _ record: MPFixture, uid: String) -> [CrossSeat] {
        record.players.enumerated().map { item -> CrossSeat in
            let i = item.offset, id = item.element
            let p = session.participants[id]
            let kind: CrossSeatKind = p?.bot != nil ? .house : (id == uid ? .local : .remote)
            let ownCharacter = p?.identity.characterId ?? ""
            let character = ownCharacter.trimmingCharacters(in: .whitespaces).isEmpty ? (p?.bot?.characterId ?? "") : ownCharacter
            return CrossSeat(index: i, kind: kind, id: id, name: p?.identity.name ?? id, bot: p?.bot, characterId: character, avatar: p?.identity.avatar ?? 0)
        }
    }
    /// Online fixtures open with seat `seed mod n` (CROSS_DESIGN §3).
    static func firstServer(_ record: MPFixture) -> Int { Int(crossMod(record.seed, Int64(max(1, record.players.count)))) }
    /// Final order: score, then fewer faults, then more points won, then seat order.
    static func placement(_ players: [String], _ state: CrossRefereeState) -> [String] {
        players.indices.sorted { a, b in
            if state.scores[a] != state.scores[b] { return state.scores[a] > state.scores[b] }
            if state.faults[a] != state.faults[b] { return state.faults[a] < state.faults[b] }
            if state.pointsWon[a] != state.pointsWon[b] { return state.pointsWon[a] > state.pointsWon[b] }
            return a < b
        }.map { players[$0] }
    }
}
