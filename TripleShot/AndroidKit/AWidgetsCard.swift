import UIKit

// AndroidKit widgets (area kit-widgets): com.google.android.material.card.MaterialCardView (androidx CardView, a
// FrameLayout), following material-components-android 1.12.0 (MaterialCardView / MaterialCardViewHelper) and androidx
// CardView 1.0 (CardViewApi21Impl):
// - Widget.MaterialComponents.CardView under Theme.TripleShot (light palette per VIEW-API): cardBackgroundColor
//   ?colorSurface (#FFFFFF), corner size 4 dp (shapeAppearanceMediumComponent), cardElevation 1 dp, strokeColor -1 (white),
//   strokeWidth 0, cardForegroundColor transparent, useCompatPadding false, preventCornerOverlap true (no extra padding on
//   API 21+ for a round rect);
// - the background is the MaterialShapeDrawable fill; the foreground (drawn above the children) is the transparent shape
//   with the stroke inside it; CardView clips its children to the rounded outline (setClipToOutline(true));
// - CardView.setPadding / setPaddingRelative do nothing: the padding is the content padding (setContentPadding);
// - the elevation shadow follows the rounded outline (MaterialShapeDrawable.getOutline, alpha 1).
// Ripples and the checked icon (no card in the app is checkable) are not drawn.

/// MaterialCardView background: the card colour in the rounded rect (MaterialShapeDrawable fill).
final class AWCardBackground: ADrawable, ADrawableOutlineProvider {
    var color: AColorStateList = AColorStateList.valueOf(AWMaterialColors.colorSurface)
    var radius: Float = 0
    private let paint = APaint(APaint.ANTI_ALIAS_FLAG)

    override var isStateful: Bool { return color.isStateful }
    override func onStateChange(_ state: [Int]) -> Bool { return color.isStateful }

    func currentColor() -> Int { return color.getColorForState(state, color.defaultColor) }

    override func draw(_ canvas: ACanvas) {
        let b = bounds
        if b.width() <= 0 || b.height() <= 0 { return }
        let c = currentColor()
        if AColor.alpha(c) == 0 { return }
        paint.style = .FILL
        paint.color = c
        paint.alpha = AColor.alpha(c) * alpha / 255
        let r = min(radius, Float(min(b.width(), b.height())) / 2)
        canvas.drawRoundRect(ARectF(Float(b.left), Float(b.top), Float(b.right), Float(b.bottom)), r, r, paint)
    }

    /// MaterialShapeDrawable.getOutline: the rounded rect; the outline alpha stays 1 (shadow even when translucent).
    func getOutline(_ outline: AOutline) {
        let b = bounds
        outline.setRoundRect(b.left, b.top, b.right, b.bottom, min(radius, Float(min(b.width(), b.height())) / 2))
    }
}

/// MaterialCardView foreground (foregroundContentDrawable): the card foreground colour and the stroke, inset by half its
/// width (MaterialShapeDrawable strokes inside the shape).
final class AWCardForeground: ADrawable {
    var strokeWidth = 0
    var strokeColor: AColorStateList? = AColorStateList.valueOf(-1)
    var foregroundColor: AColorStateList = AColorStateList.valueOf(AColor.TRANSPARENT)
    var radius: Float = 0
    private let paint = APaint(APaint.ANTI_ALIAS_FLAG)

    override var isStateful: Bool { return foregroundColor.isStateful || (strokeColor?.isStateful ?? false) }
    override func onStateChange(_ state: [Int]) -> Bool { return isStateful }

