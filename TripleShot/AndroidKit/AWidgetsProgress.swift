import CoreGraphics
import UIKit

// AndroidKit widgets: android.widget.ProgressBar (Android 15 ProgressBar.java) with the framework styles the app
// theme gives it (Theme.Material.Light through AppCompat):
// - ?android:attr/progressBarStyleHorizontal = Widget.Material.Light.ProgressBar.Horizontal: min/max width 48 dp
//   (inherited from Widget.ProgressBar), min/max height 16 dp, mirrorForRtl, not indeterminate-only, and
//   progress_horizontal_material: a layer-list of three 4 dp rectangles (corner 0) with gravity
//   center_vertical|fill_horizontal: background = white_disabled_material (#4DFFFFFF) tinted SRC_IN with
//   ?colorProgressBackgroundNormal (= colorControlNormal), secondaryProgress = ScaleDrawable(100 %) of
//   white_disabled_material tinted colorControlActivated, progress = ScaleDrawable(100 %) of white tinted
//   colorControlActivated. progressTint / progressBackgroundTint / secondaryProgressTint replace the shape's tint
//   (so a background tint colour shows at the 30 % alpha of white_disabled_material, like Android);
// - ?android:attr/progressBarStyle = Widget.Material.Light.ProgressBar: 48 dp, indeterminate only, the
//   AnimatedVectorDrawable progress_indeterminate_anim_medium_material: a circle of radius 18 stroked 4 wide with
//   square caps in a 48 viewport, tinted ?colorControlActivated, trimPathStart / trimPathEnd 0 -> 0.75 over 1333 ms
//   with trim_start_interpolator / trim_end_interpolator, trimPathOffset 0 -> 0.25 linear over 1333 ms, and the
//   group rotation 0 -> 720 degrees linear over 4444 ms, all repeating; Small (16 dp) and Large (76 dp) likewise.
// Levels follow doRefreshProgress (level = (int) (scale * 10000)) and ScaleDrawable.onBoundsChange.

/// android.widget.ProgressBar.
class AProgressBar: AView {
    /// The framework style the bar is created with.
    enum Style { case DEFAULT, SMALL, LARGE, HORIZONTAL }

    static let MAX_LEVEL = 10000
    private static let PROGRESS_ANIM_DURATION: Int64 = 80

    let progressStyle: Style

    // initProgressBar() defaults.
    private var aw_min = 0
    private var aw_max = 100
    private var aw_progress = 0
    private var aw_secondaryProgress = 0
    private var aw_minInitialized = false
    private var aw_maxInitialized = false
    private var aw_indeterminate = false
    private var aw_onlyIndeterminate = false
    private var aw_minWidth = 24
    private var aw_maxWidth = 48
    private var aw_minHeight = 24
    private var aw_maxHeight = 48
    private var aw_mirrorForRtl = false
    private var aw_noInvalidate = false
    private var aw_aggregatedIsVisible = false
    private var aw_attached = false
    private var aw_visualProgress: Float = 0
    private var aw_lastProgressAnimator: AValueAnimator?

    // ProgressTintInfo.
    private var aw_progressTintList: AColorStateList?
    private var aw_hasProgressTint = false
    private var aw_progressBackgroundTintList: AColorStateList?
    private var aw_hasProgressBackgroundTint = false
    private var aw_secondaryProgressTintList: AColorStateList?
    private var aw_hasSecondaryProgressTint = false
    private var aw_indeterminateTintList: AColorStateList?
    private var aw_hasIndeterminateTint = false

    // progress_horizontal_material: the tint of each layer's shape and the level of the two ScaleDrawables.
    private var aw_backgroundShapeTint: AColorStateList?
    private var aw_secondaryShapeTint: AColorStateList?
    private var aw_progressShapeTint: AColorStateList?
    private var aw_secondaryLevel = 0
    private var aw_progressLevel = 0
    /// The wrapped shapes keep their last bounds when a ScaleDrawable computes a zero width (`w > 0 && h > 0`).
    private var aw_secondaryShapeRight = -1
    private var aw_progressShapeRight = -1
    private var aw_drawableWidth = 0
    private var aw_drawableHeight = 0

