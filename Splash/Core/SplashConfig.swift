import Foundation

/// Port of Android core/SplashConfig.kt: physics, gestures, penalties, bot timing, network
/// cadence and RenderConfig framing. Values are identical to Android.
struct SplashConfig: Equatable {
    /// New arenas are 20 x 20 (Android 2026-10-05); restored rooms and saves keep their own size.
    var width: Double = 20.0
    var depth: Double = 20.0
    var moveSpeed: Double = 3.8
    var throwSpeed: Double = 7.8
    var gravity: Double = 2.6
    var launchLift: Double = 1.2
    var personalSpace: Double = 1.12
    var actorRadius: Double = 0.38
    var standingHeight: Double = 1.7
    var crouchHeight: Double = 1.02
    var jumpVelocity: Double = 4.2
    var jumpGravity: Double = 9.5
    var crouchSeconds: Double = 0.85
    var pickupRadius: Double = 1.05
    var answerRing: Double = 3.6
    var cleanSeconds: Double = 1.5
    var returnShield: Double = 0.8
    var paintLayers: Int = 3
    var mistakeRecovery: Double = 0.65
    var mistakePoints: Int = 1
    var target: Int = 10
    var teamTarget: Int = 20
    var duration: Double = 180.0
    var friendlyFire: Bool = false
    var doubleTapMs: Int64 = 220
    var gestureSlopDp: Double = 11.0
    var bodyTouchDp: Double = 34.0
    var arcTouchDp: Double = 24.0
    var doubleTapDistanceDp: Double = 38.0
    var movementDragDp: Double = 32.0
    var render: RenderConfig = RenderConfig()
    var snapshotHz: Int = 12
    var inputHz: Int = 20
    /// House players' pace (Android 2026-10): speed, thinking time and the room they leave.
    var difficulty: Difficulty = .standard
    /// "Paint walls · teams": each team paints the other team's wall.
    var wallBattle: Bool = false
    var hitEffect: HitEffect = .cosmetic
    /// The daily paint journey's challenge (nil in regular battles), its cycle and journey step.
    var challenge: ChallengeKind? = nil
    var chapter: Int = 0
    var challengeStep: Int = 0
    var botThinkMin: Double = 1.9
    var botThinkMax: Double = 3.8
    var particleLimit: Int = 220

    /// Android's `init { require(...) }` checks, kept as a query instead of a crash.
    var isValid: Bool {
        var ok = width >= 8.0 && depth >= 8.0 && moveSpeed > 0.0 && throwSpeed > 0.0 && gravity > 0.0
        ok = ok && personalSpace >= actorRadius * 2.0 && personalSpace < 2.0
        ok = ok && standingHeight > crouchHeight && crouchHeight > 0.0
        ok = ok && jumpVelocity > 0.0 && jumpGravity > 0.0
        ok = ok && pickupRadius >= 0.4 && pickupRadius <= 2.0 && answerRing > pickupRadius
        ok = ok && cleanSeconds >= 0.1 && cleanSeconds <= 4.0
        ok = ok && returnShield >= 0.0 && returnShield <= 2.0
        ok = ok && paintLayers >= 1 && paintLayers <= 6
        ok = ok && mistakePoints >= 0 && mistakeRecovery >= 0.0 && mistakeRecovery <= 2.0
        ok = ok && target > 0 && teamTarget > 0 && duration > 0.0
        ok = ok && doubleTapMs >= 150 && doubleTapMs <= 350
        ok = ok && snapshotHz >= 5 && snapshotHz <= 30 && inputHz >= 5 && inputHz <= 30
        ok = ok && doubleTapDistanceDp >= 20.0 && doubleTapDistanceDp <= 70.0 && movementDragDp >= 16.0 && movementDragDp <= 80.0
        ok = ok && bodyTouchDp > 0 && arcTouchDp > 0 && gestureSlopDp > 0
        ok = ok && botThinkMin > 0.0 && botThinkMax >= botThinkMin
        ok = ok && particleLimit >= 30 && particleLimit <= 600
        return ok
    }
}

/// Android `Difficulty(speed, think, space)`: house players' speed, thinking time and the room they keep.
enum Difficulty: String, KotlinEnum {
    case easy = "EASY"
    case standard = "STANDARD"
    case pro = "PRO"

    var speed: Double {
        switch self {
        case .easy: return 0.62
        case .standard: return 0.85
        case .pro: return 1.0
        }
    }

    var think: Double {
        switch self {
        case .easy: return 2.0
        case .standard: return 1.35
        case .pro: return 1.0
        }
    }

    var space: Double {
        switch self {
        case .easy: return 3.2
        case .standard: return 2.4
        case .pro: return 1.8
        }
    }
}

