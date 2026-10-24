import UIKit

// android.view.ViewRootImpl for the AndroidKit view system (VIEW-API "Views", DESIGN 2.6).
//
// An AViewRoot is one Android window. It hosts the window's root AView (an activity's decor view, a dialog's
// overlay tree, a toast) inside a plain UIView container owned by the activity layer, and runs the window's
// traversal (ViewRootImpl.performTraversals) in the Choreographer's TRAVERSAL phase:
//   1. the first traversal after the container is in a UIWindow attaches the tree (dispatchAttachedToWindow) and
//      dispatches the window insets (the container's safeAreaInsets in px; see AInsets.swift);
//   2. window visibility: GONE while the app is in the background or the container is hidden / not in a window
//      (Android: the stopped activity's window), else the root view's visibility -> dispatchWindowVisibilityChanged;
//   3. requested insets are dispatched again; a requested layout (or a new container size) measures the root view
//      with EXACTLY the container size in px and lays it out at (0, 0), with Android's second pass for
//      requestLayout() during layout; then the OnGlobalLayout listeners;
//   4. the OnPreDraw listeners (a cancelled draw is retried next frame), OnScrollChanged and OnDraw listeners, then
//      the draw walk: every invalidated VISIBLE view, in drawing order, gets computeScroll() and its traversal draw
//      (drawsInTraversal views: onDraw(ACanvas.noop) now; the others mark their content layers for Core Animation,
//      which renders them at the end of this run-loop pass). A view invalidated during the walk before the walk
//      reaches it is drawn in the same pass (a parent's onDraw invalidating its children), others next frame.
// The traversals of all roots are coalesced into the single Choreographer traversal: each root runs at most once per
// frame, in the order the roots scheduled (as each ViewRootImpl posts its own CALLBACK_TRAVERSAL).
//
// Touches: the UIKit views of the tree forward their touches to their root (AView.touchesBegan...). They become one
// Android pointer stream per window: pointer ids from 0 (lowest free id reused, stable per UITouch), pointers in id
// order, DOWN / POINTER_DOWN per new touch, one MOVE with every active pointer per UIEvent (UIKit's coalesced touches
// as the batched history), POINTER_UP / UP per lifted touch (the event still holds the lifted pointer), and one CANCEL
// when UIKit cancels the gesture (a scroll view's pan took over, a system gesture). Coordinates are root pixels
// (x/y) and window pixels (rawX/rawY); times are UITouch timestamps in the System.nanoTime() domain. The events go to
// the root view's dispatchTouchEvent (DecorView -> Window.Callback -> ViewGroup dispatch), so every Android rule
// (intercepts, touch targets, pass-through of non-consuming views, clicks, long presses) runs in AndroidKit code.

final class AViewRoot: CustomStringConvertible {
    /// The UIKit touch phase forwarded by the views of the tree.
    enum TouchPhase { case began, moved, ended, cancelled }

    // MARK: - registry (all windows, in creation order)

    private final class WeakRoot {
        weak var root: AViewRoot?
        init(_ root: AViewRoot) { self.root = root }
    }

    private static var sRoots: [WeakRoot] = []
    /// The roots waiting for the next traversal, in scheduling order (strong until their traversal ran).
    private static var sScheduled: [AViewRoot] = []
    private static var sObserversInstalled = false
    private static var sObservers: [NSObjectProtocol] = []

    /// Every live window root, bottom (oldest) to top.
    static var liveRoots: [AViewRoot] {
        sRoots.removeAll { $0.root == nil }
        return sRoots.compactMap { $0.root }
    }

    /// The root whose tree contains `view` (nil when the view is not attached to a window).
    static func rootOf(_ view: AView) -> AViewRoot? {
        view.mAttachInfo?.root
    }

    // MARK: - window state

    /// The container the activity layer owns; the root's own container view fills it.
    let host: UIView
    /// The UIView that holds the root AView (always the host's bounds).
    let containerView: AViewRootContainerView
    /// ViewRootImpl.mView: the root view of this window.
    private(set) var view: AView?
    /// The window's View.AttachInfo (handler, tree observer, window visibility, focus).
    private(set) var attachInfo: AView.AttachInfo!
    /// ViewRootImpl.mHandler / AttachInfo.mHandler: View.post goes here (the main looper).
    let handler: AHandler
    /// AttachInfo.mTreeObserver: the window's ViewTreeObserver.
    let treeObserver: AViewTreeObserver

    /// The window size in px (the container's bounds times the density, integer like Android).
    private(set) var widthPx = 0
    private(set) var heightPx = 0

    /// False for windows that never take touches (toasts: WindowManager.LayoutParams.FLAG_NOT_TOUCHABLE).
    var isTouchable = true

    /// Window.Callback.dispatchTouchEvent (Activity / Dialog): when set, every touch event of this window goes here
    /// instead of straight to the root view; the callback calls `superDispatchTouchEvent` to reach the views.
    var windowCallbackDispatchTouchEvent: ((AMotionEvent) -> Bool)?

    /// The insets most recently dispatched to the tree (View.getRootWindowInsets).
    private(set) var lastDispatchedInsets: AWindowInsetsCompat?

