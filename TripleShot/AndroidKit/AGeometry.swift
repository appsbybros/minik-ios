import CoreGraphics
import Foundation

// android.graphics.Rect, RectF, PointF and Matrix (VIEW-API "Graphics"). Rect/RectF/Matrix are reference
// types like on Android (drawables hand out their bounds Rect, code mutates RectFs in place); PointF is a
// value type (Kotlin code that mutates a shared PointF must hold it in a KRef).

// MARK: - Rect

/// android.graphics.Rect (Int coordinates, px). `==` compares the coordinates like `Rect.equals`.
final class ARect: Hashable, CustomStringConvertible {
    var left: Int
    var top: Int
    var right: Int
    var bottom: Int

    init() {
        left = 0; top = 0; right = 0; bottom = 0
    }

    init(_ left: Int, _ top: Int, _ right: Int, _ bottom: Int) {
        self.left = left; self.top = top; self.right = right; self.bottom = bottom
    }

    /// `new Rect(Rect r)` (a null source gives an empty rect).
    init(_ r: ARect?) {
        left = r?.left ?? 0; top = r?.top ?? 0; right = r?.right ?? 0; bottom = r?.bottom ?? 0
    }

    static func == (a: ARect, b: ARect) -> Bool {
        return a.left == b.left && a.top == b.top && a.right == b.right && a.bottom == b.bottom
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(left); hasher.combine(top); hasher.combine(right); hasher.combine(bottom)
    }

    /// `Rect.toString()`.
    var description: String { return "Rect(\(left), \(top) - \(right), \(bottom))" }

    func isEmpty() -> Bool { return left >= right || top >= bottom }
    func width() -> Int { return right - left }
    func height() -> Int { return bottom - top }
    func centerX() -> Int { return (left + right) >> 1 }
    func centerY() -> Int { return (top + bottom) >> 1 }
    func exactCenterX() -> Float { return Float(left + right) * 0.5 }
    func exactCenterY() -> Float { return Float(top + bottom) * 0.5 }

    func setEmpty() { left = 0; right = 0; top = 0; bottom = 0 }

    func set(_ left: Int, _ top: Int, _ right: Int, _ bottom: Int) {
        self.left = left; self.top = top; self.right = right; self.bottom = bottom
    }

    func set(_ src: ARect) {
        left = src.left; top = src.top; right = src.right; bottom = src.bottom
    }

    func offset(_ dx: Int, _ dy: Int) {
        left += dx; top += dy; right += dx; bottom += dy
    }

    func offsetTo(_ newLeft: Int, _ newTop: Int) {
        right += newLeft - left
        bottom += newTop - top
        left = newLeft
        top = newTop
    }

    func inset(_ dx: Int, _ dy: Int) {
        left += dx; top += dy; right -= dx; bottom -= dy
    }

    func inset(_ left: Int, _ top: Int, _ right: Int, _ bottom: Int) {
        self.left += left; self.top += top; self.right -= right; self.bottom -= bottom
    }

    func contains(_ x: Int, _ y: Int) -> Bool {
        return left < right && top < bottom && x >= left && x < right && y >= top && y < bottom
    }

    func contains(_ left: Int, _ top: Int, _ right: Int, _ bottom: Int) -> Bool {
        return self.left < self.right && self.top < self.bottom
            && self.left <= left && self.top <= top && self.right >= right && self.bottom >= bottom
    }

    func contains(_ r: ARect) -> Bool {
        return left < right && top < bottom && left <= r.left && top <= r.top && right >= r.right && bottom >= r.bottom
    }

    @discardableResult
    func intersect(_ left: Int, _ top: Int, _ right: Int, _ bottom: Int) -> Bool {
        if self.left < right && left < self.right && self.top < bottom && top < self.bottom {
            if self.left < left { self.left = left }
            if self.top < top { self.top = top }
            if self.right > right { self.right = right }
            if self.bottom > bottom { self.bottom = bottom }
            return true
        }
        return false
    }

    @discardableResult
    func intersect(_ r: ARect) -> Bool { return intersect(r.left, r.top, r.right, r.bottom) }

    func intersects(_ left: Int, _ top: Int, _ right: Int, _ bottom: Int) -> Bool {
        return self.left < right && left < self.right && self.top < bottom && top < self.bottom
    }

    static func intersects(_ a: ARect, _ b: ARect) -> Bool {
        return a.left < b.right && b.left < a.right && a.top < b.bottom && b.top < a.bottom
    }

