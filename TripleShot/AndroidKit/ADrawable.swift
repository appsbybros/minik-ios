import CoreGraphics
import Foundation

// android.graphics.drawable.* (VIEW-API "Graphics"): Drawable, ColorDrawable, BitmapDrawable, GradientDrawable
// (ported from GradientDrawable.draw / ensureValidRect / buildRing), InsetDrawable, VectorDrawable, and
// ContextCompat.getDrawable over the app's resources: bitmaps by name and the Swift ports of
// res/drawable/*.xml (shape drawables and the triple_help / triple_pause / triple_play vector icons).
// Bounds, sizes, radii and strokes are Android pixels. Drawables are drawn with the ACanvas/APaint pipeline,
// so they render exactly like the equivalent Canvas calls.

// MARK: - Drawable

/// android.graphics.drawable.Drawable. Subclasses override `draw`, `alpha`, `intrinsicWidth/Height`,
/// `isStateful`, `onStateChange`, `onBoundsChange`, `onLevelChange`, `getPadding`, `setTintList`.
class ADrawable {
    private let kgBounds = ARect()
    private var kgStateSet: [Int] = AStateSet.WILD_CARD
    private var kgLevel = 0
    private var kgVisible = true
    private var kgAlpha = 0xFF
    private var kgLayoutDirection = 0

    /// The Drawable.Callback (the view that shows this drawable; weak). invalidateSelf() invalidates it.
    weak var callbackView: AView? {
        didSet { kgCallbackChanged() }
    }

    init() {}

    /// Draws in its bounds.
    func draw(_ canvas: ACanvas) {}

    // MARK: Bounds

    /// `getBounds()`: the drawable's own Rect (mutating it directly does not call onBoundsChange, like Android).
    var bounds: ARect {
        get { return kgBounds }
        set { setBounds(newValue) }
    }

    final func getBounds() -> ARect { return kgBounds }

    /// `setBounds(left, top, right, bottom)`: onBoundsChange when the rect changes.
    func setBounds(_ left: Int, _ top: Int, _ right: Int, _ bottom: Int) {
        let old = kgBounds
        if old.left != left || old.top != top || old.right != right || old.bottom != bottom {
            if !old.isEmpty() {
                // first invalidate the previous bounds
                invalidateSelf()
            }
            kgBounds.set(left, top, right, bottom)
            onBoundsChange(kgBounds)
        }
    }

    func setBounds(_ bounds: ARect) {
        setBounds(bounds.left, bounds.top, bounds.right, bounds.bottom)
    }

    final func copyBounds() -> ARect { return ARect(kgBounds) }
    final func copyBounds(_ bounds: ARect) { bounds.set(kgBounds) }

    func onBoundsChange(_ bounds: ARect) {}

    // MARK: Size

    /// -1 = no intrinsic size.
    var intrinsicWidth: Int { return -1 }
    var intrinsicHeight: Int { return -1 }
    final func getIntrinsicWidth() -> Int { return intrinsicWidth }
    final func getIntrinsicHeight() -> Int { return intrinsicHeight }

    /// `getMinimumWidth()`: the intrinsic width when positive, else 0.
    var minimumWidth: Int {
        let w = intrinsicWidth
        return w > 0 ? w : 0
    }

    var minimumHeight: Int {
        let h = intrinsicHeight
        return h > 0 ? h : 0
    }

    /// `getPadding(padding)`: false and 0 padding unless the drawable has padding.
    func getPadding(_ padding: ARect) -> Bool {
        padding.set(0, 0, 0, 0)
        return false
    }

    // MARK: Alpha, tint

    /// 0...255. (Drawable.getAlpha defaults to 255.)
    var alpha: Int {
        get { return kgAlpha }
        set { kgAlpha = newValue }
    }

    final func getAlpha() -> Int { return alpha }
    final func setAlpha(_ alpha: Int) { self.alpha = alpha }

    func setTint(_ tintColor: Int) {
        setTintList(AColorStateList.valueOf(tintColor))
    }

    /// Tinting (SRC_IN); the base Drawable ignores it like Android.
    func setTintList(_ tint: AColorStateList?) {}

    @discardableResult
    func mutate() -> ADrawable { return self }

    // MARK: Callback

    func invalidateSelf() {
        callbackView?.invalidate()
    }

    final func getCallback() -> AView? { return callbackView }
    final func setCallback(_ view: AView?) { callbackView = view }

    func kgCallbackChanged() {}

    // MARK: State, level, visibility

    /// `setState(stateSet)`: onStateChange when the set differs; returns its result.
    @discardableResult
    func setState(_ stateSet: [Int]) -> Bool {
        if kgStateSet != stateSet {
            kgStateSet = stateSet
            return onStateChange(stateSet)
        }
        return false
    }

    var state: [Int] {
        get { return kgStateSet }
        set { setState(newValue) }
    }

    final func getState() -> [Int] { return kgStateSet }

    var isStateful: Bool { return false }

    func onStateChange(_ state: [Int]) -> Bool { return false }

    func jumpToCurrentState() {}

    @discardableResult
    func setLevel(_ level: Int) -> Bool {
        if kgLevel != level {
            kgLevel = level
            return onLevelChange(level)
        }
        return false
    }

    var level: Int {
        get { return kgLevel }
        set { setLevel(newValue) }
    }

    final func getLevel() -> Int { return kgLevel }

    func onLevelChange(_ level: Int) -> Bool { return false }

    @discardableResult
    func setVisible(_ visible: Bool, _ restart: Bool) -> Bool {
        let changed = kgVisible != visible
        if changed {
            kgVisible = visible
            invalidateSelf()
        }
        return changed
    }

    var isVisible: Bool { return kgVisible }

    @discardableResult
    func setLayoutDirection(_ layoutDirection: Int) -> Bool {
        if kgLayoutDirection != layoutDirection {
            kgLayoutDirection = layoutDirection
            return true
        }
        return false
    }

