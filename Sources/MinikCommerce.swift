import AppStoreCommerceKit
import Combine
import Foundation

extension EntitlementID {
    static let minikRemoveAds = EntitlementID(rawValue: "remove_ads")
    /// Minik Plus: the one-time full-access purchase, or the Remove Ads purchase made before 1.8.0.
    static let minikPlusFullAccess = EntitlementID(rawValue: "minik_plus_full_access")
    /// Minik Plus: the free "7-day Trial" product (a free Non-Consumable, App Review 3.1.1).
    static let minikPlusFreeWeek = EntitlementID(rawValue: "minik_plus_free_week")
}

/// Minik Plus and Minik Plus English sell no Remove Ads and show no ads: a free week, then the
/// one-time full-access purchase (MinikPlusAccess.swift). Each target names its products in its
/// Info.plist (project.yml); the other apps have none of these keys and keep Remove Ads.
struct MinikPaywallProducts: Equatable, Sendable {
    static let fullAccessProductInfoKey = "MinikFullAccessProductIdentifier"
    static let freeWeekProductInfoKey = "MinikFreeWeekProductIdentifier"
    static let legacyRemoveAdsProductInfoKey = "MinikLegacyRemoveAdsProductIdentifier"

    let fullAccessProductID: CommerceProductID
    let freeWeekProductID: CommerceProductID
    /// The Remove Ads product sold before 1.8.0: whoever owns it has full access forever.
    let legacyRemoveAdsProductID: CommerceProductID?

    /// Nil unless both the full-access and the free-week products are named.
    init?(
        fullAccessProductIdentifier: String?,
        freeWeekProductIdentifier: String?,
        legacyRemoveAdsProductIdentifier: String?
    ) {
        guard let fullAccess = MinikCommerceConfiguration.productID(fullAccessProductIdentifier),
              let freeWeek = MinikCommerceConfiguration.productID(freeWeekProductIdentifier),
              fullAccess != freeWeek else {
            return nil
        }
        fullAccessProductID = fullAccess
        freeWeekProductID = freeWeek
        legacyRemoveAdsProductID = MinikCommerceConfiguration.productID(legacyRemoveAdsProductIdentifier)
    }

    static func load(bundle: Bundle = .main) -> MinikPaywallProducts? {
        MinikPaywallProducts(
            fullAccessProductIdentifier: bundle.object(forInfoDictionaryKey: fullAccessProductInfoKey) as? String,
            freeWeekProductIdentifier: bundle.object(forInfoDictionaryKey: freeWeekProductInfoKey) as? String,
            legacyRemoveAdsProductIdentifier: bundle.object(forInfoDictionaryKey: legacyRemoveAdsProductInfoKey) as? String
        )
    }
}

struct MinikCommerceConfiguration: Equatable, Sendable {
    static let removeAdsProductInfoKey = "MinikRemoveAdsProductIdentifier"

    let product: ProductVariant
    let removeAdsProductID: CommerceProductID?
    /// Minik Plus and Minik Plus English only.
    let paywall: MinikPaywallProducts?

    init(
        product: ProductVariant,
        removeAdsProductIdentifier: String?,
        paywall: MinikPaywallProducts? = nil
    ) {
        self.product = product
        removeAdsProductID = Self.productID(removeAdsProductIdentifier)
        self.paywall = paywall
    }

    static func load(product: ProductVariant, bundle: Bundle = .main) -> MinikCommerceConfiguration {
        MinikCommerceConfiguration(
            product: product,
            removeAdsProductIdentifier: bundle.object(
                forInfoDictionaryKey: removeAdsProductInfoKey
            ) as? String,
            paywall: MinikPaywallProducts.load(bundle: bundle)
        )
    }

    /// A trimmed, non-empty product identifier.
    static func productID(_ identifier: String?) -> CommerceProductID? {
        let normalized = identifier?.trimmingCharacters(in: .whitespacesAndNewlines)
        return normalized.flatMap { value in
            value.isEmpty ? nil : CommerceProductID(rawValue: value)
        }
    }

