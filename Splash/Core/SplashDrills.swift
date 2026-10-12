import Foundation

/// Port of Android core/SplashDrills.kt: the defending and aiming drills of the daily paint journey.
enum Defence: String, KotlinEnum {
    case duck = "DUCK"
    case jump = "JUMP"
    case move = "MOVE"
    case mixed = "MIXED"
}

struct SplashDrillSpec {
    let kind: ChallengeKind
    let defence: Defence?
    let bots: Int
    let paired: Bool
    let opposite: Bool
    let ground: Bool
    let movingTarget: Bool
    let highTarget: Bool
    let base: Int

    init(_ kind: ChallengeKind, _ defence: Defence? = nil, _ bots: Int = 1, paired: Bool = false, opposite: Bool = false,
         ground: Bool = false, movingTarget: Bool = false, highTarget: Bool = false, base: Int = 6) {
        self.kind = kind
        self.defence = defence
        self.bots = bots
        self.paired = paired
        self.opposite = opposite
        self.ground = ground
        self.movingTarget = movingTarget
        self.highTarget = highTarget
        self.base = base
    }

    var defending: Bool { return defence != nil }
    var aiming: Bool { return !defending }

    func goal(_ cycle: Int) -> Int { return base + 2 * min(max(cycle, 0), 8) }

    func brief(_ he: Bool) -> String {
        if aiming {
            if ground {
                return he ? "ענו ואספו בלון. כוונו אל האי הזהוב על הרצפה. רק הנחיתה הראשונה נחשבת; הבלון לא יכול לפגוע קודם ברצפה."
                    : "Answer and collect a balloon. Aim for the golden island on the ground. Only the first landing counts; bouncing into it does not count."
            }
            return he ? "ענו ואספו בלון, ואז כוונו דרך הטבעת הזהובה. הבלון צריך לעבור באמת בתוך הטבעת באוויר. אין הגבלת זמן."
                : "Answer and collect a balloon, then aim through the golden ring. The balloon must actually pass inside it in the air. Take your time."
        }
        let control: String
        switch defence {
        case .duck?:
            control = he ? "געו פעמיים במהירות בזירה כדי להתכופף. ההליכה והקפיצה נחות בסיבוב הזה." : "Double-tap the arena to duck. Walking and jumping rest for this round."
        case .jump?:
            control = he ? "געו בדמות שלכם כדי לקפוץ. ההליכה והכיפוף נחים בסיבוב הזה." : "Tap your character to jump. Walking and ducking rest for this round."
        case .move?:
            control = he ? "געו בצד פנוי או גררו כדי לזוז. הקפיצה והכיפוף נחים בסיבוב הזה." : "Tap an open space or drag to move. Jumping and ducking rest for this round."
        default:
            control = he ? "בחרו: לזוז, לקפוץ בנגיעה בדמות, או להתכופף בנגיעה כפולה בזירה." : "Choose: move, tap your character to jump, or double-tap the arena to duck."
        }
        return control + (he ? " עקבו אחרי הסימן מעל הזורק. כל בלון שלא פוגע בכם מוסיף הצלחה. שלוש פגיעות מאפשרות ניסיון חדש. אין שעון."
            : " Watch the cue above the thrower. Each balloon you avoid adds a success. After three hits, try again. There is no countdown.")
    }
}

enum SplashDrills {
    private static let specs: [SplashDrillSpec] = [
        SplashDrillSpec(.duck, .duck), SplashDrillSpec(.jump, .jump),
        SplashDrillSpec(.sidestep, .move),
        SplashDrillSpec(.duckTwo, .duck, 2, base: 8), SplashDrillSpec(.jumpTwo, .jump, 2, base: 8),
        SplashDrillSpec(.dodgeTwo, .mixed, 2, base: 8),
        SplashDrillSpec(.dodgeOpposite, .mixed, 2, opposite: true, base: 8),
        SplashDrillSpec(.duckThree, .duck, 3, base: 9), SplashDrillSpec(.jumpThree, .jump, 3, base: 9),
        SplashDrillSpec(.dodgeThree, .mixed, 3, base: 9),
        SplashDrillSpec(.dodgeFour, .mixed, 4, opposite: true, base: 10),
        SplashDrillSpec(.duckPair, .duck, 2, paired: true, base: 10),
        SplashDrillSpec(.jumpPair, .jump, 2, paired: true, base: 10),
        SplashDrillSpec(.dodgePairs, .mixed, 4, paired: true, opposite: true, base: 12),
        SplashDrillSpec(.ring), SplashDrillSpec(.ringSides, movingTarget: true, base: 8),
        SplashDrillSpec(.ringHigh, movingTarget: true, highTarget: true, base: 8),
        SplashDrillSpec(.ground, ground: true), SplashDrillSpec(.groundFar, ground: true, movingTarget: true, base: 8),
    ]

