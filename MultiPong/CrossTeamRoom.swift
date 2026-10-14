import Foundation
#if MINIK_PING_PONG && canImport(FirebaseDatabase) && canImport(FirebaseAuth)
import FirebaseCore
import FirebaseAuth
import FirebaseDatabase
#endif

/// JSON text inside the team protocol (Android `JsonWire`): the snapshot and every input body are JSON strings.
enum CrossJSON {
    static func encode(_ w: MPWire) -> String {
        guard JSONSerialization.isValidJSONObject(w), let data = try? JSONSerialization.data(withJSONObject: w) else { return "{}" }
        return String(data: data, encoding: .utf8) ?? "{}"
    }
    static func decode(_ text: String) -> MPWire? {
        guard let data = text.data(using: .utf8), let value = try? JSONSerialization.jsonObject(with: data) else { return nil }
        return value as? MPWire
    }
}

/// Android cross/CrossTeamRoom.kt (MinikCrossPong 5c1aa4d): live doubles in a separate Firebase root (`minikCrossTeams`, protocol
/// `cross-teams-v1`, flexible lobby `cross-teams-v1-lobby-v2`). Old one-against-one rooms and their rules are untouched. One fixed
/// host simulates the court, acknowledges sequenced human input and pauses while a selected player is away; friends rejoin their
/// own place. Host migration is not implemented. Without this app's Firebase registration `make` returns nil.
@MainActor final class CrossTeamRoom {
    static let protocolName = "cross-teams-v1"
    static let flexibleProtocol = protocolName + "-lobby-v2"
    /// Android `failed` messages that the screen explains (compared by text, as on Android).
    enum Message {
        static let code = "Check the six-character room code."
        static let notFound = "Room not found."
        static let newer = "This room needs a newer app version."
        static let started = "This match has already started."
        static let full = "No invited place is available."
        static let restore = "The shared match could not be restored. Reopen this room."
        static let interrupted = "Connection interrupted. Reopen the room to continue."
    }
    private let changed: () -> Void
    private let failed: (String) -> Void
    private let preferences: MPPreferences
    private let identity: CrossTeamIdentity
    private(set) var code = ""
    private(set) var uid = ""
    private(set) var meta: MPWire = [:]
    private(set) var members: [String: Int] = [:]
    private(set) var lineup: CrossLineup?
    private var rawLineup: Any?
    private var lineupBusy = false
    private(set) var ready: Set<String> = []
    private(set) var profiles: [String: CrossTeamIdentity] = [:]
    private var profilesLoaded = false
    private var identityPublished = false, identityPublishing = false
    private(set) var presence: [String: Int64] = [:]
    private(set) var phase = ""
    private(set) var game: CrossEngine?
    private var receptionOptions: [String: Bool] = [:]
    private var receptionWatching: Set<String> = []
    private var consumed: [String] = []
    private var loaded = false
    private var gate = MPSequenceGate()
    private var publishedStrike = 0
    private var pendingSequence: Int64 = 0, pendingAt: Int64 = 0
    private var checkpointBody: String?
    private var connected = false, active = true, closed = false, publishing = false
    private var lastTick: Int64 = 0, lastPublish: Int64 = 0, lastPresence: Int64 = 0, offset: Int64 = 0
    private var sequence: Int64
    private var pump: Timer?
    #if MINIK_PING_PONG && canImport(FirebaseDatabase) && canImport(FirebaseAuth)
    private let auth: Auth
    private let db: Database
    private var room: DatabaseReference?
    private var watches: [(DatabaseQuery, UInt)] = []
    private var commands: [String: (DatabaseQuery, UInt)] = [:]
    #endif

