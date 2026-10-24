import Foundation
import QuartzCore
import UIKit

// android.view.Choreographer (DESIGN 2.6 / 4.3, VIEW-API "Choreographer"), translated from AOSP API 37.
//
// Per vsync, as Android's doFrame: (1) input was already delivered by UIKit; (2) the ANIMATION callback queue -
// frame callbacks (the AnimationHandler that drives every ValueAnimator is one of them) and View.postOnAnimation
// runnables, in (due time, posting) order; the callbacks that are due when the phase starts are taken out of the
// queue first, so callbacks posted during the phase run on the next frame, and a callback removed during the phase
// still runs if it was already taken out (exactly Android's extractDueCallbacksLocked); (3) TRAVERSAL: when a
// traversal was requested (View.invalidate / requestLayout -> requestTraversal), its sync barrier is removed and
// `traversalHandler` runs (AndroidKit layouts, then onDraw of the traversal-drawn views); (4) the post-traversal
// handlers (the Metal world renders and presents). Handler messages due before the vsync run before the frame.
//
// The display link is one CADisplayLink locked to 60 Hz (DESIGN 12.2) in the common run-loop modes. It runs only
// while there is work (a scheduled frame or a post-traversal handler) and the app is active; otherwise it is paused.

/// android.view.animation.AnimationUtils: the animation clock is locked to the frame time during a frame.
enum AAnimationUtils {
    nonisolated(unsafe) private static var animationClockLocked = false
    nonisolated(unsafe) private static var currentVsyncTimeMillis: Int64 = 0
    nonisolated(unsafe) private static var lastReportedTimeMillis: Int64 = 0

    static func lockAnimationClock(_ vsyncMillis: Int64) {
        animationClockLocked = true
        currentVsyncTimeMillis = vsyncMillis
    }

    static func unlockAnimationClock() {
        animationClockLocked = false
    }

    /// `AnimationUtils.currentAnimationTimeMillis()`: the frame time inside a frame (it never rewinds), else
    /// SystemClock.uptimeMillis().
    static func currentAnimationTimeMillis() -> Int64 {
        if animationClockLocked {
            // It's important that time never rewinds
            return max(currentVsyncTimeMillis, lastReportedTimeMillis)
        }
        lastReportedTimeMillis = ASystemClock.uptimeMillis()
        return lastReportedTimeMillis
    }

    static func resetForTests() {
        animationClockLocked = false
        currentVsyncTimeMillis = 0
        lastReportedTimeMillis = 0
    }
}

/// android.view.Choreographer of the main thread.
final class AChoreographer {
    /// `Choreographer.FrameCallback`.
    final class FrameCallback {
        private let block: (Int64) -> Void

        init(_ block: @escaping (_ frameTimeNanos: Int64) -> Void) {
            self.block = block
        }

        func doFrame(_ frameTimeNanos: Int64) {
            block(frameTimeNanos)
        }
    }

    static let CALLBACK_INPUT = 0
    static let CALLBACK_ANIMATION = 1
    static let CALLBACK_INSETS_ANIMATION = 2
    static let CALLBACK_TRAVERSAL = 3
    static let CALLBACK_COMMIT = 4

    /// TimeUtils.NANOS_PER_MS.
    static let NANOS_PER_MS: Int64 = 1_000_000
    /// The frame interval of the 60 Hz display link: Android's (long)(1e9 / 60f) on the 60 Hz Pixel 3 baseline.
    static let FRAME_INTERVAL_NANOS: Int64 = 16_666_666
    private static let SKIPPED_FRAME_WARNING_LIMIT: Int64 = 30
    private static let TAG = "Choreographer"
    private static let MSG_DO_SCHEDULE_CALLBACK = 2

    nonisolated(unsafe) private static let sMainInstance = AChoreographer()

    /// `Choreographer.getInstance()` (main thread).
    static func getInstance() -> AChoreographer {
        return sMainInstance
    }

