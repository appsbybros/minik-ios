import Foundation

/// Android `core/TargetThrow.kt`: a selected physical point, not a homing target. Flight is fixed at release.
enum TargetThrow {
    struct Aim: Equatable {
        let position: V
        let height: Double
    }

    /// Kotlin `dot(seconds, distance)`: the moving target dot's (side, height) offsets, as Kotlin's `Pair` (.first, .second).
    static func dot(_ seconds: Double, _ distance: Double) -> (first: Double, second: Double) {
        let rate = Kotlin.clamp(1.8 + distance * 0.30, 2.0, 10.0)
        return (first: sin(seconds * rate) * 1.32, second: 1.03 + sin(seconds * rate * 1.37 + 0.6) * 1.48)
    }

    static func valid(_ point: V, _ height: Double, _ c: GameConfig) -> Bool {
        return point.finite() && height.isFinite && height >= -0.75 && height <= 4.0 && point.x >= -4.0 && point.x <= c.width + 4 &&
            point.y >= -4.0 && point.y <= c.depth + 4
    }

    static func launch(_ a: GameActor, _ point: V, _ height: Double, _ c: GameConfig, _ wind: V, _ id: String, _ time: Double) -> Ball {
        let dir = (point - a.position).unit()
        let start = a.position + dir * 0.52
        let distance = max((point - start).length(), 0.2)
        // Long throws gain sufficient launch speed; range never silently clamps to a near target.
        let travel = Kotlin.clamp(distance / (c.ball.speed * 1.22), 0.14, 1.32)
        let velocity = (point - start) * (1 / travel) - wind * (0.5 * travel)
        let vz = (height - 1.17 + 0.5 * c.scene.gravity * travel * travel) / travel
        return Ball(start, 1.17, velocity, vz, nil, bounces: 0, flightId: id, launchAt: time)
    }
}

extension TargetThrow.Aim {
    /// Kotlin positional `TargetThrow.Aim(position, height)`.
    init(_ position: V, _ height: Double) {
        self.init(position: position, height: height)
    }
}
