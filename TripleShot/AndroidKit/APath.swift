import CoreGraphics
import Foundation

// android.graphics.Path = Skia SkPath (VIEW-API "Graphics"), recorded like SkPath: verbs, Float points and conic
// weights, with SkPath's rules (implicit moveTo after close or on an empty path, close never doubled, Android's
// reset keeping the fill type, the oval / round-rect / arc constructions as conics with Skia's start points,
// SkRRect radius scaling, arcTo without the 360 modulo, addPath's lastMoveTo bookkeeping). So computeBounds (all
// points, conic control points included) and every point is what Android produces for the same calls.
// Conics (weight != 1) have no Core Graphics equivalent: `cgPath` turns each into cubics after halving it until
// every piece spans less than ~46 degrees (radial error < 1e-5 of the radius).

final class APath {
    enum Direction { case CW, CCW }
    enum FillType { case WINDING, EVEN_ODD }

    /// SkPath verbs.
    enum KGVerb { case move, line, quad, conic, cubic, close }

    private(set) var kgVerbs: [KGVerb] = []
    /// x, y pairs (SkPathRef points).
    private(set) var kgPoints: [Float] = []
    /// One weight per conic verb.
    private(set) var kgWeights: [Float] = []
    /// SkPath fLastMoveToIndex: point index of the last moveTo, ~index after a close (~0 = none yet).
    private var lastMoveToIndex: Int = ~0
    private var cachedPath: CGPath?

    var fillType: FillType = .WINDING

    init() {}

    /// `new Path(src)`.
    init(_ src: APath?) {
        if let s = src { copyFrom(s) }
    }

    private func copyFrom(_ src: APath) {
        kgVerbs = src.kgVerbs
        kgPoints = src.kgPoints
        kgWeights = src.kgWeights
        lastMoveToIndex = src.lastMoveToIndex
        fillType = src.fillType
        cachedPath = src.cachedPath
    }

    private func changed() { cachedPath = nil }

    /// `reset()`: empties the path; Android keeps the fill type (Path.java preserves it around nReset).
    func reset() {
        let keep = fillType
        rewind()
        fillType = keep
    }

    /// `rewind()`: empties the path (SkPath::rewind resets the fill type to WINDING).
    func rewind() {
        kgVerbs.removeAll(keepingCapacity: true)
        kgPoints.removeAll(keepingCapacity: true)
        kgWeights.removeAll(keepingCapacity: true)
        lastMoveToIndex = ~0
        fillType = .WINDING
        changed()
    }

    /// `set(src)`.
    func set(_ src: APath) {
        if src === self { return }
        copyFrom(src)
    }

    func getFillType() -> FillType { return fillType }
    func setFillType(_ ft: FillType) { fillType = ft }

    /// `isEmpty()`: no verbs at all (a lone moveTo is not empty, like Skia).
    var isEmpty: Bool { return kgVerbs.isEmpty }

    func incReserve(_ extraPtCount: Int) {
        kgPoints.reserveCapacity(kgPoints.count + 2 * max(0, extraPtCount))
    }

    var kgPointCount: Int { return kgPoints.count / 2 }

    /// SkPath::getLastPt: false and (0, 0) when there are no points.
    private func lastPt() -> (x: Float, y: Float, has: Bool) {
        if kgPoints.isEmpty { return (0, 0, false) }
        return (kgPoints[kgPoints.count - 2], kgPoints[kgPoints.count - 1], true)
    }

    private func injectMoveToIfNeeded() {
        if lastMoveToIndex < 0 {
            var x: Float = 0, y: Float = 0
            if !kgVerbs.isEmpty {
                let i = ~lastMoveToIndex
                x = kgPoints[2 * i]
                y = kgPoints[2 * i + 1]
            }
            moveTo(x, y)
        }
    }

    // MARK: Contours

    func moveTo(_ x: Float, _ y: Float) {
        // remember our index
        lastMoveToIndex = kgPointCount
        kgVerbs.append(.move)
        kgPoints.append(x); kgPoints.append(y)
        changed()
    }

    func rMoveTo(_ dx: Float, _ dy: Float) {
        let p = lastPt()
        moveTo(p.x + dx, p.y + dy)
    }

    func lineTo(_ x: Float, _ y: Float) {
        injectMoveToIfNeeded()
        kgVerbs.append(.line)
        kgPoints.append(x); kgPoints.append(y)
        changed()
    }

    func rLineTo(_ dx: Float, _ dy: Float) {
        injectMoveToIfNeeded() // This can change the result of getLastPt().
        let p = lastPt()
        lineTo(p.x + dx, p.y + dy)
    }

    func quadTo(_ x1: Float, _ y1: Float, _ x2: Float, _ y2: Float) {
        injectMoveToIfNeeded()
        kgVerbs.append(.quad)
        kgPoints.append(contentsOf: [x1, y1, x2, y2])
        changed()
    }

    func rQuadTo(_ dx1: Float, _ dy1: Float, _ dx2: Float, _ dy2: Float) {
        injectMoveToIfNeeded()
        let p = lastPt()
        quadTo(p.x + dx1, p.y + dy1, p.x + dx2, p.y + dy2)
    }

    /// SkPath::conicTo (internal: android.graphics.Path has no public conicTo).
    func conicTo(_ x1: Float, _ y1: Float, _ x2: Float, _ y2: Float, _ w: Float) {
        // check for <= 0 or NaN with this test
        if !(w > 0) {
            lineTo(x2, y2)
        } else if !w.isFinite {
            lineTo(x1, y1)
            lineTo(x2, y2)
        } else if w == 1 {
            quadTo(x1, y1, x2, y2)
        } else {
            injectMoveToIfNeeded()
            kgVerbs.append(.conic)
            kgPoints.append(contentsOf: [x1, y1, x2, y2])
            kgWeights.append(w)
            changed()
        }
    }

    func cubicTo(_ x1: Float, _ y1: Float, _ x2: Float, _ y2: Float, _ x3: Float, _ y3: Float) {
        injectMoveToIfNeeded()
        kgVerbs.append(.cubic)
        kgPoints.append(contentsOf: [x1, y1, x2, y2, x3, y3])
        changed()
    }

    func rCubicTo(_ x1: Float, _ y1: Float, _ x2: Float, _ y2: Float, _ x3: Float, _ y3: Float) {
        injectMoveToIfNeeded()
        let p = lastPt()
        cubicTo(p.x + x1, p.y + y1, p.x + x2, p.y + y2, p.x + x3, p.y + y3)
    }

    func close() {
        if let last = kgVerbs.last {
            switch last {
            case .line, .quad, .conic, .cubic, .move:
                kgVerbs.append(.close)
                changed()
            case .close:
                // don't add a close if it's the first verb or a repeat
                break
            }
        }
        // signal that we need a moveTo to follow us (unless we're done)
        if lastMoveToIndex >= 0 {
            lastMoveToIndex = ~lastMoveToIndex
        }
    }

    /// `setLastPoint(dx, dy)` (SkPath::setLastPt): replaces the last point, a moveTo when there is none.
    func setLastPoint(_ dx: Float, _ dy: Float) {
        if kgPoints.isEmpty {
            moveTo(dx, dy)
        } else {
            kgPoints[kgPoints.count - 2] = dx
            kgPoints[kgPoints.count - 1] = dy
            changed()
        }
    }

    // MARK: Arcs (SkPath::arcTo)

    func arcTo(_ oval: ARectF, _ startAngle: Float, _ sweepAngle: Float, _ forceMoveTo: Bool) {
        arcTo(oval.left, oval.top, oval.right, oval.bottom, startAngle, sweepAngle, forceMoveTo)
    }

