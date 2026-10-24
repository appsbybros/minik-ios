import Foundation

/// Port of `ui/SkyMaterialCardView.kt` (Android snapshot dd722e5), statement by statement.
///
/// Paint inside the original Material card; keep its stroke, ripple and selected state.
/// `SkyMaterialCardView(context)` is `SkyMaterialCardView()`. The sky face is a non-panel FamilySkyDrawable painted in
/// `dispatchDraw`, i.e. above the card background and below the children (pressed cards sink, disabled ones turn grey);
/// the Material stroke (the card's foreground) stays above the children.
final class SkyMaterialCardView: ACardView {
    private let sky = FamilySkyDrawable()
    private var lastColor: Int? = nil
    private var lastRadius: Float = -1
    override func dispatchDraw(_ canvas: ACanvas) {
        let state: [Int] = drawableState
        let color = cardBackgroundColor.getColorForState(state, cardBackgroundColor.defaultColor)
        if lastColor != color { sky.setColor(color); lastColor = color }
        if lastRadius != radius { sky.cornerRadius = radius; lastRadius = radius }
        sky.bounds = ARect(0, 0, width, height); sky.state = state
        sky.draw(canvas)
        super.dispatchDraw(canvas)
    }
}