    var layoutDirection: Int { return kgLayoutDirection }

    /// The tint filter colour of a tint list for the current state (`updateBlendModeFilter`: a
    /// BlendModeColorFilter(tint.getColorForState(getState(), TRANSPARENT), SRC_IN)); nil without a tint.
    fileprivate func kgTintFilter(_ tint: AColorStateList?) -> Int? {
        return tint?.getColorForState(state, AColor.TRANSPARENT)
    }
}

// MARK: - ColorDrawable

/// android.graphics.drawable.ColorDrawable: fills its bounds with a colour; setAlpha modulates the colour's alpha.
final class AColorDrawable: ADrawable {
    private var baseColor: Int
    private var useColor: Int
    private let paint = APaint(APaint.ANTI_ALIAS_FLAG)
    private var tint: AColorStateList?

    override init() {
        baseColor = 0
        useColor = 0
        super.init()
    }

    init(_ color: Int) {
        baseColor = color
        useColor = color
        super.init()
    }

    /// `getColor()` / `setColor(color)`.
    var color: Int {
        get { return useColor }
        set {
            if baseColor != newValue || useColor != newValue {
                baseColor = newValue
                useColor = newValue
                invalidateSelf()
            }
        }
    }

    func setColor(_ color: Int) { self.color = color }
    func getColor() -> Int { return color }

    override var alpha: Int {
        get { return Int(UInt32(truncatingIfNeeded: useColor) >> 24) }
        set {
            var a = Int32(truncatingIfNeeded: newValue)
            a = a &+ (a >> 7) // make it 0..256
            let base = Int32(truncatingIfNeeded: baseColor)
            let baseAlpha = Int32(bitPattern: UInt32(bitPattern: base) >> 24)
            let useAlpha = (baseAlpha &* a) >> 8
            let use = Int32(bitPattern: UInt32(bitPattern: base &<< 8) >> 8) | (useAlpha &<< 24)
            if Int32(truncatingIfNeeded: useColor) != use {
                useColor = Int(use)
                invalidateSelf()
            }
        }
    }

    override func setTintList(_ tint: AColorStateList?) {
        self.tint = tint
        invalidateSelf()
    }

    override var isStateful: Bool { return tint?.isStateful ?? false }

    /// ColorDrawable.onStateChange: true whenever a tint is set (its filter colour follows the state).
    override func onStateChange(_ state: [Int]) -> Bool {
        return tint != nil
    }

    /// ColorDrawable.draw: the bounds filled with the colour, through the tint's SRC_IN colour filter.
    override func draw(_ canvas: ACanvas) {
        let filter = kgTintFilter(tint)
        if (UInt32(truncatingIfNeeded: useColor) >> 24) != 0 || filter != nil {
            paint.kgColorFilter = filter
            paint.color = useColor
            canvas.drawRect(bounds, paint)
            paint.kgColorFilter = nil
        }
    }
}

// MARK: - BitmapDrawable

/// android.graphics.drawable.BitmapDrawable: the bitmap scaled into the bounds (gravity FILL), filtered.
/// A resource drawable decodes its image on first draw; its intrinsic size is Android's (pixel size for
/// drawable-nodpi, density-scaled for drawable/).
final class ABitmapDrawable: ADrawable {
    private let resName: ADrawableRes?
    private var loadedBitmap: ABitmap?
    private let intrinsic: (width: Int, height: Int)
    /// `getPaint()`: FILTER_BITMAP_FLAG | DITHER_FLAG like Android's BitmapDrawable.
    let paint = APaint(APaint.FILTER_BITMAP_FLAG | APaint.DITHER_FLAG)
    private var tint: AColorStateList?

    init(_ res: ADrawableRes) {
        resName = res
        intrinsic = AResources.drawableIntrinsicSize(res)
        super.init()
    }

    init(_ bitmap: ABitmap?) {
        resName = nil
        loadedBitmap = bitmap
        intrinsic = bitmap.map { ($0.width, $0.height) } ?? (-1, -1)
        super.init()
    }

    var bitmap: ABitmap? {
        if loadedBitmap == nil, let r = resName, let image = AResources.cgImage(r) {
            loadedBitmap = ABitmap(cgImage: image)
        }
        return loadedBitmap
    }

    func getBitmap() -> ABitmap? { return bitmap }
    func getPaint() -> APaint { return paint }

    override var intrinsicWidth: Int { return intrinsic.width }
    override var intrinsicHeight: Int { return intrinsic.height }

    override var alpha: Int {
        get { return paint.alpha }
        set {
            if newValue != paint.alpha {
                paint.alpha = newValue
                invalidateSelf()
            }
        }
    }

    func setAntiAlias(_ aa: Bool) {
        paint.isAntiAlias = aa
        invalidateSelf()
    }

    func setFilterBitmap(_ filter: Bool) {
        paint.isFilterBitmap = filter
        invalidateSelf()
    }

    var isFilterBitmap: Bool { return paint.isFilterBitmap }

    override func setTintList(_ tint: AColorStateList?) {
        self.tint = tint
        invalidateSelf()
    }

    override var isStateful: Bool { return tint?.isStateful ?? false }

    /// BitmapDrawable.onStateChange: true whenever a tint is set (its filter colour follows the state).
    override func onStateChange(_ state: [Int]) -> Bool {
        return tint != nil
    }

    /// BitmapDrawable.draw (gravity FILL): the bitmap scaled into the bounds with the drawable's paint, through
    /// the tint's SRC_IN colour filter.
    override func draw(_ canvas: ACanvas) {
        guard let b = bitmap, !b.isRecycled else { return }
        paint.kgColorFilter = kgTintFilter(tint)
        canvas.drawBitmap(b, nil, bounds, paint)
        paint.kgColorFilter = nil
    }
}

// MARK: - GradientDrawable

