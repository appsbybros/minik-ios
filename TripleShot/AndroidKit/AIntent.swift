import UIKit
import StoreKit

// AndroidKit intents (DESIGN 4.5/4.6): android.net.Uri, android.content.Intent and ActivityNotFoundException.
//
// Intents for the app's own activities (`AIntent(context, TripleShotX.self)`) are started by the AActivityHost
// (AActivity.startActivity). Everything else is "another app" on Android and maps to the iOS service that plays
// that role:
// * ACTION_VIEW http(s) -> UIApplication.open. A Google Play listing of THIS app (Settings "Rate this app") asks the
//   App Store for its rating prompt (AppStore.requestReview, the Splash precedent); a Play listing of another app
//   opens that app's family-catalogue iOS link, else its landing page, else the family directory.
// * ACTION_SEND (directly or through Intent.createChooser) -> the iOS share sheet with EXTRA_TEXT (own Play links
//   rewritten as above) and EXTRA_SUBJECT.
// * ACTION_SENDTO mailto: -> UIApplication.open(mailto:...?subject=EXTRA_SUBJECT&body=EXTRA_TEXT).
// An intent no iOS service can handle throws AActivityNotFoundException synchronously, like Android's
// startActivity, so the Kotlin `try { startActivity(i) } catch (ActivityNotFoundException)` blocks keep working.

// MARK: - Uri

/// android.net.Uri (the parts the app uses: parse, scheme, scheme-specific part, host, path, query parameters).
/// Like Android's StringUri it keeps the string exactly as given and parses lazily; `toString()` returns it.
final class AUri: CustomStringConvertible, Equatable, Hashable {
    private let uriString: String

    private init(_ uriString: String) { self.uriString = uriString }

    /// Uri.parse(uriString): never fails (Android builds a hierarchical/opaque Uri from any string).
    static func parse(_ uriString: String) -> AUri { AUri(uriString) }

    /// Uri.fromParts(scheme, ssp, fragment).
    static func fromParts(_ scheme: String, _ ssp: String, _ fragment: String?) -> AUri {
        var s = scheme + ":" + ssp
        if let f = fragment { s += "#" + f }
        return AUri(s)
    }

    /// Uri.EMPTY.
    static let EMPTY = AUri("")

    /// The index of the scheme separator: the first ':' before any '/', '?' or '#' (StringUri.findSchemeSeparator).
    private var schemeSeparator: Int? {
        for (i, c) in uriString.utf16.enumerated() {
            if c == 0x3A { return i }                          // ':'
            if c == 0x2F || c == 0x3F || c == 0x23 { return nil } // '/', '?', '#'
        }
        return nil
    }

    private func utf16Substring(_ start: Int, _ end: Int) -> String {
        let u = Array(uriString.utf16)
        let s = max(0, min(start, u.count)), e = max(s, min(end, u.count))
        return String(utf16CodeUnits: Array(u[s..<e]), count: e - s)
    }

    /// getScheme(): nil for a relative Uri.
    var scheme: String? {
        guard let sep = schemeSeparator, sep > 0 else { return nil }
        return utf16Substring(0, sep)
    }
    func getScheme() -> String? { scheme }

    /// getSchemeSpecificPart() (decoded like Android, % escapes resolved).
    var schemeSpecificPart: String {
        let u = uriString.utf16.count
        let start = (schemeSeparator ?? -1) + 1
        var end = u
        if let hash = uriString.utf16.firstIndex(of: 0x23) {
            end = uriString.utf16.distance(from: uriString.utf16.startIndex, to: hash)
        }
        let raw = utf16Substring(start, max(start, end))
        return raw.removingPercentEncoding ?? raw
    }
    func getSchemeSpecificPart() -> String { schemeSpecificPart }

    var isHierarchical: Bool {
        guard let sep = schemeSeparator else { return true }
        let u = Array(uriString.utf16)
        return u.count > sep + 1 && u[sep + 1] == 0x2F
    }
    var isOpaque: Bool { !isHierarchical }