    private var mAdded = false
    private var mFirst = true
    private var mTraversalScheduled = false
    private var mLayoutRequested = false
    private var mInLayout = false
    private var mHandlingLayoutInLayoutRequest = false
    private var mLayoutRequesters: [AView] = []
    private var mWillDrawSoon = false
    private var mApplyInsetsRequested = false
    /// mViewVisibility: the window visibility of the last traversal.
    private var mViewVisibility = AView.GONE
    private var mLastMeasuredWidth = -1
    private var mLastMeasuredHeight = -1
    /// Views were invalidated since the last draw walk.
    private var mHasDirtyViews = true
    private var mIsDrawing = false
    private var mInvalidatedDuringDraw: [AView] = []
    /// ViewRootImpl.InvalidateOnAnimationRunnable.
    private var mInvalidateOnAnimationViews: [AView] = []
    private var mInvalidateOnAnimationPosted = false
    private lazy var mInvalidateOnAnimationRunnable = ARunnable { [weak self] in self?.runInvalidateOnAnimation() }
    /// ViewRootImpl.getRunQueue(): actions posted from a traversal for the next one.
    private var mRunQueue: [ARunnable] = []
    /// The keyboard overlap at the bottom of the container, in px (the IME insets).
    private var mImeBottomPx = 0
    private var mHiddenObservations: [NSKeyValueObservation] = []

    // Touch stream state.
    private var mTouchIds: [ObjectIdentifier: Int] = [:]
    private var mActiveTouches: [Int: UITouch] = [:]
    private var mIgnoredTouches: Set<ObjectIdentifier> = []
    private var mTouchDownTime: Int64 = 0
    private var mLastMoveEventTimestamp: TimeInterval = -1

    // MARK: - init

    /// A window whose views live in `host` (a plain UIView owned by the activity layer). Set `contentView` to give it
    /// its root view; the tree is attached by the first traversal once the host is in a UIWindow.
    init(host: UIView) {
        self.host = host
        handler = AHandler(ALooper.getMainLooper())
        treeObserver = AViewTreeObserver()
        containerView = AViewRootContainerView(frame: host.bounds)
        attachInfo = AView.AttachInfo(root: self, handler: handler, treeObserver: treeObserver)
        containerView.viewRoot = self
        containerView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        host.addSubview(containerView)
        AViewRoot.sRoots.append(WeakRoot(self))
        AViewRoot.installObserversIfNeeded()
        updateWindowSize()
        observeHiddenAncestors()
    }

    deinit {
        mHiddenObservations.forEach { $0.invalidate() }
    }

    var description: String {
        "AViewRoot{\(view.map { String(describing: type(of: $0)) } ?? "no view") \(widthPx)x\(heightPx) attached=\(mAdded)}"
    }

    // MARK: - the root view

    /// The window's root view (an activity's decor view). Setting it detaches the previous one; the new one is
    /// attached by the next traversal (ViewRootImpl.setView -> requestLayout).
    var contentView: AView? {
        get { view }
        set { setView(newValue) }
    }

    /// ViewRootImpl.setView (nil removes the current view, like WindowManager.removeView).
    func setView(_ newView: AView?) {
        if newView === view { return }
        if let old = view {
            if mAdded {
                resetTouchStream()
                old.dispatchDetachedFromWindow()
                mAdded = false
            }
            old.mViewRootParent = nil
            old.removeFromSuperview()
            AView.updateKeepScreenOn()
        }
        view = nil
        mFirst = true
        lastDispatchedInsets = nil
        mLayoutRequesters.removeAll()
        mInvalidateOnAnimationViews.removeAll()
        if let v = newView {
            precondition(v.mParent == nil && v.mViewRootParent == nil,
                         "The specified child already has a parent. You must call removeView() on the child's parent first.")
            view = v
            v.mViewRootParent = self
            containerView.addSubview(v)
            v.updateUIKitFrame()
            mHasDirtyViews = true
            requestLayout()
        } else {
            unscheduleTraversals()
        }
    }

    /// Removes the window: the tree is detached and the container leaves the host.
    func dispose() {
        setView(nil)
        mHiddenObservations.forEach { $0.invalidate() }
        mHiddenObservations.removeAll()
        containerView.removeFromSuperview()
        unscheduleTraversals()
        AViewRoot.sRoots.removeAll { $0.root == nil || $0.root === self }
    }

    var isAttached: Bool { mAdded }

    /// The window's position on the screen in px (View.getLocationOnScreen adds it).
    var windowOffsetOnScreenPx: (x: Int, y: Int) {
        guard containerView.window != nil else { return (x: 0, y: 0) }
        let p = containerView.convert(CGPoint.zero, to: nil)
        let d = AView.densityScale
        return (x: Int((p.x * d).rounded()), y: Int((p.y * d).rounded()))
    }

    // MARK: - layout requests (ViewParent of the root view)

    var isInLayout: Bool { mInLayout }

    /// ViewRootImpl.isLayoutRequested.
    var isLayoutRequested: Bool { mLayoutRequested }

    /// ViewRootImpl.requestLayout.
    func requestLayout() {
        if !mHandlingLayoutInLayoutRequest {
            mLayoutRequested = true
            scheduleTraversals()
        }
    }

