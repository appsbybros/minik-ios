import Foundation

/// Port of Android core/SportsJourney.kt: the 30-step daily skill journey of each sport and its
/// drills. Outcomes are observed at production ball contacts, net crossings and first landings.
enum CourtSkill: String, KotlinEnum {
    case aim = "AIM"
    case paint = "PAINT"
    case order = "ORDER"
    case ret = "RETURN"
    case move = "MOVE"
    case serve = "SERVE"
    case pass = "PASS"
    case set = "SET"
    case spike = "SPIKE"
    case block = "BLOCK"
}

struct CourtStage: Equatable {
    let id: String
    let en: String
    let he: String
    let skill: CourtSkill
    let base: Int
    let pattern: Int
    let moving: Bool
    let small: Bool
    let streak: Bool
    let fast: Bool

    init(_ id: String, _ en: String, _ he: String, _ skill: CourtSkill, _ base: Int = 6, _ pattern: Int = 0,
         moving: Bool = false, small: Bool = false, streak: Bool = false, fast: Bool = false) {
        self.id = id
        self.en = en
        self.he = he
        self.skill = skill
        self.base = base
        self.pattern = pattern
        self.moving = moving
        self.small = small
        self.streak = streak
        self.fast = fast
    }

    var cooperative: Bool { return [.ret, .move, .pass, .set, .spike].contains(skill) }

    func goal(_ cycle: Int) -> Int { return base + 2 * min(max(cycle, 0), 6) }

    func aptitude(_ c: SportsCharacter, _ sport: Sport) -> Int {
        if sport == .squash {
            let q = c.qualities
            return q.precision * 5 + q.reflexes * 2 + q.speed
        }
        let v = VolleySkills.of(c.id)
        switch skill {
        case .block: return v.power * 4 + v.hitting * 3 + v.precision
        case .serve: return v.serve * 5 + v.precision * 2
        default: return v.precision * 5 + v.hitting * 3 + v.speed
        }
    }

    func bot(_ cycle: Int, _ sport: Sport, _ excluded: Set<String>) -> SportsCharacter {
        var ordered = Characters.forSport(sport).filter { !excluded.contains($0.id) }.stableSorted { a, b in
            let x = aptitude(a, sport)
            let y = aptitude(b, sport)
            if x != y { return x < y }
            return a.id.javaPrecedes(b.id)
        }
        if cooperative || skill != .block { ordered.reverse() }
        return ordered[min(max(cycle, 0), ordered.count - 1)]
    }

