import Foundation

// Android cross/CrossHouse.kt (MinikCrossPong 828c6fc), with Android HouseStrategy/ServeReliability/MinikProfile.nextReturnSpeed
// on Kotlin's random sequence (MPKotlinRandom), so a house player with the same seed makes the same choices as on Android.

/// Android `ActorPresentation`: the house/remote player's stroke timing (iOS `MPEngine.minikStroke`).
enum CrossActor {
    static let windup = 0.20
    static let followEnd = 0.44
    static let total = 0.68
}

/// Racket footwork of one seat in its own frame (u lateral, v depth), eased like the classic Minik approach (smoothstep) on the
/// physics clock. `speedLimit` (world units/s) bounds settling; intercept plans are checked against it before they start.
final class CrossMotion {
    static let minTime = 0.08
    static let settleTime = 0.45
    let home: CrossLocal
    let speedLimit: Double
    private(set) var racket: CrossLocal
    /// Hand of the current approach only. Drawing keeps the stroke's hand (the last swing's), so footwork never flips it.
    private(set) var left = false
    private(set) var walkAge = 0.0
    private(set) var destination: CrossLocal
    private var origin: CrossLocal
    private var duration = 0.0
    private var age = 0.0
    init(home: CrossLocal, speedLimit: Double = .infinity) {
        self.home = home; self.speedLimit = speedLimit
        racket = home; destination = home; origin = home
    }
    var moving: Bool { age < duration }
    var remaining: Double { max(0, duration - age) }
    func approach(_ to: CrossLocal, seconds: Double, left: Bool) {
        self.left = left; origin = racket; destination = to; duration = max(seconds, CrossMotion.minTime); age = 0; walkAge = 0
    }
    func advance(_ dt: Double) {
        if !moving { return }
        // Snap the last substep so a planned arrival is never a rounding error late.
        age = age + dt >= duration - 1e-9 ? duration : age + dt
        walkAge += dt
        let t = age / duration, eased = t * t * (3 - 2 * t)
        racket = CrossLocal(origin.u + (destination.u - origin.u) * eased, origin.v + (destination.v - origin.v) * eased)
    }
    /// Back home between rallies, never faster than the speed limit.
    func settle() {
        if destination != home { approach(home, seconds: max(CrossMotion.settleTime, CrossMotion.distance(racket, home) / speedLimit), left: left) }
    }
    func place(_ at: CrossLocal, left: Bool? = nil) {
        racket = at; origin = at; destination = at; self.left = left ?? self.left; age = 0; duration = 0
    }
    func reset() { place(home, left: false); walkAge = 0 }
    static func distance(_ a: CrossLocal, _ b: CrossLocal) -> Double { hypot(a.u - b.u, a.v - b.v) }
}

/// A house player's plan: contact at absolute engine substep `tick`, the ball predicted at `point`/`height`.
struct CrossIntercept {
    var tick: Int64
    var point: MPPoint
    var height: Double
    var left: Bool
    var reachable: Bool
}

/// The live ball's first receiving bounce, `ticks` engine substeps ahead; `probe` continues from just after it.
final class CrossReceiving {
    let owner: Int
    let point: MPPoint
    let ticks: Int
    let probe: CrossBall
    init(owner: Int, point: MPPoint, ticks: Int, probe: CrossBall) { self.owner = owner; self.point = point; self.ticks = ticks; self.probe = probe }
}

/// A predicted contact chance `ticks` substeps ahead; `inZone` = inside the seat's strike zone at a playable height.
struct CrossReach {
    var ticks: Int
    var state: CrossBallState
    var inZone: Bool
}

