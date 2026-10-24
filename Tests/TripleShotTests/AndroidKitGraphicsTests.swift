import XCTest
@testable import MinikTripleShot

/// Parity tests of the AndroidKit graphics layer (area kit-graphics) against Android 12 behaviour.
/// Integer vectors come from the Java-level android.graphics code (Color, Paint's Java colour, ColorDrawable,
/// GradientDrawable, VectorDrawable, FastMath, TypedValue) run on the JVM; float vectors are exact Skia / FreeType
/// sequences (SkRGBToHSV, SkMatrix::invert, FT_Outline_Embolden strength) computed in IEEE single precision and
/// compared by bit pattern; pixel tests draw into an ABitmap canvas and read the pixels back.
final class AndroidKitGraphicsTests: XCTestCase {

    // MARK: - Color

    func testColorConstants() {
        XCTAssertEqual(AColor.BLACK, -16777216)
        XCTAssertEqual(AColor.WHITE, -1)
        XCTAssertEqual(AColor.TRANSPARENT, 0)
        XCTAssertEqual(AColor.RED, -65536)
        XCTAssertEqual(AColor.GREEN, -16711936)
        XCTAssertEqual(AColor.BLUE, -16776961)
        XCTAssertEqual(AColor.YELLOW, -256)
        XCTAssertEqual(AColor.CYAN, -16711681)
        XCTAssertEqual(AColor.MAGENTA, -65281)
        XCTAssertEqual(AColor.GRAY, -7829368)
        XCTAssertEqual(AColor.DKGRAY, -12303292)
        XCTAssertEqual(AColor.LTGRAY, -3355444)
        XCTAssertEqual(argbInt(0xFF101724), -15722716)
        XCTAssertEqual(argbInt(0x00FFFFFF), 16777215)
        XCTAssertEqual(argbInt(0x80000000), -2147483648)
    }

    func testParseColor() {
        // Color.parseColor on the JVM (Android 12 source).
        XCTAssertEqual(AColor.parseColor("#65757B"), -10128005)
        XCTAssertEqual(AColor.parseColor("#554FA99C"), 1431284124)
        XCTAssertEqual(AColor.parseColor("#AA000000"), -1442840576)
        XCTAssertEqual(AColor.parseColor("#F9FFFFFF"), -100663297)
        XCTAssertEqual(AColor.parseColor("#0B8B78"), -16020616)
        XCTAssertEqual(AColor.parseColor("#0b8b78"), -16020616)
        XCTAssertEqual(AColor.parseColor("#00000000"), 0)
        XCTAssertEqual(AColor.parseColor("#FFFFFFFF"), -1)
        XCTAssertEqual(AColor.parseColor("#E91E63"), -1499549)
        XCTAssertEqual(AColor.parseColor("#D9FFFFFF"), -637534209)
        XCTAssertEqual(AColor.parseColor("#087E69"), -16220567)
        XCTAssertEqual(AColor.parseColor("#176AC0"), -15242560)
        // Colour names, case-insensitive (Color.sColorNameMap, toLowerCase(Locale.ROOT)).
        XCTAssertEqual(AColor.parseColor("teal"), -16744320)
        XCTAssertEqual(AColor.parseColor("Navy"), -16777088)
        XCTAssertEqual(AColor.parseColor("LIGHTGREY"), -3355444)
        XCTAssertEqual(AColor.parseColor("red"), AColor.RED)
        XCTAssertEqual(AColor.parseColor("GRAY"), AColor.GRAY)
        XCTAssertEqual(AColor.parseColor("darkgray"), AColor.DKGRAY)
        XCTAssertEqual(AColor.parseColor("aqua"), AColor.CYAN)
        XCTAssertEqual(AColor.parseColor("fuchsia"), AColor.MAGENTA)
        XCTAssertEqual(AColor.parseColor("lime"), AColor.GREEN)
        XCTAssertEqual(AColor.parseColor("silver"), argbInt(0xFFC0C0C0))
    }

    func testArgbRgbAndComponents() {
        XCTAssertEqual(AColor.argb(72, 205, 232, 255), 1221454079)
        XCTAssertEqual(AColor.argb(238, 255, 255, 255), -285212673)
        XCTAssertEqual(AColor.argb(214, 255, 252, 242), -687866638)
        XCTAssertEqual(AColor.argb(46, 255, 70, 170), 788481706)
        XCTAssertEqual(AColor.rgb(255, 70, 170), -47446)
        XCTAssertEqual(AColor.rgb(220, 248, 229), -2295579)
        XCTAssertEqual(AColor.rgb(255, 205, 65), argbInt(0xFFFFCD41))
        // Java int arithmetic: out-of-range components spill into the neighbouring bytes.
        XCTAssertEqual(AColor.rgb(300, 0, 0), -13893632)
        XCTAssertEqual(AColor.rgb(-1, 0, 0), -65536)
        XCTAssertEqual(AColor.argb(256, 0, 0, 0), 0)
        let c = argbInt(0x80123456)
        XCTAssertEqual(AColor.alpha(c), 128)
        XCTAssertEqual(AColor.red(c), 18)
        XCTAssertEqual(AColor.green(c), 52)
        XCTAssertEqual(AColor.blue(c), 86)
        XCTAssertEqual(AColor.argb(AColor.alpha(c), AColor.red(c), AColor.green(c), AColor.blue(c)), c)
        XCTAssertEqual(AColor.alpha(AColor.WHITE), 255)
        XCTAssertEqual(AColor.alpha(AColor.BLACK), 255)
        XCTAssertEqual(AColor.alpha(AColor.TRANSPARENT), 0)
        XCTAssertEqual(AColor.red(AColor.WHITE), 255)
        XCTAssertEqual(AColor.blue(AColor.BLUE), 255)
        XCTAssertEqual(AColor.green(AColor.BLUE), 0)
        // A non-sign-extended value is read as its low 32 bits.
        XCTAssertEqual(AColor.alpha(0xFF00_0000), 255)
        XCTAssertEqual(AColor.red(0xFF12_3456), 0x12)
    }

    func testColorToHSVMatchesSkia() {
        func check(_ color: Int, _ h: UInt32, _ s: UInt32, _ v: UInt32, file: StaticString = #filePath, line: UInt = #line) {
            var hsv: [Float] = [0, 0, 0]
            AColor.colorToHSV(color, &hsv)
            XCTAssertEqual(hsv[0].bitPattern, h, "hue", file: file, line: line)
            XCTAssertEqual(hsv[1].bitPattern, s, "saturation", file: file, line: line)
            XCTAssertEqual(hsv[2].bitPattern, v, "value", file: file, line: line)
        }
        check(AColor.rgb(43, 119, 196), 0x4352_3232, 0x3f47_d634, 0x3f44_c4c5)    // 210.19608, 0.7806122, 0.76862746
        check(AColor.rgb(232, 137, 31), 0x41fd_2263, 0x3f5d_cb09, 0x3f68_e8e9)    // 31.64179
        check(AColor.rgb(181, 66, 146), 0x439f_2164, 0x3f22_a6e5, 0x3f35_b5b6)    // 318.26086 (negative hue + 360)
        check(AColor.rgb(35, 145, 94), 0x4318_2e8c, 0x3f42_34f7, 0x3f11_9192)     // 152.18182
        check(AColor.rgb(255, 0, 128), 0x43a4_f0f1, 0x3f80_0000, 0x3f80_0000)     // 329.88235, 1, 1
        check(AColor.rgb(10, 10, 10), 0, 0, 0x3d20_a0a1)                          // grey: hue and saturation 0
        check(AColor.rgb(200, 250, 90), 0x429d_8000, 0x3f23_d70a, 0x3f7a_fafb)    // 78.75
        // Alpha is ignored.
        var a: [Float] = [0, 0, 0], b: [Float] = [0, 0, 0]
        AColor.colorToHSV(argbInt(0x002B77C4), &a)
        AColor.colorToHSV(argbInt(0xFF2B77C4), &b)
        XCTAssertEqual(a, b)
    }

