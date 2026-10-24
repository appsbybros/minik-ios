import UIKit

// AndroidKit app structure (DESIGN 4.5): android.content.Context, android.content.res.Configuration,
// androidx.lifecycle, androidx.activity (OnBackPressedDispatcher), android.view.Window (+ WindowCompat,
// WindowInsetsControllerCompat), android.app.Activity / androidx FragmentActivity, and the iOS host that runs the
// activity stack (the Android task) inside the scene's UIWindow.
//
// Ported from the real sources the app links (androidx.activity 1.8.1, androidx.fragment 1.8.9,
// androidx.lifecycle 2.8, framework android-36): lifecycle event order, back dispatch order (newest enabled
// callback first, lifecycle-bound callbacks only while STARTED), activity transition order (A.onPause, B.onCreate,
// B.onStart, B.onResume, then A.onStop), onConfigurationChanged for the declared configChanges, and Android 15+
// edge-to-edge enforcement for targetSdk 36 (setDecorFitsSystemWindows / status- and navigation-bar colours are
// ignored, exactly as PhoneWindow does on the owner's Pixel 6).

// MARK: - Context

/// android.content.Context. The activity is the context (DESIGN 4.5: requireContext returns the activity);
/// `applicationContext` is the process-wide AApplication.
protocol AContext: AnyObject {}

extension AContext {
    /// Context.getResources().
    var resources: AContextResources { AContextResources.shared }
    /// Context.getApplicationContext().
    var applicationContext: AContext { AApplication.shared }
    /// Context.getPackageName(): the Android package (used in Play links and getIdentifier calls).
    var packageName: String { AResources.packageName }
    /// Context.getString(id).
    func getString(_ id: AStringRes) -> String { AResources.getString(id) }
    /// Context.getString(id, formatArgs): `String.format(configuration.locales[0], raw, args)`.
    func getString(_ id: AStringRes, _ args: Any?...) -> String {
        AFormat.format(ALocale.getDefault(), AResources.getString(id), args)
    }
    /// Context.getText(id).
    func getText(_ id: AStringRes) -> String { AResources.getText(id) }
    /// Context.getSharedPreferences(name, mode).
    func getSharedPreferences(_ name: String, _ mode: Int) -> ASharedPreferences { kitSharedPreferences(name, mode) }
    /// Context.getDrawable(id) / ContextCompat.getDrawable(context, id).
    func getDrawable(_ id: ADrawableRes) -> ADrawable? { kitContextDrawable(id) }
    /// Context.getColor(id): R.color already holds the ARGB value.
    func getColor(_ color: Int) -> Int { color }
    /// Context.startActivity from a non-activity context: the current top activity starts it.
    func startActivity(_ intent: AIntent) throws {
        if let activity = self as? AActivity {
            try activity.startActivity(intent)
        } else if let top = AActivityHost.shared?.topActivity {
            try top.startActivity(intent)
        } else {
            try AIntent.dispatchExternal(intent, from: nil)
        }
    }
}

// File-scope forwarders: inside the extension the member names would shadow the global functions.
private func kitSharedPreferences(_ name: String, _ mode: Int) -> ASharedPreferences { getSharedPreferences(name, mode) }
private func kitContextDrawable(_ id: ADrawableRes) -> ADrawable? { ContextCompat_getDrawable(id) }

/// android.app.Application: the application context (`context.applicationContext`).
final class AApplication: AContext {
    static let shared = AApplication()
    private init() {}

    /// Application.mActivityLifecycleCallbacks (registration order; a copy is iterated, like collectActivityLifecycleCallbacks).
    private var activityLifecycleCallbacks: [AActivityLifecycleCallbacks] = []

    /// Application.registerActivityLifecycleCallbacks.
    func registerActivityLifecycleCallbacks(_ callback: AActivityLifecycleCallbacks) {
        activityLifecycleCallbacks.append(callback)
    }

    /// Application.unregisterActivityLifecycleCallbacks (removes the first registration of that object).
    func unregisterActivityLifecycleCallbacks(_ callback: AActivityLifecycleCallbacks) {
        if let i = activityLifecycleCallbacks.firstIndex(where: { $0 === callback }) { activityLifecycleCallbacks.remove(at: i) }
    }

    /// Application.dispatchActivityCreated / Started / Resumed / Paused / Stopped / Destroyed, called from the
    /// Activity's own onCreate/onStart/onResume/onPause/onStop/onDestroy (so before the fragments of FragmentActivity).
    func dispatchActivityCreated(_ activity: AActivity, _ savedInstanceState: ABundle?) {
        for c in activityLifecycleCallbacks { c.onActivityCreated(activity, savedInstanceState) }
    }
    func dispatchActivityStarted(_ activity: AActivity) { for c in activityLifecycleCallbacks { c.onActivityStarted(activity) } }
    func dispatchActivityResumed(_ activity: AActivity) { for c in activityLifecycleCallbacks { c.onActivityResumed(activity) } }
    func dispatchActivityPaused(_ activity: AActivity) { for c in activityLifecycleCallbacks { c.onActivityPaused(activity) } }
    func dispatchActivityStopped(_ activity: AActivity) { for c in activityLifecycleCallbacks { c.onActivityStopped(activity) } }
    func dispatchActivityDestroyed(_ activity: AActivity) {
        for c in activityLifecycleCallbacks { c.onActivityDestroyed(activity) }
    }
}

/// android.app.Application.ActivityLifecycleCallbacks (every method has an empty default, like the Java interface's
/// optional pre/post methods; the app implements the ones it needs).
protocol AActivityLifecycleCallbacks: AnyObject {
    func onActivityCreated(_ activity: AActivity, _ savedInstanceState: ABundle?)
    func onActivityStarted(_ activity: AActivity)
    func onActivityResumed(_ activity: AActivity)
    func onActivityPaused(_ activity: AActivity)
    func onActivityStopped(_ activity: AActivity)
    func onActivitySaveInstanceState(_ activity: AActivity, _ outState: ABundle)
    func onActivityDestroyed(_ activity: AActivity)
}

extension AActivityLifecycleCallbacks {
    func onActivityCreated(_ activity: AActivity, _ savedInstanceState: ABundle?) {}
    func onActivityStarted(_ activity: AActivity) {}
    func onActivityResumed(_ activity: AActivity) {}
    func onActivityPaused(_ activity: AActivity) {}
    func onActivityStopped(_ activity: AActivity) {}
    func onActivitySaveInstanceState(_ activity: AActivity, _ outState: ABundle) {}
    func onActivityDestroyed(_ activity: AActivity) {}
}

/// android.content.res.Resources as reached through `context.resources` / `fragment.resources`: the configuration
/// of the app window plus the AResources getters (same semantics as the global getString/getQuantityString).
final class AContextResources {
    static let shared = AContextResources()
    private init() {}

    /// Resources.getConfiguration(): the current configuration of the app window.
    var configuration: AConfiguration { AConfiguration.current }
    func getConfiguration() -> AConfiguration { AConfiguration.current }
    /// Resources.getDisplayMetrics().
    var displayMetrics: ADisplayMetrics { AResources.displayMetrics }
    func getDisplayMetrics() -> ADisplayMetrics { AResources.displayMetrics }

    func getString(_ id: AStringRes) -> String { AResources.getString(id) }
    func getString(_ id: AStringRes, _ args: Any?...) -> String {
        AFormat.format(ALocale.getDefault(), AResources.getString(id), args)
    }
    func getQuantityString(_ id: AStringRes, _ quantity: Int) -> String { AResources.getQuantityString(id, quantity) }
    func getQuantityString(_ id: AStringRes, _ quantity: Int, _ args: Any?...) -> String {
        AFormat.format(ALocale.getDefault(), AResources.getQuantityString(id, quantity), args)
    }
    func getStringArray(_ id: AStringRes) -> [String] { AResources.getStringArray(id) }
    func getText(_ id: AStringRes) -> String { AResources.getText(id) }
    /// Resources.getIdentifier(name, defType, defPackage): nil where Android returns 0.
    func getIdentifier(_ name: String, _ defType: String, _ defPackage: String? = nil) -> String? {
        if let package = defPackage, !package.isEmpty, !name.contains(":") {
            return AResources.getIdentifier(package + ":" + name, defType)
        }
        return AResources.getIdentifier(name, defType)
    }
    /// Resources.getColor(id, theme).
    func getColor(_ color: Int, _ theme: Any? = nil) -> Int { color }
    /// Resources.getDrawable(id, theme).
    func getDrawable(_ id: ADrawableRes, _ theme: Any? = nil) -> ADrawable? { kitContextDrawable(id) }
}

// MARK: - Configuration

/// java.util.LocaleList / android.os.LocaleList: the device's preferred languages, first = default locale.
final class ALocaleList: CustomStringConvertible {
    let locales: [ALocale]

    init(_ locales: [ALocale]) { self.locales = locales }

    /// LocaleList.getDefault(): the iOS preferred-language list (first entry = ALocale.getDefault()).
    static func getDefault() -> ALocaleList {
        let tags = Locale.preferredLanguages
        if tags.isEmpty { return ALocaleList([ALocale.getDefault()]) }
        return ALocaleList(tags.map { ALocale.forLanguageTag($0) })
    }

    func get(_ index: Int) -> ALocale { locales[index] }
    subscript(index: Int) -> ALocale { locales[index] }
    func size() -> Int { locales.count }
    var isEmpty: Bool { locales.isEmpty }
    func toLanguageTags() -> String { locales.map { $0.toLanguageTag() }.joined(separator: ",") }
    var description: String { "[" + locales.map { $0.description }.joined(separator: ",") + "]" }
}

/// androidx.core.os.LocaleListCompat: `get(i)` / `[i]` return nil out of range (Kotlin `?: Locale.getDefault()`).
final class ALocaleListCompat {
    private let list: ALocaleList
    init(_ list: ALocaleList) { self.list = list }
    func get(_ index: Int) -> ALocale? { index >= 0 && index < list.locales.count ? list.locales[index] : nil }
    subscript(index: Int) -> ALocale? { self.get(index) }
    func size() -> Int { list.locales.count }
    var isEmpty: Bool { list.locales.isEmpty }
}

/// androidx.core.os.ConfigurationCompat.
enum AConfigurationCompat {
    static func getLocales(_ configuration: AConfiguration) -> ALocaleListCompat { ALocaleListCompat(configuration.locales) }
}

/// android.content.res.Configuration of the app window (immutable snapshot; `AConfiguration.current` is replaced
/// on every change). Sizes are window sizes in dp (= iOS points), like targetSdk 35+ on Android 15, where
/// screenWidthDp/HeightDp and orientation include the system bars.
final class AConfiguration: CustomStringConvertible {
    static let ORIENTATION_UNDEFINED = 0
    static let ORIENTATION_PORTRAIT = 1
    static let ORIENTATION_LANDSCAPE = 2
    static let ORIENTATION_SQUARE = 3

    static let UI_MODE_TYPE_MASK = 0x0f
    static let UI_MODE_TYPE_UNDEFINED = 0x00
    static let UI_MODE_TYPE_NORMAL = 0x01
    static let UI_MODE_NIGHT_MASK = 0x30
    static let UI_MODE_NIGHT_UNDEFINED = 0x00
    static let UI_MODE_NIGHT_NO = 0x10
    static let UI_MODE_NIGHT_YES = 0x20

    static let SCREENLAYOUT_SIZE_MASK = 0x0f
    static let SCREENLAYOUT_SIZE_SMALL = 0x01
    static let SCREENLAYOUT_SIZE_NORMAL = 0x02
    static let SCREENLAYOUT_SIZE_LARGE = 0x03
    static let SCREENLAYOUT_SIZE_XLARGE = 0x04
    static let SCREENLAYOUT_LONG_MASK = 0x30
    static let SCREENLAYOUT_LONG_NO = 0x10
    static let SCREENLAYOUT_LONG_YES = 0x20
    static let SCREENLAYOUT_LAYOUTDIR_MASK = 0xC0
    static let SCREENLAYOUT_LAYOUTDIR_LTR = 0x40
    static let SCREENLAYOUT_LAYOUTDIR_RTL = 0x80

    static let TOUCHSCREEN_FINGER = 3
    static let KEYBOARD_NOKEYS = 1
    static let KEYBOARDHIDDEN_YES = 2
    static let NAVIGATION_NONAV = 1

