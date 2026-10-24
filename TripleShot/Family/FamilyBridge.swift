import SwiftUI
import UIKit

/// Android-shaped entry points for the family services Triple Shot calls, on top of the shared iOS `Family/` module
/// (`FamilyMessages`, `FamilyCatalog`, `FamilyText`, `FamilyOverlay`), which ports MinikFamilyServices `FamilyMessages`,
/// `FamilyCatalog`, `FamilyMessagePolicy`, `FamilyText` and the `FamilyAdultGate` dialog (those names are the shared
/// module's, so they are not redeclared here). The catalogue excludes this app by its key (Info.plist
/// `MinikFamilyCatalogKey` = "tripleshot"), as Android excludes the package `com.appsbybros.minik.swish`. Triple Shot never
/// calls `FamilyMessages.setLanguage`, so the family copy follows the device language (`languageOverride` stays nil).
///
/// The card, the grown-up gate and the "No browser is available." note are the shared module's SwiftUI views
/// (`FamilyOverlay`). Android shows them as dialog windows above the activity; here one hosting controller above the
/// activities and their dialogs (below AndroidKit's toast layer) shows them. It takes touches only while the card, the
/// reminder or the gate is up. The app needs no other `FamilyOverlay` (the module would draw only the newest one).
///
/// Kotlin call site (BasketballJourneyActivity, Settings page, "More Minik apps & games"):
/// `FamilyMessages.get(this).showMoreApps(this) { approved -> FamilyAdultGate.open(this, approved) }` is
/// `FamilyBridge.showMoreApps(this) { approved in FamilyBridge.adultGate(this, approved) }`, or simply
/// `FamilyBridge.showMoreApps(this)` (the default gate is `FamilyAdultGate.open`).
enum FamilyBridge {
    // MARK: View.getContext()

    /// Java `view.getContext()` where the family code needs the hosting Activity (AndroidKit views carry no context):
    /// the activity whose window holds the view (its hierarchy root is the window's decor view), else the activity on
    /// top of the task, where Triple Shot builds its views (dialog windows included); nil before an activity exists.
    static func context(_ view: AView) -> AActivity? {
        guard let host = AActivityHost.shared else { return nil }
        let root = view.rootView
        for a in host.activities.reversed() where a.window.decorView === root { return a }
        return host.topActivity
    }

    // MARK: FamilyMessages.get(activity).showMoreApps(activity, gate)

    /// `FamilyMessages.get(a).showMoreApps(a, gate)`. `get(a)` watches the decor view with `FamilyFormStyle` and creates
    /// the singleton (cadence decode + save and the at-most-daily catalogue refresh happen on the first touch of
    /// `FamilyMessages.shared`, i.e. on the first tap, as on Android). `showMoreApps` returns false unless `ready(a)`:
    /// nothing showing, activity alive and focused (on Android an open gate dialog holds the window focus). Then a card for
    /// a weighted random other app is shown, or, with no eligible entry, the gate opens the directory. `gate` nil = the
    /// gate Triple Shot passes, `FamilyAdultGate.open` (`adultGate`).
    @discardableResult
    static func showMoreApps(a: AActivity, gate: FamilyGate? = nil) -> Bool {
        FamilyFormStyle.watch(a: a)
        return MainActor.assumeIsolated {
            let messages = FamilyMessages.shared
            if messages.isShowing || messages.gateRequest != nil || a.isFinishing || a.isDestroyed || !a.hasWindowFocus() { return false }
            install(a)
            let hostGate: FamilyGate = gate ?? { approved in FamilyBridge.adultGate(a: a, approved: approved) }
            let shown = messages.showMoreApps(gate: hostGate)
            if shown { watchEntitlement(a) }
            return shown
        }
    }
    @discardableResult
    static func showMoreApps(_ a: AActivity, _ gate: FamilyGate? = nil) -> Bool { return showMoreApps(a: a, gate: gate) }

    // MARK: FamilyAdultGate.open(activity, approved)

    /// Android `FamilyAdultGate.open(a, approved)`: "For a grown-up", "x × y = ?" with `x = 4 + nextInt(6)` and
    /// `y = 3 + nextInt(6)` (two unseeded `java.util.Random`, no reproducibility requirement), an LTR number field,
    /// Cancel / Continue; Continue runs `approved` after `Integer.parseInt(text.trim()) == x * y`, otherwise "Try again.";
    /// a tap outside cancels. Drawn by the shared module's `FamilyGateView` (light sky dialog) above the card.
    static func adultGate(a: AActivity, approved: @escaping () -> Void) {
        MainActor.assumeIsolated {
            let x = 4 + Int.random(in: 0..<6), y = 3 + Int.random(in: 0..<6)
            install(a)
            let messages = FamilyMessages.shared
            messages.gateAnswer = ""
            messages.gateError = false
            messages.gateRequest = FamilyGateRequest(x: x, y: y, approved: approved)
        }
    }
    static func adultGate(_ a: AActivity, _ approved: @escaping () -> Void) { adultGate(a: a, approved: approved) }