    @discardableResult
    func setIntersect(_ a: ARect, _ b: ARect) -> Bool {
        if a.left < b.right && b.left < a.right && a.top < b.bottom && b.top < a.bottom {
            left = max(a.left, b.left)
            top = max(a.top, b.top)
            right = min(a.right, b.right)
            bottom = min(a.bottom, b.bottom)
            return true
        }
        return false
    }

    func union(_ left: Int, _ top: Int, _ right: Int, _ bottom: Int) {
        if (left < right) && (top < bottom) {
            if (self.left < self.right) && (self.top < self.bottom) {
                if self.left > left { self.left = left }
                if self.top > top { self.top = top }
                if self.right < right { self.right = right }
                if self.bottom < bottom { self.bottom = bottom }
            } else {
                self.left = left; self.top = top; self.right = right; self.bottom = bottom
            }
        }
    }

    func union(_ r: ARect) { union(r.left, r.top, r.right, r.bottom) }

    func union(_ x: Int, _ y: Int) {
        if x < left { left = x } else if x > right { right = x }
        if y < top { top = y } else if y > bottom { bottom = y }
    }

    func sort() {
        if left > right { let t = left; left = right; right = t }
        if top > bottom { let t = top; top = bottom; bottom = t }
    }

    var cgRect: CGRect {
        return CGRect(x: CGFloat(left), y: CGFloat(top), width: CGFloat(right - left), height: CGFloat(bottom - top))
    }
}

// MARK: - RectF

/// android.graphics.RectF (Float coordinates, px). `==` compares with primitive float `==` like `RectF.equals`.
final class ARectF: Hashable, CustomStringConvertible {
    var left: Float
    var top: Float
    var right: Float
    var bottom: Float

    init() {
        left = 0; top = 0; right = 0; bottom = 0
    }

    init(_ left: Float, _ top: Float, _ right: Float, _ bottom: Float) {
        self.left = left; self.top = top; self.right = right; self.bottom = bottom
    }

    /// `new RectF(RectF r)` (a null source gives an empty rect).
    init(_ r: ARectF?) {
        left = r?.left ?? 0; top = r?.top ?? 0; right = r?.right ?? 0; bottom = r?.bottom ?? 0
    }

    /// `new RectF(Rect r)`.
    init(_ r: ARect?) {
        left = Float(r?.left ?? 0); top = Float(r?.top ?? 0); right = Float(r?.right ?? 0); bottom = Float(r?.bottom ?? 0)
    }

    static func == (a: ARectF, b: ARectF) -> Bool {
        return a.left == b.left && a.top == b.top && a.right == b.right && a.bottom == b.bottom
    }

    func hash(into hasher: inout Hasher) {
        // Float.floatToIntBits-like: +0 and -0 compare equal with ==, so hash their common value.
        hasher.combine(left == 0 ? 0 : left); hasher.combine(top == 0 ? 0 : top)
        hasher.combine(right == 0 ? 0 : right); hasher.combine(bottom == 0 ? 0 : bottom)
    }

    /// `RectF.toString()`.
    var description: String {
        return "RectF(\(javaFloatText(left)), \(javaFloatText(top)), \(javaFloatText(right)), \(javaFloatText(bottom)))"
    }

    /// `left >= right || top >= bottom` (a NaN coordinate makes the rect non-empty, like Android).
    func isEmpty() -> Bool { return left >= right || top >= bottom }
    func width() -> Float { return right - left }
    func height() -> Float { return bottom - top }
    func centerX() -> Float { return (left + right) * 0.5 }
    func centerY() -> Float { return (top + bottom) * 0.5 }

    func setEmpty() { left = 0; right = 0; top = 0; bottom = 0 }

    func set(_ left: Float, _ top: Float, _ right: Float, _ bottom: Float) {
        self.left = left; self.top = top; self.right = right; self.bottom = bottom
    }

    func set(_ src: ARectF) {
        left = src.left; top = src.top; right = src.right; bottom = src.bottom
    }

    func set(_ src: ARect) {
        left = Float(src.left); top = Float(src.top); right = Float(src.right); bottom = Float(src.bottom)
    }

    func offset(_ dx: Float, _ dy: Float) {
        left += dx; top += dy; right += dx; bottom += dy
    }

    func offsetTo(_ newLeft: Float, _ newTop: Float) {
        right += newLeft - left
        bottom += newTop - top
        left = newLeft
        top = newTop
    }

    func inset(_ dx: Float, _ dy: Float) {
        left += dx; top += dy; right -= dx; bottom -= dy
    }

    func contains(_ x: Float, _ y: Float) -> Bool {
        return left < right && top < bottom && x >= left && x < right && y >= top && y < bottom
    }

