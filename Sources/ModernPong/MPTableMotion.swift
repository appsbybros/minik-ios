import Foundation

/// Android `LooseBall` (920caca): post-point motion. Scores have already been decided: a body rebound is not a
/// racket hit. The same gravity/restitution rules continue until the ball comes to rest.
final class MPLooseBall {
    struct Body: Equatable { var x: Double, y: Double, radiusX: Double, radiusY: Double, bottom: Double, top: Double }
    private(set) var position: MPPoint
    private(set) var height: Double
    private(set) var velocity: MPPoint
    private(set) var lift: Double
    let floor: Double
    private(set) var settled = false
    private(set) var bodyHits = 0
    private(set) var tableBounces = 0
    private var lastBody: Body?
    private var bodyCooldown = 0.0
    init(position: MPPoint, height: Double, velocity: MPPoint, lift: Double, floor: Double = -0.85) {
        self.position = position; self.height = height; self.velocity = velocity; self.lift = lift; self.floor = floor
    }
    func advance(_ delta: Double, _ t: MPTuning, bodies: [Body]) {
        if settled { return }
        var left = delta.mpClamp(0, 0.1)
        while left > 1e-9 { let dt = min(left, 1.0 / 240); left -= dt; step(dt, t, bodies) }
    }
    private func step(_ dt: Double, _ t: MPTuning, _ bodies: [Body]) {
        if settled { return }
        bodyCooldown -= dt
        let before = position, z = height
        position = .init(position.x + velocity.x * dt, position.y + velocity.y * dt)
        height += lift * dt - 0.5 * t.gravity * dt * dt; lift -= t.gravity * dt
        for b in bodies {
            if height < b.bottom || height > b.top || (b == lastBody && bodyCooldown > 0) { continue }
            let dx = (position.x - b.x) / b.radiusX, dy = (position.y - b.y) / b.radiusY
            if dx * dx + dy * dy >= 1 { continue }
            var nx = dx / b.radiusX, ny = dy / b.radiusY
            let length = hypot(nx, ny)
            if length < 1e-8 { nx = 0; ny = before.y < b.y ? -1 : 1 } else { nx /= length; ny /= length }
            let inward = velocity.x * nx + velocity.y * ny
            if inward < 0 {
                velocity = .init(velocity.x - 1.50 * inward * nx, velocity.y - 1.50 * inward * ny)
                // Resolve penetration outward with no teleport through the actor.
                let radial = max(sqrt(dx * dx + dy * dy), 0.001)
                position = .init(b.x + (position.x - b.x) / radial * 1.002, b.y + (position.y - b.y) / radial * 1.002)
                bodyHits += 1; lastBody = b; bodyCooldown = 0.08
            }
        }
        // A rebound can meet the net again. A low ball cannot pass through it.
        if (before.y - 0.5) * (position.y - 0.5) < 0 && (0...1).contains(position.x) && (0...t.netHeight).contains(height) {
            position = .init(position.x, 0.5 + (before.y < 0.5 ? -0.001 : 0.001))
            velocity = .init(velocity.x * 0.7, -velocity.y * 0.2)
        }
        // Table edge is a solid shallow slab, separate from the floor beneath it.
        if !before.inside && position.inside && (-0.045...0).contains(height) {
            velocity = !(0...1).contains(before.y) ? .init(velocity.x, -velocity.y * 0.4) : .init(-velocity.x * 0.4, velocity.y)
            position = before
        }
        let table = position.inside && z >= -1e-6
        let ground = table ? 0 : floor
        if height <= ground && lift < 0 {
            height = ground
            let impact = -lift
            lift = impact < 0.16 ? 0 : impact * (table ? t.bounceRestitution : 0.42)
            velocity = .init(velocity.x * 0.82, velocity.y * 0.82)
            if table { tableBounces += 1 }
        }
        let rolling = abs(height - ground) < 0.002 && abs(lift) < 0.16
        let drag = exp(-dt * (rolling ? 5.0 : 0.18))
        velocity = .init(velocity.x * drag, velocity.y * drag)
        if rolling && hypot(velocity.x, velocity.y) < 0.025 { velocity = .zero; lift = 0; settled = true }
    }
}

/// Android `NearPlayerProjection` (fb0265e): near-side perspective for the full player view. The net,
/// baselines, physics and remote half stay fixed. Touch coordinates use the exact inverse, including Pro swipes.
/// Image coordinates are Android `CourtProjection` (iOS `MPProjection`).
enum MPNearPlayerProjection {
    private static let depth = MPProjection.bottom - MPProjection.net
    private static func remaining(_ u: Double) -> Double { 0.35 * u + 0.65 * u * u * u }
    static func imageY(_ y: Double) -> Double {
        if y <= 0.5 { return MPProjection.imageY(y) }
        if y > 1.0 { return MPProjection.bottom + (y - 1) * 2 * depth * 0.35 }
        return MPProjection.bottom - remaining(2 * (1 - y)) * depth
    }
    static func tableY(_ image: Double) -> Double {
        if image <= MPProjection.net { return MPProjection.tableY(image) }
        if image > MPProjection.bottom { return 1 + (image - MPProjection.bottom) / (2 * depth * 0.35) }
        let target = (MPProjection.bottom - image) / depth
        var lo = 0.0, hi = 1.0
        for _ in 0..<35 { let mid = (lo + hi) / 2; if remaining(mid) < target { lo = mid } else { hi = mid } }
        return 1 - (lo + hi) / 4
    }
    static func slope(_ y: Double) -> Double {
        y < 0.5 ? 6 * pow(2 * y, 2) * (MPProjection.net - MPProjection.top)
            : 2 * depth * (0.35 + 1.95 * pow((2 * (1 - y)).mpClamp(0, 1), 2))
    }
}

