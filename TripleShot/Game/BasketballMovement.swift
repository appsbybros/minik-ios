import Foundation

// Port of game/BasketballMovement.kt (Android snapshot dd722e5), statement by statement.
// `Int * Float` in Kotlin is a Float operation (`speed.toFloat() * .024f`); hypot goes through khypot
// (Math.hypot in Double, then toFloat, like kotlin.math.hypot(Float, Float)).

/** Team movement measured in court metres; independent of camera zoom and decision frequency. */
enum BasketballMovement {
    struct Step: Hashable {
        var x: Float
        var y: Float
    }

    /** Let a cutter reach the actual destination instead of reversing after a fixed 900ms. */
    static func cutDurationMillis(dx: Float, dy: Float, speed: Int, agility: Int) -> Int64 {
        let metres = khypot(dx * 0.014, dy * 0.034)
        let speedPace: Float = speed.coerceIn(0, 100).toFloat() * 0.024
        let agilityPace: Float = agility.coerceIn(0, 100).toFloat() * 0.009
        let pace: Float = 2.2 + speedPace + agilityPace
        let millis: Float = metres / pace * 1000 + 450
        return millis.toLong().coerceIn(1100, 3800)
    }

    /// Kotlin positional call form `BasketballMovement.cutDurationMillis(dx, dy, speed, agility)`.
    static func cutDurationMillis(_ dx: Float, _ dy: Float, _ speed: Int, _ agility: Int) -> Int64 {
        return cutDurationMillis(dx: dx, dy: dy, speed: speed, agility: agility)
    }

    static func step(dx: Float, dy: Float, speed: Int, agility: Int, scale: Float, dtSeconds: Float) -> Step {
        let mx = dx * 0.014
        let mz = dy * 0.034
        let distance = khypot(mx, mz)
        if distance <= 0.04 || dtSeconds <= 0 { return Step(x: 0, y: 0) }
        let speedPace: Float = speed.coerceIn(0, 100).toFloat() * 0.024
        let agilityPace: Float = agility.coerceIn(0, 100).toFloat() * 0.009
        let metresPerSecond: Float = (2.2 + speedPace + agilityPace) * scale.coerceIn(0, 2)
        let fraction = kmin(1, metresPerSecond * dtSeconds.coerceAtMost(0.08) / distance)
        return Step(x: dx * fraction, y: dy * fraction)
    }

    /// Kotlin positional call form `BasketballMovement.step(dx, dy, speed, agility, scale, dt)`.
    static func step(_ dx: Float, _ dy: Float, _ speed: Int, _ agility: Int, _ scale: Float, _ dtSeconds: Float) -> Step {
        return step(dx: dx, dy: dy, speed: speed, agility: agility, scale: scale, dtSeconds: dtSeconds)
    }
}

extension BasketballMovement.Step {
    /// Kotlin positional constructor form `Step(x, y)`.
    init(_ x: Float, _ y: Float) {
        self.init(x: x, y: y)
    }
}
