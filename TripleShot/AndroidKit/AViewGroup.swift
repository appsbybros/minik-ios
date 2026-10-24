import UIKit

// android.view.ViewGroup on UIKit (VIEW-API "Views").
//
// Children are kept in the Android child list (mChildren, the order that bringToFront changes and that layouts
// iterate) and hosted as UIKit subviews of a "child host" view, sorted by (elevation + translationZ) and then by
// child index exactly like ViewGroup.buildOrderedChildList, so drawing and hit testing follow the Android Z order.
// The child host spans the view; with clipToPadding (default true) and a non-zero padding it shrinks to the padding
// box and clips, like the clipRect of ViewGroup.dispatchDraw. clipChildren clips every child to its own bounds
// (Android clips each child RenderNode): a leaf child masks its layer; a child view group clips its child host
// instead, so its own layer stays unmasked and a layer-drawn elevation shadow stays visible outside the bounds, as
// Android draws shadows outside the clip. Scroll offsets move the host's bounds origin.
//
// Touch dispatch is the AOSP ViewGroup.dispatchTouchEvent algorithm: touch targets per pointer (split motion
// events), onInterceptTouchEvent, FLAG_DISALLOW_INTERCEPT, ACTION_CANCEL to targets taken over by an intercepting
// parent, children scanned front to back in Z order with the transformed-point-in-view test.

class AViewGroup: AView {

    // MARK: - LayoutParams

    /// ViewGroup.LayoutParams.
    class LayoutParams {
        static let MATCH_PARENT = -1
        static let FILL_PARENT = -1
        static let WRAP_CONTENT = -2

        var width: Int
        var height: Int

        init(_ width: Int, _ height: Int) {
            self.width = width
            self.height = height
        }

        init(_ source: LayoutParams) {
            self.width = source.width
            self.height = source.height
        }

        /// Resolves relative values (start/end) for the given resolved layout direction.
        func resolveLayoutDirection(_ layoutDirection: Int) {}

        static func sizeToString(_ size: Int) -> String {
            if size == WRAP_CONTENT { return "wrap-content" }
            if size == MATCH_PARENT { return "match-parent" }
            return String(size)
        }
    }

    /// ViewGroup.MarginLayoutParams (start/end margins resolve against the layout direction, AOSP semantics).
    class MarginLayoutParams: LayoutParams {
        /// Integer.MIN_VALUE: the relative margin is not set.
        static let DEFAULT_MARGIN_RELATIVE = Int(Int32.min)
        static let DEFAULT_MARGIN_RESOLVED = 0
        private static let LAYOUT_DIRECTION_MASK = 0x00000003
        private static let LEFT_MARGIN_UNDEFINED_MASK = 0x00000004
        private static let RIGHT_MARGIN_UNDEFINED_MASK = 0x00000008
        private static let NEED_RESOLUTION_MASK = 0x00000020

        var leftMargin = 0
        var topMargin = 0
        var rightMargin = 0
        var bottomMargin = 0
        private var mStartMargin = MarginLayoutParams.DEFAULT_MARGIN_RELATIVE
        private var mEndMargin = MarginLayoutParams.DEFAULT_MARGIN_RELATIVE
        private var mMarginFlags = 0

        override init(_ width: Int, _ height: Int) {
            super.init(width, height)
            mMarginFlags |= MarginLayoutParams.LEFT_MARGIN_UNDEFINED_MASK
            mMarginFlags |= MarginLayoutParams.RIGHT_MARGIN_UNDEFINED_MASK
            mMarginFlags &= ~MarginLayoutParams.NEED_RESOLUTION_MASK
        }

        /// Copy constructor (MarginLayoutParams(MarginLayoutParams)).
        init(_ source: MarginLayoutParams) {
            super.init(source.width, source.height)
            leftMargin = source.leftMargin
            topMargin = source.topMargin
            rightMargin = source.rightMargin
            bottomMargin = source.bottomMargin
            mStartMargin = source.mStartMargin
            mEndMargin = source.mEndMargin
            mMarginFlags = source.mMarginFlags
        }

        /// MarginLayoutParams(LayoutParams).
        override init(_ source: LayoutParams) {
            super.init(source)
            mMarginFlags |= MarginLayoutParams.LEFT_MARGIN_UNDEFINED_MASK
            mMarginFlags |= MarginLayoutParams.RIGHT_MARGIN_UNDEFINED_MASK
            mMarginFlags &= ~MarginLayoutParams.NEED_RESOLUTION_MASK
        }

        /// Copies the margins of a MarginLayoutParams (used by the converting constructors of subclasses).
        func copyMarginsFrom(_ source: MarginLayoutParams) {
            leftMargin = source.leftMargin
            topMargin = source.topMargin
            rightMargin = source.rightMargin
            bottomMargin = source.bottomMargin
            mStartMargin = source.mStartMargin
            mEndMargin = source.mEndMargin
            mMarginFlags = source.mMarginFlags
        }

        func setMargins(_ left: Int, _ top: Int, _ right: Int, _ bottom: Int) {
            leftMargin = left
            topMargin = top
            rightMargin = right
            bottomMargin = bottom
            mMarginFlags &= ~MarginLayoutParams.LEFT_MARGIN_UNDEFINED_MASK
            mMarginFlags &= ~MarginLayoutParams.RIGHT_MARGIN_UNDEFINED_MASK
            if isMarginRelative {
                mMarginFlags |= MarginLayoutParams.NEED_RESOLUTION_MASK
            } else {
                mMarginFlags &= ~MarginLayoutParams.NEED_RESOLUTION_MASK
            }
        }

        /// androidx core-ktx `setMargins(size)`.
        func setMargins(_ size: Int) { setMargins(size, size, size, size) }

        func setMarginsRelative(_ start: Int, _ top: Int, _ end: Int, _ bottom: Int) {
            mStartMargin = start
            topMargin = top
            mEndMargin = end
            bottomMargin = bottom
            mMarginFlags |= MarginLayoutParams.NEED_RESOLUTION_MASK
        }

        /// getMarginStart / setMarginStart (Kotlin `marginStart`).
        var marginStart: Int {
            get {
                if mStartMargin != MarginLayoutParams.DEFAULT_MARGIN_RELATIVE { return mStartMargin }
                if (mMarginFlags & MarginLayoutParams.NEED_RESOLUTION_MASK) == MarginLayoutParams.NEED_RESOLUTION_MASK {
                    doResolveMargins()
                }
                switch mMarginFlags & MarginLayoutParams.LAYOUT_DIRECTION_MASK {
                case AView.LAYOUT_DIRECTION_RTL: return rightMargin
                default: return leftMargin
                }
            }
            set {
                mStartMargin = newValue
                mMarginFlags |= MarginLayoutParams.NEED_RESOLUTION_MASK
            }
        }