/// Android `HitEffect`: what a hit does in a wall battle.
enum HitEffect: String, KotlinEnum {
    case cosmetic = "COSMETIC"
    case rest = "REST"
    case slow = "SLOW"
}

enum GameMode: String, KotlinEnum {
    case solo = "SOLO"
    case teams = "TEAMS"
}

enum Topic: String, KotlinEnum {
    case math = "MATH"
    case english = "ENGLISH"
    case world = "WORLD"
    case mixed = "MIXED"
}

/// Android `HouseSkills`: the 1-5 star ratings shown on the house-player cards. Every value
/// changes actual play (speed, aim error and prediction, dodging, release speed, answers).
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

    /// Android `require(all in 1..5)`, kept as a query; the table lookups below clamp instead.
    var isValid: Bool {
        return [speed, precision, reflexes, power, knowledge].allSatisfy { $0 >= 1 && $0 <= 5 }
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

struct SplashCharacter: Equatable {
    let id: String
    let en: String
    let he: String
    let skill: Double
    let qualities: HouseSkills

    func name(_ hebrew: Bool) -> String { return hebrew ? he : en }
}

enum Characters {
    static let all: [SplashCharacter] = [
        SplashCharacter(id: "miniko", en: "Miniko", he: "מיניקו", skill: 0.70, qualities: HouseSkills(3, 3, 3, 3, 3)),
        SplashCharacter(id: "minik", en: "Minik", he: "מיניק", skill: 0.64, qualities: HouseSkills(3, 2, 3, 2, 5)),
        SplashCharacter(id: "kyra", en: "Kyra", he: "ספיר", skill: 0.94, qualities: HouseSkills(5, 4, 5, 4, 5)),
        SplashCharacter(id: "flare", en: "Flare", he: "Flare", skill: 0.9, qualities: HouseSkills(5, 4, 5, 5, 4)),
        SplashCharacter(id: "gaya", en: "Gaya", he: "גאיה", skill: 0.83, qualities: HouseSkills(4, 5, 5, 5, 4)),
        SplashCharacter(id: "mia", en: "Mia", he: "מיה", skill: 0.77, qualities: HouseSkills(5, 5, 5, 4, 5)),
        SplashCharacter(id: "amber", en: "Amber", he: "ענבר", skill: 0.82, qualities: HouseSkills(4, 5, 3, 3, 3)),
        SplashCharacter(id: "comet", en: "Comet", he: "שביט", skill: 0.86, qualities: HouseSkills(5, 4, 5, 4, 4)),
        SplashCharacter(id: "june", en: "June", he: "סהר", skill: 0.80, qualities: HouseSkills(5, 4, 5, 3, 3)),
        SplashCharacter(id: "moshiko", en: "Bouncy Bob", he: "מושיקו", skill: 0.66, qualities: HouseSkills(1, 4, 3, 5, 3)),
        SplashCharacter(id: "coach67", en: "Coach", he: "המאמן", skill: 0.88, qualities: HouseSkills(3, 3, 3, 4, 3))
    ]

    static func get(_ id: String) -> SplashCharacter {
        return all.first { $0.id == id } ?? all[0]
    }
}

struct V: Equatable {
    var x: Double
    var y: Double

    init(_ x: Double, _ y: Double) {
        self.x = x
        self.y = y
    }

    static let zero = V(0, 0)

    static func + (a: V, b: V) -> V { return V(a.x + b.x, a.y + b.y) }
    static func - (a: V, b: V) -> V { return V(a.x - b.x, a.y - b.y) }
    static func * (a: V, n: Double) -> V { return V(a.x * n, a.y * n) }

    func length() -> Double { return hypot(x, y) }

    func unit() -> V {
        let d = length()
        return d < 0.0001 ? V(0, -1) : self * (1 / d)
    }
}

enum Facing {
    case front, back, left, right

    static func of(_ direction: V) -> Facing {
        if abs(direction.x) > abs(direction.y) * 0.85 { return direction.x < 0 ? .left : .right }
        return direction.y < 0 ? .back : .front
    }
}

/// Projection and visual balancing (Android RenderConfig).
struct RenderConfig: Equatable {
    var horizontalPadding: Double = 2.0
    var floorTop: Double = 0.32
    var floorDepth: Double = 0.552
    var heightScale: Double = 0.067
    var backPerspective: Double = 0.82
    var depthPerspective: Double = 0.018
    var characterWidth: Double = 0.235
    var numberBalloonWidth: Double = 0.125
    var wordBalloonWidth: Double = 0.16
    var longWordBalloonWidth: Double = 0.18
}