    /// ViewRootImpl.requestLayoutDuringLayout: true lets the view's request proceed (handled by a second pass).
    func requestLayoutDuringLayout(_ view: AView) -> Bool {
        // (The root view's ViewParent is this ViewRootImpl.)
        if (view.mParent == nil && view.mViewRootParent == nil) || view.mAttachInfo == nil {
            // Would not normally trigger another layout, so just let it pass through as usual
            return true
        }
        if !mLayoutRequesters.contains(where: { $0 === view }) {
            mLayoutRequesters.append(view)
        }
        if !mHandlingLayoutInLayoutRequest {
            // Let the request proceed normally; it will be processed in a second layout pass if necessary
            return true
        } else {
            // Don't let the request proceed during the second layout pass. It will post to the next frame instead.
            return false
        }
    }

    /// ViewRootImpl.requestFitSystemWindows (View.requestApplyInsets).
    func requestApplyInsets() {
        mApplyInsetsRequested = true
        scheduleTraversals()
    }

    // MARK: - invalidation

    /// A view of this window was invalidated (View.invalidate).
    func scheduleDraw(_ view: AView) {
        if mIsDrawing {
            mInvalidatedDuringDraw.append(view)
            return
        }
        mHasDirtyViews = true
        if !mWillDrawSoon {
            scheduleTraversals()
        }
    }

    /// A view left the window (View.onDetachedFromWindowInternal): it is no longer drawn by this window.
    func cancelDraw(_ view: AView) {
        mInvalidatedDuringDraw.removeAll { $0 === view }
        mInvalidateOnAnimationViews.removeAll { $0 === view }
    }

    /// ViewRootImpl.dispatchInvalidateOnAnimation: the view is invalidated in the next frame's ANIMATION phase.
    func dispatchInvalidateOnAnimation(_ view: AView) {
        mInvalidateOnAnimationViews.append(view)
        if !mInvalidateOnAnimationPosted {
            AChoreographer.getInstance().postAnimationRunnable(mInvalidateOnAnimationRunnable)
            mInvalidateOnAnimationPosted = true
        }
    }

    private func runInvalidateOnAnimation() {
        mInvalidateOnAnimationPosted = false
        let views = mInvalidateOnAnimationViews
        mInvalidateOnAnimationViews.removeAll()
        for v in views {
            v.invalidate()
        }
    }

    // MARK: - traversals

    /// ViewRootImpl.scheduleTraversals: one traversal of this window in the next frame.
    func scheduleTraversals() {
        if !mTraversalScheduled {
            mTraversalScheduled = true
            AViewRoot.sScheduled.append(self)
        }
        AViewRoot.ensureTraversalHandler()
        let choreographer = AChoreographer.getInstance()
        if !choreographer.isTraversalScheduled {
            choreographer.requestTraversal()
        }
    }

    /// ViewRootImpl.unscheduleTraversals.
    func unscheduleTraversals() {
        if mTraversalScheduled {
            mTraversalScheduled = false
            AViewRoot.sScheduled.removeAll { $0 === self }
            if AViewRoot.sScheduled.isEmpty {
                AChoreographer.getInstance().cancelTraversal()
            }
        }
    }

    /// Installs the view system's traversal (once; again if a test reset the Choreographer).
    private static func ensureTraversalHandler() {
        let choreographer = AChoreographer.getInstance()
        if choreographer.traversalHandler == nil {
            choreographer.traversalHandler = { frameTimeNanos in
                AViewRoot.runScheduledTraversals(frameTimeNanos)
            }
        }
    }

    /// The Choreographer's TRAVERSAL phase: every scheduled window, in scheduling order. A window scheduling again
    /// during this phase runs in the next frame.
    static func runScheduledTraversals(_ frameTimeNanos: Int64) {
        let roots = sScheduled
        sScheduled.removeAll()
        for root in roots {
            root.doTraversal()
        }
    }

    /// Runs this window's pending traversal now (tests, and code that needs a synchronous layout).
    func doTraversalNow() {
        if mTraversalScheduled {
            AViewRoot.sScheduled.removeAll { $0 === self }
        }
        mTraversalScheduled = true
        doTraversal()
    }

    private func doTraversal() {
        if mTraversalScheduled {
            mTraversalScheduled = false
            performTraversals()
        }
    }

    /// The window is stopped (no layout, no drawing): not in a UIWindow, the app in the background, or the container
    /// or one of its ancestors hidden (the activity layer hides a stopped activity's window).
    private var isStopped: Bool {
        guard containerView.window != nil else { return true }
        if AViewRoot.isAppInBackground { return true }
        var v: UIView? = containerView
        while let current = v, !(current is UIWindow) {
            if current.isHidden { return true }
            v = current.superview
        }
        return false
    }

    private static var isAppInBackground: Bool {
        UIApplication.shared.applicationState == .background
    }

    /// ViewRootImpl.getHostVisibility.
    private func hostVisibility(_ stopped: Bool) -> Int {
        guard let host = view, !stopped else { return AView.GONE }
        return host.visibility
    }

    private func updateWindowSize() {
        let d = AView.densityScale
        let size = containerView.bounds.size
        widthPx = Int((size.width * d).rounded())
        heightPx = Int((size.height * d).rounded())
    }

