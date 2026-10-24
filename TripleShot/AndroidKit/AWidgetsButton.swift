import UIKit

// AndroidKit widgets (area kit-widgets): android.widget.Button, androidx AppCompatButton and
// com.google.android.material.button.MaterialButton in one class (AButton, as VIEW-API says), android.widget.CompoundButton,
// the Material light palette of Theme.TripleShot, android.graphics.Outline with the elevation shadow the widgets cast, and
// the state-list animators of the button styles.
//
// MaterialButton follows material-components-android 1.12.0 (MaterialButton / MaterialButtonHelper): the background is a
// MaterialShapeDrawable (backgroundTint fill, stroke inside the shape, rounded corners) inside the insets, the insets are
// added to the style padding, a custom background replaces it for good ("background overwritten") and from then on the
// button's background tint is applied to every background (AppCompatBackgroundHelper), icons are relative compound drawables
// placed by updateIconPosition. Style defaults are the Widget.MaterialComponents.Button* styles resolved under
// Theme.TripleShot (Theme.MaterialComponents.DayNight.NoActionBar, light palette per VIEW-API): 14 sp, letter spacing
// 0.0892857143, all caps, Roboto Regular (the theme's android:fontFamily "sans" overrides the appearance's medium family),
// padding 16/4 dp (text buttons 8 dp sides), insets 6 dp top/bottom, min height 48 dp, min width 88 dp, max width 320 dp,
// corner 4 dp, elevation 2 dp with mtrl_btn_state_list_anim (pressed translationZ 6 dp). A plain `new Button(context)` is
// the framework Widget.Material.Light.Button (btn_default_material face, padding 12/10 dp, elevation 2 dp, pressed 4 dp).
// Ripples are not drawn. Elevation shadows are drawn as the view layer's shadow along the background outline.

// MARK: - Theme colours

/// Theme.TripleShot (light): colorPrimary #087E70, colorPrimaryVariant #12333A, colorSecondary #FFC83D, and the
/// MaterialComponents / AppCompat / framework (Android 15/16) light values of the other attributes.
enum AWMaterialColors {
    static let colorPrimary = argbInt(0xFF087E70)
    static let colorPrimaryVariant = argbInt(0xFF12333A)
    static let colorSecondary = argbInt(0xFFFFC83D)
    /// colorAccent = ?colorSecondary; colorControlActivated = ?colorAccent (also android:colorControlActivated).
    static let colorAccent = argbInt(0xFFFFC83D)
    static let colorControlActivated = argbInt(0xFFFFC83D)
    static let colorOnPrimary = argbInt(0xFFFFFFFF)
    static let colorOnSecondary = argbInt(0xFF000000)
    static let colorSurface = argbInt(0xFFFFFFFF)
    static let colorOnSurface = argbInt(0xFF000000)
    static let colorError = argbInt(0xFFB00020)
    static let colorBackground = argbInt(0xFFFFFFFF)
    /// android:colorForeground (foreground_material_light).
    static let colorForeground = argbInt(0xFF000000)
    /// colorButtonNormal (button_material_light).
    static let colorButtonNormal = argbInt(0xFFD6D7D7)
    /// colorControlHighlight (ripples; not drawn).
    static let colorControlHighlight = argbInt(0x1F000000)
    /// colorControlNormal = ?android:textColorSecondary, enabled value.
    static let colorControlNormal = argbInt(0x99000000)
    /// android:textColorHint (hint_foreground_material_light: foreground at 60 %).
    static let textColorHint = argbInt(0x99000000)
    static let disabledAlpha: Float = 0.26

    /// ColorStateList.modulateColorAlpha: the item's android:alpha applied to the colour's alpha.
    static func withAlpha(_ color: Int, _ alphaMod: Float) -> Int {
        let a = min(max(AWMath.javaInt(Float(AColor.alpha(color)) * alphaMod + Float(0.5)), 0), 255)
        return Int(Int32(truncatingIfNeeded: (color & 0xFFFFFF) | (a << 24)))
    }

    /// ?android:textColorPrimary (text_color_primary): foreground at 87 %, disabled 26 %.
    static var textColorPrimary: AColorStateList {
        return AColorStateList([[-AStateSet.state_enabled], []],
                               [withAlpha(colorForeground, disabledAlpha), withAlpha(colorForeground, 0.87)])
    }

    /// ?android:textColorSecondary (text_color_secondary) = colorControlNormal: 60 %, disabled 26 %.
    static var textColorSecondary: AColorStateList {
        return AColorStateList([[-AStateSet.state_enabled], []],
                               [withAlpha(colorForeground, disabledAlpha), withAlpha(colorForeground, 0.60)])
    }

    /// ?android:textColorTertiary (secondary_text_material_light #8A000000, disabled at 26 % of it).
    static var textColorTertiary: AColorStateList {
        return AColorStateList([[-AStateSet.state_enabled], []],
                               [withAlpha(argbInt(0x8A000000), disabledAlpha), argbInt(0x8A000000)])
    }

    /// ?android:textColorPrimaryDisableOnly (primary_text_disable_only_material_light).
    static var textColorPrimaryDisableOnly: AColorStateList {
        return AColorStateList([[-AStateSet.state_enabled], []], [withAlpha(colorForeground, disabledAlpha), colorForeground])
    }

    static var colorControlNormalList: AColorStateList { return textColorSecondary }

    /// colorSwitchThumbNormal (switch_thumb_material_light).
    static var colorSwitchThumbNormal: AColorStateList {
        return AColorStateList([[-AStateSet.state_enabled], []], [argbInt(0xFFBDBDBD), argbInt(0xFFF1F1F1)])
    }

    /// switch_track_material.
    static var switchTrack: AColorStateList {
        return AColorStateList([[-AStateSet.state_enabled], [AStateSet.state_checked], []],
                               [withAlpha(colorForeground, disabledAlpha), colorControlActivated, colorForeground])
    }

    /// mtrl_btn_bg_color_selector.
    static var buttonBackground: AColorStateList {
        return AColorStateList([[AStateSet.state_enabled], []], [colorPrimary, withAlpha(colorOnSurface, 0.12)])
    }

    /// mtrl_btn_text_color_selector (also the filled button's iconTint).
    static var buttonText: AColorStateList {
        return AColorStateList([[AStateSet.state_enabled], []], [colorOnPrimary, withAlpha(colorOnSurface, 0.38)])
    }