/// Receiver prediction and intercepts on copies stepped exactly like the live ball (engine substeps).
enum CrossForecast {
    static let ticks = 720
    static let reachHeight = 0.55
    static let rise = 0.08
    /// Through a serve's own bounce to the first bounce that makes a receiver; nil when the flight ends in a fault first
    /// (net, out, own side, bad serve). The live ball never moves.
    static func receiving(_ geometry: CrossGeometry, _ ball: CrossBall, striker: Int, limit: Int = CrossForecast.ticks) -> CrossReceiving? {
        let probe = ball.copy()
        var own = probe.rebound != nil
        guard limit >= 1 else { return nil }
        for tick in 1...limit {
            guard let event = probe.step(CrossBall.substep) else { continue }
            guard case let .bounce(point, owner) = event else { return nil }
            if own {
                if !geometry.inServeZone(striker, point) { return nil }
                own = false
                continue
            }
            return owner == striker ? nil : CrossReceiving(owner: owner, point: point, ticks: tick, probe: probe)
        }
        return nil
    }
    /// First point inside `seat`'s strike zone at height <= reachHeight after the bounce and not before `earliest` substeps
    /// (the reaction time from the strike), once the ball has risen `rise` off the table or is coming down (no half-volley in
    /// the bounce's own substep). Fallback: the first point after both, outside the zone.
    static func intercept(_ geometry: CrossGeometry, seat: Int, _ r: CrossReceiving, earliest: Int, limit: Int = CrossForecast.ticks) -> CrossReach {
        let probe = r.probe
        var tick = r.ticks
        var fallback = CrossReach(ticks: tick, state: probe.state, inZone: false)
        var late = false
        while tick <= limit {
            if tick >= earliest {
                let s = probe.state
                // House players stand outside the table: they wait for the ball near its end rather than returning from the
                // inner edge of the human reach window (5c1aa4d).
                if geometry.toLocal(seat, s.position).v >= CrossGeometry.reach - 0.12 && geometry.inStrikeZone(seat, s.position) &&
                    s.height <= reachHeight && (s.height >= rise || s.lift <= 0) {
                    return CrossReach(ticks: tick, state: s, inZone: true)
                }
                if !late { fallback = CrossReach(ticks: tick, state: s, inZone: false); late = true }
            }
            tick += 1
            if probe.step(CrossBall.substep) != nil || probe.stopped { break }
        }
        return fallback
    }
}

/// Classic RallyVariation for the shared table. It counts committed hits from every seat that send the ball straight back
/// along the previous lane (back to the previous striker, from within `lane` of the hitter's own last contact). The hit that
/// would be the fifth is a house player's cue to change lane (another opponent); a human shot is only counted, never bent.
final class CrossVariation {
    static let lane = 0.10
    static let limit = 5
    private var striker = -1
    private var target = -1
    private var lanes: [Int: Double] = [:]
    private(set) var straight = 0
    func reset() { striker = -1; target = -1; lanes = [:]; straight = 0 }
    /// Straight back to the previous striker, from about the hitter's own last spot (unknown on its first hit, as the classic
    /// lane counts the reply to the opening hit).
    private func continues(_ from: Int, _ to: Int, _ lateral: Double) -> Bool {
        from == target && to == striker && (lanes[from].map { abs($0 - lateral) <= CrossVariation.lane } ?? true)
    }
    /// A hit from `from` at `lateral` back to `to` would be the fifth straight one.
    func due(_ from: Int, _ to: Int, _ lateral: Double) -> Bool { continues(from, to, lateral) && straight + 1 >= CrossVariation.limit }
    func hit(_ from: Int, _ to: Int, _ lateral: Double) {
        straight = continues(from, to, lateral) ? straight + 1 : 1
        striker = from; target = to; lanes[from] = lateral
        if straight >= CrossVariation.limit { straight = 0 }
    }
}

