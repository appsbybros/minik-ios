import SwiftUI
import UIKit

/// Standalone Minik Bounce. Like Android Bounce, a finished game is an interstitial
/// opportunity and the setup screen's "For parents" link opens a grown-up gate before
/// Remove Ads and Restore. As on Android Bounce 506490e, it also hosts the Minik family
/// messages (Family/): the card for another Minik app replaces one eligible ad break in 30,
/// the idle setup shows the remove-ads reminder, and the parents page has
/// "More Minik apps & games". As on Android Bounce 4f38dd5, the parents page also offers rating,
/// sharing and feedback, behind the same grown-up gate.
@MainActor struct BounceRootView: View {
    @Environment(\.locale) private var locale
    @Environment(\.scenePhase) private var phase
    @Environment(\.openURL) private var openURL
    @StateObject private var commerce: MinikCommerceController
    @State private var showsParents = false
    @State private var parentsUnlocked = false
    /// The parents page's share sheet (Android Intent.createChooser).
    @State private var shareRequest: MinikShareText?
    /// Android's Toast after "Send feedback" when no e-mail app opens.
    @State private var supportNotice: String?
    /// The store and ad start-up (including any consent form) is done; Android's reminder waits
    /// for the host's startup messages.
    @State private var startupDone = false
    private let adCoordinator: MinikAdCoordinator
    private let familyBreak: BounceFamilyBreak

    init() {
        _commerce = StateObject(wrappedValue: MinikCommerceComposition.makeController(product: .current))
        let familyBreak = BounceFamilyBreak()
        self.familyBreak = familyBreak
        // MinikAdsComposition.makeCoordinator, plus Android Bounce's family ad break.
        adCoordinator = MinikAdCoordinator(
            configuration: MinikAdsConfiguration.load(product: .current),
            service: ProductionMinikInterstitialAdServiceFactory.make(),
            family: familyBreak.adBreak()
        )
    }

    private var hebrew: Bool { locale.language.languageCode?.identifier == "he" }
    private func t(_ english: String, _ hebrewText: String) -> String { hebrew ? hebrewText : english }

    var body: some View {
        RetroPongView(onMatchFinished: matchFinished, onParents: {
            parentsUnlocked = false
            supportNotice = nil
            showsParents = true
        }, onMenuIdle: menuIdle)
        .onAppear {
            // Android LocalizedActivity: the family texts are Hebrew on a Hebrew device, else English.
            FamilyMessages.shared.languageOverride = hebrew ? "he" : "en"
            Task { @MainActor in StoreScreenshotScene.applyOrientation() }
        }
        .onChange(of: hebrew) { _, value in FamilyMessages.shared.languageOverride = value ? "he" : "en" }
        .task {
            await commerce.start()
            await adCoordinator.start(isRemoveAdsActive: commerce.isRemoveAdsActive)
            startupDone = true
        }
        .onChange(of: phase) { _, newPhase in
            if newPhase == .active {
                Task { await commerce.refreshEntitlements() }
            } else if newPhase == .background {
                Task { await adCoordinator.applicationDidEnterBackground() }
            }
        }
        .sheet(isPresented: $showsParents) {
            parentsSheet
                // The family card opened from the parents page, and its grown-up gate, show above the sheet.
                .overlay { FamilyOverlay() }
        }
        // The family card at an ad break, its grown-up gate and the remove-ads reminder.
        .overlay { FamilyOverlay() }
    }

    /// The game's result is already saved; it appears once the ad boundary finishes (or, when the
    /// family card replaced the ad, once the card closes).
    private func matchFinished(_ completion: @escaping () -> Void) {
        let removesAds = commerce.isRemoveAdsActive
        let ownershipResolved = commerce.ownershipResolved
        familyBreak.begin()
        Task {
            await adCoordinator.record(.bounceMatch, isRemoveAdsActive: removesAds, ownershipResolved: ownershipResolved)
            familyBreak.end(completion)
        }
    }

