import XCTest
import CoreGraphics
import QuartzCore
@testable import MinikTripleShot

// Area kit-looper: AClock, ALooper (Handler / MessageQueue), AChoreographer and the animators, driven by a fake
// clock (AndroidKitTestLoop). The expected behaviour is AOSP API 37 (ValueAnimator, AnimationHandler,
// Choreographer, MessageQueue, ViewPropertyAnimator sources). The golden Float bit patterns were produced on the JVM
// by work/kit-looper/golden/Golden.java, which holds the interpolator code copied verbatim from AOSP and the
// ValueAnimator / FloatKeyframeSet / IntKeyframeSet arithmetic.
//
// Timeline used by the frame tests: install at T0 = 1e12 ns (uptime 1000000 ms); vsyncs on the 60 Hz grid
// T0 + k * 16666667 ns, i.e. at 1000000, 1000016, 1000033, 1000050, 1000066, 1000083, 1000100, 1000116 ... ms.

private final class LooperFakeView: AAnimatableView {
    var alpha: CGFloat = 1
    var translationX: Float = 0
    var translationY: Float = 0
    var scaleX: Float = 1
    var scaleY: Float = 1
    var rotation: Float = 0
    var left: Float = 0
    var top: Float = 0

    var x: Float {
        get { return left + translationX }
        set { translationX = newValue - left }
    }

    var y: Float {
        get { return top + translationY }
        set { translationY = newValue - top }
    }
}

final class AndroidKitLooperTests: XCTestCase {
    private let T0: Int64 = 1_000_000_000_000

    override func setUp() {
        super.setUp()
        AndroidKitTestLoop.frameIntervalNanos = 16_666_667
        AndroidKitTestLoop.install(startNanos: T0)
    }

    override func tearDown() {
        AndroidKitTestLoop.uninstall()
        AndroidKitTestLoop.frameIntervalNanos = 16_666_667
        super.tearDown()
    }

    private func listener(_ log: @escaping (String) -> Void) -> AAnimatorListenerAdapter {
        return AAnimatorListenerAdapter(onStart: { _ in log("start") }, onEnd: { _ in log("end") },
                                        onCancel: { _ in log("cancel") }, onRepeat: { _ in log("repeat") })
    }

    // MARK: - Clocks

    func testFakeClockDrivesNanoTimeUptimeAndElapsedRealtime() {
        XCTAssertEqual(ASystem.nanoTime(), T0)
        XCTAssertEqual(ASystemClock.uptimeMillis(), 1_000_000)
        XCTAssertEqual(ASystemClock.uptimeNanos(), T0)
        XCTAssertEqual(ASystemClock.elapsedRealtime(), 1_000_000)
        AndroidKitTestLoop.advance(millis: 5)
        XCTAssertEqual(ASystem.nanoTime(), T0 + 5_000_000)
        XCTAssertEqual(ASystemClock.uptimeMillis(), 1_000_005)
        AFakeClock.sleptNanos = 2_000_000_000
        XCTAssertEqual(ASystemClock.elapsedRealtime(), 1_002_005)
        XCTAssertEqual(ASystemClock.uptimeMillis(), 1_000_005)
        let wall = ASystem.currentTimeMillis()
        AndroidKitTestLoop.advance(millis: 250)
        XCTAssertEqual(ASystem.currentTimeMillis(), wall + 250)
    }

    func testRealClocksShareTheSinceBootTimeBaseOfCADisplayLink() {
        AndroidKitTestLoop.uninstall()
        let nanos = ASystem.nanoTime()
        let uptime = ASystemClock.uptimeMillis()
        XCTAssertGreaterThan(nanos, 0)
        XCTAssertGreaterThanOrEqual(uptime, nanos / 1_000_000)
        XCTAssertLessThan(uptime - nanos / 1_000_000, 1_000)
        // elapsedRealtime includes sleep, so it is never behind the uptime clock.
        XCTAssertGreaterThanOrEqual(ASystemClock.elapsedRealtime() + 1, uptime)
        XCTAssertGreaterThan(ASystem.currentTimeMillis(), 1_600_000_000_000)
        XCTAssertGreaterThanOrEqual(ASystem.nanoTime(), nanos)
        // CADisplayLink timestamps use CACurrentMediaTime(), the same clock as System.nanoTime() here.
        let media = Int64((CACurrentMediaTime() * 1_000_000_000).rounded())
        XCTAssertLessThan(abs(media - ASystem.nanoTime()), 50_000_000)
        AndroidKitTestLoop.install(startNanos: T0)
    }

    func testLogCallsWorkOnTheMainThreadAndOffIt() {
        ALog.d("TRIPLE_TEST", "main")
        ALog.e("TRIPLE_TEST", "with error", NSError(domain: "kit-looper", code: 1))
        let semaphore = DispatchSemaphore(value: 0)
        let thread = Thread {
            ALog.i("TRIPLE_TEST", "background")
            ALog.w("TRIPLE_TEST_2", "background")
            semaphore.signal()
        }
        thread.start()
        XCTAssertEqual(semaphore.wait(timeout: .now() + 5), .success)
        // Android's default level for every tag is INFO.
        XCTAssertTrue(ALog.isLoggable("TRIPLE_TEST", ALog.INFO))
        XCTAssertFalse(ALog.isLoggable("TRIPLE_TEST", ALog.DEBUG))
    }

    // MARK: - Test hooks

    func testInstallSetsTheHostTraversalHandlerAsideAndUninstallRestoresIt() {
        let c = AChoreographer.getInstance()
        AndroidKitTestLoop.uninstall() // back to the state setUp saved (the test host's)
        let hostTraversal = c.traversalHandler
        var hostTraversals = 0
        c.traversalHandler = { _ in hostTraversals += 1 }
        AndroidKitTestLoop.install(startNanos: T0)
        XCTAssertNil(c.traversalHandler)
        c.traversalHandler = { _ in XCTFail("a test's handler must not survive uninstall") }
        AndroidKitTestLoop.uninstall()
        c.traversalHandler?(0)
        XCTAssertEqual(hostTraversals, 1)
        c.traversalHandler = hostTraversal
        AndroidKitTestLoop.install(startNanos: T0)
    }

    // MARK: - Handler / MessageQueue

    func testMessagesRunByDueTimeThenPostingOrder() {
        let h = AHandler(ALooper.getMainLooper())
        var log: [String] = []
        h.postDelayed({ log.append("B10") }, 10)
        h.post { log.append("A") }
        h.postDelayed({ log.append("D5") }, 5)
        h.post { log.append("C") }
        h.postDelayed({ log.append("E10") }, 10)
        h.postAtFrontOfQueue(ARunnable { log.append("F") })
        AndroidKitTestLoop.runDueMessages()
        XCTAssertEqual(log, ["F", "A", "C"])
        AndroidKitTestLoop.advance(millis: 4)
        XCTAssertEqual(log, ["F", "A", "C"])
        AndroidKitTestLoop.advance(millis: 1)
        XCTAssertEqual(log, ["F", "A", "C", "D5"])
        AndroidKitTestLoop.advance(millis: 5)
        XCTAssertEqual(log, ["F", "A", "C", "D5", "B10", "E10"])
    }

    func testPostAtFrontOfQueueGoesAheadOfEarlierFrontPosts() {
        let h = AHandler()
        var log: [String] = []
        h.post { log.append("normal") }
        h.postAtFrontOfQueue(ARunnable { log.append("front1") })
        h.postAtFrontOfQueue(ARunnable { log.append("front2") })
        AndroidKitTestLoop.runDueMessages()
        XCTAssertEqual(log, ["front2", "front1", "normal"])
    }

    func testNegativeDelayRunsLikeZeroDelay() {
        let h = AHandler()
        var log: [String] = []
        h.post { log.append("first") }
        h.postDelayed({ log.append("negative") }, -50)
        AndroidKitTestLoop.runDueMessages()
        XCTAssertEqual(log, ["first", "negative"])
    }

