import Foundation

// Android cross/CrossJourney.kt and cross/CrossPractice.kt (MinikCrossPong 5c1aa4d): the daily skill journey, its 30 stages
// and the practice that counts real contacts and landings.

enum CrossSkill: String { case serve, returning, aim, backhand, forehand, shape, defend, paint, pass, set, smash }

/// One journey stage. `base` is the first cycle's goal; `streak` resets the count on a miss, `fast` speeds the feeds, `small`
/// shrinks the targets and `partnerSeat` is the teammate's seat in team stages.
struct CrossStage {
    var id: String
    var en: String
    var he: String
    var skill: CrossSkill
    var base = 8
    var streak = false
    var fast = false
    var small = false
    var partnerSeat = 2
    var cooperative: Bool { skill != .paint && skill != .defend }
    var team: Bool { [CrossSkill.pass, .set, .smash, .paint].contains(skill) }
    var aimed: Bool { [CrossSkill.aim, .backhand, .forehand, .shape].contains(skill) }
    func goal(_ cycle: Int) -> Int { base + (cycle <= 0 ? 0 : (base % 2 == 0 ? 2 : 3)) + 2 * min(7, max(0, cycle - 1)) }
    /// The qualities that matter for this skill.
    func quality(_ p: MPBot) -> Int {
        switch skill {
        case .serve: return p.serveSkill * 5 + p.accuracy * 2
        case .backhand: return p.backhandSkill * 4 + p.accuracy * 3 + p.reaction
        case .defend: return p.power * 3 + p.forehandSkill * 2 + p.reaction
        case .smash, .set: return p.accuracy * 4 + p.reaction * 2 + p.agility
        default: return p.accuracy * 5 + p.speed + p.reaction
        }
    }
    /// A partner starts with the best qualities and later cycles use less precise ones; an opponent starts gentle and grows.
    func bot(_ cycle: Int, exclude: Set<String>, helping: Bool? = nil) -> MPHousePlayer {
        let sorted = MPRoster.all.filter { !exclude.contains($0.id) }.sorted { (quality($0.profile), $0.id) < (quality($1.profile), $1.id) }
        let list = (helping ?? cooperative) ? Array(sorted.reversed()) : sorted
        guard !list.isEmpty else { return MPRoster.all[0] }
        return list[min(list.count - 1, max(0, cycle))]
    }
}

