import UIKit

// androidx.core.graphics.Insets, androidx.core.view.WindowInsetsCompat and the ViewCompat helpers the app uses
// (VIEW-API "Insets"). Values are Android pixels. AViewRoot builds the window insets from the host view's
// safeAreaInsets: status bar = top, navigation bar = bottom home-indicator area, display cutout = the notch sides
// (left/right in landscape; the top when the status bar is hidden), ime = the keyboard overlap at the bottom.
//
// NOTE (Swift): `WindowInsetsCompat.Type` cannot be a nested Swift type (`X.Type` always means the metatype), so
// the type masks are `AWindowInsetsCompat.Types.systemBars()` (nested enum), the top-level `AWindowInsetsCompatType`
// alias, or the same static functions directly on `AWindowInsetsCompat` (`AWindowInsetsCompat.systemBars()`).

/// androidx.core.graphics.Insets (immutable).
final class AInsets: Equatable, CustomStringConvertible {
    let left: Int
    let top: Int
    let right: Int
    let bottom: Int

    static let NONE = AInsets(0, 0, 0, 0)

    init(_ left: Int, _ top: Int, _ right: Int, _ bottom: Int) {
        self.left = left
        self.top = top
        self.right = right
        self.bottom = bottom
    }

    /// Insets.of(left, top, right, bottom): returns NONE for all-zero values.
    static func of(_ left: Int, _ top: Int, _ right: Int, _ bottom: Int) -> AInsets {
        if left == 0 && top == 0 && right == 0 && bottom == 0 { return NONE }
        return AInsets(left, top, right, bottom)
    }

    /// Insets.add / subtract / max / min (component-wise).
    static func add(_ a: AInsets, _ b: AInsets) -> AInsets {
        of(a.left + b.left, a.top + b.top, a.right + b.right, a.bottom + b.bottom)
    }
    static func subtract(_ a: AInsets, _ b: AInsets) -> AInsets {
        of(a.left - b.left, a.top - b.top, a.right - b.right, a.bottom - b.bottom)
    }
    static func max(_ a: AInsets, _ b: AInsets) -> AInsets {
        of(Swift.max(a.left, b.left), Swift.max(a.top, b.top), Swift.max(a.right, b.right), Swift.max(a.bottom, b.bottom))
    }
    static func min(_ a: AInsets, _ b: AInsets) -> AInsets {
        of(Swift.min(a.left, b.left), Swift.min(a.top, b.top), Swift.min(a.right, b.right), Swift.min(a.bottom, b.bottom))
    }

    static func == (a: AInsets, b: AInsets) -> Bool {
        a.left == b.left && a.top == b.top && a.right == b.right && a.bottom == b.bottom
    }

    var description: String { "Insets{left=\(left), top=\(top), right=\(right), bottom=\(bottom)}" }
}

/// WindowInsetsCompat.Type type masks (same bit values as androidx).
enum AWindowInsetsCompatTypes {
    static let FIRST = 1
    static let STATUS_BARS = 1
    static let NAVIGATION_BARS = 1 << 1
    static let CAPTION_BAR = 1 << 2
    static let IME = 1 << 3
    static let SYSTEM_GESTURES = 1 << 4
    static let MANDATORY_SYSTEM_GESTURES = 1 << 5
    static let TAPPABLE_ELEMENT = 1 << 6
    static let DISPLAY_CUTOUT = 1 << 7
    static let LAST = 1 << 8
    static let SIZE = 9

    static func statusBars() -> Int { STATUS_BARS }
    static func navigationBars() -> Int { NAVIGATION_BARS }
    static func captionBar() -> Int { CAPTION_BAR }
    static func ime() -> Int { IME }
    static func systemGestures() -> Int { SYSTEM_GESTURES }
    static func mandatorySystemGestures() -> Int { MANDATORY_SYSTEM_GESTURES }
    static func tappableElement() -> Int { TAPPABLE_ELEMENT }
    static func displayCutout() -> Int { DISPLAY_CUTOUT }
    /// statusBars() | navigationBars() | captionBar().
    static func systemBars() -> Int { STATUS_BARS | NAVIGATION_BARS | CAPTION_BAR }

    static func indexOf(_ type: Int) -> Int {
        switch type {
        case STATUS_BARS: return 0
        case NAVIGATION_BARS: return 1
        case CAPTION_BAR: return 2
        case IME: return 3
        case SYSTEM_GESTURES: return 4
        case MANDATORY_SYSTEM_GESTURES: return 5
        case TAPPABLE_ELEMENT: return 6
        case DISPLAY_CUTOUT: return 7
        case LAST: return 8
        default: preconditionFailure("type needs to be >= FIRST and <= LAST, type=\(type)")
        }
    }
}