    /// mtrl_text_btn_text_color_selector (text and outlined buttons, also their iconTint).
    static var textButtonText: AColorStateList {
        return AColorStateList([[AStateSet.state_checkable, AStateSet.state_checked, AStateSet.state_enabled],
                                [AStateSet.state_checkable, -AStateSet.state_checked, AStateSet.state_enabled],
                                [AStateSet.state_enabled], []],
                               [colorPrimary, withAlpha(colorOnSurface, 0.60), colorPrimary, withAlpha(colorOnSurface, 0.38)])
    }

    /// mtrl_btn_text_btn_bg_color_selector.
    static var textButtonBackground: AColorStateList {
        return AColorStateList([[AStateSet.state_checked], [-AStateSet.state_checked]],
                               [withAlpha(colorPrimary, 0.08), AColor.TRANSPARENT])
    }

    /// mtrl_btn_stroke_color_selector.
    static var buttonStroke: AColorStateList {
        return AColorStateList([[AStateSet.state_checked], [-AStateSet.state_checked]],
                               [colorPrimary, withAlpha(colorOnSurface, 0.12)])
    }

    /// The framework Button's text (TextAppearance.AppCompat.Widget.Button: ?android:textColorPrimary).
    static var frameworkButtonText: AColorStateList { return textColorPrimary }
}

// MARK: - Outline and elevation shadow

/// android.graphics.Outline (round rect / rect / oval / empty) for elevation shadows.
final class AOutline {
    var rect: ARect?
    var radius: Float = 0
    var alpha: Float = 1
    var isOval = false

    init() {}

    func setRoundRect(_ l: Int, _ t: Int, _ r: Int, _ b: Int, _ radius: Float) {
        rect = ARect(l, t, r, b)
        self.radius = radius
        isOval = false
    }

    func setRoundRect(_ rect: ARect, _ radius: Float) { setRoundRect(rect.left, rect.top, rect.right, rect.bottom, radius) }
    func setRect(_ l: Int, _ t: Int, _ r: Int, _ b: Int) { setRoundRect(l, t, r, b, 0) }
    func setRect(_ rect: ARect) { setRect(rect.left, rect.top, rect.right, rect.bottom) }

    func setOval(_ l: Int, _ t: Int, _ r: Int, _ b: Int) {
        rect = ARect(l, t, r, b)
        isOval = true
    }

    func setAlpha(_ alpha: Float) { self.alpha = alpha }
    func getAlpha() -> Float { return alpha }
    func setEmpty() { rect = nil }
    var isEmpty: Bool { return rect == nil || rect!.isEmpty() }
}

/// Drawable.getOutline for drawables that cast an elevation shadow (MaterialShapeDrawable faces implement it; ports
/// such as FamilySkyDrawable adopt it with their Android getOutline body).
protocol ADrawableOutlineProvider: AnyObject {
    func getOutline(_ outline: AOutline)
}

/// Elevation shadows (ViewOutlineProvider.BACKGROUND): the background's outline at elevation + translationZ, drawn with
/// the view layer's shadow (Android renders an ambient + key shadow; one layer shadow approximates Material's look with
/// the MDC-iOS key-shadow fit: blur 0.667 e, offset 1.231 e - 0.039, opacity 0.26, e in points). Views that cast one
/// keep their layer unmasked (see `aw_shadowSafeClipsToBounds`).
enum AWShadow {
    static func update(_ view: AView, _ background: ADrawable?, _ z: Float) {
        let d = CGFloat(AWidgetEnv.density)
        let e = CGFloat(z) / d
        guard e > 0.01, view.width > 0, view.height > 0, let outline = outline(view, background), !outline.isEmpty,
              outline.alpha > 0 else {
            if view.layer.shadowOpacity != 0 { view.layer.shadowOpacity = 0 }
            view.layer.shadowPath = nil
            return
        }
        let r = outline.rect!
        let rect = CGRect(x: CGFloat(r.left) / d, y: CGFloat(r.top) / d, width: CGFloat(r.width()) / d, height: CGFloat(r.height()) / d)
        let path: CGPath
        if outline.isOval {
            path = CGPath(ellipseIn: rect, transform: nil)
        } else {
            let radius = min(CGFloat(outline.radius) / d, min(rect.width, rect.height) / 2)
            path = radius > 0 ? CGPath(roundedRect: rect, cornerWidth: radius, cornerHeight: radius, transform: nil) : CGPath(rect: rect, transform: nil)
        }
        view.layer.shadowPath = path
        view.layer.shadowColor = UIColor.black.cgColor
        view.layer.shadowOpacity = Float(0.26 * min(max(CGFloat(outline.alpha), 0), 1))
        view.layer.shadowRadius = max(0.666920 * e - 0.001648, 0)
        view.layer.shadowOffset = CGSize(width: 0, height: max(1.23118 * e - 0.03933, 0))
    }

    /// ViewOutlineProvider.BACKGROUND: the background drawable's outline; no background = an invisible outline.
    static func outline(_ view: AView, _ background: ADrawable?) -> AOutline? {
        let o = AOutline()
        guard let bg = background else {
            o.setRect(0, 0, view.width, view.height)
            o.setAlpha(0)
            return o
        }
        if bg.bounds.isEmpty() { bg.setBounds(0, 0, view.width, view.height) }
        if let p = bg as? ADrawableOutlineProvider {
            p.getOutline(o)
            return o
        }
        let b = bg.bounds
        if let g = bg as? AGradientDrawable {
            // GradientDrawable.getOutline: the fill paint's (modulated) alpha when the shape is "opaque over shape"
            // (gradient colours all opaque, or a solid colour list), else 0.
            var fillAlpha = 0
            if let colors = g.colors, !colors.isEmpty {
                fillAlpha = colors.allSatisfy({ AColor.alpha($0) == 255 }) ? 255 : 0
            } else if let c = g.getColor() {
                fillAlpha = AColor.alpha(c.getColorForState(bg.state, c.defaultColor))
            }
            let a = g.alpha
            let modulated = fillAlpha * (a + (a >> 7)) >> 8
            o.setAlpha(Float(modulated) / 255)
            if g.shape == AGradientDrawable.OVAL {
                o.setOval(b.left, b.top, b.right, b.bottom)
            } else if g.shape == AGradientDrawable.RECTANGLE {
                o.setRoundRect(b.left, b.top, b.right, b.bottom, min(g.cornerRadius, Float(min(b.width(), b.height())) * 0.5))
            } else {
                return nil
            }
            return o
        }
        if let c = bg as? AColorDrawable {
            // ColorDrawable.getOutline: the bounds with the colour's alpha.
            o.setRect(b.left, b.top, b.right, b.bottom)
            o.setAlpha(Float(AColor.alpha(c.color)) / 255)
            return o
        }
        if let i = bg as? AInsetDrawable, let inner = i.getDrawable() {
            return outline(view, inner)
        }
        return nil
    }
}

