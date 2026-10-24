import Foundation

// Port of view/TripleShotShotPresentation.kt (Android 6c38131), statement by statement (spec 07 §3.6, §4.9).
// Float maths keeps the Kotlin operand order; `Float.pow(3)` and `sqrt` compute in Double like kotlin.math on the JVM
// (AndroidKit `kpow`, `ksqrt`). A new shot is detected by reference identity of the ShotState instance (`!==`).
// Kotlin `sampleRecorded` declares a local `startY` that shadows its parameter of the same name; the local is
// `worldStartY` here (its initialiser reads the parameter, every later use reads the local, as in Kotlin).

/** Lifts the existing 2D simulation into a shot plane. The original collider events stay authoritative. */
final class TripleShotShotPresentation {
    private var shot: TripleShotPhysics.ShotState? = nil
    private var release = CourtPoint(x: 0, y: 1.5, z: 0)
    var held = CourtPoint(x: 0, y: 1.5, z: 0)
    private var radial = false
    private var radialScale: Float = 0.01

    func prepareWorldRelease(point: CourtPoint, scale: Float = 0.01) {
        held = point; release = point; radial = true; radialScale = scale; shot = nil
    }

    private func radialDirection(hoop: CourtPoint) -> (Float, Float) {
        let x = release.x - hoop.x; let z = release.z - hoop.z
        let length = ksqrt(x * x + z * z).coerceAtLeast(0.001)
        return (x / length, z / length)
    }

    /** Recorded multiplayer samples use the same side-section projection as local physics. */
    func sampleRecorded(x: Float, y: Float, startX: Float, startY: Float, flightProgress: Float,
                        hoop: CourtPoint, sourceHoopX: Float, sourceHoopY: Float, rimSpan: Float, verticalScale: Float) -> CourtPoint {
        let t = flightProgress.coerceIn(0, 1)
        let correction = kpow(1 - t, 3)
        let scale = Float(1.1) / rimSpan.coerceAtLeast(1)
        let baseZ = hoop.z - (x - sourceHoopX) * scale
        let startZ = hoop.z - (startX - sourceHoopX) * scale
        let baseY = hoop.y + (sourceHoopY - y) * verticalScale
        let worldStartY = hoop.y + (sourceHoopY - startY) * verticalScale
        return CourtPoint(x: hoop.x + (held.x - hoop.x) * (1 - t),
                          y: (baseY + (held.y - worldStartY) * correction).coerceAtLeast(0.16),
                          z: baseZ + (held.z - startZ) * correction)
    }

    func sample(state: TripleShotPhysics.ShotState, geometry: TripleShotPhysics.Geometry, hoop: CourtPoint, verticalScale: Float) -> CourtPoint {
        if shot !== state { shot = state; release = held }
        if radial {
            let (dx, dz) = radialDirection(hoop: hoop)
            let radius = (geometry.hoopCenterX - state.x) * radialScale
            return CourtPoint(x: hoop.x + dx * radius, y: hoop.y + (geometry.hoopY - state.y) * radialScale, z: hoop.z + dz * radius)
        }
        let t = (state.elapsedSeconds / state.expectedFlightSeconds.coerceAtLeast(0.1)).coerceIn(0, 1)
        let anchorCorrection = kpow(1 - t, 3)
        let lateral = Float(1.1) / (geometry.rightRimX - geometry.leftRimX).coerceAtLeast(1)
        // The physics engine is a vertical side section through the basket. Its horizontal
        // axis therefore becomes court DEPTH: the two rim colliders are the near/far rim,
        // and the backboard collider sits behind them in the same plane as the glass mesh.
        let baseZ = hoop.z - (state.x - geometry.hoopCenterX) * lateral
        let startZ = hoop.z - (state.startX - geometry.hoopCenterX) * lateral
        let baseY = hoop.y + (geometry.hoopY - state.y) * verticalScale
        let startY = hoop.y + (geometry.hoopY - state.startY) * verticalScale
        // The old screen-space collider radius was calibrated independently of its X/Y
        // image stretch. At a real contact, use the actual mesh/ball radii so a resting
        // ball touches the ring rather than hovering above it or sinking through it.
        if state.rimHits > 0 {
            let rimX = abs(state.x - geometry.leftRimX) < abs(state.x - geometry.rightRimX) ? geometry.leftRimX : geometry.rightRimX
            let dx = state.x - rimX; let dy = state.y - geometry.hoopY
            let distance = ksqrt(dx * dx + dy * dy)
            if distance > 0 && distance <= (geometry.ballRadius + geometry.rimColliderRadius) * 1.12 {
                let rimZ = hoop.z - (rimX - geometry.hoopCenterX) * lateral
                return CourtPoint(x: hoop.x, y: hoop.y - dy / distance * 0.255, z: rimZ - dx / distance * 0.255)
            }
        }
        if state.backboardHits > 0 && abs(state.x - geometry.backboardX) <= geometry.ballRadius * 1.12 &&
            state.y >= geometry.backboardTopY && state.y <= geometry.backboardBottomY {
            return CourtPoint(x: hoop.x, y: baseY, z: hoop.z - 0.67 + (state.x < geometry.backboardX ? 0.21 : -0.21))
        }
        let remainingLateral: Float = state.made || state.rimHits > 0 || state.backboardHits > 0 || state.touchingNet ? 0 : 1 - t
        return CourtPoint(x: hoop.x + (release.x - hoop.x) * remainingLateral,
                          y: (baseY + (release.y - startY) * anchorCorrection).coerceAtLeast(0.16),
                          z: baseZ + (release.z - startZ) * anchorCorrection)
    }

