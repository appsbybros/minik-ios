import UIKit

// AndroidKit dialogs (DESIGN 4.5): android.content.DialogInterface, android.app.Dialog (with androidx.activity
// ComponentDialog / AppCompatDialog behaviour), android.app.AlertDialog and androidx.appcompat.app.AlertDialog (one
// AAlertDialog running a port of androidx AlertController, AlertDialogLayout, ButtonBarLayout and DialogTitle), and
// com.google.android.material.dialog.MaterialAlertDialogBuilder.
//
// Windows. A shown dialog is its own Android window: an overlay above its activity's content (and above earlier
// dialogs, so dialogs stack), holding the dim layer and the window, whose views run in their own AViewRoot. The
// window frame is computed like WindowManager: ViewRootImpl.measureHierarchy for WRAP_CONTENT sizes (first at
// config_prefDialogWidth, 320 dp on phones), DecorView's windowMinWidthMajor/Minor (95 % of the screen width in
// portrait on phones for alert dialogs), Gravity.apply + Gravity.applyDisplay inside the screen minus the system bars
// (the safe area), the soft keyboard panning the window up (windowSoftInputMode adjustPan). Touches follow Android:
// every touch on the screen goes to the topmost dialog window (modal); Dialog.dispatchTouchEvent gives it to the views,
// then Dialog.onTouchEvent cancels on an ACTION_UP outside the window (beyond the window touch slop) when the dialog is
// cancelable and closes on touch outside; MaterialAlertDialogBuilder's InsetDialogOnTouchListener also cancels on a
// touch in the transparent inset around its card. Window animations: Animation.Material.Dialog (framework dialogs),
// Animation.AppCompat.Dialog (androidx / Material alert dialogs), none for windowAnimations = 0. The dim layer and the
// window elevation shadow (16 dp) are drawn by the overlay.
//
// Looks. The app theme is Theme.MaterialComponents.DayNight; DESIGN 4.5 asks for the light variant even in iOS Dark
// Mode, so every dialog uses the light values of its Android theme:
// * framework android.app.AlertDialog (Theme.TripleShot's android:alertDialogTheme =
//   ThemeOverlay.MaterialComponents.Light.Dialog.Alert.Framework = Theme.Material.Light.Dialog.Alert with flush
//   Material text buttons): alert_dialog_material.xml, white surface with 2 dp corners inset 16 dp, title 20 sp,
//   message 16 sp, dim 0.6;
// * androidx.appcompat AlertDialog (ThemeOverlay.MaterialComponents.Dialog.Alert): abc_alert_dialog_material.xml, the
//   same metrics, AppCompat fade window animation;
// * MaterialAlertDialogBuilder (ThemeOverlay.MaterialComponents.MaterialAlertDialog): mtrl_alert_dialog.xml, colorSurface
//   card with 4 dp corners inset 24/80 dp, title Subtitle1 16 sp, message Body2 14 sp at 60 % black, buttons
//   TextButton.Dialog (8 dp start margin), dim 0.32.
// Typefaces: the theme's android:fontFamily="sans" wins over the text appearances (regular weight). Buttons are
// AButton(style: .TEXT_DIALOG) (colorPrimary #087E70, all caps). Choice lists use the Material check box / radio
// vectors tinted colorControlActivated (#FFC83D; teal #009688 in framework dialogs) and colorControlNormal.
//
// Strings: a String parameter is always literal text, whatever it spells; string resources (R.string.x,
// android.R.string.cancel) go through the explicit `res:` overloads (`setTitle(res:)`, `setPositiveButton(res:...)`),
// the Android @StringRes int overloads.
// Not ported (unused by the app): cursors and custom adapters, icons in buttons, OnKeyListener (no hardware keys),
// the title bar of a plain Dialog without FEATURE_NO_TITLE (the app always requests no title), scroll indicators.

// MARK: - DialogInterface

/// android.content.DialogInterface: the BUTTON_* constants, the listener types and cancel/dismiss. A class (not a
/// protocol) so that `ADialogInterface.BUTTON_POSITIVE` and `AAlertDialog.BUTTON_POSITIVE` both work, like Java's
/// inherited interface constants.
class ADialogInterface {
    static let BUTTON_POSITIVE = -1
    static let BUTTON_NEGATIVE = -2
    static let BUTTON_NEUTRAL = -3

    typealias OnClickListener = (_ dialog: ADialogInterface, _ which: Int) -> Void
    typealias OnMultiChoiceClickListener = (_ dialog: ADialogInterface, _ which: Int, _ isChecked: Bool) -> Void
    typealias OnCancelListener = (_ dialog: ADialogInterface) -> Void
    typealias OnDismissListener = (_ dialog: ADialogInterface) -> Void
    typealias OnShowListener = (_ dialog: ADialogInterface) -> Void

    init() {}

    func cancel() {}
    func dismiss() {}
}

/// android.view.ContextThemeWrapper: a context with a theme overlay. Dialogs built on it use that theme
/// (android.R.style.Theme_Material_Light_Dialog_Alert -> the framework alert look).
final class AContextThemeWrapper: AContext {
    let baseContext: AContext
    let themeResId: String

    init(_ base: AContext, _ themeResId: String) {
        baseContext = base
        self.themeResId = themeResId
    }

    func getBaseContext() -> AContext { baseContext }
}

/// Context helpers of the dialog layer.
enum KitContexts {
    /// The activity a context belongs to (an activity, or a ContextThemeWrapper around one).
    static func activity(_ context: AContext?) -> AActivity? {
        var c = context
        while let current = c {
            if let a = current as? AActivity { return a }
            if let w = current as? AContextThemeWrapper {
                c = w.baseContext
                continue
            }
            return nil
        }
        return nil
    }
}

// MARK: - Dialog themes

/// WindowManager.LayoutParams.windowAnimations styles of the dialog themes (0 = no animation).
enum KitWindowAnimations {
    static let NONE = 0
    /// @android:style/Animation.Material.Dialog: popup_enter_material (alpha + 20 dp rise, 220 ms) /
    /// popup_exit_material (alpha + 10 dp rise, 150 ms).
    static let MATERIAL_DIALOG = 1
    /// Animation.AppCompat.Dialog: abc_popup_enter / abc_popup_exit (alpha, 150 ms, decelerate).
    static let APPCOMPAT_DIALOG = 2
}

/// The window attributes a dialog takes from its theme (light values of Theme.TripleShot's dialog themes).
struct KitDialogTheme {
    enum Kind {
        /// android.app.Dialog: android:dialogTheme = Theme.Material.Light.Dialog.
        case plain
        /// android.app.AlertDialog: ThemeOverlay.MaterialComponents.Light.Dialog.Alert.Framework.
        case framework
        /// androidx.appcompat.app.AlertDialog: ThemeOverlay.MaterialComponents.Dialog.Alert.
        case appCompat
        /// MaterialAlertDialogBuilder: ThemeOverlay.MaterialComponents.MaterialAlertDialog.
        case material
    }

    let kind: Kind
    /// android:backgroundDimAmount.
    let dimAmount: Float
    /// android:windowMinWidthMajor / windowMinWidthMinor as fractions of the screen width (nil = @null).
    let minWidthMajor: Float?
    let minWidthMinor: Float?
    /// android:windowBackground: a rounded rectangle inset in the window (px).
    let backgroundInsetLeft: Int
    let backgroundInsetTop: Int
    let backgroundInsetRight: Int
    let backgroundInsetBottom: Int
    let cornerRadius: Float
    let backgroundColor: Int
    /// android:windowElevation (px).
    let elevation: Float
    /// android:windowAnimationStyle.
    let windowAnimations: Int

    /// dialog_min_width_major / minor (framework) and abc_dialog_min_width_* (AppCompat) have the same values:
    /// 65 % / 95 %, 55 % / 80 % on large screens, 45 % / 72 % on xlarge screens.
    static func alertMinWidths() -> (major: Float, minor: Float) {
        let size = AConfiguration.current.screenLayout & AConfiguration.SCREENLAYOUT_SIZE_MASK
        if size >= AConfiguration.SCREENLAYOUT_SIZE_XLARGE { return (0.45, 0.72) }
        if size >= AConfiguration.SCREENLAYOUT_SIZE_LARGE { return (0.55, 0.80) }
        return (0.65, 0.95)
    }

    static func resolve(_ kind: Kind) -> KitDialogTheme {
        let inset16 = aw_dpx(16)
        let corner2 = Float(aw_dpx(2))
        let z16 = Float(aw_dpx(16))
        let white = argbInt(0xFFFFFFFF)
        switch kind {
        case .plain:
            // Theme.Material.Light.BaseDialog: dialog_background_material, floating_window_z, no minimum width.
            return KitDialogTheme(kind: kind, dimAmount: 0.6, minWidthMajor: nil, minWidthMinor: nil,
                                  backgroundInsetLeft: inset16, backgroundInsetTop: inset16, backgroundInsetRight: inset16,
                                  backgroundInsetBottom: inset16, cornerRadius: corner2, backgroundColor: white,
                                  elevation: z16, windowAnimations: KitWindowAnimations.MATERIAL_DIALOG)
        case .framework:
            let min = alertMinWidths()
            return KitDialogTheme(kind: kind, dimAmount: 0.6, minWidthMajor: min.major, minWidthMinor: min.minor,
                                  backgroundInsetLeft: inset16, backgroundInsetTop: inset16, backgroundInsetRight: inset16,
                                  backgroundInsetBottom: inset16, cornerRadius: corner2, backgroundColor: white,
                                  elevation: z16, windowAnimations: KitWindowAnimations.MATERIAL_DIALOG)
        case .appCompat:
            // abc_dialog_material_background: inset 16 dp, ?dialogCornerRadius (2 dp), white; abc_floating_window_z.
            let min = alertMinWidths()
            return KitDialogTheme(kind: kind, dimAmount: 0.6, minWidthMajor: min.major, minWidthMinor: min.minor,
                                  backgroundInsetLeft: inset16, backgroundInsetTop: inset16, backgroundInsetRight: inset16,
                                  backgroundInsetBottom: inset16, cornerRadius: corner2, backgroundColor: white,
                                  elevation: z16, windowAnimations: KitWindowAnimations.APPCOMPAT_DIALOG)
        case .material:
            // MaterialAlertDialogBuilder installs its own background (create()); until then the AppCompat one.
            let min = alertMinWidths()
            return KitDialogTheme(kind: kind, dimAmount: 0.32, minWidthMajor: min.major, minWidthMinor: min.minor,
                                  backgroundInsetLeft: inset16, backgroundInsetTop: inset16, backgroundInsetRight: inset16,
                                  backgroundInsetBottom: inset16, cornerRadius: corner2, backgroundColor: white,
                                  elevation: z16, windowAnimations: KitWindowAnimations.APPCOMPAT_DIALOG)
        }
    }
}

/// A dialog window background: a filled rounded rectangle inset in the window (dialog_background_material,
/// abc_dialog_material_background, or InsetDrawable(MaterialShapeDrawable) of MaterialAlertDialogBuilder). The insets
/// are its padding (the decor view's padding) and its outline casts the window shadow.
final class KitDialogBackgroundDrawable: ADrawable, ADrawableOutlineProvider {
    let insetLeft: Int
    let insetTop: Int
    let insetRight: Int
    let insetBottom: Int
    let cornerRadius: Float
    let color: Int
    private let paint = APaint(APaint.ANTI_ALIAS_FLAG)

    init(_ insetLeft: Int, _ insetTop: Int, _ insetRight: Int, _ insetBottom: Int, _ cornerRadius: Float, _ color: Int) {
        self.insetLeft = insetLeft
        self.insetTop = insetTop
        self.insetRight = insetRight
        self.insetBottom = insetBottom
        self.cornerRadius = cornerRadius
        self.color = color
        super.init()
    }

    /// The same shape with other insets (MaterialDialogs.insetDrawable).
    func withInsets(_ l: Int, _ t: Int, _ r: Int, _ b: Int) -> KitDialogBackgroundDrawable {
        KitDialogBackgroundDrawable(l, t, r, b, cornerRadius, color)
    }

    override func draw(_ canvas: ACanvas) {
        let b = bounds
        let rect = ARectF(Float(b.left + insetLeft), Float(b.top + insetTop), Float(b.right - insetRight),
                          Float(b.bottom - insetBottom))
        if rect.isEmpty() { return }
        paint.color = color
        paint.alpha = AColor.alpha(color) * alpha / 255
        paint.style = .FILL
        canvas.drawRoundRect(rect, cornerRadius, cornerRadius, paint)
    }

    override func getPadding(_ padding: ARect) -> Bool {
        padding.set(insetLeft, insetTop, insetRight, insetBottom)
        return true
    }

    func getOutline(_ outline: AOutline) {
        let b = bounds
        outline.setRoundRect(b.left + insetLeft, b.top + insetTop, b.right - insetRight, b.bottom - insetBottom, cornerRadius)
        outline.setAlpha(Float(AColor.alpha(color)) / 255 * Float(alpha) / 255)
    }
}

// MARK: - Dialog

/// android.app.Dialog with androidx ComponentDialog (lifecycle, OnBackPressedDispatcher) and AppCompatDialog (the
/// AppCompat sub-decor of AppCompat / Material dialogs) behaviour. Listener calls are posted to the main looper like
/// Dialog's ListenersHandler messages (onShow after show(), onCancel then onDismiss after cancel()).
class ADialog: ADialogInterface, ALifecycleOwner, CustomStringConvertible {
    let mContext: AContext
    let mWindow: AWindow
    let theme: KitDialogTheme
    private(set) var mOwnerActivity: AActivity?

    var mCancelable = true
    private var mCanceled = false
    private(set) var mCreated = false
    private(set) var mShowing = false
    private(set) var mDecor: AView?

    private var mCancelMessage: OnCancelListener?
    private var mDismissMessage: OnDismissListener?
    private var mShowMessage: OnShowListener?
    private let mListenersHandler = AHandler(ALooper.getMainLooper())

    /// The window on screen (nil while not shown).
    private(set) var overlay: KitDialogOverlay?
    private var lifecycleRegistryStorage: ALifecycleRegistry?
    private var dispatcherStorage: AOnBackPressedDispatcher?

    /// `new Dialog(context)`: android:dialogTheme of the context (Theme.Material.Light.Dialog).
    init(_ context: AContext) {
        mContext = context
        theme = KitDialogTheme.resolve(.plain)
        mWindow = AWindow(context: context, isFloating: true)
        mOwnerActivity = KitContexts.activity(context)
        super.init()
        configureWindow()
    }

    /// `new Dialog(context, themeResId)`: the app's dialog styles are plain floating windows.
    init(_ context: AContext, _ themeResId: String) {
        mContext = context
        theme = KitDialogTheme.resolve(.plain)
        mWindow = AWindow(context: context, isFloating: true)
        mOwnerActivity = KitContexts.activity(context)
        super.init()
        configureWindow()
    }

    /// A dialog of one of the AlertDialog themes.
    init(context: AContext, kind: KitDialogTheme.Kind) {
        mContext = context
        theme = KitDialogTheme.resolve(kind)
        mWindow = AWindow(context: context, isFloating: true)
        mOwnerActivity = KitContexts.activity(context)
        super.init()
        configureWindow()
    }

