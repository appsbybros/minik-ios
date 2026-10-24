import Foundation

// android.os.Looper / MessageQueue / Handler / Message and java.lang.Runnable (DESIGN 4.3, CORE-API "ALooper.swift").
//
// One main MessageQueue with the semantics of Android's MessageQueue (legacy implementation, AOSP API 37):
// messages are ordered by `when` (SystemClock.uptimeMillis) and, for equal `when`, by enqueue order; a message
// posted with `when == 0` (postAtFrontOfQueue) goes to the head; removeCallbacks matches the runnable by identity and
// only touches that handler's messages; a sync barrier (posted by AChoreographer.requestTraversal, like
// ViewRootImpl.scheduleTraversals) stalls every synchronous message behind it until the next frame's traversal,
// while asynchronous messages (the Choreographer's own) still run.
//
// On iOS the queue is driven by one CFRunLoopTimer in the common run-loop modes (so scrolling does not starve it),
// armed for the earliest deliverable message. Each firing dispatches ONE message and re-arms, so UIKit touches and
// display-link frames interleave with messages the way Android's Looper polls input and vsync between messages.
// Messages that are due before a vsync run before that frame (AChoreographer drains them first), because Android
// posts the vsync as an asynchronous message at the vsync time.

/// java.lang.Runnable: a reference type, so post / postDelayed / removeCallbacks / postOnAnimation match a runnable
/// by identity exactly like Android. Keep the same instance for posting and removing.
final class ARunnable {
    private let block: (() -> Void)?
    private let selfBlock: ((ARunnable) -> Void)?

    init(_ block: @escaping () -> Void) {
        self.block = block
        self.selfBlock = nil
    }

    /// For `object : Runnable { override fun run() { ...; handler.postDelayed(this, ms) } }`: the block receives the
    /// runnable itself, without a retain cycle.
    init(withSelf block: @escaping (ARunnable) -> Void) {
        self.block = nil
        self.selfBlock = block
    }

    func run() {
        if let selfBlock = selfBlock {
            selfBlock(self)
        } else {
            block?()
        }
    }
}

/// android.os.Looper. Only the main looper exists: everything runs on the main thread (DESIGN 2.4).
final class ALooper: Equatable {
    nonisolated(unsafe) private static let sMainLooper = ALooper()

    /// The main thread's MessageQueue (`Looper.mQueue`).
    let mQueue = AMessageQueue()

    private init() {}

    /// `Looper.getMainLooper()`.
    static func getMainLooper() -> ALooper {
        return sMainLooper
    }

    /// `Looper.myLooper()`: the main looper on the main thread; nil on any other thread (none has a Looper).
    static func myLooper() -> ALooper? {
        return Thread.isMainThread ? sMainLooper : nil
    }

    /// `Looper.myQueue()`.
    static func myQueue() -> AMessageQueue {
        return sMainLooper.mQueue
    }

    /// `Looper.getQueue()`.
    var queue: AMessageQueue {
        return mQueue
    }

    func getQueue() -> AMessageQueue {
        return mQueue
    }

    /// `Looper.getThread()`.
    var thread: Thread {
        return Thread.main
    }

    /// `Looper.isCurrentThread()`.
    var isCurrentThread: Bool {
        return Thread.isMainThread
    }

    static func == (lhs: ALooper, rhs: ALooper) -> Bool {
        return lhs === rhs
    }
}

/// android.os.Message (the fields the framework and the app use).
final class AMessage {
    var what: Int = 0
    var arg1: Int = 0
    var arg2: Int = 0
    var obj: AnyObject? = nil
    /// The runnable of post / postDelayed / postAtTime.
    var callback: ARunnable? = nil
    /// The handler that dispatches the message. nil marks a sync barrier (MessageQueue.postSyncBarrier).
    var target: AHandler? = nil
    /// Uptime milliseconds at which the message is due.
    fileprivate(set) var when: Int64 = 0
    fileprivate(set) var isAsynchronous = false
    /// Enqueue order: unique and increasing.
    fileprivate(set) var insertSeq: Int64 = 0

    init() {}

    static func obtain() -> AMessage {
        return AMessage()
    }

    static func obtain(_ h: AHandler, _ callback: ARunnable) -> AMessage {
        let m = AMessage()
        m.target = h
        m.callback = callback
        return m
    }