    func testHSVToColor() {
        XCTAssertEqual(AColor.HSVToColor([210, 0.5, 0.8]), -10053172)
        XCTAssertEqual(AColor.HSVToColor([0, 0, 0.5]), -8355712)
        XCTAssertEqual(AColor.HSVToColor(0x40, [0, 0, 1]), argbInt(0x40FFFFFF))
    }

    func testColorStateList() {
        let blue = argbInt(0xff2587d6), gray = argbInt(0xff879baa)
        // FamilyFormStyle's input-face stroke: focused -> blue, otherwise gray.
        let list = AColorStateList([[AStateSet.state_focused], []], [blue, gray])
        XCTAssertTrue(list.isStateful)
        XCTAssertEqual(list.defaultColor, gray)
        XCTAssertEqual(list.getColorForState([AStateSet.state_enabled, AStateSet.state_focused], 0), blue)
        XCTAssertEqual(list.getColorForState([AStateSet.state_enabled], 0), gray)
        XCTAssertEqual(list.getColorForState([], 0), gray)
        XCTAssertEqual(list.getColorForState(nil, 7), gray)
        XCTAssertTrue(list.isOpaque)

        // Negative ids are must-not-match states; no wild card means the default argument is returned.
        let negative = AColorStateList([[-AStateSet.state_enabled], [AStateSet.state_pressed]], [AColor.RED, AColor.GREEN])
        XCTAssertEqual(negative.getColorForState([], 5), AColor.RED)
        XCTAssertEqual(negative.getColorForState([AStateSet.state_enabled], 5), 5)
        XCTAssertEqual(negative.getColorForState([AStateSet.state_enabled, AStateSet.state_pressed], 5), AColor.GREEN)
        XCTAssertEqual(negative.defaultColor, AColor.RED)

        let single = AColorStateList.valueOf(argbInt(0x80112233))
        XCTAssertFalse(single.isStateful)
        XCTAssertFalse(single.isOpaque)
        XCTAssertEqual(single.defaultColor, argbInt(0x80112233))
        XCTAssertEqual(single.getColorForState([AStateSet.state_pressed], 0), argbInt(0x80112233))
        XCTAssertEqual(single.withAlpha(0xFF).defaultColor, argbInt(0xFF112233))

        XCTAssertTrue(AStateSet.stateSetMatches([], [AStateSet.state_pressed]))
        XCTAssertTrue(AStateSet.stateSetMatches([AStateSet.state_pressed, 0, AStateSet.state_focused], [AStateSet.state_pressed]))
        XCTAssertFalse(AStateSet.stateSetMatches([AStateSet.state_pressed], [AStateSet.state_enabled, 0, AStateSet.state_pressed]))
    }

    // MARK: - Rect, RectF, PointF

    func testRect() {
        let r = ARect(1, 2, 4, 10)
        XCTAssertEqual(r.width(), 3)
        XCTAssertEqual(r.height(), 8)
        XCTAssertEqual(r.centerX(), 2)               // (1 + 4) >> 1
        XCTAssertEqual(r.exactCenterX(), 2.5)
        XCTAssertEqual(r.centerY(), 6)
        XCTAssertEqual(ARect(-3, 0, 0, 0).centerX(), -2)   // arithmetic shift: (-3 + 0) >> 1
        XCTAssertTrue(r.contains(1, 2))
        XCTAssertFalse(r.contains(4, 2))             // right edge excluded
        XCTAssertFalse(ARect(5, 5, 5, 9).contains(5, 6))
        XCTAssertTrue(ARect(5, 5, 5, 9).isEmpty())
        XCTAssertEqual(ARect(0, 0, 10, 10), ARect(0, 0, 10, 10))
        let i = ARect(0, 0, 10, 10)
        XCTAssertTrue(i.intersect(5, 5, 20, 20))
        XCTAssertEqual(i, ARect(5, 5, 10, 10))
        XCTAssertFalse(ARect(0, 0, 10, 10).intersect(10, 0, 20, 10))   // touching edges do not intersect
        let u = ARect()
        u.union(ARect(3, 3, 6, 6))
        XCTAssertEqual(u, ARect(3, 3, 6, 6))         // union into an empty rect takes the other rect
        u.union(1, 7)
        XCTAssertEqual(u, ARect(1, 3, 6, 7))
        let o = ARect(1, 1, 3, 3)
        o.offsetTo(10, 20)
        XCTAssertEqual(o, ARect(10, 20, 12, 22))
        o.inset(1, -1)
        XCTAssertEqual(o, ARect(11, 19, 11, 23))
        XCTAssertEqual(ARect(1, 2, 3, 4).description, "Rect(1, 2 - 3, 4)")
    }

    func testRectF() {
        let r = ARectF(0.5, 1.5, 4.5, 9.5)
        XCTAssertEqual(r.width(), 4)
        XCTAssertEqual(r.height(), 8)
        XCTAssertEqual(r.centerX(), 2.5)
        XCTAssertEqual(r.centerY(), 5.5)
        XCTAssertTrue(r.contains(0.5, 1.5))
        XCTAssertFalse(r.contains(4.5, 5))
        XCTAssertFalse(r.isEmpty())
        XCTAssertTrue(ARectF(1, 1, 1, 2).isEmpty())
        // NaN coordinates: `left >= right || top >= bottom` is false, so not empty (Android).
        XCTAssertFalse(ARectF(Float.nan, 0, 1, 1).isEmpty())
        XCTAssertEqual(ARectF(0, 0, 1, 1), ARectF(0, 0, 1, 1))
        XCTAssertEqual(ARectF(-0.0, 0, 1, 1), ARectF(0, 0, 1, 1))      // primitive float ==
        XCTAssertNotEqual(ARectF(Float.nan, 0, 1, 1), ARectF(Float.nan, 0, 1, 1))

        let inset = ARectF(0, 0, 10, 10)
        inset.inset(1.5, 2)
        XCTAssertEqual(inset, ARectF(1.5, 2, 8.5, 8))
        inset.offset(-1.5, 1)
        XCTAssertEqual(inset, ARectF(0, 3, 7, 9))

        let u = ARectF(0, 0, 2, 2)
        u.union(ARectF(5, -1, 6, 1))
        XCTAssertEqual(u, ARectF(0, -1, 6, 2))
        u.union(ARectF(3, 3, 3, 9))                  // empty rect: ignored
        XCTAssertEqual(u, ARectF(0, -1, 6, 2))

        let i = ARectF(0, 0, 10, 10)
        XCTAssertTrue(i.intersect(ARectF(2, -5, 4, 5)))
        XCTAssertEqual(i, ARectF(2, 0, 4, 5))
        XCTAssertTrue(ARectF.intersects(ARectF(0, 0, 1, 1), ARectF(0.5, 0.5, 2, 2)))
        XCTAssertFalse(ARectF.intersects(ARectF(0, 0, 1, 1), ARectF(1, 0, 2, 1)))

        let s = ARectF(5, 6, 1, 2)
        s.sort()
        XCTAssertEqual(s, ARectF(1, 2, 5, 6))
        let copy = ARectF(ARect(1, 2, 3, 4))
        XCTAssertEqual(copy, ARectF(1, 2, 3, 4))
    }

