import Foundation
import UIKit

// android.animation (Animator, ValueAnimator, ObjectAnimator, AnimationHandler, keyframes, AnimatorListenerAdapter),
// android.view.animation interpolators and android.view.ViewPropertyAnimator (DESIGN 4.3, VIEW-API "Animators").
// Translated statement by statement from the AOSP API 37 sources. Behaviour the game relies on:
// - start() with no start delay calls onAnimationStart and delivers a synchronous update (setCurrentPlayTime(0),
//   fraction 0) before it returns; the first frame after start() sets the start time to that frame's time (and
//   delivers fraction 0 again); later frames use (frameTime - startTime) / duration.
// - cancel() on a started animator calls onAnimationCancel then onAnimationEnd; cancel() again does nothing.
// - end() jumps to the end value, then onAnimationEnd.
// - isRunning is false during a start delay; isStarted is true from start() to the end.
// - Every animator is driven by AAnimationHandler, a single Choreographer frame callback, so animators and
//   View.postOnAnimation runnables keep Android's order inside a frame. An animator started during a frame gets
//   its first frame in that frame only if the animation handler's callback has not run yet in it.
// - The default interpolator is AccelerateDecelerate: (float)(cos((t + 1) * PI) / 2.0) + 0.5f.
// - ViewPropertyAnimator: default 300 ms and AccelerateDecelerate (the ValueAnimator defaults), start() starts
//   synchronously, without start() it starts in the next frame's ANIMATION phase; withEndAction does not run when
//   the animation is cancelled; a new animation of a property cancels that property in the running animation.
// The system "animator duration scale" is 1 (DESIGN: ignore the Android developer setting).

// MARK: - Java numeric conversions used by the animation code

/// Java `(int) float`: truncation toward zero, NaN -> 0, saturating.
private func javaF2I(_ value: Float) -> Int32 {
    if value.isNaN {
        return 0
    }
    if value >= 2147483648.0 {
        return Int32.max
    }
    if value <= -2147483648.0 {
        return Int32.min
    }
    return Int32(value)
}

/// Java `(long) float`.
private func javaF2L(_ value: Float) -> Int64 {
    if value.isNaN {
        return 0
    }
    if value >= 9223372036854775808.0 {
        return Int64.max
    }
    if value <= -9223372036854775808.0 {
        return Int64.min
    }
    return Int64(value)
}

/// Java `(int) double`.
private func javaD2I(_ value: Double) -> Int32 {
    if value.isNaN {
        return 0
    }
    if value >= 2147483648.0 {
        return Int32.max
    }
    if value <= -2147483648.0 {
        return Int32.min
    }
    return Int32(value)
}

/// Java `Math.min(float, float)` (NaN and -0.0 rules).
private func javaMinF(_ a: Float, _ b: Float) -> Float {
    if a.isNaN {
        return a
    }
    if a == 0 && b == 0 && b.bitPattern == (-Float(0)).bitPattern {
        return b
    }
    return a <= b ? a : b
}

// MARK: - Animatable view

/// The view properties that the property animators drive (AView conforms to it).
protocol AAnimatableView: AnyObject {
    var alpha: CGFloat { get set }
    var translationX: Float { get set }
    var translationY: Float { get set }
    var scaleX: Float { get set }
    var scaleY: Float { get set }
    var rotation: Float { get set }
    var x: Float { get set }
    var y: Float { get set }
}

/// The android.util.Property constants of android.view.View for ObjectAnimator:
/// `ObjectAnimator.ofFloat(v, View.TRANSLATION_Y, 0f, 4f)` -> `AObjectAnimator.ofFloat(v, AViewProperty.TRANSLATION_Y, 0, 4)`.
enum AViewProperty {
    case ALPHA
    case TRANSLATION_X
    case TRANSLATION_Y
    case SCALE_X
    case SCALE_Y
    case ROTATION
    case X
    case Y

    /// `Property.getName()`.
    var name: String {
        switch self {
        case .ALPHA: return "alpha"
        case .TRANSLATION_X: return "translationX"
        case .TRANSLATION_Y: return "translationY"
        case .SCALE_X: return "scaleX"
        case .SCALE_Y: return "scaleY"
        case .ROTATION: return "rotation"
        case .X: return "x"
        case .Y: return "y"
        }
    }

    func get(_ view: AAnimatableView) -> Float {
        switch self {
        case .ALPHA: return Float(view.alpha)
        case .TRANSLATION_X: return view.translationX
        case .TRANSLATION_Y: return view.translationY
        case .SCALE_X: return view.scaleX
        case .SCALE_Y: return view.scaleY
        case .ROTATION: return view.rotation
        case .X: return view.x
        case .Y: return view.y
        }
    }

    func set(_ view: AAnimatableView, _ value: Float) {
        switch self {
        case .ALPHA: view.alpha = CGFloat(value)
        case .TRANSLATION_X: view.translationX = value
        case .TRANSLATION_Y: view.translationY = value
        case .SCALE_X: view.scaleX = value
        case .SCALE_Y: view.scaleY = value
        case .ROTATION: view.rotation = value
        case .X: view.x = value
        case .Y: view.y = value
        }
    }
}

// MARK: - Interpolators (android.view.animation)

/// android.animation.TimeInterpolator / android.view.animation.Interpolator.
protocol ATimeInterpolator: AnyObject {
    func getInterpolation(_ input: Float) -> Float
}

typealias AInterpolator = ATimeInterpolator

final class ALinearInterpolator: ATimeInterpolator {
    init() {}

    func getInterpolation(_ input: Float) -> Float {
        return input
    }
}

final class AAccelerateDecelerateInterpolator: ATimeInterpolator {
    init() {}

    func getInterpolation(_ input: Float) -> Float {
        return Float(cos(Double(input + 1) * Double.pi) / 2.0) + 0.5
    }
}

final class ADecelerateInterpolator: ATimeInterpolator {
    private var mFactor: Float = 1.0

    init() {}

    init(_ factor: Float) {
        mFactor = factor
    }

    func getInterpolation(_ input: Float) -> Float {
        let result: Float
        if mFactor == 1.0 {
            result = 1.0 - (1.0 - input) * (1.0 - input)
        } else {
            result = Float(1.0 - pow(Double(1.0 - input), Double(2 * mFactor)))
        }
        return result
    }
}

final class AAccelerateInterpolator: ATimeInterpolator {
    private let mFactor: Float
    private let mDoubleFactor: Double

    init() {
        mFactor = 1.0
        mDoubleFactor = 2.0
    }

    init(_ factor: Float) {
        mFactor = factor
        mDoubleFactor = Double(2 * factor)
    }

    func getInterpolation(_ input: Float) -> Float {
        if mFactor == 1.0 {
            return input * input
        } else {
            return Float(pow(Double(input), mDoubleFactor))
        }
    }
}

final class AOvershootInterpolator: ATimeInterpolator {
    private let mTension: Float

    init() {
        mTension = 2.0
    }

    init(_ tension: Float) {
        mTension = tension
    }

    func getInterpolation(_ input: Float) -> Float {
        // _o(t) = t * t * ((tension + 1) * t + tension)
        // o(t) = _o(t - 1) + 1
        var t = input
        t -= 1.0
        return t * t * ((mTension + 1) * t + mTension) + 1.0
    }
}

final class AAnticipateInterpolator: ATimeInterpolator {
    private let mTension: Float

    init() {
        mTension = 2.0
    }

    init(_ tension: Float) {
        mTension = tension
    }

    func getInterpolation(_ t: Float) -> Float {
        // a(t) = t * t * ((tension + 1) * t - tension)
        return t * t * ((mTension + 1) * t - mTension)
    }
}

final class AAnticipateOvershootInterpolator: ATimeInterpolator {
    private let mTension: Float

    init() {
        mTension = 2.0 * 1.5
    }

    init(_ tension: Float) {
        mTension = tension * 1.5
    }

    init(_ tension: Float, _ extraTension: Float) {
        mTension = tension * extraTension
    }

    private static func a(_ t: Float, _ s: Float) -> Float {
        return t * t * ((s + 1) * t - s)
    }

    private static func o(_ t: Float, _ s: Float) -> Float {
        return t * t * ((s + 1) * t + s)
    }

