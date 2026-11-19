import Foundation

/// Android `core/EliminationExit.kt`. Presentation only: eliminated actors never regain collisions or controls.
enum EliminationExit {
    static let DURATION = 2.8

    static func visible(_ a: GameActor, _ time: Double) -> Bool {
        return a.active || (!a.departed && a.spectator == .letters && a.eliminatedAt >= 0 && (a.exitAt < 0 || time < a.exitAt + DURATION))
    }

    static func start(_ a: GameActor, _ c: GameConfig, _ time: Double) {
        if a.eliminatedAt < 0 || a.exitAt >= 0 { return }
        a.exitAt = time
        a.exitFrom = a.position
        let candidates = [V(-0.8, a.position.y), V(c.width + 0.8, a.position.y), V(a.position.x, -0.8), V(a.position.x, c.depth + 0.8)]
        // Kotlin `minBy`: the first of equal distances wins.
        var best = candidates[0]
        var bestDistance = (best - a.position).length()
        for candidate in candidates.dropFirst() {
            let d = (candidate - a.position).length()
            if bestDistance > d {
                best = candidate
                bestDistance = d
            }
        }
        a.exitTo = best
    }

    static func fraction(_ a: GameActor, _ time: Double) -> Double {
        return a.exitAt < 0 ? 0.0 : Kotlin.clamp((time - a.exitAt) / DURATION, 0.0, 1.0)
    }

    static func position(_ a: GameActor, _ time: Double) -> V {
        guard let from = a.exitFrom, let to = a.exitTo else { return a.position }
        return from + (to - from) * fraction(a, time)
    }

    static func walking(_ a: GameActor, _ time: Double) -> Bool {
        return a.exitAt >= 0 && time >= a.exitAt && time < a.exitAt + DURATION
    }

    static func facing(_ a: GameActor) -> V {
        return ((a.exitTo ?? a.position) - (a.exitFrom ?? a.position)).unit()
    }

    static func gait(_ a: GameActor, _ time: Double) -> Double {
        return max(time - a.exitAt, 0.0) * 7
    }
}
