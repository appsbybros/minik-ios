import CoreGraphics
import UIKit

// AndroidKit widgets: android.widget.ImageView, ported from the Android 15 source (ImageView.java):
// setImageResource / setImageDrawable / setImageBitmap -> updateDrawable, onMeasure (adjustViewBounds with
// maxWidth / maxHeight and resolveAdjustedSize), setFrame -> configureBounds (every ScaleType; FIT_START /
// FIT_CENTER / FIT_END through AMatrix.setRectToRect), onDraw (padding, cropToPadding, the draw matrix), the
// drawable state, image state and level, image alpha, the image tint, the SRC_ATOP colour filter of
// setColorFilter(int), and getBaseline. The drawable draws itself into the px canvas (ADrawable.draw).

/// android.widget.ImageView.
class AImageView: AView {
    /// ImageView.ScaleType (in nativeInt order).
    enum ScaleType: Int {
        case MATRIX = 0, FIT_XY = 1, FIT_START = 2, FIT_CENTER = 3, FIT_END = 4, CENTER = 5, CENTER_CROP = 6,
             CENTER_INSIDE = 7
    }

    private var aw_resource: ADrawableRes?
    private var aw_drawable: ADrawable?
    private var aw_haveFrame = false
    private var aw_adjustViewBounds = false
    private var aw_maxWidth = Int(Int32.max)
    private var aw_maxHeight = Int(Int32.max)
    /// setColorFilter(int): PorterDuffColorFilter(color, SRC_ATOP); nil after clearColorFilter().
    private var aw_colorFilter: Int?
    private var aw_alpha = 255
    private var aw_hasAlpha = false
    private var aw_drawableTintList: AColorStateList?
    private var aw_hasDrawableTint = false
    private var aw_state: [Int]?
    private var aw_mergeState = false
    private var aw_hasLevelSet = false
    private var aw_level = 0
    // ImageView.mDrawableWidth / mDrawableHeight start at 0 (Java int fields).
    private var aw_drawableWidth = 0
    private var aw_drawableHeight = 0
    private let aw_matrix = AMatrix()
    private var aw_drawMatrix: AMatrix?
    private let aw_tempSrc = ARectF()
    private let aw_tempDst = ARectF()
    private var aw_cropToPadding = false
    private var aw_baseline = -1
    private var aw_baselineAlignBottom = false
    private var aw_scaleType: ScaleType = .FIT_CENTER

