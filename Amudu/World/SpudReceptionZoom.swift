import Foundation

/// Android `world/SpudReceptionZoom`: presentation only. Never advances, slows or writes authoritative gameplay state.
final class SpudReceptionZoom {
    struct Focus {
        let receiver: String
        let position: V
        let ball: Ball
        let seconds: Double
    }

    private(set) var amount = 0.0
    private var retained: Focus?

    func incoming(_ e: AmuduEngine, _ ownId: String, _ own: Bool, _ others: Bool) -> Focus? {
        if e.paused || e.sharedPause || e.result != nil || (e.phase != .air && e.phase != .flight) { return nil }
        let balls: [Ball]
        if let practice = e.practice {
            balls = practice.shots.filter { $0.incoming || $0.rebounded }.map { $0.ball }
        } else {
            balls = [e.ball]
        }
        let candidates = e.activeActors.filter { !$0.member.bot && ($0.member.id == ownId ? own : others) }
        var choices: [Focus] = []
        for a in candidates {
            for b in balls {
                let skip = e.practice == nil && ((e.phase == .air && a.member.id != e.called) || (e.phase == .flight && a.member.id == e.thrower))
                if b.holder != nil || b.height < 0.23 || skip { continue }
                let delta = a.position - b.position
                let closing = delta.x * b.velocity.x + delta.y * b.velocity.y
                if closing <= 0.0 && !(delta.length() < 1.8 && b.vz < 0) { continue }
                // Predict the real gravity/wind corridor, including high tosses and defensive drills.
                for i in 0...34 {
                    let t = Double(i) * 0.04
                    let z = b.height + b.vz * t - 0.5 * e.config.scene.gravity * t * t
                    if z < 0.23 { break }
                    let p = b.position + b.velocity * t + e.windVector * (0.5 * t * t)
                    if z >= 0.3 && z <= 2.5 && (p - a.position).length() < 1.8 {
                        choices.append(Focus(receiver: a.member.id, position: a.position, ball: b, seconds: t))
                        break
                    }
                }
            }
        }
        return choices.min { l, r in
            let lo = l.receiver == ownId ? 0 : 1
            let ro = r.receiver == ownId ? 0 : 1
            if lo != ro { return lo < ro }
            return l.seconds < r.seconds
        }
    }

    func step(_ focus: Focus?, _ dt: Double) -> Focus? {
        var desired = 0.0
        if let focus {
            let p = Kotlin.clamp((1.4 - focus.seconds) / 1.1, 0.0, 1.0)
            desired = p * p * (3 - 2 * p)
        }
        if focus != nil { retained = focus }
        amount += (desired - amount) * (1 - exp(-Kotlin.clamp(dt, 0.0, 0.05) * (desired > amount ? 8.0 : 4.5)))
        if focus == nil && amount < 0.001 {
            amount = 0.0
            retained = nil
        }
        return retained
    }

    /// Kotlin keeps a reference to the live ball object; Swift keeps a copy, so the same flight is looked up again
    /// (the engine's ball, or the practice shot) while it still exists.
    func live(_ f: Focus, _ e: AmuduEngine) -> Ball {
        let id = f.ball.flightId
        if !id.isEmpty {
            if e.ball.flightId == id { return e.ball }
            if let shot = e.practice?.shots.first(where: { $0.ball.flightId == id }) { return shot.ball }
        }
        return f.ball
    }
}