    static func obtain(_ h: AHandler, _ what: Int, _ obj: AnyObject?) -> AMessage {
        let m = AMessage()
        m.target = h
        m.what = what
        m.obj = obj
        return m
    }

    /// `Message.setAsynchronous`: asynchronous messages are not stalled by sync barriers.
    func setAsynchronous(_ async: Bool) {
        isAsynchronous = async
    }

    func getWhen() -> Int64 {
        return when
    }

    func sendToTarget() {
        _ = target?.sendMessage(self)
    }
}

/// android.os.MessageQueue of the main looper.
final class AMessageQueue {
    /// The queue in dispatch order (Android's linked list `mMessages`); always sorted by `when`.
    private var mMessages: [AMessage] = []
    private var mNextBarrierToken = 0
    private var mLastInsertSeq: Int64 = 0

    fileprivate init() {}

    /// `MessageQueue.enqueueMessage(msg, when)`. A post from another thread keeps its `when` and is inserted on the
    /// main thread.
    @discardableResult
    func enqueueMessage(_ msg: AMessage, _ when: Int64) -> Bool {
        precondition(msg.target != nil, "Message must have a target.")
        if !Thread.isMainThread {
            DispatchQueue.main.async {
                _ = self.enqueueMessage(msg, when)
            }
            return true
        }
        msg.when = when
        mLastInsertSeq += 1
        msg.insertSeq = mLastInsertSeq
        mMessages.insert(msg, at: insertionIndex(when))
        AMainLooperDriver.shared.queueChanged()
        return true
    }

    /// Android's insertion rule: the head when the queue is empty, `when == 0` or `when < head.when`; otherwise after
    /// every message whose `when <= when` (equal times keep enqueue order). postSyncBarrier uses the same rule.
    private func insertionIndex(_ when: Int64) -> Int {
        if mMessages.isEmpty || when == 0 || when < mMessages[0].when {
            return 0
        }
        var lo = 1
        var hi = mMessages.count
        while lo < hi {
            let mid = (lo + hi) / 2
            if mMessages[mid].when <= when {
                lo = mid + 1
            } else {
                hi = mid
            }
        }
        return lo
    }

    /// `MessageQueue.postSyncBarrier()`: a barrier at the current uptime; returns its token.
    func postSyncBarrier() -> Int {
        let when = ASystemClock.uptimeMillis()
        let token = mNextBarrierToken
        mNextBarrierToken += 1
        let msg = AMessage()
        msg.when = when
        msg.arg1 = token
        mLastInsertSeq += 1
        msg.insertSeq = mLastInsertSeq
        mMessages.insert(msg, at: insertionIndex(when))
        AMainLooperDriver.shared.queueChanged()
        return token
    }

    /// `MessageQueue.removeSyncBarrier(token)`.
    func removeSyncBarrier(_ token: Int) {
        guard let index = mMessages.firstIndex(where: { $0.target == nil && $0.arg1 == token }) else {
            assertionFailure("The specified message queue synchronization barrier token has not been posted or has already been removed.")
            return
        }
        mMessages.remove(at: index)
        AMainLooperDriver.shared.queueChanged()
    }

    /// The index of the message next() may return: the head, or, behind a sync barrier at the head, the first
    /// asynchronous message.
    private func deliverableIndex() -> Int? {
        if mMessages.isEmpty {
            return nil
        }
        if mMessages[0].target != nil {
            return 0
        }
        var i = 1
        while i < mMessages.count && !mMessages[i].isAsynchronous {
            i += 1
        }
        return i < mMessages.count ? i : nil
    }

    /// The due time (uptime ms) of the next message the looper will dispatch, or nil (empty, or stalled by a barrier).
    func nextDeliverableWhen() -> Int64? {
        guard let index = deliverableIndex() else { return nil }
        return mMessages[index].when
    }

    /// `MessageQueue.next()` without blocking: removes and returns the message the looper dispatches at `now`
    /// (uptime ms), or nil when none is due.
    func pollMessage(_ now: Int64) -> AMessage? {
        guard let index = deliverableIndex() else { return nil }
        let msg = mMessages[index]
        if now < msg.when {
            return nil
        }
        mMessages.remove(at: index)
        return msg
    }

