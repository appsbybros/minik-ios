import XCTest
import UIKit
@testable import MinikTripleShot

// Area kit-widgets: the pure parts of the widget layer — InputFilter.LengthFilter (UTF-16 units) and the
// DigitsKeyListener filter of number fields, TypedValue dimension conversions, the Java / Skia / FastMath rounding
// the text code relies on, the TextView measure arithmetic over Android's (Roboto) line metrics, ImageView scale-type
// matrices, ProgressBar sizes and value clamping, the Switch box size, Spinner selection callbacks, ArrayAdapter,
// TabLayout selection, the RecyclerView-lite binding, TextInputLayout's box colours and MDC helpers
// (ColorUtils.compositeColors, CollapsingTextHelper.blendARGB, AnimationUtils.lerp, FastOutSlowInInterpolator).
//
// The Android app has no unit tests for this layer. Vectors marked "JVM" come from the AOSP / androidx code run on the
// JVM (work/kit-widgets/run4/jgold/src/WidgetsGolden.java: LengthFilter, Number/DigitsKeyListener, FastMath.round,
// TypedValue.complexToDimensionPixelSize/Offset, ColorUtils.compositeColors, blendARGB, AnimationUtils.lerp, the real
// androidx FastOutSlowInInterpolator); the others are worked out by hand from the AOSP / material sources the port
// follows, each step noted next to the assertion. Sizes are Android pixels; density-dependent values are checked for
// the device's density (2 or 3).

private let WMATCH = AViewGroup.LayoutParams.MATCH_PARENT
private let WWRAP = AViewGroup.LayoutParams.WRAP_CONTENT

private func wExactly(_ size: Int) -> Int { AMeasureSpec.makeMeasureSpec(size, AMeasureSpec.EXACTLY) }
private func wAtMost(_ size: Int) -> Int { AMeasureSpec.makeMeasureSpec(size, AMeasureSpec.AT_MOST) }
private func wUnspecified() -> Int { AMeasureSpec.makeMeasureSpec(0, AMeasureSpec.UNSPECIFIED) }

private func wMeasureAndLayout(_ v: AView, _ widthSpec: Int, _ heightSpec: Int) {
    v.measure(widthSpec, heightSpec)
    v.layout(0, 0, v.measuredWidth, v.measuredHeight)
}

private func wFloat(_ bits: UInt32) -> Float { Float(bitPattern: bits) }

/// Records Spinner selection callbacks.
private final class WidgetsSelectionRecorder: AOnItemSelectedListener {
    var selected: [Int] = []
    var ids: [Int64] = []
    var nothing = 0
    func onItemSelected(_ parent: AAdapterView?, _ view: AView?, _ position: Int, _ id: Int64) {
        selected.append(position)
        ids.append(id)
    }
    func onNothingSelected(_ parent: AAdapterView?) { nothing += 1 }
}

/// Records TabLayout callbacks as "s<i>", "u<i>", "r<i>".
private final class WidgetsTabRecorder: AOnTabSelectedListener {
    var calls: [String] = []
    func onTabSelected(_ tab: ATabLayout.Tab) { calls.append("s\(tab.position)") }
    func onTabUnselected(_ tab: ATabLayout.Tab) { calls.append("u\(tab.position)") }
    func onTabReselected(_ tab: ATabLayout.Tab) { calls.append("r\(tab.position)") }
}

/// A RecyclerView holder / adapter like the leaderboard's.
private final class WidgetsRowHolder: ARecyclerView.ViewHolder {
    let label: ATextView
    init(_ view: ATextView) {
        label = view
        super.init(view)
    }
}

private final class WidgetsRowAdapter: ARecyclerView.Adapter<WidgetsRowHolder> {
    var items: [String] = []
    var created = 0
    var bound: [Int] = []
    override func onCreateViewHolder(_ parent: AViewGroup, _ viewType: Int) -> WidgetsRowHolder {
        created += 1
        let t = ATextView()
        t.layoutParams = AViewGroup.MarginLayoutParams(WMATCH, WWRAP)
        return WidgetsRowHolder(t)
    }
    override func onBindViewHolder(_ holder: WidgetsRowHolder, _ position: Int) {
        bound.append(position)
        holder.label.text = "#\(position + 1) \(items[position])"
    }
    override func getItemCount() -> Int { items.count }
}

final class AndroidKitWidgetsTests: XCTestCase {
    private let T0: Int64 = 1_000_000_000_000

    override func setUp() {
        super.setUp()
        AndroidKitTestLoop.frameIntervalNanos = 16_666_667
        AndroidKitTestLoop.install(startNanos: T0)
    }

    override func tearDown() {
        AndroidKitTestLoop.uninstall()
        super.tearDown()
    }

    private var density: Float { AWidgetEnv.density }

    // MARK: - InputFilter.LengthFilter (JVM)

    private struct LF {
        let max: Int, source: String, start: Int, end: Int, dest: String, dstart: Int, dend: Int, expected: String?
        init(_ max: Int, _ source: String, _ start: Int, _ end: Int, _ dest: String, _ dstart: Int, _ dend: Int, _ expected: String?) {
            self.max = max; self.source = source; self.start = start; self.end = end
            self.dest = dest; self.dstart = dstart; self.dend = dend; self.expected = expected
        }
    }

    func testLengthFilterMatchesAndroid() {
        // JVM: android.text.InputFilter.LengthFilter.filter. Lengths are UTF-16 units; a cut never leaves a lone high
        // surrogate (the 🏀 cases), and nil means "keep the source as it is".
        let cases: [LF] = [
            LF(5, "abc", 0, 3, "", 0, 0, nil),
            LF(5, "abcdef", 0, 6, "", 0, 0, "abcde"),
            LF(5, "abcdef", 0, 6, "xy", 1, 1, "abc"),
            LF(5, "abcdef", 0, 6, "xyzuv", 0, 5, "abcde"),
            LF(5, "abcdef", 0, 6, "xyzuv", 2, 2, ""),
            LF(5, "abcdef", 2, 6, "x", 1, 1, nil),
            LF(3, "a\u{1F3C0}b", 0, 4, "x", 1, 1, "a"),
            LF(2, "\u{1F3C0}", 0, 2, "x", 1, 1, ""),
            LF(1, "\u{1F3C0}", 0, 2, "", 0, 0, ""),
            LF(4, "\u{05E9}\u{05DC}\u{05D5}\u{05DD}\u{05D5}\u{05EA}", 0, 6, "", 0, 0, "\u{05E9}\u{05DC}\u{05D5}\u{05DD}"),
            LF(18, "Ab", 0, 2, "Sixteen chars...", 16, 16, nil),
            LF(6, "abcdefgh", 0, 8, "", 0, 0, "abcdef"),
            LF(24, "Sky Comets", 0, 10, "", 0, 0, nil),
            LF(0, "a", 0, 1, "", 0, 0, ""),
            LF(5000, "x", 0, 1, "hello", 5, 5, nil),
            LF(6, "AB12CD34", 0, 8, "", 0, 0, "AB12CD"),
            LF(3, "", 0, 0, "abc", 1, 2, nil),
            LF(4, "\u{1F3C0}\u{1F3C0}\u{1F3C0}", 0, 6, "", 0, 0, "\u{1F3C0}\u{1F3C0}"),
        ]
        for c in cases {
            let f = ALengthFilter(c.max)
            XCTAssertEqual(f.getMax(), c.max)
            let out = f.filter(c.source, c.start, c.end, c.dest, c.dstart, c.dend)
            XCTAssertEqual(out, c.expected, "LengthFilter(\(c.max)) \(c.source) [\(c.start),\(c.end)) into \(c.dest) [\(c.dstart),\(c.dend))")
        }
    }

