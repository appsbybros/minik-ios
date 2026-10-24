import UIKit

// android.view.ViewConfiguration and android.view.GestureDetector (+ listeners), VIEW-API "Views".
// GestureDetector is a statement-by-statement port of the AOSP class (Android 14): the same handler messages
// (SHOW_PRESS at downTime + 100 ms, LONG_PRESS at downTime + 400 ms, TAP 300 ms after a first tap), the same slop
// squares, focal-point scrolling and callback order. Its fling velocities come from AVelocityTracker
// (AVelocityTracker.swift, the native LSQ2 strategy).

// MARK: - ViewConfiguration

final class AViewConfiguration {
    // AOSP ViewConfiguration constants (dp or ms).
    static let SCROLL_BAR_SIZE = 4
    static let SCROLL_BAR_FADE_DURATION = 250
    static let SCROLL_BAR_DEFAULT_DELAY = 300
    static let FADING_EDGE_LENGTH = 12
    static let PRESSED_STATE_DURATION = 64
    static let DEFAULT_LONG_PRESS_TIMEOUT = 400
    static let TAP_TIMEOUT = 100
    static let JUMP_TAP_TIMEOUT = 500
    static let DOUBLE_TAP_TIMEOUT = 300
    static let DOUBLE_TAP_MIN_TIME = 40
    static let HOVER_TAP_TIMEOUT = 150
    static let HOVER_TAP_SLOP = 20
    static let ZOOM_CONTROLS_TIMEOUT = 3000
    static let EDGE_SLOP = 12
    static let TOUCH_SLOP = 8
    static let DOUBLE_TAP_TOUCH_SLOP = TOUCH_SLOP
    static let PAGING_TOUCH_SLOP = TOUCH_SLOP * 2
    static let DOUBLE_TAP_SLOP = 100
    static let WINDOW_TOUCH_SLOP = 16
    static let MINIMUM_FLING_VELOCITY = 50
    static let MAXIMUM_FLING_VELOCITY = 8000
    static let OVERSCROLL_DISTANCE = 0
    static let OVERFLING_DISTANCE = 6
    static let SCROLL_FRICTION: Float = 0.015
    static let AMBIGUOUS_GESTURE_MULTIPLIER: Float = 2

    let scaledTouchSlop: Int
    let scaledDoubleTapTouchSlop: Int
    let scaledPagingTouchSlop: Int
    let scaledDoubleTapSlop: Int
    let scaledWindowTouchSlop: Int
    let scaledEdgeSlop: Int
    let scaledFadingEdgeLength: Int
    let scaledMinimumFlingVelocity: Int
    let scaledMaximumFlingVelocity: Int
    let scaledOverscrollDistance: Int
    let scaledOverflingDistance: Int
    let scaledScrollBarSize: Int
    let scaledAmbiguousGestureMultiplier: Float

    private static var cached: AViewConfiguration?

    /// ViewConfiguration.get(context): one configuration per (fixed) display density.
    static func get() -> AViewConfiguration {
        if let c = cached { return c }
        let c = AViewConfiguration(density: Float(AView.densityScale), xlarge: AViewConfiguration.isXLargeScreen())
        cached = c
        return c
    }

    /// ViewConfiguration.get(Context): the context only selects the display; there is one display here.
    static func get(_ context: Any?) -> AViewConfiguration { get() }

