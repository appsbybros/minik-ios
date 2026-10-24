import Foundation

/// Port of MinikFamilyServices `FamilyReadingPanel.java` (family snapshot 2f75e98), statement by statement.
///
/// A centered form column. Width adapts to the current window, never to a device name.
/// `new FamilyReadingPanel(context)` is `FamilyReadingPanel()` (AndroidKit views take no Context).
final class FamilyReadingPanel: AFrameLayout {
    /// Java `contentWidth(Context, int available)`: the Context only supplies the display metrics of the app window
    /// (AndroidKit keeps them in `AResources`; they follow rotation), read on every call so rotation re-flows the column.
    static func contentWidth(context: AContext?, available: Int) -> Int {
        let dm = AResources.displayMetrics
        return contentWidth(widthPixels: dm.widthPixels, heightPixels: dm.heightPixels, density: dm.density, available: available)
    }
    static func contentWidth(_ context: AContext?, _ available: Int) -> Int { return contentWidth(context: context, available: available) }
    /// The rule of `contentWidth` with the display metrics passed in (pure; checked by the parity tests).
    /// Portrait or square (width <= height): `available`; landscape: `min(available, min(round(520 d), max(round(300 d), round(0.52 available))))`.
    static func contentWidth(widthPixels: Int, heightPixels: Int, density: Float, available: Int) -> Int {
        if widthPixels <= heightPixels { return available }
        return min(available, min((520 * density).roundToInt(), max((300 * density).roundToInt(), (Float(available) * 0.52).roundToInt())))
    }
    override func onMeasure(_ widthSpec: Int, _ heightSpec: Int) {
        let available = AMeasureSpec.getSize(widthSpec) - paddingLeft - paddingRight
        var i = 0
        while i < childCount {
            let child = getChildAt(i)!; let lp = child.layoutParams as! AFrameLayout.LayoutParams
            lp.width = max(0, FamilyReadingPanel.contentWidth(context: nil, available: available) - lp.leftMargin - lp.rightMargin); lp.gravity = AGravity.TOP | AGravity.CENTER_HORIZONTAL
            i += 1
        }
        super.onMeasure(widthSpec, heightSpec)
    }
}
