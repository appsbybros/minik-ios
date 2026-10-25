import Foundation
import Combine
#if MINIK_PING_PONG && canImport(FirebaseDatabase) && canImport(FirebaseAuth)
import FirebaseCore
import FirebaseAuth
import FirebaseDatabase
#endif

/// Android `PongTeamRoom`: the separate live doubles protocol (`minikPongTeams/rooms/<code>`). One-against-one rooms
/// and their rules are untouched. The creating phone is the authority; friends send inputs and draw its snapshots.
/// New rooms use the flexible lobby (`pong-doubles-v1-lobby-v2`): the host arranges `lineup/slots`.
@MainActor final class MPTeamRoom: ObservableObject {
    static let rootPath = "minikPongTeams"
    @Published private(set) var revision = 0
    private(set) var code = "", uid = ""
    private(set) var meta: MPWire = [:]
    private(set) var members: [String: Int] = [:]
    private(set) var lineup: MPTeamLineup?
    private(set) var ready: Set<String> = []
    private(set) var profiles: [String: MPTeamIdentity] = [:]
    private(set) var presence: [String: Int64] = [:]
    private(set) var phase = ""
    private(set) var game: MPPlay?
    private(set) var lineupBusy = false
    var failed: ((String) -> Void)?
    private var identity: MPTeamIdentity
    private let defaults = UserDefaults.standard
    /// Android f0ea4aa: every seated player's shared colour (`minikPingPong/profiles/<uid>/{rankPoints, rankLevel}`).
    private var ranks: [String: MPRankBadge] = [:], rankWatching: Set<String> = []
    private let ownRank = MPRanking().badge
    /// The language a first-ever nickname is reserved in (Android `profileHebrew`).
    var hebrew = false
    private var rawLineup: Any?
    private var receptionOptions: [String: Bool] = [:], receptionWatching: Set<String> = []
    private var authority: MPTeamAuthority?
    private var checkpoint: String?
    private var connected = false, active = true, closed = false, publishing = false
    private var profilesLoaded = false, identityPublished = false, identityPublishing = false
    private var lastTick: TimeInterval = 0, lastPublish: TimeInterval = 0, lastPresence: TimeInterval = 0, moveAt: TimeInterval = 0
    private var offset: Int64 = 0
    private var sequence: Int64
    private var consumed: [String] = []
    private var pump: Timer?
    #if MINIK_PING_PONG && canImport(FirebaseDatabase) && canImport(FirebaseAuth)
    private var auth: Auth?
    private var database: Database?
    private var room: DatabaseReference?
    private var watches: [(DatabaseQuery, DatabaseHandle)] = []
    private var commands: [String: (DatabaseQuery, DatabaseHandle)] = [:]
    #endif

    init(identity: MPTeamIdentity) {
        self.identity = identity
        sequence = Int64(UserDefaults.standard.integer(forKey: "modern.pong.teams.sequence"))
    }
    static var available: Bool {
        #if MINIK_PING_PONG && canImport(FirebaseDatabase) && canImport(FirebaseAuth)
        return !MPController.offlineSmoke && MPFirebaseRepository.configured() != nil
        #else
        return false
        #endif
    }

