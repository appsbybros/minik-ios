import Foundation

// Modern-only, normalized table coordinates. The legacy PingPong/retro engine is unchanged.
struct MPPoint: Codable, Equatable {
    var x: Double
    var y: Double
    init(_ x: Double, _ y: Double) { self.x = x; self.y = y }
    static let zero = MPPoint(0, 0)
    var inside: Bool { (0...1).contains(x) && (0...1).contains(y) }
    var strikeZone: Bool { (0...1).contains(x) && (0.72...1).contains(y) }
    func distance(_ p: Self) -> Double { hypot(x - p.x, y - p.y) }
    func onSide(_ s: MPSide) -> Bool { s == .child ? y > 0.5 : y < 0.5 }
    var reflected: Self { .init(1 - x, 1 - y) }
    var reversed: Self { .init(-x, -y) }
}
extension Double {
    func mpClamp(_ lo: Double, _ hi: Double) -> Double { min(hi, max(lo, self)) }
}
enum MPSide: String, Codable { case child = "CHILD", minik = "MINIK"
    var other: Self { self == .child ? .minik : .child }
}
/// Stable wire/room ordinals, identical to Android `Difficulty`: 0 STARTER, 1 EASY, 2 MEDIUM, 3 HARD, 4 BEGINNER.
/// Beginner was appended (ordinal 4) so older rooms keep their meaning.
enum MPLevel: Int, Codable, CaseIterable {
    case easy, medium, hard, superHard, beginner
    var pro: Bool { self == .superHard }
    /// Beginner: positioning the paddle is enough; the engine times the return.
    var automaticContact: Bool { self == .beginner }
    /// Android `Difficulty.needsTwoPointLead`: only MEDIUM and HARD (iOS `.hard`, `.superHard`).
    var needsTwoPointLead: Bool { self == .hard || self == .superHard }
    var targets: [Int] { needsTwoPointLead ? [3, 5, 7, 11] : [3, 5, 7, 10] }
    func target(_ n: Int) -> Int { targets.contains(n) ? n : 7 }
    var title: String {
        switch self {
        case .beginner: return "Beginner"
        case .easy: return "Easy"
        case .medium: return "Medium"
        case .hard: return "Hard"
        case .superHard: return "Super hard"
        }
    }
    /// Android `ControlChoice.normalize`: room/control choices are Beginner (4), Standard (0) or Pro (3).
    static func control(_ value: Int) -> MPLevel {
        switch value {
        case 0, 1, 2: return .easy
        case 3: return .superHard
        default: return .beginner
        }
    }
}
enum MPFault: String, Codable {
    case net = "NET", firstBounceOut = "FIRST_BOUNCE_OUT", secondBounce = "SECOND_BOUNCE"
    case leftTable = "LEFT_TABLE", illegalServe = "ILLEGAL_SERVE", unreturned = "UNRETURNED"
}
struct MPResolution: Codable, Equatable { var winner: MPSide; var fault: MPFault }
struct MPContact {
    var point: MPPoint; var timing: Double; var spatial: Double
    var velocity: MPPoint; var direction: Double
    /// House-player placement (Android `Contact.targetX`); only a good AI return uses it.
    var targetX: Double? = nil
    var quality: Double { ((timing + spatial) / 2).mpClamp(0, 1) }
}
struct MPShot: Codable, Equatable { var velocity: MPPoint; var arc: Double }
struct MPServe: Codable, Equatable {
    var server: MPSide; var start: MPPoint; var first: MPPoint; var second: MPPoint
    var speed: Double; var arc: Double; var shot: MPShot? = nil
    var reflected: Self { .init(server: server.other, start: start.reflected, first: first.reflected,
        second: second.reflected, speed: speed, arc: arc,
        shot: shot.map { .init(velocity: $0.velocity.reversed, arc: $0.arc) }) }
}
struct MPScore: Codable, Equatable {
    var child = 0; var minik = 0; var rallies = 0; var server: MPSide = .child
    var winner: MPSide?; var streak = 0
    var reflected: Self { .init(child: minik, minik: child, rallies: rallies, server: server.other,
                               winner: winner?.other, streak: 0) }
    mutating func award(_ side: MPSide, level: MPLevel, target: Int, first: MPSide?) -> Bool {
        guard winner == nil else { return false }
        if side == .child { child += 1; streak += 1 } else { minik += 1; streak = 0 }
        rallies += 1
        let high = max(child, minik), low = min(child, minik)
        let deuce = child >= target - 1 && minik >= target - 1
        if high >= target && (!level.needsTwoPointLead || high - low >= 2) { winner = side }
        else if let first {
            if level.needsTwoPointLead && deuce { server = server.other }
            else { server = (rallies / 2) % 2 == 0 ? first : first.other }
        }
        else if level == .easy { server = .minik }
        else if level == .medium { server = .child }
        else if deuce { server = server.other }
        else { server = (rallies / 2) % 2 == 0 ? .child : .minik }
        return true
    }
}
struct MPRandom {
    private var state: UInt64
    init(seed: UInt64 = UInt64.random(in: 1...UInt64.max)) { state = seed == 0 ? 1 : seed }
    mutating func unit() -> Double {
        state &+= 0x9e3779b97f4a7c15
        var z = state; z = (z ^ (z >> 30)) &* 0xbf58476d1ce4e5b9
        z = (z ^ (z >> 27)) &* 0x94d049bb133111eb
        return Double((z ^ (z >> 31)) >> 11) / 9007199254740992
    }
    mutating func range(_ a: Double, _ b: Double) -> Double { a + unit() * (b - a) }
}
enum MPZone: Int { case backhand, middle, forehand
    static let left = Self.backhand, right = Self.forehand
    static func at(_ x: Double) -> Self { x < 1.0 / 3 ? .backhand : x > 2.0 / 3 ? .forehand : .middle }
}
struct MPChance { var answer: Double; var good: Double
    init(_ answer: Double, _ good: Double) { self.answer = answer; self.good = good }
}
struct MPProfile {
    var forehandServe, serveSuccess, serveMiddle, serveSpeed, serveVariation: Double
    var serveReceive: [MPChance]
    var forehandSame, forehandCross, backhandSame, backhandCross: MPChance
    var answerDrop, goodDrop, backhandCrossGoodDrop: Double
    var firstForehandSpeed, firstBackhandSpeed, accelerateChance: Double
    var forehandSpeedUp, backhandSpeedUp, speedDown: ClosedRange<Double>
    var maxSpeed: Double
    func chance(_ zone: MPZone, cross: Bool) -> MPChance {
        zone == .backhand ? (cross ? backhandCross : backhandSame) :
            zone == .middle && cross ? backhandCross : (cross ? forehandCross : forehandSame)
    }
    func speed(base: Double, previous: Double?, forehand: Bool, random: inout MPRandom) -> Double {
        let cap = base * maxSpeed
        guard let previous else { return min(cap, base * (forehand ? firstForehandSpeed : firstBackhandSpeed)) }
        if previous >= cap * 0.95 {
            let magnitude = random.range(0, 0.05)
            return min(cap, previous * (1 + magnitude * (random.unit() < 0.5 ? -1 : 1)))
        }
        let range = forehand ? forehandSpeedUp : backhandSpeedUp
        let change = random.unit() < accelerateChance ? random.range(range.lowerBound, range.upperBound) : -random.range(speedDown.lowerBound, speedDown.upperBound)
        return min(cap, previous * (1 + change))
    }
}
struct MPTuning {
    var tapSpatialTolerance, tapTimingWindow, tapTimingQualityExponent: Double
    var swipeCollisionForgiveness, swipeVelocityScale, minimumSwipeSpeed, maximumSwipeSpeed: Double
    var serveAssistance, ballBaseSpeed, rallySpeedGrowth, maximumBallSpeed: Double
    var gravity, bounceRestitution, netHeight, netClearanceVelocityTarget, maximumArcVelocity: Double
    var incomingVelocityInfluence, minikReactionInterval, minikMaximumReach, minikPredictionAmount: Double
    var minikAimError, minikErrorProbability, minikPoorContactProbability, minikCornerPreference: Double
    var minikReturnSpeedMultiplier, minikForehandPreference, minikServeFaultProbability: Double
    var profile: MPProfile
    init(_ a: [Double], profile: MPProfile) {
        precondition(a.count == 27)
        tapSpatialTolerance = a[0]; tapTimingWindow = a[1]; tapTimingQualityExponent = a[2]
        swipeCollisionForgiveness = a[3]; swipeVelocityScale = a[4]; minimumSwipeSpeed = a[5]; maximumSwipeSpeed = a[6]
        serveAssistance = a[7]; ballBaseSpeed = a[8]; rallySpeedGrowth = a[9]; maximumBallSpeed = a[10]
        gravity = a[11]; bounceRestitution = a[12]; netHeight = a[13]; netClearanceVelocityTarget = a[14]; maximumArcVelocity = a[15]
        incomingVelocityInfluence = a[16]; minikReactionInterval = a[17]; minikMaximumReach = a[18]; minikPredictionAmount = a[19]
        minikAimError = a[20]; minikErrorProbability = a[21]; minikPoorContactProbability = a[22]; minikCornerPreference = a[23]
        minikReturnSpeedMultiplier = a[24]; minikForehandPreference = a[25]; minikServeFaultProbability = a[26]
        self.profile = profile
    }
}
enum MPShots {
    /// Android `Shots.forgivingTap`. Standard converts the gesture speed (`c.velocity`) into a moderate pace boost;
    /// Beginner passes zero velocity. Contact and net clearance are assisted, the sidelines are not:
    /// a genuinely wide aim may leave the table.
    static func tap(_ c: MPContact, _ t: MPTuning, rally: Int, height: Double, incoming: MPPoint) -> MPShot {
        let power = (hypot(c.velocity.x, c.velocity.y) / t.maximumSwipeSpeed).mpClamp(0, 1)
        let pace = min(t.maximumBallSpeed, t.ballBaseSpeed * (1 + 0.35 * power) + min(Double(rally) * t.rallySpeedGrowth, 0.12) + min(hypot(incoming.x, incoming.y) * t.incomingVelocityInfluence, 0.05))
        let time = max(0.45, (c.point.y - 0.26) / pace)
        let inherited = (incoming.x / max(abs(incoming.y), 0.12) * pace * 0.42).mpClamp(-0.25, 0.25)
        let aim = c.direction.mpClamp(-2, 2) * pace * 0.70
        return .init(velocity: .init(inherited + aim, -pace), arc: (0.5 * t.gravity * time * time - height) / time)
    }
    static func driven(_ c: MPContact, _ t: MPTuning, height: Double, incoming: MPPoint) -> MPShot {
        let forward = max(0, -c.velocity.y), power = (forward / t.maximumSwipeSpeed).mpClamp(0, 3)
        let pace = 0.18 + power * 1.28 + min(abs(incoming.y) * t.incomingVelocityInfluence, 0.06)
        let slope = (c.velocity.x / max(forward, 0.16)).mpClamp(-1.5, 1.5)
        let lift = 0.25 + 1.55 * (1 - exp(-power * 4)) - 0.20 * power - height * 0.45 - (1 - c.quality) * 0.16
        return .init(velocity: .init(pace * slope * 0.65, -pace), arc: lift)
    }
    static func ai(_ c: MPContact, _ t: MPTuning, height: Double) -> MPShot {
        let speed = max(c.velocity.y, 0.1)
        let target = c.quality >= 0.14 ? 0.78 : (c.point.y + 0.5) * 0.5
        let time = max(0.05, (target - c.point.y) / speed)
        let requested = c.targetX.map { ($0 - c.point.x) / time } ?? c.direction * speed * 0.48
        let x = requested.mpClamp((0.06 - c.point.x) / time, (0.94 - c.point.x) / time)
        return .init(velocity: .init(x, speed), arc: (0.5 * t.gravity * time * time - height) / time)
    }
    static func serve(_ p: MPPoint, side: MPSide, tuning t: MPTuning) -> MPServe {
        let same = p.onSide(side), child = side == .child
        let scale = t.serveAssistance >= 0.6 ? 1 - t.serveAssistance * 0.35 : 1 + (0.6 - t.serveAssistance) * 0.55
        let x = 0.5 + (p.x.mpClamp(0, 1) - 0.5) * scale
        let firstX = 0.5 + (x - 0.5) * (same ? 0.30 : 0.5)
        let firstY = child ? (same ? p.y.mpClamp(0.61, 0.83) : 0.72) : (same ? p.y.mpClamp(0.17, 0.39) : 0.28)
        let secondY = child ? (same ? 0.28 : p.y.mpClamp(0.17, 0.39)) : (same ? 0.72 : p.y.mpClamp(0.61, 0.83))
        return .init(server: side, start: .init(0.5, child ? 0.87 : 0.13), first: .init(firstX, firstY), second: .init(x, secondY), speed: t.ballBaseSpeed, arc: 1.05 + t.serveAssistance * 0.22)
    }
    static func swipeServe(_ c: MPContact, _ t: MPTuning) -> MPServe? {
        let speed = hypot(c.velocity.x, c.velocity.y)
        guard speed >= 0.04, c.velocity.y < -0.04 else { return nil }
        let direction = (c.velocity.x * 0.28).mpClamp(-0.55, 0.55)
        func assist(_ raw: Double, _ safe: Double) -> Double { raw * (1 - t.serveAssistance) + safe * t.serveAssistance }
        let first = c.point.x + direction * 0.35, second = c.point.x + direction
        let power = (abs(c.velocity.y).mpClamp(t.minimumSwipeSpeed, t.maximumSwipeSpeed) - t.minimumSwipeSpeed) / max(0.01, t.maximumSwipeSpeed - t.minimumSwipeSpeed)
        return .init(server: .child, start: .init(c.point.x, 0.87), first: .init(assist(first, first.mpClamp(0.16, 0.84)), 0.72),
            second: .init(assist(second, second.mpClamp(0.16, 0.84)), assist(0.55 - power * 0.90, 0.28)),
            speed: min(t.maximumBallSpeed, t.ballBaseSpeed + speed * t.swipeVelocityScale * 0.35), arc: 1.15 + min(speed, 1) * 0.22,
            shot: t.serveAssistance < 0.9 ? driven(c, t, height: 0, incoming: .zero) : nil)
    }
    static func tapContact(_ point: MPPoint, ball: MPPoint, timing: Double, tuning t: MPTuning) -> MPContact? {
        let distance = point.distance(ball)
        guard point.strikeZone, distance <= t.tapSpatialTolerance, abs(timing) <= t.tapTimingWindow else { return nil }
        return .init(point: point, timing: pow(1 - abs(timing) / t.tapTimingWindow, t.tapTimingQualityExponent),
            spatial: 1 - distance / t.tapSpatialTolerance, velocity: .zero, direction: 0)
    }
    static func swipeContact(_ point: MPPoint, ball: MPPoint, velocity: MPPoint, tuning t: MPTuning) -> MPContact? {
        guard point.strikeZone, point.distance(ball) <= t.swipeCollisionForgiveness else { return nil }
        let speed = hypot(velocity.x, velocity.y), scale = speed > 0 ? min(speed, t.maximumSwipeSpeed * 3) / speed : 0
        let safe = speed > 0 ? MPPoint(velocity.x * scale, velocity.y * scale) : MPPoint(0, -t.minimumSwipeSpeed)
        return .init(point: point, timing: 1, spatial: 1 - point.distance(ball) / t.swipeCollisionForgiveness, velocity: safe, direction: safe.x.mpClamp(-1, 1))
    }
    static func aiContact(x: Double, speed: Double, depth: Double, tuning t: MPTuning, base: MPChance, cross: MPChance,
        previousX: Double?, response: Int, answerRoll: Double, qualityRoll: Double, pace: Double) -> MPContact? {
        let zone = MPZone.at(x)
        let crossCourt = previousX.map { MPZone.at($0) != .middle && zone != .middle && MPZone.at($0) != zone } ?? false
        let chance = crossCourt ? cross : base, p = t.profile
        let special = crossCourt && zone == .backhand
        let answer = (chance.answer - Double(response) * (special ? p.backhandCrossGoodDrop : p.answerDrop)).mpClamp(0, 1)
        guard answer > 0, answerRoll < answer else { return nil }
        let good = (chance.good - Double(response) * (special ? p.backhandCrossGoodDrop : p.goodDrop)).mpClamp(0, answer)
        let succeeds = qualityRoll < good / answer // Requested good percentage is of ALL attempts.
        let challenge = abs(x - 0.5) * 0.20 + max(0, speed - t.ballBaseSpeed) * 0.06 + abs(depth - 0.2) * 0.08
        let bias = x < 0.5 ? t.minikCornerPreference : -t.minikCornerPreference
        let direction = succeeds ? (bias + (answerRoll * 2 - 1) * t.minikAimError).mpClamp(-0.52, 0.52) : (x < 0.5 ? -0.52 : 0.52)
        let quality = succeeds ? max(0.72, 1 - challenge) : 0.05
        return .init(point: .init(x, 0.26), timing: quality, spatial: succeeds ? 0.90 : quality, velocity: .init(direction, pace), direction: direction)
    }
}