    /// Android `CrossTeamRoom(context, ...)`: nil when Firebase is not set up for this app (online rooms are not available).
    static func make(preferences: MPPreferences, hebrew: Bool, changed: @escaping () -> Void, failed: @escaping (String) -> Void) -> CrossTeamRoom? {
        #if MINIK_PING_PONG && canImport(FirebaseDatabase) && canImport(FirebaseAuth)
        guard !MPController.offlineSmoke, MPFirebaseRepository.configured() != nil, let app = FirebaseApp.app(name: MPFirebaseRepository.appName) else { return nil }
        return CrossTeamRoom(app: app, preferences: preferences, hebrew: hebrew, changed: changed, failed: failed)
        #else
        return nil
        #endif
    }
    #if MINIK_PING_PONG && canImport(FirebaseDatabase) && canImport(FirebaseAuth)
    private init(app: FirebaseApp, preferences: MPPreferences, hebrew: Bool, changed: @escaping () -> Void, failed: @escaping (String) -> Void) {
        self.changed = changed; self.failed = failed; self.preferences = preferences
        identity = CrossTeamIdentity.own(preferences.identity, hebrew: hebrew)
        sequence = preferences.teamSequence
        auth = Auth.auth(app: app)
        db = Database.database(app: app, url: "https://minikswish-default-rtdb.europe-west1.firebasedatabase.app/")
    }
    #else
    private init(preferences: MPPreferences, hebrew: Bool, changed: @escaping () -> Void, failed: @escaping (String) -> Void) {
        self.changed = changed; self.failed = failed; self.preferences = preferences
        identity = CrossTeamIdentity.own(preferences.identity, hebrew: hebrew)
        sequence = preferences.teamSequence
    }
    #endif

    // ---- state -------------------------------------------------------------------------------------------------------------
    var flexible: Bool { CrossWire.text(meta, "protocol").hasSuffix("-lobby-v2") }
    var capacity: Int { CrossWire.text(meta, "mode") == "THREE" ? 3 : 4 }
    /// uid → playing position: the lineup's selected friends, or (old rooms) the claimed connection places.
    var seats: [String: Int] { flexible ? (lineup?.humans ?? [:]) : members }
    var selectionBusy: Bool { lineupBusy }
    func occupied(_ seat: Int) -> Bool {
        guard flexible else { return true }
        guard let slots = lineup?.slots, slots.indices.contains(seat) else { return false }
        return slots[seat] != CrossLineup.empty
    }
    func playerAt(_ seat: Int) -> String? { seats.first { $0.value == seat }?.key }
    func nameAt(_ seat: Int, hebrew: Bool) -> String {
        if let player = playerAt(seat), let name = profiles[player]?.name { return name }
        return (MPRoster.find(characterAt(seat)) ?? MPRoster.all[0]).name(hebrew: hebrew)
    }
    func partnerSeat(_ seat: Int) -> Int? { let p = (seat + 2) % 4; return p < capacity ? p : nil }
    func characterAt(_ seat: Int) -> String {
        if let player = playerAt(seat), let character = profiles[player]?.character { return character }
        if flexible {
            if let slots = lineup?.slots, slots.indices.contains(seat), slots[seat].hasPrefix("b:") { return String(slots[seat].dropFirst(2)) }
            return "minik"
        }
        if !humanSeats.contains(seat), let partner = partnerSeat(seat), let player = playerAt(partner), let mate = profiles[player]?.teammate { return mate }
        return CrossWire.text(MPCodec.map(meta["roster"]), String(seat))
    }
    func present(_ player: String) -> Bool { (presence[player] ?? 0) > now() - 9000 }
    var host: Bool { !uid.isEmpty && CrossWire.text(meta, "host") == uid }
    var localSeat: Int { seats[uid] ?? -1 }
    var humanSeats: Set<Int> {
        if flexible { return Set(seats.values) }
        return Set(MPCodec.map(meta["humans"]).compactMap { ($0.value as? Bool) == true ? Int($0.key) : nil })
    }
    var everyoneHere: Bool {
        connected && (!flexible || lineup?.complete == true) && !humanSeats.isEmpty && Set(seats.values) == humanSeats &&
            seats.keys.allSatisfy { members[$0] != nil && ready.contains($0) && (phase != "lobby" || profiles[$0] != nil) && present($0) }
    }
    var canStart: Bool {
        guard host, phase == "lobby", localSeat >= 0, everyoneHere, !lineupBusy else { return false }
        guard flexible else { return true }
        let seen = lineup?.seen ?? []
        return members.keys.filter { profiles[$0] != nil && present($0) }.allSatisfy { seen.contains($0) }
    }
    var waiting: Bool { phase == "playing" && (!everyoneHere || !active) }
    private func now() -> Int64 { MPClock.now + offset }
    private func uptime() -> Int64 { Int64(ProcessInfo.processInfo.systemUptime * 1000) }

