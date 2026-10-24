import Foundation

// Port of view/TripleShotCourtMeshBuilder.kt (TripleShotGame dd722e5), statement by statement.
// Spec 06 sections 3.3, 4.9 and 7; vertex counts and bit-exact checksums in Tests/TripleShotTests/WorldMathTests.swift.
// Interleaved triangles, 8 floats per vertex: x, y, z, u, v, nx, ny, nz (stride 32 bytes). The Kotlin direct
// native-order FloatBuffer becomes a Swift `[Float]` (same values, same order). Float arithmetic follows the Kotlin
// types and order: `tube`/`ring`/net angles are Double (`i*2*PI/sides`, `Float * Double` is a Double operation, then
// `.toFloat()`), the leaf and furniture trigonometry is kotlin.math on Float (computed in Double, ksin/kcos).
// Kotlin `List<Float>.distinct()` compares with Float.equals (floatToIntBits), reproduced by `distinctFloats`.

final class TripleShotMesh {
    /// Kotlin `val vertices: FloatBuffer` (contents writable, like the renderer's reusable quad buffer).
    var vertices: [Float]
    let count: Int

    init(vertices: [Float], count: Int) {
        self.vertices = vertices
        self.count = count
    }
}

/** Static triangles with xyz / uv / normal. Built on scene change, never in the frame loop. */
final class TripleShotCourtMeshBuilder {
    private var data: [Float] = []

    private func vertex(p: CourtPoint, u: Float, v: Float, n: CourtPoint) {
        data.append(p.x); data.append(p.y); data.append(p.z); data.append(u); data.append(v)
        data.append(n.x); data.append(n.y); data.append(n.z)
    }

    @discardableResult
    func quad(a: CourtPoint, b: CourtPoint, c: CourtPoint, d: CourtPoint, n: CourtPoint,
              u0: Float = 0, v0: Float = 0, u1: Float = 1, v1: Float = 1) -> TripleShotCourtMeshBuilder {
        vertex(p: a, u: u0, v: v0, n: n); vertex(p: b, u: u0, v: v1, n: n); vertex(p: c, u: u1, v: v1, n: n)
        vertex(p: a, u: u0, v: v0, n: n); vertex(p: c, u: u1, v: v1, n: n); vertex(p: d, u: u1, v: v0, n: n)
        return self
    }

    @discardableResult
    func box(x: Float, y: Float, z: Float, w: Float, h: Float, d: Float) -> TripleShotCourtMeshBuilder {
        let l = x - w / 2; let r = x + w / 2; let b = y - h / 2; let t = y + h / 2; let f = z + d / 2; let k = z - d / 2
        quad(a: CourtPoint(x: l, y: t, z: f), b: CourtPoint(x: l, y: b, z: f), c: CourtPoint(x: r, y: b, z: f),
             d: CourtPoint(x: r, y: t, z: f), n: CourtPoint(x: 0, y: 0, z: 1))
        quad(a: CourtPoint(x: r, y: t, z: k), b: CourtPoint(x: r, y: b, z: k), c: CourtPoint(x: l, y: b, z: k),
             d: CourtPoint(x: l, y: t, z: k), n: CourtPoint(x: 0, y: 0, z: -1))
        quad(a: CourtPoint(x: l, y: t, z: k), b: CourtPoint(x: l, y: b, z: k), c: CourtPoint(x: l, y: b, z: f),
             d: CourtPoint(x: l, y: t, z: f), n: CourtPoint(x: -1, y: 0, z: 0))
        quad(a: CourtPoint(x: r, y: t, z: f), b: CourtPoint(x: r, y: b, z: f), c: CourtPoint(x: r, y: b, z: k),
             d: CourtPoint(x: r, y: t, z: k), n: CourtPoint(x: 1, y: 0, z: 0))
        quad(a: CourtPoint(x: l, y: t, z: k), b: CourtPoint(x: l, y: t, z: f), c: CourtPoint(x: r, y: t, z: f),
             d: CourtPoint(x: r, y: t, z: k), n: CourtPoint(x: 0, y: 1, z: 0))
        return self
    }

