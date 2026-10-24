import UIKit

// android.view.View on UIKit (VIEW-API "Views"; DESIGN 2.5, 4.4).
//
// The Android pixel world: every geometry value here (left/top/width/measured sizes, padding, translations,
// pivots, touch coordinates) is a device pixel, exactly as on Android. UIKit frames are derived from the Android
// integer edges (pt = px / density) and never fed back, so there is no rounding drift.
//
// Measure/layout, invalidation, visibility, drawable state, click/long-click handling, attach/detach and the
// window-insets dispatch follow the AOSP View code (Android 14), statement by statement where it matters.
//
// Drawing: a view that draws (willNotDraw == false, or a background) owns a "content layer" (a CALayer below its
// subviews) whose backing store CA manages; the layer's draw(in:) builds an ACanvas in pixels and runs the Android
// order background -> onDraw -> dispatchDraw. Children are UIKit subviews composited above it, the foreground
// drawable is a separate layer above the children. Views with drawsInTraversal == true never get a backing store:
// AViewRoot calls onDraw(ACanvas.noop) from the Choreographer traversal instead. A ViewGroup that only has a
// ColorDrawable background is drawn with layer.backgroundColor (no bitmap).
//
// Touches: UIKit touches are forwarded to the view's AViewRoot, which converts them to AMotionEvents and runs the
// Android dispatch (ViewGroup.dispatchTouchEvent) from the root; hitTest(_:with:) only decides which UIKit view
// receives the UITouch (Android-like: VISIBLE views, alpha-0 included, consuming views win, others let the touch
// fall through), which matters for UIScrollView-backed scroll views and native text fields.

/// android.view.View.MeasureSpec.
enum AMeasureSpec {
    static let MODE_SHIFT = 30
    static let MODE_MASK = 0x3 << 30
    /// The 30 size bits (Java `~MODE_MASK` on a 32-bit int).
    static let SIZE_MASK = 0x3FFF_FFFF
    static let UNSPECIFIED = 0 << 30
    static let EXACTLY = 1 << 30
    static let AT_MOST = 2 << 30

    /// makeMeasureSpec: (size & ~MODE_MASK) | (mode & MODE_MASK) with Java 32-bit masks (a negative size wraps
    /// into the size bits exactly as on Android).
    static func makeMeasureSpec(_ size: Int, _ mode: Int) -> Int {
        (size & SIZE_MASK) | (mode & MODE_MASK)
    }

    /// makeSafeMeasureSpec: like makeMeasureSpec (Android returns 0 for UNSPECIFIED only for targetSdk < M).
    static func makeSafeMeasureSpec(_ size: Int, _ mode: Int) -> Int {
        makeMeasureSpec(size, mode)
    }

    static func getMode(_ measureSpec: Int) -> Int { measureSpec & MODE_MASK }
    static func getSize(_ measureSpec: Int) -> Int { measureSpec & SIZE_MASK }

    static func adjust(_ measureSpec: Int, _ delta: Int) -> Int {
        let mode = getMode(measureSpec)
        var size = getSize(measureSpec)
        if mode == UNSPECIFIED {
            // No need to adjust size for UNSPECIFIED mode.
            return makeMeasureSpec(size, UNSPECIFIED)
        }
        size += delta
        if size < 0 {
            size = 0
        }
        return makeMeasureSpec(size, mode)
    }

    static func toString(_ measureSpec: Int) -> String {
        let mode = getMode(measureSpec)
        let size = getSize(measureSpec)
        var sb = "MeasureSpec: "
        if mode == UNSPECIFIED {
            sb += "UNSPECIFIED "
        } else if mode == EXACTLY {
            sb += "EXACTLY "
        } else if mode == AT_MOST {
            sb += "AT_MOST "
        } else {
            sb += "\(mode) "
        }
        sb += String(size)
        return sb
    }
}

/// android.view.HapticFeedbackConstants (android-36 values). AView.performHapticFeedback plays them through AHaptics
/// (AHaptics.swift: the Android vibration of each constant on iOS feedback generators).
enum AHapticFeedbackConstants {
    static let NO_HAPTICS = -1
    static let LONG_PRESS = 0
    static let VIRTUAL_KEY = 1
    static let KEYBOARD_TAP = 3
    static let KEYBOARD_PRESS = 3
    static let CLOCK_TICK = 4
    static let CALENDAR_DATE = 5
    static let CONTEXT_CLICK = 6
    static let KEYBOARD_RELEASE = 7
    static let VIRTUAL_KEY_RELEASE = 8
    static let TEXT_HANDLE_MOVE = 9
    static let ENTRY_BUMP = 10
    static let DRAG_CROSSING = 11
    static let GESTURE_START = 12
    static let GESTURE_END = 13
    static let EDGE_SQUEEZE = 14
    static let EDGE_RELEASE = 15
    static let CONFIRM = 16
    static let REJECT = 17
    static let SCROLL_TICK = 18
    static let SCROLL_ITEM_FOCUS = 19
    static let SCROLL_LIMIT = 20
    static let TOGGLE_ON = 21
    static let TOGGLE_OFF = 22
    static let GESTURE_THRESHOLD_ACTIVATE = 23
    static let GESTURE_THRESHOLD_DEACTIVATE = 24
    static let DRAG_START = 25
    static let SEGMENT_TICK = 26
    static let SEGMENT_FREQUENT_TICK = 27
    static let FLAG_IGNORE_VIEW_SETTING = 0x0001
    static let FLAG_IGNORE_GLOBAL_SETTING = 0x0002
}

/// View.OnLayoutChangeListener.
final class AOnLayoutChangeListener {
    let block: (AView, Int, Int, Int, Int, Int, Int, Int, Int) -> Void
    init(_ block: @escaping (AView, Int, Int, Int, Int, Int, Int, Int, Int) -> Void) { self.block = block }
    func onLayoutChange(_ v: AView, _ left: Int, _ top: Int, _ right: Int, _ bottom: Int,
                        _ oldLeft: Int, _ oldTop: Int, _ oldRight: Int, _ oldBottom: Int) {
        block(v, left, top, right, bottom, oldLeft, oldTop, oldRight, oldBottom)
    }
}

/// View.OnAttachStateChangeListener: closure form, or subclass and override.
class AOnAttachStateChangeListener {
    private let attached: ((AView) -> Void)?
    private let detached: ((AView) -> Void)?
    init(_ onAttached: ((AView) -> Void)? = nil, _ onDetached: ((AView) -> Void)? = nil) {
        attached = onAttached
        detached = onDetached
    }
    func onViewAttachedToWindow(_ v: AView) { attached?(v) }
    func onViewDetachedFromWindow(_ v: AView) { detached?(v) }
}

/// ViewTreeObserver.OnGlobalLayoutListener.
final class AOnGlobalLayoutListener {
    let block: () -> Void
    init(_ block: @escaping () -> Void) { self.block = block }
    func onGlobalLayout() { block() }
}

/// ViewTreeObserver.OnPreDrawListener: return false to cancel the current drawing pass (a new traversal follows).
final class AOnPreDrawListener {
    let block: () -> Bool
    init(_ block: @escaping () -> Bool) { self.block = block }
    func onPreDraw() -> Bool { block() }
}

/// ViewTreeObserver.OnScrollChangedListener.
final class AOnScrollChangedListener {
    let block: () -> Void
    init(_ block: @escaping () -> Void) { self.block = block }
    func onScrollChanged() { block() }
}

/// ViewTreeObserver.OnDrawListener.
final class AOnDrawListener {
    let block: () -> Void
    init(_ block: @escaping () -> Void) { self.block = block }
    func onDraw() { block() }
}

/// android.view.ViewTreeObserver: one per window (AViewRoot); a detached view gets a floating observer that is
/// merged into the window's observer when the view is attached (then it is no longer alive). Dispatch iterates a
/// snapshot (CopyOnWriteArray semantics: listeners removed during a dispatch are still called in that pass).
final class AViewTreeObserver {
    private var onGlobalLayoutListeners: [AOnGlobalLayoutListener] = []
    private var onPreDrawListeners: [AOnPreDrawListener] = []
    private var onScrollChangedListeners: [AOnScrollChangedListener] = []
    private var onDrawListeners: [AOnDrawListener] = []
    private(set) var isAlive = true

    init() {}

    private func checkIsAlive() -> Bool {
        if !isAlive {
            ALog.w("ViewTreeObserver", "This ViewTreeObserver is not alive, call getViewTreeObserver() again")
        }
        return isAlive
    }

    func addOnGlobalLayoutListener(_ listener: AOnGlobalLayoutListener) {
        guard checkIsAlive() else { return }
        onGlobalLayoutListeners.append(listener)
    }
    func removeOnGlobalLayoutListener(_ victim: AOnGlobalLayoutListener) {
        guard checkIsAlive() else { return }
        if let i = onGlobalLayoutListeners.firstIndex(where: { $0 === victim }) { onGlobalLayoutListeners.remove(at: i) }
    }
    /// Deprecated alias of removeOnGlobalLayoutListener.
    func removeGlobalOnLayoutListener(_ victim: AOnGlobalLayoutListener) { removeOnGlobalLayoutListener(victim) }

    func addOnPreDrawListener(_ listener: AOnPreDrawListener) {
        guard checkIsAlive() else { return }
        onPreDrawListeners.append(listener)
    }
    func removeOnPreDrawListener(_ victim: AOnPreDrawListener) {
        guard checkIsAlive() else { return }
        if let i = onPreDrawListeners.firstIndex(where: { $0 === victim }) { onPreDrawListeners.remove(at: i) }
    }

    func addOnScrollChangedListener(_ listener: AOnScrollChangedListener) {
        guard checkIsAlive() else { return }
        onScrollChangedListeners.append(listener)
    }
    func removeOnScrollChangedListener(_ victim: AOnScrollChangedListener) {
        guard checkIsAlive() else { return }
        if let i = onScrollChangedListeners.firstIndex(where: { $0 === victim }) { onScrollChangedListeners.remove(at: i) }
    }

    func addOnDrawListener(_ listener: AOnDrawListener) {
        guard checkIsAlive() else { return }
        onDrawListeners.append(listener)
    }
    func removeOnDrawListener(_ victim: AOnDrawListener) {
        guard checkIsAlive() else { return }
        if let i = onDrawListeners.firstIndex(where: { $0 === victim }) { onDrawListeners.remove(at: i) }
    }

    /// Moves every listener of a floating observer into this one and kills the floating observer.
    func merge(_ observer: AViewTreeObserver) {
        onGlobalLayoutListeners.append(contentsOf: observer.onGlobalLayoutListeners)
        onPreDrawListeners.append(contentsOf: observer.onPreDrawListeners)
        onScrollChangedListeners.append(contentsOf: observer.onScrollChangedListeners)
        onDrawListeners.append(contentsOf: observer.onDrawListeners)
        observer.kill()
    }

    func kill() {
        isAlive = false
    }

    var hasGlobalLayoutListeners: Bool { !onGlobalLayoutListeners.isEmpty }

    func dispatchOnGlobalLayout() {
        let listeners = onGlobalLayoutListeners
        for l in listeners { l.onGlobalLayout() }
    }

    /// Returns true when any listener cancelled the drawing pass (every listener is called).
    func dispatchOnPreDraw() -> Bool {
        var cancelDraw = false
        let listeners = onPreDrawListeners
        for l in listeners {
            cancelDraw = !l.onPreDraw() || cancelDraw
        }
        return cancelDraw
    }

    func dispatchOnScrollChanged() {
        let listeners = onScrollChangedListeners
        for l in listeners { l.onScrollChanged() }
    }

    func dispatchOnDraw() {
        let listeners = onDrawListeners
        for l in listeners { l.onDraw() }
    }
}

class AView: UIView, AAnimatableView {
    typealias MeasureSpec = AMeasureSpec
    typealias OnLayoutChangeListener = AOnLayoutChangeListener
    typealias OnAttachStateChangeListener = AOnAttachStateChangeListener

    // MARK: - constants

    static let NO_ID = -1
    static let VISIBLE = 0x00000000
    static let INVISIBLE = 0x00000004
    static let GONE = 0x00000008
    static let VISIBILITY_MASK = 0x0000000C

    static let LAYOUT_DIRECTION_LTR = 0
    static let LAYOUT_DIRECTION_RTL = 1
    static let LAYOUT_DIRECTION_INHERIT = 2
    static let LAYOUT_DIRECTION_LOCALE = 3
    static let LAYOUT_DIRECTION_UNDEFINED = -1

    static let TEXT_DIRECTION_INHERIT = 0
    static let TEXT_DIRECTION_FIRST_STRONG = 1
    static let TEXT_DIRECTION_ANY_RTL = 2
    static let TEXT_DIRECTION_LTR = 3
    static let TEXT_DIRECTION_RTL = 4
    static let TEXT_DIRECTION_LOCALE = 5
    static let TEXT_DIRECTION_FIRST_STRONG_LTR = 6
    static let TEXT_DIRECTION_FIRST_STRONG_RTL = 7

    static let TEXT_ALIGNMENT_INHERIT = 0
    static let TEXT_ALIGNMENT_GRAVITY = 1
    static let TEXT_ALIGNMENT_TEXT_START = 2
    static let TEXT_ALIGNMENT_TEXT_END = 3
    static let TEXT_ALIGNMENT_CENTER = 4
    static let TEXT_ALIGNMENT_VIEW_START = 5
    static let TEXT_ALIGNMENT_VIEW_END = 6

    static let MEASURED_SIZE_MASK = 0x00ff_ffff
    static let MEASURED_STATE_MASK = 0xff00_0000
    static let MEASURED_HEIGHT_STATE_SHIFT = 16
    static let MEASURED_STATE_TOO_SMALL = 0x0100_0000

    static let FOCUS_BACKWARD = 0x01
    static let FOCUS_FORWARD = 0x02
    static let FOCUS_LEFT = 0x11
    static let FOCUS_UP = 0x21
    static let FOCUS_RIGHT = 0x42
    static let FOCUS_DOWN = 0x82

    static let NOT_FOCUSABLE = 0x00000000
    static let FOCUSABLE = 0x00000001
    static let FOCUSABLE_AUTO = 0x00000010

    static let IMPORTANT_FOR_ACCESSIBILITY_AUTO = 0x00000000
    static let IMPORTANT_FOR_ACCESSIBILITY_YES = 0x00000001
    static let IMPORTANT_FOR_ACCESSIBILITY_NO = 0x00000002
    static let IMPORTANT_FOR_ACCESSIBILITY_NO_HIDE_DESCENDANTS = 0x00000004

    static let LAYER_TYPE_NONE = 0
    static let LAYER_TYPE_SOFTWARE = 1
    static let LAYER_TYPE_HARDWARE = 2

