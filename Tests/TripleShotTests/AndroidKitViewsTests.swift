import XCTest
import UIKit
@testable import MinikTripleShot

// Area kit-views: MeasureSpec, the measure/layout arithmetic of View, ViewGroup, FrameLayout, LinearLayout,
// ScrollView, HorizontalScrollView and the ConstraintLayout subset, Gravity, MarginLayoutParams, MotionEvent,
// the ViewGroup touch dispatch through an AViewRoot, and GestureDetector timings.
//
// The Android app has no unit tests for this layer; the expected values are worked out by hand from the AOSP sources
// the port follows (frameworks/base android-14: View.java, ViewGroup.java, FrameLayout.java, LinearLayout.java,
// ScrollView.java, HorizontalScrollView.java, GestureDetector.java, MotionEvent.java; ConstraintLayout 2.2 Direct
// resolution), each step noted next to the assertion. All sizes are Android pixels.

private let MATCH = AViewGroup.LayoutParams.MATCH_PARENT
private let WRAP = AViewGroup.LayoutParams.WRAP_CONTENT

private func exactly(_ size: Int) -> Int { AMeasureSpec.makeMeasureSpec(size, AMeasureSpec.EXACTLY) }
private func atMost(_ size: Int) -> Int { AMeasureSpec.makeMeasureSpec(size, AMeasureSpec.AT_MOST) }
private func unspecified(_ size: Int) -> Int { AMeasureSpec.makeMeasureSpec(size, AMeasureSpec.UNSPECIFIED) }

/// Measures with the specs and lays the view out at (0, 0) with its measured size, as a parent would.
private func measureAndLayout(_ v: AView, _ widthSpec: Int, _ heightSpec: Int) {
    v.measure(widthSpec, heightSpec)
    v.layout(0, 0, v.measuredWidth, v.measuredHeight)
}

private func frame(_ v: AView) -> [Int] { [v.left, v.top, v.right, v.bottom] }

/// A view that counts its onMeasure calls.
private final class CountingView: AView {
    var measureCount = 0
    override func onMeasure(_ widthMeasureSpec: Int, _ heightMeasureSpec: Int) {
        measureCount += 1
        super.onMeasure(widthMeasureSpec, heightMeasureSpec)
    }
}

/// A frame layout that takes the gesture from its children once the finger moves.
private final class InterceptOnMoveLayout: AFrameLayout {
    override func onInterceptTouchEvent(_ ev: AMotionEvent) -> Bool {
        ev.actionMasked == AMotionEvent.ACTION_MOVE
    }
}

/// Records every touch event a view receives (and consumes them when `consume` is set).
private final class TouchRecorderView: AView {
    var actions: [Int] = []
    var consume = true
    override func onTouchEvent(_ event: AMotionEvent) -> Bool {
        actions.append(event.actionMasked)
        return consume
    }
}

/// GestureDetector listener that records the callbacks in order.
private final class RecordingGestureListener: ASimpleOnGestureListener {
    var calls: [String] = []
    var downTimes: [Int64] = []
    override func onDown(_ e: AMotionEvent) -> Bool { calls.append("down"); downTimes.append(e.downTime); return true }
    override func onShowPress(_ e: AMotionEvent) { calls.append("showPress") }
    override func onSingleTapUp(_ e: AMotionEvent) -> Bool { calls.append("singleTapUp"); return true }
    override func onLongPress(_ e: AMotionEvent) { calls.append("longPress") }
    override func onScroll(_ e1: AMotionEvent?, _ e2: AMotionEvent, _ distanceX: Float, _ distanceY: Float) -> Bool {
        calls.append("scroll(\(distanceX),\(distanceY))"); return true
    }
    override func onSingleTapConfirmed(_ e: AMotionEvent) -> Bool { calls.append("singleTapConfirmed"); return true }
    override func onDoubleTap(_ e: AMotionEvent) -> Bool { calls.append("doubleTap"); return true }
    override func onDoubleTapEvent(_ e: AMotionEvent) -> Bool {
        calls.append("doubleTapEvent(\(e.actionMasked))"); return true
    }
}

final class AndroidKitViewsTests: XCTestCase {
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

    // MARK: - MeasureSpec

    func testMeasureSpecPacksModeAndSizeLikeJava() {
        XCTAssertEqual(AMeasureSpec.UNSPECIFIED, 0)
        XCTAssertEqual(AMeasureSpec.EXACTLY, 0x4000_0000)
        XCTAssertEqual(AMeasureSpec.AT_MOST, 0x8000_0000)

        let e = AMeasureSpec.makeMeasureSpec(1080, AMeasureSpec.EXACTLY)
        XCTAssertEqual(e, 0x4000_0438)
        XCTAssertEqual(AMeasureSpec.getMode(e), AMeasureSpec.EXACTLY)
        XCTAssertEqual(AMeasureSpec.getSize(e), 1080)

        let a = AMeasureSpec.makeMeasureSpec(500, AMeasureSpec.AT_MOST)
        XCTAssertEqual(AMeasureSpec.getMode(a), AMeasureSpec.AT_MOST)
        XCTAssertEqual(AMeasureSpec.getSize(a), 500)
        // The same bits as the Java int (negative there): 0x800001F4.
        XCTAssertEqual(Int32(truncatingIfNeeded: a), Int32(bitPattern: 0x8000_01F4))

        let u = AMeasureSpec.makeMeasureSpec(7, AMeasureSpec.UNSPECIFIED)
        XCTAssertEqual(AMeasureSpec.getMode(u), AMeasureSpec.UNSPECIFIED)
        XCTAssertEqual(AMeasureSpec.getSize(u), 7)

        // (size & ~MODE_MASK) | (mode & MODE_MASK): a negative size keeps its low 30 bits, as in Java.
        let n = AMeasureSpec.makeMeasureSpec(-1, AMeasureSpec.EXACTLY)
        XCTAssertEqual(AMeasureSpec.getMode(n), AMeasureSpec.EXACTLY)
        XCTAssertEqual(AMeasureSpec.getSize(n), 0x3FFF_FFFF)

        // MeasureSpec.adjust clamps at 0 and leaves UNSPECIFIED alone.
        XCTAssertEqual(AMeasureSpec.adjust(exactly(10), -15), exactly(0))
        XCTAssertEqual(AMeasureSpec.adjust(atMost(100), -15), atMost(85))
        XCTAssertEqual(AMeasureSpec.adjust(unspecified(100), -15), unspecified(100))
    }

    func testGetChildMeasureSpecTable() {
        let g = AViewGroup.getChildMeasureSpec
        // Parent EXACTLY 1000, padding 100.
        XCTAssertEqual(g(exactly(1000), 100, 300), exactly(300))
        XCTAssertEqual(g(exactly(1000), 100, MATCH), exactly(900))
        XCTAssertEqual(g(exactly(1000), 100, WRAP), atMost(900))
        // Parent AT_MOST 1000.
        XCTAssertEqual(g(atMost(1000), 100, 300), exactly(300))
        XCTAssertEqual(g(atMost(1000), 100, MATCH), atMost(900))
        XCTAssertEqual(g(atMost(1000), 100, WRAP), atMost(900))
        // Parent UNSPECIFIED (targetSdk >= M: the size hint is passed on).
        XCTAssertEqual(g(unspecified(1000), 100, 300), exactly(300))
        XCTAssertEqual(g(unspecified(1000), 100, MATCH), unspecified(900))
        XCTAssertEqual(g(unspecified(1000), 100, WRAP), unspecified(900))
        // More padding than room: max(0, size - padding).
        XCTAssertEqual(g(exactly(50), 100, MATCH), exactly(0))
        // A child bigger than an AT_MOST parent still gets its exact size.
        XCTAssertEqual(g(atMost(100), 0, 300), exactly(300))
    }

