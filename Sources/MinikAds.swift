import Foundation

enum MinikAdContentRating: String, Equatable, Sendable {
    case general = "G"
}

struct MinikAdProviderConfiguration: Equatable, Sendable {
    let applicationIdentifier: String
    let interstitialAdUnitIdentifier: String
    let isChildDirected: Bool
    let treatsUserAsUnderAgeOfConsent: Bool
    let maximumContentRating: MinikAdContentRating
    let allowsPersonalizedAds: Bool
}

struct MinikAdsConfiguration: Equatable, Sendable {
    static let enabledInfoKey = "MinikAdsEnabled"
    static let policyApprovedInfoKey = "MinikAdsPolicyApproved"
    static let applicationIdentifierInfoKey = "MinikAdsApplicationIdentifier"
    static let interstitialUnitIdentifierInfoKey = "MinikInterstitialAdUnitIdentifier"

    let product: ProductVariant
    let isEnabled: Bool
    let isPolicyApproved: Bool
    let applicationIdentifier: String?
    let interstitialAdUnitIdentifier: String?

    init(
        product: ProductVariant,
        isEnabled: Bool,
        isPolicyApproved: Bool,
        applicationIdentifier: String?,
        interstitialAdUnitIdentifier: String?
    ) {
        self.product = product
        self.isEnabled = isEnabled
        self.isPolicyApproved = isPolicyApproved
        self.applicationIdentifier = Self.normalized(applicationIdentifier)
        self.interstitialAdUnitIdentifier = Self.normalized(interstitialAdUnitIdentifier)
    }

    static func load(product: ProductVariant, bundle: Bundle = .main) -> MinikAdsConfiguration {
        MinikAdsConfiguration(
            product: product,
            isEnabled: boolValue(bundle.object(forInfoDictionaryKey: enabledInfoKey)),
            isPolicyApproved: boolValue(bundle.object(forInfoDictionaryKey: policyApprovedInfoKey)),
            applicationIdentifier: bundle.object(
                forInfoDictionaryKey: applicationIdentifierInfoKey
            ) as? String,
            interstitialAdUnitIdentifier: bundle.object(
                forInfoDictionaryKey: interstitialUnitIdentifierInfoKey
            ) as? String
        )
    }

    var providerConfiguration: MinikAdProviderConfiguration? {
        guard isEnabled,
              isPolicyApproved,
              let applicationIdentifier,
              let interstitialAdUnitIdentifier else {
            return nil
        }
        return MinikAdProviderConfiguration(
            applicationIdentifier: applicationIdentifier,
            interstitialAdUnitIdentifier: interstitialAdUnitIdentifier,
            isChildDirected: true,
            treatsUserAsUnderAgeOfConsent: true,
            maximumContentRating: .general,
            allowsPersonalizedAds: false
        )
    }

    private static func normalized(_ value: String?) -> String? {
        guard let value = value?.trimmingCharacters(in: .whitespacesAndNewlines),
              !value.isEmpty,
              !isKnownGoogleSampleOrTestIdentifier(value) else {
            return nil
        }
        return value
    }

    static func isKnownGoogleSampleOrTestIdentifier(_ value: String) -> Bool {
        let googleDemoPublisherID = ["394025", "6099942544"].joined()
        let normalized = value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return normalized.contains("ca-app-pub-\(googleDemoPublisherID)")
            || normalized.contains("/21775744923/example/")
    }

    private static func boolValue(_ value: Any?) -> Bool {
        switch value {
        case let bool as Bool:
            return bool
        case let number as NSNumber:
            return number.boolValue
        case let string as String:
            return ["1", "true", "yes"].contains(string.lowercased())
        default:
            return false
        }
    }
}

enum MinikInterstitialPresentationResult: Equatable, Sendable {
    case presented
    case unavailable
    case failed
}

protocol MinikInterstitialAdService: Sendable {
    func configure(_ configuration: MinikAdProviderConfiguration) async -> Bool
    func presentInterstitial() async -> MinikInterstitialPresentationResult
    /// Returns once the presented interstitial has closed (at once when none is on screen).
    /// Minik Math waits for it, as Android does, before a round's results appear.
    func waitUntilDismissed() async
}

extension MinikInterstitialAdService {
    func waitUntilDismissed() async {}
}

actor UnconfiguredMinikInterstitialAdService: MinikInterstitialAdService {
    func configure(_ configuration: MinikAdProviderConfiguration) async -> Bool {
        false
    }

    func presentInterstitial() async -> MinikInterstitialPresentationResult {
        .unavailable
    }
}

