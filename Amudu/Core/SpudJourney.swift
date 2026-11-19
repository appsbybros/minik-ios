import Foundation

/// Android `core/SpudJourney.kt` `DrillSkill` (same order; `catching` is Kotlin `CATCH`).
enum DrillSkill: CaseIterable {
    case catching, duck, jump, move, dodge, ring, ground, tree, rebound, pass, call, freeze, tag
}

/// Android `SpudStage`: one challenge of the daily skill journey.
struct SpudStage {
    let id: String
    let en: String
    let he: String
    let skill: DrillSkill
    let bots: Int
    let paired: Bool
    let opposite: Bool
    let moving: Bool
    let high: Bool
    let base: Int

    init(_ id: String, _ en: String, _ he: String, _ skill: DrillSkill, _ bots: Int = 1, paired: Bool = false, opposite: Bool = false,
         moving: Bool = false, high: Bool = false, base: Int = 6) {
        self.id = id
        self.en = en
        self.he = he
        self.skill = skill
        self.bots = bots
        self.paired = paired
        self.opposite = opposite
        self.moving = moving
        self.high = high
        self.base = base
    }

    var cooperative: Bool { return skill == .catching || skill == .pass || skill == .call }
    var defence: Bool { return skill == .duck || skill == .jump || skill == .move || skill == .dodge }
    var throwing: Bool {
        return skill == .ring || skill == .ground || skill == .tree || skill == .rebound || skill == .pass || skill == .call ||
            skill == .tag
    }

    /// Kotlin `copy(id = ...)`: the same challenge under another identity (an inserted condition variant).
    func copy(id newId: String) -> SpudStage {
        return SpudStage(newId, en, he, skill, bots, paired: paired, opposite: opposite, moving: moving, high: high, base: base)
    }

    func goal(_ cycle: Int) -> Int { return base + 2 * min(max(cycle, 0), 8) }

    func aptitude(_ c: AmuduCharacter) -> Int {
        let q = c.qualities
        switch skill {
        case .catching, .pass, .call:
            return q.accuracy * 5 + q.catching * 2 + q.speed
        case .duck, .jump, .dodge, .move:
            return q.accuracy * 5 + q.power * 2 + q.speed * 2
        default:
            return q.accuracy * 5 + q.catching * 2
        }
    }

    /// The partner or opponent for this cycle: partners and guides start with the most able character, opponents
    /// with the least able one.
    func bot(_ cycle: Int, _ excluded: Set<String>) -> AmuduCharacter {
        let ranked = AmuduCharacters.all.filter { !excluded.contains($0.id) }.sorted { a, b in
            let x = aptitude(a)
            let y = aptitude(b)
            if x != y { return x < y }
            return Kotlin.less(a.id, b.id)
        }
        let ordered = (cooperative || !defence) ? Array(ranked.reversed()) : ranked
        return ordered[min(max(cycle, 0), ordered.count - 1)]
    }

    func brief(_ he: Bool) -> String {
        switch skill {
        case .catching:
            return he ? "געו בתפיסה כשהכדור מתקרב. יש חצי שנייה לתפוס לפני הנגיעה בקרקע."
                : "Tap Catch as the ball arrives. Your catch window lasts half a second; catch before the ground."
        case .tag:
            return he ? "פגעו בשחקן המסומן. בדקו אם מותרת נגיעה בקרקע לפני הפגיעה."
                : "Hit the marked player. Check whether a ground bounce is allowed before the hit."
        case .duck:
            return he ? "געו פעמיים בזירה כדי להתכופף מתחת לכדור. בסיבוב הזה לא הולכים ולא קופצים. עקבו אחרי הסימן מעל הזורק."
                : "Double-tap the arena to duck under the ball. Walking and jumping rest this round. Watch the cue above the thrower."
        case .jump:
            return he ? "געו בקפיצה כשהכדור הנמוך מתקרב. בסיבוב הזה לא הולכים ולא מתכופפים. עקבו אחרי הזורק ותזמנו את הקפיצה."
                : "Tap Jump as the low ball approaches. Walking and ducking rest this round. Watch the thrower and time your jump."
        case .move:
            return he ? "גררו כדי לזוז מנתיב הכדור. בסיבוב הזה לא קופצים ולא מתכופפים." : "Drag to leave the ball's path. Jumping and ducking rest this round."
        case .dodge:
            return he ? "בחרו איך להתחמק: גררו לתנועה, געו בקפיצה או געו פעמיים לכיפוף. צמד כדורים תמיד מאפשר אותה התחמקות לשניהם."
                : "Choose how to escape: drag to move, tap Jump or double-tap to duck. Paired balls always allow the same escape for both."
        case .ground:
            return he ? "געו באי הזהוב לכיוון, ואז החליקו מהכדור כדי לזרוק. רק הנגיעה הראשונה בקרקע נספרת. התאמנו בעוצמות שונות."
                : "Tap the golden island to aim, then swipe from your ball to throw. Only the first ground contact counts. Explore different throwing strengths."
        case .ring:
            return he ? "כוונו לטבעת והחליקו מהכדור כדי לזרוק. הזריקה צריכה לעבור בתוך הטבעת באוויר. החלקה מהירה יותר מעלה ומאיצה את הכדור."
                : "Aim at the ring and swipe from your ball to throw. The ball must pass inside the ring in the air. A faster swipe throws higher and faster."
        case .tree:
            return he ? "כוונו לסימון שעל גזע העץ והחליקו מהכדור. פגעו בעץ לפני שהכדור נוגע בקרקע."
                : "Aim at the mark on the tree trunk and swipe from your ball. Hit the tree before the ball touches the ground."
        case .rebound:
            return he ? "זרקו אל גזע העץ ותפסו את הכדור החוזר לפני הנחיתה. גררו להתמקמות וגעו בתפיסה כשהכדור מגיע."
                : "Throw at the tree trunk, then catch the rebound before it lands. Drag into position and tap Catch as the ball arrives."
        case .pass:
            return he ? "מסרו לשותף המסומן, ואז תפסו את המסירה החוזרת. כשהסימון עובר, כוונו לשותף החדש. זוזו לכיוון מסירות שנוטות לצד."
                : "Pass to the marked partner, then catch the return. When the marker moves, aim at the new partner. Move toward passes that drift sideways."
        case .call:
            return he ? "געו בשותף המסומן כדי לקרוא לו, ואז החליקו כלפי מעלה מהכדור להרמה. השותף צריך להגיע לתפיסה לפני הנחיתה."
                : "Tap the marked partner to call them, then swipe upward from your ball for a lob. Your partner must reach the catch before it lands."
        case .freeze:
            return he ? "גררו כדי לרוץ בזמן שמופיע 'רוצו'. כשמופיע SPUD, שחררו ועצרו עד הסימן הבא. חייבים לרוץ לפני כל עצירה."
                : "Drag to run while RUN is shown. When SPUD appears, release and stay still until the next cue. Run before each stop."
        }
    }

