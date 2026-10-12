import Foundation

/// Port of Android core/PaintChallenges.kt: the daily paint journey's challenge kinds, its progress, and the paint
/// walls of challenges and wall battles. Raw values are the Kotlin enum names (saved and shared by name).
enum ChallengeKind: String, KotlinEnum {
    case cover = "COVER"
    case duel = "DUEL"
    case pattern = "PATTERN"
    case letter = "LETTER"
    case passing = "PASSING"
    case shape = "SHAPE"
    case target = "TARGET"
    case timedTarget = "TIMED_TARGET"
    case race = "RACE"
    case duck = "DUCK"
    case jump = "JUMP"
    case sidestep = "SIDESTEP"
    case duckTwo = "DUCK_TWO"
    case jumpTwo = "JUMP_TWO"
    case dodgeTwo = "DODGE_TWO"
    case dodgeOpposite = "DODGE_OPPOSITE"
    case duckThree = "DUCK_THREE"
    case jumpThree = "JUMP_THREE"
    case dodgeThree = "DODGE_THREE"
    case dodgeFour = "DODGE_FOUR"
    case duckPair = "DUCK_PAIR"
    case jumpPair = "JUMP_PAIR"
    case dodgePairs = "DODGE_PAIRS"
    case ring = "RING"
    case ringSides = "RING_SIDES"
    case ringHigh = "RING_HIGH"
    case ground = "GROUND"
    case groundFar = "GROUND_FAR"
    case passWide = "PASS_WIDE"
    case passQuick = "PASS_QUICK"

    var en: String { return ChallengeKind.names[self]?.0 ?? rawValue }
    var he: String { return ChallengeKind.names[self]?.1 ?? rawValue }

    private static let names: [ChallengeKind: (String, String)] = [
        .cover: ("Paint the wall", "צובעים את הקיר"), .duel: ("Friendly duel", "דו־קרב ידידותי"),
        .pattern: ("Paint a star", "צובעים כוכב"), .letter: ("Paint a letter", "צובעים אות"),
        .passing: ("Keep the balloon flying", "שומרים את הבלון באוויר"),
        .shape: ("Stay inside the heart", "נשארים בתוך הלב"), .target: ("Ten accurate throws", "עשר זריקות מדויקות"),
        .timedTarget: ("Beat the target clock", "קליעה נגד השעון"), .race: ("Wall painting race", "מרוץ צביעת קיר"),
        .duck: ("Duck under the splash", "מתכופפים מתחת לבלון"), .jump: ("Jump the low balloon", "קופצים מעל הבלון"),
        .sidestep: ("Step out of the way", "זזים הצדה"), .duckTwo: ("Two throwers, one duck", "שני זורקים, כיפוף אחד"),
        .jumpTwo: ("Two throwers, one jump", "שני זורקים, קפיצה אחת"), .dodgeTwo: ("Read two throwers", "קוראים שני זורקים"),
        .dodgeOpposite: ("Watch both sides", "מסתכלים לשני הצדדים"), .duckThree: ("Duck in rhythm", "מתכופפים בקצב"),
        .jumpThree: ("Jump in rhythm", "קופצים בקצב"), .dodgeThree: ("Three-way lookout", "שומרים על שלושה כיוונים"),
        .dodgeFour: ("All-around awareness", "עירנות מכל הכיוונים"), .duckPair: ("Duck together", "מתכופפים מול צמד"),
        .jumpPair: ("Jump together", "קופצים מול צמד"), .dodgePairs: ("Choose your escape", "בוחרים איך להתחמק"),
        .ring: ("Through the floating ring", "דרך הטבעת המרחפת"), .ringSides: ("Follow the ring", "עוקבים אחרי הטבעת"),
        .ringHigh: ("Aim a little higher", "מכוונים גבוה יותר"), .ground: ("Land on the island", "נוחתים על האי"),
        .groundFar: ("Near and far islands", "איים קרובים ורחוקים"), .passWide: ("Move and catch", "זזים ותופסים"),
        .passQuick: ("Ready for the next pass", "מוכנים למסירה הבאה"),
    ]