    func arcTo(_ oval: ARectF, _ startAngle: Float, _ sweepAngle: Float) {
        arcTo(oval.left, oval.top, oval.right, oval.bottom, startAngle, sweepAngle, false)
    }

    /// `arcTo(left, top, right, bottom, startAngle, sweepAngle, forceMoveTo)`: degrees, 0 = 3 o'clock, positive =
    /// clockwise on screen. Conics per quadrant built like SkConic::BuildUnitArc.
    func arcTo(_ left: Float, _ top: Float, _ right: Float, _ bottom: Float,
               _ startAngle: Float, _ sweepAngle: Float, _ forceMoveTo: Bool) {
        let ovalW = right - left, ovalH = bottom - top
        if ovalW < 0 || ovalH < 0 { return }
        var forceMoveTo = forceMoveTo
        if kgVerbs.isEmpty { forceMoveTo = true }

        // arc_is_lone_point
        if sweepAngle == 0 && (startAngle == 0 || startAngle == 360) {
            // Chrome uses this path to move into and out of ovals.
            let ptX = right, ptY = KGPathMath.centerOf(top, bottom)
            if forceMoveTo { moveTo(ptX, ptY) } else { lineTo(ptX, ptY) }
            return
        } else if ovalW == 0 && ovalH == 0 {
            if forceMoveTo { moveTo(right, top) } else { lineTo(right, top) }
            return
        }

        // angles_to_unit_vectors
        let startRad = KitGraphics.degreesToRadians(startAngle)
        var stopRad = KitGraphics.degreesToRadians(startAngle + sweepAngle)
        let startVy = KitGraphics.sinSnapToZero(startRad), startVx = KitGraphics.cosSnapToZero(startRad)
        var stopVy = KitGraphics.sinSnapToZero(stopRad), stopVx = KitGraphics.cosSnapToZero(stopRad)
        // If the sweep angle is nearly (but less than) 360, precision loss may make the vectors coincide.
        if startVx == stopVx && startVy == stopVy {
            let sw = abs(sweepAngle)
            if sw < 360 && sw > 359 {
                // make a guess at a tiny angle (in radians) to tweak by
                let deltaRad: Float = sweepAngle < 0 ? -(Float(1) / 512) : Float(1) / 512
                // not sure how much will be enough, so we use a loop
                repeat {
                    stopRad -= deltaRad
                    stopVy = KitGraphics.sinSnapToZero(stopRad)
                    stopVx = KitGraphics.cosSnapToZero(stopRad)
                } while startVx == stopVx && startVy == stopVy
            }
        }
        let cw = sweepAngle > 0

        // Adds a move-to to 'pt' if forceMoveTo is true. Otherwise a lineTo unless we're sufficiently close to
        // 'pt' currently. This prevents spurious lineTos when adding a series of contiguous arcs from the same oval.
        func addPt(_ x: Float, _ y: Float) {
            if forceMoveTo {
                moveTo(x, y)
            } else {
                let last = lastPt()
                if !last.has || !KGPathMath.nearlyEqual(last.x, x) || !KGPathMath.nearlyEqual(last.y, y) {
                    lineTo(x, y)
                }
            }
        }

        // The sweepAngle is too small for angles_to_unit_vectors: a single point at the end angle.
        if startVx == stopVx && startVy == stopVy {
            let endAngle = KitGraphics.degreesToRadians(startAngle + sweepAngle)
            let radiusX = ovalW / 2
            let radiusY = ovalH / 2
            addPt(KGPathMath.centerOf(left, right) + radiusX * cosf(endAngle),
                  KGPathMath.centerOf(top, bottom) + radiusY * sinf(endAngle))
            return
        }

        // build_arc_conics
        let matrix = AMatrix()
        matrix.setScale(ovalW * 0.5, ovalH * 0.5)
        matrix.postTranslate(KGPathMath.centerOf(left, right), KGPathMath.centerOf(top, bottom))
        let conics = KGPathMath.buildUnitArc(startVx, startVy, stopVx, stopVy, cw, matrix)
        if conics.isEmpty {
            var p: [Float] = [stopVx, stopVy]
            matrix.mapPoints(&p)
            addPt(p[0], p[1])
            return
        }
        incReserve(conics.count * 2 + 1)
        addPt(conics[0].pts[0], conics[0].pts[1])
        for c in conics {
            conicTo(c.pts[2], c.pts[3], c.pts[4], c.pts[5], c.w)
        }
    }

    /// `addArc(oval, startAngle, sweepAngle)`: a new contour (an oval when the sweep is a full circle starting at
    /// a multiple of 90 degrees).
    func addArc(_ oval: ARectF, _ startAngle: Float, _ sweepAngle: Float) {
        addArc(oval.left, oval.top, oval.right, oval.bottom, startAngle, sweepAngle)
    }

    func addArc(_ left: Float, _ top: Float, _ right: Float, _ bottom: Float, _ startAngle: Float, _ sweepAngle: Float) {
        // SkRect::isEmpty: !(left < right && top < bottom)
        if !(left < right && top < bottom) || sweepAngle == 0 { return }
        let kFullCircleAngle: Float = 360
        if sweepAngle >= kFullCircleAngle || sweepAngle <= -kFullCircleAngle {
            // We can treat the arc as an oval if it begins at one of our legal starting positions.
            let startOver90 = startAngle / 90
            let startOver90I = (startOver90 + 0.5).rounded(.down)   // SkScalarRoundToScalar
            let error = startOver90 - startOver90I
            if KGPathMath.nearlyEqual(error, 0) {
                // Index 1 is at startAngle == 0.
                var startIndex = (startOver90I + 1).truncatingRemainder(dividingBy: 4)
                startIndex = startIndex < 0 ? startIndex + 4 : startIndex
                addOval(left, top, right, bottom, sweepAngle > 0 ? .CW : .CCW, Int(startIndex))
                return
            }
        }
        arcTo(left, top, right, bottom, startAngle, sweepAngle, true)
    }