    func role(_ he: Bool) -> String {
        if cooperative {
            return he ? "זהו שותף. מתחילים עם מוסר מדויק במיוחד. בכל מסלול חדש המסירות דורשות מעט יותר תנועה, אך נשארות בהישג יד."
                : "This is your partner. Start with a very accurate passer. Each new cycle asks for a little more movement, while passes stay within reach."
        }
        if defence {
            return he ? "זהו יריב. מתחילים מול זורק קל יותר. בכל מסלול חדש הדיוק, העוצמה והמהירות הרלוונטיים לאתגר עולים בהדרגה."
                : "This is your opponent. Start against an easier thrower. Each new cycle gradually increases the accuracy, power and speed that matter for this skill."
        }
        return he ? "הדמות היא מדריכה. מתאמנים ללא שעון, לומדים מההחטאה ומנסים שוב. שלוש החטאות מאפשרות ניסיון חדש בלי לאבד התקדמות."
            : "This character is your guide. Practice without a countdown, learn from a miss and try again. After three misses, restart without losing progress."
    }
}

/// Android `SpudJourney`: the 30 base challenges plus 10 inserted condition variants (40 per cycle), repeated in cycles.
enum SpudJourney {
    static let baseStages: [SpudStage] = [
        SpudStage("catch", "Your first catch", "התפיסה הראשונה", .catching),
        SpudStage("duck", "Duck under", "מתכופפים מתחת", .duck),
        SpudStage("jump", "Jump over", "קופצים מעל", .jump),
        SpudStage("move", "Step aside", "זזים הצדה", .move),
        SpudStage("tree", "Meet the practice tree", "פוגשים את עץ האימון", .tree),
        SpudStage("ring", "Through the ring", "דרך הטבעת", .ring),
        SpudStage("ground", "Land on the island", "נוחתים על האי", .ground),
        SpudStage("catch_move", "Move and catch", "זזים ותופסים", .catching, moving: true),
        SpudStage("pass", "Pass and return", "מוסרים ומחזירים", .pass),
        SpudStage("rebound", "Tree rebound", "תפיסה מהעץ", .rebound),
        SpudStage("duck_two", "Two throwers: duck", "שני זורקים: מתכופפים", .duck, 2, base: 8),
        SpudStage("jump_two", "Two throwers: jump", "שני זורקים: קופצים", .jump, 2, base: 8),
        SpudStage("dodge_two", "Choose your escape", "בוחרים איך להתחמק", .dodge, 2, base: 8),
        SpudStage("ring_side", "Follow the ring", "עוקבים אחרי הטבעת", .ring, moving: true, base: 8),
        SpudStage("ground_far", "Near and far", "קרוב ורחוק", .ground, moving: true, base: 8),
        SpudStage("pass_choice", "Find your teammate", "מוצאים את השותף", .pass, 3, base: 8),
        SpudStage("duck_three", "Duck in rhythm", "מתכופפים בקצב", .duck, 3, base: 9),
        SpudStage("jump_three", "Jump in rhythm", "קופצים בקצב", .jump, 3, base: 9),
        SpudStage("opposite", "Both directions", "משני הכיוונים", .dodge, 2, opposite: true, base: 8),
        SpudStage("rebound_fast", "Ready for the rebound", "מוכנים לכדור החוזר", .rebound, high: true, base: 8),
        SpudStage("ring_high", "Aim higher", "מכוונים גבוה", .ring, high: true, base: 8),
        SpudStage("catch_fast", "Quick hands", "ידיים זריזות", .catching, high: true, base: 8),
        SpudStage("duck_pair", "Two balls: duck", "שני כדורים: כיפוף", .duck, 2, paired: true, base: 10),
        SpudStage("jump_pair", "Two balls: jump", "שני כדורים: קפיצה", .jump, 2, paired: true, base: 10),
        SpudStage("dodge_three", "Three-way lookout", "שלושה כיוונים", .dodge, 3, base: 9),
        SpudStage("dodge_four", "All around you", "מכל הכיוונים", .dodge, 4, opposite: true, base: 10),
        SpudStage("dodge_pairs", "Pairs in rhythm", "צמדים בקצב", .dodge, 4, paired: true, opposite: true, base: 12),
        SpudStage("pass_wide", "Pass and move", "מוסרים וזזים", .pass, 2, moving: true, base: 8),
        SpudStage("call", "Call and lob", "קוראים ומרימים", .call, 2),
        SpudStage("freeze", "Run, call, freeze", "רצים, קוראים, עוצרים", .freeze),
    ]