    func contains(_ left: Float, _ top: Float, _ right: Float, _ bottom: Float) -> Bool {
        return self.left < self.right && self.top < self.bottom
            && self.left <= left && self.top <= top && self.right >= right && self.bottom >= bottom
    }

    func contains(_ r: ARectF) -> Bool {
        return left < right && top < bottom && left <= r.left && top <= r.top && right >= r.right && bottom >= r.bottom
    }

    @discardableResult
    func intersect(_ left: Float, _ top: Float, _ right: Float, _ bottom: Float) -> Bool {
        if self.left < right && left < self.right && self.top < bottom && top < self.bottom {
            if self.left < left { self.left = left }
            if self.top < top { self.top = top }
            if self.right > right { self.right = right }
            if self.bottom > bottom { self.bottom = bottom }
            return true
        }
        return false
    }

    @discardableResult
    func intersect(_ r: ARectF) -> Bool { return intersect(r.left, r.top, r.right, r.bottom) }

    func intersects(_ left: Float, _ top: Float, _ right: Float, _ bottom: Float) -> Bool {
        return self.left < right && left < self.right && self.top < bottom && top < self.bottom
    }

    static func intersects(_ a: ARectF, _ b: ARectF) -> Bool {
        return a.left < b.right && b.left < a.right && a.top < b.bottom && b.top < a.bottom
    }

    @discardableResult
    func setIntersect(_ a: ARectF, _ b: ARectF) -> Bool {
        if a.left < b.right && b.left < a.right && a.top < b.bottom && b.top < a.bottom {
            left = Swift.max(a.left, b.left)
            top = Swift.max(a.top, b.top)
            right = Swift.min(a.right, b.right)
            bottom = Swift.min(a.bottom, b.bottom)
            return true
        }
        return false
    }

    func union(_ left: Float, _ top: Float, _ right: Float, _ bottom: Float) {
        if (left < right) && (top < bottom) {
            if (self.left < self.right) && (self.top < self.bottom) {
                if self.left > left { self.left = left }
                if self.top > top { self.top = top }
                if self.right < right { self.right = right }
                if self.bottom < bottom { self.bottom = bottom }
            } else {
                self.left = left; self.top = top; self.right = right; self.bottom = bottom
            }
        }
    }

    func union(_ r: ARectF) { union(r.left, r.top, r.right, r.bottom) }

    func union(_ x: Float, _ y: Float) {
        if x < left { left = x } else if x > right { right = x }
        if y < top { top = y } else if y > bottom { bottom = y }
    }

    func sort() {
        if left > right { let t = left; left = right; right = t }
        if top > bottom { let t = top; top = bottom; bottom = t }
    }

    /// `RectF.round(dst)`: `FastMath.round` of each coordinate (fixed-point rounding).
    func round(_ dst: ARect) {
        dst.set(ARectF.fastRound(left), ARectF.fastRound(top), ARectF.fastRound(right), ARectF.fastRound(bottom))
    }

    /// `RectF.roundOut(dst)`: floor of left/top, ceil of right/bottom.
    func roundOut(_ dst: ARect) {
        dst.set(KitGraphics.floorInt(left), KitGraphics.floorInt(top), KitGraphics.ceilInt(right), KitGraphics.ceilInt(bottom))
    }

    /// `com.android.internal.util.FastMath.round(float)`: `(int) (((long) (value * 2^24) + 0x800000) >> 24)`.
    static func fastRound(_ value: Float) -> Int {
        let lx = KitGraphics.javaLong(value * Float(65536 * 256))
        return Int(Int32(truncatingIfNeeded: (lx &+ 0x800000) >> 24))
    }

    var cgRect: CGRect {
        return CGRect(x: CGFloat(left), y: CGFloat(top), width: CGFloat(right - left), height: CGFloat(bottom - top))
    }
}

/// `Float.toString()` for descriptions (debug text only; game text uses AKotlin `javaString`).
private func javaFloatText(_ v: Float) -> String {
    if v.isNaN { return "NaN" }
    if v == v.rounded(.towardZero) && abs(v) < 1e7 { return String(format: "%.1f", Double(v)) }
    return "\(v)"
}

// MARK: - PointF

/// android.graphics.PointF as a value type. `==` follows `PointF.equals` (Float.compare: NaN equals NaN,
/// 0.0 differs from -0.0); `equals(x, y)` uses primitive `==`.
struct APointF: Hashable, CustomStringConvertible {
    var x: Float
    var y: Float

    init() {
        x = 0; y = 0
    }

    init(_ x: Float, _ y: Float) {
        self.x = x; self.y = y
    }

