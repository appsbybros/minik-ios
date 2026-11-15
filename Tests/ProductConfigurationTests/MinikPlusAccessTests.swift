import AppStoreCommerceKit
import XCTest
@testable import MinikPlus

/// Minik Plus and Minik Plus English: no ads, a free week, then a one-time purchase
/// (docs/minik-plus-paywall-ios.md).
final class MinikPlusAccessTests: XCTestCase {
    private let day = MinikPlusAccessPolicy.day
    private let start = Date(timeIntervalSinceReferenceDate: 800_000_000)
    private let fullAccessID = CommerceProductID(rawValue: "test.plus.full-access")
    private let freeWeekID = CommerceProductID(rawValue: "test.plus.free-week")
    private let legacyID = CommerceProductID(rawValue: "test.plus.remove-ads")

    // MARK: - Trial math

    func testNothingStartedLocksTheApp() {
        let access = MinikPlusAccessPolicy.access(ownsFullAccess: false, freeWeekStartedAt: nil, now: start)
        XCTAssertEqual(access, .trialNotStarted)
        XCTAssertTrue(access.isLocked)
    }

    func testFreeWeekCountsSevenDaysRoundedUpAndThenLocks() {
        XCTAssertEqual(access(now: start), .trial(daysLeft: 7))
        XCTAssertEqual(access(now: start.addingTimeInterval(1)), .trial(daysLeft: 7))
        XCTAssertEqual(access(now: start.addingTimeInterval(day)), .trial(daysLeft: 6))
        XCTAssertEqual(access(now: start.addingTimeInterval(day + 1)), .trial(daysLeft: 6))
        XCTAssertEqual(access(now: start.addingTimeInterval(6 * day)), .trial(daysLeft: 1))
        XCTAssertEqual(access(now: start.addingTimeInterval(7 * day - 1)), .trial(daysLeft: 1))
        XCTAssertFalse(access(now: start.addingTimeInterval(7 * day - 1)).isLocked)
        XCTAssertEqual(access(now: start.addingTimeInterval(7 * day)), .trialEnded)
        XCTAssertEqual(access(now: start.addingTimeInterval(400 * day)), .trialEnded)
        XCTAssertTrue(access(now: start.addingTimeInterval(7 * day)).isLocked)
    }

    func testClockSetBackNeverExtendsTheWeek() {
        // Before the start, the week is whole and never longer.
        XCTAssertEqual(access(now: start.addingTimeInterval(-3 * day)), .trial(daysLeft: 7))
        // The device has seen day 6.5; a clock set back to day 1 still has half a day left.
        XCTAssertEqual(
            access(now: start.addingTimeInterval(day), latestSeenAt: start.addingTimeInterval(6.5 * day)),
            .trial(daysLeft: 1)
        )
        // The device has seen the end of the week; setting the clock back does not reopen it.
        XCTAssertEqual(
            access(now: start.addingTimeInterval(2 * day), latestSeenAt: start.addingTimeInterval(8 * day)),
            .trialEnded
        )
        XCTAssertEqual(
            access(now: start.addingTimeInterval(-30 * day), latestSeenAt: start.addingTimeInterval(7 * day)),
            .trialEnded
        )
    }

    func testFullAccessOpensEverythingForeverWithOrWithoutAFreeWeek() {
        XCTAssertEqual(
            MinikPlusAccessPolicy.access(ownsFullAccess: true, freeWeekStartedAt: nil, now: start),
            .fullAccess
        )
        XCTAssertEqual(
            MinikPlusAccessPolicy.access(
                ownsFullAccess: true,
                freeWeekStartedAt: start,
                now: start.addingTimeInterval(365 * day)
            ),
            .fullAccess
        )
        XCTAssertFalse(MinikPlusAccess.fullAccess.isLocked)
    }

    func testRecordedFreeWeekStartOnlyMovesEarlierAndTheLatestSeenTimeOnlyLater() {
        var record = MinikPlusAccessRecord()
        record.recordFreeWeekStart(start)
        record.recordFreeWeekStart(start.addingTimeInterval(3 * day))
        XCTAssertEqual(record.freeWeekStartedAt, start)
        record.recordFreeWeekStart(start.addingTimeInterval(-day))
        XCTAssertEqual(record.freeWeekStartedAt, start.addingTimeInterval(-day))

        record.recordSeen(start.addingTimeInterval(5 * day))
        record.recordSeen(start)
        XCTAssertEqual(record.latestSeenAt, start.addingTimeInterval(5 * day))
    }