    static let OVER_SCROLL_ALWAYS = 0
    static let OVER_SCROLL_IF_CONTENT_SCROLLS = 1
    static let OVER_SCROLL_NEVER = 2

    static let SCROLLBARS_INSIDE_OVERLAY = 0
    static let SCROLLBARS_INSIDE_INSET = 0x01000000
    static let SCROLLBARS_OUTSIDE_OVERLAY = 0x02000000
    static let SCROLLBARS_OUTSIDE_INSET = 0x03000000

    static let SOUND_EFFECTS_ENABLED = 0x08000000
    static let HAPTIC_FEEDBACK_ENABLED = 0x10000000

    /// Internal: Integer.MIN_VALUE as Android's UNDEFINED_PADDING.
    static let UNDEFINED_PADDING = Int(Int32.min)

    // android.R.attr state ids (ViewState). AStateSet (graphics) has most; window_focused is only needed here.
    static let STATE_WINDOW_FOCUSED = 16842909
    static let STATE_SELECTED = 16842913
    static let STATE_FOCUSED = 16842908
    static let STATE_ENABLED = 16842910
    static let STATE_PRESSED = 16842919
    static let STATE_ACTIVATED = 16843518

    /// Device pixels per UIKit point (Android density). Fixed for the main screen.
    static let densityScale: CGFloat = UIScreen.main.scale

    // MARK: - attach info (one per window = AViewRoot)

    /// View.AttachInfo: the window a view is attached to.
    final class AttachInfo {
        weak var root: AViewRoot?
        let handler: AHandler
        let treeObserver: AViewTreeObserver
        var windowVisibility: Int = AView.VISIBLE
        var viewScrollChanged = false
        var hasWindowFocus = true
        weak var viewRequestingLayout: AView?
        weak var focusedView: AView?
        init(root: AViewRoot, handler: AHandler, treeObserver: AViewTreeObserver) {
            self.root = root
            self.handler = handler
            self.treeObserver = treeObserver
        }
    }

    // MARK: - tree state

    /// Android `mParent` when it is a ViewGroup.
    weak var mParent: AViewGroup?
    /// The AViewRoot when this view is a window's root view (Android: mParent is the ViewRootImpl).
    weak var mViewRootParent: AViewRoot?
    var mAttachInfo: AttachInfo?
    /// The last window this view was attached to: UIKit may deliver the rest of a touch stream after a detach.
    weak var mTouchRoot: AViewRoot?
    var mLayoutParams: AViewGroup.LayoutParams?
    /// Android id name (R.id.x); findViewById searches it.
    var viewId: String?
    private var mTag: Any?
    private var mKeyedTags: [Int: Any]?

    // MARK: - geometry (px)

    var mLeft = 0
    var mTop = 0
    var mRight = 0
    var mBottom = 0
    var mScrollX = 0
    var mScrollY = 0
    var mMeasuredWidth = 0
    var mMeasuredHeight = 0
    var mOldWidthMeasureSpec = Int(Int32.min)
    var mOldHeightMeasureSpec = Int(Int32.min)
    private var mMeasureCache: [Int: (Int, Int)]?
    var mMinWidth = 0
    var mMinHeight = 0

    // MARK: - private flags

    var mForceLayout = true
    var mLayoutRequired = false
    private var mMeasuredDimensionSet = false
    private var mMeasureNeededBeforeLayout = false
    var mIsLaidOut = false
    /// The view must redraw (Android PFLAG_INVALIDATED / dirty).
    var mDirty = true
    var mWillNotDraw = false
    var mBackgroundSizeChanged = true
    private var mForegroundBoundsChanged = true
    private var mDrawableStateDirty = true
    private var mDrawableState: [Int]?
    private var mWindowAttachCount = 0
    private var mLastNotifiedRtlDirection = -1

    // MARK: - flags with Android meaning

    private(set) var mVisibility = AView.VISIBLE
    private var mEnabled = true
    private var mClickable = false
    private var mLongClickable = false
    private var mContextClickable = false
    private var mFocusableValue = AView.FOCUSABLE_AUTO
    private var mFocusableInTouchMode = false
    private var mSelected = false
    private var mActivated = false
    private var mPressed = false
    private var mPrepressed = false
    private var mHapticFeedbackEnabled = true
    private var mSoundEffectsEnabled = true
    private var mFitsSystemWindows = false
    private var mImportantForAccessibility = AView.IMPORTANT_FOR_ACCESSIBILITY_AUTO
    private var mContentDescription: String?
    private var mKeepScreenOn = false
    private var mLayerType = AView.LAYER_TYPE_NONE

    // MARK: - transformation (px, degrees)

    private var mTranslationX: Float = 0
    private var mTranslationY: Float = 0
    private var mTranslationZ: Float = 0
    private var mElevation: Float = 0
    private var mScaleX: Float = 1
    private var mScaleY: Float = 1
    private var mRotation: Float = 0
    private var mRotationX: Float = 0
    private var mRotationY: Float = 0
    private var mPivotX: Float = 0
    private var mPivotY: Float = 0
    private var mPivotExplicitlySet = false
    private var mCameraDistance: Float = 0

    // MARK: - padding

    var mPaddingLeft = 0
    var mPaddingTop = 0
    var mPaddingRight = 0
    var mPaddingBottom = 0
    private var mUserPaddingStart = AView.UNDEFINED_PADDING
    private var mUserPaddingEnd = AView.UNDEFINED_PADDING
    private var mUserPaddingLeftInitial = 0
    private var mUserPaddingRightInitial = 0
    private var mLeftPaddingDefined = false
    private var mRightPaddingDefined = false
    private var mPaddingResolvedDirection = -1

    // MARK: - directions

    private var mRawLayoutDirection = AView.LAYOUT_DIRECTION_INHERIT
    private var mRawTextDirection = AView.TEXT_DIRECTION_INHERIT
    private var mRawTextAlignment = AView.TEXT_ALIGNMENT_INHERIT

    // MARK: - drawables

    private var mBackground: ADrawable?
    private var mBackgroundResource: ADrawableRes?
    private var mForeground: ADrawable?
    private var mForegroundGravity = 0x77 // Gravity.FILL
    private var mForegroundInsidePadding = true

    // MARK: - listeners

    private var mOnClickListener: ((AView) -> Void)?
    private var mOnLongClickListener: ((AView) -> Bool)?
    private var mOnTouchListener: ((AView, AMotionEvent) -> Bool)?
    private var mOnFocusChangeListener: ((AView, Bool) -> Void)?
    private var mOnScrollChangeListener: ((AView, Int, Int, Int, Int) -> Void)?
    var mOnApplyWindowInsetsListener: ((AView, AWindowInsetsCompat) -> AWindowInsetsCompat)?
    private var mOnLayoutChangeListeners: [AOnLayoutChangeListener]?
    private var mOnAttachStateChangeListeners: [AOnAttachStateChangeListener]?

    // MARK: - touch state

    private var mHasPerformedLongPress = false
    private var mIgnoreNextUpEvent = false
    private var mInContextButtonPress = false
    private var mPendingCheckForTap: ARunnable?
    private var mPendingCheckForTapX: Float = 0
    private var mPendingCheckForTapY: Float = 0
    private var mPendingCheckForLongPress: ARunnable?
    private var mLongPressOriginalWindowAttachCount = 0
    private var mLongPressOriginalPressedState = false
    private var mLongPressX: Float = 0
    private var mLongPressY: Float = 0
    private var mPerformClick: ARunnable?
    private var mUnsetPressedState: ARunnable?
    private lazy var mTouchSlop: Int = AViewConfiguration.get().scaledTouchSlop

    // MARK: - posting before attach (HandlerActionQueue)

    private var mRunQueue: [(ARunnable, Int64)]?
    private var mFloatingTreeObserver: AViewTreeObserver?

    // MARK: - misc

    private var mAnimator: AViewPropertyAnimator?
    private var mContentLayer: ContentLayer?
    private var mForegroundLayer: ContentLayer?
    private var mUsesLayerBackgroundColor = false
    private static var sNextGeneratedId = 1

    // MARK: - init

    init() {
        super.init(frame: .zero)
        isMultipleTouchEnabled = true
        isExclusiveTouch = false
        isOpaque = false
        autoresizesSubviews = false
        clipsToBounds = false
        backgroundColor = nil
        contentScaleFactor = AView.densityScale
    }

    override convenience init(frame: CGRect) {
        self.init()
    }

    required convenience init?(coder: NSCoder) {
        self.init()
    }

    // MARK: - identity, tags

    /// View.findViewById: depth-first in child order, the view itself first.
    func findViewById<T: AView>(_ id: String) -> T? {
        findViewTraversal(id) as? T
    }

    /// View.findViewWithTag.
    func findViewWithTag<T: AView>(_ tag: AnyHashable) -> T? {
        findViewWithTagTraversal(tag) as? T
    }

    func findViewTraversal(_ id: String) -> AView? {
        viewId == id ? self : nil
    }

    func findViewWithTagTraversal(_ tag: AnyHashable) -> AView? {
        if let t = mTag as? AnyHashable, t == tag { return self }
        return nil
    }

    func setTag(_ tag: Any?) { mTag = tag }
    func getTag() -> Any? { mTag }
    /// View.setTag(int key, Object tag) / getTag(int key).
    func setTag(_ key: Int, _ tag: Any?) {
        if mKeyedTags == nil { mKeyedTags = [:] }
        mKeyedTags![key] = tag
    }
    func getTag(_ key: Int) -> Any? { mKeyedTags?[key] ?? nil }

    static func generateViewId() -> Int {
        let result = sNextGeneratedId
        var newValue = result + 1
        if newValue > 0x00FF_FFFF { newValue = 1 } // Roll over to 1, not 0.
        sNextGeneratedId = newValue
        return result
    }

    // MARK: - tree accessors

    /// Android `parent as ViewGroup`.
    var parentGroup: AViewGroup? { mParent }
    func getParentGroup() -> AViewGroup? { mParent }

    /// View.getRootView: the topmost view of this hierarchy.
    var rootView: AView {
        var p: AView = self
        while let q = p.mParent { p = q }
        return p
    }

    var isAttachedToWindow: Bool { mAttachInfo != nil }
    var isLaidOut: Bool { mIsLaidOut }
    var isLayoutRequested: Bool { mForceLayout }
    var isInLayout: Bool { mAttachInfo?.root?.isInLayout ?? false }
    var viewRoot: AViewRoot? { mAttachInfo?.root }

    /// View.isShown: this view and all its ancestors are VISIBLE and the hierarchy is attached to a window root.
    var isShown: Bool {
        var current: AView = self
        while true {
            if current.mVisibility != AView.VISIBLE { return false }
            if let p = current.mParent {
                current = p
                continue
            }
            return current.mViewRootParent != nil
        }
    }

    var windowVisibility: Int { mAttachInfo?.windowVisibility ?? AView.GONE }
    func getWindowVisibility() -> Int { windowVisibility }
    func hasWindowFocus() -> Bool { mAttachInfo?.hasWindowFocus ?? false }

    // MARK: - geometry accessors

    var width: Int { mRight - mLeft }
    var height: Int { mBottom - mTop }
    var left: Int { mLeft }
    var top: Int { mTop }
    var right: Int { mRight }
    var bottom: Int { mBottom }
    func getWidth() -> Int { width }
    func getHeight() -> Int { height }

    var measuredWidth: Int { mMeasuredWidth & AView.MEASURED_SIZE_MASK }
    var measuredHeight: Int { mMeasuredHeight & AView.MEASURED_SIZE_MASK }
    var measuredWidthAndState: Int { mMeasuredWidth }
    var measuredHeightAndState: Int { mMeasuredHeight }
    /// getMeasuredState(): width state in the high byte, height state shifted down by 16.
    var measuredState: Int {
        (mMeasuredWidth & AView.MEASURED_STATE_MASK)
            | ((mMeasuredHeight >> AView.MEASURED_HEIGHT_STATE_SHIFT)
               & (AView.MEASURED_STATE_MASK >> AView.MEASURED_HEIGHT_STATE_SHIFT))
    }

    /// View.setLeft/setTop/setRight/setBottom (direct frame edits, used by animations and code).
    func setLeft(_ left: Int) { _ = setFrame(left, mTop, mRight, mBottom) }
    func setTop(_ top: Int) { _ = setFrame(mLeft, top, mRight, mBottom) }
    func setRight(_ right: Int) { _ = setFrame(mLeft, mTop, right, mBottom) }
    func setBottom(_ bottom: Int) { _ = setFrame(mLeft, mTop, mRight, bottom) }

    var x: Float {
        get { Float(mLeft) + mTranslationX }
        set { translationX = newValue - Float(mLeft) }
    }
    var y: Float {
        get { Float(mTop) + mTranslationY }
        set { translationY = newValue - Float(mTop) }
    }
    var z: Float {
        get { mElevation + mTranslationZ }
        set { translationZ = newValue - mElevation }
    }

    var translationX: Float {
        get { mTranslationX }
        set { if mTranslationX != newValue { mTranslationX = newValue; transformPropertyChanged() } }
    }
    var translationY: Float {
        get { mTranslationY }
        set { if mTranslationY != newValue { mTranslationY = newValue; transformPropertyChanged() } }
    }
    var translationZ: Float {
        get { mTranslationZ }
        set { if mTranslationZ != newValue { mTranslationZ = newValue; mParent?.childZChanged(self) } }
    }
    var elevation: Float {
        get { mElevation }
        set { if mElevation != newValue { mElevation = newValue; mParent?.childZChanged(self) } }
    }
    var scaleX: Float {
        get { mScaleX }
        set { if mScaleX != newValue { mScaleX = newValue; transformPropertyChanged() } }
    }
    var scaleY: Float {
        get { mScaleY }
        set { if mScaleY != newValue { mScaleY = newValue; transformPropertyChanged() } }
    }
    var rotation: Float {
        get { mRotation }
        set { if mRotation != newValue { mRotation = newValue; transformPropertyChanged() } }
    }
    /// rotationX/rotationY are stored; this port renders them as 0 (no 3D transforms are used by the app).
    var rotationX: Float {
        get { mRotationX }
        set { mRotationX = newValue }
    }
    var rotationY: Float {
        get { mRotationY }
        set { mRotationY = newValue }
    }
    var cameraDistance: Float {
        get { mCameraDistance }
        set { mCameraDistance = newValue }
    }
    /// getPivotX: the explicit pivot, or the center when none was set.
    var pivotX: Float {
        get { mPivotExplicitlySet ? mPivotX : Float(width) / 2 }
        set { mPivotX = newValue; mPivotExplicitlySet = true; transformPropertyChanged() }
    }
    var pivotY: Float {
        get { mPivotExplicitlySet ? mPivotY : Float(height) / 2 }
        set { mPivotY = newValue; mPivotExplicitlySet = true; transformPropertyChanged() }
    }
    var isPivotSet: Bool { mPivotExplicitlySet }
    func resetPivot() {
        if mPivotExplicitlySet {
            mPivotExplicitlySet = false
            transformPropertyChanged()
        }
    }