    // ---- actions -------------------------------------------------------------------------------------------------------------
    func connect(_ done: @escaping () -> Void) {
        #if MINIK_PING_PONG && canImport(FirebaseDatabase) && canImport(FirebaseAuth)
        let signIn = auth
        Task { @MainActor [weak self] in
            do {
                let user: String
                if let current = signIn.currentUser { user = current.uid } else { user = try await signIn.signInAnonymously().user.uid }
                guard let self, !self.closed else { return }
                self.uid = user
                self.watch(self.db.reference(withPath: ".info/serverTimeOffset")) { [weak self] s in self?.offset = (s.value as? NSNumber)?.int64Value ?? 0 }
                self.watch(self.db.reference(withPath: ".info/connected")) { [weak self] s in
                    guard let self else { return }
                    self.connected = (s.value as? Bool) == true
                    if self.connected { self.publishIdentity(); self.publishPresence() }
                    self.changed()
                }
                self.startPump()
                done()
            } catch { self?.report(error) }
        }
        #endif
    }
    private func newCode() -> String {
        let letters = Array("ABCDEFGHJKLMNPQRSTUVWXYZ23456789")
        return String((0..<6).map { _ in letters[Int.random(in: 0..<letters.count)] })
    }
    /// An older fixed-place room (no lineup): the host's chosen characters and invited human places.
    func create(mode: String, roster: [String], humans: Set<Int>) {
        #if MINIK_PING_PONG && canImport(FirebaseDatabase) && canImport(FirebaseAuth)
        guard room == nil, ["THREE", "FOUR"].contains(mode), mode == "FOUR" || !humans.contains(3), humans.contains(0), (2...4).contains(humans.count),
              humans.allSatisfy({ (0...3).contains($0) }), roster.count == 4, roster.allSatisfy({ MPRoster.find($0) != nil }) else { return }
        let value = newCode()
        var places: [String: Any] = [:]
        for h in humans { places[String(h)] = true }
        let initial: [String: Any] = ["meta": ["host": uid, "protocol": CrossTeamRoom.protocolName, "mode": mode, "roster": roster, "humans": places,
                                               "createdAt": ServerValue.timestamp()] as [String: Any],
                                      "phase": "lobby", "seats": ["0": uid], "ready": [uid: false]]
        write(db.reference(withPath: "minikCrossTeams/rooms/" + value), initial) { [weak self] in self?.attach(value) }
        #endif
    }
    /// A flexible room (5c1aa4d): the host arranges every place; friends keep their own identity.
    func createFlexible(mode: String) {
        #if MINIK_PING_PONG && canImport(FirebaseDatabase) && canImport(FirebaseAuth)
        guard room == nil else { return }
        let count = mode == "THREE" ? 3 : 4
        let value = newCode()
        var places: [String: Any] = [:]
        for h in 0..<count { places[String(h)] = true }
        let initial: [String: Any] = ["meta": ["host": uid, "protocol": CrossTeamRoom.flexibleProtocol, "mode": mode, "roster": ["miniko", "minik", "mia", "june"],
                                               "humans": places, "createdAt": ServerValue.timestamp()] as [String: Any],
                                      "phase": "lobby", "seats": ["0": uid], "ready": [uid: false], "lineup": CrossLineup.initial(uid, count: count).wire()]
        write(db.reference(withPath: "minikCrossTeams/rooms/" + value), initial) { [weak self] in self?.attach(value) }
        #endif
    }
    /// Host only, in the lobby: put a connected friend ("u:"), a house player ("b:") or nobody ("empty") on `seat`.
    func chooseSlot(_ seat: Int, _ value: String) {
        guard host, flexible, phase == "lobby", !lineupBusy, (0..<capacity).contains(seat) else { return }
        if value.hasPrefix("u:") {
            let user = String(value.dropFirst(2))
            if members[user] == nil || profiles[user] == nil || !present(user) { return }
        }
        if value != CrossLineup.empty && !value.hasPrefix("u:") && (!value.hasPrefix("b:") || MPRoster.find(String(value.dropFirst(2))) == nil) { return }
        changeLineup { $0.choose(seat, value) }
    }
    /// Older rooms: the guest's chosen house teammate.
    func choosePartner(_ character: String) {
        guard let partner = partnerSeat(localSeat) else { return }
        if flexible { chooseSlot(partner, "b:" + character); return }
        #if MINIK_PING_PONG && canImport(FirebaseDatabase) && canImport(FirebaseAuth)
        guard phase == "lobby", !humanSeats.contains(partner), MPRoster.find(character) != nil, var own = profiles[uid] else { return }
        own.teammate = character
        if let target = room { write(target.child("profiles").child(uid), own.wire()) }
        #endif
    }
    private func changeLineup(_ change: @escaping (CrossLineup) -> CrossLineup) {
        #if MINIK_PING_PONG && canImport(FirebaseDatabase) && canImport(FirebaseAuth)
        guard let target = room, !lineupBusy else { return }
        lineupBusy = true; changed()
        let count = capacity
        target.child("lineup").runTransactionBlock({ data in
            guard let current = CrossLineup.read(data.value, count: count) else { return TransactionResult.abort() }
            let next = change(current)
            if next == current { return TransactionResult.abort() }
            data.value = next.wire()
            return TransactionResult.success(withValue: data)
        }, andCompletionBlock: { [weak self] error, _, _ in
            MainActor.assumeIsolated {
                guard let self else { return }
                self.lineupBusy = false
                if let error { self.report(error) }
                self.changed()
            }
        }, withLocalEvents: false)
        #endif
    }
    private func reconcileLineup() {
        guard host, flexible, phase == "lobby", !lineupBusy, profilesLoaded, let current = lineup else { return }
        let arrivals = members.sorted { $0.value < $1.value }.map { $0.key }.filter { profiles[$0] != nil && present($0) }
        let order = [0, 2, 1, 3].filter { $0 < capacity }
        let known = Set(members.keys)
        if current.reconcile(known, arrivals: arrivals, order: order) != current { changeLineup { $0.reconcile(known, arrivals: arrivals, order: order) } }
    }
    func join(_ value: String, preferredSeat: Int? = nil) {
        #if MINIK_PING_PONG && canImport(FirebaseDatabase) && canImport(FirebaseAuth)
        guard room == nil else { return }
        let safe = value.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        guard safe.range(of: "^[A-Z2-9]{6}$", options: .regularExpression) != nil else { failed(Message.code); return }
        let target = db.reference(withPath: "minikCrossTeams/rooms/" + safe)
        let me = uid
        Task { @MainActor [weak self] in
            do {
                let snapshot = try await target.getData()
                guard let self else { return }
                guard snapshot.exists() else { self.failed(Message.notFound); return }
                let proto = snapshot.childSnapshot(forPath: "meta/protocol").value as? String
                guard proto == CrossTeamRoom.protocolName || proto == CrossTeamRoom.flexibleProtocol else { self.failed(Message.newer); return }
                let seatsNode = snapshot.childSnapshot(forPath: "seats").children.allObjects.compactMap { $0 as? DataSnapshot }
                if seatsNode.contains(where: { ($0.value as? String) == me }) { self.attach(safe); return }
                guard (snapshot.childSnapshot(forPath: "phase").value as? String) == "lobby" else { self.failed(Message.started); return }
                let invited = snapshot.childSnapshot(forPath: "meta/humans").children.allObjects.compactMap { ($0 as? DataSnapshot).flatMap { Int($0.key) } }
                let free = invited.filter { !snapshot.childSnapshot(forPath: "seats/\($0)").exists() }
                let choices = preferredSeat.map { free.contains($0) ? [$0] : [] } ?? [2, 1, 3].filter { free.contains($0) }
                self.claim(target, safe, choices, 0)
            } catch { self?.report(error) }
        }
        #endif
    }
    #if MINIK_PING_PONG && canImport(FirebaseDatabase) && canImport(FirebaseAuth)
    private func claim(_ target: DatabaseReference, _ safe: String, _ choices: [Int], _ index: Int) {
        guard index < choices.count else { failed(Message.full); return }
        let me = uid
        target.child("seats").child(String(choices[index])).runTransactionBlock({ data in
            if let existing = data.value as? String, existing != me { return TransactionResult.abort() }
            data.value = me
            return TransactionResult.success(withValue: data)
        }, andCompletionBlock: { [weak self] error, committed, _ in
            MainActor.assumeIsolated {
                guard let self else { return }
                if let error { self.report(error) } else if !committed { self.claim(target, safe, choices, index + 1) } else { self.attach(safe) }
            }
        }, withLocalEvents: false)
    }
    #endif
    private func attach(_ value: String) {
        #if MINIK_PING_PONG && canImport(FirebaseDatabase) && canImport(FirebaseAuth)
        if closed { return }
        code = value
        let target = db.reference(withPath: "minikCrossTeams/rooms/" + value)
        room = target
        preferences.teamRoom = value
        watch(target.child("meta")) { [weak self] s in
            guard let self else { return }
            self.meta = MPCodec.map(s.value); self.lineup = CrossLineup.read(self.rawLineup, count: self.capacity); self.restoreIfNeeded(); self.changed()
        }
        watch(target.child("profiles")) { [weak self] s in
            guard let self else { return }
            self.profilesLoaded = true
            var found: [String: CrossTeamIdentity] = [:]
            for case let child as DataSnapshot in s.children.allObjects { if let p = CrossTeamIdentity.from(child.value) { found[child.key] = p } }
            self.profiles = found; self.restoreIfNeeded(); self.changed()
        }
        watch(target.child("seats")) { [weak self] s in
            guard let self else { return }
            var found: [String: Int] = [:]
            for case let child as DataSnapshot in s.children.allObjects { if let user = child.value as? String, let seat = Int(child.key) { found[user] = seat } }
            self.members = found; self.publishIdentity(); self.restoreIfNeeded(); self.listenInputs(); self.changed()
        }
        watch(target.child("lineup")) { [weak self] s in
            guard let self else { return }
            self.rawLineup = s.value; self.lineup = CrossLineup.read(s.value, count: self.capacity); self.restoreIfNeeded(); self.listenInputs(); self.changed()
        }
        watch(target.child("ready")) { [weak self] s in
            guard let self else { return }
            self.ready = Set(s.children.allObjects.compactMap { ($0 as? DataSnapshot).flatMap { ($0.value as? Bool) == true ? $0.key : nil } }); self.changed()
        }
        watch(target.child("presence")) { [weak self] s in
            guard let self else { return }
            var found: [String: Int64] = [:]
            for case let child as DataSnapshot in s.children.allObjects { found[child.key] = (child.value as? NSNumber)?.int64Value ?? 0 }
            self.presence = found; self.changed()
        }
        watch(target.child("phase")) { [weak self] s in
            guard let self else { return }
            self.phase = s.value as? String ?? "closed"; self.publishIdentity(); self.changed()
        }
        watch(target.child("snapshot")) { [weak self] s in
            guard let self else { return }
            self.checkpointBody = s.childSnapshot(forPath: "body").value as? String; self.restoreIfNeeded()
        }
        publishPresence(); changed()
        #endif
    }
    private func makeEngine() -> CrossEngine {
        let count = capacity
        let humans = humanSeats, mine = localSeat
        let players = (0..<count).map { seat -> CrossSeat in
            let id = characterAt(seat)
            let character = MPRoster.find(id) ?? MPRoster.all[0]
            let kind: CrossSeatKind = seat == mine ? .local : (humans.contains(seat) ? .remote : .house)
            return CrossSeat(index: seat, kind: kind, id: playerAt(seat) ?? "house\(seat)", name: nameAt(seat, hebrew: false),
                             bot: humans.contains(seat) ? nil : character.profile, characterId: id)
        }
        let engine = CrossEngine(seats: players, control: .beginner, target: 7, seed: CrossWire.number(meta, "createdAt"), networked: true,
                                 teams: CrossTeams.across(count), tapTargets: true)
        engine.authoritative = host
        return engine
    }
    private func snapshot() -> MPWire {
        var w: MPWire = ["protocol": CrossTeamRoom.protocolName, "seen": gate.snapshot()]
        if let game { w["engine"] = game.exportState().wire() }
        return w
    }
    private func restoreIfNeeded() {
        guard let body = checkpointBody, profilesLoaded, !meta.isEmpty, localSeat >= 0, !(host && loaded) else { return }
        do {
            guard let saved = CrossJSON.decode(body), CrossWire.text(saved, "protocol") == CrossTeamRoom.protocolName else { throw CrossStateError.invalid("protocol") }
            let seen = MPCodec.map(saved["seen"]).mapValues { ($0 as? NSNumber)?.int64Value ?? 0 }
            if !host && loaded && pendingSequence > (seen[uid] ?? 0) && uptime() - pendingAt < 1500 { return }
            let engine: CrossEngine
            if let existing = game { engine = existing } else { engine = makeEngine(); game = engine }
            try engine.restoreState(try CrossState.read(MPCodec.map(saved["engine"])), preserveInput: loaded && !host)
            if host { gate.restore(seen) }
            if !loaded { publishedStrike = engine.localStrikeID }
            loaded = true; listenInputs(); changed()
        } catch { failed(Message.restore) }
    }
    private func shareReception() {
        #if MINIK_PING_PONG && canImport(FirebaseDatabase) && canImport(FirebaseAuth)
        guard !uid.isEmpty else { return }
        if !receptionWatching.contains(uid) {
            write(db.reference(withPath: "minikCrossTeams/receptionPreferences/" + uid), ["version": 1, "slow": preferences.receptionSlow] as [String: Any])
        }
        for player in seats.keys where !receptionWatching.contains(player) {
            receptionWatching.insert(player)
            watch(db.reference(withPath: "minikCrossTeams/receptionPreferences/" + player)) { [weak self] s in
                let w = MPCodec.map(s.value)
                if CrossWire.number(w, "version") == 1, let slow = w["slow"] as? Bool { self?.receptionOptions[player] = slow } else { self?.receptionOptions[player] = nil }
            }
        }
        #endif
    }
    private func listenInputs() {
        shareReception()
        #if MINIK_PING_PONG && canImport(FirebaseDatabase) && canImport(FirebaseAuth)
        guard host, let target = room, loaded else { return }
        for player in seats.keys where commands[player] == nil {
            let query = target.child("inputs").child(player).queryOrderedByKey()
            let handle = query.observe(.childAdded, with: { [weak self] s in
                MainActor.assumeIsolated {
                    guard let self, !self.closed else { return }
                    let n = MPCodec.map(s.value)
                    if let engine = self.game, self.gate.accept(player, CrossWire.number(n, "seq")), let seat = self.seats[player], self.everyoneHere, self.active,
                       let body = CrossJSON.decode(CrossWire.text(n, "body")) {
                        let strike = CrossStrike.read(body)
                        engine.applyRemoteStrike(seat, strike, rallyId: strike.rallyId, hitIndex: strike.hitIndex)
                    }
                    self.consumed.append("inputs/\(player)/\(s.key)")
                }
            }, withCancel: { [weak self] error in MainActor.assumeIsolated { self?.report(error) } })
            commands[player] = (query, handle)
        }
        #endif
    }
    func setReady(_ value: Bool) {
        #if MINIK_PING_PONG && canImport(FirebaseDatabase) && canImport(FirebaseAuth)
        guard phase == "lobby" else { return }
        if let target = room { write(target.child("ready").child(uid), value) }
        #endif
    }
    func start() {
        #if MINIK_PING_PONG && canImport(FirebaseDatabase) && canImport(FirebaseAuth)
        guard canStart, let target = room else { return }
        game = makeEngine(); loaded = true; listenInputs()
        let update: [String: Any] = ["phase": "playing", "snapshot": ["body": CrossJSON.encode(snapshot()), "at": ServerValue.timestamp()] as [String: Any]]
        Task { @MainActor [weak self] in
            do { _ = try await target.updateChildValues(update) }
            catch { guard let self else { return }; self.loaded = false; self.game = nil; self.report(error) }
        }
        #endif
    }
    private func publishStrike() {
        #if MINIK_PING_PONG && canImport(FirebaseDatabase) && canImport(FirebaseAuth)
        guard let engine = game, let strike = engine.localStrike(), engine.localStrikeID != publishedStrike else { return }
        publishedStrike = engine.localStrikeID
        if host { return }
        sequence = max(sequence + 1, MPClock.now); preferences.teamSequence = sequence
        pendingSequence = sequence; pendingAt = uptime()
        let key = String(repeating: "0", count: max(0, 16 - String(sequence).count)) + String(sequence)
        if let target = room { write(target.child("inputs").child(uid).child(key), ["seq": sequence, "body": CrossJSON.encode(strike.wire())] as [String: Any]) }
        #endif
    }
    func setActive(_ value: Bool) { active = value; lastTick = 0; publishPresence(); changed() }
    private func publishIdentity() {
        #if MINIK_PING_PONG && canImport(FirebaseDatabase) && canImport(FirebaseAuth)
        guard !closed, phase == "lobby", connected, members[uid] != nil, !identityPublished, !identityPublishing, let target = room else { return }
        identityPublishing = true
        let profile = identity.wire(), me = uid
        Task { @MainActor [weak self] in
            do {
                _ = try await target.child("profiles").child(me).setValue(profile)
                self?.identityPublishing = false; self?.identityPublished = true
                let phase = try await target.child("phase").getData()
                guard let self, !self.closed, (phase.value as? String) == "lobby" else { return }
                self.setReady(true)
            } catch {
                self?.identityPublishing = false
                self?.report(error)
            }
        }
        #endif
    }
    /// Cancel is allowed only before play. The host removes the room; a guest releases only their own place.
    func cancel(_ done: @escaping (Bool) -> Void) {
        #if MINIK_PING_PONG && canImport(FirebaseDatabase) && canImport(FirebaseAuth)
        guard let target = room else { done(true); return }
        guard phase == "lobby" else { done(false); return }
        let hostNow = host, seat = members[uid] ?? -1, me = uid
        Task { @MainActor [weak self] in
            do {
                _ = try await target.child("presence").child(me).cancelDisconnectOperations()
                if hostNow { _ = try await target.removeValue() }
                else {
                    let release: [AnyHashable: Any] = ["seats/\(seat)": NSNull(), "ready/\(me)": NSNull(), "profiles/\(me)": NSNull(), "presence/\(me)": NSNull()]
                    _ = try await target.updateChildValues(release)
                }
                guard let self else { return }
                self.preferences.teamRoom = nil
                self.shutDown()
                done(true)
            } catch {
                self?.report(error)
                done(false)
            }
        }
        #else
        done(true)
        #endif
    }
    private func publishPresence() {
        #if MINIK_PING_PONG && canImport(FirebaseDatabase) && canImport(FirebaseAuth)
        guard !uid.isEmpty, let target = room, connected else { return }
        lastPresence = uptime()
        let r = target.child("presence").child(uid)
        r.onDisconnectSetValue(0)
        let value: Any = active ? (ServerValue.timestamp() as Any) : (0 as Any)
        write(r, value)
        #endif
    }
    private func startPump() {
        pump?.invalidate()
        pump = Timer.scheduledTimer(withTimeInterval: 0.02, repeats: true) { [weak self] _ in
            guard let room = self else { return }
            MainActor.assumeIsolated { room.tick() }
        }
    }
    private func tick() {
        if closed { return }
        reconcileLineup()
        let time = uptime()
        let dt = lastTick == 0 ? 0 : min(0.05, Double(time - lastTick) / 1000)
        lastTick = time
        if time - lastPresence > 2500 { publishIdentity(); publishPresence(); changed() }
        guard let engine = game, loaded, phase == "playing" else { return }
        engine.paused = waiting
        if host {
            engine.reception.enabled = !humanSeats.isEmpty && seats.keys.allSatisfy { receptionOptions[$0] != nil }
            for (user, seat) in seats { engine.reception.slow[seat] = receptionOptions[user] ?? true }
        }
        var remaining = dt
        while remaining > 0 { let step = min(remaining, 1.0 / 120); engine.advance(step); remaining -= step }
        _ = engine.drainEvents()
        if !waiting { publishStrike() }
        changed()
        #if MINIK_PING_PONG && canImport(FirebaseDatabase) && canImport(FirebaseAuth)
        if host && connected && !publishing && time - lastPublish >= 100, let target = room {
            publishing = true; lastPublish = time
            let ack = consumed
            var update: [String: Any] = ["snapshot": ["body": CrossJSON.encode(snapshot()), "at": ServerValue.timestamp()] as [String: Any]]
            for path in ack { update[path] = NSNull() }
            if engine.referee.winner != nil {
                update["phase"] = "finished"
                update["result"] = ["left": engine.referee.score(0), "right": engine.referee.score(1), "at": ServerValue.timestamp()] as [String: Any]
            }
            let body = update
            Task { @MainActor [weak self] in
                do {
                    _ = try await target.updateChildValues(body)
                    self?.publishing = false
                    self?.consumed.removeAll { ack.contains($0) }
                } catch {
                    self?.publishing = false
                    self?.report(error)
                }
            }
        }
        #endif
    }
    #if MINIK_PING_PONG && canImport(FirebaseDatabase) && canImport(FirebaseAuth)
    private func watch(_ query: DatabaseQuery, _ receive: @escaping @MainActor (DataSnapshot) -> Void) {
        let handle = query.observe(.value, with: { [weak self] s in
            MainActor.assumeIsolated {
                guard let self, !self.closed else { return }
                receive(s)
            }
        }, withCancel: { [weak self] error in MainActor.assumeIsolated { self?.report(error) } })
        watches.append((query, handle))
    }
    /// A write whose failure is reported (Android addOnFailureListener), optionally followed by `then`.
    private func write(_ ref: DatabaseReference, _ value: Any, then: (@MainActor () -> Void)? = nil) {
        Task { @MainActor [weak self] in
            do { _ = try await ref.setValue(value); then?() } catch { self?.report(error) }
        }
    }
    #endif
    private func report(_ error: Error) { if !closed { failed(error.localizedDescription.isEmpty ? Message.interrupted : error.localizedDescription) } }
    private func shutDown() {
        closed = true
        pump?.invalidate(); pump = nil
        #if MINIK_PING_PONG && canImport(FirebaseDatabase) && canImport(FirebaseAuth)
        for (query, handle) in watches { query.removeObserver(withHandle: handle) }
        for (query, handle) in commands.values { query.removeObserver(withHandle: handle) }
        watches = []; commands = [:]
        #endif
    }
    func close() {
        if closed { return }
        active = false; publishPresence()
        shutDown()
    }
}