    func planePoint(point: CourtPoint, geometry: TripleShotPhysics.Geometry, hoop: CourtPoint, scale: Float) -> (Float, Float) {
        let (dx, dz) = radialDirection(hoop: hoop)
        return (geometry.hoopCenterX - ((point.x - hoop.x) * dx + (point.z - hoop.z) * dz) / radialScale,
                geometry.hoopY + (hoop.y - point.y) / radialScale)
    }

    func velocity(state: TripleShotPhysics.ShotState, geometry: TripleShotPhysics.Geometry,
                  hoop: CourtPoint, verticalScale: Float) -> CourtPoint {
        if radial {
            let (dx, dz) = radialDirection(hoop: hoop)
            return CourtPoint(x: -dx * state.vx * radialScale, y: -state.vy * radialScale, z: -dz * state.vx * radialScale)
        }
        let duration = state.expectedFlightSeconds.coerceAtLeast(0.1)
        let t = (state.elapsedSeconds / duration).coerceIn(0, 1)
        let correctionSpeed: Float = t < 1 ? Float(-3) * (1 - t) * (1 - t) / duration : 0
        let lateral = Float(1.1) / (geometry.rightRimX - geometry.leftRimX).coerceAtLeast(1)
        let startZ = hoop.z - (state.startX - geometry.hoopCenterX) * lateral
        let startY = hoop.y + (geometry.hoopY - state.startY) * verticalScale
        let vx: Float = t < 1 && state.rimHits == 0 && state.backboardHits == 0 ? (hoop.x - release.x) / duration : 0
        return CourtPoint(x: vx, y: -state.vy * verticalScale + (release.y - startY) * correctionSpeed,
                          z: -state.vx * lateral + (release.z - startZ) * correctionSpeed)
    }

    // Kotlin positional call forms.
    func sampleRecorded(_ x: Float, _ y: Float, _ startX: Float, _ startY: Float, _ flightProgress: Float,
                        _ hoop: CourtPoint, _ sourceHoopX: Float, _ sourceHoopY: Float, _ rimSpan: Float, _ verticalScale: Float) -> CourtPoint {
        return sampleRecorded(x: x, y: y, startX: startX, startY: startY, flightProgress: flightProgress, hoop: hoop,
                              sourceHoopX: sourceHoopX, sourceHoopY: sourceHoopY, rimSpan: rimSpan, verticalScale: verticalScale)
    }

    func sample(_ state: TripleShotPhysics.ShotState, _ geometry: TripleShotPhysics.Geometry, _ hoop: CourtPoint, _ verticalScale: Float) -> CourtPoint {
        return sample(state: state, geometry: geometry, hoop: hoop, verticalScale: verticalScale)
    }
}