    var drill: SplashDrillSpec? { return SplashDrills.find(self) }
    /// Kotlin `passing` (renamed: the PASSING case already owns that name).
    var isPassing: Bool { return self == .passing || self == .passWide || self == .passQuick }
    var untimed: Bool { return self != .duel && self != .timedTarget && self != .race }
    var isTarget: Bool { return self == .target || self == .timedTarget }
    var hasWall: Bool { return self != .duel && !isPassing && drill == nil }
    var cooperative: Bool {
        return isPassing || self == .cover || self == .pattern || self == .letter || self == .shape || drill?.aiming == true
    }

    func aptitude(_ c: SplashCharacter) -> Int {
        let q = c.qualities
        switch self {
        case .duel:
            return q.precision * 3 + q.reflexes * 3 + q.speed * 2 + q.knowledge
        case .passing, .passWide, .passQuick:
            return q.precision * 5 + q.reflexes * 2 + q.speed
        default:
            if drill?.defending == true { return q.precision * 5 + q.speed * 2 + q.power * 2 }
            return q.precision * 5 + q.knowledge * 2 + q.speed
        }
    }

    /// The partner (cooperative challenges start with the most able character) or opponent (the least able first).
    func partner(_ chapter: Int, _ excluded: Set<String> = []) -> SplashCharacter {
        let ranked = Characters.all.filter { !excluded.contains($0.id) }.sorted { a, b in
            let x = aptitude(a)
            let y = aptitude(b)
            if x != y { return x < y }
            return a.id.javaPrecedes(b.id)
        }
        let ordered = cooperative ? Array(ranked.reversed()) : ranked
        return ordered[min(max(chapter, 0), ordered.count - 1)]
    }

    func introduction(_ hebrew: Bool) -> String {
        if cooperative {
            if isPassing {
                return hebrew ? "השותף עוזר לכם לשמור את הבלון באוויר. מתחילים עם מוסר מדויק. בכל מסלול חדש המסירות נוטות קצת יותר לצדדים, אך תמיד נשארות בהישג יד. עברו לעיגול הנחיתה כדי לתפוס אוטומטית, ואז געו בשותף כדי למסור בחזרה."
                    : "Your partner helps keep the balloon flying. Start with an accurate passer. In each new cycle, passes drift a little farther sideways but stay within reach. Move to the landing ring to catch automatically, then tap your partner to pass back."
            }
            return hebrew ? "הדמות היא מדריכה, לא יריבה. מתחילים עם מומחית לדיוק. כל מסלול חדש דורש מכם מעט יותר דיוק ועצמאות, בלי למחוק את מה שכבר הצלחתם."
                : "This character is your guide, not your opponent. Begin with a precision expert. Each new cycle asks for a little more accuracy and independence, while keeping all your progress."
        }
        return hebrew ? "כאן הדמות היא יריבה. מתחילים מול שחקן קל יותר ומתקדמים בכל מסלול ליריב מיומן יותר. באתגרי קליעה הדיוק חשוב במיוחד; בדו־קרב גם התגובה והמהירות קובעות."
            : "Here the character is your opponent. Start against an easier player, then face a stronger rival each cycle. Target challenges emphasize precision; duels also consider reflexes and movement speed."
    }

    func goal(_ hebrew: Bool) -> String {
        switch self {
        case .passWide, .passQuick:
            return ChallengeKind.passing.goal(hebrew)
        case .passing:
            return hebrew ? "תפסו מסירות בלי שהבלון ייגע ברצפה. התקדמו אל עיגול הנחיתה ומסרו בחזרה."
                : "Catch passes without letting the balloon touch the ground. Move to the landing ring and pass back."
        case .cover:
            return hebrew ? "צבעו את כל המשבצות שעל הקיר." : "Cover every tile on the wall."
        case .duel:
            return hebrew ? "נצחו את היריב בקרב קצר. כל תשובה נכונה נחשבת." : "Win a short duel. Every correct answer still counts."
        case .pattern:
            return hebrew ? "צבעו את הכוכב המסומן על הקיר." : "Fill the star marked on the wall."
        case .letter:
            return hebrew ? "צבעו את האות ש המסומנת על הקיר." : "Fill the letter M marked on the wall."
        case .shape:
            return hebrew ? "מלאו את הלב. עד שלוש זריקות מחוץ לקו." : "Fill the heart. Up to three throws outside the line."
        case .target:
            return hebrew ? "עשר זריקות לכל שחקן, ללא שעון. פגיעה במרכז שווה יותר." : "Ten throws each, no clock. The center scores more."
        case .timedTarget:
            return hebrew ? "קלעו יותר נקודות מהיריב לפני שהזמן נגמר." : "Score more than your rival before time runs out."
        case .race:
            return hebrew ? "צבעו את כל הקיר בצבע שלכם, או הובילו כשהזמן נגמר." : "Cover the wall in your color, or lead when the clock ends."
        default:
            return drill?.brief(hebrew) ?? ""
        }
    }
}