    func testResolveSizeAndStateAndDefaultSize() {
        // AT_MOST smaller than the wanted size: the spec size with MEASURED_STATE_TOO_SMALL.
        XCTAssertEqual(AView.resolveSizeAndState(300, atMost(200), 0), 200 | AView.MEASURED_STATE_TOO_SMALL)
        XCTAssertEqual(AView.resolveSizeAndState(300, atMost(200), 0), 0x0100_00C8)
        XCTAssertEqual(AView.resolveSizeAndState(150, atMost(200), 0), 150)
        XCTAssertEqual(AView.resolveSizeAndState(300, exactly(200), 0), 200)
        XCTAssertEqual(AView.resolveSizeAndState(300, unspecified(0), 0), 300)
        XCTAssertEqual(AView.resolveSizeAndState(100, exactly(100), AView.MEASURED_STATE_TOO_SMALL),
                       100 | AView.MEASURED_STATE_TOO_SMALL)
        XCTAssertEqual(AView.resolveSize(300, atMost(200)), 200)
        // View.getDefaultSize: AT_MOST and EXACTLY both give the spec size.
        XCTAssertEqual(AView.getDefaultSize(10, atMost(200)), 200)
        XCTAssertEqual(AView.getDefaultSize(10, exactly(200)), 200)
        XCTAssertEqual(AView.getDefaultSize(10, unspecified(200)), 10)
    }

    func testPlainViewDefaultMeasureUsesSuggestedMinimum() {
        let v = AView()
        v.minimumWidth = 40
        v.minimumHeight = 30
        v.measure(atMost(200), unspecified(500))
        XCTAssertEqual(v.measuredWidth, 200)
        XCTAssertEqual(v.measuredHeight, 30)
        // A background's intrinsic size raises the suggested minimum (ColorDrawable has none: -1).
        v.setBackgroundColor(AColor.RED)
        v.measure(unspecified(0), unspecified(0))
        XCTAssertEqual(v.measuredWidth, 40)
        XCTAssertEqual(v.measuredHeight, 30)
    }

    func testMeasureCacheSkipsOnMeasureForSameSpecs() {
        let v = CountingView()
        v.measure(exactly(100), exactly(50))
        XCTAssertEqual(v.measureCount, 1)
        v.layout(0, 0, 100, 50)
        // Same specs, no forced layout: no onMeasure.
        v.measure(exactly(100), exactly(50))
        XCTAssertEqual(v.measureCount, 1)
        // EXACTLY specs that differ from the old ones but match the measured size: still no onMeasure.
        let w = CountingView()
        w.measure(atMost(100), atMost(50))
        w.layout(0, 0, w.measuredWidth, w.measuredHeight)
        XCTAssertEqual(w.measureCount, 1)
        w.measure(exactly(100), exactly(50))
        XCTAssertEqual(w.measureCount, 1)
        // requestLayout forces the next measure.
        w.requestLayout()
        w.measure(exactly(100), exactly(50))
        XCTAssertEqual(w.measureCount, 2)
    }

    func testRequestLayoutPropagatesToParents() {
        let outer = AFrameLayout()
        let inner = AFrameLayout()
        let leaf = AView()
        inner.addView(leaf)
        outer.addView(inner)
        measureAndLayout(outer, exactly(100), exactly(100))
        XCTAssertFalse(outer.isLayoutRequested)
        XCTAssertFalse(inner.isLayoutRequested)
        leaf.requestLayout()
        XCTAssertTrue(leaf.isLayoutRequested)
        XCTAssertTrue(inner.isLayoutRequested)
        XCTAssertTrue(outer.isLayoutRequested)
    }

    // MARK: - LinearLayout

    func testVerticalLinearLayoutDistributesExcessByWeight() {
        let ll = ALinearLayout()
        ll.orientation = ALinearLayout.VERTICAL
        let a = AView(), b = AView(), c = AView()
        ll.addView(a, ALinearLayout.LayoutParams(MATCH, 100))
        ll.addView(b, ALinearLayout.LayoutParams(MATCH, 0, 1))
        ll.addView(c, ALinearLayout.LayoutParams(MATCH, 0, 2))
        measureAndLayout(ll, exactly(600), exactly(1000))
        // a measured EXACTLY 100; b and c skipped (0dp + weight in an EXACTLY parent). Excess 1000 - 100 = 900:
        // b gets (int)(1 * 900 / 3) = 300, c gets (int)(2 * 600 / 2) = 600.
        XCTAssertEqual(ll.measuredWidth, 600)
        XCTAssertEqual(ll.measuredHeight, 1000)
        XCTAssertEqual(frame(a), [0, 0, 600, 100])
        XCTAssertEqual(frame(b), [0, 100, 600, 400])
        XCTAssertEqual(frame(c), [0, 400, 600, 1000])
    }

    func testWeightSharesTruncateAndTheLastChildTakesTheRest() {
        let ll = ALinearLayout()
        ll.orientation = ALinearLayout.VERTICAL
        let views = [AView(), AView(), AView()]
        for v in views { ll.addView(v, ALinearLayout.LayoutParams(MATCH, 0, 1)) }
        measureAndLayout(ll, exactly(300), exactly(1000))
        // (int)(1000 / 3f) = 333, (int)(667 / 2f) = 333, (int)(334 / 1f) = 334.
        XCTAssertEqual(views.map { $0.height }, [333, 333, 334])
        XCTAssertEqual(views.map { $0.top }, [0, 333, 666])
    }

    func testWeightSumLeavesUnclaimedSpace() {
        let ll = ALinearLayout()
        ll.orientation = ALinearLayout.VERTICAL
        ll.weightSum = 4
        let v = AView()
        ll.addView(v, ALinearLayout.LayoutParams(MATCH, 0, 1))
        measureAndLayout(ll, exactly(300), exactly(1000))
        // share = (int)(1 * 1000 / 4) = 250.
        XCTAssertEqual(v.height, 250)
        XCTAssertEqual(ll.measuredHeight, 1000)
        // setWeightSum stores max(0, weightSum).
        ll.weightSum = -3
        XCTAssertEqual(ll.weightSum, 0)
    }

    func testHorizontalWeightsWithMarginsAndPadding() {
        let ll = ALinearLayout()
        ll.orientation = ALinearLayout.HORIZONTAL
        ll.setPadding(10, 0, 30, 0)
        let a = AView(), b = AView()
        let lpa = ALinearLayout.LayoutParams(0, 50, 1)
        lpa.setMargins(5, 0, 5, 0)
        ll.addView(a, lpa)
        ll.addView(b, ALinearLayout.LayoutParams(0, 50, 1))
        measureAndLayout(ll, exactly(1000), exactly(100))
        // Exactly mode: mTotalLength = margins 10 (+ padding 40) = 50; excess 1000 - 50 = 950:
        // a: (int)(950 / 2f) = 475, b: (int)(475 / 1f) = 475.
        XCTAssertEqual(a.width, 475)
        XCTAssertEqual(b.width, 475)
        XCTAssertEqual(frame(a), [15, 0, 490, 50])
        XCTAssertEqual(frame(b), [495, 0, 970, 50])
    }

    func testHorizontalGravityCenterAndChildMargins() {
        let ll = ALinearLayout()
        ll.orientation = ALinearLayout.HORIZONTAL
        ll.gravity = AGravity.CENTER
        let a = AView(), b = AView()
        let lpa = ALinearLayout.LayoutParams(100, 50)
        lpa.setMargins(10, 5, 20, 5)
        ll.addView(a, lpa)
        ll.addView(b, ALinearLayout.LayoutParams(200, 80))
        measureAndLayout(ll, exactly(1000), exactly(300))
        // mTotalLength = 100 + 10 + 20 + 200 = 330; CENTER_HORIZONTAL: childLeft = (1000 - 330) / 2 = 335.
        // CENTER_VERTICAL: a top = (300 - 50) / 2 + 5 - 5 = 125; b top = (300 - 80) / 2 = 110.
        XCTAssertEqual(ll.gravity, AGravity.CENTER)
        XCTAssertEqual(frame(a), [345, 125, 445, 175])
        XCTAssertEqual(frame(b), [465, 110, 665, 190])
    }

