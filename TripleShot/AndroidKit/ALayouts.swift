import UIKit

// The Android layouts the app uses, on AViewGroup (VIEW-API "Views"): android.view.Gravity, FrameLayout,
// LinearLayout, ScrollView, HorizontalScrollView, android.widget.Space and the ConstraintLayout subset of the XML
// layouts. Measure and layout are statement-by-statement ports of the AOSP classes (android-37 sources, targetSdk 36:
// sRemeasureWeightedChildren = true, mAllowInconsistentMeasurement = false, preserved margin params on conversion,
// margins counted in fillViewport). All values are Android pixels.
//
// Scroll views are UIScrollView-backed: the child is hosted in a UIScrollView whose content offset mirrors
// mScrollX/mScrollY in both directions (UIKit drag and deceleration update the Android scroll position; scrollTo,
// smoothScrollBy and the first-layout RTL start position of HorizontalScrollView move the UIScrollView). Dragging and
// flinging use the iOS physics; smoothScrollBy/smoothScrollTo run Android's OverScroller (250 ms, viscous fluid).

// MARK: - Gravity

/// android.view.Gravity.
enum AGravity {
    static let NO_GRAVITY = 0x0000
    static let AXIS_SPECIFIED = 0x0001
    static let AXIS_PULL_BEFORE = 0x0002
    static let AXIS_PULL_AFTER = 0x0004
    static let AXIS_CLIP = 0x0008
    static let AXIS_X_SHIFT = 0
    static let AXIS_Y_SHIFT = 4
    static let TOP = (AXIS_PULL_BEFORE | AXIS_SPECIFIED) << AXIS_Y_SHIFT
    static let BOTTOM = (AXIS_PULL_AFTER | AXIS_SPECIFIED) << AXIS_Y_SHIFT
    static let LEFT = (AXIS_PULL_BEFORE | AXIS_SPECIFIED) << AXIS_X_SHIFT
    static let RIGHT = (AXIS_PULL_AFTER | AXIS_SPECIFIED) << AXIS_X_SHIFT
    static let CENTER_VERTICAL = AXIS_SPECIFIED << AXIS_Y_SHIFT
    static let FILL_VERTICAL = TOP | BOTTOM
    static let CENTER_HORIZONTAL = AXIS_SPECIFIED << AXIS_X_SHIFT
    static let FILL_HORIZONTAL = LEFT | RIGHT
    static let CENTER = CENTER_VERTICAL | CENTER_HORIZONTAL
    static let FILL = FILL_VERTICAL | FILL_HORIZONTAL
    static let CLIP_VERTICAL = AXIS_CLIP << AXIS_Y_SHIFT
    static let CLIP_HORIZONTAL = AXIS_CLIP << AXIS_X_SHIFT
    static let RELATIVE_LAYOUT_DIRECTION = 0x00800000
    static let HORIZONTAL_GRAVITY_MASK = (AXIS_SPECIFIED | AXIS_PULL_BEFORE | AXIS_PULL_AFTER) << AXIS_X_SHIFT
    static let VERTICAL_GRAVITY_MASK = (AXIS_SPECIFIED | AXIS_PULL_BEFORE | AXIS_PULL_AFTER) << AXIS_Y_SHIFT
    static let DISPLAY_CLIP_VERTICAL = 0x10000000
    static let DISPLAY_CLIP_HORIZONTAL = 0x01000000
    static let START = RELATIVE_LAYOUT_DIRECTION | LEFT
    static let END = RELATIVE_LAYOUT_DIRECTION | RIGHT
    static let RELATIVE_HORIZONTAL_GRAVITY_MASK = START | END

    static func apply(_ gravity: Int, _ w: Int, _ h: Int, _ container: ARect, _ outRect: ARect) {
        apply(gravity, w, h, container, 0, 0, outRect)
    }

    static func apply(_ gravity: Int, _ w: Int, _ h: Int, _ container: ARect, _ outRect: ARect,
                      _ layoutDirection: Int) {
        let absGravity = getAbsoluteGravity(gravity, layoutDirection)
        apply(absGravity, w, h, container, 0, 0, outRect)
    }

    static func apply(_ gravity: Int, _ w: Int, _ h: Int, _ container: ARect, _ xAdj: Int, _ yAdj: Int,
                      _ outRect: ARect, _ layoutDirection: Int) {
        let absGravity = getAbsoluteGravity(gravity, layoutDirection)
        apply(absGravity, w, h, container, xAdj, yAdj, outRect)
    }

    /// Gravity.apply(gravity, w, h, container, xAdj, yAdj, outRect).
    static func apply(_ gravity: Int, _ w: Int, _ h: Int, _ container: ARect, _ xAdj: Int, _ yAdj: Int,
                      _ outRect: ARect) {
        let r = applyRect(gravity, w, h, (container.left, container.top, container.right, container.bottom), xAdj, yAdj)
        outRect.left = r.0
        outRect.top = r.1
        outRect.right = r.2
        outRect.bottom = r.3
    }

    /// Gravity.apply with the layout direction, on plain edges (l, t, r, b) (View foreground placement).
    static func applyRect(_ gravity: Int, _ w: Int, _ h: Int, _ container: (Int, Int, Int, Int),
                          _ layoutDirection: Int) -> (Int, Int, Int, Int) {
        applyRect(getAbsoluteGravity(gravity, layoutDirection), w, h, container, 0, 0)
    }

    /// The arithmetic of Gravity.apply (absolute gravity) on plain edges.
    static func applyRect(_ gravity: Int, _ w: Int, _ h: Int, _ container: (Int, Int, Int, Int),
                          _ xAdj: Int, _ yAdj: Int) -> (Int, Int, Int, Int) {
        let (cl, ct, cr, cb) = container
        var left = 0, top = 0, right = 0, bottom = 0
        switch gravity & ((AXIS_PULL_BEFORE | AXIS_PULL_AFTER) << AXIS_X_SHIFT) {
        case 0:
            left = cl + ((cr - cl - w) / 2) + xAdj
            right = left + w
            if (gravity & (AXIS_CLIP << AXIS_X_SHIFT)) == (AXIS_CLIP << AXIS_X_SHIFT) {
                if left < cl { left = cl }
                if right > cr { right = cr }
            }
        case AXIS_PULL_BEFORE << AXIS_X_SHIFT:
            left = cl + xAdj
            right = left + w
            if (gravity & (AXIS_CLIP << AXIS_X_SHIFT)) == (AXIS_CLIP << AXIS_X_SHIFT) {
                if right > cr { right = cr }
            }
        case AXIS_PULL_AFTER << AXIS_X_SHIFT:
            right = cr - xAdj
            left = right - w
            if (gravity & (AXIS_CLIP << AXIS_X_SHIFT)) == (AXIS_CLIP << AXIS_X_SHIFT) {
                if left < cl { left = cl }
            }
        default:
            left = cl + xAdj
            right = cr + xAdj
        }
        switch gravity & ((AXIS_PULL_BEFORE | AXIS_PULL_AFTER) << AXIS_Y_SHIFT) {
        case 0:
            top = ct + ((cb - ct - h) / 2) + yAdj
            bottom = top + h
            if (gravity & (AXIS_CLIP << AXIS_Y_SHIFT)) == (AXIS_CLIP << AXIS_Y_SHIFT) {
                if top < ct { top = ct }
                if bottom > cb { bottom = cb }
            }
        case AXIS_PULL_BEFORE << AXIS_Y_SHIFT:
            top = ct + yAdj
            bottom = top + h
            if (gravity & (AXIS_CLIP << AXIS_Y_SHIFT)) == (AXIS_CLIP << AXIS_Y_SHIFT) {
                if bottom > cb { bottom = cb }
            }
        case AXIS_PULL_AFTER << AXIS_Y_SHIFT:
            bottom = cb - yAdj
            top = bottom - h
            if (gravity & (AXIS_CLIP << AXIS_Y_SHIFT)) == (AXIS_CLIP << AXIS_Y_SHIFT) {
                if top < ct { top = ct }
            }
        default:
            top = ct + yAdj
            bottom = cb + yAdj
        }
        return (left, top, right, bottom)
    }

    /// Gravity.applyDisplay.
    static func applyDisplay(_ gravity: Int, _ display: ARect, _ inoutObj: ARect) {
        if (gravity & DISPLAY_CLIP_VERTICAL) != 0 {
            if inoutObj.top < display.top { inoutObj.top = display.top }
            if inoutObj.bottom > display.bottom { inoutObj.bottom = display.bottom }
        } else {
            var off = 0
            if inoutObj.top < display.top {
                off = display.top - inoutObj.top
            } else if inoutObj.bottom > display.bottom {
                off = display.bottom - inoutObj.bottom
            }
            if off != 0 {
                if inoutObj.height() > (display.bottom - display.top) {
                    inoutObj.top = display.top
                    inoutObj.bottom = display.bottom
                } else {
                    inoutObj.top += off
                    inoutObj.bottom += off
                }
            }
        }
        if (gravity & DISPLAY_CLIP_HORIZONTAL) != 0 {
            if inoutObj.left < display.left { inoutObj.left = display.left }
            if inoutObj.right > display.right { inoutObj.right = display.right }
        } else {
            var off = 0
            if inoutObj.left < display.left {
                off = display.left - inoutObj.left
            } else if inoutObj.right > display.right {
                off = display.right - inoutObj.right
            }
            if off != 0 {
                if inoutObj.width() > (display.right - display.left) {
                    inoutObj.left = display.left
                    inoutObj.right = display.right
                } else {
                    inoutObj.left += off
                    inoutObj.right += off
                }
            }
        }
    }

    static func applyDisplay(_ gravity: Int, _ display: ARect, _ inoutObj: ARect, _ layoutDirection: Int) {
        applyDisplay(getAbsoluteGravity(gravity, layoutDirection), display, inoutObj)
    }

    static func isVertical(_ gravity: Int) -> Bool {
        gravity > 0 && (gravity & VERTICAL_GRAVITY_MASK) != 0
    }

    static func isHorizontal(_ gravity: Int) -> Bool {
        gravity > 0 && (gravity & RELATIVE_HORIZONTAL_GRAVITY_MASK) != 0
    }

    /// Gravity.getAbsoluteGravity: START/END become LEFT/RIGHT for the layout direction.
    static func getAbsoluteGravity(_ gravity: Int, _ layoutDirection: Int) -> Int {
        var result = gravity
        // If layout is script specific and gravity is horizontal relative (START or END)
        if (result & RELATIVE_LAYOUT_DIRECTION) > 0 {
            if (result & START) == START {
                // Remove the START bit
                result &= ~START
                if layoutDirection == AView.LAYOUT_DIRECTION_RTL {
                    // Set the RIGHT bit
                    result |= RIGHT
                } else {
                    // Set the LEFT bit
                    result |= LEFT
                }
            } else if (result & END) == END {
                // Remove the END bit
                result &= ~END
                if layoutDirection == AView.LAYOUT_DIRECTION_RTL {
                    // Set the LEFT bit
                    result |= LEFT
                } else {
                    // Set the RIGHT bit
                    result |= RIGHT
                }
            }
            // Don't need the script specific bit any more, so remove it as we are converting to absolute values
            // (LEFT or RIGHT)
            result &= ~RELATIVE_LAYOUT_DIRECTION
        }
        return result
    }

    static func toString(_ gravity: Int) -> String {
        var result: [String] = []
        if (gravity & FILL) == FILL {
            result.append("FILL")
        } else {
            if (gravity & FILL_VERTICAL) == FILL_VERTICAL {
                result.append("FILL_VERTICAL")
            } else {
                if (gravity & TOP) == TOP { result.append("TOP") }
                if (gravity & BOTTOM) == BOTTOM { result.append("BOTTOM") }
            }
            if (gravity & FILL_HORIZONTAL) == FILL_HORIZONTAL {
                result.append("FILL_HORIZONTAL")
            } else {
                if (gravity & START) == START {
                    result.append("START")
                } else if (gravity & LEFT) == LEFT {
                    result.append("LEFT")
                }
                if (gravity & END) == END {
                    result.append("END")
                } else if (gravity & RIGHT) == RIGHT {
                    result.append("RIGHT")
                }
            }
        }
        if (gravity & CENTER) == CENTER {
            result.append("CENTER")
        } else {
            if (gravity & CENTER_VERTICAL) == CENTER_VERTICAL { result.append("CENTER_VERTICAL") }
            if (gravity & CENTER_HORIZONTAL) == CENTER_HORIZONTAL { result.append("CENTER_HORIZONTAL") }
        }
        if result.isEmpty { result.append("NO GRAVITY") }
        if (gravity & DISPLAY_CLIP_VERTICAL) == DISPLAY_CLIP_VERTICAL { result.append("DISPLAY_CLIP_VERTICAL") }
        if (gravity & DISPLAY_CLIP_HORIZONTAL) == DISPLAY_CLIP_HORIZONTAL { result.append("DISPLAY_CLIP_HORIZONTAL") }
        return result.joined(separator: " ")
    }
}

// MARK: - FrameLayout

/// android.widget.FrameLayout.
class AFrameLayout: AViewGroup {

    /// FrameLayout.LayoutParams: margins plus layout_gravity (-1 = unspecified: TOP | START).
    class LayoutParams: AViewGroup.MarginLayoutParams {
        static let UNSPECIFIED_GRAVITY = -1

        var gravity = LayoutParams.UNSPECIFIED_GRAVITY

        override init(_ width: Int, _ height: Int) {
            super.init(width, height)
        }

        init(_ width: Int, _ height: Int, _ gravity: Int) {
            super.init(width, height)
            self.gravity = gravity
        }

        override init(_ source: AViewGroup.LayoutParams) {
            super.init(source)
        }

        override init(_ source: AViewGroup.MarginLayoutParams) {
            super.init(source)
        }

        /// Copy constructor: margins and gravity.
        init(_ source: AFrameLayout.LayoutParams) {
            super.init(source as AViewGroup.MarginLayoutParams)
            self.gravity = source.gravity
        }
    }

    private static let DEFAULT_CHILD_GRAVITY = AGravity.TOP | AGravity.START

    var mMeasureAllChildren = false
    private var mForegroundPaddingLeft = 0
    private var mForegroundPaddingTop = 0
    private var mForegroundPaddingRight = 0
    private var mForegroundPaddingBottom = 0
    private var mMatchParentChildren: [AView] = []

    override init() {
        super.init()
    }

    /// FrameLayout.setForegroundGravity: also takes the foreground's padding for FILL.
    override func setForegroundGravity(_ foregroundGravity: Int) {
        if self.foregroundGravity != foregroundGravity {
            super.setForegroundGravity(foregroundGravity)

            // calling get* again here because the set above may apply default constraints
            let fg = foreground
            if self.foregroundGravity == AGravity.FILL, let fg = fg {
                let padding = ARect()
                if fg.getPadding(padding) {
                    mForegroundPaddingLeft = padding.left
                    mForegroundPaddingTop = padding.top
                    mForegroundPaddingRight = padding.right
                    mForegroundPaddingBottom = padding.bottom
                }
            } else {
                mForegroundPaddingLeft = 0
                mForegroundPaddingTop = 0
                mForegroundPaddingRight = 0
                mForegroundPaddingBottom = 0
            }
            requestLayout()
        }
    }

    /// FrameLayout.generateDefaultLayoutParams: (MATCH_PARENT, MATCH_PARENT).
    override func generateDefaultLayoutParams() -> AViewGroup.LayoutParams {
        LayoutParams(AViewGroup.LayoutParams.MATCH_PARENT, AViewGroup.LayoutParams.MATCH_PARENT)
    }

    func getPaddingLeftWithForeground() -> Int {
        isForegroundInsidePadding ? max(mPaddingLeft, mForegroundPaddingLeft) : mPaddingLeft + mForegroundPaddingLeft
    }

    func getPaddingRightWithForeground() -> Int {
        isForegroundInsidePadding ? max(mPaddingRight, mForegroundPaddingRight) : mPaddingRight + mForegroundPaddingRight
    }

    private func getPaddingTopWithForeground() -> Int {
        isForegroundInsidePadding ? max(mPaddingTop, mForegroundPaddingTop) : mPaddingTop + mForegroundPaddingTop
    }

    private func getPaddingBottomWithForeground() -> Int {
        isForegroundInsidePadding ? max(mPaddingBottom, mForegroundPaddingBottom) : mPaddingBottom + mForegroundPaddingBottom
    }

    override func onMeasure(_ widthMeasureSpec: Int, _ heightMeasureSpec: Int) {
        ensureResolvedPadding()
        var count = childCount

        let measureMatchParentChildren = AMeasureSpec.getMode(widthMeasureSpec) != AMeasureSpec.EXACTLY
            || AMeasureSpec.getMode(heightMeasureSpec) != AMeasureSpec.EXACTLY
        mMatchParentChildren.removeAll()

        var maxHeight = 0
        var maxWidth = 0
        var childState = 0

        for i in 0..<count {
            let child = mChildren[i]
            if mMeasureAllChildren || child.visibility != AView.GONE {
                measureChildWithMargins(child, widthMeasureSpec, 0, heightMeasureSpec, 0)
                let lp = child.mLayoutParams as! AViewGroup.MarginLayoutParams
                maxWidth = max(maxWidth, child.measuredWidth + lp.leftMargin + lp.rightMargin)
                maxHeight = max(maxHeight, child.measuredHeight + lp.topMargin + lp.bottomMargin)
                childState = AView.combineMeasuredStates(childState, child.measuredState)
                if measureMatchParentChildren {
                    if lp.width == AViewGroup.LayoutParams.MATCH_PARENT || lp.height == AViewGroup.LayoutParams.MATCH_PARENT {
                        mMatchParentChildren.append(child)
                    }
                }
            }
        }

        // Account for padding too
        maxWidth += getPaddingLeftWithForeground() + getPaddingRightWithForeground()
        maxHeight += getPaddingTopWithForeground() + getPaddingBottomWithForeground()

        // Check against our minimum height and width
        maxHeight = max(maxHeight, getSuggestedMinimumHeight())
        maxWidth = max(maxWidth, getSuggestedMinimumWidth())

        // Check against our foreground's minimum height and width
        if let drawable = foreground {
            maxHeight = max(maxHeight, AView.drawableMinimumHeight(drawable))
            maxWidth = max(maxWidth, AView.drawableMinimumWidth(drawable))
        }

        setMeasuredDimension(AView.resolveSizeAndState(maxWidth, widthMeasureSpec, childState),
                             AView.resolveSizeAndState(maxHeight, heightMeasureSpec,
                                                       childState << AView.MEASURED_HEIGHT_STATE_SHIFT))

        count = mMatchParentChildren.count
        if count > 1 {
            for i in 0..<count {
                let child = mMatchParentChildren[i]
                let lp = child.mLayoutParams as! AViewGroup.MarginLayoutParams

                let childWidthMeasureSpec: Int
                if lp.width == AViewGroup.LayoutParams.MATCH_PARENT {
                    let width = max(0, measuredWidth - getPaddingLeftWithForeground() - getPaddingRightWithForeground()
                                    - lp.leftMargin - lp.rightMargin)
                    childWidthMeasureSpec = AMeasureSpec.makeMeasureSpec(width, AMeasureSpec.EXACTLY)
                } else {
                    childWidthMeasureSpec = AViewGroup.getChildMeasureSpec(widthMeasureSpec,
                        getPaddingLeftWithForeground() + getPaddingRightWithForeground() + lp.leftMargin + lp.rightMargin,
                        lp.width)
                }

                let childHeightMeasureSpec: Int
                if lp.height == AViewGroup.LayoutParams.MATCH_PARENT {
                    let height = max(0, measuredHeight - getPaddingTopWithForeground() - getPaddingBottomWithForeground()
                                     - lp.topMargin - lp.bottomMargin)
                    childHeightMeasureSpec = AMeasureSpec.makeMeasureSpec(height, AMeasureSpec.EXACTLY)
                } else {
                    childHeightMeasureSpec = AViewGroup.getChildMeasureSpec(heightMeasureSpec,
                        getPaddingTopWithForeground() + getPaddingBottomWithForeground() + lp.topMargin + lp.bottomMargin,
                        lp.height)
                }

                child.measure(childWidthMeasureSpec, childHeightMeasureSpec)
            }
        }
    }

    override func onLayout(_ changed: Bool, _ left: Int, _ top: Int, _ right: Int, _ bottom: Int) {
        layoutChildren(left, top, right, bottom, false /* no force left gravity */)
    }