    /// SkPath::arcTo(rx, ry, xAxisRotate, largeArc, sweep, x, y): the SVG endpoint arc (VectorDrawable 'A'/'a'),
    /// as conics. `sweepCW` is SkPathDirection::kCW. Android builds Skia with SK_LEGACY_PATH_ARCTO_ENDPOINT, so
    /// the last point is the computed one (not replaced by (x, y)).
    func kgSvgArcTo(_ rx: Float, _ ry: Float, _ angle: Float, _ largeArc: Bool, _ sweepCW: Bool, _ x: Float, _ y: Float) {
        injectMoveToIfNeeded()
        let src0 = lastPt()
        // If rx = 0 or ry = 0 then this arc is treated as a straight line segment joining the endpoints.
        if rx == 0 || ry == 0 {
            lineTo(x, y)
            return
        }
        // If the current point and target point are identical, it is a zero length path.
        if src0.x == x && src0.y == y {
            lineTo(x, y)
            return
        }
        var rx = abs(rx)
        var ry = abs(ry)
        let midX = (src0.x - x) * 0.5
        let midY = (src0.y - y) * 0.5

        let pointTransform = AMatrix()
        pointTransform.setRotate(-angle)
        var tm: [Float] = [midX, midY]
        pointTransform.mapPoints(&tm)
        let squareRx = rx * rx
        let squareRy = ry * ry
        let squareX = tm[0] * tm[0]
        let squareY = tm[1] * tm[1]

        // Check if the radii are big enough to draw the arc, scale radii if not.
        var radiiScale = squareX / squareRx + squareY / squareRy
        if radiiScale > 1 {
            radiiScale = sqrtf(radiiScale)
            rx *= radiiScale
            ry *= radiiScale
        }

        pointTransform.setScale(1 / rx, 1 / ry)
        pointTransform.preRotate(-angle)

        var unit: [Float] = [src0.x, src0.y, x, y]
        pointTransform.mapPoints(&unit)
        var deltaX = unit[2] - unit[0]
        var deltaY = unit[3] - unit[1]

        let d = deltaX * deltaX + deltaY * deltaY
        let scaleFactorSquared = max(1 / d - 0.25, 0)

        var scaleFactor = sqrtf(scaleFactorSquared)
        if (!sweepCW) != largeArc {   // flipped from the original implementation
            scaleFactor = -scaleFactor
        }
        deltaX *= scaleFactor
        deltaY *= scaleFactor
        var centerX = unit[0] + unit[2]
        var centerY = unit[1] + unit[3]
        centerX *= 0.5
        centerY *= 0.5
        centerX += -deltaY
        centerY += deltaX
        unit[0] -= centerX
        unit[1] -= centerY
        unit[2] -= centerX
        unit[3] -= centerY
        let theta1 = atan2f(unit[1], unit[0])
        let theta2 = atan2f(unit[3], unit[2])
        var thetaArc = theta2 - theta1
        if thetaArc < 0 && sweepCW {   // arcSweep flipped from the original implementation
            thetaArc += KitGraphics.skPI * 2
        } else if thetaArc > 0 && !sweepCW {
            thetaArc -= KitGraphics.skPI * 2
        }

        // Very tiny angles cause our subsequent math to go wonky (skbug.com/9272).
        if abs(thetaArc) < (KitGraphics.skPI / (1000 * 1000)) {
            lineTo(x, y)
            return
        }

        pointTransform.setRotate(angle)
        pointTransform.preScale(rx, ry)

        // the arc may be slightly bigger than 1/4 circle, so allow up to 1/3rd
        let segments = KGPathMath.ceilToInt(abs(thetaArc / (2 * KitGraphics.skPI / 3)))
        let thetaWidth = thetaArc / Float(segments)
        let t = tanf(0.5 * thetaWidth)
        if !t.isFinite { return }
        var startTheta = theta1
        let w = sqrtf(0.5 + cosf(thetaWidth) * 0.5)
        func isInteger(_ s: Float) -> Bool { return s == s.rounded(.down) }
        let expectIntegers = abs(KitGraphics.skPI / 2 - abs(thetaWidth)) <= KitGraphics.nearlyZero
            && isInteger(rx) && isInteger(ry) && isInteger(x) && isInteger(y)

        for _ in 0..<max(0, segments) {
            let endTheta = startTheta + thetaWidth
            let sinEndTheta = KitGraphics.sinSnapToZero(endTheta)
            let cosEndTheta = KitGraphics.cosSnapToZero(endTheta)
            var p1x = cosEndTheta, p1y = sinEndTheta
            p1x += centerX
            p1y += centerY
            var p0x = p1x, p0y = p1y
            p0x += t * sinEndTheta
            p0y += -t * cosEndTheta
            var mapped: [Float] = [p0x, p0y, p1x, p1y]
            pointTransform.mapPoints(&mapped)
            // If the input values are on integers, place the conic on integers as well.
            if expectIntegers {
                for i in 0..<4 { mapped[i] = (mapped[i] + 0.5).rounded(.down) }
            }
            conicTo(mapped[0], mapped[1], mapped[2], mapped[3], w)
            startTheta = endTheta
        }
    }

    // MARK: Shapes

    func addRect(_ rect: ARectF, _ dir: Direction) {
        addRect(rect.left, rect.top, rect.right, rect.bottom, dir)
    }

    /// `addRect(left, top, right, bottom, dir)` (not sorted, like SkPath::addRect).
    func addRect(_ left: Float, _ top: Float, _ right: Float, _ bottom: Float, _ dir: Direction) {
        addRect(left, top, right, bottom, dir, 0)
    }

    /// SkPath::addRect with a start index (0 = top-left, 1 = top-right, 2 = bottom-right, 3 = bottom-left).
    private func addRect(_ l: Float, _ t: Float, _ r: Float, _ b: Float, _ dir: Direction, _ startIndex: Int) {
        let corners: [(Float, Float)] = [(l, t), (r, t), (r, b), (l, b)]
        let advance = dir == .CW ? 1 : 3
        var i = startIndex % 4
        incReserve(5)
        moveTo(corners[i].0, corners[i].1)
        for _ in 0..<3 {
            i = (i + advance) % 4
            lineTo(corners[i].0, corners[i].1)
        }
        close()
    }

    func addOval(_ oval: ARectF, _ dir: Direction) {
        addOval(oval.left, oval.top, oval.right, oval.bottom, dir)
    }

    func addOval(_ left: Float, _ top: Float, _ right: Float, _ bottom: Float, _ dir: Direction) {
        addOval(left, top, right, bottom, dir, 1)
    }

    /// SkPath::addOval: four quarter conics (weight sqrt(2)/2); start index 0 = top, 1 = right (Android's
    /// default), 2 = bottom, 3 = left.
    private func addOval(_ l: Float, _ t: Float, _ r: Float, _ b: Float, _ dir: Direction, _ startPointIndex: Int) {
        let cx = KGPathMath.centerOf(l, r), cy = KGPathMath.centerOf(t, b)
        let ovalPts: [(Float, Float)] = [(cx, t), (r, cy), (cx, b), (l, cy)]
        let rectPts: [(Float, Float)] = [(l, t), (r, t), (r, b), (l, b)]
        let advance = dir == .CW ? 1 : 3
        var oi = startPointIndex % 4
        // The corner iterator pts are tracking "behind" the oval/radii pts.
        var ri = (startPointIndex + (dir == .CW ? 0 : 1)) % 4
        incReserve(9)
        moveTo(ovalPts[oi].0, ovalPts[oi].1)
        for _ in 0..<4 {
            ri = (ri + advance) % 4
            oi = (oi + advance) % 4
            conicTo(rectPts[ri].0, rectPts[ri].1, ovalPts[oi].0, ovalPts[oi].1, KGPathMath.root2Over2)
        }
        close()
    }

    /// `addCircle(x, y, radius, dir)`: nothing unless radius > 0.
    func addCircle(_ x: Float, _ y: Float, _ radius: Float, _ dir: Direction) {
        if radius > 0 {
            addOval(x - radius, y - radius, x + radius, y + radius, dir)
        }
    }

    func addRoundRect(_ rect: ARectF, _ rx: Float, _ ry: Float, _ dir: Direction) {
        addRoundRect(rect.left, rect.top, rect.right, rect.bottom, rx, ry, dir)
    }

    /// `addRoundRect(..., rx, ry, dir)` (SkRRect::setRectXY: radii scaled down together to fit).
    func addRoundRect(_ left: Float, _ top: Float, _ right: Float, _ bottom: Float, _ rx: Float, _ ry: Float, _ dir: Direction) {
        if rx < 0 || ry < 0 { return }
        addRRect(KGRRect(rectXY: left, top, right, bottom, rx, ry), dir)
    }

    func addRoundRect(_ rect: ARectF, _ radii: [Float], _ dir: Direction) {
        addRoundRect(rect.left, rect.top, rect.right, rect.bottom, radii, dir)
    }