    func testLinearLayoutSetGravityFillsMissingAxes() {
        let ll = ALinearLayout()
        XCTAssertEqual(ll.gravity, AGravity.START | AGravity.TOP)
        ll.gravity = AGravity.CENTER_VERTICAL
        XCTAssertEqual(ll.gravity, AGravity.CENTER_VERTICAL | AGravity.START)
        ll.gravity = AGravity.RIGHT
        XCTAssertEqual(ll.gravity, AGravity.RIGHT | AGravity.TOP)
    }

    func testHorizontalLinearLayoutRtlPlacesTheFirstChildAtTheRight() {
        let ll = ALinearLayout()
        ll.orientation = ALinearLayout.HORIZONTAL
        ll.layoutDirection = AView.LAYOUT_DIRECTION_RTL
        let a = AView(), b = AView()
        let lpa = ALinearLayout.LayoutParams(100, 50)
        lpa.leftMargin = 10
        lpa.rightMargin = 20
        ll.addView(a, lpa)
        ll.addView(b, ALinearLayout.LayoutParams(200, 80))
        measureAndLayout(ll, exactly(1000), exactly(300))
        // START resolves to RIGHT: childLeft = 1000 - 330 = 670; the children are placed from the last one.
        XCTAssertTrue(ll.isLayoutRtl)
        XCTAssertEqual(frame(b), [670, 0, 870, 80])
        XCTAssertEqual(frame(a), [880, 0, 980, 50])
    }

    func testVerticalLinearLayoutChildLayoutGravityAndPadding() {
        let ll = ALinearLayout()
        ll.orientation = ALinearLayout.VERTICAL
        ll.setPadding(10, 20, 30, 40)
        let a = AView(), b = AView(), c = AView()
        let lpa = ALinearLayout.LayoutParams(100, 50)
        lpa.gravity = AGravity.RIGHT
        lpa.rightMargin = 5
        let lpb = ALinearLayout.LayoutParams(100, 50)
        lpb.gravity = AGravity.CENTER_HORIZONTAL
        lpb.leftMargin = 8
        let lpc = ALinearLayout.LayoutParams(100, 50)
        lpc.gravity = AGravity.END
        ll.addView(a, lpa)
        ll.addView(b, lpb)
        ll.addView(c, lpc)
        measureAndLayout(ll, exactly(500), exactly(1000))
        // childRight = 500 - 30 = 470; childSpace = 500 - 10 - 30 = 460.
        XCTAssertEqual(frame(a), [365, 20, 465, 70])
        XCTAssertEqual(frame(b), [198, 70, 298, 120])
        XCTAssertEqual(frame(c), [370, 120, 470, 170])
    }

    func testGoneChildrenTakeNoSpaceInvisibleChildrenDo() {
        let ll = ALinearLayout()
        ll.orientation = ALinearLayout.VERTICAL
        let a = AView(), b = AView(), c = AView()
        ll.addView(a, ALinearLayout.LayoutParams(MATCH, 100))
        ll.addView(b, ALinearLayout.LayoutParams(MATCH, 100))
        ll.addView(c, ALinearLayout.LayoutParams(MATCH, 100))
        b.visibility = AView.GONE
        measureAndLayout(ll, exactly(100), atMost(1000))
        XCTAssertEqual(ll.measuredHeight, 200)
        XCTAssertEqual(c.top, 100)
        b.visibility = AView.INVISIBLE
        measureAndLayout(ll, exactly(100), atMost(1000))
        XCTAssertEqual(ll.measuredHeight, 300)
        XCTAssertEqual(b.top, 100)
        XCTAssertEqual(c.top, 200)
    }

    func testWrapContentVerticalLayoutUsesWidestChildAndForcesUniformWidth() {
        let ll = ALinearLayout()
        ll.orientation = ALinearLayout.VERTICAL
        let a = AView(), b = AView()
        ll.addView(a, ALinearLayout.LayoutParams(150, 40))
        ll.addView(b, ALinearLayout.LayoutParams(MATCH, 40))
        measureAndLayout(ll, atMost(1000), atMost(1000))
        // allFillParent is false, so the width is the alternative max (150; b counts only its margins). b is then
        // remeasured EXACTLY at the final width (forceUniformWidth).
        XCTAssertEqual(ll.measuredWidth, 150)
        XCTAssertEqual(ll.measuredHeight, 80)
        XCTAssertEqual(b.width, 150)
    }

    // MARK: - FrameLayout

    func testFrameLayoutGravityAndMargins() {
        let fl = AFrameLayout()
        let a = AView(), b = AView(), c = AView()
        let lpa = AFrameLayout.LayoutParams(100, 100, AGravity.BOTTOM | AGravity.END)
        lpa.rightMargin = 10
        lpa.bottomMargin = 20
        let lpb = AFrameLayout.LayoutParams(200, 100, AGravity.CENTER)
        lpb.leftMargin = 30
        let lpc = AFrameLayout.LayoutParams(MATCH, MATCH)
        lpc.setMargins(5, 5, 5, 5)
        fl.addView(a, lpa)
        fl.addView(b, lpb)
        fl.addView(c, lpc)
        measureAndLayout(fl, exactly(1000), exactly(800))
        XCTAssertEqual(frame(a), [890, 680, 990, 780])
        // CENTER: (1000 - 200) / 2 + 30 = 430, (800 - 100) / 2 = 350.
        XCTAssertEqual(frame(b), [430, 350, 630, 450])
        // No gravity: TOP | START with the margins; MATCH_PARENT minus the margins.
        XCTAssertEqual(frame(c), [5, 5, 995, 795])

        // RTL: END is LEFT.
        fl.layoutDirection = AView.LAYOUT_DIRECTION_RTL
        measureAndLayout(fl, exactly(1000), exactly(800))
        XCTAssertEqual(frame(a), [0, 680, 100, 780])
    }

    func testFrameLayoutWrapContentAndMeasureAllChildren() {
        let fl = AFrameLayout()
        let a = AView(), b = AView()
        fl.addView(a, AFrameLayout.LayoutParams(300, 200))
        fl.addView(b, AFrameLayout.LayoutParams(500, 100))
        b.visibility = AView.GONE
        fl.measure(atMost(1000), atMost(1000))
        XCTAssertEqual(fl.measuredWidth, 300)
        XCTAssertEqual(fl.measuredHeight, 200)
        fl.measureAllChildren = true
        fl.measure(atMost(1000), atMost(1000))
        XCTAssertEqual(fl.measuredWidth, 500)
        XCTAssertEqual(fl.measuredHeight, 200)
    }

    func testFrameLayoutRemeasuresMatchParentChildrenOnlyWhenThereAreSeveral() {
        // Two MATCH_PARENT children in a wrap_content frame: both are measured again EXACTLY at the frame's size.
        let fl = AFrameLayout()
        let fixed = AView(), s1 = ASpace(), s2 = ASpace()
        fl.addView(fixed, AFrameLayout.LayoutParams(300, 200))
        fl.addView(s1, AFrameLayout.LayoutParams(MATCH, MATCH))
        fl.addView(s2, AFrameLayout.LayoutParams(MATCH, 50))
        fl.measure(atMost(1000), atMost(1000))
        XCTAssertEqual(fl.measuredWidth, 300)
        XCTAssertEqual(fl.measuredHeight, 200)
        XCTAssertEqual(s1.measuredWidth, 300)
        XCTAssertEqual(s1.measuredHeight, 200)
        XCTAssertEqual(s2.measuredWidth, 300)
        XCTAssertEqual(s2.measuredHeight, 50)

        // Android quirk kept: a single MATCH_PARENT child is not remeasured (count > 1 only).
        let fl2 = AFrameLayout()
        let fixed2 = AView(), lone = ASpace()
        fl2.addView(fixed2, AFrameLayout.LayoutParams(300, 200))
        fl2.addView(lone, AFrameLayout.LayoutParams(MATCH, MATCH))
        fl2.measure(atMost(1000), atMost(1000))
        XCTAssertEqual(fl2.measuredWidth, 300)
        XCTAssertEqual(lone.measuredWidth, 0)
        XCTAssertEqual(lone.measuredHeight, 0)
    }

