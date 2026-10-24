import Foundation

// Port of view/TripleShotRadialShot.kt (Android 6c38131), statement by statement.
// Kotlin `hypot` on Float computes in Double on the JVM (AndroidKit `khypot`); Kotlin `Pair` -> a Swift tuple.

/** A vertical plane from the actual hand to the hoop, in one physical scale on both axes. */
enum TripleShotRadialShot {
    static func geometry(base: TripleShotPhysics.Geometry, release: CourtPoint, hoop: CourtPoint, scale: Float) -> TripleShotPhysics.Geometry {
        let dx = release.x - hoop.x; let dz = release.z - hoop.z
        let distance = khypot(dx, dz).coerceAtLeast(0.001)
        let dirX = dx / distance; let dirZ = dz / distance
        // Intersect this shooting plane with the real finite backboard, not an infinite wall.
        let boardRadius: Float = abs(dirZ) > 0.001 ? Float(-0.67) / dirZ : 10000
        let meetsBoard = abs(dirX * boardRadius) <= 1.1
        var g = base
        g.gravityPxPerSec2 = Float(9.8) / scale
        g.leftRimX = base.hoopCenterX - Float(0.55) / scale; g.rightRimX = base.hoopCenterX + Float(0.55) / scale
        g.rimColliderRadius = Float(0.045) / scale; g.ballRadius = Float(0.21) / scale
        g.backboardX = meetsBoard ? base.hoopCenterX - boardRadius / scale : 1e8
        g.backboardTopY = base.hoopY - Float(1.05) / scale; g.backboardBottomY = base.hoopY + Float(0.2) / scale
        g.netBottomY = base.hoopY + Float(0.55) / scale
        g.netBottomLeftX = base.hoopCenterX - Float(0.36) / scale; g.netBottomRightX = base.hoopCenterX + Float(0.36) / scale
        return g
    }

    static func start(release: CourtPoint, hoop: CourtPoint, geometry: TripleShotPhysics.Geometry, scale: Float) -> (Float, Float) {
        (geometry.hoopCenterX - khypot(release.x - hoop.x, release.z - hoop.z) / scale,
         geometry.hoopY + (hoop.y - release.y) / scale)
    }
}
