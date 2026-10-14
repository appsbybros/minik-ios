import Foundation

@MainActor final class MPMatchLink {
    let engine: MPEngine; private let repo: any MPRepository, record: MPFixture, preferences: MPPreferences
    private var session: MPSession, subscriptions: [MPSubscription] = []
    private let authority: Bool, humans: [String], remote: String?, message: (Error) -> Void
    private var seen: [String: Int64] = [:], revision: Int64 = 0, latestLocalSequence: Int64 = 0, latestLocalAt: Int64 = 0
    private var loaded = false, ended = false, busy = false, saving = false, finalQueued = false, finalSaved = false
    private var pending: MPWire?, buffered: [MPWire] = [], lastCheckpoint: Int64 = 0, lastSave: Int64 = 0
    private var lastRallies = -1, lastAwaiting = false
    /// Android MatchLink.receptionOptions: each human's published slow-motion choice (2026-10).
    private var receptionOptions: [String: Bool] = [:]
    var active = false, networkAvailable = true
    var ready: Bool { loaded && active && networkAvailable && humans.allSatisfy(session.connected) }
    /// The child plays a house player: no other device follows this match.
    var housePlayersOnly: Bool { remote == nil }
    init(repo: any MPRepository, session: MPSession, record: MPFixture, engine: MPEngine, preferences: MPPreferences, message: @escaping (Error) -> Void) {
        self.repo = repo; self.session = session; self.record = record; self.engine = engine; self.preferences = preferences; self.message = message
        authority = session.authority(record) == repo.uid
        humans = [record.a, record.b].filter { session.participants[$0]?.bot == nil }; remote = humans.first { $0 != repo.uid }
        engine.authoritative = authority
    }
    func open() {
        subscriptions.append(repo.receptionPreferences(Set(humans), { [weak self] values in self?.receptionOptions = values; self?.applyReception() }, message))
        subscriptions.append(repo.connection { [weak self] in self?.networkAvailable = $0 })
        subscriptions.append(repo.watchLive(record.id, actions: false, { [weak self] w in self?.received(w) }, message))
        if authority && remote != nil {
            subscriptions.append(repo.watchLive(record.id, actions: true, { [weak self] w in
                guard let self, !self.ended, w["sender"] as? String == self.remote else { return }
                if !self.loaded { if self.buffered.count < 32 { self.buffered.append(w) } } else { self.remoteAction(w) }
            }, message))
        }
    }
    private func received(_ w: MPWire) {
        guard !ended else { return }
        if w.isEmpty { if authority && !loaded { loaded = true; checkpoint(); drain() }; return }
        let seq = MPCodec.number(w, "revision"); guard seq > revision else { return }; revision = seq
        guard MPCodec.number(w, "protocol") == 1 else { message(MPError.configuration); return }
        let acknowledgments = MPCodec.map(w["seen"]).mapValues { ($0 as? NSNumber)?.int64Value ?? 0 }
        do {
            if authority { if !loaded { engine.restore(try MPCodec.decode(MPState.self, w["engine"])); seen = acknowledgments } }
            else if !(latestLocalSequence > (acknowledgments[repo.uid] ?? 0) && MPClock.now - latestLocalAt < 850) {
                engine.restore(try MPCodec.decode(MPState.self, w["engine"]).reflected, preserveInput: loaded)
            }
            loaded = true; drain()
        } catch { message(error) }
    }
    private func drain() { let work = buffered.sorted { MPCodec.number($0, "sequence") < MPCodec.number($1, "sequence") }; buffered = []; work.forEach(remoteAction) }
    private func remoteAction(_ w: MPWire) {
        guard let remote else { return }; let sequence = MPCodec.number(w, "sequence")
        guard sequence > 0, sequence > (seen[remote] ?? 0) else { return }; seen[remote] = sequence
        if let flight = try? MPCodec.decode(MPFlight.self, w["flight"]) { engine.remoteStrike(flight.reflected, rallies: Int(MPCodec.number(w, "rallies")), hit: Int(MPCodec.number(w, "hit"))) }
        checkpoint()
    }
    /// Android MatchLink.applyReception: the authority shares one clock. Slow motion runs only when every human's
    /// choice is known; each receiver's own choice decides their return.
    private func applyReception() {
        guard authority else { return }
        engine.reception.enabled = humans.allSatisfy { receptionOptions[$0] != nil }
        engine.reception.slow[0] = receptionOptions[repo.uid] ?? true
        engine.reception.slow[1] = remote.flatMap { receptionOptions[$0] } ?? true
    }
    func update(_ session: MPSession) { self.session = session; if session.matches[record.id]?.phase != .playing { pending = nil } }
    func frame(_ events: [MPEvent]) {
        guard !ended, loaded, session.matches[record.id]?.phase == .playing else { return }
        applyReception()
        let now = MPClock.now
        if !authority && events.contains(where: { if case .contact(.child, _, _, _) = $0 { return true }; return false }), let flight = engine.flight {
            let sequence = preferences.sequence(record.id); latestLocalSequence = sequence; latestLocalAt = now
            do {
                let w: MPWire = ["protocol": 1, "kind": session.kind.path, "code": session.code, "rallies": engine.score.rallies, "hit": engine.rally, "clientAt": now, "flight": try MPCodec.encode(flight)]
                Task { do { try await repo.action(record.id, sequence, w) } catch { message(error) } }
            } catch { message(error) }
        }
        // A remote human's contact is already acknowledged by remoteAction's checkpoint; only local contacts trigger one.
        let contact = events.contains {
            switch $0 {
            case .contact(let side, _, _, _): return !engine.networked || side == .child
            case .point: return true
            default: return false
            }
        }
        // While slow motion may be active the peer follows the shared clock closely (Android: every 100 ms).
        let interval: Int64 = engine.reception.enabled && engine.flight != nil ? 100 : 2000
        if authority && (contact || engine.score.rallies != lastRallies || engine.awaitingServe != lastAwaiting || ready && now - lastCheckpoint >= interval) { checkpoint() }
        lastRallies = engine.score.rallies; lastAwaiting = engine.awaitingServe
        if authority && engine.score.winner != nil && !finalQueued { checkpoint() }
        if authority && engine.score.winner != nil && finalSaved && !busy && pending == nil && !saving && now - lastSave > 1500 {
            saving = true; lastSave = now
            let a = record.a == repo.uid ? engine.score.child : engine.score.minik, b = record.a == repo.uid ? engine.score.minik : engine.score.child
            let actor = repo.uid, id = record.id
            Task { do { _ = try await repo.mutate(session.kind, session.code) { try MPRules.finish($0, match: id, actor: actor, a: a, b: b) } } catch { saving = false; message(error) } }
        }
    }
    func checkpoint() {
        guard authority, loaded, !ended, !saving, session.matches[record.id]?.phase == .playing else { return }
        if engine.score.winner != nil { guard !finalQueued else { return }; finalQueued = true }
        lastCheckpoint = MPClock.now
        do {
            let w: MPWire = ["protocol": 1, "kind": session.kind.path, "code": session.code, "engine": try MPCodec.encode(engine.snapshot()), "seen": seen, "clientAt": lastCheckpoint]
            if busy { pending = w } else { write(w) }
        } catch { message(error) }
    }
    private func write(_ w: MPWire) {
        busy = true
        Task {
            let final = MPCodec.map(MPCodec.map(w["engine"])["score"])["winner"] as? String != nil
            do { try await repo.checkpoint(record.id, w); if final { finalSaved = true } }
            catch { if final { finalQueued = false }; message(error) }
            busy = false; let next = pending; pending = nil
            if let next, !saving, session.matches[record.id]?.phase == .playing { write(next) }
        }
    }
    func close() { checkpoint(); active = false; ended = true; subscriptions.forEach { $0.close() }; subscriptions = [] }
}