    // MARK: Lobby state (Android PongTeamRoom)
    var flexible: Bool { ((meta["protocol"] as? String) ?? "").hasSuffix("-lobby-v2") }
    let capacity = 4
    /// uid → playing position.
    var seats: [String: Int] { flexible ? (lineup?.humans ?? [:]) : members }
    func occupied(_ seat: Int) -> Bool {
        guard flexible else { return true }
        guard let slots = lineup?.slots, slots.indices.contains(seat) else { return false }
        return slots[seat] != MPTeamLineup.empty
    }
    func playerAt(_ seat: Int) -> String? { seats.first { $0.value == seat }?.key }
    func nameAt(_ seat: Int, hebrew: Bool) -> String {
        if let player = playerAt(seat), let name = profiles[player]?.name { return name }
        return (MPRoster.find(characterAt(seat)) ?? MPRoster.all[0]).name(hebrew: hebrew)
    }
    func partnerSeat(_ seat: Int) -> Int? { let partner = seat ^ 1; return (0..<4).contains(partner) ? partner : nil }
    func characterAt(_ seat: Int) -> String {
        if let player = playerAt(seat), let character = profiles[player]?.character { return character }
        if flexible {
            if let slots = lineup?.slots, slots.indices.contains(seat), slots[seat].hasPrefix("b:") { return String(slots[seat].dropFirst(2)) }
            return "minik"
        }
        if !humanSeats.contains(seat), let partner = partnerSeat(seat), let player = playerAt(partner), let teammate = profiles[player]?.teammate { return teammate }
        let roster = MPPlayWire.list(meta["roster"]).compactMap { $0 as? String }
        return roster.indices.contains(seat) ? roster[seat] : "minik"
    }
    func present(_ player: String) -> Bool { (presence[player] ?? 0) > now() - 9000 }
    var host: Bool { !uid.isEmpty && meta["host"] as? String == uid }
    /// Android `PongTeamRoom.arena` (a4174b6): `meta.arena`, immutable once created; older rooms read as the original court.
    var arena: MPArena { MPArena.read(meta["arena"] as? String) }
    var localSeat: Int { seats[uid] ?? -1 }
    var humanSeats: Set<Int> {
        if flexible { return Set(seats.values) }
        return Set(MPCodec.map(meta["humans"]).filter { MPReceptionAssist.flag($0.value) == true }.keys.compactMap { Int($0) })
    }
    var everyoneHere: Bool {
        guard connected, !flexible || lineup?.complete == true, !humanSeats.isEmpty, Set(seats.values) == humanSeats else { return false }
        return seats.keys.allSatisfy { members[$0] != nil && ready.contains($0) && (phase != "lobby" || profiles[$0] != nil) && present($0) }
    }
    var canStart: Bool {
        guard host, phase == "lobby", localSeat >= 0, everyoneHere, !lineupBusy else { return false }
        guard flexible, let lineup else { return true }
        return members.keys.filter { profiles[$0] != nil && present($0) }.allSatisfy { lineup.seen.contains($0) }
    }
    var waiting: Bool { phase == "playing" && (!everyoneHere || !active) }
    /// Android f0ea4aa `palette`: the host keeps the exact earned colour; the other team shows its first seated
    /// player's colour, or a distinct tint of the same hue when both have the same rank.
    func palette(_ seed: Int64 = 0) -> MPTeamColors.Palette {
        let owner = (meta["host"] as? String) ?? "", ownerTeam = (seats[owner] ?? 0) / 2
        let opponent = seats.filter { $0.value / 2 != ownerTeam }.min { $0.value < $1.value }?.key
        func color(_ id: String) -> UInt32 { MPRanks.all[(ranks[id] ?? (id == uid ? ownRank : MPRankBadge())).safe.level].color }
        return MPTeamColors.online(host: color(owner), guest: opponent.map(color), hostTeam: ownerTeam, seed: seed)
    }
    private func now() -> Int64 { MPClock.now + offset }
    private func changed() { revision &+= 1 }
    private func fail(_ message: String) { if !closed { failed?(message) } }
    private func fail(_ error: Error?) { fail(error.map { ($0 as NSError).localizedDescription } ?? "Connection interrupted. Reopen the room to continue.") }