/// Android `TableBallProjection`: common elevated-ball scale. Smoothly foreshorten high arcs, without a cap, a
/// discontinuity at the net, or any dependence on a player's current pose.
enum MPTableBallProjection {
    static func height(_ amount: Double) -> Double {
        if amount < 0 { return amount / 0.45 }
        var lo = 0.0, hi = 1.0 + amount * 25
        for _ in 0..<40 { let mid = (lo + hi) / 2; if rise(mid) < amount { lo = mid } else { hi = mid } }
        return (lo + hi) / 2
    }
    static func rise(_ z: Double) -> Double { z < 0 ? z * 0.45 : 0.04 * z + 0.07 * (1 - exp(-z / 0.05)) }
}

/// Android `ReturnPlacement` (bcee181): relative changes — ready in place +5 %; from centre to corner −3 %; opposite
/// corner −5 %.
enum MPReturnPlacement {
    static func multiplier(startX: Double, contactX: Double) -> Double {
        let d = abs(startX - contactX).mpClamp(0, 1)
        if d <= 0.10 { return 1.05 }
        if d < 0.40 { return 1.05 - (d - 0.10) / 0.30 * 0.08 }
        return 0.97 - min((d - 0.40) / 0.30, 1) * 0.02
    }
    static func adjust(_ chance: MPChance, startX: Double, contactX: Double) -> MPChance {
        let factor = multiplier(startX: startX, contactX: contactX), answer = (chance.answer * factor).mpClamp(0, 1)
        return MPChance(answer, (chance.good * factor).mpClamp(0, answer))
    }
}

/// Android `PongServeDifficulty`: placement multiplies the receiver's authored forehand/backhand probability. The
/// current roster has no left-handed override; reflection supports either hand. This never substitutes a successful
/// hit for physical paddle contact.
enum MPServeDifficulty {
    static func zone(ballX: Double, playerX: Double, team: Int, leftHanded: Bool = false) -> MPZone {
        let towardRight = (ballX - playerX) * (team == 0 ? 1 : -1) * (leftHanded ? -1 : 1)
        return towardRight > 0.025 ? .forehand : towardRight < -0.025 ? .backhand : .middle
    }
    /// Android c9f5fa6: at the legal outer aiming edge (0.07/0.93), 45–70 % by receiving-hand skill (`handSkill`, 2...10;
    /// nil derives it from the authored chance). The central serve keeps the normal authored chance. One roll only:
    /// court size and the current animation pose must not alter this probability.
    static func adjust(_ base: MPChance, landing: MPPoint, receivingTeam: Int, handSkill: Double? = nil) -> MPChance {
        let edge = ((abs(landing.x - 0.5) - 0.20) / 0.23).mpClamp(0, 1)
        let skill = handSkill.map { (($0 - 2) / 8).mpClamp(0, 1) } ?? ((base.answer - 0.4) / 0.6).mpClamp(0, 1)
        let edgeAnswer = 0.45 + 0.25 * skill
        let shortness = ((receivingTeam == 1 ? landing.y : 1 - landing.y) / 0.44).mpClamp(0, 1)
        let pressure = edge * (0.75 + 0.25 * shortness)
        let answer = base.answer + (min(base.answer, edgeAnswer) - base.answer) * pressure
        return MPChance(answer, (answer * (base.good / max(base.answer, 0.001))).mpClamp(0, answer))
    }
    /// Android `handSkill`: the receiving hand's authored skill (Minik's profile when no house player is given).
    static func handSkill(_ profile: MPBot?, _ zone: MPZone) -> Double {
        guard let p = profile ?? MPRoster.find("minik")?.profile else { return 6 }
        switch zone {
        case .forehand: return Double(p.forehandSkill)
        case .backhand: return Double(p.backhandSkill)
        case .middle: return Double(p.forehandSkill + p.backhandSkill) / 2
        }
    }
}

/// Android `PongGait` (a8d344b): presentation cadence, independent of display refresh rate and finger jitter.
final class MPGait {
    private(set) var walking = false
    private(set) var phase = 0
    private var quiet = 0.0, elapsed = 0.0, distance = 0.0
    /// `travel` is Android's Float screen travel of this frame (fraction of the view).
    func update(_ dt: Double, travel: Float, stroke: Bool) {
        if stroke { walking = false; quiet = 0; elapsed = 0; distance = 0; return }
        quiet = travel > 0.0015 ? 0 : quiet + dt
        if travel > 0.003 { walking = true }
        if quiet > 0.16 { walking = false; elapsed = 0; distance = 0; return }
        if !walking { return }
        elapsed += dt; distance += Double(travel)
        // Hold each authored pose for at least 110 ms; never skip frames after a fast drag.
        if elapsed >= 0.11 && distance >= 0.075 { phase = (phase + 1) % 4; elapsed = 0; distance = 0 }
    }
}