    /// `Choreographer.getMainThreadInstance()`.
    static func getMainThreadInstance() -> AChoreographer {
        return sMainInstance
    }

    /// All frame callbacks carry this token in the queue (Android FRAME_CALLBACK_TOKEN).
    private let FRAME_CALLBACK_TOKEN = FrameCallbackToken()
    private final class FrameCallbackToken {}

    /// The CALLBACK_ANIMATION queue. (INPUT, INSETS_ANIMATION and COMMIT have no producers in this app; TRAVERSAL is
    /// the single ViewRootImpl traversal below.)
    private let mAnimationQueue = CallbackQueue()
    private var mFrameScheduled = false
    private var mCallbacksRunning = false
    private var mLastFrameTimeNanos = Int64.min
    /// FrameData.mFrameTimeNanos: the (jitter-adjusted) time of the frame being run.
    private var mFrameTimeNanos: Int64 = 0

    /// Choreographer.FrameHandler: an asynchronous handler, so its messages are not stalled by traversal barriers.
    private lazy var mHandler: AHandler = AHandler(ALooper.getMainLooper(), { [unowned self] msg in
        if msg.what == AChoreographer.MSG_DO_SCHEDULE_CALLBACK {
            self.doScheduleCallback()
            return true
        }
        return false
    }, true)

    // ViewRootImpl.scheduleTraversals state.
    private var mTraversalScheduled = false
    private var mTraversalBarrier: Int? = nil

    /// Installed by the view system (AViewRoot): runs pending layouts, then the traversal draws.
    var traversalHandler: ((Int64) -> Void)?

    private struct PostTraversalEntry {
        weak var owner: AnyObject?
        var block: (Int64) -> Void
    }

    private var postTraversalHandlers: [PostTraversalEntry] = []

    private var displayLink: CADisplayLink?
    private let displayLinkTarget = DisplayLinkTarget()
    private var appActive = false
    private var lifecycleObserved = false
    private var lifecycleObservers: [NSObjectProtocol] = []

    private init() {}

    // MARK: Frame callbacks and animation runnables

    func postFrameCallback(_ callback: FrameCallback) {
        postFrameCallbackDelayed(callback, 0)
    }

    func postFrameCallbackDelayed(_ callback: FrameCallback, _ delayMillis: Int64) {
        postCallbackDelayedInternal(callback, FRAME_CALLBACK_TOKEN, delayMillis)
    }

    func removeFrameCallback(_ callback: FrameCallback) {
        removeCallbacksInternal(callback, FRAME_CALLBACK_TOKEN)
    }

    /// `View.postOnAnimation(r)` on an attached view: `postCallback(CALLBACK_ANIMATION, r, null)`; runs once, on the
    /// next frame, in the ANIMATION phase.
    func postAnimationRunnable(_ r: ARunnable) {
        postCallbackDelayedInternal(r, nil, 0)
    }

    /// `View.postOnAnimationDelayed(r, delay)`.
    func postAnimationRunnableDelayed(_ r: ARunnable, _ delayMillis: Int64) {
        postCallbackDelayedInternal(r, nil, delayMillis)
    }

    /// The Choreographer half of `View.removeCallbacks(r)`: `removeCallbacks(CALLBACK_ANIMATION, r, null)`.
    func removeAnimationRunnable(_ r: ARunnable) {
        removeCallbacksInternal(r, nil)
    }

    private func postCallbackDelayedInternal(_ action: AnyObject, _ token: AnyObject?, _ delayMillis: Int64) {
        if !Thread.isMainThread {
            DispatchQueue.main.async {
                self.postCallbackDelayedInternal(action, token, delayMillis)
            }
            return
        }
        let now = ASystemClock.uptimeMillis()
        let dueTime = now &+ delayMillis
        mAnimationQueue.addCallback(dueTime, action, token)
        if dueTime <= now {
            scheduleFrameLocked()
        } else {
            let msg = mHandler.obtainMessage(AChoreographer.MSG_DO_SCHEDULE_CALLBACK, action)
            msg.arg1 = AChoreographer.CALLBACK_ANIMATION
            msg.setAsynchronous(true)
            mHandler.sendMessageAtTime(msg, dueTime)
        }
    }