    // The indeterminate AnimatedVectorDrawable.
    private var aw_spinnerTint: AColorStateList?
    private let aw_spinnerBounds = ARect()
    private var aw_avdRunning = false
    private var aw_avdStartTime: Int64 = 0
    private var aw_shouldStartAnimationDrawable = false
    private let aw_paint = APaint(APaint.ANTI_ALIAS_FLAG)

    /// `ProgressBar(context)`: ?android:attr/progressBarStyle.
    override convenience init() {
        self.init(style: .DEFAULT)
    }

    /// `ProgressBar(context, null, android.R.attr.progressBarStyleHorizontal)` and the other framework styles.
    init(style: Style) {
        progressStyle = style
        super.init()
        aw_construct()
    }

    /// `ProgressBar(context, attrs, defStyleAttr)` with the framework style attributes
    /// (android.R.attr.progressBarStyleHorizontal 16842872, progressBarStyleSmall 16842873, progressBarStyleLarge
    /// 16842874; anything else is progressBarStyle).
    convenience init(_ attrs: Any?, _ defStyleAttr: Int) {
        switch defStyleAttr {
        case 16842872: self.init(style: .HORIZONTAL)
        case 16842873: self.init(style: .SMALL)
        case 16842874: self.init(style: .LARGE)
        default: self.init(style: .DEFAULT)
        }
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    /// The ProgressBar constructor after initProgressBar(): the style's drawables, sizes, min / max / progress, the
    /// indeterminate mode and mirrorForRtl.
    private func aw_construct() {
        aw_noInvalidate = true
        // progressDrawable (horizontal only): setProgressDrawable keeps mMaxHeight >= the drawable's minimum height.
        if progressStyle == .HORIZONTAL {
            aw_backgroundShapeTint = AWMaterialColors.colorControlNormalList
            aw_secondaryShapeTint = AColorStateList.valueOf(AWMaterialColors.colorControlActivated)
            aw_progressShapeTint = AColorStateList.valueOf(AWMaterialColors.colorControlActivated)
            aw_drawableWidth = -1
            aw_drawableHeight = aw_dpx(4)
            if aw_maxHeight < aw_drawableHeight {
                aw_maxHeight = aw_drawableHeight
            }
            aw_updateDrawableBounds(width, height)
            aw_doRefreshProgress(true, aw_progress, false)
            aw_doRefreshProgress(false, aw_secondaryProgress, false)
        }
        switch progressStyle {
        case .HORIZONTAL:
            aw_minWidth = aw_dpx(48)
            aw_maxWidth = aw_dpx(48)
            aw_minHeight = aw_dpx(16)
            aw_maxHeight = aw_dpx(16)
        case .DEFAULT:
            aw_setSquareSize(aw_dpx(48))
        case .SMALL:
            aw_setSquareSize(aw_dpx(16))
        case .LARGE:
            aw_setSquareSize(aw_dpx(76))
        }
        setMin(aw_min)
        setMax(aw_max)
        setProgress(aw_progress)
        setSecondaryProgress(aw_secondaryProgress)
        // indeterminateDrawable: every style has one (the horizontal one is not drawn, see aw_drawTrack).
        aw_spinnerTint = AColorStateList.valueOf(AWMaterialColors.colorControlActivated)
        aw_onlyIndeterminate = progressStyle != .HORIZONTAL
        aw_noInvalidate = false
        setIndeterminate(aw_onlyIndeterminate || aw_indeterminate)
        aw_mirrorForRtl = progressStyle == .HORIZONTAL
        // If not explicitly specified this view is important for accessibility.
        if importantForAccessibility == AView.IMPORTANT_FOR_ACCESSIBILITY_AUTO {
            importantForAccessibility = AView.IMPORTANT_FOR_ACCESSIBILITY_YES
        }
        isAccessibilityElement = true
        aw_updateAccessibilityValue()
    }

    private func aw_setSquareSize(_ size: Int) {
        aw_drawableWidth = size
        aw_drawableHeight = size
        aw_minWidth = size
        aw_maxWidth = size
        aw_minHeight = size
        aw_maxHeight = size
    }

    /// Applies XML attributes of a <ProgressBar> (android:max, android:progress, android:progressTint,
    /// android:progressBackgroundTint), in the constructor's order.
    func applyXmlAttributes(max: Int? = nil, progress: Int? = nil, progressTint: AColorStateList? = nil,
                            progressBackgroundTint: AColorStateList? = nil) {
        if let m = max { setMax(m) }
        if let p = progress { setProgress(p) }
        if let t = progressTint { setProgressTintList(t) }
        if let t = progressBackgroundTint { setProgressBackgroundTintList(t) }
    }

    // MARK: Sizes

    func setMinWidth(_ minWidth: Int) { aw_minWidth = minWidth; requestLayout() }
    func getMinWidth() -> Int { return aw_minWidth }
    func setMaxWidth(_ maxWidth: Int) { aw_maxWidth = maxWidth; requestLayout() }
    func getMaxWidth() -> Int { return aw_maxWidth }
    func setMinHeight(_ minHeight: Int) { aw_minHeight = minHeight; requestLayout() }
    func getMinHeight() -> Int { return aw_minHeight }
    func setMaxHeight(_ maxHeight: Int) { aw_maxHeight = maxHeight; requestLayout() }
    func getMaxHeight() -> Int { return aw_maxHeight }

    var minWidth: Int {
        get { return aw_minWidth }
        set { setMinWidth(newValue) }
    }

    var maxWidth: Int {
        get { return aw_maxWidth }
        set { setMaxWidth(newValue) }
    }

    var minHeight: Int {
        get { return aw_minHeight }
        set { setMinHeight(newValue) }
    }

    var maxHeight: Int {
        get { return aw_maxHeight }
        set { setMaxHeight(newValue) }
    }

    var mirrorForRtl: Bool { return aw_mirrorForRtl }
    func getMirrorForRtl() -> Bool { return aw_mirrorForRtl }

    // MARK: Indeterminate

    var isIndeterminate: Bool {
        get { return aw_indeterminate }
        set { setIndeterminate(newValue) }
    }

    /// ProgressBar.setIndeterminate: an indeterminate-only bar stays indeterminate.
    func setIndeterminate(_ indeterminate: Bool) {
        if (!aw_onlyIndeterminate || !aw_indeterminate) && indeterminate != aw_indeterminate {
            aw_indeterminate = indeterminate
            if indeterminate {
                aw_startAnimation()
            } else {
                aw_stopAnimation()
            }
            aw_updateAccessibilityValue()
        }
    }

    /// ProgressBar.isAnimating.
    var isAnimating: Bool {
        return isIndeterminate && windowVisibility == AView.VISIBLE && isShown
    }

    // MARK: Values

    var min: Int {
        get { return aw_min }
        set { setMin(newValue) }
    }

    func getMin() -> Int { return aw_min }

    /// ProgressBar.setMin.
    func setMin(_ min0: Int) {
        var min = min0
        if aw_maxInitialized {
            if min > aw_max { min = aw_max }
        }
        aw_minInitialized = true
        if aw_maxInitialized && min != aw_min {
            aw_min = min
            aw_postInvalidate()
            if aw_progress < min { aw_progress = min }
            aw_refreshProgress(true, aw_progress, false)
        } else {
            aw_min = min
        }
    }

    var max: Int {
        get { return aw_max }
        set { setMax(newValue) }
    }

    func getMax() -> Int { return aw_max }

    /// ProgressBar.setMax (the progress is clamped to the new maximum).
    func setMax(_ max0: Int) {
        var max = max0
        if aw_minInitialized {
            if max < aw_min { max = aw_min }
        }
        aw_maxInitialized = true
        if aw_minInitialized && max != aw_max {
            aw_max = max
            aw_postInvalidate()
            if aw_progress > max { aw_progress = max }
            aw_refreshProgress(true, aw_progress, false)
        } else {
            aw_max = max
        }
    }

    /// ProgressBar.getProgress (0 when indeterminate).
    var progress: Int {
        get { return aw_indeterminate ? 0 : aw_progress }
        set { setProgress(newValue) }
    }

    func getProgress() -> Int { return progress }

    func setProgress(_ progress: Int) {
        _ = aw_setProgressInternal(progress, false)
    }

    func setProgress(_ progress: Int, _ animate: Bool) {
        _ = aw_setProgressInternal(progress, animate)
    }

    /// ProgressBar.setProgressInternal: ignored when indeterminate, constrained to [min, max].
    private func aw_setProgressInternal(_ p: Int, _ animate: Bool) -> Bool {
        if aw_indeterminate { return false }
        let progress = p < aw_min ? aw_min : (p > aw_max ? aw_max : p)
        if progress == aw_progress { return false }
        aw_progress = progress
        aw_refreshProgress(true, aw_progress, animate)
        return true
    }

    func incrementProgressBy(_ diff: Int) {
        setProgress(aw_progress + diff)
    }

    var secondaryProgress: Int {
        get { return aw_indeterminate ? 0 : aw_secondaryProgress }
        set { setSecondaryProgress(newValue) }
    }

    func getSecondaryProgress() -> Int { return secondaryProgress }

    func setSecondaryProgress(_ secondaryProgress0: Int) {
        if aw_indeterminate { return }
        var secondaryProgress = secondaryProgress0
        if secondaryProgress < aw_min { secondaryProgress = aw_min }
        if secondaryProgress > aw_max { secondaryProgress = aw_max }
        if secondaryProgress != aw_secondaryProgress {
            aw_secondaryProgress = secondaryProgress
            aw_refreshProgress(false, aw_secondaryProgress, false)
        }
    }

    func incrementSecondaryProgressBy(_ diff: Int) {
        setSecondaryProgress(aw_secondaryProgress + diff)
    }

    /// ProgressBar.refreshProgress on the UI thread.
    private func aw_refreshProgress(_ primary: Bool, _ progress: Int, _ animate: Bool) {
        aw_doRefreshProgress(primary, progress, animate)
        if primary {
            aw_updateAccessibilityValue()
        }
    }

    /// ProgressBar.doRefreshProgress: the layer level is (int) (scale * MAX_LEVEL); an animated primary change
    /// runs VISUAL_PROGRESS over 80 ms with a DecelerateInterpolator.
    private func aw_doRefreshProgress(_ primary: Bool, _ progress: Int, _ animate: Bool) {
        let range = aw_max - aw_min
        let scale: Float = range > 0 ? Float(progress - aw_min) / Float(range) : 0
        if primary && animate {
            let animator = AValueAnimator.ofFloat(aw_visualProgress, scale)
            animator.setDuration(AProgressBar.PROGRESS_ANIM_DURATION)
            animator.setInterpolator(ADecelerateInterpolator())
            animator.addUpdateListener { [weak self] a in
                guard let self = self else { return }
                let value = a.animatedValueFloat
                self.aw_setVisualProgress(true, value)
                self.aw_visualProgress = value
            }
            aw_lastProgressAnimator?.cancel()
            animator.start()
            aw_lastProgressAnimator = animator
        } else {
            if primary, let last = aw_lastProgressAnimator {
                last.cancel()
                aw_lastProgressAnimator = nil
            }
            aw_setVisualProgress(primary, scale)
        }
    }

    /// ProgressBar.setVisualProgress: the level of the progress / secondaryProgress layer.
    private func aw_setVisualProgress(_ primary: Bool, _ progress: Float) {
        aw_visualProgress = progress
        guard progressStyle == .HORIZONTAL else {
            // The indeterminate drawable has no such layer: the level goes to the current drawable.
            invalidate()
            return
        }
        let level = AWMath.javaInt(progress * Float(AProgressBar.MAX_LEVEL))
        if primary {
            if aw_progressLevel != level {
                aw_progressLevel = level
                aw_scaleLayerBoundsChanged(primary: true)
                invalidate()
            }
        } else if aw_secondaryLevel != level {
            aw_secondaryLevel = level
            aw_scaleLayerBoundsChanged(primary: false)
            invalidate()
        }
    }

    private func aw_postInvalidate() {
        if !aw_noInvalidate {
            postInvalidate()
        }
    }

    private func aw_updateAccessibilityValue() {
        if aw_indeterminate {
            accessibilityValue = nil
            accessibilityTraits = []
            return
        }
        // formatStateDescription: NumberFormat.getPercentInstance(locale).format(getPercent(progress)).
        let range = Float(aw_max) - Float(aw_min)
        var percent: Float = 0
        if range > 0 {
            percent = Swift.max(0, Swift.min(1, (Float(aw_progress) - Float(aw_min)) / range))
        }
        let f = NumberFormatter()
        f.numberStyle = .percent
        f.locale = Locale(identifier: ALocale.getDefault().toLanguageTag())
        accessibilityValue = f.string(from: NSNumber(value: percent))
        accessibilityTraits = .updatesFrequently
    }

    // MARK: Tints

    var progressTintList: AColorStateList? {
        get { return aw_progressTintList }
        set { setProgressTintList(newValue) }
    }

    func getProgressTintList() -> AColorStateList? { return aw_progressTintList }

    /// ProgressBar.setProgressTintList: replaces the tint of the progress layer's shape.
    func setProgressTintList(_ tint: AColorStateList?) {
        aw_progressTintList = tint
        aw_hasProgressTint = true
        if progressStyle == .HORIZONTAL {
            aw_progressShapeTint = tint
            invalidate()
        }
    }

    var progressBackgroundTintList: AColorStateList? {
        get { return aw_progressBackgroundTintList }
        set { setProgressBackgroundTintList(newValue) }
    }

    func getProgressBackgroundTintList() -> AColorStateList? { return aw_progressBackgroundTintList }

    /// ProgressBar.setProgressBackgroundTintList: replaces the tint of the background layer's shape.
    func setProgressBackgroundTintList(_ tint: AColorStateList?) {
        aw_progressBackgroundTintList = tint
        aw_hasProgressBackgroundTint = true
        if progressStyle == .HORIZONTAL {
            aw_backgroundShapeTint = tint
            invalidate()
        }
    }

    var secondaryProgressTintList: AColorStateList? {
        get { return aw_secondaryProgressTintList }
        set { setSecondaryProgressTintList(newValue) }
    }

    func getSecondaryProgressTintList() -> AColorStateList? { return aw_secondaryProgressTintList }

    func setSecondaryProgressTintList(_ tint: AColorStateList?) {
        aw_secondaryProgressTintList = tint
        aw_hasSecondaryProgressTint = true
        if progressStyle == .HORIZONTAL {
            aw_secondaryShapeTint = tint
            invalidate()
        }
    }

    var indeterminateTintList: AColorStateList? {
        get { return aw_indeterminateTintList }
        set { setIndeterminateTintList(newValue) }
    }

    func getIndeterminateTintList() -> AColorStateList? { return aw_indeterminateTintList }

    /// ProgressBar.setIndeterminateTintList: replaces the vector's ?colorControlActivated tint.
    func setIndeterminateTintList(_ tint: AColorStateList?) {
        aw_indeterminateTintList = tint
        aw_hasIndeterminateTint = true
        aw_spinnerTint = tint
        invalidate()
    }

    // MARK: Drawable state

    override func drawableStateChanged() {
        super.drawableStateChanged()
        // updateDrawableState: the tinted shapes and the vector follow the view's state.
        invalidate()
    }

    // MARK: Animation (startAnimation / stopAnimation with an Animatable indeterminate drawable)

    private func aw_startAnimation() {
        if visibility != AView.VISIBLE || windowVisibility != AView.VISIBLE {
            return
        }
        aw_shouldStartAnimationDrawable = true
        aw_postInvalidate()
    }

    private func aw_stopAnimation() {
        aw_avdRunning = false
        aw_shouldStartAnimationDrawable = false
        aw_postInvalidate()
    }

    override func onVisibilityAggregated(_ isVisible: Bool) {
        super.onVisibilityAggregated(isVisible)
        if isVisible != aw_aggregatedIsVisible {
            aw_aggregatedIsVisible = isVisible
            if aw_indeterminate {
                if isVisible {
                    aw_startAnimation()
                } else {
                    aw_stopAnimation()
                }
            }
        }
    }

    override func onAttachedToWindow() {
        super.onAttachedToWindow()
        if aw_indeterminate {
            aw_startAnimation()
        }
        aw_attached = true
    }

    override func onDetachedFromWindow() {
        if aw_indeterminate {
            aw_stopAnimation()
        }
        super.onDetachedFromWindow()
        aw_attached = false
    }

    // MARK: Measure and bounds

    /// The current drawable's intrinsic size: the layer-list (width -1, height 4 dp) or the vector.
    override func onMeasure(_ widthMeasureSpec: Int, _ heightMeasureSpec: Int) {
        var dw = 0
        var dh = 0
        if aw_indeterminate && progressStyle == .HORIZONTAL {
            // progress_indeterminate_horizontal_material: 360 x 10 dp.
            dw = Swift.max(aw_minWidth, Swift.min(aw_maxWidth, aw_dpx(360)))
            dh = Swift.max(aw_minHeight, Swift.min(aw_maxHeight, aw_dpx(10)))
        } else {
            dw = Swift.max(aw_minWidth, Swift.min(aw_maxWidth, aw_drawableWidth))
            dh = Swift.max(aw_minHeight, Swift.min(aw_maxHeight, aw_drawableHeight))
        }
        dw += mPaddingLeft + mPaddingRight
        dh += mPaddingTop + mPaddingBottom
        let measuredWidth = AView.resolveSizeAndState(dw, widthMeasureSpec, 0)
        let measuredHeight = AView.resolveSizeAndState(dh, heightMeasureSpec, 0)
        setMeasuredDimension(measuredWidth, measuredHeight)
    }

    /// ProgressBar.onSizeChanged (no super call, like Android).
    override func onSizeChanged(_ w: Int, _ h: Int, _ oldw: Int, _ oldh: Int) {
        aw_updateDrawableBounds(w, h)
    }

    // Layer bounds of the progress drawable (LayerDrawable bounds 0, 0, right, bottom).
    private var aw_layerWidth = 0
    private var aw_layerHeight = 0

    /// ProgressBar.updateDrawableBounds: the progress drawable fills the content box; the indeterminate-only
    /// vector keeps its aspect ratio, centred.
    private func aw_updateDrawableBounds(_ w0: Int, _ h0: Int) {
        let w = w0 - (mPaddingRight + mPaddingLeft)
        let h = h0 - (mPaddingTop + mPaddingBottom)
        var right = w
        var bottom = h
        var top = 0
        var left = 0
        if aw_onlyIndeterminate {
            let intrinsicWidth = aw_drawableWidth
            let intrinsicHeight = aw_drawableHeight
            let intrinsicAspect = Float(intrinsicWidth) / Float(intrinsicHeight)
            let boundAspect = Float(w) / Float(h)
            if intrinsicAspect != boundAspect {
                if boundAspect > intrinsicAspect {
                    let width = AWMath.javaInt(Float(h) * intrinsicAspect)
                    left = (w - width) / 2
                    right = left + width
                } else {
                    let height = AWMath.javaInt(Float(w) * (1 / intrinsicAspect))
                    top = (h - height) / 2
                    bottom = top + height
                }
            }
        }
        if isLayoutRtl && aw_mirrorForRtl {
            let tempLeft = left
            left = w - right
            right = w - tempLeft
        }
        aw_spinnerBounds.set(left, top, right, bottom)
        if progressStyle == .HORIZONTAL {
            aw_layerWidth = right
            aw_layerHeight = bottom
            aw_scaleLayerBoundsChanged(primary: true)
            aw_scaleLayerBoundsChanged(primary: false)
        }
    }

    /// ScaleDrawable.onBoundsChange for a layer: w -= (int) ((w - 0) * (MAX_LEVEL - level) * 1.0f / MAX_LEVEL);
    /// gravity LEFT; the shape's bounds change only when w > 0 and h > 0.
    private func aw_scaleLayerBoundsChanged(primary: Bool) {
        let level = primary ? aw_progressLevel : aw_secondaryLevel
        let layerW = aw_layerWidth
        let barH = aw_dpx(4)
        var w = layerW
        w -= AWMath.javaInt(Float(w * (AProgressBar.MAX_LEVEL - level)) * Float(1.0) / Float(AProgressBar.MAX_LEVEL))
        let h = barH
        if w > 0 && h > 0 {
            if primary { aw_progressShapeRight = w } else { aw_secondaryShapeRight = w }
        }
    }

    // MARK: Drawing (ProgressBar.onDraw / drawTrack)

    override func onDraw(_ canvas: ACanvas) {
        super.onDraw(canvas)
        aw_drawTrack(canvas)
    }

    private func aw_drawTrack(_ canvas: ACanvas) {
        // View.draw translates the content by (-mScrollX, -mScrollY).
        let scrollSave = canvas.save()
        canvas.translate(Float(-mScrollX), Float(-mScrollY))
        let saveCount = canvas.save()
        if isLayoutRtl && aw_mirrorForRtl {
            canvas.translate(Float(width - mPaddingRight), Float(mPaddingTop))
            canvas.scale(-1, 1)
        } else {
            canvas.translate(Float(mPaddingLeft), Float(mPaddingTop))
        }
        let state = drawableState
        if !aw_indeterminate {
            if progressStyle == .HORIZONTAL {
                aw_drawLayers(canvas, state)
            }
        } else if progressStyle != .HORIZONTAL {
            aw_drawSpinner(canvas, state)
        }
        // progress_indeterminate_horizontal_material (never used by the app) is not drawn.
        canvas.restoreToCount(saveCount)
        canvas.restoreToCount(scrollSave)
        if aw_indeterminate && aw_shouldStartAnimationDrawable {
            // drawTrack starts the Animatable after drawing its first frame.
            aw_shouldStartAnimationDrawable = false
            aw_avdRunning = true
            aw_avdStartTime = ASystemClock.uptimeMillis()
            postInvalidateOnAnimation()
        }
    }

    /// GradientDrawable.draw of a tinted rectangle: the solid colour through the tint's SRC_IN filter.
    private func aw_fillShape(_ canvas: ACanvas, _ left: Int, _ top: Int, _ right: Int, _ bottom: Int, _ solid: Int,
                              _ tint: AColorStateList?, _ state: [Int]) {
        aw_paint.reset()
        aw_paint.flags = APaint.ANTI_ALIAS_FLAG
        aw_paint.style = .FILL
        aw_paint.color = solid
        aw_paint.kgColorFilter = tint?.getColorForState(state, AColor.TRANSPARENT)
        // GradientDrawable skips the fill when the paint draws nothing (colour 0 without a filter).
        if aw_paint.kgColorFilter == nil && AColor.alpha(solid) == 0 { return }
        canvas.drawRect(Float(left), Float(top), Float(right), Float(bottom), aw_paint)
        aw_paint.kgColorFilter = nil
    }

    private func aw_drawLayers(_ canvas: ACanvas, _ state: [Int]) {
        let w = aw_layerWidth
        let h = aw_layerHeight
        let barH = aw_dpx(4)
        // Gravity.apply(CENTER_VERTICAL | FILL_HORIZONTAL, -1, 4 dp, (0, 0, w, h)).
        let top = (h - barH) / 2
        let bottom = top + barH
        let whiteDisabled = argbInt(0x4DFFFFFF)
        aw_fillShape(canvas, 0, top, w, bottom, whiteDisabled, aw_backgroundShapeTint, state)
        if aw_secondaryLevel != 0 && aw_secondaryShapeRight >= 0 {
            aw_fillShape(canvas, 0, top, aw_secondaryShapeRight, bottom, whiteDisabled, aw_secondaryShapeTint, state)
        }
        if aw_progressLevel != 0 && aw_progressShapeRight >= 0 {
            aw_fillShape(canvas, 0, top, aw_progressShapeRight, bottom, argbInt(0xFFFFFFFF), aw_progressShapeTint, state)
        }
    }

    // MARK: The Material indeterminate spinner

    /// y(x) of the cubic Bezier from (0, 0) to (1, 1) with control points (x1, y1) and (x2, y2).
    private static func aw_bezier(_ x: Double, _ x1: Double, _ y1: Double, _ x2: Double, _ y2: Double) -> Double {
        func cubic(_ t: Double, _ p1: Double, _ p2: Double) -> Double {
            let u = 1 - t
            return 3 * u * u * t * p1 + 3 * u * t * t * p2 + t * t * t
        }
        var lo = 0.0
        var hi = 1.0
        for _ in 0..<40 {
            let mid = (lo + hi) / 2
            if cubic(mid, x1, x2) < x { lo = mid } else { hi = mid }
        }
        return cubic((lo + hi) / 2, y1, y2)
    }

    /// trim_start_interpolator: L0.5,0 C0.7,0 0.6,1 1,1.
    static func trimStartInterpolation(_ f: Double) -> Double {
        if f <= 0.5 { return 0 }
        if f >= 1 { return 1 }
        return aw_bezier((f - 0.5) / 0.5, 0.4, 0, 0.2, 1)
    }

    /// trim_end_interpolator: C0.2,0 0.1,1 0.5,1 L1,1.
    static func trimEndInterpolation(_ f: Double) -> Double {
        if f >= 0.5 { return 1 }
        if f <= 0 { return 0 }
        return aw_bezier(f / 0.5, 0.4, 0, 0.2, 1)
    }

    private func aw_drawSpinner(_ canvas: ACanvas, _ state: [Int]) {
        if aw_avdRunning {
            // Keep the RenderThread-style animation going while it runs.
            postInvalidateOnAnimation()
        }
        guard aw_avdRunning else { return }    // before start() and after stop() the trims are equal: empty path
        let b = aw_spinnerBounds
        if b.width() <= 0 || b.height() <= 0 { return }
        let viewport: Float
        let radius: Float
        let stroke: Float
        switch progressStyle {
        case .SMALL:
            viewport = 16; radius = 5.9375; stroke = 2.125
        case .LARGE:
            viewport = 76; radius = 29; stroke = 6
        default:
            viewport = 48; radius = 18; stroke = 4
        }
        let elapsed = Double(Swift.max(0, ASystemClock.uptimeMillis() - aw_avdStartTime))
        let trimFraction = elapsed.truncatingRemainder(dividingBy: 1333) / 1333
        let trimStart = 0.75 * AProgressBar.trimStartInterpolation(trimFraction)
        let trimEnd = 0.75 * AProgressBar.trimEndInterpolation(trimFraction)
        let trimOffset = 0.25 * trimFraction
        let rotation = 720 * elapsed.truncatingRemainder(dividingBy: 4444) / 4444
        if trimStart == trimEnd { return }
        let start = (trimStart + trimOffset).truncatingRemainder(dividingBy: 1)
        let end = (trimEnd + trimOffset).truncatingRemainder(dividingBy: 1)
        var sweepFraction = end - start
        if start > end { sweepFraction = 1 - start + end }
        guard let color = aw_spinnerTint?.getColorForState(state, AColor.TRANSPARENT) else {
            // A null tint leaves the vector's white stroke.
            aw_strokeSpinner(canvas, b, viewport, radius, stroke, start, sweepFraction, rotation, AColor.WHITE)
            return
        }
        aw_strokeSpinner(canvas, b, viewport, radius, stroke, start, sweepFraction, rotation, color)
    }

    /// The path "M0,0 m0,-r a r,r 0 1,1 0,2r a r,r 0 1,1 0,-2r" (from the top, clockwise) trimmed to
    /// [start, start + sweep] of its length, rotated by the group, stroked with square caps and miter joins.
    private func aw_strokeSpinner(_ canvas: ACanvas, _ b: ARect, _ viewport: Float, _ radius: Float, _ stroke: Float,
                                  _ start: Double, _ sweep: Double, _ rotation: Double, _ color: Int) {
        let sx = Float(b.width()) / viewport
        let sy = Float(b.height()) / viewport
        let cx = Float(b.left) + viewport / 2 * sx
        let cy = Float(b.top) + viewport / 2 * sy
        aw_paint.reset()
        aw_paint.flags = APaint.ANTI_ALIAS_FLAG
        aw_paint.style = .STROKE
        aw_paint.strokeWidth = stroke * Swift.min(sx, sy)
        aw_paint.strokeCap = .SQUARE
        aw_paint.strokeJoin = .MITER
        aw_paint.color = color
        let oval = ARectF(cx - radius * sx, cy - radius * sy, cx + radius * sx, cy + radius * sy)
        let startAngle = (-90 + rotation + 360 * start).truncatingRemainder(dividingBy: 360)
        canvas.drawArc(oval, Float(startAngle), Float(360 * sweep), false, aw_paint)
    }
}