    func testTextViewSetTextRunsTheFilters() {
        // TextView.setText: every filter on (text, 0, length, EMPTY_SPANNED, 0, 0); the result replaces the text.
        let t = ATextView()
        t.filters = [ALengthFilter(5)]
        t.setText("abcdefgh")
        XCTAssertEqual(t.text, "abcde")
        // A cut in the middle of a surrogate pair drops the whole pair.
        t.filters = [ALengthFilter(3)]
        t.setText("ab\u{1F3C0}")
        XCTAssertEqual(t.text, "ab")
        // The filters do not re-run on the current text when they change (setFilters).
        t.filters = [ALengthFilter(1)]
        XCTAssertEqual(t.text, "ab")
    }

    // MARK: - DigitsKeyListener filter of TYPE_CLASS_NUMBER (JVM)

    private struct DF {
        let sign: Bool, decimal: Bool, source: String, start: Int, end: Int, dest: String, dstart: Int, dend: Int, expected: String?
        init(_ sign: Bool, _ decimal: Bool, _ source: String, _ start: Int, _ end: Int, _ dest: String, _ dstart: Int, _ dend: Int,
             _ expected: String?) {
            self.sign = sign; self.decimal = decimal; self.source = source; self.start = start; self.end = end
            self.dest = dest; self.dstart = dstart; self.dend = dend; self.expected = expected
        }
    }

    func testDigitsKeyFilterMatchesAndroid() {
        // JVM: NumberKeyListener.filter + DigitsKeyListener.filter with the compatibility characters (no locale).
        let cases: [DF] = [
            DF(false, false, "123", 0, 3, "", 0, 0, nil),
            DF(false, false, "1a2", 0, 3, "", 0, 0, "12"),
            DF(false, false, "a", 0, 1, "12", 2, 2, ""),
            DF(false, false, "\u{0663}", 0, 1, "", 0, 0, ""),
            DF(false, false, "56", 0, 2, "", 0, 0, nil),
            DF(false, false, " 56 ", 0, 4, "", 0, 0, "56"),
            DF(false, false, "-5", 0, 2, "", 0, 0, "5"),
            DF(false, false, "1.5", 0, 3, "", 0, 0, "15"),
            DF(true, false, "-5", 0, 2, "", 0, 0, nil),
            DF(true, false, "5-", 0, 2, "", 0, 0, "5"),
            DF(true, false, "-", 0, 1, "5", 0, 0, nil),
            DF(true, false, "-", 0, 1, "5", 1, 1, ""),
            DF(true, false, "7", 0, 1, "-5", 0, 0, ""),
            DF(false, true, "1.5", 0, 3, "", 0, 0, nil),
            DF(false, true, "1.5.2", 0, 5, "", 0, 0, "15.2"),
            DF(false, true, ".", 0, 1, "1.5", 3, 3, ""),
            DF(true, true, "-1.5", 0, 4, "", 0, 0, nil),
            DF(true, true, "+.-", 0, 3, "", 0, 0, "+."),
        ]
        for c in cases {
            let f = AWDigitsKeyFilter(c.sign, c.decimal)
            XCTAssertEqual(f.filter(c.source, c.start, c.end, c.dest, c.dstart, c.dend), c.expected,
                           "digits(sign \(c.sign), decimal \(c.decimal)) \(c.source) into \(c.dest) [\(c.dstart),\(c.dend))")
        }
    }

    // MARK: - EditText input type / single line / filters (TextView.setInputType, setSingleLine)

    func testEditTextDefaultsToMultiLineText() {
        // TextView constructor for editable text: TYPE_CLASS_TEXT, not single line -> TYPE_TEXT_FLAG_MULTI_LINE.
        let e = AEditText()
        XCTAssertEqual(e.inputType, AInputType.TYPE_CLASS_TEXT | AInputType.TYPE_TEXT_FLAG_MULTI_LINE)
        XCTAssertFalse(e.isSingleLine)
        XCTAssertTrue(e.filters.isEmpty)
        // Widget.Material.Light.EditText: 18 sp (getDimensionPixelSize), gravity center_vertical | start.
        XCTAssertEqual(e.textSize, Float(ATypedValue.toDimensionPixelSize(ATypedValue.COMPLEX_UNIT_SP, 18)))
        XCTAssertEqual(e.gravity, AGravity.CENTER_VERTICAL | AGravity.START)
        // edit_text_material: insets 4 / 10 / 4 / 7 dp plus the nine-patch's 4 dp bottom padding.
        XCTAssertEqual(e.paddingLeft, aw_dpx(4))
        XCTAssertEqual(e.paddingTop, aw_dpx(10))
        XCTAssertEqual(e.paddingRight, aw_dpx(4))
        XCTAssertEqual(e.paddingBottom, aw_dpx(7) + aw_dpx(4))
    }

    func testNumberInputTypeIsSingleLineWithTheAutomaticLengthFilter() {
        // setInputType(TYPE_CLASS_NUMBER): not a multi-line type -> applySingleLine(true, true, true, true), which adds
        // LengthFilter(MAX_LENGTH_FOR_SINGLE_LINE_EDIT_TEXT = 5000) for editable text without a LengthFilter.
        let e = AEditText()
        e.inputType = AInputType.TYPE_CLASS_NUMBER
        XCTAssertTrue(e.isSingleLine)
        XCTAssertEqual(e.inputType, AInputType.TYPE_CLASS_NUMBER)
        XCTAssertEqual(e.filters.count, 1)
        XCTAssertEqual((e.filters.first as? ALengthFilter)?.getMax(), 5000)
        XCTAssertEqual(e.maxLines, 1)
    }