    func getInterpolation(_ t: Float) -> Float {
        if t < 0.5 {
            return 0.5 * AAnticipateOvershootInterpolator.a(t * 2.0, mTension)
        } else {
            return 0.5 * (AAnticipateOvershootInterpolator.o(t * 2.0 - 2.0, mTension) + 2.0)
        }
    }
}

final class ABounceInterpolator: ATimeInterpolator {
    init() {}

    private static func bounce(_ t: Float) -> Float {
        return t * t * 8.0
    }

    func getInterpolation(_ input: Float) -> Float {
        var t = input
        t *= 1.1226
        if t < 0.3535 {
            return ABounceInterpolator.bounce(t)
        } else if t < 0.7408 {
            return ABounceInterpolator.bounce(t - 0.54719) + 0.7
        } else if t < 0.9644 {
            return ABounceInterpolator.bounce(t - 0.8526) + 0.9
        } else {
            return ABounceInterpolator.bounce(t - 1.0435) + 0.95
        }
    }
}

final class ACycleInterpolator: ATimeInterpolator {
    private let mCycles: Float

    init(_ cycles: Float) {
        mCycles = cycles
    }

    func getInterpolation(_ input: Float) -> Float {
        return Float(sin(Double(2 * mCycles) * Double.pi * Double(input)))
    }
}

// MARK: - Listeners

/// `Animator.AnimatorListener`.
protocol AAnimatorListener: AnyObject {
    func onAnimationStart(_ animation: AAnimator)
    func onAnimationEnd(_ animation: AAnimator)
    func onAnimationCancel(_ animation: AAnimator)
    func onAnimationRepeat(_ animation: AAnimator)
}

/// `Animator.AnimatorPauseListener`.
protocol AAnimatorPauseListener: AnyObject {
    func onAnimationPause(_ animation: AAnimator)
    func onAnimationResume(_ animation: AAnimator)
}

/// `android.animation.AnimatorListenerAdapter`: subclass it and override, or pass closures.
class AAnimatorListenerAdapter: AAnimatorListener, AAnimatorPauseListener {
    private let onStartBlock: ((AAnimator) -> Void)?
    private let onEndBlock: ((AAnimator) -> Void)?
    private let onCancelBlock: ((AAnimator) -> Void)?
    private let onRepeatBlock: ((AAnimator) -> Void)?

    init(onStart: ((AAnimator) -> Void)? = nil, onEnd: ((AAnimator) -> Void)? = nil,
         onCancel: ((AAnimator) -> Void)? = nil, onRepeat: ((AAnimator) -> Void)? = nil) {
        onStartBlock = onStart
        onEndBlock = onEnd
        onCancelBlock = onCancel
        onRepeatBlock = onRepeat
    }

    func onAnimationStart(_ animation: AAnimator) {
        onStartBlock?(animation)
    }

    func onAnimationEnd(_ animation: AAnimator) {
        onEndBlock?(animation)
    }

    func onAnimationCancel(_ animation: AAnimator) {
        onCancelBlock?(animation)
    }

    func onAnimationRepeat(_ animation: AAnimator) {
        onRepeatBlock?(animation)
    }

    func onAnimationPause(_ animation: AAnimator) {
    }

    func onAnimationResume(_ animation: AAnimator) {
    }
}

/// `ValueAnimator.AnimatorUpdateListener`: a reference type so it can be removed by identity.
final class AAnimatorUpdateListener {
    private let block: (AValueAnimator) -> Void

    init(_ block: @escaping (AValueAnimator) -> Void) {
        self.block = block
    }

    func onAnimationUpdate(_ animation: AValueAnimator) {
        block(animation)
    }
}

// MARK: - Animator

/// `android.animation.Animator`.
class AAnimator {
    static let DURATION_INFINITE: Int64 = -1

    var mListeners: [AAnimatorListener]? = nil
    var mPauseListeners: [AAnimatorPauseListener]? = nil
    var mPaused = false
    var mStartListenersCalled = false

    init() {}

    func start() {
    }

    func cancel() {
    }

    func end() {
    }

    func pause() {
        // We only want to pause started Animators or animators that setCurrentPlayTime() have been called on.
        // mStartListenerCalled will be true if seek has happened.
        if (isStarted || mStartListenersCalled) && !mPaused {
            mPaused = true
            notifyPauseListeners(true)
        }
    }

    func resume() {
        if mPaused {
            mPaused = false
            notifyPauseListeners(false)
        }
    }

    var isPaused: Bool {
        return mPaused
    }

    var startDelay: Int64 {
        get { return 0 }
        set {}
    }

    var duration: Int64 {
        get { return 0 }
        set {}
    }

    var interpolator: ATimeInterpolator? {
        get { return nil }
        set {}
    }

    @discardableResult
    func setDuration(_ ms: Int64) -> Self {
        duration = ms
        return self
    }

    func setStartDelay(_ startDelay: Int64) {
        self.startDelay = startDelay
    }

    func setInterpolator(_ value: ATimeInterpolator?) {
        interpolator = value
    }

    var totalDuration: Int64 {
        let duration = self.duration
        if duration == AAnimator.DURATION_INFINITE {
            return AAnimator.DURATION_INFINITE
        } else {
            return startDelay &+ duration
        }
    }

    var isRunning: Bool {
        return false
    }

    /// Default: isRunning (ValueAnimator overrides it).
    var isStarted: Bool {
        return isRunning
    }

    func addListener(_ listener: AAnimatorListener) {
        if mListeners == nil {
            mListeners = []
        }
        mListeners!.append(listener)
    }

    func removeListener(_ listener: AAnimatorListener) {
        guard var list = mListeners else { return }
        if let index = list.firstIndex(where: { $0 === listener }) {
            list.remove(at: index)
        }
        mListeners = list.isEmpty ? nil : list
    }

    /// `getListeners()`.
    var listeners: [AAnimatorListener]? {
        return mListeners
    }

    func addPauseListener(_ listener: AAnimatorPauseListener) {
        if mPauseListeners == nil {
            mPauseListeners = []
        }
        mPauseListeners!.append(listener)
    }

    func removePauseListener(_ listener: AAnimatorPauseListener) {
        guard var list = mPauseListeners else { return }
        if let index = list.firstIndex(where: { $0 === listener }) {
            list.remove(at: index)
        }
        mPauseListeners = list.isEmpty ? nil : list
    }

    func removeAllListeners() {
        if mListeners != nil {
            mListeners = nil
        }
        if mPauseListeners != nil {
            mPauseListeners = nil
        }
    }

    /// `Animator.AnimatorCaller`.
    enum AnimatorCall {
        case ON_START
        case ON_END
        case ON_CANCEL
        case ON_REPEAT
    }

    /// `notifyListeners` / `callOnList`: iterates a snapshot of the listeners.
    func notifyListeners(_ notification: AnimatorCall) {
        guard let list = mListeners, !list.isEmpty else { return }
        for listener in list {
            switch notification {
            case .ON_START: listener.onAnimationStart(self)
            case .ON_END: listener.onAnimationEnd(self)
            case .ON_CANCEL: listener.onAnimationCancel(self)
            case .ON_REPEAT: listener.onAnimationRepeat(self)
            }
        }
    }

    func notifyPauseListeners(_ pause: Bool) {
        guard let list = mPauseListeners, !list.isEmpty else { return }
        for listener in list {
            if pause {
                listener.onAnimationPause(self)
            } else {
                listener.onAnimationResume(self)
            }
        }
    }

    func notifyStartListeners(_ isReversing: Bool) {
        let startListenersCalled = mStartListenersCalled
        mStartListenersCalled = true
        if mListeners != nil && !startListenersCalled {
            notifyListeners(.ON_START)
        }
    }

    func notifyEndListeners(_ isReversing: Bool) {
        let startListenersCalled = mStartListenersCalled
        mStartListenersCalled = false
        if mListeners != nil && startListenersCalled {
            notifyListeners(.ON_END)
        }
    }

    /// `completeEndAnimation` (Animator.sPostNotifyEndListenerEnabled is off for apps: end listeners run at once).
    func completeEndAnimation(_ isReversing: Bool) {
        notifyEndListeners(isReversing)
    }
}

// MARK: - Keyframes / PropertyValuesHolder

