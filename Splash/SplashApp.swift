import SwiftUI

/// Minik Splash for iOS: a standalone port of the Android game (C:/Projects/MinikSplash).
@main
struct SplashApp: App {
    /// Android `requestedOrientation`: pages portrait, battles by the "Game orientation" setting.
    @UIApplicationDelegateAdaptor(SplashAppDelegate.self) private var appDelegate

    var body: some Scene {
        WindowGroup {
            SplashRootView()
        }
    }
}
