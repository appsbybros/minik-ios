import XCTest
import UIKit
@testable import MinikTripleShot

// Area kit-platform: the Android app structure on AndroidKit (AActivity, AFragment, ADialog, AToast, AIntent,
// AHaptics). The expected values come from the Android sources the app links: ActivityInfo / Configuration constants
// (android-36), androidx.fragment 1.8.9 (transaction and lifecycle order), androidx.activity (OnBackPressedDispatcher),
// androidx.lifecycle (LifecycleRegistry sync order), AppCompat AlertController / ListView choice modes, framework
// ViewRootImpl.measureHierarchy / Gravity.apply / Window.shouldCloseOnTouch, NotificationManagerService toast timing,
// HapticFeedbackVibrationProvider. Everything runs on AndroidKit's fake main thread (AndroidKitTestLoop).

// MARK: - Test doubles

/// An activity whose content view is one FrameLayout with id "container" (TripleShotDemoActivity's layout shape).
private final class PlatformTestActivity: AActivity {
    let container = AFrameLayout()

    override func onCreate(_ savedInstanceState: ABundle?) {
        super.onCreate(savedInstanceState)
        container.viewId = "container"
        setContentView(container)
    }
}

/// A fragment that logs its lifecycle callbacks into a shared log.
private final class LogFragment: AFragment {
    let name: String
    let log: KRef<[String]>

    init(_ name: String, _ log: KRef<[String]>) {
        self.name = name
        self.log = log
        super.init()
    }

    override func onAttach(_ context: AContext) { super.onAttach(context); log.value.append(name + ".onAttach") }
    override func onCreate(_ savedInstanceState: ABundle?) { super.onCreate(savedInstanceState); log.value.append(name + ".onCreate") }
    override func onCreateView(_ inflater: ALayoutInflater, _ container: AViewGroup?, _ savedInstanceState: ABundle?) -> AView? {
        log.value.append(name + ".onCreateView")
        return AFrameLayout()
    }
    override func onViewCreated(_ view: AView, _ savedInstanceState: ABundle?) { log.value.append(name + ".onViewCreated") }
    override func onStart() { super.onStart(); log.value.append(name + ".onStart") }
    override func onResume() { super.onResume(); log.value.append(name + ".onResume") }
    override func onPause() { super.onPause(); log.value.append(name + ".onPause") }
    override func onStop() { super.onStop(); log.value.append(name + ".onStop") }
    override func onDestroyView() { super.onDestroyView(); log.value.append(name + ".onDestroyView") }
    override func onDestroy() { super.onDestroy(); log.value.append(name + ".onDestroy") }
    override func onDetach() { super.onDetach(); log.value.append(name + ".onDetach") }
}

/// A LifecycleOwner with its own registry.
private final class TestLifecycleOwner: ALifecycleOwner {
    private(set) lazy var registry = ALifecycleRegistry(self)
    var lifecycle: ALifecycle { registry }
}

/// A LifecycleEventObserver that logs "<name>:<event>".
private final class LoggingObserver: ALifecycleEventObserver {
    let name: String
    let log: KRef<[String]>
    init(_ name: String, _ log: KRef<[String]>) {
        self.name = name
        self.log = log
    }
    func onStateChanged(_ source: ALifecycleOwner, _ event: ALifecycle.Event) {
        log.value.append("\(name):\(event)")
    }
}

/// Records SystemUI's show / hide calls of the toast queue, with the fake uptime.
private final class RecordingToastPresenter: KitToastPresenting {
    var events: [String] = []
    let origin: Int64
    init(origin: Int64) { self.origin = origin }
    func showToast(_ record: KitToastManager.Record) {
        events.append("show:\(record.text)@\(ASystemClock.uptimeMillis() - origin)")
    }
    func hideToast(_ record: KitToastManager.Record) {
        events.append("hide:\(record.text)@\(ASystemClock.uptimeMillis() - origin)")
    }
}

/// A view that wants a fixed size and records the width measure specs it gets (TOO_SMALL when squeezed).
private final class WantsSizeView: AView {
    var wantedWidth = 0
    var wantedHeight = 0
    var widthSpecs: [Int] = []

    override func onMeasure(_ widthMeasureSpec: Int, _ heightMeasureSpec: Int) {
        widthSpecs.append(widthMeasureSpec)
        setMeasuredDimension(AView.resolveSizeAndState(wantedWidth, widthMeasureSpec, 0),
                             AView.resolveSizeAndState(wantedHeight, heightMeasureSpec, 0))
    }
}

final class AndroidKitPlatformTests: XCTestCase {
    private let T0: Int64 = 1_000_000_000_000
    private var savedConfiguration: AConfiguration!
    private var activities: [AActivity] = []

    override func setUp() {
        super.setUp()
        AndroidKitTestLoop.install(startNanos: T0)
        savedConfiguration = AConfiguration.current
        KitToastManager.shared.resetForTesting()
    }

    override func tearDown() {
        for a in activities {
            a.performDestroy()
        }
        activities.removeAll()
        KitToastManager.shared.resetForTesting()
        KitToastManager.shared.presenter = nil
        AConfiguration.current = savedConfiguration
        AndroidKitTestLoop.uninstall()
        super.tearDown()
    }

    /// A created, started and resumed test activity (ActivityThread's launch order).
    private func resumedActivity() -> PlatformTestActivity {
        let a = PlatformTestActivity()
        a.performCreate()
        a.performStart()
        a.performPostCreate()
        a.performResume()
        activities.append(a)
        return a
    }

    private func portraitPhoneConfiguration() -> AConfiguration {
        AConfiguration.make(windowSize: CGSize(width: 393, height: 852), screenSize: CGSize(width: 393, height: 852),
                            scale: 3, dark: false)
    }

    // MARK: - ActivityInfo: requested orientation -> iOS mask