    /// A message that Android orders ahead of a vsync frame message: the vsync is posted asynchronously at
    /// `vsyncMillis` after message `seqLimit` was enqueued, so earlier messages, and messages with the same time
    /// enqueued before it, run first.
    func pollMessage(beforeVsync vsyncMillis: Int64, enqueuedUpTo seqLimit: Int64) -> AMessage? {
        guard let index = deliverableIndex() else { return nil }
        let msg = mMessages[index]
        guard msg.when < vsyncMillis || (msg.when == vsyncMillis && msg.insertSeq <= seqLimit) else {
            return nil
        }
        mMessages.remove(at: index)
        return msg
    }

    /// The insert sequence of the most recently enqueued message.
    var lastInsertSeq: Int64 {
        return mLastInsertSeq
    }

    /// `MessageQueue.removeMessages(h, r, object)`: runnable identity, this handler only.
    func removeMessages(_ h: AHandler, _ r: ARunnable, _ object: AnyObject?) {
        removeWhere { $0.target === h && $0.callback === r && (object == nil || $0.obj === object) }
    }

    /// `MessageQueue.removeMessages(h, what, object)`.
    func removeMessages(_ h: AHandler, _ what: Int, _ object: AnyObject?) {
        removeWhere { $0.target === h && $0.what == what && (object == nil || $0.obj === object) }
    }

    /// `MessageQueue.removeCallbacksAndMessages(h, object)`: every message of this handler (object nil), or those
    /// whose obj is `object`.
    func removeCallbacksAndMessages(_ h: AHandler, _ object: AnyObject?) {
        removeWhere { $0.target === h && (object == nil || $0.obj === object) }
    }

    func hasMessages(_ h: AHandler, _ r: ARunnable, _ object: AnyObject?) -> Bool {
        return mMessages.contains { $0.target === h && $0.callback === r && (object == nil || $0.obj === object) }
    }

    func hasMessages(_ h: AHandler, _ what: Int, _ object: AnyObject?) -> Bool {
        return mMessages.contains { $0.target === h && $0.what == what && (object == nil || $0.obj === object) }
    }

    /// `MessageQueue.isIdle()`.
    func isIdle() -> Bool {
        let now = ASystemClock.uptimeMillis()
        return mMessages.isEmpty || now < mMessages[0].when
    }

    private func removeWhere(_ predicate: (AMessage) -> Bool) {
        if !Thread.isMainThread {
            preconditionFailure("AMessageQueue removals must run on the main thread")
        }
        let before = mMessages.count
        mMessages.removeAll(where: predicate)
        if mMessages.count != before {
            AMainLooperDriver.shared.queueChanged()
        }
    }

    // MARK: Test hooks

    /// Messages and barriers currently queued.
    var countForTests: Int {
        return mMessages.count
    }

    var hasSyncBarrierForTests: Bool {
        return mMessages.contains { $0.target == nil }
    }

    func resetForTests() {
        mMessages.removeAll()
        mNextBarrierToken = 0
    }
}

/// Runs the main ALooper from the iOS main run loop: one CFRunLoopTimer in the common modes, armed for the earliest
/// deliverable message. Each firing dispatches one message (one `Looper.loop()` iteration) and re-arms.
final class AMainLooperDriver {
    nonisolated(unsafe) static let shared = AMainLooperDriver()
    private static let IDLE_SECONDS: CFTimeInterval = 1_000_000_000
    private var timer: CFRunLoopTimer?
    /// The `when` the timer is armed for; nil while idle (or right after a firing).
    private var armedWhen: Int64? = nil

    private init() {}

    /// The head of the queue may have changed: re-arm the run-loop timer.
    func queueChanged() {
        if !Thread.isMainThread {
            DispatchQueue.main.async {
                self.queueChanged()
            }
            return
        }
        rearm()
    }

    /// Dispatches the next message that is due at `now` (uptime ms). Returns false when none is due.
    @discardableResult
    func dispatchNextMessage(_ now: Int64) -> Bool {
        guard let msg = ALooper.getMainLooper().mQueue.pollMessage(now) else { return false }
        msg.target?.dispatchMessage(msg)
        return true
    }