/// The PropertyValuesHolder + FloatKeyframeSet / IntKeyframeSet of one animated value. A primitive float/int holder
/// has no TypeEvaluator (PropertyValuesHolder.init() only adds one for Float.class / Integer.class), so values are
/// `prev + fraction * (next - prev)` (float) and `prev + (int)(fraction * (next - prev))` (int).
private final class APropertyValuesHolder {
    enum Kind {
        case FLOAT
        case INT
    }

    struct Keyframe {
        var fraction: Float
        var floatValue: Float
        var intValue: Int32
        var hasValue: Bool
        var valueWasSetOnStart: Bool
    }

    private(set) var kind: Kind
    private var keyframes: [Keyframe] = []
    let property: AViewProperty?
    private(set) var floatAnimatedValue: Float = 0
    private(set) var intAnimatedValue: Int32 = 0

    init(property: AViewProperty?, floatValues: [Float]) {
        self.property = property
        kind = .FLOAT
        setFloatValues(floatValues)
    }

    init(intValues: [Int32]) {
        property = nil
        kind = .INT
        setIntValues(intValues)
    }

    /// `KeyframeSet.ofFloat`: one value animates from an unset keyframe (0, or the property's start value).
    func setFloatValues(_ values: [Float]) {
        kind = .FLOAT
        let numKeyframes = values.count
        precondition(numKeyframes > 0, "Animator values must not be empty")
        var badValue = false
        var frames: [Keyframe] = []
        if numKeyframes == 1 {
            frames.append(Keyframe(fraction: 0, floatValue: 0, intValue: 0, hasValue: false, valueWasSetOnStart: false))
            frames.append(Keyframe(fraction: 1, floatValue: values[0], intValue: 0, hasValue: true, valueWasSetOnStart: false))
            if values[0].isNaN {
                badValue = true
            }
        } else {
            frames.append(Keyframe(fraction: 0, floatValue: values[0], intValue: 0, hasValue: true, valueWasSetOnStart: false))
            for i in 1..<numKeyframes {
                frames.append(Keyframe(fraction: Float(i) / Float(numKeyframes - 1), floatValue: values[i], intValue: 0,
                                       hasValue: true, valueWasSetOnStart: false))
                if values[i].isNaN {
                    badValue = true
                }
            }
        }
        if badValue {
            ALog.w("Animator", "Bad value (NaN) in float animator")
        }
        keyframes = frames
    }

    /// `KeyframeSet.ofInt`.
    func setIntValues(_ values: [Int32]) {
        kind = .INT
        let numKeyframes = values.count
        precondition(numKeyframes > 0, "Animator values must not be empty")
        var frames: [Keyframe] = []
        if numKeyframes == 1 {
            frames.append(Keyframe(fraction: 0, floatValue: 0, intValue: 0, hasValue: false, valueWasSetOnStart: false))
            frames.append(Keyframe(fraction: 1, floatValue: 0, intValue: values[0], hasValue: true, valueWasSetOnStart: false))
        } else {
            frames.append(Keyframe(fraction: 0, floatValue: 0, intValue: values[0], hasValue: true, valueWasSetOnStart: false))
            for i in 1..<numKeyframes {
                frames.append(Keyframe(fraction: Float(i) / Float(numKeyframes - 1), floatValue: 0, intValue: values[i],
                                       hasValue: true, valueWasSetOnStart: false))
            }
        }
        keyframes = frames
    }

    /// `PropertyValuesHolder.init()`: nothing to set up for primitive float/int values.
    func initHolder() {
    }

    /// `setupSetterAndGetter(target)` for a Property: keyframes without a value take the property's current value.
    func setupSetterAndGetter(_ target: AAnimatableView) {
        guard let property = property, kind == .FLOAT else { return }
        var testValue: Float? = nil
        for i in keyframes.indices where !keyframes[i].hasValue || keyframes[i].valueWasSetOnStart {
            if testValue == nil {
                testValue = property.get(target)
            }
            keyframes[i].floatValue = testValue!
            keyframes[i].hasValue = true
            keyframes[i].valueWasSetOnStart = true
        }
    }

    func calculateValue(_ fraction: Float) {
        switch kind {
        case .FLOAT:
            floatAnimatedValue = getFloatValue(fraction)
        case .INT:
            intAnimatedValue = getIntValue(fraction)
        }
    }

    var animatedValue: Any {
        switch kind {
        case .FLOAT:
            return floatAnimatedValue
        case .INT:
            return Int(intAnimatedValue)
        }
    }

    func setAnimatedValue(_ target: AAnimatableView?) {
        guard let property = property, let target = target, kind == .FLOAT else { return }
        property.set(target, floatAnimatedValue)
    }

    /// `FloatKeyframeSet.getFloatValue` (no per-keyframe interpolators, no evaluator).
    private func getFloatValue(_ fraction: Float) -> Float {
        let numKeyframes = keyframes.count
        if fraction <= 0 {
            let prev = keyframes[0]
            let next = keyframes[1]
            let intervalFraction = (fraction - prev.fraction) / (next.fraction - prev.fraction)
            return prev.floatValue + intervalFraction * (next.floatValue - prev.floatValue)
        } else if fraction >= 1 {
            let prev = keyframes[numKeyframes - 2]
            let next = keyframes[numKeyframes - 1]
            let intervalFraction = (fraction - prev.fraction) / (next.fraction - prev.fraction)
            return prev.floatValue + intervalFraction * (next.floatValue - prev.floatValue)
        }
        var prev = keyframes[0]
        for i in 1..<numKeyframes {
            let next = keyframes[i]
            if fraction < next.fraction {
                let intervalFraction = (fraction - prev.fraction) / (next.fraction - prev.fraction)
                return prev.floatValue + intervalFraction * (next.floatValue - prev.floatValue)
            }
            prev = next
        }
        // shouldn't get here
        return keyframes[numKeyframes - 1].floatValue
    }

    /// `IntKeyframeSet.getIntValue` (Java int arithmetic).
    private func getIntValue(_ fraction: Float) -> Int32 {
        let numKeyframes = keyframes.count
        if fraction <= 0 {
            let prev = keyframes[0]
            let next = keyframes[1]
            let intervalFraction = (fraction - prev.fraction) / (next.fraction - prev.fraction)
            return prev.intValue &+ javaF2I(intervalFraction * Float(next.intValue &- prev.intValue))
        } else if fraction >= 1 {
            let prev = keyframes[numKeyframes - 2]
            let next = keyframes[numKeyframes - 1]
            let intervalFraction = (fraction - prev.fraction) / (next.fraction - prev.fraction)
            return prev.intValue &+ javaF2I(intervalFraction * Float(next.intValue &- prev.intValue))
        }
        var prev = keyframes[0]
        for i in 1..<numKeyframes {
            let next = keyframes[i]
            if fraction < next.fraction {
                let intervalFraction = (fraction - prev.fraction) / (next.fraction - prev.fraction)
                return prev.intValue &+ javaF2I(intervalFraction * Float(next.intValue &- prev.intValue))
            }
            prev = next
        }
        // shouldn't get here
        return keyframes[numKeyframes - 1].intValue
    }
}

// MARK: - ValueAnimator

/// `android.animation.ValueAnimator`.
class AValueAnimator: AAnimator {
    private static let TAG = "ValueAnimator"
    nonisolated(unsafe) private static var sDurationScale: Float = 1.0
    nonisolated(unsafe) private static let sDefaultInterpolator: ATimeInterpolator = AAccelerateDecelerateInterpolator()

    static let RESTART = 1
    static let REVERSE = 2
    static let INFINITE = -1

    /// `ValueAnimator.setDurationScale` (the system animator duration scale; 1 on iOS).
    static func setDurationScale(_ durationScale: Float) {
        sDurationScale = durationScale
    }

    static func getDurationScale() -> Float {
        return sDurationScale
    }

    static func areAnimatorsEnabled() -> Bool {
        return !(sDurationScale == 0)
    }

    /// `ValueAnimator.getCurrentAnimationsCount()`.
    static func getCurrentAnimationsCount() -> Int {
        return AAnimationHandler.getInstance().getAnimationCount()
    }