    /// Android Bounce `AdCoordinator.familyMenuIdle`, about every second while the setup is idle:
    /// the family remove-ads reminder (after 14 days, then at most every 14 days). Its
    /// "Remove ads" opens the parents page, which starts with its own grown-up gate.
    private func menuIdle() {
        // Android skips QA capture launches; iOS skips App Store capture launches.
        guard startupDone, !showsParents, StoreScreenshotScene.name == nil, !FamilyMessages.shared.isShowing else { return }
        FamilyMessages.shared.remind(
            ownershipResolved: commerce.ownershipResolved,
            adFree: { [commerce] in commerce.isRemoveAdsActive },
            purchaseAvailable: commerce.removeAdsProduct != nil,
            gate: { approved in approved() },
            purchase: {
                parentsUnlocked = false
                supportNotice = nil
                showsParents = true
            }
        )
    }

    @ViewBuilder private var parentsSheet: some View {
        if parentsUnlocked {
            NavigationStack {
                ScrollView {
                    VStack(spacing: 18) {
                        // Android MonetizationActivity: first on the parents page; a quiet link on iOS.
                        FamilyMenuLink(title: FamilyMessages.text("More Minik apps & games", "עוד אפליקציות ומשחקי מיניק",
                                                                  language: hebrew ? "he" : "en")) {
                            FamilyMessages.shared.showMoreApps(gate: nil)
                        }
                        // Android 4f38dd5: the page is "For parents"; "Remove ads" is now its first heading.
                        Text(t("Remove ads", "הסרת פרסומות"))
                            .font(.headline)
                            .multilineTextAlignment(.center)
                        Text(commerce.isRemoveAdsActive
                             ? t("Ads are removed on this Apple account.", "הפרסומות הוסרו בחשבון Apple הזה.")
                             : t("Remove ads with a one-time App Store purchase.", "הסירו פרסומות ברכישה חד־פעמית ב־App Store."))
                            .multilineTextAlignment(.center)
                        if !commerce.isRemoveAdsActive {
                            Button(t("Remove ads", "הסרת פרסומות") + (commerce.removeAdsProduct.map { " · " + $0.displayPrice } ?? "")) {
                                Task { await commerce.purchaseRemoveAds() }
                            }
                            .buttonStyle(.borderedProminent)
                            .disabled(commerce.removeAdsProduct == nil || commerce.isBusy)
                            if commerce.removeAdsProduct == nil {
                                Text(t("The App Store product is currently unavailable. Please try again later.",
                                       "המוצר אינו זמין כרגע ב־App Store. נסו שוב מאוחר יותר."))
                                    .font(.callout)
                                    .multilineTextAlignment(.center)
                            }
                        }
                        Button(t("Restore purchases", "שחזור רכישות")) {
                            Task { await commerce.restorePurchases() }
                        }
                        .buttonStyle(.bordered)
                        .disabled(commerce.isBusy)
                        supportSection
                    }
                    .padding(24)
                    .frame(maxWidth: 520)
                    .frame(maxWidth: .infinity)
                }
                .sheet(item: $shareRequest) { request in
                    MinikShareSheet(text: request.text)
                }
                .navigationTitle(t("For parents", "להורים"))
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button(t("Close", "סגירה")) { showsParents = false }
                    }
                }
            }
            .environment(\.layoutDirection, hebrew ? .rightToLeft : .leftToRight)
        } else {
            ParentalGateView(
                onCancel: { showsParents = false },
                onUnlock: { parentsUnlocked = true }
            )
        }
    }

    // MARK: Rate, share and feedback (Android Bounce 4f38dd5 MonetizationActivity)

    /// Android's page link for sharing. Android shares the Google Play listing; Minik Bounce has no
    /// App Store link yet, so it shares the app's page at miniklearn.com (its family catalogue
    /// landing page), as the other iPhone ports do.
    static let publicPage = "https://miniklearn.com/apps/minik-bounce-and-learn/"

    /// "More ways to support Minik Bounce": only on the parents page, after the grown-up gate.
    @ViewBuilder private var supportSection: some View {
        Text(t("More ways to support Minik Bounce", "עוד דרכים לתמוך במיניק"))
            .font(.headline)
            .multilineTextAlignment(.center)
            .padding(.top, 6)
        Button(t("Rate Minik Bounce & Learn", "דירוג מיניק – מקפצים ולומדים")) {
            // Android opens the store listing; iOS asks the App Store for its rating prompt.
            supportNotice = nil
            MinikAppFeedback.requestReview()
        }
        .buttonStyle(.bordered)
        Button(t("Share Minik Bounce & Learn", "שיתוף מיניק – מקפצים ולומדים")) {
            supportNotice = nil
            shareRequest = MinikShareText(text: t(
                "Try Minik Bounce & Learn: keep the ball bouncing and answer the question train.",
                "בואו לשחק במיניק – מקפצים ולומדים: מקפיצים את הכדור ועונים לרכבת השאלות."
            ) + " " + Self.publicPage)
        }
        .buttonStyle(.bordered)
        Button(t("Send feedback", "שליחת משוב"), action: sendFeedback)
            .buttonStyle(.bordered)
        if let supportNotice {
            Text(supportNotice)
                .font(.callout)
                .multilineTextAlignment(.center)
        }
    }

    /// Android ACTION_SENDTO mailto: with the localized subject; with no e-mail app, the address
    /// is copied and a notice says so.
    private func sendFeedback() {
        supportNotice = nil
        var mail = URLComponents()
        mail.scheme = "mailto"
        mail.path = MinikAppFeedback.feedbackAddress
        mail.queryItems = [URLQueryItem(name: "subject",
                                        value: t("Feedback on Minik Bounce & Learn", "משוב על מיניק – מקפצים ולומדים"))]
        let copied = t("No email app found. The feedback address was copied.",
                       "לא נמצאה אפליקציית דואר. כתובת המשוב הועתקה.")
        let fallback = {
            UIPasteboard.general.string = MinikAppFeedback.feedbackAddress
            supportNotice = copied
        }
        guard let url = mail.url else { fallback(); return }
        openURL(url) { accepted in
            if !accepted { fallback() }
        }
    }
}