/// Android `HouseStrategy` on Kotlin's random sequence: short placement patterns with skill-scaled width/tempo.
final class CrossHouseStrategy {
    private let skill: Double
    private var plan: [(x: Double, pace: Double)] = []
    private var previousZone = -1
    private var repeats = 0
    init(skill: Double) { self.skill = skill }
    func reset() { plan = []; previousZone = -1; repeats = 0 }
    func aim(_ incomingX: Double, random: inout MPKotlinRandom) -> (x: Double, pace: Double) {
        let variety = ((skill - 6) / 4).mpClamp(0, 1)
        let left = 0.24 - 0.12 * variety
        let right = 1 - left
        if plan.isEmpty {
            let same = incomingX < 0.40 ? left : (incomingX > 0.60 ? right : 0.50)
            let opposite: Double
            if same < 0.5 { opposite = right } else if same > 0.5 { opposite = left } else { opposite = random.nextBoolean() ? left : right }
            let first = random.nextBoolean() ? left : right
            let other = 1 - first
            let choice = random.nextDouble()
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
        // This also covers boundaries between patterns. Tiny jitter is not a new placement.
        if CrossHouseStrategy.zone(target) == previousZone && repeats >= 2 {
            switch previousZone {
            case 0: target = right
            case 2: target = left
            default: target = random.nextBoolean() ? left : right
            }
        }
        let nextZone = CrossHouseStrategy.zone(target)
        repeats = nextZone == previousZone ? repeats + 1 : 1
        previousZone = nextZone
        let jitter = random.nextDouble(-0.02, 0.02)
        return ((target + jitter).mpClamp(0.08, 0.92), shot.pace)
    }
    static func zone(_ x: Double) -> Int { min(2, max(0, Int(x * 3))) }
}

/// Android `ServeReliability` on Kotlin's random sequence: the requested long-run fault rate without clusters.
final class CrossServeReliability {
    private var shielded = 0
    private var attempts = 0
    func fault(_ rate: Double, random: inout MPKotlinRandom) -> Bool {
        attempts += 1
        if shielded > 0 { shielded -= 1; return false }
        let p = rate.mpClamp(0, 0.30)
        let protection = p < 0.20 ? 4 : 2
        let hazard = attempts == 1 ? p : p / (1 - Double(protection) * p)
        let result = random.nextDouble() < hazard
        if result { shielded = protection }
        return result
    }
}

/// Target opponent, placement and pace multiplier of a house player's good returns (HouseStrategy adapted to the cross
/// table). Weaker players mostly send the ball back to its sender, centrally; stronger ones switch opponents, go wider and
/// deeper. Never the same opponent more than `maxRepeats` times in a row (serves included).
final class CrossStrategy {
    static let maxRepeats = 3
    static let midDepth = (CrossAimMap.sideNear + CrossGeometry.reach - 0.15) / 2
    let geometry: CrossGeometry
    let seat: Int
    let variety: Double
    /// P(switching away from the sender).
    let switching: Double
    let opponents: [Int]
    private let patterns: CrossHouseStrategy
    private(set) var lastTarget = -1
    private(set) var repeats = 0
    init(_ geometry: CrossGeometry, seat: Int, skill: Double) {
        self.geometry = geometry; self.seat = seat
        variety = ((skill - 6) / 4).mpClamp(0, 1)
        switching = 0.35 + 0.45 * ((skill - 6) / 4).mpClamp(0, 1)
        let own = geometry.wrap(seat)
        opponents = geometry.seats.filter { $0 != own }
        patterns = CrossHouseStrategy(skill: skill)
    }
    func newRally() { patterns.reset() }
    func reset() { patterns.reset(); lastTarget = -1; repeats = 0 }
    /// The sender unless switching (a nil sender, the serve, picks freely); `lane` marks a target that would continue a straight
    /// repeated lane, which is avoided like a fourth repeat.
    func target(_ sender: Int?, random: inout MPKotlinRandom, lane: (Int) -> Bool = { _ in false }) -> Int {
        let back: Int? = sender.flatMap { opponents.contains($0) ? $0 : nil }
        var choice: Int
        if let back, random.nextDouble() >= switching { choice = back }
        else {
            let others = opponents.filter { $0 != back }
            choice = random.element(others.isEmpty ? opponents : others)
        }
        let last = lastTarget, count = repeats
        let overused: (Int) -> Bool = { $0 == last && count >= CrossStrategy.maxRepeats }
        // Prefer an opponent that breaks both; the repeat limit wins when only two opponents conflict.
        if overused(choice) || lane(choice) {
            var pool = opponents.filter { !overused($0) && !lane($0) }
            if pool.isEmpty { pool = opponents.filter { !overused($0) } }
            if pool.isEmpty { pool = opponents }
            choice = random.element(pool)
        }
        repeats = choice == lastTarget ? repeats + 1 : 1
        lastTarget = choice
        return choice
    }
    /// Landing point inside `target`'s arm and HouseStrategy's pace multiplier; `incomingU` is the contact's lateral.
    func place(_ target: Int, incomingU: Double, random: inout MPKotlinRandom) -> (point: MPPoint, pace: Double) {
        let pattern = patterns.aim((incomingU / CrossGeometry.width + 0.5).mpClamp(0, 1), random: &random)
        let u = ((pattern.x - 0.5) * CrossGeometry.width * (0.6 + 0.4 * variety)).mpClamp(-CrossAimMap.edgeU, CrossAimMap.edgeU)
        let spread = random.nextDouble(-1, 1)
        let depth = (CrossStrategy.midDepth + spread * (0.06 + 0.105 * variety)).mpClamp(CrossAimMap.sideNear, CrossGeometry.reach - 0.15)
        return (geometry.fromLocal(target, u, depth), pattern.pace)
    }
}

/// A house ball toward `point` in `target`'s territory; a `fault` is the player's genuine bad shot (flat into a net, long beyond
/// an arm end, or short into its own territory).
struct CrossHouseShot {
    var target: Int
    var point: MPPoint
    var launch: CrossLaunch
    var fault = false
}

/// One house player: the character's own tuning (`MPBot.tuning(level, houseControls: true)` = Android
/// `BotProfile.controlTuning`, so every relative strength is kept), its footwork limit, intercept plan, the classic contact roll
/// (`MPShots.aiContact` exactly as the classic house return) and its shot and serve choice. Only the authority runs it; peers
/// animate house players from checkpoints.
final class CrossHouse {
    /// World units/s per movement multiplier (850 source px/s at 754 px per unit).
    static let speed = 1.13
    static let contactReach = 0.12
    static let good = 0.14
    static let innerDepth = 0.45
    static let serveBounce = 0.78