// MARK: - StateListAnimator

/// android.animation.StateListAnimator for elevation / translationZ (the button and card styles' animators): the
/// first matching state spec wins; a new match cancels the running animation and animates translationZ from its
/// current value (ObjectAnimator, AccelerateDecelerate) while elevation jumps (duration 0).
final class AWStateListElevation {
    struct Tuple {
        let spec: [Int]
        let translationZ: Float
        let duration: Int64
        let startDelay: Int64
        let elevation: Float
    }

    let tuples: [Tuple]
    private weak var view: AView?
    private var lastMatch = -1
    private var animator: AValueAnimator?
    /// Called after every elevation / translationZ change (the owner refreshes its shadow).
    var onZChanged: (() -> Void)?

    init(_ view: AView, _ tuples: [Tuple]) {
        self.view = view
        self.tuples = tuples
    }

    func setState(_ state: [Int]) {
        guard let v = view else { return }
        var match = -1
        for (i, t) in tuples.enumerated() where AStateSet.stateSetMatches(t.spec, state) {
            match = i
            break
        }
        if match == lastMatch { return }
        animator?.cancel()
        animator = nil
        lastMatch = match
        if match < 0 { return }
        let t = tuples[match]
        v.elevation = t.elevation
        if (t.duration <= 0 && t.startDelay <= 0) || !v.isAttachedToWindow {
            v.translationZ = t.translationZ
            onZChanged?()
            return
        }
        onZChanged?()
        let a = AValueAnimator.ofFloat(v.translationZ, t.translationZ)
        a.duration = t.duration
        a.startDelay = t.startDelay
        a.addUpdateListener { [weak self, weak v] anim in
            v?.translationZ = anim.animatedValueFloat
            self?.onZChanged?()
        }
        animator = a
        a.start()
    }

    func cancel() {
        animator?.cancel()
        animator = nil
    }

    /// mtrl_btn_state_list_anim (Widget.MaterialComponents.Button).
    static func materialButton(_ view: AView) -> AWStateListElevation {
        let e = Float(aw_dpx(2))
        return AWStateListElevation(view, [
            Tuple(spec: [AStateSet.state_enabled, AStateSet.state_pressed], translationZ: Float(aw_dpx(6)), duration: 100, startDelay: 0, elevation: e),
            Tuple(spec: [AStateSet.state_enabled, AStateSet.state_hovered], translationZ: Float(aw_dpx(2)), duration: 100, startDelay: 0, elevation: e),
            Tuple(spec: [AStateSet.state_enabled, AStateSet.state_focused], translationZ: Float(aw_dpx(2)), duration: 100, startDelay: 0, elevation: e),
            Tuple(spec: [AStateSet.state_enabled], translationZ: 0, duration: 100, startDelay: 100, elevation: e),
            Tuple(spec: [], translationZ: 0, duration: 0, startDelay: 0, elevation: 0),
        ])
    }

    /// button_state_list_anim_material (framework Widget.Material.Button).
    static func frameworkButton(_ view: AView) -> AWStateListElevation {
        let e = Float(aw_dpx(2))
        return AWStateListElevation(view, [
            Tuple(spec: [AStateSet.state_pressed, AStateSet.state_enabled], translationZ: Float(aw_dpx(4)), duration: 100, startDelay: 0, elevation: e),
            Tuple(spec: [AStateSet.state_enabled], translationZ: 0, duration: 100, startDelay: 100, elevation: e),
            Tuple(spec: [], translationZ: 0, duration: 0, startDelay: 0, elevation: 0),
        ])
    }
}

// MARK: - MaterialShapeDrawable faces

/// The MaterialButton background: InsetDrawable(MaterialShapeDrawable) with the backgroundTint fill (a null tint leaves
/// the shape's paint black, as on Android), rounded corners and the stroke drawn inside the shape.
final class AWMaterialButtonBackground: ADrawable, ADrawableOutlineProvider {
    var insetLeft = 0, insetTop = 0, insetRight = 0, insetBottom = 0
    var cornerRadius: Float = 0
    var fillTint: AColorStateList?
    var strokeWidth = 0
    var strokeColor: AColorStateList?
    private let paint = APaint(APaint.ANTI_ALIAS_FLAG)

    override var isStateful: Bool { return true }
    override func onStateChange(_ state: [Int]) -> Bool { return true }

    override func setTintList(_ tint: AColorStateList?) {
        fillTint = tint
        invalidateSelf()
    }

    /// The shape rectangle inside the insets.
    var shapeRect: ARectF {
        let b = bounds
        return ARectF(Float(b.left + insetLeft), Float(b.top + insetTop), Float(b.right - insetRight), Float(b.bottom - insetBottom))
    }

    func fillColor() -> Int {
        guard let t = fillTint else { return AColor.BLACK }
        return t.getColorForState(state, t.defaultColor)
    }

    override func draw(_ canvas: ACanvas) {
        let r = shapeRect
        if r.width() <= 0 || r.height() <= 0 { return }
        let radius = min(cornerRadius, min(r.width(), r.height()) / 2)
        let fill = fillColor()
        if AColor.alpha(fill) > 0 {
            paint.style = .FILL
            paint.color = fill
            paint.alpha = AColor.alpha(fill) * alpha / 255
            canvas.drawRoundRect(r, radius, radius, paint)
        }
        if strokeWidth > 0, let sc = strokeColor {
            let c = sc.getColorForState(state, sc.defaultColor)
            if AColor.alpha(c) > 0 {
                let half = Float(strokeWidth) / 2
                let sr = ARectF(r.left + half, r.top + half, r.right - half, r.bottom - half)
                let srad = max(radius - half, 0)
                paint.style = .STROKE
                paint.strokeWidth = Float(strokeWidth)
                paint.color = c
                paint.alpha = AColor.alpha(c) * alpha / 255
                canvas.drawRoundRect(sr, srad, srad, paint)
            }
        }
    }

    /// MaterialShapeDrawable.getOutline: the shape's rounded rectangle (alpha left at 1).
    func getOutline(_ outline: AOutline) {
        let r = shapeRect
        outline.setRoundRect(AWMath.javaInt(r.left), AWMath.javaInt(r.top), AWMath.javaInt(r.right), AWMath.javaInt(r.bottom),
                             min(cornerRadius, min(r.width(), r.height()) / 2))
    }
}