    /// ViewRootImpl.performTraversals.
    private func performTraversals() {
        guard let host = view else { return }
        // A window that is not on screen yet (the activity is created before its window is shown) attaches later.
        if containerView.window == nil {
            if mAdded {
                detachTree()
            }
            return
        }
        mWillDrawSoon = true
        defer { mWillDrawSoon = false }

        updateWindowSize()
        let stopped = isStopped
        let viewVisibility = hostVisibility(stopped)
        let viewVisibilityChanged = !mFirst && mViewVisibility != viewVisibility

        if mFirst {
            mLayoutRequested = true
            mHasDirtyViews = true
            attachInfo.windowVisibility = viewVisibility
            mAdded = true
            host.dispatchAttachedToWindow(attachInfo, 0)
            dispatchApplyInsets(host)
        }

        if viewVisibilityChanged {
            attachInfo.windowVisibility = viewVisibility
            host.dispatchWindowVisibilityChanged(viewVisibility)
            if viewVisibility == AView.VISIBLE {
                mHasDirtyViews = true
            }
            AView.updateKeepScreenOn()
        }
        mViewVisibility = viewVisibility

        // Execute enqueued actions on every traversal (the second-pass layout requests of the last one).
        if !mRunQueue.isEmpty {
            let actions = mRunQueue
            mRunQueue.removeAll()
            for action in actions {
                handler.post(action)
            }
        }

        if widthPx != mLastMeasuredWidth || heightPx != mLastMeasuredHeight {
            // A resized window lays out again (ViewRootImpl.handleResized -> requestLayout).
            mLayoutRequested = true
        }

        if !mFirst && mLayoutRequested && !mApplyInsetsRequested {
            // Safety net for a missed safe-area notification: a layout pass re-checks the insets.
            if let last = lastDispatchedInsets, last != computeWindowInsets() {
                mApplyInsetsRequested = true
            }
        }
        if mApplyInsetsRequested {
            dispatchApplyInsets(host)
        }

        let layoutRequested = mLayoutRequested && !stopped
        if layoutRequested {
            // Clear this now, so that if anything requests a layout in the rest of this function we will catch it
            // and re-run a full layout pass.
            mLayoutRequested = false
            measureHierarchy(host)
            performLayout(host)
        }

        if layoutRequested {
            treeObserver.dispatchOnGlobalLayout()
        }

        mFirst = false
        mWillDrawSoon = false

        let isViewVisible = viewVisibility == AView.VISIBLE
        let cancelDraw = treeObserver.dispatchOnPreDraw() || !isViewVisible
        if !cancelDraw {
            performDraw(host)
        } else if isViewVisible {
            // Try again
            scheduleTraversals()
        }
    }

    /// ViewRootImpl.measureHierarchy for a MATCH_PARENT window: EXACTLY the window size.
    private func measureHierarchy(_ host: AView) {
        let childWidthMeasureSpec = AMeasureSpec.makeMeasureSpec(widthPx, AMeasureSpec.EXACTLY)
        let childHeightMeasureSpec = AMeasureSpec.makeMeasureSpec(heightPx, AMeasureSpec.EXACTLY)
        host.measure(childWidthMeasureSpec, childHeightMeasureSpec)
        mLastMeasuredWidth = widthPx
        mLastMeasuredHeight = heightPx
    }

    /// ViewRootImpl.performLayout, with the second pass for views that requested a layout during the first.
    private func performLayout(_ host: AView) {
        mInLayout = true
        host.layout(0, 0, host.measuredWidth, host.measuredHeight)
        mInLayout = false

        if !mLayoutRequesters.isEmpty {
            // requestLayout() was called during layout. If no layout-request flags are set on the requesting views,
            // there is no problem. If some requests are still pending, then we need to clear those flags and do a
            // full request/measure/layout pass to handle this situation.
            if let validLayoutRequesters = getValidLayoutRequesters(false) {
                // Set this flag to indicate that any further requests are happening during the second pass, which
                // may result in posting those requests to the next frame instead
                mHandlingLayoutInLayoutRequest = true

                // Process fresh layout requests, then measure and layout
                for view in validLayoutRequesters {
                    ALog.w("View", "requestLayout() improperly called by \(view) during layout: running second layout pass")
                    view.requestLayout()
                }
                measureHierarchy(host)
                mInLayout = true
                host.layout(0, 0, host.measuredWidth, host.measuredHeight)

                mHandlingLayoutInLayoutRequest = false

                // Check the valid requests again, this time without checking/clearing the layout flags, since
                // requests happening during the second pass get noop'd
                if let secondPass = getValidLayoutRequesters(true) {
                    // Post second-pass requests to the next frame
                    mRunQueue.append(ARunnable {
                        for view in secondPass {
                            ALog.w("View", "requestLayout() improperly called by \(view) during second layout pass: posting in next frame")
                            view.requestLayout()
                        }
                    })
                }
            }
        }
        mInLayout = false
    }