enum CrossJourney {
    static let stages: [CrossStage] = [
        CrossStage(id: "serve", en: "Find the called court", he: "מגישים לשולחן המסומן", skill: .serve, base: 6),
        CrossStage(id: "return", en: "Keep the ball moving", he: "ממשיכים להחזיר", skill: .returning, base: 6),
        CrossStage(id: "aim", en: "Golden islands", he: "איים זהובים", skill: .aim, base: 6),
        CrossStage(id: "serve_streak", en: "Serving rhythm", he: "קצב הגשות", skill: .serve, base: 8, streak: true),
        CrossStage(id: "backhand", en: "Backhand rhythm", he: "קצב גב כף היד", skill: .backhand, base: 6),
        CrossStage(id: "triangle", en: "Paint a triangle", he: "צובעים משולש", skill: .shape, base: 6),
        CrossStage(id: "forehand", en: "Forehand rhythm", he: "קצב כף היד", skill: .forehand, base: 6),
        CrossStage(id: "pass", en: "Pass to your partner", he: "מוסרים לחבר הקבוצה", skill: .pass, base: 5),
        CrossStage(id: "set", en: "Raise it together", he: "מרימים יחד", skill: .set, base: 5),
        CrossStage(id: "smash", en: "Time your smash", he: "מנחיתים בזמן", skill: .smash, base: 5),
        CrossStage(id: "paint_opposite", en: "Partners across the table", he: "שותפים משני צדי השולחן", skill: .paint),
        CrossStage(id: "steady", en: "Steady hands", he: "ידיים יציבות", skill: .returning, base: 10, streak: true),
        CrossStage(id: "star", en: "Light the star", he: "מאירים את הכוכב", skill: .shape, base: 10),
        CrossStage(id: "quick", en: "A little quicker", he: "קצת יותר מהר", skill: .returning, base: 10, fast: true),
        CrossStage(id: "defend", en: "Guard your court", he: "שומרים על השולחן", skill: .defend, base: 10),
        CrossStage(id: "paint_right", en: "Partners on the right", he: "שותפים מצד ימין", skill: .paint, partnerSeat: 1),
        CrossStage(id: "small", en: "Little islands", he: "איים קטנים", skill: .aim, base: 8, small: true),
        CrossStage(id: "backhand_streak", en: "Backhand streak", he: "רצף גב כף היד", skill: .backhand, base: 8, streak: true),
        CrossStage(id: "pass_quick", en: "Quick team passes", he: "מסירות קבוצתיות זריזות", skill: .pass, base: 8, fast: true),
        CrossStage(id: "set_quick", en: "Raise and ready", he: "מרימים ומתכוננים", skill: .set, base: 8, fast: true),
        CrossStage(id: "smash_aim", en: "Pick your smash lane", he: "בוחרים כיוון להנחתה", skill: .smash, base: 8),
        CrossStage(id: "paint_left", en: "Partners on the left", he: "שותפים מצד שמאל", skill: .paint, partnerSeat: 3),
        CrossStage(id: "diamond", en: "Diamond trail", he: "שביל היהלום", skill: .shape, base: 8),
        CrossStage(id: "defend_two", en: "Two serving partners", he: "שני מוסרים", skill: .defend, base: 12),
        CrossStage(id: "defend_three", en: "Three serving partners", he: "שלושה מוסרים", skill: .defend, base: 14, fast: true),
        CrossStage(id: "forehand_streak", en: "Forehand streak", he: "רצף כף היד", skill: .forehand, base: 10, streak: true),
        CrossStage(id: "backhand_quick", en: "Quick backhands", he: "גב כף היד בזריזות", skill: .backhand, base: 12, fast: true),
        CrossStage(id: "star_small", en: "Little star artist", he: "אמן הכוכב הקטן", skill: .shape, base: 10, small: true),
        CrossStage(id: "smash_quick", en: "Team lightning", he: "ברק קבוצתי", skill: .smash, base: 10, fast: true),
        CrossStage(id: "final", en: "Court explorer", he: "אלוף השולחנות", skill: .aim, base: 16, streak: true, fast: true),
    ]
    static func stage(_ step: Int) -> CrossStage { stages[crossMod(step, 30)] }
}

/// Equal physical area samples, clipped to the actual table outline. Serve bounces are excluded by the caller.
final class CrossPaint {
    let size = 52
    let span = CrossGeometry.reach * 2
    private(set) var owners: [Int]
    private let original: [Int]
    init(_ geometry: CrossGeometry, teams: CrossTeams?) {
        let n = 52, width = CrossGeometry.reach * 2
        var cells: [Int] = []
        cells.reserveCapacity(n * n)
        for i in 0..<(n * n) {
            let p = MPPoint(((Double(i % n) + 0.5) / Double(n) - 0.5) * width, ((Double(i / n) + 0.5) / Double(n) - 0.5) * width)
            if let owner = geometry.owner(p) { cells.append(teams.map { $0.seats[owner] } ?? owner) } else { cells.append(-1) }
        }
        owners = cells
        original = cells
    }
    func point(_ i: Int) -> MPPoint { MPPoint(((Double(i % size) + 0.5) / Double(size) - 0.5) * span, ((Double(i / size) + 0.5) / Double(size) - 0.5) * span) }
    func paint(_ at: MPPoint, team: Int) { for i in owners.indices where owners[i] >= 0 && point(i).distance(at) < 0.18 { owners[i] = team } }
    /// The share of the OTHER team's original area now painted by `team`.
    func coverage(_ team: Int) -> Double {
        let territory = owners.indices.filter { original[$0] >= 0 && original[$0] != team }
        return territory.isEmpty ? 0 : Double(territory.filter { owners[$0] == team }.count) / Double(territory.count)
    }
    /// Restores saved cells; false (nothing changed) for another grid size.
    func restore(_ cells: [Int]) -> Bool {
        guard cells.count == owners.count else { return false }
        owners = cells
        return true
    }
}

