import Foundation

/// Port of Android core/Characters.kt. `Character` is `SportsCharacter` on iOS (Swift has its own
/// `Character`).
enum Topic: String, KotlinEnum {
    case math = "MATH"
    case english = "ENGLISH"
    case world = "WORLD"
    case mixed = "MIXED"
}

/// Android `HouseSkills`: 1-5 star ratings that change real play.
struct HouseSkills: Equatable {
    let speed: Int
    let precision: Int
    let reflexes: Int
    let power: Int
    let knowledge: Int

    init(_ speed: Int, _ precision: Int, _ reflexes: Int, _ power: Int, _ knowledge: Int = 3) {
        self.speed = speed
        self.precision = precision
        self.reflexes = reflexes
        self.power = power
        self.knowledge = knowledge
    }

    private static func star(_ value: Int) -> Int { return min(max(value, 1), 5) - 1 }

    var correctAnswerProbability: Double { return Double(knowledge) / 7.0 }
    var movementFactor: Double { return 0.5 + Double(speed - 1) * 0.125 }
    var throwFactor: Double { return 0.64 + Double(power - 1) * 0.09 }
    var aimErrorDegrees: Double { return [26.0, 19.0, 12.0, 6.0, 2.0][HouseSkills.star(precision)] }
    var prediction: Double { return 0.25 + Double(precision - 1) * 0.15 }
    var dodgeChance: Double { return [0.10, 0.20, 0.32, 0.46, 0.62][HouseSkills.star(reflexes)] }
    var reactionSeconds: Double { return [0.38, 0.31, 0.24, 0.18, 0.13][HouseSkills.star(reflexes)] }
}

struct SportsCharacter: Equatable {
    let id: String
    let en: String
    let he: String
    let skill: Double
    let qualities: HouseSkills

    func name(_ hebrew: Bool) -> String { return hebrew ? he : en }
}

enum Characters {
    static let all: [SportsCharacter] = [
        SportsCharacter(id: "miniko", en: "Miniko", he: "מיניקו", skill: 0.70, qualities: HouseSkills(3, 3, 3, 3, 3)),
        SportsCharacter(id: "minik", en: "Minik", he: "מיניק", skill: 0.64, qualities: HouseSkills(3, 2, 3, 2, 5)),
        SportsCharacter(id: "kyra", en: "Kyra", he: "ספיר", skill: 0.94, qualities: HouseSkills(5, 4, 5, 4, 5)),
        SportsCharacter(id: "flare", en: "Flare", he: "ברק", skill: 0.9, qualities: HouseSkills(5, 4, 5, 5, 4)),
        SportsCharacter(id: "gaya", en: "Gaya", he: "גאיה", skill: 0.83, qualities: HouseSkills(4, 5, 5, 5, 4)),
        SportsCharacter(id: "mia", en: "Mia", he: "מיה", skill: 0.77, qualities: HouseSkills(5, 5, 5, 4, 5)),
        SportsCharacter(id: "amber", en: "Amber", he: "ענבר", skill: 0.82, qualities: HouseSkills(4, 5, 3, 3, 3)),
        SportsCharacter(id: "comet", en: "Comet", he: "שביט", skill: 0.86, qualities: HouseSkills(5, 4, 5, 4, 4)),
        SportsCharacter(id: "june", en: "June", he: "סהר", skill: 0.80, qualities: HouseSkills(5, 4, 5, 3, 3)),
        SportsCharacter(id: "moshiko", en: "Bouncy Bob", he: "מושיקו", skill: 0.66, qualities: HouseSkills(1, 4, 3, 5, 3)),
        SportsCharacter(id: "coach67", en: "Coach", he: "המאמן", skill: 0.88, qualities: HouseSkills(3, 3, 3, 4, 3))
    ]

    static let volleyOnly: [SportsCharacter] = [
        SportsCharacter(id: "flash", en: "Flash", he: "פלאש", skill: 0.94, qualities: HouseSkills(5, 5, 5, 4, 4)),
        SportsCharacter(id: "finn", en: "Finn", he: "פין", skill: 0.86, qualities: HouseSkills(3, 4, 5, 5, 3)),
        SportsCharacter(id: "rowan", en: "Rowan", he: "רוני", skill: 0.80, qualities: HouseSkills(3, 3, 4, 4, 3)),
        SportsCharacter(id: "diego", en: "Diego", he: "דייגו", skill: 0.84, qualities: HouseSkills(4, 4, 4, 4, 3)),
        SportsCharacter(id: "kai", en: "Kai", he: "קאי", skill: 0.73, qualities: HouseSkills(4, 3, 3, 3, 3)),
        SportsCharacter(id: "skye", en: "Skye", he: "סקיי", skill: 0.75, qualities: HouseSkills(4, 4, 3, 2, 3))
    ]

    static func forSport(_ sport: Sport) -> [SportsCharacter] { return sport == .volley ? all + volleyOnly : all }

    static func get(_ id: String) -> SportsCharacter {
        return (all + volleyOnly).first { $0.id == id } ?? all[0]
    }
}
