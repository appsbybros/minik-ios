import Foundation

/// App Store captures only: the "App Store screenshots" workflow launches a Simulator build with
/// `-MinikScreenshotScene splash.<scene>` (or `home`) and, for the arena,
/// `-MinikScreenshotOrientation landscape` (see appstore/screenshots.json). Normal launches never
/// pass these arguments, so nothing here changes the game for players.
enum SplashScreenshot {
    /// The fixed seed of every captured battle: the same questions, balloons and first moves.
    static let seed: Int64 = 20_261_024

    static var name: String? {
        guard let value = UserDefaults.standard.string(forKey: "MinikScreenshotScene")?
            .trimmingCharacters(in: .whitespacesAndNewlines), !value.isEmpty else { return nil }
        return value
    }

    static var wantsLandscape: Bool {
        return UserDefaults.standard.string(forKey: "MinikScreenshotOrientation") == "landscape"
    }

    /// The part after `prefix.`, e.g. "beach" for "splash.beach".
    static func value(after prefix: String) -> String? {
        guard let name, name.hasPrefix(prefix + ".") else { return nil }
        return String(name.dropFirst(prefix.count + 1))
    }

    /// Every capture starts from a fresh install: the settings, saved battle and cup, online room,
    /// camera choices, menu sections and points that an earlier capture left on the Simulator are
    /// removed before the app reads them (SplashPrefs files "minik_splash", "splash_*").
    static func prepare() {
        guard name != nil else { return }
        let defaults = UserDefaults.standard
        for key in defaults.dictionaryRepresentation().keys
            where key.hasPrefix("minik_splash.") || key.hasPrefix("splash_") || key.hasPrefix("family_menu_sections.") {
            defaults.removeObject(forKey: key)
        }
    }
}