    let orientation: Int
    let screenWidthDp: Int
    let screenHeightDp: Int
    let smallestScreenWidthDp: Int
    let densityDpi: Int
    let fontScale: Float
    let uiMode: Int
    let screenLayout: Int
    let locales: ALocaleList
    let touchscreen = AConfiguration.TOUCHSCREEN_FINGER
    let keyboard = AConfiguration.KEYBOARD_NOKEYS
    let keyboardHidden = AConfiguration.KEYBOARDHIDDEN_YES
    let navigation = AConfiguration.NAVIGATION_NONAV
    let mcc = 0
    let mnc = 0

    init(orientation: Int, screenWidthDp: Int, screenHeightDp: Int, smallestScreenWidthDp: Int, densityDpi: Int,
         fontScale: Float, uiMode: Int, locales: ALocaleList) {
        self.orientation = orientation
        self.screenWidthDp = screenWidthDp
        self.screenHeightDp = screenHeightDp
        self.smallestScreenWidthDp = smallestScreenWidthDp
        self.densityDpi = densityDpi
        self.fontScale = fontScale
        self.uiMode = uiMode
        self.locales = locales
        self.screenLayout = AConfiguration.computeScreenLayout(screenWidthDp, screenHeightDp, locales)
    }

    /// `new Configuration(other)`.
    convenience init(_ other: AConfiguration) {
        self.init(orientation: other.orientation, screenWidthDp: other.screenWidthDp, screenHeightDp: other.screenHeightDp,
                  smallestScreenWidthDp: other.smallestScreenWidthDp, densityDpi: other.densityDpi,
                  fontScale: other.fontScale, uiMode: other.uiMode, locales: other.locales)
    }

    /// Configuration.locale (deprecated): the first locale.
    var locale: ALocale { locales.locales.first ?? ALocale.getDefault() }
    func getLocales() -> ALocaleList { locales }
    /// Configuration.getLayoutDirection(): RTL for the right-to-left scripts of the primary locale.
    var layoutDirection: Int { AConfiguration.isRtl(locale) ? 1 : 0 }
    func getLayoutDirection() -> Int { layoutDirection }
    /// True in night mode (uiMode & UI_MODE_NIGHT_MASK == UI_MODE_NIGHT_YES).
    var isNightModeActive: Bool { (uiMode & AConfiguration.UI_MODE_NIGHT_MASK) == AConfiguration.UI_MODE_NIGHT_YES }

    /// The CONFIG_* bits (AActivityInfo) that differ between this and `other`, like Configuration.diff.
    func diff(_ other: AConfiguration) -> Int {
        var changes = 0
        if orientation != other.orientation { changes |= AActivityInfo.CONFIG_ORIENTATION }
        if screenWidthDp != other.screenWidthDp || screenHeightDp != other.screenHeightDp {
            changes |= AActivityInfo.CONFIG_SCREEN_SIZE
        }
        if smallestScreenWidthDp != other.smallestScreenWidthDp { changes |= AActivityInfo.CONFIG_SMALLEST_SCREEN_SIZE }
        if (screenLayout & ~AConfiguration.SCREENLAYOUT_LAYOUTDIR_MASK)
            != (other.screenLayout & ~AConfiguration.SCREENLAYOUT_LAYOUTDIR_MASK) {
            changes |= AActivityInfo.CONFIG_SCREEN_LAYOUT
        }
        if densityDpi != other.densityDpi { changes |= AActivityInfo.CONFIG_DENSITY }
        if fontScale != other.fontScale { changes |= AActivityInfo.CONFIG_FONT_SCALE }
        if uiMode != other.uiMode { changes |= AActivityInfo.CONFIG_UI_MODE }
        if locales.toLanguageTags() != other.locales.toLanguageTags() { changes |= AActivityInfo.CONFIG_LOCALE }
        if layoutDirection != other.layoutDirection { changes |= AActivityInfo.CONFIG_LAYOUT_DIRECTION }
        return changes
    }

    var description: String {
        let night = isNightModeActive ? "night" : "notnight"
        return "{\(fontScale) \(locales) sw\(smallestScreenWidthDp)dp w\(screenWidthDp)dp h\(screenHeightDp)dp "
            + "\(densityDpi)dpi \(orientation == AConfiguration.ORIENTATION_LANDSCAPE ? "land" : "port") \(night)}"
    }

    // MARK: Current configuration

    /// The configuration of the app window. Updated by AActivityHost on size/orientation and trait changes.
    nonisolated(unsafe) static var current: AConfiguration = AConfiguration.makeFallback()

    /// `AConfiguration.locales[0]` (DESIGN 2.7): the device locales of the current configuration.
    static var locales: ALocaleList { current.locales }

    /// Builds the configuration of a window of `size` points (iOS points = Android dp).
    static func make(windowSize size: CGSize, screenSize: CGSize, scale: CGFloat, dark: Bool) -> AConfiguration {
        let w = max(0, Int(size.width.rounded(.down)))
        let h = max(0, Int(size.height.rounded(.down)))
        let smallest = max(0, Int(min(screenSize.width, screenSize.height).rounded(.down)))
        let night = dark ? UI_MODE_NIGHT_YES : UI_MODE_NIGHT_NO
        return AConfiguration(orientation: w <= h ? ORIENTATION_PORTRAIT : ORIENTATION_LANDSCAPE,
                              screenWidthDp: w, screenHeightDp: h, smallestScreenWidthDp: smallest,
                              densityDpi: Int((scale * 160).rounded()), fontScale: 1,
                              uiMode: UI_MODE_TYPE_NORMAL | night, locales: ALocaleList.getDefault())
    }

    private static func makeFallback() -> AConfiguration {
        let screen = kitOnMain { (UIScreen.main.bounds.size, UIScreen.main.scale,
                                  UIScreen.main.traitCollection.userInterfaceStyle == .dark) }
        return make(windowSize: screen.0, screenSize: screen.0, scale: screen.1, dark: screen.2)
    }

    /// Android `Configuration.screenLayout` size class (sw, long) and layout-direction bits.
    private static func computeScreenLayout(_ w: Int, _ h: Int, _ locales: ALocaleList) -> Int {
        let longSide = max(w, h), shortSide = min(w, h)
        let size: Int
        if longSide >= 960 && shortSide >= 720 { size = SCREENLAYOUT_SIZE_XLARGE }
        else if longSide >= 640 && shortSide >= 480 { size = SCREENLAYOUT_SIZE_LARGE }
        else if longSide >= 470 && shortSide >= 320 { size = SCREENLAYOUT_SIZE_NORMAL }
        else { size = SCREENLAYOUT_SIZE_SMALL }
        // Android: "long" when the aspect ratio exceeds 5:3 (longSize * 3 / 5 >= shortSize - 1).
        let long = (longSide * 3) / 5 >= shortSide - 1 ? SCREENLAYOUT_LONG_YES : SCREENLAYOUT_LONG_NO
        let first = locales.locales.first ?? ALocale.getDefault()
        let dir = isRtl(first) ? SCREENLAYOUT_LAYOUTDIR_RTL : SCREENLAYOUT_LAYOUTDIR_LTR
        return size | long | dir
    }

    /// TextUtils.getLayoutDirectionFromLocale: right-to-left scripts (Hebrew, Arabic, Persian, Urdu, ...).
    static func isRtl(_ locale: ALocale) -> Bool {
        switch locale.language {
        case "he", "iw", "ar", "fa", "ur", "yi", "ji", "ps", "sd", "ug", "dv", "ku", "ckb": return true
        default: return false
        }
    }
}

/// Runs `body` on the main thread (synchronously), for statics that may be first touched off the main thread.
private func kitOnMain<T>(_ body: () -> T) -> T {
    if Thread.isMainThread { return body() }
    return DispatchQueue.main.sync(execute: body)
}

// MARK: - ActivityInfo

/// android.content.pm.ActivityInfo: requested-orientation and configChanges constants, and the mapping of a
/// requested orientation to the iOS interface-orientation mask.
enum AActivityInfo {
    static let SCREEN_ORIENTATION_UNSET = -2
    static let SCREEN_ORIENTATION_UNSPECIFIED = -1
    static let SCREEN_ORIENTATION_LANDSCAPE = 0
    static let SCREEN_ORIENTATION_PORTRAIT = 1
    static let SCREEN_ORIENTATION_USER = 2
    static let SCREEN_ORIENTATION_BEHIND = 3
    static let SCREEN_ORIENTATION_SENSOR = 4
    static let SCREEN_ORIENTATION_NOSENSOR = 5
    static let SCREEN_ORIENTATION_SENSOR_LANDSCAPE = 6
    static let SCREEN_ORIENTATION_SENSOR_PORTRAIT = 7
    static let SCREEN_ORIENTATION_REVERSE_LANDSCAPE = 8
    static let SCREEN_ORIENTATION_REVERSE_PORTRAIT = 9
    static let SCREEN_ORIENTATION_FULL_SENSOR = 10
    static let SCREEN_ORIENTATION_USER_LANDSCAPE = 11
    static let SCREEN_ORIENTATION_USER_PORTRAIT = 12
    static let SCREEN_ORIENTATION_FULL_USER = 13
    static let SCREEN_ORIENTATION_LOCKED = 14

    static let CONFIG_MCC = 0x0001
    static let CONFIG_MNC = 0x0002
    static let CONFIG_LOCALE = 0x0004
    static let CONFIG_TOUCHSCREEN = 0x0008
    static let CONFIG_KEYBOARD = 0x0010
    static let CONFIG_KEYBOARD_HIDDEN = 0x0020
    static let CONFIG_NAVIGATION = 0x0040
    static let CONFIG_ORIENTATION = 0x0080
    static let CONFIG_SCREEN_LAYOUT = 0x0100
    static let CONFIG_UI_MODE = 0x0200
    static let CONFIG_SCREEN_SIZE = 0x0400
    static let CONFIG_SMALLEST_SCREEN_SIZE = 0x0800
    static let CONFIG_DENSITY = 0x1000
    static let CONFIG_LAYOUT_DIRECTION = 0x2000
    static let CONFIG_COLOR_MODE = 0x4000
    static let CONFIG_FONT_SCALE = 0x40000000

    /// The iOS mask for an Android requested orientation.
    /// - Phones rotate to three orientations under SENSOR/USER/UNSPECIFIED (Android `config_allowAllRotations`
    ///   is false on phones), iPads to all four; FULL_SENSOR/FULL_USER allow all four.
    /// - Android LANDSCAPE is rotation 90 (top of the device to the left, home side right) = iOS landscapeRight;
    ///   REVERSE_LANDSCAPE = landscapeLeft.
    /// - BEHIND takes the mask of the activity below (`behind`); LOCKED keeps `current`.
    /// The iOS rotation lock is always honoured (Android SENSOR ignores the user's lock; iOS cannot).
    static func interfaceOrientationMask(_ requested: Int, isPad: Bool, current: UIInterfaceOrientation,
                                         behind: UIInterfaceOrientationMask? = nil) -> UIInterfaceOrientationMask {
        let free: UIInterfaceOrientationMask = isPad ? .all : .allButUpsideDown
        switch requested {
        case SCREEN_ORIENTATION_PORTRAIT: return .portrait
        case SCREEN_ORIENTATION_REVERSE_PORTRAIT: return .portraitUpsideDown
        case SCREEN_ORIENTATION_SENSOR_PORTRAIT, SCREEN_ORIENTATION_USER_PORTRAIT: return [.portrait, .portraitUpsideDown]
        case SCREEN_ORIENTATION_LANDSCAPE: return .landscapeRight
        case SCREEN_ORIENTATION_REVERSE_LANDSCAPE: return .landscapeLeft
        case SCREEN_ORIENTATION_SENSOR_LANDSCAPE, SCREEN_ORIENTATION_USER_LANDSCAPE: return .landscape
        case SCREEN_ORIENTATION_FULL_SENSOR, SCREEN_ORIENTATION_FULL_USER: return .all
        case SCREEN_ORIENTATION_NOSENSOR: return .portrait
        case SCREEN_ORIENTATION_BEHIND: return behind ?? free
        case SCREEN_ORIENTATION_LOCKED: return mask(of: current) ?? .portrait
        default: return free   // UNSPECIFIED, UNSET, USER, SENSOR
        }
    }