    static func find(_ kind: ChallengeKind) -> SplashDrillSpec? { return specs.first { $0.kind == kind } }

    /// Stable IDs are stored by name; order is educational rather than enum declaration order.
    static let journey: [ChallengeKind] = [
        .cover, .target, .passing, .duck, .jump,
        .sidestep, .pattern, .ring, .ground, .letter,
        .duckTwo, .jumpTwo, .passWide, .ringSides, .dodgeTwo,
        .shape, .dodgeOpposite, .groundFar, .duel, .duckThree,
        .jumpThree, .passQuick, .ringHigh, .dodgeThree, .timedTarget,
        .duckPair, .jumpPair, .dodgeFour, .dodgePairs, .race,
    ]

    /// Keep completed-count, points and receipts. The expanded route continues at the same count.
    /// No new drill is awarded for free and a retry can never erase prior points.
    static func migrateCompleted(_ old: Int) -> Int { return max(old, 0) }
}

/// Android `DrillFlight`.
final class DrillFlight {
    let aim: V
    var passed: Bool

    init(_ aim: V, passed: Bool = false) {
        self.aim = aim
        self.passed = passed
    }
}

/// Android `SplashDrillSession`: this observes production projectile segments; rendering and button presses never
/// award hits.
final class SplashDrillSession {
    let spec: SplashDrillSpec
    let config: SplashConfig
    var successes = 0
    var mistakes = 0
    var wave = 0
    var nextCue = 2.5
    var releaseAt = -1.0
    var lastSuccess = -10.0
    var cueHigh = true
    var cueBots: [String] = []
    var incoming: [String: DrillFlight] = [:]
    /// Kotlin `resolved` (a LinkedHashSet): insertion order kept for the saved state.
    private(set) var resolvedOrder: [String] = []
    private var resolvedSet = Set<String>()

    init(_ spec: SplashDrillSpec, _ config: SplashConfig) {
        self.spec = spec
        self.config = config
    }

    var goal: Int { return spec.goal(config.chapter) }
    var won: Bool { return successes >= goal }
    var failed: Bool { return mistakes >= 3 }
    var radius: Double { return (spec.ground ? 1.5 : 1.15) - min(Double(config.chapter) * 0.035, 0.3) }

    var target: V {
        let slot = (successes + mistakes) % 3
        let x = spec.movingTarget ? [0.28, 0.72, 0.5][slot] : 0.5
        let y = (spec.ground && spec.movingTarget) ? [0.3, 0.5, 0.38][slot] : 0.3
        return V(config.width * x, config.depth * y)
    }

    var height: Double {
        if spec.ground { return 0.1 }
        if spec.highTarget { return 2.5 + Double(successes % 2) * 0.5 }
        return 1.7
    }

    func restoreResolved(_ ids: [String]) {
        resolvedOrder = []
        resolvedSet = []
        for id in ids where !resolvedSet.contains(id) {
            resolvedOrder.append(id)
            resolvedSet.insert(id)
        }
    }

    func allows(_ cmd: Command) -> Bool {
        if !spec.defending { return true }
        switch cmd {
        case .move, .walkTo:
            return spec.defence == .move || spec.defence == .mixed
        case .jump:
            return spec.defence == .jump || spec.defence == .mixed
        case .crouch:
            return spec.defence == .duck || spec.defence == .mixed
        default:
            return false
        }
    }

    func prepare(_ e: SplashEngine) {
        guard let human = e.actors.first(where: { !$0.member.bot }) else { return }
        human.position = V(config.width * 0.5, config.depth * 0.65)
        let bots = e.actors.filter { $0.member.bot }
        for (i, a) in bots.enumerated() {
            let angle = spec.opposite ? 2 * Double.pi * Double(i) / Double(bots.count)
                : -Double.pi / 2 + (Double(i) - Double(bots.count - 1) * 0.5) * 0.65
            a.position = spec.aiming ? V(config.width * 0.1, config.depth * 0.3) : human.position + V(cos(angle), sin(angle)) * 7.0
            a.move = V(0, 0)
            a.held = nil
        }
    }

