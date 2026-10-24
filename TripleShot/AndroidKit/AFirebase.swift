import Foundation
#if canImport(FirebaseCore) && canImport(FirebaseAuth) && canImport(FirebaseDatabase)
import FirebaseAuth
import FirebaseCore
import FirebaseDatabase
#endif

// Android-shaped Firebase API (com.google.firebase.FirebaseApp, .auth.FirebaseAuth, .database.*, and
// com.google.android.gms.tasks.Task) over the iOS SDK products FirebaseCore, FirebaseAuth and FirebaseDatabase,
// so firebase/TripleShotFirebaseRepository.kt translates call for call (DESIGN 4.7, spec 05).
//
// Threading, as on Android: every Task listener, ValueEventListener / ChildEventListener callback and
// Transaction.Handler.onComplete runs on the main thread. Task listeners are posted to the main Looper (one
// message each, also when added to a task that is already complete), like TaskExecutors.MAIN_THREAD. Database
// events are delivered by FirebaseDatabase on the main queue; a removed listener receives nothing afterwards
// (Android zombifies its registration). Transaction.Handler.doTransaction runs synchronously on the main thread
// while FirebaseDatabase's worker waits (Android runs it on its run-loop thread; the handlers are pure, and the
// main thread keeps the rest of the port single-threaded).
//
// Values: everything written goes through CustomClassMapper semantics (AFirebaseCodec.serialize, the model
// codecs for Kotlin wire classes); everything read is first turned into Android's plain value (Long / Double /
// Boolean / String / Map / List with Android's array rule) before typed getValue conversions.
//
// Project: a named FirebaseApp "tripleshot" configured from GoogleService-Info.plist in the app bundle (spec 05
// 4.1.3 / spec 23 9.2: Config/Firebase/MinikTripleShot/GoogleService-Info.plist, copied into the bundle under that
// name), which must belong to the Firebase project "minikswish" (the Android app's project) and to this app's
// bundle id. The database is opened by the URL the repository passes, Android's hard-coded
// https://minikswish-default-rtdb.europe-west1.firebasedatabase.app (AFirebaseApp.DATABASE_URL), memory cache only
// (no persistence), like Android. Without a usable plist (or without the SDK) nothing crashes: sign-in and every
// database task fail with AFirebaseNotConfiguredException (message nil, so callers show their own "Firebase
// error" text), transactions complete with an UNAVAILABLE error and listeners are cancelled with UNAVAILABLE.

// MARK: - Main thread

private enum AFirebaseMain {
    /// The main Looper, where Android posts Task listeners (TaskExecutors.MAIN_THREAD).
    nonisolated(unsafe) static let handler = AHandler(ALooper.getMainLooper())

    static func post(_ block: @escaping () -> Void) {
        handler.post(block)
    }

    /// FirebaseDatabase / FirebaseAuth already call back on the main queue; anything else hops there.
    static func onMain(_ block: @escaping () -> Void) {
        if Thread.isMainThread {
            block()
        } else {
            DispatchQueue.main.async(execute: block)
        }
    }

    static func sync<T>(_ body: () -> T) -> T {
        if Thread.isMainThread {
            return body()
        }
        return DispatchQueue.main.sync(execute: body)
    }
}

// MARK: - Tasks (com.google.android.gms.tasks)

/// com.google.android.gms.tasks.Task<TResult>.
final class ATask<TResult> {
    private(set) var isComplete = false
    private(set) var isSuccessful = false
    private(set) var isCanceled = false
    /// Task.getException(): the failure of a failed task.
    private(set) var exception: Error?
    private var value: TResult?
    private var pending: [(ATask<TResult>) -> Void] = []

    init() {}

    /// Task.getResult() of a successful task; nil while pending, after a failure or a cancellation (where
    /// Android throws).
    var result: TResult? {
        return isSuccessful ? value : nil
    }

    func getResult() -> TResult? {
        return result
    }

    func getException() -> Error? {
        return exception
    }

    @discardableResult
    func addOnSuccessListener(_ listener: @escaping (TResult) -> Void) -> ATask<TResult> {
        return addListener { task in
            if task.isSuccessful, let value = task.value {
                listener(value)
            }
        }
    }

    @discardableResult
    func addOnFailureListener(_ listener: @escaping (Error) -> Void) -> ATask<TResult> {
        return addListener { task in
            if task.isComplete && !task.isSuccessful && !task.isCanceled, let error = task.exception {
                listener(error)
            }
        }
    }

    @discardableResult
    func addOnCompleteListener(_ listener: @escaping (ATask<TResult>) -> Void) -> ATask<TResult> {
        return addListener(listener)
    }

    @discardableResult
    func addOnCanceledListener(_ listener: @escaping () -> Void) -> ATask<TResult> {
        return addListener { task in
            if task.isCanceled {
                listener()
            }
        }
    }

    private func addListener(_ listener: @escaping (ATask<TResult>) -> Void) -> ATask<TResult> {
        if isComplete {
            AFirebaseMain.post { listener(self) }
        } else {
            pending.append(listener)
        }
        return self
    }

    /// Completes the task once; the listeners added so far are posted in the order they were added.
    fileprivate func complete(result: TResult?, exception: Error?, canceled: Bool) -> Bool {
        if isComplete {
            return false
        }
        isComplete = true
        isCanceled = canceled
        isSuccessful = !canceled && exception == nil
        value = result
        self.exception = exception
        let listeners = pending
        pending = []
        for listener in listeners {
            AFirebaseMain.post { listener(self) }
        }
        return true
    }
}

/// com.google.android.gms.tasks.TaskCompletionSource<TResult>.
final class ATaskCompletionSource<TResult> {
    let task = ATask<TResult>()

    init() {}

    func setResult(_ result: TResult) {
        let completed = trySetResult(result)
        precondition(completed, "Task is already complete")
    }

    @discardableResult
    func trySetResult(_ result: TResult) -> Bool {
        return completeOnMain(result: result, exception: nil)
    }

    func setException(_ exception: Error) {
        let completed = trySetException(exception)
        precondition(completed, "Task is already complete")
    }

    @discardableResult
    func trySetException(_ exception: Error) -> Bool {
        return completeOnMain(result: nil, exception: exception)
    }

    private func completeOnMain(result: TResult?, exception: Error?) -> Bool {
        return AFirebaseMain.sync { task.complete(result: result, exception: exception, canceled: false) }
    }
}

/// com.google.android.gms.tasks.Tasks (the factories).
enum ATasks {
    static func forResult<TResult>(_ result: TResult) -> ATask<TResult> {
        let source = ATaskCompletionSource<TResult>()
        source.setResult(result)
        return source.task
    }

    static func forException<TResult>(_ exception: Error) -> ATask<TResult> {
        let source = ATaskCompletionSource<TResult>()
        source.setException(exception)
        return source.task
    }
}

// MARK: - Exceptions

/// Firebase-layer throwables: com.google.firebase.FirebaseException and the subclasses below. `message` is
/// Throwable.getMessage() (also the LocalizedError description).
class AFirebaseException: Error, LocalizedError, CustomStringConvertible, @unchecked Sendable {
    let message: String?
    let cause: Error?

    init(_ message: String?, cause: Error? = nil) {
        self.message = message
        self.cause = cause
    }

    var errorDescription: String? {
        return message
    }

    var javaClassName: String {
        return "com.google.firebase.FirebaseException"
    }

    /// Throwable.toString().
    var description: String {
        guard let message = message else { return javaClassName }
        return javaClassName + ": " + message
    }
}

/// com.google.firebase.database.DatabaseException ("Firebase Database error: ..." from DatabaseError.toException,
/// and the CustomClassMapper conversion failures).
final class ADatabaseException: AFirebaseException, @unchecked Sendable {
    override var javaClassName: String {
        return "com.google.firebase.database.DatabaseException"
    }
}

/// java.lang.Exception as Query.get() fails it ("Client is offline", or the server's reason).
final class AQueryGetException: AFirebaseException, @unchecked Sendable {
    override var javaClassName: String {
        return "java.lang.Exception"
    }
}

/// com.google.firebase.auth.FirebaseAuthException.
final class AFirebaseAuthException: AFirebaseException, @unchecked Sendable {
    /// FirebaseAuthException.getErrorCode(), e.g. "ERROR_OPERATION_NOT_ALLOWED".
    let errorCode: String

    init(_ errorCode: String, _ message: String?, cause: Error? = nil) {
        self.errorCode = errorCode
        super.init(message, cause: cause)
    }

    override var javaClassName: String {
        return "com.google.firebase.auth.FirebaseAuthException"
    }
}

/// com.google.firebase.FirebaseNetworkException.
final class AFirebaseNetworkException: AFirebaseException, @unchecked Sendable {
    override var javaClassName: String {
        return "com.google.firebase.FirebaseNetworkException"
    }
}

/// iOS only: TripleShot's Firebase registration is missing (no or wrong GoogleService-Info.plist, or the SDK is
/// not linked). Android always has it (the build fails without google-services.json). The message is nil so the
/// callers' `message ?: getString(R.string.minik_swish_firebase_error)` shows the app's own text.
final class AFirebaseNotConfiguredException: AFirebaseException, @unchecked Sendable {
    init() {
        super.init(nil)
    }

    override var javaClassName: String {
        return "com.google.firebase.FirebaseException"
    }
}

// MARK: - DatabaseError

