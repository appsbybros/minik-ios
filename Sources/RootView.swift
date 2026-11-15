import SwiftUI

struct RootView: View {
    let configuration: ProductConfiguration
    @Environment(\.layoutDirection) private var systemLayoutDirection
    @Environment(\.scenePhase) private var scenePhase
    @StateObject private var interfaceLocaleController: InterfaceLocaleController
    @StateObject private var learningReminderController: LearningReminderController
    @StateObject private var commerceController: MinikCommerceController
    @StateObject private var removeAdsReminderController: RemoveAdsReminderController
    private let adCoordinator: MinikAdCoordinator
    private let pingPongHostServices: MinikPingPongHostServices
    /// Minik Plus: the thank-you note after full access was bought or restored.
    @State private var showsUnlockThanks = false

    @MainActor
    init(
        configuration: ProductConfiguration,
        interfaceLocaleRepository: InterfaceLocaleRepository = InterfaceLocaleRepository(),
        learningReminderRepository: LearningReminderPreferenceRepository = LearningReminderPreferenceRepository(),
        learningReminderService: any LearningReminderNotificationService = UserNotificationsLearningReminderService(),
        commerceController: MinikCommerceController? = nil,
        adCoordinator: MinikAdCoordinator? = nil,
        removeAdsReminderController: RemoveAdsReminderController? = nil
    ) {
        self.configuration = configuration
        _interfaceLocaleController = StateObject(wrappedValue: InterfaceLocaleController(
            product: configuration.variant,
            repository: interfaceLocaleRepository
        ))
        _learningReminderController = StateObject(wrappedValue: LearningReminderController(
            policy: LearningReminderPolicy(product: configuration.variant),
            repository: learningReminderRepository,
            service: learningReminderService
        ))
        let resolvedCommerceController = commerceController ?? MinikCommerceComposition.makeController(
            product: configuration.variant
        )
        let resolvedAdCoordinator = adCoordinator ?? MinikAdsComposition.makeCoordinator(
            product: configuration.variant
        )
        _commerceController = StateObject(wrappedValue: resolvedCommerceController)
        _removeAdsReminderController = StateObject(wrappedValue:
            removeAdsReminderController ?? RemoveAdsReminderController(product: configuration.variant)
        )
        self.adCoordinator = resolvedAdCoordinator
        self.pingPongHostServices = MinikPingPongHostServices(
            adCoordinator: resolvedAdCoordinator,
            commerceController: resolvedCommerceController
        )
        // Set before the first screen is drawn: menu labels such as "More Minik apps & games" read it.
        if configuration.variant.showsFamilyMessages {
            FamilyMessages.shared.languageOverride = RootView.familyLanguage(
                configuration,
                interfaceLocale: interfaceLocaleRepository.load(for: configuration.variant)
            )
        }
    }