    /// `addRoundRect(..., radii[8], dir)`: [top-left x, y, top-right x, y, bottom-right x, y, bottom-left x, y].
    func addRoundRect(_ left: Float, _ top: Float, _ right: Float, _ bottom: Float, _ radii: [Float], _ dir: Direction) {
        precondition(radii.count >= 8, "java.lang.ArrayIndexOutOfBoundsException: radii[] needs 8 values")
        addRRect(KGRRect(rectRadii: left, top, right, bottom, radii), dir)
    }

    /// SkPath::addRRect with Android's start indices (6 for CW, 7 for CCW).
    fileprivate func addRRect(_ rr: KGRRect, _ dir: Direction) {
        let startIndex = dir == .CW ? 6 : 7
        if rr.isRect || rr.isEmpty {
            // degenerate(rect) => radii points are collapsing
            addRect(rr.l, rr.t, rr.r, rr.b, dir, (startIndex + 1) / 2)
            return
        }
        if rr.isOval {
            // degenerate(oval) => line points are collapsing
            addOval(rr.l, rr.t, rr.r, rr.b, dir, startIndex / 2)
            return
        }
        let (l, t, r, b) = (rr.l, rr.t, rr.r, rr.b)
        // SkPath_RRectPointIterator
        let rrPts: [(Float, Float)] = [
            (l + rr.radii[0].0, t), (r - rr.radii[1].0, t),
            (r, t + rr.radii[1].1), (r, b - rr.radii[2].1),
            (r - rr.radii[2].0, b), (l + rr.radii[3].0, b),
            (l, b - rr.radii[3].1), (l, t + rr.radii[0].1),
        ]
        let rectPts: [(Float, Float)] = [(l, t), (r, t), (r, b), (l, b)]
        let cw = dir == .CW
        // we start with a conic on odd indices when moving CW vs. even indices when moving CCW
        let startsWithConic = ((startIndex & 1) == 1) == cw
        var pi = startIndex % 8
        var ri = (startIndex / 2 + (cw ? 0 : 1)) % 4
        func nextPoint() -> (Float, Float) {
            pi = (pi + (cw ? 1 : 7)) % 8
            return rrPts[pi]
        }
        func nextCorner() -> (Float, Float) {
            ri = (ri + (cw ? 1 : 3)) % 4
            return rectPts[ri]
        }
        let weight = KGPathMath.root2Over2
        incReserve(startsWithConic ? 12 : 13)
        moveTo(rrPts[pi].0, rrPts[pi].1)
        if startsWithConic {
            for _ in 0..<3 {
                let c = nextCorner(); let p = nextPoint()
                conicTo(c.0, c.1, p.0, p.1, weight)
                let q = nextPoint()
                lineTo(q.0, q.1)
            }
            let c = nextCorner(); let p = nextPoint()
            conicTo(c.0, c.1, p.0, p.1, weight)
            // final lineTo handled by close().
        } else {
            for _ in 0..<4 {
                let q = nextPoint()
                lineTo(q.0, q.1)
                let c = nextCorner(); let p = nextPoint()
                conicTo(c.0, c.1, p.0, p.1, weight)
            }
        }
        close()
    }

    // MARK: Paths

    /// `addPath(src)`.
    func addPath(_ src: APath) {
        addPath(src, AMatrix())
    }

    /// `addPath(src, dx, dy)`.
    func addPath(_ src: APath, _ dx: Float, _ dy: Float) {
        let m = AMatrix()
        m.setTranslate(dx, dy)
        addPath(src, m)
    }

    /// `addPath(src, matrix)` = SkPath::addPath(src, matrix, kAppend_AddPathMode), fLastMoveToIndex bookkeeping
    /// included (an appended closed contour leaves Skia's flipped index, as on Android).
    func addPath(_ src: APath, _ matrix: AMatrix) {
        if src.isEmpty { return }
        // Detect if we're trying to add ourself
        let s = src === self ? APath(src) : src
        lastMoveToIndex = kgPointCount + s.lastMoveToIndex
        var mapped = s.kgPoints
        matrix.mapPoints(&mapped)
        kgVerbs.append(contentsOf: s.kgVerbs)
        kgPoints.append(contentsOf: mapped)
        kgWeights.append(contentsOf: s.kgWeights)
        // fiddle with fLastMoveToIndex, as we do in SkPath::close()
        if kgVerbs.last == .close, lastMoveToIndex >= 0 {
            lastMoveToIndex = ~lastMoveToIndex
        }
        changed()
    }

    /// `offset(dx, dy)`: every point translated (SkPath::offset).
    func offset(_ dx: Float, _ dy: Float) {
        let m = AMatrix()
        m.setTranslate(dx, dy)
        transform(m)
    }

    /// `offset(dx, dy, dst)`: the offset path into `dst` (this path unchanged).
    func offset(_ dx: Float, _ dy: Float, _ dst: APath?) {
        guard let d = dst else { offset(dx, dy); return }
        d.set(self)
        d.offset(dx, dy)
    }

    /// `transform(matrix)`: every point mapped by the matrix (conic weights unchanged, affine maps).
    func transform(_ matrix: AMatrix) {
        if kgPoints.isEmpty || matrix.isIdentity() { return }
        var p = kgPoints
        matrix.mapPoints(&p)
        kgPoints = p
        changed()
    }

    /// `transform(matrix, dst)`.
    func transform(_ matrix: AMatrix, _ dst: APath?) {
        guard let d = dst else { transform(matrix); return }
        d.set(self)
        d.transform(matrix)
    }

    /// `computeBounds(bounds, exact)` = SkPath::getBounds: the bounds of all points (control points included);
    /// (0, 0, 0, 0) for no points or a non-finite point.
    func computeBounds(_ bounds: ARectF, _ exact: Bool) {
        if kgPoints.isEmpty {
            bounds.set(0, 0, 0, 0)
            return
        }
        var minX = kgPoints[0], minY = kgPoints[1], maxX = kgPoints[0], maxY = kgPoints[1]
        var i = 0
        while i < kgPoints.count {
            let x = kgPoints[i], y = kgPoints[i + 1]
            if !x.isFinite || !y.isFinite {
                bounds.set(0, 0, 0, 0)
                return
            }
            minX = min(minX, x); maxX = max(maxX, x)
            minY = min(minY, y); maxY = max(maxY, y)
            i += 2
        }
        bounds.set(minX, minY, maxX, maxY)
    }

    func computeBounds(_ bounds: ARectF) {
        computeBounds(bounds, true)
    }

    // MARK: Core Graphics

    /// The path for Core Graphics (px coordinates); conics become cubics. The fill type is applied by the
    /// drawing call (`cgFillRule`).
    var cgPath: CGPath {
        if let p = cachedPath { return p }
        let path = CGMutablePath()
        var i = 0
        var wi = 0
        var curX: Double = 0, curY: Double = 0
        func pt(_ k: Int) -> CGPoint { return CGPoint(x: CGFloat(kgPoints[k]), y: CGFloat(kgPoints[k + 1])) }
        for verb in kgVerbs {
            switch verb {
            case .move:
                path.move(to: pt(i))
                curX = Double(kgPoints[i]); curY = Double(kgPoints[i + 1])
                i += 2
            case .line:
                path.addLine(to: pt(i))
                curX = Double(kgPoints[i]); curY = Double(kgPoints[i + 1])
                i += 2
            case .quad:
                path.addQuadCurve(to: pt(i + 2), control: pt(i))
                curX = Double(kgPoints[i + 2]); curY = Double(kgPoints[i + 3])
                i += 4
            case .conic:
                KGPathMath.appendConic(path, curX, curY, Double(kgPoints[i]), Double(kgPoints[i + 1]),
                                       Double(kgPoints[i + 2]), Double(kgPoints[i + 3]), Double(kgWeights[wi]))
                curX = Double(kgPoints[i + 2]); curY = Double(kgPoints[i + 3])
                i += 4
                wi += 1
            case .cubic:
                path.addCurve(to: pt(i + 4), control1: pt(i), control2: pt(i + 2))
                curX = Double(kgPoints[i + 4]); curY = Double(kgPoints[i + 5])
                i += 6
            case .close:
                path.closeSubpath()
            }
        }
        cachedPath = path
        return path
    }