    func brief(_ sport: Sport, _ he: Bool) -> String {
        switch skill {
        case .aim, .serve:
            if sport == .squash {
                return he ? "הקישו על המעגל הזהוב בקיר כדי להגיש. הכדור עצמו חייב לפגוע במטרה מעל קו ההגשה."
                    : "Tap the golden wall circle to serve. Your ball must hit the target above the service line."
            }
            return he ? "הקישו על האי הזהוב כדי להגיש אליו. הכדור צריך לעבור מעל הרשת ולנחות בתוך האי."
                : "Tap the golden island to serve there. The ball must clear the net and land inside the island."
        case .paint:
            return he ? "צבעו את הצורה: הקישו בכל פעם על עיגול שעדיין לא נצבע. רק פגיעת כדור אמיתית צובעת חלק."
                : "Color the shape: tap a circle that is not painted yet. Only a real ball impact paints a piece."
        case .order:
            return he ? "עקבו אחרי המספר הזהוב. פגעו בחלקים לפי הסדר כדי לגלות את הצורה." : "Follow the golden number. Hit each piece in order to reveal the shape."
        case .ret:
            if sport == .squash {
                return he ? "הדמות עוקבת אחרי הכדור. כשהוא מגיע למחבט, הקישו על המטרה בקיר כדי להחזיר."
                    : "Your player follows the ball. As it reaches your racket, tap the wall target to return."
            }
            return he ? "כשהכדור מתקרב, הקישו על יעד במגרש היריב. רק החזרה שלכם שעוברת מעל הרשת נספרת."
                : "As the ball approaches, tap a target in the other court. Only your own return over the net counts."
        case .move:
            return he ? "גררו את הדמות לעבר סימן הנחיתה. לאחר שזזתם, הקישו בזמן כדי להחזיר. עמידה במקום אינה מספיקה."
                : "Drag your player toward the landing marker. After moving, time your tap to return. Standing still is not enough."
        case .pass:
            return he ? "כשהכדור מגיע, הקישו על חבר הקבוצה למסירה. המסירה נספרת רק כשחבר הקבוצה נוגע בכדור."
                : "As the ball arrives, tap your teammate to pass. The pass counts only when your teammate contacts the ball."
        case .set:
            return he ? "כשהכדור מגיע, געו פעמיים כדי להרים כדור נמוך לחבר הקבוצה. המתינו לחבטה שלו."
                : "As the ball arrives, double-tap to set a low ball for your teammate. Wait for their contact."
        case .spike:
            return he ? "התקרבו לכדור הגבוה וגעו פעמיים כדי לקפוץ ולהנחית. הכדור צריך לעבור מעל הרשת."
                : "Get close to the high ball and double-tap to jump and spike. Your shot must pass over the net."
        case .block:
            return he ? "התמקמו ליד הרשת מול הכדור. הקישו על הרשת בתזמון הנכון כדי לקפוץ ולחסום בשתי ידיים."
                : "Stand near the net facing the ball. Time a tap on the net to jump and block with both hands."
        }
    }

    func role(_ he: Bool) -> String {
        if cooperative {
            return he ? "זהו שותף לאימון. מתחילים עם מוסר מדויק. במסלול הבא מקבלים שותף פחות מדויק, אך הכדורים נשארים בהישג יד."
                : "This is your practice partner. Start with an accurate feeder. Later cycles use less precise partners, while every feed stays reachable."
        }
        if skill == .block {
            return he ? "זהו יריב. מתחילים מול מנחית קל יותר; בכל מסלול חדש העוצמה והחבטה הרלוונטיות לאתגר עולות."
                : "This is your opponent. Start against an easier attacker; later cycles increase the power and hitting skill relevant to this challenge."
        }
        return he ? "המדריך מעודד בזמן שאתם מכוונים. בכל מסלול חדש המטרות מאתגרות מעט יותר. שלוש החטאות מאפשרות ניסיון חדש, בלי לאבד התקדמות."
            : "Your guide cheers while you aim. Each cycle makes the targets a little harder. After three misses, retry without losing progress."
    }
}

