import UIKit

// Port of ui/TripleShotOnlineIdentity.kt (TripleShotGame 6c38131), spec 05 section 4.13.
//
// The online nickname (1-5 letters, OnlineNickname.valid) kept in SharedPreferences "tripleshot_online_identity"
// (keys "nickname" and "confirmed"), and the programmatic bilingual chooser dialog: an android.app.AlertDialog
// whose view is built in code exactly like the Kotlin (AndroidKit ALinearLayout / ATextView / AEditText /
// TripleShotButton), restyled on show by FamilyFormStyle and FamilySkyUi like on Android. Hebrew texts and an RTL
// layout only when the first device language is he/iw; any other language gets English.
//
// iOS: Android's Back key cancels the dialog; here the dialog's own Cancel button and a tap outside do the same
// (both exist on Android too), so no extra control is added. The only iOS-only addition is a VoiceOver
// announcement of the field error, which TalkBack reads on Android (spec 05 section 8.10).

enum TripleShotOnlineIdentity {
    private static func prefs(c: AContext) -> ASharedPreferences {
        return c.getSharedPreferences("tripleshot_online_identity", 0)
    }

    /// The stored nickname when valid, else a random English default that is saved (not confirmed).
    static func name(c: AContext) -> String {
        let p = prefs(c: c)
        if let stored = p.getString("nickname", nil), OnlineNickname.valid(stored) {
            return stored
        }
        let created = ["Comet", "Sunny", "Bunny", "Spark", "Orbit"].kRandom(KotlinRandom.Default)
        p.edit().putString("nickname", created).apply()
        return created
    }

