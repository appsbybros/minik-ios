import UIKit

// AndroidKit widgets (area kit-widgets): android.widget.AdapterView / AbsSpinner / Spinner with BaseAdapter /
// ArrayAdapter and the framework item layouts simple_spinner_item / simple_spinner_dropdown_item; a vertical
// androidx RecyclerView (Adapter / ViewHolder / LinearLayoutManager) for the leaderboard list; and the Material
// TabLayout (Widget.MaterialComponents.TabLayout, fixed mode, fill gravity).
//
// Spinner follows the Android 15 framework (AdapterView, AbsSpinner, Spinner): measuring with the selected item's view,
// the selected view laid out as the only child (gravity start|center_vertical), setSelection / setSelectionInt and the
// layout pass that reports onItemSelected (posted while in layout, as Android: no callback for a selection made before
// the listener was set). The dropdown is an iOS menu (UIButton with showsMenuAsPrimaryAction over the spinner, items
// in adapter order); picking an item calls setSelection(position) like the DropdownPopup.
//
// RecyclerView-lite: a vertical scrolling list (the ScrollView port) whose content is a vertical LinearLayout of every
// item view; adapter.notifyDataSetChanged() rebinds all positions, reusing the view holders of the same view type
// (the scroll position is kept). TabLayout follows material 1.12.0 (TabLayout, TabView, SlidingTabIndicator,
// TabIndicatorInterpolator): 48 dp tall, colorSurface background, equal tabs with 12 dp side padding, 14 sp medium
// all-caps labels (12 sp when wrapping to two lines), a 2 dp full-width indicator sliding in 250 ms (FastOutSlowIn).

// MARK: - Adapter (android.widget.Adapter / BaseAdapter)

/// android.database.DataSetObserver.
class ADataSetObserver {
    private let changed: (() -> Void)?
    private let invalidated: (() -> Void)?

    init(onChanged: (() -> Void)? = nil, onInvalidated: (() -> Void)? = nil) {
        changed = onChanged
        invalidated = onInvalidated
    }

    func onChanged() { changed?() }
    func onInvalidated() { invalidated?() }
}

/// android.widget.BaseAdapter (Adapter / ListAdapter / SpinnerAdapter). Subclasses override getCount, getItem,
/// getItemId and getView.
class ABaseAdapter {
    static let IGNORE_ITEM_VIEW_TYPE = -1
    static let NO_SELECTION = Int(Int32.min)

    private var aw_observers: [ADataSetObserver] = []

    init() {}

    func getCount() -> Int { return 0 }
    var count: Int { return getCount() }
    func getItem(_ position: Int) -> Any? { return nil }
    func getItemId(_ position: Int) -> Int64 { return Int64(position) }
    func hasStableIds() -> Bool { return false }

    /// The view of an item (the selected view of a Spinner).
    func getView(_ position: Int, _ convertView: AView?, _ parent: AViewGroup) -> AView {
        preconditionFailure("BaseAdapter.getView is abstract")
    }

    /// The view of an item in the dropdown (BaseAdapter: getView).
    func getDropDownView(_ position: Int, _ convertView: AView?, _ parent: AViewGroup) -> AView {
        return getView(position, convertView, parent)
    }

    func getItemViewType(_ position: Int) -> Int { return 0 }
    func getViewTypeCount() -> Int { return 1 }
    func isEmpty() -> Bool { return getCount() == 0 }
    var isEmptyAdapter: Bool { return isEmpty() }
    func areAllItemsEnabled() -> Bool { return true }
    func isEnabled(_ position: Int) -> Bool { return true }

    func registerDataSetObserver(_ observer: ADataSetObserver) {
        if !aw_observers.contains(where: { $0 === observer }) { aw_observers.append(observer) }
    }

    func unregisterDataSetObserver(_ observer: ADataSetObserver) {
        aw_observers.removeAll { $0 === observer }
    }

    /// DataSetObservable.notifyChanged: observers in reverse registration order.
    func notifyDataSetChanged() {
        for o in aw_observers.reversed() { o.onChanged() }
    }

    func notifyDataSetInvalidated() {
        for o in aw_observers.reversed() { o.onInvalidated() }
    }

    /// The text an item view shows (Object.toString of the item; a String is its own text).
    static func aw_itemText(_ item: Any?) -> String {
        guard let item = item else { return "null" }
        if let s = item as? String { return s }
        if let c = item as? ACharSequence { return c.aw_plain }
        if let d = item as? CustomStringConvertible { return d.description }
        return String(describing: item)
    }
}

/// android.widget.ArrayAdapter<T>: the item's text in the TextView of `resource` (a framework item layout, or any
/// resource the app registers with `AArrayAdapter.registerLayout`).
class AArrayAdapter<T>: ABaseAdapter {
    private var mObjects: [T]
    private var mResource: String
    private var mDropDownResource: String
    private let mFieldId: String?
    private var mNotifyOnChange = true
    weak var aw_context: AContext?

    init(_ context: AContext, _ resource: String) {
        aw_context = context
        mResource = resource
        mDropDownResource = resource
        mFieldId = nil
        mObjects = []
        super.init()
    }

    init(_ context: AContext, _ resource: String, _ objects: [T]) {
        aw_context = context
        mResource = resource
        mDropDownResource = resource
        mFieldId = nil
        mObjects = objects
        super.init()
    }

    init(_ context: AContext, _ resource: String, _ textViewResourceId: String, _ objects: [T]) {
        aw_context = context
        mResource = resource
        mDropDownResource = resource
        mFieldId = textViewResourceId
        mObjects = objects
        super.init()
    }

    // MARK: Data

    func add(_ object: T) {
        mObjects.append(object)
        if mNotifyOnChange { notifyDataSetChanged() }
    }

    func addAll(_ collection: [T]) {
        mObjects.append(contentsOf: collection)
        if mNotifyOnChange { notifyDataSetChanged() }
    }

    func insert(_ object: T, _ index: Int) {
        mObjects.insert(object, at: index)
        if mNotifyOnChange { notifyDataSetChanged() }
    }

    func clear() {
        mObjects.removeAll()
        if mNotifyOnChange { notifyDataSetChanged() }
    }

    func setNotifyOnChange(_ notifyOnChange: Bool) { mNotifyOnChange = notifyOnChange }

    /// ArrayAdapter.notifyDataSetChanged: notifyOnChange is turned back on.
    override func notifyDataSetChanged() {
        super.notifyDataSetChanged()
        mNotifyOnChange = true
    }

    override func getCount() -> Int { return mObjects.count }

    override func getItem(_ position: Int) -> Any? { return mObjects[position] }

    /// The typed item (Kotlin `adapter.getItem(position)`).
    func item(_ position: Int) -> T { return mObjects[position] }

    override func getItemId(_ position: Int) -> Int64 { return Int64(position) }

    // MARK: Views

    override func getView(_ position: Int, _ convertView: AView?, _ parent: AViewGroup) -> AView {
        return aw_createViewFromResource(position, convertView, parent, mResource)
    }

    /// ArrayAdapter.setDropDownViewResource.
    func setDropDownViewResource(_ resource: String) {
        mDropDownResource = resource
    }

    override func getDropDownView(_ position: Int, _ convertView: AView?, _ parent: AViewGroup) -> AView {
        return aw_createViewFromResource(position, convertView, parent, mDropDownResource)
    }

    private func aw_createViewFromResource(_ position: Int, _ convertView: AView?, _ parent: AViewGroup, _ resource: String) -> AView {
        let view = convertView ?? AArrayAdapterLayouts.inflate(resource)
        let text: ATextView
        if let field = mFieldId {
            guard let t: ATextView = view.findViewById(field) else {
                preconditionFailure("java.lang.IllegalStateException: Failed to find view with ID \(field) in item layout")
            }
            text = t
        } else {
            guard let t = view as? ATextView else {
                preconditionFailure("java.lang.IllegalStateException: ArrayAdapter requires the resource ID to be a TextView")
            }
            text = t
        }
        text.setText(ABaseAdapter.aw_itemText(getItem(position)))
        return view
    }
}

/// The item layouts ArrayAdapter inflates (framework layouts by their android.R.layout names).
enum AArrayAdapterLayouts {
    nonisolated(unsafe) private static var registered: [String: () -> AView] = [:]

    /// Registers an app layout for ArrayAdapter (the builder must return a TextView or a tree holding the field).
    static func registerLayout(_ name: String, _ builder: @escaping () -> AView) {
        registered[name] = builder
    }

    static func inflate(_ name: String) -> AView {
        if let b = registered[name] { return b() }
        switch name {
        case "android:simple_spinner_dropdown_item":
            return simpleSpinnerDropdownItem()
        case "android:simple_list_item_1":
            return simpleListItem1()
        default:
            return simpleSpinnerItem()
        }
    }

    /// simple_spinner_item: a single-line TextView (?android:spinnerItemStyle = Widget.AppCompat.TextView.SpinnerItem:
    /// TextAppearance.Material.Widget.TextView.SpinnerItem 16 sp ?textColorPrimary, padding start / end 8 dp),
    /// match_parent x wrap_content, ellipsize marquee, textAlignment inherit.
    static func simpleSpinnerItem() -> ATextView {
        let t = ATextView()
        t.viewId = "text1"
        t.applyXmlTextSize(16)
        t.setTextColor(AWMaterialColors.textColorPrimary)
        t.setPaddingRelative(aw_dpx(8), 0, aw_dpx(8), 0)
        t.applyXmlSingleLine(true, hasXmlEllipsize: true)
        t.setEllipsize(.MARQUEE)
        t.textAlignment = AView.TEXT_ALIGNMENT_INHERIT
        t.layoutParams = AViewGroup.LayoutParams(AViewGroup.LayoutParams.MATCH_PARENT, AViewGroup.LayoutParams.WRAP_CONTENT)
        return t
    }

    /// simple_spinner_dropdown_item: a CheckedTextView (?android:spinnerDropDownItemStyle =
    /// Widget.Material.Light.DropDownItem.Spinner: 16 sp ?textColorPrimaryDisableOnly, padding start / end 8 dp,
    /// gravity center_vertical), match_parent x ?dropdownListPreferredItemHeight (48 dp), single line, marquee.
    static func simpleSpinnerDropdownItem() -> ATextView {
        let t = ATextView()
        t.viewId = "text1"
        t.applyXmlTextSize(16)
        t.setTextColor(AWMaterialColors.textColorPrimaryDisableOnly)
        t.setPaddingRelative(aw_dpx(8), 0, aw_dpx(8), 0)
        t.setGravity(AGravity.CENTER_VERTICAL)
        t.applyXmlSingleLine(true, hasXmlEllipsize: true)
        t.setEllipsize(.MARQUEE)
        t.layoutParams = AViewGroup.LayoutParams(AViewGroup.LayoutParams.MATCH_PARENT, aw_dpx(48))
        return t
    }