enum SportsJourney {
    static let squash: [CourtStage] = [
        CourtStage("first", "Your first target", "המטרה הראשונה", .aim),
        CourtStage("left_right", "Left and right", "ימין ושמאל", .aim, moving: true),
        CourtStage("paint_ring", "Paint a rainbow ring", "צובעים טבעת קשת", .paint, 8, 1),
        CourtStage("return", "Meet the rebound", "פוגשים את הכדור החוזר", .ret),
        CourtStage("high_low", "Up and down", "למעלה ולמטה", .aim, 8, 2, moving: true),
        CourtStage("triangle", "Color a triangle", "צובעים משולש", .paint, 9, 2),
        CourtStage("steps", "Move to the rebound", "זזים לכדור החוזר", .move),
        CourtStage("serve_streak", "Serve in rhythm", "מגישים בקצב", .serve, 6, streak: true),
        CourtStage("star", "Light the star", "מאירים את הכוכב", .paint, 10, 3),
        CourtStage("number_ring", "Around in order", "מקיפים לפי הסדר", .order, 8, 1),
        CourtStage("return_sides", "Return to both sides", "מחזירים לשני הצדדים", .ret, 8, moving: true),
        CourtStage("little_targets", "Little golden targets", "מטרות זהב קטנות", .aim, 8, small: true),
        CourtStage("diamond", "Fill the diamond", "ממלאים יהלום", .paint, 8, 4),
        CourtStage("run_return", "Run and return", "רצים ומחזירים", .move, 8, moving: true),
        CourtStage("order_triangle", "Triangle trail", "שביל משולש", .order, 9, 2),
        CourtStage("return_streak", "Steady racket", "מחבט יציב", .ret, 8, streak: true),
        CourtStage("wave", "Paint a wave", "צובעים גל", .paint, 10, 5),
        CourtStage("serve_corners", "Golden corners", "פינות זהובות", .serve, 10, moving: true, small: true),
        CourtStage("quick_return", "Quick rebound", "כדור חוזר מהיר", .ret, 8, fast: true),
        CourtStage("order_star", "Star trail", "שביל כוכבים", .order, 10, 3),
        CourtStage("steps_streak", "Move in rhythm", "זזים בקצב", .move, 8, streak: true),
        CourtStage("small_ring", "Tiny rainbow", "קשת קטנה", .paint, 10, 1, small: true),
        CourtStage("serve_precision", "Precision serves", "הגשות מדויקות", .serve, 10, small: true, streak: true),
        CourtStage("return_precision", "Golden returns", "החזרות זהובות", .ret, 10, moving: true, small: true),
        CourtStage("order_wave", "Follow the wave", "עוקבים אחרי הגל", .order, 12, 5),
        CourtStage("quick_steps", "Quick feet", "רגליים זריזות", .move, 10, moving: true, fast: true),
        CourtStage("star_precision", "Star artist", "אמן הכוכבים", .paint, 12, 3, small: true),
        CourtStage("return_rhythm", "Racket rhythm", "קצב המחבט", .ret, 10, streak: true, fast: true),
        CourtStage("order_diamond", "Diamond explorer", "מגלים יהלום", .order, 12, 4, small: true),
        CourtStage("final", "Court explorer", "מגלים את המגרש", .move, 12, moving: true, small: true, fast: true)
    ]

    static let volley: [CourtStage] = [
        CourtStage("serve", "Your first serve", "ההגשה הראשונה", .serve),
        CourtStage("receive", "Ready hands", "ידיים מוכנות", .ret),
        CourtStage("move", "Follow the ball", "עוקבים אחרי הכדור", .move),
        CourtStage("pass", "Find your teammate", "מוצאים חבר קבוצה", .pass),
        CourtStage("set", "Lift it up", "מרימים גבוה", .set),
        CourtStage("spike", "Your first spike", "ההנחתה הראשונה", .spike),
        CourtStage("block", "Hands above the net", "ידיים מעל הרשת", .block, 5),
        CourtStage("serve_sides", "Serve both islands", "מגישים לשני האיים", .serve, 8, moving: true),
        CourtStage("receive_sides", "Side to side", "מצד לצד", .move, 8, moving: true),
        CourtStage("pass_rhythm", "Passing rhythm", "קצב המסירות", .pass, 8, streak: true),
        CourtStage("set_move", "Move and lift", "זזים ומרימים", .set, 8, moving: true),
        CourtStage("spike_sides", "Find open sand", "מוצאים חול פנוי", .spike, 8, moving: true),
        CourtStage("block_five", "Five blocks in a row", "חמש חסימות ברצף", .block, 5, streak: true),
        CourtStage("serve_small", "Little islands", "איים קטנים", .serve, 8, small: true),
        CourtStage("ten_returns", "Ten good returns", "עשר החזרות טובות", .ret, 10),
        CourtStage("pass_wide", "Wide passes", "מסירות לצדדים", .pass, 8, moving: true),
        CourtStage("set_rhythm", "Steady setter", "מרימים בקצב", .set, 8, streak: true),
        CourtStage("spike_high", "Reach for the sky", "מגיעים לשמים", .spike, 8, fast: true),
        CourtStage("block_sides", "Guard both sides", "שומרים על הצדדים", .block, 6, moving: true),
        CourtStage("serve_streak", "Serving streak", "רצף הגשות", .serve, 10, streak: true),
        CourtStage("quick_receive", "Quick returns", "החזרות זריזות", .ret, 10, fast: true),
        CourtStage("quick_move", "Light feet", "רגליים קלות", .move, 10, moving: true, fast: true),
        CourtStage("pass_streak", "Team connection", "קשר קבוצתי", .pass, 10, moving: true, streak: true),
        CourtStage("set_aim", "Lift and find space", "מרימים ומוצאים מקום", .set, 10, moving: true, fast: true),
        CourtStage("spike_streak", "Smashing rhythm", "קצב ההנחתות", .spike, 8, streak: true),
        CourtStage("block_quick", "Quick wall", "חומה זריזה", .block, 7, fast: true),
        CourtStage("serve_precision", "Island explorer", "מגלים איים", .serve, 10, moving: true, small: true, streak: true),
        CourtStage("receive_streak", "Rally rhythm", "קצב ההחזרות", .ret, 12, streak: true, fast: true),
        CourtStage("block_final", "Beach guardian", "שומרי החוף", .block, 8, moving: true, streak: true, fast: true),
        CourtStage("final", "Beach star", "כוכבי החוף", .spike, 12, moving: true, streak: true, fast: true)
    ]