    /// The Core Graphics fill rule of `fillType`.
    var cgFillRule: CGPathFillRule {
        return fillType == .EVEN_ODD ? .evenOdd : .winding
    }
}

// MARK: - Skia geometry helpers

enum KGPathMath {
    /// SK_ScalarRoot2Over2.
    static let root2Over2: Float = 0.707106781

    /// SkRect::centerX/centerY: `a / 2 + b / 2` (SkScalarHalf(fLeft) + SkScalarHalf(fRight)).
    static func centerOf(_ a: Float, _ b: Float) -> Float {
        return a * 0.5 + b * 0.5
    }

    /// SkScalarNearlyEqual(x, y): |x - y| <= SK_ScalarNearlyZero.
    static func nearlyEqual(_ x: Float, _ y: Float) -> Bool {
        return abs(x - y) <= KitGraphics.nearlyZero
    }

    /// SkScalarCeilToInt = sk_float_saturate2int(ceilf(x)).
    static func ceilToInt(_ x: Float) -> Int {
        return saturate2int(x.rounded(.up))
    }

    /// sk_float_saturate2int.
    static func saturate2int(_ x: Float) -> Int {
        var v = x < 2147483520 ? x : 2147483520
        v = v > -2147483520 ? v : -2147483520
        return Int(v.rounded(.towardZero))
    }

    /// SkPoint::setLength(x, y, length) (set_point_length<false>): computed in double; (0, 0) when it fails.
    static func setLength(_ x: Float, _ y: Float, _ length: Float) -> (Float, Float) {
        let xx = Double(x), yy = Double(y)
        let dmag = (xx * xx + yy * yy).squareRoot()
        let dscale = Double(length) / dmag
        let rx = Float(Double(x) * dscale)
        let ry = Float(Double(y) * dscale)
        if !rx.isFinite || !ry.isFinite || (rx == 0 && ry == 0) {
            return (0, 0)
        }
        return (rx, ry)
    }

    /// SkConic::BuildUnitArc: the conics of the unit-circle arc from uStart to uStop (clockwise when `cw`),
    /// mapped by `userMatrix`. Each element: pts = [x0, y0, x1, y1, x2, y2], w = weight.
    static func buildUnitArc(_ uStartX: Float, _ uStartY: Float, _ uStopX: Float, _ uStopY: Float,
                             _ cw: Bool, _ userMatrix: AMatrix?) -> [(pts: [Float], w: Float)] {
        // rotate by x,y so that uStart is (1.0)
        let x = uStartX * uStopX + uStartY * uStopY
        var y = uStartX * uStopY - uStartY * uStopX
        let absY = abs(y)
        // check for (effectively) coincident vectors
        if absY <= KitGraphics.nearlyZero && x > 0 && ((y >= 0 && cw) || (y <= 0 && !cw)) {
            return []
        }
        if !cw {
            y = -y
        }
        // We decide to use 1-conic per quadrant of a circle. What quadrant does [xy] lie in?
        var quadrant = 0
        if y == 0 {
            quadrant = 2 // 180
        } else if x == 0 {
            quadrant = y > 0 ? 1 : 3 // 90 : 270
        } else {
            if y < 0 {
                quadrant += 2
            }
            if (x < 0) != (y < 0) {
                quadrant += 1
            }
        }
        let quadrantPts: [Float] = [1, 0, 1, 1, 0, 1, -1, 1, -1, 0, -1, -1, 0, -1, 1, -1]
        var dst: [(pts: [Float], w: Float)] = []
        for i in 0..<quadrant {
            dst.append((Array(quadrantPts[(i * 4)..<(i * 4 + 6)]), root2Over2))
        }
        // Now compute any remaining (sub-90-degree) arc for the last conic
        let lastQx = quadrantPts[quadrant * 4], lastQy = quadrantPts[quadrant * 4 + 1]
        let dot = lastQx * x + lastQy * y
        if dot < 1 {
            let cosThetaOver2 = sqrtf((1 + dot) / 2)
            let off = setLength(lastQx + x, lastQy + y, 1 / cosThetaOver2)
            // SkPointPriv::EqualsWithinTolerance(lastQ, offCurve): !CanNormalize(dx, dy)
            let dx = lastQx - off.0, dy = lastQy - off.1
            let equal = !(dx.isFinite && dy.isFinite && (dx != 0 || dy != 0))
            if !equal {
                dst.append(([lastQx, lastQy, off.0, off.1, x, y], cosThetaOver2))
            }
        }
        // now handle counter-clockwise and the initial unitStart rotation
        let matrix = AMatrix()
        matrix.setSinCos(uStartY, uStartX)
        if !cw {
            matrix.preScale(1, -1)
        }
        if let m = userMatrix {
            matrix.postConcat(m)
        }
        for i in 0..<dst.count {
            var p = dst[i].pts
            matrix.mapPoints(&p)
            dst[i].pts = p
        }
        return dst
    }

    /// Appends the conic (x0, y0) -(x1, y1, w)-> (x2, y2) as cubics: halved (SkConic::chop) until the weight is
    /// at least 0.92 (pieces under ~46 degrees), each piece a cubic with control points at 4/3 w / (1 + w) of
    /// the way to the conic's control point (exact tangents, radial error < 1e-5).
    static func appendConic(_ path: CGMutablePath, _ x0: Double, _ y0: Double, _ x1: Double, _ y1: Double,
                            _ x2: Double, _ y2: Double, _ w: Double) {
        if w < 0.92 && w > 0 {
            let scale = 1 / (1 + w)
            let newW = (0.5 + w * 0.5).squareRoot()
            let wx1 = w * x1, wy1 = w * y1
            let mx = (x0 + 2 * wx1 + x2) * scale * 0.5
            let my = (y0 + 2 * wy1 + y2) * scale * 0.5
            appendConic(path, x0, y0, (x0 + wx1) * scale, (y0 + wy1) * scale, mx, my, newW)
            appendConic(path, mx, my, (wx1 + x2) * scale, (wy1 + y2) * scale, x2, y2, newW)
            return
        }
        let k = 4.0 / 3.0 * w / (1 + w)
        path.addCurve(to: CGPoint(x: x2, y: y2),
                      control1: CGPoint(x: x0 + (x1 - x0) * k, y: y0 + (y1 - y0) * k),
                      control2: CGPoint(x: x2 + (x1 - x2) * k, y: y2 + (y1 - y2) * k))
    }
}

// MARK: - SkRRect

