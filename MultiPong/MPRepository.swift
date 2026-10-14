import Foundation

typealias MPWire = [String: Any]
enum MPCodec {
    static func map(_ value: Any?) -> MPWire {
        if let value = value as? MPWire { return value }
        if let value = value as? [Any] { return Dictionary(uniqueKeysWithValues: value.enumerated().compactMap { $0.element is NSNull ? nil : (String($0.offset), $0.element) }) }
        return [:]
    }
    /// Android `PongCodec.items`: an RTDB list arrives as a List when dense and as an index-keyed Map otherwise; keep index order.
    static func items(_ value: Any?) -> [Any] {
        if let list = value as? [Any] { return list }
        guard let keyed = value as? MPWire else { return [] }
        var indexed: [(Int, Any)] = []
        for (key, item) in keyed { if let index = Int(key) { indexed.append((index, item)) } }
        return indexed.sorted { $0.0 < $1.0 }.map { $0.1 }
    }
    private static func strings(_ value: Any?) -> [String] { items(value).compactMap { $0 as? String } }
    static func encode<T: Encodable>(_ value: T) throws -> MPWire { map(try JSONSerialization.jsonObject(with: JSONEncoder().encode(value))) }
    static func decode<T: Decodable>(_ type: T.Type, _ value: Any?) throws -> T {
        try JSONDecoder().decode(type, from: JSONSerialization.data(withJSONObject: value ?? [:]))
    }
    static func session(_ value: Any?) throws -> MPSession {
        var w = map(value)
        w["connections"] = map(w["connections"]).mapValues { map($0) }
        // RTDB returns dense numeric keys (knockout rounds and their players) as arrays; Android reads
        // them by index and ignores absent slots.
        if w["rounds"] != nil {
            w["rounds"] = map(w["rounds"]).mapValues { raw -> Any in
                var round = map(raw)
                let players = map(round["players"]).sorted { (Int($0.key) ?? Int.max) < (Int($1.key) ?? Int.max) }
                round["players"] = players.compactMap { $0.value as? String }
                // Android PongCodec.round: group tables, byes and walkover tables, each list in index order.
                if round["tables"] != nil { round["tables"] = items(round["tables"]).map { strings($0) }.filter { !$0.isEmpty } }
                if round["byes"] != nil { round["byes"] = strings(round["byes"]) }
                if round["walkovers"] != nil { round["walkovers"] = items(round["walkovers"]).map { strings($0) }.filter { !$0.isEmpty } }
                return round
            }
        }
        // Android PongCodec.match: seat-ordered players, one score per player and the placement, as arrays or index-keyed maps.
        if w["matches"] != nil {
            w["matches"] = map(w["matches"]).mapValues { raw -> Any in
                var m = map(raw)
                if m["players"] != nil {
                    let players = strings(m["players"])
                    m["players"] = players
                    let scores = items(m["scores"])
                    m["scores"] = players.indices.map { $0 < scores.count ? ((scores[$0] as? NSNumber)?.intValue ?? 0) : 0 }
                }
                if m["placement"] != nil { m["placement"] = strings(m["placement"]) }
                m["ready"] = map(m["ready"]).filter { ($0.value as? Bool) == true }
                return m
            }
        }
        return try decode(MPSession.self, w)
    }
    static func session(_ s: MPSession) throws -> MPWire {
        var w = try encode(s); w["roster"] = s.roster; w["rosterSize"] = s.roster.count
        w["matches"] = try s.matches.mapValues { m -> MPWire in var v = try encode(m); v["authorityUid"] = s.authority(m); return v }
        return w
    }
    static func number(_ w: MPWire, _ key: String) -> Int64 { (w[key] as? NSNumber)?.int64Value ?? 0 }
}
/// Play order of live actions: rally, then hit, then the sender's sequence.
enum MPRepositoryOrder {
    static func before(_ a: MPWire, _ b: MPWire) -> Bool {
        let left = (MPCodec.number(a, "rallyId"), MPCodec.number(a, "hitIndex"), MPCodec.number(a, "sequence"))
        let right = (MPCodec.number(b, "rallyId"), MPCodec.number(b, "hitIndex"), MPCodec.number(b, "sequence"))
        return left < right
    }
}
final class MPSubscription {
    private var cancel: (() -> Void)?
    init(_ cancel: @escaping () -> Void = {}) { self.cancel = cancel }
    /// Re-entrancy safe: the local repository notifies synchronously, so closing may lead back here.
    func close() { let action = cancel; cancel = nil; action?() }
    deinit { cancel?() }
}
@MainActor protocol MPRepository: AnyObject {
    var uid: String { get }; var online: Bool { get }
    func connect() async throws -> String
    func profile(index: Int, hebrew: Bool, avatar: Int, character: String) async throws -> MPIdentity
    func get(_ kind: MPSessionKind, _ code: String) async throws -> MPSession?
    func openRooms() async throws -> [(MPSessionKind, String)]
    func reserve(_ kind: MPSessionKind, _ code: String) async throws
    func create(_ session: MPSession) async throws -> MPSession
    func mutate(_ kind: MPSessionKind, _ code: String, _ change: @escaping (MPSession) throws -> MPSession) async throws -> MPSession
    func observe(_ kind: MPSessionKind, _ code: String, _ changed: @escaping (Result<MPSession, Error>) -> Void) -> MPSubscription
    func presence(_ kind: MPSessionKind, _ code: String) -> MPSubscription
    func connection(_ changed: @escaping (Bool) -> Void) -> MPSubscription
    func watchLive(_ id: String, actions: Bool, _ changed: @escaping (MPWire) -> Void, _ failed: @escaping (Error) -> Void) -> MPSubscription
    func checkpoint(_ id: String, _ value: MPWire) async throws
    func action(_ id: String, _ sequence: Int64, _ value: MPWire) async throws
    func leave(_ session: MPSession, delete: Bool) async throws
    func cleanup() async throws
    /// Android `PongRepository.receptionPreferences` (5c1aa4d): publishes this player's "slow motion for my return" choice and
    /// reports every listed player's (uid → slow) as it changes. Without a server every choice is unknown, so no match slows.
    func receptionPreferences(_ players: Set<String>, _ changed: @escaping ([String: Bool]) -> Void, _ failed: @escaping (String) -> Void) -> MPSubscription
}
extension MPRepository {
    func receptionPreferences(_ players: Set<String>, _ changed: @escaping ([String: Bool]) -> Void, _ failed: @escaping (String) -> Void) -> MPSubscription {
        changed([:]); return MPSubscription()
    }
}