/// com.google.firebase.database.DatabaseError.
final class ADatabaseError: CustomStringConvertible {
    static let DATA_STALE = -1
    static let OPERATION_FAILED = -2
    static let PERMISSION_DENIED = -3
    static let DISCONNECTED = -4
    static let EXPIRED_TOKEN = -6
    static let INVALID_TOKEN = -7
    static let MAX_RETRIES = -8
    static let OVERRIDDEN_BY_SET = -9
    static let UNAVAILABLE = -10
    static let USER_CODE_EXCEPTION = -11
    static let NETWORK_ERROR = -24
    static let WRITE_CANCELED = -25
    static let UNKNOWN_ERROR = -999

    private static let errorReasons: [Int: String] = [
        DATA_STALE: "The transaction needs to be run again with current data",
        OPERATION_FAILED: "The server indicated that this operation failed",
        PERMISSION_DENIED: "This client does not have permission to perform this operation",
        DISCONNECTED: "The operation had to be aborted due to a network disconnect",
        EXPIRED_TOKEN: "The supplied auth token has expired",
        INVALID_TOKEN: "The supplied auth token was invalid",
        MAX_RETRIES: "The transaction had too many retries",
        OVERRIDDEN_BY_SET: "The transaction was overridden by a subsequent set",
        UNAVAILABLE: "The service is unavailable",
        USER_CODE_EXCEPTION: "User code called from the Firebase Database runloop threw an exception:\n",
        NETWORK_ERROR: "The operation could not be performed due to a network error",
        WRITE_CANCELED: "The write was canceled by the user.",
        UNKNOWN_ERROR: "An unknown error occurred"
    ]

    private static let errorCodes: [String: Int] = [
        "datastale": DATA_STALE,
        "failure": OPERATION_FAILED,
        "permission_denied": PERMISSION_DENIED,
        "disconnected": DISCONNECTED,
        "expired_token": EXPIRED_TOKEN,
        "invalid_token": INVALID_TOKEN,
        "maxretries": MAX_RETRIES,
        "overriddenbyset": OVERRIDDEN_BY_SET,
        "unavailable": UNAVAILABLE,
        "network_error": NETWORK_ERROR,
        "write_canceled": WRITE_CANCELED
    ]

    let code: Int
    let message: String
    let details: String

    private init(_ code: Int, _ message: String, _ details: String?) {
        self.code = code
        self.message = message
        self.details = details ?? ""
    }

    static func fromStatus(_ status: String, _ reason: String? = nil, _ details: String? = nil) -> ADatabaseError {
        let code = errorCodes[status.lowercased()] ?? UNKNOWN_ERROR
        return ADatabaseError(code, reason ?? errorReasons[code] ?? "", details)
    }

    static func fromCode(_ code: Int) -> ADatabaseError {
        guard let message = errorReasons[code] else {
            preconditionFailure("Invalid Firebase Database error code: \(code)")
        }
        return ADatabaseError(code, message, nil)
    }

    /// An exception thrown by user code inside the database run loop (doTransaction).
    static func fromException(_ exception: Error) -> ADatabaseError {
        let reason = (errorReasons[USER_CODE_EXCEPTION] ?? "") + String(describing: exception)
        return ADatabaseError(USER_CODE_EXCEPTION, reason, nil)
    }

    /// The Android error for a FirebaseDatabase iOS NSError (FUtilities errorForStatus: domain "com.firebase",
    /// code 1 permission_denied / 2 unavailable / 3 write_canceled / 9999 other; the description is the server's
    /// reason or the status).
    static func fromFirebaseError(_ error: Error) -> ADatabaseError {
        let nsError = error as NSError
        let description = nsError.localizedDescription
        guard nsError.domain == "com.firebase" else {
            return ADatabaseError(UNKNOWN_ERROR, description, nil)
        }
        switch nsError.code {
        case 1:
            return ADatabaseError(PERMISSION_DENIED, description, nil)
        case 2:
            return ADatabaseError(UNAVAILABLE, description, nil)
        case 3:
            return fromCode(WRITE_CANCELED)
        default:
            break
        }
        switch description {
        case "maxretry": return fromCode(MAX_RETRIES)       // FConstants kFTransactionTooManyRetries
        case "set": return fromCode(OVERRIDDEN_BY_SET)      // kFTransactionSet
        case "disconnect": return fromCode(DISCONNECTED)    // kFTransactionDisconnect
        default: break
        }
        if let code = errorCodes[description.lowercased()] {
            return fromCode(code)
        }
        return ADatabaseError(UNKNOWN_ERROR, description, nil)
    }

    func getCode() -> Int {
        return code
    }

    func getMessage() -> String {
        return message
    }

    func getDetails() -> String {
        return details
    }

    func toException() -> ADatabaseException {
        return ADatabaseException("Firebase Database error: " + message)
    }

    var description: String {
        return "DatabaseError: " + message
    }
}

// MARK: - FirebaseApp

/// com.google.firebase.FirebaseApp. TripleShot's "default" app is the named iOS app "tripleshot" (never the
/// process-wide default FirebaseApp, which may belong to another project when the code is embedded in a bigger
/// app), configured once from GoogleService-Info.plist of the minikswish project.
final class AFirebaseApp {
    static let APP_NAME = "tripleshot"
    static let PROJECT_ID = "minikswish"
    /// The Realtime Database the Android app uses (TripleShotFirebaseRepository.DATABASE_URL, opened by explicit
    /// URL). Also the URL of the default instance (Android's google-services.json of minikswish carries it).
    static let DATABASE_URL = "https://minikswish-default-rtdb.europe-west1.firebasedatabase.app"
    static let OPTIONS_RESOURCE = "GoogleService-Info"
    static let LOG_TAG = "AFirebase"

    let name: String
    /// False when the registration is missing; every Firebase call then fails gracefully.
    let isAvailable: Bool
    let unavailableReason: String?

    #if canImport(FirebaseCore) && canImport(FirebaseAuth) && canImport(FirebaseDatabase)
    let firebaseApp: FirebaseApp?

    private init(app: FirebaseApp?, unavailableReason: String?) {
        self.name = AFirebaseApp.APP_NAME
        self.firebaseApp = app
        self.isAvailable = app != nil
        self.unavailableReason = unavailableReason
    }
    #else
    private init(unavailableReason: String?) {
        self.name = AFirebaseApp.APP_NAME
        self.isAvailable = false
        self.unavailableReason = unavailableReason
    }
    #endif

    nonisolated(unsafe) private static var instance: AFirebaseApp?

    /// FirebaseApp.getInstance().
    static func getInstance() -> AFirebaseApp {
        return AFirebaseMain.sync {
            if let existing = instance {
                return existing
            }
            let created = configure()
            instance = created
            if let reason = created.unavailableReason {
                ALog.w(LOG_TAG, "TripleShot online features are disabled: \(reason)")
            }
            return created
        }
    }

    func getName() -> String {
        return name
    }

    /// FirebaseApp.getApplicationContext() (the repository reads the online nickname with it).
    var applicationContext: AContext {
        return AApplication.shared
    }

    func getApplicationContext() -> AContext {
        return applicationContext
    }

    #if canImport(FirebaseCore) && canImport(FirebaseAuth) && canImport(FirebaseDatabase)
    private static func unavailable(_ reason: String) -> AFirebaseApp {
        return AFirebaseApp(app: nil, unavailableReason: reason)
    }

    private static func configure() -> AFirebaseApp {
        // App Store captures run offline (TripleShotScreenshot); normal launches are unaffected.
        if TripleShotScreenshot.isActive { return unavailable("App Store screenshot capture (offline)") }
        if let app = FirebaseApp.app(name: APP_NAME) {
            return AFirebaseApp(app: app, unavailableReason: nil)
        }
        guard let path = Bundle.main.path(forResource: OPTIONS_RESOURCE, ofType: "plist") else {
            return unavailable("GoogleService-Info.plist is not in the app bundle")
        }
        guard let options = FirebaseOptions(contentsOfFile: path) else {
            return unavailable("GoogleService-Info.plist could not be read")
        }
        guard options.projectID == PROJECT_ID else {
            return unavailable("GoogleService-Info.plist belongs to project \(options.projectID ?? "?"), not \(PROJECT_ID)")
        }
        let bundleID = Bundle.main.bundleIdentifier ?? ""
        guard options.bundleID == bundleID else {
            // The registration of another app: its iOS API key is restricted to that bundle id (spec 23 9.2).
            return unavailable("GoogleService-Info.plist is registered for \(options.bundleID), this app is \(bundleID)")
        }
        guard let apiKey = options.apiKey, !apiKey.isEmpty, isValidGoogleAppID(options.googleAppID) else {
            // FirebaseApp.configure would raise ("Configuration fails ... invalid GOOGLE_APP_ID").
            return unavailable("GoogleService-Info.plist has no valid API_KEY / GOOGLE_APP_ID")
        }
        if let plistURL = options.databaseURL, !plistURL.isEmpty, trimmedURL(plistURL) != DATABASE_URL {
            ALog.w(LOG_TAG, "GoogleService-Info.plist DATABASE_URL \(plistURL) is not \(DATABASE_URL)")
        }
        FirebaseApp.configure(name: APP_NAME, options: options)
        guard let app = FirebaseApp.app(name: APP_NAME) else {
            return unavailable("FirebaseApp \(APP_NAME) could not be configured")
        }
        return AFirebaseApp(app: app, unavailableReason: nil)
    }
    #else
    private static func configure() -> AFirebaseApp {
        return AFirebaseApp(unavailableReason: "the Firebase SDK is not linked into this build")
    }
    #endif

    /// Kotlin `url.trimEnd('/')`.
    static func trimmedURL(_ url: String) -> String {
        var text = Substring(url)
        while text.hasSuffix("/") {
            text = text.dropLast()
        }
        return String(text)
    }