    init(_ p: APointF) {
        x = p.x; y = p.y
    }

    mutating func set(_ x: Float, _ y: Float) {
        self.x = x; self.y = y
    }

    mutating func set(_ p: APointF) {
        x = p.x; y = p.y
    }

    mutating func negate() {
        x = -x; y = -y
    }

    mutating func offset(_ dx: Float, _ dy: Float) {
        x += dx; y += dy
    }

    func equals(_ x: Float, _ y: Float) -> Bool {
        return self.x == x && self.y == y
    }

    /// `PointF.length()`: `(float) Math.hypot(x, y)`.
    func length() -> Float {
        return APointF.length(x, y)
    }

    static func length(_ x: Float, _ y: Float) -> Float {
        return Float(hypot(Double(x), Double(y)))
    }

    private static func floatToIntBits(_ f: Float) -> UInt32 {
        return f.isNaN ? 0x7fc0_0000 : f.bitPattern
    }

    static func == (a: APointF, b: APointF) -> Bool {
        return floatToIntBits(a.x) == floatToIntBits(b.x) && floatToIntBits(a.y) == floatToIntBits(b.y)
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(APointF.floatToIntBits(x)); hasher.combine(APointF.floatToIntBits(y))
    }

    var description: String { return "PointF(\(x), \(y))" }

    var cgPoint: CGPoint { return CGPoint(x: CGFloat(x), y: CGFloat(y)) }
}

// MARK: - Matrix

/// android.graphics.Matrix = Skia SkMatrix (3x3, Float). Values in Android order
/// [MSCALE_X, MSKEW_X, MTRANS_X, MSKEW_Y, MSCALE_Y, MTRANS_Y, MPERSP_0, MPERSP_1, MPERSP_2].
/// Every operation reproduces SkMatrix's arithmetic (the type-dependent fast paths included), so results are
/// bit-identical to Android for the same inputs. `==` compares the nine values with `==` like `Matrix.equals`.
final class AMatrix: Equatable, CustomStringConvertible {
    static let MSCALE_X = 0
    static let MSKEW_X = 1
    static let MTRANS_X = 2
    static let MSKEW_Y = 3
    static let MSCALE_Y = 4
    static let MTRANS_Y = 5
    static let MPERSP_0 = 6
    static let MPERSP_1 = 7
    static let MPERSP_2 = 8

    /// `Matrix.ScaleToFit`.
    enum ScaleToFit { case FILL, START, CENTER, END }

    private var m: [Float] = [1, 0, 0, 0, 1, 0, 0, 0, 1]

    // SkMatrix type mask bits.
    private static let kTranslate = 0x01
    private static let kScale = 0x02
    private static let kAffine = 0x04
    private static let kPerspective = 0x08

    init() {}

    /// `new Matrix(Matrix src)`.
    init(_ src: AMatrix?) {
        if let s = src { m = s.m }
    }

    static func == (a: AMatrix, b: AMatrix) -> Bool {
        for i in 0..<9 where a.m[i] != b.m[i] { return false }
        return true
    }

    /// `Matrix.toString()`.
    var description: String {
        return "Matrix{[\(m[0]), \(m[1]), \(m[2])][\(m[3]), \(m[4]), \(m[5])][\(m[6]), \(m[7]), \(m[8])]}"
    }

    // MARK: Type (SkMatrix::computeTypeMask)

    private var typeMask: Int {
        if m[6] != 0 || m[7] != 0 || m[8] != 1 {
            return AMatrix.kTranslate | AMatrix.kScale | AMatrix.kAffine | AMatrix.kPerspective
        }
        var mask = 0
        if m[2] != 0 || m[5] != 0 { mask |= AMatrix.kTranslate }
        if m[1] != 0 || m[3] != 0 {
            // Skew may be scale-inducing; Skia conservatively sets the scale bit too.
            mask |= AMatrix.kAffine | AMatrix.kScale
        } else if m[0] != 1 || m[4] != 1 {
            mask |= AMatrix.kScale
        }
        return mask
    }

    private var hasPerspective: Bool { return (typeMask & AMatrix.kPerspective) != 0 }
    private var isScaleTranslate: Bool { return (typeMask & ~(AMatrix.kScale | AMatrix.kTranslate)) == 0 }

    func isIdentity() -> Bool { return typeMask == 0 }
    func isAffine() -> Bool { return !hasPerspective }