    /// FrameLayout.layoutChildren.
    func layoutChildren(_ left: Int, _ top: Int, _ right: Int, _ bottom: Int, _ forceLeftGravity: Bool) {
        let count = childCount

        let parentLeft = getPaddingLeftWithForeground()
        let parentRight = right - left - getPaddingRightWithForeground()

        let parentTop = getPaddingTopWithForeground()
        let parentBottom = bottom - top - getPaddingBottomWithForeground()

        for i in 0..<count {
            let child = mChildren[i]
            if child.visibility != AView.GONE {
                let lp = child.mLayoutParams as! AViewGroup.MarginLayoutParams

                let width = child.measuredWidth
                let height = child.measuredHeight

                var childLeft: Int
                var childTop: Int

                var gravity = (lp as? AFrameLayout.LayoutParams)?.gravity ?? -1
                if gravity == -1 {
                    gravity = AFrameLayout.DEFAULT_CHILD_GRAVITY
                }

                let layoutDirection = self.layoutDirection
                let absoluteGravity = AGravity.getAbsoluteGravity(gravity, layoutDirection)
                let verticalGravity = gravity & AGravity.VERTICAL_GRAVITY_MASK

                switch absoluteGravity & AGravity.HORIZONTAL_GRAVITY_MASK {
                case AGravity.CENTER_HORIZONTAL:
                    childLeft = parentLeft + (parentRight - parentLeft - width) / 2 + lp.leftMargin - lp.rightMargin
                case AGravity.RIGHT where !forceLeftGravity:
                    childLeft = parentRight - width - lp.rightMargin
                default:
                    childLeft = parentLeft + lp.leftMargin
                }

                switch verticalGravity {
                case AGravity.TOP:
                    childTop = parentTop + lp.topMargin
                case AGravity.CENTER_VERTICAL:
                    childTop = parentTop + (parentBottom - parentTop - height) / 2 + lp.topMargin - lp.bottomMargin
                case AGravity.BOTTOM:
                    childTop = parentBottom - height - lp.bottomMargin
                default:
                    childTop = parentTop + lp.topMargin
                }

                child.layout(childLeft, childTop, childLeft + width, childTop + height)
            }
        }
    }

    /// setMeasureAllChildren / getMeasureAllChildren.
    var measureAllChildren: Bool {
        get { mMeasureAllChildren }
        set { mMeasureAllChildren = newValue }
    }
    func setMeasureAllChildren(_ measureAll: Bool) { mMeasureAllChildren = measureAll }
    func getMeasureAllChildren() -> Bool { mMeasureAllChildren }
    func getConsiderGoneChildrenWhenMeasuring() -> Bool { mMeasureAllChildren }

    override func shouldDelayChildPressedState() -> Bool { false }

    override func checkLayoutParams(_ p: AViewGroup.LayoutParams?) -> Bool {
        p is AFrameLayout.LayoutParams
    }

    /// FrameLayout.generateLayoutParams(LayoutParams): margins are kept (targetSdk >= N).
    override func generateLayoutParams(_ lp: AViewGroup.LayoutParams) -> AViewGroup.LayoutParams {
        if let f = lp as? AFrameLayout.LayoutParams {
            return LayoutParams(f)
        } else if let m = lp as? AViewGroup.MarginLayoutParams {
            return LayoutParams(m)
        }
        return LayoutParams(lp)
    }
}

// MARK: - LinearLayout

/// android.widget.LinearLayout.
class ALinearLayout: AViewGroup {
    static let HORIZONTAL = 0
    static let VERTICAL = 1

    static let SHOW_DIVIDER_NONE = 0
    static let SHOW_DIVIDER_BEGINNING = 1
    static let SHOW_DIVIDER_MIDDLE = 2
    static let SHOW_DIVIDER_END = 4

    /// LinearLayout.LayoutParams: margins, weight and layout_gravity (-1 = the layout's minor gravity).
    class LayoutParams: AViewGroup.MarginLayoutParams {
        var weight: Float = 0
        var gravity = -1

        override init(_ width: Int, _ height: Int) {
            super.init(width, height)
            weight = 0
        }

        init(_ width: Int, _ height: Int, _ weight: Float) {
            super.init(width, height)
            self.weight = weight
        }

        override init(_ source: AViewGroup.LayoutParams) {
            super.init(source)
        }

        override init(_ source: AViewGroup.MarginLayoutParams) {
            super.init(source)
        }

        /// Copy constructor: margins, weight and gravity.
        init(_ source: ALinearLayout.LayoutParams) {
            super.init(source as AViewGroup.MarginLayoutParams)
            self.weight = source.weight
            self.gravity = source.gravity
        }
    }

    private static let VERTICAL_GRAVITY_COUNT = 4
    private static let INDEX_CENTER_VERTICAL = 0
    private static let INDEX_TOP = 1
    private static let INDEX_BOTTOM = 2
    private static let INDEX_FILL = 3

    /// Java `MEASURED_STATE_MASK >> MEASURED_HEIGHT_STATE_SHIFT` on a 32-bit int: 0xffffff00 (sign-extended).
    static let JAVA_HEIGHT_STATE_MASK = Int(Int32(bitPattern: 0xff00_0000) >> 16)

    /// targetSdk >= P: weighted children are always remeasured.
    private static let sRemeasureWeightedChildren = true
    /// targetSdk > M.
    private let mAllowInconsistentMeasurement = false

    private var mBaselineAligned = true
    private var mBaselineAlignedChildIndex = -1
    private var mBaselineChildTop = 0
    private var mOrientation = ALinearLayout.HORIZONTAL
    private var mGravity = AGravity.START | AGravity.TOP
    private(set) var mTotalLength = 0
    private var mWeightSum: Float = -1.0
    private var mUseLargestChild = false
    private var mMaxAscent: [Int]?
    private var mMaxDescent: [Int]?
    private var mDivider: ADrawable?
    private var mDividerWidth = 0
    private var mDividerHeight = 0
    private var mShowDividers = ALinearLayout.SHOW_DIVIDER_NONE
    private var mDividerPadding = 0
    private var mLayoutDirection = AView.LAYOUT_DIRECTION_UNDEFINED

    override init() {
        super.init()
    }

    // MARK: dividers

    private func isShowingDividers() -> Bool {
        mShowDividers != ALinearLayout.SHOW_DIVIDER_NONE && mDivider != nil
    }

    var showDividers: Int {
        get { mShowDividers }
        set { setShowDividers(newValue) }
    }

    func setShowDividers(_ showDividers: Int) {
        if showDividers == mShowDividers { return }
        mShowDividers = showDividers
        setWillNotDraw(!isShowingDividers())
        requestLayout()
    }

    override func shouldDelayChildPressedState() -> Bool { false }

    var dividerDrawable: ADrawable? {
        get { mDivider }
        set { setDividerDrawable(newValue) }
    }

    func setDividerDrawable(_ divider: ADrawable?) {
        if divider === mDivider { return }
        mDivider = divider
        if let d = divider {
            mDividerWidth = d.intrinsicWidth
            mDividerHeight = d.intrinsicHeight
        } else {
            mDividerWidth = 0
            mDividerHeight = 0
        }
        setWillNotDraw(!isShowingDividers())
        requestLayout()
    }

    var dividerPadding: Int {
        get { mDividerPadding }
        set { setDividerPadding(newValue) }
    }

    func setDividerPadding(_ padding: Int) {
        if padding == mDividerPadding { return }
        mDividerPadding = padding
        if isShowingDividers() {
            requestLayout()
            invalidate()
        }
    }

    var dividerWidth: Int { mDividerWidth }

    override func onDraw(_ canvas: ACanvas) {
        if mDivider == nil { return }
        if mOrientation == ALinearLayout.VERTICAL {
            drawDividersVertical(canvas)
        } else {
            drawDividersHorizontal(canvas)
        }
    }

    func drawDividersVertical(_ canvas: ACanvas) {
        let count = getVirtualChildCount()
        for i in 0..<count {
            if let child = getVirtualChildAt(i), child.visibility != AView.GONE {
                if hasDividerBeforeChildAt(i) {
                    let lp = child.mLayoutParams as! AViewGroup.MarginLayoutParams
                    let top = child.top - lp.topMargin - mDividerHeight
                    drawHorizontalDivider(canvas, top)
                }
            }
        }
        if hasDividerBeforeChildAt(count) {
            let child = getLastNonGoneChild()
            var bottom = 0
            if let c = child {
                let lp = c.mLayoutParams as! AViewGroup.MarginLayoutParams
                bottom = c.bottom + lp.bottomMargin
            } else {
                bottom = height - paddingBottom - mDividerHeight
            }
            drawHorizontalDivider(canvas, bottom)
        }
    }

    private func getLastNonGoneChild() -> AView? {
        var i = getVirtualChildCount() - 1
        while i >= 0 {
            if let child = getVirtualChildAt(i), child.visibility != AView.GONE {
                return child
            }
            i -= 1
        }
        return nil
    }

    func drawDividersHorizontal(_ canvas: ACanvas) {
        let count = getVirtualChildCount()
        let isLayoutRtl = self.isLayoutRtl
        for i in 0..<count {
            if let child = getVirtualChildAt(i), child.visibility != AView.GONE {
                if hasDividerBeforeChildAt(i) {
                    let lp = child.mLayoutParams as! AViewGroup.MarginLayoutParams
                    let position: Int
                    if isLayoutRtl {
                        position = child.right + lp.rightMargin
                    } else {
                        position = child.left - lp.leftMargin - mDividerWidth
                    }
                    drawVerticalDivider(canvas, position)
                }
            }
        }
        if hasDividerBeforeChildAt(count) {
            let child = getLastNonGoneChild()
            var position: Int
            if let c = child {
                let lp = c.mLayoutParams as! AViewGroup.MarginLayoutParams
                if isLayoutRtl {
                    position = c.left - lp.leftMargin - mDividerWidth
                } else {
                    position = c.right + lp.rightMargin
                }
            } else {
                if isLayoutRtl {
                    position = paddingLeft
                } else {
                    position = width - paddingRight - mDividerWidth
                }
            }
            drawVerticalDivider(canvas, position)
        }
    }

    func drawHorizontalDivider(_ canvas: ACanvas, _ top: Int) {
        guard let d = mDivider else { return }
        d.setBounds(paddingLeft + mDividerPadding, top, width - paddingRight - mDividerPadding, top + mDividerHeight)
        d.draw(canvas)
    }

    func drawVerticalDivider(_ canvas: ACanvas, _ left: Int) {
        guard let d = mDivider else { return }
        d.setBounds(left, paddingTop + mDividerPadding, left + mDividerWidth, height - paddingBottom - mDividerPadding)
        d.draw(canvas)
    }

    // MARK: properties

    var isBaselineAligned: Bool {
        get { mBaselineAligned }
        set { mBaselineAligned = newValue }
    }
    func setBaselineAligned(_ baselineAligned: Bool) { mBaselineAligned = baselineAligned }

    var isMeasureWithLargestChildEnabled: Bool {
        get { mUseLargestChild }
        set { mUseLargestChild = newValue }
    }
    func setMeasureWithLargestChildEnabled(_ enabled: Bool) { mUseLargestChild = enabled }

    /// LinearLayout.getBaseline.
    override func getBaseline() -> Int {
        if mBaselineAlignedChildIndex < 0 {
            return super.getBaseline()
        }
        precondition(childCount > mBaselineAlignedChildIndex,
                     "mBaselineAlignedChildIndex of LinearLayout set to an index that is out of bounds.")
        let child = mChildren[mBaselineAlignedChildIndex]
        let childBaseline = child.getBaseline()
        if childBaseline == -1 {
            if mBaselineAlignedChildIndex == 0 {
                // this is just the default case, safe to return -1
                return -1
            }
            // the user picked an index that points to something that doesn't know how to calculate its baseline.
            preconditionFailure("mBaselineAlignedChildIndex of LinearLayout points to a View that doesn't know how to get its baseline.")
        }
        var childTop = mBaselineChildTop
        if mOrientation == ALinearLayout.VERTICAL {
            let majorGravity = mGravity & AGravity.VERTICAL_GRAVITY_MASK
            if majorGravity != AGravity.TOP {
                switch majorGravity {
                case AGravity.BOTTOM:
                    childTop = mBottom - mTop - mPaddingBottom - mTotalLength
                case AGravity.CENTER_VERTICAL:
                    childTop += ((mBottom - mTop - mPaddingTop - mPaddingBottom) - mTotalLength) / 2
                default:
                    break
                }
            }
        }
        let lp = child.mLayoutParams as! AViewGroup.MarginLayoutParams
        return childTop + lp.topMargin + childBaseline
    }

    var baselineAlignedChildIndex: Int {
        get { mBaselineAlignedChildIndex }
        set { setBaselineAlignedChildIndex(newValue) }
    }
    func setBaselineAlignedChildIndex(_ i: Int) {
        precondition(i >= 0 && i < childCount, "base aligned child index out of range (0, \(childCount))")
        mBaselineAlignedChildIndex = i
    }

    func getVirtualChildAt(_ index: Int) -> AView? {
        getChildAt(index)
    }

    func getVirtualChildCount() -> Int {
        childCount
    }

    /// getWeightSum / setWeightSum (negative values are stored as 0, like Android's max(0, weightSum)).
    var weightSum: Float {
        get { mWeightSum }
        set { setWeightSum(newValue) }
    }
    func setWeightSum(_ weightSum: Float) {
        mWeightSum = max(0.0, weightSum)
    }

    var orientation: Int {
        get { mOrientation }
        set { setOrientation(newValue) }
    }

    func setOrientation(_ orientation: Int) {
        if mOrientation != orientation {
            mOrientation = orientation
            requestLayout()
        }
    }

    func getOrientation() -> Int { mOrientation }

    var gravity: Int {
        get { mGravity }
        set { setGravity(newValue) }
    }

    func getGravity() -> Int { mGravity }

    /// LinearLayout.setGravity: a missing horizontal part becomes START, a missing vertical part TOP.
    func setGravity(_ gravity: Int) {
        var g = gravity
        if mGravity != g {
            if (g & AGravity.RELATIVE_HORIZONTAL_GRAVITY_MASK) == 0 {
                g |= AGravity.START
            }
            if (g & AGravity.VERTICAL_GRAVITY_MASK) == 0 {
                g |= AGravity.TOP
            }
            mGravity = g
            requestLayout()
        }
    }

    func setHorizontalGravity(_ horizontalGravity: Int) {
        let gravity = horizontalGravity & AGravity.RELATIVE_HORIZONTAL_GRAVITY_MASK
        if (mGravity & AGravity.RELATIVE_HORIZONTAL_GRAVITY_MASK) != gravity {
            mGravity = (mGravity & ~AGravity.RELATIVE_HORIZONTAL_GRAVITY_MASK) | gravity
            requestLayout()
        }
    }

    func setVerticalGravity(_ verticalGravity: Int) {
        let gravity = verticalGravity & AGravity.VERTICAL_GRAVITY_MASK
        if (mGravity & AGravity.VERTICAL_GRAVITY_MASK) != gravity {
            mGravity = (mGravity & ~AGravity.VERTICAL_GRAVITY_MASK) | gravity
            requestLayout()
        }
    }

    // MARK: measure

    override func onMeasure(_ widthMeasureSpec: Int, _ heightMeasureSpec: Int) {
        ensureResolvedPadding()
        if mOrientation == ALinearLayout.VERTICAL {
            measureVertical(widthMeasureSpec, heightMeasureSpec)
        } else {
            measureHorizontal(widthMeasureSpec, heightMeasureSpec)
        }
    }

    func hasDividerBeforeChildAt(_ childIndex: Int) -> Bool {
        if mShowDividers == ALinearLayout.SHOW_DIVIDER_NONE {
            // Short-circuit to save iteration over child views.
            return false
        }
        if childIndex == getVirtualChildCount() {
            // Check whether the end divider should draw.
            return (mShowDividers & ALinearLayout.SHOW_DIVIDER_END) != 0
        }
        let allViewsAreGoneBefore = allViewsAreGoneBefore(childIndex)
        if allViewsAreGoneBefore {
            // This is the first view that's not gone, check if beginning divider is enabled.
            return (mShowDividers & ALinearLayout.SHOW_DIVIDER_BEGINNING) != 0
        } else {
            return (mShowDividers & ALinearLayout.SHOW_DIVIDER_MIDDLE) != 0
        }
    }

    private func hasDividerAfterChildAt(_ childIndex: Int) -> Bool {
        if mShowDividers == ALinearLayout.SHOW_DIVIDER_NONE {
            return false
        }
        if allViewsAreGoneAfter(childIndex) {
            // This is the last view that's not gone, check if end divider is enabled.
            return (mShowDividers & ALinearLayout.SHOW_DIVIDER_END) != 0
        }
        return (mShowDividers & ALinearLayout.SHOW_DIVIDER_MIDDLE) != 0
    }

    private func allViewsAreGoneBefore(_ childIndex: Int) -> Bool {
        var i = childIndex - 1
        while i >= 0 {
            if let child = getVirtualChildAt(i), child.visibility != AView.GONE {
                return false
            }
            i -= 1
        }
        return true
    }

    private func allViewsAreGoneAfter(_ childIndex: Int) -> Bool {
        let count = getVirtualChildCount()
        var i = childIndex + 1
        while i < count {
            if let child = getVirtualChildAt(i), child.visibility != AView.GONE {
                return false
            }
            i += 1
        }
        return true
    }

    private func lpOf(_ child: AView) -> ALinearLayout.LayoutParams {
        child.mLayoutParams as! ALinearLayout.LayoutParams
    }

