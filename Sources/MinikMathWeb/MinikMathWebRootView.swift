#if MINIK_MATH_WEB
import SwiftUI
import UIKit

/// The small Minik Math: Android Minik Math (C:/Projects/minikMath) on iOS. Its web app runs
/// unchanged (MinikMathWebView); this root does what Android's host does around it: ads after
/// finished rounds on Android's schedule, the parents page behind a grown-up gate, landscape
/// for Ping Pong on phones, and hidden system bars.
@MainActor
struct MinikMathWebRootView: View {
    @Environment(\.scenePhase) private var phase
    @Environment(\.openURL) private var openURL
    @StateObject private var model = MinikMathWebModel()

    var body: some View {
        ZStack {
            (model.isPingPong ? MinikMathWebColors.pingPong : MinikMathWebColors.systemBars)
                .ignoresSafeArea()
            if model.failed {
                failure
            } else {
                MinikMathWebView(model: model, active: phase == .active && model.sheet == nil)
                    .id(model.page)
            }
        }
        .statusBarHidden(true)
        .persistentSystemOverlays(.hidden)
        .preferredColorScheme(.light)
        .task { await model.start() }
        .onChange(of: phase) { _, newPhase in
            model.sceneChanged(active: newPhase == .active)
        }
        .sheet(item: $model.sheet) { sheet in
            sheetContent(sheet)
                .environment(\.locale, Locale(identifier: model.language))
                .environment(\.layoutDirection, model.hebrew ? .rightToLeft : .leftToRight)
        }
    }

    @ViewBuilder
    private func sheetContent(_ sheet: MinikMathWebModel.Sheet) -> some View {
        switch sheet {
        case .parents:
            MinikMathParentsView(commerce: model.commerce, hebrew: model.hebrew) {
                model.sheet = nil
            }
        case .link(let url):
            ParentalGateView(onCancel: { model.sheet = nil }, onUnlock: {
                model.sheet = nil
                openURL(url)
            })
        }
    }

    private var failure: some View {
        VStack(spacing: 20) {
            Text(model.hebrew ? "לא ניתן לפתוח את המשחק כרגע." : "The game could not be opened.")
                .multilineTextAlignment(.center)
            Button(model.hebrew ? "נסו שוב" : "Try again") { model.retry() }
                .buttonStyle(.borderedProminent)
        }
        .padding()
        .environment(\.layoutDirection, model.hebrew ? .rightToLeft : .leftToRight)
    }
}

/// What the web app asks of its host, and the host's state.
@MainActor
final class MinikMathWebModel: ObservableObject {
    enum Sheet: Identifiable, Equatable {
        case parents
        case link(URL)

        var id: String {
            switch self {
            case .parents: return "parents"
            case .link(let url): return "link " + url.absoluteString
            }
        }
    }

    @Published var sheet: Sheet?
    @Published var failed = false
    /// "en" or "he": the web app's own EN/HE switch decides, as on Android.
    @Published private(set) var language: String
    @Published private(set) var isPingPong = false
    /// A new value reloads the web app (after a failure).
    @Published private(set) var page = UUID()

    let commerce: MinikCommerceController
    let ads: MinikMathAdCoordinator

    init() {
        commerce = MinikCommerceComposition.makeController(product: .current)
        ads = MinikMathAdCoordinator.make()
        // The web app starts in Hebrew when the device prefers it; it reports its language once loaded.
        let preferred = Locale.preferredLanguages.first?.lowercased() ?? ""
        language = preferred.hasPrefix("he") || preferred.hasPrefix("iw") ? "he" : "en"
    }

    var hebrew: Bool { language == "he" }

    /// The purchase check comes first: an ad never shows before it is known whether ads are removed.
    func start() async {
        await commerce.start()
        await ads.start(isRemoveAdsActive: commerce.isRemoveAdsActive)
    }

    func sceneChanged(active: Bool) {
        ads.setForeground(active)
        if active {
            Task { await commerce.refreshEntitlements() }
        }
    }

    func setLanguage(_ value: String?) {
        language = MinikMathWebBridge.language(value)
    }

    func setPlaying(_ value: Bool) {
        ads.setPlaying(value)
    }

    /// The web app's "Parents · Remove ads" link, with the language it shows.
    func openParents(language value: String?) {
        setLanguage(value)
        if sheet == nil { sheet = .parents }
    }

    func finishRound(_ id: String, results: @escaping () -> Void) {
        ads.finish(id, isRemoveAdsActive: commerce.isRemoveAdsActive, results: results)
    }

    /// A link out of the app (the "main site" footer): opened after the grown-up gate.
    func openLink(_ url: URL) {
        if sheet == nil { sheet = .link(url) }
    }

    func pageChanged(pingPong: Bool) {
        isPingPong = pingPong
        MinikMathOrientation.apply(pingPong: pingPong)
    }

    func retry() {
        failed = false
        page = UUID()
    }
}

/// Android's parents page (MonetizationActivity): Remove Ads, Restore and the privacy policy,
/// behind the grown-up gate every Minik app uses. Android's access codes are not offered: on iOS
/// only an App Store purchase may remove ads.
struct MinikMathParentsView: View {
    @ObservedObject var commerce: MinikCommerceController
    let hebrew: Bool
    let onClose: () -> Void
    @Environment(\.openURL) private var openURL
    @State private var unlocked = false
    @State private var restoreFoundNothing = false

    var body: some View {
        if unlocked {
            options
        } else {
            ParentalGateView(onCancel: onClose, onUnlock: { unlocked = true })
        }
    }

