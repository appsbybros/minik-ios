import Foundation

// Port of game/BasketballVisualMotion.kt (Android 6c38131), statement by statement.
// Kotlin Long arithmetic never traps, so the time differences use wrapping `&-`
// (`now - Long.MIN_VALUE/2` stays in range for real clock values, as on Android).

/** Presentation only: never changes the actor's position, speed, collision or basketball rules. */
final class BasketballVisualMotion {
    private let depthScale: Float
    private(set) var facing = 0
    private(set) var mirror = false
    private(set) var moving = false
    private(set) var frameIndex = 0
    private var initialized = false
    private var x: Float = 0
    private var y: Float = 0
    private var candidate = 0
    private var candidateSince: Int64 = 0
    private var mirrorCandidate = false
    private var mirrorSince: Int64 = 0
    private var lastTravel: Int64 = Int64.min / 2
    private var frameAt: Int64 = 0
    private var stride: Float = 0

    init(depthScale: Float = Float(0.034)) { self.depthScale = depthScale }

    /// Kotlin positional constructor form `BasketballVisualMotion(.017f)`.
    convenience init(_ depthScale: Float) { self.init(depthScale: depthScale) }

    func update(now: Int64, nextX: Float, nextY: Float, wantedFacing: Int, sideFacing: Int,
                wantedMirror: Bool, committedAction: Bool) {
        let distance: Float = initialized ? khypot((nextX - x) * 0.014, (nextY - y) * depthScale) : 0
        x = nextX; y = nextY
        if !initialized || distance > 2 {
            initialized = true; facing = wantedFacing; candidate = wantedFacing; candidateSince = now
            frameAt = now; stride = 0; moving = false; lastTravel = Int64.min / 2
        }
        if committedAction {
            facing = wantedFacing; candidate = wantedFacing; candidateSince = now
        } else if wantedFacing != candidate {
            candidate = wantedFacing; candidateSince = now
        } else if now &- candidateSince >= 220 { facing = candidate }
        // Mirroring a FRONT/BACK image reverses the shirt and changes its whole silhouette.
        // Only a genuine side-facing pose uses left/right mirroring.
        if facing != sideFacing { mirror = false; mirrorCandidate = wantedMirror; mirrorSince = now }
        else {
            if wantedMirror != mirrorCandidate { mirrorCandidate = wantedMirror; mirrorSince = now }
            if committedAction || now &- mirrorSince >= 180 { mirror = mirrorCandidate }
        }
        // Kotlin `distance in .016f..2f`.
        if distance >= 0.016 && distance <= 2 {
            lastTravel = now; stride += distance
        }
        moving = !committedAction && now &- lastTravel < 180
        if moving && stride >= 0.36 && now &- frameAt >= 180 {
            // Kotlin Float `%=` is the truncating (fmod) remainder.
            frameIndex = 1 - frameIndex; stride = stride.truncatingRemainder(dividingBy: 0.36); frameAt = now
        }
        if !moving { stride = 0 }
    }

    /// Kotlin positional call form `visual.update(now, x, y, facing, sideFacing, mirror, committed)`.
    func update(_ now: Int64, _ nextX: Float, _ nextY: Float, _ wantedFacing: Int, _ sideFacing: Int,
                _ wantedMirror: Bool, _ committedAction: Bool) {
        update(now: now, nextX: nextX, nextY: nextY, wantedFacing: wantedFacing, sideFacing: sideFacing,
               wantedMirror: wantedMirror, committedAction: committedAction)
    }
}
