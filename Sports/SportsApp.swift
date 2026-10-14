import SwiftUI

/// Minik Squash and Minik Beach Volleyball for iOS: a standalone port of the Android games
/// (C:/Projects/MinikSports). The Info.plist `SportsGame` key (SQUASH or VOLLEY) picks the game,
/// like the Android manifest's `sports.game` meta-data.
@main
struct SportsApp: App {
    /// Android `requestedOrientation`: Squash pages portrait, matches follow the device.
    @UIApplicationDelegateAdaptor(SportsAppDelegate.self) private var appDelegate

    var body: some Scene {
        WindowGroup {
            SportsRootView()
        }
    }
}
