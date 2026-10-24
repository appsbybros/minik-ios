import Foundation

// Port of game/BasketballJourney.kt (Android 6c38131), statement by statement.
// The stage table is generated from the Kotlin source (ids, English and Hebrew names, goals,
// team sizes and quiet flags are byte-identical).

enum BasketballSkill: String, KotlinEnum { case MOVE, PASS, RELEASE, BASKET, SWITCH, STEAL, SCREEN, ALLEY, CROSSOVER, BEHIND_BACK, SPIN }

struct BasketballGoal: Hashable {
    var skill: BasketballSkill
    var amount: Int
}

struct BasketballStage: Hashable {
    var id: String
    var en: String
    var he: String
    var goals: [BasketballGoal]
    var teamSize: Int = 2
    var quiet: Bool = false

    var helping: Bool { return !goals.contains { [BasketballSkill.STEAL, BasketballSkill.SWITCH].contains($0.skill) } }

    func quality(r: BasketballRatings, helper: Bool = true) -> Int {
        switch goals.first!.skill {
        case .PASS: return helper ? r.ballHandling * 3 + r.agility + r.offense : r.stealing * 3 + r.defense + r.agility
        case .SCREEN: return helper ? r.strength * 3 + r.offense + r.agility : r.defense * 3 + r.agility + r.speed
        case .ALLEY: return helper ? r.jumping * 3 + r.dunking * 2 + r.speed : r.blocking * 3 + r.jumping * 2 + r.defense
        case .STEAL, .SWITCH: return helper ? r.defense * 3 + r.stealing + r.speed : r.ballHandling * 3 + r.speed + r.agility
        case .RELEASE, .BASKET: return helper ? r.offense * 3 + r.ballHandling + r.agility : r.blocking * 3 + r.defense * 2 + r.jumping
        case .MOVE, .CROSSOVER, .BEHIND_BACK, .SPIN: return helper ? r.offense * 3 + r.agility + r.speed : r.defense * 3 + r.speed * 2 + r.agility
        }
    }

    func bot(cycle: Int, excluded: Set<String>, helper: Bool) -> TripleShotCharacterProfile {
        // sortedWith(compareBy { quality(it.ratings, helper) }.thenBy { it.id }): stable, ids in Java String order.
        let list = TripleShotCharacterRoster.all.filter { !excluded.contains($0.id) && !$0.adaptiveBot }.stableSorted { a, b in
            let qa = quality(r: a.ratings, helper: helper)
            let qb = quality(r: b.ratings, helper: helper)
            if qa != qb { return qa < qb }
            return a.id.javaPrecedes(b.id)
        }
        return (helper ? Array(list.reversed()) : list)[cycle.coerceIn(0, list.count - 1)]
    }
}

enum BasketballJourney {
    private static func g(_ s: BasketballSkill, _ n: Int) -> BasketballGoal { return BasketballGoal(skill: s, amount: n) }