    /// The Dialog constructor (w.setGravity(CENTER)) and PhoneWindow.generateLayout for the dialog theme.
    private func configureWindow() {
        let a = mWindow.attributes
        a.gravity = AGravity.CENTER
        a.flags |= AWindowManager.LayoutParams.FLAG_DIM_BEHIND
        a.dimAmount = theme.dimAmount
        a.windowAnimations = theme.windowAnimations
        a.softInputMode = AWindowManager.LayoutParams.SOFT_INPUT_ADJUST_PAN
        mWindow.attributes = a
        mWindow.minWidthMajor = theme.minWidthMajor
        mWindow.minWidthMinor = theme.minWidthMinor
        mWindow.windowElevation = theme.elevation
        mWindow.installThemeBackground(
            KitDialogBackgroundDrawable(theme.backgroundInsetLeft, theme.backgroundInsetTop, theme.backgroundInsetRight,
                                        theme.backgroundInsetBottom, theme.cornerRadius, theme.backgroundColor),
            padding: ARect(theme.backgroundInsetLeft, theme.backgroundInsetTop, theme.backgroundInsetRight,
                           theme.backgroundInsetBottom))
        // windowCloseOnTouchOutside: true in every dialog theme.
        mWindow.setCloseOnTouchOutsideIfNotSet(true)
        if theme.kind == .appCompat || theme.kind == .material {
            mWindow.installAppCompatDialogSubDecor()
        }
        mWindow.onAttributesChanged = { [weak self] in self?.windowAttributesChanged() }
    }

    var description: String {
        "\(type(of: self)){\(String(UInt(bitPattern: ObjectIdentifier(self).hashValue), radix: 16))}"
    }

    // MARK: Context, window, owner

    /// Dialog.getContext().
    var context: AContext { mContext }
    func getContext() -> AContext { mContext }

    /// Dialog.getWindow() (nullable in Java; always set here).
    var window: AWindow! { mWindow }
    func getWindow() -> AWindow! { mWindow }

    /// Dialog.getOwnerActivity / setOwnerActivity.
    var ownerActivity: AActivity? {
        get { mOwnerActivity }
        set { mOwnerActivity = newValue }
    }
    func getOwnerActivity() -> AActivity? { mOwnerActivity }
    func setOwnerActivity(_ activity: AActivity) { mOwnerActivity = activity }

    // MARK: ComponentDialog (lifecycle, back dispatcher)

    private var lifecycleRegistry: ALifecycleRegistry {
        if let r = lifecycleRegistryStorage { return r }
        let r = ALifecycleRegistry(self)
        lifecycleRegistryStorage = r
        return r
    }

    var lifecycle: ALifecycle { lifecycleRegistry }

    /// ComponentDialog.getOnBackPressedDispatcher(): its fallback is Dialog.onBackPressed (cancel if cancelable).
    var onBackPressedDispatcher: AOnBackPressedDispatcher {
        if let d = dispatcherStorage { return d }
        let d = AOnBackPressedDispatcher { [weak self] in self?.superOnBackPressed() }
        dispatcherStorage = d
        return d
    }

    /// Dialog.onBackPressed: iOS has no Back key; AActivity.onBackPressed (from an on-screen control) sends it to the
    /// topmost dialog.
    func onBackPressed() {
        onBackPressedDispatcher.onBackPressed()
    }

    private func superOnBackPressed() {
        if mCancelable {
            cancel()
        }
    }

    // MARK: Lifecycle override points (call super)

    /// Dialog.onCreate (ComponentDialog: ON_CREATE).
    func onCreate(_ savedInstanceState: ABundle?) {
        lifecycleRegistry.handleLifecycleEvent(.ON_CREATE)
    }

    /// Dialog.onStart (ComponentDialog: ON_RESUME).
    func onStart() {
        lifecycleRegistry.handleLifecycleEvent(.ON_RESUME)
    }

    /// Dialog.onStop (ComponentDialog: ON_DESTROY, then a fresh lifecycle for the next show).
    func onStop() {
        lifecycleRegistry.handleLifecycleEvent(.ON_DESTROY)
        lifecycleRegistryStorage = nil
    }

    /// Dialog.create(): onCreate without showing.
    func create() {
        if !mCreated {
            dispatchOnCreate(nil)
        }
    }

    private func dispatchOnCreate(_ savedInstanceState: ABundle?) {
        if !mCreated {
            onCreate(savedInstanceState)
            mCreated = true
        }
    }

    // MARK: Show / hide / dismiss / cancel

    /// Dialog.show(): creates the dialog if needed, onStart, adds the window, then posts the OnShowListener.
    func show() {
        if mShowing {
            if let decor = mDecor {
                decor.visibility = AView.VISIBLE
                overlay?.isHidden = false
                mOwnerActivity?.dialogWindowAttributesChanged(self)
            }
            return
        }
        mCanceled = false
        if !mCreated {
            dispatchOnCreate(nil)
        }
        onStart()
        mDecor = mWindow.decorView
        if !addWindow() {
            mDecor = nil
            return
        }
        mShowing = true
        sendShowMessage()
    }

    /// Dialog.hide(): the decor view GONE (the window, and its dim, disappear; isShowing becomes false).
    func hide() {
        if let decor = mDecor {
            decor.visibility = AView.GONE
            overlay?.isHidden = true
            mOwnerActivity?.dialogWindowAttributesChanged(self)
        }
    }

    /// Dialog.dismiss(): removes the window now on the main thread.
    override func dismiss() {
        if Thread.isMainThread {
            dismissDialog()
        } else {
            DispatchQueue.main.async { [self] in self.dismissDialog() }
        }
    }

    /// Dialog.dismissDialog.
    func dismissDialog() {
        guard mDecor != nil, mShowing else { return }
        removeWindow()
        mDecor = nil
        onStop()
        mShowing = false
        sendDismissMessage()
    }

    /// Dialog.cancel(): the OnCancelListener (once), then dismiss.
    override func cancel() {
        if !mCanceled, let listener = mCancelMessage {
            mCanceled = true
            mListenersHandler.post { [self] in listener(self) }
        }
        dismiss()
    }

    /// Dialog.isShowing(): the decor view is in a window and VISIBLE.
    var isShowing: Bool {
        guard let decor = mDecor else { return false }
        return decor.visibility == AView.VISIBLE
    }

    private func sendShowMessage() {
        if let listener = mShowMessage {
            mListenersHandler.post { [self] in listener(self) }
        }
    }

    private func sendDismissMessage() {
        if let listener = mDismissMessage {
            mListenersHandler.post { [self] in listener(self) }
        }
    }

    // MARK: Listeners and options

    func setCancelable(_ flag: Bool) {
        mCancelable = flag
    }

    var isCancelable: Bool { mCancelable }

    /// Dialog.setCanceledOnTouchOutside: true also makes the dialog cancelable.
    func setCanceledOnTouchOutside(_ cancel: Bool) {
        if cancel && !mCancelable {
            mCancelable = true
        }
        mWindow.setCloseOnTouchOutside(cancel)
    }

    func setOnCancelListener(_ listener: OnCancelListener?) {
        mCancelMessage = listener
    }

    func setOnDismissListener(_ listener: OnDismissListener?) {
        mDismissMessage = listener
    }

    func setOnShowListener(_ listener: OnShowListener?) {
        mShowMessage = listener
    }

    /// Dialog.requestWindowFeature (FEATURE_NO_TITLE: the app's plain dialogs never show a title bar).
    @discardableResult
    func requestWindowFeature(_ featureId: Int) -> Bool {
        mWindow.requestFeature(featureId)
    }

    // MARK: Content

    func setContentView(_ view: AView) {
        mWindow.setContentView(view)
    }

    func setContentView(_ view: AView, _ params: AViewGroup.LayoutParams) {
        mWindow.setContentView(view, params)
    }

    /// Dialog.setContentView(layoutResID): the Swift builder registered for the layout.
    func setContentView(_ layoutResID: String) {
        mWindow.contentParent.removeAllViews()
        ALayoutInflater.from(mContext).inflate(layoutResID, mWindow.contentParent, true)
    }

    func addContentView(_ view: AView, _ params: AViewGroup.LayoutParams) {
        mWindow.addContentView(view, params)
    }

    func findViewById<T: AView>(_ id: String) -> T? {
        mWindow.findViewById(id)
    }

    func requireViewById<T: AView>(_ id: String) -> T {
        guard let v: T = findViewById(id) else {
            preconditionFailure("ID does not reference a View inside this Dialog")
        }
        return v
    }

    /// Dialog.setTitle (the window title; AlertDialog shows it in its title panel).
    func setTitle(_ title: String?) {
        mWindow.setTitle(title)
    }

    func setTitle(res titleId: AStringRes) {
        setTitle(AResources.getText(titleId))
    }

    // MARK: Touch

    /// Dialog.dispatchTouchEvent (Window.Callback): the views first, then onTouchEvent.
    func dispatchTouchEvent(_ ev: AMotionEvent) -> Bool {
        if let root = overlay?.viewRoot, root.superDispatchTouchEvent(ev) {
            return true
        }
        return onTouchEvent(ev)
    }

    /// Dialog.onTouchEvent: cancels on a touch outside the window when cancelable and closing on touch outside.
    func onTouchEvent(_ event: AMotionEvent) -> Bool {
        if mCancelable && mShowing && mWindow.shouldCloseOnTouch(event) {
            cancel()
            return true
        }
        return false
    }

    // MARK: Window (WindowManager.addView / removeViewImmediate)

    private func addWindow() -> Bool {
        guard let activity = mOwnerActivity ?? AActivityHost.shared?.topActivity, !activity.isDestroyed else {
            ALog.e("WindowManager", "android.view.WindowManager$BadTokenException: Unable to add window -- token null "
                   + "is not valid; is your activity running?")
            return false
        }
        activity.loadViewIfNeeded()
        guard let root = activity.rootView else { return false }
        let o = KitDialogOverlay(dialog: self, window: mWindow)
        overlay = o
        root.addOverlay(o)
        o.attachWindow()
        activity.dialogWindowShown(self)
        return true
    }

    private func removeWindow() {
        overlay?.detach(animated: true)
        overlay = nil
        (mOwnerActivity ?? AActivityHost.shared?.topActivity)?.dialogWindowRemoved(self)
    }

    /// The owning activity was destroyed with this dialog showing: Android removes the leaked window without
    /// telling the dialog (no dismiss callbacks; a later dismiss() does nothing).
    func windowRemovedWithActivity() {
        overlay?.detach(animated: false)
        overlay = nil
        mDecor = nil
    }

    /// The window dims what is behind it (FLAG_DIM_BEHIND with a dim amount, the window visible).
    var dimsBehind: Bool {
        guard mShowing, let decor = mDecor, decor.visibility == AView.VISIBLE else { return false }
        let a = mWindow.attributes
        return (a.flags & AWindowManager.LayoutParams.FLAG_DIM_BEHIND) != 0 && a.dimAmount > 0
    }

    /// Window.setAttributes / setLayout / setDimAmount / setBackgroundDrawable while shown: relayout.
    private func windowAttributesChanged() {
        guard mShowing, let o = overlay else { return }
        o.windowAttributesChanged()
        mOwnerActivity?.dialogWindowAttributesChanged(self)
    }
}

// MARK: - AlertDialog

/// android.app.AlertDialog / androidx.appcompat.app.AlertDialog: title, message, list, custom view and three buttons
/// laid out by the AlertController port, in the look of the dialog's theme (KitDialogTheme.Kind).
class AAlertDialog: ADialog {
    private(set) var mAlert: KitAlertController!

    override init(context: AContext, kind: KitDialogTheme.Kind) {
        super.init(context: context, kind: kind)
        mAlert = KitAlertController(context, self, mWindow, KitAlertTheme.resolve(kind))
    }

    /// `new AlertDialog(context)` (framework theme).
    override convenience init(_ context: AContext) {
        self.init(context: context, kind: .framework)
    }

    /// AlertDialog.getButton(whichButton): nil before the dialog is created (Java returns null).
    func getButton(_ whichButton: Int) -> AButton! {
        mAlert.getButton(whichButton)
    }

    /// AlertDialog.getListView(): nil when the dialog has no list.
    var listView: AAlertDialog.RecycleListView! { mAlert.mListView }
    func getListView() -> AAlertDialog.RecycleListView! { mAlert.mListView }

    override func setTitle(_ title: String?) {
        super.setTitle(title)
        mAlert.setTitle(title)
    }

    func setCustomTitle(_ customTitleView: AView?) {
        mAlert.setCustomTitle(customTitleView)
    }

    func setMessage(_ message: String?) {
        mAlert.setMessage(message)
    }

    func setView(_ view: AView?) {
        mAlert.setView(view)
    }

    func setView(_ view: AView?, _ viewSpacingLeft: Int, _ viewSpacingTop: Int, _ viewSpacingRight: Int,
                 _ viewSpacingBottom: Int) {
        mAlert.setView(view, viewSpacingLeft, viewSpacingTop, viewSpacingRight, viewSpacingBottom)
    }

    func setButton(_ whichButton: Int, _ text: String?, _ listener: OnClickListener?) {
        mAlert.setButton(whichButton, text, listener, nil)
    }

    func setIcon(_ icon: ADrawable?) {
        mAlert.setIcon(icon)
    }

    func setIcon(res resId: ADrawableRes) {
        mAlert.setIcon(res: resId)
    }

    override func onCreate(_ savedInstanceState: ABundle?) {
        super.onCreate(savedInstanceState)
        mAlert.installContent()
    }

    // MARK: Builder

    /// AlertDialog.Builder (android.app.AlertDialog: the framework look; AContextThemeWrapper contexts too).
    class Builder {
        let P: KitAlertParams
        let mKind: KitDialogTheme.Kind

        init(_ context: AContext) {
            P = KitAlertParams(context)
            mKind = .framework
        }

        /// Builder(context, themeResId).
        init(_ context: AContext, _ themeResId: String) {
            P = KitAlertParams(context)
            mKind = .framework
        }

        init(context: AContext, kind: KitDialogTheme.Kind) {
            P = KitAlertParams(context)
            mKind = kind
        }

        var context: AContext { P.mContext }
        func getContext() -> AContext { P.mContext }

        @discardableResult
        func setTitle(_ title: String?) -> Self {
            P.mTitle = title
            return self
        }

        @discardableResult
        func setTitle(res titleId: AStringRes) -> Self {
            P.mTitle = AResources.getText(titleId)
            return self
        }

        @discardableResult
        func setCustomTitle(_ customTitleView: AView?) -> Self {
            P.mCustomTitleView = customTitleView
            return self
        }

        @discardableResult
        func setMessage(_ message: String?) -> Self {
            P.mMessage = message
            return self
        }

        @discardableResult
        func setMessage(res messageId: AStringRes) -> Self {
            P.mMessage = AResources.getText(messageId)
            return self
        }

        @discardableResult
        func setIcon(_ icon: ADrawable?) -> Self {
            P.mIcon = icon
            return self
        }

        @discardableResult
        func setIcon(res iconId: ADrawableRes) -> Self {
            P.mIconId = iconId
            return self
        }

        @discardableResult
        func setPositiveButton(_ text: String?, _ listener: OnClickListener?) -> Self {
            P.mPositiveButtonText = text
            P.mPositiveButtonListener = listener
            return self
        }

        @discardableResult
        func setPositiveButton(res textId: AStringRes, _ listener: OnClickListener?) -> Self {
            setPositiveButton(AResources.getText(textId), listener)
        }

        @discardableResult
        func setNegativeButton(_ text: String?, _ listener: OnClickListener?) -> Self {
            P.mNegativeButtonText = text
            P.mNegativeButtonListener = listener
            return self
        }

        @discardableResult
        func setNegativeButton(res textId: AStringRes, _ listener: OnClickListener?) -> Self {
            setNegativeButton(AResources.getText(textId), listener)
        }

        @discardableResult
        func setNeutralButton(_ text: String?, _ listener: OnClickListener?) -> Self {
            P.mNeutralButtonText = text
            P.mNeutralButtonListener = listener
            return self
        }

