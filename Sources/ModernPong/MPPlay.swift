import Foundation

/// Android `PongContactGeometry`: the table-relative receiving plane shared by physics, prediction and the swing.
enum MPContactGeometry {
    static let endInset = 0.04, lateralReach = 0.22, preparationInset = 0.28
    static func baseline(_ team: Int) -> Double { team == 0 ? 1 - endInset : endInset }
    static func distanceToEnd(_ team: Int, _ y: Double) -> Double { team == 0 ? 1 - y : y }
    static func preparation(_ team: Int, _ y: Double) -> Double {
        let u = ((preparationInset - distanceToEnd(team, y)) / (preparationInset - endInset)).mpClamp(0, 1)
        return u * u * (3 - 2 * u)
    }
}

/// Android `PongTeamMode` (wire names ALTERNATE / FREE).
enum MPTeamMode: String, CaseIterable {
    case alternate = "ALTERNATE", free = "FREE"
    func title(_ he: Bool) -> String {
        switch self {
        case .alternate: return he ? "חובטים לפי התור" : "Take turns hitting"
        case .free: return he ? "כל אחד יכול לחבוט" : "Either teammate can hit"
        }
    }
    func explanation(_ he: Bool) -> String {
        switch self {
        case .alternate: return he ? "אחרי כל חבטה התור עובר לחבר הקבוצה. רק השחקן המסומן יכול להחזיר את הכדור. כל אחד שומר על הצד שלו." : "After each hit, it is your teammate’s turn. Only the highlighted player can return the ball. Each player covers their own side."
        case .free: return he ? "שניכם יכולים להחזיר את הכדור. כל אחד שומר על הצד שלו ומחזיר כדורים שבטווח שלו." : "Either teammate can return the ball. Cover your own side and hit the balls within your reach."
        }
    }
}

/// Android `PongActor`: one player standing behind an end line.
struct MPActor: Equatable {
    let character: String; let team: Int; let human: Bool
    var at: MPPoint; var goal: MPPoint; var swing = 0.0; var backhand = false; var contacts = 0
    init(_ character: String, _ team: Int, _ human: Bool, _ at: MPPoint) { self.character = character; self.team = team; self.human = human; self.at = at; goal = at }
}
/// Android `PongMark`: a paint splash where the ball really bounced.
struct MPMark: Equatable { var at: MPPoint; var team: Int }

/// Android `PongSkill`.
enum MPSkill { case serve, returning, direction, backhand, forehand, paint, shape, defend, territoryServe, territoryRally, teamAlternate, teamFree }