    /// Calls `ready` with the nickname: at once when it was confirmed before (unless `always`), else after the
    /// chooser dialog's Continue. Cancel (or a tap outside) dismisses the dialog without calling `ready`.
    static func choose(c: AContext, always: Bool = false, ready: @escaping (String) -> Void) {
        let p = prefs(c: c)
        if !always && p.getBoolean("confirmed", false) {
            ready(name(c: c))
            return
        }
        // Build.VERSION.SDK_INT >= 24: configuration.locales[0].language.
        let language = c.resources.configuration.locales[0].language
        let he = ["he", "iw"].contains(language)
        func tr(en: String, heb: String) -> String {
            return he ? heb : en
        }
        let d = c.resources.displayMetrics.density
        func dp(n: Int) -> Int {
            return (n.toFloat() * d + Float(0.5)).toInt()
        }
        let body = ALinearLayout()
        body.orientation = ALinearLayout.VERTICAL
        body.setPadding(dp(n: 24), dp(n: 24), dp(n: 24), dp(n: 24))
        body.layoutDirection = he ? AView.LAYOUT_DIRECTION_RTL : AView.LAYOUT_DIRECTION_LTR
        func label(value: String, size: Float) -> ATextView {
            let view = ATextView()
            view.text = value
            view.textSize = size
            view.setTextColor(argbInt(0xff23384d))
            view.gravity = AGravity.START
            view.textAlignment = AView.TEXT_ALIGNMENT_VIEW_START
            return view
        }
        let title = label(value: tr(en: "Your online nickname", heb: "הכינוי שלכם ברשת"), size: 23)
        title.setTypeface(title.typeface, ATypeface.BOLD); title.gravity = AGravity.CENTER
        title.textAlignment = AView.TEXT_ALIGNMENT_CENTER
        body.addView(title)
        let message = label(
            value: tr(
                en: "Use a nickname of 1–5 letters online. Your full name stays on this device.",
                heb: "ברשת משתמשים בכינוי בן 1–5 אותיות. השם המלא נשאר במכשיר הזה."
            ),
            size: 18
        )
        let messageParams = ALinearLayout.LayoutParams(-1, -2)
        messageParams.topMargin = dp(n: 16)
        messageParams.bottomMargin = dp(n: 16)
        body.addView(message, messageParams)
        let field = AEditText()
        field.setSingleLine()
        field.setText(name(c: c))
        field.textSize = 20
        field.hint = tr(en: "Online nickname", heb: "כינוי ברשת")
        field.gravity = AGravity.START | AGravity.CENTER_VERTICAL
        field.textAlignment = AView.TEXT_ALIGNMENT_VIEW_START
        field.inputType = AInputType.TYPE_CLASS_TEXT | AInputType.TYPE_TEXT_FLAG_CAP_WORDS
        body.addView(field, ALinearLayout.LayoutParams(-1, dp(n: 56)))
        func button(value: String, color: Int) -> TripleShotButton {
            let view = TripleShotButton()
            view.text = value
            view.textSize = 18
            view.isAllCaps = false
            view.gravity = AGravity.CENTER
            FamilySkyUi.button(button: view, colors: AColorStateList.valueOf(color))
            return view
        }
        let suggest = button(value: tr(en: "Suggest a fun nickname", heb: "הצעה לכינוי חמוד"), color: argbInt(0xffa6dcff))
        suggest.setOnClickListener { _ in
            field.setText(
                (he ? ["כוכב", "ניצוץ", "שמש", "ארנב", "קסם"] : ["Comet", "Sunny", "Bunny", "Spark", "Orbit"])
                    .kRandom(KotlinRandom.Default)
            )
        }
        let suggestParams = ALinearLayout.LayoutParams(-1, dp(n: 60))
        suggestParams.topMargin = dp(n: 16)
        body.addView(suggest, suggestParams)
        let actions = ALinearLayout()
        actions.orientation = ALinearLayout.HORIZONTAL
        let cancel = button(value: tr(en: "Cancel", heb: "ביטול"), color: argbInt(0xffe91e63))
        let accept = button(value: tr(en: "Continue", heb: "המשך"), color: FamilyMenu.PLAY)
        let cancelParams = ALinearLayout.LayoutParams(0, dp(n: 60), 1)
        cancelParams.marginEnd = dp(n: 8)
        actions.addView(cancel, cancelParams)
        let acceptParams = ALinearLayout.LayoutParams(0, dp(n: 60), 1)
        acceptParams.marginStart = dp(n: 8)
        actions.addView(accept, acceptParams)
        let actionsParams = ALinearLayout.LayoutParams(-1, -2)
        actionsParams.topMargin = dp(n: 24)
        body.addView(actions, actionsParams)
        let dialog = AAlertDialog.Builder(c).setView(body).create()
        // The dialog is held by its activity while shown; weak captures avoid a dialog -> view -> listener cycle.
        cancel.setOnClickListener { [weak dialog] _ in
            dialog?.dismiss()
        }
        accept.setOnClickListener { [weak dialog] _ in
            let value = field.text.ktrim()
            if !OnlineNickname.valid(value) {
                let error = tr(en: "Choose 1–5 letters; no spaces or numbers.", heb: "בחרו 1–5 אותיות, ללא רווחים או מספרים.")
                field.error = error
                // iOS only: VoiceOver hears the error like TalkBack does.
                UIAccessibility.post(notification: .announcement, argument: error)
                return
            }
            p.edit().putString("nickname", value).putBoolean("confirmed", true).apply()
            dialog?.dismiss()
            ready(value)
        }
        dialog.setOnShowListener { [weak dialog] _ in
            guard let dialog = dialog else { return }
            FamilyFormStyle.apply(v: body)
            FamilySkyUi.dialog(dialog: dialog)
            dialog.window?.setLayout(min(dp(n: 560), c.resources.displayMetrics.widthPixels - dp(n: 32)), -2)
        }
        dialog.show()
    }

    // MARK: Positional (Kotlin call-site) forms

    static func name(_ c: AContext) -> String {
        return name(c: c)
    }

    static func choose(_ c: AContext, _ always: Bool = false, _ ready: @escaping (String) -> Void) {
        choose(c: c, always: always, ready: ready)
    }
}