    func testMessagePostedWhileDispatchingRunsAfterTheMessagesAlreadyDue() {
        let h = AHandler()
        var log: [String] = []
        h.post {
            log.append("A")
            h.post { log.append("C") }
        }
        h.post { log.append("B") }
        AndroidKitTestLoop.runDueMessages()
        XCTAssertEqual(log, ["A", "B", "C"])
    }

    func testDelayedMessageRunsExactlyAtItsUptime() {
        let h = AHandler()
        var ranAt: [Int64] = []
        h.postDelayed({ ranAt.append(ASystemClock.uptimeMillis()) }, 100)
        AndroidKitTestLoop.advance(millis: 99)
        XCTAssertEqual(ranAt, [])
        AndroidKitTestLoop.advance(millis: 1)
        XCTAssertEqual(ranAt, [1_000_100])
    }

    func testPostAtTimeUsesTheGivenUptime() {
        let h = AHandler()
        var log: [Int64] = []
        h.postAtTime(ARunnable { log.append(AndroidKitTestLoop.nowMillis) }, 1_000_040)
        AndroidKitTestLoop.advance(millis: 100)
        XCTAssertEqual(log, [1_000_040])
    }

    func testRemoveCallbacksMatchesTheRunnableInstanceAndOnlyThatHandler() {
        let h1 = AHandler(ALooper.getMainLooper())
        let h2 = AHandler(ALooper.getMainLooper())
        var count = 0
        let r = ARunnable { count += 1 }
        let other = ARunnable { count += 100 }
        h1.post(r)
        h1.postDelayed(r, 5)
        h2.post(r)
        h1.post(other)
        XCTAssertTrue(h1.hasCallbacks(r))
        h1.removeCallbacks(r)
        XCTAssertFalse(h1.hasCallbacks(r))
        XCTAssertTrue(h2.hasCallbacks(r))
        XCTAssertTrue(h1.hasCallbacks(other))
        AndroidKitTestLoop.advance(millis: 10)
        XCTAssertEqual(count, 101)
    }

    func testAnEqualLookingRunnableIsNotRemoved() {
        let h = AHandler()
        var log: [String] = []
        let a = ARunnable { log.append("a") }
        let b = ARunnable { log.append("a") }
        h.post(a)
        h.removeCallbacks(b)
        AndroidKitTestLoop.runDueMessages()
        XCTAssertEqual(log, ["a"])
    }

    func testRemoveCallbacksAndMessagesNullClearsOnlyThatHandler() {
        let game = AHandler(ALooper.getMainLooper())
        let other = AHandler(ALooper.getMainLooper())
        var log: [String] = []
        game.post { log.append("game1") }
        game.postDelayed({ log.append("game2") }, 10)
        other.postDelayed({ log.append("other") }, 5)
        game.removeCallbacksAndMessages(nil)
        AndroidKitTestLoop.advance(millis: 20)
        XCTAssertEqual(log, ["other"])
    }

    func testRemoveCallbacksAndMessagesWithATokenOnlyRemovesThatToken() {
        let h = AHandler()
        let token = NSObject()
        var log: [String] = []
        h.postDelayed(ARunnable { log.append("tokened") }, token, 5)
        h.postDelayed(ARunnable { log.append("plain") }, 5)
        h.removeCallbacksAndMessages(token)
        AndroidKitTestLoop.advance(millis: 10)
        XCTAssertEqual(log, ["plain"])
    }

    func testRunnableRemovingItselfWhileRunningStillFinishesThatRun() {
        let h = AHandler()
        var log: [String] = []
        var r: ARunnable!
        r = ARunnable {
            log.append("run")
            h.removeCallbacks(r)
        }
        h.post(r)
        h.postDelayed(r, 5)
        AndroidKitTestLoop.advance(millis: 10)
        XCTAssertEqual(log, ["run"])
    }

    func testSelfReschedulingRunnableTicksAtItsDelay() {
        let h = AHandler()
        var ticks: [Int64] = []
        let tick = ARunnable(withSelf: { r in
            ticks.append(AndroidKitTestLoop.nowMillis)
            if ticks.count < 3 {
                h.postDelayed(r, 1000)
            }
        })
        h.postDelayed(tick, 1000)
        AndroidKitTestLoop.advance(millis: 5000)
        XCTAssertEqual(ticks, [1_001_000, 1_002_000, 1_003_000])
    }

    func testHandlerCallbackReceivesWhatMessagesInOrderAndRemoveMessagesDropsThem() {
        var log: [String] = []
        let h = AHandler(ALooper.getMainLooper(), { msg in
            log.append("what \(msg.what) arg1 \(msg.arg1)")
            return true
        })
        let m = h.obtainMessage(7)
        m.arg1 = 3
        h.sendMessageDelayed(m, 10)
        h.sendEmptyMessage(1)
        h.sendEmptyMessageDelayed(2, 5)
        h.sendEmptyMessageDelayed(9, 5)
        XCTAssertTrue(h.hasMessages(9))
        h.removeMessages(9)
        XCTAssertFalse(h.hasMessages(9))
        AndroidKitTestLoop.advance(millis: 20)
        XCTAssertEqual(log, ["what 1 arg1 0", "what 2 arg1 0", "what 7 arg1 3"])
    }

    func testMainLooperIdentity() {
        XCTAssertTrue(ALooper.myLooper() === ALooper.getMainLooper())
        XCTAssertTrue(ALooper.myLooper() == ALooper.getMainLooper())
        XCTAssertTrue(AHandler().getLooper() === ALooper.getMainLooper())
    }

    // MARK: - Sync barrier (ViewRootImpl.scheduleTraversals)

    func testTraversalBarrierHoldsBackMessagesPostedAfterTheRequestUntilTheTraversal() {
        var log: [String] = []
        let choreographer = AChoreographer.getInstance()
        choreographer.traversalHandler = { _ in log.append("traversal") }
        let h = AHandler()
        h.post { log.append("before") }
        choreographer.requestTraversal()
        h.post { log.append("after") }
        AndroidKitTestLoop.runDueMessages()
        XCTAssertEqual(log, ["before"])
        AndroidKitTestLoop.advance(millis: 17)
        XCTAssertEqual(log, ["before", "traversal", "after"])
    }

    func testAsynchronousMessagesBypassTheTraversalBarrier() {
        var log: [String] = []
        let sync = AHandler(ALooper.getMainLooper())
        let async = AHandler.createAsync(ALooper.getMainLooper())
        AChoreographer.getInstance().requestTraversal()
        sync.post { log.append("sync") }
        async.post { log.append("async") }
        AndroidKitTestLoop.runDueMessages()
        XCTAssertEqual(log, ["async"])
        XCTAssertTrue(AndroidKitTestLoop.runFrame())
        AndroidKitTestLoop.runDueMessages()
        XCTAssertEqual(log, ["async", "sync"])
    }

    // MARK: - Choreographer

    func testFrameCallbacksAndAnimationRunnablesRunInPostingOrder() {
        var log: [String] = []
        let c = AChoreographer.getInstance()
        c.postFrameCallback(AChoreographer.FrameCallback { _ in log.append("fc1") })
        c.postAnimationRunnable(ARunnable { log.append("r1") })
        c.postFrameCallback(AChoreographer.FrameCallback { _ in log.append("fc2") })
        c.postAnimationRunnable(ARunnable { log.append("r2") })
        XCTAssertTrue(AndroidKitTestLoop.runFrame())
        XCTAssertEqual(log, ["fc1", "r1", "fc2", "r2"])
        XCTAssertFalse(AndroidKitTestLoop.runFrame())
    }

    func testCallbacksPostedDuringAFrameRunInTheNextFrame() {
        var log: [String] = []
        let c = AChoreographer.getInstance()
        var loop: ARunnable!
        loop = ARunnable {
            log.append("loop \(AndroidKitTestLoop.nowMillis)")
            if log.count < 3 {
                c.postAnimationRunnable(loop)
            }
        }
        AndroidKitTestLoop.advance(millis: 1)
        c.postAnimationRunnable(loop)
        AndroidKitTestLoop.advance(millis: 100)
        XCTAssertEqual(log, ["loop 1000016", "loop 1000033", "loop 1000050"])
    }