    func testFrameLayoutDefaultLayoutParamsAreMatchParent() {
        let fl = AFrameLayout()
        let v = AView()
        fl.addView(v)
        let lp = v.layoutParams as? AFrameLayout.LayoutParams
        XCTAssertNotNil(lp)
        XCTAssertEqual(lp?.width, MATCH)
        XCTAssertEqual(lp?.height, MATCH)
        XCTAssertEqual(lp?.gravity, AFrameLayout.LayoutParams.UNSPECIFIED_GRAVITY)
        // LinearLayout: WRAP x WRAP horizontal, MATCH x WRAP vertical; margins survive the conversion.
        let ll = ALinearLayout()
        ll.orientation = ALinearLayout.VERTICAL
        let w = AView()
        let margins = AViewGroup.MarginLayoutParams(10, 20)
        margins.setMargins(1, 2, 3, 4)
        ll.addView(w, margins)
        let converted = w.layoutParams as? ALinearLayout.LayoutParams
        XCTAssertNotNil(converted)
        XCTAssertEqual(converted?.width, 10)
        XCTAssertEqual(converted?.topMargin, 2)
        XCTAssertEqual(converted?.bottomMargin, 4)
        let x = AView()
        ll.addView(x)
        XCTAssertEqual(x.layoutParams?.width, MATCH)
        XCTAssertEqual(x.layoutParams?.height, WRAP)
    }

    // MARK: - ScrollView / HorizontalScrollView

    func testScrollViewMeasuresItsChildUnspecifiedAndClampsScrolling() {
        let sv = AScrollView()
        let content = ALinearLayout()
        content.orientation = ALinearLayout.VERTICAL
        for _ in 0..<3 { content.addView(AView(), ALinearLayout.LayoutParams(MATCH, 500)) }
        sv.addView(content, AFrameLayout.LayoutParams(MATCH, WRAP))
        measureAndLayout(sv, exactly(1000), exactly(800))
        XCTAssertEqual(sv.measuredHeight, 800)
        XCTAssertEqual(content.measuredWidth, 1000)
        XCTAssertEqual(content.measuredHeight, 1500)
        XCTAssertEqual(sv.getScrollRange(), 700)
        sv.scrollTo(0, 1000)
        XCTAssertEqual(sv.scrollY, 700)
        sv.scrollTo(0, -5)
        XCTAssertEqual(sv.scrollY, 0)
        sv.scrollTo(0, 250)
        XCTAssertEqual(sv.scrollY, 250)
        XCTAssertTrue(sv.canScrollVertically(1))
        XCTAssertTrue(sv.canScrollVertically(-1))
    }

    func testScrollViewFillViewportStretchesAShortChild() {
        let sv = AScrollView()
        let content = ALinearLayout()
        content.orientation = ALinearLayout.VERTICAL
        content.addView(AView(), ALinearLayout.LayoutParams(MATCH, 100))
        sv.addView(content, AFrameLayout.LayoutParams(MATCH, WRAP))
        measureAndLayout(sv, exactly(1000), exactly(800))
        XCTAssertEqual(content.measuredHeight, 100)
        sv.isFillViewport = true
        measureAndLayout(sv, exactly(1000), exactly(800))
        XCTAssertEqual(content.measuredHeight, 800)
        XCTAssertEqual(sv.getScrollRange(), 0)
        XCTAssertFalse(sv.canScrollVertically(1))
    }

    func testScrollViewHostsOneDirectChildAndDelaysChildPressedState() {
        let sv = AScrollView()
        XCTAssertTrue(sv.shouldDelayChildPressedState())
        XCTAssertFalse(AFrameLayout().shouldDelayChildPressedState())
        XCTAssertFalse(ALinearLayout().shouldDelayChildPressedState())
        XCTAssertTrue(AViewGroup().shouldDelayChildPressedState())
        sv.addView(AView())
        XCTAssertEqual(sv.childCount, 1)
    }

    func testHorizontalScrollViewStartsAtTheRightEndInRtl() {
        let hsv = AHorizontalScrollView()
        hsv.layoutDirection = AView.LAYOUT_DIRECTION_RTL
        let content = ALinearLayout()
        content.orientation = ALinearLayout.HORIZONTAL
        let items = [AView(), AView(), AView()]
        for v in items { content.addView(v, ALinearLayout.LayoutParams(500, MATCH)) }
        hsv.addView(content, AFrameLayout.LayoutParams(WRAP, MATCH))
        measureAndLayout(hsv, exactly(1000), exactly(300))
        // The child is measured UNSPECIFIED horizontally: 1500 wide; it is wider than the view, so it is laid out at
        // the left (forceLeftGravity) and the first layout scrolls to scrollRange - 0 = 500.
        XCTAssertEqual(content.measuredWidth, 1500)
        XCTAssertEqual(frame(content), [0, 0, 1500, 300])
        XCTAssertEqual(hsv.getScrollRange(), 500)
        XCTAssertEqual(hsv.scrollX, 500)
        // The RTL row puts the first item at the right end of the content.
        XCTAssertEqual(items.map { $0.left }, [1000, 500, 0])
    }

    func testHorizontalScrollViewLtrStartsAtZero() {
        let hsv = AHorizontalScrollView()
        hsv.layoutDirection = AView.LAYOUT_DIRECTION_LTR
        let content = ALinearLayout()
        for _ in 0..<3 { content.addView(AView(), ALinearLayout.LayoutParams(500, MATCH)) }
        hsv.addView(content, AFrameLayout.LayoutParams(WRAP, MATCH))
        measureAndLayout(hsv, exactly(1000), exactly(300))
        XCTAssertEqual(hsv.scrollX, 0)
        hsv.scrollTo(900, 0)
        XCTAssertEqual(hsv.scrollX, 500)
    }

    // MARK: - ConstraintLayout subset

    func testConstraintLayoutParentAnchorsBiasPercentAndMax() {
        let cl = AConstraintLayout()
        typealias CLP = AConstraintLayout.LayoutParams

        // 0dp x 0dp to all four parent sides: the whole container.
        let background = AView()
        let lbg = CLP(0, 0)
        lbg.topToTop = CLP.PARENT_ID; lbg.bottomToBottom = CLP.PARENT_ID
        lbg.startToStart = CLP.PARENT_ID; lbg.endToEnd = CLP.PARENT_ID
        cl.addView(background, lbg)

        // A 440 x 50 card centred horizontally under a 5 px top margin.
        let card = AView()
        let lcard = CLP(440, 50)
        lcard.topToTop = CLP.PARENT_ID; lcard.startToStart = CLP.PARENT_ID; lcard.endToEnd = CLP.PARENT_ID
        lcard.topMargin = 5
        cl.addView(card, lcard)

        // width_percent 0.58 with bias 0 and a 20 px left margin: left = (int)(20 + 0.5), right = (int)(20 + 580 + 0.5).
        let percent = AView()
        let lpct = CLP(0, 100)
        lpct.leftToLeft = CLP.PARENT_ID; lpct.rightToRight = CLP.PARENT_ID; lpct.topToTop = CLP.PARENT_ID
        lpct.horizontalBias = 0
        lpct.leftMargin = 20
        lpct.matchConstraintPercentWidth = 0.58
        cl.addView(percent, lpct)

        // 0dp with max 520 and 20 px start/end margins: min(960, 520) = 520, centred: 20 + (int)(0.5 + 0.5 * 440).
        let capped = ASpace()
        capped.minimumHeight = 50
        let lcap = CLP(0, WRAP)
        lcap.startToStart = CLP.PARENT_ID; lcap.endToEnd = CLP.PARENT_ID; lcap.topToTop = CLP.PARENT_ID
        lcap.marginStart = 20; lcap.marginEnd = 20
        lcap.matchConstraintMaxWidth = 520
        cl.addView(capped, lcap)

        measureAndLayout(cl, exactly(1000), exactly(2000))
        XCTAssertEqual(frame(background), [0, 0, 1000, 2000])
        XCTAssertEqual(frame(card), [280, 5, 720, 55])
        XCTAssertEqual(frame(percent), [20, 0, 600, 100])
        XCTAssertEqual(frame(capped), [240, 0, 760, 50])
    }