    /// The single-orientation mask of an interface orientation (nil for unknown).
    static func mask(of orientation: UIInterfaceOrientation) -> UIInterfaceOrientationMask? {
        switch orientation {
        case .portrait: return .portrait
        case .portraitUpsideDown: return .portraitUpsideDown
        case .landscapeLeft: return .landscapeLeft
        case .landscapeRight: return .landscapeRight
        default: return nil
        }
    }
}

// MARK: - Lifecycle (androidx.lifecycle)

/// androidx.lifecycle.LifecycleOwner.
protocol ALifecycleOwner: AnyObject {
    var lifecycle: ALifecycle { get }
}

/// androidx.lifecycle.LifecycleObserver (marker).
protocol ALifecycleObserver: AnyObject {}

/// androidx.lifecycle.LifecycleEventObserver.
protocol ALifecycleEventObserver: ALifecycleObserver {
    func onStateChanged(_ source: ALifecycleOwner, _ event: ALifecycle.Event)
}

/// androidx.lifecycle.DefaultLifecycleObserver (every method defaults to nothing).
protocol ADefaultLifecycleObserver: ALifecycleObserver {
    func onCreate(_ owner: ALifecycleOwner)
    func onStart(_ owner: ALifecycleOwner)
    func onResume(_ owner: ALifecycleOwner)
    func onPause(_ owner: ALifecycleOwner)
    func onStop(_ owner: ALifecycleOwner)
    func onDestroy(_ owner: ALifecycleOwner)
}

extension ADefaultLifecycleObserver {
    func onCreate(_ owner: ALifecycleOwner) {}
    func onStart(_ owner: ALifecycleOwner) {}
    func onResume(_ owner: ALifecycleOwner) {}
    func onPause(_ owner: ALifecycleOwner) {}
    func onStop(_ owner: ALifecycleOwner) {}
    func onDestroy(_ owner: ALifecycleOwner) {}
}

/// A LifecycleEventObserver from a closure (Kotlin `LifecycleEventObserver { source, event -> }`).
final class ALifecycleEventObserverBlock: ALifecycleEventObserver {
    private let block: (ALifecycleOwner, ALifecycle.Event) -> Void
    init(_ block: @escaping (ALifecycleOwner, ALifecycle.Event) -> Void) { self.block = block }
    func onStateChanged(_ source: ALifecycleOwner, _ event: ALifecycle.Event) { block(source, event) }
}

/// androidx.lifecycle.Lifecycle.
class ALifecycle {
    enum State: Int, Comparable {
        case DESTROYED = 0, INITIALIZED, CREATED, STARTED, RESUMED
        func isAtLeast(_ state: State) -> Bool { rawValue >= state.rawValue }
        static func < (a: State, b: State) -> Bool { a.rawValue < b.rawValue }
    }

    enum Event {
        case ON_CREATE, ON_START, ON_RESUME, ON_PAUSE, ON_STOP, ON_DESTROY, ON_ANY

        var targetState: State {
            switch self {
            case .ON_CREATE, .ON_STOP: return .CREATED
            case .ON_START, .ON_PAUSE: return .STARTED
            case .ON_RESUME: return .RESUMED
            case .ON_DESTROY: return .DESTROYED
            case .ON_ANY: preconditionFailure("ON_ANY doesn't have a target state")
            }
        }
        static func upFrom(_ state: State) -> Event? {
            switch state {
            case .INITIALIZED: return .ON_CREATE
            case .CREATED: return .ON_START
            case .STARTED: return .ON_RESUME
            default: return nil
            }
        }
        static func downFrom(_ state: State) -> Event? {
            switch state {
            case .CREATED: return .ON_DESTROY
            case .STARTED: return .ON_STOP
            case .RESUMED: return .ON_PAUSE
            default: return nil
            }
        }
        static func downTo(_ state: State) -> Event? {
            switch state {
            case .DESTROYED: return .ON_DESTROY
            case .CREATED: return .ON_STOP
            case .STARTED: return .ON_PAUSE
            default: return nil
            }
        }
        static func upTo(_ state: State) -> Event? {
            switch state {
            case .CREATED: return .ON_CREATE
            case .STARTED: return .ON_START
            case .RESUMED: return .ON_RESUME
            default: return nil
            }
        }
    }

    var currentState: State { .INITIALIZED }
    func addObserver(_ observer: ALifecycleObserver) {}
    func removeObserver(_ observer: ALifecycleObserver) {}
}

/// androidx.lifecycle.LifecycleRegistry (port of 2.8: observers are synced in insertion order going up and in
/// reverse insertion order going down; an observer added later never gets ahead of earlier ones).
final class ALifecycleRegistry: ALifecycle {
    private final class ObserverWithState {
        let observer: ALifecycleObserver
        var state: State
        init(_ observer: ALifecycleObserver, _ state: State) { self.observer = observer; self.state = state }

        func dispatchEvent(_ owner: ALifecycleOwner, _ event: Event) {
            let newState = event.targetState
            state = min(state, newState)
            if let d = observer as? ADefaultLifecycleObserver {
                switch event {
                case .ON_CREATE: d.onCreate(owner)
                case .ON_START: d.onStart(owner)
                case .ON_RESUME: d.onResume(owner)
                case .ON_PAUSE: d.onPause(owner)
                case .ON_STOP: d.onStop(owner)
                case .ON_DESTROY: d.onDestroy(owner)
                case .ON_ANY: preconditionFailure("ON_ANY must not been send by anybody")
                }
            }
            (observer as? ALifecycleEventObserver)?.onStateChanged(owner, event)
            state = newState
        }
    }

    private var observerMap: [ObserverWithState] = []
    private var state: State = .INITIALIZED
    private weak var owner: ALifecycleOwner?
    private var addingObserverCounter = 0
    private var handlingEvent = false
    private var newEventOccurred = false
    private var parentStates: [State] = []

    init(_ provider: ALifecycleOwner) {
        owner = provider
    }

    override var currentState: State {
        get { state }
        set { moveToState(newValue) }
    }

    func setCurrentState(_ state: State) { moveToState(state) }

    func handleLifecycleEvent(_ event: Event) { moveToState(event.targetState) }

    var observerCount: Int { observerMap.count }

    private func index(of observer: ALifecycleObserver) -> Int? {
        observerMap.firstIndex { $0.observer === observer }
    }

    private func contains(_ entry: ObserverWithState) -> Bool { observerMap.contains { $0 === entry } }

    private func moveToState(_ next: State) {
        if state == next { return }
        precondition(!(state == .INITIALIZED && next == .DESTROYED),
                     "State must be at least CREATED to move to DESTROYED")
        state = next
        if handlingEvent || addingObserverCounter != 0 {
            newEventOccurred = true
            return
        }
        handlingEvent = true
        sync()
        handlingEvent = false
        if state == .DESTROYED { observerMap = [] }
    }

    private var isSynced: Bool {
        guard let eldest = observerMap.first, let newest = observerMap.last else { return true }
        return eldest.state == newest.state && state == newest.state
    }

    private func calculateTargetState(_ observer: ALifecycleObserver) -> State {
        var siblingState: State? = nil
        if let i = index(of: observer), i > 0 { siblingState = observerMap[i - 1].state }
        let parentState = parentStates.last
        var result = state
        if let s = siblingState, s < result { result = s }
        if let p = parentState, p < result { result = p }
        return result
    }

    override func addObserver(_ observer: ALifecycleObserver) {
        let initialState: State = state == .DESTROYED ? .DESTROYED : .INITIALIZED
        if index(of: observer) != nil { return }
        let statefulObserver = ObserverWithState(observer, initialState)
        observerMap.append(statefulObserver)
        guard let owner = owner else { return }
        let isReentrance = addingObserverCounter != 0 || handlingEvent
        var targetState = calculateTargetState(observer)
        addingObserverCounter += 1
        while statefulObserver.state < targetState && contains(statefulObserver) {
            parentStates.append(statefulObserver.state)
            guard let event = Event.upFrom(statefulObserver.state) else { break }
            statefulObserver.dispatchEvent(owner, event)
            parentStates.removeLast()
            targetState = calculateTargetState(observer)
        }
        if !isReentrance { sync() }
        addingObserverCounter -= 1
    }

    override func removeObserver(_ observer: ALifecycleObserver) {
        if let i = index(of: observer) { observerMap.remove(at: i) }
    }

    private func forwardPass(_ owner: ALifecycleOwner) {
        var i = 0
        while i < observerMap.count && !newEventOccurred {
            let entry = observerMap[i]
            while entry.state < state && !newEventOccurred && contains(entry) {
                parentStates.append(entry.state)
                guard let event = Event.upFrom(entry.state) else { break }
                entry.dispatchEvent(owner, event)
                parentStates.removeLast()
            }
            if i < observerMap.count && observerMap[i] === entry { i += 1 }
        }
    }

    private func backwardPass(_ owner: ALifecycleOwner) {
        for entry in observerMap.reversed() {
            if newEventOccurred { break }
            while entry.state > state && !newEventOccurred && contains(entry) {
                guard let event = Event.downFrom(entry.state) else { break }
                parentStates.append(event.targetState)
                entry.dispatchEvent(owner, event)
                parentStates.removeLast()
            }
        }
    }

    private func sync() {
        guard let owner = owner else { return }
        while !isSynced {
            newEventOccurred = false
            if let eldest = observerMap.first, state < eldest.state { backwardPass(owner) }
            if !newEventOccurred, let newest = observerMap.last, state > newest.state { forwardPass(owner) }
        }
        newEventOccurred = false
    }
}

// MARK: - OnBackPressedDispatcher (androidx.activity)

/// androidx.activity.OnBackPressedCallback. Subclass and override `handleOnBackPressed`, or pass a closure.
/// iOS has no system Back: the dispatcher runs only when an on-screen control calls `activity.onBackPressed()`.
class AOnBackPressedCallback {
    var isEnabled: Bool {
        didSet { enabledChangedCallback?() }
    }
    fileprivate var cancellables: [KitCancellable] = []
    fileprivate var enabledChangedCallback: (() -> Void)?
    private let handler: ((AOnBackPressedCallback) -> Void)?

    init(_ enabled: Bool) {
        isEnabled = enabled
        handler = nil
    }

    /// Kotlin `object : OnBackPressedCallback(enabled) { override fun handleOnBackPressed() = block() }`.
    init(_ enabled: Bool, _ handleOnBackPressed: @escaping (AOnBackPressedCallback) -> Void) {
        isEnabled = enabled
        handler = handleOnBackPressed
    }

    /// Removes this callback from every dispatcher it was added to.
    func remove() {
        for c in cancellables { c.cancel() }
    }

    func handleOnBackPressed() {
        handler?(self)
    }

    func handleOnBackCancelled() {}

    fileprivate func addCancellable(_ c: KitCancellable) { cancellables.append(c) }
    fileprivate func removeCancellable(_ c: KitCancellable) { cancellables.removeAll { $0 === c } }
}

/// A Cancellable of the dispatcher (androidx.activity.Cancellable).
private final class KitCancellable {
    var onCancel: (() -> Void)?
    init(_ onCancel: (() -> Void)? = nil) { self.onCancel = onCancel }
    func cancel() { onCancel?() }
}

/// androidx.activity.OnBackPressedDispatcher.
final class AOnBackPressedDispatcher {
    private var onBackPressedCallbacks: [AOnBackPressedCallback] = []
    private let fallbackOnBackPressed: (() -> Void)?
    private var hasEnabledCallbacksFlag = false

    init(_ fallbackOnBackPressed: (() -> Void)? = nil) {
        self.fallbackOnBackPressed = fallbackOnBackPressed
    }

    private func updateEnabledCallbacks() {
        hasEnabledCallbacksFlag = onBackPressedCallbacks.contains { $0.isEnabled }
    }

    func addCallback(_ onBackPressedCallback: AOnBackPressedCallback) {
        _ = addCancellableCallback(onBackPressedCallback)
    }

