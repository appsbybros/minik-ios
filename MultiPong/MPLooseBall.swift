import Foundation

// Android LooseBall.kt (MinikCrossPong 5375378, ab089c5; unchanged at dd94c09). The classic court (MPEngine, floor -2.03, far
// end 0) and the cross table (CrossEngine, floor -0.38, its own tabletop, no classic net) both let a decided ball finish its
// motion with it.

/// Post-point motion. Scores have already been decided: a body rebound is not a racket hit. The same gravity/restitution rules
/// continue until the ball comes to rest.
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
    private let onTable: (MPPoint) -> Bool
    private let classicNet: Bool
    private let farEnd: Double?
    private var lastBody: Body?
    private var bodyCooldown = 0.0
    /// Android ab089c5: an optional scenic-court boundary, expressed relative to the table, not background pixels. Only a decided
    /// ball travelling past the far end eases to a planar stop. Gravity continues so it can fall to the floor instead of hanging
    /// in the air.
    private var farCoastRemaining: Double?
    init(_ position: MPPoint, _ height: Double, _ velocity: MPPoint, _ lift: Double, floor: Double = -0.85,
         onTable: @escaping (MPPoint) -> Bool = { $0.inside }, classicNet: Bool = true, farEnd: Double? = nil) {
        self.position = position; self.height = height; self.velocity = velocity; self.lift = lift; self.floor = floor
        self.onTable = onTable; self.classicNet = classicNet; self.farEnd = farEnd
    }
    func advance(_ delta: Double, _ t: MPTuning, _ bodies: [Body] = []) {
        if settled { return }
        var left = delta.mpClamp(0, 0.1)
        while left > 1e-9 { let dt = min(left, 1.0 / 240); left -= dt; step(dt, t, bodies) }
    }
    private func step(_ dt: Double, _ t: MPTuning, _ bodies: [Body]) {
        if settled { return }
        bodyCooldown -= dt
        let before = position, z = height
        if let farEnd, farCoastRemaining == nil, position.y <= farEnd, velocity.y < 0 {
            farCoastRemaining = 0.4
            // Even a very fast miss must remain on the floor just behind the far baseline.
            let speed = hypot(velocity.x, velocity.y)
            if speed > 0.9 { velocity = MPPoint(velocity.x * 0.9 / speed, velocity.y * 0.9 / speed) }
        }
        let remaining = farCoastRemaining
        let travel: Double
        if let remaining {
            if remaining <= 0 { travel = 0 } else { let part = min(dt, remaining); travel = part * (1 - 0.5 * part / remaining) }
        } else { travel = dt }
        position = MPPoint(position.x + velocity.x * travel, position.y + velocity.y * travel)
        if let remaining, let farEnd {
            let factor = remaining <= 0 ? 0 : max(0, 1 - dt / remaining)
            velocity = MPPoint(velocity.x * factor, velocity.y * factor)
            farCoastRemaining = max(0, remaining - dt)
            position = MPPoint(position.x, max(position.y, farEnd - 0.20))
        }
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
                velocity = MPPoint(velocity.x - 1.50 * inward * nx, velocity.y - 1.50 * inward * ny)
                // Resolve penetration outward with no teleport through the actor.
                let radial = max(sqrt(dx * dx + dy * dy), 0.001)
                position = MPPoint(b.x + (position.x - b.x) / radial * 1.002, b.y + (position.y - b.y) / radial * 1.002)
                bodyHits += 1; lastBody = b; bodyCooldown = 0.08
            }
        }
        // A rebound can meet the net again. A low ball cannot pass through it.
        if classicNet && (before.y - 0.5) * (position.y - 0.5) < 0 && position.x >= 0 && position.x <= 1 && height >= 0 && height <= t.netHeight {
            position = MPPoint(position.x, 0.5 + (before.y < 0.5 ? -0.001 : 0.001))
            velocity = MPPoint(velocity.x * 0.7, -velocity.y * 0.2)
        }
        // Table edge is a solid shallow slab, separate from the floor beneath it.
        if !onTable(before) && onTable(position) && height >= -0.045 && height <= 0 {
            velocity = !(before.y >= 0 && before.y <= 1) ? MPPoint(velocity.x, -velocity.y * 0.4) : MPPoint(-velocity.x * 0.4, velocity.y)
            position = before
        }
        let table = onTable(position) && z >= -1e-6
        let ground = table ? 0 : floor
        if height <= ground && lift < 0 {
            height = ground
            let impact = -lift
            lift = impact < 0.16 ? 0 : impact * (table ? t.bounceRestitution : 0.42)
            velocity = MPPoint(velocity.x * 0.82, velocity.y * 0.82)
            if table { tableBounces += 1 }
        }
        let rolling = abs(height - ground) < 0.002 && abs(lift) < 0.16
        let drag = exp(-dt * (rolling ? 5.0 : 0.18))
        velocity = MPPoint(velocity.x * drag, velocity.y * drag)
        if rolling && hypot(velocity.x, velocity.y) < 0.025 { velocity = .zero; lift = 0; settled = true }
    }
}