/// The SkRRect rules Android's round rects go through (setRectXY / setRectRadii, scaleRadii with flush_to_zero
/// and SkScaleToSides::AdjustRadii, computeType).
fileprivate struct KGRRect {
    var l: Float = 0, t: Float = 0, r: Float = 0, b: Float = 0
    /// (rx, ry) for top-left, top-right, bottom-right, bottom-left.
    var radii: [(Float, Float)] = [(0, 0), (0, 0), (0, 0), (0, 0)]
    var isEmpty = false
    var isRect = false
    var isOval = false

    /// SkRRect::initializeRect: false (and an empty rrect) for a non-finite or empty rect.
    private mutating func initializeRect(_ left: Float, _ top: Float, _ right: Float, _ bottom: Float) -> Bool {
        // Check this before sorting because sorting can hide nans.
        if !(left.isFinite && top.isFinite && right.isFinite && bottom.isFinite) {
            (l, t, r, b) = (0, 0, 0, 0)
            isEmpty = true
            return false
        }
        (l, t, r, b) = (min(left, right), min(top, bottom), max(left, right), max(top, bottom))
        if !(l < r && t < b) {
            isEmpty = true
            return false
        }
        return true
    }

    /// SkRRect::setRectXY.
    init(rectXY left: Float, _ top: Float, _ right: Float, _ bottom: Float, _ xRad: Float, _ yRad: Float) {
        if !initializeRect(left, top, right, bottom) { return }
        var xRad = xRad, yRad = yRad
        if !(xRad.isFinite && yRad.isFinite) {
            xRad = 0; yRad = 0 // devolve into a simple rect
        }
        let w = r - l, h = b - t
        if w < xRad + xRad || h < yRad + yRad {
            // At most one of these two divides will be by zero, and neither numerator is zero.
            let scale = min(w / (xRad + xRad), h / (yRad + yRad))
            xRad *= scale
            yRad *= scale
        }
        if xRad <= 0 || yRad <= 0 {
            // all corners are square in this case
            isRect = true
            return
        }
        radii = [(xRad, yRad), (xRad, yRad), (xRad, yRad), (xRad, yRad)]
        if xRad >= w * 0.5 && yRad >= h * 0.5 {
            isOval = true
        }
    }

    /// SkRRect::setRectRadii.
    init(rectRadii left: Float, _ top: Float, _ right: Float, _ bottom: Float, _ values: [Float]) {
        if !initializeRect(left, top, right, bottom) { return }
        if !values[0..<8].allSatisfy({ $0.isFinite }) {
            isRect = true // devolve into a simple rect
            return
        }
        var rx: [Float] = [values[0], values[2], values[4], values[6]]
        var ry: [Float] = [values[1], values[3], values[5], values[7]]
        if KGRRect.clampToZero(&rx, &ry) {
            isRect = true
            return
        }
        // scaleRadii: proportionally scale down all radii to fit (CSS 'Overlapping Curves').
        var scale = 1.0
        let width = Double(r) - Double(l)
        let height = Double(b) - Double(t)
        scale = KGRRect.computeMinScale(rx[0], rx[1], width, scale)
        scale = KGRRect.computeMinScale(ry[1], ry[2], height, scale)
        scale = KGRRect.computeMinScale(rx[2], rx[3], width, scale)
        scale = KGRRect.computeMinScale(ry[3], ry[0], height, scale)

        (rx[0], rx[1]) = KGRRect.flushToZero(rx[0], rx[1])
        (ry[1], ry[2]) = KGRRect.flushToZero(ry[1], ry[2])
        (rx[2], rx[3]) = KGRRect.flushToZero(rx[2], rx[3])
        (ry[3], ry[0]) = KGRRect.flushToZero(ry[3], ry[0])

        if scale < 1.0 {
            (rx[0], rx[1]) = KGRRect.adjustRadii(width, scale, rx[0], rx[1])
            (ry[1], ry[2]) = KGRRect.adjustRadii(height, scale, ry[1], ry[2])
            (rx[2], rx[3]) = KGRRect.adjustRadii(width, scale, rx[2], rx[3])
            (ry[3], ry[0]) = KGRRect.adjustRadii(height, scale, ry[3], ry[0])
        }
        // adjust radii may set x or y to zero; set companion to zero as well
        _ = KGRRect.clampToZero(&rx, &ry)
        radii = (0..<4).map { (rx[$0], ry[$0]) }
        // SkRRect::computeType
        var allRadiiEqual = true
        var allCornersSquare = rx[0] == 0 || ry[0] == 0
        for i in 1..<4 {
            if rx[i] != 0 && ry[i] != 0 {
                allCornersSquare = false
            }
            if rx[i] != rx[i - 1] || ry[i] != ry[i - 1] {
                allRadiiEqual = false
            }
        }
        if allCornersSquare {
            isRect = true
            return
        }
        if allRadiiEqual && rx[0] >= (r - l) * 0.5 && ry[0] >= (b - t) * 0.5 {
            isOval = true
        }
    }

    /// clamp_to_zero: a corner with a radius <= 0 is square; true when every corner is square.
    private static func clampToZero(_ rx: inout [Float], _ ry: inout [Float]) -> Bool {
        var allCornersSquare = true
        for i in 0..<4 {
            if rx[i] <= 0 || ry[i] <= 0 {
                rx[i] = 0
                ry[i] = 0
            } else {
                allCornersSquare = false
            }
        }
        return allCornersSquare
    }

    /// compute_min_scale.
    private static func computeMinScale(_ rad1: Float, _ rad2: Float, _ limit: Double, _ curMin: Double) -> Double {
        let sum = Double(rad1) + Double(rad2)
        if sum > limit {
            return min(curMin, limit / sum)
        }
        return curMin
    }

    /// flush_to_zero(a, b): returns the new (a, b).
    private static func flushToZero(_ a: Float, _ b: Float) -> (Float, Float) {
        if a + b == a {
            return (a, 0)
        } else if a + b == b {
            return (0, b)
        }
        return (a, b)
    }

    /// SkScaleToSides::AdjustRadii(limit, scale, &a, &b): returns the new (a, b).
    private static func adjustRadii(_ limit: Double, _ scale: Double, _ a0: Float, _ b0: Float) -> (Float, Float) {
        var a = Float(Double(a0) * scale)
        var b = Float(Double(b0) * scale)
        if Double(a + b) > limit {
            let aIsMin = !(a > b)
            let newMinRadius = aIsMin ? a : b
            var newMaxRadius = Float(limit - Double(newMinRadius))
            // Reduce newMaxRadius an ulp at a time until it fits.
            while Double(newMaxRadius + newMinRadius) > limit {
                newMaxRadius = newMaxRadius.nextDown
            }
            if aIsMin { b = newMaxRadius } else { a = newMaxRadius }
        }
        return (a, b)
    }
}

// MARK: - PathParser (VectorDrawable path data)

/// The framework VectorDrawable path parser (hwui PathParser::getPathDataFromAsciiString +
/// VectorDrawableUtils::verbsToPath): SVG path data M L H V C S Q T A Z and their relative forms; numbers end at a
/// space, a comma, a '-' (not after an exponent) or a second '.', parsed with strtof; arcs go through Skia's SVG
/// arcTo. Invalid data fails like Android's inflation (IllegalArgumentException).
enum APathParser {
    static func createPathFromPathData(_ pathData: String) -> APath {
        let path = APath()
        let parsed = parse(pathData)
        // VectorDrawableUtils::verbsToPath
        var resolver = Resolver()
        var previousCommand: UInt8 = UInt8(ascii: "m")
        var start = 0
        for i in 0..<parsed.verbs.count {
            let verbSize = parsed.sizes[i]
            resolver.addCommand(path, previousCommand, parsed.verbs[i], parsed.points, start, start + verbSize)
            previousCommand = parsed.verbs[i]
            start += verbSize
        }
        return path
    }

    private static func isLetter(_ c: UInt8) -> Bool {
        return (c >= 65 && c <= 90) || (c >= 97 && c <= 122)
    }

