import Foundation

// Port of game/DribbleGesture.kt (Android 6c38131), statement by statement.
// Kotlin Long subtraction never traps, so the time differences use wrapping `&-`.

/** Accumulates travel, not individual MotionEvent size. Two reversals form left-right-left or right-left-right. */
final class DribbleGesture {
    private let legDistance: Float
    private let cooldownMs: Int64
    private var leg: Float = 0
    private var committed = 0
    private var lastAt: Int64 = 0
    private var firedAt: Int64 = -10000
    private var reversals = 0

    init(legDistance: Float, cooldownMs: Int64 = 480) {
        self.legDistance = legDistance
        self.cooldownMs = cooldownMs
    }

    /// Kotlin positional constructor form `DribbleGesture(dp(18f))`.
    convenience init(_ legDistance: Float, _ cooldownMs: Int64 = 480) {
        self.init(legDistance: legDistance, cooldownMs: cooldownMs)
    }

    func reset() { leg = 0; committed = 0; reversals = 0; lastAt = 0 }

    func move(dx: Float, now: Int64) -> Int {
        if now &- lastAt > 650 { leg = 0; committed = 0; reversals = 0 }
        lastAt = now
        if dx == 0 { return 0 }
        if leg * dx < 0 { leg = 0 }
        leg += dx
        if abs(leg) < legDistance { return 0 }
        let sign = leg < 0 ? -1 : 1
        let reversed = committed != 0 && sign != committed
        committed = sign
        if reversed { reversals += 1 }
        if !reversed || reversals < 2 || now &- firedAt < cooldownMs { return 0 }
        reversals = 0
        firedAt = now
        return sign
    }

    /// Kotlin positional call form `dribbleGesture.move(rawDx, now)`.
    func move(_ dx: Float, _ now: Int64) -> Int {
        return move(dx: dx, now: now)
    }
}
