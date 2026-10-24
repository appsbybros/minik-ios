import UIKit

// AndroidKit fragments (DESIGN 4.5): android.os.Bundle, android.view.LayoutInflater (a registry of the Swift
// builders that replace the XML layouts), and androidx.fragment 1.8.9 (Fragment, FragmentManager,
// FragmentTransaction/BackStackRecord, FragmentStore, FragmentStateManager, SpecialEffectsController).
//
// The fragment state machine is a statement-level port of the androidx sources the app links
// (fragment-ktx 1.8.9), so lifecycle callbacks run in Android's order, e.g. for replace(A -> B):
// A.onPause, A.onStop, B.onAttach, B.onCreate, B.onCreateView, B.onViewCreated, B.onViewStateRestored, B.onStart,
// A.onDestroyView, A.onDestroy, A.onDetach, B.onResume. commit() runs on the next main-looper turn (or in
// executePendingTransactions / the activity lifecycle), popBackStack is asynchronous, and non-reordered pops and
// adds run as separate batches, exactly like FragmentManager.removeRedundantOperationsAndExecute.
//
// Not ported (no Triple Shot code path uses them; specs 13-19): animations, transitions and postponed transitions
// (every special effect completes at once, like androidx with no animation set), predictive back, saved state
// (iOS never recreates an activity, so onSaveInstanceState is never called), retained fragments, fragment
// results, menus, <fragment> layout tags, FragmentContainerView. A commit after the activity has been stopped is
// executed instead of throwing "Can not perform this action after onSaveInstanceState".

// MARK: - Bundle

/// android.os.Bundle: a typed key-value map. Getters return the default (or nil) for a missing key or a value of
/// another type, like Android (which logs the ClassCastException and returns the default).
final class ABundle: CustomStringConvertible {
    private var keysInOrder: [String] = []
    private var values: [String: Any?] = [:]

    init() {}

    /// `new Bundle(b)`: a shallow copy.
    init(_ b: ABundle) {
        keysInOrder = b.keysInOrder
        values = b.values
    }

    static let EMPTY = ABundle()

    /// Bundle.size() (a method in Kotlin too).
    func size() -> Int { keysInOrder.count }
    /// Bundle.isEmpty() (Kotlin property syntax `isEmpty`).
    var isEmpty: Bool { keysInOrder.isEmpty }
    func clear() { keysInOrder.removeAll(); values.removeAll() }
    func containsKey(_ key: String) -> Bool { values.keys.contains(key) }
    func keySet() -> [String] { keysInOrder }
    @discardableResult func remove(_ key: String) -> Any? {
        guard values.keys.contains(key) else { return nil }
        keysInOrder.removeAll { $0 == key }
        return values.removeValue(forKey: key) ?? nil
    }

    func putAll(_ bundle: ABundle) {
        for k in bundle.keysInOrder { put(k, bundle.values[k] ?? nil) }
    }

    private func put(_ key: String, _ value: Any?) {
        if !values.keys.contains(key) { keysInOrder.append(key) }
        values[key] = .some(value)
    }

    /// Bundle.get(key) (deprecated untyped getter).
    func get(_ key: String) -> Any? { values[key] ?? nil }

    func putString(_ key: String, _ value: String?) { put(key, value) }
    func putInt(_ key: String, _ value: Int) { put(key, value) }
    func putLong(_ key: String, _ value: Int64) { put(key, value) }
    func putFloat(_ key: String, _ value: Float) { put(key, value) }
    func putDouble(_ key: String, _ value: Double) { put(key, value) }
    func putBoolean(_ key: String, _ value: Bool) { put(key, value) }
    func putStringArrayList(_ key: String, _ value: [String]?) { put(key, value.map { KitStringArrayList($0) }) }
    func putStringArray(_ key: String, _ value: [String]?) { put(key, value) }
    func putIntArray(_ key: String, _ value: [Int]?) { put(key, value) }
    func putLongArray(_ key: String, _ value: [Int64]?) { put(key, value) }
    func putFloatArray(_ key: String, _ value: [Float]?) { put(key, value) }
    func putDoubleArray(_ key: String, _ value: [Double]?) { put(key, value) }
    func putBooleanArray(_ key: String, _ value: [Bool]?) { put(key, value) }
    func putBundle(_ key: String, _ value: ABundle?) { put(key, value) }
    func putCharSequence(_ key: String, _ value: String?) { put(key, value) }

    func getString(_ key: String) -> String? { get(key) as? String }
    func getString(_ key: String, _ defaultValue: String) -> String { getString(key) ?? defaultValue }
    func getCharSequence(_ key: String) -> String? { getString(key) }
    func getInt(_ key: String, _ defaultValue: Int = 0) -> Int { get(key) as? Int ?? defaultValue }
    func getLong(_ key: String, _ defaultValue: Int64 = 0) -> Int64 { get(key) as? Int64 ?? defaultValue }
    func getFloat(_ key: String, _ defaultValue: Float = 0) -> Float { get(key) as? Float ?? defaultValue }
    func getDouble(_ key: String, _ defaultValue: Double = 0) -> Double { get(key) as? Double ?? defaultValue }
    func getBoolean(_ key: String, _ defaultValue: Bool = false) -> Bool { get(key) as? Bool ?? defaultValue }
    func getStringArrayList(_ key: String) -> [String]? { (get(key) as? KitStringArrayList)?.items }
    func getStringArray(_ key: String) -> [String]? { get(key) as? [String] }
    func getIntArray(_ key: String) -> [Int]? { get(key) as? [Int] }
    func getLongArray(_ key: String) -> [Int64]? { get(key) as? [Int64] }
    func getFloatArray(_ key: String) -> [Float]? { get(key) as? [Float] }
    func getDoubleArray(_ key: String) -> [Double]? { get(key) as? [Double] }
    func getBooleanArray(_ key: String) -> [Bool]? { get(key) as? [Bool] }
    func getBundle(_ key: String) -> ABundle? { get(key) as? ABundle }

    var description: String {
        "Bundle[{" + keysInOrder.map { k in "\(k)=\(values[k].flatMap { $0 }.map { "\($0)" } ?? "null")" }.joined(separator: ", ") + "}]"
    }
}

/// An ArrayList<String> stored in a Bundle (distinct from a String[] like on Android: getStringArray does not
/// return it).
private final class KitStringArrayList: CustomStringConvertible {
    let items: [String]
    init(_ items: [String]) { self.items = items }
    var description: String { "[" + items.joined(separator: ", ") + "]" }
}

/// DESIGN 4.5: fragment arguments are an ABundle.
typealias AFragmentArgs = ABundle

// MARK: - LayoutInflater

/// android.view.LayoutInflater over the Swift layout builders. Each XML layout of the app (R.layout.x) is
/// translated into a builder that creates the same view tree (ids, attributes, params) and is registered here by
/// the screen that owns the layout: `ALayoutInflater.register(R.layout.fragment_x) { inflater in ... }`.
/// The builder sets the layout root's `layoutParams` from the XML root's layout_* attributes.
final class ALayoutInflater {
    typealias Builder = (_ inflater: ALayoutInflater) -> AView

    nonisolated(unsafe) private static var builders: [String: Builder] = [:]

    /// Registers the builder of a layout resource (R.layout.x). A later registration replaces an earlier one.
    static func register(_ layout: String, _ builder: @escaping Builder) {
        builders[layout] = builder
    }

    static func isRegistered(_ layout: String) -> Bool { builders[layout] != nil }

    let context: AContext?

    init(_ context: AContext?) { self.context = context }

    /// LayoutInflater.from(context).
    static func from(_ context: AContext?) -> ALayoutInflater { ALayoutInflater(context) }

    /// LayoutInflater.cloneInContext(newContext).
    func cloneInContext(_ newContext: AContext?) -> ALayoutInflater { ALayoutInflater(newContext) }

    func getContext() -> AContext? { context }

    /// inflate(resource, root): attaches to root when root is not null.
    @discardableResult
    func inflate(_ resource: String, _ root: AViewGroup?) -> AView {
        inflate(resource, root, root != nil)
    }

    /// inflate(resource, root, attachToRoot), with Android's layout-params rules: with a root, the layout root
    /// gets `root.generateLayoutParams(xml params)`; without one, the XML root's layout_* attributes are dropped
    /// (null layout params). Returns root when attached, else the layout root.
    @discardableResult
    func inflate(_ resource: String, _ root: AViewGroup?, _ attachToRoot: Bool) -> AView {
        guard let builder = ALayoutInflater.builders[resource] else {
            preconditionFailure("android.view.InflateException: no Swift builder registered for layout \(resource)")
        }
        let temp = builder(self)
        let xmlParams = temp.layoutParams
        guard let root = root else {
            temp.layoutParams = nil
            return temp
        }
        let params = xmlParams.map { root.generateLayoutParams($0) } ?? root.generateDefaultLayoutParams()
        if attachToRoot {
            root.addView(temp, params)
            return root
        }
        temp.layoutParams = params
        return temp
    }
}

// MARK: - Fragment

/// androidx.fragment.app.Fragment. Subclasses override the lifecycle methods with unlabelled parameters (like the
/// Java API) and must call super, as on Android (a missing super call stops with SuperNotCalledException).
class AFragment: ALifecycleOwner, CustomStringConvertible {
    static let INITIALIZING = -1          // Not yet attached.
    static let ATTACHED = 0               // Attached to the host.
    static let CREATED = 1                // Created.
    static let VIEW_CREATED = 2           // View Created.
    static let AWAITING_EXIT_EFFECTS = 3  // Downward state, awaiting exit effects
    static let ACTIVITY_CREATED = 4       // Fully created, not started.
    static let STARTED = 5                // Created and started, not resumed.
    static let AWAITING_ENTER_EFFECTS = 6 // Upward state, awaiting enter effects
    static let RESUMED = 7                // Created started and resumed.

    var mState = AFragment.INITIALIZING
    var mSavedFragmentState: ABundle?
    var mWho: String = UUID().uuidString.lowercased()
    var mPreviousWho: String?
    var mArguments: ABundle?
    var mAdded = false
    var mRemoving = false
    var mBeingSaved = false
    var mFromLayout = false
    var mInLayout = false
    var mRestored = false
    var mPerformedCreateView = false
    var mBackStackNesting = 0
    var mFragmentManager: AFragmentManager?
    var mHost: AActivity?
    var mChildFragmentManager = AFragmentManager()
    var mParentFragment: AFragment?
    var mFragmentId: String?
    var mContainerId: String?
    var mTag: String?
    var mHidden = false
    var mDetached = false
    var mDeferStart = false
    var mHiddenChanged = false
    var mIsCreated = false
    var mTransitioning = false
    var mMaxState: ALifecycle.State = .RESUMED
    var mContainer: AViewGroup?
    var mView: AView?
    var mLifecycleRegistry: ALifecycleRegistry!
    var mViewLifecycleOwner: AFragmentViewLifecycleOwner?
    var mCalled = false
    var mPostOnViewCreatedAlpha: CGFloat = 1
    private var mLayoutInflater: ALayoutInflater?
    /// `Fragment(@LayoutRes contentLayoutId)`: inflated by the default onCreateView.
    let contentLayoutId: String?

    init() {
        contentLayoutId = nil
        initLifecycle()
    }

    /// `Fragment(R.layout.x)`.
    init(contentLayoutId: String) {
        self.contentLayoutId = contentLayoutId
        initLifecycle()
    }

    private func initLifecycle() {
        mLifecycleRegistry = ALifecycleRegistry(self)
    }

    var lifecycle: ALifecycle { mLifecycleRegistry }
    func getLifecycle() -> ALifecycle { mLifecycleRegistry }