    // MARK: FamilyMessages.text(activity, en, he)

    /// Android `FamilyMessages.text(a, en, he)`: the shared family copy in the family language.
    static func text(a: AActivity, en: String, he: String) -> String { return text(language: language(a), en, he) }
    static func text(_ a: AActivity, _ en: String, _ he: String) -> String { return text(a: a, en: en, he: he) }

    /// The rule of `text` for a family language tag: `l = language.split("-")[0]`; "he" → Hebrew, else
    /// `FamilyText.get(l, en)` (es, ar, hi, nl, fr, de, ru, pt, uk, am), else English.
    static func text(language: String, _ en: String, _ he: String) -> String {
        let l = String(language.split(separator: "-", omittingEmptySubsequences: false).first ?? "")
        return l == "he" ? he : FamilyText.get(l, en)
    }

    /// Android `FamilyMessages.language(a)` without a `setLanguage` override (Triple Shot never sets one): the activity's
    /// first configuration locale as a language tag ("he-IL", "es-ES", ...); a tag starting with "iw" is Hebrew.
    static func language(_ a: AActivity) -> String {
        return language(tag: a.resources.configuration.getLocales().get(0).toLanguageTag())
    }

    static func language(tag l: String) -> String { return l.hasPrefix("iw") ? "he" : l }

    // MARK: Overlay host

    @MainActor private static var overlayHost: UIHostingController<FamilyOverlay>?
    @MainActor private static var overlayView: FamilyBridgeOverlayView?
    private static let main = AHandler(ALooper.getMainLooper())

    /// Puts the shared `FamilyOverlay` above the activities and their dialogs, just below AndroidKit's toast layer
    /// (Android shows the card and the gate as dialog windows on top of the activity window). Made once, then moved back
    /// to that place on every use, since activities started later are inserted there too.
    @MainActor private static func install(_ activity: AActivity) {
        let container: FamilyBridgeOverlayView
        if let existing = overlayView {
            container = existing
        } else {
            container = FamilyBridgeOverlayView(frame: UIScreen.main.bounds)
            container.backgroundColor = .clear
            container.autoresizingMask = [.flexibleWidth, .flexibleHeight]
            let host = UIHostingController(rootView: FamilyOverlay())
            host.view.backgroundColor = .clear
            host.view.isOpaque = false
            host.view.frame = container.bounds
            host.view.autoresizingMask = [.flexibleWidth, .flexibleHeight]
            container.addSubview(host.view)
            overlayHost = host
            overlayView = container
        }
        if let activityHost = AActivityHost.shared, let hostView = activityHost.viewIfLoaded {
            let joining = overlayHost.map { $0.parent !== activityHost } ?? false
            if joining, let host = overlayHost { activityHost.addChild(host) }
            container.frame = hostView.bounds
            hostView.insertSubview(container, belowSubview: activityHost.toastLayer)
            if joining, let host = overlayHost { host.didMove(toParent: activityHost) }
        } else if let window = activity.viewIfLoaded?.window {
            container.frame = window.bounds
            window.addSubview(container)
        }
    }

    /// Android `watchEntitlement` (FamilyMessages.show): every 500 ms while the card shows, dismiss it when its activity
    /// is finishing or destroyed (Triple Shot has no ad-free state: `adFree` is `() -> false`). The gate, a dialog window of
    /// the same Android activity, goes away with that activity too.
    private static func watchEntitlement(_ a: AActivity) {
        main.postDelayed({ [weak a] in
            MainActor.assumeIsolated {
                let messages = FamilyMessages.shared
                if messages.card == nil && messages.gateRequest == nil { return }
                if let a = a, !a.isDestroyed, !a.isFinishing { watchEntitlement(a); return }
                messages.cancelGate()
                messages.dismissCard()
            }
        }, 500)
    }
}

/// The window-level container of the shared `FamilyOverlay`. Touches fall through to the activity below unless a family
/// dialog (card, reminder, gate) is showing; the "No browser" note never takes touches, like an Android toast.
private final class FamilyBridgeOverlayView: UIView {
    override func hitTest(_ point: CGPoint, with event: UIEvent?) -> UIView? {
        let messages = FamilyMessages.shared
        guard messages.card != nil || messages.reminderVisible || messages.gateRequest != nil else { return nil }
        return super.hitTest(point, with: event)
    }
}
