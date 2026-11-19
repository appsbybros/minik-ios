import Foundation

/// Android `core/AttackPhysics.kt`: predict an incoming attack from its public ballistic path, never its catch roll.
enum AttackPhysics {
    struct Approach: Equatable {
        let at: Double
        let until: Double
        let height: Double
    }

    /// Low (0.55), torso (1.10) or high (1.80) attack height from one roll.
    static func height(_ roll: Double) -> Double {
        if roll < 0.70 { return 1.10 }
        if roll < 0.85 { return 0.55 }
        return 1.80
    }

    static func catchFactor(_ height: Double) -> Double {
        if height < 1.05 { return 2.0 / 3 + (1.0 / 3) * Kotlin.clamp((height - 0.80) / 0.25, 0.0, 1.0) }
        if height > 1.50 { return 1 - (1.0 / 9) * Kotlin.clamp((height - 1.50) / 0.20, 0.0, 1.0) }
        return 1.0
    }

    static func approach(_ b: Ball, _ a: GameActor, _ c: GameConfig, _ wind: V) -> Approach? {
        let speed = b.velocity.length()
        if speed < 0.05 || b.holder != nil { return nil }
        let d = b.velocity * (1 / speed)
        let delta = a.position - b.position
        let along = delta.x * d.x + delta.y * d.y
        if along < 0 || along / speed > 1.0 { return nil }
        let drift = wind * (0.5 * pow(along / speed, 2.0))
        let corrected = delta - drift
        let forward = corrected.x * d.x + corrected.y * d.y
        let cross = abs(corrected.x * d.y - corrected.y * d.x)
        let radius = 0.28 + BallContact.radius(c.ball)
        if cross > radius { return nil }
        let span = max(radius * radius - cross * cross, 0.0).squareRoot()
        let at = max((forward - span) / speed, 0.0)
        let until = (forward + span) / speed
        if until <= 0 || at > 1.0 { return nil }
        let z = b.height + b.vz * at - 0.5 * c.scene.gravity * at * at
        if z < 0.23 || z > c.standingHeight + BallContact.radius(c.ball) { return nil }
        let centre = max(forward / speed, 0.0)
        return Approach(at: at, until: until, height: b.height + b.vz * centre - 0.5 * c.scene.gravity * centre * centre)
    }

    static func canDuck(_ b: Ball, _ a: GameActor, _ c: GameConfig, _ p: Approach) -> Bool {
        if p.until > c.duckSeconds || a.jumpHeight > 0 { return false }
        let top = max(c.duckHeight, 1.4) + BallContact.radius(c.ball) / 2
        for i in 0...12 {
            let t = p.at + (p.until - p.at) * Double(i) / 12
            if !(b.height + b.vz * t - 0.5 * c.scene.gravity * t * t > top + 0.02) { return false }
        }
        return true
    }

    static func canJump(_ b: Ball, _ a: GameActor, _ c: GameConfig, _ p: Approach) -> Bool {
        if a.jumpHeight > 0 { return false }
        let velocity = CatchPhysics.jumpVelocity(a)
        let radius = BallContact.radius(c.ball) / 2
        for i in 0...12 {
            let t = p.at + (p.until - p.at) * Double(i) / 12
            let feet = max(velocity * t - 0.5 * c.scene.gravity * t * t, 0.0)
            let z = b.height + b.vz * t - 0.5 * c.scene.gravity * t * t
            if !(feet - radius > z + 0.02) { return false }
        }
        return true
    }
}