    init(density: Float, xlarge: Bool) {
        // sizeAndDensity = density * 1.5 on SCREENLAYOUT_SIZE_XLARGE, as AOSP.
        let sizeAndDensity: Float = xlarge ? density * 1.5 : density
        func dimensionPixelSize(_ dp: Int) -> Int {
            // Resources.getDimensionPixelSize: (int)(value + 0.5f), at least 1 for a non-zero value.
            let f = Float(dp) * density
            let res = AViewConfiguration.f2i(f >= 0 ? f + 0.5 : f - 0.5)
            if res != 0 { return res }
            if dp == 0 { return 0 }
            return dp > 0 ? 1 : -1
        }
        func scaled(_ v: Int) -> Int { AViewConfiguration.f2i(sizeAndDensity * Float(v) + 0.5) }
        scaledEdgeSlop = scaled(AViewConfiguration.EDGE_SLOP)
        scaledFadingEdgeLength = scaled(AViewConfiguration.FADING_EDGE_LENGTH)
        scaledScrollBarSize = dimensionPixelSize(AViewConfiguration.SCROLL_BAR_SIZE)
        scaledDoubleTapSlop = scaled(AViewConfiguration.DOUBLE_TAP_SLOP)
        scaledWindowTouchSlop = scaled(AViewConfiguration.WINDOW_TOUCH_SLOP)
        scaledMinimumFlingVelocity = dimensionPixelSize(AViewConfiguration.MINIMUM_FLING_VELOCITY)
        scaledMaximumFlingVelocity = dimensionPixelSize(AViewConfiguration.MAXIMUM_FLING_VELOCITY)
        scaledTouchSlop = dimensionPixelSize(AViewConfiguration.TOUCH_SLOP)
        scaledPagingTouchSlop = scaledTouchSlop * 2
        scaledDoubleTapTouchSlop = scaledTouchSlop
        scaledOverscrollDistance = scaled(AViewConfiguration.OVERSCROLL_DISTANCE)
        scaledOverflingDistance = scaled(AViewConfiguration.OVERFLING_DISTANCE)
        scaledAmbiguousGestureMultiplier = AViewConfiguration.AMBIGUOUS_GESTURE_MULTIPLIER
    }

    /// Configuration.SCREENLAYOUT_SIZE_XLARGE: at least 960 x 720 dp (iPad sizes).
    private static func isXLargeScreen() -> Bool {
        let b = UIScreen.main.bounds.size
        let longSide = max(b.width, b.height), shortSide = min(b.width, b.height)
        return longSide >= 960 && shortSide >= 720
    }

    /// Java (int) cast of a float: truncation toward zero, NaN -> 0, saturating to the Int32 range.
    static func f2i(_ f: Float) -> Int {
        if f.isNaN { return 0 }
        if f >= 2147483648.0 { return Int(Int32.max) }   // Float(Int32.max) rounds up to 2^31
        if f <= -2147483648.0 { return Int(Int32.min) }
        return Int(f)
    }

    static func getTapTimeout() -> Int { TAP_TIMEOUT }
    static func getJumpTapTimeout() -> Int { JUMP_TAP_TIMEOUT }
    static func getDoubleTapTimeout() -> Int { DOUBLE_TAP_TIMEOUT }
    static func getDoubleTapMinTime() -> Int { DOUBLE_TAP_MIN_TIME }
    static func getLongPressTimeout() -> Int { DEFAULT_LONG_PRESS_TIMEOUT }
    static func getPressedStateDuration() -> Int { PRESSED_STATE_DURATION }
    static func getScrollFriction() -> Float { SCROLL_FRICTION }
    static func getScrollBarFadeDuration() -> Int { SCROLL_BAR_FADE_DURATION }
    static func getScrollDefaultDelay() -> Int { SCROLL_BAR_DEFAULT_DELAY }
    static func getAmbiguousGestureMultiplier() -> Float { AMBIGUOUS_GESTURE_MULTIPLIER }
    // Deprecated unscaled getters (values in dp), used by GestureDetector without a context.
    static func getTouchSlop() -> Int { TOUCH_SLOP }
    static func getDoubleTapSlop() -> Int { DOUBLE_TAP_SLOP }
    static func getMinimumFlingVelocity() -> Int { MINIMUM_FLING_VELOCITY }
    static func getMaximumFlingVelocity() -> Int { MAXIMUM_FLING_VELOCITY }
}

// MARK: - GestureDetector listeners

protocol AOnGestureListener: AnyObject {
    func onDown(_ e: AMotionEvent) -> Bool
    func onShowPress(_ e: AMotionEvent)
    func onSingleTapUp(_ e: AMotionEvent) -> Bool
    func onScroll(_ e1: AMotionEvent?, _ e2: AMotionEvent, _ distanceX: Float, _ distanceY: Float) -> Bool
    func onLongPress(_ e: AMotionEvent)
    func onFling(_ e1: AMotionEvent?, _ e2: AMotionEvent, _ velocityX: Float, _ velocityY: Float) -> Bool
}

protocol AOnDoubleTapListener: AnyObject {
    func onSingleTapConfirmed(_ e: AMotionEvent) -> Bool
    func onDoubleTap(_ e: AMotionEvent) -> Bool
    func onDoubleTapEvent(_ e: AMotionEvent) -> Bool
}

protocol AOnContextClickListener: AnyObject {
    func onContextClick(_ e: AMotionEvent) -> Bool
}