    func testRequestedOrientationConstantsHaveTheAndroidValues() {
        XCTAssertEqual(AActivityInfo.SCREEN_ORIENTATION_UNSPECIFIED, -1)
        XCTAssertEqual(AActivityInfo.SCREEN_ORIENTATION_LANDSCAPE, 0)
        XCTAssertEqual(AActivityInfo.SCREEN_ORIENTATION_PORTRAIT, 1)
        XCTAssertEqual(AActivityInfo.SCREEN_ORIENTATION_USER, 2)
        XCTAssertEqual(AActivityInfo.SCREEN_ORIENTATION_SENSOR, 4)
        XCTAssertEqual(AActivityInfo.SCREEN_ORIENTATION_SENSOR_LANDSCAPE, 6)
        XCTAssertEqual(AActivityInfo.SCREEN_ORIENTATION_SENSOR_PORTRAIT, 7)
        XCTAssertEqual(AActivityInfo.SCREEN_ORIENTATION_FULL_SENSOR, 10)
        XCTAssertEqual(AActivityInfo.SCREEN_ORIENTATION_LOCKED, 14)
        XCTAssertEqual(AActivityInfo.CONFIG_ORIENTATION, 0x0080)
        XCTAssertEqual(AActivityInfo.CONFIG_SCREEN_SIZE, 0x0400)
        XCTAssertEqual(AActivityInfo.CONFIG_SMALLEST_SCREEN_SIZE, 0x0800)
        XCTAssertEqual(AActivityInfo.CONFIG_SCREEN_LAYOUT, 0x0100)
        XCTAssertEqual(AActivityInfo.CONFIG_KEYBOARD_HIDDEN, 0x0020)
    }

    func testPortraitAndLandscapeRequestsMapToFixedMasks() {
        for isPad in [false, true] {
            XCTAssertEqual(AActivityInfo.interfaceOrientationMask(AActivityInfo.SCREEN_ORIENTATION_PORTRAIT, isPad: isPad,
                                                                  current: .landscapeLeft), .portrait)
            XCTAssertEqual(AActivityInfo.interfaceOrientationMask(AActivityInfo.SCREEN_ORIENTATION_SENSOR_LANDSCAPE,
                                                                  isPad: isPad, current: .portrait), .landscape)
            // Android LANDSCAPE is rotation 90 (home side right) = UIInterfaceOrientation.landscapeRight.
            XCTAssertEqual(AActivityInfo.interfaceOrientationMask(AActivityInfo.SCREEN_ORIENTATION_LANDSCAPE, isPad: isPad,
                                                                  current: .portrait), .landscapeRight)
            XCTAssertEqual(AActivityInfo.interfaceOrientationMask(AActivityInfo.SCREEN_ORIENTATION_REVERSE_LANDSCAPE,
                                                                  isPad: isPad, current: .portrait), .landscapeLeft)
            XCTAssertEqual(AActivityInfo.interfaceOrientationMask(AActivityInfo.SCREEN_ORIENTATION_SENSOR_PORTRAIT,
                                                                  isPad: isPad, current: .portrait),
                           [.portrait, .portraitUpsideDown])
            XCTAssertEqual(AActivityInfo.interfaceOrientationMask(AActivityInfo.SCREEN_ORIENTATION_FULL_SENSOR, isPad: isPad,
                                                                  current: .portrait), .all)
        }
    }

    func testSensorUserAndUnspecifiedFollowTheDeviceWithoutUpsideDownOnPhones() {
        let free = [AActivityInfo.SCREEN_ORIENTATION_SENSOR, AActivityInfo.SCREEN_ORIENTATION_USER,
                    AActivityInfo.SCREEN_ORIENTATION_UNSPECIFIED]
        for requested in free {
            XCTAssertEqual(AActivityInfo.interfaceOrientationMask(requested, isPad: false, current: .portrait),
                           .allButUpsideDown)
            XCTAssertEqual(AActivityInfo.interfaceOrientationMask(requested, isPad: true, current: .portrait), .all)
        }
    }

    func testLockedKeepsTheCurrentOrientationAndBehindUsesTheActivityBelow() {
        XCTAssertEqual(AActivityInfo.interfaceOrientationMask(AActivityInfo.SCREEN_ORIENTATION_LOCKED, isPad: false,
                                                              current: .landscapeLeft), .landscapeLeft)
        XCTAssertEqual(AActivityInfo.interfaceOrientationMask(AActivityInfo.SCREEN_ORIENTATION_LOCKED, isPad: false,
                                                              current: .unknown), .portrait)
        XCTAssertEqual(AActivityInfo.interfaceOrientationMask(AActivityInfo.SCREEN_ORIENTATION_BEHIND, isPad: false,
                                                              current: .portrait, behind: .landscape), .landscape)
        XCTAssertEqual(AActivityInfo.mask(of: .portraitUpsideDown), .portraitUpsideDown)
        XCTAssertNil(AActivityInfo.mask(of: .unknown))
    }

    func testTheManifestGivesTheLauncherActivityPortraitAndTheJourneyTheDeviceOrientation() {
        TripleShotApp.registerManifest()
        let demo = AActivity.manifest["TripleShotDemoActivity"]
        XCTAssertEqual(demo?.screenOrientation, AActivityInfo.SCREEN_ORIENTATION_PORTRAIT)
        XCTAssertEqual(demo?.configChanges, TripleShotApp.handledConfigChanges)
        XCTAssertEqual(AActivity.manifest["BasketballJourneyActivity"]?.screenOrientation,
                       AActivityInfo.SCREEN_ORIENTATION_UNSPECIFIED)
        XCTAssertEqual(TripleShotApp.handledConfigChanges & AActivityHost.sizeConfigChanges, AActivityHost.sizeConfigChanges)
    }

    // MARK: - Configuration

    func testConfigurationOfAPortraitPhoneWindow() {
        let c = portraitPhoneConfiguration()
        XCTAssertEqual(c.orientation, AConfiguration.ORIENTATION_PORTRAIT)
        XCTAssertEqual(c.screenWidthDp, 393)
        XCTAssertEqual(c.screenHeightDp, 852)
        XCTAssertEqual(c.smallestScreenWidthDp, 393)
        XCTAssertEqual(c.densityDpi, 480)
        XCTAssertEqual(c.fontScale, 1)
        XCTAssertEqual(c.uiMode, AConfiguration.UI_MODE_TYPE_NORMAL | AConfiguration.UI_MODE_NIGHT_NO)
        XCTAssertFalse(c.isNightModeActive)
        XCTAssertEqual(c.screenLayout & AConfiguration.SCREENLAYOUT_SIZE_MASK, AConfiguration.SCREENLAYOUT_SIZE_NORMAL)
        XCTAssertEqual(c.screenLayout & AConfiguration.SCREENLAYOUT_LONG_MASK, AConfiguration.SCREENLAYOUT_LONG_YES)
    }