    fileprivate func addCancellableCallback(_ callback: AOnBackPressedCallback) -> KitCancellable {
        onBackPressedCallbacks.append(callback)
        let cancellable = KitCancellable()
        cancellable.onCancel = { [weak self, weak callback, unowned cancellable] in
            guard let callback = callback else { return }
            if let self = self, let i = self.onBackPressedCallbacks.firstIndex(where: { $0 === callback }) {
                self.onBackPressedCallbacks.remove(at: i)
            }
            callback.removeCancellable(cancellable)
            callback.enabledChangedCallback?()
            callback.enabledChangedCallback = nil
        }
        callback.addCancellable(cancellable)
        updateEnabledCallbacks()
        callback.enabledChangedCallback = { [weak self] in self?.updateEnabledCallbacks() }
        return cancellable
    }

    /// addCallback(owner, callback): the callback is in the dispatcher only while `owner` is at least STARTED
    /// (added on ON_START, removed on ON_STOP, forgotten on ON_DESTROY).
    func addCallback(_ owner: ALifecycleOwner, _ onBackPressedCallback: AOnBackPressedCallback) {
        let lifecycle = owner.lifecycle
        if lifecycle.currentState == .DESTROYED { return }
        let observer = LifecycleOnBackPressedCancellable(self, lifecycle, onBackPressedCallback)
        onBackPressedCallback.addCancellable(observer.handle)
        updateEnabledCallbacks()
        onBackPressedCallback.enabledChangedCallback = { [weak self] in self?.updateEnabledCallbacks() }
        observer.start()
    }

    /// activity-ktx `addCallback(owner, enabled) { ... }`.
    @discardableResult
    func addCallback(_ owner: ALifecycleOwner?, _ enabled: Bool = true,
                     _ onBackPressed: @escaping (AOnBackPressedCallback) -> Void) -> AOnBackPressedCallback {
        let callback = AOnBackPressedCallback(enabled, onBackPressed)
        if let owner = owner { addCallback(owner, callback) } else { addCallback(callback) }
        return callback
    }

    func hasEnabledCallbacks() -> Bool { hasEnabledCallbacksFlag }

    /// Runs the newest enabled callback, else the fallback (the activity's default Back).
    func onBackPressed() {
        if let callback = onBackPressedCallbacks.last(where: { $0.isEnabled }) {
            callback.handleOnBackPressed()
            return
        }
        fallbackOnBackPressed?()
    }

    private final class LifecycleOnBackPressedCancellable: ALifecycleEventObserver {
        private weak var dispatcher: AOnBackPressedDispatcher?
        private let lifecycle: ALifecycle
        /// Held strongly like androidx (`private val onBackPressedCallback`): Kotlin code passes inline callback objects
        /// that nothing else keeps.
        private let callback: AOnBackPressedCallback
        private var currentCancellable: KitCancellable?
        let handle = KitCancellable()

        init(_ dispatcher: AOnBackPressedDispatcher, _ lifecycle: ALifecycle, _ callback: AOnBackPressedCallback) {
            self.dispatcher = dispatcher
            self.lifecycle = lifecycle
            self.callback = callback
            handle.onCancel = { [weak self] in self?.cancel() }
        }

        func start() { lifecycle.addObserver(self) }

        func onStateChanged(_ source: ALifecycleOwner, _ event: ALifecycle.Event) {
            if event == .ON_START {
                if let d = dispatcher { currentCancellable = d.addCancellableCallback(callback) }
            } else if event == .ON_STOP {
                currentCancellable?.cancel()
            } else if event == .ON_DESTROY {
                cancel()
            }
        }

        func cancel() {
            lifecycle.removeObserver(self)
            callback.removeCancellable(handle)
            currentCancellable?.cancel()
            currentCancellable = nil
        }
    }
}

// MARK: - Window

/// android.view.WindowManager (the LayoutParams the app sets on dialog windows).
enum AWindowManager {
    final class LayoutParams {
        static let MATCH_PARENT = -1
        static let FILL_PARENT = -1
        static let WRAP_CONTENT = -2

        static let FLAG_DIM_BEHIND = 0x00000002
        static let FLAG_BLUR_BEHIND = 0x00000004
        static let FLAG_NOT_FOCUSABLE = 0x00000008
        static let FLAG_NOT_TOUCHABLE = 0x00000010
        static let FLAG_NOT_TOUCH_MODAL = 0x00000020
        static let FLAG_KEEP_SCREEN_ON = 0x00000080
        static let FLAG_LAYOUT_IN_SCREEN = 0x00000100
        static let FLAG_LAYOUT_NO_LIMITS = 0x00000200
        static let FLAG_FULLSCREEN = 0x00000400
        static let FLAG_SECURE = 0x00002000
        static let FLAG_WATCH_OUTSIDE_TOUCH = 0x00040000
        static let FLAG_TRANSLUCENT_STATUS = 0x04000000
        static let FLAG_TRANSLUCENT_NAVIGATION = 0x08000000
        static let FLAG_DRAWS_SYSTEM_BAR_BACKGROUNDS = Int(Int32.min)

        static let SOFT_INPUT_STATE_UNSPECIFIED = 0
        static let SOFT_INPUT_STATE_HIDDEN = 2
        static let SOFT_INPUT_STATE_ALWAYS_HIDDEN = 3
        static let SOFT_INPUT_STATE_VISIBLE = 4
        static let SOFT_INPUT_ADJUST_UNSPECIFIED = 0x00
        static let SOFT_INPUT_ADJUST_RESIZE = 0x10
        static let SOFT_INPUT_ADJUST_PAN = 0x20
        static let SOFT_INPUT_ADJUST_NOTHING = 0x30

        static let LAYOUT_IN_DISPLAY_CUTOUT_MODE_DEFAULT = 0
        static let LAYOUT_IN_DISPLAY_CUTOUT_MODE_SHORT_EDGES = 1
        static let LAYOUT_IN_DISPLAY_CUTOUT_MODE_NEVER = 2
        static let LAYOUT_IN_DISPLAY_CUTOUT_MODE_ALWAYS = 3

        var width: Int
        var height: Int
        var x = 0
        var y = 0
        var gravity = 0
        var flags = 0
        var dimAmount: Float = 1
        var alpha: Float = 1
        /// Window animation style resource; 0 = no window animations (dialogs start with their theme's fade).
        var windowAnimations = 0
        var horizontalMargin: Float = 0
        var verticalMargin: Float = 0
        var softInputMode = 0
        var screenBrightness: Float = -1
        var layoutInDisplayCutoutMode = 0
        var title = ""

        init() {
            width = LayoutParams.MATCH_PARENT
            height = LayoutParams.MATCH_PARENT
        }

        init(_ width: Int, _ height: Int) {
            self.width = width
            self.height = height
        }

        /// `new LayoutParams(source)` / copyFrom.
        init(_ other: LayoutParams) {
            width = other.width; height = other.height
            copyFrom(other)
        }

        func copyFrom(_ o: LayoutParams) {
            width = o.width; height = o.height; x = o.x; y = o.y; gravity = o.gravity; flags = o.flags
            dimAmount = o.dimAmount; alpha = o.alpha; windowAnimations = o.windowAnimations
            horizontalMargin = o.horizontalMargin; verticalMargin = o.verticalMargin; softInputMode = o.softInputMode
            screenBrightness = o.screenBrightness; layoutInDisplayCutoutMode = o.layoutInDisplayCutoutMode; title = o.title
        }
    }
}

/// android.view.Window of an activity or of a dialog. `decorView` is the root of the window's view tree
/// (activities: hosted by the activity's AViewRoot; dialogs: by the dialog overlay's AViewRoot), `contentParent`
/// is android.R.id.content.
final class AWindow {
    static let FEATURE_OPTIONS_PANEL = 0
    static let FEATURE_NO_TITLE = 1
    static let FEATURE_PROGRESS = 2
    static let FEATURE_LEFT_ICON = 3
    static let FEATURE_RIGHT_ICON = 4
    static let FEATURE_INDETERMINATE_PROGRESS = 5
    static let FEATURE_CONTEXT_MENU = 6
    static let FEATURE_CUSTOM_TITLE = 7
    static let FEATURE_ACTION_BAR = 8
    static let FEATURE_ACTION_BAR_OVERLAY = 9
    static let FEATURE_ACTION_MODE_OVERLAY = 10
    /// android.R.id.content.
    static let ID_ANDROID_CONTENT = "content"

    /// Android 15+ for apps targeting SDK 35+ (Triple Shot targets 36): every activity window is edge-to-edge,
    /// `setDecorFitsSystemWindows` is ignored, `statusBarColor` is ignored and `navigationBarColor` reads as
    /// transparent (PhoneWindow, android-36). The owner's reference renders (Pixel 6, store captures) are this mode.
    /// Set to false to emulate pre-15 devices (decor fits the system bars, coloured bar backgrounds).
    nonisolated(unsafe) static var edgeToEdgeEnforced = true

    weak var context: AContext?
    /// True for dialog windows (floating).
    let isFloating: Bool
    let decorView: AFrameLayout
    /// android.R.id.content (the AppCompat sub-decor's ContentFrameLayout in AppCompat dialogs).
    private(set) var contentParent: AFrameLayout
    private var hasAppCompatSubDecor = false

    /// Window.setTitle / getAttributes().getTitle().
    private(set) var title: String?
    /// Window.setElevation / android:windowElevation (px): the shadow of a floating window.
    var windowElevation: Float = 0
    /// android:windowMinWidthMajor / windowMinWidthMinor of a floating window, as fractions of the screen width
    /// (DecorView.onMeasure); nil = @null.
    var minWidthMajor: Float?
    var minWidthMinor: Float?
    /// Window.mCloseOnTouchOutside / mSetCloseOnTouchOutside.
    private var mCloseOnTouchOutside = false
    private var mSetCloseOnTouchOutside = false
    /// The legacy status/navigation bar backgrounds (pre-15 emulation only).
    private let statusBarGuard: AView
    private let navigationBarGuard: AView

    var attributes: AWindowManager.LayoutParams {
        didSet { onAttributesChanged?() }
    }
    private var features = Set<Int>()
    private var mDecorFitsSystemWindows = true
    private var mStatusBarColor = 0
    private var mNavigationBarColor = 0
    private var mBackgroundReplaced = false

    var isNavigationBarContrastEnforced = true
    var isStatusBarContrastEnforced = false

    // WindowInsetsController state (androidx WindowInsetsControllerCompat writes it).
    fileprivate(set) var appearanceLightStatusBars: Bool
    fileprivate(set) var appearanceLightNavigationBars: Bool
    fileprivate(set) var hiddenInsetTypes = 0
    fileprivate(set) var systemBarsBehavior = AWindowInsetsControllerCompat.BEHAVIOR_DEFAULT

    /// Called after any status-bar / navigation-bar / keep-screen-on relevant change.
    var onSystemBarsChanged: (() -> Void)?
    /// Called after the window attributes changed (dialog relayout).
    var onAttributesChanged: (() -> Void)?

    init(context: AContext?, isFloating: Bool) {
        self.context = context
        self.isFloating = isFloating
        let decor = KitDecorView()
        decorView = decor
        contentParent = AFrameLayout()
        contentParent.viewId = AWindow.ID_ANDROID_CONTENT
        statusBarGuard = AView()
        navigationBarGuard = AView()
        if isFloating {
            // Dialog windows: wrap-content, centred, dimmed behind, theme window animation.
            let lp = AWindowManager.LayoutParams(AWindowManager.LayoutParams.WRAP_CONTENT,
                                                 AWindowManager.LayoutParams.WRAP_CONTENT)
            lp.flags = AWindowManager.LayoutParams.FLAG_DIM_BEHIND
            lp.dimAmount = 0.6
            lp.windowAnimations = 1
            attributes = lp
            appearanceLightStatusBars = false
            appearanceLightNavigationBars = false
        } else {
            attributes = AWindowManager.LayoutParams()
            // Theme.TripleShot: android:windowLightStatusBar = true (dark status-bar icons).
            appearanceLightStatusBars = true
            appearanceLightNavigationBars = false
            // Theme.TripleShot android:statusBarColor / navigationBarColor #FFFDF5 (pre-15 only).
            mStatusBarColor = AWindow.edgeToEdgeEnforced ? 0 : argbInt(0xFFFFFDF5)
            mNavigationBarColor = argbInt(0xFFFFFDF5)
            mDecorFitsSystemWindows = !AWindow.edgeToEdgeEnforced
        }
        decor.mWindow = self
        decorView.addView(contentParent, AFrameLayout.LayoutParams(AViewGroup.LayoutParams.MATCH_PARENT,
                                                                   AViewGroup.LayoutParams.MATCH_PARENT))
        if !isFloating {
            decorView.addView(statusBarGuard, AFrameLayout.LayoutParams(AViewGroup.LayoutParams.MATCH_PARENT, 0,
                                                                        AGravity.TOP))
            decorView.addView(navigationBarGuard, AFrameLayout.LayoutParams(AViewGroup.LayoutParams.MATCH_PARENT, 0,
                                                                            AGravity.BOTTOM))
            installContentInsetsApplier()
            applyThemeBackground(dark: AConfiguration.current.isNightModeActive)
        }
    }