    /// simple_list_item_1: ?android:textAppearanceListItemSmall (16 sp), min height 48 dp, padding 16 dp, centre
    /// vertical.
    static func simpleListItem1() -> ATextView {
        let t = ATextView()
        t.viewId = "text1"
        t.applyXmlTextSize(16)
        t.setTextColor(AWMaterialColors.textColorPrimary)
        t.setGravity(AGravity.CENTER_VERTICAL)
        t.setPaddingRelative(aw_dpx(16), 0, aw_dpx(16), 0)
        t.setMinHeight(aw_dpx(48))
        t.layoutParams = AViewGroup.LayoutParams(AViewGroup.LayoutParams.MATCH_PARENT, AViewGroup.LayoutParams.WRAP_CONTENT)
        return t
    }
}

// MARK: - AdapterView

/// AdapterView.OnItemSelectedListener.
protocol AOnItemSelectedListener: AnyObject {
    func onItemSelected(_ parent: AAdapterView?, _ view: AView?, _ position: Int, _ id: Int64)
    func onNothingSelected(_ parent: AAdapterView?)
}

/// AdapterView.OnItemClickListener.
protocol AOnItemClickListener: AnyObject {
    func onItemClick(_ parent: AAdapterView?, _ view: AView?, _ position: Int, _ id: Int64)
}

/// A closure OnItemSelectedListener (Kotlin `object : OnItemSelectedListener { ... }` with lambdas).
final class ASimpleOnItemSelectedListener: AOnItemSelectedListener {
    private let selected: (AAdapterView?, AView?, Int, Int64) -> Void
    private let nothing: (AAdapterView?) -> Void

    init(onItemSelected: @escaping (AAdapterView?, AView?, Int, Int64) -> Void,
         onNothingSelected: @escaping (AAdapterView?) -> Void = { _ in }) {
        selected = onItemSelected
        nothing = onNothingSelected
    }

    func onItemSelected(_ parent: AAdapterView?, _ view: AView?, _ position: Int, _ id: Int64) {
        selected(parent, view, position, id)
    }

    func onNothingSelected(_ parent: AAdapterView?) { nothing(parent) }
}

/// android.widget.AdapterView (the parts AbsSpinner / Spinner use).
class AAdapterView: AViewGroup {
    typealias OnItemSelectedListener = AOnItemSelectedListener
    typealias OnItemClickListener = AOnItemClickListener

    static let INVALID_POSITION = -1
    static let INVALID_ROW_ID = Int64.min
    static let ITEM_VIEW_TYPE_IGNORE = -1

    var mFirstPosition = 0
    var mLayoutHeight = 0
    var mInLayout = false
    var mOnItemSelectedListener: AOnItemSelectedListener?
    var mOnItemClickListener: AOnItemClickListener?
    var mDataChanged = false
    var mNextSelectedPosition = AAdapterView.INVALID_POSITION
    var mNextSelectedRowId = AAdapterView.INVALID_ROW_ID
    var mSelectedPosition = AAdapterView.INVALID_POSITION
    var mSelectedRowId = AAdapterView.INVALID_ROW_ID
    var mItemCount = 0
    var mOldItemCount = 0
    var mOldSelectedPosition = AAdapterView.INVALID_POSITION
    var mOldSelectedRowId = AAdapterView.INVALID_ROW_ID
    var mBlockLayoutRequests = false
    var mNeedSync = false
    private var mSelectionNotifier: ARunnable?
    private var mPendingSelectionNotifier: ARunnable?

    override init() {
        super.init()
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    /// The adapter (Spinner: its SpinnerAdapter).
    func getAdapterBase() -> ABaseAdapter? { return nil }

    // MARK: Listeners

    var onItemSelectedListener: AOnItemSelectedListener? {
        get { return mOnItemSelectedListener }
        set { setOnItemSelectedListener(newValue) }
    }

    func setOnItemSelectedListener(_ listener: AOnItemSelectedListener?) {
        mOnItemSelectedListener = listener
    }

    func getOnItemSelectedListener() -> AOnItemSelectedListener? { return mOnItemSelectedListener }

    var onItemClickListener: AOnItemClickListener? {
        get { return mOnItemClickListener }
        set { setOnItemClickListener(newValue) }
    }

    func setOnItemClickListener(_ listener: AOnItemClickListener?) {
        mOnItemClickListener = listener
    }

    /// AdapterView.setOnClickListener: not allowed.
    override func setOnClickListener(_ l: ((AView) -> Void)?) {
        preconditionFailure("java.lang.RuntimeException: Don't call setOnClickListener for an AdapterView. You probably want setOnItemClickListener instead")
    }

    /// AdapterView.addView: not supported (children are managed by the AdapterView).
    override func addView(_ child: AView, _ index: Int, _ params: AViewGroup.LayoutParams) {
        preconditionFailure("java.lang.UnsupportedOperationException: addView(View, int, LayoutParams) is not supported in AdapterView")
    }

    /// AdapterView.performItemClick.
    @discardableResult
    func performItemClick(_ view: AView?, _ position: Int, _ id: Int64) -> Bool {
        if let l = mOnItemClickListener {
            l.onItemClick(self, view, position, id)
            return true
        }
        return false
    }

    // MARK: Selection

    var selectedItemPosition: Int { return getSelectedItemPosition() }
    func getSelectedItemPosition() -> Int { return mNextSelectedPosition }

    var selectedItemId: Int64 { return getSelectedItemId() }
    func getSelectedItemId() -> Int64 { return mNextSelectedRowId }

    /// The selected view (AbsSpinner.getSelectedView).
    func getSelectedView() -> AView? { return nil }
    var selectedView: AView? { return getSelectedView() }

    var selectedItem: Any? { return getSelectedItem() }

    func getSelectedItem() -> Any? {
        guard let adapter = getAdapterBase() else { return nil }
        let selection = getSelectedItemPosition()
        if adapter.getCount() > 0 && selection >= 0 {
            return adapter.getItem(selection)
        }
        return nil
    }

    func getCount() -> Int { return mItemCount }

    func getItemAtPosition(_ position: Int) -> Any? {
        guard let adapter = getAdapterBase(), position >= 0 else { return nil }
        return adapter.getItem(position)
    }

    func getItemIdAtPosition(_ position: Int) -> Int64 {
        guard let adapter = getAdapterBase(), position >= 0 else { return AAdapterView.INVALID_ROW_ID }
        return adapter.getItemId(position)
    }

    var firstVisiblePosition: Int { return mFirstPosition }
    var lastVisiblePosition: Int { return mFirstPosition + childCount - 1 }

    func setNextSelectedPositionInt(_ position: Int) {
        mNextSelectedPosition = position
        mNextSelectedRowId = getItemIdAtPosition(position)
    }

    func setSelectedPositionInt(_ position: Int) {
        mSelectedPosition = position
        mSelectedRowId = getItemIdAtPosition(position)
    }

    func checkSelectionChanged() {
        if mSelectedPosition != mOldSelectedPosition || mSelectedRowId != mOldSelectedRowId {
            selectionChanged()
            mOldSelectedPosition = mSelectedPosition
            mOldSelectedRowId = mSelectedRowId
        }
        // If we have a pending selection notification -- and we won't if we just fired one in selectionChanged() --
        // run it now.
        if let p = mPendingSelectionNotifier {
            p.run()
        }
    }

    /// AdapterView.selectionChanged: posted while in layout (or with layout requests blocked), else immediate. An
    /// accessibility service also makes it run without a listener (AccessibilityManager.isEnabled).
    func selectionChanged() {
        mPendingSelectionNotifier = nil
        if mOnItemSelectedListener != nil || UIAccessibility.isVoiceOverRunning || UIAccessibility.isSwitchControlRunning {
            if mInLayout || mBlockLayoutRequests {
                if let n = mSelectionNotifier {
                    _ = removeCallbacks(n)
                } else {
                    mSelectionNotifier = ARunnable { [weak self] in self?.aw_runSelectionNotifier() }
                }
                _ = post(mSelectionNotifier!)
            } else {
                dispatchOnItemSelected()
            }
        }
    }

    /// AdapterView.SelectionNotifier.run.
    private func aw_runSelectionNotifier() {
        mPendingSelectionNotifier = nil
        if mDataChanged && isLayoutRequested {
            if getAdapterBase() != nil {
                mPendingSelectionNotifier = mSelectionNotifier
            }
        } else {
            dispatchOnItemSelected()
        }
    }

    private func dispatchOnItemSelected() {
        fireOnSelected()
    }

    private func fireOnSelected() {
        guard let l = mOnItemSelectedListener else { return }
        let selection = getSelectedItemPosition()
        if selection >= 0 {
            let v = getSelectedView()
            l.onItemSelected(self, v, selection, getAdapterBase()?.getItemId(selection) ?? AAdapterView.INVALID_ROW_ID)
        } else {
            l.onNothingSelected(self)
        }
    }

    /// AdapterView.handleDataChanged (lookForSelectablePosition is the identity, like AdapterView's).
    func handleDataChanged() {
        let count = mItemCount
        var found = false
        if count > 0 {
            var newPos: Int
            if mNeedSync {
                mNeedSync = false
            }
            newPos = getSelectedItemPosition()
            if newPos >= count { newPos = count - 1 }
            if newPos < 0 { newPos = 0 }
            let selectablePos = newPos
            if selectablePos >= 0 {
                setNextSelectedPositionInt(selectablePos)
                checkSelectionChanged()
                found = true
            }
        }
        if !found {
            mSelectedPosition = AAdapterView.INVALID_POSITION
            mSelectedRowId = AAdapterView.INVALID_ROW_ID
            mNextSelectedPosition = AAdapterView.INVALID_POSITION
            mNextSelectedRowId = AAdapterView.INVALID_ROW_ID
            mNeedSync = false
            checkSelectionChanged()
        }
    }

    override func onLayout(_ changed: Bool, _ left: Int, _ top: Int, _ right: Int, _ bottom: Int) {
        mLayoutHeight = height
    }

    /// AdapterView.AdapterDataSetObserver.
    func aw_makeDataSetObserver() -> ADataSetObserver {
        return ADataSetObserver(onChanged: { [weak self] in
            guard let self = self, let adapter = self.getAdapterBase() else { return }
            self.mDataChanged = true
            self.mOldItemCount = self.mItemCount
            self.mItemCount = adapter.getCount()
            self.requestLayout()
        }, onInvalidated: { [weak self] in
            guard let self = self else { return }
            self.mDataChanged = true
            self.mOldItemCount = self.mItemCount
            self.mItemCount = 0
            self.mSelectedPosition = AAdapterView.INVALID_POSITION
            self.mSelectedRowId = AAdapterView.INVALID_ROW_ID
            self.mNextSelectedPosition = AAdapterView.INVALID_POSITION
            self.mNextSelectedRowId = AAdapterView.INVALID_ROW_ID
            self.mNeedSync = false
            self.requestLayout()
        })
    }
}

// MARK: - AbsSpinner

/// android.widget.AbsSpinner.
class AAbsSpinner: AAdapterView {
    var mAdapter: ABaseAdapter?
    var mHeightMeasureSpec = 0
    var mWidthMeasureSpec = 0
    var mSelectionLeftPadding = 0
    var mSelectionTopPadding = 0
    var mSelectionRightPadding = 0
    var mSelectionBottomPadding = 0
    let mSpinnerPadding = ARect()
    /// RecycleBin: position -> scrap view.
    var mRecycler: [Int: AView] = [:]
    private var mDataSetObserver: ADataSetObserver?