    /// getViewLifecycleOwner(): only between onCreateView and onDestroyView.
    var viewLifecycleOwner: ALifecycleOwner {
        guard let owner = mViewLifecycleOwner else {
            preconditionFailure("Can't access the Fragment View's LifecycleOwner for \(self) when getView() is null i.e., before onCreateView() or after onDestroyView()")
        }
        return owner
    }
    func getViewLifecycleOwner() -> ALifecycleOwner { viewLifecycleOwner }

    var description: String {
        var s = "\(type(of: self)){\(String(UInt(bitPattern: ObjectIdentifier(self).hashValue), radix: 16))} (\(mWho)"
        if let id = mFragmentId { s += " id=" + id }
        if let tag = mTag { s += " tag=" + tag }
        return s + ")"
    }

    // MARK: Identity and arguments

    var id: String? { mFragmentId }
    func getId() -> String? { mFragmentId }
    var tag: String? { mTag }
    func getTag() -> String? { mTag }

    var arguments: ABundle? {
        get { mArguments }
        set { mArguments = newValue }
    }
    func getArguments() -> ABundle? { mArguments }
    func setArguments(_ args: ABundle?) { mArguments = args }
    func requireArguments() -> ABundle {
        guard let a = mArguments else { preconditionFailure("Fragment \(self) does not have any arguments.") }
        return a
    }

    var isStateSaved: Bool { mFragmentManager?.isStateSaved ?? false }

    // MARK: Host, context, managers

    /// getContext(): the activity while attached.
    var context: AContext? { mHost }
    func getContext() -> AContext? { mHost }
    func requireContext() -> AContext {
        guard let c = mHost else { preconditionFailure("Fragment \(self) not attached to a context.") }
        return c
    }

    var activity: AActivity? { mHost }
    func getActivity() -> AActivity? { mHost }
    func requireActivity() -> AActivity {
        guard let a = mHost else { preconditionFailure("Fragment \(self) not attached to an activity.") }
        return a
    }

    var host: AActivity? { mHost }
    func requireHost() -> AActivity { requireActivity() }

    /// getResources(): requireContext().getResources().
    var resources: AContextResources { requireContext().resources }
    func getResources() -> AContextResources { resources }
    func getString(_ resId: AStringRes) -> String { resources.getString(resId) }
    func getString(_ resId: AStringRes, _ formatArgs: Any?...) -> String {
        AFormat.format(ALocale.getDefault(), AResources.getString(resId), formatArgs)
    }
    func getText(_ resId: AStringRes) -> String { resources.getText(resId) }

    var parentFragmentManager: AFragmentManager {
        guard let fm = mFragmentManager else {
            preconditionFailure("Fragment \(self) not associated with a fragment manager.")
        }
        return fm
    }
    func getParentFragmentManager() -> AFragmentManager { parentFragmentManager }

    var childFragmentManager: AFragmentManager {
        if mHost == nil { preconditionFailure("Fragment \(self) has not been attached yet.") }
        return mChildFragmentManager
    }
    func getChildFragmentManager() -> AFragmentManager { childFragmentManager }

    var parentFragment: AFragment? { mParentFragment }
    func getParentFragment() -> AFragment? { mParentFragment }
    func requireParentFragment() -> AFragment {
        guard let p = mParentFragment else {
            preconditionFailure(mHost == nil ? "Fragment \(self) is not attached to any Fragment or host"
                                             : "Fragment \(self) is not a child Fragment, it is directly attached to \(String(describing: mHost))")
        }
        return p
    }

    // MARK: State queries

    var isAdded: Bool { mHost != nil && mAdded }
    var isDetached: Bool { mDetached }
    var isRemoving: Bool { mRemoving }
    var isInLayout: Bool { mInLayout }
    var isResumed: Bool { mState >= AFragment.RESUMED }
    var isVisible: Bool {
        isAdded && !isHidden && mView != nil && (mView?.isAttachedToWindow ?? false) && mView?.visibility == AView.VISIBLE
    }
    var isHidden: Bool { mHidden || (mFragmentManager?.isParentHidden(mParentFragment) ?? false) }
    func isInBackStack() -> Bool { mBackStackNesting > 0 }

    var view: AView? { mView }
    func getView() -> AView? { mView }
    func requireView() -> AView {
        guard let v = mView else {
            preconditionFailure("Fragment \(self) did not return a View from onCreateView() or this was called before onCreateView().")
        }
        return v
    }

    /// getLayoutInflater(): the cached inflater of the last onCreateView.
    var layoutInflater: ALayoutInflater { mLayoutInflater ?? performGetLayoutInflater(nil) }
    func getLayoutInflater() -> ALayoutInflater { layoutInflater }
    func onGetLayoutInflater(_ savedInstanceState: ABundle?) -> ALayoutInflater {
        ALayoutInflater.from(mHost).cloneInContext(mHost)
    }
    func performGetLayoutInflater(_ savedInstanceState: ABundle?) -> ALayoutInflater {
        let inflater = onGetLayoutInflater(savedInstanceState)
        mLayoutInflater = inflater
        return inflater
    }

    /// Fragment.startActivity(intent): the host activity starts it.
    func startActivity(_ intent: AIntent) throws {
        guard let host = mHost else { preconditionFailure("Fragment \(self) not attached to Activity") }
        try host.startActivity(intent)
    }

    /// setMenuVisibility / setHasOptionsMenu: the app has no options menu.
    func setHasOptionsMenu(_ hasMenu: Bool) {}

    // MARK: Lifecycle callbacks (override points; call super)

    func onAttach(_ context: AContext) { mCalled = true }

    func onCreate(_ savedInstanceState: ABundle?) {
        mCalled = true
        if !mChildFragmentManager.isStateAtLeast(AFragment.CREATED) {
            mChildFragmentManager.dispatchCreate()
        }
    }

    /// Default: inflates `contentLayoutId` into the container without attaching it.
    func onCreateView(_ inflater: ALayoutInflater, _ container: AViewGroup?, _ savedInstanceState: ABundle?) -> AView? {
        if let layout = contentLayoutId {
            return inflater.inflate(layout, container, false)
        }
        return nil
    }

    func onViewCreated(_ view: AView, _ savedInstanceState: ABundle?) {}

    func onActivityCreated(_ savedInstanceState: ABundle?) { mCalled = true }

    func onViewStateRestored(_ savedInstanceState: ABundle?) { mCalled = true }

    func onStart() { mCalled = true }

    func onResume() { mCalled = true }

    /// Never called on iOS (no activity recreation).
    func onSaveInstanceState(_ outState: ABundle) {}

    func onConfigurationChanged(_ newConfig: AConfiguration) { mCalled = true }

    func onPause() { mCalled = true }

    func onStop() { mCalled = true }

    func onLowMemory() { mCalled = true }

    func onDestroyView() { mCalled = true }

    func onDestroy() { mCalled = true }

    func onDetach() { mCalled = true }

    func onHiddenChanged(_ hidden: Bool) {}

    func onPrimaryNavigationFragmentChanged(_ isPrimaryNavigationFragment: Bool) {}

    func onAttachFragment(_ childFragment: AFragment) {}

    // MARK: Framework internals (androidx Fragment.perform*)

    private func checkCalled(_ name: String) {
        precondition(mCalled, "androidx.fragment.app.SuperNotCalledException: Fragment \(self) did not call through to super.\(name)()")
    }

    /// The container lookup of this fragment's child FragmentManager (Fragment.createFragmentContainer).
    func createFragmentContainer() -> KitFragmentContainer {
        KitFragmentContainer(findViewById: { [weak self] id in self?.mView?.findViewById(id) as AView? },
                             hasView: { [weak self] in self?.mView != nil })
    }

    func performAttach() {
        mChildFragmentManager.attachController(mHost!, createFragmentContainer(), self)
        mState = AFragment.ATTACHED
        mCalled = false
        onAttach(mHost!)
        checkCalled("onAttach")
        mFragmentManager?.dispatchOnAttachFragment(self)
        mChildFragmentManager.dispatchAttach()
    }

    func performCreate(_ savedInstanceState: ABundle?) {
        mChildFragmentManager.noteStateNotSaved()
        mState = AFragment.CREATED
        mCalled = false
        onCreate(savedInstanceState)
        mIsCreated = true
        checkCalled("onCreate")
        mLifecycleRegistry.handleLifecycleEvent(.ON_CREATE)
    }

    func performCreateView(_ inflater: ALayoutInflater, _ container: AViewGroup?, _ savedInstanceState: ABundle?) {
        mChildFragmentManager.noteStateNotSaved()
        mPerformedCreateView = true
        mViewLifecycleOwner = AFragmentViewLifecycleOwner(self)
        mView = onCreateView(inflater, container, savedInstanceState)
        if mView != nil {
            mViewLifecycleOwner?.initialize()
        } else {
            mViewLifecycleOwner = nil
        }
    }

    func performViewCreated() {
        onViewCreated(mView!, nil)
        mChildFragmentManager.dispatchViewCreated()
    }

    func performActivityCreated(_ savedInstanceState: ABundle?) {
        mChildFragmentManager.noteStateNotSaved()
        mState = AFragment.AWAITING_EXIT_EFFECTS
        mCalled = false
        onActivityCreated(savedInstanceState)
        checkCalled("onActivityCreated")
        restoreViewState()
        mChildFragmentManager.dispatchActivityCreated()
    }

    private func restoreViewState() {
        if mView != nil {
            mCalled = false
            onViewStateRestored(nil)
            checkCalled("onViewStateRestored")
            if mView != nil {
                mViewLifecycleOwner?.handleLifecycleEvent(.ON_CREATE)
            }
        }
        mSavedFragmentState = nil
    }

    func performStart() {
        mChildFragmentManager.noteStateNotSaved()
        mChildFragmentManager.execPendingActions(true)
        mState = AFragment.STARTED
        mCalled = false
        onStart()
        checkCalled("onStart")
        mLifecycleRegistry.handleLifecycleEvent(.ON_START)
        if mView != nil {
            mViewLifecycleOwner?.handleLifecycleEvent(.ON_START)
        }
        mChildFragmentManager.dispatchStart()
    }

    func performResume() {
        mChildFragmentManager.noteStateNotSaved()
        mChildFragmentManager.execPendingActions(true)
        mState = AFragment.RESUMED
        mCalled = false
        onResume()
        checkCalled("onResume")
        mLifecycleRegistry.handleLifecycleEvent(.ON_RESUME)
        if mView != nil {
            mViewLifecycleOwner?.handleLifecycleEvent(.ON_RESUME)
        }
        mChildFragmentManager.dispatchResume()
    }

    func noteStateNotSaved() { mChildFragmentManager.noteStateNotSaved() }

    func performPrimaryNavigationFragmentChanged() {
        let isPrimary = mFragmentManager?.isPrimaryNavigation(self) ?? false
        if mIsPrimaryNavigationFragment == nil || mIsPrimaryNavigationFragment != isPrimary {
            mIsPrimaryNavigationFragment = isPrimary
            onPrimaryNavigationFragmentChanged(isPrimary)
            mChildFragmentManager.dispatchPrimaryNavigationFragmentChanged()
        }
    }
    private var mIsPrimaryNavigationFragment: Bool?

    func performConfigurationChanged(_ newConfig: AConfiguration) {
        mCalled = false
        onConfigurationChanged(newConfig)
        checkCalled("onConfigurationChanged")
    }

    func performLowMemory() {
        mCalled = false
        onLowMemory()
        checkCalled("onLowMemory")
    }

    func performSaveInstanceState(_ outState: ABundle) { onSaveInstanceState(outState) }

    func performPause() {
        mChildFragmentManager.dispatchPause()
        if mView != nil {
            mViewLifecycleOwner?.handleLifecycleEvent(.ON_PAUSE)
        }
        mLifecycleRegistry.handleLifecycleEvent(.ON_PAUSE)
        mState = AFragment.AWAITING_ENTER_EFFECTS
        mCalled = false
        onPause()
        checkCalled("onPause")
    }

