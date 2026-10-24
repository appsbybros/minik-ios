import Foundation
import UIKit

/// App Store captures only: the "App Store screenshots" workflow launches a Simulator build with
/// `-MinikScreenshotScene spud.<scene>` and, for the court, `-MinikScreenshotOrientation landscape`
/// (see appstore/screenshots.json). Normal launches never pass these arguments, so nothing here
/// changes the game for players.
enum SpudScreenshot {
    /// The fixed seed of every captured match: the same house players and the same first moves.
    static let seed: Int64 = 20_261_024

    static var name: String? {
        guard let value = UserDefaults.standard.string(forKey: "MinikScreenshotScene")?
            .trimmingCharacters(in: .whitespacesAndNewlines), !value.isEmpty else { return nil }
        return value
    }

    static var wantsLandscape: Bool {
        return UserDefaults.standard.string(forKey: "MinikScreenshotOrientation") == "landscape"
    }

    /// The part after `prefix.`, e.g. "park" for "spud.park".
    static func value(after prefix: String) -> String? {
        guard let name, name.hasPrefix(prefix + ".") else { return nil }
        return String(name.dropFirst(prefix.count + 1))
    }

    /// Every capture starts from a fresh install: the Spud settings, saved games and points that an
    /// earlier capture left on the Simulator are removed before the app reads them.
    static func prepare() {
        guard name != nil else { return }
        let defaults = UserDefaults.standard
        for key in defaults.dictionaryRepresentation().keys where key.hasPrefix("amudu.") {
            defaults.removeObject(forKey: key)
        }
    }
}