    /// LinearLayout.measureVertical.
    func measureVertical(_ widthMeasureSpec: Int, _ heightMeasureSpec: Int) {
        mTotalLength = 0
        var maxWidth = 0
        var childState = 0
        var alternativeMaxWidth = 0
        var weightedMaxWidth = 0
        var allFillParent = true
        var totalWeight: Float = 0

        let count = getVirtualChildCount()

        let widthMode = AMeasureSpec.getMode(widthMeasureSpec)
        let heightMode = AMeasureSpec.getMode(heightMeasureSpec)

        var matchWidth = false
        var skippedMeasure = false

        let baselineChildIndex = mBaselineAlignedChildIndex
        let useLargestChild = mUseLargestChild

        var largestChildHeight = Int(Int32.min)
        var consumedExcessSpace = 0

        var nonSkippedChildCount = 0

        // See how tall everyone is. Also remember max width.
        var i = 0
        while i < count {
            defer { i += 1 }
            guard let child = getVirtualChildAt(i) else {
                mTotalLength += measureNullChild(i)
                continue
            }

            if child.visibility == AView.GONE {
                i += getChildrenSkipCount(child, i)
                continue
            }

            nonSkippedChildCount += 1
            if hasDividerBeforeChildAt(i) {
                mTotalLength += mDividerHeight
            }

            let lp = lpOf(child)

            totalWeight += lp.weight

            let useExcessSpace = lp.height == 0 && lp.weight > 0
            if heightMode == AMeasureSpec.EXACTLY && useExcessSpace {
                // Optimization: don't bother measuring children who are only laid out using excess space. These
                // views will get measured later if we have space to distribute.
                let totalLength = mTotalLength
                mTotalLength = max(totalLength, totalLength + lp.topMargin + lp.bottomMargin)
                skippedMeasure = true
            } else {
                if useExcessSpace {
                    // The heightMode is either UNSPECIFIED or AT_MOST, and this child is only laid out using excess
                    // space. Measure using WRAP_CONTENT so that we can find out the view's optimal height. We'll
                    // restore the original height of 0 after measurement.
                    lp.height = AViewGroup.LayoutParams.WRAP_CONTENT
                }

                // Determine how big this child would like to be. If this or previous children have given a
                // weight, then we allow it to use all available space (and we will shrink things later if needed).
                let usedHeight = totalWeight == 0 ? mTotalLength : 0
                measureChildBeforeLayout(child, i, widthMeasureSpec, 0, heightMeasureSpec, usedHeight)

                let childHeight = child.measuredHeight
                if useExcessSpace {
                    // Restore the original height and record how much space we've allocated to excess-only
                    // children so that we can match the behavior of EXACTLY measurement.
                    lp.height = 0
                    consumedExcessSpace += childHeight
                }

                let totalLength = mTotalLength
                mTotalLength = max(totalLength, totalLength + childHeight + lp.topMargin + lp.bottomMargin
                                   + getNextLocationOffset(child))

                if useLargestChild {
                    largestChildHeight = max(childHeight, largestChildHeight)
                }
            }

            // If applicable, compute the additional offset to the child's baseline we'll need later when asked
            // getBaseline.
            if baselineChildIndex >= 0 && baselineChildIndex == i + 1 {
                mBaselineChildTop = mTotalLength
            }

            // if we are trying to use a child index for our baseline, the above book keeping only works if there are
            // no children above it with weight. fail fast to aid the developer.
            precondition(!(i < baselineChildIndex && lp.weight > 0),
                         "A child of LinearLayout with index less than mBaselineAlignedChildIndex has weight > 0, which won't work.  Either remove the weight, or don't set mBaselineAlignedChildIndex.")

            var matchWidthLocally = false
            if widthMode != AMeasureSpec.EXACTLY && lp.width == AViewGroup.LayoutParams.MATCH_PARENT {
                // The width of the linear layout will scale, and at least one child said it wanted to match our
                // width. Set a flag indicating that we need to remeasure at least that view when we know our width.
                matchWidth = true
                matchWidthLocally = true
            }

            let margin = lp.leftMargin + lp.rightMargin
            let measuredWidth = child.measuredWidth + margin
            maxWidth = max(maxWidth, measuredWidth)
            childState = AView.combineMeasuredStates(childState, child.measuredState)

            allFillParent = allFillParent && lp.width == AViewGroup.LayoutParams.MATCH_PARENT
            if lp.weight > 0 {
                // Widths of weighted Views are bogus if we end up remeasuring, so keep them separate.
                weightedMaxWidth = max(weightedMaxWidth, matchWidthLocally ? margin : measuredWidth)
            } else {
                alternativeMaxWidth = max(alternativeMaxWidth, matchWidthLocally ? margin : measuredWidth)
            }

            i += getChildrenSkipCount(child, i)
        }

        if nonSkippedChildCount > 0 && hasDividerBeforeChildAt(count) {
            mTotalLength += mDividerHeight
        }

        if useLargestChild && (heightMode == AMeasureSpec.AT_MOST || heightMode == AMeasureSpec.UNSPECIFIED) {
            mTotalLength = 0

            var j = 0
            while j < count {
                defer { j += 1 }
                guard let child = getVirtualChildAt(j) else {
                    mTotalLength += measureNullChild(j)
                    continue
                }

                if child.visibility == AView.GONE {
                    j += getChildrenSkipCount(child, j)
                    continue
                }

                let lp = lpOf(child)
                // Account for negative margins
                let totalLength = mTotalLength
                mTotalLength = max(totalLength, totalLength + largestChildHeight + lp.topMargin + lp.bottomMargin
                                   + getNextLocationOffset(child))
            }
        }

        // Add in our padding
        mTotalLength += mPaddingTop + mPaddingBottom

        var heightSize = mTotalLength

        // Check against our minimum height
        heightSize = max(heightSize, getSuggestedMinimumHeight())

        // Reconcile our calculated size with the heightMeasureSpec
        let heightSizeAndState = AView.resolveSizeAndState(heightSize, heightMeasureSpec, 0)
        heightSize = heightSizeAndState & AView.MEASURED_SIZE_MASK
        // Either expand children with weight to take up available space or shrink them if they extend beyond our
        // current bounds. If we skipped measurement on any children, we need to measure them now.
        var remainingExcess = heightSize - mTotalLength + (mAllowInconsistentMeasurement ? 0 : consumedExcessSpace)
        if skippedMeasure || ((ALinearLayout.sRemeasureWeightedChildren || remainingExcess != 0) && totalWeight > 0.0) {
            var remainingWeightSum = mWeightSum > 0.0 ? mWeightSum : totalWeight

            mTotalLength = 0

            for k in 0..<count {
                guard let child = getVirtualChildAt(k), child.visibility != AView.GONE else {
                    continue
                }

                let lp = lpOf(child)
                let childWeight = lp.weight
                if childWeight > 0 {
                    let share = AViewConfiguration.f2i(childWeight * Float(remainingExcess) / remainingWeightSum)
                    remainingExcess -= share
                    remainingWeightSum -= childWeight

                    let childHeight: Int
                    if mUseLargestChild && heightMode != AMeasureSpec.EXACTLY {
                        childHeight = largestChildHeight
                    } else if lp.height == 0 && (!mAllowInconsistentMeasurement || heightMode == AMeasureSpec.EXACTLY) {
                        // This child needs to be laid out from scratch using only its share of excess space.
                        childHeight = share
                    } else {
                        // This child had some intrinsic height to which we need to add its share of excess space.
                        childHeight = child.measuredHeight + share
                    }

                    let childHeightMeasureSpec = AMeasureSpec.makeMeasureSpec(max(0, childHeight), AMeasureSpec.EXACTLY)
                    let childWidthMeasureSpec = AViewGroup.getChildMeasureSpec(widthMeasureSpec,
                        mPaddingLeft + mPaddingRight + lp.leftMargin + lp.rightMargin, lp.width)
                    child.measure(childWidthMeasureSpec, childHeightMeasureSpec)

                    // Child may now not fit in vertical dimension. (Java's int `MEASURED_STATE_MASK >> 16` sign-extends
                    // to 0xffffff00: the width state bits pass too.)
                    childState = AView.combineMeasuredStates(childState, child.measuredState
                        & ALinearLayout.JAVA_HEIGHT_STATE_MASK)
                }

                let margin = lp.leftMargin + lp.rightMargin
                let measuredWidth = child.measuredWidth + margin
                maxWidth = max(maxWidth, measuredWidth)

                let matchWidthLocally = widthMode != AMeasureSpec.EXACTLY && lp.width == AViewGroup.LayoutParams.MATCH_PARENT

                alternativeMaxWidth = max(alternativeMaxWidth, matchWidthLocally ? margin : measuredWidth)

                allFillParent = allFillParent && lp.width == AViewGroup.LayoutParams.MATCH_PARENT

                let totalLength = mTotalLength
                mTotalLength = max(totalLength, totalLength + child.measuredHeight + lp.topMargin + lp.bottomMargin
                                   + getNextLocationOffset(child))
            }

            // Add in our padding
            mTotalLength += mPaddingTop + mPaddingBottom
            // TODO: Should we recompute the heightSpec based on the new total length?
        } else {
            alternativeMaxWidth = max(alternativeMaxWidth, weightedMaxWidth)

            // We have no limit, so make all weighted views as tall as the largest child. Children will have already
            // been measured once.
            if useLargestChild && heightMode != AMeasureSpec.EXACTLY {
                for k in 0..<count {
                    guard let child = getVirtualChildAt(k), child.visibility != AView.GONE else {
                        continue
                    }
                    let lp = lpOf(child)
                    let childExtra = lp.weight
                    if childExtra > 0 {
                        child.measure(AMeasureSpec.makeMeasureSpec(child.measuredWidth, AMeasureSpec.EXACTLY),
                                      AMeasureSpec.makeMeasureSpec(largestChildHeight, AMeasureSpec.EXACTLY))
                    }
                }
            }
        }

        if !allFillParent && widthMode != AMeasureSpec.EXACTLY {
            maxWidth = alternativeMaxWidth
        }

        maxWidth += mPaddingLeft + mPaddingRight

        // Check against our minimum width
        maxWidth = max(maxWidth, getSuggestedMinimumWidth())

        setMeasuredDimension(AView.resolveSizeAndState(maxWidth, widthMeasureSpec, childState), heightSizeAndState)

        if matchWidth {
            forceUniformWidth(count, heightMeasureSpec)
        }
    }

    private func forceUniformWidth(_ count: Int, _ heightMeasureSpec: Int) {
        // Pretend that the linear layout has an exact size.
        let uniformMeasureSpec = AMeasureSpec.makeMeasureSpec(measuredWidth, AMeasureSpec.EXACTLY)
        for i in 0..<count {
            if let child = getVirtualChildAt(i), child.visibility != AView.GONE {
                let lp = lpOf(child)
                if lp.width == AViewGroup.LayoutParams.MATCH_PARENT {
                    // Temporarily force children to reuse their old measured height
                    let oldHeight = lp.height
                    lp.height = child.measuredHeight

                    // Remeasue with new dimensions
                    measureChildWithMargins(child, uniformMeasureSpec, 0, heightMeasureSpec, 0)
                    lp.height = oldHeight
                }
            }
        }
    }

    /// LinearLayout.measureHorizontal (baseline alignment of TextView children included).
    func measureHorizontal(_ widthMeasureSpec: Int, _ heightMeasureSpec: Int) {
        mTotalLength = 0
        var maxHeight = 0
        var childState = 0
        var alternativeMaxHeight = 0
        var weightedMaxHeight = 0
        var allFillParent = true
        var totalWeight: Float = 0

        let count = getVirtualChildCount()

        let widthMode = AMeasureSpec.getMode(widthMeasureSpec)
        let heightMode = AMeasureSpec.getMode(heightMeasureSpec)

        var matchHeight = false
        var skippedMeasure = false

        if mMaxAscent == nil || mMaxDescent == nil {
            mMaxAscent = [Int](repeating: 0, count: ALinearLayout.VERTICAL_GRAVITY_COUNT)
            mMaxDescent = [Int](repeating: 0, count: ALinearLayout.VERTICAL_GRAVITY_COUNT)
        }

        var maxAscent = [-1, -1, -1, -1]
        var maxDescent = [-1, -1, -1, -1]

        let baselineAligned = mBaselineAligned
        let useLargestChild = mUseLargestChild

        let isExactly = widthMode == AMeasureSpec.EXACTLY

        var largestChildWidth = Int(Int32.min)
        var usedExcessSpace = 0

        var nonSkippedChildCount = 0

        let INDEX_CENTER_VERTICAL = ALinearLayout.INDEX_CENTER_VERTICAL
        let INDEX_TOP = ALinearLayout.INDEX_TOP
        let INDEX_BOTTOM = ALinearLayout.INDEX_BOTTOM
        let INDEX_FILL = ALinearLayout.INDEX_FILL

        // See how wide everyone is. Also remember max height.
        var i = 0
        while i < count {
            defer { i += 1 }
            guard let child = getVirtualChildAt(i) else {
                mTotalLength += measureNullChild(i)
                continue
            }

            if child.visibility == AView.GONE {
                i += getChildrenSkipCount(child, i)
                continue
            }

            nonSkippedChildCount += 1
            if hasDividerBeforeChildAt(i) {
                mTotalLength += mDividerWidth
            }

            let lp = lpOf(child)

            totalWeight += lp.weight

            let useExcessSpace = lp.width == 0 && lp.weight > 0
            if widthMode == AMeasureSpec.EXACTLY && useExcessSpace {
                // Optimization: don't bother measuring children who are only laid out using excess space. These
                // views will get measured later if we have space to distribute.
                if isExactly {
                    mTotalLength += lp.leftMargin + lp.rightMargin
                } else {
                    let totalLength = mTotalLength
                    mTotalLength = max(totalLength, totalLength + lp.leftMargin + lp.rightMargin)
                }

                // Baseline alignment requires to measure widgets to obtain the baseline offset (in particular for
                // TextViews). The following defeats the optimization mentioned above. Allow the child to use as
                // much space as it wants because we can shrink things later (and re-measure).
                if baselineAligned {
                    let freeWidthSpec = AMeasureSpec.makeSafeMeasureSpec(AMeasureSpec.getSize(widthMeasureSpec), AMeasureSpec.UNSPECIFIED)
                    let freeHeightSpec = AMeasureSpec.makeSafeMeasureSpec(AMeasureSpec.getSize(heightMeasureSpec), AMeasureSpec.UNSPECIFIED)
                    child.measure(freeWidthSpec, freeHeightSpec)
                } else {
                    skippedMeasure = true
                }
            } else {
                if useExcessSpace {
                    // The widthMode is either UNSPECIFIED or AT_MOST, and this child is only laid out using excess
                    // space. Measure using WRAP_CONTENT so that we can find out the view's optimal width. We'll
                    // restore the original width of 0 after measurement.
                    lp.width = AViewGroup.LayoutParams.WRAP_CONTENT
                }

                // Determine how big this child would like to be. If this or previous children have given a weight,
                // then we allow it to use all available space (and we will shrink things later if needed).
                let usedWidth = totalWeight == 0 ? mTotalLength : 0
                measureChildBeforeLayout(child, i, widthMeasureSpec, usedWidth, heightMeasureSpec, 0)
                let childWidth = child.measuredWidth
                if useExcessSpace {
                    // Restore the original width and record how much space we've allocated to excess-only children
                    // so that we can match the behavior of EXACTLY measurement.
                    lp.width = 0
                    usedExcessSpace += childWidth
                }

                if isExactly {
                    mTotalLength += childWidth + lp.leftMargin + lp.rightMargin + getNextLocationOffset(child)
                } else {
                    let totalLength = mTotalLength
                    mTotalLength = max(totalLength, totalLength + childWidth + lp.leftMargin + lp.rightMargin
                                       + getNextLocationOffset(child))
                }

                if useLargestChild {
                    largestChildWidth = max(childWidth, largestChildWidth)
                }
            }

            var matchHeightLocally = false
            if heightMode != AMeasureSpec.EXACTLY && lp.height == AViewGroup.LayoutParams.MATCH_PARENT {
                // The height of the linear layout will scale, and at least one child said it wanted to match our
                // height. Set a flag indicating that we need to remeasure at least that view when we know our height.
                matchHeight = true
                matchHeightLocally = true
            }

            let margin = lp.topMargin + lp.bottomMargin
            let childHeight = child.measuredHeight + margin
            childState = AView.combineMeasuredStates(childState, child.measuredState)

            if baselineAligned {
                let childBaseline = child.getBaseline()
                if childBaseline != -1 {
                    // Translates the child's vertical gravity into an index in the range 0..VERTICAL_GRAVITY_COUNT
                    let gravity = (lp.gravity < 0 ? mGravity : lp.gravity) & AGravity.VERTICAL_GRAVITY_MASK
                    let index = ((gravity >> AGravity.AXIS_Y_SHIFT) & ~AGravity.AXIS_SPECIFIED) >> 1

                    maxAscent[index] = max(maxAscent[index], childBaseline)
                    maxDescent[index] = max(maxDescent[index], childHeight - childBaseline)
                }
            }

            maxHeight = max(maxHeight, childHeight)

            allFillParent = allFillParent && lp.height == AViewGroup.LayoutParams.MATCH_PARENT
            if lp.weight > 0 {
                // Heights of weighted Views are bogus if we end up remeasuring, so keep them separate.
                weightedMaxHeight = max(weightedMaxHeight, matchHeightLocally ? margin : childHeight)
            } else {
                alternativeMaxHeight = max(alternativeMaxHeight, matchHeightLocally ? margin : childHeight)
            }

            i += getChildrenSkipCount(child, i)
        }

        if nonSkippedChildCount > 0 && hasDividerBeforeChildAt(count) {
            mTotalLength += mDividerWidth
        }

        // Check mMaxAscent[INDEX_TOP] first because it maps to Gravity.TOP, the most common case
        if maxAscent[INDEX_TOP] != -1 || maxAscent[INDEX_CENTER_VERTICAL] != -1
            || maxAscent[INDEX_BOTTOM] != -1 || maxAscent[INDEX_FILL] != -1 {
            let ascent = max(maxAscent[INDEX_FILL], max(maxAscent[INDEX_CENTER_VERTICAL],
                                                        max(maxAscent[INDEX_TOP], maxAscent[INDEX_BOTTOM])))
            let descent = max(maxDescent[INDEX_FILL], max(maxDescent[INDEX_CENTER_VERTICAL],
                                                          max(maxDescent[INDEX_TOP], maxDescent[INDEX_BOTTOM])))
            maxHeight = max(maxHeight, ascent + descent)
        }

        if useLargestChild && (widthMode == AMeasureSpec.AT_MOST || widthMode == AMeasureSpec.UNSPECIFIED) {
            mTotalLength = 0
            nonSkippedChildCount = 0

            var j = 0
            while j < count {
                defer { j += 1 }
                guard let child = getVirtualChildAt(j) else {
                    mTotalLength += measureNullChild(j)
                    continue
                }

                if child.visibility == AView.GONE {
                    j += getChildrenSkipCount(child, j)
                    continue
                }

                nonSkippedChildCount += 1
                if hasDividerBeforeChildAt(j) {
                    mTotalLength += mDividerWidth
                }

                let lp = lpOf(child)
                if isExactly {
                    mTotalLength += largestChildWidth + lp.leftMargin + lp.rightMargin + getNextLocationOffset(child)
                } else {
                    let totalLength = mTotalLength
                    mTotalLength = max(totalLength, totalLength + largestChildWidth + lp.leftMargin + lp.rightMargin
                                       + getNextLocationOffset(child))
                }
            }

            if nonSkippedChildCount > 0 && hasDividerBeforeChildAt(count) {
                mTotalLength += mDividerWidth
            }
        }

        // Add in our padding
        mTotalLength += mPaddingLeft + mPaddingRight

        var widthSize = mTotalLength

        // Check against our minimum width
        widthSize = max(widthSize, getSuggestedMinimumWidth())

        // Reconcile our calculated size with the widthMeasureSpec
        let widthSizeAndState = AView.resolveSizeAndState(widthSize, widthMeasureSpec, 0)
        widthSize = widthSizeAndState & AView.MEASURED_SIZE_MASK

        // Either expand children with weight to take up available space or shrink them if they extend beyond our
        // current bounds. If we skipped measurement on any children, we need to measure them now.
        var remainingExcess = widthSize - mTotalLength + (mAllowInconsistentMeasurement ? 0 : usedExcessSpace)
        if skippedMeasure || ((ALinearLayout.sRemeasureWeightedChildren || remainingExcess != 0) && totalWeight > 0.0) {
            var remainingWeightSum = mWeightSum > 0.0 ? mWeightSum : totalWeight

            maxAscent = [-1, -1, -1, -1]
            maxDescent = [-1, -1, -1, -1]
            maxHeight = -1

            mTotalLength = 0
            nonSkippedChildCount = 0

            for k in 0..<count {
                guard let child = getVirtualChildAt(k), child.visibility != AView.GONE else {
                    continue
                }

                nonSkippedChildCount += 1
                if hasDividerBeforeChildAt(k) {
                    mTotalLength += mDividerWidth
                }

                let lp = lpOf(child)
                let childWeight = lp.weight
                if childWeight > 0 {
                    let share = AViewConfiguration.f2i(childWeight * Float(remainingExcess) / remainingWeightSum)
                    remainingExcess -= share
                    remainingWeightSum -= childWeight

                    let childWidth: Int
                    if mUseLargestChild && widthMode != AMeasureSpec.EXACTLY {
                        childWidth = largestChildWidth
                    } else if lp.width == 0 && (!mAllowInconsistentMeasurement || widthMode == AMeasureSpec.EXACTLY) {
                        // This child needs to be laid out from scratch using only its share of excess space.
                        childWidth = share
                    } else {
                        // This child had some intrinsic width to which we need to add its share of excess space.
                        childWidth = child.measuredWidth + share
                    }

                    let childWidthMeasureSpec = AMeasureSpec.makeMeasureSpec(max(0, childWidth), AMeasureSpec.EXACTLY)
                    let childHeightMeasureSpec = AViewGroup.getChildMeasureSpec(heightMeasureSpec,
                        mPaddingTop + mPaddingBottom + lp.topMargin + lp.bottomMargin, lp.height)
                    child.measure(childWidthMeasureSpec, childHeightMeasureSpec)

                    // Child may now not fit in horizontal dimension.
                    childState = AView.combineMeasuredStates(childState, child.measuredState & AView.MEASURED_STATE_MASK)
                }

                if isExactly {
                    mTotalLength += child.measuredWidth + lp.leftMargin + lp.rightMargin + getNextLocationOffset(child)
                } else {
                    let totalLength = mTotalLength
                    mTotalLength = max(totalLength, totalLength + child.measuredWidth + lp.leftMargin + lp.rightMargin
                                       + getNextLocationOffset(child))
                }

                let matchHeightLocally = heightMode != AMeasureSpec.EXACTLY && lp.height == AViewGroup.LayoutParams.MATCH_PARENT

                let margin = lp.topMargin + lp.bottomMargin
                let childHeight = child.measuredHeight + margin
                maxHeight = max(maxHeight, childHeight)
                alternativeMaxHeight = max(alternativeMaxHeight, matchHeightLocally ? margin : childHeight)

                allFillParent = allFillParent && lp.height == AViewGroup.LayoutParams.MATCH_PARENT

                if baselineAligned {
                    let childBaseline = child.getBaseline()
                    if childBaseline != -1 {
                        // Translates the child's vertical gravity into an index in the range 0..2
                        let gravity = (lp.gravity < 0 ? mGravity : lp.gravity) & AGravity.VERTICAL_GRAVITY_MASK
                        let index = ((gravity >> AGravity.AXIS_Y_SHIFT) & ~AGravity.AXIS_SPECIFIED) >> 1

                        maxAscent[index] = max(maxAscent[index], childBaseline)
                        maxDescent[index] = max(maxDescent[index], childHeight - childBaseline)
                    }
                }
            }

            if nonSkippedChildCount > 0 && hasDividerBeforeChildAt(count) {
                mTotalLength += mDividerWidth
            }

            // Add in our padding
            mTotalLength += mPaddingLeft + mPaddingRight
            // TODO: Should we update widthSize with the new total length?

            // Check mMaxAscent[INDEX_TOP] first because it maps to Gravity.TOP, the most common case
            if maxAscent[INDEX_TOP] != -1 || maxAscent[INDEX_CENTER_VERTICAL] != -1
                || maxAscent[INDEX_BOTTOM] != -1 || maxAscent[INDEX_FILL] != -1 {
                let ascent = max(maxAscent[INDEX_FILL], max(maxAscent[INDEX_CENTER_VERTICAL],
                                                            max(maxAscent[INDEX_TOP], maxAscent[INDEX_BOTTOM])))
                let descent = max(maxDescent[INDEX_FILL], max(maxDescent[INDEX_CENTER_VERTICAL],
                                                              max(maxDescent[INDEX_TOP], maxDescent[INDEX_BOTTOM])))
                maxHeight = max(maxHeight, ascent + descent)
            }
        } else {
            alternativeMaxHeight = max(alternativeMaxHeight, weightedMaxHeight)

            // We have no limit, so make all weighted views as wide as the largest child. Children will have already
            // been measured once.
            if useLargestChild && widthMode != AMeasureSpec.EXACTLY {
                for k in 0..<count {
                    guard let child = getVirtualChildAt(k), child.visibility != AView.GONE else {
                        continue
                    }
                    let lp = lpOf(child)
                    let childExtra = lp.weight
                    if childExtra > 0 {
                        child.measure(AMeasureSpec.makeMeasureSpec(largestChildWidth, AMeasureSpec.EXACTLY),
                                      AMeasureSpec.makeMeasureSpec(child.measuredHeight, AMeasureSpec.EXACTLY))
                    }
                }
            }
        }

        if !allFillParent && heightMode != AMeasureSpec.EXACTLY {
            maxHeight = alternativeMaxHeight
        }

        maxHeight += mPaddingTop + mPaddingBottom

        // Check against our minimum height
        maxHeight = max(maxHeight, getSuggestedMinimumHeight())

        mMaxAscent = maxAscent
        mMaxDescent = maxDescent

        setMeasuredDimension(widthSizeAndState | (childState & AView.MEASURED_STATE_MASK),
                             AView.resolveSizeAndState(maxHeight, heightMeasureSpec,
                                                       childState << AView.MEASURED_HEIGHT_STATE_SHIFT))

        if matchHeight {
            forceUniformHeight(count, widthMeasureSpec)
        }
    }