/// android.widget.Button's framework background (btn_default_material: inset 4/6 dp, 2 dp corners, white tinted with
/// colorButtonNormal, padding 8/4 dp inside the insets).
final class AWFrameworkButtonBackground: ADrawable, ADrawableOutlineProvider {
    private var tint: AColorStateList?
    private let paint = APaint(APaint.ANTI_ALIAS_FLAG)

    override var isStateful: Bool { return tint?.isStateful ?? false }
    override func onStateChange(_ state: [Int]) -> Bool { return tint?.isStateful ?? false }

    override func setTintList(_ l: AColorStateList?) {
        tint = l
        invalidateSelf()
    }

    private var shapeRect: ARectF {
        let b = bounds
        let h = Float(aw_dpx(4)), v = Float(aw_dpx(6))
        return ARectF(Float(b.left) + h, Float(b.top) + v, Float(b.right) - h, Float(b.bottom) - v)
    }

    private func color() -> Int {
        if let t = tint { return t.getColorForState(state, t.defaultColor) }
        return AWMaterialColors.colorButtonNormal
    }

    override func draw(_ canvas: ACanvas) {
        let r = shapeRect
        if r.width() <= 0 || r.height() <= 0 { return }
        let c = color()
        paint.color = c
        paint.alpha = AColor.alpha(c) * alpha / 255
        let radius = Float(aw_dpx(2))
        canvas.drawRoundRect(r, radius, radius, paint)
    }

    /// InsetDrawable padding: the shape's padding (8/4 dp) plus the insets (4/6 dp).
    override func getPadding(_ r: ARect) -> Bool {
        r.set(aw_dpx(4) + aw_dpx(8), aw_dpx(6) + aw_dpx(4), aw_dpx(4) + aw_dpx(8), aw_dpx(6) + aw_dpx(4))
        return true
    }

    func getOutline(_ outline: AOutline) {
        let r = shapeRect
        outline.setRoundRect(AWMath.javaInt(r.left), AWMath.javaInt(r.top), AWMath.javaInt(r.right), AWMath.javaInt(r.bottom),
                             Float(aw_dpx(2)))
    }
}

// MARK: - Button / MaterialButton

/// android.widget.Button, AppCompatButton and MaterialButton in one class (VIEW-API). `AButton()` is what an XML
/// <Button> (MaterialComponentsViewInflater), `MaterialButton(context)` or `TripleShotButton(context)` gives under the
/// app theme (Widget.MaterialComponents.Button); `AButton(style:)` / `applyStyle(_:)` select the other styles the
/// layouts use; `.FRAMEWORK` is a plain `new Button(context)` (Widget.Material.Light.Button), which is not a MaterialButton.
class AButton: ATextView {
    enum Style {
        /// Widget.MaterialComponents.Button (filled, elevated): the theme's materialButtonStyle.
        case FILLED
        /// Widget.MaterialComponents.Button.UnelevatedButton.
        case UNELEVATED
        /// Widget.MaterialComponents.Button.TextButton.
        case TEXT
        /// Widget.MaterialComponents.Button.TextButton.Dialog (single line, end ellipsis, min width 64 dp).
        case TEXT_DIALOG
        /// Widget.MaterialComponents.Button.OutlinedButton.
        case OUTLINED
        /// android.widget.Button created in code (framework Widget.Material.Light.Button).
        case FRAMEWORK
    }

    static let ICON_GRAVITY_START = 0x1, ICON_GRAVITY_TEXT_START = 0x2, ICON_GRAVITY_END = 0x3, ICON_GRAVITY_TEXT_END = 0x4,
               ICON_GRAVITY_TOP = 0x10, ICON_GRAVITY_TEXT_TOP = 0x20

    private(set) var buttonStyle: Style = .FILLED
    /// `button is MaterialButton` (false only for a framework Button).
    var isMaterialButton: Bool { return buttonStyle != .FRAMEWORK }

    // MaterialButtonHelper state
    let aw_materialBackground = AWMaterialButtonBackground()
    var aw_backgroundOverwritten = false
    var aw_materialBackgroundTint: AColorStateList?
    var aw_cornerRadiusSet = false
    var aw_rippleColor: AColorStateList?
    var aw_checkable = false
    var aw_checked = false
    private var aw_broadcastingChecked = false
    private var aw_onCheckedChangeListeners: [(AButton, Bool) -> Void] = []
    var aw_toggleCheckedStateOnClick = true
    // AppCompatBackgroundHelper support tint (custom backgrounds)
    var aw_supportTint: AColorStateList?
    var aw_hasSupportTint = false
    // Icon
    var aw_icon: ADrawable?
    var aw_iconSize = 0
    var aw_iconPadding = 0
    var aw_iconGravity = AButton.ICON_GRAVITY_START
    var aw_iconTint: AColorStateList?
    var aw_iconLeft = 0
    var aw_iconTop = 0
    // Elevation
    var aw_stateListAnimator: AWStateListElevation?
    private var aw_inConfiguration = false

    override init() {
        super.init()
        aw_configure(.FILLED)
    }

