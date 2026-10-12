import UIKit

/// Android `requestedOrientation`: every page is portrait; a battle follows the "Game orientation"
/// setting, and its ↻ button switches between portrait and landscape.
@MainActor final class SplashAppDelegate: NSObject, UIApplicationDelegate {
    static var orientations: UIInterfaceOrientationMask = .portrait

    func application(_ application: UIApplication, supportedInterfaceOrientationsFor window: UIWindow?) -> UIInterfaceOrientationMask {
        return SplashAppDelegate.orientations
    }
}

@MainActor enum SplashOrientation {
    /// Android `SCREEN_ORIENTATION_PORTRAIT` (every page).
    static let page: UIInterfaceOrientationMask = .portrait

    /// Android `gameOrientation`: 0 automatic rotation (FULL_SENSOR), 1 portrait, 2 landscape (SENSOR_LANDSCAPE).
    static func game(_ saved: Int) -> UIInterfaceOrientationMask {
        switch saved {
        case 1: return .portrait
        case 2: return .landscape
        default: return UIDevice.current.userInterfaceIdiom == .pad ? .all : .allButUpsideDown
        }
    }

    /// Android `onRotate`: landscape turns to portrait, anything else to landscape (SENSOR_LANDSCAPE).
    static func rotated(landscape: Bool) -> UIInterfaceOrientationMask {
        return landscape ? .portrait : .landscape
    }

    static func apply(_ mask: UIInterfaceOrientationMask) {
        if SplashAppDelegate.orientations == mask { return }
        SplashAppDelegate.orientations = mask
        for case let scene as UIWindowScene in UIApplication.shared.connectedScenes {
            for window in scene.windows {
                window.rootViewController?.setNeedsUpdateOfSupportedInterfaceOrientations()
            }
            scene.requestGeometryUpdate(.iOS(interfaceOrientations: mask)) { _ in }
        }
    }
}