    let geometry: CrossGeometry
    let physics: MPTuning
    let seat: Int
    let profile: MPBot
    let tuning: MPTuning
    let skill: Double
    let speedLimit: Double
    let reactionTicks: Int
    var random: MPKotlinRandom
    let strategy: CrossStrategy
    private let reliability = CrossServeReliability()
    private let minik: Bool
    var plan: CrossIntercept?
    /// The planned stroke has started: one swing per plan.
    var swung = false
    private var lastX: Double?
    private var responses = 0
    private var receivedServe = false
    private var lastSpeed: [Double] = [.nan, .nan]

    init(_ geometry: CrossGeometry, physics: MPTuning, seat: Int, profile: MPBot, control: MPLevel, seed: Int64) {
        self.geometry = geometry; self.physics = physics; self.seat = seat; self.profile = profile
        let own = profile.tuning(control, houseControls: true)
        tuning = own
        skill = profile.tacticalSkill
        speedLimit = CrossHouse.speed * profile.movement
        reactionTicks = Int(ceil(own.minikReactionInterval / CrossBall.substep - 1e-9))
        random = MPKotlinRandom(seed: seed)
        strategy = CrossStrategy(geometry, seat: seat, skill: profile.tacticalSkill)
        minik = profile.characterId == "minik"
    }
    func newRally() { plan = nil; swung = false; lastX = nil; responses = 0; receivedServe = false; lastSpeed = [.nan, .nan]; strategy.newRally() }
    func reset() { newRally(); strategy.reset() }
    /// Plans the contact of a ball predicted for this seat and approaches so the racket arrives WINDUP before contact. Beyond
    /// the speed limit the plan is unreachable: the racket moves at that limit and falls short (no teleport).
    @discardableResult func makePlan(_ reach: CrossReach, now: Int64, motion: CrossMotion) -> CrossIntercept {
        let at = geometry.toLocal(seat, reach.state.position)
        let left = at.u < 0
        let available = max(CrossMotion.minTime, Double(reach.ticks) * CrossBall.substep - CrossActor.windup)
        let spot = CrossLocal(at.u.mpClamp(-CrossGeometry.strikeHalf, CrossGeometry.strikeHalf), at.v.mpClamp(CrossGeometry.strikeNear, CrossGeometry.strikeFar))
        let from = motion.racket
        let travel = CrossMotion.distance(from, spot)
        let reachable = reach.inZone && travel <= speedLimit * available + 1e-9
        let k = reachable || travel < 1e-9 ? 1.0 : min(1.0, speedLimit * available / travel)
        motion.approach(CrossLocal(from.u + (spot.u - from.u) * k, from.v + (spot.v - from.v) * k), seconds: available, left: left)
        swung = false
        let intercept = CrossIntercept(tick: now + Int64(reach.ticks), point: reach.state.position, height: reach.state.height, left: left, reachable: reachable)
        plan = intercept
        return intercept
    }
    /// The contact roll at the planned tick, as the classic house return: serve-receive or return chances by zone third,
    /// cross-court, response-index degradation and the next return speed per hand. `served` = this seat served this rally,
    /// `serveBall` = the incoming ball is the serve. nil = no contact (a miss).
    func roll(_ ball: CrossBallState, racket: MPPoint, reachable: Bool, ready: Bool, served: Bool, serveBall: Bool) -> MPContact? {
        let p = tuning.profile
        let local = geometry.toLocal(seat, ball.position)
        let x = (local.u / CrossGeometry.width + 0.5).mpClamp(0, 1)
        let zone = MPZone.at(x)
        let firstReceive = serveBall && responses == 0
        if firstReceive { receivedServe = true }
        let firstMiddle = minik && served && responses == 0 && zone == .middle
        let base: MPChance
        if firstMiddle { base = MPChance(1, 0.95) }
        else if firstReceive { base = p.serveReceive[zone.rawValue] }
        else { base = p.chance(zone, cross: false) }
        let cross = firstReceive || firstMiddle ? base : p.chance(zone, cross: true)
        let hand = zone == .forehand || (zone == .middle && x >= 0.5) ? 0 : 1
        let returnSpeed = CrossHouse.nextReturnSpeed(p, base: tuning.ballBaseSpeed, previous: lastSpeed[hand], forehand: hand == 0, random: &random)
        let responseIndex = receivedServe ? max(0, responses - 1) : responses
        responses += 1
        if !reachable || !ready || racket.distance(ball.position) > CrossHouse.contactReach { return nil }
        let answerRoll = random.nextDouble()
        let qualityRoll = random.nextDouble()
        guard let c = MPShots.aiContact(x: x, speed: ball.velocity.length / CrossShots.paceScale, depth: (CrossGeometry.reach - local.v) / CrossShots.drivenScale,
                                        tuning: tuning, base: base, cross: cross, previousX: lastX, response: responseIndex,
                                        answerRoll: answerRoll, qualityRoll: qualityRoll, pace: returnSpeed) else { return nil }
        lastX = x; lastSpeed[hand] = returnSpeed
        return c
    }
    /// The return for contact `c` at `from`: a good shot to the strategy's opponent and spot at the character's pace (next return
    /// speed x pattern, capped by its maxSpeed), or for quality < good a genuine own fault.
    func shot(_ c: MPContact, from: MPPoint, height: Double, sender: Int?, lane: (Int) -> Bool = { _ in false }) -> CrossHouseShot {
        let local = geometry.toLocal(seat, from)
        if c.quality < CrossHouse.good { return fault(from, height: height, local: local) }
        let target = strategy.target(sender, random: &random, lane: lane)
        let placed = strategy.place(target, incomingU: local.u, random: &random)
        let pace = min(c.velocity.y * placed.pace, tuning.ballBaseSpeed * tuning.profile.maxSpeed) * CrossShots.paceScale
        return CrossHouseShot(target: target, point: placed.point, launch: CrossShots.targeted(geometry, physics, from: from, height: height, target: placed.point, pace: pace))
    }
    /// A genuine own fault, one of three: flat into a net (lowered lift), long beyond an opponent's arm end (aim noise, out), or
    /// short into its own territory. A path that meets no net falls back to the short ball.
    private func fault(_ from: MPPoint, height: Double, local: CrossLocal) -> CrossHouseShot {
        let pace = CrossShots.basePace(tuning)
        switch random.nextIndex(3) {
        case 0:
            let target = random.element(strategy.opponents)
            let point = geometry.fromLocal(target, random.nextDouble(-0.2, 0.2), CrossHouse.innerDepth)
            let f = geometry.netSpans(from, point).map(\.start).min()
            if let f, f > 0.02 {
                // Hit flat and hard: the ball is down at 40 % of the net height where its path meets the first net.
                let tau = ((point - from).length * f / (2 * pace)).mpClamp(0.3, 0.7)
                let lift = (physics.netHeight * 0.4 - height + 0.5 * physics.gravity * tau * tau) / tau
                return CrossHouseShot(target: target, point: point, launch: CrossLaunch(velocity: (point - from) * (f / tau), lift: lift), fault: true)
            }
        case 1:
            let target = random.element(strategy.opponents)
            let lateral = random.nextDouble(-0.2, 0.2)
            let point = geometry.fromLocal(target, lateral, CrossGeometry.reach + random.nextDouble(0.12, 0.3))
            return CrossHouseShot(target: target, point: point, launch: CrossShots.targeted(geometry, physics, from: from, height: height, target: point, pace: pace), fault: true)
        default: break
        }
        let point = geometry.fromLocal(seat, (local.u * 0.5).mpClamp(-0.3, 0.3), CrossHouse.innerDepth)
        return CrossHouseShot(target: seat, point: point, launch: CrossShots.targeted(geometry, physics, from: from, height: height, target: point, pace: pace), fault: true)
    }
    /// The classic house serve adapted: serve reliability decides a fault, whose first bounce misses the own serve area;
    /// otherwise a two-bounce serve, first in the own serve zone, then in `target`'s (else a chosen opponent's) territory, at the
    /// character's serve pace. `middle`: the tour's return lesson serves to the middle of the learner's arm, where the paddle
    /// starts, so the lesson is about choosing the player.
    func serve(_ start: MPPoint, target: Int? = nil, allowFault: Bool = true, middle: Bool = false) -> CrossServe {
        let p = tuning.profile
        var faulty = false
        if allowFault { faulty = reliability.fault(tuning.minikServeFaultProbability, random: &random) }
        let to: Int
        if let target { to = target } else { to = strategy.target(nil, random: &random) }
        let x: Double
        if middle { x = random.nextDouble(0.46, 0.54) }
        else if random.nextDouble() < p.serveMiddle { x = random.nextDouble(0.40, 0.60) }
        else if random.nextBoolean() { x = random.nextDouble(0.04, 1.0 / 6) }
        else { x = random.nextDouble(5.0 / 6, 0.96) }
        let magnitude = random.nextDouble() * p.serveVariation
        let variation = magnitude * (random.nextBoolean() ? 1 : -1)
        let pace = CrossShots.basePace(tuning) * p.serveSpeed * (1 + variation)
        let lateral = ((x - 0.5) * CrossGeometry.width).mpClamp(-CrossAimMap.edgeU, CrossAimMap.edgeU)
        let second = geometry.fromLocal(to, lateral, random.nextDouble(0.72, 0.95))
        let first: MPPoint
        if faulty {
            let side: Double = random.nextBoolean() ? 1 : -1
            first = geometry.fromLocal(seat, side * (CrossGeometry.half + 0.12), CrossHouse.serveBounce)
        } else { first = geometry.fromLocal(seat, (x - 0.5) * 0.30, CrossHouse.serveBounce) }
        return CrossShots.serve(geometry, physics, server: seat, start: start, first: first, second: second, pace: pace)
    }
    /// Serve hand, as the classic minikForehandPreference.
    func serveHand() -> Bool { random.nextDouble() >= tuning.minikForehandPreference }
    /// Android `MinikProfile.nextReturnSpeed` on Kotlin's random sequence.
    static func nextReturnSpeed(_ p: MPProfile, base: Double, previous: Double, forehand: Bool, random: inout MPKotlinRandom) -> Double {
        let limit = base * p.maxSpeed
        if previous.isNaN { return base * (forehand ? p.firstForehandSpeed : p.firstBackhandSpeed) }
        // Near the cap, vary once around the previous hit, without stacking acceleration and jitter.
        if previous >= limit * 0.95 {
            let magnitude = random.nextDouble(0, 0.05)
            let change = magnitude * (random.nextBoolean() ? 1 : -1)
            return min(previous * (1 + change), limit)
        }
        let range = forehand ? p.forehandSpeedUp : p.backhandSpeedUp
        let change: Double
        if random.nextDouble() < p.accelerateChance { change = random.nextDouble(range.lowerBound, range.upperBound) }
        else { change = -random.nextDouble(p.speedDown.lowerBound, p.speedDown.upperBound) }
        return min(previous * (1 + change), limit)
    }
}