    override init() {
        super.init()
        // initAbsSpinner
        setFocusable(true)
        setWillNotDraw(false)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    override func getAdapterBase() -> ABaseAdapter? { return mAdapter }

    /// AbsSpinner.setAdapter: selection 0 (or none), observers, relayout.
    func setAdapterInternal(_ adapter: ABaseAdapter?) {
        if let old = mAdapter {
            if let o = mDataSetObserver { old.unregisterDataSetObserver(o) }
            resetList()
        }
        mAdapter = adapter
        mOldSelectedPosition = AAdapterView.INVALID_POSITION
        mOldSelectedRowId = AAdapterView.INVALID_ROW_ID
        if let a = adapter {
            mOldItemCount = mItemCount
            mItemCount = a.getCount()
            let o = aw_makeDataSetObserver()
            mDataSetObserver = o
            a.registerDataSetObserver(o)
            let position = mItemCount > 0 ? 0 : AAdapterView.INVALID_POSITION
            setSelectedPositionInt(position)
            setNextSelectedPositionInt(position)
            if mItemCount == 0 {
                checkSelectionChanged()
            }
        } else {
            resetList()
            checkSelectionChanged()
        }
        requestLayout()
    }

    func resetList() {
        mDataChanged = false
        mNeedSync = false
        removeAllViewsInLayout()
        mOldSelectedPosition = AAdapterView.INVALID_POSITION
        mOldSelectedRowId = AAdapterView.INVALID_ROW_ID
        setSelectedPositionInt(AAdapterView.INVALID_POSITION)
        setNextSelectedPositionInt(AAdapterView.INVALID_POSITION)
        invalidate()
    }

    override func onMeasure(_ widthMeasureSpec: Int, _ heightMeasureSpec: Int) {
        let widthMode = AMeasureSpec.getMode(widthMeasureSpec)
        var widthSize: Int
        var heightSize: Int
        mSpinnerPadding.left = mPaddingLeft > mSelectionLeftPadding ? mPaddingLeft : mSelectionLeftPadding
        mSpinnerPadding.top = mPaddingTop > mSelectionTopPadding ? mPaddingTop : mSelectionTopPadding
        mSpinnerPadding.right = mPaddingRight > mSelectionRightPadding ? mPaddingRight : mSelectionRightPadding
        mSpinnerPadding.bottom = mPaddingBottom > mSelectionBottomPadding ? mPaddingBottom : mSelectionBottomPadding
        if mDataChanged {
            handleDataChanged()
        }
        var preferredHeight = 0
        var preferredWidth = 0
        var needsMeasuring = true
        let selectedPosition = getSelectedItemPosition()
        if selectedPosition >= 0, let adapter = mAdapter, selectedPosition < adapter.getCount() {
            var view = mRecycler.removeValue(forKey: selectedPosition)
            if view == nil {
                view = adapter.getView(selectedPosition, nil, self)
                if view!.importantForAccessibility == AView.IMPORTANT_FOR_ACCESSIBILITY_AUTO {
                    view!.importantForAccessibility = AView.IMPORTANT_FOR_ACCESSIBILITY_YES
                }
            }
            if let view = view {
                mRecycler[selectedPosition] = view
                if view.layoutParams == nil {
                    mBlockLayoutRequests = true
                    view.layoutParams = generateDefaultLayoutParams()
                    mBlockLayoutRequests = false
                }
                measureChild(view, widthMeasureSpec, heightMeasureSpec)
                preferredHeight = getChildHeight(view) + mSpinnerPadding.top + mSpinnerPadding.bottom
                preferredWidth = getChildWidth(view) + mSpinnerPadding.left + mSpinnerPadding.right
                needsMeasuring = false
            }
        }
        if needsMeasuring {
            preferredHeight = mSpinnerPadding.top + mSpinnerPadding.bottom
            if widthMode == AMeasureSpec.UNSPECIFIED {
                preferredWidth = mSpinnerPadding.left + mSpinnerPadding.right
            }
        }
        preferredHeight = Swift.max(preferredHeight, getSuggestedMinimumHeight())
        preferredWidth = Swift.max(preferredWidth, getSuggestedMinimumWidth())
        heightSize = AView.resolveSizeAndState(preferredHeight, heightMeasureSpec, 0)
        widthSize = AView.resolveSizeAndState(preferredWidth, widthMeasureSpec, 0)
        setMeasuredDimension(widthSize, heightSize)
        mHeightMeasureSpec = heightMeasureSpec
        mWidthMeasureSpec = widthMeasureSpec
    }

    func getChildHeight(_ child: AView) -> Int { return child.measuredHeight }
    func getChildWidth(_ child: AView) -> Int { return child.measuredWidth }

    /// AbsSpinner.generateDefaultLayoutParams: (MATCH_PARENT, WRAP_CONTENT).
    override func generateDefaultLayoutParams() -> AViewGroup.LayoutParams {
        return AViewGroup.LayoutParams(AViewGroup.LayoutParams.MATCH_PARENT, AViewGroup.LayoutParams.WRAP_CONTENT)
    }

    func recycleAllViews() {
        let position = mFirstPosition
        for i in 0..<childCount {
            if let v = getChildAt(i) { mRecycler[position + i] = v }
        }
    }

    /// AbsSpinner.setSelection(position, animate): an immediate layout of the new selection.
    func setSelection(_ position: Int, _ animate: Bool) {
        let shouldAnimate = animate && mFirstPosition <= position && position <= mFirstPosition + childCount - 1
        setSelectionInt(position, shouldAnimate)
    }

    /// AbsSpinner.setSelection(position): applied by the next layout.
    func setSelection(_ position: Int) {
        setNextSelectedPositionInt(position)
        requestLayout()
        invalidate()
    }

    func setSelectionInt(_ position: Int, _ animate: Bool) {
        if position != mOldSelectedPosition {
            mBlockLayoutRequests = true
            let delta = position - mSelectedPosition
            setNextSelectedPositionInt(position)
            layout(delta, animate)
            mBlockLayoutRequests = false
        }
    }

    /// AbsSpinner.layout (Spinner implements it).
    func layout(_ delta: Int, _ animate: Bool) {}

    override func getSelectedView() -> AView? {
        if mItemCount > 0 && mSelectedPosition >= 0 {
            return getChildAt(mSelectedPosition - mFirstPosition)
        }
        return nil
    }

    /// AbsSpinner.requestLayout: blocked while it lays out its own selection.
    override func requestLayout() {
        if !mBlockLayoutRequests {
            super.requestLayout()
        }
    }

    override func getCount() -> Int { return mItemCount }

    /// AbsSpinner.pointToPosition.
    func pointToPosition(_ x: Int, _ y: Int) -> Int {
        let frame = ARect()
        var i = childCount - 1
        while i >= 0 {
            if let child = getChildAt(i), child.visibility == AView.VISIBLE {
                child.getHitRect(frame)
                if frame.contains(x, y) { return mFirstPosition + i }
            }
            i -= 1
        }
        return AAdapterView.INVALID_POSITION
    }

    /// RecycleBin.clear: the scrap views are dropped.
    func aw_clearRecycler() {
        mRecycler.removeAll()
    }
}

// MARK: - Spinner

/// The transparent button over a Spinner that shows its dropdown as an iOS menu.
final class AWSpinnerMenuButton: UIButton {}

/// spinner_background_material (the default background a Spinner gets; the app always replaces it): padding end 48 dp,
/// the ic_spinner_caret triangle (24 dp, 12 dp from the end) in ?colorControlNormal.
final class AWSpinnerBackground: ADrawable {
    private let aw_paint = APaint(APaint.ANTI_ALIAS_FLAG)
    private var aw_layoutDirection = AView.LAYOUT_DIRECTION_LTR

    override func setLayoutDirection(_ layoutDirection: Int) -> Bool {
        aw_layoutDirection = layoutDirection
        return true
    }

    override func getPadding(_ r: ARect) -> Bool {
        if aw_layoutDirection == AView.LAYOUT_DIRECTION_RTL {
            r.set(aw_dpx(48), 0, 0, 0)
        } else {
            r.set(0, 0, aw_dpx(48), 0)
        }
        return true
    }

