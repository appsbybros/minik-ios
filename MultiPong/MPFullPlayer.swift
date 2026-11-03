import Foundation

/// Android `NearPlayerProjection` (MinikCrossPong 7254ab2, from Modern Ping Pong): the near-side perspective of the classic court
/// when the player's own full avatar is shown. The net, the baselines, the physics and the far half stay fixed; touches use the
/// exact inverse, including Pro swipes. Image coordinates are Android `CourtProjection` (iOS `MPProjection`).
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
}

/// Android `PongGait` (MinikCrossPong 7254ab2): the walking cadence of the full avatar, independent of the display refresh rate
/// and of finger jitter.
final class MPGait {
    private(set) var walking = false
    private(set) var phase = 0
    private var quiet = 0.0, elapsed = 0.0, distance = 0.0
    /// `travel` is this frame's foot travel as a fraction of the avatar's height.
    func update(_ dt: Double, travel: Double, stroke: Bool) {
        if stroke { walking = false; quiet = 0; elapsed = 0; distance = 0; return }
        quiet = travel > 0.0015 ? 0 : quiet + dt
        if travel > 0.003 { walking = true }
        if quiet > 0.16 { walking = false; elapsed = 0; distance = 0; return }
        if !walking { return }
        elapsed += dt; distance += travel
        // Hold each authored pose for at least 110 ms; never skip frames after a fast drag.
        if elapsed >= 0.11 && distance >= 0.075 { phase = (phase + 1) % 4; elapsed = 0; distance = 0 }
    }
}
