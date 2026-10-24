import UIKit

// The Triple Shot app process (DESIGN 1 "App/", 4.5): Android's process start, AndroidManifest.xml and launcher.
//
// Android starts the process, then the MAIN/LAUNCHER activity TripleShotDemoActivity (portrait; configChanges
// orientation|screenSize|smallestScreenSize|screenLayout|keyboardHidden, so rotation never recreates it). Here the
// UIKit app delegate registers the manifest, and the window scene's delegate creates the window whose root view
// controller is the AActivityHost (the Android task), which creates and starts the launcher activity; the scene's
// foreground / active / inactive / background transitions drive the activity lifecycle (onRestart/onStart,
// onResume, onPause, onStop). The supported interface orientations are the top activity's requestedOrientation
// (AActivityHost.orientationMask, portrait at launch like the manifest).
//
// Info.plist: the app runs with scenes when the target declares UIApplicationSceneManifest (the scene delegate class
// comes from application(_:configurationForConnecting:options:), so the manifest needs no UISceneConfigurations);
// without the key it falls back to an app-delegate window with the same lifecycle. Firebase (AFirebaseApp) and the
// audio session (AAudio) set themselves up on first use.

/// The application's AndroidManifest.xml: label, activities and their attributes.
enum TripleShotApp {
    /// android:label of the application (the same in every language).
    static let label = "Triple Shot"

    /// android:configChanges of TripleShotDemoActivity and BasketballJourneyActivity.
    static let handledConfigChanges = AActivityInfo.CONFIG_ORIENTATION | AActivityInfo.CONFIG_SCREEN_SIZE
        | AActivityInfo.CONFIG_SMALLEST_SCREEN_SIZE | AActivityInfo.CONFIG_SCREEN_LAYOUT | AActivityInfo.CONFIG_KEYBOARD_HIDDEN

    /// Registers the manifest entries of the app's activities (by class name).
    static func registerManifest() {
        // <activity android:name=".TripleShotDemoActivity" android:screenOrientation="portrait" android:configChanges=...>
        AActivity.manifest["TripleShotDemoActivity"] = AActivityManifestEntry(
            screenOrientation: AActivityInfo.SCREEN_ORIENTATION_PORTRAIT, configChanges: handledConfigChanges,
            label: nil)
        // <activity android:name=".ui.BasketballJourneyActivity" android:configChanges=...> (no screenOrientation)
        AActivity.manifest["BasketballJourneyActivity"] = AActivityManifestEntry(
            screenOrientation: AActivityInfo.SCREEN_ORIENTATION_UNSPECIFIED, configChanges: handledConfigChanges,
            label: nil)
        // <activity android:name=".ui.CloudPracticeActivity" android:screenOrientation="portrait"> (unreachable in
        // release builds; listed for completeness)
        AActivity.manifest["CloudPracticeActivity"] = AActivityManifestEntry(
            screenOrientation: AActivityInfo.SCREEN_ORIENTATION_PORTRAIT, configChanges: 0, label: nil)
    }

    /// The MAIN / LAUNCHER activity.
    static func makeLauncherActivity() -> AActivity {
        TripleShotDemoActivity()
    }

    /// The target declares UIApplicationSceneManifest (scene-based lifecycle).
    static var usesScenes: Bool {
        Bundle.main.object(forInfoDictionaryKey: "UIApplicationSceneManifest") != nil
    }

    /// Creates the activity host in a window and shows it.
    static func start(in window: UIWindow) {
        AActivityHost.install(in: window, launcher: TripleShotApp.makeLauncherActivity)
        window.makeKeyAndVisible()
    }
}

/// The application delegate (Android's process): manifest, scene configuration and supported orientations.
@main
final class TripleShotAppDelegate: UIResponder, UIApplicationDelegate {
    /// The window when the target has no scene manifest.
    var window: UIWindow?

    func application(_ application: UIApplication,
                     didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?) -> Bool {
        TripleShotApp.registerManifest()
        if !TripleShotApp.usesScenes {
            let window = UIWindow(frame: UIScreen.main.bounds)
            self.window = window
            TripleShotApp.start(in: window)
        }
        return true
    }

    func application(_ application: UIApplication, configurationForConnecting connectingSceneSession: UISceneSession,
                     options: UIScene.ConnectionOptions) -> UISceneConfiguration {
        let configuration = UISceneConfiguration(name: "Default Configuration", sessionRole: connectingSceneSession.role)
        configuration.delegateClass = TripleShotSceneDelegate.self
        return configuration
    }

    /// Activity.setRequestedOrientation: the top activity's mask.
    func application(_ application: UIApplication, supportedInterfaceOrientationsFor window: UIWindow?) -> UIInterfaceOrientationMask {
        AActivityHost.orientationMask
    }

    // Lifecycle without scenes (the scene delegate handles it otherwise).

    func applicationWillEnterForeground(_ application: UIApplication) {
        if !TripleShotApp.usesScenes {
            AActivityHost.shared?.sceneWillEnterForeground()
        }
    }

    func applicationDidBecomeActive(_ application: UIApplication) {
        if !TripleShotApp.usesScenes {
            AActivityHost.shared?.sceneDidBecomeActive()
        }
    }

    func applicationWillResignActive(_ application: UIApplication) {
        if !TripleShotApp.usesScenes {
            AActivityHost.shared?.sceneWillResignActive()
        }
    }

    func applicationDidEnterBackground(_ application: UIApplication) {
        if !TripleShotApp.usesScenes {
            AActivityHost.shared?.sceneDidEnterBackground()
        }
    }
}

/// The window scene delegate: the app window (the Android task) and the activity lifecycle of the scene.
final class TripleShotSceneDelegate: UIResponder, UIWindowSceneDelegate {
    var window: UIWindow?

    func scene(_ scene: UIScene, willConnectTo session: UISceneSession, options connectionOptions: UIScene.ConnectionOptions) {
        guard let windowScene = scene as? UIWindowScene else { return }
        let window = UIWindow(windowScene: windowScene)
        self.window = window
        TripleShotApp.start(in: window)
    }

    /// The task goes to the foreground: onRestart + onStart of the top activity.
    func sceneWillEnterForeground(_ scene: UIScene) {
        AActivityHost.shared?.sceneWillEnterForeground()
    }

    /// onResume of the top activity.
    func sceneDidBecomeActive(_ scene: UIScene) {
        AActivityHost.shared?.sceneDidBecomeActive()
    }

    /// onPause of the top activity (also for the app switcher, notification centre or a system alert).
    func sceneWillResignActive(_ scene: UIScene) {
        AActivityHost.shared?.sceneWillResignActive()
    }

    /// onStop of the top activity.
    func sceneDidEnterBackground(_ scene: UIScene) {
        AActivityHost.shared?.sceneDidEnterBackground()
    }
}
