import Foundation

/// Port of `ui/TripleShotButton.kt` (Android 6c38131), statement by statement.
///
/// TripleShot centres lettering within the full painted control, including its shallow depth edge.
/// The shared family aligner centres below the upper gloss; compensate only that measured
/// geometric difference when painting text. Background, hit target and layout stay intact.
///
/// `TripleShotButton(context)` is `TripleShotButton()` (default `materialButtonStyle`: a filled MaterialButton); an XML
/// style is `TripleShotButton(style: .OUTLINED)` (or `applyStyle(_:)`), like any AButton.
final class TripleShotButton: AButton {
    var inkOverride: Int? = nil
    var labelOffsetDp: Float = Float(0.65)
    override func setBackgroundTintList(_ tint: AColorStateList?) {
        let face = background as? FamilySkyDrawable
        if let face = face, let tint = tint {
            // Material tint cannot replace the state colours of a custom painted drawable.
            super.setBackgroundTintList(nil)
            face.setColor(tint)
        } else { super.setBackgroundTintList(tint) }
    }
    override func onDraw(_ canvas: ACanvas) {
        let face = background as? FamilySkyDrawable
        guard let face = face, !face.isPanel, !text.isEmpty else { super.onDraw(canvas); return }
        let state: [Int] = drawableState
        let color = FamilySkyDrawable.palette(color: face.sourceColors().getColorForState(state, face.sourceColors().defaultColor))
        if AColor.alpha(color) > 0 && AColor.alpha(currentTextColor) > 0 {
            let ink = inkOverride ?? TripleShotButton.ink(color: color, isEnabled: isEnabled)
            if currentTextColor != ink { setTextColor(ink) }
        }
        let lettering = ARectF()
        face.copyTextFaceBounds(out: lettering)
        let save = canvas.save()
        // The owner judges the complete painted control, including its shallow depth edge.
        // Full-face centering still appeared high. Keep glyph shaping but center on the
        // painted outer bounds, moving the letters down by half that small lower edge.
        canvas.translate(0, face.bounds.exactCenterY() - lettering.centerY() + labelOffsetDp * resources.displayMetrics.density)
        super.onDraw(canvas); canvas.restoreToCount(save)
    }

    /// The lettering colour `onDraw` picks for a palette-mapped face colour (inline in Kotlin; a function here so the
    /// parity tests can check it): `dark = (red*299 + green*587 + blue*114) / 1000 < 130` (integer maths);
    /// `ink = dark && isEnabled ? WHITE : #FF23384D`.
    static func ink(color: Int, isEnabled: Bool) -> Int {
        let dark = (AColor.red(color) * 299 + AColor.green(color) * 587 + AColor.blue(color) * 114) / 1000 < 130
        return dark && isEnabled ? AColor.WHITE : argbInt(0xff23384d)
    }
}
