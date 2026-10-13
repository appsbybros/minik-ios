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
        FamilyMessages.shared.languageOverride = RootView.familyLanguage(
            configuration,
            interfaceLocale: interfaceLocaleRepository.load(for: configuration.variant)
        )
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
            await learningReminderController.synchronize(locale: interfaceLocaleController.selectedLocale)
            await commerceController.start()
            // Modern Ping Pong runs its own match-based ads (MPAds); the shared coordinator
            // would only preload an interstitial it never shows.
            if configuration.launchExperience != .pingPong {
                await adCoordinator.start(isRemoveAdsActive: commerceController.isRemoveAdsActive)
            }
            await evaluateRemoveAdsReminder()
        }
        .onChange(of: scenePhase) { _, newPhase in
            if newPhase == .active {
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
        // the family remove-ads reminder, above every Minik app.
        .overlay { FamilyOverlay() }
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