    // MARK: Decor

    func getDecorView() -> AView { decorView }
    func peekDecorView() -> AView? { decorView }

    /// AppCompatDelegateImpl.createSubDecor for a floating window (abc_dialog_title_material): a vertical layout with
    /// the AppCompat title (GONE: AppCompat dialogs request FEATURE_NO_TITLE) and a ContentFrameLayout that takes the
    /// android.R.id.content id from the framework content view.
    func installAppCompatDialogSubDecor() {
        if hasAppCompatSubDecor { return }
        hasAppCompatSubDecor = true
        let subDecor = ALinearLayout()
        subDecor.orientation = ALinearLayout.VERTICAL
        let titleView = ATextView()
        titleView.viewId = "appcompat:title"
        titleView.visibility = AView.GONE
        subDecor.addView(titleView, ALinearLayout.LayoutParams(AViewGroup.LayoutParams.MATCH_PARENT,
                                                               AViewGroup.LayoutParams.WRAP_CONTENT))
        let contentFrame = AFrameLayout()
        // Move any views already in the framework content view into the ContentFrameLayout.
        while contentParent.childCount > 0, let child = contentParent.getChildAt(0) {
            let params = child.layoutParams
            contentParent.removeViewAt(0)
            if let p = params {
                contentFrame.addView(child, p)
            } else {
                contentFrame.addView(child)
            }
        }
        subDecor.addView(contentFrame, ALinearLayout.LayoutParams(AViewGroup.LayoutParams.MATCH_PARENT,
                                                                  AViewGroup.LayoutParams.MATCH_PARENT))
        contentParent.viewId = nil
        contentFrame.viewId = AWindow.ID_ANDROID_CONTENT
        contentParent.addView(subDecor, AFrameLayout.LayoutParams(AViewGroup.LayoutParams.MATCH_PARENT,
                                                                  AViewGroup.LayoutParams.MATCH_PARENT))
        contentParent = contentFrame
    }

    /// Window.setTitle.
    func setTitle(_ title: String?) {
        self.title = title
        attributes.title = title ?? ""
    }

    /// Window.setElevation / getElevation.
    func setElevation(_ elevation: Float) {
        windowElevation = elevation
        onAttributesChanged?()
    }

    func getElevation() -> Float { windowElevation }

    // MARK: Close on touch outside (floating windows)

    func setCloseOnTouchOutside(_ close: Bool) {
        mCloseOnTouchOutside = close
        mSetCloseOnTouchOutside = true
    }

    func setCloseOnTouchOutsideIfNotSet(_ close: Bool) {
        if !mSetCloseOnTouchOutside {
            mCloseOnTouchOutside = close
            mSetCloseOnTouchOutside = true
        }
    }

    func shouldCloseOnTouchOutside() -> Bool { mCloseOnTouchOutside }

    /// Window.shouldCloseOnTouch: an ACTION_UP outside the decor view (beyond the window touch slop) or ACTION_OUTSIDE.
    func shouldCloseOnTouch(_ event: AMotionEvent) -> Bool {
        let isOutside = (event.action == AMotionEvent.ACTION_UP && isOutOfBounds(event))
            || event.action == AMotionEvent.ACTION_OUTSIDE
        return mCloseOnTouchOutside && peekDecorView() != nil && isOutside
    }

    private func isOutOfBounds(_ event: AMotionEvent) -> Bool {
        let x = event.x.toInt()
        let y = event.y.toInt()
        let slop = AViewConfiguration.get().scaledWindowTouchSlop
        return (x < -slop) || (y < -slop) || (x > (decorView.width + slop)) || (y > (decorView.height + slop))
    }

    func findViewById<T: AView>(_ id: String) -> T? { decorView.findViewById(id) }

    /// Window.setContentView(view): replaces the content of android.R.id.content.
    /// PhoneWindow.setContentView(view): `setContentView(view, new LayoutParams(MATCH_PARENT, MATCH_PARENT))`.
    func setContentView(_ view: AView) {
        setContentView(view, AViewGroup.LayoutParams(AViewGroup.LayoutParams.MATCH_PARENT,
                                                     AViewGroup.LayoutParams.MATCH_PARENT))
    }

    func setContentView(_ view: AView, _ params: AViewGroup.LayoutParams) {
        contentParent.removeAllViews()
        contentParent.addView(view, params)
    }

    func addContentView(_ view: AView, _ params: AViewGroup.LayoutParams) {
        contentParent.addView(view, params)
    }

    /// Window.setBackgroundDrawable: the decor background; the decor takes the drawable's padding (DecorView).
    func setBackgroundDrawable(_ drawable: ADrawable?) {
        mBackgroundReplaced = true
        decorView.background = drawable
        let padding = ARect()
        if let d = drawable, d.getPadding(padding) {
            decorView.setPadding(padding.left, padding.top, padding.right, padding.bottom)
        } else {
            decorView.setPadding(0, 0, 0, 0)
        }
        onAttributesChanged?()
    }

    /// setBackgroundDrawableResource(android.R.color.x / R.color.x): a colour resource (ARGB Int).
    func setBackgroundDrawableResource(_ color: Int) {
        setBackgroundDrawable(AColorDrawable(color))
    }

    /// setBackgroundDrawableResource(R.drawable.x).
    func setBackgroundDrawableResource(_ drawable: ADrawableRes) {
        setBackgroundDrawable(ContextCompat_getDrawable(drawable))
    }

    /// Installs a background without marking it as replaced by the app (theme defaults, alert flavours).
    func installThemeBackground(_ drawable: ADrawable?, padding: ARect? = nil) {
        decorView.background = drawable
        if let p = padding {
            decorView.setPadding(p.left, p.top, p.right, p.bottom)
        } else {
            decorView.setPadding(0, 0, 0, 0)
        }
    }

    var isBackgroundReplaced: Bool { mBackgroundReplaced }

    /// Theme.MaterialComponents.DayNight windowBackground (?android:colorBackground): white / #121212.
    func applyThemeBackground(dark: Bool) {
        if isFloating || mBackgroundReplaced { return }
        decorView.background = AColorDrawable(dark ? argbInt(0xFF121212) : argbInt(0xFFFFFFFF))
    }

    // MARK: Features, flags, layout

    @discardableResult
    func requestFeature(_ featureId: Int) -> Bool {
        features.insert(featureId)
        return true
    }

    func hasFeature(_ featureId: Int) -> Bool { features.contains(featureId) }

    func addFlags(_ flags: Int) { setFlags(flags, flags) }
    func clearFlags(_ flags: Int) { setFlags(0, flags) }
    func setFlags(_ flags: Int, _ mask: Int) {
        let a = attributes
        a.flags = (a.flags & ~mask) | (flags & mask)
        attributes = a
        onSystemBarsChanged?()
    }

    /// Window.setLayout(width, height) in px (or MATCH_PARENT / WRAP_CONTENT).
    func setLayout(_ width: Int, _ height: Int) {
        let a = attributes
        a.width = width
        a.height = height
        attributes = a
    }

    func setGravity(_ gravity: Int) {
        let a = attributes
        a.gravity = gravity
        attributes = a
    }

    func setDimAmount(_ amount: Float) {
        let a = attributes
        a.dimAmount = amount
        attributes = a
    }

    func setWindowAnimations(_ resId: Int) {
        let a = attributes
        a.windowAnimations = resId
        attributes = a
    }

    func setSoftInputMode(_ mode: Int) {
        let a = attributes
        a.softInputMode = mode
        attributes = a
    }

    func getAttributes() -> AWindowManager.LayoutParams { attributes }
    func setAttributes(_ a: AWindowManager.LayoutParams) { attributes = a }

    var keepsScreenOn: Bool { (attributes.flags & AWindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON) != 0 }

    // MARK: System bars

    /// Window.setDecorFitsSystemWindows: ignored under edge-to-edge enforcement (Android 15+, targetSdk 36).
    func setDecorFitsSystemWindows(_ decorFitsSystemWindows: Bool) {
        if AWindow.edgeToEdgeEnforced || isFloating { return }
        mDecorFitsSystemWindows = decorFitsSystemWindows
        AViewCompat.requestApplyInsets(decorView)
    }

    func decorFitsSystemWindows() -> Bool { mDecorFitsSystemWindows }

    /// Window.statusBarColor: ignored under edge-to-edge enforcement (reads transparent).
    var statusBarColor: Int {
        get { mStatusBarColor }
        set {
            if AWindow.edgeToEdgeEnforced { return }
            mStatusBarColor = newValue
            updateBarGuards()
        }
    }

    /// Window.navigationBarColor: kept, but reads TRANSPARENT under edge-to-edge enforcement.
    var navigationBarColor: Int {
        get { AWindow.edgeToEdgeEnforced ? 0 : mNavigationBarColor }
        set {
            mNavigationBarColor = newValue
            updateBarGuards()
        }
    }

    var isStatusBarsHidden: Bool { (hiddenInsetTypes & AWindowInsetsCompat.statusBars()) != 0 }
    var isNavigationBarsHidden: Bool { (hiddenInsetTypes & AWindowInsetsCompat.navigationBars()) != 0 }

    /// The screen edges whose system gestures need a second swipe: Android's transient bars (hidden bars with
    /// BEHAVIOR_SHOW_TRANSIENT_BARS_BY_SWIPE: the first swipe only reveals the bar).
    var deferredSystemGestureEdges: UIRectEdge {
        guard systemBarsBehavior == AWindowInsetsControllerCompat.BEHAVIOR_SHOW_TRANSIENT_BARS_BY_SWIPE else { return [] }
        var edges: UIRectEdge = []
        if isNavigationBarsHidden { edges.insert(.bottom) }
        if isStatusBarsHidden { edges.insert(.top) }
        return edges
    }

    fileprivate func setAppearanceLightStatusBars(_ light: Bool) {
        appearanceLightStatusBars = light
        onSystemBarsChanged?()
    }

    fileprivate func setAppearanceLightNavigationBars(_ light: Bool) {
        appearanceLightNavigationBars = light
        onSystemBarsChanged?()
    }

    fileprivate func setHidden(_ types: Int, _ hidden: Bool) {
        if hidden { hiddenInsetTypes |= types } else { hiddenInsetTypes &= ~types }
        onSystemBarsChanged?()
        AViewCompat.requestApplyInsets(decorView)
    }

    fileprivate func setBehavior(_ behavior: Int) {
        systemBarsBehavior = behavior
        onSystemBarsChanged?()
    }

    /// PhoneWindow's sDefaultContentInsetsApplier (pre-15 emulation): the content fits the system bars and the
    /// bar areas show the status/navigation bar colours.
    private func installContentInsetsApplier() {
        AViewCompat.setOnApplyWindowInsetsListener(contentParent) { [weak self] v, insets in
            guard let self = self, self.mDecorFitsSystemWindows, !AWindow.edgeToEdgeEnforced else {
                v.setPadding(0, 0, 0, 0)
                self?.setGuardHeights(0, 0)
                return insets
            }
            let bars = insets.getInsets(AWindowInsetsCompat.systemBars())
            v.setPadding(bars.left, bars.top, bars.right, bars.bottom)
            self.setGuardHeights(bars.top, bars.bottom)
            return AWindowInsetsCompat.CONSUMED
        }
    }

    private func setGuardHeights(_ top: Int, _ bottom: Int) {
        if let lp = statusBarGuard.layoutParams, lp.height != top { lp.height = top; statusBarGuard.layoutParams = lp }
        if let lp = navigationBarGuard.layoutParams, lp.height != bottom {
            lp.height = bottom; navigationBarGuard.layoutParams = lp
        }
        updateBarGuards()
    }