/// Android `ChallengeProgress`: a receipt advances exactly one stage. The caller persists this with points atomically.
/// Kotlin keeps the receipts in a LinkedHashSet; the array keeps the same insertion order (the latest 128).
struct ChallengeProgress: Equatable {
    var completed = 0
    var points = 0
    var lastBonusDay = ""
    var receipts: [String] = []

    var chapter: Int { return completed / SplashDrills.journey.count }
    var kind: ChallengeKind { return SplashDrills.journey[completed % SplashDrills.journey.count] }
    var opponent: SplashCharacter { return kind.partner(chapter) }

    func finish(_ receipt: String, _ stage: Int, _ won: Bool, _ day: String, _ finishedKind: ChallengeKind? = nil) -> ChallengeProgress {
        if !won || stage != completed || receipts.contains(receipt) || (finishedKind ?? kind) != kind { return self }
        let daily = lastBonusDay.javaPrecedes(day)
        var next = self
        next.completed = completed + 1
        next.points = points + 40 + min(chapter, 10) * 10 + (daily ? 30 : 0)
        next.lastBonusDay = daily ? day : lastBonusDay
        next.receipts = Array((receipts + [receipt]).suffix(128))
        return next
    }
}

/// Android `PaintWall`: authoritative coverage cells; decoration never counts as paint.
final class PaintWall {
    let id: Int
    let y: Double
    let width: Double
    let height: Double
    let columns: Int
    let rows: Int
    var cells: [Int]

    init(_ id: Int, _ y: Double, _ width: Double, height: Double = 5.0, columns: Int = 14, rows: Int = 8) {
        self.id = id
        self.y = y
        self.width = width
        self.height = height
        self.columns = columns
        self.rows = rows
        cells = Array(repeating: -1, count: columns * rows)
    }

    func world(_ u: Double, _ v: Double) -> V { return V(width * (0.14 + 0.72 * u), y) }
    func uv(_ x: Double, _ z: Double) -> V { return V((x / width - 0.14) / 0.72, z / height) }
    func at(_ index: Int) -> V { return V((Double(index % columns) + 0.5) / Double(columns), (Double(index / columns) + 0.5) / Double(rows)) }

    @discardableResult
    func paint(_ u: Double, _ v: Double, _ team: Int, _ radius: Double) -> Int {
        var changed = 0
        for i in cells.indices {
            let pt = at(i)
            if hypot(pt.x - u, (pt.y - v) * 0.72) <= radius && cells[i] != team {
                cells[i] = team
                changed += 1
            }
        }
        return changed
    }

    func fraction(_ team: Int) -> Double { return Double(cells.filter { $0 == team }.count) / Double(cells.count) }
}

/// Android `PaintSession`: the walls, catches, target points and throws of a challenge or wall battle.
final class PaintSession {
    let config: SplashConfig
    let hebrew: Bool
    let kind: ChallengeKind?
    let active: Bool
    let walls: [PaintWall]
    var catches = 0
    var points = [0, 0]
    var throwsTaken = [0, 0]
    var spills = 0
    var failed = false
    let radius: Double
    let targetMask: [Bool]

    init(_ config: SplashConfig, _ hebrew: Bool) {
        self.config = config
        self.hebrew = hebrew
        kind = config.challenge
        active = config.wallBattle || config.challenge?.hasWall == true
        if !active {
            walls = []
        } else if config.wallBattle {
            walls = [PaintWall(0, 1.2, config.width), PaintWall(1, config.depth - 1.2, config.width)]
        } else {
            walls = [PaintWall(0, 1.2, config.width)]
        }
        radius = max(0.20 - Double(config.chapter) * 0.007, 0.12)
        let challenge = config.challenge
        targetMask = (0..<(14 * 8)).map { i in PaintSession.inside(challenge, hebrew, (Double(i % 14) + 0.5) / 14, (Double(i / 14) + 0.5) / 8) }
    }