    /// A database root URL that FirebaseDatabase accepts without raising: http(s), a host, no path.
    static func isDatabaseRootURL(_ url: String) -> Bool {
        guard let parsed = URL(string: url), let scheme = parsed.scheme?.lowercased(),
              scheme == "https" || scheme == "http", let host = parsed.host, !host.isEmpty else {
            return false
        }
        return parsed.path.isEmpty || parsed.path == "/"
    }

    /// The format FirebaseCore's FIRApp validateAppID accepts: "<version>:..." and, for version 1,
    /// "1:<project number>:ios:<hex>" (anything else makes FirebaseApp.configure raise).
    static func isValidGoogleAppID(_ appID: String) -> Bool {
        let parts = appID.split(separator: ":", omittingEmptySubsequences: false).map(String.init)
        guard let version = parts.first, !version.isEmpty, version.allSatisfy({ $0.isASCII && $0.isNumber }),
              parts.count >= 2 else {
            return false
        }
        if version != "1" {
            return true
        }
        guard parts.count == 4, !parts[1].isEmpty, parts[1].allSatisfy({ $0.isASCII && $0.isNumber }),
              parts[2] == "ios", !parts[3].isEmpty, parts[3].allSatisfy({ $0.isASCII && $0.isHexDigit }) else {
            return false
        }
        return true
    }
}

// MARK: - FirebaseAuth

/// com.google.firebase.auth.FirebaseAuth of TripleShot's app (shared with any other user of the same uid,
/// e.g. a QuestionEngine edge client).
final class AFirebaseAuth {
    nonisolated(unsafe) private static var instance: AFirebaseAuth?

    static func getInstance() -> AFirebaseAuth {
        if let existing = instance {
            return existing
        }
        let created = AFirebaseAuth(app: AFirebaseApp.getInstance())
        instance = created
        return created
    }

    let app: AFirebaseApp
    private var pendingSignIn: ATask<AAuthResult>?

    #if canImport(FirebaseCore) && canImport(FirebaseAuth) && canImport(FirebaseDatabase)
    private let auth: Auth?

    private init(app: AFirebaseApp) {
        self.app = app
        self.auth = app.firebaseApp.map { Auth.auth(app: $0) }
    }
    #else
    private init(app: AFirebaseApp) {
        self.app = app
    }
    #endif

    /// FirebaseAuth.getCurrentUser(): the signed-in (anonymous) user, persisted by the SDK across launches.
    var currentUser: AFirebaseUser? {
        #if canImport(FirebaseCore) && canImport(FirebaseAuth) && canImport(FirebaseDatabase)
        guard let user = auth?.currentUser else { return nil }
        return AFirebaseUser(user)
        #else
        return nil
        #endif
    }

    func getCurrentUser() -> AFirebaseUser? {
        return currentUser
    }

    /// FirebaseAuth.getUid().
    func getUid() -> String? {
        return currentUser?.uid
    }

    /// FirebaseAuth.signInAnonymously(). Concurrent calls share one sign-in (the iOS SDK would otherwise create
    /// several anonymous users); the outcome for each caller is the same as on Android.
    @discardableResult
    func signInAnonymously() -> ATask<AAuthResult> {
        if let pending = pendingSignIn {
            return pending
        }
        let source = ATaskCompletionSource<AAuthResult>()
        #if canImport(FirebaseCore) && canImport(FirebaseAuth) && canImport(FirebaseDatabase)
        guard let auth = auth else {
            source.setException(AFirebaseNotConfiguredException())
            return source.task
        }
        pendingSignIn = source.task
        auth.signInAnonymously { [weak self] result, error in
            AFirebaseMain.onMain {
                self?.pendingSignIn = nil
                if let result = result {
                    source.setResult(AAuthResult(user: AFirebaseUser(result.user)))
                } else {
                    source.setException(AFirebaseAuth.exception(error))
                }
            }
        }
        #else
        source.setException(AFirebaseNotConfiguredException())
        #endif
        return source.task
    }

    /// FirebaseAuth.signOut().
    func signOut() {
        #if canImport(FirebaseCore) && canImport(FirebaseAuth) && canImport(FirebaseDatabase)
        do {
            try auth?.signOut()
        } catch {
            ALog.w(AFirebaseApp.LOG_TAG, "signOut failed: \(error)")
        }
        #endif
    }

    /// The Android exception for an iOS FirebaseAuth NSError (domain FIRAuthErrorDomain): a network error is a
    /// FirebaseNetworkException with Android's text, everything else a FirebaseAuthException.
    static func exception(_ error: Error?) -> Error {
        guard let error = error else {
            return AFirebaseAuthException("ERROR_INTERNAL_ERROR", "An internal error has occurred.")
        }
        let nsError = error as NSError
        if nsError.domain == "FIRAuthErrorDomain" && nsError.code == 17020 {
            return AFirebaseNetworkException(
                "A network error (such as timeout, interrupted connection or unreachable host) has occurred.", cause: error)
        }
        let name = nsError.userInfo["FIRAuthErrorUserInfoNameKey"] as? String ?? "ERROR_UNKNOWN"
        return AFirebaseAuthException(name, nsError.localizedDescription, cause: error)
    }
}

/// com.google.firebase.auth.FirebaseUser.
final class AFirebaseUser {
    let uid: String
    let isAnonymous: Bool

    #if canImport(FirebaseCore) && canImport(FirebaseAuth) && canImport(FirebaseDatabase)
    private let user: User

    fileprivate init(_ user: User) {
        self.user = user
        self.uid = user.uid
        self.isAnonymous = user.isAnonymous
    }
    #else
    fileprivate init(uid: String, isAnonymous: Bool) {
        self.uid = uid
        self.isAnonymous = isAnonymous
    }
    #endif

    func getUid() -> String {
        return uid
    }

    /// FirebaseUser.getIdToken(forceRefresh).
    @discardableResult
    func getIdToken(_ forceRefresh: Bool) -> ATask<AGetTokenResult> {
        let source = ATaskCompletionSource<AGetTokenResult>()
        #if canImport(FirebaseCore) && canImport(FirebaseAuth) && canImport(FirebaseDatabase)
        user.getIDTokenResult(forcingRefresh: forceRefresh) { result, error in
            AFirebaseMain.onMain {
                if let result = result {
                    source.setResult(AGetTokenResult(
                        token: result.token,
                        expirationTimestamp: Int64(result.expirationDate.timeIntervalSince1970.rounded(.down)),
                        issuedAtTimestamp: Int64(result.issuedAtDate.timeIntervalSince1970.rounded(.down)),
                        authTimestamp: Int64(result.authDate.timeIntervalSince1970.rounded(.down)),
                        signInProvider: result.signInProvider,
                        claims: result.claims))
                } else {
                    source.setException(AFirebaseAuth.exception(error))
                }
            }
        }
        #else
        source.setException(AFirebaseNotConfiguredException())
        #endif
        return source.task
    }
}

/// com.google.firebase.auth.AuthResult.
final class AAuthResult {
    let user: AFirebaseUser?

    init(user: AFirebaseUser?) {
        self.user = user
    }

    func getUser() -> AFirebaseUser? {
        return user
    }
}

/// com.google.firebase.auth.GetTokenResult (timestamps in seconds since the epoch).
final class AGetTokenResult {
    let token: String?
    let expirationTimestamp: Int64
    let issuedAtTimestamp: Int64
    let authTimestamp: Int64
    let signInProvider: String?
    let claims: [String: Any]

    init(token: String?, expirationTimestamp: Int64, issuedAtTimestamp: Int64, authTimestamp: Int64,
         signInProvider: String?, claims: [String: Any]) {
        self.token = token
        self.expirationTimestamp = expirationTimestamp
        self.issuedAtTimestamp = issuedAtTimestamp
        self.authTimestamp = authTimestamp
        self.signInProvider = signInProvider
        self.claims = claims
    }

    func getToken() -> String? {
        return token
    }
}

// MARK: - FirebaseDatabase

/// com.google.firebase.database.FirebaseDatabase of TripleShot's app.
final class AFirebaseDatabase {
    nonisolated(unsafe) private static var instances: [String: AFirebaseDatabase] = [:]

    /// FirebaseDatabase.getInstance(): the plist's DATABASE_URL (Android: google-services.json's), or the
    /// minikswish database when the plist has none (both SDKs would otherwise guess
    /// "https://<project>-default-rtdb.firebaseio.com", which is not where minikswish's database lives).
    static func getInstance() -> AFirebaseDatabase {
        return instance(nil)
    }

    /// FirebaseDatabase.getInstance(url).
    static func getInstance(_ url: String) -> AFirebaseDatabase {
        return instance(url)
    }

    private static func instance(_ url: String?) -> AFirebaseDatabase {
        let key = url ?? ""
        if let existing = instances[key] {
            return existing
        }
        let created = AFirebaseDatabase(app: AFirebaseApp.getInstance(), url: url)
        instances[key] = created
        return created
    }

    let app: AFirebaseApp
    /// The explicit URL, nil for the default instance.
    let url: String?

    #if canImport(FirebaseCore) && canImport(FirebaseAuth) && canImport(FirebaseDatabase)
    fileprivate let database: Database?