    var catalog: CommerceCatalog? {
        var entitlementByProductID: [CommerceProductID: EntitlementID] = [:]
        if let removeAdsProductID {
            entitlementByProductID[removeAdsProductID] = .minikRemoveAds
        }
        if let paywall {
            entitlementByProductID[paywall.fullAccessProductID] = .minikPlusFullAccess
            entitlementByProductID[paywall.freeWeekProductID] = .minikPlusFreeWeek
            if let legacy = paywall.legacyRemoveAdsProductID,
               legacy != paywall.fullAccessProductID,
               legacy != paywall.freeWeekProductID {
                // Grandfathering: the earlier Remove Ads purchase unlocks everything.
                entitlementByProductID[legacy] = .minikPlusFullAccess
            }
        }
        guard !entitlementByProductID.isEmpty else { return nil }
        return CommerceCatalog(
            entitlementByProductID: entitlementByProductID,
            supportedProductKinds: [.nonConsumable]
        )
    }
}

struct MinikCommerceEntitlementRepository: @unchecked Sendable {
    private let userDefaults: UserDefaults
    private let keyPrefix: String

    init(
        userDefaults: UserDefaults = .standard,
        keyPrefix: String = "minik.commerce.remove-ads.v1"
    ) {
        self.userDefaults = userDefaults
        self.keyPrefix = keyPrefix
    }

    func isRemoveAdsActive(for product: ProductVariant) -> Bool {
        userDefaults.bool(forKey: key(for: product))
    }

    func save(_ state: EntitlementState, for product: ProductVariant) {
        userDefaults.set(state.contains(.minikRemoveAds), forKey: key(for: product))
    }

    private func key(for product: ProductVariant) -> String {
        "\(keyPrefix).\(product.rawValue)"
    }
}

private struct MinikCommerceFulfillmentHandler: CommerceFulfillmentHandler {
    let product: ProductVariant
    let repository: MinikCommerceEntitlementRepository

    func fulfill(_ fulfillment: CommerceFulfillment) async throws {
        repository.save(fulfillment.entitlementState, for: product)
    }
}

enum MinikCommerceComposition {
    @MainActor
    static func makeController(
        product: ProductVariant,
        bundle: Bundle = .main,
        repository: MinikCommerceEntitlementRepository = MinikCommerceEntitlementRepository()
    ) -> MinikCommerceController {
        let configuration = MinikCommerceConfiguration.load(product: product, bundle: bundle)
        let freeWeekStartReader: (any MinikFreeWeekStartReading)? =
            configuration.paywall == nil ? nil : StoreKitFreeWeekStartReader()
        guard let catalog = configuration.catalog else {
            return MinikCommerceController(
                configuration: configuration,
                store: nil,
                repository: repository
            )
        }
        let store = StoreKitCommerceStore(
            catalog: catalog,
            fulfillmentHandler: MinikCommerceFulfillmentHandler(
                product: product,
                repository: repository
            )
        )
        return MinikCommerceController(
            configuration: configuration,
            store: store,
            repository: repository,
            freeWeekStartReader: freeWeekStartReader
        )
    }
}

@MainActor
final class MinikCommerceController: ObservableObject {
    enum Status: Equatable {
        case unconfigured
        case loading
        case ready
        case purchasing
        case pending
        case cancelled
        case restoring
        case failed
    }

    @Published private(set) var status: Status
    @Published private(set) var removeAdsProduct: CommerceProduct?
    @Published private(set) var isRemoveAdsActive: Bool
    /// Android `RemoveAds.ownershipResolved`: the store has answered whether Remove Ads is owned (an
    /// entitlement refresh, purchase or restore succeeded); the family messages wait for it.
    private(set) var ownershipResolved = false

    /// Minik Plus: the full-access and free-week products, once the App Store has loaded them.
    @Published private(set) var fullAccessProduct: CommerceProduct?
    @Published private(set) var freeWeekProduct: CommerceProduct?
    /// Minik Plus: what the app may open now. Always `.fullAccess` where no paywall is configured.
    @Published private(set) var plusAccess: MinikPlusAccess
    /// A grown-up opened the buy screen during the free week (the chip or the Parent Area).
    @Published private(set) var isPaywallRequested = false