    /// Original identities retain their completion status when new conditions are inserted: after base stage `key`, a
    /// copy of base stage `value.0` under the id `value.1`.
    private static let inserted: [Int: (Int, String)] = [9: (5, "ring_breeze"), 14: (7, "catch_evening"), 16: (4, "tree_evening"),
                                                         18: (6, "ground_breeze"), 20: (8, "pass_night"), 22: (13, "ring_night"),
                                                         24: (21, "catch_night"), 26: (14, "ground_night"), 28: (4, "tree_night"),
                                                         29: (8, "pass_breeze")]

    static let stages: [SpudStage] = {
        var list: [SpudStage] = []
        for (i, s) in baseStages.enumerated() {
            list.append(s)
            if let entry = inserted[i] { list.append(baseStages[entry.0].copy(id: entry.1)) }
        }
        return list
    }()

    static var size: Int { return stages.count }

    static func stage(_ step: Int) -> SpudStage { return stages[Kotlin.floorMod(step, size)] }

    /// Kotlin `key(step)`: "cycle:id", the mastery identity of a challenge.
    static func key(_ step: Int) -> String { return "\(step / size):\(stage(step).id)" }

    /// Kotlin `legacyStep(step)`: a step of the old 30-challenge journey in the 40-challenge journey.
    static func legacyStep(_ step: Int) -> Int {
        if step < 0 { return step }
        let id = baseStages[step % 30].id
        return (step / 30) * size + (stages.firstIndex { $0.id == id } ?? -1)
    }

    static func firstUnfinished(_ mastered: Set<String>, _ start: Int = 0) -> Int {
        var n = start
        while mastered.contains(key(n)) { n += 1 }
        return n
    }
}

/// Android `SpudProgress`: the completed challenges and the journey points. Kotlin keeps the receipts in a
/// LinkedHashSet; the array keeps the same insertion order (the latest 128).
struct SpudProgress: Equatable {
    var completed = 0
    var points = 0
    var bonusDay = ""
    var receipts: [String] = []
    /// Kotlin `mastered`: the `SpudJourney.key` of every completed challenge (a set; order is not meaningful).
    var mastered: Set<String> = []

    /// Kotlin `done(step)`.
    func done(_ step: Int) -> Bool {
        return step < completed || mastered.contains(SpudJourney.key(step))
    }

    /// A first win of the current challenge earns 40 points, 10 more for every completed cycle (up to 100), and 30 more
    /// for the first win of the day. A replayed match (same receipt) earns nothing.
    func finish(_ id: String, _ step: Int, _ won: Bool, _ day: String) -> SpudProgress {
        if !won || step != completed || receipts.contains(id) { return self }
        let daily = Kotlin.less(bonusDay, day)
        var earned = mastered
        earned.insert(SpudJourney.key(step))
        var next = self
        next.completed = SpudJourney.firstUnfinished(earned, completed + 1)
        next.points = points + 40 + min(completed / SpudJourney.size, 10) * 10 + (daily ? 30 : 0)
        next.bonusDay = daily ? day : bonusDay
        next.receipts = Array((receipts + [id]).suffix(128))
        next.mastered = earned
        return next
    }

    /// Kotlin `SpudProgress.migrate`: a saved 30-challenge progress keeps its mastery and points but gains no new
    /// challenges.
    static func migrate(completed: Int, points: Int, bonusDay: String, receipts: [String]) -> SpudProgress {
        var earned: Set<String> = []
        for i in 0..<max(completed, 0) { earned.insert(SpudJourney.key(SpudJourney.legacyStep(i))) }
        return SpudProgress(completed: SpudJourney.firstUnfinished(earned), points: points, bonusDay: bonusDay, receipts: receipts,
                            mastered: earned)
    }
}