    private init(app: AFirebaseApp, url: String?) {
        self.app = app
        self.url = url
        if let firebaseApp = app.firebaseApp {
            // No setPersistenceEnabled: memory cache only, like the Android repository. An explicit URL goes to the
            // SDK unchanged (an invalid one raises there, as Android's getInstance(url) throws).
            var databaseURL = url ?? AFirebaseApp.DATABASE_URL
            if url == nil, let plistURL = firebaseApp.options.databaseURL, AFirebaseApp.isDatabaseRootURL(plistURL) {
                databaseURL = plistURL
            }
            self.database = Database.database(app: firebaseApp, url: databaseURL)
        } else {
            self.database = nil
        }
    }
    #else
    private init(app: AFirebaseApp, url: String?) {
        self.app = app
        self.url = url
    }
    #endif

    /// FirebaseDatabase.getReference() (Kotlin `database.reference`).
    var reference: ADatabaseReference {
        return getReference()
    }

    func getReference() -> ADatabaseReference {
        return ADatabaseReference(database: self, path: [])
    }

    /// FirebaseDatabase.getReference(path).
    func getReference(_ path: String) -> ADatabaseReference {
        if let problem = AFirebaseCodec.rootPathProblem(path) {
            preconditionFailure(problem)
        }
        return ADatabaseReference(database: self, path: AFirebaseCodec.pathSegments(path))
    }

    func goOnline() {
        #if canImport(FirebaseCore) && canImport(FirebaseAuth) && canImport(FirebaseDatabase)
        database?.goOnline()
        #endif
    }

    func goOffline() {
        #if canImport(FirebaseCore) && canImport(FirebaseAuth) && canImport(FirebaseDatabase)
        database?.goOffline()
        #endif
    }

    func purgeOutstandingWrites() {
        #if canImport(FirebaseCore) && canImport(FirebaseAuth) && canImport(FirebaseDatabase)
        database?.purgeOutstandingWrites()
        #endif
    }
}

// MARK: - Query parameters

fileprivate struct AFirebaseQueryParams {
    enum Index: Equatable {
        case priority
        case key
        case value
        case child(String)
    }

    enum Value: Equatable {
        case null
        case double(Double)
        case string(String)
        case bool(Bool)
    }

    struct Bound: Equatable {
        let value: Value
        let key: String?
    }

    var index: Index?
    var start: Bound?
    var end: Bound?
    var isEqualTo = false
    var limit: Int?
    var limitFromFirst = false

    /// QuerySpec identity: listeners are removed per (listener, path, params), like Android. The priority index is
    /// QueryParams' default index, so orderByPriority() alone is the default spec (QuerySpec.isDefault()).
    var specKey: String {
        var parts: [String] = []
        switch index {
        case .priority?: break
        case .key?: parts.append("i=.key")
        case .value?: parts.append("i=.value")
        case .child(let path)?: parts.append("i=child:" + path)
        case nil: break
        }
        if let start = start { parts.append("sp=" + AFirebaseQueryParams.describe(start)) }
        if let end = end { parts.append("ep=" + AFirebaseQueryParams.describe(end)) }
        if let limit = limit { parts.append((limitFromFirst ? "lf=" : "ll=") + String(limit)) }
        return parts.joined(separator: ";")
    }

    private static func describe(_ bound: Bound) -> String {
        let value: String
        switch bound.value {
        case .null: value = "null"
        case .double(let d): value = "d:" + String(d.bitPattern)
        case .string(let s): value = "s:" + s
        case .bool(let b): value = "b:" + String(b)
        }
        return value + "@" + (bound.key ?? "")
    }
}

// MARK: - Query / DatabaseReference

/// com.google.firebase.database.Query.
class AQuery: CustomStringConvertible {
    let database: AFirebaseDatabase
    /// The path segments below the database root.
    let path: [String]
    fileprivate let params: AFirebaseQueryParams

    fileprivate init(database: AFirebaseDatabase, path: [String], params: AFirebaseQueryParams) {
        self.database = database
        self.path = path
        self.params = params
    }

    /// Query.getRef().
    var ref: ADatabaseReference {
        return ADatabaseReference(database: database, path: path)
    }

    func getRef() -> ADatabaseReference {
        return ref
    }

    fileprivate var specKey: String {
        return pathKey + "|" + params.specKey
    }

    fileprivate var pathKey: String {
        return (database.url ?? "") + "|" + path.joined(separator: "/")
    }

    /// QuerySpec.isDefault(): no ordering, range or limit.
    fileprivate var isDefaultSpec: Bool {
        return params.specKey.isEmpty
    }

    var description: String {
        return (database.url ?? "") + "/" + path.joined(separator: "/")
    }

    // MARK: Ordering, ranges, limits

    func orderByChild(_ path: String) -> AQuery {
        precondition(path != "$key" && path != ".key", "Can't use '\(path)' as path, please use orderByKey() instead!")
        precondition(path != "$priority" && path != ".priority",
                     "Can't use '\(path)' as path, please use orderByPriority() instead!")
        precondition(path != "$value" && path != ".value", "Can't use '\(path)' as path, please use orderByValue() instead!")
        if let problem = AFirebaseCodec.pathProblem(path) {
            preconditionFailure(problem)
        }
        return ordered(.child(AFirebaseCodec.pathSegments(path).joined(separator: "/")))
    }

    func orderByKey() -> AQuery {
        return ordered(.key)
    }

    func orderByValue() -> AQuery {
        return ordered(.value)
    }

    func orderByPriority() -> AQuery {
        return ordered(.priority)
    }

    private func ordered(_ index: AFirebaseQueryParams.Index) -> AQuery {
        precondition(params.index == nil, "You can't combine multiple orderBy calls!")
        var next = params
        next.index = index
        return AQuery(database: database, path: path, params: next)
    }

    func startAt(_ value: Double) -> AQuery {
        return starting(.double(value), nil)
    }

    func startAt(_ value: Double, _ key: String?) -> AQuery {
        return starting(.double(value), key)
    }

    func startAt(_ value: String?) -> AQuery {
        return starting(value.map { .string($0) } ?? .null, nil)
    }

    func startAt(_ value: String?, _ key: String?) -> AQuery {
        return starting(value.map { .string($0) } ?? .null, key)
    }

    func startAt(_ value: Bool) -> AQuery {
        return starting(.bool(value), nil)
    }

    func startAt(_ value: Bool, _ key: String?) -> AQuery {
        return starting(.bool(value), key)
    }

    func endAt(_ value: Double) -> AQuery {
        return ending(.double(value), nil)
    }

    func endAt(_ value: Double, _ key: String?) -> AQuery {
        return ending(.double(value), key)
    }

    func endAt(_ value: String?) -> AQuery {
        return ending(value.map { .string($0) } ?? .null, nil)
    }

    func endAt(_ value: String?, _ key: String?) -> AQuery {
        return ending(value.map { .string($0) } ?? .null, key)
    }

    func endAt(_ value: Bool) -> AQuery {
        return ending(.bool(value), nil)
    }

    func endAt(_ value: Bool, _ key: String?) -> AQuery {
        return ending(.bool(value), key)
    }

    func equalTo(_ value: Double) -> AQuery {
        return equal(.double(value), nil)
    }

    func equalTo(_ value: Double, _ key: String?) -> AQuery {
        return equal(.double(value), key)
    }

    func equalTo(_ value: String?) -> AQuery {
        return equal(value.map { .string($0) } ?? .null, nil)
    }

    func equalTo(_ value: String?, _ key: String?) -> AQuery {
        return equal(value.map { .string($0) } ?? .null, key)
    }

    func equalTo(_ value: Bool) -> AQuery {
        return equal(.bool(value), nil)
    }

    func equalTo(_ value: Bool, _ key: String?) -> AQuery {
        return equal(.bool(value), key)
    }

    private func starting(_ value: AFirebaseQueryParams.Value, _ key: String?) -> AQuery {
        precondition(params.start == nil, "Can't call startAt(), startAfter(), or equalTo() multiple times")
        var next = params
        next.start = AFirebaseQueryParams.Bound(value: value, key: key)
        return AQuery(database: database, path: path, params: next)
    }

    private func ending(_ value: AFirebaseQueryParams.Value, _ key: String?) -> AQuery {
        precondition(params.end == nil, "Can't call endAt(), endBefore(), or equalTo() multiple times")
        var next = params
        next.end = AFirebaseQueryParams.Bound(value: value, key: key)
        return AQuery(database: database, path: path, params: next)
    }

    private func equal(_ value: AFirebaseQueryParams.Value, _ key: String?) -> AQuery {
        precondition(params.start == nil, "Cannot combine equalTo() with startAt() or startAfter()")
        precondition(params.end == nil, "Cannot combine equalTo() with endAt() or endBefore()")
        var next = params
        next.start = AFirebaseQueryParams.Bound(value: value, key: key)
        next.end = next.start
        next.isEqualTo = true
        return AQuery(database: database, path: path, params: next)
    }

    func limitToFirst(_ limit: Int) -> AQuery {
        precondition(limit > 0, "Limit must be a positive integer!")
        precondition(params.limit == nil, "Can't call limitToFirst on query with previously set limit!")
        var next = params
        next.limit = limit
        next.limitFromFirst = true
        return AQuery(database: database, path: path, params: next)
    }

    func limitToLast(_ limit: Int) -> AQuery {
        precondition(limit > 0, "Limit must be a positive integer!")
        precondition(params.limit == nil, "Can't call limitToLast on query with previously set limit!")
        var next = params
        next.limit = limit
        next.limitFromFirst = false
        return AQuery(database: database, path: path, params: next)
    }

    // MARK: Reading

    /// Query.addValueEventListener: the current value (possibly from the local cache) and every change.
    @discardableResult
    func addValueEventListener(_ listener: AValueEventListener) -> AValueEventListener {
        let registration = AListenerRegistration(identity: listener, query: self)
        AListenerRegistry.add(registration)
        observeValue(registration, listener, once: false)
        return listener
    }

