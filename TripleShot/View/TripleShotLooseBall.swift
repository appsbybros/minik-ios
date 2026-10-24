import Foundation

// Port of view/TripleShotLooseBall.kt (Android 6c38131), statement by statement.

/** The rebound remains in the same court coordinates as the released shot and both players. */
final class TripleShotLooseBall {
    private let gravity: Float
    private let centerX: Float
    private let back: Float
    private(set) var position: CourtPoint
    private(set) var velocity: CourtPoint

    init(start: CourtPoint, velocity: CourtPoint, gravity: Float, centerX: Float = 0, back: Float = -11) {
        self.gravity = gravity
        self.centerX = centerX
        self.back = back
        self.position = start
        self.velocity = velocity
    }

    func advance(seconds: Float) {
        var left = seconds.coerceIn(0, 0.05)
        while left > 0 {
            let dt = kmin(left, Float(1) / Float(240)); left -= dt
            var vy = velocity.y - gravity * dt
            var vx = velocity.x; var vz = velocity.z
            var y = position.y + vy * dt
            if y < TripleShotLooseBall.RADIUS {
                y = TripleShotLooseBall.RADIUS
                if abs(vy) > 0.8 { vy = abs(vy) * 0.55; vx *= 0.88; vz *= 0.88 }
                else { vy = 0; vx *= 1 - dt * 2.1; vz *= 1 - dt * 2.1 }
            }
            position = CourtPoint(x: position.x + vx * dt, y: y, z: position.z + vz * dt)
            velocity = CourtPoint(x: vx, y: vy, z: vz)
        }
    }

    var outOfBounds: Bool { abs(position.x - centerX) > 8.4 || position.z < back - 0.4 || position.z > 12.4 }

    static let RADIUS: Float = 0.21
}