    func testFrameTimeIsTheVsyncTime() {
        var times: [Int64] = []
        let c = AChoreographer.getInstance()
        AndroidKitTestLoop.advance(millis: 1)
        c.postFrameCallback(AChoreographer.FrameCallback { t in times.append(t) })
        AndroidKitTestLoop.advance(millis: 16)
        XCTAssertEqual(times, [T0 + 16_666_667])
        XCTAssertEqual(c.lastFrameTimeNanos, T0 + 16_666_667)
    }

    func testCallbackRemovedDuringTheFrameStillRunsWhenItWasAlreadyTakenForThatFrame() {
        // Choreographer.doCallbacks takes the due callbacks out of the queue before running any of them.
        var log: [String] = []
        let c = AChoreographer.getInstance()
        let r2 = ARunnable { log.append("r2") }
        let r1 = ARunnable {
            log.append("r1")
            c.removeAnimationRunnable(r2)
        }
        c.postAnimationRunnable(r1)
        c.postAnimationRunnable(r2)
        AndroidKitTestLoop.runFrame()
        XCTAssertEqual(log, ["r1", "r2"])
    }

    func testCallbackRemovedBeforeTheFrameDoesNotRun() {
        var log: [String] = []
        let c = AChoreographer.getInstance()
        let r = ARunnable { log.append("r") }
        let fc = AChoreographer.FrameCallback { _ in log.append("fc") }
        c.postAnimationRunnable(r)
        c.postFrameCallback(fc)
        c.removeAnimationRunnable(r)
        c.removeFrameCallback(fc)
        AndroidKitTestLoop.advance(millis: 50)
        XCTAssertEqual(log, [])
    }

    func testDelayedFrameCallbackRunsOnTheFirstFrameAfterItsDueTime() {
        var log: [Int64] = []
        let c = AChoreographer.getInstance()
        c.postFrameCallbackDelayed(AChoreographer.FrameCallback { _ in log.append(AndroidKitTestLoop.nowMillis) }, 50)
        XCTAssertFalse(c.wantsFrame)
        AndroidKitTestLoop.advance(millis: 49)
        XCTAssertEqual(log, [])
        AndroidKitTestLoop.advance(millis: 2)
        XCTAssertEqual(log, [1_000_050])
    }

    func testMessagesDueBeforeTheVsyncRunBeforeTheFrame() {
        var log: [String] = []
        let c = AChoreographer.getInstance()
        let h = AHandler()
        c.postAnimationRunnable(ARunnable { log.append("frame") })
        h.post { log.append("message") }
        XCTAssertTrue(AndroidKitTestLoop.runFrame())
        XCTAssertEqual(log, ["message", "frame"])
    }

    func testFrameRequestedByAMessageDrainedBeforeTheVsyncWaitsForTheNextVsync() {
        var log: [String] = []
        let c = AChoreographer.getInstance()
        let h = AHandler()
        c.addPostTraversalHandler(self) { _ in log.append("post") }
        h.post {
            log.append("message")
            c.postAnimationRunnable(ARunnable { log.append("runnable") })
        }
        XCTAssertTrue(AndroidKitTestLoop.runFrame())
        XCTAssertEqual(log, ["message", "post"])
        AndroidKitTestLoop.advance(millis: 17)
        XCTAssertEqual(log, ["message", "post", "runnable", "post"])
        c.removePostTraversalHandler(self)
        XCTAssertFalse(c.wantsFrame)
    }

    func testTraversalRequestedDuringTheAnimationPhaseRunsInTheSameFrame() {
        var log: [String] = []
        let c = AChoreographer.getInstance()
        c.traversalHandler = { t in log.append("traversal \(t)") }
        c.postFrameCallback(AChoreographer.FrameCallback { t in
            log.append("frame \(t)")
            c.requestTraversal()
        })
        AndroidKitTestLoop.runFrame()
        XCTAssertEqual(log, ["frame \(T0)", "traversal \(T0)"])
    }

    func testTraversalRequestedDuringTheTraversalRunsInTheNextFrame() {
        var count = 0
        let c = AChoreographer.getInstance()
        c.traversalHandler = { _ in
            count += 1
            if count == 1 {
                c.requestTraversal()
            }
        }
        c.requestTraversal()
        AndroidKitTestLoop.runFrame()
        XCTAssertEqual(count, 1)
        XCTAssertTrue(c.isTraversalScheduled)
        AndroidKitTestLoop.advance(millis: 17)
        XCTAssertEqual(count, 2)
        XCTAssertFalse(c.isTraversalScheduled)
    }

    func testPostTraversalHandlersRunAfterTheTraversalOnEveryTick() {
        var log: [String] = []
        let c = AChoreographer.getInstance()
        let owner = NSObject()
        c.traversalHandler = { _ in log.append("traversal") }
        c.addPostTraversalHandler(owner) { _ in log.append("post") }
        c.postFrameCallback(AChoreographer.FrameCallback { _ in
            log.append("frame")
            c.requestTraversal()
        })
        XCTAssertTrue(AndroidKitTestLoop.runFrame())
        XCTAssertEqual(log, ["frame", "traversal", "post"])
        AndroidKitTestLoop.advance(millis: 34)
        XCTAssertEqual(log, ["frame", "traversal", "post", "post", "post"])
        c.removePostTraversalHandler(owner)
        XCTAssertFalse(c.wantsFrame)
    }

    // MARK: - ValueAnimator: start, frames, end

    func testStartCallsOnStartAndDeliversASynchronousZeroUpdate() {
        let animator = AValueAnimator.ofFloat(0, 1)
        animator.duration = 100
        var log: [String] = []
        animator.addUpdateListener { a in log.append("update \(a.animatedValueFloat) running=\(a.isRunning)") }
        animator.addListener(AAnimatorListenerAdapter(onStart: { a in log.append("start running=\(a.isRunning)") },
                                                      onEnd: { _ in log.append("end") },
                                                      onCancel: { _ in log.append("cancel") }))
        XCTAssertFalse(animator.isStarted)
        XCTAssertFalse(animator.isRunning)
        animator.start()
        XCTAssertEqual(log, ["start running=true", "update 0.0 running=true"])
        XCTAssertTrue(animator.isRunning)
        XCTAssertTrue(animator.isStarted)
        XCTAssertEqual(animator.animatedFraction, 0)
        XCTAssertEqual(AAnimationHandler.getInstance().getAnimationCount(), 1)
        XCTAssertEqual(AValueAnimator.getCurrentAnimationsCount(), 1)
    }

    func testThePlayClockStartsAtTheFirstFrameAfterStart() {
        AndroidKitTestLoop.advance(millis: 1)
        let animator = AValueAnimator.ofFloat(0, 1)
        animator.duration = 100
        animator.interpolator = ALinearInterpolator()
        var values: [Float] = []
        var times: [Int64] = []
        var log: [String] = []
        animator.addUpdateListener { a in
            values.append(a.animatedValueFloat)
            times.append(AndroidKitTestLoop.nowMillis)
        }
        animator.addListener(AAnimatorListenerAdapter(onEnd: { a in log.append("end running=\(a.isRunning) started=\(a.isStarted)") }))
        animator.start()
        AndroidKitTestLoop.advance(millis: 200)
        XCTAssertEqual(times, [1_000_001, 1_000_016, 1_000_033, 1_000_050, 1_000_066, 1_000_083, 1_000_100, 1_000_116])
        XCTAssertEqual(values, [0, 0, Float(17) / 100, Float(34) / 100, Float(50) / 100, Float(67) / 100, Float(84) / 100, 1])
        XCTAssertEqual(log, ["end running=false started=false"])
        XCTAssertFalse(animator.isRunning)
        XCTAssertEqual(AAnimationHandler.getInstance().getAnimationCount(), 0)
        XCTAssertFalse(AChoreographer.getInstance().wantsFrame)
    }