/// android.graphics.drawable.GradientDrawable: rectangle (corner radius or radii) / oval / line / ring, solid
/// colour (ColorStateList) or linear / radial gradient, stroke (ColorStateList, dashes) inset by half its width,
/// drawable alpha modulating fill and stroke (with a layer when both are translucent). Not final: Java
/// subclasses (e.g. a marker class) extend it.
class AGradientDrawable: ADrawable {
    static let RECTANGLE = 0
    static let OVAL = 1
    static let LINE = 2
    static let RING = 3
    static let LINEAR_GRADIENT = 0
    static let RADIAL_GRADIENT = 1
    static let SWEEP_GRADIENT = 2
    static let RADIUS_TYPE_PIXELS = 0
    static let RADIUS_TYPE_FRACTION = 1
    static let RADIUS_TYPE_FRACTION_PARENT = 2

    enum Orientation { case TOP_BOTTOM, TR_BL, RIGHT_LEFT, BR_TL, BOTTOM_TOP, BL_TR, LEFT_RIGHT, TL_BR }

    // GradientState
    private var stShape = AGradientDrawable.RECTANGLE
    private var stGradient = AGradientDrawable.LINEAR_GRADIENT
    private var stOrientation: Orientation
    private var stSolidColors: AColorStateList?
    private var stStrokeColors: AColorStateList?
    private var stGradientColors: [Int]?
    private var stPositions: [Float]?
    private var stStrokeWidth = -1
    private var stStrokeDashWidth: Float = 0
    private var stStrokeDashGap: Float = 0
    private var stRadius: Float = 0
    private var stRadiusArray: [Float]?
    private var stPadding: ARect?
    private var stWidth = -1
    private var stHeight = -1
    private var stInnerRadiusRatio: Float = 3.0
    private var stThicknessRatio: Float = 9.0
    private var stInnerRadius = -1
    private var stThickness = -1
    private var stDither = false
    private var stCenterX: Float = 0.5
    private var stCenterY: Float = 0.5
    private var stGradientRadius: Float = 0.5
    private var stGradientRadiusType = AGradientDrawable.RADIUS_TYPE_PIXELS
    private var stUseLevel = false
    private var stUseLevelForShape = true
    private var stTint: AColorStateList?

    // Drawable fields
    private let fillPaint = APaint(APaint.ANTI_ALIAS_FLAG)
    private var strokePaint: APaint?
    private var layerPaint: APaint?
    private var gdAlpha = 0xFF
    private let gdPath = APath()
    private let gdRect = ARectF()
    private var gradientIsDirty = false
    private var pathIsDirty = true
    private var ringPath: APath?
    private var computedGradientRadius: Float = 0

    /// `new GradientDrawable()`: rectangle, TOP_BOTTOM, no colours (transparent until setColor).
    override init() {
        stOrientation = .TOP_BOTTOM
        super.init()
        updateLocalState()
    }

    /// `new GradientDrawable(orientation, colors)`.
    init(_ orientation: Orientation, _ colors: [Int]?) {
        stOrientation = orientation
        stGradientColors = colors
        super.init()
        updateLocalState()
    }

    private func updateLocalState() {
        if let solid = stSolidColors {
            fillPaint.color = solid.getColorForState(state, 0)
        } else if stGradientColors == nil {
            // If we don't have a solid color and we don't have a gradient, the app is stroking the shape.
            fillPaint.color = 0
        } else {
            // Otherwise, make sure the fill alpha is maxed out.
            fillPaint.color = AColor.BLACK
        }
        if stStrokeWidth >= 0 {
            let p = APaint(APaint.ANTI_ALIAS_FLAG)
            p.style = .STROKE
            p.strokeWidth = Float(stStrokeWidth)
            if let sc = stStrokeColors {
                p.color = sc.getColorForState(state, 0)
            }
            if stStrokeDashWidth != 0 {
                p.pathEffect = ADashPathEffect([stStrokeDashWidth, stStrokeDashGap], 0)
            }
            strokePaint = p
        }
        gradientIsDirty = true
    }

    // MARK: Shape and corners

    /// `getShape()` / `setShape(shape)`.
    var shape: Int {
        get { return stShape }
        set {
            ringPath = nil
            pathIsDirty = true
            stShape = newValue
            invalidateSelf()
        }
    }

    final func setShape(_ shape: Int) { self.shape = shape }
    final func getShape() -> Int { return shape }

    /// `getCornerRadius()` / `setCornerRadius(radius)` (px; negative = 0; clears the radii array).
    var cornerRadius: Float {
        get { return stRadius }
        set {
            stRadius = newValue < 0 ? 0 : newValue
            stRadiusArray = nil
            pathIsDirty = true
            invalidateSelf()
        }
    }

    final func setCornerRadius(_ radius: Float) { cornerRadius = radius }
    final func getCornerRadius() -> Float { return cornerRadius }

    /// `getCornerRadii()` / `setCornerRadii(radii)`: 8 values, top-left x/y, top-right, bottom-right, bottom-left.
    var cornerRadii: [Float]? {
        get { return stRadiusArray }
        set {
            stRadiusArray = newValue
            if newValue == nil {
                stRadius = 0
            }
            pathIsDirty = true
            invalidateSelf()
        }
    }

    final func setCornerRadii(_ radii: [Float]?) { cornerRadii = radii }
    final func getCornerRadii() -> [Float]? { return cornerRadii }

    /// `setSize(width, height)`: the intrinsic size.
    func setSize(_ width: Int, _ height: Int) {
        stWidth = width
        stHeight = height
        pathIsDirty = true
        invalidateSelf()
    }

    override var intrinsicWidth: Int { return stWidth }
    override var intrinsicHeight: Int { return stHeight }

    /// `setPadding(left, top, right, bottom)` (API 29).
    func setPadding(_ left: Int, _ top: Int, _ right: Int, _ bottom: Int) {
        stPadding = ARect(left, top, right, bottom)
        invalidateSelf()
    }