    func performStop() {
        mChildFragmentManager.dispatchStop()
        if mView != nil {
            mViewLifecycleOwner?.handleLifecycleEvent(.ON_STOP)
        }
        mLifecycleRegistry.handleLifecycleEvent(.ON_STOP)
        mState = AFragment.ACTIVITY_CREATED
        mCalled = false
        onStop()
        checkCalled("onStop")
    }

    func performDestroyView() {
        mChildFragmentManager.dispatchDestroyView()
        if mView != nil, let owner = mViewLifecycleOwner, owner.lifecycle.currentState.isAtLeast(.CREATED) {
            owner.handleLifecycleEvent(.ON_DESTROY)
        }
        mState = AFragment.CREATED
        mCalled = false
        onDestroyView()
        checkCalled("onDestroyView")
        mPerformedCreateView = false
    }

    func performDestroy() {
        mChildFragmentManager.dispatchDestroy()
        mLifecycleRegistry.handleLifecycleEvent(.ON_DESTROY)
        mState = AFragment.ATTACHED
        mCalled = false
        mIsCreated = false
        onDestroy()
        checkCalled("onDestroy")
    }

    func performDetach() {
        mState = AFragment.INITIALIZING
        mCalled = false
        onDetach()
        mLayoutInflater = nil
        checkCalled("onDetach")
        // Destroy the child FragmentManager if we still have it here (retained fragments).
        if !mChildFragmentManager.isDestroyed {
            mChildFragmentManager.dispatchDestroy()
            mChildFragmentManager = AFragmentManager()
        }
    }

    /// Fragment.initState: the fragment can be added again as a new instance of itself.
    func initState() {
        initLifecycle()
        mPreviousWho = mWho
        mWho = UUID().uuidString.lowercased()
        mAdded = false
        mRemoving = false
        mFromLayout = false
        mInLayout = false
        mRestored = false
        mBackStackNesting = 0
        mFragmentManager = nil
        mChildFragmentManager = AFragmentManager()
        mHost = nil
        mFragmentId = nil
        mContainerId = nil
        mTag = nil
        mHidden = false
        mDetached = false
    }

    func findFragmentByWho(_ who: String) -> AFragment? {
        if who == mWho { return self }
        return mChildFragmentManager.findFragmentByWho(who)
    }
}

/// androidx FragmentViewLifecycleOwner: the lifecycle of the fragment's view (created lazily, like Android).
final class AFragmentViewLifecycleOwner: ALifecycleOwner {
    private weak var fragment: AFragment?
    private var registry: ALifecycleRegistry?

    init(_ fragment: AFragment) { self.fragment = fragment }

    func initialize() {
        if registry == nil { registry = ALifecycleRegistry(self) }
    }

    var isInitialized: Bool { registry != nil }

    var lifecycle: ALifecycle {
        initialize()
        return registry!
    }

    func setCurrentState(_ state: ALifecycle.State) { registry?.setCurrentState(state) }
    func handleLifecycleEvent(_ event: ALifecycle.Event) { registry?.handleLifecycleEvent(event) }
}

/// androidx FragmentContainer: where a FragmentManager finds its container views (the activity window or the
/// parent fragment's view).
struct KitFragmentContainer {
    let findViewById: (String) -> AView?
    let hasView: () -> Bool
}

// MARK: - FragmentTransaction (BackStackRecord)

/// androidx FragmentTransaction + BackStackRecord in one class: the operations of one transaction, its back-stack
/// entry once committed with addToBackStack.
final class AFragmentTransaction: AFragmentManager.BackStackEntry, KitOpGenerator, CustomStringConvertible {
    static let OP_NULL = 0
    static let OP_ADD = 1
    static let OP_REPLACE = 2
    static let OP_REMOVE = 3
    static let OP_HIDE = 4
    static let OP_SHOW = 5
    static let OP_DETACH = 6
    static let OP_ATTACH = 7
    static let OP_SET_PRIMARY_NAV = 8
    static let OP_UNSET_PRIMARY_NAV = 9
    static let OP_SET_MAX_LIFECYCLE = 10

    static let TRANSIT_UNSET = -1
    static let TRANSIT_NONE = 0
    static let TRANSIT_ENTER_MASK = 0x1000
    static let TRANSIT_EXIT_MASK = 0x2000
    static let TRANSIT_FRAGMENT_OPEN = 1 | 0x1000
    static let TRANSIT_FRAGMENT_CLOSE = 2 | 0x2000
    static let TRANSIT_FRAGMENT_FADE = 3 | 0x1000

    final class Op {
        var mCmd: Int
        var mFragment: AFragment?
        var mFromExpandedOp: Bool
        var mOldMaxState: ALifecycle.State = .RESUMED
        var mCurrentMaxState: ALifecycle.State = .RESUMED

        init(_ cmd: Int, _ fragment: AFragment?, _ fromExpandedOp: Bool = false) {
            mCmd = cmd
            mFragment = fragment
            mFromExpandedOp = fromExpandedOp
        }

        init(_ cmd: Int, _ fragment: AFragment, _ state: ALifecycle.State) {
            mCmd = cmd
            mFragment = fragment
            mFromExpandedOp = false
            mOldMaxState = fragment.mMaxState
            mCurrentMaxState = state
        }
    }

    let mManager: AFragmentManager
    var mOps: [Op] = []
    var mTransition = AFragmentTransaction.TRANSIT_NONE
    var mAddToBackStack = false
    var mAllowAddToBackStack = true
    var mName: String?
    var mReorderingAllowed = false
    var mCommitRunnables: [() -> Void]?
    var mCommitted = false
    var mIndex = -1
    var mBeingSaved = false

    init(_ manager: AFragmentManager) { mManager = manager }

    var description: String {
        var s = "BackStackEntry{\(String(UInt(bitPattern: ObjectIdentifier(self).hashValue), radix: 16))"
        if mIndex >= 0 { s += " #\(mIndex)" }
        if let n = mName { s += " " + n }
        return s + "}"
    }

    // BackStackEntry
    var id: Int { mIndex }
    func getId() -> Int { mIndex }
    var name: String? { mName }
    func getName() -> String? { mName }

    func addOp(_ op: Op) { mOps.append(op) }

    // MARK: Operations

    @discardableResult
    func add(_ fragment: AFragment, _ tag: String?) -> AFragmentTransaction {
        doAddOp(nil, fragment, tag, AFragmentTransaction.OP_ADD)
        return self
    }

    @discardableResult
    func add(_ containerViewId: String, _ fragment: AFragment) -> AFragmentTransaction {
        doAddOp(containerViewId, fragment, nil, AFragmentTransaction.OP_ADD)
        return self
    }

    @discardableResult
    func add(_ containerViewId: String, _ fragment: AFragment, _ tag: String?) -> AFragmentTransaction {
        doAddOp(containerViewId, fragment, tag, AFragmentTransaction.OP_ADD)
        return self
    }

    func doAddOp(_ containerViewId: String?, _ fragment: AFragment, _ tag: String?, _ opcmd: Int) {
        if let tag = tag {
            if let old = fragment.mTag, old != tag {
                preconditionFailure("Can't change tag of fragment \(fragment): was \(old) now \(tag)")
            }
            fragment.mTag = tag
        }
        if let id = containerViewId {
            if let old = fragment.mFragmentId, old != id {
                preconditionFailure("Can't change container ID of fragment \(fragment): was \(old) now \(id)")
            }
            fragment.mContainerId = id
            fragment.mFragmentId = id
        }
        addOp(Op(opcmd, fragment))
        // BackStackRecord.doAddOp
        fragment.mFragmentManager = mManager
    }

    @discardableResult
    func replace(_ containerViewId: String, _ fragment: AFragment) -> AFragmentTransaction {
        replace(containerViewId, fragment, nil)
    }

    @discardableResult
    func replace(_ containerViewId: String, _ fragment: AFragment, _ tag: String?) -> AFragmentTransaction {
        precondition(!containerViewId.isEmpty, "Must use non-zero containerViewId")
        doAddOp(containerViewId, fragment, tag, AFragmentTransaction.OP_REPLACE)
        return self
    }

    private func checkSameManager(_ fragment: AFragment?, _ what: String) {
        if let f = fragment, let fm = f.mFragmentManager, fm !== mManager {
            preconditionFailure("Cannot \(what) Fragment attached to a different FragmentManager. Fragment \(f) is already attached to a FragmentManager.")
        }
    }

    @discardableResult
    func remove(_ fragment: AFragment) -> AFragmentTransaction {
        checkSameManager(fragment, "remove")
        addOp(Op(AFragmentTransaction.OP_REMOVE, fragment))
        return self
    }

    @discardableResult
    func hide(_ fragment: AFragment) -> AFragmentTransaction {
        checkSameManager(fragment, "hide")
        addOp(Op(AFragmentTransaction.OP_HIDE, fragment))
        return self
    }

    @discardableResult
    func show(_ fragment: AFragment) -> AFragmentTransaction {
        checkSameManager(fragment, "show")
        addOp(Op(AFragmentTransaction.OP_SHOW, fragment))
        return self
    }

    @discardableResult
    func detach(_ fragment: AFragment) -> AFragmentTransaction {
        checkSameManager(fragment, "detach")
        addOp(Op(AFragmentTransaction.OP_DETACH, fragment))
        return self
    }

    @discardableResult
    func attach(_ fragment: AFragment) -> AFragmentTransaction {
        addOp(Op(AFragmentTransaction.OP_ATTACH, fragment))
        return self
    }

    @discardableResult
    func setPrimaryNavigationFragment(_ fragment: AFragment?) -> AFragmentTransaction {
        checkSameManager(fragment, "setPrimaryNavigation for")
        addOp(Op(AFragmentTransaction.OP_SET_PRIMARY_NAV, fragment))
        return self
    }

    @discardableResult
    func setMaxLifecycle(_ fragment: AFragment, _ state: ALifecycle.State) -> AFragmentTransaction {
        precondition(fragment.mFragmentManager === mManager,
                     "Cannot setMaxLifecycle for Fragment not attached to FragmentManager \(mManager)")
        precondition(!(state == .INITIALIZED && fragment.mState > AFragment.INITIALIZING),
                     "Cannot set maximum Lifecycle to \(state) after the Fragment has been created")
        precondition(state != .DESTROYED,
                     "Cannot set maximum Lifecycle to DESTROYED. Use remove() to remove the fragment from the FragmentManager and trigger its destruction.")
        addOp(Op(AFragmentTransaction.OP_SET_MAX_LIFECYCLE, fragment, state))
        return self
    }

    var isEmpty: Bool { mOps.isEmpty }

    /// setCustomAnimations: fragment animations are not used by the app (no effect, like an empty animation).
    @discardableResult
    func setCustomAnimations(_ enter: Int, _ exit: Int) -> AFragmentTransaction { self }
    @discardableResult
    func setCustomAnimations(_ enter: Int, _ exit: Int, _ popEnter: Int, _ popExit: Int) -> AFragmentTransaction { self }

    @discardableResult
    func setTransition(_ transition: Int) -> AFragmentTransaction {
        mTransition = transition
        return self
    }

    @discardableResult
    func addToBackStack(_ name: String?) -> AFragmentTransaction {
        precondition(mAllowAddToBackStack, "This FragmentTransaction is not allowed to be added to the back stack.")
        mAddToBackStack = true
        mName = name
        return self
    }

    var isAddToBackStackAllowed: Bool { mAllowAddToBackStack }

    @discardableResult
    func disallowAddToBackStack() -> AFragmentTransaction {
        precondition(!mAddToBackStack, "This transaction is already being added to the back stack")
        mAllowAddToBackStack = false
        return self
    }

    @discardableResult
    func setReorderingAllowed(_ reorderingAllowed: Bool) -> AFragmentTransaction {
        mReorderingAllowed = reorderingAllowed
        return self
    }

