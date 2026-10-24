import Foundation

// Port of view/TripleShotWorldMath.kt (TripleShotGame 6c38131), statement by statement.
// Spec 06 sections 3.2, 4.6, 4.10 and 7; golden values 9.6 (Tests/TripleShotTests/WorldMathTests.swift).
// The Kotlin matrices are hand-written (no android.opengl.Matrix): column-major FloatArray(16) in the GL convention
// (clip z in [-w, w]), kept on the CPU exactly as Kotlin computes them; the Metal vertex shader remaps clip z
// (spec 06 section 8 item 7). All arithmetic is Float in the Kotlin order; kotlin.math on Float (tan, sqrt, exp)
// is computed in Double like the JVM (ktan/ksqrt/kexp), min/max are java.lang.Math.min/max (kmin/kmax).
// FloatArray parameters that Kotlin fills in place are `inout [Float]`. `project` keeps Android's pixel units
// (Int surface width/height, DESIGN 9) and returns Kotlin's Pair as a `(first:, second:)` tuple.

/** Reused column-major buffers; standard right-handed OpenGL camera, +Z toward the viewer. */
enum TripleShotWorldMath {
    static let RIGHT_X: Float = 0.8351647
    static let RIGHT_Z: Float = -0.55

    static func perspective(out: inout [Float], fov: Float, aspect: Float) {
        for i in out.indices { out[i] = 0 }
        let f: Float = 1 / ktan(fov * PI_F / 360)
        out[0] = f / aspect; out[5] = f
        out[10] = -1.004008; out[11] = -1; out[14] = -0.4008016
    }

    static func lookAt(out: inout [Float], eye: CourtPoint, target: CourtPoint) {
        let dx = eye.x - target.x; let dy = eye.y - target.y; let dz = eye.z - target.z
        let l = ksqrt(dx * dx + dy * dy + dz * dz).coerceAtLeast(0.001)
        let zx = dx / l; let zy = dy / l; let zz = dz / l
        let xl = ksqrt(zz * zz + zx * zx).coerceAtLeast(0.001)
        let xx = zz / xl; let xz = -zx / xl
        let yx = zy * xz; let yy = zz * xx - zx * xz; let yz = -zy * xx
        out[0] = xx; out[1] = yx; out[2] = zx; out[3] = 0
        out[4] = 0; out[5] = yy; out[6] = zy; out[7] = 0
        out[8] = xz; out[9] = yz; out[10] = zz; out[11] = 0
        out[12] = -(xx * eye.x + xz * eye.z)
        out[13] = -(yx * eye.x + yy * eye.y + yz * eye.z)
        out[14] = -(zx * eye.x + zy * eye.y + zz * eye.z); out[15] = 1
    }

    static func multiply(out: inout [Float], a: [Float], b: [Float]) {
        for c in 0...3 {
            for r in 0...3 {
                let p0: Float = a[r] * b[c * 4]
                let p1: Float = a[r + 4] * b[c * 4 + 1]
                let p2: Float = a[r + 8] * b[c * 4 + 2]
                let p3: Float = a[r + 12] * b[c * 4 + 3]
                out[c * 4 + r] = p0 + p1 + p2 + p3
            }
        }
    }

    static func project(m: [Float], p: CourtPoint, width: Int, height: Int) -> (first: Float, second: Float)? {
        let w = m[3] * p.x + m[7] * p.y + m[11] * p.z + m[15]
        if w <= 0.2 { return nil }
        let first: Float = (1 + (m[0] * p.x + m[4] * p.y + m[8] * p.z + m[12]) / w) * width.toFloat() * 0.5
        let second: Float = (1 - (m[1] * p.x + m[5] * p.y + m[9] * p.z + m[13]) / w) * height.toFloat() * 0.5
        return (first: first, second: second)
    }
}

struct TripleShotCameraSpec {
    var fovY: Float
    var minimumDistance: Float
    var maximumDistance: Float
    var elevation: Float

    init(fovY: Float = 44, minimumDistance: Float = 10.3, maximumDistance: Float = 42, elevation: Float = 0.43) {
        self.fovY = fovY
        self.minimumDistance = minimumDistance
        self.maximumDistance = maximumDistance
        self.elevation = elevation
    }
}

/** Fixed lens, damped dolly and focus. Wider framing responds sooner than tighter framing. */
final class TripleShotWorldCamera {
    private let spec: TripleShotCameraSpec
    private(set) var focusX: Float = 0
    private(set) var focusZ: Float = 0
    private(set) var focusY: Float = 2
    private(set) var distance: Float
    private var initialized = false
    private var narrowerFor: Float = 0
    private var narrowing = false
    private(set) var view = [Float](repeating: 0, count: 16)
    private(set) var projection = [Float](repeating: 0, count: 16)
    private(set) var viewProjection = [Float](repeating: 0, count: 16)

    init(spec: TripleShotCameraSpec = TripleShotCameraSpec()) {
        self.spec = spec
        self.distance = spec.minimumDistance
    }