    private func forceUniformHeight(_ count: Int, _ widthMeasureSpec: Int) {
        // Pretend that the linear layout has an exact size. This is the measured height of ourselves. The measured
        // height should be the max height of the children, changed to accommodate the heightMeasureSpec from the
        // parent
        let uniformMeasureSpec = AMeasureSpec.makeMeasureSpec(measuredHeight, AMeasureSpec.EXACTLY)
        for i in 0..<count {
            if let child = getVirtualChildAt(i), child.visibility != AView.GONE {
                let lp = lpOf(child)
                if lp.height == AViewGroup.LayoutParams.MATCH_PARENT {
                    // Temporarily force children to reuse their old measured width
                    let oldWidth = lp.width
                    lp.width = child.measuredWidth

                    // Remeasure with new dimensions
                    measureChildWithMargins(child, widthMeasureSpec, 0, uniformMeasureSpec, 0)
                    lp.width = oldWidth
                }
            }
        }
    }

    /// The number of children to skip after measuring/laying out the given child (0).
    func getChildrenSkipCount(_ child: AView, _ index: Int) -> Int { 0 }

    /// The size occupied by a null child (0).
    func measureNullChild(_ childIndex: Int) -> Int { 0 }

    /// LinearLayout.measureChildBeforeLayout.
    func measureChildBeforeLayout(_ child: AView, _ childIndex: Int, _ widthMeasureSpec: Int, _ totalWidth: Int,
                                  _ heightMeasureSpec: Int, _ totalHeight: Int) {
        measureChildWithMargins(child, widthMeasureSpec, totalWidth, heightMeasureSpec, totalHeight)
    }

    func getLocationOffset(_ child: AView) -> Int { 0 }

    func getNextLocationOffset(_ child: AView) -> Int { 0 }

    // MARK: layout

    override func onLayout(_ changed: Bool, _ l: Int, _ t: Int, _ r: Int, _ b: Int) {
        if mOrientation == ALinearLayout.VERTICAL {
            layoutVertical(l, t, r, b)
        } else {
            layoutHorizontal(l, t, r, b)
        }
    }

    /// LinearLayout.layoutVertical.
    func layoutVertical(_ left: Int, _ top: Int, _ right: Int, _ bottom: Int) {
        let paddingLeft = mPaddingLeft

        var childTop: Int
        var childLeft: Int

        // Where right end of child should go
        let width = right - left
        let childRight = width - mPaddingRight

        // Space available for child
        let childSpace = width - paddingLeft - mPaddingRight

        let count = getVirtualChildCount()

        let majorGravity = mGravity & AGravity.VERTICAL_GRAVITY_MASK
        let minorGravity = mGravity & AGravity.RELATIVE_HORIZONTAL_GRAVITY_MASK

        switch majorGravity {
        case AGravity.BOTTOM:
            // mTotalLength contains the padding already
            childTop = mPaddingTop + bottom - top - mTotalLength
        case AGravity.CENTER_VERTICAL:
            // mTotalLength contains the padding already
            childTop = mPaddingTop + (bottom - top - mTotalLength) / 2
        default:
            childTop = mPaddingTop
        }

        var i = 0
        while i < count {
            defer { i += 1 }
            guard let child = getVirtualChildAt(i) else {
                childTop += measureNullChild(i)
                continue
            }
            if child.visibility != AView.GONE {
                let childWidth = child.measuredWidth
                let childHeight = child.measuredHeight

                let lp = lpOf(child)

                var gravity = lp.gravity
                if gravity < 0 {
                    gravity = minorGravity
                }
                let layoutDirection = self.layoutDirection
                let absoluteGravity = AGravity.getAbsoluteGravity(gravity, layoutDirection)
                switch absoluteGravity & AGravity.HORIZONTAL_GRAVITY_MASK {
                case AGravity.CENTER_HORIZONTAL:
                    childLeft = paddingLeft + ((childSpace - childWidth) / 2) + lp.leftMargin - lp.rightMargin
                case AGravity.RIGHT:
                    childLeft = childRight - childWidth - lp.rightMargin
                default:
                    childLeft = paddingLeft + lp.leftMargin
                }

                if hasDividerBeforeChildAt(i) {
                    childTop += mDividerHeight
                }

                childTop += lp.topMargin
                setChildFrame(child, childLeft, childTop + getLocationOffset(child), childWidth, childHeight)
                childTop += childHeight + lp.bottomMargin + getNextLocationOffset(child)

                i += getChildrenSkipCount(child, i)
            }
        }
    }

    /// LinearLayout.onRtlPropertiesChanged: a horizontal layout relays out when the direction changes.
    override func onRtlPropertiesChanged(_ layoutDirection: Int) {
        super.onRtlPropertiesChanged(layoutDirection)
        if layoutDirection != mLayoutDirection {
            mLayoutDirection = layoutDirection
            if mOrientation == ALinearLayout.HORIZONTAL {
                requestLayout()
            }
        }
    }

    /// LinearLayout.layoutHorizontal: in RTL the children are placed from the last one.
    func layoutHorizontal(_ left: Int, _ top: Int, _ right: Int, _ bottom: Int) {
        let isLayoutRtl = self.isLayoutRtl
        let paddingTop = mPaddingTop

        var childTop: Int
        var childLeft: Int

        // Where bottom of child should go
        let height = bottom - top
        let childBottom = height - mPaddingBottom

        // Space available for child
        let childSpace = height - paddingTop - mPaddingBottom

        let count = getVirtualChildCount()

        let majorGravity = mGravity & AGravity.RELATIVE_HORIZONTAL_GRAVITY_MASK
        let minorGravity = mGravity & AGravity.VERTICAL_GRAVITY_MASK

        let baselineAligned = mBaselineAligned

        let maxAscent = mMaxAscent ?? [-1, -1, -1, -1]
        let maxDescent = mMaxDescent ?? [-1, -1, -1, -1]

        let layoutDirection = self.layoutDirection
        switch AGravity.getAbsoluteGravity(majorGravity, layoutDirection) {
        case AGravity.RIGHT:
            // mTotalLength contains the padding already
            childLeft = mPaddingLeft + right - left - mTotalLength
        case AGravity.CENTER_HORIZONTAL:
            // mTotalLength contains the padding already
            childLeft = mPaddingLeft + (right - left - mTotalLength) / 2
        default:
            childLeft = mPaddingLeft
        }

        var start = 0
        var dir = 1
        // In case of RTL, start drawing from the last child.
        if isLayoutRtl {
            start = count - 1
            dir = -1
        }

        var i = 0
        while i < count {
            defer { i += 1 }
            let childIndex = start + dir * i
            guard let child = getVirtualChildAt(childIndex) else {
                childLeft += measureNullChild(childIndex)
                continue
            }
            if child.visibility != AView.GONE {
                let childWidth = child.measuredWidth
                let childHeight = child.measuredHeight
                var childBaseline = -1

                let lp = lpOf(child)

                if baselineAligned && lp.height != AViewGroup.LayoutParams.MATCH_PARENT {
                    childBaseline = child.getBaseline()
                }

                var gravity = lp.gravity
                if gravity < 0 {
                    gravity = minorGravity
                }

                switch gravity & AGravity.VERTICAL_GRAVITY_MASK {
                case AGravity.TOP:
                    childTop = paddingTop + lp.topMargin
                    if childBaseline != -1 {
                        childTop += maxAscent[ALinearLayout.INDEX_TOP] - childBaseline
                    }
                case AGravity.CENTER_VERTICAL:
                    // Removed support for baseline alignment when layout_gravity or gravity == center_vertical.
                    // See bug #1038483.
                    childTop = paddingTop + ((childSpace - childHeight) / 2) + lp.topMargin - lp.bottomMargin
                case AGravity.BOTTOM:
                    childTop = childBottom - childHeight - lp.bottomMargin
                    if childBaseline != -1 {
                        let descent = child.measuredHeight - childBaseline
                        childTop -= (maxDescent[ALinearLayout.INDEX_BOTTOM] - descent)
                    }
                default:
                    childTop = paddingTop
                }

                if isLayoutRtl {
                    // Because rtl rendering occurs in the reverse direction, we need to check after the child rather
                    // than before (since after=left in this context)
                    if hasDividerAfterChildAt(childIndex) {
                        childLeft += mDividerWidth
                    }
                } else if hasDividerBeforeChildAt(childIndex) {
                    childLeft += mDividerWidth
                }

                childLeft += lp.leftMargin
                setChildFrame(child, childLeft + getLocationOffset(child), childTop, childWidth, childHeight)
                childLeft += childWidth + lp.rightMargin + getNextLocationOffset(child)

                i += getChildrenSkipCount(child, childIndex)
            }
        }
    }

    private func setChildFrame(_ child: AView, _ left: Int, _ top: Int, _ width: Int, _ height: Int) {
        child.layout(left, top, left + width, top + height)
    }

    // MARK: layout params

    /// LinearLayout.generateDefaultLayoutParams: (WRAP, WRAP) horizontal, (MATCH, WRAP) vertical.
    override func generateDefaultLayoutParams() -> AViewGroup.LayoutParams {
        if mOrientation == ALinearLayout.VERTICAL {
            return LayoutParams(AViewGroup.LayoutParams.MATCH_PARENT, AViewGroup.LayoutParams.WRAP_CONTENT)
        }
        return LayoutParams(AViewGroup.LayoutParams.WRAP_CONTENT, AViewGroup.LayoutParams.WRAP_CONTENT)
    }

    /// LinearLayout.generateLayoutParams(LayoutParams): margins are kept (targetSdk >= N).
    override func generateLayoutParams(_ lp: AViewGroup.LayoutParams) -> AViewGroup.LayoutParams {
        if let l = lp as? ALinearLayout.LayoutParams {
            return LayoutParams(l)
        } else if let m = lp as? AViewGroup.MarginLayoutParams {
            return LayoutParams(m)
        }
        return LayoutParams(lp)
    }

    override func checkLayoutParams(_ p: AViewGroup.LayoutParams?) -> Bool {
        p is ALinearLayout.LayoutParams
    }
}

// MARK: - Space

/// android.widget.Space: an INVISIBLE spacer that never draws.
class ASpace: AView {
    override init() {
        super.init()
        if visibility == AView.VISIBLE {
            visibility = AView.INVISIBLE
        }
    }

    override func draw(_ canvas: ACanvas) {}

    private static func getDefaultSize2(_ size: Int, _ measureSpec: Int) -> Int {
        var result = size
        let specMode = AMeasureSpec.getMode(measureSpec)
        let specSize = AMeasureSpec.getSize(measureSpec)
        switch specMode {
        case AMeasureSpec.UNSPECIFIED:
            result = size
        case AMeasureSpec.AT_MOST:
            result = min(size, specSize)
        case AMeasureSpec.EXACTLY:
            result = specSize
        default:
            break
        }
        return result
    }

    override func onMeasure(_ widthMeasureSpec: Int, _ heightMeasureSpec: Int) {
        setMeasuredDimension(ASpace.getDefaultSize2(getSuggestedMinimumWidth(), widthMeasureSpec),
                             ASpace.getDefaultSize2(getSuggestedMinimumHeight(), heightMeasureSpec))
    }
}

// MARK: - Scroll views

/// android.widget.OverScroller in SCROLL_MODE (startScroll / computeScrollOffset / abortAnimation): the
/// smoothScrollBy animation, 250 ms with Scroller.ViscousFluidInterpolator, positions rounded with Math.round.
final class AViewsSmoothScroller {
    static let DEFAULT_DURATION = 250

    private static let VISCOUS_FLUID_SCALE: Float = 8.0
    private static let VISCOUS_FLUID_NORMALIZE: Float = 1.0 / viscousFluid(1.0)
    private static let VISCOUS_FLUID_OFFSET: Float = 1.0 - VISCOUS_FLUID_NORMALIZE * viscousFluid(1.0)

    private static func viscousFluid(_ input: Float) -> Float {
        var x = input * VISCOUS_FLUID_SCALE
        if x < 1.0 {
            x -= (1.0 - Float(exp(Double(-x))))
        } else {
            let start: Float = 0.36787944117 // 1/e == exp(-1)
            x = 1.0 - Float(exp(Double(1.0 - x)))
            x = start + x * (1.0 - start)
        }
        return x
    }

    /// Scroller.ViscousFluidInterpolator.getInterpolation.
    static func viscousFluidInterpolation(_ input: Float) -> Float {
        let interpolated = VISCOUS_FLUID_NORMALIZE * viscousFluid(input)
        if interpolated > 0 {
            return interpolated + VISCOUS_FLUID_OFFSET
        }
        return interpolated
    }

    private(set) var isFinished = true
    private var startX = 0, startY = 0, finalX = 0, finalY = 0
    private(set) var currX = 0
    private(set) var currY = 0
    private var startTime: Int64 = 0
    private var duration = 0

    func startScroll(_ startX: Int, _ startY: Int, _ dx: Int, _ dy: Int, _ duration: Int = AViewsSmoothScroller.DEFAULT_DURATION) {
        isFinished = false
        self.startX = startX
        self.startY = startY
        currX = startX
        currY = startY
        finalX = startX + dx
        finalY = startY + dy
        startTime = AAnimationUtils.currentAnimationTimeMillis()
        self.duration = duration
    }

    /// OverScroller.computeScrollOffset (SCROLL_MODE): false once finished.
    func computeScrollOffset() -> Bool {
        if isFinished {
            return false
        }
        let time = AAnimationUtils.currentAnimationTimeMillis()
        let elapsedTime = time - startTime
        if elapsedTime < Int64(duration) {
            let q = AViewsSmoothScroller.viscousFluidInterpolation(Float(elapsedTime) / Float(duration))
            currX = startX + AView.javaRound(q * Float(finalX - startX))
            currY = startY + AView.javaRound(q * Float(finalY - startY))
        } else {
            abortAnimation()
        }
        return true
    }

    func abortAnimation() {
        currX = finalX
        currY = finalY
        isFinished = true
    }
}

/// The UIScrollView that hosts a scroll view's child. It never claims hit tests itself (the owning AViewGroup's
/// hitTestDescendants returns it when no child takes the touch, so its pan recognizer sees every touch inside), and
/// forwards its touches to the Android dispatch of the window like every AView.
final class AViewsScrollHostView: UIScrollView {
    weak var ownerView: AViewGroup?

    override init(frame: CGRect) {
        super.init(frame: frame)
        isMultipleTouchEnabled = true
        isOpaque = false
        backgroundColor = nil
        autoresizesSubviews = false
        clipsToBounds = true
        delaysContentTouches = false
        canCancelContentTouches = true
        contentInsetAdjustmentBehavior = .never
        automaticallyAdjustsScrollIndicatorInsets = false
        scrollsToTop = false
        keyboardDismissMode = .none
        alwaysBounceVertical = false
        alwaysBounceHorizontal = false
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    /// Android scroll views take a drag over any child (EditText included) unless a child disallows intercepts.
    override func touchesShouldCancel(in view: UIView) -> Bool { true }

    override func hitTest(_ point: CGPoint, with event: UIEvent?) -> UIView? { nil }

    private var forwardRoot: AViewRoot? { ownerView?.touchRootForForwarding }

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        if let root = forwardRoot { root.handleTouches(touches, event, .began) } else { super.touchesBegan(touches, with: event) }
    }

    override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent?) {
        if let root = forwardRoot { root.handleTouches(touches, event, .moved) } else { super.touchesMoved(touches, with: event) }
    }

    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) {
        if let root = forwardRoot { root.handleTouches(touches, event, .ended) } else { super.touchesEnded(touches, with: event) }
    }

    override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent?) {
        if let root = forwardRoot { root.handleTouches(touches, event, .cancelled) } else { super.touchesCancelled(touches, with: event) }
    }
}

/// android.widget.ScrollView (vertical), UIScrollView-backed.
class AScrollView: AFrameLayout, UIScrollViewDelegate {
    static let ANIMATED_SCROLL_GAP = 250
    static let MAX_SCROLL_FACTOR: Float = 0.5

    private var mLastScroll: Int64 = 0
    private var mIsLayoutDirty = true
    private weak var mChildToScrollTo: AView?
    private var mFillViewport = false
    private var mSmoothScrollingEnabled = true
    let mScroller = AViewsSmoothScroller()
    /// True while UIKit (drag / deceleration) moves the content: the scroll position is taken, not pushed back.
    private var mApplyingUIKitScroll = false
    /// True while AndroidKit sets the UIScrollView geometry (its delegate callbacks are ignored).
    private var mSyncingHost = false

    override init() {
        super.init()
        // initScrollView
        setFocusable(true)
        setWillNotDraw(false)
        isVerticalScrollBarEnabled = true
        updateHostScrollConfiguration()
    }

    override func makeChildHost() -> UIView {
        let host = AViewsScrollHostView(frame: .zero)
        host.ownerView = self
        host.delegate = self
        return host
    }

    var scrollHost: UIScrollView? { mChildHost as? UIScrollView }

    override func shouldDelayChildPressedState() -> Bool { true }

    /// ScrollView.getMaxScrollAmount.
    func getMaxScrollAmount() -> Int {
        AViewConfiguration.f2i(AScrollView.MAX_SCROLL_FACTOR * Float(mBottom - mTop))
    }

    // MARK: single child

    override func addView(_ child: AView) {
        precondition(childCount == 0, "ScrollView can host only one direct child")
        super.addView(child)
    }

    override func addView(_ child: AView, _ index: Int) {
        precondition(childCount == 0, "ScrollView can host only one direct child")
        super.addView(child, index)
    }

    override func addView(_ child: AView, _ params: AViewGroup.LayoutParams) {
        precondition(childCount == 0, "ScrollView can host only one direct child")
        super.addView(child, params)
    }

    override func addView(_ child: AView, _ index: Int, _ params: AViewGroup.LayoutParams) {
        precondition(childCount == 0, "ScrollView can host only one direct child")
        super.addView(child, index, params)
    }

    private func canScroll() -> Bool {
        if let child = getChildAt(0) {
            let childHeight = child.height
            return height < childHeight + mPaddingTop + mPaddingBottom
        }
        return false
    }

    // MARK: properties

    var isFillViewport: Bool {
        get { mFillViewport }
        set { setFillViewport(newValue) }
    }

    func setFillViewport(_ fillViewport: Bool) {
        if fillViewport != mFillViewport {
            mFillViewport = fillViewport
            requestLayout()
        }
    }

    var isSmoothScrollingEnabled: Bool {
        get { mSmoothScrollingEnabled }
        set { mSmoothScrollingEnabled = newValue }
    }

    override func scrollBarsOrOverScrollDidChange() {
        updateHostScrollConfiguration()
    }

    private func updateHostScrollConfiguration() {
        guard let host = scrollHost else { return }
        host.showsVerticalScrollIndicator = isVerticalScrollBarEnabled
        host.showsHorizontalScrollIndicator = false
        host.bounces = overScrollMode != AView.OVER_SCROLL_NEVER
        host.alwaysBounceVertical = overScrollMode == AView.OVER_SCROLL_ALWAYS
        host.alwaysBounceHorizontal = false
    }

    // MARK: measure

    override func onMeasure(_ widthMeasureSpec: Int, _ heightMeasureSpec: Int) {
        super.onMeasure(widthMeasureSpec, heightMeasureSpec)

        if !mFillViewport {
            return
        }

        let heightMode = AMeasureSpec.getMode(heightMeasureSpec)
        if heightMode == AMeasureSpec.UNSPECIFIED {
            return
        }

        if childCount > 0 {
            let child = mChildren[0]
            let lp = child.mLayoutParams as! AViewGroup.MarginLayoutParams
            // targetSdkVersion >= M: the child's margins count.
            let widthPadding = mPaddingLeft + mPaddingRight + lp.leftMargin + lp.rightMargin
            let heightPadding = mPaddingTop + mPaddingBottom + lp.topMargin + lp.bottomMargin

            let desiredHeight = measuredHeight - heightPadding
            if child.measuredHeight < desiredHeight {
                let childWidthMeasureSpec = AViewGroup.getChildMeasureSpec(widthMeasureSpec, widthPadding, lp.width)
                let childHeightMeasureSpec = AMeasureSpec.makeMeasureSpec(desiredHeight, AMeasureSpec.EXACTLY)
                child.measure(childWidthMeasureSpec, childHeightMeasureSpec)
            }
        }
    }

    /// ScrollView.measureChild: the child is UNSPECIFIED vertically.
    override func measureChild(_ child: AView, _ parentWidthMeasureSpec: Int, _ parentHeightMeasureSpec: Int) {
        let lp = child.mLayoutParams!
        let childWidthMeasureSpec = AViewGroup.getChildMeasureSpec(parentWidthMeasureSpec, mPaddingLeft + mPaddingRight, lp.width)
        let verticalPadding = mPaddingTop + mPaddingBottom
        let childHeightMeasureSpec = AMeasureSpec.makeSafeMeasureSpec(
            max(0, AMeasureSpec.getSize(parentHeightMeasureSpec) - verticalPadding), AMeasureSpec.UNSPECIFIED)
        child.measure(childWidthMeasureSpec, childHeightMeasureSpec)
    }