/// GestureDetector.SimpleOnGestureListener: every callback returns false / does nothing; subclass and override.
class ASimpleOnGestureListener: AOnGestureListener, AOnDoubleTapListener, AOnContextClickListener {
    init() {}
    func onSingleTapUp(_ e: AMotionEvent) -> Bool { false }
    func onLongPress(_ e: AMotionEvent) {}
    func onScroll(_ e1: AMotionEvent?, _ e2: AMotionEvent, _ distanceX: Float, _ distanceY: Float) -> Bool { false }
    func onFling(_ e1: AMotionEvent?, _ e2: AMotionEvent, _ velocityX: Float, _ velocityY: Float) -> Bool { false }
    func onShowPress(_ e: AMotionEvent) {}
    func onDown(_ e: AMotionEvent) -> Bool { false }
    func onDoubleTap(_ e: AMotionEvent) -> Bool { false }
    func onDoubleTapEvent(_ e: AMotionEvent) -> Bool { false }
    func onSingleTapConfirmed(_ e: AMotionEvent) -> Bool { false }
    func onContextClick(_ e: AMotionEvent) -> Bool { false }
}

// MARK: - GestureDetector

final class AGestureDetector {
    typealias OnGestureListener = AOnGestureListener
    typealias OnDoubleTapListener = AOnDoubleTapListener
    typealias OnContextClickListener = AOnContextClickListener
    typealias SimpleOnGestureListener = ASimpleOnGestureListener

    private var mTouchSlopSquare = 0
    private var mDoubleTapTouchSlopSquare = 0
    private var mDoubleTapSlopSquare = 0
    private var mAmbiguousGestureMultiplier: Float = 0
    private var mMinimumFlingVelocity = 0
    private var mMaximumFlingVelocity = 0

    private static let LONGPRESS_TIMEOUT = AViewConfiguration.getLongPressTimeout()
    private static let TAP_TIMEOUT = AViewConfiguration.getTapTimeout()
    private static let DOUBLE_TAP_TIMEOUT = AViewConfiguration.getDoubleTapTimeout()
    private static let DOUBLE_TAP_MIN_TIME = AViewConfiguration.getDoubleTapMinTime()

    private let mHandler: AHandler
    private let mListener: AOnGestureListener
    private var mDoubleTapListener: AOnDoubleTapListener?
    private var mContextClickListener: AOnContextClickListener?

    private var mStillDown = false
    private var mDeferConfirmSingleTap = false
    private var mInLongPress = false
    private var mInContextClick = false
    private var mAlwaysInTapRegion = false
    private var mAlwaysInBiggerTapRegion = false
    private var mIgnoreNextUpEvent = false

    private var mCurrentDownEvent: AMotionEvent?
    private var mCurrentMotionEvent: AMotionEvent?
    private var mPreviousUpEvent: AMotionEvent?

    /// True when the user is still touching for the second tap (down, move, and up events).
    private var mIsDoubleTapping = false

    private var mLastFocusX: Float = 0
    private var mLastFocusY: Float = 0
    private var mDownFocusX: Float = 0
    private var mDownFocusY: Float = 0

    private var mIsLongpressEnabled = true

    /// Determines speed during touch scrolling.
    private var mVelocityTracker: AVelocityTracker?

    // The three handler messages of GestureHandler (SHOW_PRESS, LONG_PRESS, TAP) as removable runnables.
    private var showPressMessage: ARunnable!
    private var longPressMessage: ARunnable!
    private var tapMessage: ARunnable!

    /// GestureDetector(Context, OnGestureListener).
    convenience init(_ listener: AOnGestureListener) {
        self.init(listener, nil)
    }

    /// GestureDetector(Context, OnGestureListener) with the context argument kept for call-site fidelity.
    convenience init(_ context: Any?, _ listener: AOnGestureListener) {
        self.init(listener, nil)
    }

    /// GestureDetector(Context, OnGestureListener, Handler).
    init(_ listener: AOnGestureListener, _ handler: AHandler?) {
        mHandler = handler ?? AHandler()
        mListener = listener
        if let dt = listener as? AOnDoubleTapListener {
            setOnDoubleTapListener(dt)
        }
        if let cc = listener as? AOnContextClickListener {
            setContextClickListener(cc)
        }
        showPressMessage = ARunnable { [weak self] in
            guard let self = self, let down = self.mCurrentDownEvent else { return }
            self.mListener.onShowPress(down)
        }
        longPressMessage = ARunnable { [weak self] in
            self?.dispatchLongPress()
        }
        tapMessage = ARunnable { [weak self] in
            guard let self = self else { return }
            // If the user's finger is still down, do not count it as a tap
            if let dt = self.mDoubleTapListener {
                if !self.mStillDown {
                    if let down = self.mCurrentDownEvent { _ = dt.onSingleTapConfirmed(down) }
                } else {
                    self.mDeferConfirmSingleTap = true
                }
            }
        }
        initConfiguration()
    }