enum MinikAdOpportunity: String, Codable, Equatable, Sendable {
    case languageWriteScreen
    case languageTower
    case languagePictureMemory
    case languageSoccer
    case languageTicTacToe
    case pingPongMatch
    /// A finished Math round or a finished Ping Pong match inside Math.
    case mathRound
    /// A finished game in the standalone Minik Bounce app.
    case bounceMatch

    fileprivate var counterIncrement: Int {
        self == .languagePictureMemory ? 3 : 1
    }

    fileprivate var threshold: Int {
        switch self {
        case .languagePictureMemory:
            return 1
        case .pingPongMatch:
            // PingPongOnlyRootView reports only the owner-approved every-second-
            // match opportunity. The app-level policy must not count it again.
            return 0
        default:
            return 2
        }
    }
}

struct MinikAdPolicyState: Codable, Equatable, Sendable {
    var completedOpportunityWeight: Int
    var lastPresentedAt: Date?
    var minimumInterval: TimeInterval

    init(
        completedOpportunityWeight: Int = 0,
        lastPresentedAt: Date? = nil,
        minimumInterval: TimeInterval = AndroidCompatibleInterstitialPolicy.initialMinimumInterval
    ) {
        self.completedOpportunityWeight = max(completedOpportunityWeight, 0)
        self.lastPresentedAt = lastPresentedAt
        self.minimumInterval = max(minimumInterval, AndroidCompatibleInterstitialPolicy.minimumIntervalFloor)
    }
}

enum MinikAdPolicyDecision: Equatable, Sendable {
    case suppressedByEntitlement
    case providerUnavailable
    case initialCooldownSeeded
    case belowCompletionThreshold
    case sessionWarmup
    case minimumInterval
    case requestPresentation
}

struct AndroidCompatibleInterstitialPolicy: Equatable, Sendable {
    static let sessionWarmup: TimeInterval = 60
    static let providerMinimumInterval: TimeInterval = 120
    static let initialMinimumInterval: TimeInterval = 7 * 60
    static let minimumIntervalFloor: TimeInterval = 3 * 60

    private(set) var state: MinikAdPolicyState
    let sessionStartedAt: Date

    init(
        state: MinikAdPolicyState = MinikAdPolicyState(),
        sessionStartedAt: Date = Date()
    ) {
        self.state = state
        self.sessionStartedAt = sessionStartedAt
    }

    mutating func record(
        _ opportunity: MinikAdOpportunity,
        at date: Date,
        isRemoveAdsActive: Bool,
        isProviderReady: Bool
    ) -> MinikAdPolicyDecision {
        guard !isRemoveAdsActive else { return .suppressedByEntitlement }
        guard isProviderReady else { return .providerUnavailable }

        state.completedOpportunityWeight += opportunity.counterIncrement

        guard state.lastPresentedAt != nil else {
            // Android seeds its shared last-show timestamp on the first eligible
            // completion so a child is never shown an interstitial immediately.
            state.lastPresentedAt = date
            return .initialCooldownSeeded
        }
        guard state.completedOpportunityWeight > opportunity.threshold else {
            return .belowCompletionThreshold
        }
        guard date.timeIntervalSince(sessionStartedAt) >= Self.sessionWarmup else {
            return .sessionWarmup
        }
        guard let lastPresentedAt = state.lastPresentedAt,
              date.timeIntervalSince(lastPresentedAt) > max(
                state.minimumInterval,
                Self.providerMinimumInterval
              ) else {
            return .minimumInterval
        }
        return .requestPresentation
    }

    mutating func recordPresentation(at date: Date) {
        state.lastPresentedAt = date
        state.completedOpportunityWeight = 0
    }

    mutating func applicationDidEnterBackground() {
        // This is Android MainActivity.onStop's current 7 -> 5 -> 4 -> 3 minute
        // progression. It is persisted and never drops below three minutes.
        if state.minimumInterval >= 7 * 60 {
            state.minimumInterval = 5 * 60
        } else if state.minimumInterval >= 5 * 60 {
            state.minimumInterval = 4 * 60
        } else if state.minimumInterval >= 4 * 60 {
            state.minimumInterval = Self.minimumIntervalFloor
        } else {
            state.minimumInterval = max(state.minimumInterval, Self.minimumIntervalFloor)
        }
    }
}

struct MinikAdPolicyRepository: @unchecked Sendable {
    private let userDefaults: UserDefaults
    private let keyPrefix: String