    func testConfigurationOrientationIsLandscapeOnlyWhenWiderThanTall() {
        let landscape = AConfiguration.make(windowSize: CGSize(width: 852, height: 393),
                                            screenSize: CGSize(width: 852, height: 393), scale: 3, dark: true)
        XCTAssertEqual(landscape.orientation, AConfiguration.ORIENTATION_LANDSCAPE)
        XCTAssertTrue(landscape.isNightModeActive)
        let square = AConfiguration.make(windowSize: CGSize(width: 500, height: 500),
                                         screenSize: CGSize(width: 500, height: 500), scale: 2, dark: false)
        XCTAssertEqual(square.orientation, AConfiguration.ORIENTATION_PORTRAIT)
        let pad = AConfiguration.make(windowSize: CGSize(width: 1024, height: 1366),
                                      screenSize: CGSize(width: 1024, height: 1366), scale: 2, dark: false)
        XCTAssertEqual(pad.screenLayout & AConfiguration.SCREENLAYOUT_SIZE_MASK, AConfiguration.SCREENLAYOUT_SIZE_XLARGE)
        XCTAssertEqual(pad.densityDpi, 320)
    }

    func testRotationDiffsAreTheConfigChangesTheActivitiesHandleThemselves() {
        let portrait = portraitPhoneConfiguration()
        let landscape = AConfiguration.make(windowSize: CGSize(width: 852, height: 393),
                                            screenSize: CGSize(width: 393, height: 852), scale: 3, dark: false)
        let diff = portrait.diff(landscape)
        XCTAssertNotEqual(diff & AActivityInfo.CONFIG_ORIENTATION, 0)
        XCTAssertNotEqual(diff & AActivityInfo.CONFIG_SCREEN_SIZE, 0)
        XCTAssertEqual(diff & AActivityInfo.CONFIG_SMALLEST_SCREEN_SIZE, 0)
        XCTAssertEqual(diff & ~AActivityHost.sizeConfigChanges, 0)
        let dark = AConfiguration.make(windowSize: CGSize(width: 393, height: 852),
                                       screenSize: CGSize(width: 393, height: 852), scale: 3, dark: true)
        XCTAssertEqual(portrait.diff(dark), AActivityInfo.CONFIG_UI_MODE)
        XCTAssertEqual(portrait.diff(AConfiguration(portrait)), 0)
    }

    // MARK: - Fragments: transactions and the back stack

    func testCommitRunsOnTheNextLooperTurnAndAddsTheFragmentUpToResumed() {
        let a = resumedActivity()
        let log = KRef<[String]>([])
        let home = LogFragment("Home", log)
        a.supportFragmentManager.beginTransaction().replace("container", home).commit()
        XCTAssertTrue(a.supportFragmentManager.fragments.isEmpty)
        XCTAssertTrue(log.value.isEmpty)
        AndroidKitTestLoop.runDueMessages()
        XCTAssertEqual(log.value, ["Home.onAttach", "Home.onCreate", "Home.onCreateView", "Home.onViewCreated",
                                   "Home.onStart", "Home.onResume"])
        XCTAssertTrue(a.supportFragmentManager.fragments.first === home)
        XCTAssertTrue(home.isAdded)
        XCTAssertTrue(home.isResumed)
        XCTAssertTrue(home.view?.parentGroup === a.container)
        XCTAssertTrue(home.requireActivity() === a)
        XCTAssertEqual(a.supportFragmentManager.backStackEntryCount, 0)
    }

    func testExecutePendingTransactionsAndCommitNowRunAtOnce() {
        let a = resumedActivity()
        let log = KRef<[String]>([])
        let first = LogFragment("A", log)
        a.supportFragmentManager.beginTransaction().replace("container", first).commit()
        a.supportFragmentManager.executePendingTransactions()
        XCTAssertTrue(first.isResumed)
        let second = LogFragment("B", log)
        a.supportFragmentManager.beginTransaction().replace("container", second).commitNow()
        XCTAssertTrue(second.isResumed)
        XCTAssertFalse(first.isAdded)
    }

    func testReplaceWithoutBackStackFollowsTheAndroidCallbackOrder() {
        let a = resumedActivity()
        let log = KRef<[String]>([])
        let first = LogFragment("A", log)
        let second = LogFragment("B", log)
        let fm = a.supportFragmentManager
        fm.beginTransaction().replace("container", first).commit()
        AndroidKitTestLoop.runDueMessages()
        log.value.removeAll()
        fm.beginTransaction().replace("container", second).commit()
        AndroidKitTestLoop.runDueMessages()
        XCTAssertEqual(log.value, ["A.onPause", "A.onStop", "B.onAttach", "B.onCreate", "B.onCreateView",
                                   "B.onViewCreated", "B.onStart", "A.onDestroyView", "A.onDestroy", "A.onDetach",
                                   "B.onResume"])
        XCTAssertEqual(fm.fragments.count, 1)
        XCTAssertTrue(fm.fragments.first === second)
        XCTAssertFalse(first.isAdded)
        XCTAssertNil(first.view)
        XCTAssertEqual(a.container.childCount, 1)
    }

    func testBackStackKeepsTheReplacedFragmentCreatedAndPopRestoresIt() {
        let a = resumedActivity()
        let log = KRef<[String]>([])
        let home = LogFragment("Home", log)
        let game = LogFragment("Game", log)
        let fm = a.supportFragmentManager
        fm.beginTransaction().replace("container", home).commit()
        AndroidKitTestLoop.runDueMessages()
        log.value.removeAll()
        fm.beginTransaction().replace("container", game).addToBackStack("game").commit()
        AndroidKitTestLoop.runDueMessages()
        XCTAssertEqual(log.value, ["Home.onPause", "Home.onStop", "Game.onAttach", "Game.onCreate", "Game.onCreateView",
                                   "Game.onViewCreated", "Game.onStart", "Home.onDestroyView", "Game.onResume"])
        XCTAssertEqual(fm.backStackEntryCount, 1)
        XCTAssertEqual(fm.getBackStackEntryAt(0).getName(), "game")
        XCTAssertNil(home.view)
        XCTAssertFalse(home.isAdded)

        log.value.removeAll()
        fm.popBackStack()
        XCTAssertEqual(fm.backStackEntryCount, 1)          // asynchronous, like Android
        AndroidKitTestLoop.runDueMessages()
        XCTAssertEqual(log.value, ["Game.onPause", "Game.onStop", "Home.onCreateView", "Home.onViewCreated", "Home.onStart",
                                   "Game.onDestroyView", "Game.onDestroy", "Game.onDetach", "Home.onResume"])
        XCTAssertEqual(fm.backStackEntryCount, 0)
        XCTAssertTrue(fm.fragments.first === home)
        XCTAssertTrue(home.isResumed)
        XCTAssertFalse(game.isAdded)
    }

