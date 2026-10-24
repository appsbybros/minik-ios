import Foundation

/// Port of MinikFamilyServices `FamilyTournamentUi.java` (family snapshot 2f75e98), statement by statement.
///
/// Shared presentation for separated room actions and deliberate tournament exits.
/// Swift API: the Java parameter names are the labels (DESIGN 2.1); the unlabelled forms forward to them.
enum FamilyTournamentUi {
    /// Java `dp(Context, int)`: `Math.round(n * density)`.
    fileprivate static func dp(_ n: Int) -> Int { return (Float(n) * AResources.displayMetrics.density).roundToInt() }

    /// The dashed create/join divider. (Not called by Triple Shot; ported with the class.)
    static func divider(parent: ALinearLayout) {
        let line = FamilyTournamentDividerLine()
        line.setTag("create-join-divider"); line.importantForAccessibility = AView.IMPORTANT_FOR_ACCESSIBILITY_NO
        let lp = ALinearLayout.LayoutParams(-1, dp(2)); lp.setMargins(dp(8), dp(24), dp(8), dp(24)); parent.addView(line, lp)
    }
    static func divider(_ parent: ALinearLayout) { divider(parent: parent) }

    /// The three-button exit dialog (League Back): every button first dismisses the dialog; Save runs `onSave`, Don't save
    /// runs `onDiscard`, Cancel only closes. A tap outside does nothing (Back = cancel). `new Button(a)` is a framework
    /// android.widget.Button (AndroidKit `.FRAMEWORK` style), not a MaterialButton.
    @discardableResult
    static func confirmSave(a: AActivity, title: String, message: String, save: String, discard: String, cancel: String,
                            onSave: @escaping () -> Void, onDiscard: @escaping () -> Void) -> AAlertDialog {
        let body = ALinearLayout(); body.orientation = ALinearLayout.VERTICAL; body.setPadding(dp(24), dp(24), dp(24), dp(24))
        body.layoutDirection = a.resources.configuration.getLayoutDirection(); let panel = FamilySkyDrawable(panel: true); panel.setColor(argbInt(0xfff6f8ff)); panel.setCornerRadius(Float(dp(24))); body.background = panel
        let heading = ATextView(); heading.setText(title); heading.setTextSize(22); heading.setTypeface(nil, ATypeface.BOLD); heading.setTextColor(argbInt(0xff282d4e)); heading.setGravity(AGravity.CENTER); body.addView(heading, ALinearLayout.LayoutParams(-1, -2))
        let description = ATextView(); description.setText(message); description.setTextSize(17); description.setTextColor(argbInt(0xff282d4e)); description.setGravity(AGravity.CENTER); let textLp = ALinearLayout.LayoutParams(-1, -2); textLp.setMargins(0, dp(16), 0, dp(12)); body.addView(description, textLp)
        let scroll = AScrollView(); scroll.addView(body)
        let dialog = AAlertDialog.Builder(a).setView(scroll).create()
        let labels = [save, discard, cancel]; let fills = [argbInt(0xffb8d9ff), argbInt(0xffe91e63), argbInt(0xffe8e0ff)]
        for i in 0..<3 {
            let index = i; let b = AButton(style: .FRAMEWORK); b.setText(labels[i]); b.setTextSize(17); b.setAllCaps(false); b.setGravity(AGravity.CENTER); b.setTypeface(nil, ATypeface.BOLD); b.setTextColor(i == 1 ? AColor.WHITE : argbInt(0xff282d4e)); b.setBackgroundTintList(nil)
            let bg: AGradientDrawable = FamilySkyDrawable(); bg.setColor(fills[i]); bg.setCornerRadius(Float(dp(16))); b.background = bg; b.setPadding(dp(12), dp(10), dp(12), dp(10)); FamilyButtonAlignment.bind(button: b)
            let lp = ALinearLayout.LayoutParams(-1, dp(64)); lp.topMargin = dp(18); body.addView(b, lp); b.setTag("tournament-exit-\(i)")
            // The dialog owns its views, so the buttons reach it weakly (it is alive whenever it is showing).
            b.setOnClickListener { [weak dialog] _ in dialog?.dismiss(); if index == 0 { onSave() } else if index == 1 { onDiscard() } }
        }
        dialog.setCanceledOnTouchOutside(false); dialog.show(); let window: AWindow? = dialog.window; window?.setBackgroundDrawableResource(android.R.color.transparent); return dialog
    }
    @discardableResult
    static func confirmSave(_ a: AActivity, _ title: String, _ message: String, _ save: String, _ discard: String, _ cancel: String,
                            _ onSave: @escaping () -> Void, _ onDiscard: @escaping () -> Void) -> AAlertDialog {
        return confirmSave(a: a, title: title, message: message, save: save, discard: discard, cancel: cancel, onSave: onSave, onDiscard: onDiscard)
    }
}

/// Java's anonymous `View` of `FamilyTournamentUi.divider`: a dashed 2 dp line through the middle.
private final class FamilyTournamentDividerLine: AView {
    let paint = APaint(APaint.ANTI_ALIAS_FLAG)
    override func onDraw(_ canvas: ACanvas) {
        super.onDraw(canvas); paint.color = argbInt(0xff7892ad); paint.strokeWidth = Float(FamilyTournamentUi.dp(2)); paint.style = .STROKE
        paint.pathEffect = ADashPathEffect([Float(FamilyTournamentUi.dp(7)), Float(FamilyTournamentUi.dp(6))], 0); canvas.drawLine(0, Float(height) / 2, Float(width), Float(height) / 2, paint)
    }
}