    private func rearm() {
        if AFakeClock.isInstalled {
            return // unit tests drive the queue with AndroidKitTestLoop
        }
        let next = ALooper.getMainLooper().mQueue.nextDeliverableWhen()
        if next == armedWhen {
            return
        }
        armedWhen = next
        let runLoopTimer = ensureTimer()
        if let when = next {
            let delayNanos = max(Int64(0), when &* 1_000_000 &- ASystem.nanoTime())
            CFRunLoopTimerSetNextFireDate(runLoopTimer, CFAbsoluteTimeGetCurrent() + Double(delayNanos) / 1_000_000_000)
        } else {
            CFRunLoopTimerSetNextFireDate(runLoopTimer, CFAbsoluteTimeGetCurrent() + AMainLooperDriver.IDLE_SECONDS)
        }
    }

    private func ensureTimer() -> CFRunLoopTimer {
        if let existing = timer {
            return existing
        }
        let created: CFRunLoopTimer = CFRunLoopTimerCreateWithHandler(
            kCFAllocatorDefault,
            CFAbsoluteTimeGetCurrent() + AMainLooperDriver.IDLE_SECONDS,
            AMainLooperDriver.IDLE_SECONDS, 0, 0
        ) { [weak self] _ in
            self?.fire()
        }
        CFRunLoopTimerSetTolerance(created, 0)
        CFRunLoopAddTimer(CFRunLoopGetMain(), created, CFRunLoopMode.commonModes)
        timer = created
        return created
    }

    private func fire() {
        armedWhen = nil
        if AFakeClock.isInstalled {
            return
        }
        dispatchNextMessage(ASystemClock.uptimeMillis())
        rearm()
    }

    func resetForTests() {
        armedWhen = nil
    }
}

/// android.os.Handler (on the main looper).
final class AHandler {
    private let mLooper: ALooper
    private let mQueue: AMessageQueue
    /// `Handler.Callback`: return true when the message was handled.
    private let mCallback: ((AMessage) -> Bool)?
    private let mAsynchronous: Bool

    /// `Handler()`: the calling thread's looper (only the main thread has one).
    convenience init() {
        self.init(ALooper.myLooper() ?? ALooper.getMainLooper(), nil, false)
    }

    /// `Handler(Looper)`.
    convenience init(_ looper: ALooper) {
        self.init(looper, nil, false)
    }

    /// `Handler(Looper, Handler.Callback)`.
    convenience init(_ looper: ALooper, _ callback: ((AMessage) -> Bool)?) {
        self.init(looper, callback, false)
    }

    /// `Handler(Looper, Handler.Callback, boolean async)`: an asynchronous handler's messages bypass sync barriers.
    init(_ looper: ALooper, _ callback: ((AMessage) -> Bool)?, _ async: Bool) {
        mLooper = looper
        mQueue = looper.mQueue
        mCallback = callback
        mAsynchronous = async
    }

    /// `Handler.createAsync(looper)`.
    static func createAsync(_ looper: ALooper) -> AHandler {
        return AHandler(looper, nil, true)
    }

    var looper: ALooper {
        return mLooper
    }

    func getLooper() -> ALooper {
        return mLooper
    }

    /// Default `handleMessage` (AHandler is final: use the Handler.Callback initialiser for `what` messages).
    func handleMessage(_ msg: AMessage) {
    }

    /// `Handler.dispatchMessage`.
    func dispatchMessage(_ msg: AMessage) {
        if let callback = msg.callback {
            callback.run()
        } else {
            if let mCallback = mCallback, mCallback(msg) {
                return
            }
            handleMessage(msg)
        }
    }

    // MARK: Runnables

    @discardableResult
    func post(_ r: ARunnable) -> Bool {
        return sendMessageDelayed(getPostMessage(r, nil), 0)
    }

    /// `handler.post { ... }` with a lambda: a fresh runnable (removable only through removeCallbacksAndMessages).
    @discardableResult
    func post(_ block: @escaping () -> Void) -> Bool {
        return post(ARunnable(block))
    }

    @discardableResult
    func postAtTime(_ r: ARunnable, _ uptimeMillis: Int64) -> Bool {
        return sendMessageAtTime(getPostMessage(r, nil), uptimeMillis)
    }

    @discardableResult
    func postAtTime(_ r: ARunnable, _ token: AnyObject?, _ uptimeMillis: Int64) -> Bool {
        return sendMessageAtTime(getPostMessage(r, token), uptimeMillis)
    }

