import Foundation

/// Port of MinikFamilyServices `FamilyMenu.java` (family snapshot 2f75e98), statement by statement.
///
/// Consistent, accessible menu sections; the host explicitly assigns actions to groups.
/// Java `view.getContext()` is `FamilyBridge.context(view)` (AndroidKit views carry no context; it is the hosting
/// activity, which is what the Java code tests with `instanceof Activity`).
/// Swift API: the Java parameter names are the labels (DESIGN 2.1); the unlabelled forms forward to them.
enum FamilyMenu {
    static let LEARN = argbInt(0xffb8d9ff), PLAY = argbInt(0xffb9f4dc), SAVED = argbInt(0xffe8dcff), ADVANCED = argbInt(0xffffe082), LINK = argbInt(0xff2869bd), INK = argbInt(0xff282d4e)
    /// Java `dp(Context, int)`: `Math.round(n * density)`.
    private static func dp(_ n: Int) -> Int { return (Float(n) * AResources.displayMetrics.density).roundToInt() }

    /// Appends a collapsible panel to `parent` and returns its body. The open state is kept in the preferences
    /// "family_menu_sections" under the (localized) title; a tap on the heading toggles it, without animation.
    static func section(parent: ALinearLayout, title: String, expanded: Bool, color: Int) -> ALinearLayout {
        let c = FamilyBridge.context(parent); if let a = c { FamilyFormStyle.watch(a: a) }; let light = (parent.getTag() as? String) == "family-menu-light"; _ = light // unused here, as in Java
        let box = ALinearLayout(); box.orientation = ALinearLayout.VERTICAL; box.setPadding(dp(10), dp(4), dp(10), dp(4))
        let border: AGradientDrawable = FamilySkyDrawable(panel: true); border.setColor(color); border.setCornerRadius(Float(dp(18))); border.setStroke(dp(2), color); box.background = border
        let bp = ALinearLayout.LayoutParams(-1, -2); bp.bottomMargin = dp(14); parent.addView(box, bp)
        let heading = ALinearLayout(); heading.setGravity(AGravity.CENTER_VERTICAL); heading.minimumHeight = dp(54); heading.setPaddingRelative(dp(6), dp(4), dp(6), dp(4)); heading.isClickable = true; heading.isFocusable = true
        let name = ATextView(); name.setText(title); name.setTextColor(INK); name.setTextSize(19); name.setTypeface(nil, ATypeface.BOLD)
        let sign = ATextView(); sign.setTextColor(INK); sign.setTextSize(26); sign.setGravity(AGravity.CENTER); sign.importantForAccessibility = AView.IMPORTANT_FOR_ACCESSIBILITY_NO
        heading.addView(name, ALinearLayout.LayoutParams(0, -2, 1)); heading.addView(sign, ALinearLayout.LayoutParams(dp(42), dp(48))); box.addView(heading)
        let body = ALinearLayout(); body.orientation = ALinearLayout.VERTICAL; body.setTag(color); box.addView(body, ALinearLayout.LayoutParams(-1, -2))
        let prefs = getSharedPreferences("family_menu_sections", 0); let key = title; let open = prefs.getBoolean(key, expanded)
        body.visibility = open ? AView.VISIBLE : AView.GONE; sign.setText(open ? "\u{2212}" : "+"); heading.contentDescription = title + (open ? ", \u{2212}" : ", +")
        // The listener reaches the heading through its argument (the heading itself), so the heading does not retain itself.
        heading.setOnClickListener { heading in
            let show = body.visibility != AView.VISIBLE; body.visibility = show ? AView.VISIBLE : AView.GONE; sign.setText(show ? "\u{2212}" : "+")
            heading.contentDescription = title + (show ? ", \u{2212}" : ", +"); prefs.edit().putBoolean(key, show).apply()
        }
        FamilyMoreFrame.installFor(content: parent)
        return body
    }
    static func section(_ parent: ALinearLayout, _ title: String, _ expanded: Bool, _ color: Int) -> ALinearLayout {
        return section(parent: parent, title: title, expanded: expanded, color: color)
    }

    static func style(v: AView, color: Int) {
        guard let t = v as? ATextView else { return }; t.setTextColor(INK); t.setBackgroundTintList(nil)
        // Java also clears the AppCompat support background tint by reflection: an AndroidKit view keeps one tint.
        let shape: AGradientDrawable = FamilySkyDrawable(); shape.setColor(color); shape.setCornerRadius(Float(dp(15))); t.background = shape
        if let b = t as? AButton { FamilyButtonAlignment.bind(button: b) }
    }
    static func style(_ v: AView, _ color: Int) { style(v: v, color: color) }

