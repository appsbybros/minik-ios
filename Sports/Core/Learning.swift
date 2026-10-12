import Foundation

/// Port of Android core/Learning.kt: per-skill progression, generators and the reviewed banks
/// (the banks themselves live in QuestionFacts.swift, generated from Android).
enum Skill: String, KotlinEnum {
    case add = "ADD"
    case subtract = "SUBTRACT"
    case multiply = "MULTIPLY"
    case divide = "DIVIDE"
    case order = "ORDER"
    case fraction = "FRACTION"
    case english = "ENGLISH"
    case world = "WORLD"

    var isArithmetic: Bool { return ordinal < 6 }
}

struct SkillState: Equatable {
    var level: Int = 0
    var streak: Int = 0
    var independent: Int = 0
    var assisted: Int = 0
    var wrong: Int = 0
    var reviewed: Int = 0
}

final class LearningProfile {
    var skills: [Skill: SkillState]

    init() {
        var all: [Skill: SkillState] = [:]
        for skill in Skill.allCases { all[skill] = SkillState() }
        skills = all
    }

    func state(_ skill: Skill) -> SkillState {
        return skills[skill] ?? SkillState()
    }

    /// Mastery is per skill; assisted answers never count as independent ones.
    func record(_ skill: Skill, correct: Bool, hint: Bool) {
        var p = state(skill)
        if !correct {
            p.wrong += 1
            p.streak = 0
            p.level = max(p.level - 1, 0)
        } else if hint {
            p.assisted += 1
            p.streak = 0
        } else {
            p.independent += 1
            p.streak += 1
            if p.streak >= 3 {
                p.level = min(p.level + 1, 5)
                p.streak = 0
            }
        }
        skills[skill] = p
    }
}

struct Question: Equatable {
    let id: String
    let skill: Skill
    let level: Int
    let en: String
    let he: String
    let answer: String
    let options: [String]
    let explanationEn: String
    let explanationHe: String

    /// Android `require(options.size==4 && distinct && exactly one answer)`.
    var isValid: Bool {
        return options.count == 4 && Set(options).count == 4 && options.filter { $0 == answer }.count == 1
    }

    /// Sports shows the question as written (Android `if(hebrew)he else en`, no catalog lookup).
    func text(_ hebrew: Bool) -> String { return hebrew ? he : en }
    func explanation(_ hebrew: Bool) -> String { return hebrew ? explanationHe : explanationEn }
}

struct Fact {
    let en: String
    let he: String
    let choicesEn: [String]
    let choicesHe: [String]
    let level: Int
    let whyEn: String
    let whyHe: String
    let source: String
}

enum QuestionBank {
    /// Begins with accessible addition and progressively introduces operations. Every 4th
    /// question revisits the least-practised eligible skill, independently of combat.
    static func chooseSkill(_ profile: LearningProfile, _ topic: Topic, _ r: KotlinRandom, _ sequence: Int) -> Skill {
        let pool: [Skill]
        switch topic {
        case .english: pool = [.english]
        case .world: pool = [.world]
        case .math: pool = Array(Skill.allCases.prefix(6))
        case .mixed: pool = Skill.allCases
        }
        func learned(_ skill: Skill) -> Int { return profile.state(skill).independent }
        var eligible = pool.filter { skill in
            switch skill {
            case .multiply: return learned(.add) + learned(.subtract) >= 6
            case .divide: return learned(.multiply) >= 3
            case .order: return learned(.multiply) >= 6 && learned(.add) >= 3
            case .fraction: return learned(.divide) >= 3
            case .add, .subtract, .english, .world: return true
            }
        }
        if eligible.isEmpty { eligible = [.add] }
        if sequence % 4 == 3 {
            var best = eligible[0]
            var bestValue = profile.state(best).independent + profile.state(best).assisted
            for skill in eligible.dropFirst() {
                let value = profile.state(skill).independent + profile.state(skill).assisted
                if value < bestValue {
                    best = skill
                    bestValue = value
                }
            }
            return best
        }
        return eligible[r.nextInt(eligible.count)]
    }