    @discardableResult
    func runOnCommit(_ runnable: @escaping () -> Void) -> AFragmentTransaction {
        disallowAddToBackStack()
        if mCommitRunnables == nil { mCommitRunnables = [] }
        mCommitRunnables!.append(runnable)
        return self
    }

    // MARK: Commit

    @discardableResult
    func commit() -> Int { commitInternal(false, true) }

    @discardableResult
    func commitAllowingStateLoss() -> Int { commitInternal(true, true) }

    func commitNow() {
        disallowAddToBackStack()
        mManager.execSingleAction(self, false)
    }

    func commitNowAllowingStateLoss() {
        disallowAddToBackStack()
        mManager.execSingleAction(self, true)
    }

    func commitInternal(_ allowStateLoss: Bool, _ commitAction: Bool) -> Int {
        precondition(!mCommitted, "commit already called")
        mCommitted = true
        mIndex = mAddToBackStack ? mManager.allocBackStackIndex() : -1
        if commitAction {
            mManager.enqueueAction(self, allowStateLoss)
        }
        return mIndex
    }

    func runOnCommitRunnables() {
        if let runnables = mCommitRunnables {
            for r in runnables { r() }
            mCommitRunnables = nil
        }
    }

    // MARK: Execution (BackStackRecord)

    func generateOps(_ records: inout [AFragmentTransaction], _ isRecordPop: inout [Bool]) -> Bool {
        records.append(self)
        isRecordPop.append(false)
        if mAddToBackStack {
            mManager.addBackStackState(self)
        }
        return true
    }

    func bumpBackStackNesting(_ amt: Int) {
        if !mAddToBackStack { return }
        for op in mOps {
            if let f = op.mFragment { f.mBackStackNesting += amt }
        }
    }

    func executeOps() {
        for op in mOps {
            let f = op.mFragment
            if let f = f { f.mBeingSaved = mBeingSaved }
            switch op.mCmd {
            case AFragmentTransaction.OP_ADD:
                mManager.addFragment(f!)
            case AFragmentTransaction.OP_REMOVE:
                mManager.removeFragment(f!)
            case AFragmentTransaction.OP_HIDE:
                mManager.hideFragment(f!)
            case AFragmentTransaction.OP_SHOW:
                mManager.showFragment(f!)
            case AFragmentTransaction.OP_DETACH:
                mManager.detachFragment(f!)
            case AFragmentTransaction.OP_ATTACH:
                mManager.attachFragment(f!)
            case AFragmentTransaction.OP_SET_PRIMARY_NAV:
                mManager.setPrimaryNavigationFragment(f)
            case AFragmentTransaction.OP_UNSET_PRIMARY_NAV:
                mManager.setPrimaryNavigationFragment(nil)
            case AFragmentTransaction.OP_SET_MAX_LIFECYCLE:
                op.mOldMaxState = f!.mMaxState
                mManager.setMaxLifecycle(f!, op.mCurrentMaxState)
            default:
                preconditionFailure("Unknown cmd: \(op.mCmd)")
            }
        }
    }

    func executePopOps() {
        for op in mOps.reversed() {
            let f = op.mFragment
            if let f = f { f.mBeingSaved = mBeingSaved }
            switch op.mCmd {
            case AFragmentTransaction.OP_ADD:
                mManager.removeFragment(f!)
            case AFragmentTransaction.OP_REMOVE:
                mManager.addFragment(f!)
            case AFragmentTransaction.OP_HIDE:
                mManager.showFragment(f!)
            case AFragmentTransaction.OP_SHOW:
                mManager.hideFragment(f!)
            case AFragmentTransaction.OP_DETACH:
                mManager.attachFragment(f!)
            case AFragmentTransaction.OP_ATTACH:
                mManager.detachFragment(f!)
            case AFragmentTransaction.OP_SET_PRIMARY_NAV:
                mManager.setPrimaryNavigationFragment(nil)
            case AFragmentTransaction.OP_UNSET_PRIMARY_NAV:
                mManager.setPrimaryNavigationFragment(f)
            case AFragmentTransaction.OP_SET_MAX_LIFECYCLE:
                op.mCurrentMaxState = f!.mMaxState
                mManager.setMaxLifecycle(f!, op.mOldMaxState)
            default:
                preconditionFailure("Unknown cmd: \(op.mCmd)")
            }
        }
    }

    /// expandOps: replace -> remove(old in the same container)* + add; tracks the added fragments.
    func expandOps(_ added: inout [AFragment], _ oldPrimaryNavIn: AFragment?) -> AFragment? {
        var oldPrimaryNav = oldPrimaryNavIn
        var opNum = 0
        while opNum < mOps.count {
            let op = mOps[opNum]
            switch op.mCmd {
            case AFragmentTransaction.OP_ADD, AFragmentTransaction.OP_ATTACH:
                added.append(op.mFragment!)
            case AFragmentTransaction.OP_REMOVE, AFragmentTransaction.OP_DETACH:
                added.removeAll { $0 === op.mFragment }
                if let f = op.mFragment, f === oldPrimaryNav {
                    mOps.insert(Op(AFragmentTransaction.OP_UNSET_PRIMARY_NAV, f), at: opNum)
                    opNum += 1
                    oldPrimaryNav = nil
                }
            case AFragmentTransaction.OP_REPLACE:
                let f = op.mFragment!
                let containerId = f.mContainerId
                var alreadyAdded = false
                var i = added.count - 1
                while i >= 0 {
                    let old = added[i]
                    if old.mContainerId == containerId {
                        if old === f {
                            alreadyAdded = true
                        } else {
                            if old === oldPrimaryNav {
                                mOps.insert(Op(AFragmentTransaction.OP_UNSET_PRIMARY_NAV, old, true), at: opNum)
                                opNum += 1
                                oldPrimaryNav = nil
                            }
                            mOps.insert(Op(AFragmentTransaction.OP_REMOVE, old, true), at: opNum)
                            added.removeAll { $0 === old }
                            opNum += 1
                        }
                    }
                    i -= 1
                }
                if alreadyAdded {
                    mOps.remove(at: opNum)
                    opNum -= 1
                } else {
                    op.mCmd = AFragmentTransaction.OP_ADD
                    op.mFromExpandedOp = true
                    added.append(f)
                }
            case AFragmentTransaction.OP_SET_PRIMARY_NAV:
                mOps.insert(Op(AFragmentTransaction.OP_UNSET_PRIMARY_NAV, oldPrimaryNav, true), at: opNum)
                op.mFromExpandedOp = true
                opNum += 1
                oldPrimaryNav = op.mFragment
            default:
                break
            }
            opNum += 1
        }
        return oldPrimaryNav
    }

    func trackAddedFragmentsInPop(_ added: inout [AFragment], _ oldPrimaryNavIn: AFragment?) -> AFragment? {
        var oldPrimaryNav = oldPrimaryNavIn
        for op in mOps.reversed() {
            switch op.mCmd {
            case AFragmentTransaction.OP_ADD, AFragmentTransaction.OP_ATTACH:
                added.removeAll { $0 === op.mFragment }
            case AFragmentTransaction.OP_REMOVE, AFragmentTransaction.OP_DETACH:
                added.append(op.mFragment!)
            case AFragmentTransaction.OP_UNSET_PRIMARY_NAV:
                oldPrimaryNav = op.mFragment
            case AFragmentTransaction.OP_SET_PRIMARY_NAV:
                oldPrimaryNav = nil
            case AFragmentTransaction.OP_SET_MAX_LIFECYCLE:
                op.mCurrentMaxState = op.mOldMaxState
            default:
                break
            }
        }
        return oldPrimaryNav
    }
}

/// FragmentManager.OpGenerator: a pending action (a committed transaction or a pop request).
protocol KitOpGenerator: AnyObject {
    func generateOps(_ records: inout [AFragmentTransaction], _ isRecordPop: inout [Bool]) -> Bool
}

// MARK: - FragmentManager

/// androidx.fragment.app.FragmentManager. One per activity (supportFragmentManager) and one per fragment
/// (childFragmentManager). Container ids are the Android view id names (R.id.x).
final class AFragmentManager: CustomStringConvertible {
    static let POP_BACK_STACK_INCLUSIVE = 1

    /// FragmentManager.BackStackEntry.
    protocol BackStackEntry: AnyObject {
        func getId() -> Int
        func getName() -> String?
    }

    /// FragmentManager.OnBackStackChangedListener.
    final class OnBackStackChangedListener {
        let block: () -> Void
        init(_ block: @escaping () -> Void) { self.block = block }
        func onBackStackChanged() { block() }
    }

    private var mPendingActions: [KitOpGenerator] = []
    private var mExecutingActions = false
    let mFragmentStore = KitFragmentStore()
    var mBackStack: [AFragmentTransaction] = []
    private var mBackStackIndex = 0
    var mBackStackChangeListeners: [OnBackStackChangedListener] = []
    private var mOnAttachListeners: [(AFragmentManager, AFragment) -> Void] = []

    var mCurState = AFragment.INITIALIZING
    private(set) var mHost: AActivity?
    private var mContainer: KitFragmentContainer?
    private(set) var mParent: AFragment?
    private(set) var mPrimaryNav: AFragment?
    private var mOnBackPressedDispatcher: AOnBackPressedDispatcher?
    private lazy var mOnBackPressedCallback: AOnBackPressedCallback = AOnBackPressedCallback(false) { [weak self] _ in
        self?.handleOnBackPressed()
    }
    private var mStateSaved = false
    private var mStopped = false
    private(set) var isDestroyed = false
    private var mHavePendingDeferredStart = false
    private var mTmpRecords: [AFragmentTransaction] = []
    private var mTmpIsPop: [Bool] = []
    /// The host's main-thread handler (FragmentHostCallback.getHandler()).
    private let mHandler = AHandler(ALooper.getMainLooper())
    private lazy var mExecCommit = ARunnable { [weak self] in
        guard let self = self else { return }
        _ = self.execPendingActions(true)
    }
    private lazy var mConfigurationListenerOwner = KitListenerOwner()

    init() {}

    var description: String {
        var s = "FragmentManager{\(String(UInt(bitPattern: ObjectIdentifier(self).hashValue), radix: 16)) in "
        if let p = mParent { s += "\(p)" } else if let h = mHost { s += "\(type(of: h))" } else { s += "null" }
        return s + "}"
    }

    // MARK: Public API

    func beginTransaction() -> AFragmentTransaction { AFragmentTransaction(self) }

    /// executePendingTransactions(): runs the committed transactions now.
    @discardableResult
    func executePendingTransactions() -> Bool {
        execPendingActions(true)
    }

    func popBackStack() { enqueueAction(KitPopBackStackState(self, nil, -1, 0), false) }

    @discardableResult
    func popBackStackImmediate() -> Bool { popBackStackImmediate(nil, -1, 0) }

    func popBackStack(_ name: String?, _ flags: Int) { enqueueAction(KitPopBackStackState(self, name, -1, flags), false) }

    @discardableResult
    func popBackStackImmediate(_ name: String?, _ flags: Int) -> Bool { popBackStackImmediate(name, -1, flags) }

    func popBackStack(_ id: Int, _ flags: Int) {
        precondition(id >= 0, "Bad id: \(id)")
        enqueueAction(KitPopBackStackState(self, nil, id, flags), false)
    }

    @discardableResult
    func popBackStackImmediate(_ id: Int, _ flags: Int) -> Bool {
        precondition(id >= 0, "Bad id: \(id)")
        return popBackStackImmediate(nil, id, flags)
    }