    /// View.hasIdentityMatrix.
    var hasIdentityMatrix: Bool {
        mTranslationX == 0 && mTranslationY == 0 && mScaleX == 1 && mScaleY == 1 && mRotation == 0
    }

    /// The view matrix (local -> parent, without left/top) in pixels: T(translation) * T(p) * R * S * T(-p).
    var matrixTransform: CGAffineTransform {
        if hasIdentityMatrix { return .identity }
        let px = Double(pivotX), py = Double(pivotY)
        let rad = Double(mRotation) * Double.pi / 180
        let c = cos(rad), s = sin(rad)
        let sx = Double(mScaleX), sy = Double(mScaleY)
        let a = c * sx, b = s * sx, cc = -s * sy, dd = c * sy
        let tx = Double(mTranslationX) + px - (a * px + cc * py)
        let ty = Double(mTranslationY) + py - (b * px + dd * py)
        return CGAffineTransform(a: CGFloat(a), b: CGFloat(b), c: CGFloat(cc), d: CGFloat(dd), tx: CGFloat(tx), ty: CGFloat(ty))
    }

    /// The inverse view matrix (parent-local -> view-local), used by the touch dispatch.
    var inverseMatrixTransform: CGAffineTransform {
        if hasIdentityMatrix { return .identity }
        return matrixTransform.inverted()
    }

    private func transformPropertyChanged() {
        updateUIKitTransform()
    }

    // MARK: - UIKit geometry

    /// Sets the UIKit bounds/center/transform from the Android frame. Called after setFrame and when the
    /// parent's child host moves.
    func updateUIKitFrame() {
        let d = AView.densityScale
        let w = CGFloat(mRight - mLeft) / d
        let h = CGFloat(mBottom - mTop) / d
        let origin = mParent?.childHostOriginPx ?? (x: 0, y: 0)
        let size = CGSize(width: w, height: h)
        if bounds.size != size || bounds.origin != .zero {
            bounds = CGRect(origin: .zero, size: size)
        }
        let c = CGPoint(x: CGFloat(mLeft - origin.x) / d + w / 2, y: CGFloat(mTop - origin.y) / d + h / 2)
        if center != c { center = c }
        updateUIKitTransform()
        let layerFrame = CGRect(origin: .zero, size: size)
        if let cl = mContentLayer, cl.frame != layerFrame { cl.frame = layerFrame }
        if let fl = mForegroundLayer, fl.frame != layerFrame { fl.frame = layerFrame }
        didUpdateUIKitFrame()
    }

    /// Hook for AViewGroup (child host frame) and AScrollView (content size).
    func didUpdateUIKitFrame() {}

    /// The parent's clipChildren (ViewGroup.setClipChildren): this view's drawing is clipped to its bounds. A leaf
    /// view masks its layer; AViewGroup clips its child host instead (see AViewGroup.applyParentClip).
    func applyParentClip(_ clip: Bool) {
        if clipsToBounds != clip { clipsToBounds = clip }
    }

    private func updateUIKitTransform() {
        let t: CGAffineTransform
        if hasIdentityMatrix {
            t = .identity
        } else {
            // UIKit applies the transform around the bounds center; fold the Android pivot into tx/ty:
            // t = translation + (I - RS) (pivot - center).
            let d = Double(AView.densityScale)
            let w = Double(width), h = Double(height)
            let vx = Double(pivotX) - w / 2, vy = Double(pivotY) - h / 2
            let rad = Double(mRotation) * Double.pi / 180
            let c = cos(rad), s = sin(rad)
            let sx = Double(mScaleX), sy = Double(mScaleY)
            let a = c * sx, b = s * sx, cc = -s * sy, dd = c * sy
            let ix = vx - (a * vx + cc * vy)
            let iy = vy - (b * vx + dd * vy)
            t = CGAffineTransform(a: CGFloat(a), b: CGFloat(b), c: CGFloat(cc), d: CGFloat(dd),
                                  tx: CGFloat((Double(mTranslationX) + ix) / d), ty: CGFloat((Double(mTranslationY) + iy) / d))
        }
        if transform != t { transform = t }
    }

    // MARK: - visibility

    var visibility: Int {
        get { mVisibility }
        set { setVisibility(newValue) }
    }
    func getVisibility() -> Int { mVisibility }

    /// View.setVisibility (setFlags VISIBILITY_MASK).
    func setVisibility(_ visibility: Int) {
        let newVisibility = visibility & AView.VISIBILITY_MASK
        let old = mVisibility
        if old == newVisibility { return }
        let changed = old ^ newVisibility
        mVisibility = newVisibility
        isHidden = newVisibility != AView.VISIBLE

        // Check if the GONE bit has changed
        if (changed & AView.GONE) != 0 {
            requestLayout()
            if newVisibility == AView.GONE {
                if hasFocus() { clearFocus() }
            }
        }
        // Check if the VISIBLE bit has changed
        if (changed & AView.INVISIBLE) != 0 {
            if newVisibility == AView.INVISIBLE && mParent != nil {
                if hasFocus() { clearFocus() }
            }
        }
        if let p = mParent {
            p.onChildVisibilityChanged(self, changed, newVisibility)
            p.invalidate()
        }
        if mAttachInfo != nil {
            dispatchVisibilityChanged(self, newVisibility)
            if mParent != nil && windowVisibility == AView.VISIBLE && (mParent?.isShown ?? true) {
                dispatchVisibilityAggregated(newVisibility == AView.VISIBLE)
            }
        }
        if newVisibility == AView.VISIBLE {
            // The display list of a view is discarded while it is hidden: it redraws when shown again.
            invalidate()
        }
        updateAccessibility()
        AView.updateKeepScreenOn()
    }

    func dispatchVisibilityChanged(_ changedView: AView, _ visibility: Int) {
        onVisibilityChanged(changedView, visibility)
    }

    /// Override point: the visibility of this view or of an ancestor changed.
    func onVisibilityChanged(_ changedView: AView, _ visibility: Int) {}

    func dispatchVisibilityAggregated(_ isVisible: Bool) {
        let thisVisible = mVisibility == AView.VISIBLE
        // If we're not visible but something is telling us we are, ignore it.
        if thisVisible || !isVisible {
            onVisibilityAggregated(isVisible)
        }
    }

    /// Override point (View.onVisibilityAggregated).
    func onVisibilityAggregated(_ isVisible: Bool) {}

    func dispatchWindowVisibilityChanged(_ visibility: Int) {
        onWindowVisibilityChanged(visibility)
    }

    /// Override point: the window (AViewRoot) visibility changed (GONE when the app is in the background).
    func onWindowVisibilityChanged(_ visibility: Int) {}

    // MARK: - enabled / clickable / focusable / selected / activated / pressed

    var isEnabled: Bool {
        get { mEnabled }
        set { setEnabled(newValue) }
    }

    /// View.setEnabled: refreshes the drawable state; clickable disabled views still consume touches.
    func setEnabled(_ enabled: Bool) {
        if enabled == mEnabled { return }
        mEnabled = enabled
        if !enabled && hasFocus() { clearFocus() }
        refreshDrawableState()
        invalidate()
        if !enabled {
            cancelPendingInputEvents()
        }
        updateAccessibility()
    }

    /// View.cancelPendingInputEvents (removes the pending click).
    func cancelPendingInputEvents() {
        removePerformClickCallback()
    }

    var isClickable: Bool {
        get { mClickable }
        set { setClickable(newValue) }
    }
    func setClickable(_ clickable: Bool) {
        mClickable = clickable
        updateAccessibility()
    }

    var isLongClickable: Bool {
        get { mLongClickable }
        set { setLongClickable(newValue) }
    }
    func setLongClickable(_ longClickable: Bool) {
        mLongClickable = longClickable
    }

    var isContextClickable: Bool {
        get { mContextClickable }
        set { mContextClickable = newValue }
    }

    /// isFocusable: FOCUSABLE, or FOCUSABLE_AUTO resolved from clickability (Android setFlags).
    var isFocusable: Bool {
        get { mFocusableValue == AView.FOCUSABLE || (mFocusableValue == AView.FOCUSABLE_AUTO && (mClickable || mLongClickable)) }
        set { setFocusable(newValue) }
    }
    func setFocusable(_ focusable: Bool) {
        mFocusableValue = focusable ? AView.FOCUSABLE : AView.NOT_FOCUSABLE
        if !focusable { mFocusableInTouchMode = false }
    }
    func setFocusable(_ focusable: Int) {
        mFocusableValue = focusable
        if focusable == AView.NOT_FOCUSABLE { mFocusableInTouchMode = false }
    }
    var focusable: Int {
        get { mFocusableValue }
        set { setFocusable(newValue) }
    }
    var isFocusableInTouchMode: Bool {
        get { mFocusableInTouchMode }
        set {
            mFocusableInTouchMode = newValue
            if newValue { mFocusableValue = AView.FOCUSABLE }
        }
    }

    var isSelected: Bool {
        get { mSelected }
        set { setSelected(newValue) }
    }
    func setSelected(_ selected: Bool) {
        if mSelected != selected {
            mSelected = selected
            if !selected { resetPressedState() }
            invalidate()
            refreshDrawableState()
            dispatchSetSelected(selected)
            updateAccessibility()
        }
    }
    func dispatchSetSelected(_ selected: Bool) {}

    var isActivated: Bool {
        get { mActivated }
        set { setActivated(newValue) }
    }
    func setActivated(_ activated: Bool) {
        if mActivated != activated {
            mActivated = activated
            invalidate()
            refreshDrawableState()
            dispatchSetActivated(activated)
        }
    }
    func dispatchSetActivated(_ activated: Bool) {}

    var isPressed: Bool {
        get { mPressed }
        set { setPressed(newValue) }
    }
    /// View.setPressed: refreshes the drawable state and dispatches to non-clickable children.
    func setPressed(_ pressed: Bool) {
        let needsRefresh = pressed != mPressed
        mPressed = pressed
        if needsRefresh {
            refreshDrawableState()
        }
        dispatchSetPressed(pressed)
    }
    func dispatchSetPressed(_ pressed: Bool) {}

    private func resetPressedState() {
        if !mEnabled { return }
        if isPressed {
            setPressed(false)
            if !mHasPerformedLongPress {
                removeLongPressCallback()
            }
        }
    }

    var isHapticFeedbackEnabled: Bool {
        get { mHapticFeedbackEnabled }
        set { mHapticFeedbackEnabled = newValue }
    }
    var isSoundEffectsEnabled: Bool {
        get { mSoundEffectsEnabled }
        set { mSoundEffectsEnabled = newValue }
    }
    var fitsSystemWindows: Bool {
        get { mFitsSystemWindows }
        set { mFitsSystemWindows = newValue }
    }

    var keepScreenOn: Bool {
        get { mKeepScreenOn }
        set {
            if mKeepScreenOn != newValue {
                mKeepScreenOn = newValue
                if newValue { AView.sAnyKeepScreenOnRequested = true }
                AView.updateKeepScreenOn()
            }
        }
    }

    // MARK: - drawable state

    /// View.getDrawableState(): cached until refreshDrawableState().
    var drawableState: [Int] {
        if let s = mDrawableState, !mDrawableStateDirty { return s }
        let s = onCreateDrawableState(0)
        mDrawableState = s
        mDrawableStateDirty = false
        return s
    }
    func getDrawableState() -> [Int] { drawableState }

    /// Override point (View.onCreateDrawableState). Order as AOSP VIEW_STATE_IDS.
    func onCreateDrawableState(_ extraSpace: Int) -> [Int] {
        var s: [Int] = []
        if mAttachInfo?.hasWindowFocus ?? false { s.append(AView.STATE_WINDOW_FOCUSED) }
        if mSelected { s.append(AView.STATE_SELECTED) }
        if isFocusedSelf { s.append(AView.STATE_FOCUSED) }
        if mEnabled { s.append(AView.STATE_ENABLED) }
        if mPressed { s.append(AView.STATE_PRESSED) }
        if mActivated { s.append(AView.STATE_ACTIVATED) }
        return s
    }

    /// View.mergeDrawableStates (returns the merged array).
    static func mergeDrawableStates(_ baseState: [Int], _ additionalState: [Int]) -> [Int] {
        baseState + additionalState
    }

    func refreshDrawableState() {
        mDrawableStateDirty = true
        drawableStateChanged()
        mParent?.childDrawableStateChanged(self)
    }

    /// Override point (View.drawableStateChanged): applies the state to the background and foreground.
    func drawableStateChanged() {
        let state = drawableState
        var changed = false
        if let bg = mBackground, bg.isStateful {
            changed = bg.setState(state) || changed
        }
        if let fg = mForeground, fg.isStateful {
            changed = fg.setState(state) || changed
        }
        if changed {
            invalidate()
        }
    }

    /// Drawable.Callback.invalidateDrawable.
    func invalidateDrawable(_ drawable: ADrawable) {
        if verifyDrawable(drawable) {
            invalidate()
        }
    }

    /// Override point (View.verifyDrawable).
    func verifyDrawable(_ who: ADrawable) -> Bool {
        who === mBackground || who === mForeground
    }

    // MARK: - background / foreground

    var background: ADrawable? {
        get { mBackground }
        set { setBackgroundDrawable(newValue) }
    }
    func getBackground() -> ADrawable? { mBackground }
    func setBackground(_ background: ADrawable?) { setBackgroundDrawable(background) }

    /// View.setBackgroundDrawable.
    func setBackgroundDrawable(_ background: ADrawable?) {
        if background === mBackground { return }
        var requestLayoutNeeded = false
        mBackgroundResource = nil

        if let old = mBackground {
            old.callbackView = nil
        }

        if let bg = background {
            let padding = ARect()
            if bg.getPadding(padding) {
                resetResolvedPaddingInternal()
                mUserPaddingLeftInitial = padding.left
                mUserPaddingRightInitial = padding.right
                internalSetPadding(padding.left, padding.top, padding.right, padding.bottom)
                mLeftPaddingDefined = false
                mRightPaddingDefined = false
            }
            // Compare the minimum sizes of the old Drawable and the new. If there isn't an old or if it has a
            // different minimum size, we should layout again.
            if mBackground == nil
                || AView.drawableMinimumHeight(mBackground!) != AView.drawableMinimumHeight(bg)
                || AView.drawableMinimumWidth(mBackground!) != AView.drawableMinimumWidth(bg) {
                requestLayoutNeeded = true
            }
            mBackground = bg
            if bg.isStateful {
                _ = bg.setState(drawableState)
            }
            // Set callback last, since the view may still be initializing.
            bg.callbackView = self
            if mWillNotDraw {
                requestLayoutNeeded = true
            }
        } else {
            mBackground = nil
            requestLayoutNeeded = true
        }
        if requestLayoutNeeded {
            requestLayout()
        }
        mBackgroundSizeChanged = true
        updateDrawingConfiguration()
        invalidate()
    }