/// Android `BallFlight`: shared ballistic integration for regular matches and training.
enum BallFlight {
    static func advance(_ b: inout Ball, _ dt: Double, _ gravity: Double, _ wind: V) {
        b.position = b.position + (b.velocity * dt + wind * (0.5 * dt * dt))
        b.velocity = b.velocity + wind * dt
        b.height += b.vz * dt - 0.5 * gravity * dt * dt
        b.vz -= gravity * dt
    }

    static func segmentTime(_ before: V, _ after: V, _ point: V) -> Double {
        let d = after - before
        if d.length() < 1e-9 { return 0.0 }
        let p = point - before
        return Kotlin.clamp((p.x * d.x + p.y * d.y) / (d.x * d.x + d.y * d.y), 0.0, 1.0)
    }
}

/// Android `PracticeBall`. Kotlin's `Ball` is a shared object; here the shot owns its ball and the engine's `ball`
/// is refreshed from the first shot after every practice tick (as Kotlin does).
final class PracticeBall {
    var ball: Ball
    let owner: String
    let incoming: Bool
    let aim: V
    var rebounded: Bool
    var passed: Bool
    var evaluated: Bool
    var partnerMiss: Bool

    init(_ ball: Ball, _ owner: String, _ incoming: Bool, _ aim: V, rebounded: Bool = false, passed: Bool = false,
         evaluated: Bool = false, partnerMiss: Bool = false) {
        self.ball = ball
        self.owner = owner
        self.incoming = incoming
        self.aim = aim
        self.rebounded = rebounded
        self.passed = passed
        self.evaluated = evaluated
        self.partnerMiss = partnerMiss
    }
}

/// Android `SpudPractice`: a local practice session observes real projectile contacts, never touch counts.
/// Kotlin's `Ball` is a shared object: the engine ball and the first shot's ball are the same instance. Here every write
/// the Kotlin code makes through `e.ball` to a shot's ball is copied back into that shot.
final class SpudPractice {
    let step: Int
    let seed: Int64
    /// Kotlin `lesson`: the learning-curriculum topic ("" for a journey challenge).
    let lesson: String
    let stage: SpudStage
    let cycle: Int
    let goal: Int
    var successes = 0
    var mistakes = 0
    var wave = 0
    var nextAt = 2.3
    var releaseAt = -1.0
    var cueHigh = true
    var cue: [String] = []
    var selected = ""
    var target = V(8.0, 5.0)
    var targetHeight = 1.4
    private var random: KotlinRandom
    var freezeAt = 0.0
    var moved = 0.0
    var freezeReady = false
    var shots: [PracticeBall] = []
    var lastSuccess = -10.0

    init(_ step: Int, _ seed: Int64 = 1, _ lesson: String = "") {
        self.step = step
        self.seed = seed
        self.lesson = lesson
        if lesson == "ground" || lesson == "paint" {
            stage = SpudStage("lesson_tag", "Hit the target", "פוגעים במטרה", .tag, base: 3)
        } else {
            stage = SpudJourney.stage(!lesson.isEmpty ? PracticeCurriculum.step(lesson) : step)
        }
        cycle = lesson.isEmpty ? max(step / SpudJourney.size, 0) : 0
        goal = lesson.isEmpty ? stage.goal(cycle) : 3
        random = KotlinRandom(seed: seed)
    }

    var won: Bool { return successes >= goal }
    var failed: Bool { return mistakes >= 3 }
    var radius: Double { return stage.skill == .ground ? 1.5 : 1.05 - min(Double(cycle) * 0.025, 0.25) }
    var allowsMove: Bool { return stage.skill != .duck && stage.skill != .jump }
    var allowsJump: Bool { return stage.skill == .jump || stage.skill == .dodge }
    var allowsDuck: Bool { return stage.skill == .duck || stage.skill == .dodge }

    func human(_ e: AmuduEngine) -> GameActor {
        return e.actors.first { !$0.member.bot } ?? e.actors[0]
    }

    func partner(_ e: AmuduEngine) -> GameActor {
        let bots = e.actors.filter { $0.member.bot }
        let index = (successes + mistakes) % stage.bots
        return index < bots.count ? bots[index] : (bots.first ?? human(e))
    }

    func prepare(_ e: AmuduEngine) {
        let h = human(e)
        h.position = V(8.0, 12.0)
        e.circleFormation = false
        e.actionDeadline = 0.0
        e.frozen = false
        let bots = e.actors.filter { $0.member.bot }
        for (i, a) in bots.enumerated() {
            let angle = stage.opposite ? 2 * Double.pi * Double(i) / Double(bots.count)
                : -Double.pi / 2 + (Double(i) - Double(bots.count - 1) * 0.5) * 0.6
            if stage.defence {
                a.position = h.position + V(cos(angle), sin(angle)) * 6.0
            } else if stage.cooperative || stage.skill == .tag {
                a.position = V(4.0 + 8.0 * Double(i + 1) / Double(bots.count + 1), 5.0)
            } else {
                a.position = V(3.0, 5.0)
            }
            a.direction = (h.position - a.position).unit()
            a.facing = a.direction
        }
        ready(e)
    }