    private func initConfiguration() {
        mIsLongpressEnabled = true
        let configuration = AViewConfiguration.get()
        let touchSlop = configuration.scaledTouchSlop
        let doubleTapTouchSlop = configuration.scaledDoubleTapTouchSlop
        let doubleTapSlop = configuration.scaledDoubleTapSlop
        mMinimumFlingVelocity = configuration.scaledMinimumFlingVelocity
        mMaximumFlingVelocity = configuration.scaledMaximumFlingVelocity
        mAmbiguousGestureMultiplier = configuration.scaledAmbiguousGestureMultiplier
        mTouchSlopSquare = touchSlop * touchSlop
        mDoubleTapTouchSlopSquare = doubleTapTouchSlop * doubleTapTouchSlop
        mDoubleTapSlopSquare = doubleTapSlop * doubleTapSlop
    }

    func setOnDoubleTapListener(_ onDoubleTapListener: AOnDoubleTapListener?) {
        mDoubleTapListener = onDoubleTapListener
    }

    func setContextClickListener(_ onContextClickListener: AOnContextClickListener?) {
        mContextClickListener = onContextClickListener
    }

    /// setIsLongpressEnabled / isLongpressEnabled.
    var isLongpressEnabled: Bool {
        get { mIsLongpressEnabled }
        set { mIsLongpressEnabled = newValue }
    }
    func setIsLongpressEnabled(_ isLongpressEnabled: Bool) { mIsLongpressEnabled = isLongpressEnabled }