/// Android `PongStage`: one daily-journey challenge.
struct MPStage {
    let id: String, en: String, he: String, skill: MPSkill
    let base: Int, streak: Bool, fast: Bool, small: Bool, pattern: Int
    init(_ id: String, _ en: String, _ he: String, _ skill: MPSkill, _ base: Int = 8, streak: Bool = false, fast: Bool = false, small: Bool = false, pattern: Int = 0) {
        self.id = id; self.en = en; self.he = he; self.skill = skill; self.base = base; self.streak = streak; self.fast = fast; self.small = small; self.pattern = pattern
    }
    var serve: Bool { skill == .serve || skill == .territoryServe }
    var team: Bool { skill == .teamAlternate || skill == .teamFree }
    var territory: Bool { skill == .territoryServe || skill == .territoryRally }
    var cooperative: Bool { !territory && skill != .defend }
    func title(_ hebrew: Bool) -> String { hebrew ? he : en }
    /// Later cycles ask for a little more (Android `goal`).
    func goal(_ cycle: Int) -> Int { base + (cycle <= 0 ? 0 : (base % 2 == 0 ? 2 : 3) + 2 * min(cycle - 1, 7)) }
    func quality(_ b: MPBot) -> Int {
        switch skill {
        case .serve, .territoryServe: return b.serveSkill * 5 + b.accuracy * 2
        case .backhand: return b.backhandSkill * 5 + b.accuracy * 2 + b.reaction
        case .defend: return b.power * 4 + b.accuracy * 3
        default: return b.accuracy * 4 + b.reaction * 2 + b.agility
        }
    }
    /// A cooperative stage starts with the most accurate feeder; an opposing one with the gentlest opponent.
    func partner(_ cycle: Int, exclude: Set<String>) -> MPHousePlayer {
        let sorted = MPRoster.all.filter { !exclude.contains($0.id) }.sorted { a, b in
            let qa = quality(a.profile), qb = quality(b.profile)
            return qa != qb ? qa < qb : a.id < b.id
        }
        let list = cooperative ? Array(sorted.reversed()) : sorted
        guard !list.isEmpty else { return MPRoster.all[0] }
        return list[min(max(cycle, 0), list.count - 1)]
    }
    func briefing(_ hebrew: Bool) -> String {
        if hebrew {
            switch skill {
            case .serve: return "הקישו על האי הזהוב כדי להגיש אליו. הכדור חייב לקפוץ פעם בצד שלכם ואז לנחות בתוך האי בצד השני. רק פגיעה באי נספרת; החטאה משתמשת בניסיון אחד. אחרי שלוש החטאות אפשר לנסות שוב."
            case .returning: return "גררו את הדמות אל הכדור. אחרי הקפיצה בצד שלכם, הקישו על יעד בצד הרחוק כדי להחזיר. רק ההחזרות שלכם נספרות."
            case .direction: return "האי הזהוב מציג לאן לכוון. זוזו לכדור והקישו על האי בזמן ההחזרה. הוא יחליף מקום אחרי כל הצלחה."
            case .backhand: return "השותף מוסר לצד שמאל. השאירו את הכדור משמאל לגוף וחבטו בגב כף היד. כוונו לאי הזהוב."
            case .forehand: return "השותף מוסר לצד ימין. השאירו את הכדור מימין לגוף וחבטו בכף היד. כוונו לאי הזהוב."
            case .paint: return "החזירו כדורי צבע אל האי הזהוב. כתם מופיע רק במקום שבו הכדור באמת קפץ. האי זז אחרי פגיעה."
            case .shape: return "צבעו את הצורה: כוונו לעיגול הזהוב הבא. צריך לפגוע בכל חלק חדש; אותה נקודה אינה צובעת פעמיים."
            case .defend: return "שמרו על הצד שלכם: זוזו והחזירו את הכדורים לפני הקפיצה השנייה. מתחילים מול תוקף עדין יותר."
            case .territoryServe: return "קרב צבע בהגשות בלבד, 90 שניות. אחרי כל הגשה שלכם היריב מגיש. צבעו שטח חדש בצד השני. בסוף משווים את אחוז השטח שכבשתם."
            case .territoryRally: return "קרב צבע עם החזרות, 90 שניות. כל קפיצה ראשונה מחליפה את צבע השטח. זוזו, החזירו וכבשו יותר שטח מהיריב."
            case .teamAlternate: return "שניים מול שניים: אתם וחבר הקבוצה חובטים בתורות. הישארו בצד שלכם לצד חבר הקבוצה. הטבעת מראה מי צריך לחבוט; אי אפשר לחבוט פעמיים ברצף."
            case .teamFree: return "שניים מול שניים: כל אחד יכול להחזיר. אתם שומרים על הצד שלכם וחבר הקבוצה על שלו. כל אחד נשאר בנתיב שלו; אי אפשר לחצות את חבר הקבוצה."
            }
        }
        switch skill {
        case .serve: return "Tap the golden island to serve towards it. Bounce once on your half, then land inside the island on the far half. Only a landing inside counts; a miss uses one attempt. After three misses you can retry."
        case .returning: return "Drag your player toward the ball. After its bounce on your half, tap a far-side target to return. Only your own returns count."
        case .direction: return "The golden island shows where to aim. Move to the ball and tap the island as you return. It changes after each success."
        case .backhand: return "Your partner feeds the left side. Keep the ball to the left of your body and use a backhand. Aim for the golden island."
        case .forehand: return "Your partner feeds the right side. Keep the ball to the right of your body and use a forehand. Aim for the golden island."
        case .paint: return "Return paint balls onto the golden island. Paint appears where the ball really bounces. The island moves after a hit."
        case .shape: return "Color the shape: aim at the next golden circle. Hit every new piece; hitting the same spot twice does not fill another piece."
        case .defend: return "Protect your half: move and return the ball before its second bounce. Begin against a gentler attacker."
        case .territoryServe: return "Serve-only paint battle, 90 seconds. Your opponent serves after each of your serves. Paint new areas on the other half. At the end, compare the percentage of enemy territory captured."
        case .territoryRally: return "Paint rally, 90 seconds. Each first bounce changes the area's owner. Move, return and capture more territory than your opponent."
        case .teamAlternate: return "Two against two: take turns hitting with your teammate. Stay on your own side beside your teammate. The ring shows whose turn it is; nobody may hit twice in a row."
        case .teamFree: return "Two against two: either teammate may return. Each player covers their own side beside their teammate. You cannot cross into your teammate's lane."
        }
    }
    func role(_ he: Bool) -> String {
        if cooperative { return he ? "זהו שותף לאימון. מתחילים עם המוסר המדויק ביותר למיומנות הזאת. במסלולים הבאים השותף פחות מדויק, אך המסירות נשארות בהישג יד." : "This is your practice partner. Start with the most accurate feeder for this skill. Later cycles use less precise partners, while feeds stay reachable." }
        return he ? "זהו יריב. מתחילים מול יריב עדין; במסלולים הבאים מתחזקים הכישורים המתאימים לאתגר הזה." : "This is your opponent. Start gently; later cycles increase the skills relevant to this challenge."
    }
}
/// Android `PongJourney`: thirty stages, repeated in harder cycles.
enum MPJourney {
    static let stages: [MPStage] = [
        MPStage("serve", "Clean serves", "הגשות נקיות", .serve),
        MPStage("return", "Keep it going", "ממשיכים להחזיר", .returning, 6),
        MPStage("serve_paint", "Serve and paint", "מגישים וצובעים", .territoryServe),
        MPStage("direction", "Call the direction", "מכוונים לאי", .direction, 6),
        MPStage("paint", "Moving paint islands", "איי צבע נעים", .paint),
        MPStage("serve_streak", "Serving rhythm", "קצב הגשות", .serve, 8, streak: true),
        MPStage("forehand", "Forehand rhythm", "קצב כף היד", .forehand, 6),
        MPStage("paint_rally", "Court takeover", "כובשים את השולחן", .territoryRally),
        MPStage("backhand", "Backhand rhythm", "קצב גב כף היד", .backhand, 6),
        MPStage("triangle", "Paint a triangle", "צובעים משולש", .shape, 6, pattern: 1),
        MPStage("speed", "A little quicker", "קצת יותר מהר", .returning, 10, fast: true),
        MPStage("backhand_aim", "Backhand direction", "מכוונים בגב כף היד", .backhand, 8, small: true),
        MPStage("defend", "Guard your court", "שומרים על הצד שלכם", .defend, 10),
        MPStage("steady", "Steady returns", "החזרות יציבות", .returning, 10, streak: true),
        MPStage("star", "Light the star", "מאירים את הכוכב", .shape, 10, pattern: 2),
        MPStage("team_turn", "Take turns together", "חובטים יחד בתורות", .teamAlternate, 6),
        MPStage("team_free", "Cover the table", "מכסים את השולחן", .teamFree, 6),
        MPStage("small", "Little paint islands", "איי צבע קטנים", .paint, 8, small: true),
        MPStage("serve_precision", "Golden serves", "הגשות זהב", .serve, 10, small: true),
        MPStage("backhand_streak", "Backhand streak", "רצף גב כף היד", .backhand, 10, streak: true),
        MPStage("forehand_streak", "Forehand streak", "רצף כף היד", .forehand, 10, streak: true),
        MPStage("diamond", "Diamond trail", "שביל היהלום", .shape, 8, pattern: 3),
        MPStage("defend_fast", "Quick defender", "מגן זריז", .defend, 12, fast: true),
        MPStage("team_move", "Make room for your friend", "מפנים מקום לחבר", .teamAlternate, 8, fast: true),
        MPStage("team_sides", "Side by side", "זה לצד זה", .teamFree, 8, fast: true),
        MPStage("direction_fast", "Quick aim", "מכוונים בזריזות", .direction, 12, fast: true),
        MPStage("backhand_fast", "Quick backhands", "גב כף היד בזריזות", .backhand, 12, fast: true),
        MPStage("paint_small", "Paint explorer", "מגלים צבעים", .paint, 12, small: true),
        MPStage("star_small", "Star artist", "אמן הכוכבים", .shape, 10, small: true, pattern: 2),
        MPStage("final", "Rally star", "כוכב ההחזרות", .returning, 16, streak: true, fast: true)
    ]
    static func stage(_ step: Int) -> MPStage { stages[((step % stages.count) + stages.count) % stages.count] }
}