    var mStartTime: Int64 = -1
    var mSeekFraction: Float = -1
    private var mPauseTime: Int64 = 0
    private var mResumed = false
    private var mReversing = false
    private var mOverallFraction: Float = 0
    private var mCurrentFraction: Float = 0
    private var mLastFrameTime: Int64 = -1
    private var mFirstFrameTime: Int64 = -1
    private var mRunning = false
    private var mStarted = false
    var mInitialized = false
    private var mAnimationEndRequested = false
    private var mDuration: Int64 = 300
    private var mStartDelay: Int64 = 0
    private var mRepeatCount: Int32 = 0
    private var mRepeatMode: Int32 = 1 // RESTART
    private var mSelfPulse = true
    private var mSuppressSelfPulseRequested = false
    private var mInterpolator: ATimeInterpolator = AValueAnimator.sDefaultInterpolator
    private var mUpdateListeners: [AAnimatorUpdateListener]? = nil
    fileprivate var mValues: [APropertyValuesHolder]? = nil
    private var mDurationScale: Float = -1

    override init() {
        super.init()
    }

    static func ofInt(_ values: Int...) -> AValueAnimator {
        let anim = AValueAnimator()
        anim.setIntValues(array: values)
        return anim
    }

    static func ofFloat(_ values: Float...) -> AValueAnimator {
        let anim = AValueAnimator()
        anim.setFloatValues(array: values)
        return anim
    }

    func setIntValues(_ values: Int...) {
        setIntValues(array: values)
    }

    func setIntValues(array values: [Int]) {
        if values.isEmpty {
            return
        }
        let ints = values.map { Int32(truncatingIfNeeded: $0) }
        if let existing = mValues, !existing.isEmpty {
            existing[0].setIntValues(ints)
        } else {
            setValues([APropertyValuesHolder(intValues: ints)])
        }
        // New property/values/target should cause re-initialization prior to starting
        mInitialized = false
    }

    func setFloatValues(_ values: Float...) {
        setFloatValues(array: values)
    }

    func setFloatValues(array values: [Float]) {
        if values.isEmpty {
            return
        }
        if let existing = mValues, !existing.isEmpty {
            existing[0].setFloatValues(values)
        } else {
            setValues([APropertyValuesHolder(property: nil, floatValues: values)])
        }
        // New property/values/target should cause re-initialization prior to starting
        mInitialized = false
    }

    fileprivate func setValues(_ values: [APropertyValuesHolder]) {
        mValues = values
        // New property/values/target should cause re-initialization prior to starting
        mInitialized = false
    }

    func initAnimation() {
        if !mInitialized {
            if let values = mValues {
                for holder in values {
                    holder.initHolder()
                }
            }
            mInitialized = true
        }
    }

    override var duration: Int64 {
        get {
            return mDuration
        }
        set {
            precondition(newValue >= 0, "Animators cannot have negative duration: \(newValue)")
            mDuration = newValue
        }
    }

    func overrideDurationScale(_ durationScale: Float) {
        mDurationScale = durationScale
    }

    private func resolveDurationScale() -> Float {
        return mDurationScale >= 0 ? mDurationScale : AValueAnimator.sDurationScale
    }

    private func getScaledDuration() -> Int64 {
        return javaF2L(Float(mDuration) * resolveDurationScale())
    }

    override var totalDuration: Int64 {
        if mRepeatCount == Int32(AValueAnimator.INFINITE) {
            return AAnimator.DURATION_INFINITE
        } else {
            return mStartDelay &+ (mDuration &* Int64(mRepeatCount &+ 1))
        }
    }

    func setCurrentPlayTime(_ playTime: Int64) {
        let fraction: Float = mDuration > 0 ? Float(playTime) / Float(mDuration) : 1
        setCurrentFraction(fraction)
    }

    func setCurrentFraction(_ value: Float) {
        initAnimation()
        let fraction = clampFraction(value)
        if isPulsingInternal() {
            let seekTime = javaF2L(Float(getScaledDuration()) * fraction)
            let currentTime = AAnimationUtils.currentAnimationTimeMillis()
            // Only modify the start time when the animation is running. Seek fraction will ensure non-running
            // animations skip to the correct start time.
            mStartTime = currentTime &- seekTime
        } else {
            // If the animation loop hasn't started, or during start delay, the startTime will be adjusted once the
            // delay has passed based on seek fraction.
            mSeekFraction = fraction
        }
        mOverallFraction = fraction
        let currentIterationFraction = getCurrentIterationFraction(fraction, mReversing)
        animateValue(currentIterationFraction)
    }

    private func getCurrentIteration(_ value: Float) -> Int32 {
        let fraction = clampFraction(value)
        // If the overall fraction is a positive integer, we consider the current iteration to be complete. In other
        // words, the fraction for the current iteration would be 1, and the current iteration would be overall
        // fraction - 1.
        var iteration = Double(fraction).rounded(.down)
        if Double(fraction) == iteration && fraction > 0 {
            iteration -= 1
        }
        return javaD2I(iteration)
    }

    private func getCurrentIterationFraction(_ value: Float, _ inReverse: Bool) -> Float {
        let fraction = clampFraction(value)
        let iteration = getCurrentIteration(fraction)
        let currentFraction = fraction - Float(iteration)
        return shouldPlayBackward(iteration, inReverse) ? 1 - currentFraction : currentFraction
    }

    private func clampFraction(_ value: Float) -> Float {
        var fraction = value
        if fraction < 0 {
            fraction = 0
        } else if mRepeatCount != Int32(AValueAnimator.INFINITE) {
            fraction = javaMinF(fraction, Float(mRepeatCount &+ 1))
        }
        return fraction
    }

    private func shouldPlayBackward(_ iteration: Int32, _ inReverse: Bool) -> Bool {
        if iteration > 0 && mRepeatMode == Int32(AValueAnimator.REVERSE)
            && (iteration < (mRepeatCount &+ 1) || mRepeatCount == Int32(AValueAnimator.INFINITE)) {
            // if we were seeked to some other iteration in a reversing animator, figure out the correct direction
            // to start playing based on the iteration
            if inReverse {
                return (iteration % 2) == 0
            } else {
                return (iteration % 2) != 0
            }
        } else {
            return inReverse
        }
    }

    /// `getCurrentPlayTime()` / `setCurrentPlayTime()`.
    var currentPlayTime: Int64 {
        get {
            if !mInitialized || (!mStarted && mSeekFraction < 0) {
                return 0
            }
            if mSeekFraction >= 0 {
                return javaF2L(Float(mDuration) * mSeekFraction)
            }
            var durationScale = resolveDurationScale()
            if durationScale == 0 {
                durationScale = 1
            }
            return javaF2L(Float(AAnimationUtils.currentAnimationTimeMillis() &- mStartTime) / durationScale)
        }
        set {
            setCurrentPlayTime(newValue)
        }
    }

    override var startDelay: Int64 {
        get {
            return mStartDelay
        }
        set {
            var delay = newValue
            // Clamp start delay to non-negative range.
            if delay < 0 {
                ALog.w(AValueAnimator.TAG, "Start delay should always be non-negative")
                delay = 0
            }
            mStartDelay = delay
        }
    }

    /// `getAnimatedValue()`: Float for ofFloat, Int for ofInt (null on Android when no values were set).
    var animatedValue: Any {
        if let values = mValues, !values.isEmpty {
            return values[0].animatedValue
        }
        // Shouldn't get here; should always have values unless ValueAnimator was set up wrong
        return Optional<Float>.none as Any
    }

    func getAnimatedValue() -> Any {
        return animatedValue
    }

    /// `animatedValue as Float`.
    var animatedValueFloat: Float {
        guard let holder = mValues?.first else { return 0 }
        return holder.kind == .FLOAT ? holder.floatAnimatedValue : Float(holder.intAnimatedValue)
    }

    /// `animatedValue as Int`.
    var animatedValueInt: Int {
        guard let holder = mValues?.first else { return 0 }
        return holder.kind == .INT ? Int(holder.intAnimatedValue) : Int(javaF2I(holder.floatAnimatedValue))
    }

    var repeatCount: Int {
        get { return Int(mRepeatCount) }
        set { mRepeatCount = Int32(truncatingIfNeeded: newValue) }
    }

    func setRepeatCount(_ value: Int) {
        repeatCount = value
    }

    var repeatMode: Int {
        get { return Int(mRepeatMode) }
        set { mRepeatMode = Int32(truncatingIfNeeded: newValue) }
    }

    func setRepeatMode(_ value: Int) {
        repeatMode = value
    }