        @discardableResult
        func setNeutralButton(res textId: AStringRes, _ listener: OnClickListener?) -> Self {
            setNeutralButton(AResources.getText(textId), listener)
        }

        @discardableResult
        func setCancelable(_ cancelable: Bool) -> Self {
            P.mCancelable = cancelable
            return self
        }

        @discardableResult
        func setOnCancelListener(_ onCancelListener: OnCancelListener?) -> Self {
            P.mOnCancelListener = onCancelListener
            return self
        }

        @discardableResult
        func setOnDismissListener(_ onDismissListener: OnDismissListener?) -> Self {
            P.mOnDismissListener = onDismissListener
            return self
        }

        /// setItems(items, listener): a list; a tap calls the listener, then dismisses.
        @discardableResult
        func setItems(_ items: [String]?, _ listener: OnClickListener?) -> Self {
            P.mItems = items
            P.mOnClickListener = listener
            return self
        }

        @discardableResult
        func setItems(res itemsId: AStringRes, _ listener: OnClickListener?) -> Self {
            setItems(AResources.getStringArray(itemsId), listener)
        }

        /// setMultiChoiceItems(items, checkedItems, listener): check boxes; the dialog stays open on taps.
        @discardableResult
        func setMultiChoiceItems(_ items: [String]?, _ checkedItems: [Bool]?, _ listener: OnMultiChoiceClickListener?) -> Self {
            P.mItems = items
            P.mOnCheckboxClickListener = listener
            P.mCheckedItems = checkedItems
            P.mIsMultiChoice = true
            return self
        }

        /// setSingleChoiceItems(items, checkedItem, listener): radio buttons; the dialog stays open on taps.
        @discardableResult
        func setSingleChoiceItems(_ items: [String]?, _ checkedItem: Int, _ listener: OnClickListener?) -> Self {
            P.mItems = items
            P.mOnClickListener = listener
            P.mCheckedItem = checkedItem
            P.mIsSingleChoice = true
            return self
        }

        @discardableResult
        func setView(_ view: AView?) -> Self {
            P.mView = view
            P.mViewLayoutResId = nil
            P.mViewSpacingSpecified = false
            return self
        }

        /// setView(layoutResId): the Swift builder registered for the layout.
        @discardableResult
        func setView(res layoutResId: String) -> Self {
            P.mView = nil
            P.mViewLayoutResId = layoutResId
            P.mViewSpacingSpecified = false
            return self
        }

        /// Builder.create().
        func create() -> AAlertDialog {
            let dialog = AAlertDialog(context: P.mContext, kind: mKind)
            P.apply(dialog.mAlert)
            dialog.setCancelable(P.mCancelable)
            if P.mCancelable {
                dialog.setCanceledOnTouchOutside(true)
            }
            dialog.setOnCancelListener(P.mOnCancelListener)
            dialog.setOnDismissListener(P.mOnDismissListener)
            return dialog
        }

        /// Builder.show(): create() + show().
        @discardableResult
        func show() -> AAlertDialog {
            let dialog = create()
            dialog.show()
            return dialog
        }
    }

    /// androidx.appcompat.app.AlertDialog.Builder (Kotlin `androidx.appcompat.app.AlertDialog.Builder(context)`).
    final class AppCompatBuilder: Builder {
        override init(_ context: AContext) {
            super.init(context: context, kind: .appCompat)
        }

        override init(_ context: AContext, _ themeResId: String) {
            super.init(context: context, kind: .appCompat)
        }
    }

    // MARK: ListView of the alert (AlertController.RecycleListView)

    /// The alert's ListView: the items in a vertical scroller, with ListView's choice modes (setItemChecked,
    /// isItemChecked, checkedItemPosition) and item clicks.
    final class RecycleListView: AScrollView {
        static let CHOICE_MODE_NONE = 0
        static let CHOICE_MODE_SINGLE = 1
        static let CHOICE_MODE_MULTIPLE = 2
        static let INVALID_POSITION = -1

        private let mPaddingTopNoTitle: Int
        private let mPaddingBottomNoButtons: Int
        private let itemsLayout = ALinearLayout()
        private(set) var itemViews: [KitAlertListItemView] = []
        private var mCheckStates: [Int: Bool] = [:]
        /// AbsListView.mChoiceMode.
        var choiceMode = RecycleListView.CHOICE_MODE_NONE
        /// AdapterView.OnItemClickListener (position).
        var onItemClickListener: ((Int) -> Void)?
        private var pendingSelection = RecycleListView.INVALID_POSITION

        init(paddingTopNoTitle: Int, paddingBottomNoButtons: Int) {
            mPaddingTopNoTitle = paddingTopNoTitle
            mPaddingBottomNoButtons = paddingBottomNoButtons
            super.init()
            viewId = KitAlertIds.select_dialog_listview
            clipToPadding = false
            textAlignment = AView.TEXT_ALIGNMENT_VIEW_START
            itemsLayout.orientation = ALinearLayout.VERTICAL
            addView(itemsLayout, AFrameLayout.LayoutParams(AViewGroup.LayoutParams.MATCH_PARENT,
                                                           AViewGroup.LayoutParams.WRAP_CONTENT))
        }

        required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

        /// The number of items (Adapter.getCount).
        var count: Int { itemViews.count }

        /// ListView.setAdapter: one row per item.
        func setAdapter(_ items: [String], _ makeRow: (Int, String) -> KitAlertListItemView) {
            itemsLayout.removeAllViews()
            itemViews.removeAll()
            for (position, item) in items.enumerated() {
                let row = makeRow(position, item)
                row.setOnClickListener { [weak self] _ in
                    _ = self?.performItemClick(position)
                }
                itemViews.append(row)
                itemsLayout.addView(row, ALinearLayout.LayoutParams(AViewGroup.LayoutParams.MATCH_PARENT,
                                                                    AViewGroup.LayoutParams.WRAP_CONTENT))
            }
            updateOnScreenCheckedViews()
        }

        /// AbsListView.setItemChecked.
        func setItemChecked(_ position: Int, _ value: Bool) {
            if choiceMode == RecycleListView.CHOICE_MODE_NONE { return }
            if choiceMode == RecycleListView.CHOICE_MODE_MULTIPLE {
                mCheckStates[position] = value
            } else {
                // Clear all values if we're checking something, or unchecking the currently selected item
                if value || isItemChecked(position) {
                    mCheckStates.removeAll()
                }
                // This may end up selecting the value we just cleared but this way we ensure length of
                // mCheckStates is 1, a fact getCheckedItemPosition relies on
                if value {
                    mCheckStates[position] = true
                }
            }
            updateOnScreenCheckedViews()
        }

        /// AbsListView.isItemChecked.
        func isItemChecked(_ position: Int) -> Bool {
            if choiceMode != RecycleListView.CHOICE_MODE_NONE {
                return mCheckStates[position] ?? false
            }
            return false
        }

        /// AbsListView.getCheckedItemPosition (single choice only).
        var checkedItemPosition: Int {
            if choiceMode == RecycleListView.CHOICE_MODE_SINGLE, mCheckStates.count == 1,
               let entry = mCheckStates.first, entry.value {
                return entry.key
            }
            return RecycleListView.INVALID_POSITION
        }
        func getCheckedItemPosition() -> Int { checkedItemPosition }

        /// AbsListView.getCheckedItemCount.
        var checkedItemCount: Int { mCheckStates.values.filter { $0 }.count }

        /// AbsListView.clearChoices.
        func clearChoices() {
            mCheckStates.removeAll()
            updateOnScreenCheckedViews()
        }

        /// AbsListView.performItemClick: the choice mode toggles first, then the OnItemClickListener.
        @discardableResult
        func performItemClick(_ position: Int) -> Bool {
            var handled = false
            if choiceMode != RecycleListView.CHOICE_MODE_NONE {
                handled = true
                if choiceMode == RecycleListView.CHOICE_MODE_MULTIPLE {
                    let checked = !(mCheckStates[position] ?? false)
                    mCheckStates[position] = checked
                } else if choiceMode == RecycleListView.CHOICE_MODE_SINGLE {
                    let checked = !(mCheckStates[position] ?? false)
                    if checked {
                        mCheckStates.removeAll()
                        mCheckStates[position] = true
                    }
                }
                updateOnScreenCheckedViews()
            }
            if let listener = onItemClickListener {
                listener(position)
                handled = true
            }
            return handled
        }

        /// ListView.setSelection: the item at the top once laid out.
        func setSelection(_ position: Int) {
            pendingSelection = position
            requestLayout()
        }

        override func onLayout(_ changed: Bool, _ l: Int, _ t: Int, _ r: Int, _ b: Int) {
            super.onLayout(changed, l, t, r, b)
            if pendingSelection >= 0 && pendingSelection < itemViews.count {
                let target = itemViews[pendingSelection].top
                pendingSelection = RecycleListView.INVALID_POSITION
                let maxScroll = max(0, itemsLayout.height - (height - paddingTop - paddingBottom))
                scrollTo(0, min(target, maxScroll))
            }
        }

        /// AlertController.RecycleListView.setHasDecor.
        func setHasDecor(_ hasTitle: Bool, _ hasButtons: Bool) {
            if !hasButtons || !hasTitle {
                let paddingLeft = self.paddingLeft
                let paddingTop = hasTitle ? self.paddingTop : mPaddingTopNoTitle
                let paddingRight = self.paddingRight
                let paddingBottom = hasButtons ? self.paddingBottom : mPaddingBottomNoButtons
                setPadding(paddingLeft, paddingTop, paddingRight, paddingBottom)
            }
        }

        private func updateOnScreenCheckedViews() {
            for (position, row) in itemViews.enumerated() {
                row.isChecked = isItemChecked(position)
            }
        }
    }
}

/// androidx.appcompat.app.AlertDialog (Kotlin `androidx.appcompat.app.AlertDialog.Builder(context)` ->
/// `AAppCompatAlertDialog.Builder(context)`).
enum AAppCompatAlertDialog {
    typealias Builder = AAlertDialog.AppCompatBuilder
}

/// com.google.android.material.dialog.MaterialAlertDialogBuilder: an androidx AlertDialog in the
/// ThemeOverlay.MaterialComponents.MaterialAlertDialog look, its window background an InsetDrawable of a
/// MaterialShapeDrawable (colorSurface, 4 dp corners) inset 24 dp start/end and 80 dp top/bottom, and a touch in that
/// inset counting as outside the dialog (InsetDialogOnTouchListener).
class AMaterialAlertDialogBuilder: AAlertDialog.Builder {
    private var background: ADrawable?
    private let backgroundInsets: ARect

    override init(_ context: AContext) {
        backgroundInsets = AMaterialAlertDialogBuilder.dialogBackgroundInsets()
        // MaterialShapeDrawable: fill = backgroundTint (?colorSurface), corner = shapeAppearanceMediumComponent (4 dp);
        // android:dialogCornerRadius is @null in the overlay, so it does not replace the corner size.
        background = KitDialogBackgroundDrawable(0, 0, 0, 0, Float(aw_dpx(4)), argbInt(0xFFFFFFFF))
        super.init(context: context, kind: .material)
    }

    /// MaterialAlertDialogBuilder(context, overrideThemeResId).
    override init(_ context: AContext, _ themeResId: String) {
        backgroundInsets = AMaterialAlertDialogBuilder.dialogBackgroundInsets()
        background = KitDialogBackgroundDrawable(0, 0, 0, 0, Float(aw_dpx(4)), argbInt(0xFFFFFFFF))
        super.init(context: context, kind: .material)
    }

    /// MaterialDialogs.getDialogBackgroundInsets: start/end 24 dp, top/bottom 80 dp, start/end swapped in RTL.
    private static func dialogBackgroundInsets() -> ARect {
        let start = aw_dpx(24), top = aw_dpx(80), end = aw_dpx(24), bottom = aw_dpx(80)
        if AConfiguration.current.getLayoutDirection() == AView.LAYOUT_DIRECTION_RTL {
            return ARect(end, top, start, bottom)
        }
        return ARect(start, top, end, bottom)
    }

    func getBackground() -> ADrawable? { background }

    @discardableResult
    func setBackground(_ background: ADrawable?) -> Self {
        self.background = background
        return self
    }

    @discardableResult
    func setBackgroundInsetStart(_ backgroundInsetStart: Int) -> Self {
        if AConfiguration.current.getLayoutDirection() == AView.LAYOUT_DIRECTION_RTL {
            backgroundInsets.right = backgroundInsetStart
        } else {
            backgroundInsets.left = backgroundInsetStart
        }
        return self
    }

    @discardableResult
    func setBackgroundInsetTop(_ backgroundInsetTop: Int) -> Self {
        backgroundInsets.top = backgroundInsetTop
        return self
    }

    @discardableResult
    func setBackgroundInsetEnd(_ backgroundInsetEnd: Int) -> Self {
        if AConfiguration.current.getLayoutDirection() == AView.LAYOUT_DIRECTION_RTL {
            backgroundInsets.left = backgroundInsetEnd
        } else {
            backgroundInsets.right = backgroundInsetEnd
        }
        return self
    }

    @discardableResult
    func setBackgroundInsetBottom(_ backgroundInsetBottom: Int) -> Self {
        backgroundInsets.bottom = backgroundInsetBottom
        return self
    }

    /// MaterialAlertDialogBuilder.create: the inset background and the inset touch listener on the decor view.
    override func create() -> AAlertDialog {
        let alertDialog = super.create()
        let window: AWindow = alertDialog.mWindow
        let decorView = window.decorView
        let insets = backgroundInsets
        let insetDrawable: ADrawable?
        if let shape = background as? KitDialogBackgroundDrawable {
            insetDrawable = shape.withInsets(insets.left, insets.top, insets.right, insets.bottom)
        } else {
            insetDrawable = AInsetDrawable(background, insets.left, insets.top, insets.right, insets.bottom)
        }
        window.setBackgroundDrawable(insetDrawable)
        let listener = KitInsetDialogOnTouchListener(alertDialog, insets)
        decorView.setOnTouchListener { view, event in listener.onTouch(view, event) }
        return alertDialog
    }
}

/// com.google.android.material.dialog.InsetDialogOnTouchListener: a touch in the transparent inset around the card
/// is an outside touch (ACTION_UP becomes ACTION_OUTSIDE) for Dialog.onTouchEvent.
final class KitInsetDialogOnTouchListener {
    private weak var dialog: ADialog?
    private let leftInset: Int
    private let topInset: Int

    init(_ dialog: ADialog, _ insets: ARect) {
        self.dialog = dialog
        leftInset = insets.left
        topInset = insets.top
    }

    func onTouch(_ view: AView, _ event: AMotionEvent) -> Bool {
        guard let insetView: AView = view.findViewById(AWindow.ID_ANDROID_CONTENT) else { return false }
        let insetLeft = leftInset + insetView.left
        let insetRight = insetLeft + insetView.width
        let insetTop = topInset + insetView.top
        let insetBottom = insetTop + insetView.height
        let dialogWindow = ARectF(Float(insetLeft), Float(insetTop), Float(insetRight), Float(insetBottom))
        if dialogWindow.contains(event.x, event.y) {
            return false
        }
        let outsideEvent = AMotionEvent.obtain(event)
        if event.action == AMotionEvent.ACTION_UP {
            outsideEvent.setAction(AMotionEvent.ACTION_OUTSIDE)
        }
        view.performClick()
        return dialog?.onTouchEvent(outsideEvent) ?? false
    }
}

// MARK: - AlertController

