import Foundation

/// Android `core/ActorMovement.kt`: swept body contact — stop/slide before another player, never penetrate and push back
/// each tick.
enum ActorMovement {
    static let separation = 1.1

    private static func dot(_ a: V, _ b: V) -> Double { return a.x * b.x + a.y * b.y }

    static func advance(_ start: V, _ delta: V, _ blockers: [V], _ c: GameConfig) -> V {
        func bound(_ p: V) -> V {
            return V(Kotlin.clamp(p.x, 0.6, c.width - 0.6), Kotlin.clamp(p.y, 0.6, c.depth - 0.6))
        }
        var p = start
        var remaining = bound(start + delta) - start
        for _ in 0..<4 {
            if remaining.length() < 1e-9 { return p }
            var fraction = 1.0
            var normal: V?
            for other in blockers {
                let offset = p - other
                let approach = dot(offset, remaining)
                if approach >= -1e-12 { continue }
                let length2 = dot(remaining, remaining)
                let distance2 = dot(offset, offset)
                let disc = approach * approach - length2 * (distance2 - separation * separation)
                if disc < 0 { continue }
                let hit = distance2 <= separation * separation ? 0.0 : (-approach - disc.squareRoot()) / length2
                if hit >= 0.0 && hit <= fraction {
                    fraction = hit
                    normal = (p + remaining * hit - other).unit()
                }
            }
            p = bound(p + remaining * fraction)
            guard let n = normal else { return p }
            remaining = remaining * (1 - fraction)
            remaining = remaining - n * min(0.0, dot(remaining, n))
            remaining = bound(p + remaining) - p
        }
        return p
    }

    /// Route clearance at planning time; a blocked bot can choose another outward route or rest.
    static func clearRoute(_ start: V, _ end: V, _ other: V) -> Bool {
        let path = end - start
        let length2 = dot(path, path)
        if length2 < 1e-10 { return true }
        let t = Kotlin.clamp(dot(other - start, path) / length2, 0.0, 1.0)
        let before = (other - start).length()
        return (start + path * t - other).length() >= min(separation + 0.04, before) - 1e-6
    }
}