    @ViewBuilder
    var body: some View {
        Group {
            if configuration.launchExperience == .pingPong {
                PingPongOnlyRootView(commerce: commerceController)
            } else {
                MinikActivityHubView(
                    configuration: configuration,
                    interfaceLocaleController: interfaceLocaleController,
                    learningReminderController: learningReminderController,
                    commerceController: commerceController,
                    adCoordinator: adCoordinator
                )
            }
        }
        // Minik Plus and Minik Plus English: the welcome screen before the free week and the wall
        // after it cover every activity (and VoiceOver's view of them) until the app is unlocked.
        .accessibilityHidden(commerceController.showsPaywall)
        .overlay {
            if commerceController.showsPaywall {
                MinikPlusPaywallView(
                    commerce: commerceController,
                    variant: configuration.variant
                )
                .transition(.opacity)
            }
        }
        .overlay(alignment: .top) {
            if showsUnlockThanks {
                MinikPlusUnlockThanks()
                    .padding(.top, 12)
                    .padding(.horizontal, 16)
                    .transition(.move(edge: .top).combined(with: .opacity))
            }
        }
        .animation(.easeOut(duration: 0.2), value: commerceController.showsPaywall)
        .animation(.easeOut(duration: 0.25), value: showsUnlockThanks)
        // ISSUE-004: iPadOS 26 draws the portrait-only language apps between black bars
        // on an iPad held in landscape; the notice asks to turn the iPad upright. It is
        // applied inside the locale and layout-direction environment below.
        .minikPortraitNotice(isEnabled: configuration.contentDomain == .language)
        // The language and Math apps are drawn in the light rainbow-sky design with
        // dark text on light surfaces; in Dark Mode the system's default text turned
        // white on Math's white answer tiles. The standalone Ping Pong keeps the system's.
        .preferredColorScheme(configuration.launchExperience == .pingPong ? nil : .light)
        .onAppear { Task { @MainActor in StoreScreenshotScene.applyOrientation() } }
        .environment(\.minikVisualIdentity, configuration.visualIdentity)
        .environment(\.interfaceLocaleID, effectiveInterfaceLocale)
        .environment(\.locale, effectiveInterfaceLocale.locale)
        .environment(\.layoutDirection, effectiveLayoutDirection)
        .task {
            // Minik Plus: the free week is checked at launch, before the App Store answers.
            commerceController.evaluateAccess()
            await learningReminderController.synchronize(locale: interfaceLocaleController.selectedLocale)
            await commerceController.start()
            // Modern Ping Pong runs its own match-based ads (MPAds); the shared coordinator
            // would only preload an interstitial it never shows. Minik Plus has no ads.
            if configuration.launchExperience != .pingPong && !commerceController.isPaywallConfigured {
                await adCoordinator.start(isRemoveAdsActive: commerceController.isRemoveAdsActive)
            }
            await evaluateRemoveAdsReminder()
        }
        .onChange(of: scenePhase) { _, newPhase in
            if newPhase == .active {
                // Minik Plus: back in the app, the free week is checked again, even offline.
                commerceController.evaluateAccess()
                Task {
                    await learningReminderController.synchronize(locale: interfaceLocaleController.selectedLocale)
                    await commerceController.refreshEntitlements()
                    await evaluateRemoveAdsReminder()
                }
            } else if newPhase == .background {
                Task { await adCoordinator.applicationDidEnterBackground() }
            }
        }
        .onChange(of: interfaceLocaleController.selectedLocale) { _, newLocale in
            Task { await learningReminderController.rescheduleForLocaleChange(newLocale) }
            applyFamilyLanguage()
        }
        .onAppear { applyFamilyLanguage() }
        .onChange(of: commerceController.plusAccess) { oldAccess, newAccess in
            guard commerceController.isPaywallConfigured,
                  newAccess == .fullAccess, oldAccess != .fullAccess else { return }
            showsUnlockThanks = true
            Task { @MainActor in
                try? await Task.sleep(for: .seconds(3))
                showsUnlockThanks = false
            }
        }
        .sheet(isPresented: Binding(
            get: { removeAdsReminderController.isPresented },
            set: { isPresented in
                if !isPresented { removeAdsReminderController.remindLater() }
            }
        )) {
            RemoveAdsReminderView(
                controller: removeAdsReminderController,
                commerceController: commerceController
            )
        }
        // Android MinikFamilyServices: the "More Minik apps & games" card, its grown-up gate and
        // the family remove-ads reminder, above every Minik app that shows them.
        .overlay { if configuration.variant.showsFamilyMessages { FamilyOverlay() } }
    }

    /// Like Android Modern Ping Pong, the standalone Ping Pong app is Hebrew on a
    /// Hebrew device and English otherwise; it has no Parent Area language picker.
    private var effectiveInterfaceLocale: InterfaceLocaleID {
        guard configuration.launchExperience == .pingPong else {
            return interfaceLocaleController.selectedLocale
        }
        let primary = Locale.preferredLanguages.first.flatMap { InterfaceLocaleID(languageTag: $0) }
        return primary == .hebrew ? .hebrew : .english
    }

    private var effectiveLayoutDirection: LayoutDirection {
        if configuration.contentDomain == .language || configuration.launchExperience == .pingPong {
            return effectiveInterfaceLocale.layoutDirection
        }
        return systemLayoutDirection
    }

    @MainActor
    private func applyFamilyLanguage() {
        guard configuration.variant.showsFamilyMessages else { return }
        FamilyMessages.shared.languageOverride = RootView.familyLanguage(configuration, interfaceLocale: interfaceLocaleController.selectedLocale)
    }

    /// The language of the family card, reminder and "More Minik apps & games" label, as on Android:
    /// Minik Plus and Math Plus use the interface language; Minik Ping Pong is English, or Hebrew on a
    /// Hebrew device (LocalizedActivity); Multi Ping Pong uses its six app languages (AppText).
    private static func familyLanguage(_ configuration: ProductConfiguration, interfaceLocale: InterfaceLocaleID) -> String {
        #if MINIK_MULTI_PING_PONG
        return MPText.language
        #else
        guard configuration.launchExperience == .pingPong else { return interfaceLocale.rawValue }
        let primary = Locale.preferredLanguages.first.flatMap { InterfaceLocaleID(languageTag: $0) }
        return primary == .hebrew ? "he" : "en"
        #endif
    }

    @MainActor
    private func evaluateRemoveAdsReminder() async {
        // Minik Plus sells no Remove Ads and shows no ads.
        guard !commerceController.isPaywallConfigured else { return }
        let providerIsReady = await adCoordinator.isProviderReady()
        let adsAreActive = providerIsReady && !commerceController.isRemoveAdsActive
        removeAdsReminderController.evaluate(
            adsAreActive: adsAreActive,
            purchaseIsAvailable: commerceController.removeAdsProduct != nil
        )
    }
}

#Preview {
    RootView(configuration: .configuration(for: .minikPlus))
}