    /// View.setBackgroundColor: reuses an existing ColorDrawable background.
    func setBackgroundColor(_ color: Int) {
        if let cd = mBackground as? AColorDrawable {
            cd.mutate()
            cd.color = color
            mBackgroundResource = nil
            updateDrawingConfiguration()
            invalidate()
        } else {
            setBackground(AColorDrawable(color))
        }
    }

    /// View.setBackgroundResource (an empty name removes the background, like resid 0).
    func setBackgroundResource(_ resid: ADrawableRes) {
        if !resid.isEmpty && resid == mBackgroundResource { return }
        var d: ADrawable? = nil
        if !resid.isEmpty {
            d = ContextCompat_getDrawable(resid)
        }
        setBackground(d)
        mBackgroundResource = resid.isEmpty ? nil : resid
    }

    var foreground: ADrawable? {
        get { mForeground }
        set { setForeground(newValue) }
    }
    func getForeground() -> ADrawable? { mForeground }

    /// View.setForeground: drawn above the children.
    func setForeground(_ foreground: ADrawable?) {
        if mForeground === foreground { return }
        if let old = mForeground {
            old.callbackView = nil
        }
        mForeground = foreground
        if let fg = foreground {
            if fg.isStateful {
                _ = fg.setState(drawableState)
            }
            fg.callbackView = self
        }
        mForegroundBoundsChanged = true
        requestLayout()
        updateDrawingConfiguration()
        invalidate()
    }

    var foregroundGravity: Int {
        get { mForegroundGravity }
        set { setForegroundGravity(newValue) }
    }

    /// View.isForegroundInsidePadding (android:foregroundInsidePadding, true by default; FrameLayout reads it).
    var isForegroundInsidePadding: Bool {
        get { mForegroundInsidePadding }
        set {
            if mForegroundInsidePadding != newValue {
                mForegroundInsidePadding = newValue
                mForegroundBoundsChanged = true
                requestLayout()
            }
        }
    }
    func setForegroundGravity(_ gravity: Int) {
        var g = gravity
        if mForegroundGravity != g {
            if (g & AGravity.RELATIVE_HORIZONTAL_GRAVITY_MASK) == 0 { g |= AGravity.START }
            if (g & AGravity.VERTICAL_GRAVITY_MASK) == 0 { g |= AGravity.TOP }
            mForegroundGravity = g
            mForegroundBoundsChanged = true
            requestLayout()
        }
    }

    static func drawableMinimumWidth(_ d: ADrawable) -> Int {
        let w = d.intrinsicWidth
        return w > 0 ? w : 0
    }

    static func drawableMinimumHeight(_ d: ADrawable) -> Int {
        let h = d.intrinsicHeight
        return h > 0 ? h : 0
    }

    // MARK: - padding

    var paddingLeft: Int { ensurePaddingResolved(); return mPaddingLeft }
    var paddingTop: Int { mPaddingTop }
    var paddingRight: Int { ensurePaddingResolved(); return mPaddingRight }
    var paddingBottom: Int { mPaddingBottom }
    var paddingStart: Int { ensurePaddingResolved(); return isLayoutRtl ? mPaddingRight : mPaddingLeft }
    var paddingEnd: Int { ensurePaddingResolved(); return isLayoutRtl ? mPaddingLeft : mPaddingRight }
    var isPaddingRelative: Bool { mUserPaddingStart != AView.UNDEFINED_PADDING || mUserPaddingEnd != AView.UNDEFINED_PADDING }

    /// View.setPadding(left, top, right, bottom): clears relative padding.
    func setPadding(_ left: Int, _ top: Int, _ right: Int, _ bottom: Int) {
        resetResolvedPaddingInternal()
        mUserPaddingStart = AView.UNDEFINED_PADDING
        mUserPaddingEnd = AView.UNDEFINED_PADDING
        mUserPaddingLeftInitial = left
        mUserPaddingRightInitial = right
        mLeftPaddingDefined = true
        mRightPaddingDefined = true
        internalSetPadding(left, top, right, bottom)
    }

    /// androidx core-ktx `setPadding(size)`.
    func setPadding(_ size: Int) { setPadding(size, size, size, size) }

    /// View.setPaddingRelative(start, top, end, bottom), resolved with the current layout direction.
    func setPaddingRelative(_ start: Int, _ top: Int, _ end: Int, _ bottom: Int) {
        resetResolvedPaddingInternal()
        mUserPaddingStart = start
        mUserPaddingEnd = end
        mLeftPaddingDefined = true
        mRightPaddingDefined = true
        let dir = layoutDirection
        mPaddingResolvedDirection = dir
        if dir == AView.LAYOUT_DIRECTION_RTL {
            mUserPaddingLeftInitial = end
            mUserPaddingRightInitial = start
            internalSetPadding(end, top, start, bottom)
        } else {
            mUserPaddingLeftInitial = start
            mUserPaddingRightInitial = end
            internalSetPadding(start, top, end, bottom)
        }
    }

    /// View.internalSetPadding: requests a layout when any side changed.
    func internalSetPadding(_ left: Int, _ top: Int, _ right: Int, _ bottom: Int) {
        var changed = false
        if mPaddingLeft != left { changed = true; mPaddingLeft = left }
        if mPaddingTop != top { changed = true; mPaddingTop = top }
        if mPaddingRight != right { changed = true; mPaddingRight = right }
        if mPaddingBottom != bottom { changed = true; mPaddingBottom = bottom }
        if changed {
            paddingDidChange()
            requestLayout()
        }
    }

    /// Hook for AViewGroup (clip-to-padding child host).
    func paddingDidChange() {}

    private func resetResolvedPaddingInternal() {
        mPaddingResolvedDirection = -1
    }

    /// Layouts read mPaddingLeft/mPaddingRight directly (as the AOSP layouts read the fields): they call this first
    /// so relative (start/end) padding is resolved for the current layout direction (View.resolvePadding).
    func ensureResolvedPadding() {
        ensurePaddingResolved()
    }

    /// Relative padding depends on the resolved layout direction, which can change when the view is attached
    /// or an ancestor's direction changes: re-resolve silently (Android resolvePadding) when it differs.
    private func ensurePaddingResolved() {
        guard isPaddingRelative else { return }
        let dir = layoutDirection
        if dir == mPaddingResolvedDirection { return }
        mPaddingResolvedDirection = dir
        var left = mUserPaddingLeftInitial, right = mUserPaddingRightInitial
        if dir == AView.LAYOUT_DIRECTION_RTL {
            right = mUserPaddingStart != AView.UNDEFINED_PADDING ? mUserPaddingStart : mUserPaddingRightInitial
            left = mUserPaddingEnd != AView.UNDEFINED_PADDING ? mUserPaddingEnd : mUserPaddingLeftInitial
        } else {
            left = mUserPaddingStart != AView.UNDEFINED_PADDING ? mUserPaddingStart : mUserPaddingLeftInitial
            right = mUserPaddingEnd != AView.UNDEFINED_PADDING ? mUserPaddingEnd : mUserPaddingRightInitial
        }
        if mPaddingLeft != left || mPaddingRight != right {
            mPaddingLeft = left
            mPaddingRight = right
            paddingDidChange()
        }
    }

    // MARK: - layout direction, text direction, text alignment

    /// The cached result of the locale rule (he/iw/ar/fa/ur and other RTL-script languages are RTL).
    private static var sLocaleIsRtl: Bool?
    private static var sLocaleObserver: NSObjectProtocol?

    static var localeLayoutDirection: Int {
        if let v = sLocaleIsRtl { return v ? LAYOUT_DIRECTION_RTL : LAYOUT_DIRECTION_LTR }
        if sLocaleObserver == nil {
            sLocaleObserver = NotificationCenter.default.addObserver(
                forName: NSLocale.currentLocaleDidChangeNotification, object: nil, queue: nil) { _ in
                    AView.sLocaleIsRtl = nil
                }
        }
        let language = ALocale.getDefault().language.lowercased()
        let rtl = AView.isRtlLanguage(language)
        sLocaleIsRtl = rtl
        return rtl ? LAYOUT_DIRECTION_RTL : LAYOUT_DIRECTION_LTR
    }

    /// TextUtils.getLayoutDirectionFromLocale: RTL for the languages whose likely script is Hebrew, Arabic or Thaana
    /// (he/iw, ar, fa, ur and the other Arabic-script languages, yi, dv), as ICU resolves them on Android.
    static func isRtlLanguage(_ language: String) -> Bool {
        ["he", "iw", "ar", "fa", "ur", "yi", "ji", "ps", "sd", "ug", "dv", "ckb", "ks"].contains(language)
    }

    /// getLayoutDirection() (resolved LTR/RTL) / setLayoutDirection(raw).
    var layoutDirection: Int {
        get { resolvedLayoutDirection() }
        set { setLayoutDirection(newValue) }
    }
    var rawLayoutDirection: Int { mRawLayoutDirection }

    func resolvedLayoutDirection() -> Int {
        switch mRawLayoutDirection {
        case AView.LAYOUT_DIRECTION_RTL:
            return AView.LAYOUT_DIRECTION_RTL
        case AView.LAYOUT_DIRECTION_LTR:
            return AView.LAYOUT_DIRECTION_LTR
        case AView.LAYOUT_DIRECTION_LOCALE:
            return AView.localeLayoutDirection
        default:
            if let p = mParent { return p.resolvedLayoutDirection() }
            // A window root inherits the configuration direction (the locale's); a detached root resolves to LTR.
            if mViewRootParent != nil { return AView.localeLayoutDirection }
            return AView.LAYOUT_DIRECTION_LTR
        }
    }

    var isLayoutRtl: Bool { resolvedLayoutDirection() == AView.LAYOUT_DIRECTION_RTL }
    var isLayoutDirectionInherited: Bool { mRawLayoutDirection == AView.LAYOUT_DIRECTION_INHERIT }

    func setLayoutDirection(_ layoutDirection: Int) {
        if mRawLayoutDirection != layoutDirection {
            mRawLayoutDirection = layoutDirection
            rtlPropertiesChanged()
            requestLayout()
            invalidate()
        }
    }

    var textDirection: Int {
        get { resolvedTextDirection() }
        set { setTextDirection(newValue) }
    }
    var rawTextDirection: Int { mRawTextDirection }

    func resolvedTextDirection() -> Int {
        if mRawTextDirection != AView.TEXT_DIRECTION_INHERIT { return mRawTextDirection }
        if let p = mParent {
            let parentResolved = p.resolvedTextDirection()
            switch parentResolved {
            case AView.TEXT_DIRECTION_FIRST_STRONG, AView.TEXT_DIRECTION_ANY_RTL, AView.TEXT_DIRECTION_LTR,
                 AView.TEXT_DIRECTION_RTL, AView.TEXT_DIRECTION_LOCALE, AView.TEXT_DIRECTION_FIRST_STRONG_LTR,
                 AView.TEXT_DIRECTION_FIRST_STRONG_RTL:
                return parentResolved
            default:
                return AView.TEXT_DIRECTION_FIRST_STRONG
            }
        }
        return AView.TEXT_DIRECTION_FIRST_STRONG
    }

    func setTextDirection(_ textDirection: Int) {
        if mRawTextDirection != textDirection {
            mRawTextDirection = textDirection
            rtlPropertiesChanged()
            requestLayout()
            invalidate()
        }
    }

    var textAlignment: Int {
        get { resolvedTextAlignment() }
        set { setTextAlignment(newValue) }
    }
    var rawTextAlignment: Int { mRawTextAlignment }

    func resolvedTextAlignment() -> Int {
        if mRawTextAlignment != AView.TEXT_ALIGNMENT_INHERIT { return mRawTextAlignment }
        if let p = mParent {
            let parentResolved = p.resolvedTextAlignment()
            switch parentResolved {
            case AView.TEXT_ALIGNMENT_GRAVITY, AView.TEXT_ALIGNMENT_TEXT_START, AView.TEXT_ALIGNMENT_TEXT_END,
                 AView.TEXT_ALIGNMENT_CENTER, AView.TEXT_ALIGNMENT_VIEW_START, AView.TEXT_ALIGNMENT_VIEW_END:
                return parentResolved
            default:
                return AView.TEXT_ALIGNMENT_GRAVITY
            }
        }
        return AView.TEXT_ALIGNMENT_GRAVITY
    }

    func setTextAlignment(_ textAlignment: Int) {
        if mRawTextAlignment != textAlignment {
            mRawTextAlignment = textAlignment
            rtlPropertiesChanged()
            requestLayout()
            invalidate()
        }
    }

    /// Override point (View.onRtlPropertiesChanged): called with the resolved layout direction when it or the
    /// text direction/alignment may have changed.
    func onRtlPropertiesChanged(_ layoutDirection: Int) {}

    /// Re-resolution after a direction change: this view and every inheriting descendant re-measure and redraw.
    func rtlPropertiesChanged() {
        mLastNotifiedRtlDirection = -1
        resolveRtlPropertiesIfNeeded()
        forceLayout()
        invalidate()
    }

    /// Called at measure time: notifies onRtlPropertiesChanged once per resolved direction and re-resolves the
    /// layout params margins.
    func resolveRtlPropertiesIfNeeded() {
        let dir = resolvedLayoutDirection()
        if dir != mLastNotifiedRtlDirection {
            mLastNotifiedRtlDirection = dir
            ensurePaddingResolved()
            onRtlPropertiesChanged(dir)
        }
        mLayoutParams?.resolveLayoutDirection(dir)
    }

    // MARK: - layout params

    var layoutParams: AViewGroup.LayoutParams? {
        get { mLayoutParams }
        set { setLayoutParams(newValue) }
    }
    func getLayoutParams() -> AViewGroup.LayoutParams? { mLayoutParams }

    /// View.setLayoutParams: resolves the margins, notifies the parent and requests a layout.
    func setLayoutParams(_ params: AViewGroup.LayoutParams?) {
        guard let params = params else { preconditionFailure("Layout parameters cannot be null") }
        mLayoutParams = params
        params.resolveLayoutDirection(resolvedLayoutDirection())
        mParent?.onSetLayoutParams(self, params)
        requestLayout()
    }

    // MARK: - minimum sizes