    static func stages(_ s: Sport) -> [CourtStage] { return s == .squash ? squash : volley }
    static func stage(_ s: Sport, _ n: Int) -> CourtStage { return stages(s)[floorMod(n, 30)] }
}

/// Android `CourtPractice`: one drill of the journey.
final class CourtPractice {
    let sport: Sport
    let step: Int
    let stage: CourtStage
    let cycle: Int
    let goal: Int
    var successes = 0
    var mistakes = 0
    var attempts = 0
    var nextAt = 1.5
    var deadline = 0.0
    var pending = false
    var pendingKind = ""
    var received = false
    var initialSteps = 0.0
    /// Android `linkedSetOf<Int>()`: painted pieces in the order they were painted.
    var painted: [Int] = []
    var lastGood = -10.0

    init(_ sport: Sport, _ step: Int) {
        self.sport = sport
        self.step = step
        stage = SportsJourney.stage(sport, step)
        cycle = max(step / 30, 0)
        goal = stage.goal(cycle)
    }

    var won: Bool { return successes >= goal }
    var failed: Bool { return mistakes >= 3 }

    var radius: Double {
        let size = sport == .squash ? (stage.small ? 0.32 : 0.54) : (stage.small ? 0.8 : 1.4)
        return size * (1 - Double(min(cycle, 6)) * 0.025)
    }

    var shape: Bool { return stage.skill == .paint || stage.skill == .order }
    var serve: Bool { return [.aim, .paint, .order, .serve].contains(stage.skill) }

    func targets() -> [Vec] {
        if !shape {
            if sport == .squash {
                let x = stage.moving ? [-1.9, 1.9, 0.0][attempts % 3] : 0.0
                return [Vec(x, stage.pattern == 2 && attempts % 2 == 0 ? 3.8 : 2.65)]
            }
            return [Vec(stage.moving ? [-2.2, 2.2, 0.0][attempts % 3] : 0.0, -5.5)]
        }
        return (0..<goal).map { i -> Vec in
            let a = 2 * Double.pi * Double(i) / Double(goal) - Double.pi / 2
            let t = Double(i) / Double(goal)
            switch stage.pattern {
            case 2:
                let corners = [Vec(0.0, 4.0), Vec(2.35, 1.9), Vec(-2.35, 1.9)]
                let n = t * 3
                let k = KotlinNumber.int(n)
                return corners[k] + (corners[(k + 1) % 3] - corners[k]) * (n - Double(k))
            case 4:
                let n = t * 4
                let k = KotlinNumber.int(n)
                let v = [Vec(0.0, 4.0), Vec(2.3, 2.95), Vec(0.0, 1.9), Vec(-2.3, 2.95)]
                return v[k] + (v[(k + 1) % 4] - v[k]) * (n - Double(k))
            case 5:
                return Vec(-2.3 + 4.6 * Double(i) / Double(goal - 1), 2.95 + sin(t * 2 * Double.pi) * 0.85)
            default:
                let r = stage.pattern == 3 && i % 2 == 1 ? 0.48 : 1.0
                return Vec(cos(a) * 2.2 * r, 2.95 + sin(a) * 1.02 * r)
            }
        }
    }