    func testRectFRoundUsesFastMathAndRoundOut() {
        // com.android.internal.util.FastMath.round on the JVM.
        XCTAssertEqual(ARectF.fastRound(0.5), 1)
        XCTAssertEqual(ARectF.fastRound(1.5), 2)
        XCTAssertEqual(ARectF.fastRound(2.5), 3)
        XCTAssertEqual(ARectF.fastRound(-0.5), 0)
        XCTAssertEqual(ARectF.fastRound(-1.5), -1)
        XCTAssertEqual(ARectF.fastRound(-2.5), -2)
        XCTAssertEqual(ARectF.fastRound(0.49999997), 0)
        XCTAssertEqual(ARectF.fastRound(2.4999998), 2)
        XCTAssertEqual(ARectF.fastRound(1e10), 1410065408)   // (int) of the long result wraps like Java
        let dst = ARect()
        ARectF(0.5, -0.5, 2.5, -1.5).round(dst)
        XCTAssertEqual(dst, ARect(1, 0, 3, -1))
        ARectF(0.2, -0.2, 2.2, 3.0).roundOut(dst)
        XCTAssertEqual(dst, ARect(0, -1, 3, 3))
    }

    func testPointF() {
        var p = APointF(3, 4)
        XCTAssertEqual(p.length(), 5)
        p.offset(1, -1)
        XCTAssertEqual(p, APointF(4, 3))
        p.negate()
        XCTAssertEqual(p, APointF(-4, -3))
        // PointF.equals(Object) uses Float.compare: NaN equals NaN, 0.0 differs from -0.0.
        XCTAssertEqual(APointF(Float.nan, 1), APointF(Float.nan, 1))
        XCTAssertNotEqual(APointF(0, 0), APointF(-0.0, 0))
        // PointF.equals(x, y) uses primitive ==.
        XCTAssertTrue(APointF(0, 0).equals(-0.0, 0))
        XCTAssertFalse(APointF(Float.nan, 0).equals(Float.nan, 0))
        XCTAssertEqual(APointF(), APointF(0, 0))
    }

    // MARK: - Matrix

    private func values(_ m: AMatrix) -> [Float] {
        var v = [Float](repeating: 0, count: 9)
        m.getValues(&v)
        return v
    }

    func testMatrixScaleThenPostTranslate() {
        // TripleShotCourtView.applyBackgroundMatrix: setScale(...) then postTranslate(...)
        let m = AMatrix()
        m.setScale(2, 3)
        m.postTranslate(10, 20)
        XCTAssertEqual(values(m), [2, 0, 10, 0, 3, 20, 0, 0, 1])
        var pts: [Float] = [1, 1, -2, 0.5]
        m.mapPoints(&pts)
        XCTAssertEqual(pts, [12, 23, 6, 21.5])
        let r = ARectF()
        XCTAssertTrue(m.mapRect(r, ARectF(0, 0, 4, -2)))
        XCTAssertEqual(r, ARectF(10, 14, 18, 20))
        XCTAssertFalse(m.isIdentity())
        XCTAssertTrue(m.isAffine())
        XCTAssertTrue(m.rectStaysRect())
        let t = m.cgAffineTransform
        XCTAssertEqual(t.a, 2); XCTAssertEqual(t.d, 3); XCTAssertEqual(t.tx, 10); XCTAssertEqual(t.ty, 20)
        XCTAssertEqual(t.b, 0); XCTAssertEqual(t.c, 0)
    }

    func testMatrixPreAndPostOperations() {
        let a = AMatrix()
        a.setTranslate(10, 20)
        a.preScale(2, 3)
        XCTAssertEqual(values(a), [2, 0, 10, 0, 3, 20, 0, 0, 1])

        let b = AMatrix()
        b.setTranslate(10, 20)
        b.postScale(2, 3)
        XCTAssertEqual(values(b), [2, 0, 20, 0, 3, 60, 0, 0, 1])

        let c = AMatrix()
        c.setScale(2, 2, 5, 5)
        XCTAssertEqual(values(c), [2, 0, -5, 0, 2, -5, 0, 0, 1])
        c.setScale(1, 1, 5, 5)
        XCTAssertTrue(c.isIdentity())

        let d = AMatrix()
        d.setScale(2, 4)
        d.preTranslate(1, 1)
        XCTAssertEqual(values(d), [2, 0, 2, 0, 4, 4, 0, 0, 1])

        // Rotation by multiples of 90 degrees is exact (Skia snaps sin/cos to 0).
        let r = AMatrix()
        r.setRotate(90)
        XCTAssertEqual(values(r), [0, -1, 0, 1, 0, 0, 0, 0, 1])
        var p: [Float] = [1, 0]
        r.mapPoints(&p)
        XCTAssertEqual(p, [0, 1])                     // clockwise on screen (y down)
        let rr = ARectF()
        XCTAssertTrue(r.mapRect(rr, ARectF(0, 0, 10, 20)))
        XCTAssertEqual(rr, ARectF(-20, 0, 0, 10))
        let half = AMatrix()
        half.setRotate(180, 5, 5)
        var q: [Float] = [0, 0]
        half.mapPoints(&q)
        XCTAssertEqual(q, [10, 10])
        let post = AMatrix()
        post.setTranslate(3, 4)
        post.postRotate(90)
        XCTAssertEqual(values(post), [0, -1, -4, 1, 0, 3, 0, 0, 1])

        XCTAssertEqual(AMatrix(), AMatrix())
        let e = AMatrix(); e.setValues([1, 0, 0, 0, 1, 0, 0, 0, 1])
        XCTAssertTrue(e.isIdentity())
    }

    func testMatrixInvert() {
        let m = AMatrix()
        m.setScale(2, 4)
        m.postTranslate(6, 8)
        let inv = AMatrix()
        XCTAssertTrue(m.invert(inv))
        XCTAssertEqual(values(inv), [0.5, 0, -3, 0, 0.25, -2, 0, 0, 1])

        // General affine: SkMatrix::ComputeInv in double, rounded to float.
        let g = AMatrix()
        g.setValues([1, 2, 3, 4, 5, 6, 0, 0, 1])
        let gi = AMatrix()
        XCTAssertTrue(g.invert(gi))
        let v = values(gi)
        XCTAssertEqual(v[0].bitPattern, 0xbfd5_5555)   // -1.6666666
        XCTAssertEqual(v[1].bitPattern, 0x3f2a_aaab)   // 0.6666667
        XCTAssertEqual(v[2].bitPattern, 0x3f80_0000)   // 1
        XCTAssertEqual(v[3].bitPattern, 0x3faa_aaab)   // 1.3333334
        XCTAssertEqual(v[4].bitPattern, 0xbeaa_aaab)   // -0.33333334
        XCTAssertEqual(v[5].bitPattern, 0xc000_0000)   // -2
        XCTAssertEqual(Array(v[6...]), [0, 0, 1])

        // Singular: false, inverse untouched.
        let s = AMatrix()
        s.setScale(0, 1)
        let untouched = AMatrix()
        untouched.setTranslate(7, 7)
        XCTAssertFalse(s.invert(untouched))
        XCTAssertEqual(values(untouched), [1, 0, 7, 0, 1, 7, 0, 0, 1])
    }