    private func ready(_ e: AmuduEngine) {
        trialColour(e)
        let h = human(e)
        let n = successes + mistakes
        switch stage.skill {
        case .pass, .call, .tag:
            target = partner(e).position
        default:
            let x = stage.moving ? [5.0, 11.0, 8.0][n % 3] : 8.0
            let y = (stage.skill == .ground && stage.moving) ? [5.0, 8.0, 6.0][n % 3] : 5.0
            target = V(x, y)
        }
        if stage.skill == .ground {
            targetHeight = 0.23
        } else if stage.high && stage.skill == .ring {
            targetHeight = 2.3
        } else {
            targetHeight = 1.4
        }
        e.thrower = stage.throwing ? h.member.id : partner(e).member.id
        e.called = h.member.id
        e.selected = ""
        selected = ""
        if stage.skill == .call {
            e.phase = .circle
        } else if stage.throwing {
            e.phase = .aim
        } else {
            e.phase = .flight
        }
        let holder = stage.throwing ? h : partner(e)
        e.ball = Ball(holder.position, 1.2, V.zero, 0.0, holder.member.id)
        h.direction = (target - h.position).unit()
        h.facing = h.direction
    }

    func command(_ e: AmuduEngine, _ a: GameActor, _ c: GameCommand) -> Bool {
        if a.member.bot { return false }
        switch c {
        case .move(let v):
            if !v.finite() || !allowsMove { return false }
            a.move = v.length() > 1 ? v.unit() : v
        case .jump:
            if !allowsJump || a.jumpHeight > 0 || e.time < a.duckUntil { return false }
            a.jumpVelocity = CatchPhysics.jumpVelocity(a)
        case .duck:
            if !allowsDuck || a.jumpHeight > 0 { return false }
            a.duckUntil = e.time + e.config.duckSeconds
            a.catchUntil = 0.0
            e.emit("duck", a.member.id)
        case .catchBall:
            if stage.defence || stage.skill == .freeze || e.time < a.catchRecoveryUntil { return false }
            a.catchProbability = CatchPhysics.probability(a, e.ball, e.actor(e.thrower))
            a.catchRoll = random.nextDouble()
            a.catchReadyAt = e.time + (a.move.length() > 0.08 ? 0.1 : 0.0)
            a.catchUntil = e.time + CatchPhysics.window(a, e.config)
            a.catchRecoveryUntil = a.catchUntil + 0.12
            a.catchReach = a.move.length() > 0.08 ? 0.82 : 1.0
            a.move = V.zero
            e.emit("catch_attempt", a.member.id)
        case .aim(let v):
            if !v.finite() || v.length() < 0.01 || e.ball.holder != a.member.id { return false }
            a.direction = v.unit()
            a.facing = a.direction
        case .select(let targetId, _):
            guard stage.skill == .call, let chosen = e.actor(targetId), chosen.member.bot else { return false }
            selected = targetId
            e.selected = selected
            e.called = selected
            a.facing = (chosen.position - a.position).unit()
            e.emit("call", a.member.id, chosen.fullName())
        case .toss(let power, let drift):
            if stage.skill != .call || Kotlin.isBlank(selected) || e.ball.holder != a.member.id || !power.isFinite { return false }
            guard let partnerActor = e.actor(selected) else { return false }
            let vz = CallLob.velocity(e.config.scene, false, power)
            let t = 2 * vz / e.config.scene.gravity
            launch(e, a, partnerActor.position + V(Kotlin.clamp(drift, -1.0, 1.0) * 2.0, 0.0), 1.2, t, false)
            e.ball.burstOnGround = e.config.ball == .paint && e.callBursts.released(CallLob.high(e.config.scene, vz))
            syncLastShot(e)
            e.phase = .flight
        case .pointThrow(let point, let height):
            if !stage.throwing || stage.skill == .call || e.ball.holder != a.member.id || e.config.throwMode == .standard ||
                !TargetThrow.valid(point, height, e.config) { return false }
            e.serial += 1
            let b = TargetThrow.launch(a, point, height, e.config, e.windVector, "\(e.id)-drill-\(e.serial)", e.time)
            a.direction = b.velocity.unit()
            a.facing = a.direction
            shots.append(PracticeBall(b, a.member.id, false, target))
            e.ball = b
            armPaint(e, b.velocity.length() / e.throwProfile(a, 1.0).speed)
            syncLastShot(e)
            e.phase = .flight
            a.throwAt = e.time
            e.emit("throw", a.member.id)
        case .throwBall(let power, _):
            if !stage.throwing || stage.skill == .call || e.ball.holder != a.member.id || !power.isFinite { return false }
            let profile = e.throwProfile(a, power)
            let speed = profile.speed
            let launchPosition = a.position + a.direction * 0.52
            let travel = max((target - launchPosition).length(), 0.8) / speed
            let vz: Double
            if e.config.throwMode == .easy {
                let t = stage.skill == .ground ? travel * (0.7 + 0.6 * power) : travel
                vz = (targetHeight - 1.17 + 0.5 * e.config.scene.gravity * t * t) / t
            } else {
                vz = profile.vz
            }
            e.serial += 1
            let b = Ball(launchPosition, 1.17, a.direction * speed, vz, nil, bounces: 0, flightId: "\(e.id)-drill-\(e.serial)",
                         launchAt: e.time)
            shots.append(PracticeBall(b, a.member.id, false, target))
            e.ball = b
            armPaint(e, power)
            syncLastShot(e)
            e.phase = .flight
            a.throwAt = e.time
            e.emit("throw", a.member.id)
        case .end:
            complete(e, false)
        default:
            return false
        }
        return true
    }