    private func human(_ e: SportsEngine) -> Athlete { return e.players.first { !$0.member.bot }! }

    func prepare(_ e: SportsEngine) {
        e.phase = .rally
        e.countdown = 0.0
        e.ball.active = false
        for it in e.players { it.goal = it.p }
        let h = human(e)
        h.p = sport == .squash ? Vec(0.0, 1.6) : Vec(0.0, 5.0)
        h.goal = h.p
    }

    func tick(_ e: SportsEngine) {
        if won || failed {
            finish(e)
            return
        }
        if deadline > 0 && e.clock > deadline {
            resolve(e, false)
            return
        }
        if e.ball.active || e.phase == .ready || e.clock < nextAt { return }
        let h = human(e)
        let bot = e.players.first { $0.member.team != h.member.team }!
        let side: Double = attempts % 2 == 0 ? -1 : 1
        pending = false
        received = false
        pendingKind = ""
        initialSteps = h.steps
        e.poseStamp = -10.0
        e.phase = .rally
        e.countdown = 0.0
        e.ball.bounces = 0
        e.ball.scoringChecked = false
        e.ball.touches = 0
        e.ball.serve = false
        for it in e.players {
            it.swing = 0.0
            it.volleyKind = "auto"
            it.volleyTriedShot = -1
            it.plannedMiss = false
        }
        if serve {
            e.server = e.players.firstIndex { $0 === h } ?? 0
            e.phase = .ready
            e.serveRequested = false
            e.serveWindowStarted = false
            e.volley.reset()
            h.p = sport == .squash ? Vec(-1.65, 2.8) : Vec(0.0, 8.55)
            h.goal = h.p
            e.ball.p = h.p
            e.ball.z = 1.1
            deadline = 0.0
            return
        }
        // Feeds use the match's ballistic integrator. Partner drift stays inside a reachable court area.
        let precision = sport == .volley ? VolleySkills.of(bot.member.character).precision : bot.character.qualities.precision
        let drift: Double
        if stage.moving || stage.skill == .move {
            drift = side * (1.4 + min(0.35, Double(5 - precision) * 0.07 + Double(cycle) * 0.03))
        } else {
            drift = side * min(0.65, Double(5 - precision) * 0.08 + Double(cycle) * 0.06)
        }
        let dest = sport == .squash ? Vec(drift, 1.6) : (stage.skill == .block ? Vec(drift, 1.8) : Vec(drift, 5.0))
        let start = sport == .squash ? Vec(drift, -4.6) : (stage.skill == .block ? Vec(drift, -2.0) : Vec(drift, -5.0))
        let power = sport == .volley ? VolleySkills.of(bot.member.character).power : bot.character.qualities.power
        let time: Double
        if stage.skill == .block {
            time = 1.3 - Double(power) * 0.035 - min(Double(cycle) * 0.015, 0.08)
        } else {
            time = stage.fast ? 1.45 : 1.9
        }
        let startZ = stage.skill == .block ? 3.0 : 1.3
        let endZ = stage.skill == .spike ? 2.4 : (stage.skill == .block ? 1.0 : 0.8)
        if stage.skill == .block {
            h.p = Vec(stage.moving ? h.p.x : drift, 0.65)
            h.goal = h.p
        }
        bot.p = start
        bot.goal = start
        bot.pose = stage.skill == .block ? "spike" : "hit"
        bot.poseTime = 0.6
        if sport == .volley, let mate = e.players.first(where: { $0.member.team == h.member.team && $0 !== h }) {
            mate.p = Vec(2.2, 2.1)
            mate.goal = mate.p
        }
        let ball = e.ball
        ball.p = start
        ball.z = startZ
        ball.velocity = (dest - start) * (1 / time)
        ball.vz = (endZ - startZ + 0.5 * e.config.gravity * time * time) / time
        ball.active = true
        ball.hitter = bot.member.id
        e.shotSerial += 1
        ball.shot = e.shotSerial
        ball.front = sport == .squash
        ball.previousTeam = bot.member.team
        ball.receiver = h.member.id
        e.expected = e.players.firstIndex { $0 === h } ?? 0
        e.returnTeam = h.member.team
        deadline = e.clock + 9.0
    }