    init(
        userDefaults: UserDefaults = .standard,
        keyPrefix: String = "minik.ads.policy.v1"
    ) {
        self.userDefaults = userDefaults
        self.keyPrefix = keyPrefix
    }

    func load(for product: ProductVariant) -> MinikAdPolicyState {
        guard let data = userDefaults.data(forKey: key(for: product)),
              let state = try? JSONDecoder().decode(MinikAdPolicyState.self, from: data) else {
            return MinikAdPolicyState()
        }
        return state
    }

    func save(_ state: MinikAdPolicyState, for product: ProductVariant) {
        guard let data = try? JSONEncoder().encode(state) else { return }
        userDefaults.set(data, forKey: key(for: product))
    }

    private func key(for product: ProductVariant) -> String {
        "\(keyPrefix).\(product.rawValue)"
    }
}

enum MinikAdOpportunityResult: Equatable, Sendable {
    case policy(MinikAdPolicyDecision)
    case presentation(MinikInterstitialPresentationResult)
}

actor MinikAdCoordinator {
    let configuration: MinikAdsConfiguration
    private let service: any MinikInterstitialAdService
    private let repository: MinikAdPolicyRepository
    private var policy: AndroidCompatibleInterstitialPolicy
    private var providerIsReady = false
    private var hasStarted = false

    init(
        configuration: MinikAdsConfiguration,
        service: any MinikInterstitialAdService = UnconfiguredMinikInterstitialAdService(),
        repository: MinikAdPolicyRepository = MinikAdPolicyRepository(),
        sessionStartedAt: Date = Date()
    ) {
        self.configuration = configuration
        self.service = service
        self.repository = repository
        self.policy = AndroidCompatibleInterstitialPolicy(
            state: repository.load(for: configuration.product),
            sessionStartedAt: sessionStartedAt
        )
    }

    func start(isRemoveAdsActive: Bool) async {
        guard !hasStarted else { return }
        guard !isRemoveAdsActive else { return }
        hasStarted = true
        guard let providerConfiguration = configuration.providerConfiguration else { return }
        providerIsReady = await service.configure(providerConfiguration)
    }

    @discardableResult
    func record(
        _ opportunity: MinikAdOpportunity,
        isRemoveAdsActive: Bool,
        at date: Date = Date()
    ) async -> MinikAdOpportunityResult {
        let decision = policy.record(
            opportunity,
            at: date,
            isRemoveAdsActive: isRemoveAdsActive,
            isProviderReady: providerIsReady
        )
        repository.save(policy.state, for: configuration.product)
        guard decision == .requestPresentation else { return .policy(decision) }

        let result = await service.presentInterstitial()
        if result == .presented {
            policy.recordPresentation(at: date)
            repository.save(policy.state, for: configuration.product)
        }
        return .presentation(result)
    }

    func applicationDidEnterBackground() {
        policy.applicationDidEnterBackground()
        repository.save(policy.state, for: configuration.product)
    }

    func currentPolicyState() -> MinikAdPolicyState {
        policy.state
    }

    func isProviderReady() -> Bool {
        providerIsReady
    }
}

enum MinikAdsComposition {
    static func makeCoordinator(
        product: ProductVariant,
        bundle: Bundle = .main,
        service: (any MinikInterstitialAdService)? = nil
    ) -> MinikAdCoordinator {
        MinikAdCoordinator(
            configuration: MinikAdsConfiguration.load(product: product, bundle: bundle),
            service: service ?? ProductionMinikInterstitialAdServiceFactory.make()
        )
    }
}

final class MinikPingPongHostServices: PingPongHostServices {
    let availableActions: Set<PingPongHostAction> = []

    private let adCoordinator: MinikAdCoordinator
    private weak var commerceController: MinikCommerceController?

    init(
        adCoordinator: MinikAdCoordinator,
        commerceController: MinikCommerceController
    ) {
        self.adCoordinator = adCoordinator
        self.commerceController = commerceController
    }

    func completedMatch(number: Int, isInterstitialOpportunity: Bool) {
        guard isInterstitialOpportunity else { return }
        Task { @MainActor [weak commerceController, adCoordinator] in
            let removesAds = commerceController?.isRemoveAdsActive ?? false
            await adCoordinator.record(.pingPongMatch, isRemoveAdsActive: removesAds)
        }
    }

    func perform(_ action: PingPongHostAction) {
        // Purchase and redemption UI stay unavailable here until the Ping Pong
        // host can route them through the same grown-up gate as Parent Area.
    }
}