    override func draw(_ canvas: ACanvas) {
        let b = bounds
        if b.width() <= 0 || b.height() <= 0 { return }
        let r = min(radius, Float(min(b.width(), b.height())) / 2)
        let fg = foregroundColor.getColorForState(state, foregroundColor.defaultColor)
        if AColor.alpha(fg) > 0 {
            paint.style = .FILL
            paint.color = fg
            paint.alpha = AColor.alpha(fg) * alpha / 255
            canvas.drawRoundRect(ARectF(Float(b.left), Float(b.top), Float(b.right), Float(b.bottom)), r, r, paint)
        }
        guard strokeWidth > 0, let sc = strokeColor else { return }
        let c = sc.getColorForState(state, sc.defaultColor)
        if AColor.alpha(c) == 0 { return }
        let half = Float(strokeWidth) / 2
        paint.style = .STROKE
        paint.strokeWidth = Float(strokeWidth)
        paint.color = c
        paint.alpha = AColor.alpha(c) * alpha / 255
        let sr = max(r - half, 0)
        canvas.drawRoundRect(ARectF(Float(b.left) + half, Float(b.top) + half, Float(b.right) - half, Float(b.bottom) - half), sr, sr, paint)
    }
}

/// com.google.android.material.card.MaterialCardView (CardView / FrameLayout).
class ACardView: AFrameLayout {
    /// MaterialCardView.DEFAULT_STROKE_VALUE.
    static let DEFAULT_STROKE_VALUE = -1

    let aw_cardBackground = AWCardBackground()
    let aw_cardForeground = AWCardForeground()
    private var aw_userContentPadding = ARect()
    private var aw_useCompatPadding = false
    private var aw_preventCornerOverlap = true
    private var aw_maxCardElevation: Float = 0
    private var aw_checkable = false
    private var aw_checked = false
    private var aw_dragged = false
    private var aw_rippleColor: AColorStateList?
    private var aw_backgroundOverwritten = false
    private var aw_parentInitialized = false
    private var aw_onCheckedChangeListener: ((ACardView, Bool) -> Void)?