    func testZeroDurationSkipsToTheEndValueAtStartAndEndsOnTheFirstFrame() {
        let animator = AValueAnimator.ofFloat(3, 7)
        animator.duration = 0
        var log: [String] = []
        animator.addUpdateListener { a in log.append("update \(a.animatedValueFloat)") }
        animator.addListener(listener { log.append($0) })
        animator.start()
        XCTAssertEqual(log, ["start", "update 7.0"])
        AndroidKitTestLoop.advance(millis: 20)
        XCTAssertEqual(log, ["start", "update 7.0", "update 7.0", "end"])
    }

    func testDefaultInterpolatorIsAccelerateDecelerateAndNilMakesItLinear() {
        let animator = AValueAnimator.ofFloat(0, 1)
        XCTAssertTrue(animator.interpolator is AAccelerateDecelerateInterpolator)
        XCTAssertEqual(animator.duration, 300)
        animator.interpolator = nil
        XCTAssertTrue(animator.interpolator is ALinearInterpolator)
    }

    func testAnimatedValueTypes() {
        let f = AValueAnimator.ofFloat(0, 2)
        let i = AValueAnimator.ofInt(0, 5)
        f.start()
        i.start()
        XCTAssertNotNil(f.animatedValue as? Float)
        XCTAssertNotNil(i.animatedValue as? Int)
        XCTAssertEqual(f.animatedValue as? Float, 0)
        XCTAssertEqual(i.animatedValue as? Int, 0)
        f.end()
        i.end()
        XCTAssertEqual(f.animatedValue as? Float, 2)
        XCTAssertEqual(i.animatedValueInt, 5)
    }

    // MARK: - ValueAnimator: cancel / end

    func testCancelCallsOnCancelThenOnEndOnceAndStopsTheUpdates() {
        let animator = AValueAnimator.ofFloat(0, 1)
        animator.duration = 200
        var log: [String] = []
        var updates = 0
        animator.addUpdateListener { _ in updates += 1 }
        animator.addListener(AAnimatorListenerAdapter(onStart: { _ in log.append("start") },
                                                      onEnd: { a in log.append("end running=\(a.isRunning)") },
                                                      onCancel: { a in log.append("cancel running=\(a.isRunning)") }))
        animator.start()
        AndroidKitTestLoop.advance(millis: 50)
        let updatesAtCancel = updates
        let valueAtCancel = animator.animatedValueFloat
        animator.cancel()
        XCTAssertEqual(log, ["start", "cancel running=true", "end running=false"])
        XCTAssertFalse(animator.isRunning)
        XCTAssertFalse(animator.isStarted)
        animator.cancel()
        animator.end()
        XCTAssertEqual(log.count, 5) // end() on an ended animator restarts and ends it (AOSP): start, end
        AndroidKitTestLoop.advance(millis: 300)
        XCTAssertEqual(updates, updatesAtCancel + 1) // only end()'s jump to the end value
        XCTAssertNotEqual(valueAtCancel, 1)
        XCTAssertEqual(animator.animatedValueFloat, 1)
        XCTAssertEqual(AAnimationHandler.getInstance().getAnimationCount(), 0)
    }

    func testCancelOfANeverStartedAnimatorCallsNothing() {
        let animator = AValueAnimator.ofFloat(0, 1)
        var log: [String] = []
        animator.addListener(listener { log.append($0) })
        animator.cancel()
        XCTAssertEqual(log, [])
    }

    func testCancelAfterTheAnimatorEndedCallsNothing() {
        let animator = AValueAnimator.ofFloat(0, 1)
        animator.duration = 50
        var log: [String] = []
        animator.addListener(listener { log.append($0) })
        animator.start()
        AndroidKitTestLoop.advance(millis: 100)
        XCTAssertEqual(log, ["start", "end"])
        animator.cancel()
        XCTAssertEqual(log, ["start", "end"])
    }

    func testEndJumpsToTheEndValueThenCallsOnEnd() {
        let animator = AValueAnimator.ofFloat(10, 20)
        animator.duration = 300
        var log: [String] = []
        animator.addUpdateListener { a in log.append("update \(a.animatedValueFloat)") }
        animator.addListener(listener { log.append($0) })
        animator.start()
        AndroidKitTestLoop.advance(millis: 40)
        log.removeAll()
        animator.end()
        XCTAssertEqual(log, ["update 20.0", "end"])
        XCTAssertFalse(animator.isRunning)
        AndroidKitTestLoop.advance(millis: 100)
        XCTAssertEqual(log, ["update 20.0", "end"])
    }

    func testEndOnANeverStartedAnimatorStartsJumpsAndEnds() {
        let animator = AValueAnimator.ofFloat(0, 5)
        var log: [String] = []
        animator.addUpdateListener { a in log.append("update \(a.animatedValueFloat)") }
        animator.addListener(listener { log.append($0) })
        animator.end()
        XCTAssertEqual(log, ["start", "update 5.0", "end"])
    }

    func testCancelInsideTheSynchronousFirstUpdate() {
        // The 1v1 dunk block pattern: cancel() from the update listener during start().
        let animator = AValueAnimator.ofFloat(0, 1)
        animator.duration = 690
        animator.interpolator = ALinearInterpolator()
        var log: [String] = []
        var cancelled = false
        animator.addUpdateListener { a in
            log.append("update \(a.animatedValueFloat)")
            if !cancelled {
                cancelled = true
                a.cancel()
            }
        }
        animator.addListener(listener { log.append($0) })
        animator.start()
        XCTAssertEqual(log, ["start", "update 0.0", "cancel", "end"])
        XCTAssertFalse(animator.isRunning)
        AndroidKitTestLoop.advance(millis: 100)
        XCTAssertEqual(log, ["start", "update 0.0", "cancel", "end"])
        XCTAssertEqual(AAnimationHandler.getInstance().getAnimationCount(), 0)
    }

    func testCancelInsideAFrameUpdateEndsOnce() {
        let animator = AValueAnimator.ofFloat(0, 1)
        animator.duration = 100
        animator.interpolator = ALinearInterpolator()
        var log: [String] = []
        animator.addUpdateListener { a in
            log.append("update")
            if a.animatedValueFloat > 0.3 {
                a.cancel()
            }
        }
        animator.addListener(listener { log.append($0) })
        AndroidKitTestLoop.advance(millis: 1)
        animator.start()
        AndroidKitTestLoop.advance(millis: 200)
        // sync 0, frame 0, 0.17, 0.34 -> cancel
        XCTAssertEqual(log, ["start", "update", "update", "update", "update", "cancel", "end"])
    }

    func testListenersAddedOrRemoved() {
        let animator = AValueAnimator.ofFloat(0, 1)
        var log: [String] = []
        let first = listener { log.append("first " + $0) }
        let second = listener { log.append("second " + $0) }
        animator.addListener(first)
        animator.addListener(second)
        animator.removeListener(first)
        animator.start()
        XCTAssertEqual(log, ["second start"])
        animator.removeAllListeners()
        XCTAssertNil(animator.listeners)
        animator.cancel()
        XCTAssertEqual(log, ["second start"])
        let updateListener = animator.addUpdateListener { _ in log.append("update") }
        animator.removeUpdateListener(updateListener)
        animator.start()
        XCTAssertEqual(log, ["second start"])
    }

    // MARK: - ValueAnimator: start delay, pause, repeat

    func testStartDelayKeepsIsRunningFalseUntilTheDelayHasPassed() {
        let animator = AValueAnimator.ofFloat(0, 1)
        animator.duration = 100
        animator.startDelay = 50
        animator.interpolator = ALinearInterpolator()
        var log: [String] = []
        animator.addUpdateListener { a in log.append("update \(AndroidKitTestLoop.nowMillis) \(a.animatedValueFloat)") }
        animator.addListener(listener { log.append($0 + " \(AndroidKitTestLoop.nowMillis)") })
        animator.start()
        XCTAssertEqual(log, [])
        XCTAssertTrue(animator.isStarted)
        XCTAssertFalse(animator.isRunning)
        AndroidKitTestLoop.advance(millis: 40)
        XCTAssertEqual(log, [])
        XCTAssertFalse(animator.isRunning)
        // First frame 1000000: start time 1000050; the frame at 1000050 starts it.
        AndroidKitTestLoop.advance(millis: 11)
        XCTAssertEqual(log, ["start 1000050", "update 1000050 0.0"])
        XCTAssertTrue(animator.isRunning)
        AndroidKitTestLoop.advance(millis: 100)
        XCTAssertEqual(log.last, "end 1000150")
        XCTAssertEqual(log[log.count - 2], "update 1000150 1.0")
    }