    override func getPadding(_ padding: ARect) -> Bool {
        if let p = stPadding {
            padding.set(p)
            return true
        }
        return super.getPadding(padding)
    }

    // MARK: Ring

    func setInnerRadius(_ innerRadius: Int) { stInnerRadius = innerRadius; ringPath = nil; invalidateSelf() }
    func setInnerRadiusRatio(_ ratio: Float) { stInnerRadiusRatio = ratio; ringPath = nil; invalidateSelf() }
    func setThickness(_ thickness: Int) { stThickness = thickness; ringPath = nil; invalidateSelf() }
    func setThicknessRatio(_ ratio: Float) { stThicknessRatio = ratio; ringPath = nil; invalidateSelf() }
    /// android:useLevel for rings (default true: a ring sweeps level * 360 / 10000 degrees).
    func kgSetUseLevelForShape(_ useLevel: Bool) { stUseLevelForShape = useLevel; ringPath = nil; invalidateSelf() }

    // MARK: Colours

    /// `setColor(argb)`: a solid fill (clears the gradient colours).
    func setColor(_ argb: Int) {
        stSolidColors = AColorStateList.valueOf(argb)
        stGradientColors = nil
        fillPaint.color = argb
        invalidateSelf()
    }

    /// `setColor(colorStateList)`: a state-dependent solid fill; nil = transparent.
    func setColor(_ colorStateList: AColorStateList?) {
        guard let list = colorStateList else {
            setColor(AColor.TRANSPARENT)
            return
        }
        let color = list.getColorForState(state, 0)
        stSolidColors = list
        stGradientColors = nil
        fillPaint.color = color
        invalidateSelf()
    }

    /// `getColor()` (API 24): the solid ColorStateList, nil for gradients.
    func getColor() -> AColorStateList? { return stSolidColors }

    /// Kotlin `drawable.color` (= getColor()).
    var color: AColorStateList? { return stSolidColors }

    /// `getColors()` / `setColors(colors)` (= setColors(colors, null)): gradient colours, evenly spaced (clears the
    /// solid colour and the offsets).
    var colors: [Int]? {
        get { return stGradientColors }
        set {
            stGradientColors = newValue
            stSolidColors = nil
            stPositions = nil
            gradientIsDirty = true
            invalidateSelf()
        }
    }

    final func setColors(_ colors: [Int]?) { self.colors = colors }
    final func getColors() -> [Int]? { return colors }

    /// `setColors(colors, offsets)` (API 29).
    func setColors(_ colors: [Int]?, _ offsets: [Float]?) {
        stGradientColors = colors
        stSolidColors = nil
        stPositions = offsets
        gradientIsDirty = true
        invalidateSelf()
    }

    var orientation: Orientation {
        get { return stOrientation }
        set {
            stOrientation = newValue
            gradientIsDirty = true
            invalidateSelf()
        }
    }

    final func setOrientation(_ orientation: Orientation) { self.orientation = orientation }
    final func getOrientation() -> Orientation { return orientation }

    /// LINEAR_GRADIENT, RADIAL_GRADIENT or SWEEP_GRADIENT.
    var gradientType: Int {
        get { return stGradient }
        set {
            stGradient = newValue
            gradientIsDirty = true
            invalidateSelf()
        }
    }

    final func setGradientType(_ gradient: Int) { gradientType = gradient }
    final func getGradientType() -> Int { return gradientType }

    /// `setGradientRadius(px)` / `getGradientRadius()` (0 unless RADIAL_GRADIENT).
    var gradientRadius: Float {
        get {
            if stGradient != AGradientDrawable.RADIAL_GRADIENT { return 0 }
            _ = ensureValidRect()
            return computedGradientRadius
        }
        set {
            stGradientRadius = newValue
            stGradientRadiusType = AGradientDrawable.RADIUS_TYPE_PIXELS
            gradientIsDirty = true
            invalidateSelf()
        }
    }

    final func setGradientRadius(_ radius: Float) { gradientRadius = radius }
    final func getGradientRadius() -> Float { return gradientRadius }

    func setGradientCenter(_ x: Float, _ y: Float) {
        stCenterX = x
        stCenterY = y
        gradientIsDirty = true
        invalidateSelf()
    }

    var gradientCenterX: Float { return stCenterX }
    var gradientCenterY: Float { return stCenterY }

    func setUseLevel(_ useLevel: Bool) {
        stUseLevel = useLevel
        gradientIsDirty = true
        invalidateSelf()
    }

    var isUseLevel: Bool { return stUseLevel }

    func setDither(_ dither: Bool) {
        if dither != stDither {
            stDither = dither
            invalidateSelf()
        }
    }

    // MARK: Stroke

    func setStroke(_ width: Int, _ color: Int) {
        setStroke(width, color, 0, 0)
    }

    func setStroke(_ width: Int, _ colorStateList: AColorStateList?) {
        setStroke(width, colorStateList, 0, 0)
    }

    func setStroke(_ width: Int, _ color: Int, _ dashWidth: Float, _ dashGap: Float) {
        stStrokeWidth = width
        stStrokeColors = AColorStateList.valueOf(color)
        stStrokeDashWidth = dashWidth
        stStrokeDashGap = dashGap
        setStrokeInternal(width, color, dashWidth, dashGap)
    }

    func setStroke(_ width: Int, _ colorStateList: AColorStateList?, _ dashWidth: Float, _ dashGap: Float) {
        stStrokeWidth = width
        stStrokeColors = colorStateList
        stStrokeDashWidth = dashWidth
        stStrokeDashGap = dashGap
        let color: Int
        if let list = colorStateList {
            color = list.getColorForState(state, 0)
        } else {
            color = AColor.TRANSPARENT
        }
        setStrokeInternal(width, color, dashWidth, dashGap)
    }