    func botMayPlay(_ e: SportsEngine, _ p: Athlete) -> Bool {
        return pending && (stage.skill == .pass || stage.skill == .set) && p.member.team == human(e).member.team
    }

    func contact(_ e: SportsEngine, _ p: Athlete) {
        let h = human(e)
        if p === h {
            pending = true
            pendingKind = p.volleyKind
            received = true
            if deadline == 0.0 { deadline = e.clock + 9.0 }
        } else if pending && p.member.team == h.member.team && (stage.skill == .pass || stage.skill == .set) {
            let correct = stage.skill == .pass || pendingKind == "volley_spike" || pendingKind == "volley_up"
            resolve(e, correct)
        }
    }

    func front(_ e: SportsEngine, _ x: Double, _ z: Double) {
        if !pending { return }
        let ts = targets()
        var nearest = 0
        var best = Double.greatestFiniteMagnitude
        for i in ts.indices {
            let d = hypot(x - ts[i].x, z - ts[i].y)
            if d < best {
                best = d
                nearest = i
            }
        }
        let found = hypot(x - ts[nearest].x, z - ts[nearest].y) <= radius ? nearest : -1
        let expected = painted.count
        let moved = stage.skill != .move || human(e).steps - initialSteps > 0.6
        let good = found >= 0 && (!shape || !painted.contains(found)) && (stage.skill != .order || found == expected) && moved
        if good && shape { painted.append(found) }
        resolve(e, good)
    }

    func crossed(_ e: SportsEngine) {
        if !pending || sport != .volley || serve || [.pass, .set, .block].contains(stage.skill) { return }
        let moved = stage.skill != .move || human(e).steps - initialSteps > 0.6
        resolve(e, moved && (stage.skill != .spike || pendingKind == "volley_spike"))
    }

    func block(_ e: SportsEngine, _ id: String) {
        if stage.skill == .block && e.player(id)?.member.bot == false { resolve(e, true) }
    }

    func point(_ e: SportsEngine, _ why: String) {
        if serve && sport == .volley && pending && why == "ground" {
            let t = targets()[0]
            resolve(e, (e.ball.p - t).length() <= radius)
        } else {
            resolve(e, false)
        }
    }

    func resolve(_ e: SportsEngine, _ good: Bool) {
        if deadline == 0.0 && !e.ball.active { return }
        if good {
            successes += 1
            lastGood = e.clock
            e.event("practice_good")
        } else {
            mistakes += 1
            if stage.streak { successes = 0 }
            e.event("practice_miss")
        }
        attempts += 1
        pending = false
        deadline = 0.0
        e.ball.active = false
        e.phase = .rally
        nextAt = e.clock + 1.35
        for it in e.players {
            it.goal = it.p
            it.velocity = Vec()
        }
        if won || failed { finish(e) }
    }

    private func finish(_ e: SportsEngine) {
        e.phase = .finished
        e.winner = won ? 0 : 1
        e.ball.active = false
        e.phaseTime = 0.0
        e.event("finished", "", String(e.winner))
    }
}