    let configuration: MinikCommerceConfiguration
    private let store: (any CommerceStore)?
    private let repository: MinikCommerceEntitlementRepository
    private let accessRepository: MinikPlusAccessRepository
    private let freeWeekStartReader: (any MinikFreeWeekStartReading)?
    private let clock: @Sendable () -> Date
    /// App Store screenshot and parity captures (StoreScreenshotScene) show the app, not the wall.
    private let isStoreScreenshotCapture: Bool
    private var accessRecord: MinikPlusAccessRecord
    private var updateTask: Task<Void, Never>?
    private var hasStarted = false

    init(
        configuration: MinikCommerceConfiguration,
        store: (any CommerceStore)?,
        repository: MinikCommerceEntitlementRepository = MinikCommerceEntitlementRepository(),
        accessRepository: MinikPlusAccessRepository = MinikPlusAccessRepository(),
        freeWeekStartReader: (any MinikFreeWeekStartReading)? = nil,
        clock: @escaping @Sendable () -> Date = { Date() },
        isStoreScreenshotCapture: Bool = StoreScreenshotScene.name != nil
    ) {
        self.configuration = configuration
        self.store = store
        self.repository = repository
        self.accessRepository = accessRepository
        self.freeWeekStartReader = freeWeekStartReader
        self.clock = clock
        self.isStoreScreenshotCapture = isStoreScreenshotCapture
        isRemoveAdsActive = repository.isRemoveAdsActive(for: configuration.product)
        status = store == nil ? .unconfigured : .loading
        var record = accessRepository.load(for: configuration.product)
        if configuration.paywall != nil, !record.ownsFullAccess,
           repository.isRemoveAdsActive(for: configuration.product) {
            // Remove Ads bought before 1.8.0, as this device remembered it: full access, even offline.
            record.ownsFullAccess = true
        }
        accessRecord = record
        plusAccess = Self.access(
            for: record,
            paywallIsConfigured: configuration.paywall != nil,
            isStoreScreenshotCapture: isStoreScreenshotCapture,
            now: clock()
        )
    }

    var isBusy: Bool {
        status == .loading || status == .purchasing || status == .restoring
    }

    /// Minik Plus and Minik Plus English: no ads, a free week and the one-time full-access purchase.
    var isPaywallConfigured: Bool {
        configuration.paywall != nil
    }

    /// The welcome screen, the wall, or the buy screen a grown-up asked for, covers the app.
    var showsPaywall: Bool {
        isPaywallConfigured && (plusAccess.isLocked || isPaywallRequested)
    }

    /// Checks the free week against the clock now: at launch, on return to the app and before an
    /// activity opens. Returns true when the app is locked.
    @discardableResult
    func evaluateAccess() -> Bool {
        guard isPaywallConfigured else { return false }
        let now = clock()
        accessRecord.recordSeen(now)
        accessRepository.save(accessRecord, for: configuration.product)
        let access = Self.access(
            for: accessRecord,
            paywallIsConfigured: true,
            isStoreScreenshotCapture: isStoreScreenshotCapture,
            now: now
        )
        if plusAccess != access { plusAccess = access }
        if access == .fullAccess, isPaywallRequested { isPaywallRequested = false }
        return access.isLocked
    }

    /// Opens the buy screen during the free week (after the grown-up check).
    func requestPaywall() {
        guard isPaywallConfigured, plusAccess != .fullAccess else { return }
        isPaywallRequested = true
    }

    func dismissRequestedPaywall() {
        isPaywallRequested = false
    }

    private static func access(
        for record: MinikPlusAccessRecord,
        paywallIsConfigured: Bool,
        isStoreScreenshotCapture: Bool,
        now: Date
    ) -> MinikPlusAccess {
        guard paywallIsConfigured, !isStoreScreenshotCapture else { return .fullAccess }
        return record.access(now: now)
    }

    func start() async {
        guard !hasStarted else { return }
        hasStarted = true
        guard let store else {
            status = .unconfigured
            return
        }

        updateTask = Task { [weak self] in
            let updates = await store.transactionUpdates()
            for await update in updates {
                guard !Task.isCancelled else { return }
                if case .entitlements = update {
                    await self?.recordFreeWeekStartFromStore()
                }
                self?.apply(update)
            }
        }
        await loadProductsAndRefreshEntitlements()
    }

    func refreshEntitlements() async {
        guard let store else {
            status = .unconfigured
            return
        }
        do {
            let state = try await store.refreshEntitlements()
            await recordFreeWeekStartFromStore()
            apply(state)
            if status != .pending { status = .ready }
        } catch {
            status = .failed
        }
    }