    private func removeCallbacksInternal(_ action: AnyObject?, _ token: AnyObject?) {
        if !Thread.isMainThread {
            DispatchQueue.main.async {
                self.removeCallbacksInternal(action, token)
            }
            return
        }
        mAnimationQueue.removeCallbacks(action, token)
        if let action = action, token == nil {
            mHandler.removeMessages(AChoreographer.MSG_DO_SCHEDULE_CALLBACK, action)
        }
    }

    private func doScheduleCallback() {
        if !mFrameScheduled {
            let now = ASystemClock.uptimeMillis()
            if mAnimationQueue.hasDueCallbacks(now) {
                scheduleFrameLocked()
            }
        }
    }

    private func scheduleFrameLocked() {
        if !mFrameScheduled {
            mFrameScheduled = true
            updateDisplayLink()
        }
    }

    // MARK: Traversals (ViewRootImpl.scheduleTraversals / doTraversal)

    /// A view was invalidated or needs layout (`ViewRootImpl.scheduleTraversals`): the traversal runs in the next
    /// frame, and until then a sync barrier holds back every Handler message posted after this call (Android:
    /// "any message posted after scheduling traversals is guaranteed to run after the scheduled traversals").
    func requestTraversal() {
        if !Thread.isMainThread {
            DispatchQueue.main.async {
                self.requestTraversal()
            }
            return
        }
        if !mTraversalScheduled {
            mTraversalScheduled = true
            postTraversalBarrier()
            scheduleFrameLocked()
        }
    }

    /// `ViewRootImpl.unscheduleTraversals`.
    func cancelTraversal() {
        if mTraversalScheduled {
            mTraversalScheduled = false
            removeTraversalBarrier()
        }
    }

    var isTraversalScheduled: Bool {
        return mTraversalScheduled
    }

    private func postTraversalBarrier() {
        // While the app is inactive no frame can run (the display link is paused), so a barrier would stall every
        // Handler message until the app is active again; Android keeps both running. The barrier is posted when
        // the app becomes active (setAppActive) if the traversal is still pending.
        if !framesCanRun {
            return
        }
        if mTraversalBarrier == nil {
            mTraversalBarrier = ALooper.getMainLooper().mQueue.postSyncBarrier()
        }
    }

    private func removeTraversalBarrier() {
        if let barrier = mTraversalBarrier {
            mTraversalBarrier = nil
            ALooper.getMainLooper().mQueue.removeSyncBarrier(barrier)
        }
    }

    private func doTraversal(_ frameTimeNanos: Int64) {
        if mTraversalScheduled {
            mTraversalScheduled = false
            removeTraversalBarrier()
            mCallbacksRunning = true
            traversalHandler?(frameTimeNanos)
            mCallbacksRunning = false
        }
    }

    // MARK: Post-traversal handlers (Metal render / present)

    /// Runs `block` after the traversal on every display-link tick while `owner` is alive and registered. A second
    /// registration for the same owner replaces its block.
    func addPostTraversalHandler(_ owner: AnyObject, _ block: @escaping (Int64) -> Void) {
        if !Thread.isMainThread {
            DispatchQueue.main.async {
                self.addPostTraversalHandler(owner, block)
            }
            return
        }
        if let index = postTraversalHandlers.firstIndex(where: { $0.owner === owner }) {
            postTraversalHandlers[index].block = block
        } else {
            postTraversalHandlers.append(PostTraversalEntry(owner: owner, block: block))
        }
        updateDisplayLink()
    }

