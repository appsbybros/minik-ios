import Foundation

/// Android `core/GroundBounce.kt`: seeded surface variation shared by the authority and remote trajectory prediction.
enum GroundBounce {
    static func direction(_ incoming: V, _ flight: String, _ bounce: Int) -> V {
        var random = KotlinRandom(seed: Int64(Kotlin.hashCode(flight)) ^ ((Int64(bounce) &+ 1) &* 0x45d9f3b))
        if random.nextDouble() >= 0.15 { return incoming }
        let magnitude = random.nextDouble(0.35, 2.1)
        let angle = magnitude * (random.nextBoolean() ? 1 : -1)
        return V(incoming.x * cos(angle) - incoming.y * sin(angle), incoming.x * sin(angle) + incoming.y * cos(angle))
    }

    static func contain(_ b: inout Ball, _ c: GameConfig) {
        var vx = b.velocity.x
        var vy = b.velocity.y
        if b.position.x <= 0.250001 && vx < 0 || b.position.x >= c.width - 0.250001 && vx > 0 { vx = 0.0 }
        if b.position.y <= 0.250001 && vy < 0 || b.position.y >= c.depth - 0.250001 && vy > 0 { vy = 0.0 }
        b.position = V(Kotlin.clamp(b.position.x, 0.25, c.width - 0.25), Kotlin.clamp(b.position.y, 0.25, c.depth - 0.25))
        b.velocity = V(vx, vy)
    }

    static func edgeWind(_ b: Ball, _ c: GameConfig, _ wind: V) -> V {
        let stopX = b.position.x <= 0.250001 && b.velocity.x <= 0 && wind.x < 0 || b.position.x >= c.width - 0.250001 && b.velocity.x >= 0 && wind.x > 0
        let stopY = b.position.y <= 0.250001 && b.velocity.y <= 0 && wind.y < 0 || b.position.y >= c.depth - 0.250001 && b.velocity.y >= 0 && wind.y > 0
        return V(stopX ? 0.0 : wind.x, stopY ? 0.0 : wind.y)
    }
}