    static func generate(_ id: String, _ skill: Skill, _ level: Int, _ r: KotlinRandom, hebrew: Bool = false) -> Question {
        let l = min(max(level, 0), 5)
        if skill == .english || skill == .world {
            let bank = skill == .english ? english : world
            let eligible = bank.filter { $0.level <= l }
            let f = eligible[r.nextInt(eligible.count)]
            let opts = hebrew ? f.choicesHe : f.choicesEn
            return Question(id: id, skill: skill, level: l, en: f.en, he: f.he, answer: opts[0],
                            options: opts.kotlinShuffled(r), explanationEn: f.whyEn, explanationHe: f.whyHe)
        }
        let limit = [5, 10, 20, 50, 100, 200][l]
        var a = r.nextInt(limit + 1)
        var b = r.nextInt(limit + 1)
        var expression = ""
        var answer = 0
        var solution = ""
        if skill == .fraction {
            let d = [2, 3, 4, 5, 6, 8][l]
            a = r.nextInt(1, d)
            b = r.nextInt(1, d)
            func frac(_ n: Int) -> String {
                let g = QuestionBank.gcd(abs(n), d)
                return n % d == 0 ? String(n / d) : "\(n / g)/\(d / g)"
            }
            let right = frac(a + b)
            var opts: [String] = [right]
            var i = 1
            while opts.count < 4 {
                let candidate = frac(a + b + i)
                if !opts.contains(candidate) { opts.append(candidate) }
                i += 1
            }
            expression = "\(a)/\(d) + \(b)/\(d)"
            return Question(id: id, skill: skill, level: l, en: expression, he: expression, answer: right,
                            options: opts.kotlinShuffled(r),
                            explanationEn: "\(a) + \(b) over the common denominator \(d) = \(right)",
                            explanationHe: "מחברים את המונים מעל המכנה המשותף \(d): \(right)")
        }
        switch skill {
        case .add:
            expression = "\(a) + \(b)"
            answer = a + b
        case .subtract:
            if l < 4 && a < b {
                let t = a
                a = b
                b = t
            }
            expression = "\(a) − \(b)"
            answer = a - b
        case .multiply:
            a = r.nextInt(0, (l + 2) * 2)
            b = r.nextInt(0, (l + 2) * 2)
            expression = "\(a) × \(b)"
            answer = a * b
        case .divide:
            b = r.nextInt(1, l * 2 + 4)
            answer = r.nextInt(0, limit + 1)
            a = b * answer
            expression = "\(a) ÷ \(b)"
        case .order:
            a = r.nextInt(1, 10 + l)
            b = r.nextInt(1, 6 + l)
            let c = r.nextInt(1, 6 + l)
            expression = "\(a) + \(b) × \(c)"
            answer = a + b * c
            solution = "Multiply first: \(b) × \(c) = \(b * c). "
        case .fraction, .english, .world:
            // Unreachable (handled above); Android raises "Unexpected skill".
            expression = "\(a) + \(b)"
            answer = a + b
        }
        var opts: [Int] = [answer]
        var offset = 1
        while opts.count < 4 {
            let n = answer + (offset % 2 == 0 ? -offset : offset)
            if n >= 0 || l >= 4 {
                if !opts.contains(n) { opts.append(n) }
            }
            offset += 1
        }
        return Question(id: id, skill: skill, level: l, en: expression, he: expression, answer: String(answer),
                        options: opts.map { String($0) }.kotlinShuffled(r),
                        explanationEn: "\(solution)\(expression) = \(answer)", explanationHe: "\(expression) = \(answer)")
    }

    static func gcd(_ a: Int, _ b: Int) -> Int {
        return b == 0 ? max(a, 1) : gcd(b, a % b)
    }
}