    func removePostTraversalHandler(_ owner: AnyObject) {
        if !Thread.isMainThread {
            DispatchQueue.main.async {
                self.removePostTraversalHandler(owner)
            }
            return
        }
        postTraversalHandlers.removeAll { $0.owner == nil || $0.owner === owner }
        updateDisplayLink()
    }

    private var hasPostTraversalWork: Bool {
        return postTraversalHandlers.contains { $0.owner != nil }
    }

    private func runPostTraversalHandlers(_ frameTimeNanos: Int64) {
        postTraversalHandlers.removeAll { $0.owner == nil }
        let entries = postTraversalHandlers
        for entry in entries where entry.owner != nil {
            entry.block(frameTimeNanos)
        }
    }

    // MARK: Frame time

    /// The frame time of the last frame (System.nanoTime() domain); 0 before the first frame.
    var lastFrameTimeNanos: Int64 {
        return mLastFrameTimeNanos == Int64.min ? 0 : mLastFrameTimeNanos
    }

    /// `getFrameTimeNanos()`: the current frame's time inside a callback (Android throws outside one; this returns
    /// System.nanoTime()).
    func getFrameTimeNanos() -> Int64 {
        return mCallbacksRunning ? mFrameTimeNanos : ASystem.nanoTime()
    }

    /// `getFrameTime()`: getFrameTimeNanos() in milliseconds.
    func getFrameTime() -> Int64 {
        return getFrameTimeNanos() / AChoreographer.NANOS_PER_MS
    }

    func getFrameIntervalNanos() -> Int64 {
        return AChoreographer.FRAME_INTERVAL_NANOS
    }

    // MARK: The frame

    /// True while a frame is scheduled or a post-traversal handler is registered: the display link should tick.
    var wantsFrame: Bool {
        return mFrameScheduled || hasPostTraversalWork
    }

    /// One vsync: the display link's callback (or a simulated vsync in unit tests). `vsyncNanos` is the vsync time
    /// in the System.nanoTime() domain.
    func performTick(_ vsyncNanos: Int64) {
        var timestampNanos = vsyncNanos
        let now = ASystem.nanoTime()
        if timestampNanos > now {
            timestampNanos = now // FrameDisplayEventReceiver.onVsync: a vsync is never in the future
        }
        // Only a frame that was requested before this vsync runs now; one requested by the messages below waits
        // for the next vsync (Android delivers a vsync only after scheduleVsync).
        let frameRequested = mFrameScheduled
        runMessagesDueBefore(timestampNanos / AChoreographer.NANOS_PER_MS)
        let ranFrame = frameRequested ? doFrame(timestampNanos) : false
        runPostTraversalHandlers(ranFrame ? mFrameTimeNanos : timestampNanos)
        updateDisplayLink()
    }

    /// Android posts the vsync as an asynchronous message at the vsync time (FrameDisplayEventReceiver.onVsync), so
    /// messages that predate it (and are not stalled by a barrier) run before the frame.
    private func runMessagesDueBefore(_ vsyncMillis: Int64) {
        let queue = ALooper.getMainLooper().mQueue
        let seqLimit = queue.lastInsertSeq
        var ran = false
        while let msg = queue.pollMessage(beforeVsync: vsyncMillis, enqueuedUpTo: seqLimit) {
            ran = true
            msg.target?.dispatchMessage(msg)
        }
        if ran {
            AMainLooperDriver.shared.queueChanged()
        }
    }