    static let stages: [BasketballStage] = [
        BasketballStage(id: "move", en: "Find your feet", he: "מתחילים לזוז", goals: [g(.MOVE, 8)], quiet: true),
        BasketballStage(id: "pass", en: "A pass that arrives", he: "מסירה שמגיעה", goals: [g(.PASS, 2)], quiet: true),
        BasketballStage(id: "release", en: "Feel the release", he: "מרגישים את השחרור", goals: [g(.RELEASE, 3)], quiet: true),
        BasketballStage(id: "basket", en: "First baskets", he: "הסלים הראשונים", goals: [g(.BASKET, 2)], quiet: true),
        BasketballStage(id: "switch", en: "Choose your defender", he: "בוחרים את השומר", goals: [g(.SWITCH, 3)], quiet: true),
        BasketballStage(id: "steal", en: "Close enough to reach", he: "מתקרבים וחוטפים", goals: [g(.STEAL, 1)], quiet: true),
        BasketballStage(id: "screen", en: "Make a little space", he: "מפנים קצת מקום", goals: [g(.SCREEN, 1)]),
        BasketballStage(id: "alley", en: "A pass above the rim", he: "מסירה מעל הטבעת", goals: [g(.ALLEY, 1)]),
        BasketballStage(id: "move_pass", en: "Move, then share", he: "זזים ואז מוסרים", goals: [g(.MOVE, 10), g(.PASS, 3)]),
        BasketballStage(id: "shoot", en: "Find your shooting rhythm", he: "מוצאים קצב קליעה", goals: [g(.RELEASE, 4), g(.BASKET, 2)]),
        BasketballStage(id: "defend", en: "Read the ball", he: "קוראים את הכדור", goals: [g(.SWITCH, 2), g(.STEAL, 2)]),
        BasketballStage(id: "screen_pass", en: "Space for a teammate", he: "מקום לחבר הקבוצה", goals: [g(.SCREEN, 2), g(.PASS, 3)]),
        BasketballStage(id: "alley_twice", en: "Flying partnership", he: "שותפות באוויר", goals: [g(.ALLEY, 2)]),
        BasketballStage(id: "three_pass", en: "Three players, one ball", he: "שלושה שחקנים, כדור אחד", goals: [g(.PASS, 5)], teamSize: 3),
        BasketballStage(id: "three_move", en: "Keep the team moving", he: "הקבוצה בתנועה", goals: [g(.MOVE, 15), g(.PASS, 4)], teamSize: 3),
        BasketballStage(id: "three_screen", en: "Open the lane", he: "פותחים נתיב", goals: [g(.SCREEN, 2), g(.BASKET, 2)], teamSize: 3),
        BasketballStage(id: "three_defend", en: "Stay with the play", he: "נשארים במהלך", goals: [g(.SWITCH, 3), g(.STEAL, 2)], teamSize: 3),
        BasketballStage(id: "three_shoot", en: "Calm hands", he: "ידיים רגועות", goals: [g(.RELEASE, 5), g(.BASKET, 3)], teamSize: 3),
        BasketballStage(id: "three_alley", en: "Above and beyond", he: "עולים יחד", goals: [g(.PASS, 4), g(.ALLEY, 2)], teamSize: 3),
        BasketballStage(id: "final", en: "Team all-rounder", he: "אלופי המשחק הקבוצתי", goals: [g(.MOVE, 12), g(.PASS, 4), g(.BASKET, 3)], teamSize: 3),
        BasketballStage(id: "cross", en: "Change hands", he: "מחליפים ידיים", goals: [g(.CROSSOVER, 2)], quiet: true),
        BasketballStage(id: "behind_back", en: "Behind the back", he: "מאחורי הגב", goals: [g(.BEHIND_BACK, 2)], quiet: true),
        BasketballStage(id: "spin", en: "Turn into space", he: "סיבוב אל השטח הפנוי", goals: [g(.SPIN, 3)])
    ]

    static func stage(step: Int) -> BasketballStage { return stages[floorMod(step, stages.count)] }
}

/** Events come only from completed gestures and court outcomes, never from elapsed time. */
final class BasketballPractice {
    let step: Int
    let stage: BasketballStage
    let cycle: Int
    private var counts: [Double]

    init(step: Int, restored: [Double] = []) {
        self.step = step
        precondition(step >= 0, "Failed requirement.")
        let stage = BasketballJourney.stage(step: step)
        self.stage = stage
        self.cycle = step / BasketballJourney.stages.count
        self.counts = (0..<stage.goals.count).map { i -> Double in
            if let v = restored.getOrNull(i), v.isFinite && v >= 0 { return v }
            return 0.0
        }
    }

    var index: Int { return counts.indices.first { counts[$0] + 1e-6 < Double(goal(i: $0)) } ?? counts.count }

    var won: Bool { return index == counts.count }

    var active: BasketballSkill? { return stage.goals.getOrNull(index)?.skill }

    func goal(i: Int) -> Int {
        return stage.goals[i].amount + cycle.coerceAtMost(6) * (stage.goals[i].skill == .MOVE ? 2 : 1)
    }

    func progress(i: Int) -> Double { return counts[i].coerceAtMost(goal(i: i).toDouble()) }

    func snapshot() -> [Double] { return counts }

    @discardableResult
    func event(skill: BasketballSkill, amount: Double = 1.0) -> Bool {
        if won || active != skill || !amount.isFinite || amount <= 0 { return false }
        let before = index
        counts[before] = (counts[before] + amount).coerceAtMost(goal(i: before).toDouble())
        return index != before
    }
}

// MARK: - Positional (Kotlin call-site) forms

extension BasketballGoal {
    init(_ skill: BasketballSkill, _ amount: Int) { self.init(skill: skill, amount: amount) }
}

extension BasketballStage {
    func quality(_ r: BasketballRatings, _ helper: Bool = true) -> Int { return quality(r: r, helper: helper) }

    func bot(_ cycle: Int, _ excluded: Set<String>, _ helper: Bool) -> TripleShotCharacterProfile {
        return bot(cycle: cycle, excluded: excluded, helper: helper)
    }
}

extension BasketballJourney {
    static func stage(_ step: Int) -> BasketballStage { return stage(step: step) }
}

extension BasketballPractice {
    convenience init(_ step: Int, _ restored: [Double] = []) { self.init(step: step, restored: restored) }

    func goal(_ i: Int) -> Int { return goal(i: i) }

    func progress(_ i: Int) -> Double { return progress(i: i) }

    @discardableResult
    func event(_ skill: BasketballSkill, _ amount: Double = 1.0) -> Bool { return event(skill: skill, amount: amount) }
}