    /// ScrollView.measureChildWithMargins: the child is UNSPECIFIED vertically.
    override func measureChildWithMargins(_ child: AView, _ parentWidthMeasureSpec: Int, _ widthUsed: Int,
                                          _ parentHeightMeasureSpec: Int, _ heightUsed: Int) {
        let lp = child.mLayoutParams as! AViewGroup.MarginLayoutParams
        let childWidthMeasureSpec = AViewGroup.getChildMeasureSpec(parentWidthMeasureSpec,
            mPaddingLeft + mPaddingRight + lp.leftMargin + lp.rightMargin + widthUsed, lp.width)
        let usedTotal = mPaddingTop + mPaddingBottom + lp.topMargin + lp.bottomMargin + heightUsed
        let childHeightMeasureSpec = AMeasureSpec.makeSafeMeasureSpec(
            max(0, AMeasureSpec.getSize(parentHeightMeasureSpec) - usedTotal), AMeasureSpec.UNSPECIFIED)
        child.measure(childWidthMeasureSpec, childHeightMeasureSpec)
    }

    // MARK: scroll range

    /// ScrollView.getScrollRange.
    func getScrollRange() -> Int {
        var scrollRange = 0
        if let child = getChildAt(0) {
            scrollRange = max(0, child.height - (height - mPaddingBottom - mPaddingTop))
        }
        return scrollRange
    }

    override func computeVerticalScrollRange() -> Int {
        let count = childCount
        let contentHeight = height - mPaddingBottom - mPaddingTop
        if count == 0 {
            return contentHeight
        }
        var scrollRange = mChildren[0].bottom
        let scrollY = mScrollY
        let overscrollBottom = max(0, scrollRange - contentHeight)
        if scrollY < 0 {
            scrollRange -= scrollY
        } else if scrollY > overscrollBottom {
            scrollRange += scrollY - overscrollBottom
        }
        return scrollRange
    }

    override func computeVerticalScrollOffset() -> Int {
        max(0, super.computeVerticalScrollOffset())
    }

    // MARK: scrolling

    /// ScrollView.pageScroll's sibling fullScroll(FOCUS_UP / FOCUS_DOWN). In touch mode the focus does not move.
    @discardableResult
    func fullScroll(_ direction: Int) -> Bool {
        let down = direction == AView.FOCUS_DOWN
        let height = self.height
        var top = 0
        var bottom = height
        if down {
            let count = childCount
            if count > 0 {
                let view = mChildren[count - 1]
                bottom = view.bottom + mPaddingBottom
                top = bottom - height
            }
        }
        return scrollAndFocus(direction, top, bottom)
    }

    /// ScrollView.pageScroll(FOCUS_UP / FOCUS_DOWN).
    @discardableResult
    func pageScroll(_ direction: Int) -> Bool {
        let down = direction == AView.FOCUS_DOWN
        let height = self.height
        var top: Int
        if down {
            top = mScrollY + height
            let count = childCount
            if count > 0 {
                let view = mChildren[count - 1]
                if top + height > view.bottom {
                    top = view.bottom - height
                }
            }
        } else {
            top = mScrollY - height
            if top < 0 {
                top = 0
            }
        }
        return scrollAndFocus(direction, top, top + height)
    }

    private func scrollAndFocus(_ direction: Int, _ top: Int, _ bottom: Int) -> Bool {
        var handled = true
        let height = self.height
        let containerTop = mScrollY
        let containerBottom = containerTop + height
        let up = direction == AView.FOCUS_UP
        if top >= containerTop && bottom <= containerBottom {
            handled = false
        } else {
            let delta = up ? (top - containerTop) : (bottom - containerBottom)
            doScrollY(delta)
        }
        return handled
    }

    private func doScrollY(_ delta: Int) {
        if delta != 0 {
            if mSmoothScrollingEnabled {
                smoothScrollBy(0, delta)
            } else {
                scrollBy(0, delta)
            }
        }
    }

    /// ScrollView.smoothScrollBy: a 250 ms OverScroller animation, or an immediate scrollBy within 250 ms of the
    /// previous call.
    func smoothScrollBy(_ dx: Int, _ dy: Int) {
        if childCount == 0 {
            // Nothing to do.
            return
        }
        var dy = dy
        let duration = AAnimationUtils.currentAnimationTimeMillis() - mLastScroll
        if duration > Int64(AScrollView.ANIMATED_SCROLL_GAP) {
            let height = self.height - mPaddingBottom - mPaddingTop
            let bottom = mChildren[0].height
            let maxY = max(0, bottom - height)
            let scrollY = mScrollY
            dy = max(0, min(scrollY + dy, maxY)) - scrollY

            mScroller.startScroll(mScrollX, scrollY, 0, dy)
            stopUIKitScrolling()
            postInvalidateOnAnimation()
        } else {
            if !mScroller.isFinished {
                mScroller.abortAnimation()
            }
            scrollBy(dx, dy)
        }
        mLastScroll = AAnimationUtils.currentAnimationTimeMillis()
    }

    func smoothScrollTo(_ x: Int, _ y: Int) {
        smoothScrollBy(x - mScrollX, y - mScrollY)
    }

    /// ScrollView.computeScroll: one step of the smooth scroll per drawn frame.
    override func computeScroll() {
        if mScroller.computeScrollOffset() {
            let oldX = mScrollX
            let oldY = mScrollY
            let x = mScroller.currX
            let y = mScroller.currY
            let deltaY = y - oldY

            if oldX != x || deltaY != 0 {
                let range = getScrollRange()
                _ = overScrollBy(x - oldX, deltaY, oldX, oldY, 0, range, 0,
                                 AViewConfiguration.get().scaledOverflingDistance, false)
                onScrollChanged(mScrollX, mScrollY, oldX, oldY)
            }

            // Keep on drawing until the animation has finished.
            postInvalidateOnAnimation()
        }
    }

    /// View.overScrollBy for the smooth scroll (the clamped position goes to onOverScrolled).
    private func overScrollBy(_ deltaX: Int, _ deltaY: Int, _ scrollX: Int, _ scrollY: Int, _ scrollRangeX: Int,
                              _ scrollRangeY: Int, _ maxOverScrollX: Int, _ maxOverScrollY: Int, _ isTouchEvent: Bool) -> Bool {
        let overScrollMode = self.overScrollMode
        let canScrollHorizontal = computeHorizontalScrollRange() > computeHorizontalScrollExtent()
        let canScrollVertical = computeVerticalScrollRange() > computeVerticalScrollExtent()
        let overScrollHorizontal = overScrollMode == AView.OVER_SCROLL_ALWAYS
            || (overScrollMode == AView.OVER_SCROLL_IF_CONTENT_SCROLLS && canScrollHorizontal)
        let overScrollVertical = overScrollMode == AView.OVER_SCROLL_ALWAYS
            || (overScrollMode == AView.OVER_SCROLL_IF_CONTENT_SCROLLS && canScrollVertical)

        var maxOverScrollX = maxOverScrollX
        var maxOverScrollY = maxOverScrollY
        var newScrollX = scrollX + deltaX
        if !overScrollHorizontal {
            maxOverScrollX = 0
        }
        var newScrollY = scrollY + deltaY
        if !overScrollVertical {
            maxOverScrollY = 0
        }

        // Clamp values if at the limits and record
        let left = -maxOverScrollX
        let right = maxOverScrollX + scrollRangeX
        let top = -maxOverScrollY
        let bottom = maxOverScrollY + scrollRangeY

        var clampedX = false
        if newScrollX > right {
            newScrollX = right
            clampedX = true
        } else if newScrollX < left {
            newScrollX = left
            clampedX = true
        }

        var clampedY = false
        if newScrollY > bottom {
            newScrollY = bottom
            clampedY = true
        } else if newScrollY < top {
            newScrollY = top
            clampedY = true
        }

        onOverScrolled(newScrollX, newScrollY, clampedX, clampedY)
        return clampedX || clampedY
    }

    /// ScrollView.onOverScrolled: during the animation the position is set directly and onScrollChanged is called
    /// (computeScroll calls it once more, as on Android).
    private func onOverScrolled(_ scrollX: Int, _ scrollY: Int, _ clampedX: Bool, _ clampedY: Bool) {
        if !mScroller.isFinished {
            let oldX = mScrollX
            let oldY = mScrollY
            mScrollX = scrollX
            mScrollY = scrollY
            scrollOffsetDidChange()
            onScrollChanged(mScrollX, mScrollY, oldX, oldY)
            if clampedY {
                mScroller.abortAnimation()
            }
        } else {
            super.scrollTo(scrollX, scrollY)
        }
    }

    /// ScrollView.scrollTo: clamps to the child (the content cannot be scrolled past its ends).
    override func scrollTo(_ x: Int, _ y: Int) {
        // we rely on the fact the View.scrollBy calls scrollTo.
        if childCount > 0 {
            let child = mChildren[0]
            let cx = AScrollView.clamp(x, width - mPaddingRight - mPaddingLeft, child.width)
            let cy = AScrollView.clamp(y, height - mPaddingBottom - mPaddingTop, child.height)
            if cx != mScrollX || cy != mScrollY {
                super.scrollTo(cx, cy)
            }
        }
    }

    static func clamp(_ n: Int, _ my: Int, _ child: Int) -> Int {
        if my >= child || n < 0 {
            return 0
        }
        if (my + n) > child {
            return child - my
        }
        return n
    }

    // MARK: child rectangles and focus

    /// ScrollView.scrollToDescendant.
    func scrollToDescendant(_ child: AView) {
        if !mIsLayoutDirty {
            let rect = ARect()
            child.getDrawingRect(rect)
            // Offset from child's local coordinates to ScrollView coordinates
            offsetDescendantRectToMyCoords(child, rect)
            let scrollDelta = computeScrollDeltaToGetChildRectOnScreen(rect)
            if scrollDelta != 0 {
                scrollBy(0, scrollDelta)
            }
        } else {
            mChildToScrollTo = child
        }
    }

    private func scrollToChildRect(_ rect: ARect, _ immediate: Bool) -> Bool {
        let delta = computeScrollDeltaToGetChildRectOnScreen(rect)
        let scroll = delta != 0
        if scroll {
            if immediate {
                scrollBy(0, delta)
            } else {
                smoothScrollBy(0, delta)
            }
        }
        return scroll
    }

    /// ScrollView.computeScrollDeltaToGetChildRectOnScreen (the vertical fading edge length is 0).
    func computeScrollDeltaToGetChildRectOnScreen(_ rect: ARect) -> Int {
        if childCount == 0 { return 0 }
        let height = self.height
        let screenTop = mScrollY
        let screenBottom = screenTop + height
        var scrollYDelta = 0
        if rect.bottom > screenBottom && rect.top > screenTop {
            // need to move down to get it in view: move down just enough so that the entire rectangle is in view (or
            // at least the first screen size chunk).
            if rect.height() > height {
                // just enough to get screen size chunk on
                scrollYDelta += (rect.top - screenTop)
            } else {
                // get entire rect at bottom of screen
                scrollYDelta += (rect.bottom - screenBottom)
            }
            // make sure we aren't scrolling beyond the end of our content
            let bottom = mChildren[0].bottom
            let distanceToBottom = bottom - screenBottom
            scrollYDelta = min(scrollYDelta, distanceToBottom)
        } else if rect.top < screenTop && rect.bottom < screenBottom {
            // need to move up to get it in view: move up just enough so that entire rectangle is in view (or at
            // least the first screen size chunk of it).
            if rect.height() > height {
                // screen size chunk
                scrollYDelta -= (screenBottom - rect.bottom)
            } else {
                // entire rect at top
                scrollYDelta -= (screenTop - rect.top)
            }
            // make sure we aren't scrolling any further than the top our content
            scrollYDelta = max(scrollYDelta, -mScrollY)
        }
        return scrollYDelta
    }

    override func requestChildFocus(_ child: AView, _ focused: AView) {
        if !mIsLayoutDirty {
            scrollToDescendant(focused)
        } else {
            // The child may not be laid out yet, we can't compute the scroll yet
            mChildToScrollTo = focused
        }
        super.requestChildFocus(child, focused)
    }

    override func requestChildRectangleOnScreen(_ child: AView, _ rectangle: ARect, _ immediate: Bool) -> Bool {
        // offset into coordinate space of this scroll view
        rectangle.offset(child.left - child.scrollX, child.top - child.scrollY)
        return scrollToChildRect(rectangle, immediate)
    }

    override func requestLayout() {
        mIsLayoutDirty = true
        super.requestLayout()
    }

    // MARK: layout

    override func onLayout(_ changed: Bool, _ l: Int, _ t: Int, _ r: Int, _ b: Int) {
        super.onLayout(changed, l, t, r, b)
        mIsLayoutDirty = false
        // Give a child focus if it needs it
        if let c = mChildToScrollTo, AScrollView.isViewDescendantOf(c, self) {
            scrollToDescendant(c)
        }
        mChildToScrollTo = nil

        if !isLaidOut {
            let childHeight = childCount > 0 ? mChildren[0].measuredHeight : 0
            let scrollRange = max(0, childHeight - (b - t - mPaddingBottom - mPaddingTop))

            // Don't forget to clamp
            if mScrollY > scrollRange {
                mScrollY = scrollRange
            } else if mScrollY < 0 {
                mScrollY = 0
            }
        }

        // Calling this with the present values causes it to re-claim them
        scrollTo(mScrollX, mScrollY)
        updateScrollHost()
    }

    override func onSizeChanged(_ w: Int, _ h: Int, _ oldw: Int, _ oldh: Int) {
        super.onSizeChanged(w, h, oldw, oldh)
        guard let currentFocused = findFocus(), currentFocused !== self else { return }
        // If the currently-focused view was visible on the screen when the screen was at the old height, then scroll
        // the screen to make that view visible with the new screen height.
        let rect = ARect()
        currentFocused.getDrawingRect(rect)
        offsetDescendantRectToMyCoords(currentFocused, rect)
        if rect.bottom >= mScrollY && rect.top <= mScrollY + oldh {
            let scrollDelta = computeScrollDeltaToGetChildRectOnScreen(rect)
            doScrollY(scrollDelta)
        }
    }

    static func isViewDescendantOf(_ child: AView, _ parent: AView) -> Bool {
        if child === parent {
            return true
        }
        guard let theParent = child.parentGroup else { return false }
        return isViewDescendantOf(theParent, parent)
    }

    override func onDetachedFromWindow() {
        super.onDetachedFromWindow()
        mScroller.abortAnimation()
    }

    // MARK: touch (the drag itself is the UIScrollView's)

    /// ScrollView.onInterceptTouchEvent: the UIScrollView pan recognizer takes drags (UIKit then cancels the
    /// children's touches, which arrives as ACTION_CANCEL like an Android intercept).
    override func onInterceptTouchEvent(_ ev: AMotionEvent) -> Bool {
        false
    }

    /// ScrollView.onTouchEvent: a scroll view with content consumes the gesture (touches never fall through it).
    override func onTouchEvent(_ event: AMotionEvent) -> Bool {
        if event.actionMasked == AMotionEvent.ACTION_DOWN {
            if childCount == 0 {
                return false
            }
            // If being flinged and user touches, stop the fling.
            if !mScroller.isFinished {
                mScroller.abortAnimation()
            }
        }
        return true
    }

    /// A child that disallows intercepts keeps the drag: the pan recognizer is off until the gesture ends.
    override func requestDisallowInterceptTouchEvent(_ disallowIntercept: Bool) {
        if disallowIntercept {
            scrollHost?.panGestureRecognizer.isEnabled = false
        }
        super.requestDisallowInterceptTouchEvent(disallowIntercept)
    }

    override func touchStateDidReset() {
        if let pan = scrollHost?.panGestureRecognizer, !pan.isEnabled {
            pan.isEnabled = true
        }
    }

    override func hitTestChildHostItself(_ point: CGPoint, _ event: UIEvent?) -> UIView? {
        guard let host = scrollHost, childCount > 0 else { return nil }
        return host.point(inside: host.convert(point, from: self), with: event) ? host : nil
    }

    // MARK: UIScrollView synchronisation

    override func applyChildHostFrame(_ frame: CGRect, clips: Bool) {
        guard let host = scrollHost else { return }
        mSyncingHost = true
        if host.frame != frame { host.frame = frame }
        updateHostContentSize(host)
        if !mApplyingUIKitScroll {
            let d = AView.densityScale
            let target = CGPoint(x: CGFloat(mScrollX) / d, y: CGFloat(mScrollY) / d)
            if host.contentOffset != target {
                host.setContentOffset(target, animated: false)
            }
        }
        mSyncingHost = false
    }

    private func updateHostContentSize(_ host: UIScrollView) {
        let d = AView.densityScale
        let size = CGSize(width: host.bounds.width, height: host.bounds.height + CGFloat(getScrollRange()) / d)
        if host.contentSize != size { host.contentSize = size }
    }

    /// Pushes the scroll range and position to the UIScrollView (after a layout).
    func updateScrollHost() {
        updateChildHostGeometry()
    }

    private func stopUIKitScrolling() {
        guard let host = scrollHost, host.isDecelerating || host.isDragging else { return }
        mSyncingHost = true
        host.setContentOffset(host.contentOffset, animated: false)
        mSyncingHost = false
    }

    func scrollViewDidScroll(_ scrollView: UIScrollView) {
        if mSyncingHost { return }
        let d = AView.densityScale
        let range = getScrollRange()
        var y = Int((scrollView.contentOffset.y * d).rounded())
        if y < 0 { y = 0 }
        if y > range { y = range }
        if y != mScrollY {
            mApplyingUIKitScroll = true
            scrollTo(mScrollX, y)
            mApplyingUIKitScroll = false
        }
    }

    func scrollViewWillBeginDragging(_ scrollView: UIScrollView) {
        if !mScroller.isFinished {
            mScroller.abortAnimation()
        }
    }
}

/// android.widget.HorizontalScrollView, UIScrollView-backed; in RTL the first layout starts at the right end.
class AHorizontalScrollView: AFrameLayout, UIScrollViewDelegate {
    static let ANIMATED_SCROLL_GAP = 250
    static let MAX_SCROLL_FACTOR: Float = 0.5

    private var mLastScroll: Int64 = 0
    private var mIsLayoutDirty = true
    private weak var mChildToScrollTo: AView?
    private var mFillViewport = false
    private var mSmoothScrollingEnabled = true
    let mScroller = AViewsSmoothScroller()
    private var mApplyingUIKitScroll = false
    private var mSyncingHost = false

    override init() {
        super.init()
        // initScrollView
        setFocusable(true)
        setWillNotDraw(false)
        isHorizontalScrollBarEnabled = true
        updateHostScrollConfiguration()
    }

    override func makeChildHost() -> UIView {
        let host = AViewsScrollHostView(frame: .zero)
        host.ownerView = self
        host.delegate = self
        return host
    }

    var scrollHost: UIScrollView? { mChildHost as? UIScrollView }

    override func shouldDelayChildPressedState() -> Bool { true }

    func getMaxScrollAmount() -> Int {
        AViewConfiguration.f2i(AHorizontalScrollView.MAX_SCROLL_FACTOR * Float(mRight - mLeft))
    }

    override func addView(_ child: AView) {
        precondition(childCount == 0, "HorizontalScrollView can host only one direct child")
        super.addView(child)
    }

    override func addView(_ child: AView, _ index: Int) {
        precondition(childCount == 0, "HorizontalScrollView can host only one direct child")
        super.addView(child, index)
    }

    override func addView(_ child: AView, _ params: AViewGroup.LayoutParams) {
        precondition(childCount == 0, "HorizontalScrollView can host only one direct child")
        super.addView(child, params)
    }

    override func addView(_ child: AView, _ index: Int, _ params: AViewGroup.LayoutParams) {
        precondition(childCount == 0, "HorizontalScrollView can host only one direct child")
        super.addView(child, index, params)
    }

    var isFillViewport: Bool {
        get { mFillViewport }
        set { setFillViewport(newValue) }
    }

    func setFillViewport(_ fillViewport: Bool) {
        if fillViewport != mFillViewport {
            mFillViewport = fillViewport
            requestLayout()
        }
    }

    var isSmoothScrollingEnabled: Bool {
        get { mSmoothScrollingEnabled }
        set { mSmoothScrollingEnabled = newValue }
    }

    override func scrollBarsOrOverScrollDidChange() {
        updateHostScrollConfiguration()
    }

    private func updateHostScrollConfiguration() {
        guard let host = scrollHost else { return }
        host.showsHorizontalScrollIndicator = isHorizontalScrollBarEnabled
        host.showsVerticalScrollIndicator = false
        host.bounces = overScrollMode != AView.OVER_SCROLL_NEVER
        host.alwaysBounceHorizontal = overScrollMode == AView.OVER_SCROLL_ALWAYS
        host.alwaysBounceVertical = false
    }

    // MARK: measure