    private func popBackStackImmediate(_ name: String?, _ id: Int, _ flags: Int) -> Bool {
        execPendingActions(false)
        ensureExecReady(true)
        if let primary = mPrimaryNav, id < 0, name == nil {
            if primary.childFragmentManager.popBackStackImmediate() { return true }
        }
        let executePop = popBackStackState(&mTmpRecords, &mTmpIsPop, name, id, flags)
        if executePop {
            mExecutingActions = true
            removeRedundantOperationsAndExecute(&mTmpRecords, &mTmpIsPop)
            cleanupExec()
        }
        updateOnBackPressedCallbackEnabled()
        doPendingDeferredStart()
        mFragmentStore.burpActive()
        return executePop
    }

    var backStackEntryCount: Int { mBackStack.count }
    func getBackStackEntryCount() -> Int { mBackStack.count }
    func getBackStackEntryAt(_ index: Int) -> BackStackEntry { mBackStack[index] }

    func addOnBackStackChangedListener(_ listener: OnBackStackChangedListener) { mBackStackChangeListeners.append(listener) }
    func removeOnBackStackChangedListener(_ listener: OnBackStackChangedListener) {
        mBackStackChangeListeners.removeAll { $0 === listener }
    }

    /// FragmentOnAttachListener.
    func addFragmentOnAttachListener(_ listener: @escaping (AFragmentManager, AFragment) -> Void) {
        mOnAttachListeners.append(listener)
    }

    func dispatchOnAttachFragment(_ fragment: AFragment) {
        for l in mOnAttachListeners { l(self, fragment) }
    }

    /// getFragments(): the added fragments, in the order they were added/attached.
    var fragments: [AFragment] { mFragmentStore.getFragments() }
    func getFragments() -> [AFragment] { fragments }

    func findFragmentById(_ id: String) -> AFragment? { mFragmentStore.findFragmentById(id) }
    func findFragmentByTag(_ tag: String?) -> AFragment? { mFragmentStore.findFragmentByTag(tag) }
    func findFragmentByWho(_ who: String) -> AFragment? { mFragmentStore.findFragmentByWho(who) }
    func findActiveFragment(_ who: String) -> AFragment? { mFragmentStore.findActiveFragment(who) }

    /// isStateSaved(): true after the host was stopped (mStopped) until it starts again.
    var isStateSaved: Bool { mStateSaved || mStopped }
    func isStateAtLeast(_ state: Int) -> Bool { mCurState >= state }
    var primaryNavigationFragment: AFragment? { mPrimaryNav }
    func getPrimaryNavigationFragment() -> AFragment? { mPrimaryNav }

    // MARK: Host attachment

    func getHost() -> AActivity? { mHost }
    func getParent() -> AFragment? { mParent }
    func getContainer() -> KitFragmentContainer? { mContainer }

    /// attachController(host, container, parent). The activity's own FragmentManager uses the activity window as
    /// its container.
    func attachController(_ host: AActivity, _ parent: AFragment?) {
        attachController(host, KitFragmentContainer(findViewById: { [weak host] id in host?.findViewById(id) as AView? },
                                                    hasView: { true }), parent)
    }

    func attachController(_ host: AActivity, _ container: KitFragmentContainer, _ parent: AFragment?) {
        precondition(mHost == nil, "Already attached")
        mHost = host
        mContainer = container
        mParent = parent
        if let p = parent {
            addFragmentOnAttachListener { _, fragment in p.onAttachFragment(fragment) }
        }
        if mParent != nil {
            updateOnBackPressedCallbackEnabled()
        }
        let dispatcher = host.onBackPressedDispatcher
        mOnBackPressedDispatcher = dispatcher
        let owner: ALifecycleOwner = parent ?? KitFragmentHostOwner(host)
        dispatcher.addCallback(owner, mOnBackPressedCallback)
        host.addOnConfigurationChangedListener(mConfigurationListenerOwner) { [weak self] newConfig in
            guard let self = self else { return }
            if self.isParentAdded() { self.dispatchConfigurationChanged(newConfig, false) }
        }
    }

    // MARK: Back handling

    private func updateOnBackPressedCallbackEnabled() {
        if !mPendingActions.isEmpty {
            mOnBackPressedCallback.isEnabled = true
            return
        }
        mOnBackPressedCallback.isEnabled = backStackEntryCount > 0 && isPrimaryNavigation(mParent)
    }

    func isPrimaryNavigation(_ parent: AFragment?) -> Bool {
        guard let parent = parent else { return true }
        guard let parentFragmentManager = parent.mFragmentManager else { return false }
        return parent === parentFragmentManager.primaryNavigationFragment
            && isPrimaryNavigation(parentFragmentManager.mParent)
    }

    func isParentHidden(_ parent: AFragment?) -> Bool {
        guard let parent = parent else { return false }
        return parent.isHidden
    }

    private func handleOnBackPressed() {
        execPendingActions(true)
        if mOnBackPressedCallback.isEnabled {
            popBackStackImmediate()
        } else {
            mOnBackPressedDispatcher?.onBackPressed()
        }
    }

    // MARK: State machine

    func moveToState(_ newState: Int, _ always: Bool) {
        precondition(mHost != nil || newState == AFragment.INITIALIZING, "No activity")
        if !always && newState == mCurState { return }
        mCurState = newState
        mFragmentStore.moveToExpectedState()
        startPendingDeferredFragments()
    }

    private func startPendingDeferredFragments() {
        for fsm in mFragmentStore.getActiveFragmentStateManagers() {
            performPendingDeferredStart(fsm)
        }
    }

    func performPendingDeferredStart(_ fsm: KitFragmentStateManager) {
        let f = fsm.fragment
        if f.mDeferStart {
            if mExecutingActions {
                mHavePendingDeferredStart = true
                return
            }
            f.mDeferStart = false
            fsm.moveToExpectedState()
        }
    }

    func createOrGetFragmentStateManager(_ f: AFragment) -> KitFragmentStateManager {
        if let existing = mFragmentStore.getFragmentStateManager(f.mWho) { return existing }
        let fsm = KitFragmentStateManager(mFragmentStore, f)
        fsm.setFragmentManagerState(mCurState)
        return fsm
    }

    @discardableResult
    func addFragment(_ fragment: AFragment) -> KitFragmentStateManager {
        let fsm = createOrGetFragmentStateManager(fragment)
        fragment.mFragmentManager = self
        mFragmentStore.makeActive(fsm)
        if !fragment.mDetached {
            mFragmentStore.addFragment(fragment)
            fragment.mRemoving = false
            if fragment.mView == nil {
                fragment.mHiddenChanged = false
            }
        }
        return fsm
    }

    func removeFragment(_ fragment: AFragment) {
        let inactive = !fragment.isInBackStack()
        if !fragment.mDetached || inactive {
            mFragmentStore.removeFragment(fragment)
            fragment.mRemoving = true
        }
    }

    func hideFragment(_ fragment: AFragment) {
        if !fragment.mHidden {
            fragment.mHidden = true
            fragment.mHiddenChanged = !fragment.mHiddenChanged
        }
    }

    func showFragment(_ fragment: AFragment) {
        if fragment.mHidden {
            fragment.mHidden = false
            fragment.mHiddenChanged = !fragment.mHiddenChanged
        }
    }

    func detachFragment(_ fragment: AFragment) {
        if !fragment.mDetached {
            fragment.mDetached = true
            if fragment.mAdded {
                mFragmentStore.removeFragment(fragment)
            }
        }
    }

    func attachFragment(_ fragment: AFragment) {
        if fragment.mDetached {
            fragment.mDetached = false
            if !fragment.mAdded {
                mFragmentStore.addFragment(fragment)
            }
        }
    }

    func setPrimaryNavigationFragment(_ f: AFragment?) {
        if let f = f {
            precondition(f === findActiveFragment(f.mWho) && (f.mHost == nil || f.mFragmentManager === self),
                         "Fragment \(f) is not an active fragment of FragmentManager \(self)")
        }
        let previous = mPrimaryNav
        mPrimaryNav = f
        dispatchParentPrimaryNavigationFragmentChanged(previous)
        dispatchParentPrimaryNavigationFragmentChanged(mPrimaryNav)
    }

    private func dispatchParentPrimaryNavigationFragmentChanged(_ f: AFragment?) {
        if let f = f, f === findActiveFragment(f.mWho) {
            f.performPrimaryNavigationFragmentChanged()
        }
    }

    func dispatchPrimaryNavigationFragmentChanged() {
        updateOnBackPressedCallbackEnabled()
        dispatchParentPrimaryNavigationFragmentChanged(mPrimaryNav)
    }

    func setMaxLifecycle(_ f: AFragment, _ state: ALifecycle.State) {
        precondition(f === findActiveFragment(f.mWho) && (f.mHost == nil || f.mFragmentManager === self),
                     "Fragment \(f) is not an active fragment of FragmentManager \(self)")
        f.mMaxState = state
    }

    // MARK: Pending actions

    func enqueueAction(_ action: KitOpGenerator, _ allowStateLoss: Bool) {
        if mHost == nil {
            if allowStateLoss { return }   // not attached: the transaction is dropped
            preconditionFailure(isDestroyed ? "FragmentManager has been destroyed"
                                            : "FragmentManager has not been attached to a host.")
        }
        // Android throws "Can not perform this action after onSaveInstanceState" here when isStateSaved and
        // !allowStateLoss. iOS never saves state for recreation, so the action is executed (no crash).
        mPendingActions.append(action)
        scheduleCommit()
    }

    private func scheduleCommit() {
        if mPendingActions.count == 1 {
            mHandler.removeCallbacks(mExecCommit)
            mHandler.post(mExecCommit)
            updateOnBackPressedCallbackEnabled()
        }
    }

    func allocBackStackIndex() -> Int {
        let i = mBackStackIndex
        mBackStackIndex += 1
        return i
    }

    private func ensureExecReady(_ allowStateLoss: Bool) {
        precondition(!mExecutingActions, "FragmentManager is already executing transactions")
        if mHost == nil {
            preconditionFailure(isDestroyed ? "FragmentManager has been destroyed"
                                            : "FragmentManager has not been attached to a host.")
        }
        precondition(Thread.isMainThread, "Must be called from main thread of fragment host")
    }

    func execSingleAction(_ action: KitOpGenerator, _ allowStateLoss: Bool) {
        if allowStateLoss && (mHost == nil || isDestroyed) { return }
        ensureExecReady(allowStateLoss)
        if action.generateOps(&mTmpRecords, &mTmpIsPop) {
            mExecutingActions = true
            removeRedundantOperationsAndExecute(&mTmpRecords, &mTmpIsPop)
            cleanupExec()
        }
        updateOnBackPressedCallbackEnabled()
        doPendingDeferredStart()
        mFragmentStore.burpActive()
    }

    private func cleanupExec() {
        mExecutingActions = false
        mTmpIsPop.removeAll()
        mTmpRecords.removeAll()
    }

    @discardableResult
    func execPendingActions(_ allowStateLoss: Bool) -> Bool {
        ensureExecReady(allowStateLoss)
        var didSomething = false
        while generateOpsForPendingActions(&mTmpRecords, &mTmpIsPop) {
            mExecutingActions = true
            removeRedundantOperationsAndExecute(&mTmpRecords, &mTmpIsPop)
            cleanupExec()
            didSomething = true
        }
        updateOnBackPressedCallbackEnabled()
        doPendingDeferredStart()
        mFragmentStore.burpActive()
        return didSomething
    }

    private func generateOpsForPendingActions(_ records: inout [AFragmentTransaction], _ isPop: inout [Bool]) -> Bool {
        if mPendingActions.isEmpty { return false }
        var didSomething = false
        let actions = mPendingActions
        // Whether generateOps succeeds or not, the pending actions are cleared (Android clears them in finally).
        mPendingActions.removeAll()
        mHandler.removeCallbacks(mExecCommit)
        for action in actions {
            if action.generateOps(&records, &isPop) { didSomething = true }
        }
        return didSomething
    }