    /// `Choreographer.doFrame`: returns true when the frame ran.
    @discardableResult
    private func doFrame(_ vsyncNanos: Int64) -> Bool {
        var frameTimeNanos = vsyncNanos
        let frameIntervalNanos = AChoreographer.FRAME_INTERVAL_NANOS
        if !mFrameScheduled {
            return false // no work to do
        }
        let startNanos = ASystem.nanoTime()
        let jitterNanos = startNanos &- frameTimeNanos
        if jitterNanos >= frameIntervalNanos {
            frameTimeNanos = startNanos
            let lastFrameOffset = jitterNanos % frameIntervalNanos
            frameTimeNanos = frameTimeNanos &- lastFrameOffset
            let skippedFrames = jitterNanos / frameIntervalNanos
            if skippedFrames >= AChoreographer.SKIPPED_FRAME_WARNING_LIMIT {
                ALog.i(AChoreographer.TAG, "Skipped \(skippedFrames) frames!  The application may be doing too much work on its main thread.")
            }
        }
        if frameTimeNanos < mLastFrameTimeNanos {
            // Frame time goes backward: wait for the next vsync (the frame stays scheduled).
            return false
        }
        mFrameScheduled = false
        mLastFrameTimeNanos = frameTimeNanos
        mFrameTimeNanos = frameTimeNanos
        AAnimationUtils.lockAnimationClock(frameTimeNanos / AChoreographer.NANOS_PER_MS)
        defer {
            AAnimationUtils.unlockAnimationClock()
        }
        doAnimationCallbacks()
        doTraversal(frameTimeNanos)
        return true
    }

    /// `doCallbacks(CALLBACK_ANIMATION)`.
    private func doAnimationCallbacks() {
        let frameTimeNanos = mFrameTimeNanos
        // We use "now" to determine when callbacks become due because it's possible for earlier processing phases
        // in a frame to post callbacks that should run in a following phase.
        let now = ASystem.nanoTime()
        guard let callbacks = mAnimationQueue.extractDueCallbacks(now / AChoreographer.NANOS_PER_MS) else {
            return
        }
        mCallbacksRunning = true
        for c in callbacks {
            if c.token === FRAME_CALLBACK_TOKEN {
                (c.action as! FrameCallback).doFrame(frameTimeNanos)
            } else {
                (c.action as! ARunnable).run()
            }
        }
        mCallbacksRunning = false
    }

    // MARK: Display link (60 Hz, active app only)

    private var framesCanRun: Bool {
        if AFakeClock.isInstalled {
            return true
        }
        observeAppLifecycleIfNeeded()
        return appActive
    }

    private func updateDisplayLink() {
        if AFakeClock.isInstalled {
            return // unit tests drive frames with AndroidKitTestLoop
        }
        observeAppLifecycleIfNeeded()
        if appActive && wantsFrame {
            let link = displayLink ?? makeDisplayLink()
            if link.isPaused {
                link.isPaused = false
            }
        } else if let link = displayLink, !link.isPaused {
            link.isPaused = true
        }
    }