    /// ViewRootImpl.getValidLayoutRequesters.
    private func getValidLayoutRequesters(_ secondLayoutRequests: Bool) -> [AView]? {
        let layoutRequesters = mLayoutRequesters
        var validLayoutRequesters: [AView]? = nil
        for view in layoutRequesters {
            if view.mAttachInfo != nil && (view.mParent != nil || view.mViewRootParent != nil)
                && (secondLayoutRequests || view.mForceLayout) {
                var gone = false
                var parent: AView? = view
                // Only trigger new requests for views in a non-GONE hierarchy
                while let p = parent {
                    if p.visibility == AView.GONE {
                        gone = true
                        break
                    }
                    parent = p.mParent
                }
                if !gone {
                    if validLayoutRequesters == nil {
                        validLayoutRequesters = []
                    }
                    validLayoutRequesters!.append(view)
                }
            }
        }
        if !secondLayoutRequests {
            // If we're checking the layout flags, then we need to clean them up also
            for requester in layoutRequesters {
                var view: AView? = requester
                while let v = view, v.mForceLayout {
                    v.mForceLayout = false
                    view = v.mParent
                }
            }
        }
        mLayoutRequesters.removeAll()
        return validLayoutRequesters
    }

    /// ViewRootImpl.performDraw / draw: the scroll and draw listeners, then the draw walk.
    private func performDraw(_ host: AView) {
        if attachInfo.viewScrollChanged {
            attachInfo.viewScrollChanged = false
            treeObserver.dispatchOnScrollChanged()
        }
        treeObserver.dispatchOnDraw()
        if !mHasDirtyViews {
            return
        }
        mHasDirtyViews = false
        mIsDrawing = true
        drawWalk(host)
        mIsDrawing = false
        if !mInvalidatedDuringDraw.isEmpty {
            let invalidated = mInvalidatedDuringDraw
            mInvalidatedDuringDraw.removeAll()
            // Views invalidated after the walk passed them are drawn next frame.
            if invalidated.contains(where: { $0.mDirty && $0.mAttachInfo === attachInfo }) {
                mHasDirtyViews = true
                scheduleTraversals()
            }
        }
    }

    /// Draws every invalidated VISIBLE view of the subtree, parents before children, children in drawing (Z) order.
    private func drawWalk(_ v: AView) {
        if v.visibility != AView.VISIBLE {
            return
        }
        if v.mDirty {
            v.computeScroll()
            v.performTraversalDraw()
        }
        if let group = v as? AViewGroup, group.childCount > 0 {
            for child in group.buildOrderedChildList() {
                drawWalk(child)
            }
        }
    }

    // MARK: - attach / detach / window visibility

    /// The container moved into or out of a UIWindow.
    fileprivate func containerWindowDidChange() {
        observeHiddenAncestors()
        if containerView.window == nil {
            if mAdded {
                detachTree()
            }
        } else if view != nil {
            if mFirst {
                mLayoutRequested = true
            }
            scheduleTraversals()
        }
    }

    /// Android removes the window (ViewRootImpl.dispatchDetachedFromWindow); here the root view stays assigned and
    /// is attached again by a later traversal if the container returns to a window.
    private func detachTree() {
        guard mAdded, let host = view else { return }
        resetTouchStream()
        host.dispatchDetachedFromWindow()
        mAdded = false
        mFirst = true
        mLayoutRequested = true
        mViewVisibility = AView.GONE
        attachInfo.windowVisibility = AView.GONE
        lastDispatchedInsets = nil
        mLayoutRequesters.removeAll()
        mInvalidatedDuringDraw.removeAll()
        mInvalidateOnAnimationViews.removeAll()
        unscheduleTraversals()
        AView.updateKeepScreenOn()
    }

    /// Re-evaluates the window visibility now (the app went to the background: no frame will run to do it).
    func refreshWindowVisibility() {
        guard mAdded, let host = view else { return }
        let viewVisibility = hostVisibility(isStopped)
        if viewVisibility != mViewVisibility {
            mViewVisibility = viewVisibility
            attachInfo.windowVisibility = viewVisibility
            host.dispatchWindowVisibilityChanged(viewVisibility)
            AView.updateKeepScreenOn()
        }
        if viewVisibility == AView.VISIBLE {
            mHasDirtyViews = true
        }
        scheduleTraversals()
    }

    /// The container and its ancestors are observed for isHidden (the activity layer hides a stopped activity).
    private func observeHiddenAncestors() {
        mHiddenObservations.forEach { $0.invalidate() }
        mHiddenObservations.removeAll()
        var v: UIView? = containerView
        while let current = v, !(current is UIWindow) {
            mHiddenObservations.append(current.observe(\.isHidden, options: [.new]) { [weak self] _, _ in
                self?.hiddenStateChanged()
            })
            v = current.superview
        }
    }

    private func hiddenStateChanged() {
        if mAdded {
            refreshWindowVisibility()
        } else if view != nil {
            scheduleTraversals()
        }
    }

    // MARK: - container geometry

    /// The container's bounds changed (rotation, split view, the activity layer resized it).
    fileprivate func containerDidLayout() {
        let oldW = widthPx, oldH = heightPx
        updateWindowSize()
        if oldW != widthPx || oldH != heightPx {
            requestLayout()
        }
        if mAdded, let last = lastDispatchedInsets, last != computeWindowInsets() {
            requestApplyInsets()
        }
    }

    fileprivate func containerSafeAreaDidChange() {
        if mAdded {
            if let last = lastDispatchedInsets, last == computeWindowInsets() { return }
            requestApplyInsets()
        }
    }