    override func draw(_ canvas: ACanvas) {
        let b = bounds
        let size = Float(aw_dpx(24))
        let rtl = aw_layoutDirection == AView.LAYOUT_DIRECTION_RTL
        let left = rtl ? Float(b.left + aw_dpx(12)) : Float(b.right - aw_dpx(12)) - size
        let top = Float(b.top) + (Float(b.height()) - size) / 2
        let s = size / 24
        let path = APath()
        path.moveTo(left + 7 * s, top + 10 * s)
        path.lineTo(left + 12 * s, top + 15 * s)
        path.lineTo(left + 17 * s, top + 10 * s)
        path.close()
        aw_paint.style = .FILL
        aw_paint.color = AWMaterialColors.colorControlNormal
        canvas.drawPath(path, aw_paint)
    }
}

/// android.widget.Spinner (Widget.Material.Light.Spinner.DropDown: gravity start|center_vertical, dropdown mode,
/// disableChildrenWhenDisabled). The dropdown is an iOS menu.
class ASpinner: AAbsSpinner {
    static let MODE_DIALOG = 0
    static let MODE_DROPDOWN = 1
    static let MODE_THEME = -1

    let mode: Int
    private var mGravity = AGravity.START | AGravity.CENTER_VERTICAL
    private var mDisableChildrenWhenDisabled = true
    private var mPrompt: String?
    private var mDropDownWidth = AViewGroup.LayoutParams.WRAP_CONTENT
    private let aw_menuButton = AWSpinnerMenuButton(type: .custom)

    override convenience init() {
        self.init(ASpinner.MODE_THEME)
    }

