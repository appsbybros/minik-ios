import SwiftUI

/// Standalone Minik Bounce. Like Android Bounce, a finished game is an interstitial
/// opportunity and the setup screen's "For parents" link opens a grown-up gate before
/// Remove Ads and Restore. As on Android Bounce 506490e, it also hosts the Minik family
/// messages (Family/): the card for another Minik app replaces one eligible ad break in 30,
/// the idle setup shows the remove-ads reminder, and the parents page has
/// "More Minik apps & games".
@MainActor struct BounceRootView: View {
    @Environment(\.locale) private var locale
    @Environment(\.scenePhase) private var phase
    @StateObject private var commerce: MinikCommerceController
    @State private var showsParents = false
    @State private var parentsUnlocked = false
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
                showsParents = true
            }
        )
    }

    @ViewBuilder private var parentsSheet: some View {
        if parentsUnlocked {
            NavigationStack {
                VStack(spacing: 18) {
                    // Android MonetizationActivity: first on the parents page; a quiet link on iOS.
                    FamilyMenuLink(title: FamilyMessages.text("More Minik apps & games", "עוד אפליקציות ומשחקי מיניק",
                                                              language: hebrew ? "he" : "en")) {
                        FamilyMessages.shared.showMoreApps(gate: nil)
                    }
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
                }
                .padding(24)
                .frame(maxWidth: 520)
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
