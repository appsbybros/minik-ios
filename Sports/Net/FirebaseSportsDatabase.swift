#if canImport(FirebaseCore) && canImport(FirebaseAuth) && canImport(FirebaseDatabase)
import FirebaseAuth
import FirebaseCore
import FirebaseDatabase
import Foundation

/// Firebase Realtime Database transport for SportsOnline. Paths are relative to the database
/// root and always start with the isolated `minikSquash/` or `minikBeachVolley/` namespace.
@MainActor
final class FirebaseSportsDatabase: SportsDatabase {
    private static var clients: [String: (Auth, Database)] = [:]

    private let auth: Auth
    private let root: DatabaseReference
    private var handles: [Int: [(DatabaseReference, DatabaseHandle)]] = [:]
    private var queries: [Int: (DatabaseQuery, DatabaseHandle)] = [:]
    private var nextToken = 0

    private init(auth: Auth, database: Database) {
        self.auth = auth
        self.root = database.reference()
    }

    /// Android SportsOnline.open: the registered app on ordinary launches; the local emulators
    /// only for an explicit debug QA launch (and then only on 127.0.0.1 or 10.0.2.2).
    static func connect(host: String, emulator: Bool) throws -> FirebaseSportsDatabase {
        guard let path = Bundle.main.path(forResource: "GoogleService-Info", ofType: "plist"),
              let options = FirebaseOptions(contentsOfFile: path) else {
            throw SportsOnlineError.message("Production online registration is not activated.")
        }
        if emulator && host != "127.0.0.1" && host != "10.0.2.2" {
            throw SportsOnlineError.message("Only the local emulator is permitted in this build.")
        }
        let name = emulator ? "minik-sports-emulator" : "minik-sports-production"
        let url: String
        if emulator {
            options.projectID = "demo-minik-sports"
            url = "https://demo-minik-sports.firebaseio.com"
        } else {
            let databaseURL = options.databaseURL ?? ""
            let projectID = options.projectID ?? ""
            guard !options.googleAppID.contains("emulator"), !projectID.isEmpty, databaseURL.hasPrefix("https://") else {
                throw SportsOnlineError.message("The app's real Firebase registration is missing.")
            }
            url = databaseURL
        }
        if let pair = clients[name] { return FirebaseSportsDatabase(auth: pair.0, database: pair.1) }
        if FirebaseApp.app(name: name) == nil { FirebaseApp.configure(name: name, options: options) }
        guard let app = FirebaseApp.app(name: name) else {
            throw SportsOnlineError.message("The app's real Firebase registration is missing.")
        }
        let auth = Auth.auth(app: app)
        let database = Database.database(app: app, url: url)
        if emulator {
            auth.useEmulator(withHost: host, port: 9099)
            database.useEmulator(withHost: host, port: 9005)
        }
        clients[name] = (auth, database)
        return FirebaseSportsDatabase(auth: auth, database: database)
    }

    var serverTimestamp: Any { return ServerValue.timestamp() }

    func signIn(_ completion: @escaping @MainActor (Result<String, Error>) -> Void) {
        if let user = auth.currentUser {
            completion(.success(user.uid))
            return
        }
        let auth = self.auth
        Task { @MainActor in
            do {
                let result = try await auth.signInAnonymously()
                completion(.success(result.user.uid))
            } catch {
                completion(.failure(error))
            }
        }
    }

    func set(_ path: String, _ value: Any, _ completion: (@MainActor (Error?) -> Void)?) {
        let clean = NodeValue.sanitized(value)
        root.child(path).setValue(clean) { error, _ in
            guard let completion = completion else { return }
            Task { @MainActor in completion(error) }
        }
    }

    func update(_ path: String, _ values: [String: Any], _ completion: (@MainActor (Error?) -> Void)?) {
        let clean = (NodeValue.sanitized(values) as? [String: Any]) ?? values
        root.child(path).updateChildValues(clean) { error, _ in
            guard let completion = completion else { return }
            Task { @MainActor in completion(error) }
        }
    }

