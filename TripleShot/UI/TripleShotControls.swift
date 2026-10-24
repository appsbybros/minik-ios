import Foundation

/// Port of `ui/TripleShotControls.kt` (Android 6c38131), statement by statement.
///
/// Local navigation styling, including dynamically opened dialogs and older XML screens.
/// Swift API: the Kotlin parameter names are the labels (DESIGN 2.1); the unlabelled forms forward to them.
enum TripleShotControls {
    private static let watched = FamilyWeakHashMap<AView, Bool>()
    private static let placed = FamilyWeakHashMap<AButton, Bool>()
    private static func placeClose(button: AButton) {
        if placed.containsKey(button) || (button.getTag() as? String) == "fixed-close" { return }
        var node: AView? = button
        while let current = node { if (current.getTag() as? String) == "game-controls" { return }; node = current.parentGroup }
        guard var parent: AViewGroup = button.parentGroup else { return }
        while let linear = parent as? ALinearLayout, linear.orientation != ALinearLayout.VERTICAL {
            guard let up = linear.parentGroup else { return }
            parent = up
        }
        guard let column = parent as? ALinearLayout else { return }
        if column.orientation != ALinearLayout.VERTICAL { return }
        placed.put(button, true)
        button.post {
            guard let old = button.parentGroup else { return }
            old.removeView(button)
            if let oldRow = old as? ALinearLayout, oldRow.orientation == ALinearLayout.HORIZONTAL {
                // `old.getChildAt(i).javaClass == View::class.java`: plain View spacers only (not subclasses).
                for i in kdownTo(oldRow.childCount - 1, 0) { if type(of: oldRow.getChildAt(i)!) == AView.self { oldRow.removeViewAt(i) } }
            }
            let d = AResources.displayMetrics.density
            let row = ALinearLayout(); row.gravity = AGravity.END | AGravity.CENTER_VERTICAL; row.setPadding((12 * d).toInt(), ((19 * d).toInt() - column.paddingTop).coerceAtLeast(0), (12 * d).toInt(), (8 * d).toInt())
            row.addView(button, ALinearLayout.LayoutParams((52 * d).toInt(), (52 * d).toInt()))
            column.addView(row, 0, ALinearLayout.LayoutParams(-1, -2))
        }
    }
    static func watch(root: AView) {
        // `watched.put(root, true) == true`: the previous value.
        let previous = watched.get(root)
        watched.put(root, true)
        if previous == true { return }
        // Build.VERSION.SDK_INT >= 29 (always on iOS): re-watch every app window when this window's focus changes
        // (a dialog opens or closes over it).
        root.viewTreeObserver.addOnWindowFocusChangeListener { [weak root] _ in
            root?.post { AWindowInspector.getGlobalWindowViews().forEach { watch(root: $0) } }
        }
        func visit(view: AView) {
            if let input = view as? ATextInputLayout {
                if input.boxBackgroundMode != ATextInputLayout.BOX_BACKGROUND_NONE {
                    input.boxBackgroundColor = AColor.WHITE
                }
            }
            if let edit = view as? AEditText {
                edit.gravity = AGravity.START | AGravity.CENTER_VERTICAL
                edit.textAlignment = AView.TEXT_ALIGNMENT_VIEW_START
            }
            if let button = view as? AButton {
                let title = button.text.ktrim()
                if ["Cancel", "ביטול", "Exit game", "יציאה מהמשחק", "Back to game", "חזרה למשחק"].contains(title) {
                    let color = AColorStateList.valueOf(argbInt(0xffe91e63))
                    if (button.background as? FamilySkyDrawable)?.sourceColors()?.defaultColor != color.defaultColor {
                        FamilySkyUi.button(button: button, colors: color)
                    }
                    button.setTextColor(AColor.WHITE)
                }
                let kind: String?
                switch title {
                case "Back", "חזרה", "Back to table", "חזרה לטבלה", "Exit", "יציאה", "\u{2039}", "\u{203A}", "\u{2190}", "\u{2192}", "\u{27F5}", "\u{27F6}": kind = "close"
                case "Pause", "השהיה": kind = "pause"
                case "Help", "עזרה": kind = "help"
                default: kind = nil
                }
                if let kind = kind {
                    // `contentDescription?.toString()?.takeIf { it.isNotBlank() } ?: title`
                    let description = button.contentDescription
                    icon(button: button, kind: kind, label: description != nil && !description!.kotlinIsBlank ? description! : title)
                    if kind == "close" { placeClose(button: button) }
                }
            }
            if let group = view as? AViewGroup { for i in kuntil(0, group.childCount) { visit(view: group.getChildAt(i)!) } }
        }
        root.viewTreeObserver.addOnGlobalLayoutListener(AOnGlobalLayoutListener { [weak root] in if let root = root { visit(view: root) } })
        root.post { [weak root] in if let root = root { visit(view: root) } }
    }
    static func watch(_ root: AView) { watch(root: root) }

    static func icon(button: AButton, kind: String, label: String) {
        let d = AResources.displayMetrics.density
        let resource: ADrawableRes
        switch kind { case "close": resource = R.drawable.triple_close; case "pause": resource = R.drawable.triple_pause; case "play": resource = R.drawable.triple_play; default: resource = R.drawable.triple_help }
        button.contentDescription = label; button.text = ""; button.minWidth = 0; button.minimumWidth = 0
        button.minimumHeight = (48 * d).toInt(); button.setPadding((8 * d).toInt(), (8 * d).toInt(), (8 * d).toInt(), (8 * d).toInt())
        if button.isMaterialButton {
            button.iconTint = nil; button.iconSize = (36 * d).toInt(); button.iconPadding = 0
            button.iconGravity = AButton.ICON_GRAVITY_TEXT_START; button.setIconResource(resource)
            button.backgroundTintList = AColorStateList.valueOf(AColor.TRANSPARENT)
            button.insetTop = 0; button.insetBottom = 0; button.strokeWidth = 0
        } else {
            button.background = AInsetDrawable(ContextCompat_getDrawable(resource), (7 * d).toInt())
        }
        if let lp = button.layoutParams {
            lp.width = (52 * d).toInt(); lp.height = (52 * d).toInt()
            if let linear = lp as? ALinearLayout.LayoutParams { linear.weight = 0; linear.marginStart = (6 * d).toInt(); linear.marginEnd = (6 * d).toInt() }
            button.layoutParams = lp
        }
    }
    static func icon(_ button: AButton, _ kind: String, _ label: String) { icon(button: button, kind: kind, label: label) }
}