    @discardableResult
    func tube(a: CourtPoint, b: CourtPoint, r: Float, sides: Int = 6) -> TripleShotCourtMeshBuilder {
        let dx = b.x - a.x; let dy = b.y - a.y; let dz = b.z - a.z
        let length = ksqrt(dx * dx + dy * dy + dz * dz).coerceAtLeast(0.001)
        let ax = dx / length; let ay = dy / length; let az = dz / length
        let ref = abs(ay) > 0.9 ? CourtPoint(x: 1, y: 0, z: 0) : CourtPoint(x: 0, y: 1, z: 0)
        let ux = ay * ref.z - az * ref.y; let uy = az * ref.x - ax * ref.z; let uz = ax * ref.y - ay * ref.x
        let ul = ksqrt(ux * ux + uy * uy + uz * uz)
        let u = CourtPoint(x: ux / ul, y: uy / ul, z: uz / ul)
        let v = CourtPoint(x: ay * u.z - az * u.y, y: az * u.x - ax * u.z, z: ax * u.y - ay * u.x)
        // Kotlin `u.x*cos(t)+v.x*sin(t)`: Float times Double is a Double operation; `.toFloat()` rounds once.
        func along(_ uc: Float, _ vc: Float, _ t: Double) -> Float {
            let sum: Double = Double(uc) * cos(t) + Double(vc) * sin(t)
            return sum.toFloat()
        }
        func offset(p: CourtPoint, t: Double) -> CourtPoint {
            return CourtPoint(x: p.x + r * along(u.x, v.x, t), y: p.y + r * along(u.y, v.y, t), z: p.z + r * along(u.z, v.z, t))
        }
        for i in kuntil(0, sides) {
            let t: Double = Double(i * 2) * Double.pi / Double(sides); let next: Double = Double((i + 1) * 2) * Double.pi / Double(sides)
            let normal = CourtPoint(x: along(u.x, v.x, t), y: along(u.y, v.y, t), z: along(u.z, v.z, t))
            quad(a: offset(p: a, t: t), b: offset(p: b, t: t), c: offset(p: b, t: next), d: offset(p: a, t: next), n: normal)
        }
        return self
    }

    @discardableResult
    func ring(x: Float, y: Float, z: Float, radius: Float, wire: Float, segments: Int = 48) -> TripleShotCourtMeshBuilder {
        for i in kuntil(0, segments) {
            let a: Double = Double(i * 2) * Double.pi / Double(segments); let b: Double = Double((i + 1) * 2) * Double.pi / Double(segments)
            tube(a: CourtPoint(x: x + cos(a).toFloat() * radius, y: y, z: z + sin(a).toFloat() * radius),
                 b: CourtPoint(x: x + cos(b).toFloat() * radius, y: y, z: z + sin(b).toFloat() * radius), r: wire)
        }
        return self
    }

    /** Curved tapered leaves: solid geometry, no generated replacement artwork. */
    @discardableResult
    func leaf(x: Float, y: Float, z: Float, angle: Float, length: Float, rise: Float, width: Float) -> TripleShotCourtMeshBuilder {
        let dx = kcos(angle); let dz = ksin(angle)
        func edge(t: Float, side: Float) -> CourtPoint {
            let spread: Float = ksin(PI_F * t) * width * side
            return CourtPoint(x: x + dx * length * t - dz * spread, y: y + rise * ksin(t * PI_F * 0.72), z: z + dz * length * t + dx * spread)
        }
        for i in kuntil(0, 7) {
            let a: Float = i.toFloat() / 7; let b: Float = (i + 1).toFloat() / 7
            quad(a: edge(t: a, side: -1), b: edge(t: b, side: -1), c: edge(t: b, side: 1), d: edge(t: a, side: 1),
                 n: CourtPoint(x: -dx * 0.35, y: 1, z: -dz * 0.35))
        }
        return self
    }

    func build() -> TripleShotMesh {
        return TripleShotMesh(vertices: data, count: data.count / 8)
    }

    static func floor(centerX: Float = 0, back: Float = -11) -> TripleShotMesh {
        return TripleShotCourtMeshBuilder().quad(
            a: CourtPoint(x: centerX - 8, y: 0, z: back), b: CourtPoint(x: centerX - 8, y: 0, z: 12),
            c: CourtPoint(x: centerX + 8, y: 0, z: 12), d: CourtPoint(x: centerX + 8, y: 0, z: back),
            n: CourtPoint(x: 0, y: 1, z: 0)).build()
    }