    // MARK: Actions
    func connect(_ done: @escaping () -> Void) {
        #if MINIK_PING_PONG && canImport(FirebaseDatabase) && canImport(FirebaseAuth)
        guard MPTeamRoom.available, let app = FirebaseApp.app(name: MPFirebaseRepository.appName) else { fail("Online play is not configured for this build."); return }
        let auth = Auth.auth(app: app)
        let database = Database.database(app: app, url: "https://minikswish-default-rtdb.europe-west1.firebasedatabase.app/")
        self.auth = auth; self.database = database
        let begin: () -> Void = { [weak self] in
            guard let self, !self.closed, let user = auth.currentUser else { return }
            self.uid = user.uid
            self.watch(database.reference(withPath: ".info/serverTimeOffset")) { [weak self] s in self?.offset = (s.value as? NSNumber)?.int64Value ?? 0 }
            self.watch(database.reference(withPath: ".info/connected")) { [weak self] s in
                guard let self else { return }
                self.connected = (s.value as? Bool) == true
                if self.connected { self.publishIdentity(); self.publishPresence() }
                self.changed()
            }
            self.ranks[user.uid] = self.ownRank
            self.startPump(); self.prepareRank(done)
        }
        if auth.currentUser == nil {
            auth.signInAnonymously { [weak self] _, error in
                MainActor.assumeIsolated {
                    if let error { self?.fail(error); return }
                    begin()
                }
            }
        } else { begin() }
        #else
        fail("Online play is not configured for this build.")
        #endif
    }
    /// Android `createFlexible(mode, arena)`: `arena` must be one of the four choices (rules reject anything else).
    func createFlexible(_ mode: MPTeamMode, arena: String = "beach") {
        #if MINIK_PING_PONG && canImport(FirebaseDatabase) && canImport(FirebaseAuth)
        guard MPArena.choices.map(\.wire).contains(arena), room == nil, let database, !uid.isEmpty else { return }
        let value = MPRules.code()
        let humans: MPWire = ["0": true, "1": true, "2": true, "3": true]
        let metaValue: MPWire = ["host": uid, "protocol": MPTeamAuthority.protocolName + "-lobby-v2", "arena": arena, "mode": mode.rawValue,
                                 "roster": ["miniko", "minik", "mia", "june"], "humans": humans, "createdAt": ServerValue.timestamp()]
        let initial: MPWire = ["meta": metaValue, "phase": "lobby", "seats": ["0": uid], "ready": [uid: false],
                               "lineup": MPTeamLineup.initial(host: uid, count: 4).wire]
        database.reference(withPath: MPTeamRoom.rootPath + "/rooms/" + value).setValue(initial) { [weak self] error, _ in
            MainActor.assumeIsolated {
                if let error { self?.fail(error) } else { self?.attach(value) }
            }
        }
        #endif
    }
    /// Android `chooseSlot`: only the host, only in the lobby; a friend must be connected with a profile.
    func chooseSlot(_ seat: Int, _ value: String) {
        guard host, flexible, phase == "lobby", !lineupBusy, (0..<capacity).contains(seat) else { return }
        if value.hasPrefix("u:") {
            let user = String(value.dropFirst(2))
            guard members[user] != nil, profiles[user] != nil, present(user) else { return }
        } else if value != MPTeamLineup.empty {
            guard value.hasPrefix("b:"), MPRoster.find(String(value.dropFirst(2))) != nil else { return }
        }
        changeLineup { $0.choose(seat, value) }
    }
    private func changeLineup(_ change: @escaping (MPTeamLineup) -> MPTeamLineup) {
        #if MINIK_PING_PONG && canImport(FirebaseDatabase) && canImport(FirebaseAuth)
        guard let room, !lineupBusy else { return }
        lineupBusy = true; changed()
        let count = capacity
        room.child("lineup").runTransactionBlock({ data in
            guard let current = MPTeamLineup.read(data.value, count: count) else { return TransactionResult.abort() }
            let next = change(current)
            if next == current { return TransactionResult.abort() }
            data.value = next.wire
            return TransactionResult.success(withValue: data)
        }, andCompletionBlock: { [weak self] error, _, _ in
            MainActor.assumeIsolated {
                guard let self else { return }
                self.lineupBusy = false
                if let error { self.fail(error) }
                self.changed()
            }
        }, withLocalEvents: false)
        #endif
    }
    private func reconcileLineup() {
        guard host, flexible, phase == "lobby", !lineupBusy, profilesLoaded, let current = lineup else { return }
        let arrivals = members.sorted { $0.value < $1.value }.map(\.key).filter { profiles[$0] != nil && present($0) }
        let order = Array(0..<capacity), known = Set(members.keys)
        if current.reconcile(members: known, arrivals: arrivals, order: order) != current {
            changeLineup { $0.reconcile(members: known, arrivals: arrivals, order: order) }
        }
    }
    /// Android `join`: friends take an invited place (2, 1, 3); a saved code restores the same place.
    func join(_ raw: String) {
        #if MINIK_PING_PONG && canImport(FirebaseDatabase) && canImport(FirebaseAuth)
        guard room == nil, let database else { return }
        let safe = raw.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        guard safe.count == 6, safe.allSatisfy({ MPRules.alphabet.contains($0) }) else { fail("Check the six-character room code."); return }
        let target = database.reference(withPath: MPTeamRoom.rootPath + "/rooms/" + safe)
        let uid = self.uid
        target.getData { [weak self] error, snapshot in
            MainActor.assumeIsolated {
                guard let self else { return }
                if let error { self.fail(error); return }
                guard let snapshot, snapshot.exists() else { self.fail("Room not found."); return }
                let protocolName = (snapshot.childSnapshot(forPath: "meta/protocol").value as? String) ?? ""
                guard protocolName == MPTeamAuthority.protocolName || protocolName == MPTeamAuthority.protocolName + "-lobby-v2" else {
                    self.fail("This room needs a newer app version."); return
                }
                let seats = MPCodec.map(snapshot.childSnapshot(forPath: "seats").value)
                if seats.values.contains(where: { $0 as? String == uid }) { self.attach(safe); return }
                guard snapshot.childSnapshot(forPath: "phase").value as? String == "lobby" else { self.fail("This match has already started."); return }
                let invited = MPCodec.map(snapshot.childSnapshot(forPath: "meta/humans").value).keys.compactMap { Int($0) }
                let free = invited.filter { seats[String($0)] == nil }
                self.claim([2, 1, 3].filter { free.contains($0) }, 0, target, safe)
            }
        }
        #endif
    }
    #if MINIK_PING_PONG && canImport(FirebaseDatabase) && canImport(FirebaseAuth)
    private func claim(_ choices: [Int], _ index: Int, _ target: DatabaseReference, _ safe: String) {
        guard index < choices.count else { fail("No invited place is available."); return }
        let uid = self.uid
        target.child("seats").child(String(choices[index])).runTransactionBlock({ data in
            if let existing = data.value as? String, existing != uid { return TransactionResult.abort() }
            data.value = uid
            return TransactionResult.success(withValue: data)
        }, andCompletionBlock: { [weak self] error, committed, _ in
            MainActor.assumeIsolated {
                guard let self else { return }
                if let error { self.fail(error) } else if !committed { self.claim(choices, index + 1, target, safe) } else { self.attach(safe) }
            }
        }, withLocalEvents: false)
    }
    #endif
    private func attach(_ value: String) {
        #if MINIK_PING_PONG && canImport(FirebaseDatabase) && canImport(FirebaseAuth)
        guard !closed, let database else { return }
        code = value
        let room = database.reference(withPath: MPTeamRoom.rootPath + "/rooms/" + value)
        self.room = room
        defaults.set(value, forKey: "modern.pong.teams.room")
        watch(room.child("meta")) { [weak self] s in
            guard let self else { return }
            self.meta = MPCodec.map(s.value); self.lineup = MPTeamLineup.read(self.rawLineup, count: self.capacity); self.restoreIfNeeded(); self.changed()
        }
        watch(room.child("profiles")) { [weak self] s in
            guard let self else { return }
            self.profilesLoaded = true
            var next: [String: MPTeamIdentity] = [:]
            for case let child as DataSnapshot in s.children { if let identity = MPTeamIdentity.from(child.value) { next[child.key] = identity } }
            self.profiles = next; self.restoreIfNeeded(); self.changed()
        }
        watch(room.child("seats")) { [weak self] s in
            guard let self else { return }
            var next: [String: Int] = [:]
            for case let child as DataSnapshot in s.children { if let user = child.value as? String, let seat = Int(child.key) { next[user] = seat } }
            self.members = next; self.publishIdentity(); self.restoreIfNeeded(); self.listenInputs(); self.changed()
        }
        watch(room.child("lineup")) { [weak self] s in
            guard let self else { return }
            self.rawLineup = s.value; self.lineup = MPTeamLineup.read(s.value, count: self.capacity); self.restoreIfNeeded(); self.listenInputs(); self.changed()
        }
        watch(room.child("ready")) { [weak self] s in
            guard let self else { return }
            var next: Set<String> = []
            for case let child as DataSnapshot in s.children where MPReceptionAssist.flag(child.value) == true { next.insert(child.key) }
            self.ready = next; self.changed()
        }
        watch(room.child("presence")) { [weak self] s in
            guard let self else { return }
            var next: [String: Int64] = [:]
            for case let child as DataSnapshot in s.children { next[child.key] = (child.value as? NSNumber)?.int64Value ?? 0 }
            self.presence = next; self.changed()
        }
        watch(room.child("phase")) { [weak self] s in
            guard let self else { return }
            self.phase = (s.value as? String) ?? "closed"; self.publishIdentity(); self.changed()
        }
        watch(room.child("snapshot")) { [weak self] s in
            guard let self else { return }
            self.checkpoint = s.childSnapshot(forPath: "body").value as? String; self.restoreIfNeeded()
        }
        publishPresence(); changed()
        #endif
    }
    /// Friends draw the authority's latest snapshot; a reopened host continues from it.
    private func restoreIfNeeded() {
        guard let body = checkpoint, profilesLoaded, !meta.isEmpty, !seats.isEmpty, !(host && authority != nil) else { return }
        do {
            let restored = try MPTeamAuthority.restore(try MPJSON.decode(body), expectedSeats: seats)
            restored.game.start(); game = restored.game
            if host { authority = restored; listenInputs() }
            changed()
        } catch { fail("The shared match could not be restored. Reopen this room.") }
    }
    /// Android f0ea4aa `prepareRank`: publish this player's colour on their Ping Pong profile before the room opens.
    /// Teams may be someone's first online game: without a profile, the ordinary nickname registration creates one
    /// first, since rank-only writes cannot create a valid profile.
    private func prepareRank(_ done: @escaping () -> Void) {
        #if MINIK_PING_PONG && canImport(FirebaseDatabase) && canImport(FirebaseAuth)
        guard let database else { return }
        let ref = database.reference(withPath: "minikPingPong/profiles/" + uid), badge = ownRank
        let publish: () -> Void = { [weak self] in
            ref.updateChildValues(badge.wire) { error, _ in
                MainActor.assumeIsolated {
                    guard let self, !self.closed else { return }
                    if let error { self.fail(error) } else { done() }
                }
            }
        }
        ref.getData { [weak self] error, snapshot in
            MainActor.assumeIsolated {
                guard let self, !self.closed else { return }
                if let error { self.fail(error); return }
                if snapshot?.exists() == true { publish(); return }
                guard let repository = MPFirebaseRepository.configured() else { self.fail(nil); return }
                let preferences = MPPreferences(), stored = preferences.identity, character = self.identity.character, hebrew = self.hebrew
                Task { @MainActor [weak self] in
                    do {
                        let reserved = try await repository.profile(index: 0, hebrew: hebrew, avatar: stored?.avatar ?? 0, character: character)
                        guard let self, !self.closed else { return }
                        self.identity.name = reserved.name; preferences.identity = reserved
                        publish()
                    } catch { self?.fail(error) }
                }
            }
        }
        #endif
    }
    private func watchRanks() {
        #if MINIK_PING_PONG && canImport(FirebaseDatabase) && canImport(FirebaseAuth)
        guard let database else { return }
        for player in seats.keys.sorted() where !rankWatching.contains(player) {
            rankWatching.insert(player)
            watch(database.reference(withPath: "minikPingPong/profiles/" + player)) { [weak self] s in
                guard let self else { return }
                self.ranks[player] = MPRankBadge(wire: MPCodec.map(s.value)); self.changed()
            }
        }
        #endif
    }
    private func receptionPreferences() {
        #if MINIK_PING_PONG && canImport(FirebaseDatabase) && canImport(FirebaseAuth)
        guard !uid.isEmpty, let database else { return }
        let base = MPTeamRoom.rootPath + "/receptionPreferences/"
        if !receptionWatching.contains(uid) {
            let own: MPWire = ["version": 1, "slow": MPReceptionSettings.slow]
            database.reference(withPath: base + uid).setValue(own) { [weak self] error, _ in
                MainActor.assumeIsolated { if let error { self?.fail(error) } }
            }
        }
        for player in seats.keys.sorted() where !receptionWatching.contains(player) {
            receptionWatching.insert(player)
            watch(database.reference(withPath: base + player)) { [weak self] s in
                guard let self else { return }
                let w = MPCodec.map(s.value)
                if (w["version"] as? NSNumber)?.intValue == 1, let slow = MPReceptionAssist.flag(w["slow"]) { self.receptionOptions[player] = slow }
                else { self.receptionOptions[player] = nil }
            }
        }
        #endif
    }
    private func listenInputs() {
        receptionPreferences(); watchRanks()
        #if MINIK_PING_PONG && canImport(FirebaseDatabase) && canImport(FirebaseAuth)
        guard host, let room, authority != nil else { return }
        for player in seats.keys.sorted() where commands[player] == nil {
            let query = room.child("inputs").child(player).queryOrderedByKey()
            let handle = query.observe(.childAdded, with: { [weak self] s in
                MainActor.assumeIsolated {
                    guard let self, !self.closed, let a = self.authority else { return }
                    let n = MPCodec.map(s.value)
                    if self.everyoneHere && self.active {
                        // Android 22f756e: optional `control` and `stroke` {aim, power, top, side}.
                        let control = (n["control"] as? NSNumber)?.intValue
                        let s = MPCodec.map(n["stroke"])
                        let stroke = s.isEmpty ? nil : MPPongStroke(aim: MPPlayWire.decimal(s, "aim"), power: MPPlayWire.decimal(s, "power"), top: MPPlayWire.decimal(s, "top"), side: MPPlayWire.decimal(s, "side"))
                        a.receive(player, sequence: MPPlayWire.int64(n, "seq"), kind: (n["kind"] as? String) ?? "", x: MPPlayWire.decimal(n, "x"), y: MPPlayWire.decimal(n, "y"), control: control, stroke: stroke)
                    }
                    self.consumed.append("inputs/" + player + "/" + s.key)
                }
            }, withCancel: { [weak self] error in MainActor.assumeIsolated { self?.fail(error) } })
            commands[player] = (query, handle)
        }
        #endif
    }
    func setReady(_ value: Bool) {
        #if MINIK_PING_PONG && canImport(FirebaseDatabase) && canImport(FirebaseAuth)
        guard phase == "lobby", let room else { return }
        room.child("ready").child(uid).setValue(value) { [weak self] error, _ in MainActor.assumeIsolated { if let error { self?.fail(error) } } }
        #endif
    }
    func start() {
        #if MINIK_PING_PONG && canImport(FirebaseDatabase) && canImport(FirebaseAuth)
        guard canStart, let room, let mode = MPTeamMode(rawValue: (meta["mode"] as? String) ?? "") else { return }
        let roster = (0..<4).map { characterAt($0) }
        let engine = MPPlay(mode: mode, roster: roster, humanSeats: humanSeats, arena: (meta["arena"] as? String) ?? "")
        engine.start()
        guard let a = try? MPTeamAuthority(game: engine, seats: seats), let body = MPJSON.encode(a.checkpoint()) else { return }
        authority = a; game = engine
        listenInputs()
        let update: [AnyHashable: Any] = ["phase": "playing", "snapshot": ["body": body, "at": ServerValue.timestamp()] as [String: Any]]
        room.updateChildValues(update) { [weak self] error, _ in
            MainActor.assumeIsolated {
                guard let self, let error else { return }
                self.authority = nil; self.game = nil; self.fail(error)
            }
        }
        changed()
        #endif
    }
    /// Android `supportsSpinControls`: the host, or a host whose snapshots advertise `spinControls` (older hosts would
    /// reject stroke and control inputs).
    var supportsSpinControls: Bool {
        if host { return true }
        guard let body = checkpoint, let w = try? MPJSON.decode(body) else { return false }
        return (w["spinControls"] as? NSNumber)?.int64Value == 1
    }
    /// A move, tap, stroke or control change toward table coordinates; moves are throttled to one per 45 ms.
    func input(_ kind: String, _ to: MPPoint, control: Int? = nil, stroke: MPPongStroke? = nil) {
        guard phase == "playing", !waiting, localSeat >= 0 else { return }
        if (control != nil || stroke != nil) && !supportsSpinControls { return }
        let uptime = ProcessInfo.processInfo.systemUptime
        if kind == "move" { if uptime - moveAt < 0.045 { return }; moveAt = uptime }
        sequence = max(sequence + 1, MPClock.now)
        defaults.set(sequence, forKey: "modern.pong.teams.sequence")
        let x = to.x.mpClamp(0, 1), y = to.y.mpClamp(0, 1)
        if host { authority?.receive(uid, sequence: sequence, kind: kind, x: x, y: y, control: control, stroke: stroke); return }
        #if MINIK_PING_PONG && canImport(FirebaseDatabase) && canImport(FirebaseAuth)
        guard let room else { return }
        let key = String(repeating: "0", count: max(0, 16 - String(sequence).count)) + String(sequence)
        var value: MPWire = ["seq": NSNumber(value: sequence), "kind": kind, "x": x, "y": y]
        if let control { value["control"] = control }
        if let stroke { value["stroke"] = ["aim": stroke.aim, "power": stroke.power, "top": stroke.top, "side": stroke.side] }
        room.child("inputs").child(uid).child(key).setValue(value) { [weak self] error, _ in MainActor.assumeIsolated { if let error { self?.fail(error) } } }
        #endif
    }
    func setActive(_ value: Bool) { active = value; lastTick = 0; publishPresence(); changed() }
    private func publishIdentity() {
        #if MINIK_PING_PONG && canImport(FirebaseDatabase) && canImport(FirebaseAuth)
        guard !closed, phase == "lobby", connected, members[uid] != nil, !identityPublished, !identityPublishing, let room else { return }
        identityPublishing = true
        room.child("profiles").child(uid).setValue(identity.wire) { [weak self] error, _ in
            MainActor.assumeIsolated {
                guard let self else { return }
                self.identityPublishing = false
                if let error { self.fail(error); return }
                self.identityPublished = true
                // Joining signals readiness automatically; the host presses Start.
                room.child("phase").getData { [weak self] _, snapshot in
                    MainActor.assumeIsolated {
                        guard let self, !self.closed, snapshot?.value as? String == "lobby" else { return }
                        self.setReady(true)
                    }
                }
            }
        }
        #endif
    }
    /// Android `cancel`: only before play. The host removes the room; a friend releases only their own place.
    func cancel(_ done: @escaping (Bool) -> Void) {
        #if MINIK_PING_PONG && canImport(FirebaseDatabase) && canImport(FirebaseAuth)
        guard let room else { done(true); return }
        guard phase == "lobby" else { done(false); return }
        let uid = self.uid
        let hostNow = host, seat = members[uid] ?? -1, presenceRef = room.child("presence").child(uid)
        presenceRef.cancelDisconnectOperations { [weak self] error, _ in
            MainActor.assumeIsolated {
                guard let self else { return }
                if let error { self.fail(error); done(false); return }
                let finished: (Error?, DatabaseReference) -> Void = { [weak self] error, _ in
                    MainActor.assumeIsolated {
                        guard let self else { return }
                        if let error { self.fail(error); done(false); return }
                        self.defaults.removeObject(forKey: "modern.pong.teams.room")
                        self.stop(); done(true)
                    }
                }
                if hostNow { room.removeValue(completionBlock: finished) }
                else {
                    let release: [AnyHashable: Any] = ["seats/" + String(seat): NSNull(), "ready/" + uid: NSNull(), "profiles/" + uid: NSNull(), "presence/" + uid: NSNull()]
                    room.updateChildValues(release, withCompletionBlock: finished)
                }
            }
        }
        #else
        done(true)
        #endif
    }
    private func publishPresence() {
        #if MINIK_PING_PONG && canImport(FirebaseDatabase) && canImport(FirebaseAuth)
        guard !uid.isEmpty, let room, connected else { return }
        lastPresence = ProcessInfo.processInfo.systemUptime
        let r = room.child("presence").child(uid)
        r.onDisconnectSetValue(0)
        let value: Any
        if active { value = ServerValue.timestamp() } else { value = 0 }
        r.setValue(value) { [weak self] error, _ in MainActor.assumeIsolated { if let error { self?.fail(error) } } }
        #endif
    }
    private func startPump() {
        pump?.invalidate()
        pump = Timer.scheduledTimer(withTimeInterval: 0.02, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.tick() }
        }
    }
    private func tick() {
        guard !closed else { return }
        reconcileLineup()
        let time = ProcessInfo.processInfo.systemUptime
        let dt = lastTick == 0 ? 0 : min(time - lastTick, 0.05)
        lastTick = time
        if time - lastPresence > 2.5 { publishIdentity(); publishPresence(); changed() }
        guard let a = authority, host, phase == "playing" else { return }
        a.game.paused = waiting
        a.game.reception.enabled = !humanSeats.isEmpty && seats.keys.allSatisfy { receptionOptions[$0] != nil }
        for (user, seat) in seats { a.game.reception.slow[seat] = receptionOptions[user] ?? true }
        var remaining = dt
        while remaining > 0 { let step = min(remaining, 1.0 / 120); a.game.advance(step); remaining -= step }
        game = a.game; changed()
        #if MINIK_PING_PONG && canImport(FirebaseDatabase) && canImport(FirebaseAuth)
        guard connected, !publishing, time - lastPublish >= 0.1, let room, let body = MPJSON.encode(a.checkpoint()) else { return }
        publishing = true; lastPublish = time
        let acknowledged = consumed
        var update: [AnyHashable: Any] = ["snapshot": ["body": body, "at": ServerValue.timestamp()] as [String: Any]]
        for path in acknowledged { update[path] = NSNull() }
        if a.game.ended && a.game.ending == nil {
            update["phase"] = "finished"
            update["result"] = ["left": a.game.points[0], "right": a.game.points[1], "at": ServerValue.timestamp()] as [String: Any]
        }
        room.updateChildValues(update) { [weak self] error, _ in
            MainActor.assumeIsolated {
                guard let self else { return }
                self.publishing = false
                if let error { self.fail(error) } else { self.consumed.removeAll { acknowledged.contains($0) } }
            }
        }
        #endif
    }
    #if MINIK_PING_PONG && canImport(FirebaseDatabase) && canImport(FirebaseAuth)
    private func watch(_ query: DatabaseQuery, _ receive: @escaping (DataSnapshot) -> Void) {
        let handle = query.observe(.value, with: { [weak self] snapshot in
            MainActor.assumeIsolated {
                guard let self, !self.closed else { return }
                receive(snapshot)
            }
        }, withCancel: { [weak self] error in MainActor.assumeIsolated { self?.fail(error) } })
        watches.append((query, handle))
    }
    #endif
    private func stop() {
        closed = true; pump?.invalidate(); pump = nil
        #if MINIK_PING_PONG && canImport(FirebaseDatabase) && canImport(FirebaseAuth)
        for (query, handle) in watches { query.removeObserver(withHandle: handle) }
        for (query, handle) in commands.values { query.removeObserver(withHandle: handle) }
        watches = []; commands = [:]
        #endif
    }
    /// Leaving the screen: presence drops to "away" and every listener stops. The room itself stays.
    func close() {
        if closed { return }
        active = false; publishPresence(); stop()
    }
}