    static func link(t: ATextView) {
        t.setTextColor(LINK); t.setBackgroundTintList(nil); t.setTypeface(nil, ATypeface.BOLD); t.setTextSize(17)
        t.minimumHeight = dp(48); t.setGravity(AGravity.CENTER)
        t.setPadding(dp(12), dp(8), dp(12), dp(8))
        // The same quiet backing protects both links from bright scenery, without
        // button elevation, a colored action fill or a blurred text shadow.
        let backing = AGradientDrawable(); backing.setColor(argbInt(0xeef7fbff)); backing.setCornerRadius(Float(dp(8))); t.background = backing
        t.setShadowLayer(0, 0, 0, AColor.TRANSPARENT); t.setPaintFlags(t.paintFlags | APaint.UNDERLINE_TEXT_FLAG)
    }
    static func link(_ t: ATextView) { link(t: t) }

    /// Reparent existing actions without replacing listeners or their saved state. Labels are supplied by each host.
    /// (Not called by Triple Shot; ported with the class.)
    static func organize(root: ALinearLayout, titles: [String], labels: [[String]], profile: [AView], more: String, parents: String) {
        var original: [AView] = []; var i = 0; while i < root.childCount { original.append(root.getChildAt(i)!); i += 1 }
        var groups: [[AView]] = []; for _ in 0..<4 { groups.append([]) }
        var footer: ATextView? = nil, moreLink: ATextView? = nil
        for v in original {
            if let button = v as? AButton {
                let text = button.text
                if javaEquals(text, more) { moreLink = button; root.removeView(v); continue }
                if javaEquals(text, parents) { footer = button; root.removeView(v); continue }
                outer: for g in 0..<4 { for label in labels[g] { if javaEquals(text, label) || javaStartsWith(text, label + " (") { groups[g].append(v); root.removeView(v); break outer } } }
            }
        }
        // Tutorial/daily actions precede the profile fields, in the same section.
        for v in profile { if v.parentGroup === root { root.removeView(v); readableProfile(v); groups[0].append(v) } }
        if let moreLink = moreLink { groups[3].append(moreLink) }
        let colors = [LEARN, PLAY, SAVED, ADVANCED]
        for g in 0..<4 where !groups[g].isEmpty {
            let body = section(parent: root, title: titles[g], expanded: g < 2, color: colors[g])
            // The caller's explicit order, not translated alphabetical ordering.
            var ordered: [AView] = []
            for label in labels[g] {
                for v in groups[g] {
                    if let button = v as? AButton, javaEquals(button.text, label) || javaStartsWith(button.text, label + " (") {
                        if !ordered.contains(where: { $0 === v }) { ordered.append(v) }
                    }
                }
            }
            for v in groups[g] { if !ordered.contains(where: { $0 === v }) { ordered.append(v) } }
            for v in ordered {
                let lp = v.layoutParams as? ALinearLayout.LayoutParams ?? ALinearLayout.LayoutParams(-1, -2); lp.width = -1
                if v is AButton { lp.topMargin = dp(4); lp.bottomMargin = dp(8); style(v: v, color: colors[g]) }
                body.addView(v, lp)
            }
        }
        if let moreLink = moreLink { link(t: moreLink) }
        if let footer = footer { root.addView(footer, ALinearLayout.LayoutParams(-1, -2)); link(t: footer) }
    }
    static func organize(_ root: ALinearLayout, _ titles: [String], _ labels: [[String]], _ profile: [AView], _ more: String, _ parents: String) {
        organize(root: root, titles: titles, labels: labels, profile: profile, more: more, parents: parents)
    }

    private static func readableProfile(_ view: AView) {
        if let text = view as? ATextView, !(view is AButton) {
            let c = text.currentTextColor
            if (AColor.red(c) * 299 + AColor.green(c) * 587 + AColor.blue(c) * 114) / 1000 > 170 {
                text.setTextColor(INK); if let edit = text as? AEditText { edit.setHintTextColor(argbInt(0xff52677b)) }
            }
        }
        if let group = view as? AViewGroup { var i = 0; while i < group.childCount { readableProfile(group.getChildAt(i)!); i += 1 } }
    }

    /// Java `String.equals` / `startsWith`: UTF-16 code units, no Unicode normalisation (Swift `==` compares canonical
    /// equivalence).
    private static func javaEquals(_ a: String, _ b: String) -> Bool { return a.utf16.elementsEqual(b.utf16) }
    private static func javaStartsWith(_ s: String, _ prefix: String) -> Bool { return s.utf16.starts(with: prefix.utf16) }
}