    func testSetSingleLineThenExplicitFiltersLikeTheLeagueTeamName() {
        // TripleShotLeagueFragment: setSingleLine(); setText(...); filters = arrayOf(LengthFilter(24)).
        let e = AEditText()
        e.setSingleLine()
        XCTAssertEqual(e.inputType & AInputType.TYPE_TEXT_FLAG_MULTI_LINE, 0)
        XCTAssertEqual((e.filters.first as? ALengthFilter)?.getMax(), 5000)
        e.setText("Sky Comets")
        e.filters = [ALengthFilter(24)]
        XCTAssertEqual(e.filters.count, 1)
        XCTAssertEqual((e.filters.first as? ALengthFilter)?.getMax(), 24)
        XCTAssertEqual(e.text, "Sky Comets")
        // A later setText is cut to 24 UTF-16 units.
        e.setText(String(repeating: "x", count: 30))
        XCTAssertEqual(e.text.utf16.count, 24)
    }

    func testTextCapWordsInputTypeIsSingleLine() {
        // TripleShotOnlineIdentity: setSingleLine(); ...; inputType = TEXT | CAP_WORDS (no multi-line flag).
        let e = AEditText()
        e.setSingleLine()
        e.inputType = AInputType.TYPE_CLASS_TEXT | AInputType.TYPE_TEXT_FLAG_CAP_WORDS
        XCTAssertTrue(e.isSingleLine)
        XCTAssertEqual(e.inputType, AInputType.TYPE_CLASS_TEXT | AInputType.TYPE_TEXT_FLAG_CAP_WORDS)
    }

    func testSetErrorPutsTheIconAtTheEnd() {
        // TextView.setError(CharSequence): indicator_input_error at its intrinsic size (20 dp) as the end drawable.
        // Drawables.applyErrorDrawableIfNeeded: the right side in LTR, the left side in RTL.
        let e = AEditText()
        e.inputType = AInputType.TYPE_CLASS_NUMBER
        let before = e.compoundPaddingEnd
        let startBefore = e.compoundPaddingStart
        e.error = "Try again."
        XCTAssertEqual(e.error, "Try again.")
        let iconWidth = AWErrorIconDrawable().intrinsicWidth
        XCTAssertEqual(iconWidth, AWMath.round(20 * density))
        XCTAssertEqual(e.compoundPaddingEnd, before + iconWidth)
        XCTAssertEqual(e.compoundPaddingStart, startBefore)
        e.error = nil
        XCTAssertNil(e.error)
        XCTAssertEqual(e.compoundPaddingEnd, before)
    }

    // MARK: - TypedValue (JVM)

    func testTypedValueDimensionPixelSizeAndOffset() {
        // JVM: TypedValue.applyDimension + complexToDimensionPixelSize / complexToDimensionPixelOffset.
        // (unit, value bits, density, pixel size, pixel offset)
        let cases: [(Int, UInt32, Int, Int, Int)] = [
            (1, 0x41600000, 2, 28, 28), (1, 0x3f000000, 2, 1, 1), (1, 0x41200000, 2, 20, 20), (1, 0x41780000, 2, 31, 31),
            (2, 0x41780000, 2, 31, 31), (2, 0x41480000, 2, 25, 25), (2, 0x41900000, 2, 36, 36), (1, 0x3dcccccd, 2, 1, 0),
            (1, 0xbdcccccd, 2, -1, 0), (1, 0x0, 2, 0, 0), (0, 0x40200000, 2, 3, 2), (0, 0xc0200000, 2, -3, -2),
            (1, 0x3faaa993, 2, 3, 2), (2, 0x3e800000, 2, 1, 0), (3, 0x41400000, 2, 53, 53), (5, 0x40000000, 2, 25, 25),
            (4, 0x3c23d70a, 2, 3, 3),
            (1, 0x41600000, 3, 42, 42), (1, 0x3f000000, 3, 2, 1), (1, 0x41200000, 3, 30, 30), (1, 0x41780000, 3, 47, 46),
            (2, 0x41780000, 3, 47, 46), (2, 0x41480000, 3, 38, 37), (2, 0x41900000, 3, 54, 54), (1, 0x3dcccccd, 3, 1, 0),
            (1, 0xbdcccccd, 3, -1, 0), (1, 0x0, 3, 0, 0), (0, 0x40200000, 3, 3, 2), (0, 0xc0200000, 3, -3, -2),
            (1, 0x3faaa993, 3, 4, 3), (2, 0x3e800000, 3, 1, 0), (3, 0x41400000, 3, 80, 80), (5, 0x40000000, 3, 38, 37),
            (4, 0x3c23d70a, 3, 5, 4),
        ]
        for (unit, bits, d, size, offset) in cases {
            let m = ADisplayMetrics(density: Float(d), widthPixels: 0, heightPixels: 0, scaledDensity: Float(d))
            let v = wFloat(bits)
            XCTAssertEqual(ATypedValue.toDimensionPixelSize(unit, v, m), size, "size unit \(unit) value \(v) density \(d)")
            XCTAssertEqual(ATypedValue.toDimensionPixelOffset(unit, v, m), offset, "offset unit \(unit) value \(v) density \(d)")
        }
        // sp = dp at font scale 1 (DESIGN 2.5).
        XCTAssertEqual(ATypedValue.applyDimension(ATypedValue.COMPLEX_UNIT_SP, 16), 16 * density)
    }

    // MARK: - Java / FastMath / Skia rounding (JVM)

    func testFastMathRound() {
        // JVM: com.android.internal.util.FastMath.round (round half up through a 24-bit fixed point).
        let cases: [(UInt32, Int)] = [
            (0x0, 0), (0x3f000000, 1), (0x3fc00000, 2), (0x40200000, 3), (0xbf000000, 0), (0xbfc00000, -1),
            (0x3effffff, 0), (0x419ccccd, 20), (0x423fffff, 48), (0x42610000, 56), (0xc0700000, -4),
            (0x49742400, 1000000), (0x42f6e979, 123), (0x3e800000, 0), (0x40f00000, 8),
        ]
        for (bits, expected) in cases {
            XCTAssertEqual(AWMath.fastRound(wFloat(bits)), expected, "FastMath.round(\(wFloat(bits)))")
        }
    }