    static func ground() -> TripleShotMesh {
        return TripleShotCourtMeshBuilder().quad(
            a: CourtPoint(x: -90, y: -0.09, z: -90), b: CourtPoint(x: -90, y: -0.09, z: 70),
            c: CourtPoint(x: 90, y: -0.09, z: 70), d: CourtPoint(x: 90, y: -0.09, z: -90),
            n: CourtPoint(x: 0, y: 1, z: 0)).build()
    }
}

/** Court furniture supplies inexpensive parallax and scale cues around the owner's scenery. */
final class TripleShotCourtSurround {
    var lights: [CourtPoint] = []
    let deck: TripleShotMesh
    let metal: TripleShotMesh
    let cyan: TripleShotMesh
    let pink: TripleShotMesh
    let foliage: TripleShotMesh

    init(centerX: Float, back: Float) {
        var lights: [CourtPoint] = []
        let stone = TripleShotCourtMeshBuilder(); let steel = TripleShotCourtMeshBuilder()
        let blue = TripleShotCourtMeshBuilder(); let rose = TripleShotCourtMeshBuilder(); let green = TripleShotCourtMeshBuilder()
        stone.box(x: centerX, y: -0.14, z: (back + 12) * 0.5, w: 19, h: 0.25, d: 12 - back + 2)
        for side: Float in [-1, 1] {
            let edge = centerX + side * 8.13; let glow = side < 0 ? blue : rose
            steel.box(x: edge, y: 0.06, z: (back + 12) * 0.5, w: 0.17, h: 0.12, d: 12 - back)
            glow.box(x: edge - side * 0.025, y: 0.13, z: (back + 12) * 0.5, w: 0.09, h: 0.035, d: 12 - back)
            for z in TripleShotCourtSurround.distinctFloats([back + 1, back + 5.5, back + 10, 11]) {
                let x = centerX + side * 9.1
                stone.box(x: x, y: 0.29, z: z, w: 1.0, h: 0.58, d: 1.7)
                steel.box(x: x, y: 0.60, z: z, w: 1.06, h: 0.07, d: 1.76)
                for i in kuntil(0, 14) {
                    let angle: Float = i.toFloat() * 2.39996
                    let leafZ: Float = z + ksin(i.toFloat() * 3) * 0.38
                    let leafLength: Float = 0.42 + 0.22 * ksin(i.toFloat() * 2)
                    let leafRise: Float = 0.46 + 0.38 * (0.5 + 0.5 * kcos(i.toFloat() * 3))
                    green.leaf(x: x, y: 0.64, z: leafZ, angle: angle, length: leafLength, rise: leafRise, width: 0.12)
                }
                steel.tube(a: CourtPoint(x: x, y: 0.55, z: z), b: CourtPoint(x: x, y: 5.1, z: z), r: 0.055, sides: 8)
                steel.box(x: x - side * 0.20, y: 5.0, z: z, w: 0.62, h: 0.20, d: 0.45)
                glow.box(x: x - side * 0.20, y: 4.88, z: z, w: 0.48, h: 0.035, d: 0.32)
                lights.append(CourtPoint(x: x - side * 0.20, y: 4.85, z: z))
                glow.box(x: x - side * 0.54, y: 0.25, z: z, w: 0.025, h: 0.20, d: 1.5)
            }
            // Low sideline seating and a warm timber slat finish.
            let x = centerX + side * 8.8
            for z in [back + 3, back + 8] {
                steel.box(x: x, y: 0.30, z: z, w: 0.6, h: 0.58, d: 0.10).box(x: x, y: 0.30, z: z + 1.4, w: 0.6, h: 0.58, d: 0.10)
                stone.box(x: x, y: 0.60, z: z + 0.7, w: 0.7, h: 0.09, d: 1.8)
            }
        }
        steel.box(x: centerX, y: 0.15, z: back - 0.35, w: 17, h: 0.30, d: 0.30)
        blue.box(x: centerX, y: 0.31, z: back - 0.33, w: 17, h: 0.035, d: 0.08)
        self.lights = lights
        deck = stone.build(); metal = steel.build(); cyan = blue.build(); pink = rose.build(); foliage = green.build()
    }

    /// Kotlin `List<Float>.distinct()`: first occurrences, compared with Float.equals (floatToIntBits).
    private static func distinctFloats(_ values: [Float]) -> [Float] {
        var seen = Set<Int32>()
        var result: [Float] = []
        for value in values where seen.insert(value.toBits()).inserted { result.append(value) }
        return result
    }
}