    /// `rectStaysRect()`: axis-aligned rectangles map to axis-aligned rectangles.
    func rectStaysRect() -> Bool {
        let mask = typeMask
        if (mask & AMatrix.kPerspective) != 0 { return false }
        if (mask & AMatrix.kAffine) != 0 {
            // A 90-degree rotation (possibly with scale): diagonal zero, skews non-zero.
            return m[0] == 0 && m[4] == 0 && m[1] != 0 && m[3] != 0
        }
        return m[0] != 0 && m[4] != 0
    }

    // MARK: Setters

    func set(_ src: AMatrix?) {
        if let s = src { m = s.m } else { reset() }
    }

    func reset() {
        m = [1, 0, 0, 0, 1, 0, 0, 0, 1]
    }

    func setTranslate(_ dx: Float, _ dy: Float) {
        m = [1, 0, dx, 0, 1, dy, 0, 0, 1]
    }

    private func setScaleTranslate(_ sx: Float, _ sy: Float, _ tx: Float, _ ty: Float) {
        m = [sx, 0, tx, 0, sy, ty, 0, 0, 1]
    }

    func setScale(_ sx: Float, _ sy: Float, _ px: Float, _ py: Float) {
        if sx == 1 && sy == 1 {
            reset()
        } else {
            setScaleTranslate(sx, sy, px - sx * px, py - sy * py)
        }
    }

    func setScale(_ sx: Float, _ sy: Float) {
        if sx == 1 && sy == 1 {
            reset()
        } else {
            m = [sx, 0, 0, 0, sy, 0, 0, 0, 1]
        }
    }

    func setSinCos(_ sinValue: Float, _ cosValue: Float, _ px: Float, _ py: Float) {
        let oneMinusCosV = 1 - cosValue
        m = [cosValue, -sinValue, sinValue * py + oneMinusCosV * px,
             sinValue, cosValue, -sinValue * px + oneMinusCosV * py,
             0, 0, 1]
    }

    func setSinCos(_ sinValue: Float, _ cosValue: Float) {
        m = [cosValue, -sinValue, 0, sinValue, cosValue, 0, 0, 0, 1]
    }

    func setRotate(_ degrees: Float, _ px: Float, _ py: Float) {
        let rad = KitGraphics.degreesToRadians(degrees)
        setSinCos(KitGraphics.sinSnapToZero(rad), KitGraphics.cosSnapToZero(rad), px, py)
    }

    func setRotate(_ degrees: Float) {
        let rad = KitGraphics.degreesToRadians(degrees)
        setSinCos(KitGraphics.sinSnapToZero(rad), KitGraphics.cosSnapToZero(rad))
    }

    func setSkew(_ kx: Float, _ ky: Float, _ px: Float, _ py: Float) {
        m = [1, kx, -kx * py, ky, 1, -ky * px, 0, 0, 1]
    }

    func setSkew(_ kx: Float, _ ky: Float) {
        m = [1, kx, 0, ky, 1, 0, 0, 0, 1]
    }

    /// `setConcat(a, b)`: this = a * b (b applied first).
    @discardableResult
    func setConcat(_ a: AMatrix, _ b: AMatrix) -> Bool {
        m = AMatrix.concat(a.m, a.typeMask, b.m, b.typeMask)
        return true
    }

    /// SkMatrix::setConcat arithmetic.
    private static func concat(_ a: [Float], _ aType: Int, _ b: [Float], _ bType: Int) -> [Float] {
        if aType == 0 { return b }
        if bType == 0 { return a }
        if ((aType | bType) & ~(kScale | kTranslate)) == 0 {
            return [a[0] * b[0], 0, a[0] * b[2] + a[2],
                    0, a[4] * b[4], a[4] * b[5] + a[5],
                    0, 0, 1]
        }
        if ((aType | bType) & kPerspective) != 0 {
            func rowcol3(_ row: Int, _ col: Int) -> Float {
                return a[row] * b[col] + a[row + 1] * b[col + 3] + a[row + 2] * b[col + 6]
            }
            return [rowcol3(0, 0), rowcol3(0, 1), rowcol3(0, 2),
                    rowcol3(3, 0), rowcol3(3, 1), rowcol3(3, 2),
                    rowcol3(6, 0), rowcol3(6, 1), rowcol3(6, 2)]
        }
        func muladdmul(_ p: Float, _ q: Float, _ r: Float, _ s: Float) -> Float {
            return Float(Double(p) * Double(q) + Double(r) * Double(s))
        }
        return [muladdmul(a[0], b[0], a[1], b[3]),
                muladdmul(a[0], b[1], a[1], b[4]),
                muladdmul(a[0], b[2], a[1], b[5]) + a[2],
                muladdmul(a[3], b[0], a[4], b[3]),
                muladdmul(a[3], b[1], a[4], b[4]),
                muladdmul(a[3], b[2], a[4], b[5]) + a[5],
                0, 0, 1]
    }