/// The ids of the alert layouts (android.R.id.* and the androidx/framework internal ids, prefixed so that app ids never
/// collide with them).
enum KitAlertIds {
    static let parentPanel = "android:parentPanel"
    static let topPanel = "android:topPanel"
    static let title_template = "android:title_template"
    static let icon = "android:icon"
    static let alertTitle = "android:alertTitle"
    static let titleDividerNoCustom = "android:titleDividerNoCustom"
    static let contentPanel = "android:contentPanel"
    static let scrollView = "android:scrollView"
    static let textSpacerNoTitle = "android:textSpacerNoTitle"
    static let message = "android:message"
    static let textSpacerNoButtons = "android:textSpacerNoButtons"
    static let customPanel = "android:customPanel"
    static let custom = "android:custom"
    static let buttonPanel = "android:buttonPanel"
    static let button1 = "android:button1"
    static let button2 = "android:button2"
    static let button3 = "android:button3"
    static let spacer = "android:spacer"
    static let select_dialog_listview = "android:select_dialog_listview"
    static let text1 = "android:text1"
}

/// The text and button metrics of the three alert layouts (resolved light theme values).
struct KitAlertTheme {
    let kind: KitDialogTheme.Kind
    let titleTextSizeSp: Float
    let titleLetterSpacing: Float
    let titleColor: Int
    /// The title is match_parent (framework / AppCompat) or wrap_content (Material).
    let titleMatchParent: Bool
    let messageTextSizeSp: Float
    let messageLetterSpacing: Float
    let messageColor: Int
    let itemTextSizeSp: Float
    let itemLetterSpacing: Float
    let itemColor: Int
    let choiceTextSizeSp: Float
    let choiceLetterSpacing: Float
    let choiceColor: Int
    /// colorControlActivated / colorControlNormal of the check box and radio indicators.
    let checkedColor: Int
    let uncheckedColor: Int
    let buttonBarPaddingHorizontalDp: Float
    let buttonBarPaddingVerticalDp: Float
    /// layout_marginStart of the positive / negative buttons (TextButton.Dialog: 8 dp; .Flush: 0).
    let actionButtonMarginStartDp: Float
    /// textAppearanceMedium (DialogTitle's two-line fallback size).
    let mediumTextSizeSp: Float = 18

    static func resolve(_ kind: KitDialogTheme.Kind) -> KitAlertTheme {
        let primary = argbInt(0xDE000000)      // primary_text_material_light / material_on_surface_emphasis_high_type
        let medium = argbInt(0x99000000)       // material_on_surface_emphasis_medium
        let secondary = argbInt(0x8A000000)    // colorControlNormal = textColorSecondary
        switch kind {
        case .material:
            return KitAlertTheme(kind: kind, titleTextSizeSp: 16, titleLetterSpacing: 0.009375, titleColor: primary,
                                 titleMatchParent: false,
                                 messageTextSizeSp: 14, messageLetterSpacing: 0.0178571429, messageColor: medium,
                                 itemTextSizeSp: 14, itemLetterSpacing: 0.0178571429, itemColor: medium,
                                 choiceTextSizeSp: 16, choiceLetterSpacing: 0.03125, choiceColor: medium,
                                 checkedColor: AWMaterialColors.colorSecondary, uncheckedColor: secondary,
                                 buttonBarPaddingHorizontalDp: 8, buttonBarPaddingVerticalDp: 2,
                                 actionButtonMarginStartDp: 8)
        case .appCompat:
            return KitAlertTheme(kind: kind, titleTextSizeSp: 20, titleLetterSpacing: 0, titleColor: primary,
                                 titleMatchParent: true,
                                 messageTextSizeSp: 16, messageLetterSpacing: 0, messageColor: primary,
                                 itemTextSizeSp: 16, itemLetterSpacing: 0, itemColor: primary,
                                 choiceTextSizeSp: 18, choiceLetterSpacing: 0, choiceColor: primary,
                                 checkedColor: AWMaterialColors.colorSecondary, uncheckedColor: secondary,
                                 buttonBarPaddingHorizontalDp: 12, buttonBarPaddingVerticalDp: 4,
                                 actionButtonMarginStartDp: 0)
        case .framework, .plain:
            // Theme.Material.Light colorAccent = accent_material_light (#009688) tints the framework indicators.
            return KitAlertTheme(kind: kind, titleTextSizeSp: 20, titleLetterSpacing: 0, titleColor: primary,
                                 titleMatchParent: true,
                                 messageTextSizeSp: 16, messageLetterSpacing: 0, messageColor: primary,
                                 itemTextSizeSp: 16, itemLetterSpacing: 0, itemColor: primary,
                                 choiceTextSizeSp: 18, choiceLetterSpacing: 0, choiceColor: primary,
                                 checkedColor: argbInt(0xFF009688), uncheckedColor: secondary,
                                 buttonBarPaddingHorizontalDp: 12, buttonBarPaddingVerticalDp: 4,
                                 actionButtonMarginStartDp: 0)
        }
    }
}

/// androidx.appcompat.app.AlertController (the framework AlertController has the same logic).
final class KitAlertController {
    private let mContext: AContext
    unowned let mDialog: AAlertDialog
    private let mWindow: AWindow
    let theme: KitAlertTheme

    private var mTitle: String?
    private var mMessage: String?
    var mListView: AAlertDialog.RecycleListView?
    private var mView: AView?
    private var mViewLayoutResId: String?
    private var mViewSpacingLeft = 0
    private var mViewSpacingTop = 0
    private var mViewSpacingRight = 0
    private var mViewSpacingBottom = 0
    private var mViewSpacingSpecified = false

    var mButtonPositive: AButton?
    private var mButtonPositiveText: String?
    var mButtonPositiveMessage: ADialogInterface.OnClickListener?
    private var mButtonPositiveIcon: ADrawable?

    var mButtonNegative: AButton?
    private var mButtonNegativeText: String?
    var mButtonNegativeMessage: ADialogInterface.OnClickListener?
    private var mButtonNegativeIcon: ADrawable?

    var mButtonNeutral: AButton?
    private var mButtonNeutralText: String?
    var mButtonNeutralMessage: ADialogInterface.OnClickListener?
    private var mButtonNeutralIcon: ADrawable?

    var mScrollView: AScrollView?

    private var mIconId: ADrawableRes?
    private var mIcon: ADrawable?
    private var mIconView: AImageView?
    private var mTitleView: ATextView?
    private var mMessageView: ATextView?
    private var mCustomTitleView: AView?

    /// The ListAdapter: the items and the row kind.
    var mAdapterItems: [String]?
    var mAdapterRowKind = KitAlertListItemView.Kind.simple
    /// ArrayAdapter.getView of a multi-choice list: rows created checked when mCheckedItems[position].
    var mAdapterCheckedItems: (() -> [Bool]?)?
    var mCheckedItem = -1

    private var mShowTitle = true
    /// ButtonHandler: button listeners and the dismiss run as main-looper messages after the click.
    let mHandler = AHandler(ALooper.getMainLooper())

    init(_ context: AContext, _ dialog: AAlertDialog, _ window: AWindow, _ theme: KitAlertTheme) {
        mContext = context
        mDialog = dialog
        mWindow = window
        self.theme = theme
        // We use a custom title so never request a window title
        window.requestFeature(AWindow.FEATURE_NO_TITLE)
    }

    /// mButtonHandler: the listener message, then the dismiss message (both posted, in that order).
    private func buttonClicked(_ v: AView) {
        let listener: ADialogInterface.OnClickListener?
        let which: Int
        if v === mButtonPositive, let m = mButtonPositiveMessage {
            listener = m
            which = ADialogInterface.BUTTON_POSITIVE
        } else if v === mButtonNegative, let m = mButtonNegativeMessage {
            listener = m
            which = ADialogInterface.BUTTON_NEGATIVE
        } else if v === mButtonNeutral, let m = mButtonNeutralMessage {
            listener = m
            which = ADialogInterface.BUTTON_NEUTRAL
        } else {
            listener = nil
            which = 0
        }
        let dialog = mDialog
        if let m = listener {
            mHandler.post { m(dialog, which) }
        }
        // Post a message so we dismiss after the above handlers are executed
        mHandler.post { dialog.dismiss() }
    }

    static func canTextInput(_ v: AView) -> Bool {
        if v is AEditText {
            return true
        }
        guard let vg = v as? AViewGroup else { return false }
        var i = vg.childCount
        while i > 0 {
            i -= 1
            if let child = vg.getChildAt(i), canTextInput(child) {
                return true
            }
        }
        return false
    }

    func installContent() {
        mDialog.setContentView(buildAlertLayout())
        setupView()
    }

    func setTitle(_ title: String?) {
        mTitle = title
        mTitleView?.setText(title ?? "")
    }

    func setCustomTitle(_ customTitleView: AView?) {
        mCustomTitleView = customTitleView
    }

    func setMessage(_ message: String?) {
        mMessage = message
        mMessageView?.setText(message ?? "")
    }

    func setView(res layoutResId: String) {
        mView = nil
        mViewLayoutResId = layoutResId
        mViewSpacingSpecified = false
    }

    func setView(_ view: AView?) {
        mView = view
        mViewLayoutResId = nil
        mViewSpacingSpecified = false
    }

    func setView(_ view: AView?, _ viewSpacingLeft: Int, _ viewSpacingTop: Int, _ viewSpacingRight: Int,
                 _ viewSpacingBottom: Int) {
        mView = view
        mViewLayoutResId = nil
        mViewSpacingSpecified = true
        mViewSpacingLeft = viewSpacingLeft
        mViewSpacingTop = viewSpacingTop
        mViewSpacingRight = viewSpacingRight
        mViewSpacingBottom = viewSpacingBottom
    }

    func setButton(_ whichButton: Int, _ text: String?, _ listener: ADialogInterface.OnClickListener?, _ icon: ADrawable?) {
        switch whichButton {
        case ADialogInterface.BUTTON_POSITIVE:
            mButtonPositiveText = text
            mButtonPositiveMessage = listener
            mButtonPositiveIcon = icon
        case ADialogInterface.BUTTON_NEGATIVE:
            mButtonNegativeText = text
            mButtonNegativeMessage = listener
            mButtonNegativeIcon = icon
        case ADialogInterface.BUTTON_NEUTRAL:
            mButtonNeutralText = text
            mButtonNeutralMessage = listener
            mButtonNeutralIcon = icon
        default:
            preconditionFailure("java.lang.IllegalArgumentException: Button does not exist")
        }
    }

    func setIcon(res resId: ADrawableRes?) {
        mIcon = nil
        mIconId = resId
        if let iconView = mIconView {
            if let id = resId {
                iconView.visibility = AView.VISIBLE
                iconView.setImageResource(id)
            } else {
                iconView.visibility = AView.GONE
            }
        }
    }

    func setIcon(_ icon: ADrawable?) {
        mIcon = icon
        mIconId = nil
        if let iconView = mIconView {
            if let d = icon {
                iconView.visibility = AView.VISIBLE
                iconView.setImageDrawable(d)
            } else {
                iconView.visibility = AView.GONE
            }
        }
    }

    func getButton(_ whichButton: Int) -> AButton? {
        switch whichButton {
        case ADialogInterface.BUTTON_POSITIVE: return mButtonPositive
        case ADialogInterface.BUTTON_NEGATIVE: return mButtonNegative
        case ADialogInterface.BUTTON_NEUTRAL: return mButtonNeutral
        default: return nil
        }
    }

    /// resolvePanel: the custom panel replaces the default one (none of the app's views use the panel ids).
    private func resolvePanel(_ customPanel: AView?, _ defaultPanel: AView?) -> AViewGroup? {
        guard let custom = customPanel else {
            return defaultPanel as? AViewGroup
        }
        if let d = defaultPanel, let parent = d.parentGroup {
            parent.removeView(d)
        }
        return custom as? AViewGroup
    }

    private func setupView() {
        guard let parentPanel: AView = mWindow.findViewById(KitAlertIds.parentPanel) else { return }
        let defaultTopPanel: AView? = parentPanel.findViewById(KitAlertIds.topPanel)
        let defaultContentPanel: AView? = parentPanel.findViewById(KitAlertIds.contentPanel)
        let defaultButtonPanel: AView? = parentPanel.findViewById(KitAlertIds.buttonPanel)

        // Install custom content before setting up the title or buttons so that we can handle panel overrides.
        let customPanel: AViewGroup = parentPanel.findViewById(KitAlertIds.customPanel)!
        setupCustomContent(customPanel)

        let customTopPanel: AView? = customPanel.findViewById(KitAlertIds.topPanel)
        let customContentPanel: AView? = customPanel.findViewById(KitAlertIds.contentPanel)
        let customButtonPanel: AView? = customPanel.findViewById(KitAlertIds.buttonPanel)

        // Resolve the correct panels and remove the defaults, if needed.
        let topPanel = resolvePanel(customTopPanel, defaultTopPanel)
        let contentPanel = resolvePanel(customContentPanel, defaultContentPanel)
        let buttonPanel = resolvePanel(customButtonPanel, defaultButtonPanel)

        setupContent(contentPanel!)
        setupButtons(buttonPanel!)
        setupTitle(topPanel!)

        let hasCustomPanel = customPanel.visibility != AView.GONE
        let hasTopPanel = topPanel != nil && topPanel!.visibility != AView.GONE
        let hasButtonPanel = buttonPanel != nil && buttonPanel!.visibility != AView.GONE

        // Only display the text spacer if we don't have buttons.
        if !hasButtonPanel {
            if let content = contentPanel, let spacer: AView = content.findViewById(KitAlertIds.textSpacerNoButtons) {
                spacer.visibility = AView.VISIBLE
            }
        }

        if hasTopPanel {
            // Only clip scrolling content to padding if we have a title.
            mScrollView?.clipToPadding = true
            // Only show the divider if we have a title.
            var divider: AView? = nil
            if mMessage != nil || mListView != nil {
                divider = topPanel!.findViewById(KitAlertIds.titleDividerNoCustom)
            }
            divider?.visibility = AView.VISIBLE
        } else {
            if let content = contentPanel, let spacer: AView = content.findViewById(KitAlertIds.textSpacerNoTitle) {
                spacer.visibility = AView.VISIBLE
            }
        }

        mListView?.setHasDecor(hasTopPanel, hasButtonPanel)

        // Scroll indicators (API 23+ View scroll indicators, the indicator views removed) are not drawn on iOS.
        _ = hasCustomPanel

        if let listView = mListView, let items = mAdapterItems {
            let rowKind = mAdapterRowKind
            let checkedItems = mAdapterCheckedItems?()
            let theme = self.theme
            listView.setAdapter(items) { position, item in
                KitAlertListItemView(rowKind, theme, item, position)
            }
            if let checked = checkedItems {
                for (position, isChecked) in checked.enumerated() where isChecked && position < items.count {
                    listView.setItemChecked(position, true)
                }
            }
            let checkedItem = mCheckedItem
            if checkedItem > -1 {
                listView.setItemChecked(checkedItem, true)
                listView.setSelection(checkedItem)
            }
        }
    }

    private func setupCustomContent(_ customPanel: AViewGroup) {
        let customView: AView?
        if let v = mView {
            customView = v
        } else if let layout = mViewLayoutResId {
            customView = ALayoutInflater.from(mContext).inflate(layout, customPanel, false)
        } else {
            customView = nil
        }

        let hasCustomView = customView != nil
        if !hasCustomView || !KitAlertController.canTextInput(customView!) {
            mWindow.setFlags(KitAlertController.FLAG_ALT_FOCUSABLE_IM, KitAlertController.FLAG_ALT_FOCUSABLE_IM)
        }

        if let view = customView {
            let custom: AFrameLayout = mWindow.findViewById(KitAlertIds.custom)!
            custom.addView(view, AFrameLayout.LayoutParams(AViewGroup.LayoutParams.MATCH_PARENT,
                                                           AViewGroup.LayoutParams.MATCH_PARENT))
            if mViewSpacingSpecified {
                custom.setPadding(mViewSpacingLeft, mViewSpacingTop, mViewSpacingRight, mViewSpacingBottom)
            }
            if mListView != nil, let lp = customPanel.layoutParams as? ALinearLayout.LayoutParams {
                lp.weight = 0
            }
        } else {
            customPanel.visibility = AView.GONE
        }
    }