    private func removeRedundantOperationsAndExecute(_ records: inout [AFragmentTransaction], _ isRecordPop: inout [Bool]) {
        if records.isEmpty { return }
        precondition(records.count == isRecordPop.count, "Internal error with the back stack records")
        let numRecords = records.count
        var startIndex = 0
        var recordNum = 0
        while recordNum < numRecords {
            let canReorder = records[recordNum].mReorderingAllowed
            if !canReorder {
                // execute all previous transactions
                if startIndex != recordNum {
                    executeOpsTogether(records, isRecordPop, startIndex, recordNum)
                }
                // execute all pop operations that don't allow reordering together or one add operation
                var reorderingEnd = recordNum + 1
                if isRecordPop[recordNum] {
                    while reorderingEnd < numRecords && isRecordPop[reorderingEnd] && !records[reorderingEnd].mReorderingAllowed {
                        reorderingEnd += 1
                    }
                }
                executeOpsTogether(records, isRecordPop, recordNum, reorderingEnd)
                startIndex = reorderingEnd
                recordNum = reorderingEnd - 1
            }
            recordNum += 1
        }
        if startIndex != numRecords {
            executeOpsTogether(records, isRecordPop, startIndex, numRecords)
        }
    }

    private func executeOpsTogether(_ records: [AFragmentTransaction], _ isRecordPop: [Bool], _ startIndex: Int, _ endIndex: Int) {
        let allowReordering = records[startIndex].mReorderingAllowed
        var addToBackStack = false
        var tmpAdded = mFragmentStore.getFragments()
        var oldPrimaryNav = getPrimaryNavigationFragment()
        for recordNum in startIndex..<endIndex {
            let record = records[recordNum]
            if !isRecordPop[recordNum] {
                oldPrimaryNav = record.expandOps(&tmpAdded, oldPrimaryNav)
            } else {
                oldPrimaryNav = record.trackAddedFragmentsInPop(&tmpAdded, oldPrimaryNav)
            }
            addToBackStack = addToBackStack || record.mAddToBackStack
        }
        tmpAdded.removeAll()

        if !allowReordering && mCurState >= AFragment.CREATED {
            // When reordering isn't allowed, we may be operating on Fragments that haven't been made active
            for index in startIndex..<endIndex {
                for op in records[index].mOps {
                    if let fragment = op.mFragment, fragment.mFragmentManager != nil {
                        let fsm = createOrGetFragmentStateManager(fragment)
                        mFragmentStore.makeActive(fsm)
                    }
                }
            }
        }
        AFragmentManager.executeOps(records, isRecordPop, startIndex, endIndex)

        // The last operation determines the overall direction.
        var isPop = isRecordPop[endIndex - 1]

        // Ensure that Fragments directly affected by operations are moved to their expected state in operation order
        for index in startIndex..<endIndex {
            let record = records[index]
            if isPop {
                for op in record.mOps.reversed() {
                    if let fragment = op.mFragment {
                        createOrGetFragmentStateManager(fragment).moveToExpectedState()
                    }
                }
            } else {
                for op in record.mOps {
                    if let fragment = op.mFragment {
                        createOrGetFragmentStateManager(fragment).moveToExpectedState()
                    }
                }
            }
        }
        // And only then do we move all other fragments to the current state
        moveToState(mCurState, true)
        for controller in collectChangedControllers(records, startIndex, endIndex) {
            controller.markPostponedState()
            controller.executePendingOperations()
        }
        for recordNum in startIndex..<endIndex {
            let record = records[recordNum]
            isPop = isRecordPop[recordNum]
            if isPop && record.mIndex >= 0 {
                record.mIndex = -1
            }
            record.runOnCommitRunnables()
        }
        if addToBackStack {
            reportBackStackChanged()
        }
    }

    private func collectChangedControllers(_ records: [AFragmentTransaction], _ startIndex: Int, _ endIndex: Int) -> [KitSpecialEffectsController] {
        var controllers: [KitSpecialEffectsController] = []
        for index in startIndex..<endIndex {
            for op in records[index].mOps {
                if let container = op.mFragment?.mContainer {
                    let c = KitSpecialEffectsController.getOrCreateController(container)
                    if !controllers.contains(where: { $0 === c }) { controllers.append(c) }
                }
            }
        }
        return controllers
    }

    private static func executeOps(_ records: [AFragmentTransaction], _ isRecordPop: [Bool], _ startIndex: Int, _ endIndex: Int) {
        for i in startIndex..<endIndex {
            let record = records[i]
            if isRecordPop[i] {
                record.bumpBackStackNesting(-1)
                record.executePopOps()
            } else {
                record.bumpBackStackNesting(1)
                record.executeOps()
            }
        }
    }

    private func collectAllSpecialEffectsController() -> [KitSpecialEffectsController] {
        var controllers: [KitSpecialEffectsController] = []
        for fsm in mFragmentStore.getActiveFragmentStateManagers() {
            if let container = fsm.fragment.mContainer {
                let c = KitSpecialEffectsController.getOrCreateController(container)
                if !controllers.contains(where: { $0 === c }) { controllers.append(c) }
            }
        }
        return controllers
    }

    private func endAnimatingAwayFragments() {
        for c in collectAllSpecialEffectsController() { c.forceCompleteAllOperations() }
    }

    private func doPendingDeferredStart() {
        if mHavePendingDeferredStart {
            mHavePendingDeferredStart = false
            startPendingDeferredFragments()
        }
    }

    private func reportBackStackChanged() {
        var i = 0
        while i < mBackStackChangeListeners.count {
            mBackStackChangeListeners[i].onBackStackChanged()
            i += 1
        }
    }

    func addBackStackState(_ state: AFragmentTransaction) { mBackStack.append(state) }

    func popBackStackState(_ records: inout [AFragmentTransaction], _ isRecordPop: inout [Bool],
                           _ name: String?, _ id: Int, _ flags: Int) -> Bool {
        let index = findBackStackIndex(name, id, (flags & AFragmentManager.POP_BACK_STACK_INCLUSIVE) != 0)
        if index < 0 { return false }
        var i = mBackStack.count - 1
        while i >= index {
            records.append(mBackStack.remove(at: i))
            isRecordPop.append(true)
            i -= 1
        }
        return true
    }

    private func findBackStackIndex(_ name: String?, _ id: Int, _ inclusive: Bool) -> Int {
        if mBackStack.isEmpty { return -1 }
        if name == nil && id < 0 {
            return inclusive ? 0 : mBackStack.count - 1
        }
        var index = mBackStack.count - 1
        while index >= 0 {
            let bss = mBackStack[index]
            if let n = name, n == bss.getName() { break }
            if id >= 0 && id == bss.mIndex { break }
            index -= 1
        }
        if index < 0 { return index }
        if inclusive {
            // Consume all following entries that match.
            while index > 0 {
                let bss = mBackStack[index - 1]
                if (name != nil && name == bss.getName()) || (id >= 0 && id == bss.mIndex) {
                    index -= 1
                    continue
                }
                break
            }
        } else if index == mBackStack.count - 1 {
            return -1
        } else {
            index += 1
        }
        return index
    }

    // MARK: Host lifecycle dispatch

    func noteStateNotSaved() {
        if mHost == nil { return }
        mStateSaved = false
        mStopped = false
        for fragment in mFragmentStore.getFragments() {
            fragment.noteStateNotSaved()
        }
    }

    func dispatchAttach() {
        mStateSaved = false
        mStopped = false
        dispatchStateChange(AFragment.ATTACHED)
    }

    func dispatchCreate() {
        mStateSaved = false
        mStopped = false
        dispatchStateChange(AFragment.CREATED)
    }

    func dispatchViewCreated() {
        dispatchStateChange(AFragment.VIEW_CREATED)
    }

    func dispatchActivityCreated() {
        mStateSaved = false
        mStopped = false
        dispatchStateChange(AFragment.ACTIVITY_CREATED)
    }

    func dispatchStart() {
        mStateSaved = false
        mStopped = false
        dispatchStateChange(AFragment.STARTED)
    }

    func dispatchResume() {
        mStateSaved = false
        mStopped = false
        dispatchStateChange(AFragment.RESUMED)
    }

    func dispatchPause() {
        dispatchStateChange(AFragment.STARTED)
    }

    func dispatchStop() {
        mStopped = true
        dispatchStateChange(AFragment.ACTIVITY_CREATED)
    }

    func dispatchDestroyView() {
        dispatchStateChange(AFragment.CREATED)
    }

    func dispatchDestroy() {
        isDestroyed = true
        execPendingActions(true)
        endAnimatingAwayFragments()
        dispatchStateChange(AFragment.INITIALIZING)
        mHost?.removeOnConfigurationChangedListener(mConfigurationListenerOwner)
        mHost = nil
        mContainer = nil
        mParent = nil
        if mOnBackPressedDispatcher != nil {
            mOnBackPressedCallback.remove()
            mOnBackPressedDispatcher = nil
        }
    }

    private func dispatchStateChange(_ nextState: Int) {
        mExecutingActions = true
        mFragmentStore.dispatchStateChange(nextState)
        moveToState(nextState, false)
        for controller in collectAllSpecialEffectsController() {
            controller.forceCompleteAllOperations()
        }
        mExecutingActions = false
        execPendingActions(true)
    }

    func dispatchConfigurationChanged(_ newConfig: AConfiguration, _ recursive: Bool) {
        for f in mFragmentStore.getFragments() {
            f.performConfigurationChanged(newConfig)
            if recursive {
                f.mChildFragmentManager.dispatchConfigurationChanged(newConfig, true)
            }
        }
    }

    func dispatchLowMemory(_ recursive: Bool) {
        for f in mFragmentStore.getFragments() {
            f.performLowMemory()
            if recursive { f.mChildFragmentManager.dispatchLowMemory(true) }
        }
    }

    func dispatchOnHiddenChanged() {
        for fragment in mFragmentStore.getActiveFragments() {
            fragment.onHiddenChanged(fragment.isHidden)
            fragment.mChildFragmentManager.dispatchOnHiddenChanged()
        }
    }

    private func isParentAdded() -> Bool {
        guard let parent = mParent else { return true }
        return parent.isAdded && (parent.mFragmentManager?.isParentAdded() ?? false)
    }

    /// FragmentActivity.markState: started fragment (and fragment view) lifecycles drop to `state` (onStop).
    func markState(_ state: ALifecycle.State) -> Bool {
        var hadNotMarked = false
        for fragment in fragments {
            if fragment.host != nil {
                hadNotMarked = fragment.childFragmentManager.markState(state) || hadNotMarked
            }
            if let owner = fragment.mViewLifecycleOwner, owner.lifecycle.currentState.isAtLeast(.STARTED) {
                owner.setCurrentState(state)
                hadNotMarked = true
            }
            if fragment.mLifecycleRegistry.currentState.isAtLeast(.STARTED) {
                fragment.mLifecycleRegistry.setCurrentState(state)
                hadNotMarked = true
            }
        }
        return hadNotMarked
    }

    /// The Fragment owning `view` (the nearest ancestor that is a fragment's root view), FragmentManager.findFragment.
    static func findViewFragment(_ view: AView?) -> AFragment? {
        var v = view
        while let current = v {
            if let f = current.getTag(KitSpecialEffectsController.FRAGMENT_CONTAINER_VIEW_TAG) as? AFragment { return f }
            v = current.parentGroup
        }
        return nil
    }

    static func findFragment<F: AFragment>(_ view: AView) -> F {
        guard let f = findViewFragment(view) as? F else {
            preconditionFailure("View \(view) does not have a Fragment set")
        }
        return f
    }
}

/// The LifecycleOwner of an activity's fragment host (FragmentActivity.HostCallbacks: mFragmentLifecycleRegistry).
private final class KitFragmentHostOwner: ALifecycleOwner {
    private weak var activity: AActivity?
    init(_ activity: AActivity) { self.activity = activity }
    var lifecycle: ALifecycle { activity?.fragmentHostLifecycle ?? ALifecycleRegistry(self) }
}