    private func setStrokeInternal(_ width: Int, _ color: Int, _ dashWidth: Float, _ dashGap: Float) {
        let p: APaint
        if let existing = strokePaint {
            p = existing
        } else {
            p = APaint(APaint.ANTI_ALIAS_FLAG)
            p.style = .STROKE
            strokePaint = p
        }
        p.strokeWidth = Float(width)
        p.color = color
        var e: ADashPathEffect?
        if dashWidth > 0 {
            e = ADashPathEffect([dashWidth, dashGap], 0)
        }
        p.pathEffect = e
        gradientIsDirty = true
        invalidateSelf()
    }

    // MARK: Drawable overrides

    override var alpha: Int {
        get { return gdAlpha }
        set {
            if newValue != gdAlpha {
                gdAlpha = newValue
                invalidateSelf()
            }
        }
    }

    override func setTintList(_ tint: AColorStateList?) {
        stTint = tint
        invalidateSelf()
    }

    override var isStateful: Bool {
        return super.isStateful
            || (stSolidColors?.isStateful ?? false)
            || (stStrokeColors?.isStateful ?? false)
            || (stTint?.isStateful ?? false)
    }

    override func onStateChange(_ stateSet: [Int]) -> Bool {
        var invalidate = false
        if let solid = stSolidColors {
            let newColor = solid.getColorForState(stateSet, 0)
            if fillPaint.color != newColor {
                fillPaint.color = newColor
                invalidate = true
            }
        }
        if let sp = strokePaint, let strokeColors = stStrokeColors {
            let newColor = strokeColors.getColorForState(stateSet, 0)
            if sp.color != newColor {
                sp.color = newColor
                invalidate = true
            }
        }
        if stTint != nil {
            invalidate = true
        }
        if invalidate {
            invalidateSelf()
            return true
        }
        return false
    }

    override func onBoundsChange(_ bounds: ARect) {
        super.onBoundsChange(bounds)
        ringPath = nil
        pathIsDirty = true
        gradientIsDirty = true
    }

    override func onLevelChange(_ level: Int) -> Bool {
        _ = super.onLevelChange(level)
        gradientIsDirty = true
        pathIsDirty = true
        invalidateSelf()
        return true
    }

    // MARK: Drawing (GradientDrawable.draw)

    private func modulateAlpha(_ alpha: Int) -> Int {
        let scale = gdAlpha + (gdAlpha >> 7)
        return (alpha * scale) >> 8
    }

    /// GradientDrawable.draw (Android 12). The tint is the SRC_IN colour filter of the tint colour for the current
    /// state (mBlendModeColorFilter), applied like Android: by the layer paint when a layer is needed, otherwise by
    /// the fill and stroke paints (and a tinted drawable without solid colours fills with `mAlpha << 24`, so the
    /// whole shape shows the tint).
    override func draw(_ canvas: ACanvas) {
        if !ensureValidRect() {
            // nothing to draw
            return
        }

        // remember the alpha values, in case we temporarily overwrite them when we modulate them with mAlpha
        let prevFillAlpha = fillPaint.alpha
        let prevStrokeAlpha = strokePaint?.alpha ?? 0
        // compute the modulate alpha values
        let currFillAlpha = modulateAlpha(prevFillAlpha)
        let currStrokeAlpha = modulateAlpha(prevStrokeAlpha)

        let haveStroke = currStrokeAlpha > 0 && strokePaint != nil && strokePaint!.strokeWidth > 0
        let haveFill = currFillAlpha > 0
        let colorFilter = kgTintFilter(stTint)

        // We need a layer iff we're drawing both a fill and stroke, and the stroke is non-opaque, and our shape
        // type actually supports fill+stroke.
        let useLayer = haveStroke && haveFill && stShape != AGradientDrawable.LINE && currStrokeAlpha < 255
            && (gdAlpha < 255 || colorFilter != nil)

        if useLayer {
            let lp = layerPaint ?? APaint()
            layerPaint = lp
            lp.isDither = stDither
            lp.alpha = gdAlpha
            lp.kgColorFilter = colorFilter
            let rad = strokePaint!.strokeWidth
            canvas.saveLayer(gdRect.left - rad, gdRect.top - rad, gdRect.right + rad, gdRect.bottom + rad, lp)
            // don't perform the filter in our individual paints since the layer will do it for us
            fillPaint.kgColorFilter = nil
            strokePaint!.kgColorFilter = nil
        } else {
            // if we're not using a layer, apply the dither/filter to our individual paints
            fillPaint.alpha = currFillAlpha
            fillPaint.isDither = stDither
            fillPaint.kgColorFilter = colorFilter
            if colorFilter != nil && stSolidColors == nil {
                fillPaint.color = Int(Int32(truncatingIfNeeded: gdAlpha) &<< 24)
            }
            if haveStroke {
                strokePaint!.alpha = currStrokeAlpha
                strokePaint!.isDither = stDither
                strokePaint!.kgColorFilter = colorFilter
            }
        }

        switch stShape {
        case AGradientDrawable.RECTANGLE:
            if stRadiusArray != nil {
                buildPathIfDirty()
                canvas.drawPath(gdPath, fillPaint)
                if haveStroke {
                    canvas.drawPath(gdPath, strokePaint!)
                }
            } else if stRadius > 0 {
                // since the caller is only giving us 1 value, we will force it to be square if the rect is too small
                // in one dimension to show it.
                let rad = min(stRadius, min(gdRect.width(), gdRect.height()) * 0.5)
                canvas.drawRoundRect(gdRect, rad, rad, fillPaint)
                if haveStroke {
                    canvas.drawRoundRect(gdRect, rad, rad, strokePaint!)
                }
            } else {
                if fillPaint.color != 0 || colorFilter != nil || fillPaint.shader != nil {
                    canvas.drawRect(gdRect, fillPaint)
                }
                if haveStroke {
                    canvas.drawRect(gdRect, strokePaint!)
                }
            }
        case AGradientDrawable.OVAL:
            canvas.drawOval(gdRect, fillPaint)
            if haveStroke {
                canvas.drawOval(gdRect, strokePaint!)
            }
        case AGradientDrawable.LINE:
            let r = gdRect
            let y = r.centerY()
            if haveStroke {
                canvas.drawLine(r.left, y, r.right, y, strokePaint!)
            }
        case AGradientDrawable.RING:
            let path = buildRing()
            canvas.drawPath(path, fillPaint)
            if haveStroke {
                canvas.drawPath(path, strokePaint!)
            }
        default:
            break
        }

        if useLayer {
            canvas.restore()
        } else {
            fillPaint.alpha = prevFillAlpha
            if haveStroke {
                strokePaint!.alpha = prevStrokeAlpha
            }
        }
    }