/// Daily progress consumes actual contacts and landings. It never writes normal match scores or history. `open` is an endless
/// playground (no goal, no retry).
final class CrossPractice {
    let step: Int
    let avatar: String
    let open: Bool
    let stage: CrossStage
    let cycle: Int
    let goal: Int
    let teams: CrossTeams?
    let roster: [CrossSeat]
    private(set) var successes = 0
    private(set) var mistakes = 0
    private(set) var attempts = 0
    private(set) var clock = 0.0
    private(set) var elapsedAttempt = 0.0
    private(set) var nextIn = 0.0
    private(set) var won = false
    private(set) var ended = false
    var paused = false
    private(set) var started = false
    private(set) var eventSerial = 0
    private(set) var lastEvent = ""
    private(set) var engine: CrossEngine
    let paint: CrossPaint
    /// The shape circles already painted, in order.
    private(set) var painted: [Int] = []
    private(set) var marks: [MPPoint] = []
    private var countedRally = -1
    private var countedHit = -1
    private var humanBackhand = false
    private var humanPaints = 0
    private var scoredAttempt = false

    init(step: Int, avatar: String = "miniko", open: Bool = false) {
        self.step = step; self.avatar = avatar; self.open = open
        let stage = CrossJourney.stage(step)
        self.stage = stage
        let cycle = step / 30
        self.cycle = cycle
        goal = stage.goal(cycle)
        let teams: CrossTeams? = stage.team ? CrossTeams((0...3).map { $0 == 0 || $0 == stage.partnerSeat ? 0 : 1 }) : nil
        self.teams = teams
        var used: Set<String> = [avatar]
        var seats: [CrossSeat] = [CrossSeat(index: 0, kind: .local, id: "you", name: "You", characterId: avatar)]
        for i in 1...3 {
            let helping = stage.cooperative || teams?.same(0, i) == true
            let c = stage.bot(cycle, exclude: used, helping: helping)
            used.insert(c.id)
            seats.append(CrossSeat(index: i, kind: .house, id: "bot_" + c.id, name: c.english, bot: c.profile, characterId: c.id))
        }
        roster = seats
        let first = CrossPractice.makeEngine(stage: stage, cycle: cycle, step: step, attempts: 0, roster: seats, teams: teams)
        engine = first
        paint = CrossPaint(first.geometry, teams: teams)
    }
    var remaining: Double { max(0, 90 - clock) }
    var radius: Double { stage.skill == .shape ? (stage.small ? 0.065 : 0.09) : (stage.small ? 0.12 : 0.20) }
    var receiver: Int { stage.team ? stage.partnerSeat : (stage.skill == .shape ? 1 : 1 + attempts % 3) }
    func targets() -> [MPPoint] {
        let g = engine.geometry, seat = receiver
        if stage.skill != .shape {
            let u: Double
            switch attempts % 3 {
            case 0: u = -0.23
            case 1: u = 0.23
            default: u = 0
            }
            return [g.fromLocal(seat, u, 0.85)]
        }
        let n = goal
        let vertices: [CrossLocal]
        switch stage.id {
        case "triangle": vertices = [CrossLocal(0, 0.39), CrossLocal(0.28, 0.93), CrossLocal(-0.28, 0.93)]
        case "diamond": vertices = [CrossLocal(0, 0.38), CrossLocal(0.28, 0.66), CrossLocal(0, 0.94), CrossLocal(-0.28, 0.66)]
        default: vertices = []
        }
        return (0..<n).map { i -> MPPoint in
            if !vertices.isEmpty {
                let t = Double(i) * Double(vertices.count) / Double(n)
                let k = Int(t)
                let a = vertices[k], b = vertices[(k + 1) % vertices.count]
                return g.fromLocal(seat, a.u + (b.u - a.u) * (t - Double(k)), a.v + (b.v - a.v) * (t - Double(k)))
            }
            let angle = -Double.pi / 2 + Double(i) * 2 * Double.pi / Double(n)
            let r = stage.id.hasPrefix("star") && i % 2 == 1 ? 0.14 : 0.28
            return g.fromLocal(seat, cos(angle) * r, 0.66 + sin(angle) * r)
        }
    }
    var target: MPPoint {
        let all = targets()
        let index = stage.skill == .shape ? min(painted.count, goal - 1) : 0
        return all[max(0, min(all.count - 1, index))]
    }
    private static func makeEngine(stage: CrossStage, cycle: Int, step: Int, attempts: Int, roster: [CrossSeat], teams: CrossTeams?) -> CrossEngine {
        let serve = stage.skill == .serve
        let server: Int
        if serve { server = 0 }
        else if stage.skill == .smash { server = 1 }
        else {
            switch stage.id {
            case "defend": server = 1
            case "defend_two": server = 1 + attempts % 2
            default: server = 1 + attempts % 3
            }
        }
        var drill: CrossExercise?
        if !stage.team {
            let expected: Int? = stage.skill == .shape ? 1 : (stage.aimed || serve ? 1 + attempts % 3 : nil)
            let side: Double = stage.skill == .backhand ? -0.20 : (stage.skill == .forehand ? 0.20 : 0)
            let width = min(0.19, 0.03 + Double(10 - roster[server].profile.accuracy) * 0.018 + Double(cycle) * 0.008)
            drill = CrossExercise(drill: serve ? .serve : .returning, expected: expected, server: server, feedWidth: width, feedSide: side,
                                  paceMultiplier: stage.fast ? 1.2 : 1)
        }
        return CrossEngine(seats: roster, control: .beginner, target: 999, seed: Int64(step) * 2001 + Int64(attempts), firstServer: server,
                           exercise: drill, teams: teams, tapTargets: true, teamLesson: stage.skill == .smash ? 0 : nil)
    }
    private func makeEngine() -> CrossEngine {
        CrossPractice.makeEngine(stage: stage, cycle: cycle, step: step, attempts: attempts, roster: roster, teams: teams)
    }
    func start() { started = true }
    func advance(_ dt: Double) {
        if paused || ended || !started || !dt.isFinite { return }
        var left = min(1.0 / 30, max(0, dt))
        while left > 1e-9 && !ended {
            let n = min(left, CrossEngine.step)
            left -= n; clock += n
            if stage.skill == .paint && clock >= 90 {
                won = humanPaints >= 3 && paint.coverage(0) > paint.coverage(1); ended = true; signal(won ? "win" : "retry")
                break
            }
            if nextIn > 0 {
                nextIn -= n
                if nextIn <= 0 { engine = makeEngine(); elapsedAttempt = 0; scoredAttempt = false; countedHit = -1 }
                continue
            }
            elapsedAttempt += n
            engine.advance(n)
            for e in engine.drainEvents() {
                switch e {
                case let .contact(seat, _, point, _): if seat == 0 { humanBackhand = engine.geometry.toLocal(0, point).u < 0 }
                case let .bounce(owner, point): landing(owner: owner, point: point)
                case .rally: if stage.team && stage.skill != .paint && !scoredAttempt { finishAttempt(false) }
                default: break
                }
            }
            if let result = engine.trainingResult, !scoredAttempt {
                let point = engine.bouncePoint
                let aimed = !stage.aimed || (point.map { $0.distance(target) <= radius } ?? false)
                let hand: Bool
                switch stage.skill {
                case .backhand: hand = humanBackhand
                case .forehand: hand = !humanBackhand
                default: hand = true
                }
                finishAttempt(result.success && aimed && hand, point)
            }
            if elapsedAttempt > 18 && stage.skill != .paint && !scoredAttempt { finishAttempt(false) }
        }
    }
    private func landing(owner: Int, point: MPPoint) {
        guard let hit = engine.lastCommittedStrike else { return }
        if hit.serve || engine.referee.phase != .receivable || (countedHit == hit.hitIndex && countedRally == hit.rallyId) { return }
        countedHit = hit.hitIndex; countedRally = hit.rallyId
        if stage.skill == .paint {
            if let teams { paint.paint(point, team: teams.seats[hit.seat]) }
            if hit.seat == 0 { humanPaints += 1 }
            return
        }
        guard stage.team, !scoredAttempt, hit.seat == 0, let teams else { return }
        let friend = teams.same(0, owner)
        let okay: Bool
        switch stage.skill {
        case .pass: okay = friend
        case .set: okay = friend && engine.teamFlight?.setReceiver == owner
        case .smash: okay = !friend && (engine.teamFlight?.smashes ?? 0) > 0
        default: okay = false
        }
        finishAttempt(okay, point)
    }
    private func finishAttempt(_ good: Bool, _ point: MPPoint? = nil) {
        if scoredAttempt { return }
        scoredAttempt = true; attempts += 1
        if good {
            successes += 1
            if let point { marks.append(point); if marks.count > 80 { marks.removeFirst() } }
            if stage.skill == .shape && !painted.contains(painted.count) { painted.append(painted.count) }
            signal("good")
        } else {
            mistakes += 1
            if stage.streak { successes = 0 }
            signal("miss")
        }
        if !open && successes >= goal { won = true; ended = true; signal("win") }
        else if !open && mistakes >= 3 { ended = true; signal("retry") }
        else {
            nextIn = stage.fast ? 0.55 : 0.85; engine.paused = true
            if stage.skill == .shape && !good { attempts -= 1 }
        }
    }
    private func signal(_ s: String) { lastEvent = s; eventSerial += 1 }