/// Android `PongPaint`: equal-area cells change owner instead of piling up splashes. Rows 0–15 are the far half.
struct MPPaint: Equatable {
    static let cols = 32, rows = 32
    var owners: [Int] = (0..<(32 * 32)).map { $0 / 32 < 16 ? 1 : 0 }
    mutating func paint(_ at: MPPoint, _ team: Int, radius: Double = 0.105) {
        for y in 0..<MPPaint.rows { for x in 0..<MPPaint.cols {
            let cx = (Double(x) + 0.5) / Double(MPPaint.cols), cy = (Double(y) + 0.5) / Double(MPPaint.rows)
            if hypot(cx - at.x, cy - at.y) <= radius { owners[y * MPPaint.cols + x] = team }
        } }
    }
    /// Share of the opponent's half that `team` owns.
    func coverage(_ team: Int) -> Double {
        let half = team == 0 ? 0..<(MPPaint.rows / 2) : (MPPaint.rows / 2)..<MPPaint.rows
        var count = 0
        for y in half { for x in 0..<MPPaint.cols where owners[y * MPPaint.cols + x] == team { count += 1 } }
        return Double(count) / Double(MPPaint.cols * MPPaint.rows / 2)
    }
}

/// Android `PongRallyEnding`: the ball keeps moving for 1.65 s after the referee's decision. It awards nothing.
struct MPRallyEnding: Equatable {
    var position: MPPoint, height: Double, velocity: MPPoint, lift: Double
    let fault: MPFault, winner: Int
    var remaining = 1.65
    mutating func advance(_ dt: Double, gravity: Double) {
        if remaining <= 0 { return }
        let step = min(dt, remaining); remaining = max(0, remaining - step)
        position = .init(position.x + velocity.x * step, position.y + velocity.y * step)
        height += lift * step - 0.5 * gravity * step * step; lift -= gravity * step
        let floor = position.inside ? 0 : -1.25
        if height < floor { height = floor; lift = abs(lift) * 0.55; velocity = .init(velocity.x * 0.83, velocity.y * 0.83) }
    }
    func message(_ he: Bool, ownTeam: Int = 0) -> String {
        let why: String
        switch fault {
        case .net: why = he ? "הכדור פגע ברשת" : "Ball hit the net"
        case .secondBounce: why = he ? "הכדור קפץ פעמיים" : "Second bounce"
        case .unreturned: why = he ? "הכדור לא הוחזר" : "Ball was not returned"
        case .illegalServe: why = he ? "הגשה לא חוקית" : "Serve fault"
        default: why = he ? "הכדור יצא מחוץ לשולחן" : "Ball went out"
        }
        let point = he ? (winner == ownTeam ? "נקודה לקבוצה שלכם" : "נקודה לקבוצה היריבה") : (winner == ownTeam ? "Your team's point" : "Other team's point")
        return why + " · " + point
    }
    var wire: MPWire { ["x": position.x, "y": position.y, "z": height, "vx": velocity.x, "vy": velocity.y, "lift": lift, "fault": fault.rawValue, "winner": winner, "remaining": remaining] }
    static func from(_ f: MPFlight, _ r: MPResolution) -> MPRallyEnding {
        let v = r.fault == .net ? MPPoint(f.velocity.x * 0.35, -f.velocity.y * 0.22) : f.velocity
        let lift = f.height <= 0.001 ? abs(f.lift) * 0.6 : f.lift
        return .init(position: f.position, height: max(0, f.height), velocity: v, lift: lift, fault: r.fault, winner: r.winner == .child ? 0 : 1)
    }
    static func read(_ w: MPWire) throws -> MPRallyEnding {
        guard let fault = MPFault(rawValue: (w["fault"] as? String) ?? "") else { throw MPError.permission }
        return .init(position: .init(MPPlayWire.decimal(w, "x"), MPPlayWire.decimal(w, "y")), height: MPPlayWire.decimal(w, "z"),
                     velocity: .init(MPPlayWire.decimal(w, "vx"), MPPlayWire.decimal(w, "vy")), lift: MPPlayWire.decimal(w, "lift"),
                     fault: fault, winner: MPPlayWire.int(w, "winner"), remaining: MPPlayWire.decimal(w, "remaining"))
    }
}

/// Android `Wire.number / decimal / flag` over decoded JSON or RTDB values.
enum MPPlayWire {
    static func decimal(_ w: MPWire, _ key: String, _ fallback: Double = 0) -> Double { (w[key] as? NSNumber)?.doubleValue ?? fallback }
    static func int(_ w: MPWire, _ key: String, _ fallback: Int = 0) -> Int { (w[key] as? NSNumber)?.intValue ?? fallback }
    static func int64(_ w: MPWire, _ key: String, _ fallback: Int64 = 0) -> Int64 { (w[key] as? NSNumber)?.int64Value ?? fallback }
    static func flag(_ w: MPWire, _ key: String) -> Bool { MPReceptionAssist.flag(w[key]) == true }
    static func list(_ value: Any?) -> [Any] {
        if let list = value as? [Any] { return list }
        // A keyed map with dense numeric keys (RTDB) reads as a list.
        let map = MPCodec.map(value)
        return map.keys.compactMap { Int($0) }.sorted().compactMap { map[String($0)] }
    }
    static func numbers(_ value: Any?) throws -> [Double] {
        try list(value).map { item -> Double in
            guard let n = item as? NSNumber else { throw MPError.permission }
            return n.doubleValue
        }
    }
    static func ints(_ value: Any?) throws -> [Int] { try numbers(value).map { Int($0) } }
    static func point(_ value: Any?) throws -> MPPoint {
        let xy = try numbers(value)
        guard xy.count == 2, xy[0].isFinite, xy[1].isFinite else { throw MPError.permission }
        return .init(xy[0], xy[1])
    }
}

