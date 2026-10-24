import Foundation

/// App Store captures only: the "App Store screenshots" workflow launches a Simulator build with
/// `-MinikScreenshotScene multi.<scene>`, `pong.play|guide|rival` or `home` and `-MinikOfflineSmoke YES`
/// (see appstore/screenshots.json and `StoreScreenshotScene`). Normal launches never pass these
/// arguments, so nothing here changes the game for players.
@MainActor enum MPStoreScreenshot {
    /// The fixed seed of every captured match: the same house players and the same first rallies.
    static let seed: Int64 = 20_261_024

    /// The avatar heading on the home page's profile editor (`multi.avatar` scrolls it into view).
    static let avatarAnchor = "store-avatar-choice"

    private static var prepared = false

    /// Every capture starts from a fresh install: the identity, controls, journey, saved matches, rooms and
    /// menu sections an earlier capture left on the Simulator (keys "modern.*") are removed before the
    /// app reads them.
    static func prepare() {
        guard !prepared, StoreScreenshotScene.name != nil else { return }
        prepared = true
        let defaults = UserDefaults.standard
        for key in defaults.dictionaryRepresentation().keys where key.hasPrefix("modern.") {
            defaults.removeObject(forKey: key)
        }
    }
}