    func save() -> MPWire {
        var w: MPWire = ["version": 1, "step": step, "avatar": avatar, "open": open, "successes": successes, "mistakes": mistakes,
                         "attempts": attempts, "clock": clock, "elapsed": elapsedAttempt, "next": nextIn, "won": won, "ended": ended,
                         "countedRally": countedRally, "counted": countedHit, "backhand": humanBackhand, "humanPaints": humanPaints, "scored": scoredAttempt,
                         "paint": paint.owners, "painted": painted, "marks": marks.map { [$0.x, $0.y] }, "engine": engine.exportState().wire()]
        if let r = engine.trainingResult {
            var training: MPWire = ["good": r.success]
            if let kind = r.kind { training["kind"] = kind.rawValue }
            if let receiver = r.receiver { training["receiver"] = receiver }
            w["training"] = training
        }
        return w
    }
    static func restore(_ w: MPWire) throws -> CrossPractice {
        guard CrossWire.number(w, "version") == 1 else { throw CrossStateError.invalid("Unknown practice version") }
        let step = CrossWire.int(w, "step")
        guard step >= 0 else { throw CrossStateError.invalid("Invalid practice step") }
        let p = CrossPractice(step: step, avatar: CrossWire.text(w, "avatar", "miniko"), open: CrossWire.flag(w, "open"))
        p.successes = CrossWire.int(w, "successes"); p.mistakes = CrossWire.int(w, "mistakes"); p.attempts = CrossWire.int(w, "attempts")
        p.clock = CrossWire.decimal(w, "clock"); p.elapsedAttempt = CrossWire.decimal(w, "elapsed"); p.nextIn = CrossWire.decimal(w, "next")
        p.won = CrossWire.flag(w, "won"); p.ended = CrossWire.flag(w, "ended"); p.countedHit = CrossWire.int(w, "counted", -1)
        p.countedRally = CrossWire.int(w, "countedRally", -1); p.humanBackhand = CrossWire.flag(w, "backhand"); p.humanPaints = CrossWire.int(w, "humanPaints")
        p.scoredAttempt = CrossWire.flag(w, "scored")
        guard [p.clock, p.elapsedAttempt, p.nextIn].allSatisfy({ $0.isFinite && $0 >= 0 }), p.successes >= 0, p.mistakes >= 0, p.attempts >= 0 else {
            throw CrossStateError.invalid("Invalid practice progress")
        }
        p.engine = p.makeEngine()
        try p.engine.restoreState(try CrossState.read(MPCodec.map(w["engine"])))
        if p.nextIn > 0 { p.engine.paused = true }
        guard p.paint.restore(CrossWire.ints(w["paint"])) else { throw CrossStateError.invalid("Paint grid mismatch") }
        for value in CrossWire.ints(w["painted"]) where !p.painted.contains(value) { p.painted.append(value) }
        for raw in CrossWire.entries(w["marks"]) {
            let pair = CrossWire.entries(raw).map { ($0 as? NSNumber)?.doubleValue ?? 0 }
            if pair.count == 2 { p.marks.append(MPPoint(pair[0], pair[1])) }
        }
        return p
    }
}