    /// Query.addListenerForSingleValueEvent: one value event, then the listener is removed. As on Android the
    /// registration belongs to an internal wrapper, so removeEventListener(listener) does not cancel it.
    func addListenerForSingleValueEvent(_ listener: AValueEventListener) {
        let registration = AListenerRegistration(identity: AListenerRegistration.Wrapper(), query: self)
        AListenerRegistry.add(registration)
        observeValue(registration, listener, once: true)
    }

    /// Query.addChildEventListener.
    @discardableResult
    func addChildEventListener(_ listener: AChildEventListener) -> AChildEventListener {
        let registration = AListenerRegistration(identity: listener, query: self)
        AListenerRegistry.add(registration)
        observeChildren(registration, listener)
        return listener
    }

    /// Query.removeEventListener(ValueEventListener): this listener's registrations on this query; on a plain
    /// reference (default query) its registrations on every query at this location, like Android's SyncPoint.
    func removeEventListener(_ listener: AValueEventListener) {
        AListenerRegistry.remove(listener, self)
    }

    /// Query.removeEventListener(ChildEventListener).
    func removeEventListener(_ listener: AChildEventListener) {
        AListenerRegistry.remove(listener, self)
    }

    /// Query.get(): the server value (or the in-memory value of an active listener at this location).
    func get() -> ATask<ADataSnapshot> {
        let source = ATaskCompletionSource<ADataSnapshot>()
        #if canImport(FirebaseCore) && canImport(FirebaseAuth) && canImport(FirebaseDatabase)
        guard let query = firebaseQuery() else {
            source.setException(AFirebaseNotConfiguredException())
            return source.task
        }
        let reference = ref
        query.getData { error, snapshot in
            AFirebaseMain.onMain {
                if error == nil, let snapshot = snapshot {
                    source.setResult(ADataSnapshot(firebase: snapshot, ref: reference, key: reference.key))
                } else {
                    source.setException(AQuery.getException(error))
                }
            }
        }
        #else
        source.setException(AFirebaseNotConfiguredException())
        #endif
        return source.task
    }

    /// Query.keepSynced.
    func keepSynced(_ keepSynced: Bool) {
        #if canImport(FirebaseCore) && canImport(FirebaseAuth) && canImport(FirebaseDatabase)
        firebaseQuery()?.keepSynced(keepSynced)
        #endif
    }

    #if canImport(FirebaseCore) && canImport(FirebaseAuth) && canImport(FirebaseDatabase)
    /// Android: java.lang.Exception("Client is offline") or the server's reason; iOS puts that reason into
    /// NSLocalizedFailureReasonErrorKey ("Client is offline." with a period).
    fileprivate static func getException(_ error: Error?) -> Error {
        guard let error = error else {
            return AQueryGetException("An unknown error occurred")
        }
        let nsError = error as NSError
        if let reason = nsError.userInfo[NSLocalizedFailureReasonErrorKey] as? String {
            return AQueryGetException(reason == "Client is offline." ? "Client is offline" : reason, cause: error)
        }
        return AQueryGetException(nsError.localizedDescription, cause: error)
    }

    fileprivate func firebaseReference() -> DatabaseReference? {
        guard let firebaseDatabase = database.database else { return nil }
        if path.isEmpty {
            return firebaseDatabase.reference()
        }
        return firebaseDatabase.reference(withPath: path.joined(separator: "/"))
    }

    fileprivate func firebaseQuery() -> DatabaseQuery? {
        guard let reference = firebaseReference() else { return nil }
        var query: DatabaseQuery = reference
        switch params.index {
        case .child(let child)?: query = query.queryOrdered(byChild: child)
        case .key?: query = query.queryOrderedByKey()
        case .value?: query = query.queryOrderedByValue()
        case .priority?: query = query.queryOrderedByPriority()
        case nil: break
        }
        if params.isEqualTo, let bound = params.start {
            if let key = bound.key {
                query = query.queryEqual(toValue: AQuery.firebaseValue(bound.value), childKey: key)
            } else {
                query = query.queryEqual(toValue: AQuery.firebaseValue(bound.value))
            }
        } else {
            if let bound = params.start {
                if let key = bound.key {
                    query = query.queryStarting(atValue: AQuery.firebaseValue(bound.value), childKey: key)
                } else {
                    query = query.queryStarting(atValue: AQuery.firebaseValue(bound.value))
                }
            }
            if let bound = params.end {
                if let key = bound.key {
                    query = query.queryEnding(atValue: AQuery.firebaseValue(bound.value), childKey: key)
                } else {
                    query = query.queryEnding(atValue: AQuery.firebaseValue(bound.value))
                }
            }
        }
        if let limit = params.limit {
            query = params.limitFromFirst ? query.queryLimited(toFirst: UInt(limit)) : query.queryLimited(toLast: UInt(limit))
        }
        return query
    }

    private static func firebaseValue(_ value: AFirebaseQueryParams.Value) -> Any? {
        switch value {
        case .null: return nil
        case .double(let d): return NSNumber(value: d)
        case .string(let s): return s
        case .bool(let b): return NSNumber(value: b)
        }
    }

    private func observeValue(_ registration: AListenerRegistration, _ listener: AValueEventListener, once: Bool) {
        guard let query = firebaseQuery() else {
            cancelUnavailable(registration) { listener.onCancelled($0) }
            return
        }
        let reference = ref
        let handle = query.observe(.value, with: { [weak registration] snapshot in
            AFirebaseMain.onMain {
                guard let registration = registration, !registration.isRemoved else { return }
                if once {
                    AListenerRegistry.discard(registration)
                }
                listener.onDataChange(ADataSnapshot(firebase: snapshot, ref: reference, key: reference.key))
            }
        }, withCancel: { [weak registration] error in
            AFirebaseMain.onMain {
                guard let registration = registration, !registration.isRemoved else { return }
                AListenerRegistry.discard(registration)
                listener.onCancelled(ADatabaseError.fromFirebaseError(error))
            }
        })
        registration.observers.append((query, handle))
    }

    private func observeChildren(_ registration: AListenerRegistration, _ listener: AChildEventListener) {
        guard let query = firebaseQuery() else {
            cancelUnavailable(registration) { listener.onCancelled($0) }
            return
        }
        let reference = ref
        let cancel: (Error) -> Void = { [weak registration] error in
            AFirebaseMain.onMain {
                // One registration on Android, four observers on iOS: report the cancellation once.
                guard let registration = registration, !registration.isRemoved else { return }
                AListenerRegistry.discard(registration)
                listener.onCancelled(ADatabaseError.fromFirebaseError(error))
            }
        }
        let events: [DataEventType] = [.childAdded, .childChanged, .childRemoved, .childMoved]
        for event in events {
            let handle = query.observe(event, andPreviousSiblingKeyWith: { [weak registration] snapshot, previous in
                AFirebaseMain.onMain {
                    guard let registration = registration, !registration.isRemoved else { return }
                    let key = snapshot.key
                    let child = ADataSnapshot(firebase: snapshot, ref: reference.child(key), key: key)
                    switch event {
                    case .childAdded: listener.onChildAdded(child, previous)
                    case .childChanged: listener.onChildChanged(child, previous)
                    case .childRemoved: listener.onChildRemoved(child)
                    case .childMoved: listener.onChildMoved(child, previous)
                    default: break
                    }
                }
            }, withCancel: cancel)
            registration.observers.append((query, handle))
        }
    }
    #else
    private func observeValue(_ registration: AListenerRegistration, _ listener: AValueEventListener, once: Bool) {
        cancelUnavailable(registration) { listener.onCancelled($0) }
    }

    private func observeChildren(_ registration: AListenerRegistration, _ listener: AChildEventListener) {
        cancelUnavailable(registration) { listener.onCancelled($0) }
    }
    #endif

    /// No backend (TripleShot's registration is missing or the SDK is not linked): the registration is cancelled
    /// with UNAVAILABLE, like a listener the server refuses (posted, never inside the add call; nothing is
    /// delivered if the listener is removed first).
    private func cancelUnavailable(_ registration: AListenerRegistration,
                                   _ onCancelled: @escaping (ADatabaseError) -> Void) {
        AFirebaseMain.post { [weak registration] in
            guard let registration = registration, !registration.isRemoved else { return }
            AListenerRegistry.discard(registration)
            onCancelled(ADatabaseError.fromCode(ADatabaseError.UNAVAILABLE))
        }
    }
}

/// com.google.firebase.database.DatabaseReference.
final class ADatabaseReference: AQuery {
    init(database: AFirebaseDatabase, path: [String]) {
        super.init(database: database, path: path, params: AFirebaseQueryParams())
    }

    override var ref: ADatabaseReference {
        return self
    }

    /// DatabaseReference.getKey(): the last path segment, nil for the root.
    var key: String? {
        return path.last
    }

    func getKey() -> String? {
        return key
    }

    /// DatabaseReference.getParent(): nil for the root.
    var parent: ADatabaseReference? {
        if path.isEmpty { return nil }
        return ADatabaseReference(database: database, path: Array(path.dropLast()))
    }

    func getParent() -> ADatabaseReference? {
        return parent
    }

    var root: ADatabaseReference {
        return ADatabaseReference(database: database, path: [])
    }

    func getRoot() -> ADatabaseReference {
        return root
    }

    /// DatabaseReference.child(pathString): '.', '#', '$', '[', ']' crash like Android's DatabaseException;
    /// empty segments are ignored.
    func child(_ pathString: String) -> ADatabaseReference {
        if let problem = path.isEmpty ? AFirebaseCodec.rootPathProblem(pathString) : AFirebaseCodec.pathProblem(pathString) {
            preconditionFailure(problem)
        }
        return ADatabaseReference(database: database, path: path + AFirebaseCodec.pathSegments(pathString))
    }