    func testAccessRecordPersistsPerProduct() throws {
        let defaults = try XCTUnwrap(UserDefaults(suiteName: "MinikPlusAccessTests.\(UUID().uuidString)"))
        let repository = MinikPlusAccessRepository(userDefaults: defaults)
        var record = MinikPlusAccessRecord()
        record.recordFreeWeekStart(start)
        record.ownsFullAccess = true
        repository.save(record, for: .minikPlus)

        XCTAssertEqual(repository.load(for: .minikPlus), record)
        XCTAssertEqual(repository.load(for: .minikPlusEnglish), MinikPlusAccessRecord())
    }

    // MARK: - Products and grandfathering

    func testPaywallNeedsBothFullAccessAndFreeWeekProducts() {
        XCTAssertNil(MinikPaywallProducts(
            fullAccessProductIdentifier: nil,
            freeWeekProductIdentifier: freeWeekID.rawValue,
            legacyRemoveAdsProductIdentifier: legacyID.rawValue
        ))
        XCTAssertNil(MinikPaywallProducts(
            fullAccessProductIdentifier: fullAccessID.rawValue,
            freeWeekProductIdentifier: "  ",
            legacyRemoveAdsProductIdentifier: nil
        ))
        XCTAssertNil(MinikPaywallProducts(
            fullAccessProductIdentifier: "same",
            freeWeekProductIdentifier: "same",
            legacyRemoveAdsProductIdentifier: nil
        ))
    }

    func testCatalogGrandfathersTheEarlierRemoveAdsAsFullAccess() throws {
        let catalog = try XCTUnwrap(paywallConfiguration().catalog)
        XCTAssertEqual(catalog.entitlement(for: fullAccessID), .minikPlusFullAccess)
        XCTAssertEqual(catalog.entitlement(for: legacyID), .minikPlusFullAccess)
        XCTAssertEqual(catalog.entitlement(for: freeWeekID), .minikPlusFreeWeek)
        XCTAssertEqual(catalog.productIDs, [fullAccessID, freeWeekID, legacyID])
        XCTAssertEqual(catalog.supportedProductKinds, [.nonConsumable])
        XCTAssertFalse(catalog.entitlementByProductID.values.contains(.minikRemoveAds))
    }

    @MainActor
    func testEarlierRemoveAdsOwnerNeverSeesTheWall() async {
        let store = InMemoryCommerceStore(
            products: products(),
            entitlementState: EntitlementState(activeEntitlementIDs: [.minikPlusFullAccess])
        )
        let controller = makeController(store: store)
        await controller.start()

        XCTAssertEqual(controller.plusAccess, .fullAccess)
        XCTAssertFalse(controller.showsPaywall)
        XCTAssertFalse(controller.evaluateAccess())
        await store.finishUpdates()
    }

    @MainActor
    func testRemoveAdsRememberedByAnEarlierVersionUnlocksOffline() throws {
        let defaults = try XCTUnwrap(UserDefaults(suiteName: "MinikPlusAccessTests.\(UUID().uuidString)"))
        let repository = MinikCommerceEntitlementRepository(userDefaults: defaults)
        repository.save(EntitlementState(activeEntitlementIDs: [.minikRemoveAds]), for: .minikPlus)
        let now = start

        let controller = MinikCommerceController(
            configuration: paywallConfiguration(),
            store: nil,
            repository: repository,
            accessRepository: MinikPlusAccessRepository(userDefaults: defaults),
            clock: { now },
            isStoreScreenshotCapture: false
        )

        XCTAssertEqual(controller.plusAccess, .fullAccess)
        XCTAssertFalse(controller.showsPaywall)
    }

    // MARK: - The controller's free week

    @MainActor
    func testFirstLaunchShowsTheWelcomeAndTheFreeWeekUnlocksUntilItEnds() async {
        let clock = TestClock(start)
        let store = InMemoryCommerceStore(
            products: products(),
            outcomeByProductID: [
                freeWeekID: .purchased(EntitlementState(activeEntitlementIDs: [.minikPlusFreeWeek]))
            ]
        )
        // No free-week transaction yet; right after the purchase the week counts from now.
        let ledger = TestFreeWeekLedger()
        let controller = makeController(store: store, clock: clock, reader: ledger)
        await controller.start()
        XCTAssertEqual(controller.plusAccess, .trialNotStarted)
        XCTAssertTrue(controller.showsPaywall)
        XCTAssertEqual(controller.fullAccessProduct?.id, fullAccessID)

        await controller.startFreeWeek()
        XCTAssertEqual(controller.plusAccess, .trial(daysLeft: 7))
        XCTAssertFalse(controller.showsPaywall)

        clock.now = start.addingTimeInterval(3 * day + 60)
        XCTAssertFalse(controller.evaluateAccess())
        XCTAssertEqual(controller.plusAccess, .trial(daysLeft: 4))

        clock.now = start.addingTimeInterval(7 * day)
        XCTAssertTrue(controller.evaluateAccess())
        XCTAssertEqual(controller.plusAccess, .trialEnded)
        XCTAssertTrue(controller.showsPaywall)

        // The clock set back after the week ended does not reopen it.
        clock.now = start.addingTimeInterval(day)
        XCTAssertTrue(controller.evaluateAccess())

        // A later App Store date (another device) never gives a new week.
        ledger.start = start.addingTimeInterval(7 * day)
        await controller.refreshEntitlements()
        XCTAssertEqual(controller.plusAccess, .trialEnded)
        await store.finishUpdates()
    }

