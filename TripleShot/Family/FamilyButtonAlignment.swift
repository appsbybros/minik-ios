import Foundation

/// Port of MinikFamilyServices `FamilyButtonAlignment.java` (family 31e380d, the copy Android 6c38131 builds with),
/// statement by statement.
///
/// Aligns the rendered lettering with the raised face, not the face plus its lower lip.
/// Uses Android's shaped Layout, so RTL, fallback fonts, marks and wrapped labels use
/// the same glyphs as the real button. Raster measurement is cached until Layout changes.
/// Does not replace the view, text, font, listeners, horizontal padding or background.
///
/// Swift API: the Java parameter names are the labels (DESIGN 2.1); the unlabelled forms forward to them.
enum FamilyButtonAlignment {
    private static let bound = FamilyWeakHashMap<ATextView, Alignment>()
    private static var fullRaisedFace = false
    /// App-level optical alignment choice. Call before constructing controls.
    /// Opt-in preserves the existing gloss-excluding target in other apps.
    static func useFullRaisedFace(enabled: Bool) { fullRaisedFace = enabled }
    static func usesFullRaisedFace() -> Bool { return fullRaisedFace }
    /// Owner-requested optical adjustment: lower lettering by 3dp without moving
    /// the button, its background, or its touch target. Shared by compound labels.
    static func opticalOffsetPx(view: AView) -> Float { return Float(3) * view.resources.displayMetrics.density }

    static func bind(button: AButton) { bind(text: button, surface: button) }
    static func bind(_ button: AButton) { bind(button: button) }
    /// Spinner text and its chevron are children/siblings of the painted surface.
    static func bind(text: ATextView, surface: AView) {
        if text is ACompoundButton { return }
        let old = bound.get(text)
        if let old = old {
            if old.surface === surface { return }
            old.onViewDetachedFromWindow(text); text.removeOnAttachStateChangeListener(old)
        }
        let a = Alignment(text, surface); bound.put(text, a)
        text.addOnAttachStateChangeListener(a)
        if text.isAttachedToWindow { a.onViewAttachedToWindow(text) }
    }
    static func bind(_ text: ATextView, _ surface: AView) { bind(text: text, surface: surface) }