    /// WindowManager.LayoutParams.FLAG_ALT_FOCUSABLE_IM.
    static let FLAG_ALT_FOCUSABLE_IM = 0x00020000

    private func setupTitle(_ topPanel: AViewGroup) {
        if let customTitle = mCustomTitleView {
            // Add the custom title view directly to the topPanel layout
            topPanel.addView(customTitle, 0, ALinearLayout.LayoutParams(AViewGroup.LayoutParams.MATCH_PARENT,
                                                                        AViewGroup.LayoutParams.WRAP_CONTENT))
            // Hide the title template
            let titleTemplate: AView? = mWindow.findViewById(KitAlertIds.title_template)
            titleTemplate?.visibility = AView.GONE
        } else {
            mIconView = mWindow.findViewById(KitAlertIds.icon)
            let hasTextTitle = !(mTitle ?? "").isEmpty
            if hasTextTitle && mShowTitle {
                // Display the title if a title is supplied, else hide it.
                mTitleView = mWindow.findViewById(KitAlertIds.alertTitle)
                mTitleView?.setText(mTitle ?? "")
                // Do this last so that if the user has supplied any icons we use them instead of the default ones.
                // If the user has specified 0 then make it disappear.
                if let id = mIconId {
                    mIconView?.setImageResource(id)
                } else if let icon = mIcon {
                    mIconView?.setImageDrawable(icon)
                } else {
                    // Apply the padding from the icon to ensure the title is aligned correctly.
                    if let iconView = mIconView {
                        mTitleView?.setPadding(iconView.paddingLeft, iconView.paddingTop, iconView.paddingRight,
                                               iconView.paddingBottom)
                    }
                    mIconView?.visibility = AView.GONE
                }
            } else {
                // Hide the title template
                let titleTemplate: AView? = mWindow.findViewById(KitAlertIds.title_template)
                titleTemplate?.visibility = AView.GONE
                mIconView?.visibility = AView.GONE
                topPanel.visibility = AView.GONE
            }
        }
    }

    private func setupContent(_ contentPanel: AViewGroup) {
        mScrollView = mWindow.findViewById(KitAlertIds.scrollView)
        mScrollView?.isFocusable = false

        // Special case for users that only want to display a String
        mMessageView = contentPanel.findViewById(KitAlertIds.message)
        guard let messageView = mMessageView else { return }

        if let message = mMessage {
            messageView.setText(message)
        } else {
            messageView.visibility = AView.GONE
            mScrollView?.removeView(messageView)

            if let listView = mListView, let scrollView = mScrollView, let scrollParent = scrollView.parentGroup {
                let childIndex = scrollParent.indexOfChild(scrollView)
                scrollParent.removeViewAt(childIndex)
                scrollParent.addView(listView, childIndex, AFrameLayout.LayoutParams(AViewGroup.LayoutParams.MATCH_PARENT,
                                                                                     AViewGroup.LayoutParams.MATCH_PARENT))
            } else {
                contentPanel.visibility = AView.GONE
            }
        }
    }

    private func setupButtons(_ buttonPanel: AViewGroup) {
        let BIT_BUTTON_POSITIVE = 1
        let BIT_BUTTON_NEGATIVE = 2
        let BIT_BUTTON_NEUTRAL = 4
        var whichButtons = 0
        let handler: (AView) -> Void = { [unowned self] v in self.buttonClicked(v) }

        mButtonPositive = buttonPanel.findViewById(KitAlertIds.button1)
        mButtonPositive?.setOnClickListener(handler)
        if (mButtonPositiveText ?? "").isEmpty && mButtonPositiveIcon == nil {
            mButtonPositive?.visibility = AView.GONE
        } else {
            mButtonPositive?.setText(mButtonPositiveText ?? "")
            mButtonPositive?.visibility = AView.VISIBLE
            whichButtons |= BIT_BUTTON_POSITIVE
        }

        mButtonNegative = buttonPanel.findViewById(KitAlertIds.button2)
        mButtonNegative?.setOnClickListener(handler)
        if (mButtonNegativeText ?? "").isEmpty && mButtonNegativeIcon == nil {
            mButtonNegative?.visibility = AView.GONE
        } else {
            mButtonNegative?.setText(mButtonNegativeText ?? "")
            mButtonNegative?.visibility = AView.VISIBLE
            whichButtons |= BIT_BUTTON_NEGATIVE
        }

        mButtonNeutral = buttonPanel.findViewById(KitAlertIds.button3)
        mButtonNeutral?.setOnClickListener(handler)
        if (mButtonNeutralText ?? "").isEmpty && mButtonNeutralIcon == nil {
            mButtonNeutral?.visibility = AView.GONE
        } else {
            mButtonNeutral?.setText(mButtonNeutralText ?? "")
            mButtonNeutral?.visibility = AView.VISIBLE
            whichButtons |= BIT_BUTTON_NEUTRAL
        }

        // alertDialogCenterButtons is false in every theme of the app: no centred single button.
        let hasButtons = whichButtons != 0
        if !hasButtons {
            buttonPanel.visibility = AView.GONE
        }
    }

    // MARK: Layout (abc_alert_dialog_material / mtrl_alert_dialog / alert_dialog_material)

    private func buildAlertLayout() -> AView {
        let material = theme.kind == .material
        let MATCH = AViewGroup.LayoutParams.MATCH_PARENT
        let WRAP = AViewGroup.LayoutParams.WRAP_CONTENT
        let dialogPadding = aw_dpx(24)          // ?dialogPreferredPadding
        let paddingTop = aw_dpx(18)             // abc_dialog_padding_top_material

        let parentPanel = KitAlertDialogLayout()
        parentPanel.viewId = KitAlertIds.parentPanel
        parentPanel.orientation = ALinearLayout.VERTICAL
        parentPanel.gravity = AGravity.START | AGravity.TOP
        parentPanel.layoutParams = AFrameLayout.LayoutParams(MATCH, WRAP)

        // Title panel.
        let topPanel = ALinearLayout()
        topPanel.viewId = KitAlertIds.topPanel
        topPanel.orientation = ALinearLayout.VERTICAL
        let titleTemplate = ALinearLayout()
        titleTemplate.viewId = KitAlertIds.title_template
        titleTemplate.orientation = ALinearLayout.HORIZONTAL
        if !material {
            titleTemplate.gravity = AGravity.CENTER_VERTICAL | AGravity.START
        }
        titleTemplate.setPaddingRelative(dialogPadding, paddingTop, dialogPadding, 0)
        let icon = AImageView()
        icon.viewId = KitAlertIds.icon
        icon.scaleType = .FIT_CENTER
        let iconParams = ALinearLayout.LayoutParams(aw_dpx(32), aw_dpx(32))
        iconParams.marginEnd = aw_dpx(8)
        iconParams.rightMargin = aw_dpx(8)
        if material {
            iconParams.gravity = AGravity.START | AGravity.CENTER_VERTICAL
            icon.importantForAccessibility = AView.IMPORTANT_FOR_ACCESSIBILITY_NO
        }
        titleTemplate.addView(icon, iconParams)
        let title = KitDialogTitle(mediumTextSizePx: ATypedValue.toDimensionPixelSize(ATypedValue.COMPLEX_UNIT_SP,
                                                                                     theme.mediumTextSizeSp))
        title.viewId = KitAlertIds.alertTitle
        title.setTypeface(ATypeface.DEFAULT)
        title.applyXmlTextSize(theme.titleTextSizeSp)
        title.setLetterSpacing(theme.titleLetterSpacing)
        title.setTextColor(theme.titleColor)
        title.setSingleLine(true)
        title.ellipsize = .END
        title.textAlignment = AView.TEXT_ALIGNMENT_VIEW_START
        let titleParams = ALinearLayout.LayoutParams(theme.titleMatchParent ? MATCH : WRAP, WRAP)
        titleParams.gravity = material ? (AGravity.START | AGravity.CENTER_VERTICAL) : AGravity.START
        titleTemplate.addView(title, titleParams)
        topPanel.addView(titleTemplate, ALinearLayout.LayoutParams(MATCH, WRAP))
        let titleDivider = ASpace()
        titleDivider.viewId = KitAlertIds.titleDividerNoCustom
        titleDivider.visibility = AView.GONE
        topPanel.addView(titleDivider, ALinearLayout.LayoutParams(MATCH, aw_dpx(8)))
        parentPanel.addView(topPanel, ALinearLayout.LayoutParams(MATCH, WRAP))

        // Content panel: the message in a scroll view.
        let contentPanel = AFrameLayout()
        contentPanel.viewId = KitAlertIds.contentPanel
        contentPanel.minimumHeight = aw_dpx(48)
        let scrollView = AScrollView()
        scrollView.viewId = KitAlertIds.scrollView
        scrollView.clipToPadding = false
        let scrollContent = ALinearLayout()
        scrollContent.orientation = ALinearLayout.VERTICAL
        let spacerNoTitle = ASpace()
        spacerNoTitle.viewId = KitAlertIds.textSpacerNoTitle
        spacerNoTitle.visibility = AView.GONE
        scrollContent.addView(spacerNoTitle, ALinearLayout.LayoutParams(MATCH, paddingTop))
        let message = ATextView()
        message.viewId = KitAlertIds.message
        message.setTypeface(ATypeface.DEFAULT)
        message.applyXmlTextSize(theme.messageTextSizeSp)
        message.setLetterSpacing(theme.messageLetterSpacing)
        message.setTextColor(theme.messageColor)
        message.setPaddingRelative(dialogPadding, 0, dialogPadding, 0)
        scrollContent.addView(message, ALinearLayout.LayoutParams(MATCH, WRAP))
        let spacerNoButtons = ASpace()
        spacerNoButtons.viewId = KitAlertIds.textSpacerNoButtons
        spacerNoButtons.visibility = AView.GONE
        scrollContent.addView(spacerNoButtons, ALinearLayout.LayoutParams(MATCH, paddingTop))
        scrollView.addView(scrollContent, AFrameLayout.LayoutParams(MATCH, WRAP))
        contentPanel.addView(scrollView, AFrameLayout.LayoutParams(MATCH, WRAP))
        parentPanel.addView(contentPanel, ALinearLayout.LayoutParams(MATCH, WRAP))

        // Custom panel.
        let customPanel = AFrameLayout()
        customPanel.viewId = KitAlertIds.customPanel
        customPanel.minimumHeight = aw_dpx(48)
        let custom = AFrameLayout()
        custom.viewId = KitAlertIds.custom
        customPanel.addView(custom, AFrameLayout.LayoutParams(MATCH, WRAP))
        parentPanel.addView(customPanel, ALinearLayout.LayoutParams(MATCH, WRAP))

        // Button panel: a ButtonBarLayout in a fill-viewport scroll view.
        let buttonPanel = AScrollView()
        buttonPanel.viewId = KitAlertIds.buttonPanel
        buttonPanel.isFillViewport = true
        let buttonBar = KitButtonBarLayout()
        buttonBar.orientation = ALinearLayout.HORIZONTAL
        buttonBar.gravity = AGravity.BOTTOM
        buttonBar.layoutDirection = AView.LAYOUT_DIRECTION_LOCALE
        let barH = aw_dpx(theme.buttonBarPaddingHorizontalDp)
        let barV = aw_dpx(theme.buttonBarPaddingVerticalDp)
        if theme.kind == .appCompat {
            buttonBar.setPadding(barH, barV, barH, barV)
        } else {
            buttonBar.setPaddingRelative(barH, barV, barH, barV)
        }
        let neutral = makeButton(KitAlertIds.button3, marginStartDp: 0)
        buttonBar.addView(neutral.button, neutral.params)
        let spacer = ASpace()
        spacer.viewId = KitAlertIds.spacer
        spacer.visibility = AView.INVISIBLE
        buttonBar.addView(spacer, ALinearLayout.LayoutParams(0, 0, 1))
        let negative = makeButton(KitAlertIds.button2, marginStartDp: theme.actionButtonMarginStartDp)
        buttonBar.addView(negative.button, negative.params)
        let positive = makeButton(KitAlertIds.button1, marginStartDp: theme.actionButtonMarginStartDp)
        buttonBar.addView(positive.button, positive.params)
        buttonBar.finishInflate()
        buttonPanel.addView(buttonBar, AFrameLayout.LayoutParams(MATCH, WRAP))
        parentPanel.addView(buttonPanel, ALinearLayout.LayoutParams(MATCH, WRAP))
        return parentPanel
    }

    /// A buttonBar{Positive,Negative,Neutral}ButtonStyle button: Widget.MaterialComponents.Button.TextButton.Dialog
    /// (layout_marginStart and layout_marginLeft 8 dp) or its .Flush variant (0).
    private func makeButton(_ id: String, marginStartDp: Float) -> (button: AButton, params: ALinearLayout.LayoutParams) {
        let button = AButton(style: .TEXT_DIALOG)
        button.viewId = id
        let params = ALinearLayout.LayoutParams(AViewGroup.LayoutParams.WRAP_CONTENT, AViewGroup.LayoutParams.WRAP_CONTENT)
        if marginStartDp > 0 {
            params.marginStart = aw_dpx(marginStartDp)
            params.leftMargin = aw_dpx(marginStartDp)
        }
        return (button, params)
    }
}

/// AlertController.AlertParams: what the Builder collected, applied to the controller at create().
final class KitAlertParams {
    let mContext: AContext
    var mIconId: ADrawableRes?
    var mIcon: ADrawable?
    var mTitle: String?
    var mCustomTitleView: AView?
    var mMessage: String?
    var mPositiveButtonText: String?
    var mPositiveButtonIcon: ADrawable?
    var mPositiveButtonListener: ADialogInterface.OnClickListener?
    var mNegativeButtonText: String?
    var mNegativeButtonIcon: ADrawable?
    var mNegativeButtonListener: ADialogInterface.OnClickListener?
    var mNeutralButtonText: String?
    var mNeutralButtonIcon: ADrawable?
    var mNeutralButtonListener: ADialogInterface.OnClickListener?
    var mCancelable = true
    var mOnCancelListener: ADialogInterface.OnCancelListener?
    var mOnDismissListener: ADialogInterface.OnDismissListener?
    var mItems: [String]?
    var mOnClickListener: ADialogInterface.OnClickListener?
    var mViewLayoutResId: String?
    var mView: AView?
    var mViewSpacingLeft = 0
    var mViewSpacingTop = 0
    var mViewSpacingRight = 0
    var mViewSpacingBottom = 0
    var mViewSpacingSpecified = false
    /// The caller's checkedItems (a Java boolean[] the dialog updates on each click; a copy here).
    var mCheckedItems: [Bool]?
    var mIsMultiChoice = false
    var mIsSingleChoice = false
    var mCheckedItem = -1
    var mOnCheckboxClickListener: ADialogInterface.OnMultiChoiceClickListener?

    init(_ context: AContext) {
        mContext = context
    }