    private static func inside(_ kind: ChallengeKind?, _ hebrew: Bool, _ u: Double, _ v: Double) -> Bool {
        func within(_ x: Double, _ low: Double, _ high: Double) -> Bool { return x >= low && x <= high }
        switch kind {
        case .pattern?:
            let x = u - 0.5
            let y = (v - 0.5) * 0.85
            let a = atan2(y, x)
            return hypot(x, y) < 0.28 + 0.11 * cos(5 * a - Double.pi / 2)
        case .letter?:
            if hebrew {
                return (v < 0.25 && within(u, 0.18, 0.82)) || (within(u, 0.14, 0.27) && v < 0.86) || (within(u, 0.43, 0.56) && within(v, 0.25, 0.86)) ||
                    (within(u, 0.73, 0.86) && v < 0.86)
            }
            return ((within(u, 0.14, 0.27) || within(u, 0.73, 0.86)) && within(v, 0.15, 0.86)) ||
                (abs(v - (1.30 - 1.25 * u)) < 0.11 && within(u, 0.25, 0.5)) || (abs(v - (0.05 + 1.25 * u)) < 0.11 && within(u, 0.5, 0.75))
        case .shape?:
            let x = (u - 0.5) * 2.5
            let y = (v - 0.46) * 2.5
            let t = x * x + y * y - 0.38
            return t * t * t - x * x * y * y * y <= 0
        default:
            return true
        }
    }

    /// Kotlin `passing`.
    var passing: Bool { return kind?.isPassing == true }

    var catchGoal: Int {
        let base = kind == .passing ? 4 : (kind == .passWide ? 6 : 8)
        return base + 2 * min(config.chapter, 8)
    }

    var cooperative: Bool { return kind == .cover || kind == .pattern || kind == .letter || kind == .shape }

    func coverage(_ team: Int) -> Double {
        guard let w = walls.first else { return 0.0 }
        var painted = 0
        var total = 0
        for i in targetMask.indices where targetMask[i] {
            total += 1
            if w.cells[i] == team { painted += 1 }
        }
        return Double(painted) / Double(max(total, 1))
    }

    func hit(_ wall: Int, _ u: Double, _ v: Double, _ team: Int, _ human: Bool = true) {
        if u < 0.0 || u > 1.0 || v < 0.0 || v > 1.0 { return }
        guard wall >= 0 && wall < walls.count else { return }
        let w = walls[wall]
        if config.wallBattle && wall == team { return }
        if kind?.isTarget == true {
            let d = hypot((u - 0.5) * 1.4, v - 0.5)
            let gained: Int
            if d <= 0.08 {
                gained = 10
            } else if d <= 0.18 {
                gained = 6
            } else if d <= 0.30 {
                gained = 3
            } else if d <= 0.46 {
                gained = 1
            } else {
                gained = 0
            }
            if team >= 0 && team < points.count { points[team] += gained }
        }
        if kind == .shape && team == 0 {
            let row = min(max(Int(v * 8), 0), 7)
            let column = min(max(Int(u * 14), 0), 13)
            if !targetMask[row * 14 + column] {
                if human {
                    spills += 1
                    if spills > 3 { failed = true }
                }
                return
            }
        }
        w.paint(u, v, team, radius)
    }

    func complete() -> Bool { return cooperative && coverage(0) >= 0.999 }

    func score(_ team: Int) -> Int {
        if kind?.isTarget == true { return team >= 0 && team < points.count ? points[team] : 0 }
        if config.wallBattle { return Int((walls[1 - team].fraction(team) * 100).rounded()) }
        return Int((coverage(team) * 100).rounded())
    }

    func winner() -> Int? {
        let a = score(0)
        let b = score(1)
        if a == b { return nil }
        return a > b ? 0 : 1
    }

    func fullWinner() -> Int? {
        if config.wallBattle { return [0, 1].first { walls[1 - $0].fraction($0) >= 0.999 } }
        if kind == .race { return [0, 1].first { coverage($0) >= 0.999 } }
        return nil
    }
}
