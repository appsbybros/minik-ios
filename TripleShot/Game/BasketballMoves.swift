import Foundation

// Port of game/BasketballMoves.kt (Android 6c38131), statement by statement.
// Kotlin Float arithmetic keeps its operation order; `kotlin.math` Float functions use the AndroidKit k-functions;
// Kotlin Long subtraction never traps, so the time differences use wrapping `&-`.

/** Shared, rating-based probabilities. Each attempt makes an independent random draw. */
enum BasketballMoves {
    static func screenChance(defense: Int) -> Float {
        Float(0.95) - Float(0.10) * defense.coerceIn(0, 100).toFloat() / Float(100)
    }

    static func switchChance(defense: Int) -> Float {
        Float(0.10) + Float(0.10) * defense.coerceIn(0, 100).toFloat() / Float(100)
    }

    static func spinChance(defense: Int, quickRepeats: Int) -> Float {
        (Float(0.20) - Float(0.10) * defense.coerceIn(0, 100).toFloat() / Float(100)
            + Float(0.05) * quickRepeats.coerceAtLeast(0).toFloat()).coerceAtMost(Float(0.45))
    }

    struct Spin: Hashable {
        var success: Bool
        var fall: Bool
        var recoveryMs: Int64
        var chance: Float
    }

    final class SpinSeries {
        private var lastAt: Int64 = -10000
        private var repeats = 0

        func attempt(now: Int64, defense: Int, random: () -> Float) -> Spin {
            let since = now &- lastAt
            repeats = (since >= 350 && since <= 2200) ? repeats + 1 : 0
            lastAt = now
            let chance = BasketballMoves.spinChance(defense: defense, quickRepeats: repeats)
            if random() >= chance { return Spin(success: false, fall: false, recoveryMs: 0, chance: chance) }
            let fall = random() < Float(0.20)
            return Spin(success: true, fall: fall,
                        recoveryMs: 1000 &+ (random().coerceIn(0, 1) * Float(1000)).toLong(), chance: chance)
        }
    }
}

/** A real curved swipe: straight zigzags cannot satisfy winding and area together. */
final class CircularDribbleGesture {
    private let minimumRadius: Float
    private var x: Float = 0; private var y: Float = 0; private var area: Float = 0; private var travel: Float = 0
    private var turn: Float = 0; private var angle: Float? = nil; private var began: Int64 = 0; private var last: Int64 = 0

    init(minimumRadius: Float) { self.minimumRadius = minimumRadius }

    /// Kotlin positional constructor form `CircularDribbleGesture(dp(24f))`.
    convenience init(_ minimumRadius: Float) { self.init(minimumRadius: minimumRadius) }

    func reset() { x = 0; y = 0; area = 0; travel = 0; turn = 0; angle = nil; began = 0; last = 0 }

    func move(dx: Float, dy: Float, now: Int64) -> Int {
        if khypot(dx, dy) < 1 { return 0 }
        if now &- last > 350 || now &- began > 1600 { reset(); began = now }
        last = now
        let next = katan2(dy, dx)
        if let old = angle {
            var d = next - old
            // Kotlin compares the Float with the Double PI (in Double) and subtracts (2*PI).toFloat().
            while Double(d) > Double.pi { d -= (2 * Double.pi).toFloat() }
            while Double(d) < -Double.pi { d += (2 * Double.pi).toFloat() }
            turn += d
        }
        angle = next
        area += x * dy - y * dx; x += dx; y += dy; travel += khypot(dx, dy)
        if abs(turn) > Float(4.4) && travel > minimumRadius * 5 && abs(area) > minimumRadius * minimumRadius * 2 {
            let sign = turn < 0 ? -1 : 1
            reset()
            return sign
        }
        return 0
    }
}