    private var components: URLComponents? { URLComponents(string: uriString) }

    /// getHost().
    var host: String? { isHierarchical ? components?.host : nil }
    func getHost() -> String? { host }

    /// getPath().
    var path: String? { isHierarchical ? components?.path : nil }
    func getPath() -> String? { path }

    /// getQueryParameter(key): the first value, decoded ('+' stays '+', like Android).
    func getQueryParameter(_ key: String) -> String? {
        guard isHierarchical, let items = components?.queryItems else { return nil }
        return items.first(where: { $0.name == key })?.value
    }

    /// The Foundation URL of this Uri (nil when the string is not a valid URL).
    var url: URL? {
        if let u = URL(string: uriString) { return u }
        return URL(string: uriString.addingPercentEncoding(withAllowedCharacters: .urlFragmentAllowed) ?? uriString)
    }

    func toString() -> String { uriString }
    var description: String { uriString }

    static func == (a: AUri, b: AUri) -> Bool { a.uriString == b.uriString }
    func hash(into hasher: inout Hasher) { hasher.combine(uriString) }
}

// MARK: - ActivityNotFoundException

/// android.content.ActivityNotFoundException: no activity (iOS service) handles the intent.
struct AActivityNotFoundException: Error, CustomStringConvertible {
    let message: String
    init(_ message: String) { self.message = message }
    var localizedDescription: String { message }
    var description: String { "android.content.ActivityNotFoundException: " + message }
}

// MARK: - Intent

/// android.content.Intent: action, data, type, categories, flags, extras (an ABundle) and the explicit component
/// (an AActivity subclass of this app).
final class AIntent: CustomStringConvertible {
    static let ACTION_MAIN = "android.intent.action.MAIN"
    static let ACTION_VIEW = "android.intent.action.VIEW"
    static let ACTION_SEND = "android.intent.action.SEND"
    static let ACTION_SENDTO = "android.intent.action.SENDTO"
    static let ACTION_CHOOSER = "android.intent.action.CHOOSER"
    static let ACTION_DIAL = "android.intent.action.DIAL"

    static let CATEGORY_DEFAULT = "android.intent.category.DEFAULT"
    static let CATEGORY_BROWSABLE = "android.intent.category.BROWSABLE"
    static let CATEGORY_LAUNCHER = "android.intent.category.LAUNCHER"

    static let EXTRA_TEXT = "android.intent.extra.TEXT"
    static let EXTRA_SUBJECT = "android.intent.extra.SUBJECT"
    static let EXTRA_EMAIL = "android.intent.extra.EMAIL"
    static let EXTRA_TITLE = "android.intent.extra.TITLE"
    static let EXTRA_INTENT = "android.intent.extra.INTENT"

    static let FLAG_ACTIVITY_NEW_TASK = 0x10000000
    static let FLAG_ACTIVITY_CLEAR_TOP = 0x04000000
    static let FLAG_ACTIVITY_SINGLE_TOP = 0x20000000
    static let FLAG_ACTIVITY_CLEAR_TASK = 0x00008000
    static let FLAG_ACTIVITY_NO_ANIMATION = 0x00010000

    private var mAction: String?
    private var mData: AUri?
    private var mType: String?
    private var mCategories: [String] = []
    private(set) var flags: Int = 0
    private var mExtras: ABundle?
    /// The explicit component: an activity class of this app (Intent(packageContext, cls) / setClass).
    private(set) var componentClass: AActivity.Type?
    /// The chooser target (Intent.createChooser), Android's EXTRA_INTENT.
    private var chooserTarget: AIntent?

    init() {}

    /// Intent(action).
    init(_ action: String?) { mAction = action }

    /// Intent(action, uri).
    init(_ action: String?, _ uri: AUri?) {
        mAction = action
        mData = uri
    }

    /// Intent(packageContext, cls): an explicit intent for one of the app's activities.
    init(_ packageContext: AContext?, _ cls: AActivity.Type) {
        componentClass = cls
    }

