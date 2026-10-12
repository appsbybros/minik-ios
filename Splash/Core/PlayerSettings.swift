import Foundation

/// Port of Android core/PlayerSettings.kt.
enum WalkMode: String, KotlinEnum {
    case easy = "EASY"
    case standard = "STANDARD"
}

enum ThrowMode: String, KotlinEnum {
    case easy = "EASY"
    case standard = "STANDARD"
}

enum BalloonMode: String, KotlinEnum {
    case onePlace = "ONE_PLACE"
    case allOver = "ALL_OVER"
}

enum Arena: String, KotlinEnum {
    case beach = "BEACH"
    case park = "PARK"
    case andromeda = "ANDROMEDA"
}

struct PlayerSettings: Equatable {
    var walk: WalkMode = .easy
    var throwing: ThrowMode = .easy
    var arena: Arena = .beach
    var court: Bool = true
    var balloons: BalloonMode = .onePlace
    /// Never empty and never MIXED (Android `require`); codecs fall back to MATH.
    var subjects: Set<Topic> = [.math]
    var difficulty: Difficulty = .easy

    var jumpGravity: Double { return arena == .andromeda ? 4.6 : 9.5 }
    var projectileGravityFactor: Double { return arena == .andromeda ? 0.55 : 1.0 }

    /// Subjects in Topic order, as Android sorts them by ordinal.
    var orderedSubjects: [Topic] {
        return subjects.sorted { $0.ordinal < $1.ordinal }
    }

    /// House players: Standard controls and the harder shared environment settings.
    static func bots(_ humans: [PlayerSettings]) -> PlayerSettings {
        let arena: Arena
        if humans.contains(where: { $0.arena == .andromeda }) {
            arena = .andromeda
        } else {
            arena = humans.first?.arena ?? .beach
        }
        let balloons: BalloonMode = humans.contains(where: { $0.balloons == .allOver }) ? .allOver : .onePlace
        var subjects = Set<Topic>()
        for human in humans { subjects.formUnion(human.subjects) }
        if subjects.isEmpty { subjects = [.math] }
        // Kotlin `minByOrNull { difficulty.ordinal }`: the easiest human choice (the first one on a tie).
        var difficulty = Difficulty.easy
        if var easiest = humans.first?.difficulty {
            for human in humans.dropFirst() where human.difficulty.ordinal < easiest.ordinal { easiest = human.difficulty }
            difficulty = easiest
        }
        return PlayerSettings(walk: .standard, throwing: .standard, arena: arena,
                              court: humans.allSatisfy { $0.court }, balloons: balloons, subjects: subjects, difficulty: difficulty)
    }
}

struct TeamStyle {
    let en: String
    let he: String
    let color: UInt32
    let ink: UInt32
    let emblem: String

    func name(_ hebrew: Bool) -> String { return AppText.t(en, he, hebrew: hebrew) }
}

enum Teams {
    static let all: [TeamStyle] = [
        TeamStyle(en: "Blue Wizards", he: "הקוסמים הכחולים", color: 0xff2878d7, ink: 0xffffffff, emblem: "✦"),
        TeamStyle(en: "Yellow Rabbits", he: "הארנבים הצהובים", color: 0xffffd84c, ink: 0xff293449, emblem: "♧")
    ]

    static func style(_ team: Int) -> TeamStyle {
        return all[team == 1 ? 1 : 0]
    }
}
