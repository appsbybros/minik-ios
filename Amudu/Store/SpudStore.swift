import AppStoreCommerceKit
import Combine
import Foundation

/// iOS payment model (CLAUDE.md): the full-game purchase through the shared AppStoreCommerceKit (StoreKit 2), as
/// Minik Plus uses it (Sources/MinikCommerce.swift): the product ID from the Info.plist, the ownership remembered in
/// UserDefaults so the game stays unlocked offline, and the App Store's answers (purchase, restore, Family Sharing
/// grants, refunds) applied while the app runs.
extension EntitlementID {
    static let spudFullGame = EntitlementID(rawValue: "spud_full_game")
}

struct SpudStoreConfiguration: Equatable, Sendable {
    let productID: CommerceProductID?

    init(productIdentifier: String?) {
        let trimmed = productIdentifier?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        // An unexpanded build setting ("$(...)") is not a product.
        productID = trimmed.isEmpty || trimmed.hasPrefix("$(") ? nil : CommerceProductID(rawValue: trimmed)
    }

    static func load(bundle: Bundle = .main) -> SpudStoreConfiguration {
        return SpudStoreConfiguration(productIdentifier: bundle.object(forInfoDictionaryKey: SpudAccess.productInfoKey) as? String)
    }

    var productIdentifier: String? {
        return productID?.rawValue
    }

    /// The catalog's only product: the full game, a non-consumable.
    var catalog: CommerceCatalog? {
        guard let productID else { return nil }
        return CommerceCatalog(entitlementByProductID: [productID: .spudFullGame], supportedProductKinds: [.nonConsumable])
    }
}

/// Whether this device last knew the full game as owned (the App Store's answer replaces it whenever it arrives).
struct SpudEntitlementRepository: @unchecked Sendable {
    static let key = "amudu.store.fullGame"

    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    var ownsFullGame: Bool {
        return defaults.bool(forKey: SpudEntitlementRepository.key)
    }

    func save(_ state: EntitlementState) {
        defaults.set(state.contains(.spudFullGame), forKey: SpudEntitlementRepository.key)
    }
}

private struct SpudFulfillmentHandler: CommerceFulfillmentHandler {
    let repository: SpudEntitlementRepository

    func fulfill(_ fulfillment: CommerceFulfillment) async throws {
        repository.save(fulfillment.entitlementState)
    }
}

@MainActor
final class SpudStore: ObservableObject {
    enum Status: Equatable {
        /// No product in the Info.plist (or no store).
        case unconfigured
        case loading
        case ready
        /// The products could not be loaded (offline, or the App Store did not answer).
        case unavailable
        case purchasing
        case restoring
    }

    /// The last answer worth a line on the unlock screen; a cancelled purchase shows nothing.
    enum Notice: Equatable {
        case pending
        case purchaseFailed
        case restoreFailed
        case nothingToRestore
    }

    @Published private(set) var ownsFullGame: Bool
    @Published private(set) var product: CommerceProduct?
    @Published private(set) var status: Status
    @Published private(set) var notice: Notice?
    @Published private(set) var paint: PaintBalloonAllowance
    /// The unlock screen covers the current page (`RootView`).
    @Published private(set) var unlockVisible = false

    let configuration: SpudStoreConfiguration
    private let store: (any CommerceStore)?
    private let repository: SpudEntitlementRepository
    private let paintRepository: PaintBalloonAllowanceRepository
    private let clock: () -> Date
    private let calendar: Calendar
    /// App Store captures (`SpudScreenshot`) show the whole game.
    private let isStoreScreenshotCapture: Bool
    private var updateTask: Task<Void, Never>?
    private var relay: AnyCancellable?
    private var hasStarted = false

    init(configuration: SpudStoreConfiguration,
         store: (any CommerceStore)?,
         repository: SpudEntitlementRepository = SpudEntitlementRepository(),
         paintRepository: PaintBalloonAllowanceRepository = PaintBalloonAllowanceRepository(),
         clock: @escaping () -> Date = { Date() },
         calendar: Calendar = .autoupdatingCurrent,
         isStoreScreenshotCapture: Bool = SpudScreenshot.name != nil) {
        self.configuration = configuration
        self.store = store
        self.repository = repository
        self.paintRepository = paintRepository
        self.clock = clock
        self.calendar = calendar
        self.isStoreScreenshotCapture = isStoreScreenshotCapture
        ownsFullGame = repository.ownsFullGame
        paint = paintRepository.load()
        status = store == nil ? .unconfigured : .loading
    }

