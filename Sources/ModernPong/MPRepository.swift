import Foundation

typealias MPWire = [String: Any]
enum MPCodec {
    static func map(_ value: Any?) -> MPWire {
        if let value = value as? MPWire { return value }
        if let value = value as? [Any] { return Dictionary(uniqueKeysWithValues: value.enumerated().compactMap { $0.element is NSNull ? nil : (String($0.offset), $0.element) }) }
        return [:]
    }
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
                return round
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
final class MPSubscription {
    private var cancel: (() -> Void)?
    init(_ cancel: @escaping () -> Void = {}) { self.cancel = cancel }
    func close() { cancel?(); cancel = nil }
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
    /// Android `PongRepository.receptionPreferences`: publishes this player's slow-motion choice and follows the
    /// other humans' choices (`minikPingPong/receptionPreferences/<uid>` = {version: 1, slow}).
    func receptionPreferences(_ players: Set<String>, _ changed: @escaping ([String: Bool]) -> Void, _ failed: @escaping (Error) -> Void) -> MPSubscription
    /// Android `PongRepository.rank`: another player's published colour (`profiles/<uid>/{rankPoints, rankLevel}`).
    func rank(_ player: String, _ changed: @escaping (MPRankBadge) -> Void) -> MPSubscription
    /// Android `PongRepository.publishRank`: shares this player's colour on their profile.
    func publishRank(_ badge: MPRankBadge)
}
extension MPRepository {
    /// Local rooms have no shared colours: an opponent reads as White and nothing is published (Android defaults).
    func rank(_ player: String, _ changed: @escaping (MPRankBadge) -> Void) -> MPSubscription { changed(MPRankBadge()); return MPSubscription() }
    func publishRank(_ badge: MPRankBadge) {}
    /// Local rooms share no preferences (Android's default implementation).
    func receptionPreferences(_ players: Set<String>, _ changed: @escaping ([String: Bool]) -> Void, _ failed: @escaping (Error) -> Void) -> MPSubscription {
        changed([:]); return MPSubscription()
    }
}

/// Local sessions have their own storage. A Firebase outage never overwrites a cloud room.
@MainActor final class MPLocalRepository: MPRepository {
    let online = false; let uid: String; private let defaults: UserDefaults
    private var sessions: [String: MPSession], listeners: [String: [UUID: (Result<MPSession, Error>) -> Void]] = [:]
    private var live: [String: MPWire] = [:], watchers: [String: [UUID: (MPWire) -> Void]] = [:]
    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults; uid = defaults.string(forKey: "modern.local.uid") ?? "local_" + UUID().uuidString
        defaults.set(uid, forKey: "modern.local.uid")
        sessions = defaults.data(forKey: "modern.local.rooms").flatMap { try? JSONDecoder().decode([String: MPSession].self, from: $0) } ?? [:]
    }
    func connect() async throws -> String { uid }
    func profile(index: Int, hebrew: Bool, avatar: Int, character: String) async throws -> MPIdentity { .init(id: uid, name: MPNames.candidate(index, hebrew: hebrew, character: character), avatar: avatar, characterId: character) }
    func get(_ kind: MPSessionKind, _ code: String) async throws -> MPSession? { sessions[kind.path + "/" + code] }
    func openRooms() async throws -> [(MPSessionKind, String)] { sessions.values.map { ($0.kind, $0.code) } }
    func reserve(_ kind: MPSessionKind, _ code: String) async throws {
        if sessions.values.filter({ $0.kind == kind && !$0.complete && $0.code != code }).count >= 3 { throw MPError.limit }
    }
    func create(_ s: MPSession) async throws -> MPSession { try await reserve(s.kind, s.code); sessions[s.id] = s; save(s); return s }
    /// Android `ColorChallengeActivity.start`: a qualification room is stored without taking a saved-games slot.
    func store(_ s: MPSession) -> MPSession { sessions[s.id] = s; save(s); return s }
    func mutate(_ kind: MPSessionKind, _ code: String, _ change: @escaping (MPSession) throws -> MPSession) async throws -> MPSession {
        guard let s = sessions[kind.path + "/" + code] else { throw MPError.missing }; var n = try change(s); n.lastActivityAt = MPClock.now; sessions[n.id] = n; save(n); return n
    }
    private func save(_ s: MPSession) {
        defaults.set(try? JSONEncoder().encode(sessions), forKey: "modern.local.rooms")
        let callbacks = Array(listeners[s.id]?.values ?? [:].values); callbacks.forEach { $0(.success(s)) }
    }
    func observe(_ kind: MPSessionKind, _ code: String, _ changed: @escaping (Result<MPSession, Error>) -> Void) -> MPSubscription {
        let key = kind.path + "/" + code, token = UUID(); listeners[key, default: [:]][token] = changed
        if let s = sessions[key] { changed(.success(s)) }
        return MPSubscription { [weak self] in self?.listeners[key]?[token] = nil }
    }
    func presence(_ kind: MPSessionKind, _ code: String) -> MPSubscription {
        let key = kind.path + "/" + code
        if var s = sessions[key] { s.connections[uid] = ["0": true]; sessions[key] = s; save(s) }
        return MPSubscription { [weak self] in guard let self, var s = self.sessions[key] else { return }; s.connections[self.uid] = nil; self.sessions[key] = s; self.save(s) }
    }
    func connection(_ changed: @escaping (Bool) -> Void) -> MPSubscription { changed(true); return .init() }
    func watchLive(_ id: String, actions: Bool, _ changed: @escaping (MPWire) -> Void, _ failed: @escaping (Error) -> Void) -> MPSubscription {
        let key = id + (actions ? "/actions" : "/checkpoint"), token = UUID(); watchers[key, default: [:]][token] = changed
        changed(live[key] ?? defaults.dictionary(forKey: "modern.live." + key) ?? [:])
        return MPSubscription { [weak self] in self?.watchers[key]?[token] = nil }
    }
    func checkpoint(_ id: String, _ value: MPWire) async throws {
        let key = id + "/checkpoint"; var w = value
        w["revision"] = MPCodec.number(live[key] ?? defaults.dictionary(forKey: "modern.live." + key) ?? [:], "revision") + 1
        w["authority"] = uid; live[key] = w; defaults.set(w, forKey: "modern.live." + key)
        Array(watchers[key]?.values ?? [:].values).forEach { $0(w) }
    }
    func action(_ id: String, _ sequence: Int64, _ value: MPWire) async throws { throw MPError.permission }
    func leave(_ s: MPSession, delete: Bool) async throws {
        if let current = sessions[s.id], current.kind == .friendly, !MPRules.canFinishFriendly(current, actor: uid) { throw MPError.permission }
        sessions[s.id] = nil; defaults.set(try? JSONEncoder().encode(sessions), forKey: "modern.local.rooms")
        for id in s.matches.keys { defaults.removeObject(forKey: "modern.live." + id + "/checkpoint") }
    }
    func cleanup() async throws {
        for s in sessions.values where s.expired(MPClock.now) { try await leave(s, delete: true) }
        // Android PlayActivity.refreshRooms: completed local rooms are dismissed, not kept as history.
        for s in sessions.values where s.complete { remove(s) }
    }
    /// Android `LocalPongRepository.remove`: drops a completed local room and its checkpoints.
    func remove(_ s: MPSession) {
        sessions[s.id] = nil; defaults.set(try? JSONEncoder().encode(sessions), forKey: "modern.local.rooms")
        for id in s.matches.keys { defaults.removeObject(forKey: "modern.live." + id + "/checkpoint") }
    }
}

