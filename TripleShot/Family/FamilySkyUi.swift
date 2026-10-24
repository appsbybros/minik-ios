import Foundation

/// Port of MinikFamilyServices `FamilySkyUi.java` (family snapshot 2f75e98), statement by statement.
///
/// Explicit native-view integration; never changes geometry or action listeners.
/// Swift API: the Java parameter names are the labels (DESIGN 2.1); the unlabelled forms forward to them.
enum FamilySkyUi {
    static func button(button: AButton, colors: AColorStateList?) {
        let left = button.paddingLeft, top = button.paddingTop, right = button.paddingRight, bottom = button.paddingBottom
        button.setBackgroundTintList(nil)
        // Java then calls `setSupportBackgroundTintList(null)` by reflection (ignored when the class has no such method).
        // For a MaterialButton it is the very call `setBackgroundTintList(null)` just made (AndroidKit's AButton keeps one
        // tint); a framework Button has no such method.
        let face = FamilySkyDrawable(); face.setColor(colors); face.setCornerRadius(18 * AResources.displayMetrics.density); button.background = face
        button.setPadding(left, top, right, bottom)
        FamilyButtonAlignment.bind(button: button)
    }
    static func button(_ button: AButton, _ colors: AColorStateList?) { self.button(button: button, colors: colors) }

    static func decorate(view: AView) {
        if let b = view as? AButton, !(view is ACompoundButton) {
            if b.getBackground() is FamilySkyDrawable { FamilyButtonAlignment.bind(button: b) }
            // Quiet text links stay links, including those implemented with Button for accessibility.
            if b.getBackground() != nil && !(b.getBackground() is FamilySkyDrawable) && (b.paintFlags & APaint.UNDERLINE_TEXT_FLAG) == 0 {
                var colors = b.getBackgroundTintList()
                // `colors == null && background instanceof GradientDrawable && SDK_INT >= 24` (always API 24+ here).
                if colors == nil, let gradient = b.getBackground() as? AGradientDrawable { colors = gradient.getColor() }
                if let colors = colors { button(button: b, colors: colors) }
            }
        }
        if let group = view as? AViewGroup { var i = 0; while i < group.childCount { decorate(view: group.getChildAt(i)!); i += 1 } }
    }
    static func decorate(_ view: AView) { decorate(view: view) }

    /// Host opts in for inflated/dynamically added Material controls. Only fresh backgrounds
    /// are decorated; checked/selected state and subsequent host color decisions are retained.
    /// (Registered on the root's observer: before the root is attached that is its floating observer, which AndroidKit
    /// merges into the window's on attach, as Android does.)
    static func watch(root: AView) {
        root.viewTreeObserver.addOnGlobalLayoutListener(AOnGlobalLayoutListener { [weak root] in
            guard let root = root else { return }
            decorate(view: root); FamilyFormStyle.apply(v: root)
        })
        root.post { [weak root] in
            guard let root = root else { return }
            decorate(view: root); FamilyFormStyle.apply(v: root)
        }
    }
    static func watch(_ root: AView) { watch(root: root) }

    static func dialog(dialog: AAlertDialog) {
        // `dialog.getWindow() == null` → return (typed optional so it reads the same whatever AndroidKit's nullability).
        let window: AWindow? = dialog.window
        guard let w = window else { return }
        FamilyFormStyle.apply(v: w.decorView)
        let density = AResources.displayMetrics.density
        let panel = FamilySkyDrawable(panel: true); panel.setColor(AColor.WHITE); panel.setCornerRadius(24 * density); w.setBackgroundDrawable(panel)
        for id in [-1, -2, -3] {
            let b: AButton? = dialog.getButton(id)
            if let b = b, !(b.getBackground() is FamilySkyDrawable) {
                button(button: b, colors: AColorStateList.valueOf(id == -2 ? argbInt(0xffffd4e6) : argbInt(0xffa6dcff)))
            }
        }
    }
    static func dialog(_ dialog: AAlertDialog) { self.dialog(dialog: dialog) }
}