final class TripleShotBasketMeshes {
    let structure: TripleShotMesh
    let trim: TripleShotMesh
    let rims: TripleShotMesh
    let nets: TripleShotMesh
    let glass: TripleShotMesh

    init(hoops: [CourtPoint]) {
        let steel = TripleShotCourtMeshBuilder(); let white = TripleShotCourtMeshBuilder()
        let orange = TripleShotCourtMeshBuilder(); let rope = TripleShotCourtMeshBuilder(); let pane = TripleShotCourtMeshBuilder()
        for hoop in hoops {
            let x = hoop.x; let z = hoop.z; let side: Float = hoops.count > 1 && z > 0 ? 1 : -1
            let boardZ = z + side * 0.67; let poleZ = z + side * 1.65
            steel.box(x: x, y: 0.18, z: poleZ, w: 0.95, h: 0.36, d: 1.2)
                .tube(a: CourtPoint(x: x, y: 0.32, z: poleZ), b: CourtPoint(x: x, y: 3.7, z: poleZ), r: 0.13, sides: 12)
            steel.box(x: x, y: 0.97, z: poleZ, w: 0.32, h: 1.34, d: 0.34)
            white.box(x: x, y: 0.40, z: poleZ - side * 0.185, w: 0.34, h: 0.055, d: 0.025)
            orange.box(x: x, y: 1.22, z: poleZ - side * 0.185, w: 0.20, h: 0.22, d: 0.025)
            steel.tube(a: CourtPoint(x: x, y: 3.6, z: poleZ), b: CourtPoint(x: x, y: 3.75, z: boardZ), r: 0.10)
            white.box(x: x, y: 3.08, z: boardZ, w: 2.6, h: 0.08, d: 0.10).box(x: x, y: 4.56, z: boardZ, w: 2.6, h: 0.08, d: 0.10)
            white.box(x: x - 1.27, y: 3.82, z: boardZ, w: 0.07, h: 1.5, d: 0.10).box(x: x + 1.27, y: 3.82, z: boardZ, w: 0.07, h: 1.5, d: 0.10)
            let faceZ = boardZ - side * 0.06
            white.box(x: x, y: 3.37, z: faceZ, w: 0.86, h: 0.035, d: 0.025).box(x: x, y: 3.98, z: faceZ, w: 0.86, h: 0.035, d: 0.025)
            white.box(x: x - 0.41, y: 3.68, z: faceZ, w: 0.035, h: 0.64, d: 0.025).box(x: x + 0.41, y: 3.68, z: faceZ, w: 0.035, h: 0.64, d: 0.025)
            orange.ring(x: x, y: hoop.y, z: z, radius: 0.55, wire: 0.045).box(x: x, y: hoop.y, z: boardZ - side * 0.10, w: 0.20, h: 0.09, d: 0.25)
            pane.quad(a: CourtPoint(x: x - 1.24, y: 4.52, z: boardZ), b: CourtPoint(x: x - 1.24, y: 3.12, z: boardZ),
                      c: CourtPoint(x: x + 1.24, y: 3.12, z: boardZ), d: CourtPoint(x: x + 1.24, y: 4.52, z: boardZ),
                      n: CourtPoint(x: 0, y: 0, z: 1))
            for row in kuntil(0, 5) {
                let y0: Float = hoop.y - row.toFloat() * 0.15; let y1: Float = y0 - 0.15
                let r0: Float = 0.52 - row.toFloat() * 0.045; let r1: Float = r0 - 0.045
                for i in kuntil(0, 12) {
                    let a: Double = (Double(i) + Double(row % 2) * 0.5) * 2 * Double.pi / 12
                    for sign in [-1, 1] {
                        let b: Double = a + Double(sign) * Double.pi / 12
                        rope.tube(a: CourtPoint(x: x + cos(a).toFloat() * r0, y: y0, z: z + sin(a).toFloat() * r0),
                                  b: CourtPoint(x: x + cos(b).toFloat() * r1, y: y1, z: z + sin(b).toFloat() * r1), r: 0.009, sides: 4)
                    }
                }
            }
            rope.ring(x: x, y: hoop.y - 0.75, z: z, radius: 0.295, wire: 0.012, segments: 32)
        }
        structure = steel.build(); trim = white.build(); rims = orange.build(); nets = rope.build(); glass = pane.build()
    }
}