    /// Kotlin aliasing: the last shot's ball is `e.ball`; copy what was written through `e.ball` back into the shot.
    private func syncLastShot(_ e: AmuduEngine) {
        if let last = shots.last { last.ball = e.ball }
    }

    private func launch(_ e: AmuduEngine, _ a: GameActor, _ to: V, _ z: Double, _ t: Double, _ incoming: Bool) {
        e.serial += 1
        let b = Ball(a.position, 1.2, (to - a.position) * (1 / t) - e.windVector * (0.5 * t),
                     (z - 1.2 + 0.5 * e.config.scene.gravity * t * t) / t, nil, bounces: 0, flightId: "\(e.id)-drill-\(e.serial)",
                     launchAt: e.time)
        shots.append(PracticeBall(b, a.member.id, incoming, to))
        a.throwAt = e.time
        a.facing = (to - a.position).unit()
        e.emit("throw", a.member.id)
        e.ball = b
    }

    private func incoming(_ e: AmuduEngine) {
        trialColour(e)
        let h = human(e)
        for id in cue {
            guard let a = e.actor(id) else { continue }
            let q = AmuduCharacters.get(a.member.character).qualities
            let baseTime: Double
            if stage.defence {
                baseTime = max(6.0 / (5.0 + Double(q.power) * 0.28 + Double(min(cycle, 8)) * 0.12), 0.68)
            } else if stage.high {
                baseTime = 0.85
            } else {
                baseTime = 1.35
            }
            let t = Kotlin.clamp(baseTime * BallKind.foam.speed / e.config.ball.speed, stage.moving ? 1.05 : 0.62, 1.8)
            let offset: Double
            if stage.cooperative && (stage.moving || cycle > 0) {
                offset = min(1.4, 0.18 * Double(5 - q.accuracy) + Double(cycle) * 0.07 + (stage.moving ? 0.45 : 0.0))
            } else {
                offset = 0.0
            }
            let to: V
            if stage.skill == .catching && stage.moving {
                to = V(Kotlin.clamp(h.position.x + (h.position.x < 8 ? 2.5 : -2.5), 1.0, 15.0), h.position.y)
            } else {
                to = V(Kotlin.clamp(h.position.x + (wave % 2 == 0 ? offset : -offset), 1.0, 15.0), h.position.y)
            }
            launch(e, a, to, stage.defence ? (cueHigh ? 2.25 : 0.38) : 1.2, t, true)
            armPaint(e, e.ball.velocity.length() / e.throwProfile(a, 1.0).speed)
            syncLastShot(e)
            e.landing = to
        }
        if let first = cue.first { e.thrower = first }
        e.phase = .flight
        releaseAt = -1.0
        wave += 1
    }

