import Foundation

/// Android SharedPreferences ("sports", "family_menu_sections"), kept as prefixed UserDefaults keys
/// with the same names and JSON values.
enum SportsPrefs {
    private static let defaults = UserDefaults.standard

    /// Android `getSharedPreferences(if (qa) "sports_qa" else "sports")`.
    static var file: String { return SportsLaunch.qa ? "sports_qa" : "sports" }

    private static func key(_ file: String, _ name: String) -> String { return file + "." + name }

    static func string(_ name: String, file: String = SportsPrefs.file) -> String? {
        return defaults.string(forKey: key(file, name))
    }

    static func setString(_ value: String?, _ name: String, file: String = SportsPrefs.file) {
        if let value = value {
            defaults.set(value, forKey: key(file, name))
        } else {
            defaults.removeObject(forKey: key(file, name))
        }
    }

    static func int(_ name: String, _ fallback: Int, file: String = SportsPrefs.file) -> Int {
        return (defaults.object(forKey: key(file, name)) as? Int) ?? fallback
    }

    static func setInt(_ value: Int, _ name: String, file: String = SportsPrefs.file) {
        defaults.set(value, forKey: key(file, name))
    }

    static func bool(_ name: String, _ fallback: Bool, file: String = SportsPrefs.file) -> Bool {
        return (defaults.object(forKey: key(file, name)) as? Bool) ?? fallback
    }

    static func setBool(_ value: Bool, _ name: String, file: String = SportsPrefs.file) {
        defaults.set(value, forKey: key(file, name))
    }

    static func contains(_ name: String, file: String = SportsPrefs.file) -> Bool {
        return defaults.object(forKey: key(file, name)) != nil
    }

    static func remove(_ name: String, file: String = SportsPrefs.file) {
        defaults.removeObject(forKey: key(file, name))
    }

    /// Android `getStringSet` / `putStringSet`.
    static func stringSet(_ name: String, file: String = SportsPrefs.file) -> [String] {
        let stored = defaults.stringArray(forKey: key(file, name)) ?? []
        var unique: [String] = []
        for value in stored where !unique.contains(value) { unique.append(value) }
        return unique
    }

    static func setStringSet(_ values: [String], _ name: String, file: String = SportsPrefs.file) {
        defaults.set(values, forKey: key(file, name))
    }
}

/// The game of this app (Android manifest `sports.game`, here the Info.plist `SportsGame` key) and
/// the DEBUG-only QA launch extras that change behaviour.
enum SportsLaunch {
    static var sport: Sport {
        let value = Bundle.main.object(forInfoDictionaryKey: "SportsGame") as? String ?? "SQUASH"
        return Sport(rawValue: value) ?? .squash
    }

    /// Android `FLAG_DEBUGGABLE && intent.getBooleanExtra("qa", false)`.
    static var qa: Bool {
        #if DEBUG
        return UserDefaults.standard.bool(forKey: "qa")
        #else
        return false
        #endif
    }

    /// Android `debug && intent.getBooleanExtra("qaOnline", false)`: only an explicit debug launch
    /// (`-qaOnline YES`) uses the local Firebase emulators; every other launch uses the app's
    /// registered Firebase project.
    static var qaOnline: Bool {
        #if DEBUG
        return UserDefaults.standard.bool(forKey: "qaOnline")
        #else
        return false
        #endif
    }

    /// Android `intent.getIntExtra("qaTarget", 5)` for an explicit debug QA launch.
    static var qaTarget: Int {
        #if DEBUG
        return min(max((UserDefaults.standard.object(forKey: "qaTarget") as? Int) ?? 5, 3), 31)
        #else
        return 5
        #endif
    }
}