    func testConstraintLayoutTopToBottomOfASiblingAndEndAnchor() {
        let cl = AConstraintLayout()
        typealias CLP = AConstraintLayout.LayoutParams
        let hud = AView()
        hud.viewId = "topHud"
        let lhud = CLP(0, 30)
        lhud.startToStart = CLP.PARENT_ID; lhud.endToEnd = CLP.PARENT_ID; lhud.topToTop = CLP.PARENT_ID
        lhud.marginStart = 6; lhud.marginEnd = 6; lhud.topMargin = 5
        cl.addView(hud, lhud)
        let button = AView()
        let lb = CLP(200, 34)
        lb.topToBottom = "topHud"; lb.endToEnd = CLP.PARENT_ID
        lb.topMargin = 4; lb.marginEnd = 7
        cl.addView(button, lb)
        // Bottom-anchored only: y2 = parent bottom - margin.
        let bottomPanel = AView()
        let lp = CLP(0, 100)
        lp.startToStart = CLP.PARENT_ID; lp.endToEnd = CLP.PARENT_ID; lp.bottomToBottom = CLP.PARENT_ID
        lp.bottomMargin = 8
        cl.addView(bottomPanel, lp)
        measureAndLayout(cl, exactly(1000), exactly(600))
        XCTAssertEqual(frame(hud), [6, 5, 994, 35])
        XCTAssertEqual(frame(button), [793, 39, 993, 73])
        XCTAssertEqual(frame(bottomPanel), [0, 492, 1000, 592])

        // RTL: start/end swap sides.
        cl.layoutDirection = AView.LAYOUT_DIRECTION_RTL
        measureAndLayout(cl, exactly(1000), exactly(600))
        XCTAssertEqual(frame(button), [7, 39, 207, 73])
    }

    // MARK: - Gravity and margins

    func testGravityResolution() {
        XCTAssertEqual(AGravity.START, 0x0080_0003)
        XCTAssertEqual(AGravity.END, 0x0080_0005)
        XCTAssertEqual(AGravity.getAbsoluteGravity(AGravity.START, AView.LAYOUT_DIRECTION_RTL), AGravity.RIGHT)
        XCTAssertEqual(AGravity.getAbsoluteGravity(AGravity.END, AView.LAYOUT_DIRECTION_RTL), AGravity.LEFT)
        XCTAssertEqual(AGravity.getAbsoluteGravity(AGravity.START | AGravity.CENTER_VERTICAL, AView.LAYOUT_DIRECTION_LTR),
                       AGravity.LEFT | AGravity.CENTER_VERTICAL)
        XCTAssertEqual(AGravity.getAbsoluteGravity(AGravity.CENTER, AView.LAYOUT_DIRECTION_RTL), AGravity.CENTER)
        let out = ARect()
        AGravity.apply(AGravity.CENTER, 100, 50, ARect(0, 0, 300, 200), out)
        XCTAssertEqual([out.left, out.top, out.right, out.bottom], [100, 75, 200, 125])
        AGravity.apply(AGravity.BOTTOM | AGravity.RIGHT, 100, 50, ARect(0, 0, 300, 200), out)
        XCTAssertEqual([out.left, out.top, out.right, out.bottom], [200, 150, 300, 200])
    }

    func testMarginLayoutParamsResolveStartAndEnd() {
        let lp = AViewGroup.MarginLayoutParams(10, 10)
        lp.marginStart = 7
        lp.marginEnd = 3
        lp.resolveLayoutDirection(AView.LAYOUT_DIRECTION_RTL)
        XCTAssertEqual(lp.leftMargin, 3)
        XCTAssertEqual(lp.rightMargin, 7)
        XCTAssertEqual(lp.marginStart, 7)
        lp.resolveLayoutDirection(AView.LAYOUT_DIRECTION_LTR)
        XCTAssertEqual(lp.leftMargin, 7)
        XCTAssertEqual(lp.rightMargin, 3)

        // Without relative margins, start/end read the left/right margins of the resolved direction.
        let plain = AViewGroup.MarginLayoutParams(10, 10)
        plain.setMargins(1, 2, 3, 4)
        XCTAssertEqual(plain.marginStart, 1)
        XCTAssertEqual(plain.marginEnd, 3)
        plain.resolveLayoutDirection(AView.LAYOUT_DIRECTION_RTL)
        XCTAssertEqual(plain.marginStart, 3)
        XCTAssertEqual(plain.leftMargin, 1)
    }

    func testRelativePaddingFollowsTheLayoutDirection() {
        let v = AFrameLayout()
        v.setPaddingRelative(4, 0, 9, 0)
        XCTAssertEqual(v.paddingLeft, 4)
        XCTAssertEqual(v.paddingRight, 9)
        v.layoutDirection = AView.LAYOUT_DIRECTION_RTL
        XCTAssertEqual(v.paddingLeft, 9)
        XCTAssertEqual(v.paddingRight, 4)
        XCTAssertEqual(v.paddingStart, 4)
        XCTAssertEqual(v.paddingEnd, 9)
    }

    // MARK: - Window insets

    func testWindowInsetsFromTheSafeArea() {
        let shown = AWindowInsetsCompat.fromSafeArea(left: 0, top: 141, right: 0, bottom: 102, statusBarVisible: true,
                                                     imeBottom: 0)
        XCTAssertEqual(shown.getInsets(AWindowInsetsCompat.systemBars()), AInsets.of(0, 141, 0, 102))
        XCTAssertEqual(shown.getInsets(AWindowInsetsCompat.statusBars()), AInsets.of(0, 141, 0, 0))
        XCTAssertEqual(shown.getInsets(AWindowInsetsCompat.navigationBars()), AInsets.of(0, 0, 0, 102))
        XCTAssertEqual(shown.getInsets(AWindowInsetsCompat.displayCutout()), AInsets.NONE)
        XCTAssertEqual(shown.getInsets(AWindowInsetsCompat.systemBars() | AWindowInsetsCompat.displayCutout()),
                       AInsets.of(0, 141, 0, 102))
        XCTAssertEqual(shown.getInsets(AWindowInsetsCompat.ime()), AInsets.NONE)
        XCTAssertFalse(shown.isConsumed)
        XCTAssertTrue(AWindowInsetsCompat.CONSUMED.isConsumed)

        // Hidden bars are not visible insets; the notch top becomes the cutout; the real sizes stay readable.
        let hidden = AWindowInsetsCompat.fromSafeArea(left: 0, top: 141, right: 0, bottom: 102, statusBarVisible: false,
                                                      navigationBarVisible: false, imeBottom: 0)
        XCTAssertEqual(hidden.getInsets(AWindowInsetsCompat.systemBars()), AInsets.NONE)
        XCTAssertEqual(hidden.getInsets(AWindowInsetsCompat.displayCutout()), AInsets.of(0, 141, 0, 0))
        XCTAssertEqual(hidden.getInsetsIgnoringVisibility(AWindowInsetsCompat.systemBars()), AInsets.of(0, 141, 0, 102))
        XCTAssertEqual(hidden.getInsets(AWindowInsetsCompat.systemBars() | AWindowInsetsCompat.displayCutout()),
                       AInsets.of(0, 141, 0, 0))
    }

    func testInsetsDispatchStopsOnlyAtAConsumingGroup() {
        let insets = AWindowInsetsCompat.fromSafeArea(left: 0, top: 100, right: 0, bottom: 50, statusBarVisible: true,
                                                      imeBottom: 0)
        let group = AFrameLayout()
        let first = AView(), second = AView()
        group.addView(first)
        group.addView(second)
        var secondSaw: AInsets? = nil
        AViewCompat.setOnApplyWindowInsetsListener(first) { _, _ in AWindowInsetsCompat.CONSUMED }
        AViewCompat.setOnApplyWindowInsetsListener(second) { _, i in
            secondSaw = i.getInsets(AWindowInsetsCompat.systemBars())
            return i
        }
        // A child consuming does not stop its siblings (targetSdk >= R dispatch).
        group.dispatchApplyWindowInsets(insets)
        XCTAssertEqual(secondSaw, AInsets.of(0, 100, 0, 50))
        // The group itself consuming stops the dispatch to every child.
        secondSaw = nil
        AViewCompat.setOnApplyWindowInsetsListener(group) { _, _ in AWindowInsetsCompat.CONSUMED }
        group.dispatchApplyWindowInsets(insets)
        XCTAssertNil(secondSaw)
    }