    var minimumWidth: Int {
        get { mMinWidth }
        set { mMinWidth = newValue; requestLayout() }
    }
    var minimumHeight: Int {
        get { mMinHeight }
        set { mMinHeight = newValue; requestLayout() }
    }
    func setMinimumWidth(_ minWidth: Int) { minimumWidth = minWidth }
    func setMinimumHeight(_ minHeight: Int) { minimumHeight = minHeight }

    func getSuggestedMinimumWidth() -> Int {
        if let bg = mBackground { return max(mMinWidth, AView.drawableMinimumWidth(bg)) }
        return mMinWidth
    }
    func getSuggestedMinimumHeight() -> Int {
        if let bg = mBackground { return max(mMinHeight, AView.drawableMinimumHeight(bg)) }
        return mMinHeight
    }

    // MARK: - measure

    /// View.measure: caches by spec, calls onMeasure when forced or the spec changed.
    func measure(_ widthMeasureSpec: Int, _ heightMeasureSpec: Int) {
        let key = (widthMeasureSpec << 32) | (heightMeasureSpec & 0xffff_ffff)
        if mMeasureCache == nil { mMeasureCache = [:] }

        let forceLayout = mForceLayout

        // Optimize layout by avoiding an extra EXACTLY pass when the view is already measured as the correct size.
        let specChanged = widthMeasureSpec != mOldWidthMeasureSpec || heightMeasureSpec != mOldHeightMeasureSpec
        let isSpecExactly = AMeasureSpec.getMode(widthMeasureSpec) == AMeasureSpec.EXACTLY
            && AMeasureSpec.getMode(heightMeasureSpec) == AMeasureSpec.EXACTLY
        let matchesSpecSize = measuredWidth == AMeasureSpec.getSize(widthMeasureSpec)
            && measuredHeight == AMeasureSpec.getSize(heightMeasureSpec)
        let needsLayout = specChanged && (!isSpecExactly || !matchesSpecSize)

        if forceLayout || needsLayout {
            // first clears the measured dimension flag
            mMeasuredDimensionSet = false

            resolveRtlPropertiesIfNeeded()

            let cached: (Int, Int)? = forceLayout ? nil : mMeasureCache![key]
            if let value = cached {
                setMeasuredDimensionRaw(value.0, value.1)
                mMeasureNeededBeforeLayout = true
            } else {
                // measure ourselves, this should set the measured dimension flag back
                onMeasure(widthMeasureSpec, heightMeasureSpec)
                mMeasureNeededBeforeLayout = false
            }

            // flag not set, setMeasuredDimension() was not invoked, we raise an exception to warn the developer
            precondition(mMeasuredDimensionSet,
                         "View with id \(viewId ?? "-1"): \(type(of: self))#onMeasure() did not set the measured dimension by calling setMeasuredDimension()")

            mLayoutRequired = true
        }

        mOldWidthMeasureSpec = widthMeasureSpec
        mOldHeightMeasureSpec = heightMeasureSpec

        mMeasureCache![key] = (mMeasuredWidth, mMeasuredHeight)
    }

    /// Override point (View.onMeasure): the default size from the suggested minimum and the spec.
    func onMeasure(_ widthMeasureSpec: Int, _ heightMeasureSpec: Int) {
        setMeasuredDimension(AView.getDefaultSize(getSuggestedMinimumWidth(), widthMeasureSpec),
                             AView.getDefaultSize(getSuggestedMinimumHeight(), heightMeasureSpec))
    }

    func setMeasuredDimension(_ measuredWidth: Int, _ measuredHeight: Int) {
        setMeasuredDimensionRaw(measuredWidth, measuredHeight)
    }

    private func setMeasuredDimensionRaw(_ measuredWidth: Int, _ measuredHeight: Int) {
        mMeasuredWidth = measuredWidth
        mMeasuredHeight = measuredHeight
        mMeasuredDimensionSet = true
    }

    static func getDefaultSize(_ size: Int, _ measureSpec: Int) -> Int {
        var result = size
        let specMode = AMeasureSpec.getMode(measureSpec)
        let specSize = AMeasureSpec.getSize(measureSpec)
        switch specMode {
        case AMeasureSpec.UNSPECIFIED:
            result = size
        case AMeasureSpec.AT_MOST, AMeasureSpec.EXACTLY:
            result = specSize
        default:
            break
        }
        return result
    }

    static func resolveSize(_ size: Int, _ measureSpec: Int) -> Int {
        resolveSizeAndState(size, measureSpec, 0) & MEASURED_SIZE_MASK
    }

    static func resolveSizeAndState(_ size: Int, _ measureSpec: Int, _ childMeasuredState: Int) -> Int {
        let specMode = AMeasureSpec.getMode(measureSpec)
        let specSize = AMeasureSpec.getSize(measureSpec)
        let result: Int
        switch specMode {
        case AMeasureSpec.AT_MOST:
            if specSize < size {
                result = specSize | MEASURED_STATE_TOO_SMALL
            } else {
                result = size
            }
        case AMeasureSpec.EXACTLY:
            result = specSize
        default:
            result = size
        }
        return result | (childMeasuredState & MEASURED_STATE_MASK)
    }

    static func combineMeasuredStates(_ curState: Int, _ newState: Int) -> Int {
        curState | newState
    }

    /// View.getBaseline: -1 = no baseline (TextView overrides).
    func getBaseline() -> Int { -1 }
    var baseline: Int { getBaseline() }

    // MARK: - layout

    /// View.layout: sets the frame, then onLayout when changed or a layout was required.
    func layout(_ l: Int, _ t: Int, _ r: Int, _ b: Int) {
        if mMeasureNeededBeforeLayout {
            onMeasure(mOldWidthMeasureSpec, mOldHeightMeasureSpec)
            mMeasureNeededBeforeLayout = false
        }

        let oldL = mLeft
        let oldT = mTop
        let oldB = mBottom
        let oldR = mRight

        let changed = setFrame(l, t, r, b)

        if changed || mLayoutRequired {
            onLayout(changed, l, t, r, b)
            mLayoutRequired = false

            if let listeners = mOnLayoutChangeListeners, !listeners.isEmpty {
                let listenersCopy = listeners
                for listener in listenersCopy {
                    listener.onLayoutChange(self, l, t, r, b, oldL, oldT, oldR, oldB)
                }
            }
        }

        mForceLayout = false
        mIsLaidOut = true
    }

    /// Override point (View.onLayout).
    func onLayout(_ changed: Bool, _ left: Int, _ top: Int, _ right: Int, _ bottom: Int) {}

    /// View.setFrame: assigns the edges; onSizeChanged when the size changed. Returns whether anything changed.
    @discardableResult
    func setFrame(_ left: Int, _ top: Int, _ right: Int, _ bottom: Int) -> Bool {
        var changed = false
        if mLeft != left || mRight != right || mTop != top || mBottom != bottom {
            changed = true
            let oldWidth = mRight - mLeft
            let oldHeight = mBottom - mTop
            let newWidth = right - left
            let newHeight = bottom - top
            let sizeChanged = newWidth != oldWidth || newHeight != oldHeight

            mLeft = left
            mTop = top
            mRight = right
            mBottom = bottom
            updateUIKitFrame()

            if sizeChanged {
                onSizeChanged(newWidth, newHeight, oldWidth, oldHeight)
                if mVisibility == AView.VISIBLE {
                    invalidate()
                }
            }
            mBackgroundSizeChanged = true
            mForegroundBoundsChanged = true
        }
        return changed
    }

    /// Override point (View.onSizeChanged).
    func onSizeChanged(_ w: Int, _ h: Int, _ oldw: Int, _ oldh: Int) {}

    /// View.offsetLeftAndRight / offsetTopAndBottom.
    func offsetLeftAndRight(_ offset: Int) {
        if offset != 0 {
            mLeft += offset
            mRight += offset
            updateUIKitFrame()
        }
    }
    func offsetTopAndBottom(_ offset: Int) {
        if offset != 0 {
            mTop += offset
            mBottom += offset
            updateUIKitFrame()
        }
    }

    /// View.requestLayout: marks this view and its ancestors for a new measure/layout pass.
    func requestLayout() {
        mMeasureCache?.removeAll()

        if let ai = mAttachInfo, ai.viewRequestingLayout == nil {
            // Only trigger request-during-layout logic if this is the view requesting it, not the views in its
            // parent hierarchy
            if let root = ai.root, root.isInLayout {
                if !root.requestLayoutDuringLayout(self) {
                    return
                }
            }
            ai.viewRequestingLayout = self
        }

        mForceLayout = true
        mDirty = true

        if let p = mParent {
            if !p.isLayoutRequested {
                p.requestLayout()
            }
        } else if let root = mViewRootParent {
            if !root.isLayoutRequested {
                root.requestLayout()
            }
        }
        if let ai = mAttachInfo, ai.viewRequestingLayout === self {
            ai.viewRequestingLayout = nil
        }
    }

    /// View.forceLayout: forces a layout of this view on the next pass, without asking the parents.
    func forceLayout() {
        mMeasureCache?.removeAll()
        mForceLayout = true
        mDirty = true
    }

    func addOnLayoutChangeListener(_ listener: AOnLayoutChangeListener) {
        if mOnLayoutChangeListeners == nil { mOnLayoutChangeListeners = [] }
        if !mOnLayoutChangeListeners!.contains(where: { $0 === listener }) {
            mOnLayoutChangeListeners!.append(listener)
        }
    }

    func removeOnLayoutChangeListener(_ listener: AOnLayoutChangeListener) {
        mOnLayoutChangeListeners?.removeAll(where: { $0 === listener })
    }

    func addOnAttachStateChangeListener(_ listener: AOnAttachStateChangeListener) {
        if mOnAttachStateChangeListeners == nil { mOnAttachStateChangeListeners = [] }
        mOnAttachStateChangeListeners!.append(listener)
    }

    func removeOnAttachStateChangeListener(_ listener: AOnAttachStateChangeListener) {
        if let i = mOnAttachStateChangeListeners?.firstIndex(where: { $0 === listener }) {
            mOnAttachStateChangeListeners!.remove(at: i)
        }
    }

    // MARK: - tree observer

    var viewTreeObserver: AViewTreeObserver {
        if let ai = mAttachInfo { return ai.treeObserver }
        if mFloatingTreeObserver == nil { mFloatingTreeObserver = AViewTreeObserver() }
        return mFloatingTreeObserver!
    }
    func getViewTreeObserver() -> AViewTreeObserver { viewTreeObserver }

    // MARK: - attach / detach

    /// View.dispatchAttachedToWindow.
    func dispatchAttachedToWindow(_ info: AttachInfo, _ visibility: Int) {
        mAttachInfo = info
        if let r = info.root { mTouchRoot = r }
        mWindowAttachCount += 1
        // We will need to evaluate the drawable state at least once.
        mDrawableStateDirty = true
        if let floating = mFloatingTreeObserver {
            info.treeObserver.merge(floating)
            mFloatingTreeObserver = nil
        }
        // Transfer all pending runnables.
        if let queue = mRunQueue {
            mRunQueue = nil
            for (action, delay) in queue {
                info.handler.postDelayed(action, delay)
            }
        }
        onAttachedToWindow()

        if let listeners = mOnAttachStateChangeListeners, !listeners.isEmpty {
            let copy = listeners
            for listener in copy {
                listener.onViewAttachedToWindow(self)
            }
        }

        let vis = info.windowVisibility
        if vis != AView.GONE {
            onWindowVisibilityChanged(vis)
            if isShown {
                onVisibilityAggregated(vis == AView.VISIBLE)
            }
        }

        // Send onVisibilityChanged directly instead of dispatchVisibilityChanged.
        onVisibilityChanged(self, visibility)

        if mDrawableStateDirty {
            // If nobody has evaluated the drawable state yet, then do it now.
            refreshDrawableState()
        }
        mDirty = true
        updateDrawingConfiguration()
        info.root?.scheduleDraw(self)
        AView.updateKeepScreenOn()
    }

    /// Override point (View.onAttachedToWindow). Subclasses must call super.
    func onAttachedToWindow() {
        mIsLaidOut = false
    }

    /// View.dispatchDetachedFromWindow.
    func dispatchDetachedFromWindow() {
        if let info = mAttachInfo {
            let vis = info.windowVisibility
            if vis != AView.GONE {
                onWindowVisibilityChanged(AView.GONE)
                if isShown {
                    // Invoking onVisibilityAggregated directly here since the subtree will also receive
                    // detached from window
                    onVisibilityAggregated(false)
                }
            }
        }

        onDetachedFromWindow()
        onDetachedFromWindowInternal()

        if let listeners = mOnAttachStateChangeListeners, !listeners.isEmpty {
            let copy = listeners
            for listener in copy {
                listener.onViewDetachedFromWindow(self)
            }
        }

        mAttachInfo = nil
        AView.updateKeepScreenOn()
    }

    /// Override point (View.onDetachedFromWindow). Subclasses must call super.
    func onDetachedFromWindow() {}

    private func onDetachedFromWindowInternal() {
        mIsLaidOut = false
        removeUnsetPressCallback()
        removeLongPressCallback()
        removePerformClickCallback()
        removeTapCallback()
        if let ai = mAttachInfo {
            if ai.focusedView === self { ai.focusedView = nil }
            ai.root?.cancelDraw(self)
        }
    }

    // MARK: - posting (attach-info handler, or the run queue before attach)

    @discardableResult
    func post(_ action: ARunnable) -> Bool {
        if let ai = mAttachInfo {
            return ai.handler.post(action)
        }
        // Postpone the runnable until we know on which thread it needs to run.
        if mRunQueue == nil { mRunQueue = [] }
        mRunQueue!.append((action, 0))
        return true
    }

    @discardableResult
    func post(_ block: @escaping () -> Void) -> Bool {
        post(ARunnable(block))
    }

    @discardableResult
    func postDelayed(_ action: ARunnable, _ delayMillis: Int64) -> Bool {
        if let ai = mAttachInfo {
            return ai.handler.postDelayed(action, delayMillis)
        }
        if mRunQueue == nil { mRunQueue = [] }
        mRunQueue!.append((action, delayMillis))
        return true
    }

    @discardableResult
    func postDelayed(_ block: @escaping () -> Void, _ delayMillis: Int64) -> Bool {
        postDelayed(ARunnable(block), delayMillis)
    }

    /// View.postOnAnimation: runs once on the next frame (ANIMATION phase); before attach it is queued like post.
    func postOnAnimation(_ action: ARunnable) {
        if mAttachInfo != nil {
            AChoreographer.getInstance().postAnimationRunnable(action)
        } else {
            if mRunQueue == nil { mRunQueue = [] }
            mRunQueue!.append((action, 0))
        }
    }