    func tick(_ e: AmuduEngine, _ dt: Double) {
        let h = human(e)
        if h.jumpVelocity != 0.0 || h.jumpHeight > 0 {
            h.jumpHeight = max(h.jumpHeight + h.jumpVelocity * dt - 0.5 * e.config.scene.gravity * dt * dt, 0.0)
            h.jumpVelocity -= e.config.scene.gravity * dt
            if h.jumpHeight == 0.0 { h.jumpVelocity = 0.0 }
        }
        let old = h.position
        if allowsMove {
            let p = h.position + h.move * (e.config.moveSpeed * dt)
            h.position = V(Kotlin.clamp(p.x, 0.7, 15.3), Kotlin.clamp(p.y, 0.7, 15.3))
        }
        h.actuallyMoving = (h.position - old).length() > 0.00001
        if h.actuallyMoving {
            h.gait += dt * 9
            h.facing = h.move.unit()
        }
        if stage.skill == .freeze {
            if !freezeReady {
                moved += (h.position - old).length()
                if moved >= 1.5 && freezeAt == 0.0 { freezeAt = e.time + 1.2 }
                if freezeAt > 0 && e.time >= freezeAt {
                    freezeReady = true
                    freezeAt = e.time
                    e.emit("freeze", partner(e).member.id)
                }
            } else if e.time - freezeAt > 0.35 && h.actuallyMoving {
                credit(e, false)
                freezeReady = false
                moved = 0.0
                freezeAt = 0.0
            } else if e.time - freezeAt >= 1.6 {
                credit(e, true)
                freezeReady = false
                moved = 0.0
                freezeAt = 0.0
            }
            return
        }
        if shots.isEmpty && !stage.throwing && e.time >= nextAt && releaseAt < 0 {
            let bots = e.actors.filter { $0.member.bot }
            if !bots.isEmpty {
                let n = wave % bots.count
                cue = stage.paired ? [bots[n].member.id, bots[(n + 1) % bots.count].member.id] : [bots[n].member.id]
                cueHigh = stage.skill != .jump && (stage.skill != .dodge || wave % 2 == 0)
                releaseAt = e.time + 0.9
            }
        }
        if releaseAt >= 0 && e.time >= releaseAt { incoming(e) }
        // Kotlin iterates `shots.toList()`; a Swift array is already a copy, so removing a shot is safe.
        for s in shots {
            let before = s.ball.position
            let z = s.ball.height
            BallFlight.advance(&s.ball, dt, e.config.scene.gravity, e.windVector)
            let groundT = (s.ball.height <= 0.23 && z > 0.23) ? Kotlin.clamp((z - 0.23) / (z - s.ball.height), 0.0, 1.0) : 1.0
            if s.incoming || s.rebounded {
                let t = BallFlight.segmentTime(before, s.ball.position, h.position)
                let point = before + (s.ball.position - before) * t
                let height = z + (s.ball.height - z) * t
                let near = (point - h.position).length()
                let catching = !stage.defence && e.time >= h.catchReadyAt && e.time < h.catchUntil &&
                    near < e.config.ball.catchRadius * h.catchReach && height >= 0.35 && height <= 2.1
                if t <= groundT && catching {
                    if h.catchRoll < h.catchProbability {
                        if e.config.ball == .paint && s.ball.burstOnCatch {
                            h.catchUntil = 0.0
                            h.catchAt = e.time
                            paintImpact(e, s, h, caught: true)
                            credit(e, false)
                            remove(s)
                            continue
                        }
                        h.catchAt = e.time
                        s.ball.holder = h.member.id
                        s.ball.velocity = V.zero
                        s.ball.vz = 0.0
                        credit(e, true)
                        remove(s)
                        e.ball = s.ball
                        e.emit("catch", h.member.id)
                        continue
                    }
                    h.catchUntil = 0.0
                }
                let top = h.jumpHeight + 0.23 + (e.time < h.duckUntil ? max(e.config.duckHeight, 1.4) : e.config.standingHeight)
                if t <= groundT && near < 0.5 && height >= h.jumpHeight - 0.23 && height <= top {
                    h.hitAt = e.time
                    paintImpact(e, s, h)
                    credit(e, false)
                    remove(s)
                    continue
                }
                let direction = s.ball.velocity.unit()
                let past = s.ball.position - s.aim
                if past.x * direction.x + past.y * direction.y > 0.0 { s.passed = true }
                if s.ball.height <= 0.23 || e.time - s.ball.launchAt > 10.0 {
                    if s.ball.height <= 0.23 { paintImpact(e, s) }
                    credit(e, stage.defence && s.passed)
                    remove(s)
                    continue
                }
            } else {
                if stage.skill == .tag && s.ball.height <= 0.23 && groundT < 1.0 {
                    if !e.config.allowGroundHit || e.config.ball == .paint && s.ball.burstOnGround || s.ball.bounces > 0 {
                        paintImpact(e, s)
                        credit(e, false)
                        remove(s)
                        continue
                    }
                    s.ball.position = before + (s.ball.position - before) * groundT
                    s.ball.height = 0.23
                    s.ball.vz = abs(s.ball.vz) * e.config.ball.restitution * e.config.scene.bounce
                    s.ball.bounces += 1
                    e.emit("bounce", h.member.id)
                    continue
                }
                if stage.skill == .ground && s.ball.height <= 0.23 {
                    let at = before + (s.ball.position - before) * groundT
                    paintImpact(e, s)
                    credit(e, (at - target).length() <= radius)
                    remove(s)
                    continue
                }
                let plane = target.y
                if !s.evaluated && (before.y - plane) * (s.ball.position.y - plane) <= 0 && abs(s.ball.position.y - before.y) > 1e-7 {
                    let t = (plane - before.y) / (s.ball.position.y - before.y)
                    let at = before + (s.ball.position - before) * t
                    let height = z + (s.ball.height - z) * t
                    var hit = false
                    if t <= groundT {
                        switch stage.skill {
                        case .tag:
                            hit = abs(at.x - target.x) < 0.5 && height >= 0.23 && height <= e.config.standingHeight &&
                                (s.ball.bounces == 0 || e.config.allowGroundHit)
                        case .tree, .rebound:
                            hit = abs(at.x - target.x) < 0.65 && height >= 0.3 && height <= 1.6
                        case .pass, .call:
                            hit = abs(at.x - target.x) < e.config.ball.catchRadius && height >= 0.45 && height <= 2.1 &&
                                (stage.skill != .call || selected == partner(e).member.id)
                        case .ring:
                            hit = hypot(at.x - target.x, height - targetHeight) <= radius
                        default:
                            hit = false
                        }
                    }
                    if stage.skill != .ground {
                        if hit && stage.skill == .rebound {
                            if e.config.ball == .paint {
                                paintImpact(e, s)
                                credit(e, false)
                                remove(s)
                            } else {
                                s.ball.position = at
                                s.ball.height = height
                                let duration = Kotlin.clamp((h.position - at).length() /
                                    (s.ball.velocity.length() * (e.config.ball.restitution / 0.82).squareRoot()), 0.65, 1.7)
                                s.ball.velocity = (h.position - at) * (1 / duration) - e.windVector * (0.5 * duration)
                                s.ball.vz = (1.2 - height + 0.5 * e.config.scene.gravity * duration * duration) / duration
                                s.rebounded = true
                                e.emit("bounce", h.member.id)
                            }
                        } else if hit && (stage.skill == .pass || stage.skill == .call) {
                            let receiver = partner(e)
                            let chance = CatchPhysics.probability(receiver, s.ball, h)
                            s.evaluated = true
                            if random.nextDouble() < chance {
                                if e.config.ball == .paint && s.ball.burstOnCatch {
                                    paintImpact(e, s, receiver, caught: true)
                                    credit(e, true)
                                    remove(s)
                                    continue
                                }
                                remove(s)
                                s.ball.holder = receiver.member.id
                                s.ball.velocity = V.zero
                                s.ball.vz = 0.0
                                e.ball = s.ball
                                receiver.catchAt = e.time
                                receiver.facing = (h.position - receiver.position).unit()
                                e.emit("catch", receiver.member.id)
                                if stage.skill == .pass {
                                    cue = [receiver.member.id]
                                    releaseAt = e.time + 1.0
                                } else {
                                    credit(e, true)
                                }
                            } else {
                                s.partnerMiss = true
                            }
                        } else if stage.skill == .pass || stage.skill == .call {
                            s.evaluated = true
                        } else {
                            if hit && (stage.skill == .tree || stage.skill == .tag) {
                                paintImpact(e, s, stage.skill == .tag ? partner(e) : nil)
                            }
                            credit(e, hit)
                            remove(s)
                        }
                        continue
                    }
                }
                if s.ball.height <= 0.23 || e.time - s.ball.launchAt > 10.0 {
                    if s.ball.height <= 0.23 { paintImpact(e, s) }
                    if s.partnerMiss {
                        nextAt = e.time + 1.1
                        e.infoEn = "Your partner missed. Try the pass again; no heart lost."
                        e.infoHe = "השותף החמיץ. נסו למסור שוב; לא איבדתם לב."
                        e.infoUntil = e.time + 2.0
                    } else {
                        credit(e, false)
                    }
                    remove(s)
                    continue
                }
            }
        }
        if let first = shots.first {
            e.ball = first.ball
        } else if stage.throwing && releaseAt < 0 && e.time >= nextAt && e.result == nil {
            ready(e)
        } else if !stage.throwing && e.time >= nextAt {
            let p = partner(e)
            e.ball = Ball(p.position, 1.2, V.zero, 0.0, p.member.id)
        }
    }

