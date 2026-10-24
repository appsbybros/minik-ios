import Foundation

// AndroidKit additions for the 6c38131 port of ui/TripleShotControls.kt (fork B):
// * ViewTreeObserver.addOnWindowFocusChangeListener (API 18): listeners kept per tree observer (weakly keyed).
//   `KitWindowFocusListeners.dispatch(observer, hasFocus)` delivers ViewTreeObserver.dispatchOnWindowFocusChange;
//   the window-focus owner (AActivity.setWindowFocus, a dialog window's focus change) must call it for the window's
//   decor view tree observer, as ViewRootImpl does on MSG_WINDOW_FOCUS_CHANGED.
// * android.view.inspector.WindowInspector.getGlobalWindowViews() (API 29): the root view of every window the app
//   shows, oldest first (each activity's decor view, then its showing dialogs' decor views).

/// ViewTreeObserver.OnWindowFocusChangeListener (identity-compared, like a Java listener object).
final class AOnWindowFocusChangeListener {
    let block: (Bool) -> Void
    init(_ block: @escaping (Bool) -> Void) { self.block = block }
    func onWindowFocusChanged(_ hasFocus: Bool) { block(hasFocus) }
}

enum KitWindowFocusListeners {
    private final class Entry {
        weak var observer: AViewTreeObserver?
        var listeners: [AOnWindowFocusChangeListener] = []
        init(_ observer: AViewTreeObserver) { self.observer = observer }
    }
    nonisolated(unsafe) private static var entries: [Entry] = []

    fileprivate static func add(_ observer: AViewTreeObserver, _ listener: AOnWindowFocusChangeListener) {
        entries.removeAll { $0.observer == nil }
        if let entry = entries.first(where: { $0.observer === observer }) {
            entry.listeners.append(listener)
        } else {
            let entry = Entry(observer)
            entry.listeners.append(listener)
            entries.append(entry)
        }
    }

    fileprivate static func remove(_ observer: AViewTreeObserver, _ listener: AOnWindowFocusChangeListener) {
        entries.first(where: { $0.observer === observer })?.listeners.removeAll { $0 === listener }
    }

    /// ViewTreeObserver.dispatchOnWindowFocusChange(hasFocus): every listener, in registration order (a copy, so
    /// listeners added meanwhile wait for the next change).
    static func dispatch(_ observer: AViewTreeObserver, _ hasFocus: Bool) {
        guard let entry = entries.first(where: { $0.observer === observer }) else { return }
        for listener in entry.listeners { listener.onWindowFocusChanged(hasFocus) }
    }
}

extension AViewTreeObserver {
    @discardableResult
    func addOnWindowFocusChangeListener(_ listener: AOnWindowFocusChangeListener) -> AOnWindowFocusChangeListener {
        if isAlive { KitWindowFocusListeners.add(self, listener) }
        return listener
    }

    /// Kotlin lambda form `addOnWindowFocusChangeListener { hasFocus -> ... }`.
    @discardableResult
    func addOnWindowFocusChangeListener(_ block: @escaping (Bool) -> Void) -> AOnWindowFocusChangeListener {
        addOnWindowFocusChangeListener(AOnWindowFocusChangeListener(block))
    }

    func removeOnWindowFocusChangeListener(_ listener: AOnWindowFocusChangeListener) {
        KitWindowFocusListeners.remove(self, listener)
    }
}

/// android.view.inspector.WindowInspector.
enum AWindowInspector {
    /// The root views of the app's windows: every activity's decor view, each followed by its showing dialogs'.
    static func getGlobalWindowViews() -> [AView] {
        var views: [AView] = []
        for activity in AActivityHost.shared?.activities ?? [] {
            views.append(activity.window.decorView)
            for dialog in activity.showingDialogs where dialog.isShowing {
                if let window = dialog.window { views.append(window.decorView) }
            }
        }
        return views
    }
}

// MARK: - android.text.style.AlignmentSpan and TextUtils.ellipsize (TripleShotGameFragment 6c38131)

/// android.text.style.AlignmentSpan: a ParagraphStyle naming the alignment of the paragraphs it covers.
/// ALayout applies it per paragraph (Layout.getParagraphAlignment / drawText: the last span over the line wins).
enum AAlignmentSpan {
    /// AlignmentSpan.Standard(align).
    final class Standard {
        private let mAlignment: ALayout.Alignment
        init(_ align: ALayout.Alignment) { mAlignment = align }
        func getAlignment() -> ALayout.Alignment { mAlignment }
    }
}

extension ATextUtils {
    /// TextUtils.ellipsize(text, paint, avail, where) for END (the only form the app uses; other positions fall back
    /// to END): the text when it fits; else the longest prefix whose width plus the ellipsis "…" fits, trailing spaces
    /// dropped (MeasuredParagraph.breakText), followed by "…"; "" when nothing fits. Widths are prefix advances of
    /// `paint` (whole grapheme clusters, so a surrogate pair is never split).
    static func ellipsize(_ text: String, _ paint: APaint, _ avail: Float, _ where_: TruncateAt) -> String {
        if paint.measureText(text) <= avail { return text }
        let ellipsis = getEllipsisString(where_ == .END_SMALL ? .END_SMALL : .END)
        let room = avail - paint.measureText(ellipsis)
        if room < 0 { return "" }
        var prefix = ""
        for character in text {
            let next = prefix + String(character)
            if paint.measureText(next) > room { break }
            prefix = next
        }
        while prefix.hasSuffix(" ") { prefix.removeLast() }
        if prefix.isEmpty { return "" }
        return prefix + ellipsis
    }
}