    @MainActor
    func testReinstallKeepsTheFreeWeekFromTheAppStoreDate() async {
        // The App Store's transaction says the week began ten days ago.
        let clock = TestClock(start.addingTimeInterval(10 * day))
        let store = InMemoryCommerceStore(
            products: products(),
            entitlementState: EntitlementState(activeEntitlementIDs: [.minikPlusFreeWeek])
        )
        let controller = makeController(store: store, clock: clock, reader: FixedFreeWeekStartReader(start: start))
        await controller.start()

        XCTAssertEqual(controller.plusAccess, .trialEnded)
        XCTAssertTrue(controller.showsPaywall)
        await store.finishUpdates()
    }

    @MainActor
    func testBuyingFullAccessClosesTheWallForGood() async {
        let clock = TestClock(start.addingTimeInterval(8 * day))
        let store = InMemoryCommerceStore(
            products: products(),
            entitlementState: EntitlementState(activeEntitlementIDs: [.minikPlusFreeWeek]),
            outcomeByProductID: [
                fullAccessID: .purchased(EntitlementState(activeEntitlementIDs: [.minikPlusFreeWeek, .minikPlusFullAccess]))
            ]
        )
        let controller = makeController(store: store, clock: clock, reader: FixedFreeWeekStartReader(start: start))
        await controller.start()
        XCTAssertEqual(controller.plusAccess, .trialEnded)

        await controller.purchaseFullAccess()
        XCTAssertEqual(controller.status, .ready)
        XCTAssertEqual(controller.plusAccess, .fullAccess)
        XCTAssertFalse(controller.showsPaywall)

        clock.now = start.addingTimeInterval(900 * day)
        XCTAssertFalse(controller.evaluateAccess())
        await store.finishUpdates()
    }

    @MainActor
    func testTheBuyScreenOpenedDuringTheFreeWeekCanBeClosed() async {
        let clock = TestClock(start.addingTimeInterval(day))
        let store = InMemoryCommerceStore(
            products: products(),
            entitlementState: EntitlementState(activeEntitlementIDs: [.minikPlusFreeWeek])
        )
        let controller = makeController(store: store, clock: clock, reader: FixedFreeWeekStartReader(start: start))
        await controller.start()
        XCTAssertEqual(controller.plusAccess, .trial(daysLeft: 6))
        XCTAssertFalse(controller.showsPaywall)

        controller.requestPaywall()
        XCTAssertTrue(controller.showsPaywall)
        controller.dismissRequestedPaywall()
        XCTAssertFalse(controller.showsPaywall)
        await store.finishUpdates()
    }

    @MainActor
    func testStoreScreenshotCapturesShowTheAppInsteadOfTheWall() {
        let now = start
        let controller = MinikCommerceController(
            configuration: paywallConfiguration(),
            store: nil,
            repository: MinikCommerceEntitlementRepository(userDefaults: makeDefaults()),
            accessRepository: MinikPlusAccessRepository(userDefaults: makeDefaults()),
            clock: { now },
            isStoreScreenshotCapture: true
        )
        XCTAssertFalse(controller.showsPaywall)
        XCTAssertFalse(controller.evaluateAccess())
    }

    // MARK: - Per-target configuration

    /// The test host is the MinikPlus app: its Info.plist names the free week and full access, and
    /// has no ad identifiers, no Remove Ads product and no ad SDK.
    func testMinikPlusTargetHasThePaywallAndNoAds() throws {
        let bundle = Bundle.main
        XCTAssertEqual(
            bundle.object(forInfoDictionaryKey: MinikPaywallProducts.fullAccessProductInfoKey) as? String,
            "minik_plus_full_access"
        )
        XCTAssertEqual(
            bundle.object(forInfoDictionaryKey: MinikPaywallProducts.freeWeekProductInfoKey) as? String,
            "minik_plus_free_week"
        )
        XCTAssertEqual(
            bundle.object(forInfoDictionaryKey: MinikPaywallProducts.legacyRemoveAdsProductInfoKey) as? String,
            "remove_ads_minik"
        )
        for adKey in [
            "GADApplicationIdentifier",
            "SKAdNetworkItems",
            "NSUserTrackingUsageDescription",
            MinikAdsConfiguration.enabledInfoKey,
            MinikAdsConfiguration.applicationIdentifierInfoKey,
            MinikAdsConfiguration.interstitialUnitIdentifierInfoKey,
            MinikCommerceConfiguration.removeAdsProductInfoKey
        ] {
            XCTAssertNil(bundle.object(forInfoDictionaryKey: adKey), adKey)
        }

        let commerce = MinikCommerceConfiguration.load(product: .minikPlus, bundle: bundle)
        XCTAssertNil(commerce.removeAdsProductID)
        XCTAssertEqual(commerce.paywall?.fullAccessProductID.rawValue, "minik_plus_full_access")
        XCTAssertNil(MinikAdsConfiguration.load(product: .minikPlus, bundle: bundle).providerConfiguration)
        // MINIK_NO_ADS: the Google adapter is not compiled and the SDK is not in the process.
        XCTAssertTrue(ProductionMinikInterstitialAdServiceFactory.make() is UnconfiguredMinikInterstitialAdService)
        XCTAssertNil(NSClassFromString("GADMobileAds"))
    }

