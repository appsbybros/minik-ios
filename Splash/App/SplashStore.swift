import Foundation

/// Android SharedPreferences files "minik_splash", "splash_local_battle" and "splash_online",
/// kept as prefixed UserDefaults keys with the same names and JSON values.
enum SplashPrefs {
    private static let defaults = UserDefaults.standard

    private static func key(_ file: String, _ name: String) -> String { return file + "." + name }

    static func string(_ name: String, file: String = "minik_splash") -> String? {
        return defaults.string(forKey: key(file, name))
    }

    static func setString(_ value: String?, _ name: String, file: String = "minik_splash") {
        if let value = value {
            defaults.set(value, forKey: key(file, name))
        } else {
            defaults.removeObject(forKey: key(file, name))
        }
    }

    static func int(_ name: String, _ fallback: Int, file: String = "minik_splash") -> Int {
        return (defaults.object(forKey: key(file, name)) as? Int) ?? fallback
    }

    static func setInt(_ value: Int, _ name: String, file: String = "minik_splash") {
        defaults.set(value, forKey: key(file, name))
    }

    static func bool(_ name: String, _ fallback: Bool, file: String = "minik_splash") -> Bool {
        return (defaults.object(forKey: key(file, name)) as? Bool) ?? fallback
    }

    static func setBool(_ value: Bool, _ name: String, file: String = "minik_splash") {
        defaults.set(value, forKey: key(file, name))
    }

    /// Android `getFloat` / `putFloat` (kept as a 32-bit value, as Android stores it).
    static func float(_ name: String, _ fallback: Float, file: String = "minik_splash") -> Float {
        return (defaults.object(forKey: key(file, name)) as? NSNumber)?.floatValue ?? fallback
    }

    static func setFloat(_ value: Float, _ name: String, file: String = "minik_splash") {
        defaults.set(value, forKey: key(file, name))
    }

    static func contains(_ name: String, file: String = "minik_splash") -> Bool {
        return defaults.object(forKey: key(file, name)) != nil
    }

    /// Android `getStringSet` / `putStringSet` (a HashSet: read back in Java HashSet order).
    static func stringSet(_ name: String, file: String = "minik_splash") -> [String] {
        let stored = defaults.stringArray(forKey: key(file, name)) ?? []
        var unique: [String] = []
        for value in stored where !unique.contains(value) { unique.append(value) }
        return JavaOrder.hashMapOrder(unique)
    }

    static func setStringSet(_ values: [String], _ name: String, file: String = "minik_splash") {
        defaults.set(values, forKey: key(file, name))
    }

    /// Android keeps explicit debug QA rooms ("qaOnline" launches) in their own file.
    static var onlineFile: String { return SplashLaunch.qaOnline ? "splash_online_qa" : "splash_online" }

    static var onlineRoom: String? {
        get { return string("room", file: onlineFile) }
        set { setString(newValue, "room", file: onlineFile) }
    }
}

/// Android BuildConfig flags and the DEBUG-only QA launch extras that change behaviour.
enum SplashLaunch {
    /// Android `BuildConfig.PRO_EDITION`: this is the original Minik Splash, not Splash Pro.
    static let proEdition = false

    /// Android `BuildConfig.DEBUG && intent.getBooleanExtra("qaOnline", false)`: only an explicit
    /// debug launch (`-qaOnline YES`) uses the local Firebase emulators; every other launch uses
    /// the app's registered Firebase project.
    static var qaOnline: Bool {
        #if DEBUG
        return UserDefaults.standard.bool(forKey: "qaOnline")
        #else
        return false
        #endif
    }

    /// Android `intent.getIntExtra("qaDuration", 90)`: the battle length of an explicit debug QA room.
    static var qaDuration: Int {
        #if DEBUG
        return (UserDefaults.standard.object(forKey: "qaDuration") as? Int) ?? 90
        #else
        return 90
        #endif
    }
}

/// Port of Android LocalBattleStore.kt: one saved local battle (and its cup progress).
final class LocalBattleStore {
    struct Saved {
        let engine: SplashEngine
        let cup: Bool
        let round: Int
        let scores: [String: Int]
        let cupLength: Int
    }

    private let file = "splash_local_battle"

    func hasBattle() -> Bool {
        return SplashPrefs.contains("battle", file: file)
    }

    func save(_ e: SplashEngine, cupRound: Int, cupScores: [String: Int], cup: Bool, cupLength: Int = 3) {
        if e.practice { return }
        if e.result != nil {
            clear()
            return
        }
        var data: Node = ["members": e.members.map { WorldCodec.member($0) }, "mode": e.mode.name, "topic": e.topic.name,
                          "seed": NSNumber(value: e.seed), "id": e.matchId]
        data["config"] = WorldCodec.config(e.config)
        data["hebrew"] = e.hebrew
        data["duration"] = e.config.duration
        data["state"] = WorldCodec.checkpoint(e)
        data["cupLength"] = cupLength
        data["cup"] = cup
        data["cupRound"] = cupRound
        data["cupScores"] = cupScores
        guard let text = NodeJSON.string(data) else { return }
        SplashPrefs.setString(text, "battle", file: file)
    }

    func load() -> Saved? {
        guard let n = NodeJSON.node(SplashPrefs.string("battle", file: file)) else { return nil }
        let members = n.list("members").map { item -> Member in
            let m = NodeValue.node(item)
            return WorldCodec.member(m.str("id"), m)
        }
        guard let mode = GameMode(rawValue: n.str("mode")), let topic = Topic(rawValue: n.str("topic")),
              SplashEngine.validRoster(members, mode) else { return nil }
        // Battles saved before arenas grew keep their 12 x 12 court.
        var config = SplashConfig()
        if n["config"] != nil {
            config = WorldCodec.config(n.node("config"))
        } else {
            config.width = 12.0
            config.depth = 12.0
            config.duration = n.num("duration", 180.0)
        }
        let e = SplashEngine(members: members, mode: mode, topic: topic, seed: KotlinNumber.long(n.num("seed")),
                             config: config, hebrew: n.flag("hebrew"), matchId: n.str("id"))
        WorldCodec.restore(e, n.node("state"))
        var scores: [String: Int] = [:]
        for (key, value) in n.node("cupScores") { scores[key] = KotlinNumber.int(NodeValue.number(value) ?? 0) }
        let length = KotlinNumber.int(n.num("cupLength", 3.0))
        return Saved(engine: e, cup: n.flag("cup"), round: KotlinNumber.int(n.num("cupRound")), scores: scores,
                     cupLength: length == 5 ? 5 : 3)
    }

    func clear() {
        SplashPrefs.setString(nil, "battle", file: file)
    }
}