    func apply(_ dialog: KitAlertController) {
        if let customTitle = mCustomTitleView {
            dialog.setCustomTitle(customTitle)
        } else {
            if let title = mTitle {
                dialog.setTitle(title)
            }
            if let icon = mIcon {
                dialog.setIcon(icon)
            }
            if let iconId = mIconId {
                dialog.setIcon(res: iconId)
            }
        }
        if let message = mMessage {
            dialog.setMessage(message)
        }
        if mPositiveButtonText != nil || mPositiveButtonIcon != nil {
            dialog.setButton(ADialogInterface.BUTTON_POSITIVE, mPositiveButtonText, mPositiveButtonListener, mPositiveButtonIcon)
        }
        if mNegativeButtonText != nil || mNegativeButtonIcon != nil {
            dialog.setButton(ADialogInterface.BUTTON_NEGATIVE, mNegativeButtonText, mNegativeButtonListener, mNegativeButtonIcon)
        }
        if mNeutralButtonText != nil || mNeutralButtonIcon != nil {
            dialog.setButton(ADialogInterface.BUTTON_NEUTRAL, mNeutralButtonText, mNeutralButtonListener, mNeutralButtonIcon)
        }
        // For a list, the client can either supply an array of items or an adapter or a cursor
        if mItems != nil {
            createListView(dialog)
        }
        if let view = mView {
            if mViewSpacingSpecified {
                dialog.setView(view, mViewSpacingLeft, mViewSpacingTop, mViewSpacingRight, mViewSpacingBottom)
            } else {
                dialog.setView(view)
            }
        } else if let layout = mViewLayoutResId {
            dialog.setView(res: layout)
        }
    }

    private func createListView(_ dialog: KitAlertController) {
        let listView = AAlertDialog.RecycleListView(paddingTopNoTitle: aw_dpx(8), paddingBottomNoButtons: aw_dpx(8))
        if mIsMultiChoice {
            dialog.mAdapterRowKind = .multiple
            // The adapter keeps the AlertParams (and its checkedItems array) alive, like the Java inner class.
            dialog.mAdapterCheckedItems = { self.mCheckedItems }
        } else {
            dialog.mAdapterRowKind = mIsSingleChoice ? .single : .simple
        }
        dialog.mAdapterItems = mItems ?? []
        dialog.mCheckedItem = mCheckedItem

        if let listener = mOnClickListener {
            let isSingleChoice = mIsSingleChoice
            listView.onItemClickListener = { [unowned dialog] position in
                listener(dialog.mDialog, position)
                if !isSingleChoice {
                    dialog.mDialog.dismiss()
                }
            }
        } else if let listener = mOnCheckboxClickListener {
            listView.onItemClickListener = { [unowned dialog, unowned listView] position in
                if self.mCheckedItems != nil, position < self.mCheckedItems!.count {
                    self.mCheckedItems![position] = listView.isItemChecked(position)
                }
                listener(dialog.mDialog, position, listView.isItemChecked(position))
            }
        }

        if mIsSingleChoice {
            listView.choiceMode = AAlertDialog.RecycleListView.CHOICE_MODE_SINGLE
        } else if mIsMultiChoice {
            listView.choiceMode = AAlertDialog.RecycleListView.CHOICE_MODE_MULTIPLE
        }
        dialog.mListView = listView
    }
}

// MARK: - Alert views (AlertDialogLayout, ButtonBarLayout, DialogTitle, list rows)

/// androidx.appcompat.widget.AlertDialogLayout: the content panel gets the height left by the title and the
/// buttons; the buttons shrink to their minimum before the content does.
final class KitAlertDialogLayout: ALinearLayout {
    override init() {
        super.init()
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    override func onMeasure(_ widthMeasureSpec: Int, _ heightMeasureSpec: Int) {
        if !tryOnMeasure(widthMeasureSpec, heightMeasureSpec) {
            // Failed to perform custom measurement, let superclass handle it.
            super.onMeasure(widthMeasureSpec, heightMeasureSpec)
        }
    }

    private func tryOnMeasure(_ widthMeasureSpec: Int, _ heightMeasureSpec: Int) -> Bool {
        var topPanel: AView? = nil
        var buttonPanel: AView? = nil
        var middlePanel: AView? = nil

        let count = childCount
        for i in kuntil(0, count) {
            guard let child = getChildAt(i) else { continue }
            if child.visibility == AView.GONE {
                continue
            }
            let id = child.viewId
            if id == KitAlertIds.topPanel {
                topPanel = child
            } else if id == KitAlertIds.buttonPanel {
                buttonPanel = child
            } else if id == KitAlertIds.contentPanel || id == KitAlertIds.customPanel {
                if middlePanel != nil {
                    // Both the content and custom are visible. Abort!
                    return false
                }
                middlePanel = child
            } else {
                // Unknown top-level child. Abort!
                return false
            }
        }

        let heightMode = AMeasureSpec.getMode(heightMeasureSpec)
        let heightSize = AMeasureSpec.getSize(heightMeasureSpec)
        let widthMode = AMeasureSpec.getMode(widthMeasureSpec)

        var childState = 0
        var usedHeight = paddingTop + paddingBottom

        if let top = topPanel {
            top.measure(widthMeasureSpec, AMeasureSpec.UNSPECIFIED)
            usedHeight += top.measuredHeight
            childState = AView.combineMeasuredStates(childState, top.measuredState)
        }

        var buttonHeight = 0
        var buttonWantsHeight = 0
        if let buttons = buttonPanel {
            buttons.measure(widthMeasureSpec, AMeasureSpec.UNSPECIFIED)
            buttonHeight = KitAlertDialogLayout.resolveMinimumHeight(buttons)
            buttonWantsHeight = buttons.measuredHeight - buttonHeight
            usedHeight += buttonHeight
            childState = AView.combineMeasuredStates(childState, buttons.measuredState)
        }

        var middleHeight = 0
        if let middle = middlePanel {
            let childHeightSpec: Int
            if heightMode == AMeasureSpec.UNSPECIFIED {
                childHeightSpec = AMeasureSpec.UNSPECIFIED
            } else {
                childHeightSpec = AMeasureSpec.makeMeasureSpec(max(0, heightSize - usedHeight), heightMode)
            }
            middle.measure(widthMeasureSpec, childHeightSpec)
            middleHeight = middle.measuredHeight
            usedHeight += middleHeight
            childState = AView.combineMeasuredStates(childState, middle.measuredState)
        }

        var remainingHeight = heightSize - usedHeight

        // Time for the "real" button measure pass. If we have remaining space, make the button pane bigger up to its
        // target height. Otherwise, just remeasure the button at whatever height it needs.
        if let buttons = buttonPanel {
            usedHeight -= buttonHeight
            let heightToGive = min(remainingHeight, buttonWantsHeight)
            if heightToGive > 0 {
                remainingHeight -= heightToGive
                buttonHeight += heightToGive
            }
            let childHeightSpec = AMeasureSpec.makeMeasureSpec(buttonHeight, AMeasureSpec.EXACTLY)
            buttons.measure(widthMeasureSpec, childHeightSpec)
            usedHeight += buttons.measuredHeight
            childState = AView.combineMeasuredStates(childState, buttons.measuredState)
        }

        // If we still have remaining space, make the middle pane bigger up to the maximum height.
        if let middle = middlePanel, remainingHeight > 0 {
            usedHeight -= middleHeight
            let heightToGive = remainingHeight
            remainingHeight -= heightToGive
            middleHeight += heightToGive
            // Pass the same height mode as we're using for the dialog itself. If it's EXACTLY, then the middle pane
            // MUST use the entire height.
            let childHeightSpec = AMeasureSpec.makeMeasureSpec(middleHeight, heightMode)
            middle.measure(widthMeasureSpec, childHeightSpec)
            usedHeight += middle.measuredHeight
            childState = AView.combineMeasuredStates(childState, middle.measuredState)
        }

        // Compute desired width as maximum child width.
        var maxWidth = 0
        for i in kuntil(0, count) {
            if let child = getChildAt(i), child.visibility != AView.GONE {
                maxWidth = max(maxWidth, child.measuredWidth)
            }
        }
        maxWidth += paddingLeft + paddingRight

        let widthSizeAndState = AView.resolveSizeAndState(maxWidth, widthMeasureSpec, childState)
        let heightSizeAndState = AView.resolveSizeAndState(usedHeight, heightMeasureSpec, 0)
        setMeasuredDimension(widthSizeAndState, heightSizeAndState)

        // If the children weren't already measured EXACTLY, we need to run another measure pass to for MATCH_PARENT
        // widths.
        if widthMode != AMeasureSpec.EXACTLY {
            forceUniformWidth(count, heightMeasureSpec)
        }
        return true
    }

    private func forceUniformWidth(_ count: Int, _ heightMeasureSpec: Int) {
        // Pretend that the linear layout has an exact size.
        let uniformMeasureSpec = AMeasureSpec.makeMeasureSpec(measuredWidth, AMeasureSpec.EXACTLY)
        for i in kuntil(0, count) {
            guard let child = getChildAt(i), child.visibility != AView.GONE,
                  let lp = child.layoutParams else { continue }
            if lp.width == AViewGroup.LayoutParams.MATCH_PARENT {
                // Temporarily force children to reuse their old measured height.
                let oldHeight = lp.height
                lp.height = child.measuredHeight
                // Remeasure with new dimensions.
                measureChildWithMargins(child, uniformMeasureSpec, 0, heightMeasureSpec, 0)
                lp.height = oldHeight
            }
        }
    }

    /// ViewCompat.getMinimumHeight, descending into single-child groups.
    static func resolveMinimumHeight(_ v: AView) -> Int {
        let minHeight = v.minimumHeight
        if minHeight > 0 {
            return minHeight
        }
        if let vg = v as? AViewGroup, vg.childCount == 1, let only = vg.getChildAt(0) {
            return resolveMinimumHeight(only)
        }
        return 0
    }

    override func onLayout(_ changed: Bool, _ left: Int, _ top: Int, _ right: Int, _ bottom: Int) {
        let paddingLeft = self.paddingLeft
        // Where right end of child should go
        let width = right - left
        let childRight = width - paddingRight
        // Space available for child
        let childSpace = width - paddingLeft - paddingRight
        let totalLength = measuredHeight
        let count = childCount
        let gravity = self.gravity
        let majorGravity = gravity & AGravity.VERTICAL_GRAVITY_MASK
        let minorGravity = gravity & AGravity.RELATIVE_HORIZONTAL_GRAVITY_MASK

        var childTop: Int
        switch majorGravity {
        case AGravity.BOTTOM:
            // totalLength contains the padding already
            childTop = paddingTop + bottom - top - totalLength
        case AGravity.CENTER_VERTICAL:
            // totalLength contains the padding already
            childTop = paddingTop + (bottom - top - totalLength) / 2
        default:
            childTop = paddingTop
        }

        for i in kuntil(0, count) {
            guard let child = getChildAt(i), child.visibility != AView.GONE else { continue }
            let childWidth = child.measuredWidth
            let childHeight = child.measuredHeight
            let lp = child.layoutParams as? ALinearLayout.LayoutParams
            var layoutGravity = lp?.gravity ?? -1
            if layoutGravity < 0 {
                layoutGravity = minorGravity
            }
            let layoutDirection = isLayoutRtl ? AView.LAYOUT_DIRECTION_RTL : AView.LAYOUT_DIRECTION_LTR
            let absoluteGravity = AGravity.getAbsoluteGravity(layoutGravity, layoutDirection)
            let leftMargin = lp?.leftMargin ?? 0
            let rightMargin = lp?.rightMargin ?? 0
            let childLeft: Int
            switch absoluteGravity & AGravity.HORIZONTAL_GRAVITY_MASK {
            case AGravity.CENTER_HORIZONTAL:
                childLeft = paddingLeft + ((childSpace - childWidth) / 2) + leftMargin - rightMargin
            case AGravity.RIGHT:
                childLeft = childRight - childWidth - rightMargin
            default:
                childLeft = paddingLeft + leftMargin
            }
            childTop += lp?.topMargin ?? 0
            child.layout(childLeft, childTop, childLeft + childWidth, childTop + childHeight)
            childTop += childHeight + (lp?.bottomMargin ?? 0)
        }
    }
}

/// androidx.appcompat.widget.ButtonBarLayout: the buttons stack vertically (positive on top) when they do not fit
/// side by side.
final class KitButtonBarLayout: ALinearLayout {
    /// Amount of the second button to "peek" above the fold when stacked.
    private static let PEEK_BUTTON_DP = 16

    private var mAllowStacking = true
    private var mStacked = false
    private var mLastWidthSize = -1

    override init() {
        super.init()
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    /// The constructor's check: a layout inflated vertical is stacked (the alert layouts are horizontal).
    func finishInflate() {
        if orientation == ALinearLayout.VERTICAL {
            setStacked(mAllowStacking)
        }
    }

    func setAllowStacking(_ allowStacking: Bool) {
        if mAllowStacking != allowStacking {
            mAllowStacking = allowStacking
            if !mAllowStacking && isStacked {
                setStacked(false)
            }
            requestLayout()
        }
    }

    override func onMeasure(_ widthMeasureSpec: Int, _ heightMeasureSpec: Int) {
        let widthSize = AMeasureSpec.getSize(widthMeasureSpec)
        if mAllowStacking {
            if widthSize > mLastWidthSize && isStacked {
                // We're being measured wider this time, try un-stacking.
                setStacked(false)
            }
            mLastWidthSize = widthSize
        }

        var needsRemeasure = false

        // If we're not stacked, make sure the measure spec is AT_MOST rather than EXACTLY. This ensures that we'll
        // still get TOO_SMALL so that we know to stack the buttons.
        let initialWidthMeasureSpec: Int
        if !isStacked && AMeasureSpec.getMode(widthMeasureSpec) == AMeasureSpec.EXACTLY {
            initialWidthMeasureSpec = AMeasureSpec.makeMeasureSpec(widthSize, AMeasureSpec.AT_MOST)
            // We'll need to remeasure again to fill excess space.
            needsRemeasure = true
        } else {
            initialWidthMeasureSpec = widthMeasureSpec
        }

        super.onMeasure(initialWidthMeasureSpec, heightMeasureSpec)

        if mAllowStacking && !isStacked {
            let measuredWidth = measuredWidthAndState
            let measuredWidthState = measuredWidth & AView.MEASURED_STATE_MASK
            let stack = measuredWidthState == AView.MEASURED_STATE_TOO_SMALL
            if stack {
                setStacked(true)
                // Measure again in the new orientation.
                needsRemeasure = true
            }
        }

        if needsRemeasure {
            super.onMeasure(widthMeasureSpec, heightMeasureSpec)
        }

        // Compute minimum height such that, when stacked, some portion of the second button is visible.
        var minHeight = 0
        let firstVisible = getNextVisibleChildIndex(0)
        if firstVisible >= 0, let firstButton = getChildAt(firstVisible) {
            let firstParams = firstButton.layoutParams as? AViewGroup.MarginLayoutParams
            minHeight += paddingTop + firstButton.measuredHeight + (firstParams?.topMargin ?? 0)
                + (firstParams?.bottomMargin ?? 0)
            if isStacked {
                let secondVisible = getNextVisibleChildIndex(firstVisible + 1)
                if secondVisible >= 0, let second = getChildAt(secondVisible) {
                    minHeight += second.paddingTop + Int(Float(KitButtonBarLayout.PEEK_BUTTON_DP) * AWidgetEnv.density)
                }
            } else {
                minHeight += paddingBottom
            }
        }

        if minimumHeight != minHeight {
            setMinimumHeight(minHeight)
            // Re-measure immediately to fill excess space.
            if heightMeasureSpec == AMeasureSpec.UNSPECIFIED {
                super.onMeasure(widthMeasureSpec, heightMeasureSpec)
            }
        }
    }

    private func getNextVisibleChildIndex(_ index: Int) -> Int {
        var i = index
        let count = childCount
        while i < count {
            if getChildAt(i)?.visibility == AView.VISIBLE {
                return i
            }
            i += 1
        }
        return -1
    }

    private func setStacked(_ stacked: Bool) {
        if mStacked != stacked && (!stacked || mAllowStacking) {
            mStacked = stacked
            orientation = stacked ? ALinearLayout.VERTICAL : ALinearLayout.HORIZONTAL
            gravity = stacked ? AGravity.END : AGravity.BOTTOM
            let spacer: AView? = findViewById(KitAlertIds.spacer)
            spacer?.visibility = stacked ? AView.GONE : AView.INVISIBLE
            // Reverse the child order. This is specific to the Material button bar's layout XML and will probably
            // not generalize.
            let childCount = self.childCount
            var i = childCount - 2
            while i >= 0 {
                if let child = getChildAt(i) {
                    bringChildToFront(child)
                }
                i -= 1
            }
        }
    }

    private var isStacked: Bool { mStacked }
}

/// androidx.appcompat.widget.DialogTitle: a title that would be ellipsized gets two lines at textAppearanceMedium.
final class KitDialogTitle: ATextView {
    private let mediumTextSizePx: Int