    /// The app's store: StoreKit for the product named in the Info.plist.
    static func make(bundle: Bundle = .main) -> SpudStore {
        let configuration = SpudStoreConfiguration.load(bundle: bundle)
        let repository = SpudEntitlementRepository()
        guard let catalog = configuration.catalog else {
            return SpudStore(configuration: configuration, store: nil, repository: repository)
        }
        let store = StoreKitCommerceStore(catalog: catalog, fulfillmentHandler: SpudFulfillmentHandler(repository: repository))
        return SpudStore(configuration: configuration, store: store, repository: repository)
    }

    /// Everything is open: the purchase (or a Family Sharing grant), or an App Store capture.
    var fullGame: Bool {
        return ownsFullGame || isStoreScreenshotCapture
    }

    var isBusy: Bool {
        return status == .loading || status == .purchasing || status == .restoring
    }

    /// Redraws `target` (the app model) whenever this store changes, so its pages follow the purchase.
    func relayChanges(to target: ObservableObjectPublisher) {
        relay = objectWillChange.sink { [weak target] _ in target?.send() }
    }

    // MARK: Unlock screen

    func openUnlock() {
        notice = nil
        unlockVisible = true
        if product == nil && !isBusy && store != nil {
            Task { [weak self] in await self?.reload() }
        }
    }

    func closeUnlock() {
        unlockVisible = false
        notice = nil
    }

    // MARK: Paint balloon

    /// Free paint-balloon games that can start now (`Int.max` with the full game).
    var paintGamesLeft: Int {
        if fullGame { return Int.max }
        return paint.gamesLeft(now: clock(), calendar: calendar)
    }

    /// One paint-balloon game starts: with the full game always; otherwise it uses a free game, or returns false.
    func usePaintGame() -> Bool {
        if fullGame { return true }
        guard let next = paint.consuming(now: clock(), calendar: calendar) else { return false }
        paint = next
        paintRepository.save(next)
        return true
    }

    // MARK: App Store

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
        await loadProductsAndEntitlements()
    }

    /// Loads the price again (the unlock screen's Load the price again, or opening it without a price).
    func reload() async {
        guard store != nil, !isBusy else { return }
        await loadProductsAndEntitlements()
    }

    /// Buys the full game; the caller has passed the grown-up gate.
    func purchase() async {
        guard let store, let productID = configuration.productID else {
            status = .unconfigured
            return
        }
        guard !isBusy else { return }
        notice = nil
        status = .purchasing
        do {
            switch try await store.purchase(productID: productID) {
            case .purchased(let state):
                apply(state)
                status = .ready
                if !ownsFullGame { notice = .purchaseFailed }
            case .pending:
                // Ask to Buy: the grown-up's approval arrives later as a transaction update.
                status = .ready
                notice = .pending
            case .userCancelled:
                status = .ready
            }
        } catch {
            status = product == nil ? .unavailable : .ready
            notice = .purchaseFailed
        }
    }

    /// Restores the purchase (no grown-up gate: it buys nothing).
    func restore() async {
        guard let store else {
            status = .unconfigured
            return
        }
        guard !isBusy else { return }
        notice = nil
        status = .restoring
        do {
            let state = try await store.restorePurchases()
            apply(state)
            if !ownsFullGame { notice = .nothingToRestore }
        } catch {
            notice = .restoreFailed
        }
        status = product == nil ? .unavailable : .ready
    }

    private func loadProductsAndEntitlements() async {
        guard let store, let productID = configuration.productID else {
            status = .unconfigured
            return
        }
        status = .loading
        let loaded = try? await store.loadProducts()
        if let state = try? await store.refreshEntitlements() {
            apply(state)
        }
        if let loaded {
            product = loaded.first { $0.id == productID }
        }
        status = product == nil ? .unavailable : .ready
    }

    /// The App Store's answer decides: owned unlocks everything, not owned (a refund, a revoked Family Sharing grant)
    /// locks the free tier again.
    private func apply(_ state: EntitlementState) {
        repository.save(state)
        let owned = state.contains(.spudFullGame)
        if ownsFullGame != owned { ownsFullGame = owned }
        if owned, notice == .pending { notice = nil }
    }

    private func apply(_ update: CommerceTransactionUpdate) {
        switch update {
        case .entitlements(let state):
            apply(state)
        case .failure:
            break
        }
    }

    deinit {
        updateTask?.cancel()
    }
}