    func testMatrixRectToRect() {
        let m = AMatrix()
        XCTAssertTrue(m.setRectToRect(ARectF(0, 0, 100, 50), ARectF(0, 0, 300, 300), .CENTER))
        XCTAssertEqual(values(m), [3, 0, 0, 0, 3, 75, 0, 0, 1])
        XCTAssertTrue(m.setRectToRect(ARectF(0, 0, 100, 50), ARectF(0, 0, 300, 300), .FILL))
        XCTAssertEqual(values(m), [3, 0, 0, 0, 6, 0, 0, 0, 1])
        XCTAssertTrue(m.setRectToRect(ARectF(0, 0, 100, 50), ARectF(10, 10, 310, 310), .END))
        XCTAssertEqual(values(m), [3, 0, 10, 0, 3, 160, 0, 0, 1])
        XCTAssertFalse(m.setRectToRect(ARectF(0, 0, 0, 50), ARectF(0, 0, 300, 300), .FILL))
        XCTAssertTrue(m.isIdentity())
    }

    // MARK: - Typeface, Paint

    func testTypefaceCachingAndStyles() {
        XCTAssertTrue(ATypeface.SANS_SERIF === ATypeface.DEFAULT)
        XCTAssertTrue(ATypeface.create(ATypeface.DEFAULT, ATypeface.BOLD) === ATypeface.DEFAULT_BOLD)
        XCTAssertTrue(ATypeface.create(nil as ATypeface?, ATypeface.NORMAL) === ATypeface.DEFAULT)
        XCTAssertTrue(ATypeface.create("no-such-family", ATypeface.NORMAL) === ATypeface.DEFAULT)
        XCTAssertTrue(ATypeface.defaultFromStyle(ATypeface.BOLD) === ATypeface.DEFAULT_BOLD)
        XCTAssertTrue(ATypeface.DEFAULT_BOLD.isBold)
        XCTAssertEqual(ATypeface.DEFAULT_BOLD.style, ATypeface.BOLD)
        XCTAssertEqual(ATypeface.DEFAULT_BOLD.weight, 700)
        XCTAssertFalse(ATypeface.DEFAULT.isBold)
        let medium = ATypeface.create("sans-serif-medium", ATypeface.NORMAL)
        XCTAssertEqual(medium.weight, 500)
        XCTAssertEqual(medium.style, ATypeface.NORMAL)
        XCTAssertEqual(ATypeface.create(medium, ATypeface.BOLD).weight, 800)   // base weight + 300
        XCTAssertTrue(ATypeface.create(medium, ATypeface.BOLD) === ATypeface.create(medium, ATypeface.BOLD))
        XCTAssertEqual(ATypeface.create(nil as ATypeface?, 500, false).style, ATypeface.NORMAL)
        XCTAssertEqual(ATypeface.create(nil as ATypeface?, 600, true).style, ATypeface.BOLD_ITALIC)
        // An invalid style becomes NORMAL.
        XCTAssertTrue(ATypeface.create(ATypeface.DEFAULT, 7) === ATypeface.DEFAULT)
        XCTAssertEqual(ATypeface.DEFAULT_BOLD.uiFont(16).pointSize, 16)
    }

    func testPaintDefaultsAndFlags() {
        // Android 12: ANTI_ALIAS for new Paint(), plus DEV_KERN | EMBEDDED_BITMAP | FILTER_BITMAP always.
        XCTAssertEqual(APaint().flags, 1283)
        XCTAssertEqual(APaint(APaint.ANTI_ALIAS_FLAG).flags, 1283)
        XCTAssertEqual(APaint(0).flags, 1282)
        let p = APaint(APaint.ANTI_ALIAS_FLAG)
        XCTAssertEqual(p.color, AColor.BLACK)
        XCTAssertEqual(p.style, .FILL)
        XCTAssertEqual(p.strokeWidth, 0)
        XCTAssertEqual(p.strokeMiter, 4)
        XCTAssertEqual(p.textSize, 12)
        XCTAssertEqual(p.textAlign, .LEFT)
        XCTAssertTrue(p.isAntiAlias)
        XCTAssertTrue(p.isFilterBitmap)
        p.isFakeBoldText = true
        XCTAssertEqual(p.flags & APaint.FAKE_BOLD_TEXT_FLAG, APaint.FAKE_BOLD_TEXT_FLAG)
        p.flags = p.flags | APaint.UNDERLINE_TEXT_FLAG
        XCTAssertTrue(p.isUnderlineText)

        p.strokeWidth = 3
        p.strokeWidth = -1                               // ignored like Skia
        XCTAssertEqual(p.strokeWidth, 3)
        p.textSize = -2                                  // ignored (Paint.cpp: textSize >= 0)
        XCTAssertEqual(p.textSize, 12)

        p.setShadowLayer(3, 0, 2, AColor.BLACK)
        XCTAssertTrue(p.hasShadowLayer())
        p.setShadowLayer(0, 0, 0, AColor.TRANSPARENT)    // radius 0 removes the shadow
        XCTAssertFalse(p.hasShadowLayer())

        let copy = APaint(p)
        XCTAssertEqual(copy.color, p.color)
        XCTAssertEqual(copy.flags, p.flags)
        XCTAssertEqual(copy.strokeWidth, 3)
    }

    func testPaintAlphaJavaAndNativeSides() {
        // Paint.setAlpha / getAlpha / getColor of Android 12 on the JVM (Color.pack of `a * (1f / 255)`), and
        // the native SkPaint alpha (U8CPU, pinned to 0...255) that is drawn.
        func check(_ a: Int, _ getAlpha: Int, _ getColor: Int, _ native: Int, file: StaticString = #filePath, line: UInt = #line) {
            let p = APaint()
            p.color = argbInt(0xFF112233)
            p.alpha = a
            XCTAssertEqual(p.alpha, getAlpha, "getAlpha", file: file, line: line)
            XCTAssertEqual(p.color, getColor, "getColor", file: file, line: line)
            XCTAssertEqual(p.kgNativeAlpha, native, "native alpha", file: file, line: line)
        }
        check(0, 0, 1122867, 0)
        check(1, 1, 17900083, 1)
        check(127, 127, 2131829299, 127)
        check(128, 128, -2146360781, 128)
        check(254, 254, -32431565, 254)
        check(255, 255, -15654349, 255)
        check(256, 0, 1122867, 255)
        check(300, 44, 739320371, 255)
        check(-1, 0, 1122867, 255)
        check(-10, 247, -149872077, 255)
        check(511, 255, -15654349, 255)
        check(1000, 232, -401530317, 255)
        // setColor resets both sides.
        let p = APaint()
        p.alpha = 300
        p.color = argbInt(0x40FFFFFF)
        XCTAssertEqual(p.alpha, 0x40)
        XCTAssertEqual(p.kgNativeAlpha, 0x40)
        XCTAssertEqual(p.kgDrawColor, argbInt(0x40FFFFFF))
        p.setARGB(0x20, 1, 2, 3)
        XCTAssertEqual(p.color, argbInt(0x20010203))
        XCTAssertEqual(APaint(p).kgNativeAlpha, 0x20)
    }