    func postOnAnimation(_ block: @escaping () -> Void) {
        postOnAnimation(ARunnable(block))
    }

    /// View.removeCallbacks: removes the runnable from the handler, the animation callbacks and the run queue.
    @discardableResult
    func removeCallbacks(_ action: ARunnable) -> Bool {
        if let ai = mAttachInfo {
            ai.handler.removeCallbacks(action)
            AChoreographer.getInstance().removeAnimationRunnable(action)
        }
        mRunQueue?.removeAll(where: { $0.0 === action })
        return true
    }

    // MARK: - invalidation / drawing

    /// Override point: true for views whose onDraw only produces data (court snapshots). They never get a
    /// UIKit backing store; AViewRoot calls onDraw(ACanvas.noop) from the Choreographer traversal.
    var drawsInTraversal: Bool { false }

    var willNotDraw: Bool { mWillNotDraw }
    func setWillNotDraw(_ willNotDraw: Bool) {
        if mWillNotDraw != willNotDraw {
            mWillNotDraw = willNotDraw
            updateDrawingConfiguration()
            invalidate()
        }
    }

    /// View.invalidate: the view redraws on the next traversal (a hidden view skips the request).
    func invalidate() {
        if mVisibility != AView.VISIBLE { return }
        mDirty = true
        mAttachInfo?.root?.scheduleDraw(self)
    }

    /// View.invalidate(Rect) / invalidate(l, t, r, b): the whole view is redrawn.
    func invalidate(_ l: Int, _ t: Int, _ r: Int, _ b: Int) { invalidate() }

    func postInvalidate() { postInvalidateDelayed(0) }

    func postInvalidateDelayed(_ delayMilliseconds: Int64) {
        if let ai = mAttachInfo {
            ai.handler.postDelayed(ARunnable { [weak self] in self?.invalidate() }, delayMilliseconds)
        }
    }

    /// View.postInvalidateOnAnimation: invalidates on the next frame (nothing when detached).
    func postInvalidateOnAnimation() {
        mAttachInfo?.root?.dispatchInvalidateOnAnimation(self)
    }

    /// Override point (View.onDraw). The canvas is in pixels, origin at the view's top-left.
    func onDraw(_ canvas: ACanvas) {}

    /// Override point (ViewGroup.dispatchDraw). In the composited (UIKit) path children are separate layers and
    /// AViewGroup draws nothing here; drawing after `super.dispatchDraw` therefore lands below the children.
    func dispatchDraw(_ canvas: ACanvas) {}

    /// View.onDrawForeground: the foreground drawable (scroll bars are UIKit's).
    func onDrawForeground(_ canvas: ACanvas) {
        guard let fg = mForeground else { return }
        if mForegroundBoundsChanged {
            mForegroundBoundsChanged = false
            let selfBounds: (Int, Int, Int, Int) = mForegroundInsidePadding
                ? (0, 0, width, height)
                : (paddingLeft, paddingTop, width - paddingRight, height - paddingBottom)
            let r = AGravity.applyRect(mForegroundGravity, fg.intrinsicWidth, fg.intrinsicHeight, selfBounds,
                                       resolvedLayoutDirection())
            fg.setBounds(r.0, r.1, r.2, r.3)
        }
        fg.draw(canvas)
    }

    /// Draws the background drawable with bounds = the view's size (View.drawBackground).
    func drawBackground(_ canvas: ACanvas) {
        guard let bg = mBackground else { return }
        if mBackgroundSizeChanged {
            bg.setBounds(0, 0, mRight - mLeft, mBottom - mTop)
            mBackgroundSizeChanged = false
        }
        bg.draw(canvas)
    }

    /// Nesting depth of View.draw(Canvas) calls made by app code (offscreen rendering of a subtree).
    static var sOffscreenDrawDepth = 0

    /// View.draw(Canvas): renders this view and (offscreen) its children into the canvas.
    func draw(_ canvas: ACanvas) {
        AView.sOffscreenDrawDepth += 1
        defer { AView.sOffscreenDrawDepth -= 1 }
        drawBackground(canvas)
        onDraw(canvas)
        dispatchDraw(canvas)
        onDrawForeground(canvas)
    }

    /// Called by AViewRoot in the traversal draw phase for a dirty view.
    func performTraversalDraw() {
        mDirty = false
        if drawsInTraversal {
            // PFLAG_SKIP_DRAW (willNotDraw without a background): Android calls only dispatchDraw, never onDraw.
            if !(mWillNotDraw && mBackground == nil) {
                onDraw(ACanvas.noop)
            }
            return
        }
        updateDrawingConfiguration()
        mContentLayer?.setNeedsDisplay()
        mForegroundLayer?.setNeedsDisplay()
    }

    /// Chooses how the view's own pixels are produced: nothing, layer.backgroundColor, or a content layer.
    func updateDrawingConfiguration() {
        if drawsInTraversal {
            removeContentLayer()
            removeForegroundLayer()
            if mUsesLayerBackgroundColor { layer.backgroundColor = nil; mUsesLayerBackgroundColor = false }
            return
        }
        let skipDraw = mWillNotDraw && mBackground == nil
        if skipDraw {
            removeContentLayer()
            if mUsesLayerBackgroundColor { layer.backgroundColor = nil; mUsesLayerBackgroundColor = false }
        } else if mWillNotDraw, let cd = mBackground as? AColorDrawable, cd.alpha == 255 {
            removeContentLayer()
            layer.backgroundColor = AColor.cgColor(cd.color)
            mUsesLayerBackgroundColor = true
        } else {
            if mUsesLayerBackgroundColor { layer.backgroundColor = nil; mUsesLayerBackgroundColor = false }
            if mContentLayer == nil {
                let cl = ContentLayer(owner: self, foreground: false)
                cl.frame = CGRect(origin: .zero, size: bounds.size)
                layer.insertSublayer(cl, at: 0)
                mContentLayer = cl
                cl.setNeedsDisplay()
            }
        }
        if mForeground != nil {
            if mForegroundLayer == nil {
                let fl = ContentLayer(owner: self, foreground: true)
                fl.frame = CGRect(origin: .zero, size: bounds.size)
                layer.addSublayer(fl)
                mForegroundLayer = fl
                fl.setNeedsDisplay()
            }
        } else {
            removeForegroundLayer()
        }
    }

    private func removeContentLayer() {
        if let cl = mContentLayer {
            cl.owner = nil
            cl.removeFromSuperlayer()
            mContentLayer = nil
        }
    }

    private func removeForegroundLayer() {
        if let fl = mForegroundLayer {
            fl.owner = nil
            fl.removeFromSuperlayer()
            mForegroundLayer = nil
        }
    }

    fileprivate func renderLayer(_ ctx: CGContext, _ scale: CGFloat, foreground: Bool) {
        let w = mRight - mLeft, h = mBottom - mTop
        if w <= 0 || h <= 0 { return }
        ctx.saveGState()
        ctx.scaleBy(x: 1 / scale, y: 1 / scale)
        let canvas = ACanvas(ctx, w, h)
        if foreground {
            onDrawForeground(canvas)
        } else {
            drawBackground(canvas)
            onDraw(canvas)
            dispatchDraw(canvas)
        }
        ctx.restoreGState()
    }

    /// A CALayer below the subviews (content) or above them (foreground); CA owns the backing store and asks
    /// for the pixels when setNeedsDisplay() was called. Implicit animations are disabled.
    final class ContentLayer: CALayer {
        weak var owner: AView?
        let isForeground: Bool

        init(owner: AView, foreground: Bool) {
            self.owner = owner
            self.isForeground = foreground
            super.init()
            contentsScale = AView.densityScale
            needsDisplayOnBoundsChange = false
            zPosition = foreground ? 1000 : -1000
            isOpaque = false
        }

        override init(layer: Any) {
            let other = layer as? ContentLayer
            owner = other?.owner
            isForeground = other?.isForeground ?? false
            super.init(layer: layer)
        }

        required init?(coder: NSCoder) {
            isForeground = false
            super.init(coder: coder)
        }

        override func action(forKey event: String) -> CAAction? {
            return nil
        }

        override func draw(in ctx: CGContext) {
            owner?.renderLayer(ctx, contentsScale, foreground: isForeground)
        }
    }

    // MARK: - scrolling (View.scrollTo)

    var scrollX: Int {
        get { mScrollX }
        set { scrollTo(newValue, mScrollY) }
    }
    var scrollY: Int {
        get { mScrollY }
        set { scrollTo(mScrollX, newValue) }
    }

    /// View.scrollTo: offsets the drawing of the children (the child host moves in AViewGroup).
    func scrollTo(_ x: Int, _ y: Int) {
        if mScrollX != x || mScrollY != y {
            let oldX = mScrollX
            let oldY = mScrollY
            mScrollX = x
            mScrollY = y
            scrollOffsetDidChange()
            onScrollChanged(mScrollX, mScrollY, oldX, oldY)
            postInvalidateOnAnimation()
        }
    }

    func scrollBy(_ x: Int, _ y: Int) {
        scrollTo(mScrollX + x, mScrollY + y)
    }

    /// Hook for AViewGroup / AScrollView: apply the scroll offset to UIKit.
    func scrollOffsetDidChange() {}

    /// Override point (View.computeScroll): called for a dirty view right before it is redrawn in the traversal
    /// (ViewRootImpl -> updateDisplayListIfDirty), where scroll views advance their smooth-scroll animation.
    func computeScroll() {}

    // Scroll bars and over-scroll (the UIScrollView-backed scroll views map them to indicators and bouncing).
    private var mVerticalScrollBarEnabled = false
    private var mHorizontalScrollBarEnabled = false
    private var mOverScrollMode = AView.OVER_SCROLL_IF_CONTENT_SCROLLS

    var isVerticalScrollBarEnabled: Bool {
        get { mVerticalScrollBarEnabled }
        set { setVerticalScrollBarEnabled(newValue) }
    }
    func setVerticalScrollBarEnabled(_ verticalScrollBarEnabled: Bool) {
        if mVerticalScrollBarEnabled != verticalScrollBarEnabled {
            mVerticalScrollBarEnabled = verticalScrollBarEnabled
            scrollBarsOrOverScrollDidChange()
        }
    }

    var isHorizontalScrollBarEnabled: Bool {
        get { mHorizontalScrollBarEnabled }
        set { setHorizontalScrollBarEnabled(newValue) }
    }
    func setHorizontalScrollBarEnabled(_ horizontalScrollBarEnabled: Bool) {
        if mHorizontalScrollBarEnabled != horizontalScrollBarEnabled {
            mHorizontalScrollBarEnabled = horizontalScrollBarEnabled
            scrollBarsOrOverScrollDidChange()
        }
    }

    /// View.getOverScrollMode / setOverScrollMode (OVER_SCROLL_IF_CONTENT_SCROLLS by default).
    var overScrollMode: Int {
        get { mOverScrollMode }
        set { setOverScrollMode(newValue) }
    }
    func setOverScrollMode(_ overScrollMode: Int) {
        precondition(overScrollMode == AView.OVER_SCROLL_ALWAYS || overScrollMode == AView.OVER_SCROLL_IF_CONTENT_SCROLLS
                     || overScrollMode == AView.OVER_SCROLL_NEVER, "Invalid overscroll mode \(overScrollMode)")
        if mOverScrollMode != overScrollMode {
            mOverScrollMode = overScrollMode
            scrollBarsOrOverScrollDidChange()
        }
    }
    func getOverScrollMode() -> Int { mOverScrollMode }

    /// Hook for the scroll views: the scroll-bar or over-scroll settings changed.
    func scrollBarsOrOverScrollDidChange() {}

    /// View.setScrollBarStyle / setScrollbarFadingEnabled: the iOS indicators have their own style and fade.
    var scrollBarStyle: Int = AView.SCROLLBARS_INSIDE_OVERLAY
    var isScrollbarFadingEnabled: Bool = true

    /// Override point (View.onScrollChanged); the window's OnScrollChangedListeners fire on the next traversal.
    func onScrollChanged(_ l: Int, _ t: Int, _ oldl: Int, _ oldt: Int) {
        if let ai = mAttachInfo {
            ai.viewScrollChanged = true
            ai.root?.scheduleTraversals()
        }
        mOnScrollChangeListener?(self, l, t, oldl, oldt)
    }

    func setOnScrollChangeListener(_ l: ((AView, Int, Int, Int, Int) -> Void)?) {
        mOnScrollChangeListener = l
    }

    func computeHorizontalScrollRange() -> Int { width }
    func computeHorizontalScrollOffset() -> Int { mScrollX }
    func computeHorizontalScrollExtent() -> Int { width }
    func computeVerticalScrollRange() -> Int { height }
    func computeVerticalScrollOffset() -> Int { mScrollY }
    func computeVerticalScrollExtent() -> Int { height }

    func canScrollHorizontally(_ direction: Int) -> Bool {
        let offset = computeHorizontalScrollOffset()
        let range = computeHorizontalScrollRange() - computeHorizontalScrollExtent()
        if range == 0 { return false }
        if direction < 0 {
            return offset > 0
        } else {
            return offset < range - 1
        }
    }

    func canScrollVertically(_ direction: Int) -> Bool {
        let offset = computeVerticalScrollOffset()
        let range = computeVerticalScrollRange() - computeVerticalScrollExtent()
        if range == 0 { return false }
        if direction < 0 {
            return offset > 0
        } else {
            return offset < range - 1
        }
    }

    /// View.requestRectangleOnScreen: asks each ancestor (ScrollViews) to bring the rectangle into view.
    @discardableResult
    func requestRectangleOnScreen(_ rectangle: ARect) -> Bool {
        requestRectangleOnScreen(rectangle, false)
    }

    @discardableResult
    func requestRectangleOnScreen(_ rectangle: ARect, _ immediate: Bool) -> Bool {
        guard mParent != nil else { return false }
        var child: AView = self
        var pl = Float(rectangle.left), pt = Float(rectangle.top), pr = Float(rectangle.right), pb = Float(rectangle.bottom)
        var parent: AViewGroup? = mParent
        var scrolled = false
        while let p = parent {
            rectangle.left = Int(pl)
            rectangle.top = Int(pt)
            rectangle.right = Int(pr)
            rectangle.bottom = Int(pb)
            scrolled = p.requestChildRectangleOnScreen(child, rectangle, immediate) || scrolled
            // move it from child's content coordinate space to parent's content coordinate space
            let dx = Float(child.mLeft - child.mScrollX), dy = Float(child.mTop - child.mScrollY)
            pl += dx; pr += dx; pt += dy; pb += dy
            child = p
            parent = p.mParent
        }
        return scrolled
    }

    // MARK: - locations

