import Foundation

/// Android `world/AirborneFraming`: move the viewing camera back just enough to contain real airborne points. Never
/// changes physics.
enum AirborneFraming {
    static func fit(_ base: ArenaCamera, _ points: [(Double, Double, Double)], _ width: Double, _ height: Double, _ left: Double,
                    _ right: Double, _ top: Double, _ bottom: Double) -> ArenaCamera {
        let cx = width * base.centerX
        let cy = height * base.centerY
        if width <= 0 || height <= 0 || cx <= left || cx >= right || cy <= top || cy >= bottom { return base }
        let focal = height / (2 * tan(base.fov * Double.pi / 360))
        let si = sin(base.tilt)
        let co = cos(base.tilt)
        var distance = base.distance
        for (x, y, z) in points {
            let dx = x - base.x
            let dy = y - base.y
            let dz = z - base.focusHeight
            let vertical = -co * dy + si * dz
            let horizontalDepth = dx >= 0 ? dx * focal / (right - cx) : -dx * focal / (cx - left)
            let verticalDepth = vertical >= 0 ? vertical * focal / (cy - top) : -vertical * focal / (bottom - cy)
            distance = max(distance, si * dy + co * dz + max(2.0, max(horizontalDepth, verticalDepth)) + 0.01)
        }
        return distance == base.distance ? base : base.copy(distance: distance)
    }
}