    /// Java `Alignment implements ViewTreeObserver.OnPreDrawListener, View.OnAttachStateChangeListener`. AndroidKit's
    /// pre-draw listener is a closure object, so the Alignment owns one (`preDraw`, the same object for add and remove;
    /// it holds the Alignment weakly, the TextView holds the Alignment through its attach-state listener list).
    private final class Alignment: AOnAttachStateChangeListener {
        private weak var reference: ATextView?
        weak var surface: AView?
        private var textPosition = [0, 0], surfacePosition = [0, 0]
        private var observer: AViewTreeObserver?
        private var measured: ALayout?
        private var measuredText: String?
        private var measuredTextSize: Float = 0, measuredScaleX: Float = 0, measuredSpacing: Float = 0
        private var measuredTypeface: ATypeface?
        private var measuredWidth = 0, measuredHeight = 0
        private var inkMiddle = Float.nan
        private var paddingTotal = -1, lastTop = -1, lastBottom = -1
        private let face = ARectF()
        private lazy var preDraw = AOnPreDrawListener { [weak self] in self?.onPreDraw() ?? true }
        init(_ text: ATextView, _ faceOwner: AView) { reference = text; surface = faceOwner; super.init() }
        override func onViewAttachedToWindow(_ v: AView) {
            if let observer = observer, observer.isAlive { observer.removeOnPreDrawListener(preDraw) }
            observer = v.viewTreeObserver; observer!.addOnPreDrawListener(preDraw); v.invalidate()
        }
        override func onViewDetachedFromWindow(_ v: AView) {
            if let observer = observer, observer.isAlive { observer.removeOnPreDrawListener(preDraw) }
            observer = nil; measured = nil; measuredText = nil
        }
        func onPreDraw() -> Bool {
            guard let b = reference, let owner = surface else { return true }
            if !b.isShown || b.width == 0 || b.height == 0 || !(owner.background is FamilySkyDrawable) { return true }
            let background = owner.background as! FamilySkyDrawable
            if background.isPanel { return true }
            let gravity = (b.getGravity() & ~AGravity.VERTICAL_GRAVITY_MASK) | AGravity.CENTER_VERTICAL
            if b.getGravity() != gravity { b.setGravity(gravity); return false }
            let layoutOrNil: ALayout? = b.layout
            guard let layout = layoutOrNil, layout.getLineCount() != 0, b.text.length != 0 else { return true }
            // A host can intentionally change padding after creating/reusing its button.
            if paddingTotal < 0 || b.paddingTop != lastTop || b.paddingBottom != lastBottom {
                paddingTotal = b.paddingTop + b.paddingBottom
            }
            let text: String = layout.getText()
            if measured !== layout || text != measuredText
                || measuredTextSize != layout.getPaint().textSize
                || measuredScaleX != layout.getPaint().textScaleX
                || measuredSpacing != layout.getPaint().letterSpacing
                || measuredTypeface !== layout.getPaint().typeface
                || measuredWidth != layout.getWidth() || measuredHeight != layout.getHeight() {
                inkMiddle = FamilyButtonAlignment.measureInkMiddle(layout); measured = layout; measuredText = text
                measuredTextSize = layout.getPaint().textSize; measuredScaleX = layout.getPaint().textScaleX
                measuredSpacing = layout.getPaint().letterSpacing; measuredTypeface = layout.getPaint().typeface
                measuredWidth = layout.getWidth(); measuredHeight = layout.getHeight()
            }
            if inkMiddle.isNaN { return true }
            // View normally assigns background bounds during draw, after pre-draw. Set
            // the same direct-background bounds here so even the first frame is aligned.
            if background.getBounds().width() != owner.width || background.getBounds().height() != owner.height {
                background.setBounds(0, 0, owner.width, owner.height)
            }
            if FamilyButtonAlignment.fullRaisedFace { background.copyFaceBounds(out: face) } else { background.copyTextFaceBounds(out: face) }
            if owner !== b {
                b.getLocationInWindow(&textPosition); owner.getLocationInWindow(&surfacePosition)
                face.offset(Float(surfacePosition[0] - textPosition[0]), Float(surfacePosition[1] - textPosition[1]))
            }
            if face.isEmpty() { return true }
            let baseline: Int = b.getBaseline(), scrollY: Int = b.scrollY
            let origin = Float(baseline - layout.getLineBaseline(0) - scrollY)
            let delta = face.centerY() + FamilyButtonAlignment.opticalOffsetPx(view: b) - (origin + inkMiddle)
            // A Spinner child must not resize its wrap-content parent through padding.
            if owner !== b {
                if abs(delta) > 0.75 { b.translationY = b.translationY + delta }
                return true
            }
            lastTop = b.paddingTop; lastBottom = b.paddingBottom
            if abs(delta) <= 0.75 { return true }
            let difference = lastTop - lastBottom + (2 * delta).roundToInt()
            // Preserve the original padding budget whenever possible. Grow only if a
            // zero-padding host leaves no room for the face/font correction; never use
            // negative padding, which can clip accents or cause edge-dependent alignment.
            paddingTotal = max(paddingTotal, abs(difference))
            let top = (Float(paddingTotal + difference) / 2).roundToInt(), bottom = paddingTotal - top
            if top == lastTop && bottom == lastBottom { return true }
            lastTop = top; lastBottom = bottom
            b.setPadding(b.paddingLeft, top, b.paddingRight, bottom)
            return false // Wait for the corrected layout rather than flashing the old position.
        }
    }

    /// The raster ink middle of a laid-out text: drawn white into a bitmap padded by ceil(textSize) above and below,
    /// the first and last pixel rows with alpha >= 16, `(first + last + 1) / 2 - pad`; NaN without ink or for huge layouts.
    private static func measureInkMiddle(_ layout: ALayout) -> Float {
        let width = layout.getWidth(), pad = Double(layout.getPaint().textSize).rounded(.up).toInt()
        let height = layout.getHeight() + 2 * pad
        if width <= 0 || height <= 0 || width > 8192 || height > 4096 { return Float.nan }
        let mask = ABitmap.createBitmap(width, height, .ARGB_8888)
        defer { mask.recycle() }
        let canvas = ACanvas(mask); canvas.translate(0, Float(pad))
        // TextView applies its state color in onDraw, which may not have run yet.
        // Geometry must not depend on a stale/transparent paint color from that frame.
        let originalColor = layout.getPaint().color
        layout.getPaint().color = AColor.WHITE; layout.draw(canvas)
        layout.getPaint().color = originalColor
        var row = [Int](repeating: 0, count: width); var first = -1, last = -1
        for y in kuntil(0, height) {
            mask.getPixels(&row, 0, width, 0, y, width, 1)
            for pixel in row where (UInt32(truncatingIfNeeded: pixel) >> 24) >= 16 { if first < 0 { first = y }; last = y; break }
        }
        return first < 0 ? Float.nan : Float(first + last + 1) / 2 - Float(pad)
    }
}