    /// Intent(o): a copy (extras copied, not shared).
    init(_ o: AIntent) {
        mAction = o.mAction
        mData = o.mData
        mType = o.mType
        mCategories = o.mCategories
        flags = o.flags
        mExtras = o.mExtras.map { ABundle($0) }
        componentClass = o.componentClass
        chooserTarget = o.chooserTarget
    }

    // MARK: Action, data, type

    var action: String? {
        get { mAction }
        set { mAction = newValue }
    }
    func getAction() -> String? { mAction }
    @discardableResult func setAction(_ action: String?) -> AIntent { mAction = action; return self }

    /// Intent.getData() / setData(): setting the data clears the type (Android setData).
    var data: AUri? {
        get { mData }
        set { mData = newValue; mType = nil }
    }
    func getData() -> AUri? { mData }
    @discardableResult func setData(_ data: AUri?) -> AIntent { self.data = data; return self }
    var dataString: String? { mData?.toString() }

    /// Intent.getType() / setType(): setting the type clears the data (Android setType).
    var type: String? {
        get { mType }
        set { mType = newValue; mData = nil }
    }
    func getType() -> String? { mType }
    @discardableResult func setType(_ type: String?) -> AIntent { self.type = type; return self }
    @discardableResult func setDataAndType(_ data: AUri?, _ type: String?) -> AIntent {
        mData = data
        mType = type
        return self
    }

    var scheme: String? { mData?.scheme }

    // MARK: Categories and flags

    var categories: [String] { mCategories }
    func getCategories() -> [String]? { mCategories.isEmpty ? nil : mCategories }
    @discardableResult func addCategory(_ category: String) -> AIntent {
        if !mCategories.contains(category) { mCategories.append(category) }
        return self
    }
    func removeCategory(_ category: String) { mCategories.removeAll { $0 == category } }
    func hasCategory(_ category: String) -> Bool { mCategories.contains(category) }

    @discardableResult func addFlags(_ flags: Int) -> AIntent { self.flags |= flags; return self }
    @discardableResult func setFlags(_ flags: Int) -> AIntent { self.flags = flags; return self }
    func getFlags() -> Int { flags }

    // MARK: Component

    @discardableResult func setClass(_ packageContext: AContext?, _ cls: AActivity.Type) -> AIntent {
        componentClass = cls
        return self
    }

    // MARK: Extras (Intent.putExtra overloads return the intent, like Android)

    private var extrasForWrite: ABundle {
        if let e = mExtras { return e }
        let e = ABundle()
        mExtras = e
        return e
    }

    @discardableResult func putExtra(_ name: String, _ value: String?) -> AIntent { extrasForWrite.putString(name, value); return self }
    @discardableResult func putExtra(_ name: String, _ value: Bool) -> AIntent { extrasForWrite.putBoolean(name, value); return self }
    @discardableResult func putExtra(_ name: String, _ value: Int) -> AIntent { extrasForWrite.putInt(name, value); return self }
    @discardableResult func putExtra(_ name: String, _ value: Int64) -> AIntent { extrasForWrite.putLong(name, value); return self }
    @discardableResult func putExtra(_ name: String, _ value: Float) -> AIntent { extrasForWrite.putFloat(name, value); return self }
    @discardableResult func putExtra(_ name: String, _ value: Double) -> AIntent { extrasForWrite.putDouble(name, value); return self }
    @discardableResult func putExtra(_ name: String, _ value: [String]?) -> AIntent { extrasForWrite.putStringArray(name, value); return self }
    @discardableResult func putExtra(_ name: String, _ value: ABundle?) -> AIntent { extrasForWrite.putBundle(name, value); return self }
    @discardableResult func putExtras(_ extras: ABundle) -> AIntent { extrasForWrite.putAll(extras); return self }
    @discardableResult func putStringArrayListExtra(_ name: String, _ value: [String]?) -> AIntent {
        extrasForWrite.putStringArrayList(name, value)
        return self
    }