    func testPopBackStackInclusiveOfNullClearsTheWholeStackLikeBackToHome() {
        let a = resumedActivity()
        let log = KRef<[String]>([])
        let fm = a.supportFragmentManager
        let home = LogFragment("Home", log)
        fm.beginTransaction().replace("container", home).commit()
        fm.executePendingTransactions()
        for name in ["live_setup", "game", "leaderboard"] {
            fm.beginTransaction().replace("container", LogFragment(name, log)).addToBackStack(name).commit()
            fm.executePendingTransactions()
        }
        XCTAssertEqual(fm.backStackEntryCount, 3)
        fm.popBackStack(nil, AFragmentManager.POP_BACK_STACK_INCLUSIVE)
        fm.executePendingTransactions()
        XCTAssertEqual(fm.backStackEntryCount, 0)
        XCTAssertTrue(fm.fragments.first === home)
        // TripleShotHostFragment.backToHome then shows a new Home instance (no back-stack entry).
        let newHome = LogFragment("Home2", log)
        fm.beginTransaction().replace("container", newHome).commit()
        fm.executePendingTransactions()
        XCTAssertEqual(fm.fragments.count, 1)
        XCTAssertTrue(fm.fragments.first === newHome)
        XCTAssertFalse(home.isAdded)
        XCTAssertTrue(log.value.contains("Home.onDetach"))
    }

    func testPopBackStackByNameIsExclusiveUnlessInclusive() {
        let a = resumedActivity()
        let log = KRef<[String]>([])
        let fm = a.supportFragmentManager
        fm.beginTransaction().replace("container", LogFragment("root", log)).commit()
        fm.executePendingTransactions()
        for name in ["a", "b", "c"] {
            fm.beginTransaction().replace("container", LogFragment(name, log)).addToBackStack(name).commit()
            fm.executePendingTransactions()
        }
        fm.popBackStack("a", 0)
        fm.executePendingTransactions()
        XCTAssertEqual(fm.backStackEntryCount, 1)
        XCTAssertEqual(fm.getBackStackEntryAt(0).getName(), "a")
        fm.popBackStack("a", AFragmentManager.POP_BACK_STACK_INCLUSIVE)
        fm.executePendingTransactions()
        XCTAssertEqual(fm.backStackEntryCount, 0)
        // Popping a name that is not on the stack does nothing.
        XCTAssertFalse(fm.popBackStackImmediate("missing", 0))
    }

    func testFindFragmentByIdAndTagAndBackStackListener() {
        let a = resumedActivity()
        let log = KRef<[String]>([])
        let fm = a.supportFragmentManager
        var changes = 0
        let listener = AFragmentManager.OnBackStackChangedListener { changes += 1 }
        fm.addOnBackStackChangedListener(listener)
        let tagged = LogFragment("tagged", log)
        fm.beginTransaction().replace("container", tagged, "home-tag").addToBackStack(nil).commit()
        fm.executePendingTransactions()
        XCTAssertTrue(fm.findFragmentById("container") === tagged)
        XCTAssertTrue(fm.findFragmentByTag("home-tag") === tagged)
        XCTAssertNil(fm.findFragmentByTag("other"))
        XCTAssertEqual(changes, 1)
        XCTAssertTrue(fm.popBackStackImmediate())
        XCTAssertEqual(changes, 2)
        fm.removeOnBackStackChangedListener(listener)
    }

    func testChildFragmentManagerUsesTheParentFragmentViewAsContainer() {
        let a = resumedActivity()
        let log = KRef<[String]>([])
        let host = LogFragment("Host", log)
        a.supportFragmentManager.beginTransaction().replace("container", host).commitNow()
        let childContainer = AFrameLayout()
        childContainer.viewId = "tripleShotChildContainer"
        (host.requireView() as! AViewGroup).addView(childContainer)
        let child = LogFragment("Child", log)
        host.childFragmentManager.beginTransaction().replace("tripleShotChildContainer", child).commit()
        host.childFragmentManager.executePendingTransactions()
        XCTAssertTrue(child.isResumed)
        XCTAssertTrue(child.parentFragment === host)
        XCTAssertTrue(child.view?.parentGroup === childContainer)
        XCTAssertTrue(child.requireActivity() === a)
    }

    func testActivityBackPressPopsTheFragmentBackStackAndCallbacksComeFirst() {
        let a = resumedActivity()
        let log = KRef<[String]>([])
        let fm = a.supportFragmentManager
        fm.beginTransaction().replace("container", LogFragment("Home", log)).commitNow()
        let game = LogFragment("Game", log)
        fm.beginTransaction().replace("container", game).addToBackStack("game").commit()
        fm.executePendingTransactions()
        // A fragment's view-lifecycle callback (TripleShotGameFragment's "leave to home") is newer: it wins.
        var handled = 0
        let callback = AOnBackPressedCallback(true) { _ in handled += 1 }
        a.onBackPressedDispatcher.addCallback(game.viewLifecycleOwner, callback)
        a.onBackPressed()
        XCTAssertEqual(handled, 1)
        XCTAssertEqual(fm.backStackEntryCount, 1)
        callback.isEnabled = false
        a.onBackPressed()
        XCTAssertEqual(fm.backStackEntryCount, 0)
        XCTAssertEqual(handled, 1)
    }

    // MARK: - OnBackPressedDispatcher and LifecycleRegistry

    func testDispatcherRunsTheNewestEnabledCallbackThenTheFallback() {
        var log: [String] = []
        let dispatcher = AOnBackPressedDispatcher { log.append("fallback") }
        let first = AOnBackPressedCallback(true) { _ in log.append("first") }
        let second = AOnBackPressedCallback(true) { _ in log.append("second") }
        dispatcher.addCallback(first)
        dispatcher.addCallback(second)
        XCTAssertTrue(dispatcher.hasEnabledCallbacks())
        dispatcher.onBackPressed()
        second.isEnabled = false
        dispatcher.onBackPressed()
        first.remove()
        dispatcher.onBackPressed()
        XCTAssertEqual(log, ["second", "first", "fallback"])
        XCTAssertFalse(dispatcher.hasEnabledCallbacks())
    }

    func testLifecycleBoundCallbackIsActiveOnlyWhileStarted() {
        var log: [String] = []
        let dispatcher = AOnBackPressedDispatcher { log.append("fallback") }
        let owner = TestLifecycleOwner()
        owner.registry.handleLifecycleEvent(.ON_CREATE)
        dispatcher.addCallback(owner, AOnBackPressedCallback(true) { _ in log.append("callback") })
        dispatcher.onBackPressed()
        owner.registry.handleLifecycleEvent(.ON_START)
        dispatcher.onBackPressed()
        owner.registry.handleLifecycleEvent(.ON_STOP)
        dispatcher.onBackPressed()
        owner.registry.handleLifecycleEvent(.ON_DESTROY)
        dispatcher.onBackPressed()
        XCTAssertEqual(log, ["fallback", "callback", "fallback", "fallback"])
    }