    init(mediumTextSizePx: Int) {
        self.mediumTextSizePx = mediumTextSizePx
        super.init()
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    override func onMeasure(_ widthMeasureSpec: Int, _ heightMeasureSpec: Int) {
        super.onMeasure(widthMeasureSpec, heightMeasureSpec)
        if let layout = self.layout {
            let lineCount = layout.lineCount
            if lineCount > 0 {
                let ellipsisCount = layout.getEllipsisCount(lineCount - 1)
                if ellipsisCount > 0 {
                    setSingleLine(false)
                    setMaxLines(2)
                    if mediumTextSizePx != 0 {
                        // textSize is already expressed in pixels
                        setTextSize(ATypedValue.COMPLEX_UNIT_PX, Float(mediumTextSizePx))
                    }
                    super.onMeasure(widthMeasureSpec, heightMeasureSpec)
                }
            }
        }
    }
}

/// One row of the alert list: select_dialog_item / select_dialog_multichoice / select_dialog_singlechoice
/// (CheckedTextView with the check box / radio as its start drawable).
final class KitAlertListItemView: ATextView {
    enum Kind { case simple, multiple, single }

    let kind: Kind
    let position: Int
    private(set) var indicator: KitChoiceIndicatorDrawable?

    /// CheckedTextView.setChecked.
    var isChecked = false {
        didSet {
            if oldValue == isChecked { return }
            indicator?.checked = isChecked
            accessibilityTraits = isChecked ? [.button, .selected] : .button
            invalidate()
        }
    }

    init(_ kind: Kind, _ theme: KitAlertTheme, _ text: String, _ position: Int) {
        self.kind = kind
        self.position = position
        super.init()
        viewId = KitAlertIds.text1
        setTypeface(ATypeface.DEFAULT)
        minHeight = aw_dpx(48)                     // ?listPreferredItemHeightSmall
        background = KitListSelectorDrawable()
        accessibilityTraits = .button
        switch kind {
        case .simple:
            applyXmlTextSize(theme.itemTextSizeSp)
            setLetterSpacing(theme.itemLetterSpacing)
            setTextColor(theme.itemColor)
            setGravity(AGravity.CENTER_VERTICAL)
            // ?listPreferredItemPaddingLeft / Right = 24 dip in the dialog themes.
            if theme.kind == .framework || theme.kind == .plain {
                setPaddingRelative(aw_dpx(24), 0, aw_dpx(24), 0)
            } else {
                setPadding(aw_dpx(24), 0, aw_dpx(24), 0)
            }
        case .multiple, .single:
            applyXmlTextSize(theme.choiceTextSizeSp)
            setLetterSpacing(theme.choiceLetterSpacing)
            setTextColor(theme.choiceColor)
            if theme.kind == .material {
                setGravity(AGravity.LEFT | AGravity.CENTER_VERTICAL)
                textAlignment = AView.TEXT_ALIGNMENT_VIEW_START
            } else {
                setGravity(AGravity.CENTER_VERTICAL)
            }
            // abc_select_dialog_padding_start_material 20 dp, ?dialogPreferredPadding 24 dp.
            setPaddingRelative(aw_dpx(20), 0, aw_dpx(24), 0)
            let drawable = KitChoiceIndicatorDrawable(kind == .multiple ? .multiple : .single, theme.checkedColor,
                                                      theme.uncheckedColor)
            indicator = drawable
            setCompoundDrawablesRelativeWithIntrinsicBounds(drawable, nil, nil, nil)
            compoundDrawablePadding = aw_dpx(20)
        }
        setText(text)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }
}

/// The Material check box / radio button vectors (btn_checkbox_*_mtrl, btn_radio_*_mtrl, 32 dp) tinted with the
/// theme's activated / normal control colours.
final class KitChoiceIndicatorDrawable: ADrawable {
    enum Kind { case multiple, single }

    let kind: Kind
    let checkedColor: Int
    let uncheckedColor: Int
    var checked = false {
        didSet { if oldValue != checked { invalidateSelf() } }
    }
    private let paint = APaint(APaint.ANTI_ALIAS_FLAG)

    init(_ kind: Kind, _ checkedColor: Int, _ uncheckedColor: Int) {
        self.kind = kind
        self.checkedColor = checkedColor
        self.uncheckedColor = uncheckedColor
        super.init()
    }

    override var intrinsicWidth: Int { aw_dpx(32) }
    override var intrinsicHeight: Int { aw_dpx(32) }

    override func draw(_ canvas: ACanvas) {
        let b = bounds
        if b.isEmpty() { return }
        // One vector unit is one dp of the 32 dp box; the shapes are centred.
        let unit = Float(b.width()) / 32
        let cx = Float(b.left) + 16 * unit
        let cy = Float(b.top) + 16 * unit
        let color = checked ? checkedColor : uncheckedColor
        paint.color = color
        paint.alpha = AColor.alpha(color) * alpha / 255
        switch kind {
        case .multiple:
            let path = APath()
            path.fillType = .EVEN_ODD
            path.addRoundRect(ARectF(cx - 9 * unit, cy - 9 * unit, cx + 9 * unit, cy + 9 * unit), 2 * unit, 2 * unit, .CW)
            if checked {
                // check_path_merged: the box with the check mark cut out.
                let points: [(Float, Float)] = [(-2, 5.0000153), (-7, 0), (-5.585907, -1.414093), (-2, 2.1720138),
                                                (5.585907, -5.414093), (7, -4), (-2, 5.0000153)]
                path.moveTo(cx + points[0].0 * unit, cy + points[0].1 * unit)
                for p in points.dropFirst() {
                    path.lineTo(cx + p.0 * unit, cy + p.1 * unit)
                }
                path.close()
            } else {
                // box_inner_merged: the 2 dp frame (inner square -7..7).
                path.addRect(ARectF(cx - 7 * unit, cy - 7 * unit, cx + 7 * unit, cy + 7 * unit), .CW)
            }
            paint.style = .FILL
            canvas.drawPath(path, paint)
        case .single:
            paint.style = .STROKE
            paint.strokeWidth = 2 * unit
            canvas.drawCircle(cx, cy, 9 * unit, paint)
            if checked {
                paint.style = .FILL
                canvas.drawCircle(cx, cy, 5 * unit, paint)
            }
        }
    }
}

/// ?listChoiceBackgroundIndicator: the pressed highlight of a list row (colorControlHighlight #1F000000).
final class KitListSelectorDrawable: ADrawable {
    private var pressed = false
    private let paint = APaint(APaint.ANTI_ALIAS_FLAG)

    override var isStateful: Bool { true }

    override func onStateChange(_ state: [Int]) -> Bool {
        let p = state.contains(AStateSet.state_pressed)
        if p != pressed {
            pressed = p
            return true
        }
        return false
    }

    override func draw(_ canvas: ACanvas) {
        if !pressed { return }
        paint.color = argbInt(0x1F000000)
        paint.style = .FILL
        canvas.drawRect(bounds, paint)
    }
}

// MARK: - The dialog window on screen

/// WindowManager / ViewRootImpl window geometry for floating windows (px).
enum KitWindowLayout {
    /// config_prefDialogWidth: 320 dp, 440 dp on large screens, 580 dp from sw600dp (TypedValue.getDimension -> int).
    static func prefDialogWidthPx() -> Int {
        let config = AConfiguration.current
        let dp: Float
        if config.smallestScreenWidthDp >= 600 {
            dp = 580
        } else if (config.screenLayout & AConfiguration.SCREENLAYOUT_SIZE_MASK) >= AConfiguration.SCREENLAYOUT_SIZE_LARGE {
            dp = 440
        } else {
            dp = 320
        }
        return Int(dp * AWidgetEnv.density)
    }

    /// ViewRootImpl.getRootMeasureSpec.
    static func rootMeasureSpec(_ windowSize: Int, _ rootDimension: Int) -> Int {
        switch rootDimension {
        case AWindowManager.LayoutParams.MATCH_PARENT:
            // Window can't resize. Force root view to be windowSize.
            return AMeasureSpec.makeMeasureSpec(windowSize, AMeasureSpec.EXACTLY)
        case AWindowManager.LayoutParams.WRAP_CONTENT:
            // Window can resize. Set max size for root view.
            return AMeasureSpec.makeMeasureSpec(windowSize, AMeasureSpec.AT_MOST)
        default:
            // Window wants to be an exact size. Force root view to be that size.
            return AMeasureSpec.makeMeasureSpec(rootDimension, AMeasureSpec.EXACTLY)
        }
    }

    /// ViewRootImpl.measureHierarchy: a WRAP_CONTENT window is first measured at config_prefDialogWidth, then halfway
    /// to the available width, then at the available width.
    static func measureHierarchy(_ host: AView, _ lp: AWindowManager.LayoutParams, _ desiredWindowWidth: Int,
                                 _ desiredWindowHeight: Int) {
        var goodMeasure = false
        if lp.width == AWindowManager.LayoutParams.WRAP_CONTENT {
            // On large screens, we don't want to allow dialogs to just stretch to fill the entire width of the screen
            // to display one line of text. First try doing the layout at a smaller size to see if it will fit.
            var baseSize = prefDialogWidthPx()
            if baseSize != 0 && desiredWindowWidth > baseSize {
                var childWidthMeasureSpec = rootMeasureSpec(baseSize, lp.width)
                let childHeightMeasureSpec = rootMeasureSpec(desiredWindowHeight, lp.height)
                host.measure(childWidthMeasureSpec, childHeightMeasureSpec)
                if (host.measuredWidthAndState & AView.MEASURED_STATE_TOO_SMALL) == 0 {
                    goodMeasure = true
                } else {
                    // Didn't fit in that size... try expanding a bit.
                    baseSize = (baseSize + desiredWindowWidth) / 2
                    childWidthMeasureSpec = rootMeasureSpec(baseSize, lp.width)
                    host.measure(childWidthMeasureSpec, childHeightMeasureSpec)
                    if (host.measuredWidthAndState & AView.MEASURED_STATE_TOO_SMALL) == 0 {
                        goodMeasure = true
                    }
                }
            }
        }
        if !goodMeasure {
            let childWidthMeasureSpec = rootMeasureSpec(desiredWindowWidth, lp.width)
            let childHeightMeasureSpec = rootMeasureSpec(desiredWindowHeight, lp.height)
            host.measure(childWidthMeasureSpec, childHeightMeasureSpec)
        }
    }

    private static let AXIS_SPECIFIED = 0x0001
    private static let AXIS_PULL_BEFORE = 0x0002
    private static let AXIS_PULL_AFTER = 0x0004
    private static let AXIS_X_SHIFT = 0
    private static let AXIS_Y_SHIFT = 4

    /// android.view.Gravity.apply (absolute gravity, no clipping flags).
    static func apply(_ gravity: Int, _ w: Int, _ h: Int, _ container: ARect, _ xAdj: Int, _ yAdj: Int) -> ARect {
        let out = ARect()
        switch gravity & ((AXIS_PULL_BEFORE | AXIS_PULL_AFTER) << AXIS_X_SHIFT) {
        case 0:
            out.left = container.left + ((container.right - container.left - w) / 2) + xAdj
            out.right = out.left + w
        case AXIS_PULL_BEFORE << AXIS_X_SHIFT:
            out.left = container.left + xAdj
            out.right = out.left + w
        case AXIS_PULL_AFTER << AXIS_X_SHIFT:
            out.right = container.right - xAdj
            out.left = out.right - w
        default:
            out.left = container.left + xAdj
            out.right = container.right + xAdj
        }
        switch gravity & ((AXIS_PULL_BEFORE | AXIS_PULL_AFTER) << AXIS_Y_SHIFT) {
        case 0:
            out.top = container.top + ((container.bottom - container.top - h) / 2) + yAdj
            out.bottom = out.top + h
        case AXIS_PULL_BEFORE << AXIS_Y_SHIFT:
            out.top = container.top + yAdj
            out.bottom = out.top + h
        case AXIS_PULL_AFTER << AXIS_Y_SHIFT:
            out.bottom = container.bottom - yAdj
            out.top = out.bottom - h
        default:
            out.top = container.top + yAdj
            out.bottom = container.bottom + yAdj
        }
        return out
    }

    /// android.view.Gravity.applyDisplay without the DISPLAY_CLIP flags: the frame moves inside the display frame, and
    /// a frame larger than the display takes the display's extent.
    static func applyDisplay(_ display: ARect, _ inoutObj: ARect) {
        var off = 0
        if inoutObj.top < display.top {
            off = display.top - inoutObj.top
        } else if inoutObj.bottom > display.bottom {
            off = display.bottom - inoutObj.bottom
        }
        if off != 0 {
            if inoutObj.height() > (display.bottom - display.top) {
                inoutObj.top = display.top
                inoutObj.bottom = display.bottom
            } else {
                inoutObj.top += off
                inoutObj.bottom += off
            }
        }
        off = 0
        if inoutObj.left < display.left {
            off = display.left - inoutObj.left
        } else if inoutObj.right > display.right {
            off = display.right - inoutObj.right
        }
        if off != 0 {
            if inoutObj.width() > (display.right - display.left) {
                inoutObj.left = display.left
                inoutObj.right = display.right
            } else {
                inoutObj.left += off
                inoutObj.right += off
            }
        }
    }

    /// The window frame of a floating window in `display` (the screen minus the system bars), px.
    static func computeFrame(_ lp: AWindowManager.LayoutParams, _ w: Int, _ h: Int, _ display: ARect, _ rtl: Bool) -> ARect {
        let gravity = AGravity.getAbsoluteGravity(lp.gravity, rtl ? AView.LAYOUT_DIRECTION_RTL : AView.LAYOUT_DIRECTION_LTR)
        let pw = display.width(), ph = display.height()
        let frame = apply(gravity, w, h, display, Int(Float(lp.x) + lp.horizontalMargin * Float(pw)),
                          Int(Float(lp.y) + lp.verticalMargin * Float(ph)))
        applyDisplay(display, frame)
        return frame
    }
}

/// One dialog window on screen: a full-screen overlay above the activity content holding the dim layer and the
/// window view, which hosts the dialog's AViewRoot.
final class KitDialogOverlay: UIView {
    private weak var dialog: ADialog?
    private let dialogWindow: AWindow
    let dimView = KitDialogDimView()
    let windowView = KitDialogWindowView()
    private(set) var viewRoot: AViewRoot?
    private var layoutListener: AOnGlobalLayoutListener?
    private var keyboardFrameInScreen: CGRect?
    private var observers: [NSObjectProtocol] = []
    private var isExiting = false