    /// View.getLocationInWindow: top-left in window pixels through all transforms (Math.round).
    func getLocationInWindow(_ outLocation: inout [Int]) {
        precondition(outLocation.count >= 2, "outLocation must be an array of two integers")
        outLocation[0] = 0
        outLocation[1] = 0
        transformFromViewToWindowSpace(&outLocation)
    }

    /// View.getLocationOnScreen: the window location plus the window's position on the screen.
    func getLocationOnScreen(_ outLocation: inout [Int]) {
        getLocationInWindow(&outLocation)
        if let root = mAttachInfo?.root {
            let o = root.windowOffsetOnScreenPx
            outLocation[0] += o.x
            outLocation[1] += o.y
        }
    }

    func transformFromViewToWindowSpace(_ inOutLocation: inout [Int]) {
        guard mAttachInfo != nil else {
            // When the view is not attached to a window, this method does not make sense
            inOutLocation[0] = 0
            inOutLocation[1] = 0
            return
        }
        var px = Float(inOutLocation[0]), py = Float(inOutLocation[1])
        if !hasIdentityMatrix {
            (px, py) = AView.mapPoint(matrixTransform, px, py)
        }
        px += Float(mLeft)
        py += Float(mTop)
        var viewParent = mParent
        while let view = viewParent {
            px -= Float(view.mScrollX)
            py -= Float(view.mScrollY)
            if !view.hasIdentityMatrix {
                (px, py) = AView.mapPoint(view.matrixTransform, px, py)
            }
            px += Float(view.mLeft)
            py += Float(view.mTop)
            viewParent = view.mParent
        }
        inOutLocation[0] = AView.javaRound(px)
        inOutLocation[1] = AView.javaRound(py)
    }

    static func mapPoint(_ t: CGAffineTransform, _ x: Float, _ y: Float) -> (Float, Float) {
        let p = CGPoint(x: CGFloat(x), y: CGFloat(y)).applying(t)
        return (Float(p.x), Float(p.y))
    }

    /// java.lang.Math.round(float), bit-exact (ties toward positive infinity).
    static func javaRound(_ a: Float) -> Int {
        let intBits = Int32(bitPattern: a.bitPattern)
        let biasedExp = (intBits & 0x7F80_0000) >> 23
        let shift = (24 - 2 + 127) - biasedExp
        if (shift & -32) == 0 {
            var r = (intBits & 0x007F_FFFF) | (0x007F_FFFF + 1)
            if intBits < 0 { r = -r }
            return Int(((r >> shift) + 1) >> 1)
        } else {
            return AViewConfiguration.f2i(a)
        }
    }

    /// View.getDrawingRect.
    func getDrawingRect(_ outRect: ARect) {
        outRect.left = mScrollX
        outRect.top = mScrollY
        outRect.right = mScrollX + (mRight - mLeft)
        outRect.bottom = mScrollY + (mBottom - mTop)
    }

    /// View.getHitRect: the frame in the parent's coordinates (transformed bounding box).
    func getHitRect(_ outRect: ARect) {
        if hasIdentityMatrix || mAttachInfo == nil {
            outRect.left = mLeft
            outRect.top = mTop
            outRect.right = mRight
            outRect.bottom = mBottom
        } else {
            let r = CGRect(x: 0, y: 0, width: width, height: height).applying(matrixTransform)
            outRect.left = AViewConfiguration.f2i(Float(r.minX)) + mLeft
            outRect.top = AViewConfiguration.f2i(Float(r.minY)) + mTop
            outRect.right = AViewConfiguration.f2i(Float(r.maxX)) + mLeft
            outRect.bottom = AViewConfiguration.f2i(Float(r.maxY)) + mTop
        }
    }

    /// View.getGlobalVisibleRect: the visible part of the view in window pixels.
    @discardableResult
    func getGlobalVisibleRect(_ r: ARect) -> Bool {
        let w = mRight - mLeft
        let h = mBottom - mTop
        if w > 0 && h > 0 {
            r.left = 0
            r.top = 0
            r.right = w
            r.bottom = h
            if let p = mParent {
                return p.getChildVisibleRect(self, r)
            }
            if let root = mViewRootParent {
                return AView.intersect(r, 0, 0, root.widthPx, root.heightPx)
            }
            return true
        }
        return false
    }

    /// View.getLocalVisibleRect.
    @discardableResult
    func getLocalVisibleRect(_ r: ARect) -> Bool {
        var loc = [0, 0]
        getLocationInWindow(&loc)
        if getGlobalVisibleRect(r) {
            r.offset(-loc[0], -loc[1])
            return true
        }
        return false
    }

    /// Rect.intersect(l, t, r, b) on an ARect (unchanged and false when they do not intersect).
    static func intersect(_ rect: ARect, _ left: Int, _ top: Int, _ right: Int, _ bottom: Int) -> Bool {
        if rect.left < right && left < rect.right && rect.top < bottom && top < rect.bottom {
            if rect.left < left { rect.left = left }
            if rect.top < top { rect.top = top }
            if rect.right > right { rect.right = right }
            if rect.bottom > bottom { rect.bottom = bottom }
            return true
        }
        return false
    }

    /// View.pointInView(localX, localY, slop).
    func pointInView(_ localX: Float, _ localY: Float, _ slop: Float = 0) -> Bool {
        localX >= -slop && localY >= -slop && localX < Float(mRight - mLeft) + slop && localY < Float(mBottom - mTop) + slop
    }

    // MARK: - window insets

    func setOnApplyWindowInsetsListener(_ listener: ((AView, AWindowInsetsCompat) -> AWindowInsetsCompat)?) {
        mOnApplyWindowInsetsListener = listener
    }

    /// View.dispatchApplyWindowInsets: the listener, else onApplyWindowInsets.
    @discardableResult
    func dispatchApplyWindowInsets(_ insets: AWindowInsetsCompat) -> AWindowInsetsCompat {
        if let l = mOnApplyWindowInsetsListener {
            return l(self, insets)
        }
        return onApplyWindowInsets(insets)
    }

    /// Override point (View.onApplyWindowInsets): fitsSystemWindows views take the system window insets as
    /// padding and consume them.
    func onApplyWindowInsets(_ insets: AWindowInsetsCompat) -> AWindowInsetsCompat {
        if mFitsSystemWindows {
            let s = insets.systemWindowInsets
            internalSetPadding(s.left, s.top, s.right, s.bottom)
            return insets.consumeSystemWindowInsets()
        }
        return insets
    }

    /// View.requestApplyInsets (requestFitSystemWindows up the parents): the window dispatches its insets again on
    /// the next traversal. A detached view has no window to ask, so this does nothing then, as on Android
    /// (androidx FragmentStateManager requests again from an attach listener).
    func requestApplyInsets() {
        if let p = mParent {
            p.requestApplyInsets()
        } else if let root = mViewRootParent {
            root.requestApplyInsets()
        }
    }

    /// View.getRootWindowInsets.
    var rootWindowInsets: AWindowInsetsCompat? { mAttachInfo?.root?.lastDispatchedInsets }

    // MARK: - focus (touch mode)

    var isFocusedSelf: Bool { mAttachInfo?.focusedView === self }

    /// View.requestFocus: in touch mode only views focusable in touch mode take focus.
    @discardableResult
    func requestFocus() -> Bool {
        requestFocus(AView.FOCUS_DOWN)
    }

    @discardableResult
    func requestFocus(_ direction: Int) -> Bool {
        guard isFocusable, mFocusableInTouchMode, isShown, let ai = mAttachInfo else { return false }
        if ai.focusedView === self { return true }
        let previous = ai.focusedView
        ai.focusedView = self
        // View.handleFocusGainInternal: the parents learn about the new focus (ScrollViews scroll to it).
        mParent?.requestChildFocus(self, self)
        previous?.focusChanged(false, direction)
        focusChanged(true, direction)
        return true
    }

    func clearFocus() {
        guard let ai = mAttachInfo, ai.focusedView === self else { return }
        ai.focusedView = nil
        focusChanged(false, 0)
    }

    private func focusChanged(_ gainFocus: Bool, _ direction: Int) {
        refreshDrawableState()
        onFocusChanged(gainFocus, direction, nil)
        mOnFocusChangeListener?(self, gainFocus)
    }

    /// Override point (View.onFocusChanged).
    func onFocusChanged(_ gainFocus: Bool, _ direction: Int, _ previouslyFocusedRect: ARect?) {}

    /// View.hasFocus: this view or a descendant has the window focus.
    func hasFocus() -> Bool {
        guard let f = mAttachInfo?.focusedView else { return false }
        var v: AView? = f
        while let cur = v {
            if cur === self { return true }
            v = cur.mParent
        }
        return false
    }

    /// View.findFocus.
    func findFocus() -> AView? {
        hasFocus() ? mAttachInfo?.focusedView : nil
    }

    func setOnFocusChangeListener(_ l: ((AView, Bool) -> Void)?) { mOnFocusChangeListener = l }

    // MARK: - listeners and click handling

    /// View.setOnClickListener: also makes the view clickable (even for a nil listener, as Android).
    func setOnClickListener(_ l: ((AView) -> Void)?) {
        if !isClickable {
            setClickable(true)
        }
        mOnClickListener = l
    }

    /// View.setOnLongClickListener: also makes the view long-clickable.
    func setOnLongClickListener(_ l: ((AView) -> Bool)?) {
        if !isLongClickable {
            setLongClickable(true)
        }
        mOnLongClickListener = l
    }

    func setOnTouchListener(_ l: ((AView, AMotionEvent) -> Bool)?) {
        mOnTouchListener = l
    }

    func hasOnClickListeners() -> Bool { mOnClickListener != nil }
    func hasOnLongClickListeners() -> Bool { mOnLongClickListener != nil }

    /// View.performClick: calls the click listener (the click sound of Android is a system setting; iOS has none).
    @discardableResult
    func performClick() -> Bool {
        if let l = mOnClickListener {
            l(self)
            return true
        }
        return false
    }

    /// View.callOnClick.
    @discardableResult
    func callOnClick() -> Bool {
        if let l = mOnClickListener {
            l(self)
            return true
        }
        return false
    }

    /// View.performLongClick.
    @discardableResult
    func performLongClick() -> Bool {
        performLongClickInternal(Float.nan, Float.nan)
    }

    @discardableResult
    func performLongClick(_ x: Float, _ y: Float) -> Bool {
        performLongClickInternal(x, y)
    }

    private func performLongClickInternal(_ x: Float, _ y: Float) -> Bool {
        var handled = false
        if let listener = mOnLongClickListener {
            handled = listener(self)
        }
        if handled {
            _ = performHapticFeedback(AView.HAPTIC_LONG_PRESS)
        }
        return handled
    }

    // MARK: - haptics (HapticFeedbackConstants -> UIFeedbackGenerator)

    static let HAPTIC_LONG_PRESS = AHapticFeedbackConstants.LONG_PRESS
    static let HAPTIC_FLAG_IGNORE_VIEW_SETTING = AHapticFeedbackConstants.FLAG_IGNORE_VIEW_SETTING
    static let HAPTIC_FLAG_IGNORE_GLOBAL_SETTING = AHapticFeedbackConstants.FLAG_IGNORE_GLOBAL_SETTING

    /// View.performHapticFeedback(feedbackConstant).
    @discardableResult
    func performHapticFeedback(_ feedbackConstant: Int) -> Bool {
        performHapticFeedback(feedbackConstant, 0)
    }

    /// View.performHapticFeedback(feedbackConstant, flags): suppressed for NO_HAPTICS, a detached view or a view with
    /// haptic feedback disabled (unless FLAG_IGNORE_VIEW_SETTING); otherwise the window plays the constant's vibration
    /// (false when the constant has none, like PhoneWindowManager).
    @discardableResult
    func performHapticFeedback(_ feedbackConstant: Int, _ flags: Int) -> Bool {
        if feedbackConstant == AHapticFeedbackConstants.NO_HAPTICS || mAttachInfo == nil { return false }
        if (flags & AHapticFeedbackConstants.FLAG_IGNORE_VIEW_SETTING) == 0 && !isHapticFeedbackEnabled { return false }
        return AHaptics.perform(feedbackConstant)
    }

    // MARK: - touch dispatch (View)

    /// Override point (View.dispatchTouchEvent): the OnTouchListener (enabled views only), then onTouchEvent.
    func dispatchTouchEvent(_ event: AMotionEvent) -> Bool {
        var result = false
        if let l = mOnTouchListener, mEnabled, l(self, event) {
            result = true
        }
        if !result && onTouchEvent(event) {
            result = true
        }
        return result
    }

    /// Walks up the hierarchy: a parent that delays its children's pressed state (ScrollView, plain ViewGroup).
    func isInScrollingContainer() -> Bool {
        var p = mParent
        while let g = p {
            if g.shouldDelayChildPressedState() {
                return true
            }
            p = g.mParent
        }
        return false
    }

    /// Override point (View.onTouchEvent): pressed state, click on UP, long click after 400 ms.
    func onTouchEvent(_ event: AMotionEvent) -> Bool {
        let x = event.x
        let y = event.y
        let action = event.action

        let clickable = mClickable || mLongClickable || mContextClickable

        if !mEnabled {
            if action == AMotionEvent.ACTION_UP && mPressed {
                setPressed(false)
            }
            // A disabled view that is clickable still consumes the touch events, it just doesn't respond to them.
            return clickable
        }

        if clickable {
            switch action {
            case AMotionEvent.ACTION_UP:
                let prepressed = mPrepressed
                if mPressed || prepressed {
                    // take focus if we don't have it already and we should in touch mode.
                    var focusTaken = false
                    if isFocusable && isFocusableInTouchMode && !isFocusedSelf {
                        focusTaken = requestFocus()
                    }

                    if prepressed {
                        // The button is being released before we actually showed it as pressed. Make it show the
                        // pressed state now (before scheduling the click) to ensure the user sees it.
                        setPressed(true)
                    }

                    if !mHasPerformedLongPress && !mIgnoreNextUpEvent {
                        // This is a tap, so remove the longpress check
                        removeLongPressCallback()

                        // Only perform take click actions if we were in the pressed state
                        if !focusTaken {
                            // Use a Runnable and post this rather than calling performClick directly. This lets
                            // other visual state of the view update before click actions start.
                            if mPerformClick == nil {
                                mPerformClick = ARunnable { [weak self] in _ = self?.performClick() }
                            }
                            if !post(mPerformClick!) {
                                _ = performClick()
                            }
                        }
                    }

                    if mUnsetPressedState == nil {
                        mUnsetPressedState = ARunnable { [weak self] in self?.setPressed(false) }
                    }

                    if prepressed {
                        postDelayed(mUnsetPressedState!, Int64(AViewConfiguration.getPressedStateDuration()))
                    } else if !post(mUnsetPressedState!) {
                        // If the post failed, unpress right now
                        setPressed(false)
                    }

                    removeTapCallback()
                }
                mIgnoreNextUpEvent = false

            case AMotionEvent.ACTION_DOWN:
                mHasPerformedLongPress = false

                // Walk up the hierarchy to determine if we're inside a scrolling container.
                let isInScrollingContainer = isInScrollingContainer()

                // For views inside a scrolling container, delay the pressed feedback for a short period in case
                // this is a scroll.
                if isInScrollingContainer {
                    mPrepressed = true
                    if mPendingCheckForTap == nil {
                        mPendingCheckForTap = ARunnable { [weak self] in self?.checkForTap() }
                    }
                    mPendingCheckForTapX = event.x
                    mPendingCheckForTapY = event.y
                    postDelayed(mPendingCheckForTap!, Int64(AViewConfiguration.getTapTimeout()))
                } else {
                    // Not inside a scrolling container, so show the feedback right away
                    setPressed(true)
                    checkForLongClick(Int64(AViewConfiguration.getLongPressTimeout()), x, y)
                }

            case AMotionEvent.ACTION_CANCEL:
                setPressed(false)
                removeTapCallback()
                removeLongPressCallback()
                mInContextButtonPress = false
                mHasPerformedLongPress = false
                mIgnoreNextUpEvent = false

            case AMotionEvent.ACTION_MOVE:
                // Be lenient about moving outside of buttons
                if !pointInView(x, y, Float(mTouchSlop)) {
                    // Outside button. Remove any future long press/tap checks
                    removeTapCallback()
                    removeLongPressCallback()
                    if mPressed {
                        setPressed(false)
                    }
                }

            default:
                break
            }
            return true
        }

        return false
    }