    func addUpdateListener(_ listener: AAnimatorUpdateListener) {
        if mUpdateListeners == nil {
            mUpdateListeners = []
        }
        mUpdateListeners!.append(listener)
    }

    /// Kotlin `addUpdateListener { animator -> ... }`; returns the listener object (for removeUpdateListener).
    @discardableResult
    func addUpdateListener(_ block: @escaping (AValueAnimator) -> Void) -> AAnimatorUpdateListener {
        let listener = AAnimatorUpdateListener(block)
        addUpdateListener(listener)
        return listener
    }

    func removeAllUpdateListeners() {
        if mUpdateListeners == nil {
            return
        }
        mUpdateListeners = nil
    }

    func removeUpdateListener(_ listener: AAnimatorUpdateListener) {
        guard var list = mUpdateListeners else { return }
        if let index = list.firstIndex(where: { $0 === listener }) {
            list.remove(at: index)
        }
        mUpdateListeners = list.isEmpty ? nil : list
    }

    /// `setInterpolator(null)` installs a LinearInterpolator.
    override var interpolator: ATimeInterpolator? {
        get {
            return mInterpolator
        }
        set {
            if let value = newValue {
                mInterpolator = value
            } else {
                mInterpolator = ALinearInterpolator()
            }
        }
    }

    private func start(_ playBackwards: Bool) {
        precondition(Thread.isMainThread, "Animators may only be run on Looper threads")
        mReversing = playBackwards
        mSelfPulse = !mSuppressSelfPulseRequested
        // Special case: reversing from seek-to-0 should act as if not seeked at all.
        if playBackwards && mSeekFraction != -1 && mSeekFraction != 0 {
            if mRepeatCount == Int32(AValueAnimator.INFINITE) {
                // Calculate the fraction of the current iteration.
                let fraction = Float(Double(mSeekFraction) - Double(mSeekFraction).rounded(.down))
                mSeekFraction = 1 - fraction
            } else {
                mSeekFraction = Float(1 &+ mRepeatCount) - mSeekFraction
            }
        }
        mStarted = true
        mPaused = false
        mRunning = false
        mAnimationEndRequested = false
        // Resets mLastFrameTime when start() is called, so that if the animation was running, calling start() would
        // put the animation in the started-but-not-yet-reached-the-first-frame phase.
        mLastFrameTime = -1
        mFirstFrameTime = -1
        mStartTime = -1
        addAnimationCallback(0)
        if mStartDelay == 0 || mSeekFraction >= 0 || mReversing {
            // If there's no start delay, init the animation and notify start listeners right away to be consistent
            // with the previous behavior. Otherwise, postpone this until the first frame after the start delay.
            startAnimation()
            if mSeekFraction == -1 {
                // No seek, start at play time 0. Note that the reason we are not using fraction 0 is because for
                // animations with 0 duration, we want to be consistent with pre-N behavior: skip to the final value
                // immediately.
                setCurrentPlayTime(0)
            } else {
                setCurrentFraction(mSeekFraction)
            }
        }
    }

    override func start() {
        start(false)
    }

    override func cancel() {
        precondition(Thread.isMainThread, "Animators may only be run on Looper threads")
        // If end has already been requested, through a previous end() or cancel() call, no-op until animation
        // starts again.
        if mAnimationEndRequested {
            return
        }
        // Only cancel if the animation is actually running or has been started and is about to run.
        // Only notify listeners if the animator has actually started.
        if (mStarted || mRunning || mStartListenersCalled) && mListeners != nil {
            if !mRunning {
                // If it's not yet running, then start listeners weren't called. Call them now.
                notifyStartListeners(mReversing)
            }
            notifyListeners(.ON_CANCEL)
        }
        endAnimation()
    }

    override func end() {
        precondition(Thread.isMainThread, "Animators may only be run on Looper threads")
        if !mRunning {
            // Special case if the animation has not yet started; get it ready for ending
            startAnimation()
            mStarted = true
        } else if !mInitialized {
            initAnimation()
        }
        animateValue(shouldPlayBackward(mRepeatCount, mReversing) ? 0 : 1)
        if mAnimationEndRequested {
            return
        }
        endAnimation()
    }

    override func resume() {
        precondition(Thread.isMainThread, "Animators may only be resumed from the same thread that the animator was started on")
        if mPaused && !mResumed {
            mResumed = true
            if mPauseTime > 0 {
                addAnimationCallback(0)
            }
        }
        super.resume()
    }

    override func pause() {
        let previouslyPaused = mPaused
        super.pause()
        if !previouslyPaused && mPaused {
            mPauseTime = -1
            mResumed = false
        }
    }

    override var isRunning: Bool {
        return mRunning
    }

    override var isStarted: Bool {
        return mStarted
    }

    func reverse() {
        if isPulsingInternal() {
            let currentTime = AAnimationUtils.currentAnimationTimeMillis()
            let currentPlayTime = currentTime &- mStartTime
            let timeLeft = getScaledDuration() &- currentPlayTime
            mStartTime = currentTime &- timeLeft
            mReversing = !mReversing
        } else if mStarted {
            mReversing = !mReversing
            end()
        } else {
            start(true)
        }
    }

    private func endAnimation() {
        if mAnimationEndRequested {
            return
        }
        removeAnimationCallback()
        mAnimationEndRequested = true
        mPaused = false
        let notify = (mStarted || mRunning) && mListeners != nil
        if notify && !mRunning {
            // If it's not yet running, then start listeners weren't called. Call them now.
            notifyStartListeners(mReversing)
        }
        mLastFrameTime = -1
        mFirstFrameTime = -1
        mStartTime = -1
        completeEndAnimation(mReversing)
    }

    override func completeEndAnimation(_ isReversing: Bool) {
        // The mRunning and mStarted are reset here because isStarted() and isRunning() can be true before notifying
        // the end listeners. When notifying the end listeners, isStarted() and isRunning() should be false.
        mRunning = false
        mStarted = false
        super.completeEndAnimation(isReversing)
        // mReversing needs to be reset *after* notifying the listeners for the end callbacks.
        mReversing = false
    }

    private func startAnimation() {
        mAnimationEndRequested = false
        initAnimation()
        mRunning = true
        if mSeekFraction >= 0 {
            mOverallFraction = mSeekFraction
        } else {
            mOverallFraction = 0
        }
        notifyStartListeners(mReversing)
    }

    private func isPulsingInternal() -> Bool {
        return mLastFrameTime >= 0
    }

    private func animateBasedOnTime(_ currentTime: Int64) -> Bool {
        var done = false
        if mRunning {
            let scaledDuration = getScaledDuration()
            let fraction: Float = scaledDuration > 0 ? Float(currentTime &- mStartTime) / Float(scaledDuration) : 1
            let lastFraction = mOverallFraction
            let newIteration = javaF2I(fraction) > javaF2I(lastFraction)
            let lastIterationFinished = (fraction >= Float(mRepeatCount &+ 1)) && (mRepeatCount != Int32(AValueAnimator.INFINITE))
            if scaledDuration == 0 {
                // 0 duration animator, ignore the repeat count and skip to the end
                done = true
            } else if newIteration && !lastIterationFinished {
                // Time to repeat
                notifyListeners(.ON_REPEAT)
            } else if lastIterationFinished {
                done = true
            }
            mOverallFraction = clampFraction(fraction)
            let currentIterationFraction = getCurrentIterationFraction(mOverallFraction, mReversing)
            animateValue(currentIterationFraction)
        }
        return done
    }