    func testFakeBoldGrowthMatchesFreeTypeEmbolden() {
        // SK_USE_FREETYPE_EMBOLDEN (Android's Skia): strength = ppem(26.6) / 34, FT_Outline_Embolden moves the
        // outline by strength / 2 per side and shifts it by the same amount: growth = 2 * (strength / 2) / 64 px.
        func growth(_ size: Float) -> UInt32 {
            let p = APaint()
            p.textSize = size
            return p.kgFakeBoldExtra().bitPattern
        }
        XCTAssertEqual(growth(8), 0x3e60_0000)     // 512 / 34 = 15 -> 14 / 64 = 0.21875
        XCTAssertEqual(growth(9), 0x3e80_0000)     // 576 / 34 = 16 -> 0.25
        XCTAssertEqual(growth(27), 0x3f48_0000)    // 1728 / 34 = 50 -> 0.78125
        XCTAssertEqual(growth(36), 0x3f84_0000)    // 2304 / 34 = 67 -> 66 / 64 = 1.03125
        XCTAssertEqual(growth(48), 0x3fb4_0000)    // 3072 / 34 = 90 -> 1.40625
        XCTAssertEqual(KitGraphics.fakeBoldGrowth(0), 0)
    }

    func testTextMeasurementConventions() {
        let p = APaint(APaint.ANTI_ALIAS_FLAG)
        p.textSize = 48
        XCTAssertEqual(p.measureText(""), 0)
        let w = p.measureText("Swish")
        XCTAssertGreaterThan(w, 0)
        XCTAssertEqual(w, w.rounded(.up))         // Paint.measureText rounds up
        let fm = p.fontMetrics
        XCTAssertLessThan(fm.ascent, 0)
        XCTAssertGreaterThan(fm.descent, 0)
        XCTAssertLessThanOrEqual(fm.top, fm.ascent)
        XCTAssertGreaterThanOrEqual(fm.bottom, fm.descent)
        XCTAssertEqual(p.getFontMetrics(nil), fm.descent - fm.ascent + fm.leading)
        let bounds = ARect()
        p.getTextBounds("Swish", 0, 5, bounds)
        XCTAssertLessThan(bounds.top, 0)          // above the baseline
        XCTAssertGreaterThan(bounds.right, bounds.left)
        p.getTextBounds("", 0, 0, bounds)
        XCTAssertEqual(bounds, ARect(0, 0, 0, 0))
        // Minikin letter spacing (not rounded): letterSpacing * size * scaleX px per cluster (0.1 * 30 = 3 px).
        let q = APaint(APaint.ANTI_ALIAS_FLAG)
        q.textSize = 30
        let plain = q.kgAdvance("abc")
        q.letterSpacing = 0.1
        XCTAssertEqual(q.kgAdvance("abc") - plain, 9, accuracy: 0.01)
    }

    func testMinikinLaysTextOutAtTheIntegralSize() {
        // MinikinUtils::prepareMinikinPaint: size = (int) textSize unless LINEAR_TEXT_FLAG.
        let a = APaint()
        a.textSize = 30
        let b = APaint()
        b.textSize = 30.75
        XCTAssertEqual(b.kgLayoutSize, 30)
        XCTAssertEqual(b.measureText("Swish Swish"), a.measureText("Swish Swish"))
        let ra = ARect(), rb = ARect()
        a.getTextBounds("Swish", 0, 5, ra)
        b.getTextBounds("Swish", 0, 5, rb)
        XCTAssertEqual(ra, rb)
        b.isLinearText = true
        XCTAssertEqual(b.kgLayoutSize, 30.75)
        XCTAssertGreaterThan(b.measureText("Swish Swish"), a.measureText("Swish Swish"))
        // Letter spacing uses Minikin's size too.
        let c = APaint()
        c.textSize = 30.75
        c.letterSpacing = 0.1
        XCTAssertEqual(c.kgLetterSpacing().perCluster, CGFloat(Double(Float(0.1)) * 30), accuracy: 1e-9)
    }

    // MARK: - Path

    func testPathShapesAndBounds() {
        let p = APath()
        XCTAssertTrue(p.isEmpty)
        p.addRect(ARectF(1, 2, 5, 9), .CW)
        let b = ARectF()
        p.computeBounds(b, true)
        XCTAssertEqual(b, ARectF(1, 2, 5, 9))
        XCTAssertFalse(p.isEmpty)
        p.reset()
        XCTAssertTrue(p.isEmpty)
        p.fillType = .EVEN_ODD
        p.reset()
        XCTAssertEqual(p.fillType, .EVEN_ODD)     // Android's reset keeps the fill type
        p.rewind()
        XCTAssertEqual(p.fillType, .WINDING)

        // lineTo on an empty path starts at (0, 0); after close the next segment starts at the contour start.
        let q = APath()
        q.lineTo(4, 4)
        q.computeBounds(b, true)
        XCTAssertEqual(b, ARectF(0, 0, 4, 4))
        let r = APath()
        r.moveTo(10, 10)
        r.lineTo(20, 10)
        r.close()
        r.rLineTo(0, 5)
        r.computeBounds(b, true)
        XCTAssertEqual(b, ARectF(10, 10, 20, 15))

        let c = APath()
        c.addCircle(10, 10, 5, .CW)
        c.computeBounds(b, true)
        XCTAssertEqual(b, ARectF(5, 5, 15, 15))
        let none = APath()
        none.addCircle(10, 10, 0, .CW)            // radius <= 0: nothing
        XCTAssertTrue(none.isEmpty)
        let rr = APath()
        rr.addRoundRect(ARectF(0, 0, 10, 4), 50, 50, .CW)   // radii scaled down to fit
        rr.computeBounds(b, true)
        XCTAssertEqual(b, ARectF(0, 0, 10, 4))
        rr.offset(5, -2)
        rr.computeBounds(b, true)
        XCTAssertEqual(b, ARectF(5, -2, 15, 2))
        // Per-corner radii (SkRRect::setRectRadii with scaling to fit).
        let radii = APath()
        radii.addRoundRect(ARectF(0, 0, 20, 10), [12, 12, 12, 12, 0, 0, 0, 0], .CW)
        radii.computeBounds(b, true)
        XCTAssertEqual(b, ARectF(0, 0, 20, 10))
    }

