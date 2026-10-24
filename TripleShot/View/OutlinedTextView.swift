import Foundation

/// Port of `view/OutlinedTextView.kt` (Android snapshot dd722e5), statement by statement.
///
/// Lightweight outlined text used over the colorful court artwork.
///
/// It draws the TextView layout twice: first as a white stroke, then as the normal fill.
/// This keeps questions / answers readable without putting large opaque cards over the court.
///
/// This view is intentionally text-only (no cursor/editing). That is exactly what we need for
/// question labels, answer choices and HUD text.
///
/// `OutlinedTextView(context, attrs, defStyleAttr)` is `OutlinedTextView()` (the default TextView style). As in Kotlin,
/// `onDraw` does not call `super.onDraw`: the background (drawn by View.draw) still appears; compound drawables, cursor
/// and TextView's own clipping are skipped.
/// Swift API: the Kotlin parameter names are the labels (DESIGN 2.1); the unlabelled forms forward to them.
final class OutlinedTextView: ATextView {

    private var outlineColor: Int = AColor.WHITE
    private var outlineWidthPx: Float = AResources.displayMetrics.density * 2.6

    func setOutlineColor(color: Int) {
        outlineColor = color
        invalidate()
    }
    func setOutlineColor(_ color: Int) { setOutlineColor(color: color) }

    func setOutlineWidthDp(dp: Float) {
        outlineWidthPx = dp * AResources.displayMetrics.density
        invalidate()
    }
    func setOutlineWidthDp(_ dp: Float) { setOutlineWidthDp(dp: dp) }

    override func onDraw(_ canvas: ACanvas) {
        let layoutOrNil: ALayout? = layout
        guard let textLayout = layoutOrNil else { return }

        let save = canvas.save()

        let availableHeight =
            height - extendedPaddingTop - extendedPaddingBottom
        let extraVertical =
            (availableHeight - textLayout.height).coerceAtLeast(0)

        let verticalOffset: Float
        switch gravity & AGravity.VERTICAL_GRAVITY_MASK {
        case AGravity.BOTTOM: verticalOffset = extraVertical.toFloat()
        case AGravity.CENTER_VERTICAL: verticalOffset = Float(extraVertical) * 0.5
        default: verticalOffset = 0
        }

        let scrollXPx: Int = scrollX, scrollYPx: Int = scrollY
        canvas.translate(
            (compoundPaddingLeft - scrollXPx).toFloat(),
            (extendedPaddingTop - scrollYPx).toFloat() + verticalOffset
        )

        let oldStyle = paint.style
        let oldStrokeWidth = paint.strokeWidth
        let oldColor = paint.color
        let oldJoin = paint.strokeJoin

        paint.style = .STROKE
        paint.strokeWidth = outlineWidthPx
        paint.strokeJoin = .ROUND
        paint.color = outlineColor
        textLayout.draw(canvas)

        paint.style = .FILL
        paint.strokeWidth = 0
        paint.color = currentTextColor
        textLayout.draw(canvas)

        paint.style = oldStyle
        paint.strokeWidth = oldStrokeWidth
        paint.strokeJoin = oldJoin
        paint.color = oldColor

        canvas.restoreToCount(save)
    }
}