    private static func nextStart(_ s: [UInt8], _ startIndex: Int) -> Int {
        var index = startIndex
        while index < s.count {
            let c = s[index]
            // 'e' or 'E' are not valid path commands, but could be used for floating point numbers' notation.
            if isLetter(c) && c != UInt8(ascii: "e") && c != UInt8(ascii: "E") {
                return index
            }
            index += 1
        }
        return index
    }

    /// extract: the end of the current number and whether it ends with a '-' or '.' that starts the next one.
    private static func extract(_ s: [UInt8], _ start: Int, _ end: Int) -> (endPosition: Int, endWithNegOrDot: Bool) {
        var currentIndex = start
        var foundSeparator = false
        var endWithNegOrDot = false
        var secondDot = false
        var isExponential = false
        while currentIndex < end {
            let isPrevExponential = isExponential
            isExponential = false
            switch s[currentIndex] {
            case UInt8(ascii: " "), UInt8(ascii: ","):
                foundSeparator = true
            case UInt8(ascii: "-"):
                // The negative sign following a 'e' or 'E' is not a separator.
                if currentIndex != start && !isPrevExponential {
                    foundSeparator = true
                    endWithNegOrDot = true
                }
            case UInt8(ascii: "."):
                if !secondDot {
                    secondDot = true
                } else {
                    // This is the second dot, and it is considered as a separator.
                    foundSeparator = true
                    endWithNegOrDot = true
                }
            case UInt8(ascii: "e"), UInt8(ascii: "E"):
                isExponential = true
            default:
                break
            }
            if foundSeparator {
                break
            }
            currentIndex += 1
        }
        return (currentIndex, endWithNegOrDot)
    }

    private static func getFloats(_ s: [UInt8], _ start: Int, _ end: Int, _ out: inout [Float]) {
        if s[start] == UInt8(ascii: "z") || s[start] == UInt8(ascii: "Z") {
            return
        }
        var startPosition = start + 1
        while startPosition < end {
            let (endPosition, endWithNegOrDot) = extract(s, startPosition, end)
            if startPosition < endPosition {
                out.append(parseFloat(s, startPosition))
            }
            if endWithNegOrDot {
                // Keep the '-' or '.' sign with next number.
                startPosition = endPosition
            } else {
                startPosition = endPosition + 1
            }
        }
    }

    /// parseFloat: strtof from the number's first character (C locale).
    private static func parseFloat(_ s: [UInt8], _ position: Int) -> Float {
        var bytes = Array(s[position...]).map { CChar(bitPattern: $0) }
        bytes.append(0)
        return bytes.withUnsafeMutableBufferPointer { buf -> Float in
            let base = buf.baseAddress!
            var endPtr: UnsafeMutablePointer<CChar>? = nil
            let value = strtof(base, &endPtr)
            if value == 0 && endPtr == base {
                preconditionFailure("java.lang.IllegalArgumentException: Float format error when parsing: \(String(cString: base))")
            }
            if value.isInfinite {
                preconditionFailure("java.lang.IllegalArgumentException: Float out of range: \(String(cString: base))")
            }
            return value
        }
    }

    /// PathParser::validateVerbAndPoints.
    private static func validate(_ verb: UInt8, _ points: Int, _ position: Int, _ pathData: String) {
        let expected: Int
        switch verb {
        case UInt8(ascii: "z"), UInt8(ascii: "Z"): expected = 0
        case UInt8(ascii: "m"), UInt8(ascii: "l"), UInt8(ascii: "t"), UInt8(ascii: "M"), UInt8(ascii: "L"), UInt8(ascii: "T"):
            expected = 2
        case UInt8(ascii: "h"), UInt8(ascii: "v"), UInt8(ascii: "H"), UInt8(ascii: "V"): expected = 1
        case UInt8(ascii: "c"), UInt8(ascii: "C"): expected = 6
        case UInt8(ascii: "s"), UInt8(ascii: "q"), UInt8(ascii: "S"), UInt8(ascii: "Q"): expected = 4
        case UInt8(ascii: "a"), UInt8(ascii: "A"): expected = 7
        default:
            preconditionFailure("java.lang.IllegalArgumentException: \(Character(Unicode.Scalar(verb))) is not a valid verb. "
                                + "Failure occurred at position \(position) of path: \(pathData)")
        }
        if expected == 0 && points == 0 { return }
        if expected > 0 && points % expected == 0 { return }
        preconditionFailure("java.lang.IllegalArgumentException: \(Character(Unicode.Scalar(verb))) needs to be followed by "
                            + "\(expected > 0 ? "a multiple of " : "")\(expected) floats. However, \(points) float(s) are found. "
                            + "Failure occurred at position \(position) of path: \(pathData)")
    }

    /// PathParser::getPathDataFromAsciiString.
    private static func parse(_ pathData: String) -> (verbs: [UInt8], sizes: [Int], points: [Float]) {
        let s = Array(pathData.utf8)
        var verbs: [UInt8] = []
        var sizes: [Int] = []
        var points: [Float] = []
        var start = 0
        // Skip leading spaces.
        while start < s.count && isspace(Int32(s[start])) != 0 {
            start += 1
        }
        precondition(start < s.count, "java.lang.IllegalArgumentException: Path string cannot be empty.")
        var end = start + 1
        while end < s.count {
            end = nextStart(s, end)
            var pts: [Float] = []
            getFloats(s, start, end, &pts)
            validate(s[start], pts.count, start, pathData)
            verbs.append(s[start])
            sizes.append(pts.count)
            points.append(contentsOf: pts)
            start = end
            end += 1
        }
        if (end - start) == 1 && start < s.count {
            validate(s[start], 0, start, pathData)
            verbs.append(s[start])
            sizes.append(0)
        }
        precondition(!verbs.isEmpty, "java.lang.IllegalArgumentException: No verbs found in the string for pathData: \(pathData)")
        return (verbs, sizes, points)
    }

    /// VectorDrawableUtils PathResolver.
    private struct Resolver {
        var currentX: Float = 0
        var currentY: Float = 0
        var ctrlPointX: Float = 0
        var ctrlPointY: Float = 0
        var currentSegmentStartX: Float = 0
        var currentSegmentStartY: Float = 0