    /// DatabaseReference.push(): a child with a new chronological push id (generated on the client).
    func push() -> ADatabaseReference {
        #if canImport(FirebaseCore) && canImport(FirebaseAuth) && canImport(FirebaseDatabase)
        if let reference = firebaseReference(), let key = reference.childByAutoId().key {
            return ADatabaseReference(database: database, path: path + [key])
        }
        #endif
        return ADatabaseReference(database: database,
                                  path: path + [AFirebaseCodec.generatePushChildName(ASystem.currentTimeMillis())])
    }

    // MARK: Writing

    /// DatabaseReference.setValue(value): nil removes; a Kotlin wire class is written with its CustomClassMapper
    /// map. Completes on the server's acknowledgement.
    @discardableResult
    func setValue(_ value: Any?) -> ATask<Void> {
        let plain = writablePlain(value)
        let source = ATaskCompletionSource<Void>()
        #if canImport(FirebaseCore) && canImport(FirebaseAuth) && canImport(FirebaseDatabase)
        guard let reference = firebaseReference() else {
            source.setException(AFirebaseNotConfiguredException())
            return source.task
        }
        reference.setValue(AFirebaseCodec.firebaseValue(fromPlain: plain)) { error, _ in
            AFirebaseMain.onMain { ADatabaseReference.complete(source, error) }
        }
        #else
        source.setException(AFirebaseNotConfiguredException())
        #endif
        return source.task
    }

    /// DatabaseReference.updateChildren(update): an atomic multi-path update; keys are paths relative to this
    /// location, a nil / NSNull value removes that path.
    @discardableResult
    func updateChildren(_ update: [String: Any]) -> ATask<Void> {
        let values = writableUpdate(update)
        let source = ATaskCompletionSource<Void>()
        #if canImport(FirebaseCore) && canImport(FirebaseAuth) && canImport(FirebaseDatabase)
        guard let reference = firebaseReference() else {
            source.setException(AFirebaseNotConfiguredException())
            return source.task
        }
        reference.updateChildValues(values) { error, _ in
            AFirebaseMain.onMain { ADatabaseReference.complete(source, error) }
        }
        #else
        source.setException(AFirebaseNotConfiguredException())
        #endif
        return source.task
    }

    /// updateChildren with an insertion-ordered Kotlin map (an update's order is not observable).
    @discardableResult
    func updateChildren(_ update: KLinkedMap<String, Any>) -> ATask<Void> {
        return updateChildren(ADatabaseReference.plainMap(update))
    }

    fileprivate static func plainMap(_ update: KLinkedMap<String, Any>) -> [String: Any] {
        var map: [String: Any] = [:]
        for (key, value) in update.entries {
            map[key] = value
        }
        return map
    }

    /// DatabaseReference.removeValue() = setValue(null).
    @discardableResult
    func removeValue() -> ATask<Void> {
        return setValue(nil)
    }

    /// DatabaseReference.onDisconnect().
    func onDisconnect() -> AOnDisconnect {
        precondition(path.first.map { !$0.hasPrefix(".") } ?? true, "Invalid write location: \(description)")
        return AOnDisconnect(self)
    }

    /// DatabaseReference.runTransaction(handler) (local events fired).
    func runTransaction(_ handler: ATransaction.Handler) {
        runTransaction(handler, true)
    }

    /// DatabaseReference.runTransaction(handler, fireLocalEvents). doTransaction may run several times (first
    /// with the locally cached value, possibly null); onComplete runs once on the main thread with the error
    /// (an exception in doTransaction - here a CustomClassMapper failure of MutableData.getValue/setValue -
    /// aborts with USER_CODE_EXCEPTION, as Android's run loop does), the committed flag and the final snapshot.
    func runTransaction(_ handler: ATransaction.Handler, _ fireLocalEvents: Bool) {
        #if canImport(FirebaseCore) && canImport(FirebaseAuth) && canImport(FirebaseDatabase)
        guard let reference = firebaseReference() else {
            AFirebaseMain.post { handler.onComplete(ADatabaseError.fromCode(ADatabaseError.UNAVAILABLE), false, nil) }
            return
        }
        let state = ATransactionRunState()
        let snapshotRef = self
        reference.runTransactionBlock({ firebaseData in
            return AFirebaseMain.sync { () -> TransactionResult in
                let data = AMutableData(firebase: firebaseData)
                let result = handler.doTransaction(data)
                if let failure = data.run.failure {
                    state.userError = ADatabaseError.fromException(failure)
                    return TransactionResult.abort()
                }
                state.userError = nil
                guard result.isSuccess else {
                    return TransactionResult.abort()
                }
                if let resultData = result.data, resultData !== data {
                    firebaseData.value = AFirebaseCodec.firebaseValue(fromPlain: resultData.value)
                }
                return TransactionResult.success(withValue: firebaseData)
            }
        }, andCompletionBlock: { error, committed, snapshot in
            AFirebaseMain.onMain {
                let databaseError = error.map { ADatabaseError.fromFirebaseError($0) } ?? (committed ? nil : state.userError)
                let finalSnapshot = snapshot.map { ADataSnapshot(firebase: $0, ref: snapshotRef, key: snapshotRef.key) }
                handler.onComplete(databaseError, committed, finalSnapshot)
            }
        }, withLocalEvents: fireLocalEvents)
        #else
        AFirebaseMain.post { handler.onComplete(ADatabaseError.fromCode(ADatabaseError.UNAVAILABLE), false, nil) }
        #endif
    }

    // MARK: Write helpers

    /// CustomClassMapper.convertToPlainJavaTypes + Validation.validateWritableObject (Android throws a
    /// DatabaseException, i.e. crashes the caller, for NaN / infinity and invalid keys).
    fileprivate func writablePlain(_ value: Any?) -> Any? {
        precondition(path.first.map { !$0.hasPrefix(".") } ?? true, "Invalid write location: \(description)")
        let plain = AFirebaseCodec.serialize(value)
        if let problem = AFirebaseCodec.writableObjectProblem(plain) {
            preconditionFailure(problem)
        }
        return plain
    }

    fileprivate func writableUpdate(_ update: [String: Any]) -> [AnyHashable: Any] {
        precondition(path.first.map { !$0.hasPrefix(".") } ?? true, "Invalid write location: \(description)")
        var values: [AnyHashable: Any] = [:]
        for (key, item) in update {
            let childName = AFirebaseCodec.pathSegments(key).last ?? ""
            if childName == ".sv" || childName == ".value" {
                preconditionFailure("Path '\(key)' contains disallowed child name: \(childName)")
            }
            let plain = AFirebaseCodec.serialize(item)
            if let problem = AFirebaseCodec.writableObjectProblem(plain) {
                preconditionFailure(problem)
            }
            values[key] = AFirebaseCodec.firebaseValue(fromPlain: plain)
        }
        return values
    }

    /// Utilities.wrapOnComplete: success, or DatabaseError.toException().
    fileprivate static func complete(_ source: ATaskCompletionSource<Void>, _ error: Error?) {
        if let error = error {
            source.setException(ADatabaseError.fromFirebaseError(error).toException())
        } else {
            source.setResult(())
        }
    }
}

/// com.google.firebase.database.OnDisconnect: operations the server runs when this client disconnects. The
/// task completes when the server has queued (or cancelled) the operation; security rules are checked then and
/// again when it fires.
final class AOnDisconnect {
    private let reference: ADatabaseReference

    fileprivate init(_ reference: ADatabaseReference) {
        self.reference = reference
    }

    @discardableResult
    func setValue(_ value: Any?) -> ATask<Void> {
        let plain = reference.writablePlain(value)
        let source = ATaskCompletionSource<Void>()
        #if canImport(FirebaseCore) && canImport(FirebaseAuth) && canImport(FirebaseDatabase)
        guard let firebaseRef = reference.firebaseReference() else {
            source.setException(AFirebaseNotConfiguredException())
            return source.task
        }
        firebaseRef.onDisconnectSetValue(AFirebaseCodec.firebaseValue(fromPlain: plain)) { error, _ in
            AFirebaseMain.onMain { ADatabaseReference.complete(source, error) }
        }
        #else
        source.setException(AFirebaseNotConfiguredException())
        #endif
        return source.task
    }

    @discardableResult
    func updateChildren(_ update: [String: Any]) -> ATask<Void> {
        let values = reference.writableUpdate(update)
        let source = ATaskCompletionSource<Void>()
        #if canImport(FirebaseCore) && canImport(FirebaseAuth) && canImport(FirebaseDatabase)
        guard let firebaseRef = reference.firebaseReference() else {
            source.setException(AFirebaseNotConfiguredException())
            return source.task
        }
        firebaseRef.onDisconnectUpdateChildValues(values) { error, _ in
            AFirebaseMain.onMain { ADatabaseReference.complete(source, error) }
        }
        #else
        source.setException(AFirebaseNotConfiguredException())
        #endif
        return source.task
    }

    @discardableResult
    func updateChildren(_ update: KLinkedMap<String, Any>) -> ATask<Void> {
        return updateChildren(ADatabaseReference.plainMap(update))
    }

