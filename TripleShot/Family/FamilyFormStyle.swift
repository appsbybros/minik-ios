import Foundation

/// Port of MinikFamilyServices `FamilyFormStyle.java` (family snapshot 2f75e98), statement by statement.
///
/// Restrained form fields; never changes values, listeners, selection or layout widths.
/// Swift API: the Java parameter names are the labels (DESIGN 2.1); the unlabelled forms forward to them.
enum FamilyFormStyle {
    private static let watched = FamilyWeakHashMap<AView, Bool>()
    private final class InputFace: AGradientDrawable {}

    static func apply(v: AView) {
        let d = AResources.displayMetrics.density
        if let b = v as? AButton, !(v is ACompoundButton), v.background is FamilySkyDrawable {
            FamilyButtonAlignment.bind(button: b)
        }
        if let e = v as? AEditText, !(v.background is InputFace) {
            let face = InputFace(); face.setColor(AColor.WHITE); face.setCornerRadius(8 * d)
            face.setStroke(max(1, d.roundToInt()), AColorStateList([[android.R.attr.state_focused], []], [argbInt(0xff2587d6), argbInt(0xff879baa)]))
            e.setBackgroundTintList(nil)
            // Java also clears the AppCompat support background tint by reflection: an AndroidKit view keeps one tint.
            e.background = face; e.setTextColor(argbInt(0xff17384d)); e.setHintTextColor(argbInt(0xff536b7b))
            e.setPadding(max(e.paddingLeft, (12 * d).roundToInt()), max(e.paddingTop, (8 * d).roundToInt()), max(e.paddingRight, (12 * d).roundToInt()), max(e.paddingBottom, (8 * d).roundToInt()))
            e.minimumHeight = max(e.minimumHeight, (48 * d).roundToInt())
        } else if v is ATextView && !(v is AButton) && !v.isClickable && v.background is FamilySkyDrawable {
            let old = v.background as! FamilySkyDrawable; let flat = AGradientDrawable(); flat.setColor(old.sourceColors()); flat.setCornerRadius(8 * d); v.background = flat
        }
        if let g = v as? AViewGroup { var i = 0; while i < g.childCount { apply(v: g.getChildAt(i)!); i += 1 } }
    }
    static func apply(_ v: AView) { apply(v: v) }

    static func watch(a: AActivity) {
        let root: AView = a.window.decorView; if watched.containsKey(root) { return }; watched.put(root, true)
        root.viewTreeObserver.addOnGlobalLayoutListener(AOnGlobalLayoutListener { [weak root] in if let root = root { apply(v: root) } })
        root.post { [weak root] in if let root = root { apply(v: root) } }
    }
    static func watch(_ a: AActivity) { watch(a: a) }
}

/// `java.util.WeakHashMap` as the family helpers and TripleShotControls use it (view keys, which Java compares by
/// identity since View does not override equals): keys are held weakly, values strongly, and an entry goes away with
/// its key.
final class FamilyWeakHashMap<K: AnyObject, V> {
    private final class Entry {
        weak var key: K?
        var value: V
        init(_ key: K, _ value: V) { self.key = key; self.value = value }
    }
    private var entries: [ObjectIdentifier: Entry] = [:]
    private var purgeAt = 64

    func get(_ key: K) -> V? { return live(key)?.value }
    func containsKey(_ key: K) -> Bool { return live(key) != nil }
    func put(_ key: K, _ value: V) {
        if let e = live(key) { e.value = value; return }
        entries[ObjectIdentifier(key)] = Entry(key, value)
        if entries.count >= purgeAt {
            entries = entries.filter { $0.value.key != nil }
            purgeAt = max(64, entries.count * 2)
        }
    }
    @discardableResult func remove(_ key: K) -> V? {
        guard let e = live(key) else { return nil }
        entries[ObjectIdentifier(key)] = nil
        return e.value
    }
    var size: Int { return entries.values.filter { $0.key != nil }.count }
    /// The entry of exactly this object (an identifier whose old key is gone may have been reused by a new object).
    private func live(_ key: K) -> Entry? {
        let id = ObjectIdentifier(key)
        guard let e = entries[id] else { return nil }
        if e.key === key { return e }
        entries[id] = nil
        return nil
    }
}