    override func onMeasure(_ widthMeasureSpec: Int, _ heightMeasureSpec: Int) {
        super.onMeasure(widthMeasureSpec, heightMeasureSpec)

        if !mFillViewport {
            return
        }

        let widthMode = AMeasureSpec.getMode(widthMeasureSpec)
        if widthMode == AMeasureSpec.UNSPECIFIED {
            return
        }

        if childCount > 0 {
            let child = mChildren[0]
            let lp = child.mLayoutParams as! AViewGroup.MarginLayoutParams
            // targetSdkVersion >= M: the child's margins count.
            let widthPadding = mPaddingLeft + mPaddingRight + lp.leftMargin + lp.rightMargin
            let heightPadding = mPaddingTop + mPaddingBottom + lp.topMargin + lp.bottomMargin

            let desiredWidth = measuredWidth - widthPadding
            if child.measuredWidth < desiredWidth {
                let childWidthMeasureSpec = AMeasureSpec.makeMeasureSpec(desiredWidth, AMeasureSpec.EXACTLY)
                let childHeightMeasureSpec = AViewGroup.getChildMeasureSpec(heightMeasureSpec, heightPadding, lp.height)
                child.measure(childWidthMeasureSpec, childHeightMeasureSpec)
            }
        }
    }

    /// HorizontalScrollView.measureChild: the child is UNSPECIFIED horizontally.
    override func measureChild(_ child: AView, _ parentWidthMeasureSpec: Int, _ parentHeightMeasureSpec: Int) {
        let lp = child.mLayoutParams!
        let horizontalPadding = mPaddingLeft + mPaddingRight
        let childWidthMeasureSpec = AMeasureSpec.makeSafeMeasureSpec(
            max(0, AMeasureSpec.getSize(parentWidthMeasureSpec) - horizontalPadding), AMeasureSpec.UNSPECIFIED)
        let childHeightMeasureSpec = AViewGroup.getChildMeasureSpec(parentHeightMeasureSpec, mPaddingTop + mPaddingBottom, lp.height)
        child.measure(childWidthMeasureSpec, childHeightMeasureSpec)
    }

    /// HorizontalScrollView.measureChildWithMargins: the child is UNSPECIFIED horizontally.
    override func measureChildWithMargins(_ child: AView, _ parentWidthMeasureSpec: Int, _ widthUsed: Int,
                                          _ parentHeightMeasureSpec: Int, _ heightUsed: Int) {
        let lp = child.mLayoutParams as! AViewGroup.MarginLayoutParams
        let childHeightMeasureSpec = AViewGroup.getChildMeasureSpec(parentHeightMeasureSpec,
            mPaddingTop + mPaddingBottom + lp.topMargin + lp.bottomMargin + heightUsed, lp.height)
        let usedTotal = mPaddingLeft + mPaddingRight + lp.leftMargin + lp.rightMargin + widthUsed
        let childWidthMeasureSpec = AMeasureSpec.makeSafeMeasureSpec(
            max(0, AMeasureSpec.getSize(parentWidthMeasureSpec) - usedTotal), AMeasureSpec.UNSPECIFIED)
        child.measure(childWidthMeasureSpec, childHeightMeasureSpec)
    }

    // MARK: scroll range

    func getScrollRange() -> Int {
        var scrollRange = 0
        if let child = getChildAt(0) {
            scrollRange = max(0, child.width - (width - mPaddingLeft - mPaddingRight))
        }
        return scrollRange
    }

    override func computeHorizontalScrollRange() -> Int {
        let count = childCount
        let contentWidth = width - mPaddingLeft - mPaddingRight
        if count == 0 {
            return contentWidth
        }
        var scrollRange = mChildren[0].right
        let scrollX = mScrollX
        let overscrollRight = max(0, scrollRange - contentWidth)
        if scrollX < 0 {
            scrollRange -= scrollX
        } else if scrollX > overscrollRight {
            scrollRange += scrollX - overscrollRight
        }
        return scrollRange
    }

    override func computeHorizontalScrollOffset() -> Int {
        max(0, super.computeHorizontalScrollOffset())
    }

    // MARK: scrolling

    /// HorizontalScrollView.fullScroll(FOCUS_LEFT / FOCUS_RIGHT). In touch mode the focus does not move.
    @discardableResult
    func fullScroll(_ direction: Int) -> Bool {
        let right = direction == AView.FOCUS_RIGHT
        let width = self.width
        var left = 0
        var rightEdge = width
        if right {
            if childCount > 0 {
                let view = mChildren[0]
                rightEdge = view.right
                left = rightEdge - width
            }
        }
        return scrollAndFocus(direction, left, rightEdge)
    }

    /// HorizontalScrollView.pageScroll(FOCUS_LEFT / FOCUS_RIGHT).
    @discardableResult
    func pageScroll(_ direction: Int) -> Bool {
        let right = direction == AView.FOCUS_RIGHT
        let width = self.width
        var left: Int
        if right {
            left = mScrollX + width
            if childCount > 0 {
                let view = mChildren[0]
                if left + width > view.right {
                    left = view.right - width
                }
            }
        } else {
            left = mScrollX - width
            if left < 0 {
                left = 0
            }
        }
        return scrollAndFocus(direction, left, left + width)
    }

    private func scrollAndFocus(_ direction: Int, _ left: Int, _ right: Int) -> Bool {
        var handled = true
        let width = self.width
        let containerLeft = mScrollX
        let containerRight = containerLeft + width
        let goLeft = direction == AView.FOCUS_LEFT
        if left >= containerLeft && right <= containerRight {
            handled = false
        } else {
            let delta = goLeft ? (left - containerLeft) : (right - containerRight)
            doScrollX(delta)
        }
        return handled
    }

    private func doScrollX(_ delta: Int) {
        if delta != 0 {
            if mSmoothScrollingEnabled {
                smoothScrollBy(delta, 0)
            } else {
                scrollBy(delta, 0)
            }
        }
    }

    /// HorizontalScrollView.smoothScrollBy.
    func smoothScrollBy(_ dx: Int, _ dy: Int) {
        if childCount == 0 {
            // Nothing to do.
            return
        }
        var dx = dx
        let duration = AAnimationUtils.currentAnimationTimeMillis() - mLastScroll
        if duration > Int64(AHorizontalScrollView.ANIMATED_SCROLL_GAP) {
            let width = self.width - mPaddingRight - mPaddingLeft
            let right = mChildren[0].width
            let maxX = max(0, right - width)
            let scrollX = mScrollX
            dx = max(0, min(scrollX + dx, maxX)) - scrollX

            mScroller.startScroll(scrollX, mScrollY, dx, 0)
            stopUIKitScrolling()
            postInvalidateOnAnimation()
        } else {
            if !mScroller.isFinished {
                mScroller.abortAnimation()
            }
            scrollBy(dx, dy)
        }
        mLastScroll = AAnimationUtils.currentAnimationTimeMillis()
    }

    func smoothScrollTo(_ x: Int, _ y: Int) {
        smoothScrollBy(x - mScrollX, y - mScrollY)
    }

    /// HorizontalScrollView.computeScroll.
    override func computeScroll() {
        if mScroller.computeScrollOffset() {
            let oldX = mScrollX
            let oldY = mScrollY
            let x = mScroller.currX
            let y = mScroller.currY

            if oldX != x || oldY != y {
                let range = getScrollRange()
                _ = overScrollBy(x - oldX, y - oldY, oldX, oldY, range, 0,
                                 AViewConfiguration.get().scaledOverflingDistance, 0, false)
                onScrollChanged(mScrollX, mScrollY, oldX, oldY)
            }

            postInvalidateOnAnimation()
        }
    }

    private func overScrollBy(_ deltaX: Int, _ deltaY: Int, _ scrollX: Int, _ scrollY: Int, _ scrollRangeX: Int,
                              _ scrollRangeY: Int, _ maxOverScrollX: Int, _ maxOverScrollY: Int, _ isTouchEvent: Bool) -> Bool {
        let overScrollMode = self.overScrollMode
        let canScrollHorizontal = computeHorizontalScrollRange() > computeHorizontalScrollExtent()
        let canScrollVertical = computeVerticalScrollRange() > computeVerticalScrollExtent()
        let overScrollHorizontal = overScrollMode == AView.OVER_SCROLL_ALWAYS
            || (overScrollMode == AView.OVER_SCROLL_IF_CONTENT_SCROLLS && canScrollHorizontal)
        let overScrollVertical = overScrollMode == AView.OVER_SCROLL_ALWAYS
            || (overScrollMode == AView.OVER_SCROLL_IF_CONTENT_SCROLLS && canScrollVertical)

        var maxOverScrollX = maxOverScrollX
        var maxOverScrollY = maxOverScrollY
        var newScrollX = scrollX + deltaX
        if !overScrollHorizontal {
            maxOverScrollX = 0
        }
        var newScrollY = scrollY + deltaY
        if !overScrollVertical {
            maxOverScrollY = 0
        }

        let left = -maxOverScrollX
        let right = maxOverScrollX + scrollRangeX
        let top = -maxOverScrollY
        let bottom = maxOverScrollY + scrollRangeY

        var clampedX = false
        if newScrollX > right {
            newScrollX = right
            clampedX = true
        } else if newScrollX < left {
            newScrollX = left
            clampedX = true
        }

        var clampedY = false
        if newScrollY > bottom {
            newScrollY = bottom
            clampedY = true
        } else if newScrollY < top {
            newScrollY = top
            clampedY = true
        }

        onOverScrolled(newScrollX, newScrollY, clampedX, clampedY)
        return clampedX || clampedY
    }

    private func onOverScrolled(_ scrollX: Int, _ scrollY: Int, _ clampedX: Bool, _ clampedY: Bool) {
        if !mScroller.isFinished {
            let oldX = mScrollX
            let oldY = mScrollY
            mScrollX = scrollX
            mScrollY = scrollY
            scrollOffsetDidChange()
            onScrollChanged(mScrollX, mScrollY, oldX, oldY)
            if clampedX {
                mScroller.abortAnimation()
            }
        } else {
            super.scrollTo(scrollX, scrollY)
        }
    }

    /// HorizontalScrollView.scrollTo: clamps to the child.
    override func scrollTo(_ x: Int, _ y: Int) {
        // we rely on the fact the View.scrollBy calls scrollTo.
        if childCount > 0 {
            let child = mChildren[0]
            let cx = AHorizontalScrollView.clamp(x, width - mPaddingRight - mPaddingLeft, child.width)
            let cy = AHorizontalScrollView.clamp(y, height - mPaddingBottom - mPaddingTop, child.height)
            if cx != mScrollX || cy != mScrollY {
                super.scrollTo(cx, cy)
            }
        }
    }

    static func clamp(_ n: Int, _ my: Int, _ child: Int) -> Int {
        if my >= child || n < 0 {
            return 0
        }
        if (my + n) > child {
            return child - my
        }
        return n
    }

    // MARK: child rectangles and focus

    private func scrollToChild(_ child: AView) {
        let rect = ARect()
        child.getDrawingRect(rect)
        // Offset from child's local coordinates to ScrollView coordinates
        offsetDescendantRectToMyCoords(child, rect)
        let scrollDelta = computeScrollDeltaToGetChildRectOnScreen(rect)
        if scrollDelta != 0 {
            scrollBy(scrollDelta, 0)
        }
    }

    private func scrollToChildRect(_ rect: ARect, _ immediate: Bool) -> Bool {
        let delta = computeScrollDeltaToGetChildRectOnScreen(rect)
        let scroll = delta != 0
        if scroll {
            if immediate {
                scrollBy(delta, 0)
            } else {
                smoothScrollBy(delta, 0)
            }
        }
        return scroll
    }

    /// HorizontalScrollView.computeScrollDeltaToGetChildRectOnScreen (the horizontal fading edge length is 0).
    func computeScrollDeltaToGetChildRectOnScreen(_ rect: ARect) -> Int {
        if childCount == 0 { return 0 }
        let width = self.width
        let screenLeft = mScrollX
        let screenRight = screenLeft + width
        var scrollXDelta = 0
        if rect.right > screenRight && rect.left > screenLeft {
            // need to move right to get it in view: move right just enough so that the entire rectangle is in view
            // (or at least the first screen size chunk).
            if rect.width() > width {
                // just enough to get screen size chunk on
                scrollXDelta += (rect.left - screenLeft)
            } else {
                // get entire rect at right of screen
                scrollXDelta += (rect.right - screenRight)
            }
            // make sure we aren't scrolling beyond the end of our content
            let right = mChildren[0].right
            let distanceToRight = right - screenRight
            scrollXDelta = min(scrollXDelta, distanceToRight)
        } else if rect.left < screenLeft && rect.right < screenRight {
            // need to move right to get it in view: move right just enough so that entire rectangle is in view (or
            // at least the first screen size chunk of it).
            if rect.width() > width {
                // screen size chunk
                scrollXDelta -= (screenRight - rect.right)
            } else {
                // entire rect at left
                scrollXDelta -= (screenLeft - rect.left)
            }
            // make sure we aren't scrolling any further than the left our content
            scrollXDelta = max(scrollXDelta, -mScrollX)
        }
        return scrollXDelta
    }

    override func requestChildFocus(_ child: AView, _ focused: AView) {
        if !mIsLayoutDirty {
            scrollToChild(focused)
        } else {
            // The child may not be laid out yet, we can't compute the scroll yet
            mChildToScrollTo = focused
        }
        super.requestChildFocus(child, focused)
    }

    override func requestChildRectangleOnScreen(_ child: AView, _ rectangle: ARect, _ immediate: Bool) -> Bool {
        // offset into coordinate space of this scroll view
        rectangle.offset(child.left - child.scrollX, child.top - child.scrollY)
        return scrollToChildRect(rectangle, immediate)
    }

    override func requestLayout() {
        mIsLayoutDirty = true
        super.requestLayout()
    }

    // MARK: layout

    override func onLayout(_ changed: Bool, _ l: Int, _ t: Int, _ r: Int, _ b: Int) {
        var childWidth = 0
        var childMargins = 0

        if childCount > 0 {
            childWidth = mChildren[0].measuredWidth
            let childParams = mChildren[0].mLayoutParams as! AViewGroup.MarginLayoutParams
            childMargins = childParams.leftMargin + childParams.rightMargin
        }

        let available = r - l - getPaddingLeftWithForeground() - getPaddingRightWithForeground() - childMargins

        let forceLeftGravity = childWidth > available

        layoutChildren(l, t, r, b, forceLeftGravity)

        mIsLayoutDirty = false
        // Give a child focus if it needs it
        if let c = mChildToScrollTo, AScrollView.isViewDescendantOf(c, self) {
            scrollToChild(c)
        }
        mChildToScrollTo = nil

        if !isLaidOut {
            let scrollRange = max(0, childWidth - (r - l - mPaddingLeft - mPaddingRight))
            if isLayoutRtl {
                mScrollX = scrollRange - mScrollX
            } // mScrollX default value is "0" for LTR
            // Don't forget to clamp
            if mScrollX > scrollRange {
                mScrollX = scrollRange
            } else if mScrollX < 0 {
                mScrollX = 0
            }
        }

        // Calling this with the present values causes it to re-claim them
        scrollTo(mScrollX, mScrollY)
        updateScrollHost()
    }

    override func onSizeChanged(_ w: Int, _ h: Int, _ oldw: Int, _ oldh: Int) {
        super.onSizeChanged(w, h, oldw, oldh)
        guard let currentFocused = findFocus(), currentFocused !== self else { return }
        let maxJump = mRight - mLeft
        let rect = ARect()
        currentFocused.getDrawingRect(rect)
        offsetDescendantRectToMyCoords(currentFocused, rect)
        if rect.right + maxJump >= mScrollX && rect.left - maxJump <= mScrollX + width {
            let scrollDelta = computeScrollDeltaToGetChildRectOnScreen(rect)
            doScrollX(scrollDelta)
        }
    }

    override func onDetachedFromWindow() {
        super.onDetachedFromWindow()
        mScroller.abortAnimation()
    }

    // MARK: touch (the drag itself is the UIScrollView's)

    override func onInterceptTouchEvent(_ ev: AMotionEvent) -> Bool {
        false
    }

    override func onTouchEvent(_ event: AMotionEvent) -> Bool {
        if event.actionMasked == AMotionEvent.ACTION_DOWN {
            if childCount == 0 {
                return false
            }
            if !mScroller.isFinished {
                mScroller.abortAnimation()
            }
        }
        return true
    }

    override func requestDisallowInterceptTouchEvent(_ disallowIntercept: Bool) {
        if disallowIntercept {
            scrollHost?.panGestureRecognizer.isEnabled = false
        }
        super.requestDisallowInterceptTouchEvent(disallowIntercept)
    }

    override func touchStateDidReset() {
        if let pan = scrollHost?.panGestureRecognizer, !pan.isEnabled {
            pan.isEnabled = true
        }
    }

    override func hitTestChildHostItself(_ point: CGPoint, _ event: UIEvent?) -> UIView? {
        guard let host = scrollHost, childCount > 0 else { return nil }
        return host.point(inside: host.convert(point, from: self), with: event) ? host : nil
    }

    // MARK: UIScrollView synchronisation

    override func applyChildHostFrame(_ frame: CGRect, clips: Bool) {
        guard let host = scrollHost else { return }
        mSyncingHost = true
        if host.frame != frame { host.frame = frame }
        updateHostContentSize(host)
        if !mApplyingUIKitScroll {
            let d = AView.densityScale
            let target = CGPoint(x: CGFloat(mScrollX) / d, y: CGFloat(mScrollY) / d)
            if host.contentOffset != target {
                host.setContentOffset(target, animated: false)
            }
        }
        mSyncingHost = false
    }

    private func updateHostContentSize(_ host: UIScrollView) {
        let d = AView.densityScale
        let size = CGSize(width: host.bounds.width + CGFloat(getScrollRange()) / d, height: host.bounds.height)
        if host.contentSize != size { host.contentSize = size }
    }

    func updateScrollHost() {
        updateChildHostGeometry()
    }

    private func stopUIKitScrolling() {
        guard let host = scrollHost, host.isDecelerating || host.isDragging else { return }
        mSyncingHost = true
        host.setContentOffset(host.contentOffset, animated: false)
        mSyncingHost = false
    }

    func scrollViewDidScroll(_ scrollView: UIScrollView) {
        if mSyncingHost { return }
        let d = AView.densityScale
        let range = getScrollRange()
        var x = Int((scrollView.contentOffset.x * d).rounded())
        if x < 0 { x = 0 }
        if x > range { x = range }
        if x != mScrollX {
            mApplyingUIKitScroll = true
            scrollTo(x, mScrollY)
            mApplyingUIKitScroll = false
        }
    }

    func scrollViewWillBeginDragging(_ scrollView: UIScrollView) {
        if !mScroller.isFinished {
            mScroller.abortAnimation()
        }
    }
}

// MARK: - ConstraintLayout (subset)

/// androidx.constraintlayout.widget.ConstraintLayout, for the constraints the app's layouts use: left/right/start/end
/// and top/bottom anchors to the parent or to siblings (opposite or same side), margins and gone margins, horizontal
/// and vertical bias, and the four dimension behaviours (fixed px, wrap_content, match_parent, 0dp
/// MATCH_CONSTRAINT with spread / wrap / percent and min / max). No chains, guidelines, barriers, ratios or baselines.
///
/// The result follows ConstraintLayout 2.2.1 with its standard optimizer (DIRECT | CACHE_MEASURES): children are
/// measured with the Measurer's specs (wrap_content: the layout spec minus padding, margins not subtracted; resolved
/// MATCH_CONSTRAINT and fixed sizes EXACTLY), positions use Direct's integer centering
/// (d = (int)(0.5f + bias * distance) for a positive distance, (int)(bias * distance) otherwise), percent widths the
/// solver's float result rounded per edge, and a wrap_content layout grows to its children (top/left margins of the
/// connected sides included). START/END anchors and margins resolve with the child's layout direction and the RTL bias
/// is 1 - bias (ConstraintLayout.LayoutParams.resolveLayoutDirection).
class AConstraintLayout: AViewGroup {

    class LayoutParams: AViewGroup.MarginLayoutParams {
        static let PARENT_ID = "parent"
        static let UNSET = ""
        /// GONE_UNSET (Integer.MIN_VALUE): no gone margin.
        static let GONE_UNSET = Int(Int32.min)
        static let MATCH_CONSTRAINT = 0
        static let MATCH_CONSTRAINT_SPREAD = 0
        static let MATCH_CONSTRAINT_WRAP = 1
        static let MATCH_CONSTRAINT_PERCENT = 2
        static let HORIZONTAL = 0
        static let VERTICAL = 1
        static let CHAIN_SPREAD = 0
        static let CHAIN_SPREAD_INSIDE = 1
        static let CHAIN_PACKED = 2

        var leftToLeft = LayoutParams.UNSET
        var leftToRight = LayoutParams.UNSET
        var rightToLeft = LayoutParams.UNSET
        var rightToRight = LayoutParams.UNSET
        var topToTop = LayoutParams.UNSET
        var topToBottom = LayoutParams.UNSET
        var bottomToTop = LayoutParams.UNSET
        var bottomToBottom = LayoutParams.UNSET
        var startToEnd = LayoutParams.UNSET
        var startToStart = LayoutParams.UNSET
        var endToStart = LayoutParams.UNSET
        var endToEnd = LayoutParams.UNSET