    init(dialog: ADialog, window: AWindow) {
        self.dialog = dialog
        self.dialogWindow = window
        super.init(frame: .zero)
        backgroundColor = .clear
        isMultipleTouchEnabled = true
        dimView.backgroundColor = .black
        dimView.alpha = 0
        dimView.overlay = self
        addSubview(dimView)
        windowView.backgroundColor = .clear
        windowView.clipsToBounds = false
        addSubview(windowView)
        let center = NotificationCenter.default
        observers.append(center.addObserver(forName: UIResponder.keyboardWillChangeFrameNotification, object: nil,
                                            queue: .main) { [weak self] note in
            let frame = (note.userInfo?[UIResponder.keyboardFrameEndUserInfoKey] as? NSValue)?.cgRectValue
            MainActor.assumeIsolated { self?.keyboardFrameChanged(frame) }
        })
        observers.append(center.addObserver(forName: UIResponder.keyboardWillHideNotification, object: nil,
                                            queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.keyboardFrameChanged(nil) }
        })
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { preconditionFailure("KitDialogOverlay is created in code") }

    deinit {
        for o in observers {
            NotificationCenter.default.removeObserver(o)
        }
    }

    /// WindowManager.addView: the window is measured and placed, then its views are attached by the AViewRoot.
    func attachWindow() {
        let root = AViewRoot(host: windowView)
        root.windowCallbackDispatchTouchEvent = { [weak dialog] ev in
            dialog?.dispatchTouchEvent(ev) ?? false
        }
        viewRoot = root
        relayoutWindow()
        root.contentView = dialogWindow.decorView
        let listener = AOnGlobalLayoutListener { [weak self] in
            self?.windowDidLayout()
        }
        layoutListener = listener
        root.treeObserver.addOnGlobalLayoutListener(listener)
        runEnterAnimation()
    }

    /// WindowManager.removeViewImmediate: the views leave now; the window's last frame plays the exit animation.
    func detach(animated: Bool) {
        if isExiting { return }
        isExiting = true
        isUserInteractionEnabled = false
        if let l = layoutListener {
            viewRoot?.treeObserver.removeOnGlobalLayoutListener(l)
            layoutListener = nil
        }
        let animation = animated ? dialogWindow.attributes.windowAnimations : KitWindowAnimations.NONE
        var snapshot: UIView? = nil
        if animation != KitWindowAnimations.NONE, superview != nil,
           let snap = windowView.snapshotView(afterScreenUpdates: false) {
            let holder = UIView(frame: windowView.frame)
            holder.layer.shadowPath = windowView.layer.shadowPath
            holder.layer.shadowColor = windowView.layer.shadowColor
            holder.layer.shadowOpacity = windowView.layer.shadowOpacity
            holder.layer.shadowRadius = windowView.layer.shadowRadius
            holder.layer.shadowOffset = windowView.layer.shadowOffset
            snap.frame = holder.bounds
            holder.addSubview(snap)
            addSubview(holder)
            snapshot = holder
        }
        viewRoot?.dispose()
        viewRoot = nil
        windowView.isHidden = true
        guard let exiting = snapshot else {
            removeFromSuperview()
            return
        }
        runExitAnimation(animation, exiting) { [weak self] in
            self?.removeFromSuperview()
        }
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        dimView.frame = bounds
        relayoutWindow()
    }

    override func safeAreaInsetsDidChange() {
        super.safeAreaInsetsDidChange()
        relayoutWindow()
    }

    /// Modal window: inside the window its views take the touch, anywhere else the dim layer does (and hands it to
    /// the dialog window as an outside touch).
    override func hitTest(_ point: CGPoint, with event: UIEvent?) -> UIView? {
        guard !isHidden, isUserInteractionEnabled, alpha > 0.01 else { return nil }
        if !windowView.isHidden, windowView.frame.contains(point),
           let hit = windowView.hitTest(convert(point, to: windowView), with: event) {
            return hit
        }
        return dimView
    }

    /// The attributes, background or flags of the window changed.
    func windowAttributesChanged() {
        relayoutWindow()
        updateDim()
    }

    /// The window's views laid out: a WRAP_CONTENT window follows its content's size (ViewRootImpl relayout).
    private func windowDidLayout() {
        let lp = dialogWindow.attributes
        if lp.width == AWindowManager.LayoutParams.WRAP_CONTENT || lp.height == AWindowManager.LayoutParams.WRAP_CONTENT {
            relayoutWindow()
        }
    }

    private func keyboardFrameChanged(_ frame: CGRect?) {
        keyboardFrameInScreen = frame
        relayoutWindow()
    }

    /// The frame of the window: measureHierarchy for WRAP_CONTENT sizes, the gravity inside the screen minus the
    /// system bars, then panned above the soft keyboard (adjustPan).
    func relayoutWindow() {
        guard !isExiting, bounds.width > 0, bounds.height > 0 else { return }
        let d = AView.densityScale
        let safe = bounds.inset(by: safeAreaInsets)
        let display = ARect(Int((safe.minX * d).rounded()), Int((safe.minY * d).rounded()),
                            Int((safe.maxX * d).rounded()), Int((safe.maxY * d).rounded()))
        let lp = dialogWindow.attributes
        let decor = dialogWindow.decorView
        let desiredWidth = display.width()
        let desiredHeight = display.height()
        let wraps = lp.width == AWindowManager.LayoutParams.WRAP_CONTENT || lp.height == AWindowManager.LayoutParams.WRAP_CONTENT
        if wraps {
            KitWindowLayout.measureHierarchy(decor, lp, desiredWidth, desiredHeight)
        }
        let w: Int
        switch lp.width {
        case AWindowManager.LayoutParams.MATCH_PARENT: w = desiredWidth
        case AWindowManager.LayoutParams.WRAP_CONTENT: w = decor.measuredWidth
        default: w = lp.width
        }
        let h: Int
        switch lp.height {
        case AWindowManager.LayoutParams.MATCH_PARENT: h = desiredHeight
        case AWindowManager.LayoutParams.WRAP_CONTENT: h = decor.measuredHeight
        default: h = lp.height
        }
        let rtl = AConfiguration.current.getLayoutDirection() == AView.LAYOUT_DIRECTION_RTL
        let windowFrame = KitWindowLayout.computeFrame(lp, w, h, display, rtl)
        // adjustPan: the window moves up so that the keyboard does not cover it (not above the display frame).
        if let keyboard = keyboardFrameInScreen, let uiWindow = self.window {
            let local = convert(keyboard, from: uiWindow.screen.coordinateSpace)
            if local.minY < bounds.maxY && local.width > 0 && local.height > 0 {
                let keyboardTop = Int((local.minY * d).rounded())
                if windowFrame.bottom > keyboardTop {
                    let shift = min(windowFrame.bottom - keyboardTop, max(0, windowFrame.top - display.top))
                    windowFrame.offset(0, -shift)
                }
            }
        }
        let newFrame = CGRect(x: CGFloat(windowFrame.left) / d, y: CGFloat(windowFrame.top) / d,
                              width: CGFloat(windowFrame.width()) / d, height: CGFloat(windowFrame.height()) / d)
        if windowView.frame != newFrame {
            windowView.frame = newFrame
        }
        updateShadow(windowFrame.width(), windowFrame.height())
        updateDim()
    }

    /// The window elevation shadow from the decor background's outline (the same fit as AWShadow).
    private func updateShadow(_ widthPx: Int, _ heightPx: Int) {
        let layer = windowView.layer
        let d = AView.densityScale
        let e = CGFloat(dialogWindow.windowElevation) / d
        guard e > 0.01, widthPx > 0, heightPx > 0, let background = dialogWindow.decorView.background else {
            layer.shadowOpacity = 0
            layer.shadowPath = nil
            return
        }
        background.setBounds(0, 0, widthPx, heightPx)
        guard let outline = KitDialogOverlay.outline(of: background, widthPx, heightPx), !outline.isEmpty,
              let r = outline.rect else {
            layer.shadowOpacity = 0
            layer.shadowPath = nil
            return
        }
        let rect = CGRect(x: CGFloat(r.left) / d, y: CGFloat(r.top) / d, width: CGFloat(r.width()) / d,
                          height: CGFloat(r.height()) / d)
        let path: CGPath
        if outline.isOval {
            path = CGPath(ellipseIn: rect, transform: nil)
        } else {
            let radius = min(CGFloat(outline.radius) / d, min(rect.width, rect.height) / 2)
            path = radius > 0 ? CGPath(roundedRect: rect, cornerWidth: radius, cornerHeight: radius, transform: nil)
                : CGPath(rect: rect, transform: nil)
        }
        layer.shadowPath = path
        layer.shadowColor = UIColor.black.cgColor
        layer.shadowOpacity = Float(0.26 * min(max(CGFloat(outline.alpha), 0), 1))
        layer.shadowRadius = max(0.666920 * e - 0.001648, 0)
        layer.shadowOffset = CGSize(width: 0, height: max(1.23118 * e - 0.03933, 0))
    }

    /// The window's outline (ViewOutlineProvider.BACKGROUND of the decor view): the background drawable's outline.
    static func outline(of background: ADrawable, _ width: Int, _ height: Int) -> AOutline? {
        let o = AOutline()
        if let provider = background as? ADrawableOutlineProvider {
            provider.getOutline(o)
            return o
        }
        if let gradient = background as? AGradientDrawable {
            let b = background.bounds.isEmpty() ? ARect(0, 0, width, height) : background.bounds
            if gradient.shape == AGradientDrawable.OVAL {
                o.setOval(b.left, b.top, b.right, b.bottom)
            } else if gradient.shape == AGradientDrawable.RECTANGLE {
                o.setRoundRect(b.left, b.top, b.right, b.bottom, gradient.cornerRadius)
            } else {
                return nil
            }
            if let colors = gradient.colors, !colors.isEmpty {
                o.setAlpha(Float(AColor.alpha(colors[0])) / 255)
            }
            return o
        }
        if let color = background as? AColorDrawable {
            o.setRect(0, 0, width, height)
            o.setAlpha(Float(AColor.alpha(color.color)) / 255)
            return o
        }
        return nil
    }

    private var targetDimAlpha: CGFloat {
        let a = dialogWindow.attributes
        if (a.flags & AWindowManager.LayoutParams.FLAG_DIM_BEHIND) == 0 { return 0 }
        return CGFloat(min(max(a.dimAmount, 0), 1))
    }

    private var enterAnimationRunning = false

    private func updateDim() {
        if enterAnimationRunning || isExiting { return }
        dimView.alpha = targetDimAlpha
    }

    /// The window's enter animation (and the dim layer fading in with it).
    private func runEnterAnimation() {
        let dim = targetDimAlpha
        let d = AView.densityScale
        switch dialogWindow.attributes.windowAnimations {
        case KitWindowAnimations.MATERIAL_DIALOG:
            // popup_enter_material: alpha 0 -> 1 and translate from popup_enter_animation_from_y_delta (20 dp), 220 ms,
            // @interpolator/standard (0.2, 0, 0, 1).
            enterAnimationRunning = true
            windowView.alpha = 0
            windowView.transform = CGAffineTransform(translationX: 0, y: CGFloat(aw_dpx(20)) / d)
            dimView.alpha = 0
            let animator = UIViewPropertyAnimator(duration: 0.22, timingParameters:
                UICubicTimingParameters(controlPoint1: CGPoint(x: 0.2, y: 0), controlPoint2: CGPoint(x: 0, y: 1)))
            animator.addAnimations {
                self.windowView.alpha = 1
                self.windowView.transform = .identity
                self.dimView.alpha = dim
            }
            animator.addCompletion { [weak self] _ in
                self?.enterAnimationRunning = false
                self?.updateDim()
            }
            animator.startAnimation()
        case KitWindowAnimations.APPCOMPAT_DIALOG:
            // abc_popup_enter: alpha 0 -> 1, 150 ms, decelerate_interpolator (1 - (1 - t)^2).
            enterAnimationRunning = true
            windowView.alpha = 0
            dimView.alpha = 0
            let animator = UIViewPropertyAnimator(duration: 0.15, timingParameters:
                UICubicTimingParameters(controlPoint1: CGPoint(x: 1.0 / 3.0, y: 2.0 / 3.0),
                                        controlPoint2: CGPoint(x: 2.0 / 3.0, y: 1)))
            animator.addAnimations {
                self.windowView.alpha = 1
                self.dimView.alpha = dim
            }
            animator.addCompletion { [weak self] _ in
                self?.enterAnimationRunning = false
                self?.updateDim()
            }
            animator.startAnimation()
        default:
            windowView.alpha = 1
            dimView.alpha = dim
        }
    }

    /// The window's exit animation on its last frame, the dim layer fading out with it.
    private func runExitAnimation(_ animation: Int, _ view: UIView, _ done: @escaping () -> Void) {
        let d = AView.densityScale
        let animator: UIViewPropertyAnimator
        if animation == KitWindowAnimations.MATERIAL_DIALOG {
            // popup_exit_material: alpha 1 -> 0 and translate to popup_exit_animation_to_y_delta (-10 dp), 150 ms,
            // @interpolator/standard_accelerate (0.3, 0, 1, 1).
            animator = UIViewPropertyAnimator(duration: 0.15, timingParameters:
                UICubicTimingParameters(controlPoint1: CGPoint(x: 0.3, y: 0), controlPoint2: CGPoint(x: 1, y: 1)))
            animator.addAnimations {
                view.alpha = 0
                view.transform = CGAffineTransform(translationX: 0, y: -CGFloat(aw_dpx(10)) / d)
                self.dimView.alpha = 0
            }
        } else {
            // abc_popup_exit: alpha 1 -> 0, 150 ms, decelerate.
            animator = UIViewPropertyAnimator(duration: 0.15, timingParameters:
                UICubicTimingParameters(controlPoint1: CGPoint(x: 1.0 / 3.0, y: 2.0 / 3.0),
                                        controlPoint2: CGPoint(x: 2.0 / 3.0, y: 1)))
            animator.addAnimations {
                view.alpha = 0
                self.dimView.alpha = 0
            }
        }
        animator.addCompletion { _ in done() }
        animator.startAnimation()
    }

    /// The overlay without the dialog layer (the activity was destroyed): gone at once.
    func removeImmediately() {
        detach(animated: false)
    }
}

/// The dim layer of a dialog window: a modal window receives the touches outside its frame, so they go to the
/// dialog's window (Dialog.dispatchTouchEvent -> onTouchEvent, which cancels on ACTION_UP outside).
final class KitDialogDimView: UIView {
    weak var overlay: KitDialogOverlay?

    override init(frame: CGRect) {
        super.init(frame: frame)
        isMultipleTouchEnabled = true
        isAccessibilityElement = false
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { preconditionFailure("KitDialogDimView is created in code") }

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        overlay?.viewRoot?.handleTouches(touches, event, .began)
    }

    override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent?) {
        overlay?.viewRoot?.handleTouches(touches, event, .moved)
    }

    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) {
        overlay?.viewRoot?.handleTouches(touches, event, .ended)
    }

    override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent?) {
        overlay?.viewRoot?.handleTouches(touches, event, .cancelled)
    }
}

/// The host of a dialog window's AViewRoot: never takes a touch itself (the overlay then routes it to the dim layer).
final class KitDialogWindowView: UIView {
    override func hitTest(_ point: CGPoint, with event: UIEvent?) -> UIView? {
        let hit = super.hitTest(point, with: event)
        return hit === self ? nil : hit
    }
}