    /// The other apps keep Remove Ads exactly as before: no paywall, the same one-product catalog,
    /// and never locked.
    @MainActor
    func testAppsWithRemoveAdsKeepTheirCatalogAndAreNeverLocked() throws {
        let removeAdsID = CommerceProductID(rawValue: "test.math.remove-ads")
        for product in [ProductVariant.minikMath, .minikPingPong] {
            let configuration = MinikCommerceConfiguration(
                product: product,
                removeAdsProductIdentifier: removeAdsID.rawValue
            )
            XCTAssertNil(configuration.paywall)
            let catalog = try XCTUnwrap(configuration.catalog)
            XCTAssertEqual(catalog.entitlementByProductID, [removeAdsID: .minikRemoveAds])
            XCTAssertEqual(catalog.supportedProductKinds, [.nonConsumable])

            let controller = MinikCommerceController(
                configuration: configuration,
                store: nil,
                repository: MinikCommerceEntitlementRepository(userDefaults: makeDefaults()),
                accessRepository: MinikPlusAccessRepository(userDefaults: makeDefaults()),
                isStoreScreenshotCapture: false
            )
            XCTAssertFalse(controller.isPaywallConfigured)
            XCTAssertEqual(controller.plusAccess, .fullAccess)
            XCTAssertFalse(controller.showsPaywall)
            XCTAssertFalse(controller.evaluateAccess())
            controller.requestPaywall()
            XCTAssertFalse(controller.showsPaywall)
        }
    }

    // MARK: - Helpers

    private func access(now: Date, latestSeenAt: Date? = nil) -> MinikPlusAccess {
        MinikPlusAccessPolicy.access(
            ownsFullAccess: false,
            freeWeekStartedAt: start,
            now: now,
            latestSeenAt: latestSeenAt
        )
    }

    private func paywallConfiguration() -> MinikCommerceConfiguration {
        MinikCommerceConfiguration(
            product: .minikPlus,
            removeAdsProductIdentifier: nil,
            paywall: MinikPaywallProducts(
                fullAccessProductIdentifier: fullAccessID.rawValue,
                freeWeekProductIdentifier: freeWeekID.rawValue,
                legacyRemoveAdsProductIdentifier: legacyID.rawValue
            )
        )
    }

    private func products() -> [CommerceProduct] {
        [
            CommerceProduct(id: fullAccessID, displayName: "Full access", displayPrice: "$9.99", kind: .nonConsumable),
            CommerceProduct(id: freeWeekID, displayName: "7-day Trial", displayPrice: "Free", kind: .nonConsumable)
        ]
    }

    @MainActor
    private func makeController(
        store: InMemoryCommerceStore,
        clock: TestClock? = nil,
        reader: (any MinikFreeWeekStartReading)? = nil
    ) -> MinikCommerceController {
        let resolvedClock = clock ?? TestClock(start)
        return MinikCommerceController(
            configuration: paywallConfiguration(),
            store: store,
            repository: MinikCommerceEntitlementRepository(userDefaults: makeDefaults()),
            accessRepository: MinikPlusAccessRepository(userDefaults: makeDefaults()),
            freeWeekStartReader: reader,
            clock: { resolvedClock.now },
            isStoreScreenshotCapture: false
        )
    }

    private func makeDefaults() -> UserDefaults {
        UserDefaults(suiteName: "MinikPlusAccessTests.\(UUID().uuidString)")!
    }
}

private final class TestClock: @unchecked Sendable {
    var now: Date

    init(_ now: Date) {
        self.now = now
    }
}

private final class TestFreeWeekLedger: MinikFreeWeekStartReading, @unchecked Sendable {
    var start: Date?

    func freeWeekStart(for productID: CommerceProductID) async -> Date? {
        start
    }
}

private struct FixedFreeWeekStartReader: MinikFreeWeekStartReading {
    let start: Date?

    func freeWeekStart(for productID: CommerceProductID) async -> Date? {
        start
    }
}