    private func buildPathIfDirty() {
        if pathIsDirty {
            _ = ensureValidRect()
            gdPath.reset()
            gdPath.addRoundRect(gdRect, stRadiusArray!, .CW)
            pathIsDirty = false
        }
    }

    /// GradientDrawable.buildRing (inner radius / thickness from the ratios unless set; level sweep).
    private func buildRing() -> APath {
        if let rp = ringPath, !stUseLevelForShape || !pathIsDirty {
            return rp
        }
        pathIsDirty = false
        let sweep: Float = stUseLevelForShape ? (360.0 * Float(level) / 10000.0) : 360

        var bounds = ARectF(gdRect)
        let x = bounds.width() / 2.0
        let y = bounds.height() / 2.0
        let thickness: Float = stThickness != -1 ? Float(stThickness) : bounds.width() / stThicknessRatio
        // inner radius
        let radius: Float = stInnerRadius != -1 ? Float(stInnerRadius) : bounds.width() / stInnerRadiusRatio

        let innerBounds = ARectF(bounds)
        innerBounds.inset(x - radius, y - radius)

        bounds = ARectF(innerBounds)
        bounds.inset(-thickness, -thickness)

        let path = ringPath ?? APath()
        path.reset()
        ringPath = path
        // arcTo treats the sweep angle mod 360, so check for that, since we think 360 means draw the entire oval
        if sweep < 360 && sweep > -360 {
            path.fillType = .EVEN_ODD
            // inner top
            path.moveTo(x + radius, y)
            // outer top
            path.lineTo(x + radius + thickness, y)
            // outer arc
            path.arcTo(bounds, 0.0, sweep, false)
            // inner arc
            path.arcTo(innerBounds, sweep, -sweep, false)
            path.close()
        } else {
            // add the entire ovals
            path.addOval(bounds, .CW)
            path.addOval(innerBounds, .CCW)
        }
        return path
    }

    /// GradientDrawable.ensureValidRect: the shape rect (bounds inset by half the stroke) and the gradient
    /// shader; false when the rect is empty.
    private func ensureValidRect() -> Bool {
        if gradientIsDirty {
            gradientIsDirty = false

            let bounds = self.bounds
            var inset: Float = 0
            if let sp = strokePaint {
                inset = sp.strokeWidth * 0.5
            }
            gdRect.set(Float(bounds.left) + inset, Float(bounds.top) + inset,
                       Float(bounds.right) - inset, Float(bounds.bottom) - inset)

            if let gradientColors = stGradientColors {
                let r = gdRect
                var x0: Float, x1: Float, y0: Float, y1: Float

                if stGradient == AGradientDrawable.LINEAR_GRADIENT {
                    let level: Float = stUseLevel ? Float(self.level) / 10000.0 : 1.0
                    switch stOrientation {
                    case .TOP_BOTTOM:
                        x0 = r.left; y0 = r.top
                        x1 = x0; y1 = level * r.bottom
                    case .TR_BL:
                        x0 = r.right; y0 = r.top
                        x1 = level * r.left; y1 = level * r.bottom
                    case .RIGHT_LEFT:
                        x0 = r.right; y0 = r.top
                        x1 = level * r.left; y1 = y0
                    case .BR_TL:
                        x0 = r.right; y0 = r.bottom
                        x1 = level * r.left; y1 = level * r.top
                    case .BOTTOM_TOP:
                        x0 = r.left; y0 = r.bottom
                        x1 = x0; y1 = level * r.top
                    case .BL_TR:
                        x0 = r.left; y0 = r.bottom
                        x1 = level * r.right; y1 = level * r.top
                    case .LEFT_RIGHT:
                        x0 = r.left; y0 = r.top
                        x1 = level * r.right; y1 = y0
                    case .TL_BR:
                        x0 = r.left; y0 = r.top
                        x1 = level * r.right; y1 = level * r.bottom
                    }
                    fillPaint.shader = ALinearGradient(x0, y0, x1, y1, gradientColors, stPositions, .CLAMP)
                } else if stGradient == AGradientDrawable.RADIAL_GRADIENT {
                    x0 = r.left + (r.right - r.left) * stCenterX
                    y0 = r.top + (r.bottom - r.top) * stCenterY

                    var radius = stGradientRadius
                    if stGradientRadiusType == AGradientDrawable.RADIUS_TYPE_FRACTION {
                        // Fall back to parent width or height if intrinsic size is not specified.
                        let width: Float = stWidth >= 0 ? Float(stWidth) : r.width()
                        let height: Float = stHeight >= 0 ? Float(stHeight) : r.height()
                        radius *= min(width, height)
                    } else if stGradientRadiusType == AGradientDrawable.RADIUS_TYPE_FRACTION_PARENT {
                        radius *= min(r.width(), r.height())
                    }
                    if stUseLevel {
                        radius *= Float(self.level) / 10000.0
                    }
                    computedGradientRadius = radius
                    if radius <= 0 {
                        // We can't have a shader with non-positive radius, so let's have a very, very small radius.
                        radius = 0.001
                    }
                    fillPaint.shader = ARadialGradient(x0, y0, radius, gradientColors, nil, .CLAMP)
                } else if stGradient == AGradientDrawable.SWEEP_GRADIENT {
                    // SweepGradient has no Core Graphics equivalent and the app never uses it: the first colour
                    // fills the shape (documented gap).
                    fillPaint.shader = nil
                    if stSolidColors == nil, let first = gradientColors.first {
                        fillPaint.color = first
                        return !gdRect.isEmpty()
                    }
                }

                // If we don't have a solid color, the alpha channel must be maxed out so that alpha modulation works
                // correctly.
                if stSolidColors == nil {
                    fillPaint.color = AColor.BLACK
                }
            }
        }
        return !gdRect.isEmpty()
    }
}