    fileprivate func keyboardFrameDidChange(_ endFrameInScreen: CGRect?) {
        var overlap = 0
        if let frame = endFrameInScreen, let window = containerView.window {
            let local = containerView.convert(frame, from: window.screen.coordinateSpace)
            let bottom = containerView.bounds.maxY
            if local.minY < bottom && local.maxY > containerView.bounds.minY && local.width > 0 && local.height > 0 {
                overlap = Int(((bottom - max(local.minY, containerView.bounds.minY)) * AView.densityScale).rounded())
            }
        }
        if overlap != mImeBottomPx {
            mImeBottomPx = overlap
            if mAdded {
                requestApplyInsets()
            }
        }
    }

    // MARK: - window insets

    /// The window insets of this window in px, from the container's safe area (AInsets.swift). Hidden status /
    /// navigation bars (WindowInsetsControllerCompat.hide) are not visible insets, as on Android.
    func computeWindowInsets() -> AWindowInsetsCompat {
        let d = AView.densityScale
        let s = containerView.safeAreaInsets
        let left = Int((s.left * d).rounded())
        let top = Int((s.top * d).rounded())
        let right = Int((s.right * d).rounded())
        let bottom = Int((s.bottom * d).rounded())
        let hidden = hiddenInsetTypes
        var statusBarVisible = (hidden & AWindowInsetsCompat.statusBars()) == 0
        if let manager = containerView.window?.windowScene?.statusBarManager, manager.isStatusBarHidden {
            statusBarVisible = false
        }
        let navigationBarVisible = (hidden & AWindowInsetsCompat.navigationBars()) == 0
        return AWindowInsetsCompat.fromSafeArea(left: left, top: top, right: right, bottom: bottom,
                                                statusBarVisible: statusBarVisible,
                                                navigationBarVisible: navigationBarVisible, imeBottom: mImeBottomPx)
    }

    /// The system bars an activity window hid (AWindow.hiddenInsetTypes of the activity that owns the host).
    private var hiddenInsetTypes: Int {
        var v: UIView? = host
        while let current = v {
            if let rootView = current as? AActivityRootView {
                return rootView.activity?.window.hiddenInsetTypes ?? 0
            }
            v = current.superview
        }
        return 0
    }

    /// ViewRootImpl.dispatchApplyInsets.
    private func dispatchApplyInsets(_ host: AView) {
        mApplyInsetsRequested = false
        let insets = computeWindowInsets()
        lastDispatchedInsets = insets
        host.dispatchApplyWindowInsets(insets)
    }

    // MARK: - touches

    /// UIKit touches of any view of this window (AView.touchesBegan / Moved / Ended / Cancelled forward here).
    func handleTouches(_ touches: Set<UITouch>, _ event: UIEvent?, _ phase: TouchPhase) {
        switch phase {
        case .began:
            touchesBegan(touches)
        case .moved:
            touchesMoved(touches, event)
        case .ended:
            touchesEnded(touches)
        case .cancelled:
            touchesCancelled(touches)
        }
    }

    private var canDeliverTouches: Bool {
        mAdded && view != nil && view!.mAttachInfo != nil
    }

    private func touchesBegan(_ touches: Set<UITouch>) {
        guard canDeliverTouches else { return }
        finishStaleTouches(except: touches)
        if !canDeliverTouches { return }
        let fresh = touches.filter { mTouchIds[ObjectIdentifier($0)] == nil && !mIgnoredTouches.contains(ObjectIdentifier($0)) }
            .sorted(by: AViewRoot.touchPrecedes)
        for touch in fresh {
            var id = 0
            while mActiveTouches[id] != nil {
                id += 1
            }
            mTouchIds[ObjectIdentifier(touch)] = id
            mActiveTouches[id] = touch
            let eventTimeNanos = AViewRoot.nanos(touch.timestamp)
            let action: Int
            if mActiveTouches.count == 1 {
                mTouchDownTime = eventTimeNanos / 1_000_000
                action = AMotionEvent.ACTION_DOWN
            } else {
                let index = mActiveTouches.keys.sorted().firstIndex(of: id)!
                action = AMotionEvent.ACTION_POINTER_DOWN | (index << AMotionEvent.ACTION_POINTER_INDEX_SHIFT)
            }
            deliver(makeEvent(action, eventTimeNanos, nil))
            if !canDeliverTouches { return }
        }
    }

    private func touchesMoved(_ touches: Set<UITouch>, _ event: UIEvent?) {
        guard canDeliverTouches else { return }
        // One MOVE per UIEvent: UIKit reports the moved touches of different views in separate calls.
        if let e = event {
            if e.timestamp == mLastMoveEventTimestamp { return }
        }
        var moved = touches.filter { mTouchIds[ObjectIdentifier($0)] != nil }
        if let all = event?.allTouches {
            for t in all where t.phase == .moved && mTouchIds[ObjectIdentifier(t)] != nil {
                moved.insert(t)
            }
        }
        if moved.isEmpty { return }
        if let e = event {
            mLastMoveEventTimestamp = e.timestamp
        }
        let eventTimeNanos = AViewRoot.nanos(moved.map { $0.timestamp }.max()!)
        deliver(makeEvent(AMotionEvent.ACTION_MOVE, eventTimeNanos, event))
    }

