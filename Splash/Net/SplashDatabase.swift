import Foundation

/// The Realtime Database operations Android OnlineSession uses, so the room protocol stays
/// independent of the Firebase SDK (and the app runs offline when Firebase is not configured).
enum SplashOnlineError: LocalizedError {
    case message(String)

    var errorDescription: String? {
        switch self {
        case .message(let text): return text
        }
    }
}

enum TransactionDecision {
    case abort
    case commit(Any)
}

@MainActor
protocol SplashDatabase: AnyObject {
    /// `ServerValue.TIMESTAMP`.
    var serverTimestamp: Any { get }
    func signIn(_ completion: @escaping @MainActor (Result<String, Error>) -> Void)
    func set(_ path: String, _ value: Any, _ completion: (@MainActor (Error?) -> Void)?)
    func update(_ path: String, _ values: [String: Any], _ completion: (@MainActor (Error?) -> Void)?)
    /// Completion: error, value, exists.
    func get(_ path: String, _ completion: @escaping @MainActor (Error?, Any?, Bool) -> Void)
    func observe(_ path: String, _ onChange: @escaping @MainActor (Any?) -> Void, _ onCancel: @escaping @MainActor (Error) -> Void) -> Int
    /// Child added and child changed events (Android ChildEventListener).
    func observeChildren(_ path: String, _ onChild: @escaping @MainActor (String, Any?) -> Void, _ onCancel: @escaping @MainActor (Error) -> Void) -> Int
    func removeObserver(_ token: Int)
    /// The update block may run on any thread; it must only read its argument and captured constants.
    /// Completion: error, committed, and the value of the snapshot after the transaction.
    func transaction(_ path: String, _ update: @escaping @Sendable (Any?) -> TransactionDecision, _ completion: @escaping @MainActor (Error?, Bool, Any?) -> Void)
    func onDisconnectSet(_ path: String, _ value: Any)
}

enum SplashDatabaseFactory {
    /// Android `BuildConfig.PRODUCTION_ONLINE_ENABLED` (now true): on iOS the app's own Firebase
    /// registration is usable only when the SDK is linked and GoogleService-Info.plist is bundled.
    static var productionAvailable: Bool {
        #if canImport(FirebaseCore) && canImport(FirebaseAuth) && canImport(FirebaseDatabase)
        return Bundle.main.path(forResource: "GoogleService-Info", ofType: "plist") != nil
        #else
        return false
        #endif
    }

    /// Ordinary launches use the registered project; only an explicit debug QA launch uses the
    /// local emulators (Android `qaOnline`).
    @MainActor
    static func make(host: String, emulator: Bool) throws -> SplashDatabase {
        #if canImport(FirebaseCore) && canImport(FirebaseAuth) && canImport(FirebaseDatabase)
        return try FirebaseSplashDatabase.connect(host: host, emulator: emulator)
        #else
        throw SplashOnlineError.message("Production online registration is not activated.")
        #endif
    }

    /// Android `DatabaseError.PERMISSION_DENIED`: the Firebase Apple SDK reports
    /// "permission_denied" as code 1 in the "com.firebase" domain.
    static func isPermissionDenied(_ error: Error) -> Bool {
        let ns = error as NSError
        if ns.domain == "com.firebase" && ns.code == 1 { return true }
        return ns.localizedDescription.lowercased().contains("permission")
    }
}