struct MPFlight: Codable, Equatable {
    var position: MPPoint; var height: Double; var velocity: MPPoint; var lift: Double; var striker: MPSide
    var receiver = false; var resolved = false; var spin = 0.0; var serve: MPServe?
    struct Event { var bounced = false; var recipient: MPSide?; var resolution: MPResolution?; var point: MPPoint? }
    var valid: Bool {
        [position.x, position.y, height, velocity.x, velocity.y, lift, spin].allSatisfy(\.isFinite) &&
        (-0.3...1.3).contains(position.x) && (-0.3...1.3).contains(position.y) && (-0.1...5).contains(height) &&
        abs(velocity.x) < 8 && abs(velocity.y) < 8 && abs(lift) < 12
    }
    var reflected: Self {
        var f = self; f.position = position.reflected; f.velocity = velocity.reversed; f.striker = striker.other
        f.spin = -spin; f.serve = serve?.reflected; return f
    }
    /// Android `Flight(plan, tuning, startHeight)`: team and practice serves start from a raised paddle (0.25).
    init(_ plan: MPServe, _ t: MPTuning, startHeight: Double = 0.055) {
        position = plan.start; height = startHeight; velocity = .zero; lift = 0; striker = plan.server; serve = plan
        segment(plan.start, plan.first, speed: plan.speed, arc: plan.arc, height: height, tuning: t)
    }
    /// Android `Flight(position, height, velocity, verticalVelocity, striker)` (raw state; tests and the doubles table).
    init(position: MPPoint, height: Double, velocity: MPPoint, lift: Double, striker: MPSide) {
        self.position = position; self.height = height; self.velocity = velocity; self.lift = lift; self.striker = striker
    }
    mutating func segment(_ start: MPPoint, _ target: MPPoint, speed: Double, arc: Double, height: Double, tuning t: MPTuning) {
        var time = max(start.distance(target) / max(speed, 0.05), max(2 * arc / t.gravity * 0.55, 0.16))
        if (start.y - 0.5) * (target.y - 0.5) < 0 {
            let fraction = (0.5 - start.y) / (target.y - start.y)
            let clearance = max(0, t.netHeight + 0.025 - height * (1 - fraction))
            time = max(time, sqrt(2 * clearance / (t.gravity * fraction * (1 - fraction))))
        }
        velocity = .init((target.x - start.x) / time, (target.y - start.y) / time)
        lift = max((0.5 * t.gravity * time * time - height) / time, 0.05)
    }
    mutating func advance(_ delta: Double, _ t: MPTuning) -> Event? {
        guard !resolved else { return nil }
        let full = delta.mpClamp(0, 1.0 / 30)
        guard full > 0 else { return nil }
        let ground = (lift + sqrt(lift * lift + 2 * t.gravity * max(height, 0))) / t.gravity
        let dt = min(full, max(ground, 0)), hitsGround = ground <= full
        let previous = position, previousHeight = height
        position = .init(position.x + velocity.x * dt + 0.5 * spin * dt * dt, position.y + velocity.y * dt)
        velocity.x += spin * dt; spin *= exp(-1.4 * dt)
        height += lift * dt - 0.5 * t.gravity * dt * dt; lift -= t.gravity * dt
        if (previous.y < 0.5 && position.y >= 0.5) || (previous.y > 0.5 && position.y <= 0.5) {
            let fraction = ((0.5 - previous.y) / (position.y - previous.y)).mpClamp(0, 1), time = dt * fraction
            let netHeight = previousHeight + (lift + t.gravity * dt) * time - 0.5 * t.gravity * time * time
            if netHeight <= t.netHeight {
                position = .init(previous.x + (position.x - previous.x) * fraction, 0.5); height = max(0, netHeight)
                return resolve(striker.other, .net)
            }
        }
        if !position.inside { return resolve(receiver ? striker : striker.other, receiver ? .unreturned : .leftTable) }
        guard hitsGround else { return nil }
        height = 0
        var recipient: MPSide?
        if let plan = serve {
            guard position.onSide(striker) else { return resolve(striker.other, .illegalServe) }
            position = plan.first
            if let shot = plan.shot { velocity = shot.velocity; lift = shot.arc }
            else { segment(plan.first, plan.second, speed: plan.speed, arc: plan.arc, height: 0, tuning: t) }
            serve = nil
        } else if !receiver {
            guard position.onSide(striker.other) else { return resolve(striker.other, .firstBounceOut) }
            receiver = true; lift = abs(lift) * t.bounceRestitution; recipient = striker.other
        } else { return resolve(striker, .secondBounce) }
        let point = position
        let rest = full - dt > 1e-9 ? advance(full - dt, t) : nil
        return .init(bounced: true, recipient: recipient, resolution: rest?.resolution, point: point)
    }
    private mutating func resolve(_ side: MPSide, _ fault: MPFault) -> Event {
        resolved = true; return .init(resolution: .init(winner: side, fault: fault))
    }
    mutating func hit(_ c: MPContact, side: MPSide, tuning t: MPTuning, rally: Int, pro: Bool = false) {
        guard !resolved else { return }
        height = max(height, 0.055)
        let shot = side == .minik ? MPShots.ai(c, t, height: height) :
            pro ? MPShots.driven(c, t, height: height, incoming: velocity) : MPShots.tap(c, t, rally: rally, height: height, incoming: velocity)
        striker = side; velocity = shot.velocity; lift = shot.arc; receiver = false; serve = nil; spin = 0
    }
}