    func testLifecycleRegistrySyncsObserversInInsertionOrderUpAndReverseOrderDown() {
        let log = KRef<[String]>([])
        let owner = TestLifecycleOwner()
        owner.registry.addObserver(LoggingObserver("o1", log))
        owner.registry.addObserver(LoggingObserver("o2", log))
        owner.registry.setCurrentState(.RESUMED)
        XCTAssertEqual(log.value, ["o1:ON_CREATE", "o1:ON_START", "o1:ON_RESUME",
                                   "o2:ON_CREATE", "o2:ON_START", "o2:ON_RESUME"])
        log.value.removeAll()
        owner.registry.setCurrentState(.CREATED)
        XCTAssertEqual(log.value, ["o2:ON_PAUSE", "o2:ON_STOP", "o1:ON_PAUSE", "o1:ON_STOP"])
        log.value.removeAll()
        // A late observer catches up to the current state.
        owner.registry.addObserver(LoggingObserver("late", log))
        XCTAssertEqual(log.value, ["late:ON_CREATE"])
    }

    func testActivityLifecycleOrderAndFragmentHostState() {
        let log = KRef<[String]>([])
        let a = PlatformTestActivity()
        activities.append(a)
        a.lifecycle.addObserver(LoggingObserver("activity", log))
        a.performCreate()
        a.performStart()
        a.performPostCreate()
        a.performResume()
        a.performPause()
        a.performStop()
        XCTAssertEqual(log.value, ["activity:ON_CREATE", "activity:ON_START", "activity:ON_RESUME",
                                   "activity:ON_PAUSE", "activity:ON_STOP"])
        XCTAssertTrue(a.supportFragmentManager.isStateSaved)
        a.performRestart()
        XCTAssertFalse(a.supportFragmentManager.isStateSaved)
    }

    // MARK: - Toasts (NotificationManagerService queue timing)

    func testToastsShowOneAfterAnotherWithTheAndroidDelays() {
        let origin = ASystemClock.uptimeMillis()
        let presenter = RecordingToastPresenter(origin: origin)
        KitToastManager.shared.presenter = presenter
        AToast.makeText("one", AToast.LENGTH_SHORT).show()
        AToast.makeText("two", AToast.LENGTH_LONG).show()
        XCTAssertEqual(presenter.events, ["show:one@0"])
        AndroidKitTestLoop.advance(millis: 2332)
        XCTAssertEqual(presenter.events, ["show:one@0"])
        // SHORT_DELAY 2000 + 333 ms for the "in" animation.
        AndroidKitTestLoop.advance(millis: 1)
        XCTAssertEqual(presenter.events, ["show:one@0", "hide:one@2333", "show:two@2333"])
        // LONG_DELAY 3500 + 250 (previous "out" animation) + 333.
        AndroidKitTestLoop.advance(millis: 3500 + 250 + 333)
        XCTAssertEqual(presenter.events.last, "hide:two@6416")
        XCTAssertTrue(KitToastManager.shared.queue.isEmpty)
    }

    func testAtMostFiveToastsAreQueued() {
        KitToastManager.shared.presenter = RecordingToastPresenter(origin: 0)
        for i in 0..<7 {
            AToast.makeText("toast \(i)", AToast.LENGTH_SHORT).show()
        }
        XCTAssertEqual(KitToastManager.shared.queue.count, KitToastManager.MAX_PACKAGE_TOASTS)
        XCTAssertEqual(KitToastManager.shared.queue.map { $0.text }.last, "toast 4")
    }

    func testShowingTheCurrentToastAgainRestartsItWithTheNewDuration() {
        let origin = ASystemClock.uptimeMillis()
        let presenter = RecordingToastPresenter(origin: origin)
        KitToastManager.shared.presenter = presenter
        let toast = AToast.makeText("again", AToast.LENGTH_SHORT)
        toast.show()
        AndroidKitTestLoop.advance(millis: 1000)
        toast.setDuration(AToast.LENGTH_LONG)
        toast.show()
        XCTAssertEqual(presenter.events, ["show:again@0", "show:again@1000"])
        AndroidKitTestLoop.advance(millis: 3500 + 333 - 1)
        XCTAssertEqual(presenter.events.count, 2)
        AndroidKitTestLoop.advance(millis: 1)
        XCTAssertEqual(presenter.events.last, "hide:again@4833")
    }

    func testCancelHidesTheCurrentToastAndShowsTheNext() {
        let origin = ASystemClock.uptimeMillis()
        let presenter = RecordingToastPresenter(origin: origin)
        KitToastManager.shared.presenter = presenter
        let first = AToast.makeText("first", AToast.LENGTH_LONG)
        first.show()
        AToast.makeText("second", AToast.LENGTH_SHORT).show()
        AndroidKitTestLoop.advance(millis: 500)
        first.cancel()
        XCTAssertEqual(presenter.events, ["show:first@0", "hide:first@500", "show:second@500"])
        AndroidKitTestLoop.advance(millis: 2000 + 250 + 333)
        XCTAssertEqual(presenter.events.last, "hide:second@3083")
    }

    func testToastTextMayBeAStringResourceName() {
        XCTAssertEqual(AToast.makeText("No suitable app is installed", AToast.LENGTH_LONG).text,
                       "No suitable app is installed")
        XCTAssertEqual(AToast.makeText(R.string.minik_swish_bot_setup_choose_ready, AToast.LENGTH_SHORT).text,
                       getString(R.string.minik_swish_bot_setup_choose_ready))
        XCTAssertEqual(AToast.makeText(nil, android.R.string.cancel, AToast.LENGTH_SHORT).text,
                       getString(android.R.string.cancel))
        XCTAssertEqual(AToast.makeText("a", AToast.LENGTH_LONG).getDuration(), AToast.LENGTH_LONG)
    }

    // MARK: - Haptics