typealias AWindowInsetsCompatType = AWindowInsetsCompatTypes

/// androidx.core.view.WindowInsetsCompat (immutable value; CONSUMED has no insets and is consumed).
final class AWindowInsetsCompat: Equatable, CustomStringConvertible {
    typealias Types = AWindowInsetsCompatTypes

    // Type masks directly on the class (Kotlin `WindowInsetsCompat.Type.systemBars()`).
    static func statusBars() -> Int { Types.statusBars() }
    static func navigationBars() -> Int { Types.navigationBars() }
    static func captionBar() -> Int { Types.captionBar() }
    static func ime() -> Int { Types.ime() }
    static func systemGestures() -> Int { Types.systemGestures() }
    static func mandatorySystemGestures() -> Int { Types.mandatorySystemGestures() }
    static func tappableElement() -> Int { Types.tappableElement() }
    static func displayCutout() -> Int { Types.displayCutout() }
    static func systemBars() -> Int { Types.systemBars() }

    /// Insets per type index (see Types.indexOf), visible and "ignoring visibility" variants.
    private let typeInsets: [AInsets]
    private let typeMaxInsets: [AInsets]
    private let visibleTypes: Int
    let isConsumed: Bool

    static let CONSUMED = AWindowInsetsCompat(
        typeInsets: [AInsets](repeating: AInsets.NONE, count: Types.SIZE),
        typeMaxInsets: [AInsets](repeating: AInsets.NONE, count: Types.SIZE),
        visibleTypes: 0, consumed: true)

    init(typeInsets: [AInsets], typeMaxInsets: [AInsets], visibleTypes: Int, consumed: Bool = false) {
        precondition(typeInsets.count == Types.SIZE && typeMaxInsets.count == Types.SIZE)
        self.typeInsets = typeInsets
        self.typeMaxInsets = typeMaxInsets
        self.visibleTypes = visibleTypes
        self.isConsumed = consumed
    }

    /// WindowInsetsCompat(WindowInsetsCompat) copy constructor.
    convenience init(_ other: AWindowInsetsCompat?) {
        if let o = other {
            self.init(typeInsets: o.typeInsets, typeMaxInsets: o.typeMaxInsets, visibleTypes: o.visibleTypes,
                      consumed: o.isConsumed)
        } else {
            self.init(typeInsets: [AInsets](repeating: AInsets.NONE, count: Types.SIZE),
                      typeMaxInsets: [AInsets](repeating: AInsets.NONE, count: Types.SIZE), visibleTypes: 0)
        }
    }

    /// getInsets(typeMask): the maximum per side over the visible types of the mask.
    func getInsets(_ typeMask: Int) -> AInsets {
        var result = AInsets.NONE
        var i = Types.FIRST
        while i <= Types.LAST {
            if (typeMask & i) != 0 && (visibleTypes & i) != 0 {
                result = AInsets.max(result, typeInsets[Types.indexOf(i)])
            }
            i = i << 1
        }
        return result
    }

    /// getInsetsIgnoringVisibility(typeMask) (IME is not allowed, as androidx).
    func getInsetsIgnoringVisibility(_ typeMask: Int) -> AInsets {
        precondition((typeMask & Types.IME) == 0, "Unable to query the maximum insets for IME")
        var result = AInsets.NONE
        var i = Types.FIRST
        while i <= Types.LAST {
            if (typeMask & i) != 0 {
                result = AInsets.max(result, typeMaxInsets[Types.indexOf(i)])
            }
            i = i << 1
        }
        return result
    }

    func isVisible(_ typeMask: Int) -> Bool {
        var i = Types.FIRST
        while i <= Types.LAST {
            if (typeMask & i) != 0 && (visibleTypes & i) == 0 { return false }
            i = i << 1
        }
        return true
    }

    // Legacy "system window" insets: systemBars | ime (Impl30 semantics).
    var systemWindowInsets: AInsets { getInsets(Types.systemBars() | Types.ime()) }
    var systemWindowInsetLeft: Int { systemWindowInsets.left }
    var systemWindowInsetTop: Int { systemWindowInsets.top }
    var systemWindowInsetRight: Int { systemWindowInsets.right }
    var systemWindowInsetBottom: Int { systemWindowInsets.bottom }
    func hasSystemWindowInsets() -> Bool { systemWindowInsets != AInsets.NONE }
    func hasInsets() -> Bool {
        var i = Types.FIRST
        while i <= Types.LAST {
            if typeInsets[Types.indexOf(i)] != AInsets.NONE { return true }
            i = i << 1
        }
        return false
    }