    private func trialColour(_ e: AmuduEngine) {
        if e.config.ball == .paint && e.paintPoint != successes + mistakes {
            e.paintPoint = successes + mistakes
            e.paintColor = PaintBalloon.next(seed, e.paintPoint, e.paintColor)
        }
    }

    private func armPaint(_ e: AmuduEngine, _ power: Double) {
        e.armAttackBurst(power)
    }

    /// Kotlin `paintImpact(e, b, target, caught)`: `e.ball = b; e.burstBalloon(...)` mutates the shared ball, so the
    /// burst state is copied back into the shot.
    private func paintImpact(_ e: AmuduEngine, _ s: PracticeBall, _ target: GameActor? = nil, caught: Bool = false) {
        if e.config.ball == .paint && !s.ball.burst && s.ball.burstOnGround {
            e.ball = s.ball
            e.burstBalloon(target, call: stage.skill == .call, caught: caught)
            s.ball = e.ball
        }
    }

    private func remove(_ shot: PracticeBall) {
        if let index = shots.firstIndex(where: { $0 === shot }) { shots.remove(at: index) }
    }

    private func credit(_ e: AmuduEngine, _ success: Bool) {
        if e.result != nil { return }
        if success {
            successes += 1
            lastSuccess = e.time
            e.emit("ready", human(e).member.id)
        } else {
            mistakes += 1
            e.emit("penalty", human(e).member.id)
        }
        nextAt = e.time + 1.1
        if won || failed { complete(e, won) }
    }

    private func complete(_ e: AmuduEngine, _ won: Bool) {
        var penalties: [String: Int] = [:]
        for a in e.actors { penalties[a.member.id] = a.member.bot ? 0 : mistakes }
        let h = human(e)
        e.result = Outcome(id: e.id, penalties: penalties, winners: won ? [h.member.id] : [], elapsed: e.time)
        e.phase = .finished
        e.emit("finish", h.member.id)
    }
}