/// Local sessions have their own storage. A Firebase outage never overwrites a cloud room.
/// Android `LocalPongRepository` (828c6fc): every call reads the store, so two repositories over one store (a restarted
/// process, a second screen) always agree; a room code is never reused; activity is stamped only by a real change.
@MainActor final class MPLocalRepository: MPRepository {
    private static let roomsKey = "modern.local.rooms"
    let online = false; let uid: String; private let defaults: UserDefaults
    private var listeners: [String: [UUID: (Result<MPSession, Error>) -> Void]] = [:]
    private var watchers: [String: [UUID: (MPWire) -> Void]] = [:]
    private var saves: [String: Int] = [:]
    private var sessions: [String: MPSession] {
        get { defaults.data(forKey: MPLocalRepository.roomsKey).flatMap { try? JSONDecoder().decode([String: MPSession].self, from: $0) } ?? [:] }
        set { defaults.set(try? JSONEncoder().encode(newValue), forKey: MPLocalRepository.roomsKey) }
    }
    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults; uid = defaults.string(forKey: "modern.local.uid") ?? "local_" + UUID().uuidString
        defaults.set(uid, forKey: "modern.local.uid")
        // Android LocalPongRepository: activity presence cannot survive a killed process; durable Ready/results can.
        let stored = sessions
        if !stored.isEmpty { sessions = stored.mapValues { room in var s = room; s.connections = [:]; return s } }
    }
    func connect() async throws -> String { uid }
    func profile(index: Int, hebrew: Bool, avatar: Int, character: String) async throws -> MPIdentity { .init(id: uid, name: MPNames.candidate(index, hebrew: hebrew, character: character), avatar: avatar, characterId: character) }
    func get(_ kind: MPSessionKind, _ code: String) async throws -> MPSession? { sessions[kind.path + "/" + code] }
    func openRooms() async throws -> [(MPSessionKind, String)] { sessions.values.map { ($0.kind, $0.code) } }
    func reserve(_ kind: MPSessionKind, _ code: String) async throws {
        if sessions.values.filter({ $0.kind == kind && !$0.complete && $0.code != code }).count >= 3 { throw MPError.limit }
    }
    func create(_ session: MPSession) async throws -> MPSession {
        try await reserve(session.kind, session.code)
        // Android: a code already used is refused ("Code already used; try again.").
        if sessions[session.id] != nil { throw MPError.duplicate }
        var s = session
        let now = MPClock.now
        s.createdAt = now; s.lastActivityAt = now
        save(s)
        return s
    }
    func mutate(_ kind: MPSessionKind, _ code: String, _ change: @escaping (MPSession) throws -> MPSession) async throws -> MPSession {
        guard let s = sessions[kind.path + "/" + code] else { throw MPError.missing }
        var n = try change(s)
        // Android: only a real change (presence aside) is activity.
        var probe = n
        probe.connections = s.connections
        if probe != s { n.lastActivityAt = MPClock.now }
        save(n)
        return n
    }
    private func save(_ s: MPSession) {
        var all = sessions
        all[s.id] = s
        sessions = all
        // Android LocalPongRepository: a listener may change the room re-entrantly (auto-start); later listeners then receive
        // that newer room and must not be handed this older one afterwards.
        let n = (saves[s.id] ?? 0) + 1
        saves[s.id] = n
        let callbacks = Array(listeners[s.id]?.values ?? [:].values)
        for callback in callbacks where saves[s.id] == n { callback(.success(s)) }
    }
    func observe(_ kind: MPSessionKind, _ code: String, _ changed: @escaping (Result<MPSession, Error>) -> Void) -> MPSubscription {
        let key = kind.path + "/" + code, token = UUID(); listeners[key, default: [:]][token] = changed
        if let s = sessions[key] { changed(.success(s)) }
        return MPSubscription { [weak self] in self?.listeners[key]?[token] = nil }
    }
    func presence(_ kind: MPSessionKind, _ code: String) -> MPSubscription {
        let key = kind.path + "/" + code
        if var s = sessions[key] { s.connections[uid] = ["0": true]; save(s) }
        return MPSubscription { [weak self] in guard let self, var s = self.sessions[key] else { return }; s.connections[self.uid] = nil; self.save(s) }
    }
    func connection(_ changed: @escaping (Bool) -> Void) -> MPSubscription { changed(true); return .init() }
    private func stored(_ key: String) -> MPWire { defaults.dictionary(forKey: "modern.live." + key) ?? [:] }
    func watchLive(_ id: String, actions: Bool, _ changed: @escaping (MPWire) -> Void, _ failed: @escaping (Error) -> Void) -> MPSubscription {
        let key = id + (actions ? "/actions" : "/checkpoint"), token = UUID(); watchers[key, default: [:]][token] = changed
        changed(stored(key))
        return MPSubscription { [weak self] in self?.watchers[key]?[token] = nil }
    }
    func checkpoint(_ id: String, _ value: MPWire) async throws {
        // Android: a long local match keeps its room active (at most one stamp a minute).
        if let kindPath = value["kind"] as? String, let code = value["code"] as? String,
           let kind = MPSessionKind.allCases.first(where: { $0.path == kindPath }),
           var room = sessions[kind.path + "/" + code], MPClock.now - room.lastActivityAt >= 60_000 {
            room.lastActivityAt = MPClock.now
            save(room)
        }
        let key = id + "/checkpoint"; var w = value
        w["revision"] = MPCodec.number(stored(key), "revision") + 1
        w["authority"] = uid
        // UserDefaults raises on a value it cannot store (e.g. NSNull): such a checkpoint is skipped, never a crash.
        if PropertyListSerialization.propertyList(w, isValidFor: .binary) { defaults.set(w, forKey: "modern.live." + key) }
        Array(watchers[key]?.values ?? [:].values).forEach { $0(w) }
    }
    func action(_ id: String, _ sequence: Int64, _ value: MPWire) async throws { throw MPError.permission }
    func leave(_ s: MPSession, delete: Bool) async throws {
        if let current = sessions[s.id], current.kind == .friendly, !MPRules.canFinishFriendly(current, actor: uid) { throw MPError.permission }
        drop(s)
    }
    func cleanup() async throws {
        for s in sessions.values where s.expired(MPClock.now) { try await leave(s, delete: true) }
        // Android PlayActivity.refreshRooms: completed local rooms are dismissed, not kept as history.
        for s in sessions.values where s.complete { remove(s) }
    }
    /// Android `LocalPongRepository.remove`: drops a completed local room and its checkpoints.
    func remove(_ s: MPSession) { drop(s) }
    private func drop(_ s: MPSession) {
        var all = sessions
        all[s.id] = nil
        sessions = all
        for id in s.matches.keys { defaults.removeObject(forKey: "modern.live." + id + "/checkpoint") }
    }
}