        /// getMarginEnd / setMarginEnd (Kotlin `marginEnd`).
        var marginEnd: Int {
            get {
                if mEndMargin != MarginLayoutParams.DEFAULT_MARGIN_RELATIVE { return mEndMargin }
                if (mMarginFlags & MarginLayoutParams.NEED_RESOLUTION_MASK) == MarginLayoutParams.NEED_RESOLUTION_MASK {
                    doResolveMargins()
                }
                switch mMarginFlags & MarginLayoutParams.LAYOUT_DIRECTION_MASK {
                case AView.LAYOUT_DIRECTION_RTL: return leftMargin
                default: return rightMargin
                }
            }
            set {
                mEndMargin = newValue
                mMarginFlags |= MarginLayoutParams.NEED_RESOLUTION_MASK
            }
        }

        /// The raw relative margins (DEFAULT_MARGIN_RELATIVE when unset).
        var rawStartMargin: Int { mStartMargin }
        var rawEndMargin: Int { mEndMargin }

        var isMarginRelative: Bool {
            mStartMargin > MarginLayoutParams.DEFAULT_MARGIN_RELATIVE || mEndMargin > MarginLayoutParams.DEFAULT_MARGIN_RELATIVE
        }

        var layoutDirection: Int { mMarginFlags & MarginLayoutParams.LAYOUT_DIRECTION_MASK }

        func setLayoutDirection(_ layoutDirection: Int) {
            if layoutDirection != AView.LAYOUT_DIRECTION_LTR && layoutDirection != AView.LAYOUT_DIRECTION_RTL { return }
            if layoutDirection != (mMarginFlags & MarginLayoutParams.LAYOUT_DIRECTION_MASK) {
                mMarginFlags &= ~MarginLayoutParams.LAYOUT_DIRECTION_MASK
                mMarginFlags |= (layoutDirection & MarginLayoutParams.LAYOUT_DIRECTION_MASK)
                if isMarginRelative {
                    mMarginFlags |= MarginLayoutParams.NEED_RESOLUTION_MASK
                } else {
                    mMarginFlags &= ~MarginLayoutParams.NEED_RESOLUTION_MASK
                }
            }
        }

        override func resolveLayoutDirection(_ layoutDirection: Int) {
            setLayoutDirection(layoutDirection)
            // No relative margin or no need to resolve: use the left and right margins.
            if !isMarginRelative
                || (mMarginFlags & MarginLayoutParams.NEED_RESOLUTION_MASK) != MarginLayoutParams.NEED_RESOLUTION_MASK {
                return
            }
            doResolveMargins()
        }

        private func doResolveMargins() {
            // We have some relative margins (either the start one or the end one or both). So use them and override
            // what has been defined for left and right margins. If either start or end margin is not defined, just
            // set it to default "0".
            switch mMarginFlags & MarginLayoutParams.LAYOUT_DIRECTION_MASK {
            case AView.LAYOUT_DIRECTION_RTL:
                leftMargin = mEndMargin > MarginLayoutParams.DEFAULT_MARGIN_RELATIVE ? mEndMargin : MarginLayoutParams.DEFAULT_MARGIN_RESOLVED
                rightMargin = mStartMargin > MarginLayoutParams.DEFAULT_MARGIN_RELATIVE ? mStartMargin : MarginLayoutParams.DEFAULT_MARGIN_RESOLVED
            default:
                leftMargin = mStartMargin > MarginLayoutParams.DEFAULT_MARGIN_RELATIVE ? mStartMargin : MarginLayoutParams.DEFAULT_MARGIN_RESOLVED
                rightMargin = mEndMargin > MarginLayoutParams.DEFAULT_MARGIN_RELATIVE ? mEndMargin : MarginLayoutParams.DEFAULT_MARGIN_RESOLVED
            }
            mMarginFlags &= ~MarginLayoutParams.NEED_RESOLUTION_MASK
        }
    }

    // MARK: - child host