    @discardableResult
    func onTouchEvent(_ ev: AMotionEvent) -> Bool {
        let action = ev.action

        mCurrentMotionEvent = AMotionEvent.obtain(ev)

        if mVelocityTracker == nil {
            mVelocityTracker = AVelocityTracker.obtain()
        }
        mVelocityTracker!.addMovement(ev)

        let pointerUp = (action & AMotionEvent.ACTION_MASK) == AMotionEvent.ACTION_POINTER_UP
        let skipIndex = pointerUp ? ev.actionIndex : -1
        let isGeneratedGesture = (ev.flags & AMotionEvent.FLAG_IS_GENERATED_GESTURE) != 0

        // Determine focal point
        var sumX: Float = 0, sumY: Float = 0
        let count = ev.pointerCount
        for i in 0..<count {
            if skipIndex == i { continue }
            sumX += ev.getX(i)
            sumY += ev.getY(i)
        }
        let div = pointerUp ? count - 1 : count
        let focusX = sumX / Float(div)
        let focusY = sumY / Float(div)

        var handled = false

        switch action & AMotionEvent.ACTION_MASK {
        case AMotionEvent.ACTION_POINTER_DOWN:
            mLastFocusX = focusX
            mDownFocusX = focusX
            mLastFocusY = focusY
            mDownFocusY = focusY
            // Cancel long press and taps
            cancelTaps()

        case AMotionEvent.ACTION_POINTER_UP:
            mLastFocusX = focusX
            mDownFocusX = focusX
            mLastFocusY = focusY
            mDownFocusY = focusY

            // Check the dot product of current velocities.
            // If the pointer that left was opposing another velocity vector, clear.
            let vt = mVelocityTracker!
            vt.computeCurrentVelocity(1000, Float(mMaximumFlingVelocity))
            let upIndex = ev.actionIndex
            let id1 = ev.getPointerId(upIndex)
            let x1 = vt.getXVelocity(id1)
            let y1 = vt.getYVelocity(id1)
            for i in 0..<count {
                if i == upIndex { continue }
                let id2 = ev.getPointerId(i)
                let x = x1 * vt.getXVelocity(id2)
                let y = y1 * vt.getYVelocity(id2)
                let dot = x + y
                if dot < 0 {
                    vt.clear()
                    break
                }
            }

        case AMotionEvent.ACTION_DOWN:
            if let dt = mDoubleTapListener {
                let hadTapMessage = mHandler.hasCallbacks(tapMessage)
                if hadTapMessage { mHandler.removeCallbacks(tapMessage) }
                if let down = mCurrentDownEvent, let up = mPreviousUpEvent, hadTapMessage,
                   isConsideredDoubleTap(down, up, ev) {
                    // This is a second tap
                    mIsDoubleTapping = true
                    // Give a callback with the first tap of the double-tap
                    handled = dt.onDoubleTap(down) || handled
                    // Give a callback with down event of the double-tap
                    handled = dt.onDoubleTapEvent(ev) || handled
                } else {
                    // This is a first tap
                    mHandler.postDelayed(tapMessage, Int64(AGestureDetector.DOUBLE_TAP_TIMEOUT))
                }
            }

            mLastFocusX = focusX
            mDownFocusX = focusX
            mLastFocusY = focusY
            mDownFocusY = focusY
            let down = AMotionEvent.obtain(ev)
            mCurrentDownEvent = down
            mAlwaysInTapRegion = true
            mAlwaysInBiggerTapRegion = true
            mStillDown = true
            mInLongPress = false
            mDeferConfirmSingleTap = false

            if mIsLongpressEnabled {
                mHandler.removeCallbacks(longPressMessage)
                mHandler.postAtTime(longPressMessage,
                                    down.downTime + Int64(AViewConfiguration.getLongPressTimeout()))
            }
            mHandler.postAtTime(showPressMessage, down.downTime + Int64(AGestureDetector.TAP_TIMEOUT))
            handled = mListener.onDown(ev) || handled

        case AMotionEvent.ACTION_MOVE:
            if mInLongPress || mInContextClick {
                break
            }

            let motionClassification = ev.classification
            let hasPendingLongPress = mHandler.hasCallbacks(longPressMessage)

            let scrollX = mLastFocusX - focusX
            let scrollY = mLastFocusY - focusY
            if mIsDoubleTapping {
                // Give the move events of the double-tap
                handled = mDoubleTapListener!.onDoubleTapEvent(ev) || handled
            } else if mAlwaysInTapRegion {
                let deltaX = AViewConfiguration.f2i(focusX - mDownFocusX)
                let deltaY = AViewConfiguration.f2i(focusY - mDownFocusY)
                let distance = (deltaX &* deltaX) &+ (deltaY &* deltaY)
                var slopSquare = isGeneratedGesture ? 0 : mTouchSlopSquare

                let ambiguousGesture = motionClassification == AMotionEvent.CLASSIFICATION_AMBIGUOUS_GESTURE
                let shouldInhibitDefaultAction = hasPendingLongPress && ambiguousGesture
                if shouldInhibitDefaultAction {
                    // Inhibit default long press
                    if distance > slopSquare {
                        mHandler.removeCallbacks(longPressMessage)
                        let longPressTimeout = Int64(AViewConfiguration.getLongPressTimeout())
                        mHandler.postAtTime(longPressMessage,
                                            ev.downTime + Int64(Float(longPressTimeout) * mAmbiguousGestureMultiplier))
                    }
                    // Inhibit default scroll. If a gesture is ambiguous, we prevent scroll until the gesture is
                    // resolved. (int *= float*float, as Java compound assignment.)
                    slopSquare = AViewConfiguration.f2i(Float(slopSquare) * (mAmbiguousGestureMultiplier * mAmbiguousGestureMultiplier))
                }

                if distance > slopSquare {
                    handled = mListener.onScroll(mCurrentDownEvent, ev, scrollX, scrollY)
                    mLastFocusX = focusX
                    mLastFocusY = focusY
                    mAlwaysInTapRegion = false
                    mHandler.removeCallbacks(tapMessage)
                    mHandler.removeCallbacks(showPressMessage)
                    mHandler.removeCallbacks(longPressMessage)
                }
                let doubleTapSlopSquare = isGeneratedGesture ? 0 : mDoubleTapTouchSlopSquare
                if distance > doubleTapSlopSquare {
                    mAlwaysInBiggerTapRegion = false
                }
            } else if abs(scrollX) >= 1 || abs(scrollY) >= 1 {
                handled = mListener.onScroll(mCurrentDownEvent, ev, scrollX, scrollY)
                mLastFocusX = focusX
                mLastFocusY = focusY
            }
            let deepPress = motionClassification == AMotionEvent.CLASSIFICATION_DEEP_PRESS
            if deepPress && hasPendingLongPress {
                mHandler.removeCallbacks(longPressMessage)
                mHandler.post(longPressMessage)
            }

        case AMotionEvent.ACTION_UP:
            mStillDown = false
            let currentUpEvent = AMotionEvent.obtain(ev)
            if mIsDoubleTapping {
                // Finally, give the up event of the double-tap
                handled = mDoubleTapListener!.onDoubleTapEvent(ev) || handled
            } else if mInLongPress {
                mHandler.removeCallbacks(tapMessage)
                mInLongPress = false
            } else if mAlwaysInTapRegion && !mIgnoreNextUpEvent {
                handled = mListener.onSingleTapUp(ev)
                if mDeferConfirmSingleTap, let dt = mDoubleTapListener {
                    _ = dt.onSingleTapConfirmed(ev)
                }
            } else if !mIgnoreNextUpEvent {
                // A fling must travel the minimum tap distance
                let velocityTracker = mVelocityTracker!
                let pointerId = ev.getPointerId(0)
                velocityTracker.computeCurrentVelocity(1000, Float(mMaximumFlingVelocity))
                let velocityY = velocityTracker.getYVelocity(pointerId)
                let velocityX = velocityTracker.getXVelocity(pointerId)

                if abs(velocityY) > Float(mMinimumFlingVelocity) || abs(velocityX) > Float(mMinimumFlingVelocity) {
                    handled = mListener.onFling(mCurrentDownEvent, ev, velocityX, velocityY)
                }
            }
            // Hold the event we obtained above - listeners may have changed the original.
            mPreviousUpEvent = currentUpEvent
            if let vt = mVelocityTracker {
                // This may have been cleared when we called out to the application above.
                vt.recycle()
                mVelocityTracker = nil
            }
            mIsDoubleTapping = false
            mDeferConfirmSingleTap = false
            mIgnoreNextUpEvent = false
            mHandler.removeCallbacks(showPressMessage)
            mHandler.removeCallbacks(longPressMessage)

        case AMotionEvent.ACTION_CANCEL:
            cancel()

        default:
            break
        }

        return handled
    }

