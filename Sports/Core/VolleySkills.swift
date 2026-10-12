import Foundation

/// Port of Android core/VolleySkills.kt: volleyball-only ratings (they never change the Squash balance).
struct VolleySkills: Equatable {
    let speed: Int
    let precision: Int
    let power: Int
    let hitting: Int
    let blocking: Int
    let serve: Int

    init(_ speed: Int, _ precision: Int, _ power: Int, _ hitting: Int, _ blocking: Int, _ serve: Int) {
        self.speed = speed
        self.precision = precision
        self.power = power
        self.hitting = hitting
        self.blocking = blocking
        self.serve = serve
    }

    func values() -> [Int] { return [speed, precision, power, hitting, blocking, serve] }

    var contactChance: Double { return 0.65 + Double(hitting) * 0.067 }
    var blockChance: Double { return 0.16 + Double(blocking) * 0.145 }
    var serveChance: Double { return 0.73 + Double(serve) * 0.05 }

    static let all: [String: VolleySkills] = [
        "moshiko": VolleySkills(2, 4, 5, 4, 3, 3), "june": VolleySkills(5, 5, 4, 5, 3, 5),
        "comet": VolleySkills(5, 5, 5, 4, 5, 3), "amber": VolleySkills(4, 4, 2, 3, 2, 4),
        "mia": VolleySkills(5, 5, 4, 5, 4, 5), "gaya": VolleySkills(5, 5, 5, 5, 5, 4),
        "flare": VolleySkills(5, 4, 5, 4, 5, 3), "kyra": VolleySkills(5, 4, 4, 5, 3, 4),
        "minik": VolleySkills(3, 4, 3, 4, 2, 4), "miniko": VolleySkills(5, 3, 4, 3, 4, 3),
        "coach67": VolleySkills(4, 3, 5, 4, 4, 3), "flash": VolleySkills(5, 5, 4, 5, 4, 5),
        "finn": VolleySkills(3, 4, 5, 5, 5, 4), "rowan": VolleySkills(3, 3, 4, 4, 3, 4), "diego": VolleySkills(4, 4, 4, 4, 3, 4),
        "kai": VolleySkills(4, 3, 3, 3, 2, 3), "skye": VolleySkills(4, 4, 2, 3, 3, 3)
    ]

    static func of(_ id: String) -> VolleySkills {
        return all[id] ?? all["minik"]!
    }
}

/// Android `VolleyPalette`: ball styles and team colours.
enum VolleyPalette {
    static let ballIds = ["classic", "berry", "pink", "blue", "cyan", "green", "lime", "slate", "midnight", "rainbow"]
    static let teamIds = ["aqua", "gold", "berry"]

    static func color(_ id: String) -> UInt32 {
        switch id {
        case "berry": return 0xffb73578
        case "pink": return 0xffe91e63
        case "blue": return 0xff2979ff
        case "cyan", "aqua": return 0xff00cce8
        case "green": return 0xff32db72
        case "lime": return 0xffc9f328
        case "slate": return 0xff6489a4
        case "midnight": return 0xff142451
        case "gold", "classic": return 0xffffd741
        default: return 0xff00cce8
        }
    }
}