    init(style: Style) {
        super.init()
        aw_configure(style)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    /// Re-applies a style's defaults (an XML `style="@style/Widget.MaterialComponents.Button.OutlinedButton"`): call it
    /// right after construction, before the layout's own attributes.
    func applyStyle(_ style: Style) { aw_configure(style) }

    /// The style's attributes as the constructors read them (TextView, then MaterialButton / MaterialButtonHelper).
    private func aw_configure(_ style: Style) {
        aw_inConfiguration = true
        defer { aw_inConfiguration = false }
        buttonStyle = style
        isClickable = true
        isFocusable = true
        setGravity(AGravity.CENTER)
        aw_setRawTextSize(ATypedValue.applyDimension(ATypedValue.COMPLEX_UNIT_SP, 14), shouldRequestLayout: true)
        setTypeface(ATypeface.create("sans", ATypeface.NORMAL))
        setAllCaps(true)
        minHeight = aw_dpx(48)
        minimumHeight = aw_dpx(48)
        minWidth = aw_dpx(88)
        minimumWidth = aw_dpx(88)
        if style == .FRAMEWORK {
            setLetterSpacing(0)
            maxWidth = Int(Int32.max)
            setTextColor(AWMaterialColors.frameworkButtonText)
            aw_backgroundOverwritten = true
            super.setBackgroundDrawable(AWFrameworkButtonBackground())
            aw_installStateListAnimator(AWStateListElevation.frameworkButton(self))
            aw_updateShadow()
            return
        }
        setLetterSpacing(0.0892857143)
        maxWidth = aw_dpx(320)
        // The style padding (without the insets yet).
        var padL = aw_dpx(16), padR = aw_dpx(16)
        let padT = aw_dpx(4), padB = aw_dpx(4)
        let mb = aw_materialBackground
        mb.insetLeft = 0
        mb.insetRight = 0
        mb.insetTop = aw_dpx(6)
        mb.insetBottom = aw_dpx(6)
        if !aw_cornerRadiusSet { mb.cornerRadius = Float(aw_dpx(4)) }
        switch style {
        case .FILLED, .UNELEVATED:
            setTextColor(AWMaterialColors.buttonText)
            aw_iconTint = AWMaterialColors.buttonText
            aw_iconPadding = aw_dpx(8)
            aw_materialBackgroundTint = AWMaterialColors.buttonBackground
            mb.strokeWidth = 0
            mb.strokeColor = nil
        case .TEXT, .TEXT_DIALOG:
            padL = aw_dpx(8)
            padR = aw_dpx(8)
            setTextColor(AWMaterialColors.textButtonText)
            aw_iconTint = AWMaterialColors.textButtonText
            aw_iconPadding = aw_dpx(4)
            aw_materialBackgroundTint = AWMaterialColors.textButtonBackground
            mb.strokeWidth = 0
            mb.strokeColor = nil
            if style == .TEXT_DIALOG {
                minWidth = aw_dpx(64)
                minimumWidth = aw_dpx(64)
                applyXmlSingleLine(true)
                // AppCompatTextHelper.loadFromAttributes runs after the TextView constructor: the text appearance's
                // textAllCaps (true) calls setAllCaps(true), replacing the single-line transformation. Dialog buttons
                // are upper case on Android.
                setAllCaps(true)
            }
        case .OUTLINED:
            setTextColor(AWMaterialColors.textButtonText)
            aw_iconTint = AWMaterialColors.textButtonText
            aw_iconPadding = aw_dpx(4)
            aw_materialBackgroundTint = AWMaterialColors.textButtonBackground
            mb.strokeWidth = aw_dpx(1)
            mb.strokeColor = AWMaterialColors.buttonStroke
        case .FRAMEWORK:
            break
        }
        mb.fillTint = aw_materialBackgroundTint
        aw_backgroundOverwritten = false
        super.setBackgroundDrawable(mb)
        // MaterialButtonHelper.loadFromAttributes: the insets are added to the style padding.
        super.setPaddingRelative(padL + mb.insetLeft, padT + mb.insetTop, padR + mb.insetRight, padB + mb.insetBottom)
        if style == .FILLED {
            aw_installStateListAnimator(AWStateListElevation.materialButton(self))
        } else {
            aw_installStateListAnimator(nil)
            elevation = 0
            translationZ = 0
        }
        setCompoundDrawablePadding(aw_iconPadding)
        aw_updateIcon(aw_icon != nil)
        aw_updateShadow()
    }

    /// View.setStateListAnimator (nil removes it).
    func aw_installStateListAnimator(_ animator: AWStateListElevation?) {
        aw_stateListAnimator?.cancel()
        aw_stateListAnimator = animator
        animator?.onZChanged = { [weak self] in self?.aw_updateShadow() }
        animator?.setState(drawableState)
    }

    /// MaterialButton.isUsingOriginalBackground.
    var aw_isUsingOriginalBackground: Bool { return isMaterialButton && !aw_backgroundOverwritten }

    // MARK: Background (MaterialButton.setBackgroundDrawable / setBackgroundColor / setBackgroundTintList)

    /// MaterialButton.setBackgroundDrawable: a custom background overwrites the Material one for good, and the
    /// button's background tint becomes the AppCompat support tint of every later background.
    override func setBackgroundDrawable(_ background: ADrawable?) {
        if aw_isUsingOriginalBackground {
            if background !== self.background {
                // MaterialButtonHelper.setBackgroundOverwritten.
                aw_backgroundOverwritten = true
                aw_supportTint = aw_materialBackgroundTint
                aw_hasSupportTint = true
                aw_setBackgroundAppCompat(background)
            } else if let bg = background {
                self.background?.setState(bg.state)
            }
        } else if isMaterialButton {
            aw_setBackgroundAppCompat(background)
        } else {
            super.setBackgroundDrawable(background)
        }
        aw_updateShadow()
    }

    /// AppCompatButton.setBackgroundDrawable: View's, then the support tint applied (AppCompatBackgroundHelper).
    private func aw_setBackgroundAppCompat(_ background: ADrawable?) {
        super.setBackgroundDrawable(background)
        aw_applySupportBackgroundTint()
    }

    /// AppCompatBackgroundHelper.applySupportBackgroundTint: the tint (or no tint) on the current background.
    private func aw_applySupportBackgroundTint() {
        guard aw_hasSupportTint, let bg = background else { return }
        bg.mutate()
        bg.setTintList(aw_supportTint)
        if bg.isStateful { bg.setState(drawableState) }
        invalidate()
    }

    override func setBackgroundColor(_ color: Int) {
        if aw_isUsingOriginalBackground {
            aw_materialBackground.setTintList(AColorStateList.valueOf(color))
            invalidate()
        } else {
            super.setBackgroundColor(color)
        }
    }

    override func getBackgroundTintList() -> AColorStateList? {
        if aw_isUsingOriginalBackground { return aw_materialBackgroundTint }
        if isMaterialButton { return aw_supportTint }
        return super.getBackgroundTintList()
    }

    /// MaterialButton.setBackgroundTintList -> setSupportBackgroundTintList.
    override func setBackgroundTintList(_ tint: AColorStateList?) {
        if aw_isUsingOriginalBackground {
            if aw_materialBackgroundTint !== tint {
                aw_materialBackgroundTint = tint
                aw_materialBackground.setTintList(tint)
                aw_updateShadow()
                invalidate()
            }
        } else if isMaterialButton {
            aw_supportTint = tint
            aw_hasSupportTint = true
            aw_applySupportBackgroundTint()
        } else {
            super.setBackgroundTintList(tint)
        }
    }

    // MARK: Shape, stroke, insets

    /// MaterialButton.cornerRadius (px; 0 and ignored once a custom background replaced the Material one).
    var cornerRadius: Int {
        get { return aw_isUsingOriginalBackground ? AWMath.javaInt(aw_materialBackground.cornerRadius) : 0 }
        set { setCornerRadius(newValue) }
    }

    func getCornerRadius() -> Int { return cornerRadius }

    /// MaterialButtonHelper.setCornerRadius.
    func setCornerRadius(_ cornerRadius: Int) {
        guard aw_isUsingOriginalBackground else { return }
        if !aw_cornerRadiusSet || Float(cornerRadius) != aw_materialBackground.cornerRadius {
            aw_cornerRadiusSet = true
            aw_materialBackground.cornerRadius = Float(cornerRadius)
            aw_updateShadow()
            invalidate()
        }
    }

    /// MaterialButton.strokeWidth (px).
    var strokeWidth: Int {
        get { return aw_isUsingOriginalBackground ? aw_materialBackground.strokeWidth : 0 }
        set { setStrokeWidth(newValue) }
    }

    func setStrokeWidth(_ strokeWidth: Int) {
        if aw_isUsingOriginalBackground && aw_materialBackground.strokeWidth != strokeWidth {
            aw_materialBackground.strokeWidth = strokeWidth
            invalidate()
        }
    }

    /// MaterialButton.strokeColor.
    var strokeColor: AColorStateList? {
        get { return aw_isUsingOriginalBackground ? aw_materialBackground.strokeColor : nil }
        set { setStrokeColor(newValue) }
    }

    func setStrokeColor(_ strokeColor: AColorStateList?) {
        if aw_isUsingOriginalBackground && aw_materialBackground.strokeColor !== strokeColor {
            aw_materialBackground.strokeColor = strokeColor
            invalidate()
        }
    }

    /// MaterialButton.rippleColor (ripples are not drawn).
    var rippleColor: AColorStateList? {
        get { return aw_isUsingOriginalBackground ? aw_rippleColor : nil }
        set { if aw_isUsingOriginalBackground { aw_rippleColor = newValue } }
    }

    var insetTop: Int {
        get { return aw_materialBackground.insetTop }
        set { setInsetTop(newValue) }
    }

    var insetBottom: Int {
        get { return aw_materialBackground.insetBottom }
        set { setInsetBottom(newValue) }
    }

    func getInsetTop() -> Int { return aw_materialBackground.insetTop }
    func getInsetBottom() -> Int { return aw_materialBackground.insetBottom }

    /// MaterialButton.setInsetTop -> MaterialButtonHelper.setVerticalInsets: the padding keeps its distance to the face.
    func setInsetTop(_ insetTop: Int) { aw_setVerticalInsets(insetTop, aw_materialBackground.insetBottom) }
    func setInsetBottom(_ insetBottom: Int) { aw_setVerticalInsets(aw_materialBackground.insetTop, insetBottom) }

    private func aw_setVerticalInsets(_ newInsetTop: Int, _ newInsetBottom: Int) {
        guard isMaterialButton else { return }
        let ps = paddingStart, pt = paddingTop, pe = paddingEnd, pb = paddingBottom
        let oldInsetTop = aw_materialBackground.insetTop, oldInsetBottom = aw_materialBackground.insetBottom
        aw_materialBackground.insetBottom = newInsetBottom
        aw_materialBackground.insetTop = newInsetTop
        super.setPaddingRelative(ps, pt + newInsetTop - oldInsetTop, pe, pb + newInsetBottom - oldInsetBottom)
        aw_updateShadow()
        invalidate()
    }

    /// The XML-only android:insetLeft / insetRight (applied at inflation, padding included like the vertical ones).
    func applyXmlHorizontalInsets(_ insetLeft: Int, _ insetRight: Int) {
        guard isMaterialButton else { return }
        let pl = paddingLeft, pt = paddingTop, pr = paddingRight, pb = paddingBottom
        let oldLeft = aw_materialBackground.insetLeft, oldRight = aw_materialBackground.insetRight
        aw_materialBackground.insetLeft = insetLeft
        aw_materialBackground.insetRight = insetRight
        super.setPadding(pl + insetLeft - oldLeft, pt, pr + insetRight - oldRight, pb)
        aw_updateShadow()
        invalidate()
    }

    /// An XML `android:padding*` on a MaterialButton: inflation adds the insets to it (MaterialButtonHelper.loadFromAttributes).
    func applyXmlPadding(_ left: Int, _ top: Int, _ right: Int, _ bottom: Int) {
        if isMaterialButton {
            let mb = aw_materialBackground
            super.setPadding(left + mb.insetLeft, top + mb.insetTop, right + mb.insetRight, bottom + mb.insetBottom)
        } else {
            setPadding(left, top, right, bottom)
        }
    }

    /// Relative form of `applyXmlPadding` (android:paddingStart / paddingEnd / paddingHorizontal).
    func applyXmlPaddingRelative(_ start: Int, _ top: Int, _ end: Int, _ bottom: Int) {
        if isMaterialButton {
            let mb = aw_materialBackground
            super.setPaddingRelative(start + mb.insetLeft, top + mb.insetTop, end + mb.insetRight, bottom + mb.insetBottom)
        } else {
            setPaddingRelative(start, top, end, bottom)
        }
    }

    // MARK: Checkable (MaterialButton)

    var isCheckable: Bool {
        get { return aw_checkable }
        set { setCheckable(newValue) }
    }

    func setCheckable(_ checkable: Bool) {
        if aw_isUsingOriginalBackground { aw_checkable = checkable }
    }

    var isChecked: Bool {
        get { return aw_checked }
        set { setChecked(newValue) }
    }

    /// MaterialButton.setChecked.
    func setChecked(_ checked: Bool) {
        if isCheckable && isEnabled && aw_checked != checked {
            aw_checked = checked
            refreshDrawableState()
            if aw_broadcastingChecked { return }
            aw_broadcastingChecked = true
            for l in aw_onCheckedChangeListeners { l(self, aw_checked) }
            aw_broadcastingChecked = false
        }
    }

    func toggle() { setChecked(!aw_checked) }

    func addOnCheckedChangeListener(_ listener: @escaping (AButton, Bool) -> Void) { aw_onCheckedChangeListeners.append(listener) }
    func clearOnCheckedChangeListeners() { aw_onCheckedChangeListeners.removeAll() }

    /// MaterialButton.performClick: toggles a checkable button first.
    @discardableResult
    override func performClick() -> Bool {
        if isMaterialButton && aw_toggleCheckedStateOnClick { toggle() }
        return super.performClick()
    }

    /// MaterialButton.onCreateDrawableState: checkable / checked.
    override func onCreateDrawableState(_ extraSpace: Int) -> [Int] {
        var state = super.onCreateDrawableState(extraSpace + 2)
        if isMaterialButton {
            if isCheckable { state.append(AStateSet.state_checkable) }
            if aw_checked { state.append(AStateSet.state_checked) }
        }
        return state
    }

    /// View.drawableStateChanged + the StateListAnimator; MaterialButton.refreshDrawableState updates the icon.
    override func drawableStateChanged() {
        super.drawableStateChanged()
        let state = drawableState
        if let icon = aw_icon, icon.isStateful, icon.setState(state) { invalidate() }
        aw_stateListAnimator?.setState(state)
        aw_applySupportBackgroundTintState()
        aw_updateShadow()
    }

    /// AppCompatButton.drawableStateChanged re-applies the support tint for the new state.
    private func aw_applySupportBackgroundTintState() {
        if !aw_isUsingOriginalBackground && isMaterialButton && aw_hasSupportTint, let bg = background, bg.isStateful {
            bg.setState(drawableState)
        }
    }

    // MARK: Icon (MaterialButton.setIcon / updateIcon / updateIconPosition)

    var icon: ADrawable? {
        get { return aw_icon }
        set { setIcon(newValue) }
    }

    func getIcon() -> ADrawable? { return aw_icon }

    func setIcon(_ icon: ADrawable?) {
        if aw_icon !== icon {
            aw_icon = icon
            aw_updateIcon(true)
            aw_updateIconPosition(measuredWidth, measuredHeight)
        }
    }

    func setIconResource(_ iconResourceId: ADrawableRes) {
        setIcon(iconResourceId.isEmpty ? nil : ContextCompat_getDrawable(iconResourceId))
    }

    var iconSize: Int {
        get { return aw_iconSize }
        set { setIconSize(newValue) }
    }

    func setIconSize(_ iconSize: Int) {
        precondition(iconSize >= 0, "java.lang.IllegalArgumentException: iconSize cannot be less than 0")
        if aw_iconSize != iconSize {
            aw_iconSize = iconSize
            aw_updateIcon(true)
        }
    }

    var iconPadding: Int {
        get { return aw_iconPadding }
        set { setIconPadding(newValue) }
    }

    func setIconPadding(_ iconPadding: Int) {
        if aw_iconPadding != iconPadding {
            aw_iconPadding = iconPadding
            setCompoundDrawablePadding(iconPadding)
        }
    }

    var iconGravity: Int {
        get { return aw_iconGravity }
        set { setIconGravity(newValue) }
    }

    func setIconGravity(_ iconGravity: Int) {
        if aw_iconGravity != iconGravity {
            aw_iconGravity = iconGravity
            aw_updateIconPosition(measuredWidth, measuredHeight)
        }
    }

    var iconTint: AColorStateList? {
        get { return aw_iconTint }
        set { setIconTint(newValue) }
    }

    func setIconTint(_ iconTint: AColorStateList?) {
        if aw_iconTint !== iconTint {
            aw_iconTint = iconTint
            aw_updateIcon(false)
        }
    }

    private var aw_isIconStart: Bool { return aw_iconGravity == AButton.ICON_GRAVITY_START || aw_iconGravity == AButton.ICON_GRAVITY_TEXT_START }
    private var aw_isIconEnd: Bool { return aw_iconGravity == AButton.ICON_GRAVITY_END || aw_iconGravity == AButton.ICON_GRAVITY_TEXT_END }
    private var aw_isIconTop: Bool { return aw_iconGravity == AButton.ICON_GRAVITY_TOP || aw_iconGravity == AButton.ICON_GRAVITY_TEXT_TOP }

    /// MaterialButton.updateIcon.
    func aw_updateIcon(_ needsIconReset: Bool) {
        if let icon = aw_icon {
            icon.mutate()
            icon.setTintList(aw_iconTint)
            let w = aw_iconSize != 0 ? aw_iconSize : icon.intrinsicWidth
            let h = aw_iconSize != 0 ? aw_iconSize : icon.intrinsicHeight
            icon.setBounds(aw_iconLeft, aw_iconTop, aw_iconLeft + w, aw_iconTop + h)
            icon.setVisible(true, needsIconReset)
        }
        if needsIconReset {
            aw_resetIconDrawable()
            return
        }
        let existing = compoundDrawablesRelative
        let hasIconChanged = (aw_isIconStart && existing[0] !== aw_icon) || (aw_isIconEnd && existing[2] !== aw_icon)
            || (aw_isIconTop && existing[1] !== aw_icon)
        if hasIconChanged { aw_resetIconDrawable() }
    }

    private func aw_resetIconDrawable() {
        if aw_isIconStart {
            setCompoundDrawablesRelative(aw_icon, nil, nil, nil)
        } else if aw_isIconEnd {
            setCompoundDrawablesRelative(nil, nil, aw_icon, nil)
        } else if aw_isIconTop {
            setCompoundDrawablesRelative(nil, aw_icon, nil, nil)
        }
    }

    /// MaterialButton.getActualTextAlignment.
    private func aw_actualTextAlignment() -> ALayout.Alignment {
        switch textAlignment {
        case AView.TEXT_ALIGNMENT_GRAVITY:
            switch gravity & AGravity.RELATIVE_HORIZONTAL_GRAVITY_MASK {
            case AGravity.CENTER_HORIZONTAL: return .ALIGN_CENTER
            case AGravity.END, AGravity.RIGHT: return .ALIGN_OPPOSITE
            default: return .ALIGN_NORMAL
            }
        case AView.TEXT_ALIGNMENT_CENTER: return .ALIGN_CENTER
        case AView.TEXT_ALIGNMENT_TEXT_END, AView.TEXT_ALIGNMENT_VIEW_END: return .ALIGN_OPPOSITE
        default: return .ALIGN_NORMAL
        }
    }

    /// MaterialButton.getTextLayoutWidth.
    private func aw_textLayoutWidth() -> Int {
        guard let l = layout else { return 0 }
        var maxW: Float = 0
        for i in 0..<l.lineCount { maxW = Swift.max(maxW, l.getLineWidth(i)) }
        return AWMath.ceil(maxW)
    }

    /// MaterialButton.getTextHeight.
    private func aw_textHeight() -> Int {
        guard let l = layout else { return 0 }
        if lineCount > 1 { return l.getHeight() }
        let bounds = ARect()
        let s = aw_transformed.aw_plain
        paint.getTextBounds(s, 0, s.utf16.count, bounds)
        return Swift.min(bounds.height(), l.getHeight())
    }

    /// MaterialButton.updateIconPosition.
    func aw_updateIconPosition(_ buttonWidth: Int, _ buttonHeight: Int) {
        guard let icon = aw_icon, layout != nil else { return }
        if aw_isIconStart || aw_isIconEnd {
            aw_iconTop = 0
            let textAlignment = aw_actualTextAlignment()
            if aw_iconGravity == AButton.ICON_GRAVITY_START || aw_iconGravity == AButton.ICON_GRAVITY_END
                || (aw_iconGravity == AButton.ICON_GRAVITY_TEXT_START && textAlignment == .ALIGN_NORMAL)
                || (aw_iconGravity == AButton.ICON_GRAVITY_TEXT_END && textAlignment == .ALIGN_OPPOSITE) {
                aw_iconLeft = 0
                aw_updateIcon(false)
                return
            }
            let localIconSize = aw_iconSize == 0 ? icon.intrinsicWidth : aw_iconSize
            let availableWidth = buttonWidth - aw_textLayoutWidth() - paddingEnd - localIconSize - aw_iconPadding - paddingStart
            var newIconLeft = textAlignment == .ALIGN_CENTER ? availableWidth / 2 : availableWidth
            if isLayoutRtl != (aw_iconGravity == AButton.ICON_GRAVITY_TEXT_END) { newIconLeft = -newIconLeft }
            if aw_iconLeft != newIconLeft {
                aw_iconLeft = newIconLeft
                aw_updateIcon(false)
            }
        } else if aw_isIconTop {
            aw_iconLeft = 0
            if aw_iconGravity == AButton.ICON_GRAVITY_TOP {
                aw_iconTop = 0
                aw_updateIcon(false)
                return
            }
            let localIconSize = aw_iconSize == 0 ? icon.intrinsicHeight : aw_iconSize
            let newIconTop = Swift.max(0, (buttonHeight - aw_textHeight() - paddingTop - localIconSize - aw_iconPadding - paddingBottom) / 2)
            if aw_iconTop != newIconTop {
                aw_iconTop = newIconTop
                aw_updateIcon(false)
            }
        }
    }

    override func onLayout(_ changed: Bool, _ l: Int, _ t: Int, _ r: Int, _ b: Int) {
        super.onLayout(changed, l, t, r, b)
        aw_updateIconPosition(measuredWidth, measuredHeight)
        aw_updateShadow()
    }

    override func onTextChanged(_ text: String, _ start: Int, _ lengthBefore: Int, _ lengthAfter: Int) {
        super.onTextChanged(text, start, lengthBefore, lengthAfter)
        if !aw_inConfiguration { aw_updateIconPosition(measuredWidth, measuredHeight) }
    }

    override func setTextAlignment(_ textAlignment: Int) {
        super.setTextAlignment(textAlignment)
        aw_updateIconPosition(measuredWidth, measuredHeight)
    }

    // MARK: Elevation shadow

    override func onSizeChanged(_ w: Int, _ h: Int, _ oldw: Int, _ oldh: Int) {
        super.onSizeChanged(w, h, oldw, oldh)
        aw_updateShadow()
    }

    override func onAttachedToWindow() {
        super.onAttachedToWindow()
        aw_updateShadow()
    }

    /// The outline shadow of the current background at elevation + translationZ (z changes come through
    /// AView.elevation / translationZ and the state-list animator).
    func aw_updateShadow() {
        AWShadow.update(self, background, z)
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        aw_updateShadow()
    }

    override var elevation: Float { didSet { if oldValue != elevation { aw_updateShadow() } } }
    override var translationZ: Float { didSet { if oldValue != translationZ { aw_updateShadow() } } }

    /// The layer stays unmasked so the elevation shadow is visible (a button has no child views to clip).
    override var clipsToBounds: Bool {
        get { return false }
        set { super.clipsToBounds = false }
    }
}

// MARK: - CompoundButton

/// android.widget.CompoundButton: a checkable framework Button (Switch extends it). Widget.CompoundButton: no button
/// face, gravity center_vertical|start, ?attr/textAppearance (14 sp), textColorPrimaryDisableOnly.
class ACompoundButton: AButton {
    var aw_compoundChecked = false
    private var aw_broadcasting = false
    private var aw_onCheckedChangeListener: ((ACompoundButton, Bool) -> Void)?

