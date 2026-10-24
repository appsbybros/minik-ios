import SwiftUI

/// Spud (Android Minik Amudu, com.appsbybros.minik.spud): a standalone app with its own shell.
@main
struct AmuduApp: App {
    @UIApplicationDelegateAdaptor(AmuduAppDelegate.self) private var appDelegate
    @StateObject private var model = AppModel()

    init() {
        // App Store captures only (SpudScreenshot): start from a fresh install's settings.
        SpudScreenshot.prepare()
    }

    var body: some Scene {
        WindowGroup {
            RootView(model: model)
        }
    }
}
