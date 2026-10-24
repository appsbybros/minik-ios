import Foundation

/// Port of `ui/OutlinedTitleView.kt` (Android snapshot dd722e5), statement by statement.
///
/// Thin blue edge around the original title; keeps normal text layout and accessibility.
/// `OutlinedTitleView(context, attrs, style)` is `OutlinedTitleView()` (the default TextView style).
final class OutlinedTitleView: ATextView {
    override func onDraw(_ canvas: ACanvas) {
        let textLayout: ALayout? = layout
        if let textLayout = textLayout {
            let color = paint.color; let style = paint.style; let width = paint.strokeWidth
            paint.color = argbInt(0xff3699e8); paint.style = .STROKE; paint.strokeWidth = AResources.displayMetrics.density * 1.4
            let save = canvas.save(); canvas.translate(Float(totalPaddingLeft), Float(totalPaddingTop)); textLayout.draw(canvas); canvas.restoreToCount(save)
            paint.color = color; paint.style = style; paint.strokeWidth = width
        }
        super.onDraw(canvas)
    }
}
