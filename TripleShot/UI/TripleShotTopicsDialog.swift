import Foundation

// Port of ui/TripleShotTopicsDialog.kt (Android 6c38131), statement by statement: the topic chooser of the main menu
// (it replaces the earlier MaterialAlertDialog multi-choice list). A plain android.app.Dialog with a transparent window
// and a code-built dark gradient panel: title, a "Select all" row, one CheckBox per topic in a ScrollView whose height
// follows the screen, then Cancel / Apply. Hebrew texts and an RTL panel only when the first device language is he/iw.
// The pending set keeps Kotlin's LinkedHashSet order (`selected.intersect(available)`, then additions at the end).
// The dialog's own views reach the dialog and the check boxes weakly (Android's GC collects those cycles, ARC would not).

/** Pending choices stay local until Apply; cancelling never changes the active topics. */
enum TripleShotTopicsDialog {
    private final class WeakBox<T: AnyObject> {
        weak var value: T?
        init(_ value: T) { self.value = value }
    }

    static func show(c: AContext, title: String, selected: KLinkedSet<QuestionCategory>,
                     available: [QuestionCategory] = QuestionCategory.allCases,
                     apply: @escaping (KLinkedSet<QuestionCategory>) -> Void) {
        let he = ["he", "iw"].contains(c.resources.configuration.locales[0].language)
        func tr(en: String, h: String) -> String { return he ? h : en }
        func dp(n: Int) -> Int { return (n.toFloat() * c.resources.displayMetrics.density + Float(0.5)).toInt() }
        // `selected.intersect(available.toSet()).toMutableSet()`: the selected order, only available topics.
        let availableSet = Set(available)
        let pending = KRef(KLinkedSet(selected.elements.filter { availableSet.contains($0) }))
        let dialog = ADialog(c)
        let body = ALinearLayout()
        body.orientation = ALinearLayout.VERTICAL; body.setPadding(dp(n: 22), dp(n: 22), dp(n: 22), dp(n: 24))
        body.layoutDirection = he ? AView.LAYOUT_DIRECTION_RTL : AView.LAYOUT_DIRECTION_LTR
        let panel = AGradientDrawable(AGradientDrawable.Orientation.TOP_BOTTOM, [argbInt(0xff233b60), argbInt(0xff132841)])
        panel.cornerRadius = dp(n: 26).toFloat(); panel.setStroke(dp(n: 1), argbInt(0xff6588ad))
        body.background = panel
        let heading = ATextView()
        heading.text = title; heading.textSize = 23; heading.setTextColor(AColor.WHITE); heading.setTypeface(heading.typeface, ATypeface.BOLD); heading.gravity = AGravity.CENTER
        let headingLp = ALinearLayout.LayoutParams(-1, -2); headingLp.bottomMargin = dp(n: 16)
        body.addView(heading, headingLp)
        var checks: [WeakBox<ACheckBox>] = []
        let all = ATextView()
        all.text = tr(en: "Select all", h: "בחירת הכול"); all.textSize = 18; all.setTextColor(AColor.WHITE); all.setTypeface(all.typeface, ATypeface.BOLD)
        all.minHeight = dp(n: 48); all.gravity = AGravity.START | AGravity.CENTER_VERTICAL; all.setPadding(dp(n: 8), 0, dp(n: 8), 0)
        all.isClickable = true; all.isFocusable = true
        body.addView(all)
        let choices = ALinearLayout(); choices.orientation = ALinearLayout.VERTICAL
        let scroll = AScrollView(); scroll.isFillViewport = false; scroll.addView(choices)
        for category in available {
            let check = ACheckBox()
            check.text = category.labelFor(languageCode: he ? "he" : "en"); check.textSize = 18; check.setTextColor(AColor.WHITE); check.minHeight = dp(n: 52)
            check.gravity = AGravity.START | AGravity.CENTER_VERTICAL; check.textAlignment = AView.TEXT_ALIGNMENT_VIEW_START
            check.buttonTintList = AColorStateList.valueOf(argbInt(0xff9ad9ff)); check.setPadding(dp(n: 6), dp(n: 4), dp(n: 6), dp(n: 4))
            check.isChecked = pending.value.contains(category)
            check.setOnCheckedChangeListener { _, checked in
                if checked { pending.value.add(category) } else { pending.value.remove(category) }
            }
            checks.append(WeakBox(check))
            let lp = ALinearLayout.LayoutParams(-1, -2); lp.bottomMargin = dp(n: 4)
            choices.addView(check, lp)
        }
        let boxes = checks
        all.setOnClickListener { _ in for box in boxes { box.value?.isChecked = true } }
        let maxList = (c.resources.displayMetrics.heightPixels - dp(n: 290)).coerceAtLeast(dp(n: 100)).coerceAtMost(dp(n: 460))
        let scrollLp = ALinearLayout.LayoutParams(-1, maxList); scrollLp.topMargin = dp(n: 8); scrollLp.bottomMargin = dp(n: 20)
        body.addView(scroll, scrollLp)
        let actions = ALinearLayout(); actions.gravity = AGravity.CENTER
        func button(label: String, color: Int) -> TripleShotButton {
            let b = TripleShotButton()
            b.text = label; b.isAllCaps = false; b.textSize = 18; b.minHeight = dp(n: 56); b.setPadding(dp(n: 18), dp(n: 12), dp(n: 18), dp(n: 12))
            FamilyMenu.style(v: b, color: color)
            return b
        }
        let cancel = button(label: tr(en: "Cancel", h: "ביטול"), color: argbInt(0xffe91e63))
        cancel.setOnClickListener { [weak dialog] _ in dialog?.dismiss() }
        let accept = button(label: tr(en: "Apply", h: "אישור"), color: FamilyMenu.PLAY)
        accept.setOnClickListener { [weak dialog] _ in
            if pending.value.isEmpty {
                AToast.makeText(c, tr(en: "Choose at least one topic", h: "בחרו לפחות נושא אחד"), AToast.LENGTH_SHORT).show()
            } else {
                // `apply(pending.toSet())`: a copy (KLinkedSet is a value type).
                apply(pending.value); dialog?.dismiss()
            }
        }
        let cancelLp = ALinearLayout.LayoutParams(0, -2, 1); cancelLp.marginEnd = dp(n: 8)
        actions.addView(cancel, cancelLp)
        let acceptLp = ALinearLayout.LayoutParams(0, -2, 1); acceptLp.marginStart = dp(n: 8)
        actions.addView(accept, acceptLp)
        body.addView(actions, ALinearLayout.LayoutParams(-1, -2))
        dialog.setContentView(body); dialog.window?.setBackgroundDrawableResource(android.R.color.transparent)
        dialog.show(); dialog.window?.setLayout(min(dp(n: 540), c.resources.displayMetrics.widthPixels - dp(n: 32)), -2)
    }
}