    // MARK: - Z order

    func testZOrderAndBringToFront() {
        let g = AFrameLayout()
        let a = AView(), b = AView(), c = AView()
        g.addView(a); g.addView(b); g.addView(c)
        XCTAssertTrue(g.buildOrderedChildList() == [a, b, c])
        a.elevation = 5
        XCTAssertTrue(g.buildOrderedChildList() == [b, c, a])
        b.translationZ = 6
        XCTAssertTrue(g.buildOrderedChildList() == [c, a, b])
        c.bringToFront()
        XCTAssertTrue(g.children == [a, b, c])
        a.bringToFront()
        XCTAssertTrue(g.children == [b, c, a])
        XCTAssertEqual(g.indexOfChild(a), 2)
    }

    // MARK: - MotionEvent

    func testMotionEventObtainOffsetAndSplit() {
        let e = AMotionEvent.obtain(1000, 1016, AMotionEvent.ACTION_MOVE, 10.5, 20.25, 0)
        XCTAssertEqual(e.downTime, 1000)
        XCTAssertEqual(e.eventTime, 1016)
        XCTAssertEqual(e.actionMasked, AMotionEvent.ACTION_MOVE)
        XCTAssertEqual(e.pointerCount, 1)
        XCTAssertEqual(e.getPointerId(0), 0)
        XCTAssertEqual(e.x, 10.5)
        XCTAssertEqual(e.y, 20.25)
        XCTAssertEqual(e.historySize, 0)
        e.offsetLocation(-5, 5)
        XCTAssertEqual(e.x, 5.5)
        XCTAssertEqual(e.y, 25.25)
        e.setLocation(1, 2)
        XCTAssertEqual(e.getX(0), 1)
        XCTAssertEqual(e.getY(0), 2)

        // POINTER_DOWN of pointer 1 (index 1).
        let pd = AMotionEvent.obtainTouch(downTime: 1000, eventTimeNanos: 1_020_000_000,
                                          action: AMotionEvent.ACTION_POINTER_DOWN | (1 << AMotionEvent.ACTION_POINTER_INDEX_SHIFT),
                                          pointerIds: [0, 1], xs: [10, 300], ys: [20, 400], rawXs: [10, 300], rawYs: [20, 400])
        XCTAssertEqual(pd.actionMasked, AMotionEvent.ACTION_POINTER_DOWN)
        XCTAssertEqual(pd.actionIndex, 1)
        XCTAssertEqual(pd.findPointerIndex(1), 1)
        XCTAssertEqual(pd.findPointerIndex(5), -1)
        XCTAssertEqual(pd.eventTime, 1020)
        // Split for pointer 1 alone: its own DOWN.
        let only1 = pd.split(1 << 1)
        XCTAssertEqual(only1.action, AMotionEvent.ACTION_DOWN)
        XCTAssertEqual(only1.pointerCount, 1)
        XCTAssertEqual(only1.getPointerId(0), 1)
        XCTAssertEqual(only1.x, 300)
        // Split for pointer 0: an unrelated pointer went down -> MOVE.
        let only0 = pd.split(1 << 0)
        XCTAssertEqual(only0.action, AMotionEvent.ACTION_MOVE)
        XCTAssertEqual(only0.getPointerId(0), 0)
    }

    // MARK: - ViewConfiguration

    func testViewConfigurationScaledValues() {
        // Pixel 3 density (2.75): (int)(8 * 2.75 + 0.5) = 22; (int)(2.75 * 100 + 0.5) = 275.
        let c = AViewConfiguration(density: 2.75, xlarge: false)
        XCTAssertEqual(c.scaledTouchSlop, 22)
        XCTAssertEqual(c.scaledDoubleTapTouchSlop, 22)
        XCTAssertEqual(c.scaledPagingTouchSlop, 44)
        XCTAssertEqual(c.scaledDoubleTapSlop, 275)
        XCTAssertEqual(c.scaledMinimumFlingVelocity, 138)
        XCTAssertEqual(c.scaledMaximumFlingVelocity, 22000)
        let iphone = AViewConfiguration(density: 3, xlarge: false)
        XCTAssertEqual(iphone.scaledTouchSlop, 24)
        XCTAssertEqual(iphone.scaledDoubleTapSlop, 300)
        XCTAssertEqual(AViewConfiguration.getTapTimeout(), 100)
        XCTAssertEqual(AViewConfiguration.getDoubleTapTimeout(), 300)
        XCTAssertEqual(AViewConfiguration.getDoubleTapMinTime(), 40)
        XCTAssertEqual(AViewConfiguration.getLongPressTimeout(), 400)
        XCTAssertEqual(AViewConfiguration.getPressedStateDuration(), 64)
    }

    // MARK: - GestureDetector (fake clock)

    private func ev(_ action: Int, _ downTime: Int64, _ x: Float = 100, _ y: Float = 100) -> AMotionEvent {
        AMotionEvent.obtain(downTime, AndroidKitTestLoop.nowMillis, action, x, y, 0)
    }

    func testGestureSingleTapIsConfirmedAfterTheDoubleTapTimeout() {
        let l = RecordingGestureListener()
        let d = AGestureDetector(l)
        let down = AndroidKitTestLoop.nowMillis
        d.onTouchEvent(ev(AMotionEvent.ACTION_DOWN, down))
        AndroidKitTestLoop.advance(millis: 50)
        d.onTouchEvent(ev(AMotionEvent.ACTION_UP, down))
        XCTAssertEqual(l.calls, ["down", "singleTapUp"])
        AndroidKitTestLoop.advance(millis: 249)
        XCTAssertEqual(l.calls, ["down", "singleTapUp"])
        AndroidKitTestLoop.advance(millis: 1)
        // TAP fires DOUBLE_TAP_TIMEOUT (300 ms) after the DOWN; SHOW_PRESS was removed by the UP.
        XCTAssertEqual(l.calls, ["down", "singleTapUp", "singleTapConfirmed"])
        XCTAssertEqual(l.downTimes, [down])
    }

    func testGestureLongPressAfter400msAndShowPressAfter100ms() {
        let l = RecordingGestureListener()
        let d = AGestureDetector(l)
        let down = AndroidKitTestLoop.nowMillis
        d.onTouchEvent(ev(AMotionEvent.ACTION_DOWN, down))
        AndroidKitTestLoop.advance(millis: 99)
        XCTAssertEqual(l.calls, ["down"])
        AndroidKitTestLoop.advance(millis: 1)
        XCTAssertEqual(l.calls, ["down", "showPress"])
        AndroidKitTestLoop.advance(millis: 299)
        XCTAssertEqual(l.calls, ["down", "showPress"])
        AndroidKitTestLoop.advance(millis: 1)
        XCTAssertEqual(l.calls, ["down", "showPress", "longPress"])
        d.onTouchEvent(ev(AMotionEvent.ACTION_UP, down))
        AndroidKitTestLoop.advance(millis: 400)
        // No tap after a long press (and the TAP message was removed by dispatchLongPress).
        XCTAssertEqual(l.calls, ["down", "showPress", "longPress"])
    }

    func testGestureDoubleTap() {
        let l = RecordingGestureListener()
        let d = AGestureDetector(l)
        let down1 = AndroidKitTestLoop.nowMillis
        d.onTouchEvent(ev(AMotionEvent.ACTION_DOWN, down1))
        AndroidKitTestLoop.advance(millis: 50)
        d.onTouchEvent(ev(AMotionEvent.ACTION_UP, down1))
        AndroidKitTestLoop.advance(millis: 100)
        // 100 ms between the first UP and the second DOWN: inside [40, 300].
        let down2 = AndroidKitTestLoop.nowMillis
        d.onTouchEvent(ev(AMotionEvent.ACTION_DOWN, down2, 110, 105))
        AndroidKitTestLoop.advance(millis: 40)
        d.onTouchEvent(ev(AMotionEvent.ACTION_UP, down2, 110, 105))
        AndroidKitTestLoop.advance(millis: 500)
        XCTAssertEqual(l.calls, ["down", "singleTapUp", "doubleTap", "doubleTapEvent(0)", "down", "doubleTapEvent(1)"])
    }