    func testNegativeStartDelayIsClampedToZero() {
        let animator = AValueAnimator.ofFloat(0, 1)
        animator.startDelay = -20
        XCTAssertEqual(animator.startDelay, 0)
    }

    func testCancelDuringTheStartDelayCallsStartCancelEnd() {
        let animator = AValueAnimator.ofFloat(0, 1)
        animator.startDelay = 100
        var log: [String] = []
        animator.addListener(listener { log.append($0) })
        animator.start()
        AndroidKitTestLoop.advance(millis: 20)
        animator.cancel()
        XCTAssertEqual(log, ["start", "cancel", "end"])
    }

    func testPauseExcludesThePausedTimeFromThePlayClock() {
        let animator = AValueAnimator.ofFloat(0, 1)
        animator.duration = 100
        animator.interpolator = ALinearInterpolator()
        var values: [Float] = []
        var pauseLog: [String] = []
        animator.addUpdateListener { a in values.append(a.animatedValueFloat) }
        animator.addPauseListener(LooperPauseRecorder { pauseLog.append($0) })
        animator.start()
        AndroidKitTestLoop.advance(millis: 34) // frames 1000000 (start), 1000016, 1000033
        XCTAssertEqual(values, [0, 0, Float(16) / 100, Float(33) / 100])
        animator.pause()
        XCTAssertTrue(animator.isPaused)
        XCTAssertTrue(animator.isRunning)
        AndroidKitTestLoop.advance(millis: 100) // frame 1000050 records the pause time and leaves the loop
        XCTAssertEqual(values.count, 4)
        XCTAssertFalse(AChoreographer.getInstance().wantsFrame)
        animator.resume()
        XCTAssertFalse(animator.isPaused)
        AndroidKitTestLoop.advance(millis: 20) // frame 1000150: start time moves by 1000150 - 1000050
        XCTAssertEqual(values.last, Float(50) / 100)
        XCTAssertEqual(pauseLog, ["pause", "resume"])
    }

    func testRepeatReverseRunsForwardThenBackwardAndEndsAtTheStartValue() {
        // 25 ms frames: quarter fractions, so every value is exact in Float.
        AndroidKitTestLoop.frameIntervalNanos = 25_000_000
        AndroidKitTestLoop.install(startNanos: T0)
        let animator = AValueAnimator.ofFloat(0, 10)
        animator.duration = 100
        animator.interpolator = ALinearInterpolator()
        animator.repeatCount = 1
        animator.repeatMode = AValueAnimator.REVERSE
        XCTAssertEqual(animator.totalDuration, 200)
        var values: [Float] = []
        var log: [String] = []
        animator.addUpdateListener { a in values.append(a.animatedValueFloat) }
        animator.addListener(listener { log.append($0 + " \(AndroidKitTestLoop.nowMillis)") })
        animator.start()
        AndroidKitTestLoop.advance(millis: 300)
        XCTAssertEqual(values, [0, 0, 2.5, 5, 7.5, 10, 7.5, 5, 2.5, 0])
        XCTAssertEqual(log, ["start 1000000", "repeat 1000100", "end 1000200"])
    }

    func testRepeatRestartStartsEachIterationFromTheStartValue() {
        AndroidKitTestLoop.frameIntervalNanos = 25_000_000
        AndroidKitTestLoop.install(startNanos: T0)
        let animator = AValueAnimator.ofFloat(0, 4)
        animator.duration = 100
        animator.interpolator = ALinearInterpolator()
        animator.repeatCount = 2
        var values: [Float] = []
        animator.addUpdateListener { a in values.append(a.animatedValueFloat) }
        animator.start()
        AndroidKitTestLoop.advance(millis: 400)
        XCTAssertEqual(values, [0, 0, 1, 2, 3, 4, 1, 2, 3, 4, 1, 2, 3, 4])
        XCTAssertFalse(animator.isRunning)
    }

    // MARK: - ValueAnimator inside the frame (one AnimationHandler frame callback)

    func testAnimatorStartedInAnAnimationRunnableBeforeTheAnimationHandlerGetsItsFirstFrameInThatFrame() {
        let c = AChoreographer.getInstance()
        let first = AValueAnimator.ofFloat(0, 1)
        first.duration = 1000
        let second = AValueAnimator.ofFloat(0, 1)
        second.duration = 1000
        var secondUpdates: [Int64] = []
        second.addUpdateListener { _ in secondUpdates.append(AndroidKitTestLoop.nowMillis) }
        AndroidKitTestLoop.advance(millis: 1)
        c.postAnimationRunnable(ARunnable { second.start() }) // queued before the AnimationHandler callback
        first.start()                                         // posts the AnimationHandler frame callback
        AndroidKitTestLoop.advance(millis: 16)
        XCTAssertEqual(secondUpdates, [1_000_016, 1_000_016])
    }

    func testAnimatorStartedInAnAnimationRunnableAfterTheAnimationHandlerWaitsForTheNextFrame() {
        let c = AChoreographer.getInstance()
        let first = AValueAnimator.ofFloat(0, 1)
        first.duration = 1000
        let second = AValueAnimator.ofFloat(0, 1)
        second.duration = 1000
        var secondUpdates: [Int64] = []
        second.addUpdateListener { _ in secondUpdates.append(AndroidKitTestLoop.nowMillis) }
        AndroidKitTestLoop.advance(millis: 1)
        first.start()                                         // the AnimationHandler callback is queued first
        c.postAnimationRunnable(ARunnable { second.start() })
        AndroidKitTestLoop.advance(millis: 16)
        XCTAssertEqual(secondUpdates, [1_000_016])
        AndroidKitTestLoop.advance(millis: 17)
        XCTAssertEqual(secondUpdates, [1_000_016, 1_000_033])
    }

    func testAnimatorStartedFromAnotherAnimatorsEndListenerGetsItsFirstFrameInTheNextFrame() {
        // AOSP oracle: [firstEnd 1000050, second 1000050 0.0, second 1000066 0.0, second 1000083 0.17] count=1
        let first = AValueAnimator.ofFloat(0, 1)
        first.duration = 50
        let second = AValueAnimator.ofFloat(0, 1)
        second.duration = 100
        second.interpolator = ALinearInterpolator()
        var log: [String] = []
        second.addUpdateListener { a in log.append("second \(AndroidKitTestLoop.nowMillis) \(a.animatedValueFloat)") }
        first.addListener(AAnimatorListenerAdapter(onEnd: { _ in
            log.append("firstEnd \(AndroidKitTestLoop.nowMillis)")
            second.start()
        }))
        first.start()
        AndroidKitTestLoop.advance(millis: 100)
        XCTAssertEqual(log, ["firstEnd 1000050", "second 1000050 0.0", "second 1000066 0.0", "second 1000083 0.17"])
        XCTAssertEqual(AValueAnimator.getCurrentAnimationsCount(), 1)
    }

    func testRestartingARunningAnimatorStartsOverWithoutAnotherStartOrEnd() {
        // AOSP oracle: start() on a running animator re-delivers fraction 0 at once and restarts the play clock at
        // the next frame; onAnimationStart is not called again and onAnimationEnd only once, at the very end.
        let animator = AValueAnimator.ofFloat(0, 1)
        animator.duration = 100
        animator.interpolator = ALinearInterpolator()
        var log: [String] = []
        animator.addUpdateListener { a in log.append("update \(AndroidKitTestLoop.nowMillis) \(a.animatedValueFloat)") }
        animator.addListener(listener { log.append($0 + " \(AndroidKitTestLoop.nowMillis)") })
        animator.start()
        AndroidKitTestLoop.advance(millis: 40)
        animator.start()
        AndroidKitTestLoop.advance(millis: 200)
        XCTAssertEqual(log, ["start 1000000", "update 1000000 0.0", "update 1000000 0.0", "update 1000016 0.16",
                             "update 1000033 0.33", "update 1000040 0.0", "update 1000050 0.0", "update 1000066 0.16",
                             "update 1000083 0.33", "update 1000100 0.5", "update 1000116 0.66", "update 1000133 0.83",
                             "update 1000150 1.0", "end 1000150"])
    }