#if MINIK_PING_PONG && canImport(FirebaseDatabase) && canImport(FirebaseAuth)
import FirebaseCore
import FirebaseAuth
import FirebaseDatabase

@MainActor final class MPFirebaseRepository: MPRepository {
    /// Android `FirebasePongRepository` (MinikCrossPong): the named Firebase app `minik-cross-pong`, root `minikCrossPong`.
    static let appName = "minik-cross-pong"
    static let bundleIdentifier = "com.appsbybros.minik.crosspong"
    private let auth: Auth, database: Database, root: DatabaseReference
    private var presenceSlot = 0
    private var touched: [String: Int64] = [:]
    let online = true
    var uid: String { auth.currentUser?.uid ?? "" }
    static func configured() -> MPFirebaseRepository? {
        if let app = FirebaseApp.app(name: appName) { return .init(app: app) }
        guard let path = Bundle.main.path(forResource: "GoogleService-Info", ofType: "plist"), let options = FirebaseOptions(contentsOfFile: path),
            options.bundleID == bundleIdentifier, options.projectID == "minikswish", Bundle.main.bundleIdentifier == options.bundleID else { return nil }
        FirebaseApp.configure(name: appName, options: options)
        return FirebaseApp.app(name: appName).map { .init(app: $0) }
    }
    private init(app: FirebaseApp) {
        auth = Auth.auth(app: app); database = Database.database(app: app, url: "https://minikswish-default-rtdb.europe-west1.firebasedatabase.app/")
        // Multi Ping Pong owns ONLY this database subtree; never minikPingPong/ or tripleShot (Android PONG_ROOT).
        root = database.reference().child("minikCrossPong")
    }
    func connect() async throws -> String { if uid.isEmpty { _ = try await auth.signInAnonymously() }; return uid }
    private func ref(_ kind: MPSessionKind, _ code: String) -> DatabaseReference { root.child(kind.path).child(code) }
    private func transaction(_ ref: DatabaseReference, _ transform: @escaping (Any?) throws -> Any?) async throws -> Any? {
        try await withCheckedThrowingContinuation { continuation in
            var rejection: Error?
            ref.runTransactionBlock({ data in
                do { rejection = nil; data.value = try transform(data.value); return TransactionResult.success(withValue: data) }
                catch { rejection = error; return TransactionResult.abort() }
            }, andCompletionBlock: { error, committed, snapshot in
                if let error { continuation.resume(throwing: error) }
                else if !committed { continuation.resume(throwing: rejection ?? MPError.permission) }
                else { continuation.resume(returning: snapshot?.value) }
            }, withLocalEvents: false)
        }
    }
    func profile(index: Int, hebrew: Bool, avatar: Int, character: String) async throws -> MPIdentity {
        let id = uid
        for attempt in 0..<21 {
            let name = MPNames.candidate(index, hebrew: hebrew, suffix: attempt == 0 ? 0 : Int.random(in: 1...9999), character: character)
            do {
                _ = try await transaction(root.child("nicknames").child(name)) { value in
                    if let existing = value as? String, existing != id { throw MPError.duplicate }; return id
                }
                let identity = MPIdentity(id: id, name: name, avatar: avatar, characterId: character)
                var w = try MPCodec.encode(identity); w["updatedAt"] = ServerValue.timestamp()
                try await root.child("profiles").child(id).setValue(w); return identity
            } catch MPError.duplicate { continue }
        }; throw MPError.duplicate
    }
    func get(_ kind: MPSessionKind, _ code: String) async throws -> MPSession? {
        let snapshot = try await ref(kind, code).getData(); return snapshot.exists() ? try MPCodec.session(snapshot.value) : nil
    }
    func openRooms() async throws -> [(MPSessionKind, String)] {
        let data = try await root.child("openSlots").child(uid).getData()
        return MPSessionKind.allCases.flatMap { kind in MPCodec.map(data.childSnapshot(forPath: kind.path).value).values.compactMap { ($0 as? String).map { (kind, $0) } } }
    }
    func reserve(_ kind: MPSessionKind, _ code: String) async throws {
        let slots = root.child("openSlots").child(uid).child(kind.path), id = uid
        let before = try await slots.getData()
        for (key, value) in MPCodec.map(before.value) {
            guard let oldCode = value as? String else { continue }; let old = try await get(kind, oldCode)
            if old == nil || old!.complete || !old!.human(id) { try await slots.child(key).removeValue() }
        }
        _ = try await transaction(slots) { value in
            var w = MPCodec.map(value); if w.values.contains(where: { ($0 as? String) == code }) { return w }
            guard let free = (0...2).first(where: { w[String($0)] == nil }) else { throw MPError.limit }; w[String(free)] = code; return w
        }
    }
    private func release(_ kind: MPSessionKind, _ code: String) async throws {
        _ = try await transaction(root.child("openSlots").child(uid).child(kind.path)) { MPCodec.map($0).filter { ($0.value as? String) != code } }
    }
    func create(_ session: MPSession) async throws -> MPSession {
        guard session.host == uid else { throw MPError.permission }; var next = session
        for _ in 0..<6 {
            try await reserve(next.kind, next.code)
            var w = try MPCodec.session(next); w["createdAt"] = ServerValue.timestamp(); w["lastActivityAt"] = ServerValue.timestamp()
            do { let result = try await transaction(ref(next.kind, next.code)) { value in if value != nil && !(value is NSNull) { throw MPError.duplicate }; return w }; return try MPCodec.session(result) }
            catch MPError.duplicate { try await release(next.kind, next.code); next.code = MPRules.code() }
        }; throw MPError.duplicate
    }
    func mutate(_ kind: MPSessionKind, _ code: String, _ change: @escaping (MPSession) throws -> MPSession) async throws -> MPSession {
        let result = try await transaction(ref(kind, code)) { value in
            guard value != nil && !(value is NSNull) else { return value }
            let old = try MPCodec.session(value), next = try change(old); var w = try MPCodec.session(next)
            var semantic = next; semantic.connections = old.connections
            if semantic != old { w["lastActivityAt"] = ServerValue.timestamp() }; return w
        }
        guard result != nil && !(result is NSNull) else { throw MPError.missing }; return try MPCodec.session(result)
    }
    func observe(_ kind: MPSessionKind, _ code: String, _ changed: @escaping (Result<MPSession, Error>) -> Void) -> MPSubscription {
        watch(ref(kind, code), { raw in if raw.isEmpty { changed(.failure(MPError.missing)) } else { changed(Result { try MPCodec.session(raw) }) } }, { changed(.failure($0)) })
    }
    private func watch(_ ref: DatabaseReference, _ changed: @escaping (MPWire) -> Void, _ failed: @escaping (Error) -> Void) -> MPSubscription {
        let handle = ref.observe(.value, with: { snapshot in changed(MPCodec.map(snapshot.value)) }, withCancel: failed)
        return .init { ref.removeObserver(withHandle: handle) }
    }
    func connection(_ changed: @escaping (Bool) -> Void) -> MPSubscription {
        let r = database.reference(withPath: ".info/connected"), handle = r.observe(.value) { changed(($0.value as? Bool) == true) }
        return .init { r.removeObserver(withHandle: handle) }
    }
    /// Android `FirebasePongRepository.receptionPreferences`: `minikCrossPong/receptionPreferences/<uid>` = {version 1, slow}.
    func receptionPreferences(_ players: Set<String>, _ changed: @escaping ([String: Bool]) -> Void, _ failed: @escaping (String) -> Void) -> MPSubscription {
        let note = "Ball assistance could not be shared. The match uses normal speed until it connects."
        var values: [String: Bool] = [:]
        var handles: [(DatabaseReference, UInt)] = []
        if players.contains(uid) {
            root.child("receptionPreferences").child(uid).setValue(["version": 1, "slow": MPPreferences().receptionSlow] as [String: Any]) { error, _ in if error != nil { failed(note) } }
        }
        for player in players.sorted() {
            let ref = root.child("receptionPreferences").child(player)
            let handle = ref.observe(.value, with: { snapshot in
                let w = MPCodec.map(snapshot.value)
                if CrossWire.number(w, "version") == 1, let slow = w["slow"] as? Bool { values[player] = slow } else { values[player] = nil }
                changed(values)
            }, withCancel: { _ in values[player] = nil; changed(values); failed(note) })
            handles.append((ref, handle))
        }
        return .init { handles.forEach { $0.0.removeObserver(withHandle: $0.1) } }
    }
    func presence(_ kind: MPSessionKind, _ code: String) -> MPSubscription {
        let r = ref(kind, code).child("connections").child(uid).child(String(presenceSlot % 16)); presenceSlot += 1
        ref(kind, code).child("lastActivityAt").setValue(ServerValue.timestamp())
        var closed = false
        let online = connection { connected in guard connected && !closed else { return }; r.onDisconnectRemoveValue { error, _ in if error == nil && !closed { r.setValue(true) } } }
        return .init { closed = true; online.close(); r.removeValue(); r.cancelDisconnectOperations() }
    }
    func watchLive(_ id: String, actions: Bool, _ changed: @escaping (MPWire) -> Void, _ failed: @escaping (Error) -> Void) -> MPSubscription {
        watch(root.child("live").child(id).child(actions ? "actions" : "checkpoint"), { w in
            // Android sorts by sequence; the cross table also orders different senders' strikes by play order (rally, hit), which
            // a classic protocol-1 action (no rallyId/hitIndex) leaves at sequence order.
            if actions { w.values.flatMap { MPCodec.map($0).values }.map { MPCodec.map($0) }.sorted { MPRepositoryOrder.before($0, $1) }.forEach(changed) }
            else { changed(w) }
        }, failed)
    }
    func checkpoint(_ id: String, _ value: MPWire) async throws {
        let owner = uid
        if let path = value["kind"] as? String, MPSessionKind.allCases.contains(where: { $0.path == path }), let code = value["code"] as? String {
            let key = path + "/" + code, now = MPClock.now
            if now - (touched[key] ?? 0) >= 60_000 { touched[key] = now; try await root.child(key).child("lastActivityAt").setValue(ServerValue.timestamp()) }
        }
        _ = try await transaction(root.child("live").child(id).child("checkpoint")) { old in
            var w = value; w["revision"] = MPCodec.number(MPCodec.map(old), "revision") + 1; w["serverAt"] = ServerValue.timestamp(); w["authority"] = owner; return w
        }
    }
    func action(_ id: String, _ sequence: Int64, _ value: MPWire) async throws {
        var w = value; w["sender"] = uid; w["sequence"] = sequence; w["serverAt"] = ServerValue.timestamp()
        try await root.child("live").child(id).child("actions").child(uid).child(String(sequence % 16)).setValue(w)
    }
    func leave(_ session: MPSession, delete: Bool) async throws {
        let actor = uid; var matches: [String] = []
        _ = try await transaction(ref(session.kind, session.code)) { value in
            guard value != nil && !(value is NSNull) else { return nil }; let s = try MPCodec.session(value); matches = Array(s.matches.keys)
            // Either friendly participant may Finish a saved or playing game (Android canFinishFriendly).
            if s.kind == .friendly { guard MPRules.canFinishFriendly(s, actor: actor) else { throw MPError.permission }; return nil }
            if delete { guard MPRules.canDelete(s, actor: actor) else { throw MPError.permission }; return nil }
            var w = try MPCodec.session(MPRules.leave(s, actor: actor)); w["lastActivityAt"] = ServerValue.timestamp(); return w
        }
        if delete || session.kind == .friendly { for id in matches { try await root.child("live").child(id).removeValue() } }
        try await release(session.kind, session.code)
    }
    func cleanup() async throws {
        let offset: Int64 = await withCheckedContinuation { continuation in database.reference(withPath: ".info/serverTimeOffset").observeSingleEvent(of: .value) { continuation.resume(returning: ($0.value as? NSNumber)?.int64Value ?? 0) } }
        let now = MPClock.now + offset, cutoff = (now / 60_000) * 60_000 - 14 * 86_400_000
        for kind in MPSessionKind.allCases {
            var cursor: (Double, String)?
            repeat {
                var query = root.child(kind.path).queryOrdered(byChild: "lastActivityAt").queryEnding(atValue: cutoff).queryLimited(toFirst: 50)
                if let cursor { query = query.queryStarting(afterValue: cursor.0, childKey: cursor.1) }
                let page = try await query.getData(), nodes = page.children.allObjects.compactMap { $0 as? DataSnapshot }
                for node in nodes {
                    guard let s = try? MPCodec.session(node.value), s.expired(now), s.connections.values.allSatisfy({ $0.isEmpty }) else { continue }
                    var deletes: MPWire = [s.id: NSNull()]; for id in s.matches.keys { deletes["live/" + id] = NSNull() }
                    do { try await root.updateChildValues(deletes) }
                    catch { if let current = try await get(kind, s.code), current.expired(now), current.connections.values.allSatisfy({ $0.isEmpty }) { throw error } }
                }
                cursor = nodes.count == 50 ? nodes.last.map { ((($0.childSnapshot(forPath: "lastActivityAt").value as? NSNumber)?.doubleValue ?? 0), $0.key) } : nil
            } while cursor != nil
        }
    }
}
#endif