    func testJavaConversions() {
        // JVM: (int) f, Math.round(f), (int) Math.ceil(f), (int) Math.floor(f).
        let cases: [(UInt32, Int, Int, Int, Int)] = [
            (0x0, 0, 0, 0, 0), (0x80000000, 0, 0, 0, 0), (0x3f000000, 0, 1, 1, 0), (0xbf000000, 0, 0, 0, -1),
            (0x3fc00000, 1, 2, 2, 1), (0xbfc00000, -1, -1, -1, -2), (0x40200000, 2, 3, 3, 2), (0x3effffff, 0, 0, 1, 0),
            (0x501502f9, 2147483647, 2147483647, 2147483647, 2147483647),
            (0xd01502f9, -2147483648, -2147483648, -2147483648, -2147483648),
            (0x7fc00000, 0, 0, 0, 0), (0x407fffd6, 3, 4, 4, 3), (0xc07fffd6, -3, -4, -3, -4),
        ]
        for (bits, i, r, c, f) in cases {
            let v = wFloat(bits)
            XCTAssertEqual(AWMath.javaInt(v), i, "(int) \(v)")
            XCTAssertEqual(AWMath.round(v), r, "Math.round(\(v))")
            XCTAssertEqual(AWMath.ceil(v), c, "ceil \(v)")
            XCTAssertEqual(AWMath.floor(v), f, "floor \(v)")
        }
    }

    // MARK: - Android line metrics (Roboto) and TextView measure

    /// Roboto (upm 2048: hhea ascent 1900, descent -500; head yMax 2163, yMin -555) at `size` px, as Skia reports it and
    /// Paint.getFontMetricsInt rounds it (top floor, ascent / descent round, bottom ceil).
    private func roboto(_ size: Float) -> (top: Int, ascent: Int, descent: Int, bottom: Int) {
        let top = (-Float(2163) / 2048 * size).rounded(.down)
        let ascent = (-Float(1900) / 2048 * size + 0.5).rounded(.down)
        let descent = (Float(500) / 2048 * size + 0.5).rounded(.down)
        let bottom = (Float(555) / 2048 * size).rounded(.up)
        return (Int(top), Int(ascent), Int(descent), Int(bottom))
    }

    func testRobotoIntMetricsAtTheDeviceSizes() {
        // 16 sp: 48 px at 3x (-50.70 / -44.53 / 11.72 / 13.01), 32 px at 2x (-33.80 / -29.69 / 7.81 / 8.67).
        let m48 = AWFontMetrics.intMetrics(48)
        XCTAssertEqual([m48.top, m48.ascent, m48.descent, m48.bottom], [-51, -45, 12, 14])
        let m32 = AWFontMetrics.intMetrics(32)
        XCTAssertEqual([m32.top, m32.ascent, m32.descent, m32.bottom], [-34, -30, 8, 9])
        // getFontMetricsInt(null) = round(descent - ascent + leading) of the float metrics: 56.25 -> 56, 37.5 -> 38.
        XCTAssertEqual(AWFontMetrics.fontSpacing(48), 56)
        XCTAssertEqual(AWFontMetrics.fontSpacing(32), 38)
        for size: Float in [24, 28, 36, 42, 45, 54, 57, 60, 84] {
            let m = AWFontMetrics.intMetrics(size)
            let r = roboto(size)
            XCTAssertEqual([m.top, m.ascent, m.descent, m.bottom], [r.top, r.ascent, r.descent, r.bottom], "size \(size)")
        }
    }

    func testSingleLineTextViewHeightIsTheFontBoxWithIncludeFontPadding() {
        // StaticLayout / BoringLayout: one line, includePad -> bottom - top; without it descent - ascent.
        let t = ATextView()
        t.textSize = 16
        t.text = "Hello"
        wMeasureAndLayout(t, wUnspecified(), wUnspecified())
        let r = roboto(t.textSize)
        XCTAssertEqual(t.measuredHeight, r.bottom - r.top)
        XCTAssertEqual(t.lineCount, 1)
        // Baseline: top padding of the first line is -top (includePad).
        XCTAssertEqual(t.getBaseline(), -r.top)
        t.includeFontPadding = false
        wMeasureAndLayout(t, wUnspecified(), wUnspecified())
        XCTAssertEqual(t.measuredHeight, r.descent - r.ascent)
        // Padding adds to both.
        t.setPadding(3, 5, 7, 11)
        wMeasureAndLayout(t, wUnspecified(), wUnspecified())
        XCTAssertEqual(t.measuredHeight, r.descent - r.ascent + 16)
    }

    func testWrapContentWidthIsTheWidestLinePlusPadding() {
        // TextView.onMeasure: a boring single line takes BoringLayout's ceil'd width; with '\n' the widest paragraph
        // (Layout.getDesiredWidthWithLimit), then the compound paddings.
        let t = ATextView()
        t.textSize = 18
        t.setPadding(10, 0, 20, 0)
        t.text = "Basketball"
        wMeasureAndLayout(t, wUnspecified(), wUnspecified())
        let single = t.measuredWidth
        XCTAssertEqual(t.lineCount, 1)
        XCTAssertEqual(single, AWMath.ceil(t.layout!.getLineWidth(0)) + 30)
        XCTAssertGreaterThan(single, 30)
        // The widest paragraph sets the width; the shorter lines do not add to it.
        t.text = "A\nBasketball\nBB"
        wMeasureAndLayout(t, wUnspecified(), wUnspecified())
        XCTAssertEqual(t.measuredWidth, single)
        XCTAssertEqual(t.lineCount, 3)
        // AT_MOST caps the width.
        wMeasureAndLayout(t, wAtMost(single / 2), wUnspecified())
        XCTAssertEqual(t.measuredWidth, single / 2)
    }

    func testMaxLinesCapsTheHeightAtTheLastVisibleLine() {
        // StaticLayout.out: line 0 above = top (includePad), below = descent; line 1 above = ascent; the last visible
        // line's mMaxLineHeight uses the font bottom (includePad). TextView.getDesiredHeight(cap) = that height.
        let t = ATextView()
        t.textSize = 16
        t.text = "A\nB\nC"
        let r = roboto(t.textSize)
        wMeasureAndLayout(t, wUnspecified(), wUnspecified())
        let line0 = r.descent - r.top
        let middle = r.descent - r.ascent
        let last = r.bottom - r.ascent
        XCTAssertEqual(t.measuredHeight, line0 + middle + last)
        t.maxLines = 2
        wMeasureAndLayout(t, wUnspecified(), wUnspecified())
        XCTAssertEqual(t.measuredHeight, line0 + (r.bottom - r.ascent))
        // minLines adds lineHeight per missing line (FastMath.round(fontSpacing * mult + add)).
        let one = ATextView()
        one.textSize = 16
        one.text = "A"
        one.minLines = 3
        wMeasureAndLayout(one, wUnspecified(), wUnspecified())
        XCTAssertEqual(one.lineHeight, AWMath.fastRound(Float(AWFontMetrics.fontSpacing(one.textSize))))
        XCTAssertEqual(one.measuredHeight, (r.bottom - r.top) + 2 * one.lineHeight)
    }

