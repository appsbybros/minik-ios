import Foundation

/// Android `core/CatchPhysics.kt`: catch windows, catch chances from what is visible, and jump take-off speed.
enum CatchPhysics {
    static let HUMAN_WINDOW = 0.5

    static func window(_ a: GameActor, _ c: GameConfig) -> Double {
        return a.member.bot ? c.catchWindow : HUMAN_WINDOW
    }

    static func probability(_ a: GameActor, _ b: Ball, _ thrower: GameActor?, _ attack: Bool = false) -> Double {
        let incoming = (b.velocity * -1.0).unit()
        let facing = a.facing.unit()
        let facingEase = Kotlin.clamp((incoming.x * facing.x + incoming.y * facing.y + 1) * 0.5, 0.0, 1.0)
        let speed = hypot(b.velocity.length(), b.vz)
        let speedEase = Kotlin.clamp(1 - (speed - 4) / 12, 0.0, 1.0)
        let distanceEase = Kotlin.clamp(((thrower?.position ?? b.position) - a.position).length() / 7, 0.0, 1.0)
        let still = (a.actuallyMoving || a.move.length() > 0.08) ? 0.0 : 1.0
        let ease = Kotlin.clamp(0.42 * facingEase + 0.28 * speedEase + 0.20 * still + 0.10 * distanceEase, 0.0, 1.0)
        let skill = Double(AmuduCharacters.get(a.member.character).qualities.catching - 1) / 4.0
        let low = a.member.bot ? 0.12 + 0.18 * skill : 0.225
        let high = a.member.bot ? 0.78 + 0.19 * skill : 0.95
        return (low + (high - low) * ease) * (attack ? 0.94 : 1.0) * (a.member.bot ? 0.90 : 1.0)
    }

    static func jumpVelocity(_ a: GameActor) -> Double {
        return a.member.bot ? 3.7 + Double(AmuduCharacters.get(a.member.character).qualities.jumping) * 0.30 : 4.8
    }
}