    func hasExtra(_ name: String) -> Bool { mExtras?.containsKey(name) ?? false }
    func removeExtra(_ name: String) { mExtras?.remove(name) }
    /// Intent.getExtras(): a copy of the extras, nil when there are none.
    var extras: ABundle? { mExtras.map { ABundle($0) } }
    func getExtras() -> ABundle? { extras }

    func getStringExtra(_ name: String) -> String? { mExtras?.getString(name) }
    func getBooleanExtra(_ name: String, _ defaultValue: Bool) -> Bool { mExtras?.getBoolean(name, defaultValue) ?? defaultValue }
    func getIntExtra(_ name: String, _ defaultValue: Int) -> Int { mExtras?.getInt(name, defaultValue) ?? defaultValue }
    func getLongExtra(_ name: String, _ defaultValue: Int64) -> Int64 { mExtras?.getLong(name, defaultValue) ?? defaultValue }
    func getFloatExtra(_ name: String, _ defaultValue: Float) -> Float { mExtras?.getFloat(name, defaultValue) ?? defaultValue }
    func getDoubleExtra(_ name: String, _ defaultValue: Double) -> Double { mExtras?.getDouble(name, defaultValue) ?? defaultValue }
    func getStringArrayExtra(_ name: String) -> [String]? { mExtras?.getStringArray(name) }
    func getStringArrayListExtra(_ name: String) -> [String]? { mExtras?.getStringArrayList(name) }
    func getBundleExtra(_ name: String) -> ABundle? { mExtras?.getBundle(name) }

    // MARK: Chooser

    /// Intent.createChooser(target, title): ACTION_CHOOSER carrying the target (EXTRA_INTENT) and the title.
    static func createChooser(_ target: AIntent, _ title: String?) -> AIntent {
        let chooser = AIntent(AIntent.ACTION_CHOOSER)
        chooser.chooserTarget = target
        if let t = title { chooser.putExtra(AIntent.EXTRA_TITLE, t) }
        return chooser
    }

    var description: String {
        var parts: [String] = []
        if let a = mAction { parts.append("act=" + a) }
        if !mCategories.isEmpty { parts.append("cat=[" + mCategories.joined(separator: ",") + "]") }
        if let d = mData { parts.append("dat=" + d.toString()) }
        if let t = mType { parts.append("typ=" + t) }
        if flags != 0 { parts.append("flg=0x" + String(flags, radix: 16)) }
        if let c = componentClass { parts.append("cmp=" + String(describing: c)) }
        if mExtras != nil { parts.append("(has extras)") }
        return "Intent { " + parts.joined(separator: " ") + " }"
    }

    // MARK: - External dispatch (other apps on Android, iOS services here)

    /// Package names and Play listings: `https://play.google.com/store/apps/details?id=<package>`.
    static func playListingPackage(_ uri: AUri?) -> String? {
        guard let uri = uri, let scheme = uri.scheme?.lowercased(), scheme == "https" || scheme == "http" || scheme == "market" else {
            return nil
        }
        if scheme == "market" { return uri.getQueryParameter("id") }
        guard let host = uri.host?.lowercased(), host == "play.google.com" else { return nil }
        guard let path = uri.path, path.hasPrefix("/store/apps/details") else { return nil }
        return uri.getQueryParameter("id")
    }

    /// The iOS link for a Google Play listing: the family catalogue's iOS link of that app, else its landing page,
    /// else the family directory (FamilyCatalog, the family module's own rule for links to sibling apps).
    static func iosLinkForPlayListing(_ package: String) -> String {
        let catalogue = FamilyCatalog.load()
        if let entry = catalogue.entries.first(where: { $0.applicationId == package || $0.aliases.contains(package) }) {
            if !entry.iosUrl.isEmpty { return entry.iosUrl }
            if !entry.landingUrl.isEmpty { return entry.landingUrl }
        }
        return FamilyCatalog.directory
    }

