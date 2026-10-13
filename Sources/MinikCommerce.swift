import AppStoreCommerceKit
import Combine
import Foundation

extension EntitlementID {
    static let minikRemoveAds = EntitlementID(rawValue: "remove_ads")
}

struct MinikCommerceConfiguration: Equatable, Sendable {
    static let removeAdsProductInfoKey = "MinikRemoveAdsProductIdentifier"

    let product: ProductVariant
    let removeAdsProductID: CommerceProductID?

    init(product: ProductVariant, removeAdsProductIdentifier: String?) {
        self.product = product
        let normalized = removeAdsProductIdentifier?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        removeAdsProductID = normalized.flatMap { value in
            value.isEmpty ? nil : CommerceProductID(rawValue: value)
        }
    }

    static func load(product: ProductVariant, bundle: Bundle = .main) -> MinikCommerceConfiguration {
        MinikCommerceConfiguration(
            product: product,
            removeAdsProductIdentifier: bundle.object(
                forInfoDictionaryKey: removeAdsProductInfoKey
            ) as? String
        )
    }

    var catalog: CommerceCatalog? {
        guard let removeAdsProductID else { return nil }
        return CommerceCatalog(
            entitlementByProductID: [removeAdsProductID: .minikRemoveAds],
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
            repository: repository
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

    let configuration: MinikCommerceConfiguration
    private let store: (any CommerceStore)?
    private let repository: MinikCommerceEntitlementRepository
    private var updateTask: Task<Void, Never>?
    private var hasStarted = false

    init(
        configuration: MinikCommerceConfiguration,
        store: (any CommerceStore)?,
        repository: MinikCommerceEntitlementRepository = MinikCommerceEntitlementRepository()
    ) {
        self.configuration = configuration
        self.store = store
        self.repository = repository
        isRemoveAdsActive = repository.isRemoveAdsActive(for: configuration.product)
        status = store == nil ? .unconfigured : .loading
    }

    var isBusy: Bool {
        status == .loading || status == .purchasing || status == .restoring
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
            apply(try await store.refreshEntitlements())
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
            apply(try await store.restorePurchases())
            status = .ready
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