    func testLineSpacingExtraIsAddedBetweenLines() {
        // StaticLayout.out: extra = (int) ((below - above) * (mult - 1) + add + 0.5) on every line but the last.
        let t = ATextView()
        t.textSize = 16
        t.text = "A\nB"
        t.setLineSpacing(7.4, 1)
        let r = roboto(t.textSize)
        wMeasureAndLayout(t, wUnspecified(), wUnspecified())
        let line0 = r.descent - r.top
        let extra = AWMath.javaInt(Double(Float(7.4)) + 0.5)
        XCTAssertEqual(extra, 7)
        XCTAssertEqual(t.measuredHeight, line0 + extra + (r.bottom - r.ascent))
    }

    func testTextSizeIsSetInSpAndReadInPx() {
        let t = ATextView()
        t.textSize = 20
        XCTAssertEqual(t.textSize, 20 * density)
        t.setTextSize(ATypedValue.COMPLEX_UNIT_PX, 33)
        XCTAssertEqual(t.textSize, 33)
        t.setTextSize(ATypedValue.COMPLEX_UNIT_DIP, 10)
        XCTAssertEqual(t.textSize, 10 * density)
    }

    func testGravityGetsStartAndTopWhenAnAxisIsMissing() {
        // TextView.setGravity adds Gravity.START / Gravity.TOP for the unset axis.
        let t = ATextView()
        t.gravity = AGravity.CENTER_VERTICAL
        XCTAssertEqual(t.gravity, AGravity.CENTER_VERTICAL | AGravity.START)
        t.gravity = AGravity.END
        XCTAssertEqual(t.gravity, AGravity.END | AGravity.TOP)
    }

    func testTextDirectionLocaleFollowsTheDefaultLocale() {
        // TEXT_DIRECTION_LOCALE -> TextDirectionHeuristics.LOCALE: RTL for he / iw / ar / fa / ur.
        let units = Array("abc".utf16)
        let rtlLocale = AView.isRtlLanguage(ALocale.getDefault().language.lowercased())
        XCTAssertEqual(ATextDirectionHeuristic.LOCALE.isRtl(units, 0, units.count), rtlLocale)
        // FIRSTSTRONG_*: the first strong character decides; neutral text takes the default.
        let hebrew = Array("123 \u{05E9}\u{05DC}\u{05D5}\u{05DD}".utf16)
        XCTAssertTrue(ATextDirectionHeuristic.FIRSTSTRONG_LTR.isRtl(hebrew, 0, hebrew.count))
        let digits = Array("123".utf16)
        XCTAssertFalse(ATextDirectionHeuristic.FIRSTSTRONG_LTR.isRtl(digits, 0, digits.count))
        XCTAssertTrue(ATextDirectionHeuristic.FIRSTSTRONG_RTL.isRtl(digits, 0, digits.count))
    }

    // MARK: - ImageView scale types (ImageView.configureBounds)

    private func imageMatrix(_ scaleType: AImageView.ScaleType, _ dw: Int, _ dh: Int, _ vw: Int, _ vh: Int) -> [Float] {
        let iv = AImageView()
        let d = AGradientDrawable()
        d.setSize(dw, dh)
        iv.setImageDrawable(d)
        iv.scaleType = scaleType
        iv.measure(wExactly(vw), wExactly(vh))
        iv.layout(0, 0, vw, vh)
        var v = [Float](repeating: 0, count: 9)
        iv.imageMatrix.getValues(&v)
        return v
    }

    func testImageViewScaleTypeMatrices() {
        // 100 x 100 drawable in a 300 x 200 view.
        // CENTER_CROP: 100 * 200 > 300 * 100 is false -> scale = 300 / 100 = 3, dy = (200 - 300) * 0.5 = -50 (rounded).
        XCTAssertEqual(imageMatrix(.CENTER_CROP, 100, 100, 300, 200), [3, 0, 0, 0, 3, -50, 0, 0, 1])
        // FIT_CENTER: setRectToRect(CENTER): scale min(3, 2) = 2, tx = (300 - 200) / 2 = 50.
        XCTAssertEqual(imageMatrix(.FIT_CENTER, 100, 100, 300, 200), [2, 0, 50, 0, 2, 0, 0, 0, 1])
        // FIT_START / FIT_END: the same scale at the start / end.
        XCTAssertEqual(imageMatrix(.FIT_START, 100, 100, 300, 200), [2, 0, 0, 0, 2, 0, 0, 0, 1])
        XCTAssertEqual(imageMatrix(.FIT_END, 100, 100, 300, 200), [2, 0, 100, 0, 2, 0, 0, 0, 1])
        // CENTER_INSIDE: fits -> scale 1, dx = round(200 * 0.5) = 100, dy = round(100 * 0.5) = 50.
        XCTAssertEqual(imageMatrix(.CENTER_INSIDE, 100, 100, 300, 200), [1, 0, 100, 0, 1, 50, 0, 0, 1])
        // CENTER: translate round((300 - 100) * 0.5), round((200 - 100) * 0.5).
        XCTAssertEqual(imageMatrix(.CENTER, 100, 100, 300, 200), [1, 0, 100, 0, 1, 50, 0, 0, 1])
        // CENTER_INSIDE with a larger drawable: scale min(300 / 600, 200 / 100) = 0.5, dx = round((300 - 300) * 0.5)
        // = 0, dy = round((200 - 50) * 0.5) = 75.
        XCTAssertEqual(imageMatrix(.CENTER_INSIDE, 600, 100, 300, 200), [0.5, 0, 0, 0, 0.5, 75, 0, 0, 1])
        // FIT_XY / a drawable that fits exactly: no draw matrix (identity from getImageMatrix).
        XCTAssertEqual(imageMatrix(.FIT_XY, 100, 100, 300, 200), [1, 0, 0, 0, 1, 0, 0, 0, 1])
        XCTAssertEqual(imageMatrix(.CENTER_CROP, 300, 200, 300, 200), [1, 0, 0, 0, 1, 0, 0, 0, 1])
    }