    private func makeDisplayLink() -> CADisplayLink {
        displayLinkTarget.owner = self
        let link = CADisplayLink(target: displayLinkTarget, selector: #selector(DisplayLinkTarget.onDisplayLink(_:)))
        link.preferredFrameRateRange = CAFrameRateRange(minimum: 60, maximum: 60, preferred: 60)
        link.isPaused = true
        link.add(to: .main, forMode: .common)
        displayLink = link
        return link
    }

    fileprivate func displayLinkFired(_ link: CADisplayLink) {
        if AFakeClock.isInstalled {
            return
        }
        performTick(Int64((link.timestamp * 1_000_000_000).rounded()))
    }

    private func observeAppLifecycleIfNeeded() {
        if lifecycleObserved {
            return
        }
        lifecycleObserved = true
        appActive = UIApplication.shared.applicationState == .active
        let center = NotificationCenter.default
        lifecycleObservers.append(center.addObserver(forName: UIApplication.didBecomeActiveNotification, object: nil, queue: nil) { [weak self] _ in
            self?.setAppActive(true)
        })
        lifecycleObservers.append(center.addObserver(forName: UIApplication.willResignActiveNotification, object: nil, queue: nil) { [weak self] _ in
            self?.setAppActive(false)
        })
    }

    private func setAppActive(_ active: Bool) {
        appActive = active
        if AFakeClock.isInstalled {
            return // a unit test owns the queue and the frames (AndroidKitTestLoop)
        }
        if active {
            if mTraversalScheduled {
                postTraversalBarrier()
            }
        } else {
            removeTraversalBarrier()
        }
        updateDisplayLink()
    }

    private final class DisplayLinkTarget: NSObject {
        weak var owner: AChoreographer?

        @objc func onDisplayLink(_ link: CADisplayLink) {
            guard let owner = owner else {
                link.invalidate()
                return
            }
            owner.displayLinkFired(link)
        }
    }

    // MARK: Callback queue (Choreographer.CallbackQueue)

    private struct CallbackRecord {
        let dueTime: Int64
        let action: AnyObject
        let token: AnyObject?
    }

    private final class CallbackQueue {
        private var records: [CallbackRecord] = []

        func hasDueCallbacks(_ now: Int64) -> Bool {
            guard let head = records.first else { return false }
            return head.dueTime <= now
        }

        /// Takes the due prefix out of the queue (the queue is sorted by due time).
        func extractDueCallbacks(_ now: Int64) -> [CallbackRecord]? {
            guard let head = records.first, head.dueTime <= now else { return nil }
            var count = 1
            while count < records.count && records[count].dueTime <= now {
                count += 1
            }
            let due = Array(records[0..<count])
            records.removeFirst(count)
            return due
        }

        /// Sorted by due time; equal due times keep posting order.
        func addCallback(_ dueTime: Int64, _ action: AnyObject, _ token: AnyObject?) {
            var index = records.count
            while index > 0 && dueTime < records[index - 1].dueTime {
                index -= 1
            }
            records.insert(CallbackRecord(dueTime: dueTime, action: action, token: token), at: index)
        }

        func removeCallbacks(_ action: AnyObject?, _ token: AnyObject?) {
            records.removeAll { (action == nil || $0.action === action) && (token == nil || $0.token === token) }
        }

        func removeAll() {
            records.removeAll()
        }

        var count: Int {
            return records.count
        }
    }

    // MARK: Test hooks

    /// Callbacks waiting in the ANIMATION queue.
    var pendingAnimationCallbackCountForTests: Int {
        return mAnimationQueue.count
    }

    func resetForTests() {
        mAnimationQueue.removeAll()
        mFrameScheduled = false
        mCallbacksRunning = false
        mLastFrameTimeNanos = Int64.min
        mFrameTimeNanos = 0
        mTraversalScheduled = false
        mTraversalBarrier = nil
        traversalHandler = nil
        postTraversalHandlers.removeAll()
        if let link = displayLink, !link.isPaused {
            link.isPaused = true // the fake clock drives the frames now
        }
    }

    private var hostStateSavedForTests = false
    private var savedHostTraversalHandler: ((Int64) -> Void)? = nil
    private var savedHostPostTraversalHandlers: [PostTraversalEntry] = []

    /// AndroidKitTestLoop.install: keeps the (test host) app's view-system traversal handler and post-traversal
    /// handlers aside while a test owns the Choreographer.
    func saveHostStateForTests() {
        if hostStateSavedForTests {
            return
        }
        hostStateSavedForTests = true
        savedHostTraversalHandler = traversalHandler
        savedHostPostTraversalHandlers = postTraversalHandlers
    }

    /// AndroidKitTestLoop.uninstall: puts the saved handlers back (after the fake clock was removed).
    func restoreHostStateForTests() {
        if !hostStateSavedForTests {
            return
        }
        hostStateSavedForTests = false
        traversalHandler = savedHostTraversalHandler
        postTraversalHandlers = savedHostPostTraversalHandlers.filter { $0.owner != nil }
        savedHostTraversalHandler = nil
        savedHostPostTraversalHandlers = []
        updateDisplayLink()
    }
}

/// Unit-test driver for the Android main thread: a fake clock (AFakeClock), the main ALooper's queue and the
/// Choreographer's vsync frames, run in time order without a run loop or a display link. Vsyncs fall on a grid of
/// `frameIntervalNanos` that starts at install time and only happen while the Choreographer wants a frame.
enum AndroidKitTestLoop {
    nonisolated(unsafe) static var frameIntervalNanos: Int64 = 16_666_667
    nonisolated(unsafe) private static var vsyncOriginNanos: Int64 = 0
    nonisolated(unsafe) private static var lastVsyncNanos = Int64.min