    func step(_ e: SplashEngine) {
        if !spec.defending || won || failed { return }
        if releaseAt < 0 && incoming.isEmpty && e.shots.isEmpty && e.time >= nextCue {
            let bots = e.actors.filter { $0.member.bot }
            if bots.isEmpty { return }
            let first = wave % bots.count
            cueBots = spec.paired ? [bots[first].member.id, bots[(first + 1) % bots.count].member.id] : [bots[first].member.id]
            switch spec.defence {
            case .duck?: cueHigh = true
            case .jump?: cueHigh = false
            default: cueHigh = wave % 2 == 0
            }
            releaseAt = e.time + 0.9
            for id in cueBots { e.actor(id)?.windupAt = e.time }
        }
        if releaseAt >= 0 && e.time >= releaseAt {
            guard let human = e.actors.first(where: { !$0.member.bot }) else { return }
            for id in cueBots {
                guard let bot = e.actor(id) else { continue }
                let point = human.position
                let delta = point - bot.position
                let direction = delta.unit()
                let origin = bot.position + direction * 0.5
                let precision = Characters.get(bot.member.character).qualities.precision
                // Same arrival time and same safe action for a paired wave: never a duck/jump contradiction.
                let duration = max(1.65 - Double(config.chapter) * 0.025 - Double(precision) * 0.04, 1.25)
                let atHeight = cueHigh ? 1.48 : 0.22
                let releaseHeight = cueHigh ? 1.15 : 0.35
                let velocity = (point - origin) * (1.0 / duration)
                let lift = (atHeight - releaseHeight + 0.5 * config.gravity * duration * duration) / duration
                let shotId = "\(e.matchId)-drill-\(wave)-\(id)"
                e.shots.append(Shot(id: shotId, owner: id, questionId: "drill", answer: "", explanation: "", color: 4, position: origin,
                                    height: releaseHeight, velocity: velocity, vz: lift))
                incoming[shotId] = DrillFlight(point)
                bot.throwAt = e.time
                bot.facing = direction
                e.onEvent?("throw", id)
            }
            wave += 1
            releaseAt = -1.0
            nextCue = e.time + 3.0
        }
    }

    func flight(_ e: SplashEngine, _ s: Shot, _ old: V, _ oldHeight: Double) {
        if spec.defending {
            if let f = incoming[s.id] {
                let d = s.velocity.unit()
                let gone = s.position - f.aim
                // Mark passage now; award only on flight end. Any later hit overrides this.
                if gone.x * d.x + gone.y * d.y >= 0.0 { f.passed = true }
            }
            return
        }
        if e.actor(s.owner)?.member.bot != false || resolvedSet.contains(s.id) { return }
        let t: Double
        if spec.ground {
            if oldHeight <= 0.1 || s.height > 0.1 { return }
            t = (0.1 - oldHeight) / (s.height - oldHeight)
        } else {
            let dy = s.position.y - old.y
            if abs(dy) < 1e-8 { return }
            t = (target.y - old.y) / dy
        }
        if t < 0.0 || t > 1.0 { return }
        let point = old + (s.position - old) * t
        let z = oldHeight + (s.height - oldHeight) * t
        let distance = spec.ground ? (point - target).length() : hypot(point.x - target.x, z - height)
        resolve(e, s.id, distance <= radius)
    }

    func hit(_ e: SplashEngine, _ s: Shot, _ a: SplashActor) {
        if spec.defending && !a.member.bot && incoming[s.id] != nil {
            incoming.removeValue(forKey: s.id)
            resolve(e, s.id, false)
        }
    }

    func ended(_ e: SplashEngine, _ s: Shot) {
        if spec.defending {
            guard let f = incoming.removeValue(forKey: s.id) else { return }
            resolve(e, s.id, f.passed)
        } else if e.actor(s.owner)?.member.bot == false {
            resolve(e, s.id, false)
        }
    }

    private func resolve(_ e: SplashEngine, _ id: String, _ success: Bool) {
        if resolvedSet.contains(id) { return }
        resolvedSet.insert(id)
        resolvedOrder.append(id)
        if success {
            successes += 1
            lastSuccess = e.time
            if let human = e.actors.first(where: { !$0.member.bot }) { e.onEvent?("pickup", human.member.id) }
        } else {
            mistakes += 1
        }
    }

    func advice(_ he: Bool) -> String {
        let action: String
        if spec.aiming {
            action = he ? "אספו תשובה נכונה וכוונו למטרה" : "Collect the correct answer and aim at the target"
        } else {
            switch spec.defence {
            case .duck?: action = he ? "נגיעה כפולה להתכופפות" : "Double-tap to duck"
            case .jump?: action = he ? "נגיעה בדמות לקפיצה" : "Tap your character to jump"
            case .move?: action = he ? "געו בצד פנוי כדי לזוז" : "Tap an open space to move"
            default: action = he ? "זוזו, קפצו או התכופפו לפי הזריקה" : "Move, jump or duck to avoid the throw"
            }
        }
        return he ? "\(successes)/\(goal) הצלחות · \(3 - mistakes) לבבות · \(action)" : "\(successes)/\(goal) successes · \(3 - mistakes) hearts · \(action)"
    }
}