    // MARK: Pre / post

    @discardableResult
    func preTranslate(_ dx: Float, _ dy: Float) -> Bool {
        let mask = typeMask
        if mask <= AMatrix.kTranslate {
            m[2] += dx
            m[5] += dy
        } else if (mask & AMatrix.kPerspective) != 0 {
            let t = AMatrix(); t.setTranslate(dx, dy)
            return preConcat(t)
        } else {
            m[2] += m[0] * dx + m[1] * dy
            m[5] += m[3] * dx + m[4] * dy
        }
        return true
    }

    @discardableResult
    func postTranslate(_ dx: Float, _ dy: Float) -> Bool {
        if hasPerspective {
            let t = AMatrix(); t.setTranslate(dx, dy)
            return postConcat(t)
        }
        m[2] += dx
        m[5] += dy
        return true
    }

    @discardableResult
    func preScale(_ sx: Float, _ sy: Float) -> Bool {
        if sx == 1 && sy == 1 { return true }
        m[0] *= sx
        m[3] *= sx
        m[6] *= sx
        m[1] *= sy
        m[4] *= sy
        m[7] *= sy
        return true
    }

    @discardableResult
    func preScale(_ sx: Float, _ sy: Float, _ px: Float, _ py: Float) -> Bool {
        if sx == 1 && sy == 1 { return true }
        let t = AMatrix(); t.setScale(sx, sy, px, py)
        return preConcat(t)
    }

    @discardableResult
    func postScale(_ sx: Float, _ sy: Float) -> Bool {
        if sx == 1 && sy == 1 { return true }
        let t = AMatrix(); t.setScale(sx, sy)
        return postConcat(t)
    }

    @discardableResult
    func postScale(_ sx: Float, _ sy: Float, _ px: Float, _ py: Float) -> Bool {
        if sx == 1 && sy == 1 { return true }
        let t = AMatrix(); t.setScale(sx, sy, px, py)
        return postConcat(t)
    }

    @discardableResult
    func preRotate(_ degrees: Float) -> Bool {
        let t = AMatrix(); t.setRotate(degrees)
        return preConcat(t)
    }

    @discardableResult
    func preRotate(_ degrees: Float, _ px: Float, _ py: Float) -> Bool {
        let t = AMatrix(); t.setRotate(degrees, px, py)
        return preConcat(t)
    }

    @discardableResult
    func postRotate(_ degrees: Float) -> Bool {
        let t = AMatrix(); t.setRotate(degrees)
        return postConcat(t)
    }

    @discardableResult
    func postRotate(_ degrees: Float, _ px: Float, _ py: Float) -> Bool {
        let t = AMatrix(); t.setRotate(degrees, px, py)
        return postConcat(t)
    }

    @discardableResult
    func preSkew(_ kx: Float, _ ky: Float) -> Bool {
        let t = AMatrix(); t.setSkew(kx, ky)
        return preConcat(t)
    }

    @discardableResult
    func postSkew(_ kx: Float, _ ky: Float) -> Bool {
        let t = AMatrix(); t.setSkew(kx, ky)
        return postConcat(t)
    }

    /// this = this * other (other applied first).
    @discardableResult
    func preConcat(_ other: AMatrix) -> Bool {
        let otherType = other.typeMask
        if otherType != 0 { m = AMatrix.concat(m, typeMask, other.m, otherType) }
        return true
    }

    /// this = other * this (other applied last).
    @discardableResult
    func postConcat(_ other: AMatrix) -> Bool {
        let otherType = other.typeMask
        if otherType != 0 { m = AMatrix.concat(other.m, otherType, m, typeMask) }
        return true
    }

    // MARK: Rect to rect

    /// `setRectToRect(src, dst, stf)` (SkMatrix::setRectToRect).
    @discardableResult
    func setRectToRect(_ src: ARectF, _ dst: ARectF, _ stf: ScaleToFit) -> Bool {
        if src.isEmpty() {
            reset()
            return false
        }
        if dst.isEmpty() {
            m = [0, 0, 0, 0, 0, 0, 0, 0, 1]
        } else {
            var sx = dst.width() / src.width()
            var sy = dst.height() / src.height()
            var xLarger = false
            if stf != .FILL {
                if sx > sy {
                    xLarger = true
                    sx = sy
                } else {
                    sy = sx
                }
            }
            var tx = dst.left - src.left * sx
            var ty = dst.top - src.top * sy
            if stf == .CENTER || stf == .END {
                var diff: Float
                if xLarger {
                    diff = dst.width() - src.width() * sy
                } else {
                    diff = dst.height() - src.height() * sy
                }
                if stf == .CENTER {
                    diff = diff * 0.5
                }
                if xLarger {
                    tx += diff
                } else {
                    ty += diff
                }
            }
            setScaleTranslate(sx, sy, tx, ty)
        }
        return true
    }