    func update(scene: TripleShotWorldSnapshot, aspect: Float, dt: Float) {
        let active = scene.actors.first(where: { $0.controlled }) ?? scene.actors.first
        var minX: Float = active?.position.x ?? 0; var maxX = minX
        var minZ: Float = active?.position.z ?? 0; var maxZ = minZ
        for a in scene.actors {
            minX = kmin(minX, a.position.x - 0.65); maxX = kmax(maxX, a.position.x + 0.65)
            minZ = kmin(minZ, a.position.z); maxZ = kmax(maxZ, a.position.z)
        }
        let ball = scene.balls.first
        if let ball = ball, ball.owner == nil {
            minX = kmin(minX, ball.position.x - 0.3); maxX = kmax(maxX, ball.position.x + 0.3)
            minZ = kmin(minZ, ball.position.z); maxZ = kmax(maxZ, ball.position.z)
        }
        let hoop = scene.hoops.getOrNull(scene.activeHoopIndex) ?? scene.hoops.first
        if let hoop = hoop {
            minX = kmin(minX, hoop.x - 1.2); maxX = kmax(maxX, hoop.x + 1.2)
            minZ = kmin(minZ, hoop.z); maxZ = kmax(maxZ, hoop.z)
        }
        var targetX: Float = (minX + maxX) * 0.5
        let targetZ: Float = (minZ + maxZ) * 0.5
        if scene.teamSize == 1 { targetX += 0.25 }
        // Follow shot height with a small vertical camera move before asking for a wider frame.
        let targetY: Float = kmax(2, ((ball?.position.y ?? 0) + 0.25) * 0.42).coerceAtMost(3.8)
        let tangent: Float = ktan(spec.fovY * PI_F / 360)
        // Fit actual projected heights/feet to the safe frame, using the same lens and view basis.
        // This avoids the excessively wide depth-envelope heuristic used by the first prototype.
        let length: Float = ksqrt(1 + spec.elevation * spec.elevation)
        let cp: Float = 1 / length; let sp: Float = spec.elevation / length
        var targetDistance: Float = spec.minimumDistance
        func include(x: Float, y: Float, z: Float, padding: Float = 0.25) {
            let dx = x - targetX; let dy = y - targetY; let dz = z - targetZ
            let lateral: Float = dx * TripleShotWorldMath.RIGHT_X + dz * TripleShotWorldMath.RIGHT_Z
            let forward: Float = -dx * TripleShotWorldMath.RIGHT_Z + dz * TripleShotWorldMath.RIGHT_X
            let up: Float = dy * cp - forward * sp
            let lateralDepth: Float = (abs(lateral) + padding) / (tangent * aspect.coerceAtLeast(0.45) * 0.90)
            let upDepth: Float = (abs(up) + padding) / (tangent * (up >= 0 ? 0.66 : 0.83))
            let requiredDepth: Float = kmax(lateralDepth, upDepth)
            targetDistance = kmax(targetDistance, (requiredDepth + forward * cp + dy * sp) / length)
        }
        for a in scene.actors {
            include(x: a.position.x, y: a.position.y, z: a.position.z, padding: 0.45)
            include(x: a.position.x, y: a.position.y + 2.5, z: a.position.z, padding: 0.45)
        }
        if let it = hoop {
            include(x: it.x - 1.3, y: 4.65, z: it.z)
            include(x: it.x + 1.3, y: 4.65, z: it.z)
        }
        if let ball = ball, ball.owner == nil {
            include(x: ball.position.x, y: ball.position.y, z: ball.position.z, padding: 0.4)
        }
        let wanted = targetDistance.coerceIn(spec.minimumDistance, spec.maximumDistance)
        if !initialized { focusX = targetX; focusZ = targetZ; focusY = targetY; distance = wanted; initialized = true }
        let step = dt.coerceIn(0, 0.05)
        let follow: Float = 1 - kexp(-step * 3)
        focusX += (targetX - focusX) * follow; focusZ += (targetZ - focusZ) * follow
        focusY += (targetY - focusY) * (1 - kexp(-step * (targetY > focusY ? 5 : 1.6)))
        if wanted < distance - 0.8 { narrowerFor += step } else { narrowerFor = 0 }
        if narrowerFor > 0.65 { narrowing = true }
        if wanted > distance + 0.3 || abs(wanted - distance) < 0.08 { narrowing = false }
        if wanted > distance + 0.3 || narrowing {
            distance += (wanted - distance) * (1 - kexp(-step * (wanted > distance ? 3.2 : 1.25)))
        }
        TripleShotWorldMath.perspective(out: &projection, fov: spec.fovY, aspect: aspect)
        TripleShotWorldMath.lookAt(
            out: &view,
            eye: CourtPoint(
                x: focusX - distance * TripleShotWorldMath.RIGHT_Z,
                y: focusY + distance * spec.elevation,
                z: focusZ + distance * TripleShotWorldMath.RIGHT_X
            ),
            target: CourtPoint(x: focusX, y: focusY, z: focusZ)
        )
        TripleShotWorldMath.multiply(out: &viewProjection, a: projection, b: view)
    }
}