    /// consumeSystemWindowInsets(): the insets with the system window insets removed. Like Android this alone
    /// does not make the insets "consumed" (stable insets and the cutout are still there), so children of a
    /// ViewGroup keep receiving them; only CONSUMED stops the dispatch.
    func consumeSystemWindowInsets() -> AWindowInsetsCompat {
        var t = typeInsets
        for type in [Types.STATUS_BARS, Types.NAVIGATION_BARS, Types.CAPTION_BAR, Types.IME] {
            t[Types.indexOf(type)] = AInsets.NONE
        }
        return AWindowInsetsCompat(typeInsets: t, typeMaxInsets: typeMaxInsets, visibleTypes: visibleTypes,
                                   consumed: isConsumed)
    }

    /// inset(left, top, right, bottom): every type's insets reduced (clamped at 0), as WindowInsets.inset.
    func inset(_ left: Int, _ top: Int, _ right: Int, _ bottom: Int) -> AWindowInsetsCompat {
        func shrink(_ a: AInsets) -> AInsets {
            AInsets.of(Swift.max(0, a.left - left), Swift.max(0, a.top - top), Swift.max(0, a.right - right),
                       Swift.max(0, a.bottom - bottom))
        }
        return AWindowInsetsCompat(typeInsets: typeInsets.map(shrink), typeMaxInsets: typeMaxInsets.map(shrink),
                                   visibleTypes: visibleTypes, consumed: isConsumed)
    }

    func inset(_ insets: AInsets) -> AWindowInsetsCompat {
        inset(insets.left, insets.top, insets.right, insets.bottom)
    }

    static func == (a: AWindowInsetsCompat, b: AWindowInsetsCompat) -> Bool {
        a.isConsumed == b.isConsumed && a.visibleTypes == b.visibleTypes && a.typeInsets == b.typeInsets
            && a.typeMaxInsets == b.typeMaxInsets
    }

    var description: String {
        "WindowInsetsCompat{systemBars=\(getInsets(Types.systemBars())), cutout=\(getInsets(Types.displayCutout())), ime=\(getInsets(Types.ime())), consumed=\(isConsumed)}"
    }

    /// WindowInsetsCompat.Builder.
    final class Builder {
        private var typeInsets = [AInsets](repeating: AInsets.NONE, count: Types.SIZE)
        private var typeMaxInsets = [AInsets](repeating: AInsets.NONE, count: Types.SIZE)
        private var visibleTypes = Types.STATUS_BARS | Types.NAVIGATION_BARS | Types.CAPTION_BAR | Types.SYSTEM_GESTURES
            | Types.MANDATORY_SYSTEM_GESTURES | Types.TAPPABLE_ELEMENT | Types.DISPLAY_CUTOUT

        init() {}
        init(_ insets: AWindowInsetsCompat) {
            typeInsets = insets.typeInsets
            typeMaxInsets = insets.typeMaxInsets
            visibleTypes = insets.visibleTypes
        }
        @discardableResult
        func setInsets(_ typeMask: Int, _ insets: AInsets) -> Builder {
            var i = Types.FIRST
            while i <= Types.LAST {
                if (typeMask & i) != 0 { typeInsets[Types.indexOf(i)] = insets }
                i = i << 1
            }
            return self
        }
        @discardableResult
        func setInsetsIgnoringVisibility(_ typeMask: Int, _ insets: AInsets) -> Builder {
            var i = Types.FIRST
            while i <= Types.LAST {
                if (typeMask & i) != 0 { typeMaxInsets[Types.indexOf(i)] = insets }
                i = i << 1
            }
            return self
        }
        @discardableResult
        func setVisible(_ typeMask: Int, _ visible: Bool) -> Builder {
            if visible { visibleTypes |= typeMask } else { visibleTypes &= ~typeMask }
            return self
        }
        func build() -> AWindowInsetsCompat {
            AWindowInsetsCompat(typeInsets: typeInsets, typeMaxInsets: typeMaxInsets, visibleTypes: visibleTypes)
        }
    }

