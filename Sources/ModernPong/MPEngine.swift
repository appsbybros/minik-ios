import Foundation

enum MPEvent {
    case swing(MPSide, Int), contact(MPSide, Int, MPPoint, Double), bounce(MPSide?, MPPoint)
    case net, point(MPResolution, MPSide, Int), victory(MPSide)
}
struct MPStroke {
    var contactAt = 0.10, windowEnd = 0.23, followEnd = 0.34, total = 0.48
    var id = 0, age = 1.0, left = false, point = MPPoint(0.5, 0.87), height = 0.0, contacted = false
    var active: Bool { age < total }
    var contactWindow: Bool { age >= contactAt && age <= windowEnd && !contacted }
    mutating func start(_ id: Int, _ point: MPPoint, _ height: Double, _ left: Bool) {
        self.id = id; self.point = point; self.height = height; self.left = left; age = 0; contacted = false
    }
    /// Android `Stroke.contact` (2026-10): the follow-through starts at the actual contact, including a buffered tap.
    mutating func contact(_ point: MPPoint, _ height: Double) { self.point = point; self.height = height; contacted = true; age = contactAt }
    mutating func advance(_ dt: Double) { age = min(total, age + dt) }
    mutating func cancel() { age = total; contacted = false }
    /// Android `ActorPresentation.recoveryBlend`: after the opponent's follow-through (0.44 s) its FOLLOW pose
    /// fades into READY over 0.16 s. 1 means fully READY.
    var recoveryBlend: Double { active && age >= 0.44 ? ((age - 0.44) / 0.16).mpClamp(0, 1) : 1 }
    /// Android `ActorPresentation.angle`: player racket swing in degrees, clockwise on screen.
    var angle: Double {
        guard active else { return 0 }
        let degrees: Double
        if age < contactAt { degrees = -10 * sin(age / contactAt * .pi) }
        else if age <= windowEnd { degrees = 0 }
        else if age < followEnd { degrees = 10 * ((age - windowEnd) / (followEnd - windowEnd)) }
        else { degrees = 10 * (1 - (age - followEnd) / (total - followEnd)) }
        return (left ? -1 : 1) * degrees
    }
}
enum MPProjection {
    static let width = 941.0, height = 1672.0, left = 93.0, top = 186.0, tableWidth = 754.0, bottom = 1437.0, net = 748.0
    static func imageY(_ y: Double) -> Double { y <= 0.5 ? top + pow(y * 2, 3) * (net - top) : net + (y - 0.5) * 2 * (bottom - net) }
    static func tableY(_ y: Double) -> Double { y <= net ? cbrt((y - top) / (net - top)) * 0.5 : 0.5 + (y - net) / (bottom - net) * 0.5 }
    static func ball(_ point: MPPoint, _ height: Double) -> MPPoint { .init(left + point.x * tableWidth, imageY(point.y) - max(0, height) * (bottom - top) * 0.075) }
    static func offset(_ left: Bool) -> MPPoint { left ? .init((0.1732875093 - 0.5) * 600, (0.8169685305 - 0.65) * 600) : .init((995.0 / 1280 - 0.5) * 600, (1030.0 / 1280 - 0.65) * 600) }
    static func body(_ point: MPPoint, _ height: Double, _ left: Bool) -> MPPoint {
        let p = ball(point, height), o = offset(left); return .init(p.x - o.x, p.y - o.y)
    }
    static func reachable(_ body: MPPoint) -> Bool { (45...186).contains(body.y) && (250...691).contains(body.x) }
}
struct MPMotion {
    static let home = MPPoint(470.5, 176)
    var body = home, left = false, walkAge = 0.0
    private var origin = home, target = home, age = 0.0, duration = 0.0
    var moving: Bool { age < duration }
    mutating func approach(_ p: MPPoint, seconds: Double, left: Bool) {
        self.left = left; origin = body; target = .init(p.x.mpClamp(250, 691), p.y.mpClamp(45, 186))
        duration = max(0.08, seconds); age = 0; walkAge = 0
    }
    mutating func advance(_ dt: Double) {
        guard moving else { return }; age = min(duration, age + dt); walkAge += dt
        let f = age / duration, e = f * f * (3 - 2 * f)
        body = .init(origin.x + (target.x - origin.x) * e, origin.y + (target.y - origin.y) * e)
    }
    mutating func settle() { if target != Self.home { approach(Self.home, seconds: 0.45, left: left) } }
    func error(_ p: MPPoint, _ height: Double) -> Double {
        let offset = MPProjection.offset(left)
        return MPPoint(body.x + offset.x, body.y + offset.y).distance(MPProjection.ball(p, height))
    }
}
struct MPIntercept {
    var after: Double; var point: MPPoint; var height: Double; var left: Bool; var reachable: Bool
    var body: MPPoint { MPProjection.body(point, height, left) }
    static func predict(_ live: MPFlight, _ t: MPTuning) -> Self? {
        guard live.striker == .child, !live.resolved else { return nil }
        var future = live, bounced = future.receiver, fallback: Self?, reachable: Self?
        for tick in 1...720 {
            let elapsed = Double(tick) / 120, event = future.advance(1.0 / 120, t)
            if future.resolved { return reachable ?? fallback }
            if event?.recipient == .minik { bounced = true }
            guard bounced, elapsed + 1e-9 >= t.minikReactionInterval else { continue }
            let point = future.position, left = point.x < 0.5
            let plan = Self(after: elapsed, point: point, height: future.height, left: left,
                reachable: MPProjection.reachable(MPProjection.body(point, future.height, left)))
            // Android MinikIntercept.predict (920caca): keep the latest reachable contact; only a ball already at the far
            // end line (y <= 0.10) is taken at once.
            if plan.reachable { reachable = plan; if point.y <= 0.10 { return plan } }
            if fallback == nil { fallback = plan }
        }
        return reachable ?? fallback
    }
}
struct MPExercise {
    var serve: Bool; var incoming: Double?; var expected: MPZone?
}
struct MPState: Codable {
    var score: MPScore; var flight: MPFlight?; var rally: Int; var pointDelay: Double?; var serveDelay: Double?
    var status: String; var pendingFault: MPResolution?; var faultTime: Double
    /// Android `EngineState.reception` (2026-10): the authority's shared clock. Absent in older checkpoints.
    var reception: MPReceptionAssist? = nil
    var reflected: Self { .init(score: score.reflected, flight: flight?.reflected, rally: rally,
        pointDelay: pointDelay, serveDelay: nil, status: status,
        pendingFault: pendingFault.map { .init(winner: $0.winner.other, fault: $0.fault) }, faultTime: faultTime,
        reception: reception?.reflected) }
    var valid: Bool { score.child >= 0 && score.minik >= 0 && score.rallies >= 0 && rally >= 0 &&
        (flight?.valid ?? true) && faultTime.isFinite && (pointDelay?.isFinite ?? true) }
}
/// Android `HouseStrategy`: short placement patterns shared by every house player, with skill-scaled width and tempo.
struct MPHouseStrategy {
    let skill: Double
    private var plan: [(x: Double, pace: Double)] = []
    private var previousZone = -1, repeats = 0
    init(skill: Double) { self.skill = skill }
    mutating func reset() { plan = []; previousZone = -1; repeats = 0 }
    /// Returns the requested landing x and a pace multiplier for the next good return.
    mutating func aim(_ incomingX: Double, random: inout MPRandom) -> (x: Double, pace: Double) {
        let variety = ((skill - 6) / 4).mpClamp(0, 1)
        let left = 0.24 - 0.12 * variety, right = 1 - left
        if plan.isEmpty {
            let same = incomingX < 0.40 ? left : incomingX > 0.60 ? right : 0.50
            let opposite: Double
            if same < 0.5 { opposite = right } else if same > 0.5 { opposite = left } else { opposite = random.unit() < 0.5 ? left : right }
            let first = random.unit() < 0.5 ? left : right, other = 1 - first
            let choice = random.unit()
            if choice < 0.60 - 0.30 * variety {
                // Two controlled balls set up a faster shot to the other side.
                plan = [(same, 1.0), (same, 1.025 + 0.035 * variety), (opposite, 1.06 + 0.16 * variety)]
            } else if choice < 0.90 - 0.25 * variety {
                // A central ball, then open both sides of the court.
                plan = [(0.50, 0.98), (first, 1.0), (other, 1.04 + 0.14 * variety)]
            } else {
                // Alternating placement; stronger players go wider and accelerate more.
                plan = [(first, 0.99), (other, 1.02 + 0.04 * variety), (first, 1.05 + 0.13 * variety)]
            }
        }
        let shot = plan.removeFirst()
        var target = shot.x
        // Never a third consecutive return to the same third. Tiny jitter is not a new placement.
        if Self.zone(target) == previousZone && repeats >= 2 {
            if previousZone == 0 { target = right } else if previousZone == 2 { target = left } else { target = random.unit() < 0.5 ? left : right }
        }
        let nextZone = Self.zone(target)
        repeats = nextZone == previousZone ? repeats + 1 : 1; previousZone = nextZone
        return ((target + random.range(-0.02, 0.02)).mpClamp(0.08, 0.92), shot.pace)
    }
    static func zone(_ x: Double) -> Int { min(2, max(0, Int(x * 3))) }
}
/// Android `ServeReliability`: keeps the requested long-run fault rate without clusters.
/// A fault is followed by four protected legal serves (two when the rate is at least 20%).
struct MPServeReliability {
    private var shielded = 0, attempts = 0
    mutating func fault(_ rate: Double, random: inout MPRandom) -> Bool {
        attempts += 1
        if shielded > 0 { shielded -= 1; return false }
        let p = rate.mpClamp(0, 0.30), protection = p < 0.20 ? 4 : 2
        let hazard = attempts == 1 ? p : p / (1 - Double(protection) * p)
        let result = random.unit() < hazard
        if result { shielded = protection }
        return result
    }
}
/// Android `RallyVariation`: counts committed returns from BOTH sides. The fifth straight return in the
/// same lane is nudged once toward the centre, escaping edge-to-edge straight loops. The sending player
/// commits the variation; its peer accepts that exact flight (`adjust: false`).
struct MPRallyVariation {
    private var lane: Double?
    private var straight = 0
    mutating func reset() { lane = nil; straight = 0 }
    @discardableResult mutating func hit(_ point: MPPoint, _ velocity: MPPoint, adjust: Bool = true) -> MPPoint {
        let vertical = abs(velocity.y)
        if vertical < 0.01 || abs(velocity.x) / vertical > 0.09 { reset(); return velocity }
        if let previous = lane, abs(point.x - previous) <= 0.10 { straight += 1 } else { straight = 1 }
        lane = point.x
        if straight < 5 { return velocity }
        reset()
        if !adjust { return velocity }
        let direction: Double = point.x <= 0.5 ? 1 : -1
        return MPPoint(velocity.x + direction * vertical * 0.28, velocity.y)
    }
}
final class MPEngine {
    let level: MPLevel, target: Int, tuning: MPTuning, bot: MPBot?, networked: Bool, first: MPSide?
    let houseControls: Bool
    let exercise: MPExercise?
    /// Android `ActorPresentation.servePoint` (2026-10: 0.02, was 0.13): the far player serves from behind the end line.
    static let servePoint = MPPoint(0.5, 0.02)
    /// Android `ModernGame.expectedSpin` (guide spin lessons): 1 top spin, 2 side spin, 0 none. The return lesson then
    /// succeeds only when the committed Pro stroke carried that spin (more than 0.15).
    let expectedSpin: Int
    /// Android `ModernGame.championLevel`: a colour champion trial (target level 5...11) strengthens the house player.
    let championLevel: Int
    var paused = false
    /// Set by MPMatchLink. A networked non-authority never awards a speculative point (Android `authoritative`).
    var authoritative = true
    /// Android `ModernEngine.reception`: optional slow motion before the receiver's return, on one shared clock.
    var reception = MPReceptionAssist()
    var automaticContact: Bool { level.automaticContact }
    /// Android `returnBaseline`: the court-specific grounded paddle contact plane (0.90; 0.96 on the large table, set by
    /// `MPScene.selectedArena`). A buffered tap or stroke waits for the ball to reach it.
    var returnBaseline = 0.90
    /// Android `swipeTouchTolerance`: touch forgiveness calibrated in visible pixels by the court; physics stays in table
    /// units.
    var swipeTouchTolerance: Double
    private var touchTuning: MPTuning { var t = tuning; t.swipeCollisionForgiveness = swipeTouchTolerance; return t }
    /// Android `childCanReach`: the large table's visible reach test (nil on the compact court).
    var childCanReach: ((MPPoint, Double) -> Bool)?
    /// Android `looseBall` / `visibleBodies` / `visibleFloor` (920caca): after a point the ball keeps its real motion,
    /// may rebound off a drawn player (`visibleBodies`, set by the court every frame) and comes to rest on the floor.
    private(set) var looseBall: MPLooseBall?
    var visibleBodies: [MPLooseBall.Body] = []
    var visibleFloor = -0.85
    /// Android `settlingBall`: the next rally (and a result screen or final save) waits until the loose ball rests.
    var settlingBall: Bool { looseBall.map { !$0.settled } ?? false }
    /// Android `ballVisible`: before contact the ball is held out of view, not parked on the table or a head; the
    /// post-point rebound stays visible until it settles.
    var ballVisible: Bool { flight != nil || outBall != nil }
    /// Android `animating`.
    var animating: Bool { childStroke.active || minikStroke.active || motion.moving || settlingBall }
    /// Android `showServeDoubleBounceTip`: the child's serve bounced twice on the far side and won the point. Allowed for
    /// at most three points per app run (`MPSessionTips`).
    var showServeDoubleBounceTip: Bool {
        MPSessionTips.allow(ObjectIdentifier(self), point: score.rallies,
            eligible: userServed && rally == 0 && lastResolution?.fault == .secondBounce && lastResolution?.winner == .child)
    }
    /// Small decaying racket tilt from lateral paddle movement, in degrees (Android `paddleTilt`).
    private(set) var paddleTilt = 0.0
    private(set) var score: MPScore
    private(set) var flight: MPFlight?
    private(set) var status = "READY", awaitingServe = false, childReturnOpen = false, rally = 0
    private(set) var paddle: MPPoint?, restingPaddle = MPPoint(0.5, 0.87), restingHeight = 0.0
    private(set) var childStroke: MPStroke
    private(set) var minikStroke = MPStroke(contactAt: 0.20, windowEnd: 0.27, followEnd: 0.44, total: 0.68)
    private(set) var motion = MPMotion(), trainingResult: Bool?, trainingTime = 0.0
    private(set) var bouncePoint: MPPoint?, bounceAge = 1.0, netAge = 1.0
    /// Display only (Android `lastResolution`): how the last point ended and who won it, until the next rally.
    private(set) var lastResolution: MPResolution?
    /// Display only, never networked: the drawn loose ball after a point (`looseBall`); a ball that bounced on its
    /// hitter's own side (or twice) is also ringed where it landed.
    private(set) var outBall: MPPoint?, outHeight = 0.0, faultMark: MPPoint?, faultAge = 1.0
    /// Seconds of play since the match was won, so the last point can be seen before the result screen.
    private(set) var winnerAge = 0.0
    private var events: [MPEvent] = [], serial = 0, random: MPRandom
    private var velocity = MPPoint.zero, attemptedTap = false, minikDelay: Double?, plan: MPIntercept?
    private var serveDelay: Double?, pointDelay: Double?, pendingServe: MPServe?, pendingTap: MPPoint?
    /// Android `pendingSwipe` / `preparedStrokeTime`: a Standard or Pro stroke prepared before the ball reaches the
    /// baseline; it contacts once the ball is there.
    private var pendingSwipe: MPContact?, preparedStrokeTime = 0.0
    private var gestureStart: MPPoint?, gestureLast: MPPoint?, gestureTravel = 0.0, gestureCommitted = false
    private var tapStart: MPPoint?, tapAim = 0.0, tapAge = 0.0
    /// Android `committedStroke`: the spin of the child's last committed return (guide spin lessons).
    private var committedStroke: MPPongStroke?
    /// Android `receivingStartX`: where the house player stood when the child hit (`MPReturnPlacement`).
    private var receivingStartX = 0.5
    private var previousX: Double?, responses = 0, userServed = false, returnSpeeds: [Double?] = [nil, nil]
    private var correction = MPPoint.zero, correctionAge = 0.0, pendingFault: MPResolution?, faultTime = 0.0
    private var strategy: MPHouseStrategy, serveReliability = MPServeReliability(), rallyVariation = MPRallyVariation()
    /// Android `tapVelocity`: the fastest finger movement of a Standard tap gesture, converted into pace.
    private var tapVelocity = MPPoint.zero
    var ball: MPPoint { flight?.position ?? (awaitingServe || pendingServe != nil ? .init(0.5, 0.87) : Self.servePoint) }
    var renderedBall: MPPoint { outBall ?? MPPoint(ball.x + correction.x * correctionAge / 0.12, ball.y + correction.y * correctionAge / 0.12) }
    /// Height of the drawn ball: the live flight's, or the loose ball's after a point.
    var renderedHeight: Double { outBall != nil ? outHeight : max(0, flight?.height ?? 0.055) }
    init(level: MPLevel = .easy, target: Int = 7, bot: MPBot? = nil, houseControls: Bool = true,
         networked: Bool = false, first: MPSide = .child, exercise: MPExercise? = nil, seed: UInt64 = UInt64.random(in: 1...UInt64.max),
         expectedSpin: Int = 0, championLevel: Int = -1) {
        self.level = level; self.target = level.target(target); self.bot = bot; self.networked = networked
        self.houseControls = houseControls && bot != nil
        self.first = networked ? first : nil; self.exercise = exercise; random = .init(seed: seed)
        self.expectedSpin = expectedSpin; self.championLevel = championLevel
        // Android `ModernGame.tuning = RankPromotion.championTuning(..., championLevel)`.
        tuning = MPRankPromotion.championTuning(bot.map { $0.tuning(level, houseControls: houseControls) } ?? MPTuning.values(level), championLevel)
        swipeTouchTolerance = tuning.swipeCollisionForgiveness
        score = MPScore(server: networked ? first : level == .easy ? .minik : .child)
        switch level {
        case .beginner, .easy: childStroke = MPStroke(contactAt: 0.10, windowEnd: 0.40, followEnd: 0.50, total: 0.62)
        case .medium: childStroke = MPStroke(contactAt: 0.10, windowEnd: 0.52, followEnd: 0.64, total: 0.78)
        case .hard, .superHard: childStroke = MPStroke()
        }
        strategy = MPHouseStrategy(skill: bot?.tacticalSkill ?? 6)
        startRally()
    }
    func drainEvents() -> [MPEvent] { defer { events.removeAll(keepingCapacity: true) }; return events }
    private func startRally() {
        pendingFault = nil; trainingResult = nil; trainingTime = 0; tapStart = nil; tapAim = 0
        flight = nil; looseBall = nil; childReturnOpen = false; attemptedTap = false; rally = 0; release(); childStroke.cancel()
        minikDelay = nil; plan = nil; pointDelay = nil; serveDelay = nil; pendingServe = nil; pendingTap = nil; pendingSwipe = nil
        previousX = nil; responses = 0; userServed = score.server == .child; returnSpeeds = [nil, nil]; strategy.reset()
        rallyVariation.reset(); tapVelocity = .zero
        lastResolution = nil; outBall = nil; faultMark = nil
        awaitingServe = exercise.map(\.serve) ?? (score.server == .child)
        if awaitingServe { status = level.pro ? "SWIPE_SERVE" : "TAP_SERVE" }
        else {
            status = "MINIK_SERVE"
            if !networked {
                let left = random.unit() >= tuning.profile.forehandServe
                serveDelay = level == .easy ? 0.52 : 0.68
                motion.approach(MPProjection.body(Self.servePoint, 0.055, left), seconds: (serveDelay ?? 0.68) - 0.20, left: left)
            }
        }
    }
    /// Android `beginStroke`: a stroke animates the arm; it must not overwrite the user's movement target.
    private func swing(_ side: MPSide, _ p: MPPoint, _ h: Double = 0, left: Bool? = nil) {
        serial += 1
        if side == .child { childStroke.start(serial, p, h, left ?? (p.x < 0.5)) }
        else { minikStroke.start(serial, p, h, left ?? (p.x < 0.5)) }
        events.append(.swing(side, serial))
    }
    private func contact(_ side: MPSide, _ p: MPPoint, _ h: Double) {
        if side == .child {
            guard !childStroke.contacted else { return }
            childStroke.contact(p, h); events.append(.contact(side, childStroke.id, p, h))
        } else {
            guard !minikStroke.contacted else { return }
            minikStroke.contact(p, h); events.append(.contact(side, minikStroke.id, p, h))
        }
    }
    private func minikServe() {
        let p = tuning.profile
        // Android ServeReliability: the requested rate without back-to-back Minik faults. The guide never faults.
        let fault: Bool
        if exercise == nil { fault = serveReliability.fault(tuning.minikServeFaultProbability, random: &random) } else { fault = false }
        let x: Double
        if let incoming = exercise?.incoming { x = (0.5 + incoming * 0.30).mpClamp(0.12, 0.88) }
        else if random.unit() < p.serveMiddle { x = random.range(0.40, 0.60) }
        else { x = random.unit() < 0.5 ? random.range(0.04, 1.0 / 6) : random.range(5.0 / 6, 0.96) }
        // Android `planned.copy(start=ActorPresentation.servePoint, ...)`.
        var serve = MPShots.serve(.init(x, level == .easy || houseControls ? 0.80 : 0.75), side: .minik, tuning: tuning)
        serve.start = Self.servePoint
        let magnitude = random.unit() * p.serveVariation
        serve.speed *= p.serveSpeed * (1 + magnitude * (random.unit() < 0.5 ? -1 : 1))
        if fault { serve = .init(server: .minik, start: Self.servePoint, first: .init(-0.12, 0.28), second: .init(0.5, 0.72), speed: tuning.ballBaseSpeed, arc: tuning.netHeight * 1.5) }
        contact(.minik, serve.start, 0.055); flight = MPFlight(serve, tuning); status = "SERVED"
    }
    func advance(_ dt: Double) {
        guard !paused else { return }
        // Android ModernEngine.advance (2026-10): the receiving human (online: either human) may slow the whole
        // simulation for their return. Everything below uses the same, possibly slower, delta.
        let incoming = flight.flatMap { $0.resolved ? nil : $0 }
        let receiver = incoming.flatMap { f -> MPSide? in let side = f.striker.other; return side == .child || networked ? side : nil }
        let seat = receiver.map { $0 == .child ? 0 : 1 }
        var eta: Double?
        if let incoming, let receiver { eta = MPReceptionAssist.eta(incoming.position, incoming.velocity, .init(incoming.position.x, receiver == .child ? 0.84 : 0.16)) }
        let delta = reception.advance(dt, seat: seat, eta: eta, authority: authoritative); correctionAge = max(0, correctionAge - delta)
        if let fault = pendingFault {
            faultTime -= delta
            if faultTime <= 0 { pendingFault = nil; resolve(fault, striker: flight?.striker ?? fault.winner) }
            return
        }
        paddleTilt *= exp(-delta * 10)
        tapAge += delta; if exercise != nil { trainingTime += delta }
        childStroke.advance(delta); minikStroke.advance(delta); motion.advance(delta)
        if gestureStart == nil && !childStroke.active { paddle = nil; velocity = .zero }
        if (pointDelay != nil || awaitingServe) && plan == nil && serveDelay == nil && !minikStroke.active { motion.settle() }
        bounceAge += delta; netAge += delta; faultAge += delta
        if score.winner != nil { winnerAge += delta }
        if let ball = looseBall {
            // The point is already decided; the ball only finishes its real motion (Android LooseBall).
            ball.advance(delta, tuning, bodies: visibleBodies)
            outBall = ball.position; outHeight = ball.height
        }
        guard score.winner == nil, trainingResult == nil else { return }
        if let delay = pointDelay { pointDelay = max(0, delay - delta); if delay <= delta && !settlingBall { startRally() }; return }
        if let delay = serveDelay {
            serveDelay = delay - delta
            if delay - delta <= 0.20 && !minikStroke.active { swing(.minik, Self.servePoint, 0.055, left: motion.left) }
            if delay <= delta { serveDelay = nil; minikServe() }; return
        }
        if let serve = pendingServe {
            if childStroke.age >= 0.10 {
                contact(.child, serve.start, 0.055); flight = MPFlight(serve, tuning); pendingServe = nil; status = "SERVED"; planReturn()
            }; return
        }
        let event = flight?.advance(delta, tuning)
        if event?.bounced == true, let point = event?.point {
            bouncePoint = point; bounceAge = 0; events.append(.bounce(event?.recipient, point))
            if let exercise, event?.recipient == .minik, flight?.striker == .child {
                let aimed = exercise.expected.map { MPZone.at(point.x) == $0 } ?? true
                // Android 2026-10 guide spin lessons: the landing counts only with the requested spin.
                let spun: Bool
                switch expectedSpin {
                case 1: spun = (committedStroke?.top ?? 0) > 0.15
                case 2: spun = abs(committedStroke?.side ?? 0) > 0.15
                default: spun = true
                }
                trainingResult = aimed && spun
                childReturnOpen = false; return
            }
        }
        if let result = event?.resolution {
            if result.fault == .net { netAge = 0; events.append(.net) }
            // Late-return grace: a delayed remote human return can still arrive (Android: 2.0 s).
            if networked && (result.fault == .secondBounce || result.fault == .unreturned) { pendingFault = result; faultTime = 2.0 }
            else { resolve(result, striker: flight?.striker ?? .minik) }; return
        }
        if event?.recipient == .child { childReturnOpen = true; if pendingTap == nil { attemptedTap = false }; status = "RETURN_BALL" }
        // Beginner: position alone arms the return. A held or released paddle meets the legal
        // incoming ball exactly once, without a tap-timing requirement.
        if automaticContact && childReturnOpen, let f = flight, !f.resolved, f.receiver, f.striker == .minik,
           f.position.strikeZone, (paddle ?? restingPaddle).distance(f.position) <= 0.16 {
            swing(.child, f.position, f.height)
            returnChild(MPContact(point: f.position, timing: 1, spatial: 1, velocity: .zero, direction: tapAim))
            return
        }
        // Android 2026-10: Standard buffers a deliberate incoming-ball tap through its legal bounce. A visual wind-up
        // is not a deadline: the compact projection used to make the same apparent tap expire before the ball reached
        // the baseline.
        preparedStrokeTime = max(0, preparedStrokeTime - delta)
        let bufferedTap = (pendingTap != nil || pendingSwipe != nil) && (childStroke.age < childStroke.total || preparedStrokeTime > 0)
        if !automaticContact && (childStroke.contactWindow || bufferedTap) && childReturnOpen {
            tryReturn(); if flight?.striker == .child { return }
        }
        if preparedStrokeTime <= 0 && childStroke.age >= childStroke.total && !childStroke.contacted && (pendingTap != nil || pendingSwipe != nil) {
            pendingTap = nil; pendingSwipe = nil; status = "MISSED"
        }
        if let delay = minikDelay {
            let due = delay - delta; minikDelay = due
            if due <= 0.20 && !minikStroke.active, let plan { swing(.minik, plan.point, plan.height, left: plan.left) }
            if due <= 1e-9 { minikDelay = nil; minikReturn(); plan = nil }
        }
    }
    private func planReturn() {
        guard !networked, exercise == nil, let flight else { return }
        receivingStartX = ((motion.body.x - MPProjection.left) / MPProjection.tableWidth).mpClamp(0, 1)
        plan = MPIntercept.predict(flight, tuning)
        if var next = plan {
            minikDelay = next.after
            if let bot, bot.characterId != "minik", motion.body.distance(next.body) / max(0.08, next.after - 0.20) > 850 * bot.movement { next.reachable = false; plan = next }
            motion.approach(next.body, seconds: max(0.08, next.after - 0.20), left: next.left)
        }
    }
    private func minikReturn() {
        guard var f = flight, !f.resolved, pointDelay == nil, f.receiver, f.striker == .child, f.position.onSide(.minik) else { return }
        let p = tuning.profile, x = f.position.x.mpClamp(0, 1), zone = MPZone.at(x)
        let firstMiddle = (bot == nil || bot?.characterId == "minik") && (houseControls || level == .easy) && !userServed && responses == 0 && zone == .middle
        let receivingServe = userServed && responses == 0
        let base = firstMiddle ? MPChance(1, 0.95) : receivingServe ? p.serveReceive[zone.rawValue] : p.chance(zone, cross: false)
        let cross = firstMiddle || receivingServe ? base : p.chance(zone, cross: true)
        let hand = zone == .forehand || (zone == .middle && x >= 0.5) ? 0 : 1
        let pace = p.speed(base: tuning.ballBaseSpeed, previous: returnSpeeds[hand], forehand: hand == 0, random: &random)
        let index = userServed ? max(0, responses - 1) : responses; responses += 1
        guard plan?.reachable == true, minikStroke.active, motion.error(f.position, f.height) <= 6 else { status = "MINIK_MISSED"; return }
        // Android bcee181: placement-aware returns (ready in place, corner, opposite corner).
        guard var c = MPShots.aiContact(x: x, speed: hypot(f.velocity.x, f.velocity.y), depth: f.position.y, tuning: tuning,
            base: MPReturnPlacement.adjust(base, startX: receivingStartX, contactX: x), cross: MPReturnPlacement.adjust(cross, startX: receivingStartX, contactX: x),
            previousX: previousX, response: index, answerRoll: random.unit(), qualityRoll: random.unit(), pace: pace)
            else { status = "MINIK_MISSED"; return }
        c.point = f.position; contact(.minik, f.position, f.height)
        // House-player placement and tempo (Android HouseStrategy); the level's speed cap still applies.
        let tactical = strategy.aim(x, random: &random)
        if c.quality >= 0.14 { c.targetX = tactical.x }
        c.velocity = .init(c.velocity.x, min(pace * tactical.pace, tuning.ballBaseSpeed * p.maxSpeed))
        f.hit(c, side: .minik, tuning: tuning, rally: rally)
        f.velocity = rallyVariation.hit(f.position, f.velocity)
        rally += 1; flight = f; previousX = x; returnSpeeds[hand] = pace; status = "MINIK_RETURN"
    }
    private func resolve(_ result: MPResolution, striker: MPSide) {
        // A receiver can be a network round trip behind the authority. Its speculative
        // miss must not award/revoke a point or play point audio; the checkpoint decides.
        if networked && !authoritative { childReturnOpen = false; awaitingServe = false; return }
        if exercise != nil { trainingResult = false; childReturnOpen = false; awaitingServe = false; minikDelay = nil; plan = nil; serveDelay = nil; pendingServe = nil; pendingTap = nil; return }
        guard pointDelay == nil, score.award(result.winner, level: level, target: target, first: first) else { return }
        lastResolution = result
        if let f = flight {
            // Android 920caca: the decided ball keeps its real motion (a net ball drops back from the net) until it
            // rests; a short or double bounce is also ringed on the table where it landed.
            let v = result.fault == .net ? MPPoint(f.velocity.x, -f.velocity.y * 0.2) : f.velocity
            looseBall = MPLooseBall(position: f.position, height: max(f.height, 0), velocity: v, lift: f.lift, floor: visibleFloor)
            outBall = f.position; outHeight = max(f.height, 0)
            if result.fault == .firstBounceOut || result.fault == .secondBounce { faultMark = f.position; faultAge = 0 }
        }
        childReturnOpen = false; awaitingServe = false; release(); minikDelay = nil; plan = nil; serveDelay = nil; pendingServe = nil; pendingTap = nil; pendingSwipe = nil
        events.append(.point(result, striker, score.streak)); if let winner = score.winner { events.append(.victory(winner)) }
        let faultStatus: String
        switch result.fault {
        case .net: faultStatus = "NET_FAULT"
        case .leftTable, .firstBounceOut: faultStatus = "OUT_FAULT"
        case .secondBounce: faultStatus = "SECOND_BOUNCE"
        case .illegalServe: faultStatus = "INVALID_SERVE"
        case .unreturned: faultStatus = "BALL_IN"
        }
        status = score.winner.map { $0 == .child ? "CHILD_WIN" : "MINIK_WIN" } ?? faultStatus; pointDelay = 3.2
    }
    private var playable: Bool { !paused && score.winner == nil && pointDelay == nil && trainingResult == nil }
    /// Android `queueServe` (1d7a356): serve from the manually chosen position; never teleport the body to the old fixed
    /// centre launch point after a rally ends on one wing.
    private func queueServe(_ serve: MPServe, left: Bool? = nil) {
        var grounded = serve
        if serve.server == .child { grounded.start = .init(restingPaddle.x.mpClamp(0.06, 0.94), returnBaseline > 0.90 ? returnBaseline - 0.02 : serve.start.y) }
        awaitingServe = false; pendingServe = grounded; swing(.child, grounded.start, 0.055, left: left ?? (serve.second.x < 0.5))
    }
    /// `movePaddle` false (Android 78ed219): a tap on the full-player court never moves the player; footwork does.
    func touch(_ point: MPPoint?, movement: MPPoint = .zero, down: Bool = true, movePaddle: Bool = true) {
        guard playable else { return }
        // The paddle follows the finger on the player's side and stays there after release.
        // An armed tap retargets its pending contact before impact.
        if movePaddle, let point, point.strikeZone, !awaitingServe, pendingServe == nil {
            let old = restingPaddle
            restingPaddle = point; restingHeight = 0; paddle = point
            paddleTilt = ((point.x - old.x) * 160).mpClamp(-14, 14)
            if pendingTap != nil && !childStroke.contacted { pendingTap = point }
        }
        // Beginner rallies need positioning only; a small sideways drag still aims.
        if automaticContact && !awaitingServe && pendingServe == nil {
            if down { tapStart = point; tapAim = 0; tapAge = 0 }
            else { updateTapGesture(point, movement) }
            return
        }
        if !level.pro && !down {
            // Once contact committed its flight, later finger motion must not change it (Android).
            updateTapGesture(point, movement)
            return
        }
        guard let point, point.inside else { if !down { gestureLast = nil }; paddle = nil; return }
        if movePaddle && point.strikeZone { restingPaddle = point; restingHeight = level.pro ? max(0, flight?.height ?? 0) : 0 }
        velocity = level.pro ? movement : .zero
        if !level.pro {
            // A missed attempt can be retried 0.18 s into its swing; no long animation lock.
            guard down, !(childStroke.active && !childStroke.contacted && childStroke.age < 0.18) else { return }
            // A tap anywhere may aim a serve. During a rally only the child's half may start a swing.
            if !awaitingServe && point.y < 0.5 { return }
            tapStart = point; tapAim = 0; tapAge = 0; tapVelocity = .zero
            // Android 2026-10: a match tap serve may take the optional risk at the extreme zones; the guide never does.
            if awaitingServe { queueServe(exercise == nil ? MPShots.riskyTapServe(point, tuning, roll: random.unit()) : MPShots.serve(point, side: .child, tuning: tuning)) }
            else if let f = flight, !f.resolved, f.striker == .minik, f.position.y >= 0.65 {
                // A tap prepares the incoming ball's return; contact still needs the legal bounce and the baseline.
                let target = MPPoint(f.position.x, f.position.y.mpClamp(0.72, 1))
                attemptedTap = true; pendingTap = target
                swing(.child, target, f.height)
                // A late but legal tap must not miss during a mandatory 100 ms wind-up.
                if childReturnOpen && f.position.y >= returnBaseline { tryReturn() }
            } else if !awaitingServe { swing(.child, point) } // An early or empty swing is audible, never contact.
            return
        }
        if movePaddle { paddle = point.strikeZone ? point : nil }
        if down { gestureStart = point; gestureLast = point; gestureTravel = 0; gestureCommitted = false; return }
        guard let previous = gestureLast ?? gestureStart else { return }
        gestureTravel += previous.distance(point); gestureLast = point
        if awaitingServe && !gestureCommitted && gestureTravel >= 0.025 && Self.segmentDistance(previous, point, .init(0.5, 0.87)) <= tuning.swipeCollisionForgiveness { commitSwipe(point, movement) }
        else if !awaitingServe && childReturnOpen && gestureTravel >= 0.012, let f = flight {
            if !childStroke.active { swing(.child, point, f.height, left: movement.x < 0) }
            // The gesture is the swing. A swept contact before the grounded baseline is buffered until the ball is there.
            if !childStroke.contacted && f.receiver && f.striker == .minik && f.position.strikeZone && movement.y < -0.04 && Self.segmentDistance(previous, point, f.position) <= swipeTouchTolerance,
               let c = MPShots.swipeContact(f.position, ball: f.position, velocity: movement, tuning: touchTuning) {
                if f.position.y >= returnBaseline { returnChild(c) } else { pendingSwipe = c }
            }
        }
    }
    /// Android `standardSwipe` (6feaac5): a moving finger is a Standard stroke only during the incoming-ball contact
    /// approach; before that it remains footwork. The normal reach and bounce checks still apply. Android EASY (the
    /// "Starter" control, iOS `.medium`) may prepare earlier and waits longer.
    @discardableResult func standardSwipe(_ velocity: MPPoint) -> Bool {
        guard playable, !level.pro, !automaticContact, !awaitingServe, pendingTap == nil, let f = flight else { return false }
        if f.resolved || f.striker != .minik || !f.receiver || f.position.y < returnBaseline - (level == .medium ? 0.40 : 0.16) { return false }
        if hypot(velocity.x, velocity.y) < 0.045 { return false }
        if (childStroke.active && childStroke.contacted) || pendingSwipe?.standardSwipe == true { return false }
        let reach = childCanReach?(f.position, f.height) ?? (abs((paddle ?? restingPaddle).x - f.position.x) <= 0.19)
        let earlyStarter = level == .medium && abs(restingPaddle.x - f.position.x) <= 0.23
        if !reach && !earlyStarter { return false }
        let c = MPContact(point: f.position, timing: 1, spatial: 1, velocity: velocity, direction: velocity.x, standardSwipe: true)
        pendingTap = nil; pendingSwipe = c; preparedStrokeTime = level == .medium ? 1.5 : 0.65
        swing(.child, .init(f.position.x, max(f.position.y, returnBaseline)), f.height, left: velocity.x < 0)
        if f.position.y >= returnBaseline { tryReturn() }
        return true
    }
    /// Android `guidePreparedTap`: a drag after an armed tap aims it (the guide's and the court's prepared tap).
    func guidePreparedTap(from: MPPoint?, to: MPPoint?) {
        guard !level.pro, pendingTap != nil, !childStroke.contacted, let from else { return }
        tapStart = from
        updateTapGesture(to, .zero)
    }
    /// Android `updateTapGesture`: a small horizontal move (no forward/vertical gate) aims a Beginner or
    /// Standard return; Standard also keeps the fastest finger movement as its swing speed.
    private func updateTapGesture(_ point: MPPoint?, _ movement: MPPoint) {
        guard let start = tapStart, let point, point.inside, point.y >= 0.5, flight?.striker != .child else { return }
        let dx = point.x - start.x
        if abs(dx) >= 0.012 { tapAim = (dx / 0.085).mpClamp(-2, 2) }
        if !automaticContact && hypot(movement.x, movement.y) > hypot(tapVelocity.x, tapVelocity.y) { tapVelocity = movement }
    }
    private func commitSwipe(_ point: MPPoint, _ movement: MPPoint) {
        gestureCommitted = true
        let c = MPContact(point: point, timing: 1, spatial: 1, velocity: movement, direction: movement.x.mpClamp(-1, 1))
        if let serve = MPShots.swipeServe(c, tuning) { queueServe(serve) }
        else { swing(.child, point); resolve(.init(winner: .minik, fault: .illegalServe), striker: .child) }
    }
    /// Android `prepareGesture`: footwork. The player (paddle) moves to `point` on the near strip.
    func prepareGesture(_ point: MPPoint?) {
        if let point, point.strikeZone { paddle = point; restingPaddle = point; restingHeight = 0 }
    }
    /// Android `completeGesture` (22f756e): a finished Pro gesture (`MPPongStroke.read`) serves or prepares a spin
    /// return that contacts at the baseline.
    @discardableResult func completeGesture(_ stroke: MPPongStroke) -> Bool {
        guard playable, level.pro, stroke.valid else { return false }
        if awaitingServe { queueServe(MPShots.serve(.init(0.5 + stroke.aim * 0.3, 0.75), side: .child, tuning: tuning)); gestureCommitted = true; return true }
        guard let f = flight, !f.resolved, f.striker == .minik, f.position.y >= 0.45 else { return false }
        let c = MPContact(point: f.position, timing: 1, spatial: 1, velocity: .init(stroke.aim, -1), direction: stroke.aim, stroke: stroke)
        pendingSwipe = c; preparedStrokeTime = 1.15; velocity = c.velocity
        swing(.child, .init(f.position.x, f.position.y.mpClamp(0.72, 1)), f.height)
        if childReturnOpen && f.position.y >= returnBaseline { returnChild(c) }
        return true
    }
    func endTouch(cancelled: Bool = false) {
        tapStart = nil
        // Android 2026-10: a stationary Pro tap serves from the hand; Pro may still swipe for power. Cancellation never
        // commits a serve.
        if !cancelled && playable && awaitingServe && level.pro && !gestureCommitted && gestureTravel < 0.025, let start = gestureStart {
            queueServe(MPShots.serve(start, side: .child, tuning: tuning)); gestureCommitted = true
        }
        if !cancelled && playable && awaitingServe && level.pro && !gestureCommitted && gestureTravel >= 0.025,
           let last = gestureLast, last.distance(.init(0.5, 0.87)) <= tuning.swipeCollisionForgiveness { commitSwipe(last, velocity) }
        gestureStart = nil; gestureLast = nil; gestureTravel = 0
        // A committed stroke continues through its wind-up after finger-up. Cancel still drops input immediately; it
        // never leaves a delayed contact behind.
        if cancelled { pendingSwipe = nil; preparedStrokeTime = 0 }
        if cancelled || !childStroke.active { velocity = .zero; paddle = nil }
    }
    func release() { endTouch(cancelled: true); paddle = nil }
    private func tryReturn() {
        guard let f = flight, !f.resolved, childReturnOpen, f.receiver, f.striker == .minik else { return }
        let reach = returnBaseline - (level == .medium ? 0.10 : 0)
        if let prepared = pendingSwipe {
            if f.position.y >= reach { var c = prepared; c.point = f.position; returnChild(c) }
            return
        }
        if level.pro && f.position.y < returnBaseline { return }
        guard let p = level.pro ? paddle : pendingTap else { return }
        if level.pro && velocity.y >= -0.04 { return }
        // Android 2026-10: a timely Standard tap needs no hidden spatial target; it meets the ball itself.
        var c: MPContact?
        if level.pro { c = MPShots.swipeContact(p, ball: f.position, velocity: velocity, tuning: touchTuning) }
        else if f.position.y >= reach && f.position.strikeZone { c = MPShots.tapContact(f.position, ball: f.position, timing: 0, tuning: tuning) }
        guard var contact = c else { return }
        if !level.pro { contact.direction = tapAim; contact.velocity = tapVelocity }
        returnChild(contact)
    }
    private func returnChild(_ input: MPContact) {
        guard var f = flight else { return }
        if childCanReach?(f.position, f.height) == false { return }
        var c = input; c.point = f.position
        contact(.child, f.position, f.height); childReturnOpen = false; pendingTap = nil; pendingSwipe = nil; preparedStrokeTime = 0
        committedStroke = c.stroke
        f.hit(c, side: .child, tuning: tuning, rally: rally, pro: level.pro, safeTap: automaticContact)
        f.velocity = rallyVariation.hit(f.position, f.velocity)
        rally += 1; flight = f; status = "GOOD_RETURN"
        tapAim = 0; tapVelocity = .zero; tapStart = paddle
        planReturn()
    }
    func snapshot() -> MPState { .init(score: score, flight: flight, rally: rally, pointDelay: pointDelay, serveDelay: serveDelay, status: status, pendingFault: pendingFault, faultTime: faultTime, reception: reception) }
    func restore(_ s: MPState, preserveInput: Bool = false) {
        guard s.valid else { return }
        // Android restoreState: the shared clock is restored first, even for an acknowledged local flight.
        reception = s.reception ?? MPReceptionAssist()
        let before = ball, previousRallies = score.rallies, previousLoose = looseBall
        let samePoint = preserveInput && s.score.rallies == score.rallies && s.score.child == score.child && s.score.minik == score.minik && s.score.winner == nil
        // An acknowledgement of the same point, rally and striker must not rewind the locally
        // predicted flight or replay its contact. A fresh reconnect still restores fully.
        if samePoint, s.rally == rally, let acknowledged = s.flight, let local = flight, acknowledged.striker == local.striker,
           !acknowledged.resolved, !local.resolved, s.pendingFault == nil, s.pointDelay == nil { return }
        let remoteStrike = preserveInput && s.flight?.striker == .minik && s.flight?.resolved == false && (s.rally != rally || flight?.striker != .minik || s.score.rallies != score.rallies)
        if !samePoint { release(); childStroke.cancel(); pendingServe = nil; pendingTap = nil; pendingSwipe = nil; rallyVariation.reset() }
        if !preserveInput || !samePoint { minikStroke.cancel() }
        plan = nil; minikDelay = nil; score = s.score; flight = s.flight; rally = s.rally; pointDelay = s.pointDelay
        pendingFault = s.pendingFault; faultTime = s.faultTime; serveDelay = networked ? nil : s.serveDelay
        awaitingServe = flight == nil && pointDelay == nil && serveDelay == nil && score.server == .child && score.winner == nil
        childReturnOpen = flight.map { $0.receiver && !$0.resolved && $0.striker == .minik } ?? false
        status = awaitingServe ? "TAP_SERVE" : childReturnOpen ? "RETURN_BALL" : s.status
        lastResolution = nil; outBall = nil; looseBall = nil; faultMark = nil
        if !samePoint { attemptedTap = false }; events.removeAll()
        // Android 920caca: a checkpoint between points keeps (or starts) the loose ball, never parks it.
        if s.pointDelay != nil, let f = s.flight {
            let ball = previousRallies == s.score.rallies && previousLoose != nil ? previousLoose!
                : MPLooseBall(position: f.position, height: f.height, velocity: f.velocity, lift: f.lift, floor: visibleFloor)
            looseBall = ball; outBall = ball.position; outHeight = ball.height
        }
        if remoteStrike, let f = flight {
            // The peer already committed any rally variation; only count this return.
            if s.rally > 0 { rallyVariation.hit(f.position, f.velocity, adjust: false) }
            swing(.minik, f.position, f.height); contact(.minik, f.position, f.height); motion.approach(MPProjection.body(f.position, f.height, f.position.x < 0.5), seconds: 0.10, left: f.position.x < 0.5)
        }
        if !networked && flight?.striker == .child { planReturn() }
        correction = .init(before.x - ball.x, before.y - ball.y); correctionAge = before.distance(ball) < 0.4 ? 0.12 : 0
    }
    @discardableResult func remoteStrike(_ f: MPFlight, rallies: Int, hit: Int) -> Bool {
        guard networked, rallies == score.rallies, score.winner == nil, f.valid, f.striker == .minik, !f.resolved else { return false }
        if f.serve != nil { guard score.server == .minik, flight == nil, pointDelay == nil, hit == 0 else { return false } }
        else { guard flight?.striker == .child, hit == rally + 1, (0...0.28).contains(f.position.y), f.position.inside, !f.receiver else { return false } }
        flight = f; looseBall = nil; outBall = nil; pendingFault = nil; pointDelay = nil; serveDelay = nil; awaitingServe = false; childReturnOpen = false
        if f.serve == nil { rallyVariation.hit(f.position, f.velocity, adjust: false) }
        rally = hit; lastResolution = nil; attemptedTap = false; swing(.minik, f.position, f.height); contact(.minik, f.position, f.height)
        motion.approach(MPProjection.body(f.position, f.height, f.position.x < 0.5), seconds: 0.10, left: f.position.x < 0.5)
        status = "MINIK_RETURN"; return true
    }
    private static func segmentDistance(_ a: MPPoint, _ b: MPPoint, _ p: MPPoint) -> Double {
        let dx = b.x - a.x, dy = b.y - a.y, denominator = dx * dx + dy * dy
        let t = denominator == 0 ? 0 : (((p.x - a.x) * dx + (p.y - a.y) * dy) / denominator).mpClamp(0, 1)
        return MPPoint(a.x + dx * t, a.y + dy * t).distance(p)
    }
}