    private func checkForTap() {
        mPrepressed = false
        setPressed(true)
        let delay = Int64(AViewConfiguration.getLongPressTimeout() - AViewConfiguration.getTapTimeout())
        checkForLongClick(delay, mPendingCheckForTapX, mPendingCheckForTapY)
    }

    private func checkForLongClick(_ delay: Int64, _ x: Float, _ y: Float) {
        if mLongClickable {
            mHasPerformedLongPress = false
            if mPendingCheckForLongPress == nil {
                mPendingCheckForLongPress = ARunnable { [weak self] in self?.runCheckForLongPress() }
            }
            mLongPressX = x
            mLongPressY = y
            mLongPressOriginalWindowAttachCount = mWindowAttachCount
            mLongPressOriginalPressedState = isPressed
            postDelayed(mPendingCheckForLongPress!, delay)
        }
    }

    private func runCheckForLongPress() {
        if mLongPressOriginalPressedState == isPressed && mParent != nil
            && mLongPressOriginalWindowAttachCount == mWindowAttachCount {
            if performLongClick(mLongPressX, mLongPressY) {
                mHasPerformedLongPress = true
            }
        }
    }

    private func removeLongPressCallback() {
        if let r = mPendingCheckForLongPress { removeCallbacks(r) }
    }

    private func removePerformClickCallback() {
        if let r = mPerformClick { removeCallbacks(r) }
    }

    private func removeUnsetPressCallback() {
        if mPressed, let r = mUnsetPressedState {
            setPressed(false)
            removeCallbacks(r)
        }
    }

    private func removeTapCallback() {
        if let r = mPendingCheckForTap {
            mPrepressed = false
            removeCallbacks(r)
        }
    }

    /// Hit-testing hint for UIKit (not the Android dispatch): whether this view may consume a touch that
    /// lands on it. Override (true) for views that consume in onTouchEvent without being clickable.
    var hitTestConsumesTouches: Bool {
        mClickable || mLongClickable || mContextClickable || mOnTouchListener != nil
    }

    // MARK: - UIKit touch plumbing

    override func hitTest(_ point: CGPoint, with event: UIEvent?) -> UIView? {
        if mVisibility != AView.VISIBLE { return nil }
        if let root = mViewRootParent, !root.isTouchable { return nil }
        let d = AView.densityScale
        if !pointInView(Float(point.x * d), Float(point.y * d)) { return nil }
        if let hit = hitTestDescendants(point, event) { return hit }
        if mViewRootParent != nil { return self }
        return hitTestConsumesTouches ? self : nil
    }

    /// Topmost subview hit (AView children, or native controls inside a widget). AViewGroup adds its children.
    func hitTestDescendants(_ point: CGPoint, _ event: UIEvent?) -> UIView? {
        for sub in subviews.reversed() {
            if let hit = AView.hitTestSubview(sub, self, point, event) { return hit }
        }
        return nil
    }

    /// UIKit hit test of one subview: AViews use the Android rules; native views count only when they are
    /// interactive controls (text fields, switches, scroll views), so decorative UIKit views never eat touches.
    static func hitTestSubview(_ sub: UIView, _ container: UIView, _ point: CGPoint, _ event: UIEvent?) -> UIView? {
        let p = sub.convert(point, from: container)
        if let child = sub as? AView {
            return child.hitTest(p, with: event)
        }
        if sub.isHidden || sub.alpha < 0.01 || !sub.isUserInteractionEnabled { return nil }
        guard let h = sub.hitTest(p, with: event) else { return nil }
        if h is AView || h is UIControl || h is UITextView || h is UIScrollView { return h }
        return nil
    }

    var touchRootForForwarding: AViewRoot? { mAttachInfo?.root ?? mTouchRoot }

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        if let root = touchRootForForwarding {
            root.handleTouches(touches, event, .began)
        } else {
            super.touchesBegan(touches, with: event)
        }
    }

    override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent?) {
        if let root = touchRootForForwarding {
            root.handleTouches(touches, event, .moved)
        } else {
            super.touchesMoved(touches, with: event)
        }
    }

    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) {
        if let root = touchRootForForwarding {
            root.handleTouches(touches, event, .ended)
        } else {
            super.touchesEnded(touches, with: event)
        }
    }

    override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent?) {
        if let root = touchRootForForwarding {
            root.handleTouches(touches, event, .cancelled)
        } else {
            super.touchesCancelled(touches, with: event)
        }
    }

    // MARK: - accessibility

    var contentDescription: String? {
        get { mContentDescription }
        set {
            mContentDescription = newValue
            updateAccessibility()
        }
    }

    var importantForAccessibility: Int {
        get { mImportantForAccessibility }
        set {
            mImportantForAccessibility = newValue
            updateAccessibility()
        }
    }

    /// Maps the Android accessibility attributes to UIKit: a content description or a clickable leaf view is
    /// an element (with the button trait when clickable); IMPORTANT_FOR_ACCESSIBILITY_NO hides it.
    func updateAccessibility() {
        let important = mImportantForAccessibility != AView.IMPORTANT_FOR_ACCESSIBILITY_NO
            && mImportantForAccessibility != AView.IMPORTANT_FOR_ACCESSIBILITY_NO_HIDE_DESCENDANTS
        accessibilityElementsHidden = mImportantForAccessibility == AView.IMPORTANT_FOR_ACCESSIBILITY_NO_HIDE_DESCENDANTS
        accessibilityLabel = mContentDescription
        let isLeaf = !(self is AViewGroup)
        isAccessibilityElement = important && mVisibility == AView.VISIBLE
            && (mContentDescription != nil || (isLeaf && mClickable) || providesAccessibilityText)
        var traits: UIAccessibilityTraits = []
        if mClickable { traits.insert(.button) }
        if mSelected { traits.insert(.selected) }
        if !mEnabled { traits.insert(.notEnabled) }
        accessibilityTraits = traits
    }

    /// Override point: widgets that expose their own text to VoiceOver (TextView) return true.
    var providesAccessibilityText: Bool { false }

    override func accessibilityActivate() -> Bool {
        if mClickable && mEnabled {
            return performClick()
        }
        return false
    }

    // MARK: - layer type (rendering hint)

    var layerType: Int { mLayerType }
    func setLayerType(_ layerType: Int, _ paint: APaint?) {
        mLayerType = layerType
    }

    // MARK: - animation

    /// View.animate(): the view's (single, reused) property animator.
    func animate() -> AViewPropertyAnimator {
        if let a = mAnimator { return a }
        let a = AViewPropertyAnimator(self)
        mAnimator = a
        return a
    }

    // MARK: - tree helpers

    /// View.bringToFront: the parent moves this view to the end of its child list (drawn last, laid out last).
    func bringToFront() {
        mParent?.bringChildToFront(self)
    }

    /// View.getParent() as seen by app code (`parent as ViewGroup`): the parent view group (nil for a window root).
    var parent: AViewGroup? { mParent }
    func getParent() -> AViewGroup? { mParent }
    func getRootView() -> AView { rootView }

    /// View.getContext(): the activity whose window shows this view, else the top activity, else the application
    /// (views are created without a context in AndroidKit; the app has one activity window at a time).
    var context: AContext {
        if let root = mAttachInfo?.root ?? mTouchRoot {
            var v: UIView? = root.host
            while let current = v {
                if let rootView = current as? AActivityRootView, let activity = rootView.activity {
                    return activity
                }
                v = current.superview
            }
        }
        if let top = AActivityHost.shared?.topActivity {
            return top
        }
        return AApplication.shared
    }
    func getContext() -> AContext { context }

    /// View.getResources().
    var resources: AContextResources { context.resources }
    func getResources() -> AContextResources { resources }

    // MARK: - Java-style accessors (Java callers and Kotlin's get/set forms)

    func getLeft() -> Int { mLeft }
    func getTop() -> Int { mTop }
    func getRight() -> Int { mRight }
    func getBottom() -> Int { mBottom }
    func getMeasuredWidth() -> Int { measuredWidth }
    func getMeasuredHeight() -> Int { measuredHeight }
    func getMeasuredWidthAndState() -> Int { mMeasuredWidth }
    func getMeasuredHeightAndState() -> Int { mMeasuredHeight }
    func getMinimumWidth() -> Int { mMinWidth }
    func getMinimumHeight() -> Int { mMinHeight }
    func getPaddingLeft() -> Int { paddingLeft }
    func getPaddingTop() -> Int { paddingTop }
    func getPaddingRight() -> Int { paddingRight }
    func getPaddingBottom() -> Int { paddingBottom }
    func getPaddingStart() -> Int { paddingStart }
    func getPaddingEnd() -> Int { paddingEnd }
    func getScrollX() -> Int { mScrollX }
    func getScrollY() -> Int { mScrollY }
    func setScrollX(_ value: Int) { scrollTo(value, mScrollY) }
    func setScrollY(_ value: Int) { scrollTo(mScrollX, value) }

    func getX() -> Float { x }
    func getY() -> Float { y }
    func getZ() -> Float { z }
    func setX(_ x: Float) { self.x = x }
    func setY(_ y: Float) { self.y = y }
    func setZ(_ z: Float) { self.z = z }
    func getTranslationX() -> Float { translationX }
    func getTranslationY() -> Float { translationY }
    func getTranslationZ() -> Float { translationZ }
    func setTranslationX(_ translationX: Float) { self.translationX = translationX }
    func setTranslationY(_ translationY: Float) { self.translationY = translationY }
    func setTranslationZ(_ translationZ: Float) { self.translationZ = translationZ }
    func getElevation() -> Float { elevation }
    func setElevation(_ elevation: Float) { self.elevation = elevation }
    func getScaleX() -> Float { scaleX }
    func getScaleY() -> Float { scaleY }
    func setScaleX(_ scaleX: Float) { self.scaleX = scaleX }
    func setScaleY(_ scaleY: Float) { self.scaleY = scaleY }
    func getRotation() -> Float { rotation }
    func setRotation(_ rotation: Float) { self.rotation = rotation }
    func getPivotX() -> Float { pivotX }
    func getPivotY() -> Float { pivotY }
    func setPivotX(_ pivotX: Float) { self.pivotX = pivotX }
    func setPivotY(_ pivotY: Float) { self.pivotY = pivotY }

    /// View.getAlpha / setAlpha in Android's Float (UIKit's `alpha` is the same value as CGFloat).
    func getAlpha() -> Float { Float(alpha) }
    func setAlpha(_ alpha: Float) {
        let value = CGFloat(alpha)
        if self.alpha != value { self.alpha = value }
    }

    func getContentDescription() -> String? { mContentDescription }
    func setContentDescription(_ contentDescription: String?) { self.contentDescription = contentDescription }
    func getImportantForAccessibility() -> Int { mImportantForAccessibility }
    func setImportantForAccessibility(_ mode: Int) { importantForAccessibility = mode }
    func isImportantForAccessibility() -> Bool {
        mImportantForAccessibility != AView.IMPORTANT_FOR_ACCESSIBILITY_NO
            && mImportantForAccessibility != AView.IMPORTANT_FOR_ACCESSIBILITY_NO_HIDE_DESCENDANTS
    }

    func getLayoutDirection() -> Int { layoutDirection }
    func getTextDirection() -> Int { textDirection }
    func getTextAlignment() -> Int { textAlignment }
    func getKeepScreenOn() -> Bool { keepScreenOn }
    func setKeepScreenOn(_ keepScreenOn: Bool) { self.keepScreenOn = keepScreenOn }
    func setHapticFeedbackEnabled(_ enabled: Bool) { isHapticFeedbackEnabled = enabled }
    func setSoundEffectsEnabled(_ enabled: Bool) { isSoundEffectsEnabled = enabled }
    func setFitsSystemWindows(_ fitSystemWindows: Bool) { fitsSystemWindows = fitSystemWindows }
    func getFitsSystemWindows() -> Bool { fitsSystemWindows }

    // MARK: - keep screen on

    /// Set once any view asked to keep the screen on; until then updates are free.
    static var sAnyKeepScreenOnRequested = false

    /// Window flag FLAG_KEEP_SCREEN_ON: on while any attached, VISIBLE view chain has keepScreenOn.
    static func updateKeepScreenOn() {
        guard sAnyKeepScreenOnRequested else { return }
        var any = false
        for root in AViewRoot.liveRoots {
            if let v = root.view, AView.collectKeepScreenOn(v) { any = true }
        }
        if UIApplication.shared.isIdleTimerDisabled != any && (any || AView.sDisabledIdleTimer) {
            UIApplication.shared.isIdleTimerDisabled = any
            AView.sDisabledIdleTimer = any
        }
    }

    private static var sDisabledIdleTimer = false

    private static func collectKeepScreenOn(_ v: AView) -> Bool {
        if v.mVisibility != AView.VISIBLE { return false }
        if v.mKeepScreenOn { return true }
        if let g = v as? AViewGroup {
            for c in g.mChildren where collectKeepScreenOn(c) { return true }
        }
        return false
    }
}