    func get(_ path: String, _ completion: @escaping @MainActor (Error?, Any?, Bool) -> Void) {
        let ref = root.child(path)
        Task { @MainActor in
            do {
                let snapshot = try await ref.getData()
                completion(nil, snapshot.value, snapshot.exists())
            } catch {
                completion(error, nil, false)
            }
        }
    }

    private func register(_ entries: [(DatabaseReference, DatabaseHandle)]) -> Int {
        nextToken += 1
        handles[nextToken] = entries
        return nextToken
    }

    func observe(_ path: String, _ onChange: @escaping @MainActor (Any?) -> Void, _ onCancel: @escaping @MainActor (Error) -> Void) -> Int {
        let ref = root.child(path)
        let handle = ref.observe(.value, with: { snapshot in
            let value = snapshot.value
            Task { @MainActor in onChange(value) }
        }, withCancel: { error in
            Task { @MainActor in onCancel(error) }
        })
        return register([(ref, handle)])
    }

    func observeChildren(_ path: String, _ onChild: @escaping @MainActor (String, Any?) -> Void, _ onCancel: @escaping @MainActor (Error) -> Void) -> Int {
        let ref = root.child(path)
        let added = ref.observe(.childAdded, with: { snapshot in
            let key = snapshot.key
            let value = snapshot.value
            Task { @MainActor in onChild(key, value) }
        }, withCancel: { error in
            Task { @MainActor in onCancel(error) }
        })
        let changed = ref.observe(.childChanged, with: { snapshot in
            let key = snapshot.key
            let value = snapshot.value
            Task { @MainActor in onChild(key, value) }
        }, withCancel: { error in
            Task { @MainActor in onCancel(error) }
        })
        return register([(ref, added), (ref, changed)])
    }

    func removeObserver(_ token: Int) {
        if let (query, handle) = queries.removeValue(forKey: token) {
            query.removeObserver(withHandle: handle)
            return
        }
        guard let entries = handles.removeValue(forKey: token) else { return }
        for (ref, handle) in entries { ref.removeObserver(withHandle: handle) }
    }

    func transaction(_ path: String, _ update: @escaping @Sendable (Any?) -> TransactionDecision, _ completion: @escaping @MainActor (Error?, Bool, Any?) -> Void) {
        root.child(path).runTransactionBlock({ data in
            let current: Any? = data.value is NSNull ? nil : data.value
            switch update(current) {
            case .abort:
                return TransactionResult.abort()
            case .commit(let value):
                data.value = NodeValue.sanitized(value)
                return TransactionResult.success(withValue: data)
            }
        }, andCompletionBlock: { error, committed, snapshot in
            let value = snapshot?.value
            Task { @MainActor in completion(error, committed, value) }
        }, withLocalEvents: true)
    }

    func onDisconnectSet(_ path: String, _ value: Any) {
        root.child(path).onDisconnectSetValue(value)
    }

    func remove(_ path: String) {
        root.child(path).removeValue()
    }

    func observeQuery(_ path: String, orderBy child: String, startAt start: Double, limit: Int,
                      _ onChange: @escaping @MainActor ([(String, Any?)]) -> Void, _ onCancel: @escaping @MainActor (Error) -> Void) -> Int {
        let ref = root.child(path)
        let query = ref.queryOrdered(byChild: child).queryStarting(atValue: start).queryLimited(toFirst: UInt(max(limit, 1)))
        let handle = query.observe(.value, with: { snapshot in
            var rows: [(String, Any?)] = []
            for case let item as DataSnapshot in snapshot.children {
                rows.append((item.key, item.value))
            }
            let ordered = rows
            Task { @MainActor in onChange(ordered) }
        }, withCancel: { error in
            Task { @MainActor in onCancel(error) }
        })
        nextToken += 1
        queries[nextToken] = (query, handle)
        return nextToken
    }
}
#endif