/// Android `PongPlay`: daily-journey practice and two-against-two team play around the shared Modern flight model.
/// Its `save()` wire is the snapshot body of the online doubles protocol, so it matches Android key for key.
final class MPPlay {
    let step: Int, mode: MPTeamMode, roster: [String], openPaint: Bool, humanSeats: Set<Int>, seed: Int64
    var reception = MPReceptionAssist()
    let stage: MPStage?
    let cycle: Int, team: Bool, alternate: Bool, goal: Int
    let tuning: MPTuning
    var actors: [MPActor]
    private var botTried: [Bool], botResponses: [Int], botPreviousX: [Double?]
    private let botTunings: [MPTuning]
    var seatAims: [MPPoint], seatArmedUntil: [Double]
    var paint = MPPaint(), marks: [MPMark] = [], painted: [Int] = []
    var clock = 0.0, paused = false, started = false, successes = 0, mistakes = 0, attempts = 0, won = false, ended = false
    private(set) var flight: MPFlight?
    private(set) var ending: MPRallyEnding?
    private(set) var waitingServe = false
    var nextAt = 1.0, server = 0, hitter = 0, nextHitter: [Int]
    var points = [0, 0]
    var aim: MPPoint { get { seatAims[0] } set { seatAims[0] = newValue } }
    var armedUntil: Double { get { seatArmedUntil[0] } set { seatArmedUntil[0] = newValue } }
    var lastHumanBackhand = false, lastContact = -10.0, contactAt = MPPoint(0.5, 0.88), contactHeight = 0.24
    var pendingHuman = false, notice = "", eventSerial = 0, lastEvent = "", rally = 0
    /// Sounds for this table as MPAudio names (Android `Cue.SWING`, `CONTACT`, `APPLAUSE`).
    var onSound: (([String]) -> Void)?
    var remaining: Double { max(90 - clock, 0) }
    var human: MPActor { actors[0] }