// MARK: - InsetDrawable

/// android.graphics.drawable.InsetDrawable: the wrapped drawable drawn in the bounds inset by px insets; the
/// insets are reported as padding (so a view taking it as background gets that padding, like Android).
final class AInsetDrawable: ADrawable {
    private(set) var drawable: ADrawable?
    private let insetLeft: Int
    private let insetTop: Int
    private let insetRight: Int
    private let insetBottom: Int

    convenience init(_ drawable: ADrawable?, _ inset: Int) {
        self.init(drawable, inset, inset, inset, inset)
    }

    init(_ drawable: ADrawable?, _ insetLeft: Int, _ insetTop: Int, _ insetRight: Int, _ insetBottom: Int) {
        self.drawable = drawable
        self.insetLeft = insetLeft
        self.insetTop = insetTop
        self.insetRight = insetRight
        self.insetBottom = insetBottom
        super.init()
    }

    func getDrawable() -> ADrawable? { return drawable }

    override func kgCallbackChanged() {
        drawable?.callbackView = callbackView
    }

    override func draw(_ canvas: ACanvas) {
        drawable?.draw(canvas)
    }

    override func onBoundsChange(_ bounds: ARect) {
        let r = ARect(bounds)
        r.left += insetLeft
        r.top += insetTop
        r.right -= insetRight
        r.bottom -= insetBottom
        drawable?.setBounds(r)
    }

    override func getPadding(_ padding: ARect) -> Bool {
        let pad = drawable?.getPadding(padding) ?? { padding.set(0, 0, 0, 0); return false }()
        padding.left += insetLeft
        padding.right += insetRight
        padding.top += insetTop
        padding.bottom += insetBottom
        return pad || (insetLeft | insetRight | insetTop | insetBottom) != 0
    }

    override var intrinsicWidth: Int {
        guard let d = drawable else { return -1 }
        let childWidth = d.intrinsicWidth
        if childWidth < 0 { return -1 }
        return childWidth + insetLeft + insetRight
    }

    override var intrinsicHeight: Int {
        guard let d = drawable else { return -1 }
        let childHeight = d.intrinsicHeight
        if childHeight < 0 { return -1 }
        return childHeight + insetTop + insetBottom
    }

    override var alpha: Int {
        get { return drawable?.alpha ?? 255 }
        set { drawable?.alpha = newValue }
    }

    override func setTintList(_ tint: AColorStateList?) {
        drawable?.setTintList(tint)
    }

    override var isStateful: Bool { return drawable?.isStateful ?? false }

    override func onStateChange(_ state: [Int]) -> Bool {
        if let d = drawable, d.isStateful {
            let changed = d.setState(state)
            if changed {
                onBoundsChange(bounds)
            }
            return changed
        }
        return false
    }

    override func onLevelChange(_ level: Int) -> Bool {
        let changed = drawable?.setLevel(level) ?? false
        if changed {
            onBoundsChange(bounds)
        }
        return changed
    }

    @discardableResult
    override func mutate() -> ADrawable {
        drawable?.mutate()
        return self
    }
}

// MARK: - VectorDrawable

/// android.graphics.drawable.VectorDrawable for the app's icons: filled paths in a viewport, scaled to the
/// bounds (x and y independently, like VectorDrawable), drawn anti-aliased; the drawable alpha applies to the
/// whole icon. Intrinsic size = getDimensionPixelSize of the dp size.
final class AVectorDrawable: ADrawable {
    struct PathSpec {
        let pathData: String
        let fillColor: Int
        var fillAlpha: Float = 1
        var fillType: APath.FillType = .WINDING
    }

    private let widthDp: Float
    private let heightDp: Float
    private let viewportWidth: Float
    private let viewportHeight: Float
    private let specs: [PathSpec]
    private lazy var paths: [APath] = specs.map { spec in
        let p = APathParser.createPathFromPathData(spec.pathData)
        p.fillType = spec.fillType
        return p
    }
    private let paint = APaint(APaint.ANTI_ALIAS_FLAG)
    private var rootAlpha: Float = 1
    private var tint: AColorStateList?

    init(widthDp: Float, heightDp: Float, viewportWidth: Float, viewportHeight: Float, paths: [PathSpec]) {
        self.widthDp = widthDp
        self.heightDp = heightDp
        self.viewportWidth = viewportWidth
        self.viewportHeight = viewportHeight
        self.specs = paths
        super.init()
    }

    override var intrinsicWidth: Int { return KitGraphics.dimensionPixelSize(dp: widthDp) }
    override var intrinsicHeight: Int { return KitGraphics.dimensionPixelSize(dp: heightDp) }

    /// VectorDrawable keeps the alpha as a float (alpha / 255f) and reports `(int) (alpha * 255)`.
    override var alpha: Int {
        get { return KitGraphics.javaInt(rootAlpha * 255) }
        set {
            let a = Float(newValue) / 255
            if a != rootAlpha {
                rootAlpha = a
                invalidateSelf()
            }
        }
    }

    override func setTintList(_ tint: AColorStateList?) {
        self.tint = tint
        invalidateSelf()
    }