/// Identity token for listener registration.
final class KitListenerOwner {}

/// FragmentManager.PopBackStackState.
private final class KitPopBackStackState: KitOpGenerator {
    private unowned let manager: AFragmentManager
    let mName: String?
    let mId: Int
    let mFlags: Int

    init(_ manager: AFragmentManager, _ name: String?, _ id: Int, _ flags: Int) {
        self.manager = manager
        mName = name
        mId = id
        mFlags = flags
    }

    func generateOps(_ records: inout [AFragmentTransaction], _ isRecordPop: inout [Bool]) -> Bool {
        if let primary = manager.primaryNavigationFragment, mId < 0, mName == nil {
            if primary.childFragmentManager.popBackStackImmediate() {
                return false
            }
        }
        return manager.popBackStackState(&records, &isRecordPop, mName, mId, mFlags)
    }
}

// MARK: - FragmentStore

/// androidx FragmentStore: the added fragments (in add order) and the active fragment state managers (insertion
/// order here; Android iterates a HashMap keyed by random UUIDs, so any order is a valid Android order).
final class KitFragmentStore {
    private var mAdded: [AFragment] = []
    private var mActiveKeys: [String] = []
    private var mActive: [String: KitFragmentStateManager?] = [:]

    func makeActive(_ newlyActive: KitFragmentStateManager) {
        let f = newlyActive.fragment
        if containsActiveFragment(f.mWho) { return }
        if mActive[f.mWho] == nil { mActiveKeys.append(f.mWho) }
        mActive[f.mWho] = .some(newlyActive)
    }

    func addFragment(_ fragment: AFragment) {
        precondition(!mAdded.contains(where: { $0 === fragment }), "Fragment already added: \(fragment)")
        mAdded.append(fragment)
        fragment.mAdded = true
    }

    func dispatchStateChange(_ state: Int) {
        for fsm in activeValues() { fsm.setFragmentManagerState(state) }
    }

    func moveToExpectedState() {
        // Must add them in the proper order. mActive fragments may be out of order
        for f in mAdded {
            if let fsm = mActive[f.mWho] ?? nil {
                fsm.moveToExpectedState()
            }
        }
        // Now iterate through all active fragments, including removed and detached ones.
        for fsm in activeValues() {
            fsm.moveToExpectedState()
            let f = fsm.fragment
            let beingRemoved = f.mRemoving && !f.isInBackStack()
            if beingRemoved {
                makeInactive(fsm)
            }
        }
    }

    func removeFragment(_ fragment: AFragment) {
        mAdded.removeAll { $0 === fragment }
        fragment.mAdded = false
    }

    func makeInactive(_ newlyInactive: KitFragmentStateManager) {
        let f = newlyInactive.fragment
        guard let current = mActive[f.mWho] ?? nil, current === newlyInactive else { return }
        // Don't remove yet. That happens in burpActive().
        mActive[f.mWho] = .some(nil)
    }

    func burpActive() {
        mActiveKeys.removeAll { key in
            if case .some(.none) = mActive[key] {
                mActive.removeValue(forKey: key)
                return true
            }
            return false
        }
    }

    private func activeValues() -> [KitFragmentStateManager] {
        mActiveKeys.compactMap { mActive[$0] ?? nil }
    }

    func getActiveFragmentStateManagers() -> [KitFragmentStateManager] { activeValues() }

    func getFragments() -> [AFragment] { mAdded }

    func getActiveFragments() -> [AFragment] { activeValues().map { $0.fragment } }

    var activeFragmentCount: Int { mActiveKeys.count }

    func findFragmentById(_ id: String) -> AFragment? {
        for f in mAdded.reversed() where f.mFragmentId == id { return f }
        for fsm in activeValues() where fsm.fragment.mFragmentId == id { return fsm.fragment }
        return nil
    }

    func findFragmentByTag(_ tag: String?) -> AFragment? {
        guard let tag = tag else { return nil }
        for f in mAdded.reversed() where f.mTag == tag { return f }
        for fsm in activeValues() where fsm.fragment.mTag == tag { return fsm.fragment }
        return nil
    }

    func containsActiveFragment(_ who: String) -> Bool { (mActive[who] ?? nil) != nil }

    func getFragmentStateManager(_ who: String) -> KitFragmentStateManager? { mActive[who] ?? nil }

    func findFragmentByWho(_ who: String) -> AFragment? {
        for fsm in activeValues() {
            if let f = fsm.fragment.findFragmentByWho(who) { return f }
        }
        return nil
    }

    func findActiveFragment(_ who: String) -> AFragment? { (mActive[who] ?? nil)?.fragment }

    /// The index in the container for a fragment's view, by the add order of the fragments sharing the container.
    func findFragmentIndexInContainer(_ f: AFragment) -> Int {
        guard let container = f.mContainer else { return -1 }
        guard let fragmentIndex = mAdded.firstIndex(where: { $0 === f }) else { return -1 }
        var i = fragmentIndex - 1
        while i >= 0 {
            let under = mAdded[i]
            if under.mContainer === container, let v = under.mView {
                return container.indexOfChild(v) + 1
            }
            i -= 1
        }
        i = fragmentIndex + 1
        while i < mAdded.count {
            let over = mAdded[i]
            if over.mContainer === container, let v = over.mView {
                return container.indexOfChild(v)
            }
            i += 1
        }
        return -1
    }
}

// MARK: - FragmentStateManager

/// androidx FragmentStateManager: moves one fragment through its states towards the expected state.
final class KitFragmentStateManager {
    private let mFragmentStore: KitFragmentStore
    let fragment: AFragment
    private var mMovingToState = false
    private var mFragmentManagerState = AFragment.INITIALIZING

    init(_ fragmentStore: KitFragmentStore, _ fragment: AFragment) {
        mFragmentStore = fragmentStore
        self.fragment = fragment
    }

    func setFragmentManagerState(_ state: Int) { mFragmentManagerState = state }

    func computeExpectedState() -> Int {
        let f = fragment
        if f.mFragmentManager == nil { return f.mState }
        var maxState = mFragmentManagerState
        switch f.mMaxState {
        case .RESUMED: break
        case .STARTED: maxState = min(maxState, AFragment.STARTED)
        case .CREATED: maxState = min(maxState, AFragment.CREATED)
        case .INITIALIZED: maxState = min(maxState, AFragment.ATTACHED)
        default: maxState = min(maxState, AFragment.INITIALIZING)
        }
        // Fragments that are not currently added will sit in the CREATED state.
        if !f.mAdded {
            maxState = min(maxState, AFragment.CREATED)
        }
        var awaitingEffect: KitFragmentOperation.LifecycleImpact? = nil
        if let container = f.mContainer {
            awaitingEffect = KitSpecialEffectsController.getOrCreateController(container).getAwaitingCompletionLifecycleImpact(self)
        }
        if awaitingEffect == .ADDING {
            maxState = min(maxState, AFragment.AWAITING_ENTER_EFFECTS)
        } else if awaitingEffect == .REMOVING {
            maxState = max(maxState, AFragment.AWAITING_EXIT_EFFECTS)
        } else if f.mRemoving {
            if f.isInBackStack() {
                maxState = min(maxState, AFragment.CREATED)
            } else {
                maxState = min(maxState, AFragment.INITIALIZING)
            }
        }
        if f.mDeferStart && f.mState < AFragment.STARTED {
            maxState = min(maxState, AFragment.ACTIVITY_CREATED)
        }
        if f.mTransitioning {
            maxState = max(maxState, AFragment.AWAITING_EXIT_EFFECTS)
        }
        return maxState
    }

    func moveToExpectedState() {
        if mMovingToState { return }
        mMovingToState = true
        defer { mMovingToState = false }
        let f = fragment
        var stateWasChanged = false
        while true {
            let newState = computeExpectedState()
            if newState == f.mState { break }
            stateWasChanged = true
            if newState > f.mState {
                // Moving upward
                let nextStep = f.mState + 1
                switch nextStep {
                case AFragment.ATTACHED:
                    attach()
                case AFragment.CREATED:
                    create()
                case AFragment.VIEW_CREATED:
                    createView()
                case AFragment.AWAITING_EXIT_EFFECTS:
                    activityCreated()
                case AFragment.ACTIVITY_CREATED:
                    if let view = f.mView, let container = f.mContainer {
                        let controller = KitSpecialEffectsController.getOrCreateController(container)
                        controller.enqueueAdd(KitFragmentOperation.State.from(view.visibility), self)
                    }
                    f.mState = AFragment.ACTIVITY_CREATED
                case AFragment.STARTED:
                    start()
                case AFragment.AWAITING_ENTER_EFFECTS:
                    f.mState = AFragment.AWAITING_ENTER_EFFECTS
                case AFragment.RESUMED:
                    resume()
                default:
                    break
                }
            } else {
                // Moving downward
                let nextStep = f.mState - 1
                switch nextStep {
                case AFragment.AWAITING_ENTER_EFFECTS:
                    pause()
                case AFragment.STARTED:
                    f.mState = AFragment.STARTED
                case AFragment.ACTIVITY_CREATED:
                    stop()
                case AFragment.AWAITING_EXIT_EFFECTS:
                    if f.mView != nil, let container = f.mContainer {
                        KitSpecialEffectsController.getOrCreateController(container).enqueueRemove(self)
                    }
                    f.mState = AFragment.AWAITING_EXIT_EFFECTS
                case AFragment.VIEW_CREATED:
                    f.mInLayout = false
                    f.mState = AFragment.VIEW_CREATED
                case AFragment.CREATED:
                    destroyFragmentView()
                    f.mState = AFragment.CREATED
                case AFragment.ATTACHED:
                    destroy()
                case AFragment.INITIALIZING:
                    detach()
                default:
                    break
                }
            }
        }
        if !stateWasChanged && f.mState == AFragment.INITIALIZING {
            // The fragment never got attached but must be cleaned up (removed before it was ever attached).
            if f.mRemoving && !f.isInBackStack() && !f.mBeingSaved {
                mFragmentStore.makeInactive(self)
                f.initState()
            }
        }
        if f.mHiddenChanged {
            if f.mView != nil, let container = f.mContainer {
                let controller = KitSpecialEffectsController.getOrCreateController(container)
                if f.mHidden {
                    controller.enqueueHide(self)
                } else {
                    controller.enqueueShow(self)
                }
            }
            f.mHiddenChanged = false
            f.onHiddenChanged(f.mHidden)
            f.mChildFragmentManager.dispatchOnHiddenChanged()
        }
    }

    func attach() {
        let f = fragment
        f.mHost = f.mFragmentManager!.getHost()
        f.mParentFragment = f.mFragmentManager!.getParent()
        f.performAttach()
    }

    func create() {
        let f = fragment
        if !f.mIsCreated {
            f.performCreate(nil)
        } else {
            f.mState = AFragment.CREATED
        }
    }

    func createView() {
        let f = fragment
        if f.mFromLayout { return }
        let layoutInflater = f.performGetLayoutInflater(nil)
        var container: AViewGroup? = nil
        if let c = f.mContainer {
            container = c
        } else if let containerId = f.mContainerId {
            // FragmentContainer.onFindViewById: the activity window or the parent fragment's view.
            guard let found = f.mFragmentManager!.getContainer()?.findViewById(containerId) else {
                preconditionFailure("java.lang.IllegalArgumentException: No view found for id \(containerId) for fragment \(f)")
            }
            guard let group = found as? AViewGroup else {
                preconditionFailure("java.lang.ClassCastException: the container \(containerId) of \(f) is not a ViewGroup")
            }
            container = group
        }
        f.mContainer = container
        f.performCreateView(layoutInflater, container, nil)
        if let view = f.mView {
            view.setTag(KitSpecialEffectsController.FRAGMENT_CONTAINER_VIEW_TAG, f)
            if container != nil {
                addViewToContainer()
            }
            if f.mHidden {
                view.visibility = AView.GONE
            }
            if view.isAttachedToWindow {
                AViewCompat.requestApplyInsets(view)
            } else {
                view.addOnAttachStateChangeListener(KitRequestInsetsOnAttach())
            }
            f.performViewCreated()
            let postOnViewCreatedVisibility = view.visibility
            f.mPostOnViewCreatedAlpha = view.alpha
            if f.mContainer != nil && postOnViewCreatedVisibility == AView.VISIBLE {
                // Android sets the view alpha to 0 until the enter effect starts; with no effects the add operation
                // restores it in the same pass (KitFragmentOperation.onStart), before anything is drawn.
                view.alpha = 0
            }
        }
        f.mState = AFragment.VIEW_CREATED
    }

