import Foundation

/// Android `core/BallShadow.kt`: analytic projection of a finite ball under the arena's sun and local night lights.
enum BallShadow {
    struct Footprint: Equatable {
        let center: V
        let radiusX: Double
        let radiusY: Double
        let angle: Double
        let softness: Double
        let opacity: Double
    }

    static func project(_ b: Ball, _ c: GameConfig, _ time: Double) -> [Footprint] {
        if b.burst { return [] }
        let r = BallContact.radius(c.ball)
        let h = max(r, b.height * 2.0)
        if c.daylight != .night {
            let slope: V
            switch c.daylight {
            case .morning: slope = V(0.82, 0.40)
            case .evening: slope = V(-1.25, 0.45)
            default: slope = V(0.10, 0.14)
            }
            let stretch = (1 + pow(slope.length(), 2.0)).squareRoot()
            let blur = 0.025 + h * 0.0093
            let opacity = (c.daylight == .evening ? 0.30 : 0.48) * r * r / (r * r + blur * blur)
            return [Footprint(center: b.position + slope * h, radiusX: r * stretch, radiusY: r, angle: atan2(slope.y, slope.x),
                              softness: blur, opacity: opacity)]
        }
        // Same lamp feet and animated spotlight tracks as AmuduView.drawDaylight.
        var lights: [(V, Double, Double)] = [V(0.7, 2.2), V(c.width - 0.7, 6.5), V(1.2, c.depth - 1.0)].map { ($0, 10.0, 0.24) }
        for i in 0...2 {
            let d = Double(i)
            lights.append((V(c.width * (0.5 + 0.36 * sin(time * 0.32 + d * 2.1)), c.depth * (0.52 + 0.36 * cos(time * 0.24 + d * 2.0))),
                           12.0, 0.12))
        }
        var prints: [Footprint] = []
        for (point, z, alpha) in lights {
            if h >= z - r { continue } // A ball above a lamp cannot block its downward light.
            let scale = z / (z - h)
            let offset = b.position - point
            let radius = r * scale
            let blur = 0.07 + 0.30 * h / (z - h)
            let attenuation = 1 / (1 + pow(offset.length(), 2.0) / 160)
            prints.append(Footprint(center: point + offset * scale, radiusX: radius, radiusY: radius, angle: 0.0, softness: blur,
                                    opacity: alpha * attenuation * r * r / (r * r + blur * blur)))
        }
        let visible = prints.filter { $0.opacity > 0.008 }
        // Kotlin `sortedByDescending { it.opacity }` is stable.
        return Array(Kotlin.stableSorted(visible) { $0.opacity > $1.opacity }.prefix(2))
    }
}
