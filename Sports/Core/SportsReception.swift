import Foundation

/// Port of Android core/SportsReception.kt: one authority chooses the human receiver. Cameras may
/// opt out locally; time never does.
enum SportsReception {
    struct Focus: Equatable {
        let id: String
        let eta: Double
        let strength: Double
    }

    static func incoming(_ e: SportsEngine) -> Focus? {
        let b = e.ball
        if e.phase != .rally || !b.active || e.paused { return nil }
        let speed2 = b.velocity.x * b.velocity.x + b.velocity.y * b.velocity.y
        if speed2 < 0.04 { return nil }
        var best: Focus? = nil
        for p in e.players where !p.member.bot && e.canReturn(p) {
            let d = p.p - b.p
            let t = (d.x * b.velocity.x + d.y * b.velocity.y) / speed2
            if t < -0.08 || t > 1.25 { continue }
            let at = b.p + b.velocity * max(t, 0.0)
            if (at - p.p).length() > 1.6 { continue }
            let z = b.z + b.vz * t - 0.5 * e.config.gravity * t * t
            if z < -0.2 || z > 3.5 { continue }
            let u = min(max((1.25 - t) / 1.1, 0.0), 1.0)
            let focus = Focus(id: p.member.id, eta: t, strength: u * u * (3 - 2 * u))
            // Kotlin `minWithOrNull(compareBy { eta }.thenBy { id })`: the first of equal minima.
            if let current = best {
                if focus.eta < current.eta || (focus.eta == current.eta && focus.id.javaPrecedes(current.id)) { best = focus }
            } else {
                best = focus
            }
        }
        return best
    }

    static func smooth(_ current: Double, _ target: Double, _ realDt: Double) -> Double {
        return current + (target - current) * (1 - exp(-min(max(realDt, 0.0), 0.05) * 4.0))
    }
}
