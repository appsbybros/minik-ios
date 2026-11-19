import Foundation

/// Android `world/TightFraming`: maximize the actual visible scene, including perspective asymmetry, without moving
/// actors.
enum TightFraming {
    static func fit(_ base: ArenaCamera, _ points: [(Double, Double, Double)], _ w: Double, _ h: Double, _ left: Double, _ right: Double,
                    _ top: Double, _ bottom: Double, _ minimum: Double = 8.0) -> ArenaCamera {
        if points.isEmpty || w < 1 || h < 1 || right <= left || bottom <= top { return base }
        func at(_ distance: Double) -> ArenaCamera? {
            let camera = base.copy(distance: distance, centerX: 0.5, centerY: 0.5)
            var x0 = Double.infinity
            var x1 = -Double.infinity
            var y0 = Double.infinity
            var y1 = -Double.infinity
            for point in points {
                let p = camera.project(point.0, point.1, point.2, w, h)
                if p.depth <= 1 { return nil }
                x0 = min(x0, p.x)
                x1 = max(x1, p.x)
                y0 = min(y0, p.y)
                y1 = max(y1, p.y)
            }
            if x1 - x0 > right - left || y1 - y0 > bottom - top { return nil }
            return camera.copy(centerX: 0.5 + ((left + right) - (x0 + x1)) / 2 / w, centerY: 0.5 + ((top + bottom) - (y0 + y1)) / 2 / h)
        }
        if let tight = at(minimum) { return tight }
        var low = minimum
        var high = max(minimum + 1, base.distance)
        var fit = at(high)
        for _ in 0..<8 where fit == nil {
            low = high
            high *= 1.5
            fit = at(high)
        }
        guard var found = fit else { return base.copy(distance: high) }
        // Projection extent shrinks monotonically with distance. Subpixel precision needs a bounded search, not
        // hundreds of point-list allocations every frame.
        for _ in 0..<14 {
            let middle = (low + high) / 2
            if let candidate = at(middle) {
                high = middle
                found = candidate
            } else {
                low = middle
            }
        }
        return found
    }
}