    func purchaseRemoveAds() async {
        guard let store, let productID = configuration.removeAdsProductID else {
            status = .unconfigured
            return
        }
        status = .purchasing
        do {
            switch try await store.purchase(productID: productID) {
            case .purchased(let state):
                apply(state)
                status = .ready
            case .pending:
                status = .pending
            case .userCancelled:
                status = .cancelled
            }
        } catch {
            status = .failed
        }
    }

    func restorePurchases() async {
        guard let store else {
            status = .unconfigured
            return
        }
        status = .restoring
        do {
            let state = try await store.restorePurchases()
            await recordFreeWeekStartFromStore()
            apply(state)
            status = .ready
        } catch {
            status = .failed
        }
    }

    /// Minik Plus: asks the App Store again for the products and purchases, when the first
    /// request failed (offline) and the wall is still up.
    func reloadStore() async {
        guard store != nil, !isBusy else { return }
        await loadProductsAndRefreshEntitlements()
    }

    /// Minik Plus: buys full access (after the grown-up check).
    func purchaseFullAccess() async {
        await purchasePaywallProduct(configuration.paywall?.fullAccessProductID)
    }

    /// Minik Plus: takes the free 7-day Trial product, which starts the free week (after the
    /// grown-up check).
    func startFreeWeek() async {
        await purchasePaywallProduct(configuration.paywall?.freeWeekProductID)
    }

    private func purchasePaywallProduct(_ productID: CommerceProductID?) async {
        guard let store, let productID else {
            status = .unconfigured
            return
        }
        status = .purchasing
        do {
            switch try await store.purchase(productID: productID) {
            case .purchased(let state):
                await recordFreeWeekStartFromStore()
                apply(state)
                status = .ready
            case .pending:
                status = .pending
            case .userCancelled:
                status = .cancelled
            }
        } catch {
            status = .failed
        }
    }

    private func loadProductsAndRefreshEntitlements() async {
        guard let store else { return }
        status = .loading
        do {
            async let products = store.loadProducts()
            async let entitlements = store.refreshEntitlements()
            let (loadedProducts, state) = try await (products, entitlements)
            if let paywall = configuration.paywall {
                fullAccessProduct = loadedProducts.first { $0.id == paywall.fullAccessProductID }
                freeWeekProduct = loadedProducts.first { $0.id == paywall.freeWeekProductID }
                await recordFreeWeekStartFromStore()
                apply(state)
                status = fullAccessProduct == nil ? .failed : .ready
                return
            }
            guard let productID = configuration.removeAdsProductID else {
                status = .unconfigured
                return
            }
            removeAdsProduct = loadedProducts.first { $0.id == productID }
            apply(state)
            status = removeAdsProduct == nil ? .failed : .ready
        } catch {
            status = .failed
        }
    }

    private func apply(_ state: EntitlementState) {
        ownershipResolved = true
        isRemoveAdsActive = state.contains(.minikRemoveAds)
        repository.save(state, for: configuration.product)
        applyPlusAccess(state)
    }

    /// Minik Plus: the App Store's answer decides ownership; the free week's start only moves earlier.
    private func applyPlusAccess(_ state: EntitlementState) {
        guard isPaywallConfigured else { return }
        accessRecord.ownsFullAccess = state.contains(.minikPlusFullAccess)
        if state.contains(.minikPlusFreeWeek), accessRecord.freeWeekStartedAt == nil {
            // The App Store's date was not readable yet: the week counts from now, and a later
            // reading can only move it earlier.
            accessRecord.recordFreeWeekStart(clock())
        }
        evaluateAccess()
    }

    /// Minik Plus: the free week's start from the App Store's signed transactions.
    private func recordFreeWeekStartFromStore() async {
        guard let paywall = configuration.paywall, let freeWeekStartReader else { return }
        if let started = await freeWeekStartReader.freeWeekStart(for: paywall.freeWeekProductID) {
            accessRecord.recordFreeWeekStart(started)
        }
    }

    private func apply(_ update: CommerceTransactionUpdate) {
        switch update {
        case .entitlements(let state):
            apply(state)
            status = .ready
        case .failure:
            status = .failed
        }
    }

    deinit {
        updateTask?.cancel()
    }
}