    func testImageViewAdjustViewBoundsKeepsTheAspect() {
        // ImageView.onMeasure with adjustViewBounds: EXACTLY 200 wide, height AT_MOST 1000 -> 200 * 50 / 100 = 100.
        let iv = AImageView()
        let d = AGradientDrawable()
        d.setSize(100, 50)
        iv.setImageDrawable(d)
        iv.adjustViewBounds = true
        XCTAssertEqual(iv.scaleType, .FIT_CENTER)
        iv.measure(wExactly(200), wAtMost(1000))
        XCTAssertEqual(iv.measuredWidth, 200)
        XCTAssertEqual(iv.measuredHeight, 100)
        // Without adjustViewBounds: the drawable's size, clamped by AT_MOST.
        let plain = AImageView()
        plain.setImageDrawable(d)
        plain.measure(wAtMost(80), wUnspecified())
        XCTAssertEqual(plain.measuredWidth, 80)
        XCTAssertEqual(plain.measuredHeight, 50)
    }

    // MARK: - ProgressBar

    func testProgressBarStyleSizes() {
        // Widget.Material.Light.ProgressBar(.Small / .Large): 48 / 16 / 76 dp squares; Horizontal: 48 dp wide minimum
        // (min = max = 48 dp from Widget.ProgressBar) and 16 dp tall (min = max height 16 dp).
        let spinner = AProgressBar()
        spinner.measure(wUnspecified(), wUnspecified())
        XCTAssertEqual([spinner.measuredWidth, spinner.measuredHeight], [aw_dpx(48), aw_dpx(48)])
        XCTAssertTrue(spinner.isIndeterminate)
        let small = AProgressBar(style: .SMALL)
        small.measure(wUnspecified(), wUnspecified())
        XCTAssertEqual([small.measuredWidth, small.measuredHeight], [aw_dpx(16), aw_dpx(16)])
        let large = AProgressBar(style: .LARGE)
        large.measure(wUnspecified(), wUnspecified())
        XCTAssertEqual([large.measuredWidth, large.measuredHeight], [aw_dpx(76), aw_dpx(76)])
        let bar = AProgressBar(style: .HORIZONTAL)
        XCTAssertFalse(bar.isIndeterminate)
        bar.measure(wUnspecified(), wUnspecified())
        XCTAssertEqual([bar.measuredWidth, bar.measuredHeight], [aw_dpx(48), aw_dpx(16)])
        // The framework style attribute constructor (android.R.attr.progressBarStyleHorizontal).
        let fromAttr = AProgressBar(nil, android.R.attr.progressBarStyleHorizontal)
        XCTAssertEqual(fromAttr.progressStyle, .HORIZONTAL)
    }

    func testProgressBarClampsProgressToItsRange() {
        // ProgressBar.setProgressInternal / setMax: progress in [min, max]; a smaller max pulls the progress down.
        let bar = AProgressBar(style: .HORIZONTAL)
        XCTAssertEqual(bar.max, 100)
        bar.progress = 150
        XCTAssertEqual(bar.progress, 100)
        bar.progress = -5
        XCTAssertEqual(bar.progress, 0)
        bar.progress = 80
        bar.max = 50
        XCTAssertEqual(bar.progress, 50)
        bar.max = 1000
        XCTAssertEqual(bar.progress, 50)
        // The indeterminate spinner reports 0 and ignores setProgress.
        let spinner = AProgressBar()
        spinner.progress = 30
        XCTAssertEqual(spinner.progress, 0)
    }

    // MARK: - Switch (Widget.Material.Light.CompoundButton.Switch)

    func testSwitchBoxSizeFromTheThumbNinePatch() {
        // Switch.onMeasure: thumbWidth = intrinsic - padding (xxhdpi 81 - 2 * 11, xhdpi 54 - 2 * 7); switchWidth =
        // 2 * thumbWidth + the thumb's optical insets; switchHeight = max(track 14 dp, thumb height).
        let s = ASwitch()
        s.measure(wUnspecified(), wUnspecified())
        let threeX = density >= 2.5
        let thumb = threeX ? 81 : 54
        let pad = threeX ? 11 : 7
        let scale = density / Float(threeX ? 3 : 2)
        let thumbIntrinsic = AWMath.round(Float(thumb) * scale)
        let padding = AWMath.round(Float(pad) * scale)
        let switchWidth = 2 * (thumbIntrinsic - 2 * padding) + 2 * padding
        XCTAssertEqual(s.measuredWidth, switchWidth)
        XCTAssertEqual(s.measuredHeight, Swift.max(aw_dpx(14), thumbIntrinsic))
        XCTAssertFalse(s.isChecked)
        s.isChecked = true
        XCTAssertTrue(s.isChecked)
        // The checked state is a drawable state.
        XCTAssertTrue(s.drawableState.contains(AStateSet.state_checked))
    }

    // MARK: - ArrayAdapter + Spinner

    func testArrayAdapterItemsAndViews() {
        let ctx = AApplication.shared
        let adapter = AArrayAdapter(ctx, android.R.layout.simple_spinner_item, ["Math   \u{25BE}", "English   \u{25BE}"])
        XCTAssertEqual(adapter.getCount(), 2)
        XCTAssertEqual(adapter.getItem(1) as? String, "English   \u{25BE}")
        XCTAssertEqual(adapter.getItemId(1), 1)
        let parent = AFrameLayout()
        let v = adapter.getView(0, nil, parent) as? ATextView
        XCTAssertEqual(v?.text, "Math   \u{25BE}")
        // simple_spinner_item: single line, 16 sp, padding start / end 8 dp, MATCH_PARENT x WRAP_CONTENT.
        XCTAssertEqual(v?.isSingleLine, true)
        XCTAssertEqual(v?.textSize, Float(ATypedValue.toDimensionPixelSize(ATypedValue.COMPLEX_UNIT_SP, 16)))
        XCTAssertEqual(v?.paddingStart, aw_dpx(8))
        XCTAssertEqual(v?.layoutParams?.width, WMATCH)
        adapter.setDropDownViewResource(android.R.layout.simple_spinner_dropdown_item)
        let drop = adapter.getDropDownView(1, nil, parent) as? ATextView
        XCTAssertEqual(drop?.text, "English   \u{25BE}")
        XCTAssertEqual(drop?.layoutParams?.height, aw_dpx(48))
    }