    func testPathParserLikeVectorDrawable() {
        let triangle = APathParser.createPathFromPathData("M10,6 L22,14 L10,22 Z")
        let b = ARectF()
        triangle.computeBounds(b, true)
        XCTAssertEqual(b, ARectF(10, 6, 22, 22))
        // '-' and a second '.' separate numbers and stay with the next one (PathParser.extract).
        let packed = APathParser.createPathFromPathData("M-1-2L3.5.5")
        packed.computeBounds(b, true)
        XCTAssertEqual(b, ARectF(-1, -2, 3.5, 0.5))
        let exponent = APathParser.createPathFromPathData("M1e1,2 l1e-1,0")
        exponent.computeBounds(b, true)
        XCTAssertEqual(b.left, 10)
        XCTAssertEqual(b.right, 10.1, accuracy: 1e-5)
        // The icon disc: two SVG arcs (Skia conics) spanning the 28 x 28 viewport.
        let disc = APathParser.createPathFromPathData("M14,0 A14,14 0,1 0,14 28 A14,14 0,1 0,14 0")
        disc.computeBounds(b, true)
        XCTAssertEqual(b.left, 0, accuracy: 1e-3)
        XCTAssertEqual(b.top, 0, accuracy: 1e-3)
        XCTAssertEqual(b.right, 28, accuracy: 1e-3)
        XCTAssertEqual(b.bottom, 28, accuracy: 1e-3)
    }

    // MARK: - Canvas into a bitmap

    private func bitmapCanvas(_ w: Int, _ h: Int) -> (ABitmap, ACanvas) {
        let b = ABitmap.createBitmap(w, h, .ARGB_8888)
        return (b, ACanvas(b))
    }

    func testCanvasSaveRestoreCounts() {
        let (_, canvas) = bitmapCanvas(10, 10)
        XCTAssertEqual(canvas.saveCount, 1)
        XCTAssertEqual(canvas.save(), 1)
        XCTAssertEqual(canvas.saveLayerAlpha(ARectF(0, 0, 5, 5), 128), 2)
        XCTAssertEqual(canvas.save(), 3)
        XCTAssertEqual(canvas.saveCount, 4)
        canvas.restoreToCount(2)
        XCTAssertEqual(canvas.saveCount, 2)
        canvas.restoreToCount(5)                  // a larger count does nothing
        XCTAssertEqual(canvas.saveCount, 2)
        canvas.restore()
        XCTAssertEqual(canvas.saveCount, 1)
        let noop = ACanvas.noop
        XCTAssertEqual(noop.save(), 1)
        XCTAssertEqual(noop.saveCount, 2)
        noop.restore()
        XCTAssertEqual(ACanvas.noop.saveCount, 1)     // every draw pass gets a fresh no-op canvas
        XCTAssertNil(noop.cgContext)
        XCTAssertFalse(canvas.isHardwareAccelerated)
        XCTAssertEqual(canvas.width, 10)
    }

    func testCanvasDrawsTopLeftOriginInPixels() {
        let (b, canvas) = bitmapCanvas(10, 10)
        let paint = APaint(APaint.ANTI_ALIAS_FLAG)
        paint.color = AColor.RED
        canvas.drawRect(0, 0, 10, 5, paint)
        XCTAssertEqual(b.getPixel(5, 2), AColor.RED)
        XCTAssertEqual(b.getPixel(5, 7), 0)
        // translate + scale with a pivot (Android: translate(px, py); scale; translate(-px, -py))
        canvas.save()
        canvas.scale(-1, 1, 5, 0)
        paint.color = AColor.BLUE
        canvas.drawRect(0, 5, 2, 10, paint)       // mirrored to x 8...10
        canvas.restore()
        XCTAssertEqual(b.getPixel(9, 7), AColor.BLUE)
        XCTAssertEqual(b.getPixel(0, 7), 0)
        XCTAssertFalse(canvas.clipRect(20, 20, 30, 30))   // outside: empty clip
    }

    func testClipRectIsNotAntiAliasedAndSnapsToPixels() {
        // SkCanvas::clipRect(rect, op) without anti-aliasing: device edges rounded with floor(x + 0.5).
        let (b, canvas) = bitmapCanvas(10, 4)
        XCTAssertTrue(canvas.clipRect(0.4, 0, 2.6, 4))    // -> [0, 3)
        canvas.drawColor(AColor.RED)
        XCTAssertEqual(b.getPixel(0, 1), AColor.RED)
        XCTAssertEqual(b.getPixel(2, 1), AColor.RED)
        XCTAssertEqual(b.getPixel(3, 1), 0)

        // getClipBounds: hwui maps the device clip bounds back without Skia's outset, then SkRect::round.
        let (_, c2) = bitmapCanvas(10, 10)
        let r = ARect()
        XCTAssertTrue(c2.getClipBounds(r))
        XCTAssertEqual(r, ARect(0, 0, 10, 10))
        c2.clipRect(1.2, 2.7, 5.5, 8.4)
        XCTAssertTrue(c2.getClipBounds(r))
        XCTAssertEqual(r, ARect(1, 3, 6, 8))
        c2.translate(1, 1)
        c2.getClipBounds(r)
        XCTAssertEqual(r, ARect(0, 2, 5, 7))
    }

    func testCanvasStrokeAndGradient() {
        let (b, canvas) = bitmapCanvas(20, 4)
        let paint = APaint(APaint.ANTI_ALIAS_FLAG)
        paint.shader = ALinearGradient(0, 0, 10, 0, AColor.RED, AColor.BLUE, .CLAMP)
        canvas.drawRect(0, 0, 20, 4, paint)
        XCTAssertEqual(b.getPixel(15, 1), AColor.BLUE)     // CLAMP beyond the end
        XCTAssertEqual(b.getPixel(19, 3), AColor.BLUE)
        XCTAssertGreaterThan(AColor.red(b.getPixel(0, 1)), 200)
        // The paint alpha modulates the shader.
        let (b2, c2) = bitmapCanvas(4, 4)
        let half = APaint()
        half.alpha = 128
        half.shader = ALinearGradient(0, 0, 1, 0, AColor.WHITE, AColor.WHITE, .CLAMP)
        c2.drawRect(0, 0, 4, 4, half)
        XCTAssertLessThanOrEqual(abs(AColor.alpha(b2.getPixel(2, 2)) - 128), 1)
    }

    func testGradientsInterpolatePremultipliedLikeHwui() {
        // hwui creates gradients with kInterpolateColorsInPremul_Flag: a fade from opaque red to TRANSPARENT
        // (0x00000000) keeps the red hue (unpremultiplied red stays 255) while the alpha falls linearly.
        let (b, canvas) = bitmapCanvas(100, 1)
        let paint = APaint()
        paint.shader = ALinearGradient(0, 0, 100, 0, AColor.RED, AColor.TRANSPARENT, .CLAMP)
        canvas.drawRect(0, 0, 100, 1, paint)
        let mid = b.getPixel(49, 0)              // t = 0.495
        XCTAssertGreaterThanOrEqual(AColor.red(mid), 250)
        XCTAssertLessThanOrEqual(abs(AColor.alpha(mid) - 129), 3)
        let quarter = b.getPixel(74, 0)          // t = 0.745
        XCTAssertGreaterThanOrEqual(AColor.red(quarter), 245)
        XCTAssertLessThanOrEqual(abs(AColor.alpha(quarter) - 65), 3)
        // The atmosphere's coloured lights: RadialGradient(argb(46, rgb), TRANSPARENT) keeps its colour too.
        let (b2, c2) = bitmapCanvas(40, 40)
        let light = APaint(APaint.ANTI_ALIAS_FLAG)
        light.shader = ARadialGradient(20, 20, 20, [AColor.argb(46, 70, 150, 255), AColor.TRANSPARENT], [0, 1], .CLAMP)
        c2.drawCircle(20, 20, 20, light)
        let ring = b2.getPixel(30, 20)           // half way out
        XCTAssertGreaterThan(AColor.alpha(ring), 0)
        XCTAssertGreaterThanOrEqual(AColor.blue(ring), 200)
    }