#if MINIK_PING_PONG && canImport(FirebaseDatabase) && canImport(FirebaseAuth)
import os
import FirebaseCore
import FirebaseAuth
import FirebaseDatabase

@MainActor final class MPFirebaseRepository: MPRepository {
    static let appName = "minik-ping-pong-ios"
    fileprivate nonisolated static let log = Logger(subsystem: "com.appsbybros.minik.pingpong", category: "ModernPongRepository")
    private let auth: Auth, database: Database, root: DatabaseReference
    private var presenceSlot = 0
    private var touched: [String: Int64] = [:]
    let online = true
    var uid: String { auth.currentUser?.uid ?? "" }
    static func configured() -> MPFirebaseRepository? {
        if let app = FirebaseApp.app(name: appName) { return .init(app: app) }
        guard let path = Bundle.main.path(forResource: "GoogleService-Info", ofType: "plist"), let options = FirebaseOptions(contentsOfFile: path),
            options.bundleID == "com.appsbybros.minik.pingpong", options.projectID == "minikswish", Bundle.main.bundleIdentifier == options.bundleID else { return nil }
        FirebaseApp.configure(name: appName, options: options)
        return FirebaseApp.app(name: appName).map { .init(app: $0) }
    }
    private init(app: FirebaseApp) {
        auth = Auth.auth(app: app); database = Database.database(app: app, url: "https://minikswish-default-rtdb.europe-west1.firebasedatabase.app/")
        root = database.reference().child("minikPingPong")
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
                // Android `saveProfile` updates the profile's children, so the shared colour (rankPoints, rankLevel)
                // survives a nickname or avatar change; a blank character is removed.
                var w = try MPCodec.encode(identity); w["updatedAt"] = ServerValue.timestamp()
                if character.isEmpty { w["characterId"] = NSNull() }
                try await root.child("profiles").child(id).updateChildValues(w); return identity
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
    func rank(_ player: String, _ changed: @escaping (MPRankBadge) -> Void) -> MPSubscription {
        let ref = root.child("profiles").child(player)
        let handle = ref.observe(.value, with: { snapshot in changed(MPRankBadge(wire: MPCodec.map(snapshot.value))) },
                                 withCancel: { error in MPFirebaseRepository.log.warning("Rank unavailable: \(String(describing: error), privacy: .public)") })
        return .init { ref.removeObserver(withHandle: handle) }
    }
    func publishRank(_ badge: MPRankBadge) {
        guard !uid.isEmpty else { return }
        root.child("profiles").child(uid).updateChildValues(badge.wire) { error, _ in
            if let error { MPFirebaseRepository.log.warning("Rank sharing deferred: \(String(describing: error), privacy: .public)") }
        }
    }
    /// Android `transactionalPresenceWrite` (a8d344b): a plain setValue/removeValue at a descendant cancels the room's
    /// pending transaction (a Ready or a result), so presence and activity stamps are written as transactions too.
    private nonisolated static func transactionalPresenceWrite(_ ref: DatabaseReference, _ value: Any?) {
        ref.runTransactionBlock({ data in data.value = value; return TransactionResult.success(withValue: data) }, andCompletionBlock: { error, _, _ in
            if let error { MPFirebaseRepository.log.warning("Presence update deferred: \(String(describing: error), privacy: .public)") }
        }, withLocalEvents: false)
    }
    func receptionPreferences(_ players: Set<String>, _ changed: @escaping ([String: Bool]) -> Void, _ failed: @escaping (Error) -> Void) -> MPSubscription {
        var values: [String: Bool] = [:]
        var watches: [(DatabaseReference, DatabaseHandle)] = []
        if players.contains(uid) {
            let own: [String: Any] = ["version": 1, "slow": MPReceptionSettings.slow]
            root.child("receptionPreferences").child(uid).setValue(own) { error, _ in if error != nil { failed(MPError.assistance) } }
        }
        for player in players.sorted() {
            let ref = root.child("receptionPreferences").child(player)
            let handle = ref.observe(.value, with: { snapshot in
                let w = MPCodec.map(snapshot.value)
                if (w["version"] as? NSNumber)?.intValue == 1, let slow = MPReceptionAssist.flag(w["slow"]) { values[player] = slow } else { values[player] = nil }
                changed(values)
            }, withCancel: { _ in values[player] = nil; changed(values); failed(MPError.assistance) })
            watches.append((ref, handle))
        }
        return .init { for (ref, handle) in watches { ref.removeObserver(withHandle: handle) } }
    }
    func presence(_ kind: MPSessionKind, _ code: String) -> MPSubscription {
        let r = ref(kind, code).child("connections").child(uid).child(String(presenceSlot % 16)); presenceSlot += 1
        touch(kind, code)
        var closed = false
        let online = connection { connected in
            guard connected && !closed else { return }
            r.onDisconnectRemoveValue { error, _ in if error == nil && !closed { MPFirebaseRepository.transactionalPresenceWrite(r, true) } }
        }
        return .init { closed = true; online.close(); MPFirebaseRepository.transactionalPresenceWrite(r, nil); r.cancelDisconnectOperations() }
    }
    /// Android `FirebasePongRepository.touch`: at most one activity stamp per room and minute, written transactionally.
    private func touch(_ kind: MPSessionKind, _ code: String) {
        let key = kind.path + "/" + code, now = MPClock.now
        guard now - (touched[key] ?? 0) >= 60_000 else { return }
        touched[key] = now; MPFirebaseRepository.transactionalPresenceWrite(ref(kind, code).child("lastActivityAt"), ServerValue.timestamp())
    }
    func watchLive(_ id: String, actions: Bool, _ changed: @escaping (MPWire) -> Void, _ failed: @escaping (Error) -> Void) -> MPSubscription {
        watch(root.child("live").child(id).child(actions ? "actions" : "checkpoint"), { w in
            if actions { w.values.flatMap { MPCodec.map($0).values }.map { MPCodec.map($0) }.sorted { MPCodec.number($0, "sequence") < MPCodec.number($1, "sequence") }.forEach(changed) }
            else { changed(w) }
        }, failed)
    }
    func checkpoint(_ id: String, _ value: MPWire) async throws {
        let owner = uid
        // Android FirebasePongRepository.touch is fire-and-forget: a failed activity stamp never fails the checkpoint.
        if let path = value["kind"] as? String, let kind = MPSessionKind.allCases.first(where: { $0.path == path }), let code = value["code"] as? String { touch(kind, code) }
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