    /// The window insets of an AViewRoot host (all values in px). A hidden bar (WindowInsetsControllerCompat.hide)
    /// is not visible: getInsets returns 0 for it, getInsetsIgnoringVisibility its size, as on Android.
    static func fromSafeArea(left: Int, top: Int, right: Int, bottom: Int, statusBarVisible: Bool,
                             navigationBarVisible: Bool = true, imeBottom: Int) -> AWindowInsetsCompat {
        let b = Builder()
        let status = AInsets.of(0, statusBarVisible ? top : 0, 0, 0)
        let nav = AInsets.of(0, 0, 0, bottom)
        let cutout = AInsets.of(left, statusBarVisible ? 0 : top, right, 0)
        let all = AInsets.of(left, top, right, bottom)
        b.setInsets(Types.STATUS_BARS, status)
        b.setInsets(Types.NAVIGATION_BARS, navigationBarVisible ? nav : AInsets.NONE)
        b.setInsets(Types.CAPTION_BAR, AInsets.NONE)
        b.setInsets(Types.TAPPABLE_ELEMENT, AInsets.of(0, status.top, 0, navigationBarVisible ? bottom : 0))
        b.setInsets(Types.SYSTEM_GESTURES, all)
        b.setInsets(Types.MANDATORY_SYSTEM_GESTURES, nav)
        b.setInsets(Types.DISPLAY_CUTOUT, cutout)
        b.setInsets(Types.IME, AInsets.of(0, 0, 0, imeBottom))
        b.setInsetsIgnoringVisibility(Types.STATUS_BARS, AInsets.of(0, top, 0, 0))
        b.setInsetsIgnoringVisibility(Types.NAVIGATION_BARS, nav)
        b.setInsetsIgnoringVisibility(Types.TAPPABLE_ELEMENT, AInsets.of(0, top, 0, bottom))
        b.setInsetsIgnoringVisibility(Types.SYSTEM_GESTURES, all)
        b.setInsetsIgnoringVisibility(Types.MANDATORY_SYSTEM_GESTURES, nav)
        b.setInsetsIgnoringVisibility(Types.DISPLAY_CUTOUT, cutout)
        b.setVisible(Types.STATUS_BARS, statusBarVisible)
        b.setVisible(Types.NAVIGATION_BARS, navigationBarVisible)
        b.setVisible(Types.IME, imeBottom > 0)
        return b.build()
    }
}

/// androidx.core.view.ViewCompat (the members the app uses, plus a few trivial helpers).
enum AViewCompat {
    /// ViewCompat.setOnApplyWindowInsetsListener: replaces the view's insets listener (nil removes it).
    static func setOnApplyWindowInsetsListener(_ v: AView, _ l: ((AView, AWindowInsetsCompat) -> AWindowInsetsCompat)?) {
        v.setOnApplyWindowInsetsListener(l)
    }

    /// ViewCompat.requestApplyInsets: asks the window to dispatch insets again on the next traversal.
    static func requestApplyInsets(_ v: AView) {
        v.requestApplyInsets()
    }

    /// ViewCompat.dispatchApplyWindowInsets.
    @discardableResult
    static func dispatchApplyWindowInsets(_ v: AView, _ insets: AWindowInsetsCompat) -> AWindowInsetsCompat {
        v.dispatchApplyWindowInsets(insets)
    }

    /// ViewCompat.onApplyWindowInsets.
    static func onApplyWindowInsets(_ v: AView, _ insets: AWindowInsetsCompat) -> AWindowInsetsCompat {
        v.onApplyWindowInsets(insets)
    }

    /// ViewCompat.getRootWindowInsets: the last insets dispatched to the view's window (nil when detached).
    static func getRootWindowInsets(_ v: AView) -> AWindowInsetsCompat? {
        v.rootWindowInsets
    }

    static func getLayoutDirection(_ v: AView) -> Int { v.layoutDirection }
    static func setLayoutDirection(_ v: AView, _ layoutDirection: Int) { v.layoutDirection = layoutDirection }
    static func isAttachedToWindow(_ v: AView) -> Bool { v.isAttachedToWindow }
    static func isLaidOut(_ v: AView) -> Bool { v.isLaidOut }
    static func setElevation(_ v: AView, _ elevation: Float) { v.elevation = elevation }
    static func getElevation(_ v: AView) -> Float { v.elevation }
    static func setTranslationZ(_ v: AView, _ translationZ: Float) { v.translationZ = translationZ }
    static func postOnAnimation(_ v: AView, _ r: ARunnable) { v.postOnAnimation(r) }
    static func postInvalidateOnAnimation(_ v: AView) { v.postInvalidateOnAnimation() }
    static func generateViewId() -> Int { AView.generateViewId() }
}