    func testShadowLayerGoesDownInBitmapCanvas() {
        // dy > 0 moves the shadow down on Android.
        let (b, canvas) = bitmapCanvas(40, 40)
        let paint = APaint(APaint.ANTI_ALIAS_FLAG)
        paint.color = AColor.WHITE
        paint.setShadowLayer(1, 0, 10, AColor.BLACK)
        canvas.drawRect(10, 5, 30, 15, paint)
        XCTAssertGreaterThan(AColor.alpha(b.getPixel(20, 22)), 100)   // 10 px below the rect
        XCTAssertEqual(AColor.alpha(b.getPixel(20, 1)), 0)            // nothing above
    }

    func testHwuiDrawRules() {
        let (b, canvas) = bitmapCanvas(10, 10)
        let paint = APaint()
        paint.style = .STROKE
        paint.strokeWidth = 4
        paint.strokeCap = .ROUND
        canvas.drawCircle(5, 5, 0, paint)          // radius <= 0: nothing (SkiaCanvas::drawCircle)
        XCTAssertEqual(b.getPixel(5, 5), 0)
        paint.style = .FILL
        canvas.drawArc(ARectF(10, 0, 0, 10), 0, 90, true, paint)   // unsorted oval: empty, nothing
        XCTAssertEqual(b.getPixel(7, 7), 0)
        canvas.drawArc(ARectF(0, 0, 10, 10), 0, 90, true, paint)   // clockwise quarter wedge
        XCTAssertEqual(b.getPixel(7, 7), AColor.BLACK)
        XCTAssertEqual(b.getPixel(2, 2), 0)
        // A paint alpha set out of range draws opaque (native pin), as on Android.
        let (b2, c2) = bitmapCanvas(2, 2)
        let opaque = APaint()
        opaque.color = AColor.GREEN
        opaque.alpha = 256
        c2.drawRect(0, 0, 2, 2, opaque)
        XCTAssertEqual(b2.getPixel(1, 1), AColor.GREEN)
    }

    func testBitmapPixels() {
        let b = ABitmap.createBitmap(3, 2, .ARGB_8888)
        XCTAssertTrue(b.isMutable)
        XCTAssertEqual(b.allocationByteCount, 24)
        XCTAssertEqual(b.getPixel(0, 0), 0)
        b.setPixel(1, 1, argbInt(0x80FF0000))
        XCTAssertEqual(b.getPixel(1, 1), argbInt(0x80FF0000))     // premultiplied storage, unpremultiplied read
        b.eraseColor(AColor.GREEN)
        var row = [Int](repeating: 0, count: 3)
        b.getPixels(&row, 0, 3, 0, 1, 3, 1)
        XCTAssertEqual(row, [AColor.GREEN, AColor.GREEN, AColor.GREEN])
        let scaled = ABitmap.createScaledBitmap(b, 6, 4, true)
        XCTAssertEqual(scaled.width, 6)
        XCTAssertEqual(scaled.height, 4)
        XCTAssertEqual(scaled.getPixel(5, 3), AColor.GREEN)
        let image = ABitmap.createBitmap([AColor.RED, AColor.BLUE], 2, 1, .ARGB_8888)
        XCTAssertFalse(image.isMutable)
        XCTAssertTrue(ABitmap.createBitmap(image, 0, 0, 2, 1) === image)   // unchanged immutable source is returned
        XCTAssertEqual(image.getPixel(1, 0), AColor.BLUE)
        b.recycle()
        XCTAssertTrue(b.isRecycled)
    }

    // MARK: - Drawables

    func testDimensionPixelSize() {
        // TypedValue.complexToDimensionPixelSize on the JVM at densities 2, 3 and 2.625.
        XCTAssertEqual(KitGraphics.dimensionPixelSize(dp: 14, density: 2), 28)
        XCTAssertEqual(KitGraphics.dimensionPixelSize(dp: 14, density: 3), 42)
        XCTAssertEqual(KitGraphics.dimensionPixelSize(dp: 14, density: 2.625), 37)
        XCTAssertEqual(KitGraphics.dimensionPixelSize(dp: 20, density: 2.625), 53)
        XCTAssertEqual(KitGraphics.dimensionPixelSize(dp: 11, density: 2.625), 29)
        XCTAssertEqual(KitGraphics.dimensionPixelSize(dp: 3, density: 2.625), 8)
        XCTAssertEqual(KitGraphics.dimensionPixelSize(dp: 36, density: 2.625), 95)
        XCTAssertEqual(KitGraphics.dimensionPixelSize(dp: 0.1, density: 2), 1)   // never 0 for a non-zero size
        XCTAssertEqual(KitGraphics.dimensionPixelSize(dp: 0.3, density: 3), 1)
        XCTAssertEqual(KitGraphics.dimensionPixelSize(dp: 0, density: 3), 0)
    }

    func testColorDrawableAlpha() {
        let d = AColorDrawable(argbInt(0x80FF0000))
        XCTAssertEqual(d.alpha, 0x80)
        d.alpha = 128
        // ColorDrawable.setAlpha: alpha += alpha >> 7; useAlpha = baseAlpha * alpha >> 8 (JVM vectors)
        XCTAssertEqual(d.color, 1090453504)       // 0x40FF0000
        XCTAssertEqual(d.alpha, 64)
        d.alpha = 255
        XCTAssertEqual(d.color, -2130771968)      // 0x80FF0000
        let e = AColorDrawable(argbInt(0xDDF2FFFC))
        e.alpha = 100
        XCTAssertEqual(e.color, 1458765820)
        XCTAssertEqual(d.intrinsicWidth, -1)
    }

    func testTintsAreSrcInColorFilters() {
        // ColorDrawable: the tint colour with the drawable colour's alpha.
        let (b, canvas) = bitmapCanvas(4, 4)
        let cd = AColorDrawable(argbInt(0x80FF0000))
        cd.setTint(AColor.GREEN)
        cd.setBounds(0, 0, 4, 4)
        cd.draw(canvas)
        XCTAssertEqual(b.getPixel(2, 2), argbInt(0x8000FF00))
        // GradientDrawable without solid colours: Android fills with `mAlpha << 24` under a tint, so a tinted
        // stroke-only shape shows the tint everywhere.
        let (b2, c2) = bitmapCanvas(10, 10)
        let stroke = AGradientDrawable()
        stroke.setStroke(2, AColor.BLUE)
        stroke.setBounds(0, 0, 10, 10)
        stroke.draw(c2)
        XCTAssertEqual(b2.getPixel(5, 5), 0)
        XCTAssertEqual(b2.getPixel(0, 5), AColor.BLUE)
        let (b3, c3) = bitmapCanvas(10, 10)
        stroke.setTint(AColor.GREEN)
        stroke.draw(c3)
        XCTAssertEqual(b3.getPixel(5, 5), AColor.GREEN)
        XCTAssertEqual(b3.getPixel(0, 5), AColor.GREEN)
    }