    private func updateBarGuards() {
        if AWindow.edgeToEdgeEnforced || isFloating {
            statusBarGuard.visibility = AView.GONE
            navigationBarGuard.visibility = AView.GONE
            return
        }
        statusBarGuard.visibility = AView.VISIBLE
        navigationBarGuard.visibility = AView.VISIBLE
        statusBarGuard.setBackgroundColor(mStatusBarColor)
        navigationBarGuard.setBackgroundColor(mNavigationBarColor)
    }
}

/// androidx.core.view.WindowCompat.
enum AWindowCompat {
    static let FEATURE_ACTION_BAR = 8
    static let FEATURE_ACTION_BAR_OVERLAY = 9
    static let FEATURE_ACTION_MODE_OVERLAY = 10

    static func setDecorFitsSystemWindows(_ window: AWindow, _ decorFitsSystemWindows: Bool) {
        window.setDecorFitsSystemWindows(decorFitsSystemWindows)
    }

    static func getInsetsController(_ window: AWindow, _ view: AView) -> AWindowInsetsControllerCompat {
        AWindowInsetsControllerCompat(window, view)
    }
}

/// androidx.core.view.WindowInsetsControllerCompat. The state lives in the window: dark/light bar content maps to
/// the iOS status-bar style, hidden status bars to prefersStatusBarHidden, hidden navigation bars to the
/// auto-hidden home indicator (+ deferred bottom-edge gestures for transient bars).
final class AWindowInsetsControllerCompat {
    static let BEHAVIOR_SHOW_BARS_BY_TOUCH = 0
    static let BEHAVIOR_SHOW_BARS_BY_SWIPE = 1
    static let BEHAVIOR_DEFAULT = 1
    static let BEHAVIOR_SHOW_TRANSIENT_BARS_BY_SWIPE = 2

    private let window: AWindow

    init(_ window: AWindow, _ view: AView) {
        self.window = window
    }

    /// True = dark status-bar content (for light backgrounds).
    var isAppearanceLightStatusBars: Bool {
        get { window.appearanceLightStatusBars }
        set { window.setAppearanceLightStatusBars(newValue) }
    }

    var isAppearanceLightNavigationBars: Bool {
        get { window.appearanceLightNavigationBars }
        set { window.setAppearanceLightNavigationBars(newValue) }
    }

    var systemBarsBehavior: Int {
        get { window.systemBarsBehavior }
        set { window.setBehavior(newValue) }
    }

    func hide(_ types: Int) { window.setHidden(types, true) }
    func show(_ types: Int) { window.setHidden(types, false) }
}

// MARK: - Activity

/// The AndroidManifest.xml attributes of an activity class (registered by the app, see TripleShotApp.swift).
struct AActivityManifestEntry {
    var screenOrientation: Int
    /// The `android:configChanges` bits (AActivityInfo.CONFIG_*) the activity handles itself.
    var configChanges: Int
    var label: String?

    init(screenOrientation: Int = AActivityInfo.SCREEN_ORIENTATION_UNSPECIFIED, configChanges: Int = 0, label: String? = nil) {
        self.screenOrientation = screenOrientation
        self.configChanges = configChanges
        self.label = label
    }
}

/// android.app.Activity / androidx.fragment.app.FragmentActivity / AppCompatActivity as one class: a
/// UIViewController child of AActivityHost whose view hosts the window's decor view in an AViewRoot and the
/// overlays of its dialogs. Subclasses override the Android lifecycle methods and call super like on Android.
class AActivity: UIViewController, AContext, ALifecycleOwner {
    /// The manifest, by activity class name ("TripleShotDemoActivity").
    nonisolated(unsafe) static var manifest: [String: AActivityManifestEntry] = [:]

    /// `AppCompatActivity(@LayoutRes contentLayoutId)`: inflated by super.onCreate.
    let contentLayoutId: String?
    /// Activity.getIntent().
    var intent: AIntent

    private var lifecycleRegistryStorage: ALifecycleRegistry?
    private var fragmentLifecycleRegistryStorage: ALifecycleRegistry?
    private var fragmentManagerStorage: AFragmentManager?
    private var dispatcherStorage: AOnBackPressedDispatcher?
    private var windowStorage: AWindow?
    private var mRequestedOrientation: Int
    /// The mask a LOCKED request resolved to (the orientation when it was requested).
    fileprivate var lockedMask: UIInterfaceOrientationMask?
    fileprivate var configurationListeners: [(owner: AnyObject, block: (AConfiguration) -> Void)] = []

    // Android lifecycle flags (Activity.mCreated / mStarted... and FragmentActivity.mCreated / mStopped).
    fileprivate(set) var isCreatedState = false
    fileprivate(set) var isStartedState = false
    fileprivate(set) var isResumedState = false
    private var fragmentsCreated = false
    private var mFinished = false
    private var mDestroyed = false
    fileprivate var windowFocus = false
    fileprivate var lastConfiguration: AConfiguration?
    private var mCalled = false

    /// The dialogs currently shown on this activity's window, bottom to top.
    fileprivate(set) var showingDialogs: [ADialog] = []

    init(contentLayoutId: String?) {
        self.contentLayoutId = contentLayoutId
        self.intent = AIntent(AIntent.ACTION_MAIN)
        self.mRequestedOrientation = AActivityInfo.SCREEN_ORIENTATION_UNSPECIFIED
        super.init(nibName: nil, bundle: nil)
        self.mRequestedOrientation = manifestEntry.screenOrientation
    }