    // MARK: Inverse

    /// `invert(inverse)` (SkMatrix::invert): false, and `inverse` unchanged, when not invertible.
    @discardableResult
    func invert(_ inverse: AMatrix) -> Bool {
        let mask = typeMask
        if mask == 0 {
            inverse.reset()
            return true
        }
        if (mask & ~(AMatrix.kScale | AMatrix.kTranslate)) == 0 {
            if (mask & AMatrix.kScale) != 0 {
                if m[0] == 0 || m[4] == 0 { return false }
                let invX = Float(1) / m[0]
                let invY = Float(1) / m[4]
                let tx = -m[2] * invX
                let ty = -m[5] * invY
                inverse.m = [invX, 0, tx, 0, invY, ty, 0, 0, 1]
            } else {
                inverse.setTranslate(-m[2], -m[5])
            }
            return true
        }
        let isPersp = (mask & AMatrix.kPerspective) != 0
        func dcross(_ a: Double, _ b: Double, _ c: Double, _ d: Double) -> Double { return a * b - c * d }
        var det: Double
        if isPersp {
            det = Double(m[0]) * dcross(Double(m[4]), Double(m[8]), Double(m[5]), Double(m[7]))
                + Double(m[1]) * dcross(Double(m[5]), Double(m[6]), Double(m[3]), Double(m[8]))
                + Double(m[2]) * dcross(Double(m[3]), Double(m[7]), Double(m[4]), Double(m[6]))
        } else {
            det = dcross(Double(m[0]), Double(m[4]), Double(m[1]), Double(m[3]))
        }
        let tolerance = KitGraphics.nearlyZero * KitGraphics.nearlyZero * KitGraphics.nearlyZero
        if abs(Float(det)) <= tolerance { return false }
        let invDet = 1.0 / det
        if invDet == 0 { return false }   // underflow
        var dst = [Float](repeating: 0, count: 9)
        if isPersp {
            func scross(_ a: Float, _ b: Float, _ c: Float, _ d: Float) -> Float { return a * b - c * d }
            func sd(_ a: Float, _ b: Float, _ c: Float, _ d: Float) -> Float { return Float(Double(scross(a, b, c, d)) * invDet) }
            dst[0] = sd(m[4], m[8], m[5], m[7])
            dst[1] = sd(m[2], m[7], m[1], m[8])
            dst[2] = sd(m[1], m[5], m[2], m[4])
            dst[3] = sd(m[5], m[6], m[3], m[8])
            dst[4] = sd(m[0], m[8], m[2], m[6])
            dst[5] = sd(m[2], m[3], m[0], m[5])
            dst[6] = sd(m[3], m[7], m[4], m[6])
            dst[7] = sd(m[1], m[6], m[0], m[7])
            dst[8] = sd(m[0], m[4], m[1], m[3])
        } else {
            dst[0] = Float(Double(m[4]) * invDet)
            dst[1] = Float(Double(-m[1]) * invDet)
            dst[2] = Float(dcross(Double(m[1]), Double(m[5]), Double(m[4]), Double(m[2])) * invDet)
            dst[3] = Float(Double(-m[3]) * invDet)
            dst[4] = Float(Double(m[0]) * invDet)
            dst[5] = Float(dcross(Double(m[3]), Double(m[2]), Double(m[0]), Double(m[5])) * invDet)
            dst[6] = 0
            dst[7] = 0
            dst[8] = 1
        }
        for v in dst where !v.isFinite { return false }
        inverse.m = dst
        return true
    }

    // MARK: Mapping

    /// Maps one point with the SkMatrix map proc of this matrix's type.
    private func mapXY(_ x: Float, _ y: Float, _ mask: Int) -> (Float, Float) {
        if mask == 0 { return (x, y) }
        if mask == AMatrix.kTranslate { return (x + m[2], y + m[5]) }
        if (mask & ~(AMatrix.kScale | AMatrix.kTranslate)) == 0 {
            if (mask & AMatrix.kTranslate) == 0 { return (x * m[0], y * m[4]) }
            return (x * m[0] + m[2], y * m[4] + m[5])
        }
        if (mask & AMatrix.kPerspective) == 0 {
            return ((x * m[0] + y * m[1]) + m[2], (y * m[4] + x * m[3]) + m[5])
        }
        let px = (x * m[0] + y * m[1]) + m[2]
        let py = (x * m[3] + y * m[4]) + m[5]
        var z = (x * m[6] + y * m[7]) + m[8]
        if z != 0 { z = 1 / z }
        return (px * z, py * z)
    }

