import UIKit

/// Android `requestedOrientation`: the pages are portrait; a game follows the saved battle orientation (any
/// orientation until the player taps ↻), and the result page keeps the game's orientation.
@MainActor final class AmuduAppDelegate: NSObject, UIApplicationDelegate {
    static var orientations: UIInterfaceOrientationMask = .portrait

    func application(_ application: UIApplication, supportedInterfaceOrientationsFor window: UIWindow?) -> UIInterfaceOrientationMask {
        return AmuduAppDelegate.orientations
    }
}

@MainActor enum ScreenOrientation {
    /// Android `SCREEN_ORIENTATION_PORTRAIT` (every page).
    static let page: UIInterfaceOrientationMask = .portrait

    /// Android `battleOrientation`: "portrait" (SENSOR_PORTRAIT), "landscape" (SENSOR_LANDSCAPE) or none (FULL_SENSOR).
    static func battle(_ saved: String?) -> UIInterfaceOrientationMask {
        let pad = UIDevice.current.userInterfaceIdiom == .pad
        switch saved {
        case "portrait": return pad ? [.portrait, .portraitUpsideDown] : .portrait
        case "landscape": return .landscape
        default: return pad ? .all : .allButUpsideDown
        }
    }

    static func apply(_ mask: UIInterfaceOrientationMask) {
        if AmuduAppDelegate.orientations == mask { return }
        AmuduAppDelegate.orientations = mask
        for case let scene as UIWindowScene in UIApplication.shared.connectedScenes {
            for window in scene.windows {
                window.rootViewController?.setNeedsUpdateOfSupportedInterfaceOrientations()
            }
            scene.requestGeometryUpdate(.iOS(interfaceOrientations: mask)) { _ in }
        }
    }
}