    /// `AppCompatActivity()`; also how startActivity instantiates the class of an Intent.
    required convenience init() {
        self.init(contentLayoutId: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        preconditionFailure("AActivity is created in code")
    }

    var manifestEntry: AActivityManifestEntry {
        AActivity.manifest[String(describing: type(of: self))] ?? AActivityManifestEntry()
    }

    // MARK: Components

    var lifecycle: ALifecycle { lifecycleRegistry }

    var lifecycleRegistry: ALifecycleRegistry {
        if let r = lifecycleRegistryStorage { return r }
        let r = ALifecycleRegistry(self)
        lifecycleRegistryStorage = r
        return r
    }

    /// FragmentActivity.mFragmentLifecycleRegistry: the LifecycleOwner of the activity's FragmentManager host. The
    /// registry holds its owner weakly (like androidx), so the owner object lives as long as the activity.
    var fragmentHostLifecycle: ALifecycleRegistry {
        if let r = fragmentLifecycleRegistryStorage { return r }
        let r = ALifecycleRegistry(fragmentHostLifecycleOwner)
        fragmentLifecycleRegistryStorage = r
        return r
    }

    private lazy var fragmentHostLifecycleOwner = KitFragmentHostLifecycleOwner(self)

    /// FragmentActivity.getSupportFragmentManager().
    var supportFragmentManager: AFragmentManager {
        if let fm = fragmentManagerStorage { return fm }
        let fm = AFragmentManager()
        fragmentManagerStorage = fm
        return fm
    }

    func getSupportFragmentManager() -> AFragmentManager { supportFragmentManager }

    /// ComponentActivity.getOnBackPressedDispatcher(): its fallback is Activity.onBackPressed's default.
    var onBackPressedDispatcher: AOnBackPressedDispatcher {
        if let d = dispatcherStorage { return d }
        let d = AOnBackPressedDispatcher { [weak self] in self?.defaultOnBackPressed() }
        dispatcherStorage = d
        return d
    }

    /// Activity.getWindow().
    var window: AWindow {
        if let w = windowStorage { return w }
        let w = AWindow(context: self, isFloating: false)
        w.onSystemBarsChanged = { [weak self] in self?.systemBarsChanged() }
        windowStorage = w
        return w
    }

    func getWindow() -> AWindow { window }

    // MARK: UIKit

    override func loadView() {
        let root = AActivityRootView(frame: UIScreen.main.bounds)
        root.activity = self
        view = root
        let viewRoot = AViewRoot(host: root.contentHost)
        // Window.Callback.dispatchTouchEvent = Activity.dispatchTouchEvent.
        viewRoot.windowCallbackDispatchTouchEvent = { [weak self] ev in
            self?.dispatchTouchEvent(ev) ?? false
        }
        viewRoot.contentView = window.decorView
        root.viewRoot = viewRoot
    }

    /// Activity.dispatchTouchEvent: onUserInteraction on ACTION_DOWN, the window's views, then onTouchEvent.
    func dispatchTouchEvent(_ ev: AMotionEvent) -> Bool {
        if ev.action == AMotionEvent.ACTION_DOWN {
            onUserInteraction()
        }
        if let root = rootView?.viewRoot, root.superDispatchTouchEvent(ev) {
            return true
        }
        return onTouchEvent(ev)
    }

    /// Activity.onUserInteraction (override point).
    func onUserInteraction() {}

    /// Activity.onTouchEvent: a touch no view handled (an activity window never closes on touch outside).
    func onTouchEvent(_ event: AMotionEvent) -> Bool {
        if window.shouldCloseOnTouch(event) {
            finish()
            return true
        }
        return false
    }

    var rootView: AActivityRootView? { viewIfLoaded as? AActivityRootView }

    override var preferredStatusBarStyle: UIStatusBarStyle {
        // A dimming dialog darkens the bars (Android clears light-bar appearance behind a dim layer).
        if showingDialogs.contains(where: { $0.dimsBehind }) { return .lightContent }
        return window.appearanceLightStatusBars ? .darkContent : .lightContent
    }

    override var prefersStatusBarHidden: Bool { window.isStatusBarsHidden }
    override var prefersHomeIndicatorAutoHidden: Bool { window.isNavigationBarsHidden }
    override var preferredScreenEdgesDeferringSystemGestures: UIRectEdge { window.deferredSystemGestureEdges }

    private func systemBarsChanged() {
        setNeedsStatusBarAppearanceUpdate()
        setNeedsUpdateOfHomeIndicatorAutoHidden()
        setNeedsUpdateOfScreenEdgesDeferringSystemGestures()
        AActivityHost.shared?.systemBarsChanged(self)
    }

    // MARK: Android lifecycle (override points; call super)

    /// Activity.onCreate. Super attaches the FragmentManager, inflates `contentLayoutId` and creates the fragments.
    func onCreate(_ savedInstanceState: ABundle?) {
        mCalled = true
        // ComponentActivity: the context becomes available -> FragmentActivity attaches its FragmentManager.
        supportFragmentManager.attachController(self, nil)
        // Activity.onCreate (ComponentActivity's super call): the application callbacks.
        AApplication.shared.dispatchActivityCreated(self, savedInstanceState)
        if let layout = contentLayoutId { setContentView(layout) }
        // FragmentActivity.onCreate (after super.onCreate).
        fragmentHostLifecycle.handleLifecycleEvent(.ON_CREATE)
        supportFragmentManager.dispatchCreate()
    }

    func onPostCreate(_ savedInstanceState: ABundle?) { mCalled = true }

    func onStart() {
        mCalled = true
        // FragmentActivity.onStart.
        if !fragmentsCreated {
            fragmentsCreated = true
            supportFragmentManager.dispatchActivityCreated()
        }
        supportFragmentManager.execPendingActions(true)
        // Activity.onStart (FragmentActivity's super call).
        AApplication.shared.dispatchActivityStarted(self)
        fragmentHostLifecycle.handleLifecycleEvent(.ON_START)
        supportFragmentManager.dispatchStart()
    }

    func onRestart() { mCalled = true }

    func onResume() {
        mCalled = true
        // Activity.onResume (FragmentActivity's super call comes first).
        AApplication.shared.dispatchActivityResumed(self)
        // FragmentActivity.onResume.
        supportFragmentManager.execPendingActions(true)
    }

    func onPostResume() {
        mCalled = true
        onResumeFragments()
    }

    /// FragmentActivity.onResumeFragments.
    func onResumeFragments() {
        fragmentHostLifecycle.handleLifecycleEvent(.ON_RESUME)
        supportFragmentManager.dispatchResume()
    }

    func onPause() {
        mCalled = true
        // Activity.onPause (FragmentActivity's super call comes first).
        AApplication.shared.dispatchActivityPaused(self)
        supportFragmentManager.dispatchPause()
        fragmentHostLifecycle.handleLifecycleEvent(.ON_PAUSE)
    }

    func onStop() {
        mCalled = true
        // Activity.onStop (FragmentActivity's super call comes first).
        AApplication.shared.dispatchActivityStopped(self)
        markFragmentsCreated()
        supportFragmentManager.dispatchStop()
        fragmentHostLifecycle.handleLifecycleEvent(.ON_STOP)
    }

    func onDestroy() {
        mCalled = true
        // Activity.onDestroy (FragmentActivity's super call comes first).
        AApplication.shared.dispatchActivityDestroyed(self)
        supportFragmentManager.dispatchDestroy()
        fragmentHostLifecycle.handleLifecycleEvent(.ON_DESTROY)
    }

    /// Activity.onConfigurationChanged for the configChanges the manifest declares. Super dispatches to the
    /// fragments (ComponentActivity's OnConfigurationChangedListeners: one per FragmentManager).
    func onConfigurationChanged(_ newConfig: AConfiguration) {
        mCalled = true
        for listener in configurationListeners { listener.block(newConfig) }
    }

    func onWindowFocusChanged(_ hasFocus: Bool) {}

    /// Never called on iOS (no process death / state restoration).
    func onSaveInstanceState(_ outState: ABundle) {}

    /// ComponentActivity.onBackPressed(): the topmost showing dialog takes Back first (it has window focus), then
    /// the OnBackPressedDispatcher. iOS has no Back key: on-screen controls call this.
    func onBackPressed() {
        // The focused window: the topmost dialog that is not hidden (Dialog.hide leaves the window without focus).
        if let dialog = showingDialogs.last(where: { $0.isShowing }) {
            dialog.onBackPressed()
            return
        }
        onBackPressedDispatcher.onBackPressed()
    }

    /// Activity.onBackPressed's default (the dispatcher's fallback): a non-root activity finishes; the root activity
    /// of the task moves the task to the back on Android 12+, which iOS cannot do (no effect).
    private func defaultOnBackPressed() {
        if !isTaskRoot { finish() }
    }

    // MARK: Lifecycle driving (AActivityHost)

    private func checkSuper(_ name: String) {
        precondition(mCalled, "Activity \(type(of: self)) did not call through to super.\(name)()")
    }

    func performCreate() {
        if isCreatedState { return }
        mCalled = false
        onCreate(nil)
        checkSuper("onCreate")
        isCreatedState = true
        lastConfiguration = AConfiguration.current
        lifecycleRegistry.handleLifecycleEvent(.ON_CREATE)
    }

    func performPostCreate() {
        mCalled = false
        onPostCreate(nil)
        checkSuper("onPostCreate")
    }

    func performStart() {
        if isStartedState || mDestroyed { return }
        mCalled = false
        onStart()
        checkSuper("onStart")
        isStartedState = true
        lifecycleRegistry.handleLifecycleEvent(.ON_START)
    }

    func performRestart() {
        if isStartedState || mDestroyed { return }
        mCalled = false
        onRestart()
        checkSuper("onRestart")
        performStart()
    }

    func performResume() {
        if isResumedState || !isStartedState || mDestroyed { return }
        mCalled = false
        onResume()
        checkSuper("onResume")
        isResumedState = true
        mCalled = false
        onPostResume()
        checkSuper("onPostResume")
        lifecycleRegistry.handleLifecycleEvent(.ON_RESUME)
    }

    func performPause() {
        if !isResumedState { return }
        lifecycleRegistry.handleLifecycleEvent(.ON_PAUSE)
        mCalled = false
        onPause()
        checkSuper("onPause")
        isResumedState = false
    }

    func performStop() {
        if isResumedState { performPause() }
        if !isStartedState { return }
        lifecycleRegistry.handleLifecycleEvent(.ON_STOP)
        mCalled = false
        onStop()
        checkSuper("onStop")
        isStartedState = false
    }

    func performDestroy() {
        if mDestroyed { return }
        performStop()
        lifecycleRegistry.handleLifecycleEvent(.ON_DESTROY)
        mDestroyed = true
        // The activity's windows go away with it (no dismiss callbacks: Android removes leaked windows).
        for dialog in showingDialogs.reversed() { dialog.windowRemovedWithActivity() }
        showingDialogs.removeAll()
        mCalled = false
        onDestroy()
        checkSuper("onDestroy")
    }

    /// Delivers a configuration change (sizes/orientation) the activity handles itself.
    func performConfigurationChanged(_ newConfig: AConfiguration) {
        lastConfiguration = newConfig
        mCalled = false
        onConfigurationChanged(newConfig)
        checkSuper("onConfigurationChanged")
    }

    fileprivate func setWindowFocus(_ focus: Bool) {
        if windowFocus == focus { return }
        windowFocus = focus
        // ViewRootImpl.handleWindowFocusChanged: the tree observer's OnWindowFocusChangeListeners
        // (AKitAdditionsB.swift), then the window callback (Activity.onWindowFocusChanged).
        KitWindowFocusListeners.dispatch(window.decorView.viewTreeObserver, focus)
        onWindowFocusChanged(focus)
    }

    /// FragmentActivity.markFragmentsCreated: started fragment (and view) lifecycles drop to CREATED.
    private func markFragmentsCreated() {
        var reiterate = true
        while reiterate { reiterate = supportFragmentManager.markState(.CREATED) }
    }

    /// ComponentActivity.addOnConfigurationChangedListener (used by every FragmentManager of this activity).
    func addOnConfigurationChangedListener(_ owner: AnyObject, _ block: @escaping (AConfiguration) -> Void) {
        configurationListeners.append((owner: owner, block: block))
    }

    func removeOnConfigurationChangedListener(_ owner: AnyObject) {
        configurationListeners.removeAll { $0.owner === owner }
    }

    // MARK: Activity API

    /// Activity.setContentView(view).
    func setContentView(_ view: AView) { window.setContentView(view) }

    func setContentView(_ view: AView, _ params: AViewGroup.LayoutParams) { window.setContentView(view, params) }

    /// Activity.setContentView(layoutResID): the Swift builder registered for the layout name.
    func setContentView(_ layoutResID: String) {
        window.contentParent.removeAllViews()
        _ = ALayoutInflater.from(self).inflate(layoutResID, window.contentParent, true)
    }

    func addContentView(_ view: AView, _ params: AViewGroup.LayoutParams) { window.addContentView(view, params) }

    /// Activity.findViewById: searches the window's decor view.
    func findViewById<T: AView>(_ id: String) -> T? { window.findViewById(id) }

    func requireViewById<T: AView>(_ id: String) -> T {
        guard let v: T = findViewById(id) else { preconditionFailure("ID does not reference a View inside this Activity") }
        return v
    }

    /// Activity.getRequestedOrientation / setRequestedOrientation.
    var requestedOrientation: Int {
        get { mRequestedOrientation }
        set {
            mRequestedOrientation = newValue
            if newValue == AActivityInfo.SCREEN_ORIENTATION_LOCKED {
                lockedMask = AActivityInfo.mask(of: AActivityHost.shared?.currentInterfaceOrientation ?? .portrait)
            } else {
                lockedMask = nil
            }
            AActivityHost.shared?.updateOrientation()
        }
    }

    func getRequestedOrientation() -> Int { requestedOrientation }
    func setRequestedOrientation(_ orientation: Int) { requestedOrientation = orientation }

    /// Activity.startActivity: the app's own activities (AIntent(context, Class)), URLs, share sheets, mail.
    /// Throws AActivityNotFoundException when no app can handle an external intent, like Android.
    func startActivity(_ intent: AIntent) throws {
        if let cls = intent.componentClass {
            let activity = cls.init()
            activity.intent = intent
            if let host = AActivityHost.shared {
                host.startActivity(activity, from: self)
            }
            return
        }
        try AIntent.dispatchExternal(intent, from: self)
    }

    /// Activity.finish(): isFinishing becomes true now; the activity is paused, stopped and destroyed after the
    /// current message, like Android.
    func finish() {
        if mFinished { return }
        mFinished = true
        AActivityHost.shared?.finish(self)
    }

    var isFinishing: Bool { mFinished }
    var isDestroyed: Bool { mDestroyed }
    var isChangingConfigurations: Bool { false }
    var isTaskRoot: Bool { AActivityHost.shared?.activities.first === self }

    /// Activity.moveTaskToBack: iOS apps cannot send themselves to the background (returns false).
    @discardableResult
    func moveTaskToBack(_ nonRoot: Bool) -> Bool { false }

    /// Activity.hasWindowFocus(): false while a dialog window is on top, the activity is not the top resumed one,
    /// or the app is inactive.
    func hasWindowFocus() -> Bool { windowFocus }

    /// Activity.runOnUiThread: runs now on the main thread, else posts to it.
    func runOnUiThread(_ action: @escaping () -> Void) {
        if Thread.isMainThread {
            action()
        } else {
            DispatchQueue.main.async { action() }
        }
    }

    /// Activity.getApplication().
    var application: AApplication { AApplication.shared }

    // MARK: Dialog windows

    fileprivate func refreshFocus() {
        AActivityHost.shared?.refreshFocus()
    }

    func dialogWindowShown(_ dialog: ADialog) {
        showingDialogs.removeAll { $0 === dialog }
        showingDialogs.append(dialog)
        systemBarsChanged()
        refreshFocus()
    }

    func dialogWindowRemoved(_ dialog: ADialog) {
        showingDialogs.removeAll { $0 === dialog }
        systemBarsChanged()
        refreshFocus()
    }

    /// A shown dialog changed its dim or visibility (the status-bar appearance behind the dim layer, window focus).
    func dialogWindowAttributesChanged(_ dialog: ADialog) {
        systemBarsChanged()
        refreshFocus()
    }
}

/// The LifecycleOwner of FragmentActivity's host lifecycle (mFragmentLifecycleRegistry).
private final class KitFragmentHostLifecycleOwner: ALifecycleOwner {
    weak var activity: AActivity?
    init(_ activity: AActivity) { self.activity = activity }
    var lifecycle: ALifecycle { activity?.fragmentHostLifecycle ?? ALifecycle() }
}

/// The view of an AActivity: the AViewRoot host of the decor view, with the activity's dialog overlays above it.
final class AActivityRootView: UIView {
    weak var activity: AActivity?
    let contentHost = UIView()
    var viewRoot: AViewRoot?

    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = .clear
        contentHost.frame = bounds
        contentHost.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        contentHost.backgroundColor = .clear
        addSubview(contentHost)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { preconditionFailure("AActivityRootView is created in code") }

    override func layoutSubviews() {
        super.layoutSubviews()
        contentHost.frame = bounds
        for sub in subviews where sub !== contentHost { sub.frame = bounds }
    }

    /// Adds a dialog overlay on top of the activity content and the dialogs already shown.
    func addOverlay(_ overlay: UIView) {
        overlay.frame = bounds
        overlay.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        addSubview(overlay)
    }
}

// MARK: - Activity host (the task)

/// The window's root view controller: the activity stack (an Android task), the orientation mask of the top
/// activity, its status-bar / home-indicator choices, the app window configuration and the toast layer.
final class AActivityHost: UIViewController {
    nonisolated(unsafe) private(set) static var shared: AActivityHost?
    /// The supported orientations of the top activity (the app delegate returns it too).
    nonisolated(unsafe) static var orientationMask: UIInterfaceOrientationMask = .portrait

    enum SceneState { case background, inactive, active }

    private(set) var activities: [AActivity] = []
    private(set) var sceneState: SceneState = .inactive
    private let launcher: () -> AActivity
    private let handler = AHandler(ALooper.getMainLooper())
    /// Above every activity and dialog; never takes touches.
    let toastLayer = KitPassThroughView()

