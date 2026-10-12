import Foundation

/// Port of Android ArenaCamera.kt (MinikSports): the perspective (or, for the wide volleyball court,
/// orthographic) camera used by the court renderer and the touch mapping. Android works in pixels
/// and iOS in points; the projection only depends on the view size, so the same world point lands on
/// the same relative screen position.
struct GroundPoint: Equatable {
    let x: Double
    let y: Double

    init(_ x: Double, _ y: Double) {
        self.x = x
        self.y = y
    }
}

/// Android `ScreenPoint(x: Float, y: Float, depth: Double)`; the Float rounding is kept.
struct ScreenPoint: Equatable {
    var x: Float
    var y: Float
    let depth: Double
}

struct ArenaCamera: Equatable {
    var x: Double
    var y: Double
    var distance: Double
    var focusHeight: Double
    var tilt: Double
    var fov: Double
    var centerY: Double
    var yaw: Double
    var horizontalScale: Double
    var centerX: Double
    var orthographic: Bool

    init(_ x: Double, _ y: Double, _ distance: Double = 26.0, _ focusHeight: Double = 0.0, _ tilt: Double = 1.02,
         _ fov: Double = 52.0, _ centerY: Double = 0.65, _ yaw: Double = 0.0, _ horizontalScale: Double = 1.0,
         _ centerX: Double = 0.5, orthographic: Bool = false) {
        self.x = x
        self.y = y
        self.distance = distance
        self.focusHeight = focusHeight
        self.tilt = tilt
        self.fov = fov
        self.centerY = centerY
        self.yaw = yaw
        self.horizontalScale = horizontalScale
        self.centerX = centerX
        self.orthographic = orthographic
    }

    /// Android `init { require(distance > 3 && tilt in .2..1.2 && fov in 25.0..85.0) }`, kept as a query.
    var isValid: Bool {
        return distance > 3 && tilt >= 0.2 && tilt <= 1.2 && fov >= 25.0 && fov <= 85.0
    }

    func project(_ x: Double, _ y: Double, _ z: Double, _ width: Int, _ height: Int) -> ScreenPoint {
        let dx = x - self.x
        let dy = y - self.y
        let rx = cos(yaw) * dx - sin(yaw) * dy
        let ry = sin(yaw) * dx + cos(yaw) * dy
        let dz = z - focusHeight
        let depth = distance - sin(tilt) * ry - cos(tilt) * dz
        let f = Double(height) / (2 * tan(fov * Double.pi / 360))
        let projectionDepth = orthographic ? distance : max(depth, 0.1)
        let sx = Double(width) * centerX + rx * f * horizontalScale / projectionDepth
        let sy = Double(height) * centerY - (-cos(tilt) * ry + sin(tilt) * dz) * f / projectionDepth
        return ScreenPoint(x: Float(sx), y: Float(sy), depth: depth)
    }

    func ground(_ sx: Float, _ sy: Float, _ width: Int, _ height: Int, _ z: Double = 0.0) -> GroundPoint {
        let si = sin(tilt)
        let co = cos(tilt)
        let f = Double(height) / (2 * tan(fov * Double.pi / 360))
        let r = (Double(height) * centerY - Double(sy)) / f
        let dz = z - focusHeight
        if orthographic {
            let ry = (si * dz - r * distance) / co
            let rx = (Double(sx) - Double(width) * centerX) * distance / (f * horizontalScale)
            return GroundPoint(x + cos(yaw) * rx + sin(yaw) * ry, y - sin(yaw) * rx + cos(yaw) * ry)
        }
        var denominator = r * si - co
        if abs(denominator) < 0.02 { denominator = -0.02 }
        let ry = (r * (distance - co * dz) - si * dz) / denominator
        let depth = distance - si * ry - co * dz
        let rx = (Double(sx) - Double(width) * centerX) * depth / (f * horizontalScale)
        return GroundPoint(x + cos(yaw) * rx + sin(yaw) * ry, y - sin(yaw) * rx + cos(yaw) * ry)
    }

    /// Centres the points and backs away (one unit at a time, at most 100) until every point sits
    /// inside the safe frame.
    func frameGround(_ points: [GroundPoint], _ width: Int, _ height: Int, _ z: Double) -> ArenaCamera {
        guard let first = points.first else { return self }
        var minX = first.x
        var maxX = first.x
        var minY = first.y
        var maxY = first.y
        for p in points {
            minX = min(minX, p.x)
            maxX = max(maxX, p.x)
            minY = min(minY, p.y)
            maxY = max(maxY, p.y)
        }
        var c = self
        c.x = (minX + maxX) / 2
        c.y = (minY + maxY) / 2
        c.focusHeight = z
        c.distance = 24.0
        let w = Double(width)
        let h = Double(height)
        let top = h * (height > width ? 0.48 : 0.38)
        for _ in 0..<100 {
            let fits = points.allSatisfy { point in
                let p = c.project(point.x, point.y, z, width, height)
                let px = Double(p.x)
                let py = Double(p.y)
                return px >= w * 0.10 && px <= w * 0.90 && py >= top && py <= h * 0.80
            }
            if fits { return c }
            c.distance += 1
        }
        return c
    }

    /// Smooth exponential approach (rate 3.2 per second, steps capped at 0.1 s); never overshoots.
    func toward(_ target: ArenaCamera, _ dt: Double) -> ArenaCamera {
        let a = 1 - exp(-min(max(dt, 0.0), 0.1) * 3.2)
        var c = self
        c.x = x + (target.x - x) * a
        c.y = y + (target.y - y) * a
        c.distance = distance + (target.distance - distance) * a
        c.focusHeight = focusHeight + (target.focusHeight - focusHeight) * a
        c.centerY = centerY + (target.centerY - centerY) * a
        c.yaw = yaw + (target.yaw - yaw) * a
        c.tilt = tilt + (target.tilt - tilt) * a
        return c
    }
}