    /// Rewrites every Google Play listing URL inside a shared text to its iOS link (see iosLinkForPlayListing).
    static func rewritePlayLinks(_ text: String) -> String {
        let pattern = "(?:https?://)?play\\.google\\.com/store/apps/details\\?id=([A-Za-z0-9_.]+)[A-Za-z0-9_.&=%-]*"
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return text }
        let ns = text as NSString
        var out = ""
        var last = 0
        for match in regex.matches(in: text, range: NSRange(location: 0, length: ns.length)) {
            out += ns.substring(with: NSRange(location: last, length: match.range.location - last))
            out += iosLinkForPlayListing(ns.substring(with: match.range(at: 1)))
            last = match.range.location + match.range.length
        }
        out += ns.substring(from: last)
        return out
    }

    /// Activity.startActivity for an intent that leaves the app. Throws AActivityNotFoundException when nothing on
    /// iOS can handle it (Android: no matching activity).
    static func dispatchExternal(_ intent: AIntent, from activity: AActivity?) throws {
        if intent.componentClass != nil {
            preconditionFailure("dispatchExternal called with an explicit app activity intent")
        }
        switch intent.action {
        case ACTION_CHOOSER?:
            guard let target = intent.chooserTarget else { throw AActivityNotFoundException("No Activity found to handle " + intent.description) }
            try dispatchChooserTarget(target, title: intent.getStringExtra(EXTRA_TITLE), from: activity)
        case ACTION_SEND?:
            try presentShareSheet(target: intent, from: activity)
        case ACTION_SENDTO?:
            try openMailTo(intent)
        case ACTION_VIEW?:
            try openView(intent)
        case ACTION_DIAL?:
            guard let data = intent.data, let url = data.url, data.scheme?.lowercased() == "tel" else {
                throw AActivityNotFoundException("No Activity found to handle " + intent.description)
            }
            try openURL(url, intent)
        default:
            throw AActivityNotFoundException("No Activity found to handle " + intent.description)
        }
    }

    private static func dispatchChooserTarget(_ target: AIntent, title: String?, from activity: AActivity?) throws {
        // Android's chooser lists the matching apps; iOS's share sheet is the chooser for ACTION_SEND. A chooser
        // around another action opens that action directly (the system picks the app).
        if target.action == ACTION_SEND {
            try presentShareSheet(target: target, from: activity)
        } else {
            try dispatchExternal(target, from: activity)
        }
    }

    private static func openView(_ intent: AIntent) throws {
        guard let data = intent.data else { throw AActivityNotFoundException("No Activity found to handle " + intent.description) }
        if let package = playListingPackage(data) {
            if package == AResources.packageName {
                // The app's own store listing ("Rate this app"): the App Store rating prompt (Splash precedent).
                guard let scene = activeWindowScene() else { throw AActivityNotFoundException("No window to show the rating prompt") }
                MainActor.assumeIsolated { AppStore.requestReview(in: scene) }
                return
            }
            guard let url = URL(string: iosLinkForPlayListing(package)) else {
                throw AActivityNotFoundException("No Activity found to handle " + intent.description)
            }
            try openURL(url, intent)
            return
        }
        guard let scheme = data.scheme?.lowercased(), let url = data.url else {
            throw AActivityNotFoundException("No Activity found to handle " + intent.description)
        }
        if scheme == "http" || scheme == "https" {
            // canOpenURL needs no Info.plist declaration for http(s); false only when nothing can browse.
            guard UIApplication.shared.canOpenURL(url) else {
                throw AActivityNotFoundException("No Activity found to handle " + intent.description)
            }
        }
        try openURL(url, intent)
    }

    private static func openURL(_ url: URL, _ intent: AIntent) throws {
        UIApplication.shared.open(url, options: [:]) { opened in
            if !opened { ALog.w("AIntent", "iOS could not open " + intent.description) }
        }
    }

    /// ACTION_SENDTO mailto:address -> the default mail app with EXTRA_SUBJECT / EXTRA_TEXT (/ EXTRA_EMAIL).
    private static func openMailTo(_ intent: AIntent) throws {
        guard let data = intent.data, data.scheme?.lowercased() == "mailto" else {
            throw AActivityNotFoundException("No Activity found to handle " + intent.description)
        }
        var mail = URLComponents()
        mail.scheme = "mailto"
        var recipients = data.schemeSpecificPart
        var existingQuery: [URLQueryItem] = []
        if let q = recipients.firstIndex(of: "?") {
            existingQuery = URLComponents(string: "mailto:" + recipients)?.queryItems ?? []
            recipients = String(recipients[..<q])
        }
        if let extra = intent.getStringArrayExtra(EXTRA_EMAIL), !extra.isEmpty {
            recipients = ([recipients].filter { !$0.isEmpty } + extra).joined(separator: ",")
        }
        mail.path = recipients
        var items = existingQuery
        if let subject = intent.getStringExtra(EXTRA_SUBJECT) { items.append(URLQueryItem(name: "subject", value: subject)) }
        if let body = intent.getStringExtra(EXTRA_TEXT) { items.append(URLQueryItem(name: "body", value: body)) }
        if !items.isEmpty { mail.queryItems = items }
        guard let url = mail.url else { throw AActivityNotFoundException("No Activity found to handle " + intent.description) }
        try openURL(url, intent)
    }

    /// ACTION_SEND -> UIActivityViewController with the text (and the subject for mail targets).
    private static func presentShareSheet(target: AIntent, from activity: AActivity?) throws {
        let text = target.getStringExtra(EXTRA_TEXT).map(rewritePlayLinks)
        let subject = target.getStringExtra(EXTRA_SUBJECT)
        guard let shareText = text, !shareText.isEmpty else {
            throw AActivityNotFoundException("No Activity found to handle " + target.description)
        }
        guard let presenter = topPresenter(activity) else {
            throw AActivityNotFoundException("No window to present the share sheet")
        }
        let item = KitShareItem(text: shareText, subject: subject)
        let sheet = UIActivityViewController(activityItems: [item], applicationActivities: nil)
        if let pop = sheet.popoverPresentationController {
            // iPad: anchor at the bottom centre of the window, like Android's bottom-sheet chooser.
            pop.sourceView = presenter.view
            let b = presenter.view.bounds
            pop.sourceRect = CGRect(x: b.midX, y: b.maxY - 1, width: 1, height: 1)
            pop.permittedArrowDirections = []
        }
        presenter.present(sheet, animated: true)
    }

    static func activeWindowScene() -> UIWindowScene? {
        let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
        return scenes.first(where: { $0.activationState == .foregroundActive }) ?? scenes.first
    }

    /// The view controller to present a system sheet from: the activity host (topmost presented controller).
    private static func topPresenter(_ activity: AActivity?) -> UIViewController? {
        var vc: UIViewController? = AActivityHost.shared ?? activity
        if vc == nil {
            vc = activeWindowScene()?.windows.first(where: { $0.isKeyWindow })?.rootViewController
        }
        while let presented = vc?.presentedViewController { vc = presented }
        return vc
    }
}

/// The shared text of an ACTION_SEND, with EXTRA_SUBJECT as the subject for mail-like targets.
private final class KitShareItem: NSObject, UIActivityItemSource {
    let text: String
    let subject: String?

    init(text: String, subject: String?) {
        self.text = text
        self.subject = subject
    }

    func activityViewControllerPlaceholderItem(_ activityViewController: UIActivityViewController) -> Any { text }

    func activityViewController(_ activityViewController: UIActivityViewController,
                                itemForActivityType activityType: UIActivity.ActivityType?) -> Any? { text }

    func activityViewController(_ activityViewController: UIActivityViewController,
                                subjectForActivityType activityType: UIActivity.ActivityType?) -> String { subject ?? "" }
}