        var goneLeftMargin = LayoutParams.GONE_UNSET
        var goneTopMargin = LayoutParams.GONE_UNSET
        var goneRightMargin = LayoutParams.GONE_UNSET
        var goneBottomMargin = LayoutParams.GONE_UNSET
        var goneStartMargin = LayoutParams.GONE_UNSET
        var goneEndMargin = LayoutParams.GONE_UNSET

        var horizontalBias: Float = 0.5
        var verticalBias: Float = 0.5

        var constrainedWidth = false
        var constrainedHeight = false

        var matchConstraintDefaultWidth = LayoutParams.MATCH_CONSTRAINT_SPREAD
        var matchConstraintDefaultHeight = LayoutParams.MATCH_CONSTRAINT_SPREAD
        var matchConstraintMinWidth = 0
        var matchConstraintMinHeight = 0
        var matchConstraintMaxWidth = 0
        var matchConstraintMaxHeight = 0
        var matchConstraintPercentWidth: Float = 1
        var matchConstraintPercentHeight: Float = 1

        // Resolved by resolveLayoutDirection / validate.
        var mResolvedLeftToLeft = LayoutParams.UNSET
        var mResolvedLeftToRight = LayoutParams.UNSET
        var mResolvedRightToLeft = LayoutParams.UNSET
        var mResolvedRightToRight = LayoutParams.UNSET
        var mResolveGoneLeftMargin = LayoutParams.GONE_UNSET
        var mResolveGoneRightMargin = LayoutParams.GONE_UNSET
        var mResolvedHorizontalBias: Float = 0.5
        var mHorizontalDimensionFixed = true
        var mVerticalDimensionFixed = true

        override init(_ width: Int, _ height: Int) {
            super.init(width, height)
        }

        override init(_ source: AViewGroup.LayoutParams) {
            super.init(source)
        }

        override init(_ source: AViewGroup.MarginLayoutParams) {
            super.init(source)
        }

        /// Copy constructor (ConstraintLayout.LayoutParams(LayoutParams)).
        init(_ source: AConstraintLayout.LayoutParams) {
            super.init(source as AViewGroup.MarginLayoutParams)
            leftToLeft = source.leftToLeft; leftToRight = source.leftToRight
            rightToLeft = source.rightToLeft; rightToRight = source.rightToRight
            topToTop = source.topToTop; topToBottom = source.topToBottom
            bottomToTop = source.bottomToTop; bottomToBottom = source.bottomToBottom
            startToEnd = source.startToEnd; startToStart = source.startToStart
            endToStart = source.endToStart; endToEnd = source.endToEnd
            goneLeftMargin = source.goneLeftMargin; goneTopMargin = source.goneTopMargin
            goneRightMargin = source.goneRightMargin; goneBottomMargin = source.goneBottomMargin
            goneStartMargin = source.goneStartMargin; goneEndMargin = source.goneEndMargin
            horizontalBias = source.horizontalBias; verticalBias = source.verticalBias
            constrainedWidth = source.constrainedWidth; constrainedHeight = source.constrainedHeight
            matchConstraintDefaultWidth = source.matchConstraintDefaultWidth
            matchConstraintDefaultHeight = source.matchConstraintDefaultHeight
            matchConstraintMinWidth = source.matchConstraintMinWidth
            matchConstraintMinHeight = source.matchConstraintMinHeight
            matchConstraintMaxWidth = source.matchConstraintMaxWidth
            matchConstraintMaxHeight = source.matchConstraintMaxHeight
            matchConstraintPercentWidth = source.matchConstraintPercentWidth
            matchConstraintPercentHeight = source.matchConstraintPercentHeight
            mResolvedLeftToLeft = source.mResolvedLeftToLeft; mResolvedLeftToRight = source.mResolvedLeftToRight
            mResolvedRightToLeft = source.mResolvedRightToLeft; mResolvedRightToRight = source.mResolvedRightToRight
            mResolveGoneLeftMargin = source.mResolveGoneLeftMargin; mResolveGoneRightMargin = source.mResolveGoneRightMargin
            mResolvedHorizontalBias = source.mResolvedHorizontalBias
        }

        /// ConstraintLayout.LayoutParams.validate.
        func validate() {
            mHorizontalDimensionFixed = true
            mVerticalDimensionFixed = true
            if width == AViewGroup.LayoutParams.WRAP_CONTENT && constrainedWidth {
                mHorizontalDimensionFixed = false
                if matchConstraintDefaultWidth == LayoutParams.MATCH_CONSTRAINT_SPREAD {
                    matchConstraintDefaultWidth = LayoutParams.MATCH_CONSTRAINT_WRAP
                }
            }
            if height == AViewGroup.LayoutParams.WRAP_CONTENT && constrainedHeight {
                mVerticalDimensionFixed = false
                if matchConstraintDefaultHeight == LayoutParams.MATCH_CONSTRAINT_SPREAD {
                    matchConstraintDefaultHeight = LayoutParams.MATCH_CONSTRAINT_WRAP
                }
            }
            if width == LayoutParams.MATCH_CONSTRAINT || width == AViewGroup.LayoutParams.MATCH_PARENT {
                mHorizontalDimensionFixed = false
                // We have to reset LayoutParams width/height to WRAP_CONTENT here, as some widgets like TextView will
                // use the layout params directly as a hint to know if they need to request a layout when their
                // content change (e.g. during setTextView)
                if width == LayoutParams.MATCH_CONSTRAINT && matchConstraintDefaultWidth == LayoutParams.MATCH_CONSTRAINT_WRAP {
                    width = AViewGroup.LayoutParams.WRAP_CONTENT
                    constrainedWidth = true
                }
            }
            if height == LayoutParams.MATCH_CONSTRAINT || height == AViewGroup.LayoutParams.MATCH_PARENT {
                mVerticalDimensionFixed = false
                if height == LayoutParams.MATCH_CONSTRAINT && matchConstraintDefaultHeight == LayoutParams.MATCH_CONSTRAINT_WRAP {
                    height = AViewGroup.LayoutParams.WRAP_CONTENT
                    constrainedHeight = true
                }
            }
        }

        /// ConstraintLayout.LayoutParams.resolveLayoutDirection: START/END anchors become LEFT/RIGHT.
        override func resolveLayoutDirection(_ layoutDirection: Int) {
            let originalLeftMargin = leftMargin
            let originalRightMargin = rightMargin

            super.resolveLayoutDirection(layoutDirection)
            let isRtl = AView.LAYOUT_DIRECTION_RTL == self.layoutDirection

            mResolvedRightToLeft = LayoutParams.UNSET
            mResolvedRightToRight = LayoutParams.UNSET
            mResolvedLeftToLeft = LayoutParams.UNSET
            mResolvedLeftToRight = LayoutParams.UNSET

            mResolveGoneLeftMargin = goneLeftMargin
            mResolveGoneRightMargin = goneRightMargin
            mResolvedHorizontalBias = horizontalBias

            let unset = LayoutParams.UNSET
            // Post JB MR1, if start/end are defined, they take precedence over left/right
            if isRtl {
                var startEndDefined = false
                if startToEnd != unset {
                    mResolvedRightToLeft = startToEnd
                    startEndDefined = true
                } else if startToStart != unset {
                    mResolvedRightToRight = startToStart
                    startEndDefined = true
                }
                if endToStart != unset {
                    mResolvedLeftToRight = endToStart
                    startEndDefined = true
                }
                if endToEnd != unset {
                    mResolvedLeftToLeft = endToEnd
                    startEndDefined = true
                }
                if goneStartMargin != LayoutParams.GONE_UNSET {
                    mResolveGoneRightMargin = goneStartMargin
                }
                if goneEndMargin != LayoutParams.GONE_UNSET {
                    mResolveGoneLeftMargin = goneEndMargin
                }
                if startEndDefined {
                    mResolvedHorizontalBias = 1 - horizontalBias
                }
            } else {
                if startToEnd != unset {
                    mResolvedLeftToRight = startToEnd
                }
                if startToStart != unset {
                    mResolvedLeftToLeft = startToStart
                }
                if endToStart != unset {
                    mResolvedRightToLeft = endToStart
                }
                if endToEnd != unset {
                    mResolvedRightToRight = endToEnd
                }
                if goneStartMargin != LayoutParams.GONE_UNSET {
                    mResolveGoneLeftMargin = goneStartMargin
                }
                if goneEndMargin != LayoutParams.GONE_UNSET {
                    mResolveGoneRightMargin = goneEndMargin
                }
            }
            // if no constraint is defined via RTL attributes, use left/right if present
            if endToStart == unset && endToEnd == unset && startToStart == unset && startToEnd == unset {
                if rightToLeft != unset {
                    mResolvedRightToLeft = rightToLeft
                    if rightMargin <= 0 && originalRightMargin > 0 {
                        rightMargin = originalRightMargin
                    }
                } else if rightToRight != unset {
                    mResolvedRightToRight = rightToRight
                    if rightMargin <= 0 && originalRightMargin > 0 {
                        rightMargin = originalRightMargin
                    }
                }
                if leftToLeft != unset {
                    mResolvedLeftToLeft = leftToLeft
                    if leftMargin <= 0 && originalLeftMargin > 0 {
                        leftMargin = originalLeftMargin
                    }
                } else if leftToRight != unset {
                    mResolvedLeftToRight = leftToRight
                    if leftMargin <= 0 && originalLeftMargin > 0 {
                        leftMargin = originalLeftMargin
                    }
                }
            }
        }
    }

    // MARK: solver model

    private enum Behaviour { case FIXED, WRAP_CONTENT, MATCH_PARENT, MATCH_CONSTRAINT }

    /// One side of a widget: the target (nil = the parent), whether the target side is its far side
    /// (right/bottom), the margin and the gone margin.
    private struct Anchor {
        var connected = false
        var target: Widget? = nil
        var targetFar = false
        var margin = 0
        var goneMargin = AConstraintLayout.LayoutParams.GONE_UNSET
    }

    private final class Widget {
        let view: AView
        let lp: AConstraintLayout.LayoutParams
        var gone: Bool
        var hBehaviour = Behaviour.FIXED
        var vBehaviour = Behaviour.FIXED
        var fixedWidth = 0
        var fixedHeight = 0
        var left = Anchor(), right = Anchor(), top = Anchor(), bottom = Anchor()
        var hBias: Float = 0.5
        var vBias: Float = 0.5
        var mcDefaultW = 0, mcDefaultH = 0
        var mcMinW = 0, mcMaxW = 0, mcMinH = 0, mcMaxH = 0
        var mcPercentW: Float = 1, mcPercentH: Float = 1
        // results (container content coordinates)
        var width = 0, height = 0
        var x1 = 0, x2 = 0, y1 = 0, y2 = 0
        var hResolved = false, vResolved = false
        var hVisiting = false, vVisiting = false
        var measured = false

        init(_ view: AView, _ lp: AConstraintLayout.LayoutParams) {
            self.view = view
            self.lp = lp
            self.gone = view.visibility == AView.GONE
        }

        /// ConstraintWidget.getWidth / getHeight: 0 for GONE.
        var w: Int { gone ? 0 : width }
        var h: Int { gone ? 0 : height }

        /// ConstraintAnchor.getMargin: 0 for a GONE widget; the gone margin when the target is GONE.
        func margin(_ a: Anchor) -> Int {
            if gone { return 0 }
            if a.goneMargin != AConstraintLayout.LayoutParams.GONE_UNSET, let t = a.target, t.gone {
                return a.goneMargin
            }
            return a.margin
        }
    }

    private var mWidgets: [Widget] = []
    // The container (content box) and the Measurer's capture.
    private var mContainerWidth = 0
    private var mContainerHeight = 0
    private var mHorizontalFixed = true
    private var mVerticalFixed = true
    private var mLayoutWidthSpec = 0
    private var mLayoutHeightSpec = 0
    private var mPaddingWidthCaptured = 0
    private var mPaddingHeightCaptured = 0
    private var mPaddingX = 0
    private var mPaddingY = 0
    private var mClMinWidth = 0
    private var mClMinHeight = 0
    private var mMaxWidth = Int(Int32.max)
    private var mMaxHeight = Int(Int32.max)

    override init() {
        super.init()
    }

    override func shouldDelayChildPressedState() -> Bool { false }

    /// ConstraintLayout's own minimum and maximum sizes (android:minWidth/minHeight, maxWidth/maxHeight).
    var constraintMinWidth: Int {
        get { mClMinWidth }
        set { if mClMinWidth != newValue { mClMinWidth = newValue; requestLayout() } }
    }
    var constraintMinHeight: Int {
        get { mClMinHeight }
        set { if mClMinHeight != newValue { mClMinHeight = newValue; requestLayout() } }
    }
    var maxWidth: Int {
        get { mMaxWidth }
        set { if mMaxWidth != newValue { mMaxWidth = newValue; requestLayout() } }
    }
    var maxHeight: Int {
        get { mMaxHeight }
        set { if mMaxHeight != newValue { mMaxHeight = newValue; requestLayout() } }
    }

    override func generateDefaultLayoutParams() -> AViewGroup.LayoutParams {
        LayoutParams(AViewGroup.LayoutParams.WRAP_CONTENT, AViewGroup.LayoutParams.WRAP_CONTENT)
    }

    override func checkLayoutParams(_ p: AViewGroup.LayoutParams?) -> Bool {
        p is AConstraintLayout.LayoutParams
    }

    override func generateLayoutParams(_ p: AViewGroup.LayoutParams) -> AViewGroup.LayoutParams {
        if let c = p as? AConstraintLayout.LayoutParams {
            return LayoutParams(c)
        } else if let m = p as? AViewGroup.MarginLayoutParams {
            return LayoutParams(m)
        }
        return LayoutParams(p)
    }

    private func isRtl() -> Bool {
        // android:supportsRtl = true in the app manifest.
        layoutDirection == AView.LAYOUT_DIRECTION_RTL
    }

    /// getPaddingWidth: the start/end padding when it is set, else left + right.
    private func getPaddingWidth() -> Int {
        var widthPadding = max(0, paddingLeft) + max(0, paddingRight)
        let rtlPadding = max(0, paddingStart) + max(0, paddingEnd)
        if rtlPadding > 0 {
            widthPadding = rtlPadding
        }
        return widthPadding
    }

    // MARK: measure

    override func onMeasure(_ widthMeasureSpec: Int, _ heightMeasureSpec: Int) {
        ensureResolvedPadding()
        let widthMode = AMeasureSpec.getMode(widthMeasureSpec)
        var widthSize = AMeasureSpec.getSize(widthMeasureSpec)
        let heightMode = AMeasureSpec.getMode(heightMeasureSpec)
        var heightSize = AMeasureSpec.getSize(heightMeasureSpec)

        // resolveSystem: padding capture (Measurer.captureLayoutInfo).
        let paddingY = max(0, paddingTop)
        let paddingBottomValue = max(0, paddingBottom)
        let paddingHeight = paddingY + paddingBottomValue
        let paddingWidth = getPaddingWidth()
        mLayoutWidthSpec = widthMeasureSpec
        mLayoutHeightSpec = heightMeasureSpec
        mPaddingWidthCaptured = paddingWidth
        mPaddingHeightCaptured = paddingHeight
        let paddingStartValue = max(0, paddingStart)
        let paddingEndValue = max(0, paddingEnd)
        if paddingStartValue > 0 || paddingEndValue > 0 {
            mPaddingX = isRtl() ? paddingEndValue : paddingStartValue
        } else {
            mPaddingX = max(0, paddingLeft)
        }
        mPaddingY = paddingY

        widthSize -= paddingWidth
        heightSize -= paddingHeight

        // setSelfDimensionBehaviour.
        let count = childCount
        mHorizontalFixed = widthMode == AMeasureSpec.EXACTLY
        mVerticalFixed = heightMode == AMeasureSpec.EXACTLY
        switch widthMode {
        case AMeasureSpec.AT_MOST:
            mContainerWidth = count == 0 ? max(0, mClMinWidth) : widthSize
        case AMeasureSpec.EXACTLY:
            mContainerWidth = min(mMaxWidth - paddingWidth, widthSize)
        default:
            mContainerWidth = count == 0 ? max(0, mClMinWidth) : 0
        }
        switch heightMode {
        case AMeasureSpec.AT_MOST:
            mContainerHeight = count == 0 ? max(0, mClMinHeight) : heightSize
        case AMeasureSpec.EXACTLY:
            mContainerHeight = min(mMaxHeight - paddingHeight, heightSize)
        default:
            mContainerHeight = count == 0 ? max(0, mClMinHeight) : 0
        }
        let availableWidth = mContainerWidth
        let availableHeight = mContainerHeight

        buildWidgets()
        solve(widthMode: widthMode, heightMode: heightMode, availableWidth: availableWidth, availableHeight: availableHeight)

        // resolveMeasuredDimension.
        let androidLayoutWidth = mContainerWidth + mPaddingWidthCaptured
        let androidLayoutHeight = mContainerHeight + mPaddingHeightCaptured
        var resolvedWidthSize = AView.resolveSizeAndState(androidLayoutWidth, widthMeasureSpec, 0)
        var resolvedHeightSize = AView.resolveSizeAndState(androidLayoutHeight, heightMeasureSpec, 0)
        resolvedWidthSize &= AView.MEASURED_SIZE_MASK
        resolvedHeightSize &= AView.MEASURED_SIZE_MASK
        resolvedWidthSize = min(mMaxWidth, resolvedWidthSize)
        resolvedHeightSize = min(mMaxHeight, resolvedHeightSize)
        if mWidthMeasuredTooSmall {
            resolvedWidthSize |= AView.MEASURED_STATE_TOO_SMALL
        }
        if mHeightMeasuredTooSmall {
            resolvedHeightSize |= AView.MEASURED_STATE_TOO_SMALL
        }
        setMeasuredDimension(resolvedWidthSize, resolvedHeightSize)
    }

    private var mWidthMeasuredTooSmall = false
    private var mHeightMeasuredTooSmall = false

    /// setChildrenConstraints + applyConstraintsFromLayoutParams for the supported constraints.
    private func buildWidgets() {
        var widgets: [Widget] = []
        var byId: [String: Widget] = [:]
        for child in mChildren {
            let lp: AConstraintLayout.LayoutParams
            if let c = child.mLayoutParams as? AConstraintLayout.LayoutParams {
                lp = c
            } else {
                let converted = generateLayoutParams(child.mLayoutParams ?? generateDefaultLayoutParams()) as! AConstraintLayout.LayoutParams
                child.mLayoutParams = converted
                lp = converted
            }
            lp.resolveLayoutDirection(child.layoutDirection)
            lp.validate()
            let w = Widget(child, lp)
            widgets.append(w)
            if let id = child.viewId { byId[id] = w }
        }
        if let myId = viewId { _ = myId } // a child anchored to this layout's own id means the parent
        func target(_ id: String) -> (connected: Bool, widget: Widget?) {
            if id == AConstraintLayout.LayoutParams.UNSET { return (false, nil) }
            if id == AConstraintLayout.LayoutParams.PARENT_ID || id == viewId { return (true, nil) }
            if let w = byId[id] { return (true, w) }
            return (false, nil) // an id that is not a child: no constraint (ConstraintLayout ignores it)
        }
        for w in widgets {
            let lp = w.lp
            // Left
            var t = target(lp.mResolvedLeftToLeft)
            if lp.mResolvedLeftToLeft != AConstraintLayout.LayoutParams.UNSET {
                if t.connected { w.left = Anchor(connected: true, target: t.widget, targetFar: false, margin: lp.leftMargin, goneMargin: lp.mResolveGoneLeftMargin) }
            } else {
                t = target(lp.mResolvedLeftToRight)
                if t.connected { w.left = Anchor(connected: true, target: t.widget, targetFar: true, margin: lp.leftMargin, goneMargin: lp.mResolveGoneLeftMargin) }
            }
            // Right
            t = target(lp.mResolvedRightToLeft)
            if lp.mResolvedRightToLeft != AConstraintLayout.LayoutParams.UNSET {
                if t.connected { w.right = Anchor(connected: true, target: t.widget, targetFar: false, margin: lp.rightMargin, goneMargin: lp.mResolveGoneRightMargin) }
            } else {
                t = target(lp.mResolvedRightToRight)
                if t.connected { w.right = Anchor(connected: true, target: t.widget, targetFar: true, margin: lp.rightMargin, goneMargin: lp.mResolveGoneRightMargin) }
            }
            // Top
            t = target(lp.topToTop)
            if lp.topToTop != AConstraintLayout.LayoutParams.UNSET {
                if t.connected { w.top = Anchor(connected: true, target: t.widget, targetFar: false, margin: lp.topMargin, goneMargin: lp.goneTopMargin) }
            } else {
                t = target(lp.topToBottom)
                if t.connected { w.top = Anchor(connected: true, target: t.widget, targetFar: true, margin: lp.topMargin, goneMargin: lp.goneTopMargin) }
            }
            // Bottom
            t = target(lp.bottomToTop)
            if lp.bottomToTop != AConstraintLayout.LayoutParams.UNSET {
                if t.connected { w.bottom = Anchor(connected: true, target: t.widget, targetFar: false, margin: lp.bottomMargin, goneMargin: lp.goneBottomMargin) }
            } else {
                t = target(lp.bottomToBottom)
                if t.connected { w.bottom = Anchor(connected: true, target: t.widget, targetFar: true, margin: lp.bottomMargin, goneMargin: lp.goneBottomMargin) }
            }
            if lp.mResolvedHorizontalBias >= 0 { w.hBias = lp.mResolvedHorizontalBias }
            if lp.verticalBias >= 0 { w.vBias = lp.verticalBias }

            // Dimensions.
            if !lp.mHorizontalDimensionFixed {
                if lp.width == AViewGroup.LayoutParams.MATCH_PARENT {
                    w.hBehaviour = lp.constrainedWidth ? .MATCH_CONSTRAINT : .MATCH_PARENT
                    w.left.margin = lp.leftMargin
                    w.right.margin = lp.rightMargin
                } else {
                    w.hBehaviour = .MATCH_CONSTRAINT
                }
            } else {
                w.hBehaviour = lp.width == AViewGroup.LayoutParams.WRAP_CONTENT ? .WRAP_CONTENT : .FIXED
                w.fixedWidth = lp.width
            }
            if !lp.mVerticalDimensionFixed {
                if lp.height == AViewGroup.LayoutParams.MATCH_PARENT {
                    w.vBehaviour = lp.constrainedHeight ? .MATCH_CONSTRAINT : .MATCH_PARENT
                    w.top.margin = lp.topMargin
                    w.bottom.margin = lp.bottomMargin
                } else {
                    w.vBehaviour = .MATCH_CONSTRAINT
                }
            } else {
                w.vBehaviour = lp.height == AViewGroup.LayoutParams.WRAP_CONTENT ? .WRAP_CONTENT : .FIXED
                w.fixedHeight = lp.height
            }
            // setHorizontalMatchStyle / setVerticalMatchStyle.
            w.mcDefaultW = lp.matchConstraintDefaultWidth
            w.mcMinW = lp.matchConstraintMinWidth
            w.mcMaxW = lp.matchConstraintMaxWidth == Int(Int32.max) ? 0 : lp.matchConstraintMaxWidth
            w.mcPercentW = lp.matchConstraintPercentWidth
            if w.mcPercentW > 0 && w.mcPercentW < 1 && w.mcDefaultW == AConstraintLayout.LayoutParams.MATCH_CONSTRAINT_SPREAD {
                w.mcDefaultW = AConstraintLayout.LayoutParams.MATCH_CONSTRAINT_PERCENT
            }
            w.mcDefaultH = lp.matchConstraintDefaultHeight
            w.mcMinH = lp.matchConstraintMinHeight
            w.mcMaxH = lp.matchConstraintMaxHeight == Int(Int32.max) ? 0 : lp.matchConstraintMaxHeight
            w.mcPercentH = lp.matchConstraintPercentHeight
            if w.mcPercentH > 0 && w.mcPercentH < 1 && w.mcDefaultH == AConstraintLayout.LayoutParams.MATCH_CONSTRAINT_SPREAD {
                w.mcDefaultH = AConstraintLayout.LayoutParams.MATCH_CONSTRAINT_PERCENT
            }
            w.width = w.hBehaviour == .FIXED ? w.fixedWidth : 0
            w.height = w.vBehaviour == .FIXED ? w.fixedHeight : 0
        }
        mWidgets = widgets
    }