    /// Android's input dispatcher always closes a pointer stream (UP or CANCEL). UIKit may not, when the view a finger
    /// went down on leaves the window mid-gesture (a fragment replaced under the finger): the touch can end without
    /// touchesEnded/touchesCancelled reaching any view of this window. A finger that UIKit has already ended or
    /// cancelled is closed here, before the next pointer change; otherwise every later DOWN would arrive as a
    /// POINTER_DOWN of a stream that never ends, and no view of the window would get a tap again. When UIKit does
    /// deliver the end later, the touch is no longer tracked and the delivery is ignored.
    private func finishStaleTouches(except current: Set<UITouch>) {
        let stale = mActiveTouches.values.filter {
            !current.contains($0) && ($0.phase == .ended || $0.phase == .cancelled)
        }
        if stale.isEmpty { return }
        let cancelled = stale.filter { $0.phase == .cancelled }
        if !cancelled.isEmpty {
            touchesCancelled(Set(cancelled))
        } else {
            touchesEnded(Set(stale))
        }
    }

    private func touchesEnded(_ touches: Set<UITouch>) {
        finishStaleTouches(except: touches)
        let ending = touches.compactMap { t -> (Int, UITouch)? in
            guard let id = mTouchIds[ObjectIdentifier(t)] else { return nil }
            return (id, t)
        }.sorted { $0.0 < $1.0 }
        for t in touches {
            mIgnoredTouches.remove(ObjectIdentifier(t))
        }
        for (id, touch) in ending {
            guard mActiveTouches[id] != nil else { continue }
            let eventTimeNanos = AViewRoot.nanos(touch.timestamp)
            let action: Int
            if mActiveTouches.count == 1 {
                action = AMotionEvent.ACTION_UP
            } else {
                let index = mActiveTouches.keys.sorted().firstIndex(of: id)!
                action = AMotionEvent.ACTION_POINTER_UP | (index << AMotionEvent.ACTION_POINTER_INDEX_SHIFT)
            }
            if canDeliverTouches {
                deliver(makeEvent(action, eventTimeNanos, nil))
            }
            mActiveTouches[id] = nil
            mTouchIds[ObjectIdentifier(touch)] = nil
        }
        if mActiveTouches.isEmpty {
            mLastMoveEventTimestamp = -1
        }
    }

    private func touchesCancelled(_ touches: Set<UITouch>) {
        let cancelling = touches.filter { mTouchIds[ObjectIdentifier($0)] != nil }
        for t in touches {
            mIgnoredTouches.remove(ObjectIdentifier(t))
        }
        if cancelling.isEmpty { return }
        let eventTimeNanos = AViewRoot.nanos(cancelling.map { $0.timestamp }.max()!)
        if canDeliverTouches {
            deliver(makeEvent(AMotionEvent.ACTION_CANCEL, eventTimeNanos, nil))
        }
        // The rest of a cancelled gesture is not delivered (the remaining fingers are ignored until they lift).
        for (_, t) in mActiveTouches where !cancelling.contains(t) {
            mIgnoredTouches.insert(ObjectIdentifier(t))
        }
        mActiveTouches.removeAll()
        mTouchIds.removeAll()
        mLastMoveEventTimestamp = -1
    }

    /// Forgets the touch stream (the window is detached or its view replaced); the views already got CANCEL from
    /// their ViewGroup detach.
    private func resetTouchStream() {
        for (_, t) in mActiveTouches {
            mIgnoredTouches.insert(ObjectIdentifier(t))
        }
        mActiveTouches.removeAll()
        mTouchIds.removeAll()
        mLastMoveEventTimestamp = -1
    }

    /// Several touches beginning in one UIEvent get their ids in a stable order: earlier timestamp, then position.
    private static func touchPrecedes(_ a: UITouch, _ b: UITouch) -> Bool {
        if a.timestamp != b.timestamp { return a.timestamp < b.timestamp }
        let pa = a.location(in: nil), pb = b.location(in: nil)
        if pa.x != pb.x { return pa.x < pb.x }
        return pa.y < pb.y
    }

    /// UITouch timestamps (seconds since boot, the CLOCK_UPTIME_RAW clock of ASystem.nanoTime) in nanoseconds.
    private static func nanos(_ timestamp: TimeInterval) -> Int64 {
        Int64((timestamp * 1_000_000_000).rounded())
    }