    func testGradientDrawableState() {
        let g = AGradientDrawable()
        XCTAssertEqual(g.shape, AGradientDrawable.RECTANGLE)
        XCTAssertEqual(g.intrinsicWidth, -1)
        XCTAssertNil(g.color)
        g.cornerRadius = -5
        XCTAssertEqual(g.cornerRadius, 0)
        let list = AColorStateList([[AStateSet.state_focused], []], [AColor.BLUE, AColor.GRAY])
        g.setColor(list)
        XCTAssertTrue(g.color === list)
        XCTAssertTrue(g.isStateful)
        XCTAssertTrue(g.setState([AStateSet.state_focused]))   // the fill colour changes
        XCTAssertFalse(g.setState([AStateSet.state_focused]))  // same state set: no change
        g.colors = [AColor.RED, AColor.BLUE]
        XCTAssertNil(g.color)                     // gradient colours replace the solid colour
        g.setSize(30, 40)
        XCTAssertEqual(g.intrinsicWidth, 30)
        XCTAssertEqual(g.intrinsicHeight, 40)
        XCTAssertFalse(g.getPadding(ARect()))
        g.alpha = 128
        XCTAssertEqual(g.alpha, 128)
    }

    func testGradientDrawableDrawsFillAndInsetStroke() {
        let (b, canvas) = bitmapCanvas(10, 10)
        let g = AGradientDrawable()
        g.setColor(AColor.RED)
        g.setStroke(2, AColor.BLUE)
        g.setBounds(0, 0, 10, 10)
        g.draw(canvas)
        XCTAssertEqual(b.getPixel(5, 5), AColor.RED)
        XCTAssertEqual(b.getPixel(0, 5), AColor.BLUE)          // the stroke lies inside the bounds
        XCTAssertEqual(b.getPixel(9, 5), AColor.BLUE)
        // Orientation gradient (BasketballJourneyActivity's TL_BR background).
        let (b2, c2) = bitmapCanvas(30, 30)
        let tlbr = AGradientDrawable(.TL_BR, [argbInt(0xffcef2eb), argbInt(0xffffdfaf), argbInt(0xffccd9ff)])
        tlbr.setBounds(0, 0, 30, 30)
        tlbr.draw(c2)
        XCTAssertEqual(AColor.alpha(b2.getPixel(15, 15)), 255)
        XCTAssertLessThanOrEqual(abs(AColor.red(b2.getPixel(0, 0)) - 0xce), 6)
        XCTAssertLessThanOrEqual(abs(AColor.blue(b2.getPixel(29, 29)) - 0xff), 6)
    }

    func testDrawableAlphaVectors() {
        // GradientDrawable.modulateAlpha and VectorDrawable's float alpha round trip (JVM vectors).
        let (_, canvas) = bitmapCanvas(4, 4)
        let g = AGradientDrawable()
        g.setColor(argbInt(0xDD112233))
        g.setBounds(0, 0, 4, 4)
        g.alpha = 128
        g.draw(canvas)                            // draws with alpha 0xDD * (128 + 0) >> 8 = 111, then restores
        XCTAssertEqual(g.color?.defaultColor, argbInt(0xDD112233))
        let v = AVectorDrawable(widthDp: 36, heightDp: 36, viewportWidth: 28, viewportHeight: 28, paths: [])
        for a in [0, 1, 77, 128, 200, 254, 255] {
            v.alpha = a
            XCTAssertEqual(v.alpha, a)
        }
    }

    func testInsetDrawable() {
        let inner = AGradientDrawable()
        inner.setSize(20, 10)
        let d = AInsetDrawable(inner, 7)
        XCTAssertEqual(d.intrinsicWidth, 34)
        XCTAssertEqual(d.intrinsicHeight, 24)
        let pad = ARect()
        XCTAssertTrue(d.getPadding(pad))
        XCTAssertEqual(pad, ARect(7, 7, 7, 7))
        d.setBounds(0, 0, 100, 50)
        XCTAssertEqual(inner.bounds, ARect(7, 7, 93, 43))
    }

    func testXmlDrawablePorts() {
        guard let idle = ContextCompat_getDrawable("triple_shot_answer_idle") as? AGradientDrawable else {
            return XCTFail("triple_shot_answer_idle is a shape drawable")
        }
        XCTAssertEqual(idle.cornerRadius, Float(KitGraphics.dimensionPixelSize(dp: 14)))
        XCTAssertEqual(idle.color?.defaultColor, argbInt(0xDDF2FFFC))
        XCTAssertEqual(idle.intrinsicWidth, -1)
        let panel = ContextCompat_getDrawable("triple_shot_panel") as? AGradientDrawable
        XCTAssertEqual(panel?.cornerRadius, Float(KitGraphics.dimensionPixelSize(dp: 20)))
        XCTAssertEqual(panel?.color?.defaultColor, argbInt(0xEFFFFFFF))
        let feedback = ContextCompat_getDrawable("triple_shot_feedback_panel") as? AGradientDrawable
        XCTAssertEqual(feedback?.cornerRadius, Float(KitGraphics.dimensionPixelSize(dp: 11)))
        XCTAssertEqual(feedback?.color?.defaultColor, argbInt(0xE6FFFDF5))
        XCTAssertFalse(ContextCompat_getDrawable("triple_shot_panel") === ContextCompat_getDrawable("triple_shot_panel"))
        let help = ContextCompat_getDrawable("triple_help")
        XCTAssertEqual(help?.intrinsicWidth, KitGraphics.dimensionPixelSize(dp: 36))
        XCTAssertEqual(help?.intrinsicHeight, KitGraphics.dimensionPixelSize(dp: 36))
        XCTAssertNotNil(ContextCompat_getDrawable("triple_pause"))
        XCTAssertNil(ContextCompat_getDrawable("no_such_drawable_name"))
    }

    func testVectorIconRendering() {
        guard let play = ContextCompat_getDrawable("triple_play") else { return XCTFail("triple_play") }
        let (b, canvas) = bitmapCanvas(28, 28)
        play.setBounds(0, 0, 28, 28)              // 1 px per viewport unit
        play.draw(canvas)
        XCTAssertEqual(b.getPixel(14, 14), argbInt(0xFF174575))    // inside the triangle
        XCTAssertEqual(b.getPixel(3, 14), argbInt(0xFFD1EDFF))     // disc, outside the triangle
        XCTAssertEqual(b.getPixel(0, 0), 0)                        // outside the disc
        // Half alpha applies to the whole icon (one layer), not per path.
        let (b2, c2) = bitmapCanvas(28, 28)
        play.alpha = 128
        play.draw(c2)
        let p = b2.getPixel(14, 14)
        XCTAssertLessThanOrEqual(abs(AColor.alpha(p) - 128), 1)
        XCTAssertLessThanOrEqual(abs(AColor.red(p) - 0x17), 2)
    }
}