    private func makeWindowRoot() -> (UIWindow, AViewRoot) {
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 320, height: 480))
        let host = UIView(frame: window.bounds)
        window.addSubview(host)
        return (window, AViewRoot(host: host))
    }

    func testSpinnerSelectionMadeBeforeTheListenerIsNotReported() {
        // AbsSpinner.setSelection(position, false) lays the selection out at once; checkSelectionChanged then records
        // it as the old selection although no listener was set, so the first layout reports nothing (no
        // accessibility service).
        let (window, root) = makeWindowRoot()
        let decor = AFrameLayout()
        let spinner = ASpinner(ASpinner.MODE_DROPDOWN)
        let ctx = AApplication.shared
        spinner.adapter = AArrayAdapter(ctx, android.R.layout.simple_spinner_item, ["a", "b", "c"])
        XCTAssertEqual(spinner.selectedItemPosition, 0)
        spinner.setSelection(2, false)
        XCTAssertEqual(spinner.selectedItemPosition, 2)
        let recorder = WidgetsSelectionRecorder()
        spinner.onItemSelectedListener = recorder
        decor.addView(spinner, AFrameLayout.LayoutParams(WMATCH, aw_dpx(38)))
        root.contentView = decor
        AndroidKitTestLoop.advance(millis: 40)
        if !(UIAccessibility.isVoiceOverRunning || UIAccessibility.isSwitchControlRunning) {
            XCTAssertEqual(recorder.selected, [])
        }
        XCTAssertEqual(spinner.selectedItem as? String, "c")
        XCTAssertEqual((spinner.selectedView as? ATextView)?.text, "c")
        // AbsSpinner.setSelection(position): applied by the next layout; reported by a posted notifier.
        spinner.setSelection(1)
        XCTAssertEqual(recorder.selected, [])
        AndroidKitTestLoop.advance(millis: 40)
        XCTAssertEqual(recorder.selected, [1])
        XCTAssertEqual(recorder.ids, [1])
        // setSelection(position, false) with the listener set: an immediate layout, a posted report.
        spinner.setSelection(0, false)
        XCTAssertEqual(recorder.selected, [1])
        AndroidKitTestLoop.runDueMessages()
        XCTAssertEqual(recorder.selected, [1, 0])
        root.dispose()
        _ = window
    }

    func testSpinnerMeasuresWithTheSelectedItemView() {
        // AbsSpinner.onMeasure: the selected view (simple_spinner_item: 16 sp single line with font padding) plus the
        // spinner padding; Spinner.layout places it at the start, centred vertically.
        let spinner = ASpinner(ASpinner.MODE_DROPDOWN)
        let ctx = AApplication.shared
        spinner.adapter = AArrayAdapter(ctx, android.R.layout.simple_spinner_item, ["Topic"])
        spinner.setPadding(aw_dpx(8), 0, aw_dpx(8), 0)
        wMeasureAndLayout(spinner, wExactly(600), wUnspecified())
        let size = Float(ATypedValue.toDimensionPixelSize(ATypedValue.COMPLEX_UNIT_SP, 16))
        let r = roboto(size)
        XCTAssertEqual(spinner.measuredHeight, r.bottom - r.top)
        XCTAssertEqual(spinner.childCount, 1)
        // A fixed height centres the item: (38 dp - item) / 2.
        wMeasureAndLayout(spinner, wExactly(600), wExactly(aw_dpx(38)))
        let child = spinner.getChildAt(0)!
        XCTAssertEqual(child.top, (aw_dpx(38) - (r.bottom - r.top)) / 2)
        // MATCH_PARENT item: the content width, at the start padding (START gravity; RIGHT in RTL lands on the same x).
        XCTAssertEqual(child.width, 600 - 2 * aw_dpx(8))
        XCTAssertEqual(child.left, aw_dpx(8))
    }

    // MARK: - TabLayout

    func testTabLayoutSelectsTheFirstTabBeforeTheListenerAndDispatchesInOrder() {
        // TabLayout.addTab: the first tab is selected on add (no listener yet); selectTab dispatches unselected then
        // selected; selecting the current tab dispatches reselected.
        let tabs = ATabLayout()
        tabs.addTab(tabs.newTab().setText("\u{05E0}\u{05D9}\u{05E7}\u{05D5}\u{05D3}"))
        tabs.addTab(tabs.newTab().setText("\u{05E8}\u{05E6}\u{05E3}"))
        XCTAssertEqual(tabs.tabCount, 2)
        XCTAssertEqual(tabs.selectedTabPosition, 0)
        let recorder = WidgetsTabRecorder()
        tabs.addOnTabSelectedListener(recorder)
        tabs.getTabAt(1)!.select()
        XCTAssertEqual(recorder.calls, ["u0", "s1"])
        XCTAssertEqual(tabs.selectedTabPosition, 1)
        tabs.getTabAt(1)!.select()
        XCTAssertEqual(recorder.calls, ["u0", "s1", "r1"])
        XCTAssertTrue(tabs.getTabAt(1)!.isSelected)
        XCTAssertFalse(tabs.getTabAt(0)!.isSelected)
    }

    func testTabLayoutIsFortyEightDpTall() {
        // TabLayout.onMeasure: an UNSPECIFIED height becomes EXACTLY round(48 dp) + padding.
        let tabs = ATabLayout()
        tabs.addTab(tabs.newTab().setText("A"))
        tabs.addTab(tabs.newTab().setText("B"))
        tabs.measure(wExactly(1000), wUnspecified())
        XCTAssertEqual(tabs.measuredHeight, AWMath.round(48 * density))
        tabs.layout(0, 0, 1000, tabs.measuredHeight)
        // MODE_FIXED + GRAVITY_FILL: the strip is re-measured EXACTLY at the layout's width and shares it between the
        // tabs (width 0, weight 1); 500 px is below tabMaxWidth (264 dp), so the TabViews keep it.
        let strip = tabs.getChildAt(0) as? AViewGroup
        XCTAssertEqual(strip?.width, 1000)
        XCTAssertEqual(strip?.childCount, 2)
        XCTAssertEqual(strip?.getChildAt(0)?.width, 500)
        XCTAssertEqual(strip?.getChildAt(1)?.width, 500)
    }

    // MARK: - RecyclerView-lite

    func testRecyclerViewBindsEveryItemAndRebindsOnNotify() {
        let list = ARecyclerView()
        let adapter = WidgetsRowAdapter()
        adapter.items = ["Ann", "Ben", "Cy"]
        list.layoutManager = ALinearLayoutManager(nil)
        list.adapter = adapter
        XCTAssertEqual(list.itemViews.count, 3)
        XCTAssertEqual(adapter.created, 3)
        XCTAssertEqual(adapter.bound, [0, 1, 2])
        XCTAssertEqual((list.itemViews[2] as? ATextView)?.text, "#3 Cy")
        // notifyDataSetChanged: every position is bound again; holders of the same type are reused.
        adapter.items = ["Dan", "Eve"]
        adapter.notifyDataSetChanged()
        XCTAssertEqual(list.itemViews.count, 2)
        XCTAssertEqual(adapter.created, 3)
        XCTAssertEqual(adapter.bound, [0, 1, 2, 0, 1])
        XCTAssertEqual((list.itemViews[0] as? ATextView)?.text, "#1 Dan")
        XCTAssertEqual(list.findViewHolderForAdapterPosition(1)?.adapterPosition, 1)
        // Without a layout manager nothing is bound (RecyclerView skips layout).
        let bare = ARecyclerView()
        let other = WidgetsRowAdapter()
        other.items = ["x"]
        bare.adapter = other
        XCTAssertEqual(bare.itemViews.count, 0)
    }

    // MARK: - TextInputLayout (FilledBox) and MDC helpers

    func testCompositeColorsMatchesColorUtils() {
        // JVM: androidx.core.graphics.ColorUtils.compositeColors.
        let cases: [(UInt32, UInt32, UInt32)] = [
            (0x1f000000, 0xffffffff, 0xffe0e0e0), (0xffffffff, 0xffffffff, 0xffffffff), (0x29000000, 0xffffffff, 0xffd6d6d6),
            (0x0a000000, 0xffffffff, 0xfff5f5f5), (0x80ff0000, 0x800000ff, 0xc0aa0054), (0x00000000, 0x00000000, 0x00000000),
            (0x6b000000, 0xfff2fffc, 0xff8c9492),
        ]
        for (fg, bg, expected) in cases {
            XCTAssertEqual(ATextInputLayout.compositeColors(argbInt(fg), argbInt(bg)), argbInt(expected))
        }
    }

    func testBlendARGBMatchesCollapsingTextHelper() {
        // JVM: CollapsingTextHelper.blendARGB.
        let cases: [(UInt32, UInt32, UInt32, UInt32)] = [
            (0x99000000, 0xff087e70, 0x0, 0x99000000), (0x99000000, 0xff087e70, 0x3f800000, 0xff087e70),
            (0x99000000, 0xff087e70, 0x3f000000, 0xcc043f38), (0x99000000, 0xff087e70, 0x3e800000, 0xb302201c),
            (0xffffffff, 0x00000000, 0x3eaaa64c, 0xaaaaaaaa),
        ]
        for (c1, c2, ratio, expected) in cases {
            XCTAssertEqual(AWCollapsingTextHelper.blendARGB(argbInt(c1), argbInt(c2), wFloat(ratio)), argbInt(expected))
        }
    }

    func testAnimationUtilsIntLerp() {
        // JVM: AnimationUtils.lerp(int, int, float) = start + Math.round(fraction * (end - start)).
        let cases: [(Int, Int, UInt32, Int)] = [
            (540, 0, 0x0, 540), (540, 0, 0x3f800000, 0), (540, 0, 0x3f000000, 270), (100, 1080, 0x3e99999a, 394),
            (0, 7, 0x3f000000, 4), (0, -7, 0x3f000000, -3), (10, 20, 0x3f733333, 20),
        ]
        for (a, b, f, expected) in cases {
            XCTAssertEqual(AWAnimationUtils.lerp(a, b, wFloat(f)), expected, "lerp(\(a), \(b), \(wFloat(f)))")
        }
    }

    func testFastOutSlowInInterpolatorMatchesAndroidx() {
        // JVM: androidx.interpolator.view.animation.FastOutSlowInInterpolator (bit patterns).
        let cases: [(UInt32, UInt32)] = [
            (0xbdcccccd, 0x0), (0x0, 0x0), (0x3a83126f, 0x37a7c5ad), (0x3ba3d633, 0x38d1b604), (0x3ba3d70a, 0x38d1b717),
            (0x3dcccccd, 0x3cd42c3f), (0x3e800000, 0x3e724745), (0x3eaaaa9f, 0x3eea1a60), (0x3f000000, 0x3f468db9),
            (0x3f19999a, 0x3f60418a), (0x3f400000, 0x3f759b3d), (0x3f666666, 0x3f7e9100), (0x3f7eb852, 0x3f800000),
            (0x3f7fbe77, 0x3f800000), (0x3f800000, 0x3f800000), (0x3f99999a, 0x3f800000),
        ]
        let i = AFastOutSlowInInterpolator()
        for (input, expected) in cases {
            let out = i.getInterpolation(wFloat(input))
            XCTAssertEqual(out.bitPattern, expected, "FastOutSlowIn(\(wFloat(input))) = \(out)")
        }
    }

    func testTextInputLayoutTakesTheHintAndPutsTheFilledBoxOnTheEditText() {
        // TextInputLayout.setEditText: the EditText's hint moves to the layout (TextInputEditText.getHint reports
        // it); the FilledBox background is the box drawable; boxBackgroundColor reads back layered over colorSurface
        // (applyBoxAttributes stores calculateBoxBackgroundColor()).
        let til = ATextInputLayout()
        let edit = ATextInputEditText()
        edit.hint = "Your name"
        til.addView(edit, ALinearLayout.LayoutParams(WMATCH, WWRAP))
        XCTAssertTrue(til.editText === edit)
        XCTAssertTrue(edit.parentGroup === til.inputFrame)
        XCTAssertTrue(til.isProvidingHint())
        XCTAssertEqual(til.hint, "Your name")
        XCTAssertEqual(edit.hint, "Your name")
        XCTAssertNil(edit.aw_hint)
        XCTAssertEqual(til.boxBackgroundMode, ATextInputLayout.BOX_BACKGROUND_FILLED)
        XCTAssertTrue(edit.background is AWBoxBackgroundDrawable)
        XCTAssertEqual(til.boxBackgroundColor, argbInt(0xffe0e0e0))
        // TripleShotControls: boxBackgroundColor = WHITE (all states).
        til.boxBackgroundColor = AColor.WHITE
        XCTAssertEqual(til.boxBackgroundColor, AColor.WHITE)
        XCTAssertEqual((edit.background as? AWBoxBackgroundDrawable)?.fillColor, AColor.WHITE)
        // FilledBox TextInputEditText: padding 16 / 24 / 16 / 10 dp, 16 sp.
        XCTAssertEqual([edit.paddingLeft, edit.paddingTop, edit.paddingRight, edit.paddingBottom],
                       [aw_dpx(16), aw_dpx(24), aw_dpx(16), aw_dpx(10)])
        XCTAssertEqual(edit.textSize, Float(ATypedValue.toDimensionPixelSize(ATypedValue.COMPLEX_UNIT_SP, 16)))
        // A replaced EditText background is put back by the next box update (the FamilyFormStyle race).
        edit.background = AGradientDrawable()
        til.updateTextInputBoxState()
        XCTAssertTrue(edit.background is AWBoxBackgroundDrawable)
    }
}
