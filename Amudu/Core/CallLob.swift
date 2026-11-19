import Foundation

/// Android `core/CallLob.kt`: the name-call toss (gentle, medium and strong lobs per arena).
enum CallLob {
    static let WIND_FACTOR = 0.90

    static func maximumVz(_ scene: ArenaScene) -> Double {
        let old = 9.8 * 4.0 / 2 - 1.2 / 4.0
        let vz = scene == .andromeda ? old : old * (0.75).squareRoot()
        let apex = (1.2 + vz * vz / (2 * scene.gravity)) * 0.90
        return (2 * scene.gravity * (apex - 1.2)).squareRoot()
    }

    static func spreadFactor(_ scene: ArenaScene, _ vz: Double) -> Double {
        return 1.2 + vz * vz / (2 * scene.gravity) > (1.2 + pow(maximumVz(scene), 2.0) / (2 * scene.gravity)) * 0.50 ? 0.95 : 0.85
    }

    static func minimumApex(_ scene: ArenaScene, _ human: Bool) -> Double {
        return (scene == .beach ? 3.08 : 2.8) * (human ? 1.15 : 1.0) * 1.20 * 1.10 * 1.15
    }

    static func velocity(_ scene: ArenaScene, _ human: Bool, _ power: Double) -> Double {
        let low = (2 * scene.gravity * (minimumApex(scene, human) - 1.2)).squareRoot()
        return low + (maximumVz(scene) - low) * pow(Kotlin.clamp(power, 0.0, 1.0), 2.0)
    }

    static func high(_ scene: ArenaScene, _ vz: Double) -> Bool {
        return (1.2 + vz * vz / (2 * scene.gravity)) >= 0.80 * (1.2 + pow(maximumVz(scene), 2.0) / (2 * scene.gravity))
    }

    /// A deliberate sideways swipe overrides random sideways spread; depth variation remains.
    static func aimedOffset(_ random: V, _ drift: Double, _ radius: Double) -> V {
        let d = Kotlin.clamp(drift, -1.0, 1.0)
        if abs(d) < 0.08 { return random }
        let x = d * radius
        let y = random.y * max(0.0, 1 - d * d).squareRoot()
        let v = V(x, y)
        return v.length() > radius ? v.unit() * radius : v
    }
}