    /// `mapPoints(dst, dstIndex, src, srcIndex, pointCount)`.
    func mapPoints(_ dst: inout [Float], _ dstIndex: Int, _ src: [Float], _ srcIndex: Int, _ pointCount: Int) {
        let mask = typeMask
        for i in 0..<max(0, pointCount) {
            let (x, y) = mapXY(src[srcIndex + 2 * i], src[srcIndex + 2 * i + 1], mask)
            dst[dstIndex + 2 * i] = x
            dst[dstIndex + 2 * i + 1] = y
        }
    }

    /// `mapPoints(dst, src)`.
    func mapPoints(_ dst: inout [Float], _ src: [Float]) {
        precondition(dst.count == src.count, "java.lang.ArrayIndexOutOfBoundsException")
        mapPoints(&dst, 0, src, 0, src.count >> 1)
    }

    /// `mapPoints(pts)`: in place.
    func mapPoints(_ pts: inout [Float]) {
        let src = pts
        mapPoints(&pts, 0, src, 0, src.count >> 1)
    }

    /// `mapVectors(vecs)`: like mapPoints without the translation.
    func mapVectors(_ vecs: inout [Float]) {
        let noTranslate = AMatrix(self)
        noTranslate.m[2] = 0
        noTranslate.m[5] = 0
        noTranslate.mapPoints(&vecs)
    }

    /// `mapRect(dst, src)`: the bounds of the mapped rect; returns `rectStaysRect()`.
    @discardableResult
    func mapRect(_ dst: ARectF, _ src: ARectF) -> Bool {
        let mask = typeMask
        if mask <= AMatrix.kTranslate {
            dst.set(src.left + m[2], src.top + m[5], src.right + m[2], src.bottom + m[5])
            dst.sort()
            return true
        }
        if (mask & ~(AMatrix.kScale | AMatrix.kTranslate)) == 0 {
            dst.set(src.left * m[0] + m[2], src.top * m[4] + m[5], src.right * m[0] + m[2], src.bottom * m[4] + m[5])
            dst.sort()
            return true
        }
        let corners = [(src.left, src.top), (src.right, src.top), (src.right, src.bottom), (src.left, src.bottom)]
        var minX = Float.infinity, minY = Float.infinity, maxX = -Float.infinity, maxY = -Float.infinity
        for (cx, cy) in corners {
            let (x, y) = mapXY(cx, cy, mask)
            minX = Swift.min(minX, x); minY = Swift.min(minY, y)
            maxX = Swift.max(maxX, x); maxY = Swift.max(maxY, y)
        }
        dst.set(minX, minY, maxX, maxY)
        return rectStaysRect()
    }

    /// `mapRect(rect)`: in place.
    @discardableResult
    func mapRect(_ rect: ARectF) -> Bool {
        return mapRect(rect, ARectF(rect))
    }

    /// `mapRadius(radius)`: the mean radius of a mapped circle (SkMatrix::mapRadius).
    func mapRadius(_ radius: Float) -> Float {
        var v = [radius, 0, 0, radius]
        mapVectors(&v)
        let d0 = APointF.length(v[0], v[1])
        let d1 = APointF.length(v[2], v[3])
        return Float(sqrt(Double(d0) * Double(d1)))
    }

    // MARK: Values

    /// `getValues(values)`: the nine values in Android order.
    func getValues(_ values: inout [Float]) {
        precondition(values.count >= 9, "java.lang.ArrayIndexOutOfBoundsException")
        for i in 0..<9 { values[i] = m[i] }
    }

    /// `setValues(values)`.
    func setValues(_ values: [Float]) {
        precondition(values.count >= 9, "java.lang.ArrayIndexOutOfBoundsException")
        m = Array(values[0..<9])
    }

    /// The affine part as a Core Graphics transform (CG's a, b, c, d = sx, ky, kx, sy).
    var cgAffineTransform: CGAffineTransform {
        return CGAffineTransform(a: CGFloat(m[0]), b: CGFloat(m[3]), c: CGFloat(m[1]), d: CGFloat(m[4]),
                                 tx: CGFloat(m[2]), ty: CGFloat(m[5]))
    }
}