    private func t(_ english: String, _ hebrewText: String) -> String {
        hebrew ? hebrewText : english
    }

    private var options: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    Text(t("One purchase removes ads throughout this app, including all its games.",
                           "רכישה אחת מסירה פרסומות מכל האפליקציה, כולל כל המשחקים שבה."))
                    if let status {
                        Text(status)
                            .font(.callout)
                            .foregroundStyle(.secondary)
                    }
                    Button(purchaseTitle) {
                        restoreFoundNothing = false
                        Task { await commerce.purchaseRemoveAds() }
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(commerce.isRemoveAdsActive || commerce.removeAdsProduct == nil || commerce.isBusy)
                    Button(t("Restore purchase", "שחזור רכישה")) {
                        Task {
                            await commerce.restorePurchases()
                            restoreFoundNothing = commerce.status == .ready && !commerce.isRemoveAdsActive
                        }
                    }
                    .buttonStyle(.bordered)
                    .disabled(commerce.isBusy)
                    Text(t("Already paid? Restore using the same Apple account. You will not be charged again.",
                           "כבר שילמתם? שחזרו באמצעות אותו חשבון Apple. לא תחויבו שוב."))
                        .font(.callout)
                    if let privacyPolicy {
                        Button(t("Privacy policy", "מדיניות פרטיות")) { openURL(privacyPolicy) }
                    }
                }
                .multilineTextAlignment(.center)
                .padding(24)
                .frame(maxWidth: 600)
                .frame(maxWidth: .infinity)
            }
            .navigationTitle(t("Remove ads", "הסרת פרסומות"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(t("Close", "סגירה"), action: onClose)
                }
            }
        }
    }

    private var purchaseTitle: String {
        if let product = commerce.removeAdsProduct {
            return t("Remove ads", "הסרת פרסומות") + " · " + product.displayPrice
        }
        return t("Remove ads · one-time purchase", "הסרת פרסומות · רכישה חד־פעמית")
    }

    /// Android's purchase states, in its words, with the App Store in place of Google Play.
    private var status: String? {
        if commerce.isRemoveAdsActive {
            return t("Ads are removed.", "הפרסומות הוסרו.")
        }
        switch commerce.status {
        case .loading:
            return t("Connecting to the App Store…", "מתחברים ל־App Store…")
        case .unconfigured:
            return t("Purchases will be available when this app is set up in the App Store.",
                     "רכישות יהיו זמינות לאחר הגדרת האפליקציה ב־App Store.")
        case .purchasing, .restoring:
            return t("Checking your purchase…", "בודקים את הרכישה…")
        case .pending:
            return t("Payment is pending. Ads will be removed after approval.",
                     "התשלום ממתין לאישור. הפרסומות יוסרו לאחר האישור.")
        case .cancelled:
            return t("Purchase cancelled. You can keep playing.", "הרכישה בוטלה. אפשר להמשיך לשחק.")
        case .failed:
            if commerce.removeAdsProduct == nil {
                return t("The App Store product is currently unavailable. Please try again later.",
                         "המוצר אינו זמין כרגע ב־App Store. נסו שוב מאוחר יותר.")
            }
            return t("Could not check your purchase. Please try again when connected.",
                     "לא ניתן לבדוק את הרכישה. נסו שוב כשיש חיבור לרשת.")
        case .ready:
            return restoreFoundNothing
                ? t("No previous purchase was found for this Apple account.", "לא נמצאה רכישה קודמת בחשבון Apple הזה.")
                : nil
        }
    }

    private var privacyPolicy: URL? {
        guard let value = Bundle.main.object(forInfoDictionaryKey: "MinikPrivacyPolicyURL") as? String,
              let url = URL(string: value), url.scheme == "https" else {
            return nil
        }
        return url
    }
}

/// Android requests landscape for the Ping Pong page (MainActivity.updateOrientationForUrl).
/// Phones follow it; tablets keep every orientation, as Android 16 tablets do, and the web Ping
/// Pong already plays in a portrait tablet window. The Math pages follow the device.
@MainActor
enum MinikMathOrientation {
    private(set) static var landscapeOnly = false

    /// The app delegate's supported orientations (MinikAppDelegate).
    static var supported: UIInterfaceOrientationMask {
        if UIDevice.current.userInterfaceIdiom == .pad { return .all }
        return landscapeOnly ? .landscape : .allButUpsideDown
    }

    static func apply(pingPong: Bool) {
        let lock = pingPong && UIDevice.current.userInterfaceIdiom == .phone
        guard lock != landscapeOnly else { return }
        landscapeOnly = lock
        guard let scene = UIApplication.shared.connectedScenes
            .compactMap({ $0 as? UIWindowScene })
            .first else {
            return
        }
        // Without the lock, the screen turns back to the way the phone is held.
        for window in scene.windows {
            window.rootViewController?.setNeedsUpdateOfSupportedInterfaceOrientations()
        }
        if lock {
            scene.requestGeometryUpdate(.iOS(interfaceOrientations: .landscape)) { _ in }
        }
    }
}

/// Android Minik Math's host colours.
enum MinikMathWebColors {
    /// The system-bar background around the Math pages (rgb 248, 245, 255).
    static let systemBars = Color(red: 248 / 255, green: 245 / 255, blue: 1)
    /// The background of the Ping Pong page (rgb 18, 18, 31).
    static let pingPong = Color(red: 18 / 255, green: 18 / 255, blue: 31 / 255)
    static let pingPongBackground = UIColor(red: 18 / 255, green: 18 / 255, blue: 31 / 255, alpha: 1)
}
#endif