    /// The UIKit view that holds the children's views (the AViewGroup itself never has child AViews as direct
    /// subviews). It never hit-tests on its own: AViewGroup.hitTestDescendants walks its subviews.
    class ChildHostView: UIView {
        weak var owner: AViewGroup?
        override init(frame: CGRect) {
            super.init(frame: frame)
            isMultipleTouchEnabled = true
            isOpaque = false
            autoresizesSubviews = false
            backgroundColor = nil
        }
        required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }
        override func hitTest(_ point: CGPoint, with event: UIEvent?) -> UIView? { nil }
    }

    // MARK: - state

    /// The Android child list (order of addView / bringToFront).
    private(set) var mChildren: [AView] = []
    /// The UIKit host of the children (see the file comment).
    private(set) var mChildHost: UIView!
    private var mClipChildren = true
    private var mClipToPadding = true
    /// The parent's clipChildren applies to this group: its child host clips the children to the bounds.
    private(set) var mClippedByParent = false
    private var mHostClipsToPadding = false
    private var mLastHostOrigin: (x: Int, y: Int) = (x: 0, y: 0)
    private var mFirstTouchTarget: TouchTarget?
    /// FLAG_DISALLOW_INTERCEPT.
    var mDisallowIntercept = false
    /// FLAG_SPLIT_MOTION_EVENTS (on by default since targetSdk HONEYCOMB).
    private var mSplitMotionEvents = true
    private var mOnHierarchyChangeListener: ((AViewGroup, AView, Bool) -> Void)?
    private var mLastTouchDownIndex = -1
    private var mLastTouchDownTime: Int64 = 0
    private var mLastTouchDownX: Float = 0
    private var mLastTouchDownY: Float = 0

    override init() {
        super.init()
        mWillNotDraw = true
        let host = makeChildHost()
        if let h = host as? ChildHostView { h.owner = self }
        host.frame = CGRect(origin: .zero, size: bounds.size)
        addSubview(host)
        mChildHost = host
    }

    /// Override point for AScrollView / AHorizontalScrollView (a UIScrollView host).
    func makeChildHost() -> UIView {
        ChildHostView(frame: .zero)
    }

    /// The Android coordinate (in this group's space, before scrolling) of the host's content origin.
    var childHostOriginPx: (x: Int, y: Int) {
        mHostClipsToPadding ? (x: mPaddingLeft, y: mPaddingTop) : (x: 0, y: 0)
    }

    override func didUpdateUIKitFrame() {
        updateChildHostGeometry()
    }

    override func paddingDidChange() {
        updateChildHostGeometry()
    }

    override func scrollOffsetDidChange() {
        updateChildHostGeometry()
    }

    /// Places the child host: the padding box when clipping to padding, else the whole view; the bounds origin
    /// carries the scroll offset. Repositions the children when the host origin changed.
    func updateChildHostGeometry() {
        guard mChildHost != nil else { return }
        let d = AView.densityScale
        let clipHost = mClipToPadding && (mPaddingLeft | mPaddingTop | mPaddingRight | mPaddingBottom) != 0
        mHostClipsToPadding = clipHost
        let origin = childHostOriginPx
        let originChanged = origin.x != mLastHostOrigin.x || origin.y != mLastHostOrigin.y
        mLastHostOrigin = origin
        let w = width, h = height
        let frame: CGRect
        if clipHost {
            frame = CGRect(x: CGFloat(mPaddingLeft) / d, y: CGFloat(mPaddingTop) / d,
                           width: CGFloat(max(0, w - mPaddingLeft - mPaddingRight)) / d,
                           height: CGFloat(max(0, h - mPaddingTop - mPaddingBottom)) / d)
        } else {
            frame = CGRect(x: 0, y: 0, width: CGFloat(w) / d, height: CGFloat(h) / d)
        }
        applyChildHostFrame(frame, clips: clipHost || mClippedByParent)
        if originChanged {
            for c in mChildren { c.updateUIKitFrame() }
        }
    }

    /// Override point for scroll views (content size and offset); sets frame, clipping and the scroll origin.
    func applyChildHostFrame(_ frame: CGRect, clips: Bool) {
        guard let host = mChildHost else { return }
        let d = AView.densityScale
        if host.frame.size != frame.size || host.center != CGPoint(x: frame.midX, y: frame.midY) {
            host.bounds = CGRect(x: CGFloat(mScrollX) / d, y: CGFloat(mScrollY) / d, width: frame.width, height: frame.height)
            host.center = CGPoint(x: frame.midX, y: frame.midY)
        } else {
            let origin = CGPoint(x: CGFloat(mScrollX) / d, y: CGFloat(mScrollY) / d)
            if host.bounds.origin != origin { host.bounds.origin = origin }
        }
        if host.clipsToBounds != clips { host.clipsToBounds = clips }
    }

    // MARK: - clipping

    /// The parent's clipChildren: the children (this group's subtree) are clipped by the child host; the group's own
    /// layer is never masked (elevation shadows).
    override func applyParentClip(_ clip: Bool) {
        if clipsToBounds { clipsToBounds = false }
        if mClippedByParent != clip {
            mClippedByParent = clip
            updateChildHostGeometry()
        }
    }

    var clipChildren: Bool {
        get { mClipChildren }
        set { setClipChildren(newValue) }
    }
    func getClipChildren() -> Bool { mClipChildren }
    func setClipChildren(_ clipChildren: Bool) {
        if mClipChildren != clipChildren {
            mClipChildren = clipChildren
            for c in mChildren { c.applyParentClip(clipChildren) }
            invalidate()
        }
    }

    var clipToPadding: Bool {
        get { mClipToPadding }
        set { setClipToPadding(newValue) }
    }
    func getClipToPadding() -> Bool { mClipToPadding }
    func setClipToPadding(_ clipToPadding: Bool) {
        if mClipToPadding != clipToPadding {
            mClipToPadding = clipToPadding
            updateChildHostGeometry()
            invalidate()
        }
    }

    // MARK: - children

    var childCount: Int { mChildren.count }
    func getChildCount() -> Int { mChildren.count }

    /// ViewGroup.getChildAt: nil when out of range.
    func getChildAt(_ index: Int) -> AView? {
        if index < 0 || index >= mChildren.count { return nil }
        return mChildren[index]
    }

    func indexOfChild(_ child: AView?) -> Int {
        guard let child = child else { return -1 }
        return mChildren.firstIndex(where: { $0 === child }) ?? -1
    }

    /// androidx core-ktx `ViewGroup.children` (a snapshot of the child list).
    var children: [AView] { mChildren }

    /// ViewGroup.generateDefaultLayoutParams: (WRAP_CONTENT, WRAP_CONTENT).
    func generateDefaultLayoutParams() -> LayoutParams {
        LayoutParams(LayoutParams.WRAP_CONTENT, LayoutParams.WRAP_CONTENT)
    }

    /// ViewGroup.checkLayoutParams.
    func checkLayoutParams(_ p: LayoutParams?) -> Bool { p != nil }

    /// ViewGroup.generateLayoutParams(LayoutParams).
    func generateLayoutParams(_ p: LayoutParams) -> LayoutParams { p }

    func addView(_ child: AView) {
        addView(child, -1)
    }

    func addView(_ child: AView, _ index: Int) {
        var params = child.mLayoutParams
        if params == nil {
            params = generateDefaultLayoutParams()
        }
        addView(child, index, params!)
    }

    func addView(_ child: AView, _ width: Int, _ height: Int) {
        let params = generateDefaultLayoutParams()
        params.width = width
        params.height = height
        addView(child, -1, params)
    }

    func addView(_ child: AView, _ params: LayoutParams) {
        addView(child, -1, params)
    }

    /// ViewGroup.addView(child, index, params): requestLayout, invalidate, addViewInner.
    func addView(_ child: AView, _ index: Int, _ params: LayoutParams) {
        requestLayout()
        invalidate()
        addViewInner(child, index, params, false)
    }

    /// ViewGroup.addViewInLayout (no requestLayout of this group).
    @discardableResult
    func addViewInLayout(_ child: AView, _ index: Int, _ params: LayoutParams, _ preventRequestLayout: Bool = false) -> Bool {
        addViewInner(child, index, params, preventRequestLayout)
        return true
    }

    private func addViewInner(_ child: AView, _ index: Int, _ params: LayoutParams, _ preventRequestLayout: Bool) {
        precondition(child.mParent == nil && child.mViewRootParent == nil,
                     "The specified child already has a parent. You must call removeView() on the child's parent first.")
        var p = params
        if !checkLayoutParams(p) {
            p = generateLayoutParams(p)
        }
        if preventRequestLayout {
            child.mLayoutParams = p
        } else {
            child.setLayoutParams(p)
        }
        var i = index
        if i < 0 {
            i = mChildren.count
        }
        precondition(i <= mChildren.count, "index=\(i) count=\(mChildren.count)")
        mChildren.insert(child, at: i)
        // tell our children
        child.mParent = self
        child.applyParentClip(mClipChildren)
        attachChildUIKitView(child)

        if let ai = mAttachInfo {
            child.dispatchAttachedToWindow(ai, child.visibility)
        }
        if child.isLayoutDirectionInherited {
            child.rtlPropertiesChanged()
        }
        dispatchViewAdded(child)
    }

    private func attachChildUIKitView(_ child: AView) {
        mChildHost.addSubview(child)
        child.updateUIKitFrame()
        sortChildViewsByZ()
    }

    func removeView(_ view: AView) {
        if removeViewInternal(view) {
            requestLayout()
            invalidate()
        }
    }

    func removeViewInLayout(_ view: AView) {
        _ = removeViewInternal(view)
    }

    func removeViewAt(_ index: Int) {
        guard let v = getChildAt(index) else { preconditionFailure("index \(index) out of range") }
        removeViewInternal(index, v)
        requestLayout()
        invalidate()
    }

    /// ViewGroup.removeViews(start, count).
    func removeViews(_ start: Int, _ count: Int) {
        removeViewsInternal(start, count)
        requestLayout()
        invalidate()
    }

    func removeAllViews() {
        removeAllViewsInLayout()
        requestLayout()
        invalidate()
    }

    /// ViewGroup.removeAllViewsInLayout: children are detached from the last to the first.
    func removeAllViewsInLayout() {
        let count = mChildren.count
        if count <= 0 { return }
        let children = mChildren
        mChildren.removeAll()
        let detach = mAttachInfo != nil
        var i = count - 1
        while i >= 0 {
            let view = children[i]
            if let ai = mAttachInfo, ai.focusedView != nil, view.hasFocus() { ai.focusedView = nil }
            cancelTouchTarget(view)
            if detach {
                view.dispatchDetachedFromWindow()
            }
            dispatchViewRemoved(view)
            view.mParent = nil
            view.removeFromSuperview()
            i -= 1
        }
    }

    private func removeViewInternal(_ view: AView) -> Bool {
        let index = indexOfChild(view)
        if index >= 0 {
            removeViewInternal(index, view)
            return true
        }
        return false
    }

    private func removeViewInternal(_ index: Int, _ view: AView) {
        if let ai = mAttachInfo, ai.focusedView != nil, view.hasFocus() { ai.focusedView = nil }
        cancelTouchTarget(view)
        if view.mAttachInfo != nil {
            view.dispatchDetachedFromWindow()
        }
        mChildren.remove(at: index)
        view.mParent = nil
        view.removeFromSuperview()
        dispatchViewRemoved(view)
    }

    private func removeViewsInternal(_ start: Int, _ count: Int) {
        let end = start + count
        precondition(start >= 0 && count >= 0 && end <= mChildren.count, "IndexOutOfBounds")
        let detach = mAttachInfo != nil
        for i in start..<end {
            let view = mChildren[i]
            if let ai = mAttachInfo, ai.focusedView != nil, view.hasFocus() { ai.focusedView = nil }
            cancelTouchTarget(view)
            if detach {
                view.dispatchDetachedFromWindow()
            }
            dispatchViewRemoved(view)
            view.mParent = nil
            view.removeFromSuperview()
        }
        mChildren.removeSubrange(start..<end)
    }

    /// ViewGroup.bringChildToFront: moves the child to the end of the child list (layout order changes too).
    func bringChildToFront(_ child: AView) {
        let index = indexOfChild(child)
        if index >= 0 {
            mChildren.remove(at: index)
            mChildren.append(child)
            sortChildViewsByZ()
            requestLayout()
            invalidate()
        }
    }

    func setOnHierarchyChangeListener(_ l: ((AViewGroup, AView, Bool) -> Void)?) {
        mOnHierarchyChangeListener = l
    }

    private func dispatchViewAdded(_ child: AView) {
        onViewAdded(child)
        mOnHierarchyChangeListener?(self, child, true)
    }

    private func dispatchViewRemoved(_ child: AView) {
        onViewRemoved(child)
        mOnHierarchyChangeListener?(self, child, false)
    }

    /// Override points (ViewGroup.onViewAdded / onViewRemoved).
    func onViewAdded(_ child: AView) {}
    func onViewRemoved(_ child: AView) {}

    /// Called by setLayoutParams on a child (ViewGroup.onSetLayoutParams).
    func onSetLayoutParams(_ child: AView, _ layoutParams: LayoutParams) {
        requestLayout()
    }

    /// ViewGroup.onChildVisibilityChanged (override point).
    func onChildVisibilityChanged(_ child: AView, _ oldVisibility: Int, _ newVisibility: Int) {}

    /// ViewGroup.childDrawableStateChanged (addStatesFromChildren is not used).
    func childDrawableStateChanged(_ child: AView) {}

    // MARK: - Z order

    /// The children sorted by Z then child order (ViewGroup.buildOrderedChildList; stable insertion sort).
    func buildOrderedChildList() -> [AView] {
        var list: [AView] = []
        list.reserveCapacity(mChildren.count)
        for (i, next) in mChildren.enumerated() {
            let currentZ = next.z
            // insert ahead of any Views with greater Z
            var insertIndex = i
            while insertIndex > 0 && list[insertIndex - 1].z > currentZ {
                insertIndex -= 1
            }
            list.insert(next, at: insertIndex)
        }
        return list
    }

    func childZChanged(_ child: AView) {
        sortChildViewsByZ()
        invalidate()
    }

    /// Keeps the UIKit subview order of the host equal to the Android drawing order.
    private func sortChildViewsByZ() {
        guard let host = mChildHost else { return }
        let ordered = buildOrderedChildList()
        var current = host.subviews.compactMap { $0 as? AView }
        if current.count == ordered.count && zip(current, ordered).allSatisfy({ $0 === $1 }) { return }
        for (i, v) in ordered.enumerated() {
            if i < current.count && current[i] === v { continue }
            host.insertSubview(v, at: i)
            current = host.subviews.compactMap { $0 as? AView }
        }
    }

    // MARK: - find

    override func findViewTraversal(_ id: String) -> AView? {
        if viewId == id { return self }
        for v in mChildren {
            if let found = v.findViewTraversal(id) {
                return found
            }
        }
        return nil
    }

    override func findViewWithTagTraversal(_ tag: AnyHashable) -> AView? {
        if let me = super.findViewWithTagTraversal(tag) { return me }
        for v in mChildren {
            if let found = v.findViewWithTagTraversal(tag) {
                return found
            }
        }
        return nil
    }

    // MARK: - attach / detach / visibility dispatch

    override func dispatchAttachedToWindow(_ info: AttachInfo, _ visibility: Int) {
        super.dispatchAttachedToWindow(info, visibility)
        let children = mChildren
        for child in children {
            child.dispatchAttachedToWindow(info, AViewGroup.combineVisibility(visibility, child.visibility))
        }
    }

    override func dispatchDetachedFromWindow() {
        // If we still have a touch target, we are still in the process of dispatching motion events to a child;
        // we need to get rid of that child to avoid dispatching events to it after the window is torn down. To
        // make sure we keep the child in a consistent state, we first send it an ACTION_CANCEL motion event.
        cancelAndClearTouchTargets(nil)
        let children = mChildren
        for child in children {
            child.dispatchDetachedFromWindow()
        }
        super.dispatchDetachedFromWindow()
    }

    static func combineVisibility(_ vis1: Int, _ vis2: Int) -> Int {
        // This works because VISIBLE < INVISIBLE < GONE.
        max(vis1, vis2)
    }

    override func dispatchWindowVisibilityChanged(_ visibility: Int) {
        super.dispatchWindowVisibilityChanged(visibility)
        let children = mChildren
        for child in children {
            child.dispatchWindowVisibilityChanged(visibility)
        }
    }

    override func dispatchVisibilityChanged(_ changedView: AView, _ visibility: Int) {
        super.dispatchVisibilityChanged(changedView, visibility)
        let children = mChildren
        for child in children {
            child.dispatchVisibilityChanged(changedView, visibility)
        }
    }

    override func dispatchVisibilityAggregated(_ isVisible: Bool) {
        let thisVisible = visibility == AView.VISIBLE
        super.dispatchVisibilityAggregated(isVisible)
        let children = mChildren
        for child in children {
            // Only dispatch to visible children. Not visible children and their subtrees already know that they
            // aren't visible and that's not going to change as a result of whatever triggered this dispatch.
            if child.visibility == AView.VISIBLE {
                child.dispatchVisibilityAggregated(isVisible && thisVisible)
            }
        }
    }

    override func dispatchSetPressed(_ pressed: Bool) {
        for child in mChildren {
            // Children that are clickable on their own should not show a pressed state when their parent view
            // does. Clearing a pressed state always propagates.
            if !pressed || (!child.isClickable && !child.isLongClickable) {
                child.setPressed(pressed)
            }
        }
    }

    override func dispatchSetSelected(_ selected: Bool) {
        for child in mChildren {
            child.setSelected(selected)
        }
    }

    override func dispatchSetActivated(_ activated: Bool) {
        for child in mChildren {
            child.setActivated(activated)
        }
    }

    override func rtlPropertiesChanged() {
        super.rtlPropertiesChanged()
        for child in mChildren where child.isLayoutDirectionInherited
            || child.rawTextDirection == AView.TEXT_DIRECTION_INHERIT
            || child.rawTextAlignment == AView.TEXT_ALIGNMENT_INHERIT {
            child.rtlPropertiesChanged()
        }
    }

    // MARK: - measure helpers

    /// ViewGroup.measureChildren: measures every child that is not GONE.
    func measureChildren(_ widthMeasureSpec: Int, _ heightMeasureSpec: Int) {
        for child in mChildren where child.visibility != AView.GONE {
            measureChild(child, widthMeasureSpec, heightMeasureSpec)
        }
    }

    /// ViewGroup.measureChild: the child's spec from the padding (margins ignored).
    func measureChild(_ child: AView, _ parentWidthMeasureSpec: Int, _ parentHeightMeasureSpec: Int) {
        let lp = child.mLayoutParams!
        let childWidthMeasureSpec = AViewGroup.getChildMeasureSpec(parentWidthMeasureSpec, mPaddingLeft + mPaddingRight, lp.width)
        let childHeightMeasureSpec = AViewGroup.getChildMeasureSpec(parentHeightMeasureSpec, mPaddingTop + mPaddingBottom, lp.height)
        child.measure(childWidthMeasureSpec, childHeightMeasureSpec)
    }

    /// ViewGroup.measureChildWithMargins.
    func measureChildWithMargins(_ child: AView, _ parentWidthMeasureSpec: Int, _ widthUsed: Int,
                                 _ parentHeightMeasureSpec: Int, _ heightUsed: Int) {
        let lp = child.mLayoutParams as! MarginLayoutParams
        let childWidthMeasureSpec = AViewGroup.getChildMeasureSpec(parentWidthMeasureSpec,
            mPaddingLeft + mPaddingRight + lp.leftMargin + lp.rightMargin + widthUsed, lp.width)
        let childHeightMeasureSpec = AViewGroup.getChildMeasureSpec(parentHeightMeasureSpec,
            mPaddingTop + mPaddingBottom + lp.topMargin + lp.bottomMargin + heightUsed, lp.height)
        child.measure(childWidthMeasureSpec, childHeightMeasureSpec)
    }

    /// ViewGroup.getChildMeasureSpec (AOSP, targetSdk >= M: UNSPECIFIED children get the size hint).
    static func getChildMeasureSpec(_ spec: Int, _ padding: Int, _ childDimension: Int) -> Int {
        let specMode = AMeasureSpec.getMode(spec)
        let specSize = AMeasureSpec.getSize(spec)

        let size = max(0, specSize - padding)

        var resultSize = 0
        var resultMode = 0

        switch specMode {
        // Parent has imposed an exact size on us
        case AMeasureSpec.EXACTLY:
            if childDimension >= 0 {
                resultSize = childDimension
                resultMode = AMeasureSpec.EXACTLY
            } else if childDimension == LayoutParams.MATCH_PARENT {
                // Child wants to be our size. So be it.
                resultSize = size
                resultMode = AMeasureSpec.EXACTLY
            } else if childDimension == LayoutParams.WRAP_CONTENT {
                // Child wants to determine its own size. It can't be bigger than us.
                resultSize = size
                resultMode = AMeasureSpec.AT_MOST
            }

        // Parent has imposed a maximum size on us
        case AMeasureSpec.AT_MOST:
            if childDimension >= 0 {
                // Child wants a specific size... so be it
                resultSize = childDimension
                resultMode = AMeasureSpec.EXACTLY
            } else if childDimension == LayoutParams.MATCH_PARENT {
                // Child wants to be our size, but our size is not fixed. Constrain child to not be bigger than us.
                resultSize = size
                resultMode = AMeasureSpec.AT_MOST
            } else if childDimension == LayoutParams.WRAP_CONTENT {
                // Child wants to determine its own size. It can't be bigger than us.
                resultSize = size
                resultMode = AMeasureSpec.AT_MOST
            }

        // Parent asked to see how big we want to be
        case AMeasureSpec.UNSPECIFIED:
            if childDimension >= 0 {
                // Child wants a specific size... let them have it
                resultSize = childDimension
                resultMode = AMeasureSpec.EXACTLY
            } else if childDimension == LayoutParams.MATCH_PARENT {
                // Child wants to be our size... find out how big it should be
                resultSize = size
                resultMode = AMeasureSpec.UNSPECIFIED
            } else if childDimension == LayoutParams.WRAP_CONTENT {
                // Child wants to determine its own size.... find out how big it should be
                resultSize = size
                resultMode = AMeasureSpec.UNSPECIFIED
            }

        default:
            break
        }
        return AMeasureSpec.makeMeasureSpec(resultSize, resultMode)
    }

    // MARK: - window insets

    /// ViewGroup.dispatchApplyWindowInsets (targetSdk >= R): the group's own result goes to every child unless
    /// it is consumed; the group returns its own result.
    @discardableResult
    override func dispatchApplyWindowInsets(_ insets: AWindowInsetsCompat) -> AWindowInsetsCompat {
        let result = super.dispatchApplyWindowInsets(insets)
        if result.isConsumed {
            return result
        }
        let children = mChildren
        for child in children {
            child.dispatchApplyWindowInsets(result)
        }
        return result
    }

    // MARK: - layout direction requests

    /// ViewGroup.requestChildRectangleOnScreen: false (ScrollViews override).
    func requestChildRectangleOnScreen(_ child: AView, _ rectangle: ARect, _ immediate: Bool) -> Bool {
        false
    }

    /// ViewGroup.requestChildFocus: `focused` (a descendant through `child`) gained the focus; passed up to the
    /// parents (ScrollViews override it to bring the focused view into view).
    func requestChildFocus(_ child: AView, _ focused: AView) {
        mParent?.requestChildFocus(self, focused)
    }

    /// ViewGroup.offsetDescendantRectToMyCoords: from the descendant's coordinates into this group's.
    func offsetDescendantRectToMyCoords(_ descendant: AView, _ rect: ARect) {
        offsetRectBetweenParentAndChild(descendant, rect, true, false)
    }

    /// ViewGroup.offsetRectIntoDescendantCoords: from this group's coordinates into the descendant's.
    func offsetRectIntoDescendantCoords(_ descendant: AView, _ rect: ARect) {
        offsetRectBetweenParentAndChild(descendant, rect, false, false)
    }

    /// ViewGroup.offsetRectBetweenParentAndChild.
    func offsetRectBetweenParentAndChild(_ descendantView: AView, _ rect: ARect, _ offsetFromChildToParent: Bool,
                                         _ clipToBounds: Bool) {
        // already in the same coord system :)
        if descendantView === self {
            return
        }
        var descendant: AView = descendantView
        var theParent: AViewGroup? = descendant.mParent
        // search and offset up to the parent
        while let p = theParent, p !== self {
            if offsetFromChildToParent {
                rect.offset(descendant.mLeft - descendant.mScrollX, descendant.mTop - descendant.mScrollY)
                if clipToBounds {
                    if !AView.intersect(rect, 0, 0, p.mRight - p.mLeft, p.mBottom - p.mTop) {
                        rect.left = 0
                        rect.top = 0
                        rect.right = 0
                        rect.bottom = 0
                    }
                }
            } else {
                if clipToBounds {
                    if !AView.intersect(rect, 0, 0, p.mRight - p.mLeft, p.mBottom - p.mTop) {
                        rect.left = 0
                        rect.top = 0
                        rect.right = 0
                        rect.bottom = 0
                    }
                }
                rect.offset(descendant.mScrollX - descendant.mLeft, descendant.mScrollY - descendant.mTop)
            }
            descendant = p
            theParent = descendant.mParent
        }
        // now that we are up to this view, need to offset one more time to get into our coordinate space
        precondition(theParent === self, "parameter must be a descendant of this view")
        if offsetFromChildToParent {
            rect.offset(descendant.mLeft - descendant.mScrollX, descendant.mTop - descendant.mScrollY)
        } else {
            rect.offset(descendant.mScrollX - descendant.mLeft, descendant.mScrollY - descendant.mTop)
        }
    }

    /// ViewGroup.shouldDelayChildPressedState: true by default (FrameLayout, LinearLayout and ConstraintLayout
    /// return false; ScrollViews true).
    func shouldDelayChildPressedState() -> Bool { true }

    /// ViewGroup.getChildVisibleRect(child, r, null, false).
    func getChildVisibleRect(_ child: AView, _ r: ARect) -> Bool {
        var rl = Float(r.left), rt = Float(r.top), rr = Float(r.right), rb = Float(r.bottom)
        if !child.hasIdentityMatrix {
            let mapped = CGRect(x: CGFloat(rl), y: CGFloat(rt), width: CGFloat(rr - rl), height: CGFloat(rb - rt))
                .applying(child.matrixTransform)
            rl = Float(mapped.minX); rt = Float(mapped.minY); rr = Float(mapped.maxX); rb = Float(mapped.maxY)
        }
        let dx = Float(child.mLeft - mScrollX)
        let dy = Float(child.mTop - mScrollY)
        rl += dx; rr += dx; rt += dy; rb += dy

        let width = Float(mRight - mLeft)
        let height = Float(mBottom - mTop)

        func intersect(_ l: Float, _ t: Float, _ r2: Float, _ b: Float) -> Bool {
            if rl < r2 && l < rr && rt < b && t < rb {
                if rl < l { rl = l }
                if rt < t { rt = t }
                if rr > r2 { rr = r2 }
                if rb > b { rb = b }
                return true
            }
            return false
        }

        var rectIsVisible = true
        if mParent == nil || (mParent?.clipChildren ?? true) {
            // Clip to bounds.
            rectIsVisible = intersect(0, 0, width, height)
        }
        if rectIsVisible && mClipToPadding && (mPaddingLeft | mPaddingTop | mPaddingRight | mPaddingBottom) != 0 {
            // Clip to padding.
            rectIsVisible = intersect(Float(mPaddingLeft), Float(mPaddingTop), width - Float(mPaddingRight),
                                      height - Float(mPaddingBottom))
        }
        r.left = Int(rl.rounded(.down))
        r.top = Int(rt.rounded(.down))
        r.right = Int(rr.rounded(.up))
        r.bottom = Int(rb.rounded(.up))

        if rectIsVisible {
            if let p = mParent {
                rectIsVisible = p.getChildVisibleRect(self, r)
            } else if let root = mViewRootParent {
                rectIsVisible = AView.intersect(r, 0, 0, root.widthPx, root.heightPx)
            }
        }
        return rectIsVisible
    }

    // MARK: - drawing

    /// ViewGroup.dispatchDraw: in the composited path the children are UIKit layers (nothing to draw); during
    /// an app-initiated View.draw(Canvas) the children are drawn into the canvas in Z order.
    override func dispatchDraw(_ canvas: ACanvas) {
        guard AView.sOffscreenDrawDepth > 0 else { return }
        let ordered = buildOrderedChildList()
        let saveCount = canvas.save()
        if mClipToPadding && (mPaddingLeft | mPaddingTop | mPaddingRight | mPaddingBottom) != 0 {
            canvas.clipRect(Float(mScrollX + mPaddingLeft), Float(mScrollY + mPaddingTop),
                            Float(mScrollX + width - mPaddingRight), Float(mScrollY + height - mPaddingBottom))
        }
        for child in ordered where child.visibility == AView.VISIBLE {
            let s = canvas.save()
            canvas.translate(Float(child.mLeft - mScrollX), Float(child.mTop - mScrollY))
            if !child.hasIdentityMatrix {
                canvas.translate(child.translationX, child.translationY)
                canvas.translate(child.pivotX, child.pivotY)
                canvas.rotate(child.rotation)
                canvas.scale(child.scaleX, child.scaleY)
                canvas.translate(-child.pivotX, -child.pivotY)
            }
            if mClipChildren {
                canvas.clipRect(0, 0, Float(child.width), Float(child.height))
            }
            child.draw(canvas)
            canvas.restoreToCount(s)
        }
        canvas.restoreToCount(saveCount)
    }

    // MARK: - UIKit hit testing

    override func hitTestDescendants(_ point: CGPoint, _ event: UIEvent?) -> UIView? {
        for sub in subviews.reversed() {
            if sub === mChildHost {
                for childView in mChildHost.subviews.reversed() {
                    if let hit = AView.hitTestSubview(childView, self, point, event) { return hit }
                }
                if let hostHit = hitTestChildHostItself(point, event) { return hostHit }
                continue
            }
            if let hit = AView.hitTestSubview(sub, self, point, event) { return hit }
        }
        return nil
    }

    /// Override point: scroll views return their UIScrollView host when no child takes the touch, so the
    /// native pan recognizer sees it.
    func hitTestChildHostItself(_ point: CGPoint, _ event: UIEvent?) -> UIView? { nil }

    // MARK: - touch dispatch (ViewGroup)

    /// ViewGroup.TouchTarget.
    final class TouchTarget {
        static let ALL_POINTER_IDS = -1 // all ones
        let child: AView
        var pointerIdBits: Int
        var next: TouchTarget?
        init(_ child: AView, _ pointerIdBits: Int) {
            self.child = child
            self.pointerIdBits = pointerIdBits
        }
    }

    /// ViewGroup.setMotionEventSplittingEnabled / isMotionEventSplittingEnabled.
    var isMotionEventSplittingEnabled: Bool {
        get { mSplitMotionEvents }
        set { mSplitMotionEvents = newValue }
    }
    func setMotionEventSplittingEnabled(_ split: Bool) { mSplitMotionEvents = split }

    /// Override point (ViewGroup.onInterceptTouchEvent): return true to take the gesture from the children.
    func onInterceptTouchEvent(_ ev: AMotionEvent) -> Bool {
        false
    }

    /// ViewGroup.requestDisallowInterceptTouchEvent: propagates to the ancestors.
    func requestDisallowInterceptTouchEvent(_ disallowIntercept: Bool) {
        if disallowIntercept == mDisallowIntercept {
            // We're already in this state, assume our ancestors are too
            return
        }
        mDisallowIntercept = disallowIntercept
        // Pass it up to our parent
        mParent?.requestDisallowInterceptTouchEvent(disallowIntercept)
    }

    /// The Android dispatch over this group. Hit-test-free: every decision is made here with Android rules.
    override func dispatchTouchEvent(_ ev: AMotionEvent) -> Bool {
        var handled = false
        let action = ev.action
        let actionMasked = action & AMotionEvent.ACTION_MASK

        // Handle an initial down.
        if actionMasked == AMotionEvent.ACTION_DOWN {
            // Throw away all previous state when starting a new touch gesture. The framework may have dropped the
            // up or cancel event for the previous gesture due to an app switch, ANR, or some other state change.
            cancelAndClearTouchTargets(ev)
            resetTouchState()
        }

        // Check for interception.
        let intercepted: Bool
        if actionMasked == AMotionEvent.ACTION_DOWN || mFirstTouchTarget != nil {
            let disallowIntercept = mDisallowIntercept
            if !disallowIntercept {
                intercepted = onInterceptTouchEvent(ev)
                ev.setAction(action) // restore action in case it was changed
            } else {
                intercepted = false
            }
        } else {
            // There are no touch targets and this action is not an initial down so this view group continues to
            // intercept touches.
            intercepted = true
        }

        // Check for cancelation.
        let canceled = actionMasked == AMotionEvent.ACTION_CANCEL

        // Update list of touch targets for pointer down, if needed.
        let split = mSplitMotionEvents
        var newTouchTarget: TouchTarget? = nil
        var alreadyDispatchedToNewTouchTarget = false
        if !canceled && !intercepted {
            if actionMasked == AMotionEvent.ACTION_DOWN
                || (split && actionMasked == AMotionEvent.ACTION_POINTER_DOWN)
                || actionMasked == AMotionEvent.ACTION_HOVER_MOVE {
                let actionIndex = ev.actionIndex // always 0 for down
                let idBitsToAssign = split ? 1 << ev.getPointerId(actionIndex) : TouchTarget.ALL_POINTER_IDS

                // Clean up earlier touch targets for this pointer id in case they have become out of sync.
                removePointersFromTouchTargets(idBitsToAssign)

                let childrenCount = mChildren.count
                if newTouchTarget == nil && childrenCount != 0 {
                    let x = ev.getX(actionIndex)
                    let y = ev.getY(actionIndex)
                    // Find a child that can receive the event. Scan children from front to back.
                    let preorderedList = buildOrderedChildList()
                    var i = childrenCount - 1
                    while i >= 0 {
                        let child = preorderedList[i]
                        i -= 1
                        if !child.canReceivePointerEvents() || !isTransformedTouchPointInView(x, y, child) {
                            continue
                        }

                        newTouchTarget = getTouchTarget(child)
                        if let target = newTouchTarget {
                            // Child is already receiving touch within its bounds. Give it the new pointer in
                            // addition to the ones it is handling.
                            target.pointerIdBits |= idBitsToAssign
                            break
                        }

                        if dispatchTransformedTouchEvent(ev, false, child, idBitsToAssign) {
                            // Child wants to receive touch within its bounds.
                            mLastTouchDownTime = ev.downTime
                            mLastTouchDownIndex = indexOfChild(child)
                            mLastTouchDownX = ev.x
                            mLastTouchDownY = ev.y
                            newTouchTarget = addTouchTarget(child, idBitsToAssign)
                            alreadyDispatchedToNewTouchTarget = true
                            break
                        }
                    }
                }

                if newTouchTarget == nil, var target = mFirstTouchTarget {
                    // Did not find a child to receive the event. Assign the pointer to the least recently added
                    // target.
                    while let next = target.next {
                        target = next
                    }
                    target.pointerIdBits |= idBitsToAssign
                    newTouchTarget = target
                }
            }
        }

        // Dispatch to touch targets.
        if mFirstTouchTarget == nil {
            // No touch targets so treat this as an ordinary view.
            handled = dispatchTransformedTouchEvent(ev, canceled, nil, TouchTarget.ALL_POINTER_IDS)
        } else {
            // Dispatch to touch targets, excluding the new touch target if we already dispatched to it. Cancel
            // touch targets if necessary.
            var predecessor: TouchTarget? = nil
            var target = mFirstTouchTarget
            while let t = target {
                let next = t.next
                if alreadyDispatchedToNewTouchTarget && t === newTouchTarget {
                    handled = true
                } else {
                    let cancelChild = intercepted
                    if dispatchTransformedTouchEvent(ev, cancelChild, t.child, t.pointerIdBits) {
                        handled = true
                    }
                    if cancelChild {
                        if predecessor == nil {
                            mFirstTouchTarget = next
                        } else {
                            predecessor!.next = next
                        }
                        target = next
                        continue
                    }
                }
                predecessor = t
                target = next
            }
        }

        // Update list of touch targets for pointer up or cancel, if needed.
        if canceled || actionMasked == AMotionEvent.ACTION_UP || actionMasked == AMotionEvent.ACTION_HOVER_MOVE {
            resetTouchState()
        } else if split && actionMasked == AMotionEvent.ACTION_POINTER_UP {
            let actionIndex = ev.actionIndex
            let idBitsToRemove = 1 << ev.getPointerId(actionIndex)
            removePointersFromTouchTargets(idBitsToRemove)
        }

        return handled
    }

    private func resetTouchState() {
        clearTouchTargets()
        mDisallowIntercept = false
        touchStateDidReset()
    }

    /// Hook: the gesture state was reset (a new DOWN, or the gesture ended or was cancelled). The UIScrollView-backed
    /// scroll views re-enable their pan recognizer here after a child disallowed intercepts.
    func touchStateDidReset() {}

    private func clearTouchTargets() {
        mFirstTouchTarget = nil
    }

    private func cancelAndClearTouchTargets(_ event: AMotionEvent?) {
        if mFirstTouchTarget != nil {
            var ev = event
            if ev == nil {
                let now = ASystemClock.uptimeMillis()
                ev = AMotionEvent.obtain(now, now, AMotionEvent.ACTION_CANCEL, 0, 0, 0)
            }
            var target = mFirstTouchTarget
            while let t = target {
                _ = dispatchTransformedTouchEvent(ev!, true, t.child, t.pointerIdBits)
                target = t.next
            }
            clearTouchTargets()
        }
    }

    private func getTouchTarget(_ child: AView) -> TouchTarget? {
        var target = mFirstTouchTarget
        while let t = target {
            if t.child === child {
                return t
            }
            target = t.next
        }
        return nil
    }

    private func addTouchTarget(_ child: AView, _ pointerIdBits: Int) -> TouchTarget {
        let target = TouchTarget(child, pointerIdBits)
        target.next = mFirstTouchTarget
        mFirstTouchTarget = target
        return target
    }

    private func removePointersFromTouchTargets(_ pointerIdBits: Int) {
        var predecessor: TouchTarget? = nil
        var target = mFirstTouchTarget
        while let t = target {
            let next = t.next
            if (t.pointerIdBits & pointerIdBits) != 0 {
                t.pointerIdBits &= ~pointerIdBits
                if t.pointerIdBits == 0 {
                    if predecessor == nil {
                        mFirstTouchTarget = next
                    } else {
                        predecessor!.next = next
                    }
                    target = next
                    continue
                }
            }
            predecessor = t
            target = next
        }
    }

    /// Removes the child's touch target and sends it ACTION_CANCEL (ViewGroup.cancelTouchTarget).
    private func cancelTouchTarget(_ view: AView) {
        var predecessor: TouchTarget? = nil
        var target = mFirstTouchTarget
        while let t = target {
            let next = t.next
            if t.child === view {
                if predecessor == nil {
                    mFirstTouchTarget = next
                } else {
                    predecessor!.next = next
                }
                let now = ASystemClock.uptimeMillis()
                let event = AMotionEvent.obtain(now, now, AMotionEvent.ACTION_CANCEL, 0, 0, 0)
                _ = view.dispatchTouchEvent(event)
                return
            }
            predecessor = t
            target = next
        }
    }

    /// ViewGroup.isTransformedTouchPointInView.
    func isTransformedTouchPointInView(_ x: Float, _ y: Float, _ child: AView) -> Bool {
        var px = x + Float(mScrollX - child.mLeft)
        var py = y + Float(mScrollY - child.mTop)
        if !child.hasIdentityMatrix {
            (px, py) = AView.mapPoint(child.inverseMatrixTransform, px, py)
        }
        return child.pointInView(px, py)
    }

    /// ViewGroup.dispatchTransformedTouchEvent: offsets (and splits) the event into the child's coordinates.
    private func dispatchTransformedTouchEvent(_ event: AMotionEvent, _ cancel: Bool, _ child: AView?,
                                               _ desiredPointerIdBits: Int) -> Bool {
        var handled: Bool

        // Canceling motions is a special case. We don't need to perform any transformations or filtering. The
        // important part is the action, not the contents.
        let oldAction = event.action
        if cancel || oldAction == AMotionEvent.ACTION_CANCEL {
            event.setAction(AMotionEvent.ACTION_CANCEL)
            if let c = child {
                handled = c.dispatchTouchEvent(event)
            } else {
                handled = super.dispatchTouchEvent(event)
            }
            event.setAction(oldAction)
            return handled
        }

        // Calculate the number of pointers to deliver.
        let oldPointerIdBits = event.pointerIdBits
        let newPointerIdBits = oldPointerIdBits & desiredPointerIdBits

        // If for some reason we ended up in an inconsistent state where it looks like we might produce a motion
        // event with no pointers in it, then drop the event.
        if newPointerIdBits == 0 {
            return false
        }

        // If the number of pointers is the same and we don't need to perform any fancy irreversible
        // transformations, then we can reuse the motion event for this dispatch as long as we are careful to
        // revert any changes we make. Otherwise we need to make a copy.
        let transformedEvent: AMotionEvent
        if newPointerIdBits == oldPointerIdBits {
            if child == nil || child!.hasIdentityMatrix {
                if let c = child {
                    let offsetX = Float(mScrollX - c.mLeft)
                    let offsetY = Float(mScrollY - c.mTop)
                    event.offsetLocation(offsetX, offsetY)
                    handled = c.dispatchTouchEvent(event)
                    event.offsetLocation(-offsetX, -offsetY)
                } else {
                    handled = super.dispatchTouchEvent(event)
                }
                return handled
            }
            transformedEvent = AMotionEvent.obtain(event)
        } else {
            transformedEvent = event.split(newPointerIdBits)
        }

        // Perform any necessary transformations and dispatch.
        if let c = child {
            let offsetX = Float(mScrollX - c.mLeft)
            let offsetY = Float(mScrollY - c.mTop)
            transformedEvent.offsetLocation(offsetX, offsetY)
            if !c.hasIdentityMatrix {
                transformedEvent.transform(c.inverseMatrixTransform)
            }
            handled = c.dispatchTouchEvent(transformedEvent)
        } else {
            handled = super.dispatchTouchEvent(transformedEvent)
        }

        // Done.
        transformedEvent.recycle()
        return handled
    }
}

extension AView {
    /// View.canReceivePointerEvents: VISIBLE (legacy view animations are not used by the app).
    func canReceivePointerEvents() -> Bool {
        visibility == AView.VISIBLE
    }
}