        mutating func addCommand(_ outPath: APath, _ previousCmd: UInt8, _ cmd: UInt8, _ points: [Float],
                                 _ start: Int, _ end: Int) {
            var incr = 2
            var reflectiveCtrlPointX: Float
            var reflectiveCtrlPointY: Float
            var previousCmd = previousCmd
            let c = Character(Unicode.Scalar(cmd))

            switch c {
            case "z", "Z":
                outPath.close()
                // Path is closed here, but we need to move the pen to the closed position. So we cache the
                // segment's starting position, and restore it here.
                currentX = currentSegmentStartX
                currentY = currentSegmentStartY
                ctrlPointX = currentSegmentStartX
                ctrlPointY = currentSegmentStartY
                outPath.moveTo(currentX, currentY)
            case "m", "M", "l", "L", "t", "T":
                incr = 2
            case "h", "H", "v", "V":
                incr = 1
            case "c", "C":
                incr = 6
            case "s", "S", "q", "Q":
                incr = 4
            case "a", "A":
                incr = 7
            default:
                break
            }

            var k = start
            while k < end {
                switch c {
                case "m": // moveto - Start a new sub-path (relative)
                    currentX += points[k + 0]
                    currentY += points[k + 1]
                    if k > start {
                        // Subsequent pairs are treated as implicit lineto commands.
                        outPath.rLineTo(points[k + 0], points[k + 1])
                    } else {
                        outPath.rMoveTo(points[k + 0], points[k + 1])
                        currentSegmentStartX = currentX
                        currentSegmentStartY = currentY
                    }
                case "M": // moveto - Start a new sub-path
                    currentX = points[k + 0]
                    currentY = points[k + 1]
                    if k > start {
                        outPath.lineTo(points[k + 0], points[k + 1])
                    } else {
                        outPath.moveTo(points[k + 0], points[k + 1])
                        currentSegmentStartX = currentX
                        currentSegmentStartY = currentY
                    }
                case "l": // lineto - Draw a line from the current point (relative)
                    outPath.rLineTo(points[k + 0], points[k + 1])
                    currentX += points[k + 0]
                    currentY += points[k + 1]
                case "L": // lineto - Draw a line from the current point
                    outPath.lineTo(points[k + 0], points[k + 1])
                    currentX = points[k + 0]
                    currentY = points[k + 1]
                case "h": // horizontal lineto - Draws a horizontal line (relative)
                    outPath.rLineTo(points[k + 0], 0)
                    currentX += points[k + 0]
                case "H": // horizontal lineto - Draws a horizontal line
                    outPath.lineTo(points[k + 0], currentY)
                    currentX = points[k + 0]
                case "v": // vertical lineto - Draws a vertical line from the current point (r)
                    outPath.rLineTo(0, points[k + 0])
                    currentY += points[k + 0]
                case "V": // vertical lineto - Draws a vertical line from the current point
                    outPath.lineTo(currentX, points[k + 0])
                    currentY = points[k + 0]
                case "c": // curveto - Draws a cubic Bezier curve (relative)
                    outPath.rCubicTo(points[k + 0], points[k + 1], points[k + 2], points[k + 3], points[k + 4], points[k + 5])
                    ctrlPointX = currentX + points[k + 2]
                    ctrlPointY = currentY + points[k + 3]
                    currentX += points[k + 4]
                    currentY += points[k + 5]
                case "C": // curveto - Draws a cubic Bezier curve
                    outPath.cubicTo(points[k + 0], points[k + 1], points[k + 2], points[k + 3], points[k + 4], points[k + 5])
                    currentX = points[k + 4]
                    currentY = points[k + 5]
                    ctrlPointX = points[k + 2]
                    ctrlPointY = points[k + 3]
                case "s": // smooth curveto - Draws a cubic Bezier curve (reflective cp)
                    reflectiveCtrlPointX = 0
                    reflectiveCtrlPointY = 0
                    if previousCmd == UInt8(ascii: "c") || previousCmd == UInt8(ascii: "s")
                        || previousCmd == UInt8(ascii: "C") || previousCmd == UInt8(ascii: "S") {
                        reflectiveCtrlPointX = currentX - ctrlPointX
                        reflectiveCtrlPointY = currentY - ctrlPointY
                    }
                    outPath.rCubicTo(reflectiveCtrlPointX, reflectiveCtrlPointY, points[k + 0], points[k + 1],
                                     points[k + 2], points[k + 3])
                    ctrlPointX = currentX + points[k + 0]
                    ctrlPointY = currentY + points[k + 1]
                    currentX += points[k + 2]
                    currentY += points[k + 3]
                case "S": // shorthand/smooth curveto Draws a cubic Bezier curve(reflective cp)
                    reflectiveCtrlPointX = currentX
                    reflectiveCtrlPointY = currentY
                    if previousCmd == UInt8(ascii: "c") || previousCmd == UInt8(ascii: "s")
                        || previousCmd == UInt8(ascii: "C") || previousCmd == UInt8(ascii: "S") {
                        reflectiveCtrlPointX = 2 * currentX - ctrlPointX
                        reflectiveCtrlPointY = 2 * currentY - ctrlPointY
                    }
                    outPath.cubicTo(reflectiveCtrlPointX, reflectiveCtrlPointY, points[k + 0], points[k + 1],
                                    points[k + 2], points[k + 3])
                    ctrlPointX = points[k + 0]
                    ctrlPointY = points[k + 1]
                    currentX = points[k + 2]
                    currentY = points[k + 3]
                case "q": // Draws a quadratic Bezier (relative)
                    outPath.rQuadTo(points[k + 0], points[k + 1], points[k + 2], points[k + 3])
                    ctrlPointX = currentX + points[k + 0]
                    ctrlPointY = currentY + points[k + 1]
                    currentX += points[k + 2]
                    currentY += points[k + 3]
                case "Q": // Draws a quadratic Bezier
                    outPath.quadTo(points[k + 0], points[k + 1], points[k + 2], points[k + 3])
                    ctrlPointX = points[k + 0]
                    ctrlPointY = points[k + 1]
                    currentX = points[k + 2]
                    currentY = points[k + 3]
                case "t": // Draws a quadratic Bezier curve(reflective control point)(relative)
                    reflectiveCtrlPointX = 0
                    reflectiveCtrlPointY = 0
                    if previousCmd == UInt8(ascii: "q") || previousCmd == UInt8(ascii: "t")
                        || previousCmd == UInt8(ascii: "Q") || previousCmd == UInt8(ascii: "T") {
                        reflectiveCtrlPointX = currentX - ctrlPointX
                        reflectiveCtrlPointY = currentY - ctrlPointY
                    }
                    outPath.rQuadTo(reflectiveCtrlPointX, reflectiveCtrlPointY, points[k + 0], points[k + 1])
                    ctrlPointX = currentX + reflectiveCtrlPointX
                    ctrlPointY = currentY + reflectiveCtrlPointY
                    currentX += points[k + 0]
                    currentY += points[k + 1]
                case "T": // Draws a quadratic Bezier curve (reflective control point)
                    reflectiveCtrlPointX = currentX
                    reflectiveCtrlPointY = currentY
                    if previousCmd == UInt8(ascii: "q") || previousCmd == UInt8(ascii: "t")
                        || previousCmd == UInt8(ascii: "Q") || previousCmd == UInt8(ascii: "T") {
                        reflectiveCtrlPointX = 2 * currentX - ctrlPointX
                        reflectiveCtrlPointY = 2 * currentY - ctrlPointY
                    }
                    outPath.quadTo(reflectiveCtrlPointX, reflectiveCtrlPointY, points[k + 0], points[k + 1])
                    ctrlPointX = reflectiveCtrlPointX
                    ctrlPointY = reflectiveCtrlPointY
                    currentX = points[k + 0]
                    currentY = points[k + 1]
                case "a": // Draws an elliptical arc (rx ry x-axis-rotation large-arc-flag sweep-flag x y)
                    outPath.kgSvgArcTo(points[k + 0], points[k + 1], points[k + 2], points[k + 3] != 0,
                                       !(points[k + 4] == 0), points[k + 5] + currentX, points[k + 6] + currentY)
                    currentX += points[k + 5]
                    currentY += points[k + 6]
                    ctrlPointX = currentX
                    ctrlPointY = currentY
                case "A": // Draws an elliptical arc
                    outPath.kgSvgArcTo(points[k + 0], points[k + 1], points[k + 2], points[k + 3] != 0,
                                       !(points[k + 4] == 0), points[k + 5], points[k + 6])
                    currentX = points[k + 5]
                    currentY = points[k + 6]
                    ctrlPointX = currentX
                    ctrlPointY = currentY
                default:
                    preconditionFailure("Unsupported command: \(c)")
                }
                previousCmd = cmd
                k += incr
            }
        }
    }
}
