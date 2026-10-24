import Foundation

// Port of game/BasketballTouchShot.kt (Android snapshot dd722e5), statement by statement.
// `sign(delta)` is kotlin.math.sign (Math.signum: -1, 0 or +1) → `ksign`.

/** One touch transfer function for the visible preview and the actual release. Sensors stay independent. */
enum BasketballTouchShot {
    static let IDEAL_PULL: Float = 0.70

    static func powerError(pull: Float) -> Float {
        let delta = pull.coerceIn(0, 1.2) - IDEAL_PULL
        let magnitude = abs(delta)
        // A broad, continuous sweet spot; deliberately weak/strong throws can still miss.
        let softened: Float = magnitude <= 0.12 ? magnitude * 0.40 : 0.048 + (magnitude - 0.12)
        let gain: Float = Float(1.70) / Float(1.35)
        return (delta.ksign * softened * gain).coerceIn(-1.7, 1.7)
    }

    /// Kotlin positional call form `BasketballTouchShot.powerError(pull)`.
    static func powerError(_ pull: Float) -> Float {
        return powerError(pull: pull)
    }

    static func skill(aim: Float, pull: Float, flickGyro: Float = 0) -> ShotSkill {
        let power = (powerError(pull: pull) + flickGyro.coerceIn(0, 0.72) / 1.35).coerceIn(-1.7, 1.7)
        let arc: Float = ((pull * 20 - 15) / 7).coerceIn(-1.7, 1.7)
        return ShotSkill(
            aimError: aim.coerceIn(-1.30, 1.30),
            powerError: power,
            arcError: arc,
            rawPeakGyro: 3.05 + power * 1.35,
            rawReleasePitchDeg: pull * 20
        )
    }

    /// Kotlin positional call form `BasketballTouchShot.skill(aim, pull)` / `skill(aim, pull, flickGyro)`.
    static func skill(_ aim: Float, _ pull: Float, _ flickGyro: Float = 0) -> ShotSkill {
        return skill(aim: aim, pull: pull, flickGyro: flickGyro)
    }
}