    override init() {
        super.init()
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    // MARK: Drawable callback

    override func verifyDrawable(_ who: ADrawable) -> Bool {
        return aw_drawable === who || super.verifyDrawable(who)
    }

    /// ImageView.invalidateDrawable: refreshes the cached intrinsic size (and the matrix) of its own drawable.
    override func invalidateDrawable(_ drawable: ADrawable) {
        if drawable === aw_drawable {
            let w = drawable.intrinsicWidth
            let h = drawable.intrinsicHeight
            if w != aw_drawableWidth || h != aw_drawableHeight {
                aw_drawableWidth = w
                aw_drawableHeight = h
                aw_configureBounds()
            }
            invalidate()
        } else {
            super.invalidateDrawable(drawable)
        }
    }

    // MARK: Image content

    /// ImageView.getDrawable().
    var drawable: ADrawable? { return aw_drawable }
    func getDrawable() -> ADrawable? { return aw_drawable }

    /// ImageView.setImageResource: always (re)loads the resource, even for the same name.
    func setImageResource(_ resId: ADrawableRes) {
        let oldWidth = aw_drawableWidth
        let oldHeight = aw_drawableHeight
        aw_updateDrawable(nil)
        aw_resource = resId
        aw_resolveUri()
        if oldWidth != aw_drawableWidth || oldHeight != aw_drawableHeight {
            requestLayout()
        }
        invalidate()
    }

    /// ImageView.setImageDrawable: no-op for the drawable already shown.
    func setImageDrawable(_ drawable: ADrawable?) {
        if aw_drawable !== drawable {
            aw_resource = nil
            let oldWidth = aw_drawableWidth
            let oldHeight = aw_drawableHeight
            aw_updateDrawable(drawable)
            if oldWidth != aw_drawableWidth || oldHeight != aw_drawableHeight {
                requestLayout()
            }
            invalidate()
        }
    }

    /// ImageView.setImageBitmap: a BitmapDrawable of the bitmap, always set again (Android clears mDrawable first,
    /// so the old drawable keeps its callback).
    func setImageBitmap(_ bm: ABitmap?) {
        aw_drawable = nil
        setImageDrawable(ABitmapDrawable(bm))
    }

    /// ImageView.resolveUri: loads the resource when no drawable is set (an unknown name gives no drawable and is
    /// not tried again, like the caught Resources.NotFoundException).
    private func aw_resolveUri() {
        if aw_drawable != nil { return }
        guard let res = aw_resource else { return }
        let d = ContextCompat_getDrawable(res)
        if d == nil {
            aw_resource = nil
        }
        aw_updateDrawable(d)
    }

    private func aw_updateDrawable(_ d: ADrawable?) {
        var sameDrawable = false
        if let old = aw_drawable {
            sameDrawable = old === d
            old.callbackView = nil
            if !sameDrawable && isAttachedToWindow {
                old.setVisible(false, false)
            }
        }
        aw_drawable = d
        if let d = d {
            d.callbackView = self
            d.setLayoutDirection(layoutDirection)
            if d.isStateful {
                d.setState(drawableState)
            }
            if !sameDrawable {
                let visible = isAttachedToWindow && windowVisibility == AView.VISIBLE && isShown
                d.setVisible(visible, true)
            }
            if aw_hasLevelSet {
                d.setLevel(aw_level)
            }
            aw_drawableWidth = d.intrinsicWidth
            aw_drawableHeight = d.intrinsicHeight
            aw_applyImageTint()
            aw_applyAlpha()
            aw_configureBounds()
        } else {
            aw_drawableWidth = -1
            aw_drawableHeight = -1
        }
    }

    /// ImageView.resizeFromDrawable.
    private func aw_resizeFromDrawable() {
        guard let d = aw_drawable else { return }
        var w = d.intrinsicWidth
        if w < 0 { w = aw_drawableWidth }
        var h = d.intrinsicHeight
        if h < 0 { h = aw_drawableHeight }
        if w != aw_drawableWidth || h != aw_drawableHeight {
            aw_drawableWidth = w
            aw_drawableHeight = h
            requestLayout()
        }
    }

    // MARK: State and level

    /// ImageView.setImageState.
    func setImageState(_ state: [Int], _ merge: Bool) {
        aw_state = state
        aw_mergeState = merge
        if aw_drawable != nil {
            refreshDrawableState()
            aw_resizeFromDrawable()
        }
    }

    override func onCreateDrawableState(_ extraSpace: Int) -> [Int] {
        guard let s = aw_state else { return super.onCreateDrawableState(extraSpace) }
        if !aw_mergeState { return s }
        return AView.mergeDrawableStates(super.onCreateDrawableState(extraSpace + s.count), s)
    }

    override func drawableStateChanged() {
        super.drawableStateChanged()
        if let d = aw_drawable, d.isStateful, d.setState(drawableState) {
            invalidateDrawable(d)
        }
    }

    override func setSelected(_ selected: Bool) {
        super.setSelected(selected)
        aw_resizeFromDrawable()
    }

    /// ImageView.setImageLevel.
    func setImageLevel(_ level: Int) {
        aw_level = level
        aw_hasLevelSet = true
        if let d = aw_drawable {
            d.setLevel(level)
            aw_resizeFromDrawable()
        }
    }

    override func onRtlPropertiesChanged(_ layoutDirection: Int) {
        super.onRtlPropertiesChanged(layoutDirection)
        aw_drawable?.setLayoutDirection(layoutDirection)
    }

    /// ImageView.onVisibilityAggregated (targetSdk >= N): the drawable follows the aggregated visibility.
    override func onVisibilityAggregated(_ isVisible: Bool) {
        super.onVisibilityAggregated(isVisible)
        aw_drawable?.setVisible(isVisible, false)
    }

    // MARK: Scale type and matrix

    var scaleType: ScaleType {
        get { return aw_scaleType }
        set { setScaleType(newValue) }
    }

    func getScaleType() -> ScaleType { return aw_scaleType }

    func setScaleType(_ scaleType: ScaleType) {
        if aw_scaleType != scaleType {
            aw_scaleType = scaleType
            requestLayout()
            invalidate()
        }
    }

    /// ImageView.getImageMatrix: the draw matrix, or a new identity matrix when there is none (do not modify it in
    /// place; call setImageMatrix).
    var imageMatrix: AMatrix {
        get { return getImageMatrix() }
        set { setImageMatrix(newValue) }
    }

    func getImageMatrix() -> AMatrix {
        if let m = aw_drawMatrix { return m }
        return AMatrix()
    }

    /// ImageView.setImageMatrix: null and identity collapse; the values are copied; no invalidation when unchanged.
    func setImageMatrix(_ matrix: AMatrix?) {
        var m = matrix
        if let mm = m, mm.isIdentity() { m = nil }
        if (m == nil && !aw_matrix.isIdentity()) || (m != nil && aw_matrix != m!) {
            aw_matrix.set(m)
            aw_configureBounds()
            invalidate()
        }
    }

    /// ImageView.animateTransform.
    func animateTransform(_ matrix: AMatrix?) {
        guard let d = aw_drawable else { return }
        if let matrix = matrix {
            d.setBounds(0, 0, aw_drawableWidth, aw_drawableHeight)
            if aw_drawMatrix == nil { aw_drawMatrix = AMatrix() }
            aw_drawMatrix!.set(matrix)
        } else {
            let vwidth = width - mPaddingLeft - mPaddingRight
            let vheight = height - mPaddingTop - mPaddingBottom
            d.setBounds(0, 0, vwidth, vheight)
            aw_drawMatrix = nil
        }
        invalidate()
    }

    var cropToPadding: Bool {
        get { return aw_cropToPadding }
        set { setCropToPadding(newValue) }
    }

    func getCropToPadding() -> Bool { return aw_cropToPadding }

    func setCropToPadding(_ cropToPadding: Bool) {
        if aw_cropToPadding != cropToPadding {
            aw_cropToPadding = cropToPadding
            requestLayout()
            invalidate()
        }
    }

    /// ImageView.setAdjustViewBounds: `true` also sets ScaleType.FIT_CENTER; no layout request of its own.
    var adjustViewBounds: Bool {
        get { return aw_adjustViewBounds }
        set { setAdjustViewBounds(newValue) }
    }

    func getAdjustViewBounds() -> Bool { return aw_adjustViewBounds }

    func setAdjustViewBounds(_ adjustViewBounds: Bool) {
        aw_adjustViewBounds = adjustViewBounds
        if adjustViewBounds {
            setScaleType(.FIT_CENTER)
        }
    }

    /// ImageView.setMaxWidth / setMaxHeight (only used with adjustViewBounds; no layout request, like Android).
    var maxWidth: Int {
        get { return aw_maxWidth }
        set { aw_maxWidth = newValue }
    }

    var maxHeight: Int {
        get { return aw_maxHeight }
        set { aw_maxHeight = newValue }
    }

    func getMaxWidth() -> Int { return aw_maxWidth }
    func setMaxWidth(_ maxWidth: Int) { aw_maxWidth = maxWidth }
    func getMaxHeight() -> Int { return aw_maxHeight }
    func setMaxHeight(_ maxHeight: Int) { aw_maxHeight = maxHeight }

    // MARK: Tint, colour filter, alpha

    /// ImageView.setImageTintList (the drawable's SRC_IN tint).
    var imageTintList: AColorStateList? {
        get { return aw_drawableTintList }
        set { setImageTintList(newValue) }
    }

    func getImageTintList() -> AColorStateList? { return aw_drawableTintList }

    func setImageTintList(_ tint: AColorStateList?) {
        aw_drawableTintList = tint
        aw_hasDrawableTint = true
        aw_applyImageTint()
    }

    private func aw_applyImageTint() {
        guard let d0 = aw_drawable, aw_hasDrawableTint else { return }
        let d = d0.mutate()
        aw_drawable = d
        d.setTintList(aw_drawableTintList)
        // The drawable may not have been stateful before the tint.
        if d.isStateful {
            d.setState(drawableState)
        }
    }

    /// ImageView.setColorFilter(int): PorterDuffColorFilter(color, PorterDuff.Mode.SRC_ATOP).
    func setColorFilter(_ color: Int) {
        aw_setColorFilter(color)
    }

    /// ImageView.clearColorFilter().
    func clearColorFilter() {
        aw_setColorFilter(nil)
    }

    /// The colour of the SRC_ATOP filter (getColorFilter() as a colour), nil without one.
    var colorFilterColor: Int? { return aw_colorFilter }

    /// ImageView.setColorFilter(ColorFilter): `mColorFilter != cf` compares references, so a new
    /// PorterDuffColorFilter always applies, and clearing is a no-op without a filter.
    private func aw_setColorFilter(_ color: Int?) {
        if color == nil && aw_colorFilter == nil { return }
        aw_colorFilter = color
        if let d = aw_drawable { aw_drawable = d.mutate() }
        invalidate()
    }

    /// ImageView.getImageAlpha / setImageAlpha (the drawable's alpha, not the view's).
    var imageAlpha: Int {
        get { return aw_alpha }
        set { setImageAlpha(newValue) }
    }

    func getImageAlpha() -> Int { return aw_alpha }

    func setImageAlpha(_ alpha: Int) {
        let a = alpha & 0xFF
        if aw_alpha != a {
            aw_alpha = a
            aw_hasAlpha = true
            aw_applyAlpha()
            invalidate()
        }
    }

    private func aw_applyAlpha() {
        guard let d0 = aw_drawable, aw_hasAlpha else { return }
        let d = d0.mutate()
        aw_drawable = d
        // mAlpha * mViewAlphaScale >> 8 with mViewAlphaScale = 256.
        d.alpha = (aw_alpha * 256) >> 8
    }

    // MARK: Baseline

    override func getBaseline() -> Int {
        return aw_baselineAlignBottom ? measuredHeight : aw_baseline
    }

    func setBaseline(_ baseline: Int) {
        if aw_baseline != baseline {
            aw_baseline = baseline
            requestLayout()
        }
    }

    var baselineAlignBottom: Bool {
        get { return aw_baselineAlignBottom }
        set { setBaselineAlignBottom(newValue) }
    }

    func getBaselineAlignBottom() -> Bool { return aw_baselineAlignBottom }

    func setBaselineAlignBottom(_ aligned: Bool) {
        if aw_baselineAlignBottom != aligned {
            aw_baselineAlignBottom = aligned
            requestLayout()
        }
    }

    // MARK: Measure (ImageView.onMeasure)

    override func onMeasure(_ widthMeasureSpec: Int, _ heightMeasureSpec: Int) {
        aw_resolveUri()
        var w: Int
        var h: Int
        // Desired aspect ratio of the content (without padding).
        var desiredAspect: Float = 0
        var resizeWidth = false
        var resizeHeight = false
        let widthSpecMode = AMeasureSpec.getMode(widthMeasureSpec)
        let heightSpecMode = AMeasureSpec.getMode(heightMeasureSpec)

        if aw_drawable == nil {
            aw_drawableWidth = -1
            aw_drawableHeight = -1
            w = 0
            h = 0
        } else {
            w = aw_drawableWidth
            h = aw_drawableHeight
            if w <= 0 { w = 1 }
            if h <= 0 { h = 1 }
            if aw_adjustViewBounds {
                resizeWidth = widthSpecMode != AMeasureSpec.EXACTLY
                resizeHeight = heightSpecMode != AMeasureSpec.EXACTLY
                desiredAspect = Float(w) / Float(h)
            }
        }

        let pleft = mPaddingLeft
        let pright = mPaddingRight
        let ptop = mPaddingTop
        let pbottom = mPaddingBottom

        var widthSize: Int
        var heightSize: Int

        if resizeWidth || resizeHeight {
            widthSize = aw_resolveAdjustedSize(w + pleft + pright, aw_maxWidth, widthMeasureSpec)
            heightSize = aw_resolveAdjustedSize(h + ptop + pbottom, aw_maxHeight, heightMeasureSpec)
            if desiredAspect != 0 {
                // (float)(widthSize - pleft - pright) / (heightSize - ptop - pbottom): a float division.
                let actualAspect = Float(widthSize - pleft - pright) / Float(heightSize - ptop - pbottom)
                if Double(abs(actualAspect - desiredAspect)) > 0.0000001 {
                    var done = false
                    if resizeWidth {
                        let newWidth = AWMath.javaInt(desiredAspect * Float(heightSize - ptop - pbottom)) + pleft + pright
                        // The width may outgrow its first estimate when the height is fixed (targetSdk > 17).
                        if !resizeHeight {
                            widthSize = aw_resolveAdjustedSize(newWidth, aw_maxWidth, widthMeasureSpec)
                        }
                        if newWidth <= widthSize {
                            widthSize = newWidth
                            done = true
                        }
                    }
                    if !done && resizeHeight {
                        let newHeight = AWMath.javaInt(Float(widthSize - pleft - pright) / desiredAspect) + ptop + pbottom
                        if !resizeWidth {
                            heightSize = aw_resolveAdjustedSize(newHeight, aw_maxHeight, heightMeasureSpec)
                        }
                        if newHeight <= heightSize {
                            heightSize = newHeight
                        }
                    }
                }
            }
        } else {
            w += pleft + pright
            h += ptop + pbottom
            w = Swift.max(w, getSuggestedMinimumWidth())
            h = Swift.max(h, getSuggestedMinimumHeight())
            widthSize = AView.resolveSizeAndState(w, widthMeasureSpec, 0)
            heightSize = AView.resolveSizeAndState(h, heightMeasureSpec, 0)
        }
        setMeasuredDimension(widthSize, heightSize)
    }

    private func aw_resolveAdjustedSize(_ desiredSize: Int, _ maxSize: Int, _ measureSpec: Int) -> Int {
        var result = desiredSize
        let specMode = AMeasureSpec.getMode(measureSpec)
        let specSize = AMeasureSpec.getSize(measureSpec)
        switch specMode {
        case AMeasureSpec.UNSPECIFIED:
            result = Swift.min(desiredSize, maxSize)
        case AMeasureSpec.AT_MOST:
            result = Swift.min(Swift.min(desiredSize, specSize), maxSize)
        case AMeasureSpec.EXACTLY:
            result = specSize
        default:
            break
        }
        return result
    }

    // MARK: Bounds (ImageView.setFrame / configureBounds)

    @discardableResult
    override func setFrame(_ left: Int, _ top: Int, _ right: Int, _ bottom: Int) -> Bool {
        let changed = super.setFrame(left, top, right, bottom)
        aw_haveFrame = true
        aw_configureBounds()
        return changed
    }

    private func aw_configureBounds() {
        guard let d = aw_drawable, aw_haveFrame else { return }
        let dwidth = aw_drawableWidth
        let dheight = aw_drawableHeight
        let vwidth = width - mPaddingLeft - mPaddingRight
        let vheight = height - mPaddingTop - mPaddingBottom
        let fits = (dwidth < 0 || vwidth == dwidth) && (dheight < 0 || vheight == dheight)

        if dwidth <= 0 || dheight <= 0 || aw_scaleType == .FIT_XY {
            // No intrinsic size, or told to fill: the drawable fills the content box.
            d.setBounds(0, 0, vwidth, vheight)
            aw_drawMatrix = nil
            return
        }
        d.setBounds(0, 0, dwidth, dheight)
        switch aw_scaleType {
        case .MATRIX:
            aw_drawMatrix = aw_matrix.isIdentity() ? nil : aw_matrix
        case _ where fits:
            aw_drawMatrix = nil
        case .CENTER:
            aw_drawMatrix = aw_matrix
            aw_matrix.setTranslate(Float(AWMath.round(Float(vwidth - dwidth) * 0.5)),
                                   Float(AWMath.round(Float(vheight - dheight) * 0.5)))
        case .CENTER_CROP:
            aw_drawMatrix = aw_matrix
            let scale: Float
            var dx: Float = 0
            var dy: Float = 0
            if dwidth * vheight > vwidth * dheight {
                scale = Float(vheight) / Float(dheight)
                dx = (Float(vwidth) - Float(dwidth) * scale) * 0.5
            } else {
                scale = Float(vwidth) / Float(dwidth)
                dy = (Float(vheight) - Float(dheight) * scale) * 0.5
            }
            aw_matrix.setScale(scale, scale)
            aw_matrix.postTranslate(Float(AWMath.round(dx)), Float(AWMath.round(dy)))
        case .CENTER_INSIDE:
            aw_drawMatrix = aw_matrix
            let scale: Float
            if dwidth <= vwidth && dheight <= vheight {
                scale = 1
            } else {
                scale = Swift.min(Float(vwidth) / Float(dwidth), Float(vheight) / Float(dheight))
            }
            let dx = Float(AWMath.round((Float(vwidth) - Float(dwidth) * scale) * 0.5))
            let dy = Float(AWMath.round((Float(vheight) - Float(dheight) * scale) * 0.5))
            aw_matrix.setScale(scale, scale)
            aw_matrix.postTranslate(dx, dy)
        default:
            // FIT_START / FIT_CENTER / FIT_END: Matrix.setRectToRect(src, dst, ScaleToFit).
            aw_tempSrc.set(0, 0, Float(dwidth), Float(dheight))
            aw_tempDst.set(0, 0, Float(vwidth), Float(vheight))
            aw_drawMatrix = aw_matrix
            let stf: AMatrix.ScaleToFit
            switch aw_scaleType {
            case .FIT_START: stf = .START
            case .FIT_END: stf = .END
            default: stf = .CENTER
            }
            aw_matrix.setRectToRect(aw_tempSrc, aw_tempDst, stf)
        }
    }

    // MARK: Drawing (ImageView.onDraw)

    override func onDraw(_ canvas: ACanvas) {
        super.onDraw(canvas)
        guard let d = aw_drawable else { return }
        if aw_drawableWidth == 0 || aw_drawableHeight == 0 { return }
        // View.draw translates the content by (-mScrollX, -mScrollY).
        let scrollSave = canvas.save()
        canvas.translate(Float(-mScrollX), Float(-mScrollY))
        if aw_drawMatrix == nil && mPaddingTop == 0 && mPaddingLeft == 0 {
            aw_drawContent(d, canvas)
        } else {
            let saveCount = canvas.getSaveCount()
            canvas.save()
            if aw_cropToPadding {
                let sx = mScrollX
                let sy = mScrollY
                canvas.clipRect(sx + mPaddingLeft, sy + mPaddingTop, sx + mRight - mLeft - mPaddingRight,
                                sy + mBottom - mTop - mPaddingBottom)
            }
            canvas.translate(Float(mPaddingLeft), Float(mPaddingTop))
            if let m = aw_drawMatrix {
                canvas.concat(m)
            }
            aw_drawContent(d, canvas)
            canvas.restoreToCount(saveCount)
        }
        canvas.restoreToCount(scrollSave)
    }

    /// Draws the drawable; with a colour filter the drawable's pixels go through SRC_ATOP with the filter colour
    /// (result = colour x drawable alpha + drawable x (1 - colour alpha)), in an isolated layer like the filter.
    private func aw_drawContent(_ d: ADrawable, _ canvas: ACanvas) {
        guard let filter = aw_colorFilter, let c = canvas.cgContext else {
            d.draw(canvas)
            return
        }
        let b = d.bounds
        let layer = canvas.saveLayer(ARectF(b), nil)
        d.draw(canvas)
        c.saveGState()
        c.setBlendMode(.sourceAtop)
        c.setFillColor(AColor.cgColor(filter))
        c.fill(CGRect(x: CGFloat(b.left), y: CGFloat(b.top), width: CGFloat(b.right - b.left),
                      height: CGFloat(b.bottom - b.top)))
        c.restoreGState()
        canvas.restoreToCount(layer)
    }
}