    @discardableResult
    func removeValue() -> ATask<Void> {
        let source = ATaskCompletionSource<Void>()
        #if canImport(FirebaseCore) && canImport(FirebaseAuth) && canImport(FirebaseDatabase)
        guard let firebaseRef = reference.firebaseReference() else {
            source.setException(AFirebaseNotConfiguredException())
            return source.task
        }
        firebaseRef.onDisconnectRemoveValue { error, _ in
            AFirebaseMain.onMain { ADatabaseReference.complete(source, error) }
        }
        #else
        source.setException(AFirebaseNotConfiguredException())
        #endif
        return source.task
    }

    /// OnDisconnect.cancel(): cancels the queued operations at this location and all its children.
    @discardableResult
    func cancel() -> ATask<Void> {
        let source = ATaskCompletionSource<Void>()
        #if canImport(FirebaseCore) && canImport(FirebaseAuth) && canImport(FirebaseDatabase)
        guard let firebaseRef = reference.firebaseReference() else {
            source.setException(AFirebaseNotConfiguredException())
            return source.task
        }
        firebaseRef.cancelDisconnectOperations { error, _ in
            AFirebaseMain.onMain { ADatabaseReference.complete(source, error) }
        }
        #else
        source.setException(AFirebaseNotConfiguredException())
        #endif
        return source.task
    }
}

// MARK: - Listeners

/// com.google.firebase.database.ValueEventListener (registered and removed by identity).
protocol AValueEventListener: AnyObject {
    func onDataChange(_ snapshot: ADataSnapshot)
    func onCancelled(_ error: ADatabaseError)
}

/// com.google.firebase.database.ChildEventListener (registered and removed by identity).
protocol AChildEventListener: AnyObject {
    func onChildAdded(_ snapshot: ADataSnapshot, _ previousChildName: String?)
    func onChildChanged(_ snapshot: ADataSnapshot, _ previousChildName: String?)
    func onChildRemoved(_ snapshot: ADataSnapshot)
    func onChildMoved(_ snapshot: ADataSnapshot, _ previousChildName: String?)
    func onCancelled(_ error: ADatabaseError)
}

/// A ValueEventListener object built from closures (Kotlin `object : ValueEventListener { ... }`).
final class ASimpleValueEventListener: AValueEventListener {
    private let dataChange: (ADataSnapshot) -> Void
    private let cancelled: (ADatabaseError) -> Void

    init(onDataChange: @escaping (ADataSnapshot) -> Void, onCancelled: @escaping (ADatabaseError) -> Void = { _ in }) {
        self.dataChange = onDataChange
        self.cancelled = onCancelled
    }

    func onDataChange(_ snapshot: ADataSnapshot) {
        dataChange(snapshot)
    }

    func onCancelled(_ error: ADatabaseError) {
        cancelled(error)
    }
}

/// A ChildEventListener object built from closures (unset callbacks do nothing, like `= Unit` overrides).
final class ASimpleChildEventListener: AChildEventListener {
    private let added: (ADataSnapshot, String?) -> Void
    private let changed: (ADataSnapshot, String?) -> Void
    private let removed: (ADataSnapshot) -> Void
    private let moved: (ADataSnapshot, String?) -> Void
    private let cancelled: (ADatabaseError) -> Void

    init(onChildAdded: @escaping (ADataSnapshot, String?) -> Void = { _, _ in },
         onChildChanged: @escaping (ADataSnapshot, String?) -> Void = { _, _ in },
         onChildRemoved: @escaping (ADataSnapshot) -> Void = { _ in },
         onChildMoved: @escaping (ADataSnapshot, String?) -> Void = { _, _ in },
         onCancelled: @escaping (ADatabaseError) -> Void = { _ in }) {
        self.added = onChildAdded
        self.changed = onChildChanged
        self.removed = onChildRemoved
        self.moved = onChildMoved
        self.cancelled = onCancelled
    }

    func onChildAdded(_ snapshot: ADataSnapshot, _ previousChildName: String?) {
        added(snapshot, previousChildName)
    }

    func onChildChanged(_ snapshot: ADataSnapshot, _ previousChildName: String?) {
        changed(snapshot, previousChildName)
    }

    func onChildRemoved(_ snapshot: ADataSnapshot) {
        removed(snapshot)
    }

    func onChildMoved(_ snapshot: ADataSnapshot, _ previousChildName: String?) {
        moved(snapshot, previousChildName)
    }

    func onCancelled(_ error: ADatabaseError) {
        cancelled(error)
    }
}

/// One listener registration (Android EventRegistration): removed registrations are zombied and deliver nothing.
private final class AListenerRegistration {
    /// The internal listener object of addListenerForSingleValueEvent.
    final class Wrapper {}

    /// The listener object the registration is removed by (identity).
    let identity: AnyObject
    let specKey: String
    let pathKey: String
    var isRemoved = false
    #if canImport(FirebaseCore) && canImport(FirebaseAuth) && canImport(FirebaseDatabase)
    var observers: [(DatabaseQuery, DatabaseHandle)] = []
    #endif

    init(identity: AnyObject, query: AQuery) {
        self.identity = identity
        self.specKey = query.specKey
        self.pathKey = query.pathKey
    }

    func detach() {
        isRemoved = true
        #if canImport(FirebaseCore) && canImport(FirebaseAuth) && canImport(FirebaseDatabase)
        for (query, handle) in observers {
            query.removeObserver(withHandle: handle)
        }
        observers = []
        #endif
    }
}

/// Active registrations (main thread only). Keeps the listeners alive while registered, like Android.
private enum AListenerRegistry {
    nonisolated(unsafe) static var registrations: [AListenerRegistration] = []

    static func add(_ registration: AListenerRegistration) {
        registrations.append(registration)
    }

    static func remove(_ listener: AnyObject, _ query: AQuery) {
        let anyQueryAtPath = query.isDefaultSpec
        let specKey = query.specKey
        let pathKey = query.pathKey
        let matches: (AListenerRegistration) -> Bool = { registration in
            registration.identity === listener
                && (anyQueryAtPath ? registration.pathKey == pathKey : registration.specKey == specKey)
        }
        let matching = registrations.filter(matches)
        registrations.removeAll(where: matches)
        for registration in matching {
            registration.detach()
        }
    }

    static func discard(_ registration: AListenerRegistration) {
        registrations.removeAll { $0 === registration }
        registration.detach()
    }
}

// MARK: - DataSnapshot

/// com.google.firebase.database.DataSnapshot: an immutable copy of the data at a location. `children` are in the
/// snapshot's index order (key order, or the query's order for a query result), each child in key order.
final class ADataSnapshot {
    let ref: ADatabaseReference?
    let key: String?
    let node: AFirebaseNode

    init(ref: ADatabaseReference?, key: String?, node: AFirebaseNode) {
        self.ref = ref
        self.key = key
        self.node = node
    }

    /// A snapshot of a Firebase iOS value (or its Swift equivalent), e.g. for tests.
    convenience init(key: String?, value: Any?) {
        self.init(ref: nil, key: key, node: AFirebaseCodec.node(fromFirebaseValue: value))
    }

    func getKey() -> String? {
        return key
    }

    func getRef() -> ADatabaseReference? {
        return ref
    }

    func exists() -> Bool {
        return !node.isEmpty
    }

    /// DataSnapshot.child(path) (path validated like DatabaseReference.child).
    func child(_ path: String) -> ADataSnapshot {
        if let problem = (ref?.path.isEmpty ?? true) ? AFirebaseCodec.rootPathProblem(path) : AFirebaseCodec.pathProblem(path) {
            preconditionFailure(problem)
        }
        let segments = AFirebaseCodec.pathSegments(path)
        return ADataSnapshot(ref: ref?.child(path), key: segments.last ?? key, node: node.child(path: segments))
    }

    func hasChild(_ path: String) -> Bool {
        return child(path).exists()
    }

    func hasChildren() -> Bool {
        return node.childCount > 0
    }

    /// DataSnapshot.getChildrenCount() (Kotlin Long).
    var childrenCount: Int64 {
        return Int64(node.childCount)
    }

    func getChildrenCount() -> Int64 {
        return childrenCount
    }

    var children: [ADataSnapshot] {
        return node.namedChildren.map { kid in
            ADataSnapshot(ref: ref?.child(kid.key), key: kid.key, node: kid.node)
        }
    }

    func getChildren() -> [ADataSnapshot] {
        return children
    }

    /// DataSnapshot.getValue(): nil, String, Bool, Int64, Double, [String: Any] or [Any] (Android's plain value).
    var value: Any? {
        return AFirebaseCodec.plainValue(node)
    }

    func getValue() -> Any? {
        return value
    }

    /// DataSnapshot.getPriority(): TripleShot never sets priorities.
    var priority: Any? {
        return nil
    }

    // Typed getValue(X::class.java). Android throws a DatabaseException on a type mismatch (a crash inside a
    // listener); here the mismatch is logged and nil returned, so callers fall back to their defaults.

    func getValue(_ type: String.Type) -> String? {
        return converted { try AFirebaseCodec.convertString($0) }
    }

    func getValue(_ type: Int64.Type) -> Int64? {
        return converted { try AFirebaseCodec.convertLong($0) }
    }

    func getValue(_ type: Int.Type) -> Int? {
        return converted { try AFirebaseCodec.convertInteger($0) }
    }

    func getValue(_ type: Double.Type) -> Double? {
        return converted { try AFirebaseCodec.convertDouble($0) }
    }

    func getValue(_ type: Float.Type) -> Float? {
        return converted { try AFirebaseCodec.convertFloat($0) }
    }

    func getValue(_ type: Bool.Type) -> Bool? {
        return converted { try AFirebaseCodec.convertBoolean($0) }
    }