    // MARK: - Golden timelines (JVM, AOSP arithmetic)

    /// Starts `animator` at 1000001 ms and returns every update value: the synchronous one, then one per frame at
    /// 1000016, 1000033, ... ms (up to `frames` frames).
    private func timeline(_ animator: AValueAnimator, frames: Int64) -> [Float] {
        AndroidKitTestLoop.advance(millis: 1)
        var values: [Float] = []
        animator.addUpdateListener { a in values.append(a.animatedValueFloat) }
        animator.start()
        AndroidKitTestLoop.advance(nanos: frames * 16_666_667 - 1_000_000)
        return values
    }

    private func timelineBits(_ animator: AValueAnimator, frames: Int64) -> [UInt32] {
        return timeline(animator, frames: frames).map { $0.bitPattern }
    }

    func testGoldenWalkDecelerate455() {
        // Human walk (TripleShotCourtView): ofFloat(0f, 1f), 455 ms, DecelerateInterpolator().
        let animator = AValueAnimator.ofFloat(0, 1)
        animator.duration = 455
        animator.interpolator = ADecelerateInterpolator()
        var ended = false
        animator.addListener(AAnimatorListenerAdapter(onEnd: { _ in ended = true }))
        let got = timelineBits(animator, frames: 29)
        let golden: [UInt32] = [0x00000000, 0x3D962DB0, 0x3E1351C8, 0x3E54B074, 0x3E8BAF56, 0x3EAB9882, 0x3EC852D8,
                                0x3EE575AA, 0x3F009542, 0x3F0CF7EE, 0x3F196F2F, 0x3F252F75, 0x3F2F97A2, 0x3F39F4BC,
                                0x3F439ADB, 0x3F4C0889, 0x3F544B7A, 0x3F5BD772, 0x3F624AA1, 0x3F68736B, 0x3F6DE53C,
                                0x3F725DEB, 0x3F766C8E, 0x3F79C438, 0x3F7C4267, 0x3F7E36E3, 0x3F7F7466, 0x3F7FF816,
                                0x3F800000]
        XCTAssertEqual(got, [0x00000000] + golden)
        XCTAssertTrue(ended)
    }

    func testGoldenBotAimDefaultAccelerateDecelerate580() {
        // Bot aim: ofFloat(0f, 1f), 580 ms, no interpolator set (AccelerateDecelerate).
        let animator = AValueAnimator.ofFloat(0, 1)
        animator.duration = 580
        let got = timelineBits(animator, frames: 29)
        let golden: [UInt32] = [0x00000000, 0x3B0AD200, 0x3C0A86E0, 0x3C954CA0, 0x3D0563B8, 0x3D505A10, 0x3D92940C,
                                0x3DC6D6C8, 0x3E010BAC, 0x3E1FE5E0, 0x3E43918E, 0x3E69EBAE, 0x3E881666, 0x3E9D6490,
                                0x3EB388A9, 0x3EC8F7B0, 0x3EE03098, 0x3EF7AE7F, 0x3F06EE06, 0x3F12A724, 0x3F1E37CD,
                                0x3F28DEDF, 0x3F33D9E0, 0x3F3E6469, 0x3F47D4FA, 0x3F5144F2, 0x3F5A04A2, 0x3F618E87,
                                0x3F68C356]
        XCTAssertEqual(got, [0x00000000] + golden)
        XCTAssertTrue(animator.isRunning)
    }

    func testGoldenReplayLinearValuesInMilliseconds() {
        // Remote replay: ofFloat(0f, durationMs.toFloat()), Linear.
        let animator = AValueAnimator.ofFloat(0, 1234)
        animator.duration = 1234
        animator.interpolator = ALinearInterpolator()
        let got = timelineBits(animator, frames: 29)
        let golden: [UInt32] = [0x00000000, 0x41880000, 0x42080000, 0x42480000, 0x42860000, 0x42A80000, 0x42C80000,
                                0x42EA0000, 0x43060000, 0x43160000, 0x43270000, 0x43380000, 0x43480000, 0x43590001,
                                0x436A0000, 0x437A0000, 0x43858000, 0x438E0000, 0x43960000, 0x439E8001, 0x43A70000,
                                0x43AF0000, 0x43B77FFF, 0x43C00000, 0x43C80000, 0x43D08000, 0x43D90001, 0x43E10000,
                                0x43E98000]
        XCTAssertEqual(got, [0x00000000] + golden)
    }

    func testGoldenThreeKeyframesAccelerateDecelerate300() {
        let animator = AValueAnimator.ofFloat(2.5, -7.25, 13.125)
        animator.duration = 300
        let got = timelineBits(animator, frames: 29)
        let golden: [UInt32] = [0x40200000, 0x4016235A, 0x3FF1BA57, 0x3F98CCBD, 0x3E49BD30, 0xBF847EAA, 0xC0180004,
                                0xC07CA0A4, 0xC0B3F7DC, 0xC0E80000, 0xC06914EC, 0xBE1764C0, 0x403C0014, 0x40BCD6A4,
                                0x41072FF3, 0x41265300, 0x413EBA26, 0x414D6F48, 0x41520000]
        XCTAssertEqual(got, [0x40200000] + golden) // ends on the 19th frame (1000316 ms)
    }

    func testGoldenIntKeyframesTruncateTowardZero() {
        let animator = AValueAnimator.ofInt(10, -7)
        animator.duration = 100
        animator.interpolator = ALinearInterpolator()
        AndroidKitTestLoop.advance(millis: 1)
        var values: [Int] = []
        animator.addUpdateListener { a in values.append(a.animatedValueInt) }
        animator.start()
        AndroidKitTestLoop.advance(nanos: 29 * 16_666_667 - 1_000_000)
        XCTAssertEqual(values, [10, 10, 8, 5, 2, -1, -4, -7])
    }

    // MARK: - Interpolators (AOSP formulas, JVM golden bits)

    private static let goldenInputs: [UInt32] = [0x00000000, 0x3D4CCCCD, 0x3DCCCCCD, 0x3E23D70A, 0x3E800000, 0x3EAAAAAB,
                                                 0x3ECCCCCD, 0x3F000000, 0x3F19999A, 0x3F2AAAAB, 0x3F400000, 0x3F547AE1,
                                                 0x3F666666, 0x3F7D70A4, 0x3F800000]