    /// One Android event with every active pointer (id order) at its current location, root px.
    private func makeEvent(_ action: Int, _ eventTimeNanos: Int64, _ uiEvent: UIEvent?) -> AMotionEvent {
        let d = AView.densityScale
        let ids = mActiveTouches.keys.sorted()
        let rootView: UIView = view ?? containerView
        var xs: [Float] = [], ys: [Float] = [], rawXs: [Float] = [], rawYs: [Float] = []
        xs.reserveCapacity(ids.count)
        for id in ids {
            let touch = mActiveTouches[id]!
            let p = touch.location(in: rootView)
            let r = touch.location(in: nil)
            xs.append(Float(p.x * d))
            ys.append(Float(p.y * d))
            rawXs.append(Float(r.x * d))
            rawYs.append(Float(r.y * d))
        }
        let ev = AMotionEvent.obtainTouch(downTime: mTouchDownTime, eventTimeNanos: eventTimeNanos, action: action,
                                          pointerIds: ids, xs: xs, ys: ys, rawXs: rawXs, rawYs: rawYs)
        guard let e = uiEvent else { return ev }
        // Batched history: the coalesced samples of the moved touches before the current one, oldest first.
        var samples: [[UITouch]] = []
        var reference = -1
        var history = Int.max
        for (i, id) in ids.enumerated() {
            let touch = mActiveTouches[id]!
            if touch.phase == .moved, let coalesced = e.coalescedTouches(for: touch), !coalesced.isEmpty {
                samples.append(coalesced)
                history = min(history, coalesced.count - 1)
                if reference < 0 { reference = i }
            } else {
                samples.append([touch])
            }
        }
        if reference < 0 || history == Int.max || history <= 0 { return ev }
        for k in 0..<history {
            let back = history - k
            var hx: [Float] = [], hy: [Float] = []
            for list in samples {
                let index = list.count - 1 - back
                let s = index >= 0 ? list[index] : list[list.count - 1]
                let p = s.location(in: rootView)
                hx.append(Float(p.x * d))
                hy.append(Float(p.y * d))
            }
            let ref = samples[reference]
            ev.addHistorySample(eventTimeNanos: AViewRoot.nanos(ref[ref.count - 1 - back].timestamp), xs: hx, ys: hy)
        }
        return ev
    }

    private func deliver(_ ev: AMotionEvent) {
        guard view != nil else { return }
        if let callback = windowCallbackDispatchTouchEvent {
            _ = callback(ev)
        } else {
            _ = superDispatchTouchEvent(ev)
        }
    }

    /// Window.superDispatchTouchEvent: the event into the view hierarchy (the root view's dispatchTouchEvent).
    @discardableResult
    func superDispatchTouchEvent(_ ev: AMotionEvent) -> Bool {
        guard let host = view, host.mAttachInfo != nil else { return false }
        return host.dispatchTouchEvent(ev)
    }

    /// Delivers a synthetic Android event to this window as if it came from the touch screen (tests, accessibility).
    @discardableResult
    func injectTouchEvent(_ ev: AMotionEvent) -> Bool {
        guard canDeliverTouches else { return false }
        if let callback = windowCallbackDispatchTouchEvent {
            return callback(ev)
        }
        return superDispatchTouchEvent(ev)
    }

    // MARK: - app and keyboard notifications (all windows)

    private static func installObserversIfNeeded() {
        if sObserversInstalled { return }
        sObserversInstalled = true
        let center = NotificationCenter.default
        sObservers.append(center.addObserver(forName: UIApplication.didEnterBackgroundNotification, object: nil,
                                             queue: .main) { _ in
            for root in AViewRoot.liveRoots { root.refreshWindowVisibility() }
        })
        let foreground: @Sendable (Notification) -> Void = { _ in
            for root in AViewRoot.liveRoots where root.view != nil { root.refreshWindowVisibilityLater() }
        }
        sObservers.append(center.addObserver(forName: UIApplication.willEnterForegroundNotification, object: nil,
                                             queue: .main, using: foreground))
        sObservers.append(center.addObserver(forName: UIApplication.didBecomeActiveNotification, object: nil,
                                             queue: .main, using: foreground))
        sObservers.append(center.addObserver(forName: UIResponder.keyboardWillChangeFrameNotification, object: nil,
                                             queue: .main) { note in
            let frame = (note.userInfo?[UIResponder.keyboardFrameEndUserInfoKey] as? NSValue)?.cgRectValue
            for root in AViewRoot.liveRoots { root.keyboardFrameDidChange(frame) }
        })
        sObservers.append(center.addObserver(forName: UIResponder.keyboardWillHideNotification, object: nil,
                                             queue: .main) { _ in
            for root in AViewRoot.liveRoots { root.keyboardFrameDidChange(nil) }
        })
    }

    /// The window becomes visible again on the next traversal (after the activity's onRestart/onResume).
    private func refreshWindowVisibilityLater() {
        if !mAdded {
            scheduleTraversals()
            return
        }
        mHasDirtyViews = true
        scheduleTraversals()
    }
}

/// The UIView of an AViewRoot: it fills the host (autoresizing), holds the root AView, reports size, safe-area and
/// window changes to its root, and never takes a touch itself (only the window's views do, through the root view).
final class AViewRootContainerView: UIView {
    weak var viewRoot: AViewRoot?

    override init(frame: CGRect) {
        super.init(frame: frame)
        isMultipleTouchEnabled = true
        isOpaque = false
        backgroundColor = nil
        autoresizesSubviews = false
        clipsToBounds = false
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        viewRoot?.containerDidLayout()
    }

    override func safeAreaInsetsDidChange() {
        super.safeAreaInsetsDidChange()
        viewRoot?.containerSafeAreaDidChange()
    }

    override func didMoveToWindow() {
        super.didMoveToWindow()
        viewRoot?.containerWindowDidChange()
    }

    /// The window's root view takes every touch inside the window (an alpha-0 view too, as Android); a window that is
    /// not touchable lets every touch through.
    override func hitTest(_ point: CGPoint, with event: UIEvent?) -> UIView? {
        guard let root = viewRoot, root.isTouchable, !isHidden, isUserInteractionEnabled, let v = root.view else {
            return nil
        }
        return v.hitTest(v.convert(point, from: self), with: event)
    }
}