    /// `doAnimationFrame(frameTime)`: one frame (frame time in uptime milliseconds). Returns true when it ended.
    @discardableResult
    func doAnimationFrame(_ frameTime: Int64) -> Bool {
        if mStartTime < 0 {
            // First frame. If there is start delay, start delay count down will happen *after* this frame.
            mStartTime = mReversing ? frameTime : frameTime &+ javaF2L(Float(mStartDelay) * resolveDurationScale())
        }
        // Handle pause/resume
        if mPaused {
            mPauseTime = frameTime
            removeAnimationCallback()
            return false
        } else if mResumed {
            mResumed = false
            if mPauseTime > 0 {
                // Offset by the duration that the animation was paused
                mStartTime = mStartTime &+ (frameTime &- mPauseTime)
            }
        }
        if !mRunning {
            // If not running, that means the animation is in the start delay phase of a forward running animation.
            // In the case of reversing, we want to run start delay in the end.
            if mStartTime > frameTime && mSeekFraction == -1 {
                // This is when no seek fraction is set during start delay. If developers change the seek fraction
                // during the delay, animation will start from the seeked position right away.
                return false
            } else {
                // If mRunning is not set by now, that means non-zero start delay, no seeking, not reversing. At this
                // point, start delay has passed.
                mRunning = true
                startAnimation()
            }
        }
        if mLastFrameTime < 0 {
            if mSeekFraction >= 0 {
                let seekTime = javaF2L(Float(getScaledDuration()) * mSeekFraction)
                mStartTime = frameTime &- seekTime
                mSeekFraction = -1
            }
        }
        mLastFrameTime = frameTime
        // The frame time might be before the start time during the first frame of an animation. The "current time"
        // must always be on or after the start time to avoid animating frames at negative time intervals.
        let currentTime = max(frameTime, mStartTime)
        let finished = animateBasedOnTime(currentTime)
        if finished {
            endAnimation()
        }
        return finished
    }

    private func removeAnimationCallback() {
        if !mSelfPulse {
            return
        }
        AAnimationHandler.getInstance().removeCallback(self)
    }

    private func addAnimationCallback(_ delay: Int64) {
        if !mSelfPulse {
            return
        }
        AAnimationHandler.getInstance().addAnimationFrameCallback(self, delay)
    }

    /// `getAnimatedFraction()`: the interpolated fraction of the last update.
    var animatedFraction: Float {
        return mCurrentFraction
    }

    func animateValue(_ value: Float) {
        guard let values = mValues else { return }
        let fraction = mInterpolator.getInterpolation(value)
        mCurrentFraction = fraction
        for holder in values {
            holder.calculateValue(fraction)
        }
        if mSeekFraction >= 0 || mStartListenersCalled {
            if let listeners = mUpdateListeners {
                for listener in listeners {
                    listener.onAnimationUpdate(self)
                }
            }
        }
    }
}

// MARK: - ObjectAnimator

/// `android.animation.ObjectAnimator` for view properties (`ObjectAnimator.ofFloat(view, View.TRANSLATION_Y, ...)`).
final class AObjectAnimator: AValueAnimator {
    private var mTarget: AAnimatableView?
    private var mProperty: AViewProperty?

    override init() {
        super.init()
    }

    static func ofFloat(_ target: AAnimatableView, _ property: AViewProperty, _ values: Float...) -> AObjectAnimator {
        let anim = AObjectAnimator()
        anim.setTarget(target)
        anim.setProperty(property)
        anim.setFloatValues(array: values)
        return anim
    }

    func setProperty(_ property: AViewProperty) {
        mProperty = property
        mInitialized = false
    }

    var propertyName: String {
        return mProperty?.name ?? ""
    }

    override func setFloatValues(array values: [Float]) {
        if let existing = mValues, !existing.isEmpty {
            super.setFloatValues(array: values)
        } else {
            // No values yet - this animator is being constructed piecemeal. Init the values with whatever the
            // current property is
            setValues([APropertyValuesHolder(property: mProperty, floatValues: values)])
        }
    }

    override func start() {
        // AnimationHandler.autoCancelBasedOn(this) only cancels animators that called setAutoCancel(true); none do.
        super.start()
    }

    override func initAnimation() {
        if !mInitialized {
            if let target = mTarget, let values = mValues {
                for holder in values {
                    holder.setupSetterAndGetter(target)
                }
            }
            super.initAnimation()
        }
    }

    var target: AAnimatableView? {
        return mTarget
    }

    func getTarget() -> AAnimatableView? {
        return mTarget
    }

    func setTarget(_ target: AAnimatableView?) {
        let oldTarget = mTarget
        if oldTarget !== target {
            if isStarted {
                cancel()
            }
            mTarget = target
            // New target should cause re-initialization prior to starting
            mInitialized = false
        }
    }

    override func animateValue(_ value: Float) {
        let target = mTarget
        super.animateValue(value)
        if let values = mValues {
            for holder in values {
                holder.setAnimatedValue(target)
            }
        }
    }
}

// MARK: - AnimationHandler

/// `android.animation.AnimationHandler`: one Choreographer frame callback that runs every started ValueAnimator,
/// in start order. An animator added during the iteration waits for the next frame; a removed one is skipped.
final class AAnimationHandler {
    nonisolated(unsafe) private static let sInstance = AAnimationHandler()

    static func getInstance() -> AAnimationHandler {
        return sInstance
    }

    private var mDelayedCallbackStartTime: [ObjectIdentifier: Int64] = [:]
    private var mAnimationCallbacks: [AValueAnimator?] = []
    private var mListDirty = false

    private lazy var mFrameCallback: AChoreographer.FrameCallback = AChoreographer.FrameCallback { [unowned self] frameTimeNanos in
        self.doAnimationFrame(frameTimeNanos / AChoreographer.NANOS_PER_MS)
        if self.mAnimationCallbacks.count > 0 {
            AChoreographer.getInstance().postFrameCallback(self.mFrameCallback)
        }
    }

    private init() {}

    /// Register to get a callback on the next frame after the delay.
    func addAnimationFrameCallback(_ callback: AValueAnimator, _ delay: Int64) {
        if mAnimationCallbacks.count == 0 {
            AChoreographer.getInstance().postFrameCallback(mFrameCallback)
        }
        if !mAnimationCallbacks.contains(where: { $0 === callback }) {
            mAnimationCallbacks.append(callback)
        }
        if delay > 0 {
            mDelayedCallbackStartTime[ObjectIdentifier(callback)] = ASystemClock.uptimeMillis() &+ delay
        }
    }

    func removeCallback(_ callback: AValueAnimator) {
        mDelayedCallbackStartTime.removeValue(forKey: ObjectIdentifier(callback))
        if let id = mAnimationCallbacks.firstIndex(where: { $0 === callback }) {
            mAnimationCallbacks[id] = nil
            mListDirty = true
        }
    }

    private func doAnimationFrame(_ frameTime: Int64) {
        let currentTime = ASystemClock.uptimeMillis()
        let size = mAnimationCallbacks.count
        var i = 0
        while i < size {
            if let callback = mAnimationCallbacks[i], isCallbackDue(callback, currentTime) {
                callback.doAnimationFrame(frameTime)
            }
            i += 1
        }
        cleanUpList()
    }

    private func isCallbackDue(_ callback: AValueAnimator, _ currentTime: Int64) -> Bool {
        guard let startTime = mDelayedCallbackStartTime[ObjectIdentifier(callback)] else {
            return true
        }
        if startTime < currentTime {
            mDelayedCallbackStartTime.removeValue(forKey: ObjectIdentifier(callback))
            return true
        }
        return false
    }

    private func cleanUpList() {
        if mListDirty {
            mAnimationCallbacks.removeAll { $0 == nil }
            mListDirty = false
        }
    }

    /// `getAnimationCount()`: animators currently registered.
    func getAnimationCount() -> Int {
        return mAnimationCallbacks.reduce(0) { $0 + ($1 == nil ? 0 : 1) }
    }

    func resetForTests() {
        mDelayedCallbackStartTime.removeAll()
        mAnimationCallbacks.removeAll()
        mListDirty = false
    }
}

// MARK: - ViewPropertyAnimator

/// `android.view.ViewPropertyAnimator`, returned by `view.animate()` (one instance per view, created by AView).
final class AViewPropertyAnimator {
    static let NONE = 0x0000
    static let TRANSLATION_X = 0x0001
    static let TRANSLATION_Y = 0x0002
    static let TRANSLATION_Z = 0x0004
    static let SCALE_X = 0x0008
    static let SCALE_Y = 0x0010
    static let ROTATION = 0x0020
    static let ROTATION_X = 0x0040
    static let ROTATION_Y = 0x0080
    static let X = 0x0100
    static let Y = 0x0200
    static let Z = 0x0400
    static let ALPHA = 0x0800