    private func goldenInterpolators() -> [(String, ATimeInterpolator, [UInt32])] {
        return [
            ("linear", ALinearInterpolator(),
             [0x00000000, 0x3D4CCCCD, 0x3DCCCCCD, 0x3E23D70A, 0x3E800000, 0x3EAAAAAB, 0x3ECCCCCD, 0x3F000000, 0x3F19999A,
              0x3F2AAAAB, 0x3F400000, 0x3F547AE1, 0x3F666666, 0x3F7D70A4, 0x3F800000]),
            ("accelerateDecelerate", AAccelerateDecelerateInterpolator(),
             [0x00000000, 0x3BC9B6C0, 0x3CC87900, 0x3D7D52E8, 0x3E15F61A, 0x3E800002, 0x3EB0E442, 0x3F000000, 0x3F278DDF,
              0x3F400002, 0x3F5A827A, 0x3F6E2CCA, 0x3F79BC38, 0x3F7FEFD4, 0x3F800000]),
            ("decelerate", ADecelerateInterpolator(),
             [0x00000000, 0x3DC7AE18, 0x3E428F60, 0x3E96BB96, 0x3EE00000, 0x3F0E38E4, 0x3F23D70A, 0x3F400000, 0x3F570A3E,
              0x3F638E39, 0x3F700000, 0x3F789A02, 0x3F7D70A4, 0x3F7FF972, 0x3F800000]),
            ("decelerate2_5", ADecelerateInterpolator(2.5),
             [0x00000000, 0x3E67A5FC, 0x3ED1AB4E, 0x3F14F00F, 0x3F434000, 0x3F5E49BF, 0x3F6C17EB, 0x3F780000, 0x3F7D60E9,
              0x3F7EF24E, 0x3F7FC000, 0x3F7FF6B2, 0x3F7FFF58, 0x3F800000, 0x3F800000]),
            ("accelerate", AAccelerateInterpolator(),
             [0x00000000, 0x3B23D70B, 0x3C23D70B, 0x3CD1B717, 0x3D800000, 0x3DE38E3A, 0x3E23D70B, 0x3E800000, 0x3EB851EC,
              0x3EE38E3A, 0x3F100000, 0x3F305BC0, 0x3F4F5C28, 0x3F7AE7D6, 0x3F800000]),
            ("accelerate1_5", AAccelerateInterpolator(1.5),
             [0x00000000, 0x3903126F, 0x3A83126F, 0x3B8637BC, 0x3C800000, 0x3D17B427, 0x3D83126F, 0x3E000000, 0x3E5D2F1C,
              0x3E97B427, 0x3ED80000, 0x3F1260A1, 0x3F3A9FBD, 0x3F786584, 0x3F800000]),
            ("overshoot", AOvershootInterpolator(),
             [0x00000000, 0x3E6E76D0, 0x3EDDB234, 0x3F22120E, 0x3F5C0000, 0x3F800000, 0x3F89374C, 0x3F900000, 0x3F90624E,
              0x3F8E38E3, 0x3F8A0000, 0x3F858306, 0x3F822D0E, 0x3F800675, 0x3F800000]),
            ("overshoot1_2", AOvershootInterpolator(1.2),
             [0x00000000, 0x3E497F6C, 0x3EBC84B8, 0x3F0AF30C, 0x3F3F3333, 0x3F61A8C6, 0x3F74F0D8, 0x3F833333, 0x3F868DB9,
              0x3F86A315, 0x3F853333, 0x3F830E38, 0x3F814120, 0x3F8003DC, 0x3F800000]),
            ("anticipate", AAnticipateInterpolator(),
             [0x80000000, 0xBB978D51, 0xBC8B4396, 0xBD1F6230, 0xBDA00000, 0xBDE38E3A, 0xBE03126F, 0xBE000000, 0xBD9374B9,
              0x00000000, 0x3E100000, 0x3EACD4CC, 0x3F1126E6, 0x3F7360E2, 0x3F800000]),
            ("anticipateOvershoot", AAnticipateOvershootInterpolator(),
             [0x80000000, 0xBC54FDF4, 0xBD343959, 0xBDB45AE6, 0xBE000000, 0xBD97B424, 0x3D831271, 0x3F000000, 0x3F6F9DB3,
              0x3F897B43, 0x3F900000, 0x3F8C2225, 0x3F85A1CB, 0x3F801323, 0x3F800000]),
            ("bounce", ABounceInterpolator(),
             [0x00000000, 0x3CCE79E8, 0x3DCE79E8, 0x3E84250F, 0x3F214F3D, 0x3F707CCE, 0x3F46EDE4, 0x3F339B95, 0x3F53E7C1,
              0x3F7CA2EE, 0x3F66A1DD, 0x3F733B94, 0x3F7573B3, 0x3F7CA289, 0x3F8001C9]),
            ("cycle0_5", ACycleInterpolator(0.5),
             [0x00000000, 0x3E20305B, 0x3E9E377A, 0x3EF6A86B, 0x3F3504F3, 0x3F5DB3D8, 0x3F737871, 0x3F800000, 0x3F737870,
              0x3F5DB3D7, 0x3F3504F3, 0x3F02508B, 0x3E9E377C, 0x3D00A889, 0x250D3132]),
        ]
    }

    func testInterpolatorsMatchTheAndroidFormulasBitForBit() {
        for (name, interpolator, expected) in goldenInterpolators() {
            let got = AndroidKitLooperTests.goldenInputs.map { interpolator.getInterpolation(Float(bitPattern: $0)).bitPattern }
            XCTAssertEqual(got, expected, name)
        }
    }

    func testInterpolatorFormulas() {
        let ad = AAccelerateDecelerateInterpolator()
        let decelerate = ADecelerateInterpolator()
        for i in 0...100 {
            let t = Float(i) / 100
            XCTAssertEqual(ad.getInterpolation(t).bitPattern, (Float(cos(Double(t + 1) * Double.pi) / 2.0) + 0.5).bitPattern)
            XCTAssertEqual(decelerate.getInterpolation(t).bitPattern, (1 - (1 - t) * (1 - t)).bitPattern)
            XCTAssertEqual(ALinearInterpolator().getInterpolation(t), t)
        }
        XCTAssertEqual(ad.getInterpolation(0), 0)
        XCTAssertEqual(ad.getInterpolation(0.5), 0.5)
        XCTAssertEqual(ad.getInterpolation(1), 1)
    }

    // MARK: - ViewPropertyAnimator

    func testViewPropertyAnimatorStartIsSynchronousWithAndroidDefaults() {
        let view = LooperFakeView()
        view.alpha = 0
        let animator = AViewPropertyAnimator(view)
        XCTAssertEqual(animator.duration, 300)
        XCTAssertTrue(animator.interpolator is AAccelerateDecelerateInterpolator)
        var log: [String] = []
        animator.alpha(1)
            .withStartAction { log.append("startAction alpha=\(view.alpha)") }
            .withEndAction { log.append("endAction alpha=\(view.alpha)") }
            .start()
        XCTAssertEqual(log, ["startAction alpha=0.0"])
        XCTAssertEqual(view.alpha, 0)
        XCTAssertEqual(animator.runningAnimationCountForTests, 1)
        AndroidKitTestLoop.advance(millis: 151) // vsync T0 + 150.000003 ms: fraction 0.5 -> AccelerateDecelerate 0.5
        XCTAssertEqual(view.alpha, 0.5)
        AndroidKitTestLoop.advance(millis: 148) // up to 299 ms: the 300.000006 ms vsync has not happened yet
        XCTAssertEqual(log.count, 1)
        AndroidKitTestLoop.advance(millis: 2) // vsync 1000300 ms ends it
        XCTAssertEqual(log, ["startAction alpha=0.0", "endAction alpha=1.0"])
        XCTAssertEqual(view.alpha, 1)
        XCTAssertEqual(animator.runningAnimationCountForTests, 0)
    }

    func testViewPropertyAnimatorWithoutStartBeginsInTheNextFrame() {
        let view = LooperFakeView()
        let animator = AViewPropertyAnimator(view)
        animator.translationX(100).setDuration(100).setInterpolator(ALinearInterpolator())
        XCTAssertEqual(animator.runningAnimationCountForTests, 0)
        XCTAssertTrue(AndroidKitTestLoop.runFrame()) // 1000000: the starter runs and starts the animator
        XCTAssertEqual(animator.runningAnimationCountForTests, 1)
        XCTAssertEqual(view.translationX, 0)
        AndroidKitTestLoop.advance(millis: 34) // 1000016: first animator frame (start time); 1000033: 17 ms in
        XCTAssertEqual(view.translationX, 0 + (Float(17) / Float(100)) * 100)
    }

    func testViewPropertyAnimatorStartDelayRunsTheStartActionWhenTheDelayEnds() {
        // AOSP oracle: [] delay=100 [startAction 1000100 ty=0.0, endAction 1000200 ty=10.0] ty=10.0
        let view = LooperFakeView()
        let animator = AViewPropertyAnimator(view)
        var log: [String] = []
        animator.translationY(10).setStartDelay(100).setDuration(100).setInterpolator(ALinearInterpolator())
            .withStartAction { log.append("startAction \(AndroidKitTestLoop.nowMillis) ty=\(view.translationY)") }
            .withEndAction { log.append("endAction \(AndroidKitTestLoop.nowMillis) ty=\(view.translationY)") }
            .start()
        XCTAssertEqual(log, [])
        XCTAssertEqual(animator.startDelay, 100)
        AndroidKitTestLoop.advance(millis: 400)
        XCTAssertEqual(log, ["startAction 1000100 ty=0.0", "endAction 1000200 ty=10.0"])
        XCTAssertEqual(view.translationY, 10)
    }