    func testHapticConstantsPlayTheAndroidEffects() {
        XCTAssertEqual(AHaptics.effect(AHapticFeedbackConstants.LONG_PRESS), .heavyClick)
        XCTAssertEqual(AHaptics.effect(AHapticFeedbackConstants.CLOCK_TICK), .textureTick)
        XCTAssertEqual(AHaptics.effect(AHapticFeedbackConstants.VIRTUAL_KEY), .click)
        XCTAssertEqual(AHaptics.effect(AHapticFeedbackConstants.CONFIRM), .click)
        XCTAssertEqual(AHaptics.effect(AHapticFeedbackConstants.REJECT), .doubleClick)
        XCTAssertEqual(AHaptics.effect(AHapticFeedbackConstants.CONTEXT_CLICK), .tick)
        XCTAssertEqual(AHaptics.effect(AHapticFeedbackConstants.KEYBOARD_TAP), .click)
        XCTAssertEqual(AHaptics.effect(AHapticFeedbackConstants.KEYBOARD_RELEASE), .tick)
        XCTAssertEqual(AHaptics.effect(AHapticFeedbackConstants.TOGGLE_ON), .primitiveTick(0.5))
        XCTAssertEqual(AHaptics.effect(AHapticFeedbackConstants.TOGGLE_OFF), .primitiveLowTick(0.2))
        XCTAssertEqual(AHaptics.effect(AHapticFeedbackConstants.GESTURE_THRESHOLD_DEACTIVATE), .primitiveTick(0.4))
        XCTAssertNil(AHaptics.effect(AHapticFeedbackConstants.NO_HAPTICS))
        XCTAssertNil(AHaptics.effect(AHapticFeedbackConstants.TEXT_HANDLE_MOVE))
        XCTAssertNil(AHaptics.effect(10_001))
        XCTAssertFalse(AHaptics.perform(AHapticFeedbackConstants.NO_HAPTICS))
    }

    // MARK: - Window geometry (ViewRootImpl / WindowManager)

    func testRootMeasureSpecs() {
        XCTAssertEqual(KitWindowLayout.rootMeasureSpec(1000, AWindowManager.LayoutParams.MATCH_PARENT),
                       AMeasureSpec.makeMeasureSpec(1000, AMeasureSpec.EXACTLY))
        XCTAssertEqual(KitWindowLayout.rootMeasureSpec(1000, AWindowManager.LayoutParams.WRAP_CONTENT),
                       AMeasureSpec.makeMeasureSpec(1000, AMeasureSpec.AT_MOST))
        XCTAssertEqual(KitWindowLayout.rootMeasureSpec(1000, 640), AMeasureSpec.makeMeasureSpec(640, AMeasureSpec.EXACTLY))
    }

    func testMeasureHierarchyTriesThePreferredDialogWidthThenHalfwayThenAll() {
        let base = KitWindowLayout.prefDialogWidthPx()
        let lp = AWindowManager.LayoutParams(AWindowManager.LayoutParams.WRAP_CONTENT, AWindowManager.LayoutParams.WRAP_CONTENT)
        let fits = WantsSizeView()
        fits.wantedWidth = base - 10
        fits.wantedHeight = 100
        KitWindowLayout.measureHierarchy(fits, lp, base * 2, 5000)
        XCTAssertEqual(fits.widthSpecs, [AMeasureSpec.makeMeasureSpec(base, AMeasureSpec.AT_MOST)])
        XCTAssertEqual(fits.measuredWidth, base - 10)

        let wider = WantsSizeView()
        wider.wantedWidth = base + 10
        KitWindowLayout.measureHierarchy(wider, lp, base * 2, 5000)
        XCTAssertEqual(wider.widthSpecs, [AMeasureSpec.makeMeasureSpec(base, AMeasureSpec.AT_MOST),
                                          AMeasureSpec.makeMeasureSpec((base + base * 2) / 2, AMeasureSpec.AT_MOST)])
        XCTAssertEqual(wider.measuredWidth, base + 10)

        let widest = WantsSizeView()
        widest.wantedWidth = base * 3
        KitWindowLayout.measureHierarchy(widest, lp, base * 2, 5000)
        XCTAssertEqual(widest.widthSpecs.count, 3)
        XCTAssertEqual(widest.widthSpecs.last, AMeasureSpec.makeMeasureSpec(base * 2, AMeasureSpec.AT_MOST))

        let exact = WantsSizeView()
        KitWindowLayout.measureHierarchy(exact, AWindowManager.LayoutParams(700, 400), base * 2, 5000)
        XCTAssertEqual(exact.widthSpecs, [AMeasureSpec.makeMeasureSpec(700, AMeasureSpec.EXACTLY)])
    }

    func testGravityApplyCentresAndNoGravityAlsoCentres() {
        let container = ARect(0, 0, 1000, 2000)
        let centred = KitWindowLayout.apply(AGravity.CENTER, 300, 200, container, 0, 0)
        XCTAssertEqual([centred.left, centred.top, centred.right, centred.bottom], [350, 900, 650, 1100])
        let none = KitWindowLayout.apply(AGravity.NO_GRAVITY, 300, 200, container, 0, 0)
        XCTAssertEqual([none.left, none.top], [350, 900])
        let topLeft = KitWindowLayout.apply(AGravity.TOP | AGravity.LEFT, 300, 200, container, 10, 20)
        XCTAssertEqual([topLeft.left, topLeft.top], [10, 20])
        let bottomRight = KitWindowLayout.apply(AGravity.BOTTOM | AGravity.RIGHT, 300, 200, container, 10, 20)
        XCTAssertEqual([bottomRight.right, bottomRight.bottom], [990, 1980])
        let fill = KitWindowLayout.apply(AGravity.FILL_HORIZONTAL | AGravity.CENTER_VERTICAL, 300, 200, container, 0, 0)
        XCTAssertEqual([fill.left, fill.right], [0, 1000])
    }

    func testApplyDisplayKeepsTheWindowOnScreenAndShrinksATallerOne() {
        let display = ARect(0, 100, 1000, 1900)
        let shifted = ARect(100, 50, 400, 250)
        KitWindowLayout.applyDisplay(display, shifted)
        XCTAssertEqual([shifted.top, shifted.bottom], [100, 300])
        let tall = ARect(100, -50, 400, 2050)
        KitWindowLayout.applyDisplay(display, tall)
        XCTAssertEqual([tall.top, tall.bottom], [100, 1900])
        let lp = AWindowManager.LayoutParams(300, 200)
        lp.gravity = AGravity.START | AGravity.TOP
        let rtl = KitWindowLayout.computeFrame(lp, 300, 200, display, true)
        XCTAssertEqual([rtl.left, rtl.right, rtl.top], [700, 1000, 100])
    }