    /// Weak: the view owns its animator. A running animation keeps the view alive through its record, as the
    /// AnimationHandler -> animator -> listener -> view chain does on Android.
    private weak var mView: AAnimatableView?
    private var mDuration: Int64 = 0
    private var mDurationSet = false
    private var mStartDelay: Int64 = 0
    private var mStartDelaySet = false
    private var mInterpolator: ATimeInterpolator? = nil
    private var mInterpolatorSet = false
    private var mListener: AAnimatorListener? = nil
    private var mUpdateListener: ((AValueAnimator) -> Void)? = nil
    private var mTempValueAnimator: AValueAnimator? = nil
    private var mPendingAnimations: [NameValuesHolder] = []
    private var mPendingOnStartAction: (() -> Void)? = nil
    private var mPendingOnEndAction: (() -> Void)? = nil
    /// `mAnimatorMap` (+ the start/end action maps), in start order.
    private var mAnimatorMap: [AnimatorRecord] = []
    private lazy var mAnimatorEventListener = AnimatorEventListener(self)
    private lazy var mAnimatorUpdateListener = AAnimatorUpdateListener { [weak self] animation in
        self?.onAnimationUpdate(animation)
    }
    /// Posted to start the pending property animations together in the next frame's ANIMATION phase.
    private lazy var mAnimationStarter = ARunnable { [weak self] in
        self?.startAnimation()
    }

    private struct NameValuesHolder {
        let mNameConstant: Int
        let mFromValue: Float
        let mDeltaValue: Float
    }

    private final class PropertyBundle {
        var mPropertyMask: Int
        var mNameValuesHolder: [NameValuesHolder]

        init(_ propertyMask: Int, _ nameValuesHolder: [NameValuesHolder]) {
            mPropertyMask = propertyMask
            mNameValuesHolder = nameValuesHolder
        }

        /// Removes the given property from being animated as a part of this bundle; true if it was part of it.
        func cancel(_ propertyConstant: Int) -> Bool {
            if (mPropertyMask & propertyConstant) != 0 {
                for i in 0..<mNameValuesHolder.count where mNameValuesHolder[i].mNameConstant == propertyConstant {
                    mNameValuesHolder.remove(at: i)
                    mPropertyMask &= ~propertyConstant
                    return true
                }
            }
            return false
        }
    }

    private final class AnimatorRecord {
        let animator: AValueAnimator
        let bundle: PropertyBundle
        let view: AAnimatableView
        var onStartAction: (() -> Void)?
        var onEndAction: (() -> Void)?

        init(_ animator: AValueAnimator, _ bundle: PropertyBundle, _ view: AAnimatableView) {
            self.animator = animator
            self.bundle = bundle
            self.view = view
        }
    }

    /// The single listener of every animator this object starts.
    private final class AnimatorEventListener: AAnimatorListener {
        weak var owner: AViewPropertyAnimator?

        init(_ owner: AViewPropertyAnimator) {
            self.owner = owner
        }

        func onAnimationStart(_ animation: AAnimator) {
            owner?.onEventStart(animation)
        }

        func onAnimationEnd(_ animation: AAnimator) {
            owner?.onEventEnd(animation)
        }

        func onAnimationCancel(_ animation: AAnimator) {
            owner?.onEventCancel(animation)
        }

        func onAnimationRepeat(_ animation: AAnimator) {
            owner?.onEventRepeat(animation)
        }
    }

    /// Created once per view by `AView.animate()`.
    init(_ view: AAnimatableView) {
        mView = view
    }

    // MARK: Configuration

    @discardableResult
    func setDuration(_ duration: Int64) -> AViewPropertyAnimator {
        precondition(duration >= 0, "Animators cannot have negative duration: \(duration)")
        mDurationSet = true
        mDuration = duration
        return self
    }

    /// `getDuration()`: the set duration, else the ValueAnimator default (300).
    var duration: Int64 {
        if mDurationSet {
            return mDuration
        }
        if mTempValueAnimator == nil {
            mTempValueAnimator = AValueAnimator()
        }
        return mTempValueAnimator!.duration
    }

    /// `getStartDelay()`.
    var startDelay: Int64 {
        return mStartDelaySet ? mStartDelay : 0
    }

    @discardableResult
    func setStartDelay(_ startDelay: Int64) -> AViewPropertyAnimator {
        precondition(startDelay >= 0, "Animators cannot have negative start delay: \(startDelay)")
        mStartDelaySet = true
        mStartDelay = startDelay
        return self
    }

    /// `setInterpolator(null)` makes the animation linear (ValueAnimator.setInterpolator(null)).
    @discardableResult
    func setInterpolator(_ interpolator: ATimeInterpolator?) -> AViewPropertyAnimator {
        mInterpolatorSet = true
        mInterpolator = interpolator
        return self
    }

    /// `getInterpolator()`: the set one, else the ValueAnimator default (AccelerateDecelerate).
    var interpolator: ATimeInterpolator? {
        if mInterpolatorSet {
            return mInterpolator
        }
        if mTempValueAnimator == nil {
            mTempValueAnimator = AValueAnimator()
        }
        return mTempValueAnimator!.interpolator
    }

    @discardableResult
    func setListener(_ listener: AAnimatorListener?) -> AViewPropertyAnimator {
        mListener = listener
        return self
    }

    @discardableResult
    func setUpdateListener(_ listener: ((AValueAnimator) -> Void)?) -> AViewPropertyAnimator {
        mUpdateListener = listener
        return self
    }

    // MARK: Start / cancel

    /// Starts the pending animations now (synchronously, like Android) instead of in the next frame.
    func start() {
        removeStarter()
        startAnimation()
    }

    /// Cancels every running animation of this view (onAnimationCancel, then onAnimationEnd; end actions do not
    /// run) and drops the pending ones.
    func cancel() {
        if mAnimatorMap.count > 0 {
            let running = mAnimatorMap.map { $0.animator }
            for runningAnim in running {
                runningAnim.cancel()
            }
        }
        mPendingAnimations.removeAll()
        mPendingOnStartAction = nil
        mPendingOnEndAction = nil
        removeStarter()
    }

    // MARK: Properties

    @discardableResult
    func x(_ value: Float) -> AViewPropertyAnimator {
        animateProperty(AViewPropertyAnimator.X, value)
        return self
    }

    @discardableResult
    func xBy(_ value: Float) -> AViewPropertyAnimator {
        animatePropertyBy(AViewPropertyAnimator.X, value)
        return self
    }

    @discardableResult
    func y(_ value: Float) -> AViewPropertyAnimator {
        animateProperty(AViewPropertyAnimator.Y, value)
        return self
    }

    @discardableResult
    func yBy(_ value: Float) -> AViewPropertyAnimator {
        animatePropertyBy(AViewPropertyAnimator.Y, value)
        return self
    }

    @discardableResult
    func rotation(_ value: Float) -> AViewPropertyAnimator {
        animateProperty(AViewPropertyAnimator.ROTATION, value)
        return self
    }

    @discardableResult
    func rotationBy(_ value: Float) -> AViewPropertyAnimator {
        animatePropertyBy(AViewPropertyAnimator.ROTATION, value)
        return self
    }

    @discardableResult
    func translationX(_ value: Float) -> AViewPropertyAnimator {
        animateProperty(AViewPropertyAnimator.TRANSLATION_X, value)
        return self
    }

    @discardableResult
    func translationXBy(_ value: Float) -> AViewPropertyAnimator {
        animatePropertyBy(AViewPropertyAnimator.TRANSLATION_X, value)
        return self
    }

    @discardableResult
    func translationY(_ value: Float) -> AViewPropertyAnimator {
        animateProperty(AViewPropertyAnimator.TRANSLATION_Y, value)
        return self
    }

    @discardableResult
    func translationYBy(_ value: Float) -> AViewPropertyAnimator {
        animatePropertyBy(AViewPropertyAnimator.TRANSLATION_Y, value)
        return self
    }

    @discardableResult
    func scaleX(_ value: Float) -> AViewPropertyAnimator {
        animateProperty(AViewPropertyAnimator.SCALE_X, value)
        return self
    }

    @discardableResult
    func scaleXBy(_ value: Float) -> AViewPropertyAnimator {
        animatePropertyBy(AViewPropertyAnimator.SCALE_X, value)
        return self
    }

    @discardableResult
    func scaleY(_ value: Float) -> AViewPropertyAnimator {
        animateProperty(AViewPropertyAnimator.SCALE_Y, value)
        return self
    }

    @discardableResult
    func scaleYBy(_ value: Float) -> AViewPropertyAnimator {
        animatePropertyBy(AViewPropertyAnimator.SCALE_Y, value)
        return self
    }