    private func cancel() {
        mHandler.removeCallbacks(showPressMessage)
        mHandler.removeCallbacks(longPressMessage)
        mHandler.removeCallbacks(tapMessage)
        mVelocityTracker?.recycle()
        mVelocityTracker = nil
        mIsDoubleTapping = false
        mStillDown = false
        mAlwaysInTapRegion = false
        mAlwaysInBiggerTapRegion = false
        mDeferConfirmSingleTap = false
        mInLongPress = false
        mInContextClick = false
        mIgnoreNextUpEvent = false
    }

    private func cancelTaps() {
        mHandler.removeCallbacks(showPressMessage)
        mHandler.removeCallbacks(longPressMessage)
        mHandler.removeCallbacks(tapMessage)
        mIsDoubleTapping = false
        mAlwaysInTapRegion = false
        mAlwaysInBiggerTapRegion = false
        mDeferConfirmSingleTap = false
        mInLongPress = false
        mInContextClick = false
        mIgnoreNextUpEvent = false
    }

    private func isConsideredDoubleTap(_ firstDown: AMotionEvent, _ firstUp: AMotionEvent,
                                       _ secondDown: AMotionEvent) -> Bool {
        if !mAlwaysInBiggerTapRegion {
            return false
        }

        let deltaTime = secondDown.eventTime - firstUp.eventTime
        if deltaTime > Int64(AGestureDetector.DOUBLE_TAP_TIMEOUT) || deltaTime < Int64(AGestureDetector.DOUBLE_TAP_MIN_TIME) {
            return false
        }

        let deltaX = AViewConfiguration.f2i(firstDown.x) - AViewConfiguration.f2i(secondDown.x)
        let deltaY = AViewConfiguration.f2i(firstDown.y) - AViewConfiguration.f2i(secondDown.y)
        let isGeneratedGesture = (firstDown.flags & AMotionEvent.FLAG_IS_GENERATED_GESTURE) != 0
        let slopSquare = isGeneratedGesture ? 0 : mDoubleTapSlopSquare
        return (deltaX &* deltaX &+ deltaY &* deltaY) < slopSquare
    }

    private func dispatchLongPress() {
        mHandler.removeCallbacks(tapMessage)
        mDeferConfirmSingleTap = false
        mInLongPress = true
        if let down = mCurrentDownEvent {
            mListener.onLongPress(down)
        }
    }
}