    func testDecorViewMinimumWidthOfFloatingWindows() {
        XCTAssertEqual(KitDecorView.complexFraction(0.95), Float(7_969_177) / Float(1 << 23))
        AConfiguration.current = portraitPhoneConfiguration()
        let window = AWindow(context: nil, isFloating: true)
        window.minWidthMajor = 0.65
        window.minWidthMinor = 0.95
        let content = WantsSizeView()
        content.wantedWidth = 100
        content.wantedHeight = 100
        window.setContentView(content)
        let decor = window.decorView
        decor.measure(AMeasureSpec.makeMeasureSpec(5000, AMeasureSpec.AT_MOST),
                      AMeasureSpec.makeMeasureSpec(5000, AMeasureSpec.AT_MOST))
        let expected = (KitDecorView.complexFraction(0.95) * (Float(393) * AWidgetEnv.density)).toInt()
        XCTAssertEqual(decor.measuredWidth, expected)
        decor.measure(AMeasureSpec.makeMeasureSpec(500, AMeasureSpec.EXACTLY),
                      AMeasureSpec.makeMeasureSpec(5000, AMeasureSpec.AT_MOST))
        XCTAssertEqual(decor.measuredWidth, 500)
    }

    // MARK: - Dialogs

    func testAlertBuilderTextsButtonsAndPanels() {
        let a = resumedActivity()
        let dialog = AAlertDialog.Builder(a)
            .setTitle("Game paused")
            .setMessage("The game and clock are waiting for you.")
            .setPositiveButton("Resume", nil)
            .setNegativeButton(android.R.string.cancel, nil)
            .create()
        XCTAssertNil(dialog.getButton(AAlertDialog.BUTTON_POSITIVE))
        dialog.create()
        XCTAssertEqual(dialog.getButton(AAlertDialog.BUTTON_POSITIVE)?.text, "Resume")
        XCTAssertEqual(dialog.getButton(ADialogInterface.BUTTON_NEGATIVE)?.text, getString(android.R.string.cancel))
        XCTAssertEqual(dialog.getButton(AAlertDialog.BUTTON_NEUTRAL)?.visibility, AView.GONE)
        XCTAssertNil(dialog.listView)
        let message: ATextView? = dialog.findViewById(KitAlertIds.message)
        XCTAssertEqual(message?.text, "The game and clock are waiting for you.")
        let title: ATextView? = dialog.findViewById(KitAlertIds.alertTitle)
        XCTAssertEqual(title?.text, "Game paused")
        let custom: AView? = dialog.findViewById(KitAlertIds.customPanel)
        XCTAssertEqual(custom?.visibility, AView.GONE)
        XCTAssertEqual(dialog.window.attributes.dimAmount, 0.6)
        XCTAssertTrue(dialog.isCancelable)
        XCTAssertTrue(dialog.window.shouldCloseOnTouchOutside())
    }

    func testButtonClickPostsTheListenerThenTheDismiss() {
        let a = resumedActivity()
        var log: [String] = []
        let dialog = AAppCompatAlertDialog.Builder(a)
            .setMessage("m")
            .setPositiveButton("OK") { _, which in log.append("click \(which)") }
            .setOnDismissListener { _ in log.append("dismiss") }
            .create()
        dialog.show()
        XCTAssertTrue(dialog.isShowing)
        dialog.getButton(AAlertDialog.BUTTON_POSITIVE).performClick()
        XCTAssertTrue(log.isEmpty)
        AndroidKitTestLoop.runDueMessages()
        XCTAssertEqual(log, ["click -1", "dismiss"])
        XCTAssertFalse(dialog.isShowing)
    }

    func testShowCancelAndDismissListenersArePostedInAndroidOrder() {
        let a = resumedActivity()
        var log: [String] = []
        let dialog = ADialog(a)
        dialog.requestWindowFeature(AWindow.FEATURE_NO_TITLE)
        dialog.setContentView(AFrameLayout())
        dialog.setOnShowListener { _ in log.append("show") }
        dialog.setOnCancelListener { _ in log.append("cancel") }
        dialog.setOnDismissListener { _ in log.append("dismiss") }
        dialog.show()
        XCTAssertTrue(dialog.isShowing)
        XCTAssertTrue(a.showingDialogs.contains { $0 === dialog })
        XCTAssertTrue(dialog.dimsBehind)
        AndroidKitTestLoop.runDueMessages()
        dialog.cancel()
        dialog.cancel()
        XCTAssertFalse(dialog.isShowing)
        XCTAssertFalse(a.showingDialogs.contains { $0 === dialog })
        AndroidKitTestLoop.runDueMessages()
        XCTAssertEqual(log, ["show", "cancel", "dismiss"])
    }

    func testBackPressCancelsTheTopDialogOnlyWhenCancelable() {
        let a = resumedActivity()
        let dialog = ADialog(a)
        dialog.setContentView(AFrameLayout())
        dialog.setCancelable(false)
        dialog.show()
        a.onBackPressed()
        XCTAssertTrue(dialog.isShowing)
        dialog.setCancelable(true)
        a.onBackPressed()
        XCTAssertFalse(dialog.isShowing)
    }

    func testOutsideTouchUpBeyondTheSlopCancels() {
        let a = resumedActivity()
        let dialog = ADialog(a)
        dialog.setContentView(AFrameLayout())
        dialog.setCanceledOnTouchOutside(true)
        dialog.show()
        let slop = Float(AViewConfiguration.get().scaledWindowTouchSlop)
        let down = AMotionEvent.obtain(0, 0, AMotionEvent.ACTION_DOWN, -slop - 2, -slop - 2, 0)
        XCTAssertFalse(dialog.onTouchEvent(down))
        let nearUp = AMotionEvent.obtain(0, 10, AMotionEvent.ACTION_UP, -slop, -slop, 0)
        XCTAssertFalse(dialog.onTouchEvent(nearUp))
        XCTAssertTrue(dialog.isShowing)
        let farUp = AMotionEvent.obtain(0, 10, AMotionEvent.ACTION_UP, -slop - 2, -slop - 2, 0)
        XCTAssertTrue(dialog.onTouchEvent(farUp))
        XCTAssertFalse(dialog.isShowing)
    }

    func testMultiChoiceListTogglesBeforeTheListenerAndSetItemChecked() {
        let a = resumedActivity()
        var log: [String] = []
        let dialog = AMaterialAlertDialogBuilder(a)
            .setTitle("Choose topics")
            .setMultiChoiceItems(["Science", "History", "Math"], [false, true, false]) { _, which, isChecked in
                log.append("\(which)=\(isChecked)")
            }
            .setPositiveButton("Apply", nil)
            .create()
        dialog.create()
        let list = dialog.listView!
        XCTAssertEqual(list.count, 3)
        XCTAssertEqual(list.choiceMode, AAlertDialog.RecycleListView.CHOICE_MODE_MULTIPLE)
        XCTAssertFalse(list.isItemChecked(0))
        XCTAssertTrue(list.isItemChecked(1))
        list.performItemClick(0)
        list.performItemClick(1)
        XCTAssertEqual(log, ["0=true", "1=false"])
        list.setItemChecked(2, true)
        XCTAssertTrue(list.isItemChecked(2))
        XCTAssertEqual(log.count, 2)
        XCTAssertTrue(list.itemViews[0].isChecked)
        XCTAssertEqual(dialog.window.attributes.dimAmount, 0.32)
    }