    /// The Measurer's spec for one axis (SELF_DIMENSIONS, or EXACTLY for a resolved MATCH_CONSTRAINT size).
    private func childSpec(_ behaviour: Behaviour, _ dimension: Int, _ layoutSpec: Int, _ padding: Int, _ margins: Int,
                           _ resolvedSize: Int?) -> Int {
        switch behaviour {
        case .FIXED:
            return AMeasureSpec.makeMeasureSpec(dimension, AMeasureSpec.EXACTLY)
        case .WRAP_CONTENT:
            return AViewGroup.getChildMeasureSpec(layoutSpec, padding, AViewGroup.LayoutParams.WRAP_CONTENT)
        case .MATCH_PARENT:
            return AViewGroup.getChildMeasureSpec(layoutSpec, padding + margins, AViewGroup.LayoutParams.MATCH_PARENT)
        case .MATCH_CONSTRAINT:
            if let size = resolvedSize {
                return AMeasureSpec.makeMeasureSpec(size, AMeasureSpec.EXACTLY)
            }
            return AViewGroup.getChildMeasureSpec(layoutSpec, padding, AViewGroup.LayoutParams.WRAP_CONTENT)
        }
    }

    /// Measurer.measure: measures the child (min/max clamps re-measure EXACTLY) and stores the widget size.
    private func measureWidget(_ w: Widget, _ resolvedWidth: Int?, _ resolvedHeight: Int?) {
        if w.gone {
            w.width = 0
            w.height = 0
            return
        }
        var horizontalSpec = childSpec(w.hBehaviour, w.fixedWidth, mLayoutWidthSpec, mPaddingWidthCaptured,
                                       w.lp.leftMargin + w.lp.rightMargin, resolvedWidth)
        var verticalSpec = childSpec(w.vBehaviour, w.fixedHeight, mLayoutHeightSpec, mPaddingHeightCaptured,
                                     w.lp.topMargin + w.lp.bottomMargin, resolvedHeight)
        let child = w.view
        child.measure(horizontalSpec, verticalSpec)
        let mw = child.measuredWidth
        let mh = child.measuredHeight
        var width = mw
        var height = mh
        if w.mcMinW > 0 { width = max(w.mcMinW, width) }
        if w.mcMaxW > 0 { width = min(w.mcMaxW, width) }
        if w.mcMinH > 0 { height = max(w.mcMinH, height) }
        if w.mcMaxH > 0 { height = min(w.mcMaxH, height) }
        if mw != width || mh != height {
            if mw != width { horizontalSpec = AMeasureSpec.makeMeasureSpec(width, AMeasureSpec.EXACTLY) }
            if mh != height { verticalSpec = AMeasureSpec.makeMeasureSpec(height, AMeasureSpec.EXACTLY) }
            child.measure(horizontalSpec, verticalSpec)
            width = child.measuredWidth
            height = child.measuredHeight
        }
        w.width = width
        w.height = height
        w.measured = true
    }

    /// A MATCH_CONSTRAINT axis whose size comes from the constraints (spread with both sides, or percent);
    /// a spread axis with a dangling side measures like wrap_content (ConstraintWidgetContainer.measure).
    private func hasConstrainedSize(_ w: Widget, horizontal: Bool) -> Bool {
        if horizontal {
            guard w.hBehaviour == .MATCH_CONSTRAINT else { return false }
            if w.mcDefaultW == AConstraintLayout.LayoutParams.MATCH_CONSTRAINT_PERCENT { return true }
            if w.mcDefaultW == AConstraintLayout.LayoutParams.MATCH_CONSTRAINT_WRAP { return false }
            return w.left.connected && w.right.connected
        } else {
            guard w.vBehaviour == .MATCH_CONSTRAINT else { return false }
            if w.mcDefaultH == AConstraintLayout.LayoutParams.MATCH_CONSTRAINT_PERCENT { return true }
            if w.mcDefaultH == AConstraintLayout.LayoutParams.MATCH_CONSTRAINT_WRAP { return false }
            return w.top.connected && w.bottom.connected
        }
    }

    private func solve(widthMode: Int, heightMode: Int, availableWidth: Int, availableHeight: Int) {
        mWidthMeasuredTooSmall = false
        mHeightMeasuredTooSmall = false
        // 1. Self dimensions (BasicMeasure.measureChildren): every child whose size does not come from the
        //    constraints, with the wrap spec for an unresolved MATCH_CONSTRAINT side.
        for w in mWidgets where !w.gone {
            let hConstrained = hasConstrainedSize(w, horizontal: true)
            let vConstrained = hasConstrainedSize(w, horizontal: false)
            if hConstrained || vConstrained { continue }
            measureWidget(w, nil, nil)
        }
        for w in mWidgets where w.gone {
            w.width = 0
            w.height = 0
        }

        // 2. Wrap-content container sizes from the children (the solver's minimum wrap).
        if !mHorizontalFixed {
            var extent = 0
            for w in mWidgets where !w.gone {
                if hasConstrainedSize(w, horizontal: true) && !w.measured {
                    measureWidget(w, nil, nil)
                }
                var e = w.w
                if w.left.connected { e += w.margin(w.left) }
                if w.right.connected { e += w.margin(w.right) }
                extent = max(extent, e)
            }
            extent = max(extent, max(0, mClMinWidth - mPaddingWidthCaptured))
            if widthMode == AMeasureSpec.AT_MOST && extent > availableWidth && availableWidth > 0 {
                mWidthMeasuredTooSmall = true
                extent = availableWidth
            }
            mContainerWidth = extent
        }

        // 3. Horizontal resolution.
        for w in mWidgets { resolveHorizontal(w) }

        // 4. Vertical sizes: measure with the resolved horizontal size; a wrap-content container grows to the
        //    children.
        for w in mWidgets where !w.gone {
            let resolvedW: Int? = hasConstrainedSize(w, horizontal: true) ? w.x2 - w.x1 : nil
            if hasConstrainedSize(w, horizontal: false) {
                continue
            }
            if resolvedW != nil || !w.measured {
                measureWidget(w, resolvedW, nil)
            }
        }
        if !mVerticalFixed {
            var extent = 0
            for w in mWidgets where !w.gone {
                if hasConstrainedSize(w, horizontal: false) {
                    let resolvedW: Int? = hasConstrainedSize(w, horizontal: true) ? w.x2 - w.x1 : nil
                    measureWidget(w, resolvedW, nil)
                }
            }
            for w in mWidgets where !w.gone {
                extent = max(extent, verticalExtent(w))
            }
            extent = max(extent, max(0, mClMinHeight - mPaddingHeightCaptured))
            if heightMode == AMeasureSpec.AT_MOST && extent > availableHeight && availableHeight > 0 {
                mHeightMeasuredTooSmall = true
                extent = availableHeight
            }
            mContainerHeight = extent
        }

        // 5. Vertical resolution.
        for w in mWidgets { resolveVertical(w) }

        // 6. Final measure of the children sized by their constraints (USE_GIVEN_DIMENSIONS).
        for w in mWidgets where !w.gone {
            let hc = hasConstrainedSize(w, horizontal: true)
            let vc = hasConstrainedSize(w, horizontal: false)
            if hc || vc {
                let child = w.view
                let horizontalSpec = hc ? AMeasureSpec.makeMeasureSpec(w.x2 - w.x1, AMeasureSpec.EXACTLY)
                    : childSpec(w.hBehaviour, w.fixedWidth, mLayoutWidthSpec, mPaddingWidthCaptured,
                                w.lp.leftMargin + w.lp.rightMargin, nil)
                let verticalSpec = vc ? AMeasureSpec.makeMeasureSpec(w.y2 - w.y1, AMeasureSpec.EXACTLY)
                    : childSpec(w.vBehaviour, w.fixedHeight, mLayoutHeightSpec, mPaddingHeightCaptured,
                                w.lp.topMargin + w.lp.bottomMargin, nil)
                child.measure(horizontalSpec, verticalSpec)
            }
        }
    }

    /// The bottom extent a widget needs inside a wrap_content container.
    private func verticalExtent(_ w: Widget) -> Int {
        var top = 0
        if w.top.connected {
            if let t = w.top.target {
                resolveVerticalProvisional(t)
                top = (w.top.targetFar ? t.y2 : t.y1) + w.margin(w.top)
            } else {
                top = w.margin(w.top)
            }
        }
        var e = top + w.h
        if w.bottom.connected && w.bottom.target == nil { e += w.margin(w.bottom) }
        return e
    }

    /// Positions in a wrap container before its height is known (top anchored chains only).
    private func resolveVerticalProvisional(_ w: Widget) {
        if w.vResolved { return }
        var top = 0
        if w.top.connected {
            if let t = w.top.target {
                if !t.vVisiting {
                    t.vVisiting = true
                    resolveVerticalProvisional(t)
                    t.vVisiting = false
                }
                top = (w.top.targetFar ? t.y2 : t.y1) + w.margin(w.top)
            } else {
                top = w.margin(w.top)
            }
        }
        w.y1 = top
        w.y2 = top + w.h
    }

    /// The final value of a target side (parent sides: 0 and the container size).
    private func horizontalTargetValue(_ a: Anchor) -> Int? {
        guard a.connected else { return nil }
        if let t = a.target {
            if !t.hResolved {
                if t.hVisiting { return nil }
                resolveHorizontal(t)
            }
            return a.targetFar ? t.x2 : t.x1
        }
        return a.targetFar ? mContainerWidth : 0
    }

    private func verticalTargetValue(_ a: Anchor) -> Int? {
        guard a.connected else { return nil }
        if let t = a.target {
            if !t.vResolved {
                if t.vVisiting { return nil }
                resolveVertical(t)
            }
            return a.targetFar ? t.y2 : t.y1
        }
        return a.targetFar ? mContainerHeight : 0
    }

    /// Direct.solveHorizontalCenterConstraints arithmetic (also used for match-constraint sizes).
    private static func centered(_ s1: Int, _ s2: Int, _ size: Int, _ bias: Float) -> (Int, Int) {
        let distance = s1 > s2 ? s1 - s2 - size : s2 - s1 - size
        let d1: Int
        if distance > 0 {
            d1 = AViewConfiguration.f2i(0.5 + bias * Float(distance))
        } else {
            d1 = AViewConfiguration.f2i(bias * Float(distance))
        }
        let x1 = s1 + d1
        return s1 > s2 ? (x1, x1 - size) : (x1, x1 + size)
    }

    private func resolveHorizontal(_ w: Widget) {
        if w.hResolved { return }
        w.hVisiting = true
        defer {
            w.hVisiting = false
            w.hResolved = true
        }
        let l = horizontalTargetValue(w.left)
        let r = horizontalTargetValue(w.right)
        let marginL = w.margin(w.left)
        let marginR = w.margin(w.right)

        if w.hBehaviour == .MATCH_PARENT && !w.gone {
            // Optimizer.checkMatchParent: from the parent's sides with the margins.
            w.x1 = marginL
            w.x2 = mContainerWidth - marginR
            return
        }
        if hasConstrainedSize(w, horizontal: true) && !w.gone {
            if w.mcDefaultW == AConstraintLayout.LayoutParams.MATCH_CONSTRAINT_PERCENT {
                // The solver: width = percent * parent width, centred with the bias; each edge rounded.
                let widthF = w.mcPercentW * Float(mContainerWidth)
                var width = widthF
                if w.mcMinW > 0 { width = max(Float(w.mcMinW), width) }
                if w.mcMaxW > 0 { width = min(Float(w.mcMaxW), width) }
                if let l = l, let r = r {
                    let s1 = Float(l + marginL)
                    let s2 = Float(r - marginR)
                    let begin = s1 + w.hBias * (s2 - s1 - width)
                    w.x1 = AViewConfiguration.f2i(begin + 0.5)
                    w.x2 = AViewConfiguration.f2i(begin + width + 0.5)
                } else if let l = l {
                    let begin = Float(l + marginL)
                    w.x1 = AViewConfiguration.f2i(begin + 0.5)
                    w.x2 = AViewConfiguration.f2i(begin + width + 0.5)
                } else if let r = r {
                    let end = Float(r - marginR)
                    w.x2 = AViewConfiguration.f2i(end + 0.5)
                    w.x1 = AViewConfiguration.f2i(end - width + 0.5)
                } else {
                    w.x1 = 0
                    w.x2 = AViewConfiguration.f2i(width + 0.5)
                }
                return
            }
            // Direct.solveHorizontalMatchConstraint (spread).
            if let l = l, let r = r {
                let s1 = l + marginL
                let s2 = r - marginR
                if s2 >= s1 {
                    var width = s2 - s1
                    width = max(w.mcMinW, width)
                    if w.mcMaxW > 0 { width = min(w.mcMaxW, width) }
                    let distance = s2 - s1 - width
                    let d1 = AViewConfiguration.f2i(0.5 + w.hBias * Float(distance))
                    w.x1 = s1 + d1
                    w.x2 = w.x1 + width
                } else {
                    // The solver keeps the widget between the anchors: zero width at the centre.
                    let mid = AViewConfiguration.f2i(Float(s1) + w.hBias * Float(s2 - s1) + 0.5)
                    w.x1 = mid
                    w.x2 = mid
                }
                return
            }
        }
        let width = w.w
        if let l = l, let r = r {
            var s1 = l + marginL
            var s2 = r - marginR
            var bias = w.hBias
            if l == r {
                bias = 0.5
                s1 = l
                s2 = r
            }
            let (x1, x2) = AConstraintLayout.centered(s1, s2, width, bias)
            w.x1 = min(x1, x2)
            w.x2 = max(x1, x2)
        } else if let l = l {
            w.x1 = l + marginL
            w.x2 = w.x1 + width
        } else if let r = r {
            w.x2 = r - marginR
            w.x1 = w.x2 - width
        } else {
            w.x1 = 0
            w.x2 = width
        }
    }

    private func resolveVertical(_ w: Widget) {
        if w.vResolved { return }
        w.vVisiting = true
        defer {
            w.vVisiting = false
            w.vResolved = true
        }
        let t = verticalTargetValue(w.top)
        let b = verticalTargetValue(w.bottom)
        let marginT = w.margin(w.top)
        let marginB = w.margin(w.bottom)

        if w.vBehaviour == .MATCH_PARENT && !w.gone {
            w.y1 = marginT
            w.y2 = mContainerHeight - marginB
            return
        }
        if hasConstrainedSize(w, horizontal: false) && !w.gone {
            if w.mcDefaultH == AConstraintLayout.LayoutParams.MATCH_CONSTRAINT_PERCENT {
                let heightF = w.mcPercentH * Float(mContainerHeight)
                var height = heightF
                if w.mcMinH > 0 { height = max(Float(w.mcMinH), height) }
                if w.mcMaxH > 0 { height = min(Float(w.mcMaxH), height) }
                if let t = t, let b = b {
                    let s1 = Float(t + marginT)
                    let s2 = Float(b - marginB)
                    let begin = s1 + w.vBias * (s2 - s1 - height)
                    w.y1 = AViewConfiguration.f2i(begin + 0.5)
                    w.y2 = AViewConfiguration.f2i(begin + height + 0.5)
                } else if let t = t {
                    let begin = Float(t + marginT)
                    w.y1 = AViewConfiguration.f2i(begin + 0.5)
                    w.y2 = AViewConfiguration.f2i(begin + height + 0.5)
                } else if let b = b {
                    let end = Float(b - marginB)
                    w.y2 = AViewConfiguration.f2i(end + 0.5)
                    w.y1 = AViewConfiguration.f2i(end - height + 0.5)
                } else {
                    w.y1 = 0
                    w.y2 = AViewConfiguration.f2i(height + 0.5)
                }
                return
            }
            if let t = t, let b = b {
                let s1 = t + marginT
                let s2 = b - marginB
                if s2 >= s1 {
                    var height = s2 - s1
                    height = max(w.mcMinH, height)
                    if w.mcMaxH > 0 { height = min(w.mcMaxH, height) }
                    let distance = s2 - s1 - height
                    let d1 = AViewConfiguration.f2i(0.5 + w.vBias * Float(distance))
                    w.y1 = s1 + d1
                    w.y2 = w.y1 + height
                } else {
                    let mid = AViewConfiguration.f2i(Float(s1) + w.vBias * Float(s2 - s1) + 0.5)
                    w.y1 = mid
                    w.y2 = mid
                }
                return
            }
        }
        let height = w.h
        if let t = t, let b = b {
            var s1 = t + marginT
            var s2 = b - marginB
            var bias = w.vBias
            if t == b {
                bias = 0.5
                s1 = t
                s2 = b
            }
            // Direct.solveVerticalCenterConstraints (s1 > s2 mirrors the offset).
            let distance = s1 > s2 ? s1 - s2 - height : s2 - s1 - height
            let d1: Int
            if distance > 0 {
                d1 = AViewConfiguration.f2i(0.5 + bias * Float(distance))
            } else {
                d1 = AViewConfiguration.f2i(bias * Float(distance))
            }
            if s1 > s2 {
                let y1 = s1 - d1
                w.y1 = min(y1, y1 - height)
                w.y2 = max(y1, y1 - height)
            } else {
                w.y1 = s1 + d1
                w.y2 = w.y1 + height
            }
        } else if let t = t {
            w.y1 = t + marginT
            w.y2 = w.y1 + height
        } else if let b = b {
            w.y2 = b - marginB
            w.y1 = w.y2 - height
        } else {
            w.y1 = 0
            w.y2 = height
        }
    }

    // MARK: layout

    /// ConstraintLayout.onLayout: GONE children are skipped; positions are offset by the padding.
    override func onLayout(_ changed: Bool, _ left: Int, _ top: Int, _ right: Int, _ bottom: Int) {
        for w in mWidgets {
            let child = w.view
            guard child.mParent === self else { continue }
            if child.visibility == AView.GONE {
                continue
            }
            let l = mPaddingX + w.x1
            let t = mPaddingY + w.y1
            let r = l + (w.x2 - w.x1)
            let b = t + (w.y2 - w.y1)
            child.layout(l, t, r, b)
        }
    }

    override func onViewAdded(_ child: AView) {
        super.onViewAdded(child)
        requestLayout()
    }

    override func onViewRemoved(_ child: AView) {
        super.onViewRemoved(child)
        mWidgets.removeAll { $0.view === child }
        requestLayout()
    }
}