/// Android Bounce `AdCoordinator`: at one eligible ad break in 30 (at most once a day, only with a
/// loaded ad and after the store has answered whether Remove Ads is owned) the family card for
/// another Minik app replaces the interstitial, and the game's result appears once the card closes
/// (Android `finished: results.run()`).
@MainActor private final class BounceFamilyBreak {
    private var replaced = false
    private var resume: (() -> Void)?

    func adBreak() -> MinikFamilyAdBreak {
        MinikFamilyAdBreak(
            isShowing: { FamilyMessages.shared.isShowing },
            replaceAd: { [self] ownershipResolved in
                let shown = FamilyMessages.shared.replaceAd(
                    UUID().uuidString.lowercased(),
                    ownershipResolved: ownershipResolved,
                    adFree: { MinikCommerceEntitlementRepository().isRemoveAdsActive(for: .current) },
                    gate: nil,
                    finished: { [weak self] in self?.cardClosed() }
                )
                replaced = shown
                return shown
            }
        )
    }

    /// Before a finished game's ad break.
    func begin() {
        replaced = false
        resume = nil
    }

    /// After the break: the result shows now, or when the family card that replaced the ad closes.
    func end(_ completion: @escaping () -> Void) {
        if replaced && FamilyMessages.shared.isShowing {
            resume = completion
        } else {
            replaced = false
            completion()
        }
    }

    private func cardClosed() {
        replaced = false
        let next = resume
        resume = nil
        next?()
    }
}