    func testGestureTooFastSecondTapIsNotADoubleTap() {
        let l = RecordingGestureListener()
        let d = AGestureDetector(l)
        let down1 = AndroidKitTestLoop.nowMillis
        d.onTouchEvent(ev(AMotionEvent.ACTION_DOWN, down1))
        AndroidKitTestLoop.advance(millis: 30)
        d.onTouchEvent(ev(AMotionEvent.ACTION_UP, down1))
        AndroidKitTestLoop.advance(millis: 20)
        // 20 ms < DOUBLE_TAP_MIN_TIME (40): a new first tap.
        let down2 = AndroidKitTestLoop.nowMillis
        d.onTouchEvent(ev(AMotionEvent.ACTION_DOWN, down2))
        AndroidKitTestLoop.advance(millis: 30)
        d.onTouchEvent(ev(AMotionEvent.ACTION_UP, down2))
        AndroidKitTestLoop.advance(millis: 400)
        XCTAssertEqual(l.calls, ["down", "singleTapUp", "down", "singleTapUp", "singleTapConfirmed"])
    }

    func testGestureSecondPointerCancelsTapAndLongPress() {
        let l = RecordingGestureListener()
        let d = AGestureDetector(l)
        let down = AndroidKitTestLoop.nowMillis
        d.onTouchEvent(ev(AMotionEvent.ACTION_DOWN, down))
        AndroidKitTestLoop.advance(millis: 50)
        let pd = AMotionEvent.obtainTouch(downTime: down, eventTimeNanos: AndroidKitTestLoop.nowNanos,
                                          action: AMotionEvent.ACTION_POINTER_DOWN | (1 << AMotionEvent.ACTION_POINTER_INDEX_SHIFT),
                                          pointerIds: [0, 1], xs: [100, 300], ys: [100, 300], rawXs: [100, 300], rawYs: [100, 300])
        d.onTouchEvent(pd)
        AndroidKitTestLoop.advance(millis: 600)
        XCTAssertEqual(l.calls, ["down"])
    }

    func testGestureScrollStartsBeyondTheTouchSlop() {
        let l = RecordingGestureListener()
        let d = AGestureDetector(l)
        let slop = AViewConfiguration.get().scaledTouchSlop
        let down = AndroidKitTestLoop.nowMillis
        d.onTouchEvent(ev(AMotionEvent.ACTION_DOWN, down, 100, 100))
        AndroidKitTestLoop.advance(millis: 16)
        // Exactly the slop: distance = slop^2, not > slop^2.
        d.onTouchEvent(ev(AMotionEvent.ACTION_MOVE, down, 100 + Float(slop), 100))
        XCTAssertEqual(l.calls, ["down"])
        AndroidKitTestLoop.advance(millis: 16)
        d.onTouchEvent(ev(AMotionEvent.ACTION_MOVE, down, 100 + Float(slop) + 1, 100))
        // distanceX = lastFocus - focus = 100 - (101 + slop).
        XCTAssertEqual(l.calls, ["down", "scroll(\(Float(-(slop + 1))),0.0)"])
    }

    // MARK: - Window root: attach, measure EXACTLY the container, touch dispatch

