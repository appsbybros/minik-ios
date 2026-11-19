import Foundation

/// Android `core/FleeMovement.kt`: pick a safe outward route occasionally; never roll a new direction each frame.
enum FleeMovement {
    private static func dot(_ a: V, _ b: V) -> Double { return a.x * b.x + a.y * b.y }

    private static func rotate(_ v: V, _ a: Double) -> V {
        return V(v.x * cos(a) - v.y * sin(a), v.x * sin(a) + v.y * cos(a))
    }

    static func update(_ a: GameActor, _ ball: Ball, _ wind: V, _ c: GameConfig, _ time: Double, _ dt: Double, _ seed: Int64,
                       _ phase: Phase, _ actors: [GameActor] = []) {
        let key = ball.flightId + ":" + String(ball.bounces) + ":" + phase.rawValue
        if a.fleeFlight != key || time >= a.fleeNextAt {
            var random = KotlinRandom(seed: seed ^ Int64(Kotlin.hashCode(key)) ^ Int64(Kotlin.hashCode(a.member.id)))
            let bias = random.nextDouble(-0.65, 0.65)
            let away = (a.position - ball.position).unit()
            let future = ball.position + ball.velocity * 0.55 + wind * (0.5 * 0.55 * 0.55)
            let safe = (a.position - future).unit()
            let preferred = rotate(safe, bias)
            let speed = c.moveSpeed * c.scene.run * AmuduCharacters.get(a.member.character).qualities.runFactor
            let horizon = 0.65
            func bound(_ p: V) -> V {
                return V(Kotlin.clamp(p.x, 0.6, c.width - 0.6), Kotlin.clamp(p.y, 0.6, c.depth - 0.6))
            }
            var best = V(0.0, 0.0)
            var bestScore = 0.0
            let angles = [-Double.pi / 2, -Double.pi / 3, -Double.pi / 6, 0.0, Double.pi / 6, Double.pi / 3, Double.pi / 2]
            let directions = angles.map { rotate(away, $0) } + [preferred, a.fleeDirection]
            for direction in directions {
                if direction.length() < 0.01 { continue }
                let dest = bound(a.position + direction.unit() * (speed * horizon))
                let travel = dest - a.position
                if travel.length() < 0.12 || dot(travel.unit(), away) < -0.20 { continue }
                if actors.contains(where: { $0 !== a && $0.active && !ActorMovement.clearRoute(a.position, dest, $0.position) }) { continue }
                // Do not cut across the ball's path in pursuit of a farther end point.
                let halfway = a.position + travel * 0.5
                let initial = (a.position - ball.position).length()
                if (halfway - ball.position).length() < initial - 0.20 { continue }
                let clearance = 0.65 * ((dest - future).length() - (a.position - future).length()) +
                    0.35 * ((dest - ball.position).length() - initial)
                let heading = travel.unit()
                let score = clearance + 3.0 * dot(heading, preferred) + 0.18 * dot(heading, a.fleeDirection)
                if score > bestScore + 0.025 {
                    bestScore = score
                    best = heading
                }
            }
            a.fleeDirection = best
            a.fleeFlight = key
            a.fleeNextAt = time + 0.40 + random.nextDouble() * 0.18
        }
        // Smooth the actual command as well as the rendered pose, with fixed gameplay speed limits.
        let blend = 1 - exp(-dt * 9)
        a.move = a.move + (a.fleeDirection - a.move) * blend
        if a.move.length() < 0.025 && a.fleeDirection.length() < 0.01 { a.move = V(0.0, 0.0) }
        if a.move.length() < 0.08 { a.facing = (ball.position - a.position).unit() }
    }
}