    override var isStateful: Bool { return tint?.isStateful ?? false }

    /// VectorDrawable.onStateChange: true whenever a tint is set (its filter colour follows the state).
    override func onStateChange(_ state: [Int]) -> Bool {
        return tint != nil
    }

    /// VectorDrawable.draw (hwui VectorDrawable::Tree): the paths in the bounds (viewport scaled to them, x and y
    /// independently) and clipped to them like the cached bitmap hwui renders; that bitmap is drawn with the root
    /// alpha (`(U8CPU) (alpha * 255)`) and the tint's SRC_IN colour filter, i.e. a layer over the whole icon.
    override func draw(_ canvas: ACanvas) {
        let b = bounds
        if b.width() <= 0 || b.height() <= 0 {
            // Nothing to draw
            return
        }
        let alpha255 = min(255, max(0, KitGraphics.javaInt(rootAlpha * 255)))
        if alpha255 == 0 { return }
        let filter = kgTintFilter(tint)
        let save: Int
        if alpha255 < 255 || filter != nil {
            let layerPaint = APaint()
            layerPaint.alpha = alpha255
            layerPaint.kgColorFilter = filter
            save = canvas.saveLayer(ARectF(b), layerPaint)
        } else {
            save = canvas.save()
        }
        canvas.clipRect(b)
        canvas.translate(Float(b.left), Float(b.top))
        canvas.scale(Float(b.width()) / viewportWidth, Float(b.height()) / viewportHeight)
        for (i, spec) in specs.enumerated() {
            // hwui FullPath: applyAlpha(fillColor, fillAlpha) = SkColorSetA(color, alpha(color) * fillAlpha).
            let a = KitGraphics.javaInt(Float(AColor.alpha(spec.fillColor)) * spec.fillAlpha)
            paint.color = AColor.argb(min(255, max(0, a)), AColor.red(spec.fillColor), AColor.green(spec.fillColor),
                                      AColor.blue(spec.fillColor))
            canvas.drawPath(paths[i], paint)
        }
        canvas.restoreToCount(save)
    }
}

// MARK: - ContextCompat.getDrawable

/// `ContextCompat.getDrawable(context, R.drawable.x)`: a new drawable for the resource (an ABitmapDrawable for an
/// image, the Swift port of an XML drawable), nil for an unknown name.
func ContextCompat_getDrawable(_ res: ADrawableRes) -> ADrawable? {
    if let make = KGXmlDrawables.factories[res] {
        return make()
    }
    if AResources.drawables[res] != nil {
        return ABitmapDrawable(res)
    }
    return nil
}

/// res/drawable/*.xml of the Android app, ported to Swift (inflation order and Resources rounding kept:
/// <corners android:radius> and <stroke android:width> are getDimensionPixelSize, colours ARGB).
enum KGXmlDrawables {
    static let factories: [String: () -> ADrawable] = [
        // <shape rectangle><solid #DDF2FFFC/><corners 14dp/><stroke 2dp #6632BFA8/></shape>
        "triple_shot_answer_idle": { shape(0xDDF2FFFC, 14, 2, 0x6632BFA8) },
        // <shape rectangle><solid #FFFDE7A6/><corners 14dp/><stroke 3dp #FFFFA000/></shape>
        "triple_shot_answer_selected": { shape(0xFFFDE7A6, 14, 3, 0xFFFFA000) },
        // <shape rectangle><solid #E6FFFDF5/><corners 11dp/><stroke 1dp #B5233C4A/></shape>
        "triple_shot_feedback_panel": { shape(0xE6FFFDF5, 11, 1, 0xB5233C4A) },
        // <shape rectangle><solid #EFFFFFFF/><corners 20dp/><stroke 2dp #3232BFA8/></shape>
        "triple_shot_panel": { shape(0xEFFFFFFF, 20, 2, 0x3232BFA8) },
        // <vector 36dp x 36dp, viewport 28 x 28>: a #D1EDFF disc with a #174575 glyph.
        "triple_help": { icon("M12,20 L16,20 L16,24 L12,24 Z M8,10 C8,2 22,2 22,10 C22,14 16,14 16,18 L12,18 C12,12 18,12 18,10 C18,6 12,6 12,10 Z") },
        "triple_pause": { icon("M8,6 L11,6 L11,22 L8,22 Z M17,6 L20,6 L20,22 L17,22 Z") },
        "triple_play": { icon("M10,6 L22,14 L10,22 Z") },
    ]

    /// A `<shape android:shape="rectangle">` with solid, corners and stroke children (in that XML order).
    static func shape(_ solid: UInt32, _ radiusDp: Float, _ strokeWidthDp: Float, _ strokeColor: UInt32) -> AGradientDrawable {
        let d = AGradientDrawable()
        d.shape = AGradientDrawable.RECTANGLE
        d.setColor(AColorStateList.valueOf(argbInt(solid)))
        d.cornerRadius = Float(KitGraphics.dimensionPixelSize(dp: radiusDp))
        d.setStroke(KitGraphics.dimensionPixelSize(dp: strokeWidthDp), AColorStateList.valueOf(argbInt(strokeColor)))
        return d
    }

    /// The control icons: `M14,0 A14,14 0,1 0,14 28 A14,14 0,1 0,14 0` (#D1EDFF) under the glyph (#174575).
    static func icon(_ glyph: String) -> AVectorDrawable {
        return AVectorDrawable(widthDp: 36, heightDp: 36, viewportWidth: 28, viewportHeight: 28, paths: [
            AVectorDrawable.PathSpec(pathData: "M14,0 A14,14 0,1 0,14 28 A14,14 0,1 0,14 0", fillColor: argbInt(0xFFD1EDFF)),
            AVectorDrawable.PathSpec(pathData: glyph, fillColor: argbInt(0xFF174575)),
        ])
    }
}