    init(launcher: @escaping () -> AActivity) {
        self.launcher = launcher
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { preconditionFailure("AActivityHost is created in code") }

    /// Installs the host as the window's root view controller and launches the launcher activity
    /// (onCreate, onStart; onResume once the scene is active).
    @discardableResult
    static func install(in window: UIWindow, launcher: @escaping () -> AActivity) -> AActivityHost {
        let host = AActivityHost(launcher: launcher)
        shared = host
        window.rootViewController = host
        host.loadViewIfNeeded()
        host.updateConfiguration(size: window.bounds.size, notify: false)
        host.launch()
        AToast.hostDidInstall()
        return host
    }

    var topActivity: AActivity? { activities.last }

    var currentInterfaceOrientation: UIInterfaceOrientation {
        view.window?.windowScene?.interfaceOrientation ?? .portrait
    }

    override func loadView() {
        let v = UIView(frame: UIScreen.main.bounds)
        v.backgroundColor = .black
        toastLayer.frame = v.bounds
        toastLayer.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        toastLayer.backgroundColor = .clear
        v.addSubview(toastLayer)
        view = v
    }

    // MARK: Launch and transitions

    private func launch() {
        let activity = launcher()
        if activity.intent.categories.isEmpty { activity.intent.addCategory(AIntent.CATEGORY_LAUNCHER) }
        activities.append(activity)
        activity.performCreate()
        activity.performStart()
        activity.performPostCreate()
        makeVisible(activity)
        if sceneState == .active { activity.performResume() }
        updateOrientation()
        refreshFocus()
        systemBarsChanged(activity)
    }

    /// Android's start of another activity of the task: A.onPause, then B.onCreate/onStart/onResume (B shown on
    /// top), then A.onStop (A's window hidden). Runs after the current message, like ActivityThread.
    func startActivity(_ activity: AActivity, from source: AActivity?) {
        _ = handler.post { [weak self] in
            guard let self = self else { return }
            let previous = self.topActivity
            previous?.performPause()
            self.activities.append(activity)
            activity.performCreate()
            activity.performStart()
            activity.performPostCreate()
            self.makeVisible(activity)
            if self.sceneState == .active { activity.performResume() }
            self.updateOrientation()
            self.refreshFocus()
            self.systemBarsChanged(activity)
            _ = self.handler.post { [weak self, weak previous] in
                guard let self = self, let previous = previous, previous !== self.topActivity else { return }
                previous.performStop()
                previous.rootView?.isHidden = true
            }
        }
    }

    /// Android's finish: B.onPause, A.onRestart/onStart/onResume (A shown again), then B.onStop and B.onDestroy.
    func finish(_ activity: AActivity) {
        _ = handler.post { [weak self] in
            guard let self = self, let index = self.activities.firstIndex(where: { $0 === activity }) else { return }
            let wasTop = index == self.activities.count - 1
            if wasTop {
                activity.performPause()
                self.activities.remove(at: index)
                if let below = self.topActivity {
                    below.rootView?.isHidden = false
                    self.deliverPendingConfiguration(below)
                    below.performRestart()
                    if self.sceneState == .active { below.performResume() }
                    self.updateOrientation()
                    self.systemBarsChanged(below)
                }
                self.refreshFocus()
                _ = self.handler.post { [weak self] in
                    activity.performDestroy()
                    self?.removeVisible(activity)
                    self?.relaunchIfEmpty()
                }
            } else {
                self.activities.remove(at: index)
                activity.performDestroy()
                self.removeVisible(activity)
            }
        }
    }

    /// Android finishing the last activity leaves the task; tapping the app again starts the launcher activity.
    private func relaunchIfEmpty() {
        if activities.isEmpty && sceneState != .background { launch() }
    }

    private func makeVisible(_ activity: AActivity) {
        addChild(activity)
        let v = activity.view!
        v.frame = view.bounds
        v.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        v.isHidden = false
        view.insertSubview(v, belowSubview: toastLayer)
        activity.didMove(toParent: self)
    }

    private func removeVisible(_ activity: AActivity) {
        activity.willMove(toParent: nil)
        activity.viewIfLoaded?.removeFromSuperview()
        activity.removeFromParent()
    }

    // MARK: Scene activation (resume/pause also follow app active/inactive)

    func sceneWillEnterForeground() {
        sceneState = .inactive
        if activities.isEmpty { launch(); return }
        if let top = topActivity {
            deliverPendingConfiguration(top)
            top.performRestart()
        }
        refreshFocus()
    }

    func sceneDidBecomeActive() {
        sceneState = .active
        if activities.isEmpty { launch() }
        topActivity?.performResume()
        refreshFocus()
        updateKeepScreenOn()
    }

    func sceneWillResignActive() {
        sceneState = .inactive
        topActivity?.performPause()
        refreshFocus()
    }

    func sceneDidEnterBackground() {
        sceneState = .background
        topActivity?.performStop()
        refreshFocus()
    }

    /// Window focus: the top activity while resumed, active and without a dialog on top.
    func refreshFocus() {
        let top = topActivity
        for activity in activities {
            let focus = activity === top && sceneState == .active && activity.isResumedState
                && !activity.showingDialogs.contains(where: { $0.isShowing })
            activity.setWindowFocus(focus)
        }
    }

    // MARK: Orientation

    override var supportedInterfaceOrientations: UIInterfaceOrientationMask { AActivityHost.orientationMask }

    private func mask(for index: Int) -> UIInterfaceOrientationMask {
        let activity = activities[index]
        if let locked = activity.lockedMask, activity.requestedOrientation == AActivityInfo.SCREEN_ORIENTATION_LOCKED {
            return locked
        }
        let behind: UIInterfaceOrientationMask? = index > 0 ? mask(for: index - 1) : nil
        return AActivityInfo.interfaceOrientationMask(activity.requestedOrientation,
                                                      isPad: UIDevice.current.userInterfaceIdiom == .pad,
                                                      current: currentInterfaceOrientation, behind: behind)
    }

    /// Applies the requested orientation of the top activity: supportedInterfaceOrientations +
    /// setNeedsUpdateOfSupportedInterfaceOrientations + UIWindowScene.requestGeometryUpdate (the proven
    /// SplashOrientation pattern).
    func updateOrientation() {
        guard !activities.isEmpty else { return }
        let mask = self.mask(for: activities.count - 1)
        if mask == AActivityHost.orientationMask { return }
        AActivityHost.orientationMask = mask
        setNeedsUpdateOfSupportedInterfaceOrientations()
        if let scene = view.window?.windowScene {
            scene.requestGeometryUpdate(.iOS(interfaceOrientations: mask)) { _ in }
        }
    }

    // MARK: Configuration

    override func viewWillTransition(to size: CGSize, with coordinator: UIViewControllerTransitionCoordinator) {
        super.viewWillTransition(to: size, with: coordinator)
        updateConfiguration(size: size, notify: true)
        coordinator.animate(alongsideTransition: { [weak self] _ in
            self?.view.layoutIfNeeded()
        }, completion: nil)
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        registerForTraitChanges([UITraitUserInterfaceStyle.self]) { (self: AActivityHost, previous: UITraitCollection) in
            self.userInterfaceStyleChanged(previous)
        }
    }

    private func userInterfaceStyleChanged(_ previous: UITraitCollection) {
        let dark = traitCollection.userInterfaceStyle == .dark
        if (previous.userInterfaceStyle == .dark) == dark { return }
        // uiMode is not in the manifest configChanges: Android recreates the activity; iOS cannot, so the
        // configuration (uiMode night bits) is updated without a callback.
        updateConfiguration(size: view.bounds.size, notify: false)
        for activity in activities { activity.window.applyThemeBackground(dark: dark) }
    }

    /// Recomputes AConfiguration.current; the top started activity gets onConfigurationChanged for a rotation /
    /// window-size change (both activities declare orientation|screenSize|smallestScreenSize|screenLayout), the
    /// others when they come back to the front.
    func updateConfiguration(size: CGSize, notify: Bool) {
        let screen = view.window?.screen ?? UIScreen.main
        let dark = traitCollection.userInterfaceStyle == .dark
        let newConfig = AConfiguration.make(windowSize: size, screenSize: screen.bounds.size, scale: screen.scale, dark: dark)
        if AConfiguration.current.diff(newConfig) == 0 { return }
        AConfiguration.current = newConfig
        guard notify, let top = topActivity, top.isStartedState else { return }
        deliverPendingConfiguration(top)
    }

    /// The size bits of a configuration diff: the changes the app's activities handle themselves
    /// (configChanges = orientation|screenSize|smallestScreenSize|screenLayout|keyboardHidden). Other changes
    /// (uiMode, locale) make Android recreate the activity, which has no iOS counterpart: no callback.
    static let sizeConfigChanges = AActivityInfo.CONFIG_ORIENTATION | AActivityInfo.CONFIG_SCREEN_SIZE
        | AActivityInfo.CONFIG_SMALLEST_SCREEN_SIZE | AActivityInfo.CONFIG_SCREEN_LAYOUT

    private func deliverPendingConfiguration(_ activity: AActivity) {
        let current = AConfiguration.current
        guard let last = activity.lastConfiguration, activity.isCreatedState, !activity.isDestroyed else { return }
        let diff = last.diff(current)
        if diff == 0 { return }
        if (diff & AActivityHost.sizeConfigChanges) != 0 {
            activity.performConfigurationChanged(current)
        } else {
            activity.lastConfiguration = current
        }
    }

    // MARK: System bars

    override var childForStatusBarStyle: UIViewController? { topActivity }
    override var childForStatusBarHidden: UIViewController? { topActivity }
    override var childForHomeIndicatorAutoHidden: UIViewController? { topActivity }
    override var childForScreenEdgesDeferringSystemGestures: UIViewController? { topActivity }

    func systemBarsChanged(_ activity: AActivity) {
        guard activity === topActivity else { return }
        setNeedsStatusBarAppearanceUpdate()
        setNeedsUpdateOfHomeIndicatorAutoHidden()
        setNeedsUpdateOfScreenEdgesDeferringSystemGestures()
        updateKeepScreenOn()
    }

    /// FLAG_KEEP_SCREEN_ON of the top activity's window -> the idle timer. View.setKeepScreenOn is AView's own; when
    /// the window flag goes away, the views' requests are applied again.
    private var idleTimerDisabledByWindowFlag = false

    func updateKeepScreenOn() {
        guard sceneState != .background, let top = topActivity else { return }
        let keep = top.window.keepsScreenOn
        if keep != idleTimerDisabledByWindowFlag {
            idleTimerDisabledByWindowFlag = keep
            UIApplication.shared.isIdleTimerDisabled = keep
            if !keep {
                AView.updateKeepScreenOn()
            }
        }
    }
}

/// A full-screen view that never takes touches (toast layer).
final class KitPassThroughView: UIView {
    override func hitTest(_ point: CGPoint, with event: UIEvent?) -> UIView? { nil }
}

// MARK: - DecorView

/// com.android.internal.policy.DecorView: the root view of a window. For a floating window (a dialog) measured
/// AT_MOST, the theme's windowMinWidthMinor (portrait) / windowMinWidthMajor (landscape) fraction of the screen width
/// (Configuration.screenWidthDp) is its minimum width. (The app's dialog themes set no fixed widths or heights.)
final class KitDecorView: AFrameLayout {
    /// DecorView.mWindow.
    weak var mWindow: AWindow?

    override init() {
        super.init()
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    override func onMeasure(_ widthMeasureSpec: Int, _ heightMeasureSpec: Int) {
        guard let w = mWindow, w.isFloating else {
            super.onMeasure(widthMeasureSpec, heightMeasureSpec)
            return
        }
        let config = AConfiguration.current
        let isPortrait = config.orientation == AConfiguration.ORIENTATION_PORTRAIT
        let widthMode = AMeasureSpec.getMode(widthMeasureSpec)

        super.onMeasure(widthMeasureSpec, heightMeasureSpec)

        let width = measuredWidth
        var measure = false
        var exactWidthSpec = AMeasureSpec.makeMeasureSpec(width, AMeasureSpec.EXACTLY)
        if widthMode == AMeasureSpec.AT_MOST, let fraction = isPortrait ? w.minWidthMinor : w.minWidthMajor {
            // TypedValue.applyDimension(COMPLEX_UNIT_DIP, screenWidthDp) and (int) tv.getFraction(available, available).
            let availableWidth = Float(config.screenWidthDp) * AWidgetEnv.density
            let min = (KitDecorView.complexFraction(fraction) * availableWidth).toInt()
            if width < min {
                exactWidthSpec = AMeasureSpec.makeMeasureSpec(min, AMeasureSpec.EXACTLY)
                measure = true
            }
        }
        if measure {
            super.onMeasure(exactWidthSpec, heightMeasureSpec)
        }
    }

    /// A fraction as aapt2 stores it (TypedValue complex: 23-bit mantissa, radix 0p23) and complexToFloat reads it.
    static func complexFraction(_ value: Float) -> Float {
        let bits = UInt64(value * Float(1 << 23) + 0.5)
        let mantissa = bits & 0xFFFFFF
        return Float(mantissa) / Float(1 << 23)
    }
}
