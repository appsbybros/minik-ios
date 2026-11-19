import Foundation

/// Android `PracticeConditions`: the arena, wind and light of a journey challenge or lesson.
enum PracticeConditions: String, CaseIterable {
    case calm = "CALM"
    case breeze = "BREEZE"
    case wind = "WIND"
    case space = "SPACE"
    case evening = "EVENING"
    case breezeEvening = "BREEZE_EVENING"
    case windNight = "WIND_NIGHT"
    case night = "NIGHT"

    var scene: ArenaScene {
        switch self {
        case .space: return .andromeda
        case .calm, .breeze, .wind, .evening, .breezeEvening, .windNight, .night: return .park
        }
    }

    var wind: Wind {
        switch self {
        case .calm, .evening, .night: return .none
        case .breeze, .space, .breezeEvening: return .slow
        case .wind, .windNight: return .fast
        }
    }

    var daylight: Daylight {
        switch self {
        case .evening, .breezeEvening: return .evening
        case .windNight, .night: return .night
        case .calm, .breeze, .wind, .space: return .noon
        }
    }
}

/// Android `core/PracticeCurriculum.kt`: the learning topics, their challenge, balls and practice settings.
enum PracticeCurriculum {
    static let topics = ["controls", "balls", "wind", "light", "gravity", "ground", "paint", "calls", "stop", "rules"]

    static func step(_ topic: String) -> Int {
        let id: String
        switch topic {
        case "controls", "light": id = "tree"
        case "balls": id = "ground"
        case "wind": id = "ring_side"
        case "gravity": id = "jump"
        case "calls": id = "call"
        case "stop": id = "freeze"
        default: id = "tree"
        }
        return SpudJourney.stages.firstIndex { $0.id == id } ?? -1
    }

    static func recommendedBall(_ step: Int, _ topic: String = "") -> BallKind {
        return topic == "paint" ? .paint : .foam
    }

    static func balls(_ step: Int, _ topic: String = "") -> [BallKind] {
        if topic == "paint" { return [.paint] }
        return BallKind.allCases.filter { $0 != .paint || SpudJourney.stage(step).skill != .rebound }
    }

    static func ball(_ step: Int, _ selection: String, _ topic: String = "") -> BallKind {
        let choices = balls(step, topic)
        if let named = choices.first(where: { $0.rawValue == selection }) { return named }
        let recommended = recommendedBall(step, topic)
        if choices.contains(recommended) { return recommended }
        return choices[0]
    }

    static func conditions(_ step: Int) -> PracticeConditions {
        switch SpudJourney.stage(step).id {
        case "ring_breeze", "ground_breeze", "pass_breeze": return .breeze
        case "catch_evening": return .evening
        case "tree_evening": return .breezeEvening
        case "pass_night", "catch_night": return .night
        case "ring_night", "ground_night", "tree_night": return .windNight
        default: return step / SpudJourney.size % 3 == 2 ? .space : .calm
        }
    }

    static func config(_ step: Int, _ mode: ThrowMode, _ ball: BallKind, _ conditions: PracticeConditions, _ participants: Int,
                       _ topic: String = "", _ ground: Bool = false) throws -> GameConfig {
        return try GameConfig(scene: conditions.scene, ball: ball, participants: participants, width: 16.0, depth: 16.0,
                              daylight: conditions.daylight, throwMode: mode, wind: conditions.wind, rules: .spud, actionSeconds: 0,
                              challengeStep: step, allowGroundHit: ground, practiceLesson: topic)
    }
}