    func activityCreated() {
        fragment.performActivityCreated(nil)
    }

    func start() {
        fragment.performStart()
    }

    func resume() {
        let f = fragment
        f.performResume()
        f.mSavedFragmentState = nil
    }

    func pause() {
        fragment.performPause()
    }

    func stop() {
        fragment.performStop()
    }

    func destroyFragmentView() {
        let f = fragment
        // In cases where we never got up to AWAITING_EXIT_EFFECTS, remove the view from the container manually.
        if let container = f.mContainer, let view = f.mView {
            container.removeView(view)
        }
        f.performDestroyView()
        f.mContainer = nil
        f.mView = nil
        // Set here to ensure that Observers are called after the Fragment's view is set to null
        f.mViewLifecycleOwner = nil
        f.mInLayout = false
    }

    func destroy() {
        let f = fragment
        // beingRemoved || FragmentManagerViewModel.shouldDestroy(f): always true, no fragment is retained (the
        // retained branch, which only moves the state to ATTACHED, cannot happen).
        f.performDestroy()
        mFragmentStore.makeInactive(self)
    }

    func detach() {
        let f = fragment
        f.performDetach()
        f.mState = AFragment.INITIALIZING
        f.mHost = nil
        f.mParentFragment = nil
        f.mFragmentManager = nil
        // beingRemoved || nonConfig.shouldDestroy(f): always true (no retained fragments).
        f.initState()
    }

    func addViewToContainer() {
        let f = fragment
        guard let container = f.mContainer, let view = f.mView else { return }
        let index = mFragmentStore.findFragmentIndexInContainer(f)
        if index < 0 {
            container.addView(view)
        } else {
            container.addView(view, index)
        }
    }
}

/// View.OnAttachStateChangeListener of FragmentStateManager.createView: requestApplyInsets once attached.
private final class KitRequestInsetsOnAttach: AOnAttachStateChangeListener {
    init() { super.init(nil, nil) }
    override func onViewAttachedToWindow(_ v: AView) {
        v.removeOnAttachStateChangeListener(self)
        AViewCompat.requestApplyInsets(v)
    }
}

// MARK: - SpecialEffectsController (no effects)

/// One add/remove/show/hide of a fragment view (SpecialEffectsController.Operation +
/// FragmentStateManagerOperation). The app sets no fragment animations or transitions, so every operation is
/// started, applied and completed in the same executePendingOperations pass, as androidx does when no effect exists.
final class KitFragmentOperation {
    enum State {
        case REMOVED, VISIBLE, GONE, INVISIBLE

        static func from(_ visibility: Int) -> State {
            switch visibility {
            case AView.VISIBLE: return .VISIBLE
            case AView.INVISIBLE: return .INVISIBLE
            case AView.GONE: return .GONE
            default: preconditionFailure("Unknown visibility \(visibility)")
            }
        }

        func applyState(_ view: AView, _ container: AViewGroup) {
            switch self {
            case .REMOVED:
                view.parentGroup?.removeView(view)
            case .VISIBLE:
                if view.parentGroup == nil { container.addView(view) }
                view.visibility = AView.VISIBLE
            case .GONE:
                view.visibility = AView.GONE
            case .INVISIBLE:
                view.visibility = AView.INVISIBLE
            }
        }
    }

    enum LifecycleImpact { case NONE, ADDING, REMOVING }

    var finalState: State
    var lifecycleImpact: LifecycleImpact
    let fsm: KitFragmentStateManager
    var fragment: AFragment { fsm.fragment }
    private var completionListeners: [() -> Void] = []
    private(set) var isCanceled = false
    private(set) var isComplete = false
    private(set) var isStarted = false
    var isAwaitingContainerChanges = true

    init(_ finalState: State, _ lifecycleImpact: LifecycleImpact, _ fsm: KitFragmentStateManager) {
        self.finalState = finalState
        self.lifecycleImpact = lifecycleImpact
        self.fsm = fsm
    }

    func cancel(_ container: AViewGroup) {
        isStarted = false
        if isCanceled { return }
        isCanceled = true
        complete()
    }

    func mergeWith(_ finalState: State, _ lifecycleImpact: LifecycleImpact) {
        switch lifecycleImpact {
        case .ADDING:
            if self.finalState == .REMOVED {
                self.finalState = .VISIBLE
                self.lifecycleImpact = .ADDING
                isAwaitingContainerChanges = true
            }
        case .REMOVING:
            self.finalState = .REMOVED
            self.lifecycleImpact = .REMOVING
            isAwaitingContainerChanges = true
        case .NONE:
            if self.finalState != .REMOVED {
                self.finalState = finalState
            }
        }
    }

    func addCompletionListener(_ listener: @escaping () -> Void) { completionListeners.append(listener) }

    func onStart() {
        if isStarted { return }
        isStarted = true
        if lifecycleImpact == .ADDING {
            let f = fragment
            guard let view = f.mView else { return }
            if view.parentGroup == nil {
                fsm.addViewToContainer()
                view.alpha = 0
            }
            if view.alpha == 0 && view.visibility == AView.VISIBLE {
                view.visibility = AView.INVISIBLE
            }
            view.alpha = f.mPostOnViewCreatedAlpha
        } else if lifecycleImpact == .REMOVING {
            fragment.mView?.clearFocus()
        }
    }

    func complete() {
        isStarted = false
        if isComplete { return }
        isComplete = true
        for listener in completionListeners { listener() }
        // FragmentStateManagerOperation.complete
        fragment.mTransitioning = false
        fsm.moveToExpectedState()
    }
}

/// SpecialEffectsController for one container view (shared by every FragmentManager using that container).
final class KitSpecialEffectsController {
    /// View tag keys (androidx R.id.special_effects_controller_view_tag / fragment_container_view_tag).
    static let SPECIAL_EFFECTS_CONTROLLER_VIEW_TAG = 0x7F0A_0F01
    static let FRAGMENT_CONTAINER_VIEW_TAG = 0x7F0A_0F02

    let container: AViewGroup
    private var pendingOperations: [KitFragmentOperation] = []
    private var runningOperations: [KitFragmentOperation] = []
    private var isContainerPostponed = false

    init(_ container: AViewGroup) { self.container = container }

    static func getOrCreateController(_ container: AViewGroup) -> KitSpecialEffectsController {
        if let c = container.getTag(SPECIAL_EFFECTS_CONTROLLER_VIEW_TAG) as? KitSpecialEffectsController { return c }
        let c = KitSpecialEffectsController(container)
        container.setTag(SPECIAL_EFFECTS_CONTROLLER_VIEW_TAG, c)
        return c
    }

    func getAwaitingCompletionLifecycleImpact(_ fsm: KitFragmentStateManager) -> KitFragmentOperation.LifecycleImpact? {
        let pending = findPendingOperation(fsm.fragment)?.lifecycleImpact
        let running = findRunningOperation(fsm.fragment)?.lifecycleImpact
        switch pending {
        case nil, .NONE?: return running
        default: return pending
        }
    }

    private func findPendingOperation(_ fragment: AFragment) -> KitFragmentOperation? {
        pendingOperations.first { $0.fragment === fragment && !$0.isCanceled }
    }

    private func findRunningOperation(_ fragment: AFragment) -> KitFragmentOperation? {
        runningOperations.first { $0.fragment === fragment && !$0.isCanceled }
    }

    func enqueueAdd(_ finalState: KitFragmentOperation.State, _ fsm: KitFragmentStateManager) { enqueue(finalState, .ADDING, fsm) }
    func enqueueShow(_ fsm: KitFragmentStateManager) { enqueue(.VISIBLE, .NONE, fsm) }
    func enqueueHide(_ fsm: KitFragmentStateManager) { enqueue(.GONE, .NONE, fsm) }
    func enqueueRemove(_ fsm: KitFragmentStateManager) { enqueue(.REMOVED, .REMOVING, fsm) }

    private func enqueue(_ finalState: KitFragmentOperation.State, _ lifecycleImpact: KitFragmentOperation.LifecycleImpact,
                         _ fsm: KitFragmentStateManager) {
        let existing = findPendingOperation(fsm.fragment)
            ?? ((fsm.fragment.mTransitioning || fsm.fragment.mRemoving) ? findRunningOperation(fsm.fragment) : nil)
        if let existing = existing {
            existing.mergeWith(finalState, lifecycleImpact)
            return
        }
        let operation = KitFragmentOperation(finalState, lifecycleImpact, fsm)
        pendingOperations.append(operation)
        // Ensure that we still run the applyState() call for pending operations
        operation.addCompletionListener { [weak self, unowned operation] in
            guard let self = self else { return }
            if self.pendingOperations.contains(where: { $0 === operation }), let view = operation.fragment.mView {
                operation.finalState.applyState(view, self.container)
            }
        }
        // Ensure that we remove the Operation from the list of operations when the operation is complete
        operation.addCompletionListener { [weak self, unowned operation] in
            self?.pendingOperations.removeAll { $0 === operation }
            self?.runningOperations.removeAll { $0 === operation }
        }
    }

    func markPostponedState() {
        updateFinalState()
        isContainerPostponed = false   // postponeEnterTransition is not used
    }

    func isPendingExecute() -> Bool { !pendingOperations.isEmpty }

    func executePendingOperations() {
        if isContainerPostponed { return }
        if !container.isAttachedToWindow {
            forceCompleteAllOperations()
            return
        }
        let currentlyRunning = runningOperations
        runningOperations.removeAll()
        for operation in currentlyRunning {
            operation.cancel(container)
            if !operation.isComplete { runningOperations.append(operation) }
        }
        if !pendingOperations.isEmpty {
            updateFinalState()
            let newPending = pendingOperations
            if newPending.isEmpty { return }
            pendingOperations.removeAll()
            runningOperations.append(contentsOf: newPending)
            // DefaultSpecialEffectsController.collectEffects: no animations or transitions -> no effects; the
            // container changes are applied when an operation completes synchronously.
            for operation in newPending {
                operation.addCompletionListener { [weak self, unowned operation] in self?.applyContainerChangesToOperation(operation) }
            }
            // processStart, then commitEffects (no effects: apply the container changes, then complete).
            for operation in newPending { operation.onStart() }
            for operation in newPending { applyContainerChangesToOperation(operation) }
            for operation in newPending { operation.complete() }
        }
    }

    private func applyContainerChangesToOperation(_ operation: KitFragmentOperation) {
        if operation.isAwaitingContainerChanges {
            if let view = operation.fragment.mView {
                operation.finalState.applyState(view, container)
            }
            operation.isAwaitingContainerChanges = false
        }
    }

    func forceCompleteAllOperations() {
        updateFinalState()
        for operation in pendingOperations { operation.onStart() }
        let running = runningOperations
        for operation in running { operation.cancel(container) }
        let pending = pendingOperations
        for operation in pending { operation.cancel(container) }
    }

    private func updateFinalState() {
        for operation in pendingOperations where operation.lifecycleImpact == .ADDING {
            guard let view = operation.fragment.mView else { continue }
            operation.mergeWith(KitFragmentOperation.State.from(view.visibility), .NONE)
        }
    }
}