    override init() {
        super.init()
        // CardView(context): the round-rect background, elevation and clip to outline (CardViewApi21Impl.initialize).
        let elevation = Float(1) * AWidgetEnv.density
        aw_maxCardElevation = elevation
        self.elevation = elevation
        aw_parentInitialized = true
        // MaterialCardViewHelper.loadFromAttributes.
        let radius = Float(4) * AWidgetEnv.density
        aw_cardBackground.radius = radius
        aw_cardForeground.radius = radius
        aw_cardForeground.strokeColor = AColorStateList.valueOf(ACardView.DEFAULT_STROKE_VALUE)
        aw_cardForeground.strokeWidth = 0
        super.setBackgroundDrawable(aw_cardBackground)
        foreground = aw_cardForeground
        aw_updateContentPadding()
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    // MARK: Background and foreground

    /// MaterialCardView.setBackgroundDrawable: "Setting a custom background is not supported" — it is set anyway and
    /// the card's shape background is gone.
    override func setBackgroundDrawable(_ background: ADrawable?) {
        if aw_parentInitialized {
            aw_backgroundOverwritten = true
            super.setBackgroundDrawable(background)
            aw_updateShadow()
        }
    }

    /// MaterialCardView.getCardBackgroundColor.
    var cardBackgroundColor: AColorStateList { return aw_cardBackground.color }
    func getCardBackgroundColor() -> AColorStateList { return aw_cardBackground.color }

    func setCardBackgroundColor(_ color: Int) { setCardBackgroundColor(AColorStateList.valueOf(color)) }

    /// MaterialCardViewHelper.setCardBackgroundColor (bgDrawable.setFillColor; null leaves no fill).
    func setCardBackgroundColor(_ color: AColorStateList?) {
        aw_cardBackground.color = color ?? AColorStateList.valueOf(AColor.TRANSPARENT)
        aw_cardBackground.setState(drawableState)
        aw_updateShadow()
        invalidate()
    }

    /// MaterialCardView.setCardForegroundColor (null = transparent).
    func setCardForegroundColor(_ foregroundColor: AColorStateList?) {
        aw_cardForeground.foregroundColor = foregroundColor ?? AColorStateList.valueOf(AColor.TRANSPARENT)
        aw_cardForeground.setState(drawableState)
        invalidate()
    }

    var cardForegroundColor: AColorStateList { return aw_cardForeground.foregroundColor }

    // MARK: Shape

    /// CardView.setRadius / MaterialCardView.getRadius (px, the shape's corner size).
    var radius: Float {
        get { return aw_cardBackground.radius }
        set { setRadius(newValue) }
    }

    func getRadius() -> Float { return aw_cardBackground.radius }

    func setRadius(_ radius: Float) {
        aw_cardBackground.radius = radius
        aw_cardForeground.radius = radius
        aw_updateClip()
        aw_updateShadow()
        invalidate()
    }

    // MARK: Elevation (CardView.setCardElevation: View elevation)

    var cardElevation: Float {
        get { return elevation }
        set { setCardElevation(newValue) }
    }

    func getCardElevation() -> Float { return elevation }

    func setCardElevation(_ elevation: Float) {
        self.elevation = elevation
        aw_updateShadow()
    }

    var maxCardElevation: Float {
        get { return aw_maxCardElevation }
        set { setMaxCardElevation(newValue) }
    }

    func setMaxCardElevation(_ maxCardElevation: Float) { aw_maxCardElevation = maxCardElevation }

    // MARK: Stroke

    /// MaterialCardView.setStrokeWidth (px).
    var strokeWidth: Int {
        get { return aw_cardForeground.strokeWidth }
        set { setStrokeWidth(newValue) }
    }

    func setStrokeWidth(_ strokeWidth: Int) {
        if aw_cardForeground.strokeWidth != strokeWidth {
            aw_cardForeground.strokeWidth = strokeWidth
        }
        invalidate()
    }

    /// MaterialCardView.getStrokeColor (deprecated int getter) / setStrokeColor(int).
    var strokeColor: Int {
        get { return aw_cardForeground.strokeColor?.defaultColor ?? ACardView.DEFAULT_STROKE_VALUE }
        set { setStrokeColor(AColorStateList.valueOf(newValue)) }
    }

    func getStrokeColor() -> Int { return strokeColor }

    var strokeColorStateList: AColorStateList? { return aw_cardForeground.strokeColor }

    func setStrokeColor(_ strokeColor: Int) { setStrokeColor(AColorStateList.valueOf(strokeColor)) }

    func setStrokeColor(_ strokeColor: AColorStateList?) {
        if aw_cardForeground.strokeColor !== strokeColor {
            aw_cardForeground.strokeColor = strokeColor
            aw_cardForeground.setState(drawableState)
        }
        invalidate()
    }

    /// MaterialCardView.rippleColor (ripples are not drawn).
    var rippleColor: AColorStateList? {
        get { return aw_rippleColor }
        set { aw_rippleColor = newValue }
    }

    func setRippleColor(_ rippleColor: AColorStateList?) { aw_rippleColor = rippleColor }

    // MARK: Padding (CardView content padding)

    /// CardView.setPadding: a no-op (the content padding is the padding).
    override func setPadding(_ left: Int, _ top: Int, _ right: Int, _ bottom: Int) {}

    /// CardView.setPaddingRelative: a no-op.
    override func setPaddingRelative(_ start: Int, _ top: Int, _ end: Int, _ bottom: Int) {}

    /// MaterialCardView.setContentPadding -> MaterialCardViewHelper.setUserContentPadding.
    func setContentPadding(_ left: Int, _ top: Int, _ right: Int, _ bottom: Int) {
        aw_userContentPadding.set(left, top, right, bottom)
        aw_updateContentPadding()
    }

    /// MaterialCardViewHelper.updateContentPadding -> CardView.setContentPadding -> CardViewApi21Impl.updatePadding:
    /// without compat padding the padding is the content padding (no corner offset for a round rect).
    private func aw_updateContentPadding() {
        let p = aw_userContentPadding
        super.setPadding(p.left, p.top, p.right, p.bottom)
        aw_updateClip()
    }

    var contentPaddingLeft: Int { return aw_userContentPadding.left }
    var contentPaddingTop: Int { return aw_userContentPadding.top }
    var contentPaddingRight: Int { return aw_userContentPadding.right }
    var contentPaddingBottom: Int { return aw_userContentPadding.bottom }

    /// CardView.useCompatPadding (API 21+: only matters when enabled; the shadow padding is not emulated).
    var useCompatPadding: Bool {
        get { return aw_useCompatPadding }
        set { aw_useCompatPadding = newValue; aw_updateContentPadding() }
    }

    func setUseCompatPadding(_ useCompatPadding: Bool) { self.useCompatPadding = useCompatPadding }

    var preventCornerOverlap: Bool {
        get { return aw_preventCornerOverlap }
        set { aw_preventCornerOverlap = newValue; aw_updateContentPadding() }
    }

    func setPreventCornerOverlap(_ preventCornerOverlap: Bool) { self.preventCornerOverlap = preventCornerOverlap }

    // MARK: Checkable

    var isCheckable: Bool {
        get { return aw_checkable }
        set { setCheckable(newValue) }
    }

    func setCheckable(_ checkable: Bool) { aw_checkable = checkable }

    var isChecked: Bool {
        get { return aw_checked }
        set { setChecked(newValue) }
    }

    /// MaterialCardView.setChecked -> toggle().
    func setChecked(_ checked: Bool) {
        if aw_checked != checked { toggle() }
    }

    /// MaterialCardView.toggle: only a checkable, enabled card.
    func toggle() {
        if aw_checkable && isEnabled {
            aw_checked = !aw_checked
            refreshDrawableState()
            aw_onCheckedChangeListener?(self, aw_checked)
        }
    }

    func setOnCheckedChangeListener(_ listener: ((ACardView, Bool) -> Void)?) { aw_onCheckedChangeListener = listener }

    var isDragged: Bool {
        get { return aw_dragged }
        set {
            if aw_dragged != newValue {
                aw_dragged = newValue
                refreshDrawableState()
            }
        }
    }

    /// MaterialCardView.onCreateDrawableState: checkable / checked / dragged.
    override func onCreateDrawableState(_ extraSpace: Int) -> [Int] {
        var state = super.onCreateDrawableState(extraSpace + 3)
        if aw_checkable { state.append(AStateSet.state_checkable) }
        if aw_checked { state.append(AStateSet.state_checked) }
        if aw_dragged { state.append(ACardView.STATE_DRAGGED) }
        return state
    }

    /// R.attr.state_dragged of the Material library.
    static let STATE_DRAGGED = 0x7F04_0466

    // MARK: Clipping and shadow

    /// CardView clips its children to the rounded outline (setClipToOutline(true)): the child host clips, rounded
    /// when it spans the card (no padding box clip).
    override func applyChildHostFrame(_ frame: CGRect, clips: Bool) {
        super.applyChildHostFrame(frame, clips: true)
        aw_updateClip()
    }

    private func aw_updateClip() {
        guard let host = mChildHost else { return }
        if !host.clipsToBounds { host.clipsToBounds = true }
        let d = CGFloat(AWidgetEnv.density)
        let spansCard = abs(host.frame.minX) < 0.01 && abs(host.frame.minY) < 0.01
            && abs(host.frame.width - CGFloat(width) / d) < 0.01 && abs(host.frame.height - CGFloat(height) / d) < 0.01
        let r = CGFloat(min(aw_cardBackground.radius, Float(min(width, height)) / 2)) / d
        let corner = spansCard && !aw_backgroundOverwritten ? max(r, 0) : 0
        if host.layer.cornerRadius != corner { host.layer.cornerRadius = corner }
    }

    override func onSizeChanged(_ w: Int, _ h: Int, _ oldw: Int, _ oldh: Int) {
        super.onSizeChanged(w, h, oldw, oldh)
        aw_updateClip()
        aw_updateShadow()
    }

    override func onLayout(_ changed: Bool, _ l: Int, _ t: Int, _ r: Int, _ b: Int) {
        super.onLayout(changed, l, t, r, b)
        aw_updateShadow()
    }

    override func drawableStateChanged() {
        super.drawableStateChanged()
        aw_updateShadow()
    }

    override var elevation: Float { didSet { if oldValue != elevation { aw_updateShadow() } } }
    override var translationZ: Float { didSet { if oldValue != translationZ { aw_updateShadow() } } }

    func aw_updateShadow() {
        AWShadow.update(self, background, z)
    }

    /// The card layer stays unmasked so its shadow shows; the children are clipped by the child host instead.
    override var clipsToBounds: Bool {
        get { return false }
        set { super.clipsToBounds = false }
    }
}