    func testGoldenScoreFlashScaleWithDefaultInterpolator() {
        // flashHumanScore: scaleX = 1.12f; animate().scaleX(1f).setDuration(360L).withEndAction { ... }.start()
        let view = LooperFakeView()
        view.scaleX = 1.12
        let animator = AViewPropertyAnimator(view)
        AndroidKitTestLoop.advance(millis: 1)
        var scales: [UInt32] = []
        var ended = false
        animator.setUpdateListener { _ in scales.append(view.scaleX.bitPattern) }
        animator.scaleX(1).setDuration(360).withEndAction { ended = true }.start()
        AndroidKitTestLoop.advance(nanos: 29 * 16_666_667 - 1_000_000)
        let golden: [UInt32] = [0x3F8F5C29, 0x3F8F4690, 0x3F8F0640, 0x3F8EA3F4, 0x3F8E1591, 0x3F8D632A, 0x3F8C9DDA,
                                0x3F8BB15B, 0x3F8AAE4A, 0x3F89AAF0, 0x3F888CA6, 0x3F876977, 0x3F8658AC, 0x3F853E3C,
                                0x3F843180, 0x3F834662, 0x3F8264B8, 0x3F81A0CA, 0x3F810768, 0x3F8088CE, 0x3F803264,
                                0x3F80077B, 0x3F800000]
        XCTAssertEqual(scales, [0x3F8F5C29] + golden) // ends on the 23rd frame (1000383 ms)
        XCTAssertTrue(ended)
    }

    func testViewPropertyAnimatorCancelCallsListenerCancelThenEndAndSkipsTheEndAction() {
        let view = LooperFakeView()
        let animator = AViewPropertyAnimator(view)
        var log: [String] = []
        animator.setListener(listener { log.append($0) })
        animator.scaleX(2).withEndAction { log.append("endAction") }.start()
        AndroidKitTestLoop.advance(millis: 50)
        animator.cancel()
        XCTAssertEqual(log, ["start", "cancel", "end"])
        let scaleAtCancel = view.scaleX
        XCTAssertGreaterThan(scaleAtCancel, 1)
        AndroidKitTestLoop.advance(millis: 400)
        XCTAssertEqual(view.scaleX, scaleAtCancel)
        XCTAssertEqual(log, ["start", "cancel", "end"])
        XCTAssertEqual(animator.runningAnimationCountForTests, 0)
    }

    func testANewAnimationOfTheSamePropertyCancelsTheRunningOne() {
        let view = LooperFakeView()
        let animator = AViewPropertyAnimator(view)
        var log: [String] = []
        animator.alpha(0).withEndAction { log.append("fadeOutEnd") }.start()
        AndroidKitTestLoop.advance(millis: 50)
        XCTAssertEqual(animator.runningAnimationCountForTests, 1)
        let alphaWhenRestarted = view.alpha
        animator.alpha(1).withEndAction { log.append("fadeInEnd") }.start()
        XCTAssertEqual(animator.runningAnimationCountForTests, 1)
        XCTAssertEqual(view.alpha, alphaWhenRestarted) // the new animation starts from the current value
        AndroidKitTestLoop.advance(millis: 400)
        XCTAssertEqual(log, ["fadeInEnd"])
        XCTAssertEqual(view.alpha, 1)
    }

    func testAnimatingAnotherPropertyLeavesTheFirstAnimationRunning() {
        let view = LooperFakeView()
        let animator = AViewPropertyAnimator(view)
        var log: [String] = []
        animator.alpha(0).withEndAction { log.append("alphaEnd") }.start()
        AndroidKitTestLoop.advance(millis: 50)
        animator.scaleY(2).withEndAction { log.append("scaleEnd") }.start()
        XCTAssertEqual(animator.runningAnimationCountForTests, 2)
        AndroidKitTestLoop.advance(millis: 400)
        XCTAssertEqual(log, ["alphaEnd", "scaleEnd"])
        XCTAssertEqual(view.alpha, 0)
        XCTAssertEqual(view.scaleY, 2)
    }

    func testViewPropertyAnimatorSettingsPersistAcrossAnimations() {
        let view = LooperFakeView()
        let animator = AViewPropertyAnimator(view)
        animator.setDuration(500).setInterpolator(ALinearInterpolator())
        animator.x(100).start()
        XCTAssertEqual(animator.duration, 500)
        AndroidKitTestLoop.advance(millis: 1000)
        XCTAssertEqual(view.x, 100)
        var ended = false
        animator.translationXBy(-50).withEndAction { ended = true }.start()
        AndroidKitTestLoop.advance(millis: 250) // 250 ms into the 500 ms linear animation
        XCTAssertFalse(ended)
        AndroidKitTestLoop.advance(millis: 300)
        XCTAssertTrue(ended)
        XCTAssertEqual(view.translationX, 50)
    }

    // MARK: - ObjectAnimator (FamilyMoreFrame cue bounce)

    func testObjectAnimatorReverseInfiniteBounce() {
        AndroidKitTestLoop.frameIntervalNanos = 5_000_000
        AndroidKitTestLoop.install(startNanos: T0)
        let arrow = LooperFakeView()
        let bounce = AObjectAnimator.ofFloat(arrow, AViewProperty.TRANSLATION_Y, 0, 4)
        bounce.setDuration(850)
        bounce.setRepeatMode(AValueAnimator.REVERSE)
        bounce.setRepeatCount(AValueAnimator.INFINITE)
        var repeats = 0
        bounce.addListener(AAnimatorListenerAdapter(onRepeat: { _ in repeats += 1 }))
        bounce.start()
        XCTAssertEqual(arrow.translationY, 0)
        XCTAssertEqual(bounce.totalDuration, AAnimator.DURATION_INFINITE)
        AndroidKitTestLoop.advance(millis: 425) // fraction 0.5 forward: AccelerateDecelerate(0.5) = 0.5
        XCTAssertEqual(arrow.translationY, 2)
        AndroidKitTestLoop.advance(millis: 425) // fraction 1.0: end of the first iteration (repeat fires)
        XCTAssertEqual(arrow.translationY, 4)
        XCTAssertEqual(repeats, 1)
        AndroidKitTestLoop.advance(millis: 425) // fraction 1.5: backward 0.5
        XCTAssertEqual(arrow.translationY, 2)
        XCTAssertEqual(repeats, 1)
        AndroidKitTestLoop.advance(millis: 425) // fraction 2.0
        XCTAssertEqual(arrow.translationY, 0)
        XCTAssertEqual(repeats, 2)
        XCTAssertTrue(bounce.isRunning)
        bounce.cancel()
        XCTAssertFalse(bounce.isRunning)
        arrow.translationY = 0
        AndroidKitTestLoop.advance(millis: 100)
        XCTAssertEqual(arrow.translationY, 0)
    }

    func testObjectAnimatorWithOneValueStartsFromTheCurrentPropertyValue() {
        let view = LooperFakeView()
        view.rotation = 30
        let spin = AObjectAnimator.ofFloat(view, AViewProperty.ROTATION, 90)
        spin.setDuration(100)
        spin.interpolator = ALinearInterpolator()
        spin.start()
        XCTAssertEqual(view.rotation, 30)
        spin.end()
        XCTAssertEqual(view.rotation, 90)
    }
}

/// An Animator.AnimatorPauseListener that logs "pause" / "resume".
private final class LooperPauseRecorder: AAnimatorPauseListener {
    private let log: (String) -> Void

    init(_ log: @escaping (String) -> Void) {
        self.log = log
    }

    func onAnimationPause(_ animation: AAnimator) {
        log("pause")
    }

    func onAnimationResume(_ animation: AAnimator) {
        log("resume")
    }
}
