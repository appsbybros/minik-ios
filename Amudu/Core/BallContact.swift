import Foundation

/// Android `core/BallContact.kt`: first contact along the complete travel segment, before a later ground crossing.
enum BallContact {
    static func radius(_ kind: BallKind) -> Double {
        return 0.30 * kind.visualScale * (kind == .beach ? 1.2 : 1.0)
    }

    static func first(_ from: V, _ to: V, _ fromZ: Double, _ toZ: Double, _ center: V, _ radius: Double, _ bottom: Double,
                      _ top: Double) -> Double? {
        let d = to - from
        let f = from - center
        let aa = d.x * d.x + d.y * d.y
        var enter = 0.0
        var leave = 1.0
        if aa < 1e-12 {
            if f.length() > radius { return nil }
        } else {
            let bb = 2 * (f.x * d.x + f.y * d.y)
            let cc = f.x * f.x + f.y * f.y - radius * radius
            let discriminant = bb * bb - 4 * aa * cc
            if discriminant < 0 { return nil }
            let root = discriminant.squareRoot()
            enter = max(enter, (-bb - root) / (2 * aa))
            leave = min(leave, (-bb + root) / (2 * aa))
        }
        let dz = toZ - fromZ
        if abs(dz) < 1e-12 {
            // Kotlin `fromZ !in bottom..top` (an empty range when bottom > top).
            if !(fromZ >= bottom && fromZ <= top) { return nil }
        } else {
            let a = (bottom - fromZ) / dz
            let b = (top - fromZ) / dz
            enter = max(enter, min(a, b))
            leave = min(leave, max(a, b))
        }
        return (enter <= leave && enter >= 0.0 && enter <= 1.0) ? enter : nil
    }
}