    private func makeWindowRoot(widthPt: CGFloat = 200, heightPt: CGFloat = 300) -> (UIWindow, AViewRoot) {
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: widthPt, height: heightPt))
        let host = UIView(frame: window.bounds)
        window.addSubview(host)
        return (window, AViewRoot(host: host))
    }

    func testViewRootAttachesOnTheFirstTraversalAndMeasuresTheContainer() {
        let (window, root) = makeWindowRoot()
        let decor = AFrameLayout()
        let child = AView()
        decor.addView(child, AFrameLayout.LayoutParams(MATCH, MATCH))
        var attachedAt: Int64 = -1
        child.addOnAttachStateChangeListener(AOnAttachStateChangeListener({ _ in attachedAt = AndroidKitTestLoop.nowMillis }))
        root.contentView = decor
        // Android: setView only schedules; the first traversal attaches, measures and lays out.
        XCTAssertFalse(decor.isAttachedToWindow)
        XCTAssertTrue(decor.isShown)
        AndroidKitTestLoop.advance(millis: 20)
        XCTAssertTrue(decor.isAttachedToWindow)
        XCTAssertTrue(child.isAttachedToWindow)
        XCTAssertNotEqual(attachedAt, -1)
        let scale = UIScreen.main.scale
        let w = Int((200 * scale).rounded()), h = Int((300 * scale).rounded())
        XCTAssertEqual(root.widthPx, w)
        XCTAssertEqual(root.heightPx, h)
        XCTAssertEqual(frame(decor), [0, 0, w, h])
        XCTAssertEqual(frame(child), [0, 0, w, h])
        XCTAssertNotNil(root.lastDispatchedInsets)
        XCTAssertTrue(AViewRoot.liveRoots.contains { $0 === root })
        // A posted runnable runs on the window's handler.
        var ran = false
        child.post { ran = true }
        AndroidKitTestLoop.runDueMessages()
        XCTAssertTrue(ran)
        root.dispose()
        XCTAssertFalse(decor.isAttachedToWindow)
        _ = window
    }

    func testViewRootRunsRequestedLayoutsInTheNextFrame() {
        let (window, root) = makeWindowRoot()
        let decor = AFrameLayout()
        let child = AView()
        decor.addView(child, AFrameLayout.LayoutParams(100, 50))
        root.contentView = decor
        AndroidKitTestLoop.advance(millis: 20)
        XCTAssertEqual(child.width, 100)
        var globalLayouts = 0
        decor.viewTreeObserver.addOnGlobalLayoutListener(AOnGlobalLayoutListener { globalLayouts += 1 })
        child.layoutParams = AFrameLayout.LayoutParams(120, 60, AGravity.BOTTOM | AGravity.RIGHT)
        XCTAssertEqual(child.width, 100)
        AndroidKitTestLoop.advance(millis: 20)
        XCTAssertEqual(child.width, 120)
        XCTAssertEqual(child.right, root.widthPx)
        XCTAssertEqual(child.bottom, root.heightPx)
        XCTAssertEqual(globalLayouts, 1)
        root.dispose()
        _ = window
    }

    func testTouchFallsThroughANonConsumingViewToTheClickableViewBelow() {
        let (window, root) = makeWindowRoot()
        let decor = AFrameLayout()
        let button = AView()
        var clicks = 0
        button.setOnClickListener { _ in clicks += 1 }
        let cover = AView()
        decor.addView(button, AFrameLayout.LayoutParams(300, 300))
        decor.addView(cover, AFrameLayout.LayoutParams(300, 300))
        root.contentView = decor
        AndroidKitTestLoop.advance(millis: 20)

        let t = AndroidKitTestLoop.nowMillis
        root.injectTouchEvent(AMotionEvent.obtain(t, t, AMotionEvent.ACTION_DOWN, 100, 100, 0))
        XCTAssertTrue(button.isPressed)
        AndroidKitTestLoop.advance(millis: 40)
        root.injectTouchEvent(AMotionEvent.obtain(t, AndroidKitTestLoop.nowMillis, AMotionEvent.ACTION_UP, 100, 100, 0))
        // The click is posted (View.PerformClick), so it runs after the UP.
        XCTAssertEqual(clicks, 0)
        AndroidKitTestLoop.runDueMessages()
        XCTAssertEqual(clicks, 1)
        XCTAssertFalse(button.isPressed)
        root.dispose()
        _ = window
    }

    func testMovingBeyondTheSlopOutsideTheViewCancelsTheClick() {
        let (window, root) = makeWindowRoot()
        let decor = AFrameLayout()
        let button = AView()
        var clicks = 0
        button.setOnClickListener { _ in clicks += 1 }
        decor.addView(button, AFrameLayout.LayoutParams(300, 300))
        root.contentView = decor
        AndroidKitTestLoop.advance(millis: 20)
        let slop = Float(AViewConfiguration.get().scaledTouchSlop)
        let t = AndroidKitTestLoop.nowMillis
        root.injectTouchEvent(AMotionEvent.obtain(t, t, AMotionEvent.ACTION_DOWN, 290, 100, 0))
        // Inside the slop band outside the bounds: still pressed.
        root.injectTouchEvent(AMotionEvent.obtain(t, t + 10, AMotionEvent.ACTION_MOVE, 300 + slop - 1, 100, 0))
        XCTAssertTrue(button.isPressed)
        root.injectTouchEvent(AMotionEvent.obtain(t, t + 20, AMotionEvent.ACTION_MOVE, 300 + slop + 1, 100, 0))
        XCTAssertFalse(button.isPressed)
        root.injectTouchEvent(AMotionEvent.obtain(t, t + 30, AMotionEvent.ACTION_UP, 300 + slop + 1, 100, 0))
        AndroidKitTestLoop.advance(millis: 100)
        XCTAssertEqual(clicks, 0)
        root.dispose()
        _ = window
    }

    func testLongClickAfter400ms() {
        let (window, root) = makeWindowRoot()
        let decor = AFrameLayout()
        let button = AView()
        var clicks = 0, longClicks = 0
        button.setOnClickListener { _ in clicks += 1 }
        button.setOnLongClickListener { _ in longClicks += 1; return true }
        decor.addView(button, AFrameLayout.LayoutParams(300, 300))
        root.contentView = decor
        AndroidKitTestLoop.advance(millis: 20)
        let t = AndroidKitTestLoop.nowMillis
        root.injectTouchEvent(AMotionEvent.obtain(t, t, AMotionEvent.ACTION_DOWN, 100, 100, 0))
        AndroidKitTestLoop.advance(millis: 399)
        XCTAssertEqual(longClicks, 0)
        AndroidKitTestLoop.advance(millis: 1)
        XCTAssertEqual(longClicks, 1)
        root.injectTouchEvent(AMotionEvent.obtain(t, AndroidKitTestLoop.nowMillis, AMotionEvent.ACTION_UP, 100, 100, 0))
        AndroidKitTestLoop.advance(millis: 100)
        // A performed long press suppresses the click.
        XCTAssertEqual(clicks, 0)
        root.dispose()
        _ = window
    }

    func testInterceptingParentSendsCancelToTheChild() {
        let (window, root) = makeWindowRoot()
        let decor = AFrameLayout()
        let group = InterceptOnMoveLayout()
        let child = TouchRecorderView()
        group.addView(child, AFrameLayout.LayoutParams(MATCH, MATCH))
        decor.addView(group, AFrameLayout.LayoutParams(400, 400))
        root.contentView = decor
        AndroidKitTestLoop.advance(millis: 20)
        let t = AndroidKitTestLoop.nowMillis
        root.injectTouchEvent(AMotionEvent.obtain(t, t, AMotionEvent.ACTION_DOWN, 50, 50, 0))
        root.injectTouchEvent(AMotionEvent.obtain(t, t + 16, AMotionEvent.ACTION_MOVE, 80, 50, 0))
        root.injectTouchEvent(AMotionEvent.obtain(t, t + 32, AMotionEvent.ACTION_MOVE, 120, 50, 0))
        XCTAssertEqual(child.actions, [AMotionEvent.ACTION_DOWN, AMotionEvent.ACTION_CANCEL])
        root.dispose()
        _ = window
    }

    func testDisallowInterceptKeepsTheGestureInTheChild() {
        let (window, root) = makeWindowRoot()
        let decor = AFrameLayout()
        let group = InterceptOnMoveLayout()
        let child = TouchRecorderView()
        child.setOnTouchListener { v, e in
            if e.actionMasked == AMotionEvent.ACTION_DOWN { v.parentGroup?.requestDisallowInterceptTouchEvent(true) }
            return false
        }
        group.addView(child, AFrameLayout.LayoutParams(MATCH, MATCH))
        decor.addView(group, AFrameLayout.LayoutParams(400, 400))
        root.contentView = decor
        AndroidKitTestLoop.advance(millis: 20)
        let t = AndroidKitTestLoop.nowMillis
        root.injectTouchEvent(AMotionEvent.obtain(t, t, AMotionEvent.ACTION_DOWN, 50, 50, 0))
        root.injectTouchEvent(AMotionEvent.obtain(t, t + 16, AMotionEvent.ACTION_MOVE, 80, 50, 0))
        root.injectTouchEvent(AMotionEvent.obtain(t, t + 32, AMotionEvent.ACTION_UP, 80, 50, 0))
        XCTAssertEqual(child.actions, [AMotionEvent.ACTION_DOWN, AMotionEvent.ACTION_MOVE, AMotionEvent.ACTION_UP])
        root.dispose()
        _ = window
    }

    func testAlphaZeroViewStillTakesTouchesButInvisibleDoesNot() {
        let (window, root) = makeWindowRoot()
        let decor = AFrameLayout()
        let below = TouchRecorderView()
        let top = TouchRecorderView()
        decor.addView(below, AFrameLayout.LayoutParams(300, 300))
        decor.addView(top, AFrameLayout.LayoutParams(300, 300))
        root.contentView = decor
        AndroidKitTestLoop.advance(millis: 20)
        top.alpha = 0
        var t = AndroidKitTestLoop.nowMillis
        root.injectTouchEvent(AMotionEvent.obtain(t, t, AMotionEvent.ACTION_DOWN, 10, 10, 0))
        root.injectTouchEvent(AMotionEvent.obtain(t, t + 5, AMotionEvent.ACTION_UP, 10, 10, 0))
        XCTAssertEqual(top.actions, [AMotionEvent.ACTION_DOWN, AMotionEvent.ACTION_UP])
        XCTAssertEqual(below.actions, [])
        top.visibility = AView.INVISIBLE
        AndroidKitTestLoop.advance(millis: 20)
        t = AndroidKitTestLoop.nowMillis
        root.injectTouchEvent(AMotionEvent.obtain(t, t, AMotionEvent.ACTION_DOWN, 10, 10, 0))
        root.injectTouchEvent(AMotionEvent.obtain(t, t + 5, AMotionEvent.ACTION_UP, 10, 10, 0))
        XCTAssertEqual(below.actions, [AMotionEvent.ACTION_DOWN, AMotionEvent.ACTION_UP])
        root.dispose()
        _ = window
    }

    func testInvalidateDuringDrawOfAParentDrawsTheChildInTheSamePass() {
        let (window, root) = makeWindowRoot()
        let decor = AFrameLayout()
        let parent = TraversalDrawingLayout()
        let child = TraversalDrawingView()
        parent.child = child
        parent.addView(child, AFrameLayout.LayoutParams(MATCH, MATCH))
        decor.addView(parent, AFrameLayout.LayoutParams(MATCH, MATCH))
        root.contentView = decor
        AndroidKitTestLoop.advance(millis: 20)
        let parentDraws = parent.draws, childDraws = child.draws
        XCTAssertGreaterThan(parentDraws, 0)
        parent.invalidate()
        AndroidKitTestLoop.advance(millis: 17)
        // The parent's onDraw invalidated the child before the walk reached it: both drew in the same frame.
        XCTAssertEqual(parent.draws, parentDraws + 1)
        XCTAssertEqual(child.draws, childDraws + 1)
        root.dispose()
        _ = window
    }
}

/// A group drawn in the traversal (like the court views) whose onDraw invalidates its child.
private final class TraversalDrawingLayout: AFrameLayout {
    var draws = 0
    weak var child: AView?
    override var drawsInTraversal: Bool { true }
    override init() {
        super.init()
        setWillNotDraw(false)
    }
    override func onDraw(_ canvas: ACanvas) {
        draws += 1
        child?.invalidate()
    }
}

private final class TraversalDrawingView: AView {
    var draws = 0
    override var drawsInTraversal: Bool { true }
    override func onDraw(_ canvas: ACanvas) {
        draws += 1
    }
}