    override init() {
        super.init(style: .FRAMEWORK)
        aw_configureCompound()
    }

    override init(style: Style) {
        super.init(style: style)
        aw_configureCompound()
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    private func aw_configureCompound() {
        aw_installStateListAnimator(nil)
        elevation = 0
        translationZ = 0
        super.setBackgroundDrawable(nil)
        setPadding(0, 0, 0, 0)
        setGravity(AGravity.CENTER_VERTICAL | AGravity.START)
        aw_setRawTextSize(ATypedValue.applyDimension(ATypedValue.COMPLEX_UNIT_SP, 14), shouldRequestLayout: true)
        setAllCaps(false)
        setTextColor(AWMaterialColors.textColorPrimaryDisableOnly)
        // Widget.CompoundButton has no minimum / maximum sizes (TextView defaults).
        aw_minimum = 0
        aw_minMode = ATextView.LINES
        minimumHeight = 0
        minWidth = 0
        minimumWidth = 0
        maxWidth = Int(Int32.max)
    }

    /// CompoundButton.isChecked / setChecked.
    override var isChecked: Bool {
        get { return aw_compoundChecked }
        set { setChecked(newValue) }
    }

    override func setChecked(_ checked: Bool) {
        if aw_compoundChecked != checked {
            aw_compoundChecked = checked
            refreshDrawableState()
            aw_checkedDidChange()
            if aw_broadcasting { return }
            aw_broadcasting = true
            aw_onCheckedChangeListener?(self, aw_compoundChecked)
            aw_broadcasting = false
        }
    }

    /// Hook for ASwitch (thumb animation).
    func aw_checkedDidChange() {}

    override func toggle() { setChecked(!aw_compoundChecked) }

    /// CompoundButton.setOnCheckedChangeListener (Kotlin `{ _, isChecked -> }`).
    func setOnCheckedChangeListener(_ listener: ((ACompoundButton, Bool) -> Void)?) { aw_onCheckedChangeListener = listener }

    /// CompoundButton.onCreateDrawableState: checked.
    override func onCreateDrawableState(_ extraSpace: Int) -> [Int] {
        var state = super.onCreateDrawableState(extraSpace + 1)
        if aw_compoundChecked { state.append(AStateSet.state_checked) }
        return state
    }

    /// CompoundButton.performClick: toggles first, then the click listener (a framework Button never toggles itself).
    @discardableResult
    override func performClick() -> Bool {
        toggle()
        let handled = super.performClick()
        if !handled { invalidate() }
        return handled
    }

    override var accessibilityValue: String? {
        get { return aw_compoundChecked ? "1" : "0" }
        set { super.accessibilityValue = newValue }
    }
}