    /// `Spinner(context, mode)`.
    init(_ mode: Int) {
        self.mode = mode == ASpinner.MODE_THEME ? ASpinner.MODE_DROPDOWN : mode
        super.init()
        isClickable = true
        setBackgroundDrawable(AWSpinnerBackground())
        aw_installMenuButton()
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    // MARK: The iOS menu

    private func aw_installMenuButton() {
        let b = aw_menuButton
        b.backgroundColor = .clear
        b.showsMenuAsPrimaryAction = true
        b.preferredMenuElementOrder = .fixed
        b.menu = UIMenu(children: [UIDeferredMenuElement.uncached { [weak self] completion in
            completion(self?.aw_menuItems() ?? [])
        }])
        b.addTarget(self, action: #selector(aw_menuTouchDown), for: .touchDown)
        b.addTarget(self, action: #selector(aw_menuTouchEnded), for: [.touchUpInside, .touchUpOutside, .touchCancel, .touchDragExit])
        b.addTarget(self, action: #selector(aw_menuTouchEnded), for: .menuActionTriggered)
        addSubview(b)
    }

    /// The dropdown items (DropDownAdapter over the spinner adapter): the item texts in adapter order; picking one is
    /// DropdownPopup's item click: setSelection(position), then the item click listener.
    private func aw_menuItems() -> [UIMenuElement] {
        guard let adapter = mAdapter else { return [] }
        var items: [UIMenuElement] = []
        for position in 0..<adapter.getCount() {
            let title = ABaseAdapter.aw_itemText(adapter.getItem(position))
            let action = UIAction(title: title) { [weak self] _ in
                guard let self = self else { return }
                self.setSelection(position)
                if self.mOnItemClickListener != nil {
                    self.performItemClick(nil, position, adapter.getItemId(position))
                }
            }
            if !adapter.isEnabled(position) { action.attributes = .disabled }
            items.append(action)
        }
        return items
    }

    @objc private func aw_menuTouchDown() {
        if isEnabled { setPressed(true) }
    }

    @objc private func aw_menuTouchEnded() {
        setPressed(false)
    }

    private func aw_layoutMenuButton() {
        let d = CGFloat(AWidgetEnv.density)
        aw_menuButton.frame = CGRect(x: 0, y: 0, width: CGFloat(width) / d, height: CGFloat(height) / d)
        aw_menuButton.semanticContentAttribute = isLayoutRtl ? .forceRightToLeft : .forceLeftToRight
        bringSubviewToFront(aw_menuButton)
    }

    // MARK: Adapter

    var adapter: ABaseAdapter? {
        get { return mAdapter }
        set { setAdapter(newValue) }
    }

    func getAdapter() -> ABaseAdapter? { return mAdapter }

    /// Spinner.setAdapter: the view type count must be 1.
    func setAdapter(_ adapter: ABaseAdapter?) {
        setAdapterInternal(adapter)
        aw_clearRecycler()
        if let a = adapter, a.getViewTypeCount() != 1 {
            preconditionFailure("java.lang.IllegalArgumentException: Spinner adapter view type count must be 1")
        }
        updateAccessibility()
    }

    /// Spinner.setOnItemClickListener: not allowed.
    override func setOnItemClickListener(_ listener: AOnItemClickListener?) {
        preconditionFailure("java.lang.RuntimeException: setOnItemClickListener cannot be used with a spinner.")
    }

    // MARK: Attributes

    func setGravity(_ gravity0: Int) {
        var gravity = gravity0
        if mGravity != gravity {
            if (gravity & AGravity.HORIZONTAL_GRAVITY_MASK) == 0 { gravity |= AGravity.START }
            mGravity = gravity
            requestLayout()
        }
    }

    var gravity: Int {
        get { return mGravity }
        set { setGravity(newValue) }
    }

    var prompt: String? {
        get { return mPrompt }
        set { mPrompt = newValue }
    }

    func setPrompt(_ prompt: String?) { mPrompt = prompt }

    var dropDownWidth: Int {
        get { return mDropDownWidth }
        set { mDropDownWidth = newValue }
    }

    /// The dropdown's background, offsets: the iOS menu has its own look.
    func setPopupBackgroundDrawable(_ background: ADrawable?) {}
    func setDropDownVerticalOffset(_ pixels: Int) {}
    func setDropDownHorizontalOffset(_ pixels: Int) {}

    override func setEnabled(_ enabled: Bool) {
        super.setEnabled(enabled)
        aw_menuButton.isEnabled = enabled
        if mDisableChildrenWhenDisabled {
            for i in 0..<childCount { getChildAt(i)?.setEnabled(enabled) }
        }
    }

    // MARK: Measure and layout (Spinner)

    override func onMeasure(_ widthMeasureSpec: Int, _ heightMeasureSpec: Int) {
        super.onMeasure(widthMeasureSpec, heightMeasureSpec)
        if AMeasureSpec.getMode(widthMeasureSpec) == AMeasureSpec.AT_MOST {
            let measuredWidth = self.measuredWidth
            setMeasuredDimension(Swift.min(Swift.max(measuredWidth, measureContentWidth(mAdapter, background)),
                                           AMeasureSpec.getSize(widthMeasureSpec)), measuredHeight)
        }
    }

    /// Spinner.measureContentWidth: the widest of the first 15 dropdown views around the selection, plus the
    /// background padding.
    func measureContentWidth(_ adapter: ABaseAdapter?, _ background: ADrawable?) -> Int {
        guard let adapter = adapter else { return 0 }
        var width = 0
        let widthMeasureSpec = AMeasureSpec.makeSafeMeasureSpec(measuredWidth, AMeasureSpec.UNSPECIFIED)
        let heightMeasureSpec = AMeasureSpec.makeSafeMeasureSpec(measuredHeight, AMeasureSpec.UNSPECIFIED)
        var start = Swift.max(0, getSelectedItemPosition())
        let end = Swift.min(adapter.getCount(), start + 15)
        let count = end - start
        start = Swift.max(0, start - (15 - count))
        var i = start
        while i < end {
            let itemView = adapter.getView(i, nil, self)
            if itemView.layoutParams == nil {
                itemView.layoutParams = AViewGroup.LayoutParams(AViewGroup.LayoutParams.WRAP_CONTENT,
                                                                AViewGroup.LayoutParams.WRAP_CONTENT)
            }
            itemView.measure(widthMeasureSpec, heightMeasureSpec)
            width = Swift.max(width, itemView.measuredWidth)
            i += 1
        }
        if let bg = background {
            let r = ARect()
            if bg.getPadding(r) { width += r.left + r.right }
        }
        return width
    }

    override func onLayout(_ changed: Bool, _ l: Int, _ t: Int, _ r: Int, _ b: Int) {
        super.onLayout(changed, l, t, r, b)
        mInLayout = true
        layout(0, false)
        mInLayout = false
        aw_layoutMenuButton()
    }

    /// Spinner.layout: the selected view becomes the only child, placed by the gravity.
    override func layout(_ delta: Int, _ animate: Bool) {
        let childrenLeft = mSpinnerPadding.left
        let childrenWidth = mRight - mLeft - mSpinnerPadding.left - mSpinnerPadding.right
        if mDataChanged {
            handleDataChanged()
        }
        if mItemCount == 0 {
            resetList()
            return
        }
        if mNextSelectedPosition >= 0 {
            setSelectedPositionInt(mNextSelectedPosition)
        }
        recycleAllViews()
        removeAllViewsInLayout()
        mFirstPosition = mSelectedPosition
        if mAdapter != nil {
            let sel = makeView(mSelectedPosition, true)
            let width = sel.measuredWidth
            var selectedOffset = childrenLeft
            let absoluteGravity = AGravity.getAbsoluteGravity(mGravity, isLayoutRtl ? AView.LAYOUT_DIRECTION_RTL : AView.LAYOUT_DIRECTION_LTR)
            switch absoluteGravity & AGravity.HORIZONTAL_GRAVITY_MASK {
            case AGravity.CENTER_HORIZONTAL:
                selectedOffset = childrenLeft + (childrenWidth / 2) - (width / 2)
            case AGravity.RIGHT:
                selectedOffset = childrenLeft + childrenWidth - width
            default:
                break
            }
            sel.offsetLeftAndRight(selectedOffset)
        }
        aw_clearRecycler()
        invalidate()
        checkSelectionChanged()
        mDataChanged = false
        mNeedSync = false
        setNextSelectedPositionInt(mSelectedPosition)
        updateAccessibility()
    }

    private func makeView(_ position: Int, _ addChild: Bool) -> AView {
        if !mDataChanged, let child = mRecycler.removeValue(forKey: position) {
            setUpChild(child, addChild)
            return child
        }
        let child = mAdapter!.getView(position, nil, self)
        setUpChild(child, addChild)
        return child
    }

    private func setUpChild(_ child: AView, _ addChild: Bool) {
        let lp = child.layoutParams ?? generateDefaultLayoutParams()
        addViewInLayout(child, 0, lp)
        child.setSelected(hasFocus())
        if mDisableChildrenWhenDisabled {
            child.setEnabled(isEnabled)
        }
        let childHeightSpec = AViewGroup.getChildMeasureSpec(mHeightMeasureSpec, mSpinnerPadding.top + mSpinnerPadding.bottom, lp.height)
        let childWidthSpec = AViewGroup.getChildMeasureSpec(mWidthMeasureSpec, mSpinnerPadding.left + mSpinnerPadding.right, lp.width)
        child.measure(childWidthSpec, childHeightSpec)
        let childTop = mSpinnerPadding.top + ((measuredHeight - mSpinnerPadding.bottom - mSpinnerPadding.top - child.measuredHeight) / 2)
        let childBottom = childTop + child.measuredHeight
        let width = child.measuredWidth
        let childLeft = 0
        let childRight = childLeft + width
        child.layout(childLeft, childTop, childRight, childBottom)
        if !addChild {
            removeViewInLayout(child)
        }
    }

    override func getBaseline() -> Int {
        var child: AView? = nil
        if childCount > 0 {
            child = getChildAt(0)
        } else if let a = mAdapter, a.getCount() > 0 {
            let c = makeView(0, false)
            mRecycler[0] = c
            child = c
        }
        if let c = child {
            let childBaseline = c.getBaseline()
            return childBaseline >= 0 ? c.top + childBaseline : -1
        }
        return -1
    }

    // MARK: Accessibility

    /// The menu button is the accessibility element (a pop-up button with the selected item's text).
    override func updateAccessibility() {
        super.updateAccessibility()
        isAccessibilityElement = false
        aw_menuButton.accessibilityLabel = contentDescription ?? (getSelectedItem().map { ABaseAdapter.aw_itemText($0) })
        aw_menuButton.accessibilityTraits = .button
    }
}

// MARK: - RecyclerView (vertical list)

/// androidx.recyclerview.widget.RecyclerView, vertical LinearLayoutManager only: every item is bound into a vertical
/// LinearLayout inside the ScrollView port (no recycling; the leaderboard has at most 20 rows).
class ARecyclerView: AScrollView {
    static let NO_POSITION = -1
    static let INVALID_TYPE = -1
    static let HORIZONTAL = 0
    static let VERTICAL = 1

    /// RecyclerView.LayoutParams (margins).
    class LayoutParams: AViewGroup.MarginLayoutParams {}

    /// RecyclerView.ViewHolder.
    class ViewHolder {
        let itemView: AView
        fileprivate(set) var mPosition = ARecyclerView.NO_POSITION
        fileprivate(set) var mItemViewType = ARecyclerView.INVALID_TYPE
        fileprivate weak var mOwnerRecyclerView: ARecyclerView?

        init(_ itemView: AView) {
            self.itemView = itemView
        }

        var adapterPosition: Int { return mOwnerRecyclerView == nil ? ARecyclerView.NO_POSITION : mPosition }
        var bindingAdapterPosition: Int { return adapterPosition }
        var absoluteAdapterPosition: Int { return adapterPosition }
        var layoutPosition: Int { return mPosition }
        var itemViewType: Int { return mItemViewType }
        func getAdapterPosition() -> Int { return adapterPosition }
        func getBindingAdapterPosition() -> Int { return bindingAdapterPosition }
        func getAbsoluteAdapterPosition() -> Int { return absoluteAdapterPosition }
        func getLayoutPosition() -> Int { return layoutPosition }
        func getItemViewType() -> Int { return itemViewType }
    }

    /// The non-generic part of RecyclerView.Adapter (what the RecyclerView calls).
    class AdapterBase {
        fileprivate var aw_observers: [ObjectIdentifier: () -> Void] = [:]

        init() {}

        func aw_itemCount() -> Int { return 0 }
        func aw_itemViewType(_ position: Int) -> Int { return 0 }
        func aw_createViewHolder(_ parent: AViewGroup, _ viewType: Int) -> ViewHolder {
            preconditionFailure("RecyclerView.Adapter.onCreateViewHolder is abstract")
        }
        func aw_bindViewHolder(_ holder: ViewHolder, _ position: Int) {}
        func aw_viewRecycled(_ holder: ViewHolder) {}

        /// notifyDataSetChanged and the item / range notifications (all rebind every position here).
        func notifyDataSetChanged() {
            for o in aw_observers.values { o() }
        }

        func notifyItemChanged(_ position: Int) { notifyDataSetChanged() }
        func notifyItemRangeChanged(_ positionStart: Int, _ itemCount: Int) { notifyDataSetChanged() }
        func notifyItemInserted(_ position: Int) { notifyDataSetChanged() }
        func notifyItemRangeInserted(_ positionStart: Int, _ itemCount: Int) { notifyDataSetChanged() }
        func notifyItemRemoved(_ position: Int) { notifyDataSetChanged() }
        func notifyItemRangeRemoved(_ positionStart: Int, _ itemCount: Int) { notifyDataSetChanged() }
        func notifyItemMoved(_ fromPosition: Int, _ toPosition: Int) { notifyDataSetChanged() }
    }

    /// RecyclerView.Adapter<VH>: subclasses override onCreateViewHolder, onBindViewHolder and getItemCount.
    class Adapter<VH: ViewHolder>: AdapterBase {
        override init() {
            super.init()
        }

        func onCreateViewHolder(_ parent: AViewGroup, _ viewType: Int) -> VH {
            preconditionFailure("RecyclerView.Adapter.onCreateViewHolder is abstract")
        }

        func onBindViewHolder(_ holder: VH, _ position: Int) {
            preconditionFailure("RecyclerView.Adapter.onBindViewHolder is abstract")
        }

        func getItemCount() -> Int {
            preconditionFailure("RecyclerView.Adapter.getItemCount is abstract")
        }

        var itemCount: Int { return getItemCount() }

        func getItemViewType(_ position: Int) -> Int { return 0 }
        func getItemId(_ position: Int) -> Int64 { return Int64(ARecyclerView.NO_ID) }
        func onViewRecycled(_ holder: VH) {}

        override func aw_itemCount() -> Int { return getItemCount() }
        override func aw_itemViewType(_ position: Int) -> Int { return getItemViewType(position) }

        override func aw_createViewHolder(_ parent: AViewGroup, _ viewType: Int) -> ViewHolder {
            let holder = onCreateViewHolder(parent, viewType)
            holder.mItemViewType = viewType
            return holder
        }

        override func aw_bindViewHolder(_ holder: ViewHolder, _ position: Int) {
            guard let h = holder as? VH else { return }
            onBindViewHolder(h, position)
        }

        override func aw_viewRecycled(_ holder: ViewHolder) {
            if let h = holder as? VH { onViewRecycled(h) }
        }
    }

    /// RecyclerView.LayoutManager.
    class LayoutManager {
        fileprivate weak var aw_recyclerView: ARecyclerView?
        init() {}
        var orientationValue: Int { return ARecyclerView.VERTICAL }
    }

    private let aw_content = ALinearLayout()
    private var aw_holders: [ViewHolder] = []
    private var mLayout: LayoutManager?
    private var mAdapter: AdapterBase?
    private var aw_hasFixedSize = false

    override init() {
        super.init()
        aw_content.orientation = ALinearLayout.VERTICAL
        isVerticalScrollBarEnabled = false
        super.addView(aw_content, -1, AFrameLayout.LayoutParams(AViewGroup.LayoutParams.MATCH_PARENT, AViewGroup.LayoutParams.WRAP_CONTENT))
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    // MARK: Layout manager and adapter

    var layoutManager: LayoutManager? {
        get { return mLayout }
        set { setLayoutManager(newValue) }
    }

    func getLayoutManager() -> LayoutManager? { return mLayout }

    func setLayoutManager(_ layout: LayoutManager?) {
        mLayout?.aw_recyclerView = nil
        mLayout = layout
        layout?.aw_recyclerView = self
        aw_populate()
    }

    var adapter: AdapterBase? {
        get { return mAdapter }
        set { setAdapter(newValue) }
    }

    func getAdapter() -> AdapterBase? { return mAdapter }

    /// RecyclerView.setAdapter: the old adapter's holders are dropped, the new one is bound.
    func setAdapter(_ adapter: AdapterBase?) {
        if let old = mAdapter {
            old.aw_observers[ObjectIdentifier(self)] = nil
            for h in aw_holders { old.aw_viewRecycled(h); h.mOwnerRecyclerView = nil }
        }
        aw_holders.removeAll()
        aw_content.removeAllViews()
        mAdapter = adapter
        adapter?.aw_observers[ObjectIdentifier(self)] = { [weak self] in self?.aw_populate() }
        aw_populate()
    }

    func setHasFixedSize(_ hasFixedSize: Bool) { aw_hasFixedSize = hasFixedSize }

    /// Binds every position (holders of the same view type are reused, like a rebinding layout pass).
    private func aw_populate() {
        guard let adapter = mAdapter, mLayout != nil else { return }
        let count = adapter.aw_itemCount()
        var newHolders: [ViewHolder] = []
        for position in 0..<count {
            let type = adapter.aw_itemViewType(position)
            var holder: ViewHolder
            if position < aw_holders.count, aw_holders[position].mItemViewType == type {
                holder = aw_holders[position]
            } else {
                holder = adapter.aw_createViewHolder(self, type)
                holder.mItemViewType = type
            }
            holder.mOwnerRecyclerView = self
            holder.mPosition = position
            adapter.aw_bindViewHolder(holder, position)
            newHolders.append(holder)
        }
        for old in aw_holders where !newHolders.contains(where: { $0 === old }) {
            adapter.aw_viewRecycled(old)
            old.mOwnerRecyclerView = nil
            old.mPosition = ARecyclerView.NO_POSITION
        }
        aw_holders = newHolders
        // The content shows exactly the holders' item views, in position order.
        let wanted = newHolders.map { $0.itemView }
        let current = aw_content.children
        if current.count != wanted.count || zip(current, wanted).contains(where: { $0 !== $1 }) {
            aw_content.removeAllViews()
            for v in wanted {
                if let p = v.parentGroup { p.removeView(v) }
                aw_content.addView(v, ARecyclerView.aw_linearParams(v.layoutParams))
            }
        }
        requestLayout()
        invalidate()
    }

    /// The item's RecyclerView / margin params as the vertical LinearLayout's (LinearLayoutManager measures with
    /// the margins; WRAP_CONTENT heights are UNSPECIFIED in the scrolling direction, as in the LinearLayout here).
    private static func aw_linearParams(_ lp: AViewGroup.LayoutParams?) -> ALinearLayout.LayoutParams {
        guard let lp = lp else {
            return ALinearLayout.LayoutParams(AViewGroup.LayoutParams.MATCH_PARENT, AViewGroup.LayoutParams.WRAP_CONTENT)
        }
        if let l = lp as? ALinearLayout.LayoutParams { return l }
        let out = ALinearLayout.LayoutParams(lp.width, lp.height)
        if let m = lp as? AViewGroup.MarginLayoutParams {
            out.leftMargin = m.leftMargin
            out.topMargin = m.topMargin
            out.rightMargin = m.rightMargin
            out.bottomMargin = m.bottomMargin
            out.marginStart = m.marginStart
            out.marginEnd = m.marginEnd
        }
        return out
    }

    /// RecyclerView.generateLayoutParams for items inflated with this parent.
    override func generateDefaultLayoutParams() -> AViewGroup.LayoutParams {
        return ARecyclerView.LayoutParams(AViewGroup.LayoutParams.WRAP_CONTENT, AViewGroup.LayoutParams.WRAP_CONTENT)
    }

    // MARK: Children

    /// The bound item views (RecyclerView's children).
    var itemViews: [AView] { return aw_content.children }

    func findViewHolderForAdapterPosition(_ position: Int) -> ViewHolder? {
        return aw_holders.getOrNull(position)
    }

    func getChildAdapterPosition(_ child: AView) -> Int {
        return aw_holders.firstIndex(where: { $0.itemView === child }) ?? ARecyclerView.NO_POSITION
    }

    /// RecyclerView.scrollToPosition: the item's top at the top (LinearLayoutManager).
    func scrollToPosition(_ position: Int) {
        guard let h = aw_holders.getOrNull(position) else { return }
        scrollTo(0, Swift.max(0, h.itemView.top))
    }

    func smoothScrollToPosition(_ position: Int) {
        guard let h = aw_holders.getOrNull(position) else { return }
        smoothScrollTo(0, Swift.max(0, h.itemView.top))
    }
}

/// androidx LinearLayoutManager (vertical, not reversed; the only layout the app uses).
final class ALinearLayoutManager: ARecyclerView.LayoutManager {
    static let HORIZONTAL = 0
    static let VERTICAL = 1

    let orientation: Int
    let reverseLayout: Bool

    init(_ context: AContext?) {
        orientation = ALinearLayoutManager.VERTICAL
        reverseLayout = false
        super.init()
    }

    init(_ context: AContext?, _ orientation: Int, _ reverseLayout: Bool) {
        precondition(orientation == ALinearLayoutManager.VERTICAL && !reverseLayout,
                     "ALinearLayoutManager supports the vertical, non-reversed layout only")
        self.orientation = orientation
        self.reverseLayout = reverseLayout
        super.init()
    }

    override var orientationValue: Int { return orientation }
}

// MARK: - TabLayout

/// TabLayout.OnTabSelectedListener.
protocol AOnTabSelectedListener: AnyObject {
    func onTabSelected(_ tab: ATabLayout.Tab)
    func onTabUnselected(_ tab: ATabLayout.Tab)
    func onTabReselected(_ tab: ATabLayout.Tab)
}

/// A closure OnTabSelectedListener.
final class ASimpleOnTabSelectedListener: AOnTabSelectedListener {
    private let selected: (ATabLayout.Tab) -> Void
    private let unselected: (ATabLayout.Tab) -> Void
    private let reselected: (ATabLayout.Tab) -> Void

    init(onTabSelected: @escaping (ATabLayout.Tab) -> Void, onTabUnselected: @escaping (ATabLayout.Tab) -> Void = { _ in },
         onTabReselected: @escaping (ATabLayout.Tab) -> Void = { _ in }) {
        selected = onTabSelected
        unselected = onTabUnselected
        reselected = onTabReselected
    }

    func onTabSelected(_ tab: ATabLayout.Tab) { selected(tab) }
    func onTabUnselected(_ tab: ATabLayout.Tab) { unselected(tab) }
    func onTabReselected(_ tab: ATabLayout.Tab) { reselected(tab) }
}

/// com.google.android.material.tabs.TabLayout (Widget.MaterialComponents.TabLayout, MODE_FIXED, GRAVITY_FILL):
/// a horizontal strip of equal tabs over a colorSurface background with a sliding 2 dp indicator.
class ATabLayout: AFrameLayout {
    typealias OnTabSelectedListener = AOnTabSelectedListener

    static let MODE_SCROLLABLE = 0, MODE_FIXED = 1, MODE_AUTO = 2
    static let GRAVITY_FILL = 0, GRAVITY_CENTER = 1, GRAVITY_START = 2
    static let INDICATOR_GRAVITY_BOTTOM = 0, INDICATOR_GRAVITY_CENTER = 1, INDICATOR_GRAVITY_TOP = 2, INDICATOR_GRAVITY_STRETCH = 3
    private static let DEFAULT_HEIGHT = 48
    private static let TAB_MIN_WIDTH_MARGIN = 56

    /// TabLayout.Tab.
    final class Tab {
        static let INVALID_POSITION = -1
        fileprivate(set) weak var parent: ATabLayout?
        fileprivate var view: AWTabView!
        private(set) var text: String?
        private(set) var contentDescription: String?
        private var tag: Any?
        fileprivate(set) var position = Tab.INVALID_POSITION

        fileprivate init() {}

        /// Tab.setText (returns the tab, for chaining).
        @discardableResult
        func setText(_ text: String?) -> Tab {
            if (contentDescription ?? "").isEmpty, let t = text, !t.isEmpty {
                view?.contentDescription = t
            }
            self.text = text
            updateView()
            return self
        }

        @discardableResult
        func setText(res: AStringRes) -> Tab { return setText(getString(res)) }

        func getText() -> String? { return text }

        @discardableResult
        func setContentDescription(_ contentDesc: String?) -> Tab {
            contentDescription = contentDesc
            updateView()
            return self
        }

        @discardableResult
        func setTag(_ tag: Any?) -> Tab {
            self.tag = tag
            return self
        }

        func getTag() -> Any? { return tag }
        func getPosition() -> Int { return position }

        var isSelected: Bool {
            guard let p = parent else { return false }
            let selected = p.getSelectedTabPosition()
            return selected != Tab.INVALID_POSITION && selected == position
        }

        /// Tab.select.
        func select() {
            guard let p = parent else {
                preconditionFailure("java.lang.IllegalArgumentException: Tab not attached to a TabLayout")
            }
            p.selectTab(self)
        }

        fileprivate func updateView() {
            view?.update()
        }
    }

    private var tabs: [Tab] = []
    private var selectedTab: Tab?
    private let slidingTabIndicator = AWSlidingTabIndicator()
    private var selectedListeners: [AOnTabSelectedListener] = []

    fileprivate var tabPaddingStart = 0
    fileprivate var tabPaddingTop = 0
    fileprivate var tabPaddingEnd = 0
    fileprivate var tabPaddingBottom = 0
    fileprivate var tabTextSize: Float = 0
    fileprivate var tabTextMultiLineSize: Float = 0
    fileprivate var tabTextColors: AColorStateList?
    fileprivate var tabMaxWidth = Int(Int32.max)
    private var requestedTabMaxWidth = 0
    fileprivate var mode = ATabLayout.MODE_FIXED
    fileprivate var tabGravity = ATabLayout.GRAVITY_FILL
    fileprivate var tabIndicatorAnimationDuration: Int64 = 250
    fileprivate var tabIndicatorGravity = ATabLayout.INDICATOR_GRAVITY_BOTTOM
    fileprivate var tabIndicatorFullWidth = true
    fileprivate var tabSelectedIndicatorColor = AWMaterialColors.colorPrimary
    fileprivate var tabIndicatorHeight = -1
    fileprivate let tabIndicatorTimeInterpolator: ATimeInterpolator = AWAnimationUtils.FAST_OUT_SLOW_IN_INTERPOLATOR

    override init() {
        super.init()
        slidingTabIndicator.owner = self
        // Widget.MaterialComponents.TabLayout (light palette).
        setBackgroundDrawable(AColorDrawable(AWMaterialColors.colorSurface))
        tabPaddingStart = aw_dpx(12)
        tabPaddingEnd = aw_dpx(12)
        tabPaddingTop = 0
        tabPaddingBottom = 0
        tabTextSize = Float(ATypedValue.toDimensionPixelSize(ATypedValue.COMPLEX_UNIT_SP, 14))
        tabTextMultiLineSize = Float(ATypedValue.toDimensionPixelSize(ATypedValue.COMPLEX_UNIT_SP, 12))
        tabTextColors = AColorStateList([[AStateSet.state_selected], []],
                                        [AWMaterialColors.colorPrimary, AWMaterialColors.withAlpha(AWMaterialColors.colorOnSurface, 0.60)])
        requestedTabMaxWidth = aw_dpx(264)
        super.addView(slidingTabIndicator, -1, AFrameLayout.LayoutParams(AViewGroup.LayoutParams.WRAP_CONTENT, AViewGroup.LayoutParams.MATCH_PARENT))
        applyModeAndGravity()
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    /// TabLayout.addView: only TabItems (not used by the app).
    override func addView(_ child: AView, _ index: Int, _ params: AViewGroup.LayoutParams) {
        preconditionFailure("java.lang.IllegalArgumentException: Only TabItem instances can be added to TabLayout")
    }

    // MARK: Tabs

    func newTab() -> Tab {
        let tab = Tab()
        tab.parent = self
        tab.view = AWTabView(self, tab)
        return tab
    }

    func addTab(_ tab: Tab) { addTab(tab, tabs.isEmpty) }
    func addTab(_ tab: Tab, _ position: Int) { addTab(tab, position, tabs.isEmpty) }
    func addTab(_ tab: Tab, _ setSelected: Bool) { addTab(tab, tabs.count, setSelected) }

    func addTab(_ tab: Tab, _ position: Int, _ setSelected: Bool) {
        precondition(tab.parent === self, "java.lang.IllegalArgumentException: Tab belongs to a different TabLayout.")
        configureTab(tab, position)
        addTabView(tab)
        if setSelected {
            tab.select()
        }
    }

    private func configureTab(_ tab: Tab, _ position: Int) {
        tab.position = position
        tabs.insert(tab, at: position)
        for i in (position + 1)..<tabs.count {
            tabs[i].position = i
        }
    }

    private func addTabView(_ tab: Tab) {
        let tabView = tab.view!
        tabView.setSelected(false)
        tabView.setActivated(false)
        slidingTabIndicator.addView(tabView, tab.position, createLayoutParamsForTabs())
    }

    private func createLayoutParamsForTabs() -> ALinearLayout.LayoutParams {
        let lp = ALinearLayout.LayoutParams(AViewGroup.LayoutParams.WRAP_CONTENT, AViewGroup.LayoutParams.MATCH_PARENT)
        updateTabViewLayoutParams(lp)
        return lp
    }

    private func updateTabViewLayoutParams(_ lp: ALinearLayout.LayoutParams) {
        if mode == ATabLayout.MODE_FIXED && tabGravity == ATabLayout.GRAVITY_FILL {
            lp.width = 0
            lp.weight = 1
        } else {
            lp.width = AViewGroup.LayoutParams.WRAP_CONTENT
            lp.weight = 0
        }
    }

    func removeAllTabs() {
        for i in stride(from: slidingTabIndicator.childCount - 1, through: 0, by: -1) {
            slidingTabIndicator.removeViewAt(i)
        }
        for t in tabs { t.parent = nil; t.position = Tab.INVALID_POSITION }
        tabs.removeAll()
        selectedTab = nil
    }

    var tabCount: Int { return tabs.count }
    func getTabCount() -> Int { return tabs.count }
    func getTabAt(_ index: Int) -> Tab? { return tabs.getOrNull(index) }

    var selectedTabPosition: Int { return getSelectedTabPosition() }
    func getSelectedTabPosition() -> Int { return selectedTab?.position ?? Tab.INVALID_POSITION }

    // MARK: Listeners

    func addOnTabSelectedListener(_ listener: AOnTabSelectedListener) {
        if !selectedListeners.contains(where: { $0 === listener }) {
            selectedListeners.append(listener)
        }
    }

    func removeOnTabSelectedListener(_ listener: AOnTabSelectedListener) {
        selectedListeners.removeAll { $0 === listener }
    }

    func clearOnTabSelectedListeners() { selectedListeners.removeAll() }

    // MARK: Selection

    func selectTab(_ tab: Tab?) { selectTab(tab, true) }

    func selectTab(_ tab: Tab?, _ updateIndicator: Bool) {
        let currentTab = selectedTab
        if currentTab === tab {
            if let current = currentTab {
                dispatchTabReselected(current)
                animateToTab(current.position)
            }
        } else {
            let newPosition = tab?.position ?? Tab.INVALID_POSITION
            if updateIndicator {
                if (currentTab == nil || currentTab!.position == Tab.INVALID_POSITION) && newPosition != Tab.INVALID_POSITION {
                    setScrollPosition(newPosition, 0, true)
                } else {
                    animateToTab(newPosition)
                }
                if newPosition != Tab.INVALID_POSITION {
                    setSelectedTabView(newPosition)
                }
            }
            selectedTab = tab
            if let current = currentTab, current.parent != nil {
                dispatchTabUnselected(current)
            }
            if let t = tab {
                dispatchTabSelected(t)
            }
        }
    }

    private func dispatchTabSelected(_ tab: Tab) {
        for l in selectedListeners.reversed() { l.onTabSelected(tab) }
    }

    private func dispatchTabUnselected(_ tab: Tab) {
        for l in selectedListeners.reversed() { l.onTabUnselected(tab) }
    }

    private func dispatchTabReselected(_ tab: Tab) {
        for l in selectedListeners.reversed() { l.onTabReselected(tab) }
    }

    private func setSelectedTabView(_ position: Int) {
        let tabCount = slidingTabIndicator.childCount
        if position < tabCount {
            for i in 0..<tabCount {
                guard let child = slidingTabIndicator.getChildAt(i) else { continue }
                if (i == position && !child.isSelected) || (i != position && child.isSelected) {
                    child.setSelected(i == position)
                    child.setActivated(i == position)
                    (child as? AWTabView)?.updateTab()
                    continue
                }
                child.setSelected(i == position)
                child.setActivated(i == position)
            }
        }
    }

    /// TabLayout.setScrollPosition (fixed mode: no scrolling, the indicator jumps).
    func setScrollPosition(_ position: Int, _ positionOffset: Float, _ updateSelectedTabView: Bool) {
        let roundedPosition = AWMath.round(Float(position) + positionOffset)
        if roundedPosition < 0 || roundedPosition >= slidingTabIndicator.childCount { return }
        slidingTabIndicator.setIndicatorPositionFromTabPosition(position, positionOffset)
        if updateSelectedTabView {
            setSelectedTabView(roundedPosition)
        }
    }

    private func animateToTab(_ newPosition: Int) {
        if newPosition == Tab.INVALID_POSITION { return }
        if !isAttachedToWindow || !isLaidOut || slidingTabIndicator.childrenNeedLayout() {
            setScrollPosition(newPosition, 0, true)
            return
        }
        slidingTabIndicator.animateIndicatorToPosition(newPosition, tabIndicatorAnimationDuration)
    }

    // MARK: Attributes

    /// TabLayout.setSelectedTabIndicatorColor (app:tabIndicatorColor).
    func setSelectedTabIndicatorColor(_ color: Int) {
        tabSelectedIndicatorColor = color
        slidingTabIndicator.invalidate()
    }

    func setSelectedTabIndicatorHeight(_ height: Int) {
        tabIndicatorHeight = height
        slidingTabIndicator.invalidate()
    }

    /// TabLayout.setTabTextColors (app:tabTextColor / app:tabSelectedTextColor).
    func setTabTextColors(_ textColor: AColorStateList?) {
        if tabTextColors !== textColor {
            tabTextColors = textColor
            updateAllTabs()
        }
    }

    func setTabTextColors(_ normalColor: Int, _ selectedColor: Int) {
        setTabTextColors(AColorStateList([[AStateSet.state_selected], []], [selectedColor, normalColor]))
    }

    var tabTextColorsList: AColorStateList? { return tabTextColors }

    var tabMode: Int {
        get { return mode }
        set { if newValue != mode { mode = newValue; applyModeAndGravity() } }
    }

    var tabGravityValue: Int {
        get { return tabGravity }
        set { if newValue != tabGravity { tabGravity = newValue; applyModeAndGravity() } }
    }

    var isTabIndicatorFullWidth: Bool {
        get { return tabIndicatorFullWidth }
        set { tabIndicatorFullWidth = newValue; slidingTabIndicator.invalidate() }
    }

    private func applyModeAndGravity() {
        slidingTabIndicator.setPaddingRelative(0, 0, 0, 0)
        slidingTabIndicator.gravity = mode == ATabLayout.MODE_FIXED && tabGravity == ATabLayout.GRAVITY_CENTER
            ? AGravity.CENTER_HORIZONTAL : AGravity.START
        updateTabViews(true)
    }

    private func updateTabViews(_ requestLayout: Bool) {
        for i in 0..<slidingTabIndicator.childCount {
            guard let child = slidingTabIndicator.getChildAt(i),
                  let lp = child.layoutParams as? ALinearLayout.LayoutParams else { continue }
            child.minimumWidth = 0
            updateTabViewLayoutParams(lp)
            if requestLayout { child.requestLayout() }
        }
    }

    private func updateAllTabs() {
        for t in tabs { t.updateView() }
    }

    // MARK: Measure (TabLayout.onMeasure)

    override func onMeasure(_ widthMeasureSpec: Int, _ heightMeasureSpec0: Int) {
        var heightMeasureSpec = heightMeasureSpec0
        let idealHeight = AWMath.round(Float(ATabLayout.DEFAULT_HEIGHT) * AWidgetEnv.density)
        switch AMeasureSpec.getMode(heightMeasureSpec) {
        case AMeasureSpec.AT_MOST:
            if childCount == 1 && AMeasureSpec.getSize(heightMeasureSpec) >= idealHeight {
                getChildAt(0)?.minimumHeight = idealHeight
            }
        case AMeasureSpec.UNSPECIFIED:
            heightMeasureSpec = AMeasureSpec.makeMeasureSpec(idealHeight + paddingTop + paddingBottom, AMeasureSpec.EXACTLY)
        default:
            break
        }
        let specWidth = AMeasureSpec.getSize(widthMeasureSpec)
        if AMeasureSpec.getMode(widthMeasureSpec) != AMeasureSpec.UNSPECIFIED {
            tabMaxWidth = requestedTabMaxWidth > 0
                ? requestedTabMaxWidth
                : AWMath.javaInt(Float(specWidth) - Float(ATabLayout.TAB_MIN_WIDTH_MARGIN) * AWidgetEnv.density)
        }
        super.onMeasure(widthMeasureSpec, heightMeasureSpec)
        if childCount == 1, let child = getChildAt(0) {
            let remeasure: Bool
            switch mode {
            case ATabLayout.MODE_FIXED:
                remeasure = child.measuredWidth != measuredWidth
            default:
                remeasure = child.measuredWidth < measuredWidth
            }
            if remeasure {
                let childHeightMeasureSpec = AViewGroup.getChildMeasureSpec(heightMeasureSpec, paddingTop + paddingBottom,
                                                                            child.layoutParams?.height ?? AViewGroup.LayoutParams.MATCH_PARENT)
                let childWidthMeasureSpec = AMeasureSpec.makeMeasureSpec(measuredWidth, AMeasureSpec.EXACTLY)
                child.measure(childWidthMeasureSpec, childHeightMeasureSpec)
            }
        }
    }
}

/// TabLayout.SlidingTabIndicator: the horizontal strip of tab views; draws the selected-tab indicator (below the tab
/// contents) and slides it between tabs.
final class AWSlidingTabIndicator: ALinearLayout {
    weak var owner: ATabLayout?
    private let indicatorBounds = ARect(-1, 0, -1, 0)
    private var indicatorAnimator: AValueAnimator?
    private var indicatorPosition = -1
    private let aw_paint = APaint(APaint.ANTI_ALIAS_FLAG)

    override init() {
        super.init()
        orientation = ALinearLayout.HORIZONTAL
        setWillNotDraw(false)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    func childrenNeedLayout() -> Bool {
        for i in 0..<childCount {
            if let child = getChildAt(i), child.width <= 0 { return true }
        }
        return false
    }

    /// TabIndicatorInterpolator.calculateIndicatorWidthForTab (full width, or the label's width).
    private func indicatorRange(_ tab: AView?) -> (left: Int, right: Int) {
        guard let tab = tab else { return (0, 0) }
        if !(owner?.tabIndicatorFullWidth ?? true), let tv = tab as? AWTabView {
            return tv.contentRange()
        }
        return (tab.left, tab.right)
    }

    func setIndicatorPositionFromTabPosition(_ position: Int, _ positionOffset: Float) {
        indicatorPosition = AWMath.round(Float(position) + positionOffset)
        if let a = indicatorAnimator, a.isRunning { a.cancel() }
        let firstTitle = getChildAt(position)
        let nextTitle = getChildAt(position + 1)
        tweenIndicatorPosition(firstTitle, nextTitle, positionOffset)
    }

    private func tweenIndicatorPosition(_ startTitle: AView?, _ endTitle: AView?, _ fraction: Float) {
        let hasVisibleTitle = startTitle != nil && startTitle!.width > 0
        if hasVisibleTitle {
            let s = indicatorRange(startTitle)
            let e = indicatorRange(endTitle)
            indicatorBounds.left = AWAnimationUtils.lerp(s.left, e.left, fraction)
            indicatorBounds.right = AWAnimationUtils.lerp(s.right, e.right, fraction)
        } else {
            indicatorBounds.left = -1
            indicatorBounds.right = -1
        }
        postInvalidateOnAnimation()
    }

    func animateIndicatorToPosition(_ position: Int, _ duration: Int64) {
        if let a = indicatorAnimator, a.isRunning, indicatorPosition != position {
            a.cancel()
        }
        updateOrRecreateIndicatorAnimation(true, position, duration)
    }

    private func updateOrRecreateIndicatorAnimation(_ recreateAnimation: Bool, _ position: Int, _ duration: Int64) {
        if indicatorPosition == position { return }
        guard let owner = owner else { return }
        let currentView = getChildAt(owner.getSelectedTabPosition())
        guard let targetView = getChildAt(position) else {
            jumpIndicatorToPosition(owner.getSelectedTabPosition())
            return
        }
        indicatorPosition = position
        let update: (AValueAnimator) -> Void = { [weak self] anim in
            self?.tweenIndicatorPosition(currentView, targetView, anim.animatedFraction)
        }
        if recreateAnimation || indicatorAnimator == nil {
            let a = AValueAnimator()
            a.interpolator = owner.tabIndicatorTimeInterpolator
            a.setDuration(duration)
            a.setFloatValues(0, 1)
            a.addUpdateListener(update)
            indicatorAnimator = a
            a.start()
        } else {
            indicatorAnimator!.removeAllUpdateListeners()
            indicatorAnimator!.addUpdateListener(update)
        }
    }

    private func jumpIndicatorToPosition(_ position: Int) {
        let currentView = getChildAt(position)
        let r = indicatorRange(currentView)
        indicatorBounds.left = currentView == nil ? 0 : r.left
        indicatorBounds.right = currentView == nil ? 0 : r.right
        indicatorPosition = position
        invalidate()
    }

    override func onLayout(_ changed: Bool, _ l: Int, _ t: Int, _ r: Int, _ b: Int) {
        super.onLayout(changed, l, t, r, b)
        if let a = indicatorAnimator, a.isRunning, let owner = owner {
            updateOrRecreateIndicatorAnimation(false, owner.getSelectedTabPosition(), -1)
        } else {
            if indicatorPosition == -1 { indicatorPosition = owner?.getSelectedTabPosition() ?? -1 }
            jumpIndicatorToPosition(indicatorPosition)
        }
    }

    /// SlidingTabIndicator.draw: the indicator first, then the tabs above it.
    override func onDraw(_ canvas: ACanvas) {
        super.onDraw(canvas)
        guard let owner = owner else { return }
        var indicatorHeight = owner.tabIndicatorHeight
        if indicatorHeight < 0 { indicatorHeight = aw_dpx(2) }
        var indicatorTop = 0
        var indicatorBottom = 0
        switch owner.tabIndicatorGravity {
        case ATabLayout.INDICATOR_GRAVITY_BOTTOM:
            indicatorTop = height - indicatorHeight
            indicatorBottom = height
        case ATabLayout.INDICATOR_GRAVITY_CENTER:
            indicatorTop = (height - indicatorHeight) / 2
            indicatorBottom = (height + indicatorHeight) / 2
        case ATabLayout.INDICATOR_GRAVITY_TOP:
            indicatorTop = 0
            indicatorBottom = indicatorHeight
        case ATabLayout.INDICATOR_GRAVITY_STRETCH:
            indicatorTop = 0
            indicatorBottom = height
        default:
            break
        }
        if indicatorBounds.right - indicatorBounds.left > 0 {
            aw_paint.style = .FILL
            aw_paint.color = owner.tabSelectedIndicatorColor
            canvas.drawRect(Float(indicatorBounds.left), Float(indicatorTop), Float(indicatorBounds.right), Float(indicatorBottom), aw_paint)
        }
    }
}

/// TabLayout.TabView: a vertical LinearLayout (gravity center, padding start / end 12 dp) with the label TextView
/// (design_layout_tab_text: wrap_content, end ellipsis, centred, at most 2 lines; tabTextAppearance =
/// TextAppearance.MaterialComponents.Button: 14 sp sans-serif-medium, 0.0892857143 em, all caps).
final class AWTabView: ALinearLayout {
    private weak var tabLayout: ATabLayout?
    private weak var tab: ATabLayout.Tab?
    private var textView: ATextView?
    private var defaultMaxLines = 2

    init(_ tabLayout: ATabLayout, _ tab: ATabLayout.Tab) {
        self.tabLayout = tabLayout
        self.tab = tab
        super.init()
        setPaddingRelative(tabLayout.tabPaddingStart, tabLayout.tabPaddingTop, tabLayout.tabPaddingEnd, tabLayout.tabPaddingBottom)
        gravity = AGravity.CENTER
        orientation = ALinearLayout.VERTICAL
        isClickable = true
        update()
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    /// TabView.performClick: the tab is selected (the click listener first, like Android).
    @discardableResult
    override func performClick() -> Bool {
        let handled = super.performClick()
        if let t = tab {
            t.select()
            return true
        }
        return handled
    }

    override func setSelected(_ selected: Bool) {
        super.setSelected(selected)
        textView?.setSelected(selected)
    }

    func updateTab() {
        update()
    }

    /// TabView.update / updateTextAndIcon.
    func update() {
        guard let layout = tabLayout else { return }
        if textView == nil {
            let t = ATextView()
            t.setEllipsize(.END)
            t.setGravity(AGravity.CENTER)
            t.setMaxLines(2)
            addView(t, ALinearLayout.LayoutParams(AViewGroup.LayoutParams.WRAP_CONTENT, AViewGroup.LayoutParams.WRAP_CONTENT))
            textView = t
            defaultMaxLines = t.maxLines
        }
        guard let t = textView else { return }
        // TextViewCompat.setTextAppearance(textView, tabTextAppearance).
        t.setTextSize(ATypedValue.COMPLEX_UNIT_PX, layout.tabTextSize)
        t.setTypeface(ATypeface.create("sans-serif-medium", ATypeface.NORMAL))
        t.setLetterSpacing(0.0892857143)
        t.setAllCaps(true)
        if let colors = layout.tabTextColors { t.setTextColor(colors) }
        let text = tab?.getText()
        let hasText = !(text ?? "").isEmpty
        if hasText {
            t.setText(text!)
            t.visibility = AView.VISIBLE
            visibility = AView.VISIBLE
        } else {
            t.visibility = AView.GONE
            t.setText("")
        }
        contentDescription = tab?.contentDescription ?? (hasText ? text : nil)
        t.setSelected(isSelected)
    }

    /// TabView.onMeasure: at most tabMaxWidth; a label wrapping to two lines uses the 12 sp size.
    override func onMeasure(_ origWidthMeasureSpec: Int, _ origHeightMeasureSpec: Int) {
        let specWidthSize = AMeasureSpec.getSize(origWidthMeasureSpec)
        let specWidthMode = AMeasureSpec.getMode(origWidthMeasureSpec)
        let maxWidth = tabLayout?.tabMaxWidth ?? 0
        let widthMeasureSpec: Int
        if maxWidth > 0 && (specWidthMode == AMeasureSpec.UNSPECIFIED || specWidthSize > maxWidth) {
            widthMeasureSpec = AMeasureSpec.makeMeasureSpec(maxWidth, AMeasureSpec.AT_MOST)
        } else {
            widthMeasureSpec = origWidthMeasureSpec
        }
        let heightMeasureSpec = origHeightMeasureSpec
        super.onMeasure(widthMeasureSpec, heightMeasureSpec)
        guard let t = textView, let layout = tabLayout else { return }
        var textSize = layout.tabTextSize
        let maxLines = defaultMaxLines
        if t.lineCount > 1 {
            textSize = layout.tabTextMultiLineSize
        }
        let curTextSize = t.textSize
        let curLineCount = t.lineCount
        let curMaxLines = t.maxLines
        if textSize != curTextSize || (curMaxLines >= 0 && maxLines != curMaxLines) {
            var updateTextView = true
            if layout.mode == ATabLayout.MODE_FIXED && textSize > curTextSize && curLineCount == 1 {
                let textLayout = t.layout
                if textLayout == nil
                    || AWTabView.approximateLineWidth(textLayout!, 0, textSize) > Float(measuredWidth - paddingLeft - paddingRight) {
                    updateTextView = false
                }
            }
            if updateTextView {
                t.setTextSize(ATypedValue.COMPLEX_UNIT_PX, textSize)
                t.setMaxLines(maxLines)
                super.onMeasure(widthMeasureSpec, heightMeasureSpec)
            }
        }
    }

    /// TabView.approximateLineWidth.
    private static func approximateLineWidth(_ layout: ALayout, _ line: Int, _ textSize: Float) -> Float {
        return layout.getLineWidth(line) * (textSize / layout.getPaint().textSize)
    }

    /// The label's horizontal extent in the strip (calculateTabViewContentBounds).
    func contentRange() -> (left: Int, right: Int) {
        guard let t = textView else { return (left, right) }
        let w = AWMath.ceil(t.layout.map { l -> Float in
            var m: Float = 0
            for i in 0..<l.lineCount { m = Swift.max(m, l.getLineWidth(i)) }
            return m
        } ?? 0)
        let center = (left + right) / 2
        let contentWidth = Swift.max(w, aw_dpx(24))
        return (center - contentWidth / 2, center + contentWidth / 2)
    }
}