    @discardableResult
    func postDelayed(_ r: ARunnable, _ delayMillis: Int64) -> Bool {
        return sendMessageDelayed(getPostMessage(r, nil), delayMillis)
    }

    @discardableResult
    func postDelayed(_ block: @escaping () -> Void, _ delayMillis: Int64) -> Bool {
        return postDelayed(ARunnable(block), delayMillis)
    }

    @discardableResult
    func postDelayed(_ r: ARunnable, _ token: AnyObject?, _ delayMillis: Int64) -> Bool {
        return sendMessageDelayed(getPostMessage(r, token), delayMillis)
    }

    @discardableResult
    func postAtFrontOfQueue(_ r: ARunnable) -> Bool {
        return sendMessageAtFrontOfQueue(getPostMessage(r, nil))
    }

    /// `removeCallbacks(r)`: every pending message of THIS handler whose runnable is `r` (identity).
    func removeCallbacks(_ r: ARunnable) {
        if !Thread.isMainThread {
            DispatchQueue.main.async { self.removeCallbacks(r) }
            return
        }
        mQueue.removeMessages(self, r, nil)
    }

    func removeCallbacks(_ r: ARunnable, _ token: AnyObject?) {
        if !Thread.isMainThread {
            DispatchQueue.main.async { self.removeCallbacks(r, token) }
            return
        }
        mQueue.removeMessages(self, r, token)
    }

    /// `removeCallbacksAndMessages(null)` removes every pending message of this handler only; with a token, the
    /// messages whose obj is that token.
    func removeCallbacksAndMessages(_ token: AnyObject?) {
        if !Thread.isMainThread {
            DispatchQueue.main.async { self.removeCallbacksAndMessages(token) }
            return
        }
        mQueue.removeCallbacksAndMessages(self, token)
    }

    func hasCallbacks(_ r: ARunnable) -> Bool {
        return mQueue.hasMessages(self, r, nil)
    }

    // MARK: Messages

    func obtainMessage() -> AMessage {
        let m = AMessage()
        m.target = self
        return m
    }

    func obtainMessage(_ what: Int) -> AMessage {
        return AMessage.obtain(self, what, nil)
    }

    func obtainMessage(_ what: Int, _ obj: AnyObject?) -> AMessage {
        return AMessage.obtain(self, what, obj)
    }

    @discardableResult
    func sendMessage(_ msg: AMessage) -> Bool {
        return sendMessageDelayed(msg, 0)
    }

    @discardableResult
    func sendEmptyMessage(_ what: Int) -> Bool {
        return sendEmptyMessageDelayed(what, 0)
    }

    @discardableResult
    func sendEmptyMessageDelayed(_ what: Int, _ delayMillis: Int64) -> Bool {
        return sendMessageDelayed(AMessage.obtain(self, what, nil), delayMillis)
    }

    @discardableResult
    func sendMessageDelayed(_ msg: AMessage, _ delayMillis: Int64) -> Bool {
        var delay = delayMillis
        if delay < 0 {
            delay = 0
        }
        return sendMessageAtTime(msg, ASystemClock.uptimeMillis() &+ delay)
    }

    @discardableResult
    func sendMessageAtTime(_ msg: AMessage, _ uptimeMillis: Int64) -> Bool {
        return enqueueMessage(msg, uptimeMillis)
    }

    @discardableResult
    func sendMessageAtFrontOfQueue(_ msg: AMessage) -> Bool {
        return enqueueMessage(msg, 0)
    }

    func removeMessages(_ what: Int) {
        mQueue.removeMessages(self, what, nil)
    }

    func removeMessages(_ what: Int, _ obj: AnyObject?) {
        mQueue.removeMessages(self, what, obj)
    }

    func hasMessages(_ what: Int) -> Bool {
        return mQueue.hasMessages(self, what, nil)
    }

    private func getPostMessage(_ r: ARunnable, _ token: AnyObject?) -> AMessage {
        let m = AMessage()
        m.obj = token
        m.callback = r
        return m
    }

    private func enqueueMessage(_ msg: AMessage, _ uptimeMillis: Int64) -> Bool {
        msg.target = self
        if mAsynchronous {
            msg.setAsynchronous(true)
        }
        return mQueue.enqueueMessage(msg, uptimeMillis)
    }
}
