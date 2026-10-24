import SwiftUI

/// Minik Splash for iOS: a standalone port of the Android game (C:/Projects/MinikSplash).
@main
struct SplashApp: App {
    /// Android `requestedOrientation`: pages portrait, battles by the "Game orientation" setting.
    @UIApplicationDelegateAdaptor(SplashAppDelegate.self) private var appDelegate

    init() {
        // Android SplashActivity.onCreate `FamilyButtonAlignment.useFullRaisedFace(true)` (104b1be): Splash centres
        // raised-button lettering on the whole raised face, not below its gloss (FamilyKit.RaisedLettering).
        FamilyKit.Lettering.fullRaisedFace = true
        // App Store captures only (SplashScreenshot): start from a fresh install's settings.
        SplashScreenshot.prepare()
    }

    var body: some Scene {
        WindowGroup {
            SplashRootView()
        }
    }
}
