import CoreGraphics
import Foundation

/// Android `Matrix.setPolyToPoly(src, 0, dst, 0, 4)`: the perspective map of a unit square onto a
/// screen quadrilateral, and `Matrix.invert`. Core Graphics transforms are affine only, so the
/// arena maps every point of a wall or a target plane through this instead of concatenating it.
struct PlanarMap: Equatable {
    // x' = (a u + b v + c) / (g u + h v + i), y' = (d u + e v + f) / (g u + h v + i)
    let a: Double
    let b: Double
    let c: Double
    let d: Double
    let e: Double
    let f: Double
    let g: Double
    let h: Double
    let i: Double

    /// The square corners (0, 0), (1, 0), (1, 1) and (0, 1) land on `p0`, `p1`, `p2` and `p3`
    /// (Heckbert's square-to-quadrilateral mapping). Four point pairs fix a perspective map, so
    /// this is the same map Android builds from the same corners.
    static func square(_ p0: CGPoint, _ p1: CGPoint, _ p2: CGPoint, _ p3: CGPoint) -> PlanarMap {
        let x0 = Double(p0.x), y0 = Double(p0.y), x1 = Double(p1.x), y1 = Double(p1.y)
        let x2 = Double(p2.x), y2 = Double(p2.y), x3 = Double(p3.x), y3 = Double(p3.y)
        let sx = x0 - x1 + x2 - x3
        let sy = y0 - y1 + y2 - y3
        if sx == 0 && sy == 0 {
            return PlanarMap(a: x1 - x0, b: x3 - x0, c: x0, d: y1 - y0, e: y3 - y0, f: y0, g: 0, h: 0, i: 1)
        }
        let dx1 = x1 - x2, dx2 = x3 - x2, dy1 = y1 - y2, dy2 = y3 - y2
        let det = dx1 * dy2 - dx2 * dy1
        let g = det == 0 ? 0 : (sx * dy2 - dx2 * sy) / det
        let h = det == 0 ? 0 : (dx1 * sy - sx * dy1) / det
        return PlanarMap(a: x1 - x0 + g * x1, b: x3 - x0 + h * x3, c: x0, d: y1 - y0 + g * y1, e: y3 - y0 + h * y3, f: y0,
                         g: g, h: h, i: 1)
    }

    func map(_ u: Double, _ v: Double) -> CGPoint {
        let w = g * u + h * v + i
        return CGPoint(x: (a * u + b * v + c) / w, y: (d * u + e * v + f) / w)
    }

    /// Android `Matrix.invert`: nil (Android `false`) for a degenerate quadrilateral.
    func inverted() -> PlanarMap? {
        let ca = e * i - f * h
        let cb = -(d * i - f * g)
        let cc = d * h - e * g
        let det = a * ca + b * cb + c * cc
        if !det.isFinite || abs(det) < 1e-11 { return nil }
        let cd = -(b * i - c * h)
        let ce = a * i - c * g
        let cf = -(a * h - b * g)
        let cg = b * f - c * e
        let ch = -(a * f - c * d)
        let ci = a * e - b * d
        return PlanarMap(a: ca / det, b: cd / det, c: cg / det, d: cb / det, e: ce / det, f: ch / det, g: cc / det, h: cf / det, i: ci / det)
    }
}