    /// getValue(X::class.java) for a Kotlin wire class (missing keys keep the Kotlin defaults).
    func getValue<T: AFirebaseMappable>(_ type: T.Type) -> T? {
        do {
            return try T.fromFirebaseOrThrow(value)
        } catch {
            ADataSnapshot.report(error, key)
            return nil
        }
    }

    private func converted<T>(_ conversion: (Any) throws -> T) -> T? {
        guard let plain = value else { return nil }
        do {
            return try conversion(plain)
        } catch {
            ADataSnapshot.report(error, key)
            return nil
        }
    }

    fileprivate static func report(_ error: Error, _ key: String?) {
        ALog.w(AFirebaseCodec.LOG_TAG, "getValue(\(key ?? "<root>")) failed: \(error)")
    }

    #if canImport(FirebaseCore) && canImport(FirebaseAuth) && canImport(FirebaseDatabase)
    /// A FirebaseDatabase iOS snapshot: the top-level children keep the SDK's (query) order, deeper levels are
    /// key-ordered like Android's child snapshots.
    fileprivate convenience init(firebase snapshot: DataSnapshot, ref: ADatabaseReference?, key: String?) {
        self.init(ref: ref, key: key, node: ADataSnapshot.node(of: snapshot))
    }

    private static func node(of snapshot: DataSnapshot) -> AFirebaseNode {
        guard snapshot.hasChildren() else {
            return AFirebaseCodec.node(fromFirebaseValue: snapshot.value)
        }
        var kids: [AFirebaseNamedNode] = []
        for case let child as DataSnapshot in snapshot.children {
            let childNode = AFirebaseCodec.node(fromFirebaseValue: child.value)
            if !childNode.isEmpty {
                kids.append(AFirebaseNamedNode(key: child.key, node: childNode))
            }
        }
        return kids.isEmpty ? .empty : .children(kids)
    }
    #endif
}

// MARK: - MutableData and transactions

/// com.google.firebase.database.MutableData: the data at a transaction's location, read and replaced inside
/// Transaction.Handler.doTransaction.
final class AMutableData {
    /// One doTransaction run: the first exception Android would have thrown out of doTransaction.
    final class Run {
        fileprivate(set) var failure: Error?

        fileprivate func record(_ error: Error) {
            if failure == nil {
                failure = error
            }
        }
    }

    /// The tree a stand-alone MutableData edits (tests and offline use).
    private final class Holder {
        var root: AFirebaseNode

        init(_ root: AFirebaseNode) {
            self.root = root
        }
    }

    private enum Storage {
        case plain(Holder, [String])
        #if canImport(FirebaseCore) && canImport(FirebaseAuth) && canImport(FirebaseDatabase)
        case firebase(MutableData)
        #endif
    }

    private let storage: Storage
    let run: Run

    private init(storage: Storage, run: Run) {
        self.storage = storage
        self.run = run
    }

    /// A stand-alone MutableData holding a Firebase iOS value (or its Swift equivalent).
    convenience init(value: Any?) {
        self.init(storage: .plain(Holder(AFirebaseCodec.node(fromFirebaseValue: value)), []), run: Run())
    }

    #if canImport(FirebaseCore) && canImport(FirebaseAuth) && canImport(FirebaseDatabase)
    fileprivate convenience init(firebase data: MutableData) {
        self.init(storage: .firebase(data), run: Run())
    }
    #endif

    fileprivate var node: AFirebaseNode {
        switch storage {
        case .plain(let holder, let path):
            return holder.root.child(path: path)
        #if canImport(FirebaseCore) && canImport(FirebaseAuth) && canImport(FirebaseDatabase)
        case .firebase(let data):
            return AFirebaseCodec.node(fromFirebaseValue: data.value)
        #endif
        }
    }

    /// MutableData.getKey(): the last segment of the location, nil for the root.
    var key: String? {
        switch storage {
        case .plain(_, let path):
            return path.last
        #if canImport(FirebaseCore) && canImport(FirebaseAuth) && canImport(FirebaseDatabase)
        case .firebase(let data):
            return data.key
        #endif
        }
    }

    func getKey() -> String? {
        return key
    }

    /// MutableData.getValue() / setValue(value) (Kotlin `currentData.value`). Setting serializes with
    /// CustomClassMapper semantics; a value Android rejects (NaN, infinity, an invalid key) is recorded as the
    /// exception that aborts the transaction, and nothing is written.
    var value: Any? {
        get {
            return AFirebaseCodec.plainValue(node)
        }
        set {
            setValue(newValue)
        }
    }

    func getValue() -> Any? {
        return value
    }

    func setValue(_ newValue: Any?) {
        let plain = AFirebaseCodec.serialize(newValue)
        if let problem = AFirebaseCodec.writableObjectProblem(plain) {
            run.record(ADatabaseException(problem))
            return
        }
        switch storage {
        case .plain(let holder, let path):
            holder.root = holder.root.updatingChild(path: path[...], with: AFirebaseCodec.node(fromFirebaseValue: plain))
        #if canImport(FirebaseCore) && canImport(FirebaseAuth) && canImport(FirebaseDatabase)
        case .firebase(let data):
            data.value = AFirebaseCodec.firebaseValue(fromPlain: plain)
        #endif
        }
    }

    // Typed getValue(X::class.java). A type mismatch is recorded as the DatabaseException Android would throw
    // out of doTransaction (the transaction then aborts with USER_CODE_EXCEPTION) and nil returned.

    func getValue<T: AFirebaseMappable>(_ type: T.Type) -> T? {
        do {
            return try T.fromFirebaseOrThrow(value)
        } catch {
            run.record(AFirebaseCodec.databaseException(error))
            return nil
        }
    }

    func getValue(_ type: String.Type) -> String? {
        return converted { try AFirebaseCodec.convertString($0) }
    }

    func getValue(_ type: Int64.Type) -> Int64? {
        return converted { try AFirebaseCodec.convertLong($0) }
    }

    func getValue(_ type: Int.Type) -> Int? {
        return converted { try AFirebaseCodec.convertInteger($0) }
    }

    func getValue(_ type: Double.Type) -> Double? {
        return converted { try AFirebaseCodec.convertDouble($0) }
    }

    func getValue(_ type: Float.Type) -> Float? {
        return converted { try AFirebaseCodec.convertFloat($0) }
    }

    func getValue(_ type: Bool.Type) -> Bool? {
        return converted { try AFirebaseCodec.convertBoolean($0) }
    }

    private func converted<T>(_ conversion: (Any) throws -> T) -> T? {
        guard let plain = value else { return nil }
        do {
            return try conversion(plain)
        } catch {
            run.record(error)
            return nil
        }
    }

    func hasChildren() -> Bool {
        return node.childCount > 0
    }

    func hasChild(_ path: String) -> Bool {
        return !node.child(path: AFirebaseCodec.pathSegments(path)).isEmpty
    }

    /// MutableData.child(path): the mutable data at a child location of the same transaction.
    func child(_ path: String) -> AMutableData {
        if let problem = AFirebaseCodec.pathProblem(path) {
            preconditionFailure(problem)
        }
        switch storage {
        case .plain(let holder, let base):
            return AMutableData(storage: .plain(holder, base + AFirebaseCodec.pathSegments(path)), run: run)
        #if canImport(FirebaseCore) && canImport(FirebaseAuth) && canImport(FirebaseDatabase)
        case .firebase(let data):
            return AMutableData(storage: .firebase(data.childData(byAppendingPath: path)), run: run)
        #endif
        }
    }

    var childrenCount: Int64 {
        return Int64(node.childCount)
    }

    func getChildrenCount() -> Int64 {
        return childrenCount
    }

    var children: [AMutableData] {
        return node.namedChildren.map { child($0.key) }
    }

    func getChildren() -> [AMutableData] {
        return children
    }
}

private final class ATransactionRunState {
    var userError: ADatabaseError?
}

/// com.google.firebase.database.Transaction.
enum ATransaction {
    /// Transaction.Handler.
    protocol Handler: AnyObject {
        /// May run several times; return ATransaction.success(currentData) after setting its value, or abort().
        func doTransaction(_ currentData: AMutableData) -> ATransaction.Result
        /// Once, on the main thread: error (nil unless the transaction failed), committed, final data.
        func onComplete(_ error: ADatabaseError?, _ committed: Bool, _ currentData: ADataSnapshot?)
    }

    /// Transaction.Result.
    final class Result {
        let isSuccess: Bool
        fileprivate let data: AMutableData?

        fileprivate init(isSuccess: Bool, data: AMutableData?) {
            self.isSuccess = isSuccess
            self.data = data
        }

        func getIsSuccess() -> Bool {
            return isSuccess
        }
    }

    static func success(_ resultData: AMutableData) -> Result {
        return Result(isSuccess: true, data: resultData)
    }

    static func abort() -> Result {
        return Result(isSuccess: false, data: nil)
    }
}

// MARK: - ServerValue

/// com.google.firebase.database.ServerValue placeholders (the same dictionaries FirebaseDatabase iOS builds in
/// FIRServerValue.m).
enum AServerValue {
    /// ServerValue.TIMESTAMP: {".sv": "timestamp"}.
    nonisolated(unsafe) static let TIMESTAMP: [String: Any] = [".sv": "timestamp"]

    /// ServerValue.increment(long delta): {".sv": {"increment": delta}}.
    static func increment(_ delta: Int) -> [String: Any] {
        return [".sv": ["increment": Int64(delta)]]
    }

    static func increment(_ delta: Int64) -> [String: Any] {
        return [".sv": ["increment": delta]]
    }

    /// ServerValue.increment(double delta).
    static func increment(_ delta: Double) -> [String: Any] {
        return [".sv": ["increment": delta]]
    }
}