    init(step: Int = -1, mode: MPTeamMode = .alternate, roster: [String] = ["miniko", "minik", "mia", "june"], openPaint: Bool = false,
         humanSeats: Set<Int> = [0], seed: Int64 = Int64.random(in: 1...Int64.max)) {
        self.step = step; self.mode = mode; self.openPaint = openPaint; self.seed = seed
        var ids = roster.filter { MPRoster.find($0) != nil }
        let fallback = ["miniko", "minik", "mia", "june"]
        while ids.count < 4 { ids.append(fallback[ids.count]) }
        let r = Array(ids.prefix(4))
        self.roster = r
        let stage: MPStage?
        if step >= 0 { stage = MPJourney.stage(step) }
        else if openPaint { stage = MPStage("free_paint", "Paint playground", "מגרש הצבעים", .paint) }
        else { stage = nil }
        self.stage = stage
        let cycle = max(step / 30, 0)
        self.cycle = cycle
        let team = stage?.team ?? !openPaint
        self.team = team
        alternate = stage.map { $0.skill == .teamAlternate } ?? (mode == .alternate)
        goal = stage?.goal(cycle) ?? 7
        // Doubles receive behind the end line; a firmer table rebound carries short serves into racket reach.
        var t = MPTuning.values(.easy)
        if team { t.bounceRestitution = 0.86 }
        tuning = t
        let table: [MPActor] = team
            ? [MPActor(r[0], 0, humanSeats.contains(0), .init(0.3, 0.88)), MPActor(r[1], 0, humanSeats.contains(1), .init(0.7, 0.88)),
               MPActor(r[2], 1, humanSeats.contains(2), .init(0.3, 0.12)), MPActor(r[3], 1, humanSeats.contains(3), .init(0.7, 0.12))]
            : [MPActor(r[0], 0, humanSeats.contains(0), .init(0.5, 0.88)), MPActor(r[1], 1, humanSeats.contains(1), .init(0.5, 0.12))]
        actors = table
        let count = table.count
        // Practice has one learner (Android `require`); seats outside the table are ignored.
        self.humanSeats = step >= 0 ? [0] : humanSeats.filter { $0 >= 0 && $0 < count }
        botTried = Array(repeating: false, count: count); botResponses = Array(repeating: 0, count: count)
        botPreviousX = Array(repeating: nil, count: count)
        botTunings = table.map { (MPRoster.find($0.character) ?? MPRoster.all[0]).profile.tuning(.easy, houseControls: true) }
        seatAims = table.map { MPPoint(0.5, $0.team == 0 ? 0.25 : 0.75) }
        seatArmedUntil = Array(repeating: -1, count: count)
        nextHitter = [0, team ? 2 : 1]
    }
    var targeted: Bool {
        guard let stage else { return false }
        return [MPSkill.serve, .direction, .paint, .shape, .backhand, .forehand].contains(stage.skill) || stage.small
    }
    var radius: Double { (stage?.small == true ? 0.085 : 0.145) * (1 - Double(min(cycle, 7)) * 0.025) }
    func targets() -> [MPPoint] {
        guard let stage, stage.skill == .shape else {
            let i = successes % 3
            return [MPPoint([0.5, 0.24, 0.76][i], [0.25, 0.32, 0.19][i])]
        }
        return (0..<goal).map { i in
            let a = 2 * Double.pi * Double(i) / Double(goal) - Double.pi / 2
            let r = stage.pattern == 2 && i % 2 == 1 ? 0.48 : 1.0
            if stage.pattern == 1 {
                let v = [MPPoint(0.5, 0.11), MPPoint(0.85, 0.4), MPPoint(0.15, 0.4)]
                let t = Double(i) * 3 / Double(goal), k = Int(t), next = v[(k + 1) % 3]
                return MPPoint(v[k].x + (next.x - v[k].x) * (t - Double(k)), v[k].y + (next.y - v[k].y) * (t - Double(k)))
            }
            return MPPoint(0.5 + cos(a) * 0.32 * r, 0.26 + sin(a) * 0.15 * r)
        }
    }
    var target: MPPoint { targets()[stage?.skill == .shape ? min(painted.count, goal - 1) : 0] }
    func start() { started = true }
    func move(_ to: MPPoint) { moveSeat(0, to) }
    func moveSeat(_ seat: Int, _ to: MPPoint) {
        guard !paused, !ended, humanSeats.contains(seat), to.x.isFinite, to.y.isFinite else { return }
        actors[seat].goal = .init(laneX(seat, to.x), baselineY(actors[seat].team))
    }
    @discardableResult func tap(_ to: MPPoint) -> Bool { tapSeat(0, to) }
    @discardableResult func tapSeat(_ seat: Int, _ to: MPPoint) -> Bool {
        guard !paused, !ended, started, humanSeats.contains(seat), to.x.isFinite, to.y.isFinite else { return false }
        let side = actors[seat].team
        seatAims[seat] = .init(to.x.mpClamp(0.07, 0.93), to.y.mpClamp(side == 0 ? 0.08 : 0.57, side == 0 ? 0.43 : 0.92))
        if waitingServe {
            let expected = stage == nil ? nextHitter[server] : 0
            if seat != expected { return false }
            serve(seat, seatAims[seat]); return true
        }
        onSound?(["minik_kick2"]); seatArmedUntil[seat] = clock + 0.42
        return attemptSeat(seat)
    }
    private func event(_ kind: String) {
        lastEvent = kind; eventSerial += 1
        switch kind {
        case "serve", "contact": onSound?(["minik_kick2", "minik_kick"])
        case "win": onSound?(["minik_claps"])
        default: break
        }
    }
    private func serve(_ who: Int, _ target: MPPoint) {
        let side: MPSide = actors[who].team == 0 ? .child : .minik
        let profile = (MPRoster.find(actors[who].character) ?? MPRoster.all[0]).profile
        let fast = stage?.fast == true ? 0.13 : 0.0
        let opposing = stage?.cooperative == false ? Double(profile.power) * 0.012 : 0.0
        let pace = who == 0 ? tuning.ballBaseSpeed : min(tuning.ballBaseSpeed + fast + Double(min(cycle, 8)) * 0.008 + opposing, 0.7)
        var plan = MPShots.serve(target, side: side, tuning: tuning)
        plan.speed = pace
        // The target is the visible aim; assistance controls loft, not a hidden lateral remapping.
        plan.second = target
        plan.first = .init((actors[who].at.x + target.x) / 2, team ? (side == .child ? 0.90 : 0.10) : (side == .child ? 0.72 : 0.28))
        plan.start = .init(actors[who].at.x, side == .child ? 0.96 : 0.04)
        let launched = MPFlight(plan, tuning, startHeight: 0.25)
        flight = launched
        lastContact = clock; contactAt = launched.position; contactHeight = launched.height
        resetBotTries(); waitingServe = false; hitter = who; actors[who].swing = 0.3; actors[who].contacts += 1
        pendingHuman = who == 0; lastHumanBackhand = false
        if team && alternate { nextHitter[actors[who].team] = partner(who) }
        event("serve")
    }
    private func resetBotTries() { botTried = Array(repeating: false, count: actors.count) }
    private func partner(_ i: Int) -> Int { actors.indices.first { $0 != i && actors[$0].team == actors[i].team } ?? i }
    private func launch() {
        pendingHuman = false; rally = 0; actors[0].goal = actors[0].at; notice = ""
        botResponses = Array(repeating: 0, count: actors.count); botPreviousX = Array(repeating: nil, count: actors.count); resetBotTries()
        guard let stage else {
            let who = nextHitter[server]
            if actors[who].human { waitingServe = true } else { serve(who, botAim(who)) }
            return
        }
        if stage.serve { waitingServe = true; return }
        let who = team ? nextHitter[1] : 1
        let skill = (MPRoster.find(actors[who].character) ?? MPRoster.all[0]).profile
        let drift = min(Double(10 - skill.accuracy) * 0.018 + Double(cycle) * 0.015, 0.2)
        let x: Double
        switch stage.skill {
        case .backhand: x = 0.25
        case .forehand: x = 0.75
        default: x = 0.5 + (attempts % 2 == 0 ? -1 : 1) * drift
        }
        serve(who, team ? botAim(who) : MPPoint(x, 0.75)); pendingHuman = false
    }
    func advance(_ delta: Double) {
        guard started, !paused else { return }
        if var tail = ending { tail.advance(delta, gravity: tuning.gravity); ending = tail.remaining <= 0 ? nil : tail }
        if ended { return }
        // Android: the receiving human (online: any human seat on that side) may slow the shared clock.
        var candidateSeat: Int?, candidateEta = 0.0
        if let f0 = flight, !f0.resolved {
            let side = f0.striker == .minik ? 0 : 1
            for i in humanSeats.sorted() where actors[i].team == side && (!team || !alternate || nextHitter[side] == i) {
                if let eta = MPReceptionAssist.eta(f0.position, f0.velocity, actors[i].at), eta >= -0.12, candidateSeat == nil || eta < candidateEta {
                    candidateSeat = i; candidateEta = eta
                }
            }
        }
        let dt = reception.advance(delta, seat: candidateSeat, eta: candidateSeat == nil ? nil : candidateEta); clock += dt
        if stage?.territory == true && clock >= 90 { won = paint.coverage(0) > paint.coverage(1); ended = true; event(won ? "win" : "retry"); return }
        for i in actors.indices { actors[i].swing = max(actors[i].swing - dt, 0) }
        planBots(); moveActors(dt)
        guard var f = flight else {
            if ending == nil && !waitingServe && clock >= nextAt { launch() }
            return
        }
        let outcome = f.advance(dt, tuning); flight = f
        if let outcome, outcome.bounced {
            let at = outcome.point ?? f.position, owner = f.striker == .child ? 0 : 1
            if stage?.territory == true { paint.paint(at, owner); mark(at, owner) }
            if outcome.recipient == .minik && pendingHuman {
                pendingHuman = false
                if stage?.territory != true {
                    scoreTarget(at)
                    if stage != nil && !team { flight = nil; attempts += 1; nextAt = clock + 1; return }
                }
            }
            if stage?.skill == .territoryServe && outcome.recipient != nil {
                if owner == 0 { flight = nil; serve(1, botAim(1)); pendingHuman = false } else { flight = nil; attempts += 1; nextAt = clock + 1 }
                return
            }
        }
        if let resolution = outcome?.resolution { resolve(resolution); return }
        for seat in humanSeats.sorted() where seatArmedUntil[seat] >= clock { _ = attemptSeat(seat) }
        guard let live = flight else { return }
        if live.receiver {
            let receiving = live.striker == .minik ? 0 : 1
            let bots = actors.indices.filter { actors[$0].team == receiving && !actors[$0].human }
            if let candidate = bots.first(where: { canHit($0) }), !botTried[candidate] { botReturn(candidate) }
        }
    }
    private func mark(_ at: MPPoint, _ owner: Int) {
        guard let skill = stage?.skill, [MPSkill.paint, .shape, .territoryServe, .territoryRally].contains(skill) else { return }
        marks.append(.init(at: at, team: owner))
        if marks.count > 160 { marks.removeFirst() }
    }
    private func scoreTarget(_ at: MPPoint) {
        mark(at, 0)
        var good = !targeted || at.distance(target) <= radius
        if good, let skill = stage?.skill {
            if skill == .backhand { good = lastHumanBackhand } else if skill == .forehand { good = !lastHumanBackhand }
        }
        if good {
            successes += 1
            if stage?.skill == .shape { painted.append(painted.count) }
            event("good")
        } else { miss() }
        if let stage, !stage.territory, !openPaint, successes >= goal { won = true; ended = true; event("win") }
    }
    private func miss() {
        mistakes += 1
        if stage?.streak == true { successes = 0 }
        event("miss")
        if mistakes >= 3 && !openPaint { ended = true; won = false; event("retry") }
    }
    private func resolve(_ result: MPResolution) {
        ending = flight.map { MPRallyEnding.from($0, result) }
        if let stage {
            if !stage.territory && result.winner == .minik { miss() }
        } else {
            let winner = result.winner == .child ? 0 : 1
            points[winner] += 1
            if points[winner] >= goal { ended = true; won = winner == 0; event(won ? "win" : "retry") }
            server = (points[0] + points[1]) / 2 % 2
        }
        flight = nil; waitingServe = false; attempts += 1; nextAt = clock + 1.65; seatArmedUntil = Array(repeating: -1, count: actors.count)
    }
    private func canHit(_ i: Int) -> Bool {
        guard let f = flight else { return false }
        let a = actors[i], side: MPSide = a.team == 0 ? .child : .minik
        if !f.receiver || f.striker == side || f.resolved || (team && alternate && nextHitter[a.team] != i) { return false }
        if !f.position.onSide(side) || f.height < 0.025 || f.height > 1.2 { return false }
        // Bodies stand behind the baseline: a return waits for the ball to reach the racket there.
        let atBaseline = MPContactGeometry.distanceToEnd(a.team, f.position.y) <= MPContactGeometry.endInset
        return abs(f.position.x - a.at.x) < MPContactGeometry.lateralReach && atBaseline
    }
    private func attemptSeat(_ seat: Int) -> Bool {
        if !canHit(seat) { return false }
        hit(seat, seatAims[seat]); seatArmedUntil[seat] = -1
        return true
    }
    private func botReturn(_ i: Int) {
        if stage != nil { hit(i, botAim(i)); return }
        botTried[i] = true
        guard let f = flight else { return }
        // Normal-match character percentages, once per incoming ball, from a seed that saved games reproduce.
        let t = botTunings[i], profile = t.profile
        let x = actors[i].team == 1 ? f.position.x : 1 - f.position.x
        let zone = MPZone.at(x), serving = rally == 0
        let base = serving ? profile.serveReceive[zone.rawValue] : profile.chance(zone, cross: false)
        let cross = serving ? base : profile.chance(zone, cross: true)
        let mixed = Int64(attempts) &* 1000003 &+ Int64(rally) &* 1009 &+ Int64(i) &* 9176
        var random = MPKotlinRandom(seed: seed ^ mixed)
        let response = botResponses[i]
        botResponses[i] += 1
        let answerRoll = random.nextDouble(), qualityRoll = random.nextDouble()
        guard let contact = MPShots.aiContact(x: x, speed: hypot(f.velocity.x, f.velocity.y), depth: MPContactGeometry.endInset, tuning: t, base: base, cross: cross,
                                              previousX: botPreviousX[i], response: response, answerRoll: answerRoll, qualityRoll: qualityRoll, pace: 0.65) else { return }
        botPreviousX[i] = x
        let target = botAim(i)
        // Poor returns visibly go long and are adjudicated by the flight, never awarded as good shots.
        hit(i, contact.quality >= 0.14 ? target : MPPoint(target.x, actors[i].team == 0 ? -0.15 : 1.15))
    }
    private func hit(_ i: Int, _ target: MPPoint) {
        guard var f = flight else { return }
        actors[i].backhand = f.position.x < actors[i].at.x - 0.012
        contactAt = f.position; contactHeight = f.height
        // Android Flight.hit(practice = true), whose pace and loft this table replaces below.
        f.height = max(f.height, 0.055); f.striker = actors[i].team == 0 ? .child : .minik
        f.receiver = false; f.serve = nil; f.spin = 0
        let speed = stage?.fast == true ? min(0.75 + Double(successes) * 0.022 + Double(cycle) * 0.02, 1.08) : (team ? 0.82 : 0.65)
        var time = (f.position.distance(target) / speed).mpClamp(team ? 0.60 : 0.7, 1.65)
        let fraction = (0.5 - f.position.y) / (target.y - f.position.y)
        if fraction >= 0.01 && fraction <= 0.99 {
            let clear = max(0, tuning.netHeight + 0.045 - f.height * (1 - fraction))
            time = max(time, sqrt(2 * clear / (tuning.gravity * fraction * (1 - fraction))))
        }
        f.velocity = .init((target.x - f.position.x) / time, (target.y - f.position.y) / time)
        f.lift = (0.5 * tuning.gravity * time * time - f.height) / time
        flight = f
        resetBotTries(); hitter = i; actors[i].swing = 0.34; actors[i].contacts += 1; lastContact = clock; rally += 1; pendingHuman = i == 0
        if i == 0 { lastHumanBackhand = actors[i].backhand }
        if team && alternate {
            nextHitter[actors[i].team] = partner(i)
            actors[i].goal = .init(actors[i].at.x < 0.5 ? 0.12 : 0.88, actors[i].team == 0 ? 0.95 : 0.05)
        }
        event("contact")
    }
    private func botAim(_ i: Int) -> MPPoint {
        let a = actors[i], profile = (MPRoster.find(a.character) ?? MPRoster.all[0]).profile
        let cooperative = stage?.cooperative == true
        let amount = cooperative ? min(Double(10 - profile.accuracy) * 0.017 + Double(cycle) * 0.01, 0.2) : 0.18 + Double(profile.accuracy) * 0.012
        let receiving = a.team == 1 ? 0 : 1
        let activeIndex = team && alternate ? nextHitter[receiving] : (receiving == 0 ? 0 : (team ? 2 : 1))
        let x: Double
        if stage?.territory == true { x = 0.5 + sin(Double(attempts) * 2.399 + Double(rally) * 1.7) * (0.12 + Double(profile.accuracy) * 0.024) }
        else if team && alternate { x = actors[activeIndex].at.x }
        else if team && cooperative { x = actors[receiving == 0 ? ((rally / 2) % 2 == 0 ? 0 : 1) : 2 + (rally / 2) % 2].at.x }
        else if stage?.skill == .backhand { x = human.at.x - 0.13 }
        else if stage?.skill == .forehand { x = human.at.x + 0.13 }
        else { x = 0.5 + ((rally + attempts) % 2 == 0 ? -1.0 : 1.0) * amount }
        let depth = stage?.territory == true ? 0.15 + Double((attempts * 7 + rally * 3) % 11) * 0.019 : 0.25
        let bounceY = a.team == 0 ? depth : 1 - depth
        let contactY = MPContactGeometry.baseline(1 - a.team)
        let from = flight?.position ?? MPPoint(a.at.x, a.team == 0 ? 0.96 : 0.04)
        // Aim along the receiver's racket lane, not at their x on the bounce (that sent angled shots wide).
        let ratio = ((bounceY - from.y) / (contactY - from.y)).mpClamp(0, 1)
        return .init((from.x + (x.mpClamp(0.15, 0.85) - from.x) * ratio).mpClamp(0.10, 0.90), bounceY)
    }
    private func planBots() {
        guard let f = flight else { return }
        let receiving = f.striker == .minik ? 0 : 1
        var forecast = f, target = f.position
        for _ in 0..<360 {
            if forecast.resolved { break }
            _ = forecast.advance(1.0 / 120, tuning)
            if forecast.receiver {
                target = forecast.position
                if MPContactGeometry.distanceToEnd(receiving, target.y) <= MPContactGeometry.endInset { break }
            }
        }
        for i in actors.indices where !actors[i].human {
            let canChase = actors[i].team == receiving && (!team || !alternate || nextHitter[actors[i].team] == i)
            if canChase { actors[i].goal = .init(laneX(i, target.x), baselineY(actors[i].team)) }
        }
    }
    /// Each doubles player owns a half-lane on a fixed baseline; teammates can never cross.
    private func baselineY(_ team: Int) -> Double { team == 0 ? 0.88 : 0.12 }
    private func laneX(_ i: Int, _ x: Double) -> Double {
        if !team { return x.mpClamp(0.07, 0.93) }
        let left = actors.indices.first { actors[$0].team == actors[i].team } == i
        return left ? x.mpClamp(0.09, 0.38) : x.mpClamp(0.62, 0.91)
    }
    private func moveActors(_ dt: Double) {
        for i in actors.indices {
            let a = actors[i], x = laneX(i, a.goal.x)
            let speed = a.human ? 0.85 : 0.35 + Double((MPRoster.find(a.character) ?? MPRoster.all[0]).profile.speed) * 0.035
            let delta = (x - a.at.x).mpClamp(-speed * dt, speed * dt)
            actors[i].at = .init(laneX(i, a.at.x + delta), baselineY(a.team)); actors[i].goal = .init(x, baselineY(a.team))
        }
    }
    /// Android `PongPlay.save()`; version 2 carries every seat's aim and input deadline.
    func save() -> MPWire {
        var w: MPWire = [:]
        w["seed"] = NSNumber(value: seed); w["botTried"] = botTried; w["botResponses"] = botResponses
        w["botPreviousX"] = botPreviousX.map { value -> Any in
            if let value { return value }
            return NSNull()
        }
        w["reception"] = reception.wire; w["version"] = 2; w["humanSeats"] = humanSeats.sorted()
        w["seatAims"] = seatAims.map { [$0.x, $0.y] }; w["seatArmed"] = seatArmedUntil
        w["step"] = step; w["mode"] = mode.rawValue; w["roster"] = roster; w["open"] = openPaint
        w["clock"] = clock; w["successes"] = successes; w["mistakes"] = mistakes; w["attempts"] = attempts; w["won"] = won; w["ended"] = ended
        w["nextAt"] = nextAt; w["server"] = server; w["hitter"] = hitter; w["nextHitter"] = nextHitter; w["points"] = points
        w["aim"] = [aim.x, aim.y]; w["armedUntil"] = armedUntil; w["backhand"] = lastHumanBackhand; w["contact"] = lastContact
        w["contactAt"] = [contactAt.x, contactAt.y]; w["contactHeight"] = contactHeight; w["pending"] = pendingHuman
        w["waiting"] = waitingServe; w["rally"] = rally; w["paint"] = paint.owners; w["painted"] = painted
        w["marks"] = marks.map { mark -> [Any] in [mark.at.x, mark.at.y, mark.team] }
        w["actors"] = actors.map { a -> MPWire in ["x": a.at.x, "y": a.at.y, "gx": a.goal.x, "gy": a.goal.y, "swing": a.swing, "back": a.backhand, "contacts": a.contacts] }
        if let ending { w["ending"] = ending.wire } else { w["ending"] = NSNull() }
        if let flight, let encoded = try? MPCodec.encode(flight) { w["flight"] = encoded } else { w["flight"] = NSNull() }
        return w
    }
    /// Android `PongPlay.restore`. Throws on anything Android would reject.
    static func restore(_ w: MPWire) throws -> MPPlay {
        let version = MPPlayWire.int(w, "version")
        guard (1...2).contains(version) else { throw MPError.permission }
        let ids = MPPlayWire.list(w["roster"]).compactMap { $0 as? String }
        guard ids.count == 4, ids.allSatisfy({ MPRoster.find($0) != nil }) else { throw MPError.permission }
        let step = MPPlayWire.int(w, "step")
        guard (-1...100_000).contains(step) else { throw MPError.permission }
        guard let mode = MPTeamMode(rawValue: (w["mode"] as? String) ?? "") else { throw MPError.permission }
        let seats: Set<Int>
        if version == 1 { seats = [0] } else { seats = try Set(MPPlayWire.ints(w["humanSeats"])) }
        let seed = (w["seed"] as? NSNumber)?.int64Value ?? 1
        let e = MPPlay(step: step, mode: mode, roster: ids, openPaint: MPPlayWire.flag(w, "open"), humanSeats: seats, seed: seed)
        guard e.humanSeats == seats else { throw MPError.permission }
        for (i, v) in MPPlayWire.list(w["botTried"]).enumerated() where i < e.botTried.count { e.botTried[i] = MPReceptionAssist.flag(v) == true }
        for (i, v) in MPPlayWire.list(w["botResponses"]).enumerated() where i < e.botResponses.count { e.botResponses[i] = (v as? NSNumber)?.intValue ?? 0 }
        // RTDB and JSON keep the nulls of `botPreviousX`; a keyed map skips them.
        if let list = w["botPreviousX"] as? [Any] {
            for (i, v) in list.enumerated() where i < e.botPreviousX.count { e.botPreviousX[i] = (v as? NSNumber)?.doubleValue }
        }
        if version == 2 {
            let aims = MPPlayWire.list(w["seatAims"]), armed = try MPPlayWire.numbers(w["seatArmed"])
            guard aims.count == e.actors.count, armed.count == e.actors.count else { throw MPError.permission }
            for i in e.actors.indices {
                e.seatAims[i] = try MPPlayWire.point(aims[i])
                guard armed[i].isFinite else { throw MPError.permission }
                e.seatArmedUntil[i] = armed[i]
            }
        }
        e.reception = try MPReceptionAssist(wire: MPCodec.map(w["reception"]))
        e.clock = MPPlayWire.decimal(w, "clock"); e.successes = MPPlayWire.int(w, "successes"); e.mistakes = MPPlayWire.int(w, "mistakes")
        e.attempts = MPPlayWire.int(w, "attempts"); e.won = MPPlayWire.flag(w, "won"); e.ended = MPPlayWire.flag(w, "ended")
        e.nextAt = MPPlayWire.decimal(w, "nextAt"); e.server = MPPlayWire.int(w, "server"); e.hitter = MPPlayWire.int(w, "hitter")
        e.nextHitter = try MPPlayWire.ints(w["nextHitter"]); e.points = try MPPlayWire.ints(w["points"])
        e.aim = try MPPlayWire.point(w["aim"]); e.armedUntil = MPPlayWire.decimal(w, "armedUntil")
        if let at = w["contactAt"], !(at is NSNull) { e.contactAt = try MPPlayWire.point(at) }
        e.contactHeight = (w["contactHeight"] as? NSNumber)?.doubleValue ?? 0.24
        e.lastHumanBackhand = MPPlayWire.flag(w, "backhand"); e.lastContact = MPPlayWire.decimal(w, "contact")
        e.pendingHuman = MPPlayWire.flag(w, "pending"); e.waitingServe = MPPlayWire.flag(w, "waiting"); e.rally = MPPlayWire.int(w, "rally")
        let owners = try MPPlayWire.ints(w["paint"])
        guard owners.count == e.paint.owners.count, owners.allSatisfy({ (0...1).contains($0) }) else { throw MPError.permission }
        e.paint.owners = owners
        for value in try MPPlayWire.ints(w["painted"]) where !e.painted.contains(value) { e.painted.append(value) }
        for item in MPPlayWire.list(w["marks"]) {
            let m = try MPPlayWire.numbers(item)
            guard m.count >= 3 else { throw MPError.permission }
            e.marks.append(.init(at: .init(m[0], m[1]), team: Int(m[2])))
        }
        for (i, item) in MPPlayWire.list(w["actors"]).enumerated() {
            guard i < e.actors.count else { throw MPError.permission }
            let a = MPCodec.map(item)
            e.actors[i].at = .init(MPPlayWire.decimal(a, "x"), MPPlayWire.decimal(a, "y"))
            e.actors[i].goal = .init(MPPlayWire.decimal(a, "gx"), MPPlayWire.decimal(a, "gy"))
            e.actors[i].swing = MPPlayWire.decimal(a, "swing"); e.actors[i].backhand = MPPlayWire.flag(a, "back"); e.actors[i].contacts = MPPlayWire.int(a, "contacts")
        }
        let ending = MPCodec.map(w["ending"])
        if !ending.isEmpty { e.ending = try MPRallyEnding.read(ending) }
        let flight = MPCodec.map(w["flight"])
        if !flight.isEmpty {
            let restored = try MPCodec.decode(MPFlight.self, flight)
            guard restored.valid else { throw MPError.permission }
            e.flight = restored
        }
        guard e.nextHitter.count == 2, e.nextHitter.allSatisfy({ e.actors.indices.contains($0) }), e.points.count == 2, e.clock.isFinite, e.clock >= 0 else { throw MPError.permission }
        return e
    }
}