    /// Installs the fake clock at `startNanos` and clears the queue, the Choreographer and the animation handler.
    /// Installing again (without uninstall) restarts the fake timeline.
    static func install(startNanos: Int64 = 1_000_000_000_000) {
        AChoreographer.getInstance().saveHostStateForTests()
        AFakeClock.install(nanos: startNanos)
        resetAndroidMainThread()
        vsyncOriginNanos = startNanos
        lastVsyncNanos = Int64.min
    }

    /// Clears the test's messages, frames and animators, removes the fake clock and gives the host app back its
    /// traversal and post-traversal handlers.
    static func uninstall() {
        resetAndroidMainThread()
        AFakeClock.uninstall()
        AChoreographer.getInstance().restoreHostStateForTests()
        AMainLooperDriver.shared.queueChanged()
    }

    private static func resetAndroidMainThread() {
        ALooper.getMainLooper().mQueue.resetForTests()
        AMainLooperDriver.shared.resetForTests()
        AChoreographer.getInstance().resetForTests()
        AAnimationHandler.getInstance().resetForTests()
        AAnimationUtils.resetForTests()
    }

    static var nowNanos: Int64 {
        return AFakeClock.nanos ?? ASystem.nanoTime()
    }

    static var nowMillis: Int64 {
        return nowNanos / 1_000_000
    }

    /// Dispatches every message that is due now, one at a time, including messages that become due while running.
    static func runDueMessages() {
        while AMainLooperDriver.shared.dispatchNextMessage(ASystemClock.uptimeMillis()) {}
    }

    /// Runs a vsync at the current fake time if the Choreographer wants a frame. Returns true if one ran.
    @discardableResult
    static func runFrame() -> Bool {
        guard AChoreographer.getInstance().wantsFrame else { return false }
        lastVsyncNanos = nowNanos
        AChoreographer.getInstance().performTick(nowNanos)
        return true
    }

    static func advance(millis: Int64) {
        advance(nanos: millis * 1_000_000)
    }

    /// Moves the fake clock forward by `delta`, dispatching messages at their due times and running a vsync on every
    /// grid point while the Choreographer wants a frame, in time order (a message due at a vsync time runs first).
    static func advance(nanos delta: Int64) {
        let target = nowNanos + delta
        while true {
            let queue = ALooper.getMainLooper().mQueue
            var eventTime: Int64? = nil
            var isFrame = false
            if let when = queue.nextDeliverableWhen() {
                eventTime = max(when * 1_000_000, nowNanos)
            }
            if AChoreographer.getInstance().wantsFrame {
                let vsync = nextVsync(atOrAfter: nowNanos)
                if eventTime == nil || vsync <= eventTime! {
                    eventTime = vsync
                    isFrame = true
                }
            }
            guard let time = eventTime, time <= target else { break }
            AFakeClock.nanos = time
            if isFrame {
                lastVsyncNanos = time
                AChoreographer.getInstance().performTick(time)
            } else {
                AMainLooperDriver.shared.dispatchNextMessage(ASystemClock.uptimeMillis())
            }
        }
        AFakeClock.nanos = target
    }

    /// The first grid vsync at or after `time` that is later than the last vsync.
    private static func nextVsync(atOrAfter time: Int64) -> Int64 {
        let interval = frameIntervalNanos
        let offset = max(Int64(0), time - vsyncOriginNanos)
        var vsync = vsyncOriginNanos + (offset + interval - 1) / interval * interval
        while vsync <= lastVsyncNanos {
            vsync += interval
        }
        return vsync
    }
}