    @discardableResult
    func alpha(_ value: Float) -> AViewPropertyAnimator {
        animateProperty(AViewPropertyAnimator.ALPHA, value)
        return self
    }

    @discardableResult
    func alphaBy(_ value: Float) -> AViewPropertyAnimator {
        animatePropertyBy(AViewPropertyAnimator.ALPHA, value)
        return self
    }

    /// `withLayer()`: hardware layers do not exist on iOS; a no-op.
    @discardableResult
    func withLayer() -> AViewPropertyAnimator {
        return self
    }

    /// Runs when the next started animation starts (synchronously in start() when there is no start delay).
    @discardableResult
    func withStartAction(_ runnable: @escaping () -> Void) -> AViewPropertyAnimator {
        mPendingOnStartAction = runnable
        return self
    }

    @discardableResult
    func withStartAction(_ runnable: ARunnable?) -> AViewPropertyAnimator {
        if let runnable = runnable {
            mPendingOnStartAction = { runnable.run() }
        } else {
            mPendingOnStartAction = nil
        }
        return self
    }

    /// Runs when the next started animation ends normally; not when it is cancelled.
    @discardableResult
    func withEndAction(_ runnable: @escaping () -> Void) -> AViewPropertyAnimator {
        mPendingOnEndAction = runnable
        return self
    }

    @discardableResult
    func withEndAction(_ runnable: ARunnable?) -> AViewPropertyAnimator {
        if let runnable = runnable {
            mPendingOnEndAction = { runnable.run() }
        } else {
            mPendingOnEndAction = nil
        }
        return self
    }

    // MARK: Implementation

    /// One ValueAnimator from 0 to 1 for all pending properties.
    private func startAnimation() {
        guard let view = mView else {
            mPendingAnimations.removeAll()
            return
        }
        let animator = AValueAnimator.ofFloat(1.0)
        let nameValueList = mPendingAnimations
        mPendingAnimations.removeAll()
        var propertyMask = 0
        for nameValuesHolder in nameValueList {
            propertyMask |= nameValuesHolder.mNameConstant
        }
        let record = AnimatorRecord(animator, PropertyBundle(propertyMask, nameValueList), view)
        mAnimatorMap.append(record)
        if let action = mPendingOnStartAction {
            record.onStartAction = action
            mPendingOnStartAction = nil
        }
        if let action = mPendingOnEndAction {
            record.onEndAction = action
            mPendingOnEndAction = nil
        }
        animator.addUpdateListener(mAnimatorUpdateListener)
        animator.addListener(mAnimatorEventListener)
        if mStartDelaySet {
            animator.startDelay = mStartDelay
        }
        if mDurationSet {
            animator.duration = mDuration
        }
        if mInterpolatorSet {
            animator.interpolator = mInterpolator
        }
        animator.start()
    }

    private func animateProperty(_ constantName: Int, _ toValue: Float) {
        guard let view = mView else { return }
        let fromValue = getValue(view, constantName)
        let deltaValue = toValue - fromValue
        animatePropertyBy(constantName, fromValue, deltaValue)
    }

    private func animatePropertyBy(_ constantName: Int, _ byValue: Float) {
        guard let view = mView else { return }
        let fromValue = getValue(view, constantName)
        animatePropertyBy(constantName, fromValue, byValue)
    }

    private func animatePropertyBy(_ constantName: Int, _ startValue: Float, _ byValue: Float) {
        // First, cancel any existing animations on this property
        if mAnimatorMap.count > 0 {
            var animatorToCancel: AValueAnimator? = nil
            for record in mAnimatorMap {
                if record.bundle.cancel(constantName) {
                    // property was canceled - cancel the animation if it's now empty. Note that it's safe to break
                    // out here because every new animation on a property will cancel a previous animation on that
                    // property, so there can only ever be one such animation running.
                    if record.bundle.mPropertyMask == AViewPropertyAnimator.NONE {
                        // the animation is no longer changing anything - cancel it
                        animatorToCancel = record.animator
                        break
                    }
                }
            }
            animatorToCancel?.cancel()
        }
        mPendingAnimations.append(NameValuesHolder(mNameConstant: constantName, mFromValue: startValue, mDeltaValue: byValue))
        removeStarter()
        postStarter()
    }

    /// `mView.postOnAnimation(mAnimationStarter)`: through the AView (its run queue holds it while detached), or
    /// straight to the Choreographer for any other animatable target.
    private func postStarter() {
        if let view = mView as? AView {
            view.postOnAnimation(mAnimationStarter)
        } else {
            AChoreographer.getInstance().postAnimationRunnable(mAnimationStarter)
        }
    }

    /// `mView.removeCallbacks(mAnimationStarter)`.
    private func removeStarter() {
        if let view = mView as? AView {
            view.removeCallbacks(mAnimationStarter)
        } else {
            AChoreographer.getInstance().removeAnimationRunnable(mAnimationStarter)
        }
    }

    private func setValue(_ view: AAnimatableView, _ propertyConstant: Int, _ value: Float) {
        switch propertyConstant {
        case AViewPropertyAnimator.TRANSLATION_X:
            view.translationX = value
        case AViewPropertyAnimator.TRANSLATION_Y:
            view.translationY = value
        case AViewPropertyAnimator.ROTATION:
            view.rotation = value
        case AViewPropertyAnimator.SCALE_X:
            view.scaleX = value
        case AViewPropertyAnimator.SCALE_Y:
            view.scaleY = value
        case AViewPropertyAnimator.X:
            view.x = value
        case AViewPropertyAnimator.Y:
            view.y = value
        case AViewPropertyAnimator.ALPHA:
            view.alpha = CGFloat(value)
        default:
            break
        }
    }

    private func getValue(_ view: AAnimatableView, _ propertyConstant: Int) -> Float {
        switch propertyConstant {
        case AViewPropertyAnimator.TRANSLATION_X:
            return view.translationX
        case AViewPropertyAnimator.TRANSLATION_Y:
            return view.translationY
        case AViewPropertyAnimator.ROTATION:
            return view.rotation
        case AViewPropertyAnimator.SCALE_X:
            return view.scaleX
        case AViewPropertyAnimator.SCALE_Y:
            return view.scaleY
        case AViewPropertyAnimator.X:
            return view.x
        case AViewPropertyAnimator.Y:
            return view.y
        case AViewPropertyAnimator.ALPHA:
            return Float(view.alpha)
        default:
            return 0
        }
    }

    private func record(for animation: AAnimator) -> AnimatorRecord? {
        return mAnimatorMap.first { $0.animator === animation }
    }

    fileprivate func onEventStart(_ animation: AAnimator) {
        if let record = record(for: animation) {
            if let action = record.onStartAction {
                action()
            }
            record.onStartAction = nil
        }
        mListener?.onAnimationStart(animation)
    }

    fileprivate func onEventCancel(_ animation: AAnimator) {
        mListener?.onAnimationCancel(animation)
        record(for: animation)?.onEndAction = nil
    }

    fileprivate func onEventRepeat(_ animation: AAnimator) {
        mListener?.onAnimationRepeat(animation)
    }

    fileprivate func onEventEnd(_ animation: AAnimator) {
        mListener?.onAnimationEnd(animation)
        if let record = record(for: animation) {
            if let action = record.onEndAction {
                action()
            }
            record.onEndAction = nil
        }
        mAnimatorMap.removeAll { $0.animator === animation }
    }

    /// Sets each property of the animation's bundle to `from + fraction * delta` (fraction = interpolated).
    private func onAnimationUpdate(_ animation: AValueAnimator) {
        guard let record = record(for: animation) else {
            // Shouldn't happen, but just to play it safe
            return
        }
        let fraction = animation.animatedFraction
        let valueList = record.bundle.mNameValuesHolder
        for values in valueList {
            let value = values.mFromValue + fraction * values.mDeltaValue
            if values.mNameConstant == AViewPropertyAnimator.ALPHA {
                record.view.alpha = CGFloat(value)
            } else {
                setValue(record.view, values.mNameConstant, value)
            }
        }
        mUpdateListener?(animation)
    }

    // MARK: Test hooks

    /// Animations started and not yet ended.
    var runningAnimationCountForTests: Int {
        return mAnimatorMap.count
    }
}
