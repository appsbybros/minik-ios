import Foundation

/// Android `world/GroundPoint`.
struct GroundPoint: Equatable {
    let x: Double
    let y: Double
}

/// Android `world/ScreenPoint` (Kotlin keeps x/y as Float; iOS keeps view points as Double).
struct ScreenPoint: Equatable {
    let x: Double
    let y: Double
    let depth: Double
}

/// Android `world/ArenaCamera`: the perspective camera shared by the world renderer, the drawn actors and the touch
/// mapping. `width`/`height` are the view size (Android pixels, iOS points; the projection only uses their ratio and
/// scale, so both give the same picture). Kotlin's `require(distance > 3 && tilt in .2..1.2 && fov in 25..85)` holds
/// for every camera the arena builds and is not re-checked.
struct ArenaCamera: Equatable {
    var x: Double
    var y: Double
    var distance: Double = 26.0
    var focusHeight: Double = 0.0
    var tilt: Double = 1.12
    var fov: Double = 52.0
    var centerY: Double = 0.61
    var centerX: Double = 0.5

    init(x: Double, y: Double, distance: Double = 26.0, focusHeight: Double = 0.0, tilt: Double = 1.12, fov: Double = 52.0,
         centerY: Double = 0.61, centerX: Double = 0.5) {
        self.x = x
        self.y = y
        self.distance = distance
        self.focusHeight = focusHeight
        self.tilt = tilt
        self.fov = fov
        self.centerY = centerY
        self.centerX = centerX
    }

    func project(_ px: Double, _ py: Double, _ z: Double, _ width: Double, _ height: Double) -> ScreenPoint {
        let si = sin(tilt)
        let co = cos(tilt)
        let dy = py - y
        let dz = z - focusHeight
        let depth = distance - si * dy - co * dz
        let f = height / (2 * tan(fov * Double.pi / 360))
        let safe = max(depth, 0.1)
        return ScreenPoint(x: width * centerX + (px - x) * f / safe, y: height * centerY - (-co * dy + si * dz) * f / safe, depth: depth)
    }

    /// The ground point under a screen point (the inverse of `project` at height `z`).
    func ground(_ sx: Double, _ sy: Double, _ width: Double, _ height: Double, _ z: Double = 0.0) -> GroundPoint {
        let si = sin(tilt)
        let co = cos(tilt)
        let f = height / (2 * tan(fov * Double.pi / 360))
        let r = (height * centerY - sy) / f
        let dz = z - focusHeight
        var divisor = r * si - co
        if abs(divisor) < 0.02 { divisor = -0.02 }
        let dy = (r * (distance - co * dz) - si * dz) / divisor
        let depth = distance - si * dy - co * dz
        return GroundPoint(x: x + (sx - width * centerX) * depth / f, y: y + dy)
    }

    /// Smooth approach toward `target` (framing centers switch at once, like Android).
    func toward(_ target: ArenaCamera, _ dt: Double) -> ArenaCamera {
        let a = 1 - exp(-Kotlin.clamp(dt, 0.0, 0.1) * 4.2)
        var next = self
        next.x = x + (target.x - x) * a
        next.y = y + (target.y - y) * a
        next.distance = distance + (target.distance - distance) * a
        next.focusHeight = focusHeight + (target.focusHeight - focusHeight) * a
        next.centerX = target.centerX
        next.centerY = target.centerY
        next.tilt = tilt + (target.tilt - tilt) * a
        return next
    }

    /// Kotlin `copy(...)` for the fields the arena changes.
    func copy(x newX: Double? = nil, y newY: Double? = nil, distance newDistance: Double? = nil, focusHeight newFocus: Double? = nil,
              centerX newCenterX: Double? = nil, centerY newCenterY: Double? = nil, tilt newTilt: Double? = nil) -> ArenaCamera {
        var next = self
        if let newX { next.x = newX }
        if let newY { next.y = newY }
        if let newDistance { next.distance = newDistance }
        if let newFocus { next.focusHeight = newFocus }
        if let newCenterX { next.centerX = newCenterX }
        if let newCenterY { next.centerY = newCenterY }
        if let newTilt { next.tilt = newTilt }
        return next
    }
}

/// Android `world/LandscapeFraming`: fit ground positions plus sprite headroom into the playable region, without
/// changing the world.
enum LandscapeFraming {
    static func fit(_ base: ArenaCamera, _ positions: [(Double, Double)], _ width: Double, _ height: Double, _ left: Double, _ right: Double,
                    _ top: Double, _ bottom: Double, _ actorHeight: Double) -> ArenaCamera {
        // Kotlin `require(width > 0 && height > 0 && left < right && top < bottom)`; iOS keeps the camera instead.
        if !(width > 0 && height > 0 && left < right && top < bottom) { return base }
        var camera = base
        for _ in 0..<180 {
            let inside = positions.allSatisfy { point in
                [0.0, actorHeight].allSatisfy { z in
                    let p = camera.project(point.0, point.1, z, width, height)
                    return p.depth > 1 && p.x >= left && p.x <= right && p.y >= top && p.y <= bottom
                }
            }
            if inside { return camera }
            camera = camera.copy(distance: camera.distance + 0.5)
        }
        return camera
    }
}