    func testSingleChoiceListKeepsTheDialogOpenAndItemsDismiss() {
        let a = resumedActivity()
        var chosen: [Int] = []
        let single = AAppCompatAlertDialog.Builder(a)
            .setTitle("Choose your shot")
            .setSingleChoiceItems(["Shot with aiming arc", "Jump shot"], 1) { _, index in chosen.append(index) }
            .create()
        single.show()
        let list = single.listView!
        XCTAssertEqual(list.checkedItemPosition, 1)
        list.performItemClick(0)
        XCTAssertEqual(list.checkedItemPosition, 0)
        XCTAssertEqual(chosen, [0])
        XCTAssertTrue(single.isShowing)
        single.dismiss()

        var picked: [Int] = []
        let items = AMaterialAlertDialogBuilder(a)
            .setItems(["General", "Science"]) { _, which in picked.append(which) }
            .create()
        items.show()
        items.listView.performItemClick(1)
        XCTAssertEqual(picked, [1])
        XCTAssertFalse(items.isShowing)
    }

    func testMaterialBuilderInstallsTheInsetSurfaceBackground() {
        let a = resumedActivity()
        let dialog = AMaterialAlertDialogBuilder(a).setMessage("m").create()
        let background = dialog.window.decorView.background as? KitDialogBackgroundDrawable
        XCTAssertNotNil(background)
        XCTAssertEqual(background?.insetTop, aw_dpx(80))
        XCTAssertEqual(background?.insetBottom, aw_dpx(80))
        XCTAssertEqual(background?.insetLeft, aw_dpx(24))
        XCTAssertEqual(background?.cornerRadius, Float(aw_dpx(4)))
        XCTAssertEqual(dialog.window.decorView.paddingTop, aw_dpx(80))
        let content: AView? = dialog.window.decorView.findViewById(AWindow.ID_ANDROID_CONTENT)
        XCTAssertTrue(content === dialog.window.contentParent)
    }

    // MARK: - Intents and Uris

    func testUriPartsOfPlayAndMailLinks() {
        let play = AUri.parse("https://play.google.com/store/apps/details?id=com.appsbybros.minik.swish")
        XCTAssertEqual(play.scheme, "https")
        XCTAssertEqual(play.host, "play.google.com")
        XCTAssertEqual(play.path, "/store/apps/details")
        XCTAssertEqual(play.getQueryParameter("id"), "com.appsbybros.minik.swish")
        XCTAssertEqual(AIntent.playListingPackage(play), "com.appsbybros.minik.swish")
        XCTAssertNil(AIntent.playListingPackage(AUri.parse("https://miniklearn.com/")))
        let mail = AUri.parse("mailto:appsbybros.dev@gmail.com")
        XCTAssertEqual(mail.scheme, "mailto")
        XCTAssertEqual(mail.schemeSpecificPart, "appsbybros.dev@gmail.com")
        XCTAssertTrue(mail.isOpaque)
        XCTAssertEqual(mail.toString(), "mailto:appsbybros.dev@gmail.com")
    }

    func testIntentExtrasDataTypeAndChooser() {
        let send = AIntent(AIntent.ACTION_SEND)
        send.type = "text/plain"
        send.putExtra(AIntent.EXTRA_TEXT, "https://play.google.com/store/apps/details?id=x").putExtra("flag", true)
        XCTAssertEqual(send.getStringExtra(AIntent.EXTRA_TEXT), "https://play.google.com/store/apps/details?id=x")
        XCTAssertTrue(send.getBooleanExtra("flag", false))
        XCTAssertEqual(send.getIntExtra("missing", 7), 7)
        send.setData(AUri.parse("content://x"))
        XCTAssertNil(send.type)
        let chooser = AIntent.createChooser(send, "Share")
        XCTAssertEqual(chooser.action, AIntent.ACTION_CHOOSER)
        XCTAssertEqual(chooser.getStringExtra(AIntent.EXTRA_TITLE), "Share")
        let page = AIntent(nil, PlatformTestActivity.self).putExtra("page", "settings")
        XCTAssertEqual(page.componentClass.map { ObjectIdentifier($0) }, ObjectIdentifier(PlatformTestActivity.self))
        let copy = AIntent(page)
        copy.putExtra("page", "brief")
        XCTAssertEqual(page.getStringExtra("page"), "settings")
    }

    func testBundleTypedGettersReturnTheDefaultForOtherTypes() {
        let b = ABundle()
        b.putString("s", "text")
        b.putInt("i", 3)
        b.putBoolean("b", true)
        XCTAssertEqual(b.getString("s"), "text")
        XCTAssertEqual(b.getInt("s", 9), 9)
        XCTAssertEqual(b.getInt("i"), 3)
        XCTAssertTrue(b.getBoolean("b"))
        XCTAssertEqual(b.keySet(), ["s", "i", "b"])
        XCTAssertEqual(b.size(), 3)
        b.remove("i")
        XCTAssertFalse(b.containsKey("i"))
    }

    // MARK: - Strings in dialog and toast APIs

    /// A String argument is literal text even when it spells a resource name; only the `res:` overloads (Android's
    /// @StringRes int overloads) resolve resources.
    func testStringArgumentsAreLiteralTextAndResOverloadsResolve() {
        let name = R.string.minik_swish_bot_setup_choose_ready
        let text = ATextView()
        text.setText(name)
        XCTAssertEqual(text.text, name)
        text.text = "Room: ABC"
        XCTAssertEqual(text.text, "Room: ABC")
        text.setText(res: name)
        XCTAssertEqual(text.text, getString(name))
        let toast = AToast.makeText(name, AToast.LENGTH_SHORT)
        XCTAssertEqual(toast.text, name)
        XCTAssertEqual(AToast.makeText(res: name, AToast.LENGTH_SHORT).text, getString(name))
        toast.setText(android.R.string.cancel)
        XCTAssertEqual(toast.text, android.R.string.cancel)
        toast.setText(res: android.R.string.cancel)
        XCTAssertEqual(toast.text, getString(android.R.string.cancel))
    }
}
