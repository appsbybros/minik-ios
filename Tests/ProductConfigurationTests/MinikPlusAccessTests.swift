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

    // MARK: - The window once a day during the free week (owner, 16 November 2026)

    func testDailyWindowDayFollowsTheDevicesLocalDate() {
        let jerusalem = calendar("Asia/Jerusalem")
        let morning = localDate(2026, 11, 16, 8, 0, in: jerusalem)
        let lateEvening = localDate(2026, 11, 16, 23, 59, in: jerusalem)
        let afterMidnight = localDate(2026, 11, 17, 0, 1, in: jerusalem)
        XCTAssertEqual(dayKey(morning, jerusalem), dayKey(lateEvening, jerusalem))
        XCTAssertNotEqual(dayKey(lateEvening, jerusalem), dayKey(afterMidnight, jerusalem))
        XCTAssertEqual(afterMidnight.timeIntervalSince(lateEvening), 120)

        // The same moment is another day in another time zone: 23:30 in London on 16 November is
        // already the 17th in Jerusalem.
        let london = calendar("Europe/London")
        let instant = localDate(2026, 11, 16, 23, 30, in: london)
        XCTAssertEqual(dayKey(instant, london), "1-2026-11-16")
        XCTAssertEqual(dayKey(instant, jerusalem), "1-2026-11-17")
    }

    func testDailyWindowOpensOnlyDuringTheFreeWeekAndOncePerDay() {
        let jerusalem = calendar("Asia/Jerusalem")
        let now = localDate(2026, 11, 16, 9, 0, in: jerusalem)
        let today = dayKey(now, jerusalem)
        let yesterday = dayKey(localDate(2026, 11, 15, 23, 50, in: jerusalem), jerusalem)
        let tomorrow = dayKey(localDate(2026, 11, 17, 0, 10, in: jerusalem), jerusalem)

        // During the free week: the first time today, not again today.
        XCTAssertTrue(opensByItself(.trial(daysLeft: 5), lastShownDay: nil, now: now, jerusalem))
        XCTAssertTrue(opensByItself(.trial(daysLeft: 5), lastShownDay: yesterday, now: now, jerusalem))
        XCTAssertTrue(opensByItself(.trial(daysLeft: 1), lastShownDay: yesterday, now: now, jerusalem))
        XCTAssertFalse(opensByItself(.trial(daysLeft: 5), lastShownDay: today, now: now, jerusalem))
        // A clock set back to an earlier day is another day: once more, then not again that day.
        XCTAssertTrue(opensByItself(.trial(daysLeft: 5), lastShownDay: tomorrow, now: now, jerusalem))

        // Full access never; before and after the week the window is up anyway (not this rule).
        for access in [MinikPlusAccess.fullAccess, .trialNotStarted, .trialEnded] {
            XCTAssertFalse(opensByItself(access, lastShownDay: nil, now: now, jerusalem), "\(access)")
            XCTAssertFalse(opensByItself(access, lastShownDay: yesterday, now: now, jerusalem), "\(access)")
        }
    }

    func testRecordsSavedBeforeTheDailyWindowStillLoad() throws {
        let defaults = makeDefaults()
        let repository = MinikPlusAccessRepository(userDefaults: defaults)
        // A record as 1.8.0 (2021) saved it, without windowShownDay.
        struct EarlierRecord: Codable {
            var ownsFullAccess: Bool
            var freeWeekStartedAt: Date?
            var latestSeenAt: Date?
        }
        let earlier = EarlierRecord(ownsFullAccess: false, freeWeekStartedAt: start, latestSeenAt: start)
        defaults.set(try JSONEncoder().encode(earlier), forKey: "minik.plus-access.v1.\(ProductVariant.minikPlus.rawValue)")

        let record = repository.load(for: .minikPlus)
        XCTAssertEqual(record.freeWeekStartedAt, start)
        XCTAssertEqual(record.latestSeenAt, start)
        XCTAssertNil(record.windowShownDay)
    }

    @MainActor
    func testDuringTheFreeWeekTheWindowOpensByItselfOnceEachDay() async {
        let jerusalem = calendar("Asia/Jerusalem")
        let weekStart = localDate(2026, 11, 16, 9, 0, in: jerusalem)
        let clock = TestClock(weekStart.addingTimeInterval(3600))
        let accessDefaults = makeDefaults()
        let store = InMemoryCommerceStore(
            products: products(),
            entitlementState: EntitlementState(activeEntitlementIDs: [.minikPlusFreeWeek])
        )
        let controller = makeController(
            store: store,
            clock: clock,
            reader: FixedFreeWeekStartReader(start: weekStart),
            calendar: jerusalem,
            accessDefaults: accessDefaults
        )
        await controller.start()
        XCTAssertEqual(controller.plusAccess, .trial(daysLeft: 7))

        // The first time the app becomes active today: the window, with the days left; it closes.
        XCTAssertFalse(controller.evaluateAccessOnBecomingActive())
        XCTAssertTrue(controller.showsPaywall)
        controller.dismissRequestedPaywall()
        XCTAssertFalse(controller.showsPaywall)

        // Again the same day, also late in the evening: nothing.
        clock.now = localDate(2026, 11, 16, 23, 55, in: jerusalem)
        XCTAssertFalse(controller.evaluateAccessOnBecomingActive())
        XCTAssertFalse(controller.showsPaywall)

        // Past midnight, starting an activity (not becoming active) does not open it.
        clock.now = localDate(2026, 11, 17, 0, 5, in: jerusalem)
        XCTAssertFalse(controller.evaluateAccess())
        XCTAssertFalse(controller.showsPaywall)

        // The first time the app becomes active on the next day: the window again.
        clock.now = localDate(2026, 11, 17, 7, 30, in: jerusalem)
        XCTAssertFalse(controller.evaluateAccessOnBecomingActive())
        XCTAssertTrue(controller.showsPaywall)
        XCTAssertEqual(controller.plusAccess, .trial(daysLeft: 7))
        controller.dismissRequestedPaywall()

        // A relaunch the same day remembers it was shown.
        let relaunched = makeController(
            store: store,
            clock: clock,
            reader: FixedFreeWeekStartReader(start: weekStart),
            calendar: jerusalem,
            accessDefaults: accessDefaults
        )
        clock.now = localDate(2026, 11, 17, 18, 0, in: jerusalem)
        XCTAssertFalse(relaunched.evaluateAccessOnBecomingActive())
        XCTAssertFalse(relaunched.showsPaywall)
        XCTAssertEqual(relaunched.plusAccess, .trial(daysLeft: 6))

        // After the week the wall is up and cannot be closed.
        clock.now = weekStart.addingTimeInterval(7 * day)
        XCTAssertTrue(relaunched.evaluateAccessOnBecomingActive())
        XCTAssertEqual(relaunched.plusAccess, .trialEnded)
        relaunched.dismissRequestedPaywall()
        XCTAssertTrue(relaunched.showsPaywall)
        await store.finishUpdates()
    }

    @MainActor
    func testTheDayTheWeekStartsTheWelcomeCountsAsThatDaysWindow() async {
        let jerusalem = calendar("Asia/Jerusalem")
        let clock = TestClock(localDate(2026, 11, 16, 10, 0, in: jerusalem))
        let store = InMemoryCommerceStore(
            products: products(),
            outcomeByProductID: [
                freeWeekID: .purchased(EntitlementState(activeEntitlementIDs: [.minikPlusFreeWeek]))
            ]
        )
        let controller = makeController(store: store, clock: clock, reader: TestFreeWeekLedger(), calendar: jerusalem)
        // Before the week: the welcome at every launch, and it cannot be closed.
        XCTAssertTrue(controller.evaluateAccessOnBecomingActive())
        await controller.start()
        XCTAssertEqual(controller.plusAccess, .trialNotStarted)
        controller.dismissRequestedPaywall()
        XCTAssertTrue(controller.showsPaywall)

        await controller.startFreeWeek()
        XCTAssertEqual(controller.plusAccess, .trial(daysLeft: 7))
        XCTAssertFalse(controller.showsPaywall)

        clock.now = localDate(2026, 11, 16, 20, 0, in: jerusalem)
        XCTAssertFalse(controller.evaluateAccessOnBecomingActive())
        XCTAssertFalse(controller.showsPaywall)

        clock.now = localDate(2026, 11, 17, 8, 0, in: jerusalem)
        XCTAssertFalse(controller.evaluateAccessOnBecomingActive())
        XCTAssertTrue(controller.showsPaywall)
        await store.finishUpdates()
    }

    @MainActor
    func testFullAccessNeverOpensTheDailyWindow() async {
        let jerusalem = calendar("Asia/Jerusalem")
        let clock = TestClock(localDate(2026, 11, 16, 10, 0, in: jerusalem))
        let store = InMemoryCommerceStore(
            products: products(),
            entitlementState: EntitlementState(activeEntitlementIDs: [.minikPlusFreeWeek, .minikPlusFullAccess])
        )
        let controller = makeController(
            store: store,
            clock: clock,
            reader: FixedFreeWeekStartReader(start: start),
            calendar: jerusalem
        )
        await controller.start()
        for dayOffset in 0..<10 {
            clock.now = localDate(2026, 11, 16 + dayOffset, 9, 0, in: jerusalem)
            XCTAssertFalse(controller.evaluateAccessOnBecomingActive())
            XCTAssertFalse(controller.showsPaywall)
        }
        await store.finishUpdates()
    }

    // MARK: - When the App Store does not answer (1.8.0 (2021) on a real iPhone)

    @MainActor
    func testWithoutTheProductsTheWindowStopsWaitingAndStartFreeWeekStillLetsTheChildIn() async {
        let accessDefaults = makeDefaults()
        let clock = TestClock(start)
        // The App Store answers, but without the products (not yet ready in App Store Connect).
        let store = ScriptedCommerceStore(products: [])
        let controller = makeController(store: store, clock: clock, accessDefaults: accessDefaults)
        await controller.start()
        XCTAssertEqual(controller.status, .failed)
        XCTAssertEqual(controller.storeProblem, .productUnavailable, "online: never blame the internet")
        XCTAssertFalse(controller.isBusy)
        XCTAssertNil(controller.fullAccessProduct)
        XCTAssertEqual(controller.plusAccess, .trialNotStarted)

        await controller.startFreeWeek()
        XCTAssertEqual(controller.plusAccess, .trial(daysLeft: 7))
        XCTAssertFalse(controller.showsPaywall)
        XCTAssertFalse(controller.isBusy)

        // The week counts from that moment on this device, also after a relaunch.
        clock.now = start.addingTimeInterval(7 * day)
        let relaunched = makeController(store: store, clock: clock, accessDefaults: accessDefaults)
        XCTAssertEqual(relaunched.plusAccess, .trialEnded)
    }

    @MainActor
    func testAStoreThatNeverAnswersTimesOutAndTheFreeWeekStillStarts() async {
        let store = ScriptedCommerceStore(products: products(), answersProductRequests: false)
        let controller = makeController(store: store, storeRequestTimeout: .milliseconds(200))
        await controller.start()
        XCTAssertEqual(controller.status, .failed)
        XCTAssertEqual(controller.storeProblem, .notAnswering)
        XCTAssertFalse(controller.isBusy)
        XCTAssertNil(controller.fullAccessProduct)

        await controller.startFreeWeek()
        XCTAssertEqual(controller.plusAccess, .trial(daysLeft: 7))
        XCTAssertFalse(controller.showsPaywall)
    }

    @MainActor
    func testALaterTryAgainFillsInThePrice() async {
        let store = ScriptedCommerceStore(products: [])
        let controller = makeController(store: store)
        await controller.start()
        XCTAssertEqual(controller.status, .failed)

        await store.setProducts(products())
        await controller.reloadStore()
        XCTAssertEqual(controller.status, .ready)
        XCTAssertEqual(controller.fullAccessProduct?.displayPrice, "$9.99")
        XCTAssertEqual(controller.freeWeekProduct?.id, freeWeekID)
    }

    @MainActor
    func testAFreeWeekPurchaseThatFailsOrWaitsStartsTheWeekOnTheDevice() async {
        // The product loads, but taking it fails (here: no outcome configured, so it throws).
        let failing = InMemoryCommerceStore(products: products())
        let failingController = makeController(store: failing)
        await failingController.start()
        await failingController.startFreeWeek()
        XCTAssertEqual(failingController.plusAccess, .trial(daysLeft: 7))
        XCTAssertEqual(failingController.status, .ready)
        await failing.finishUpdates()

        // Ask to Buy: the approval waits; the child is not kept waiting.
        let pending = InMemoryCommerceStore(products: products(), outcomeByProductID: [freeWeekID: .pending])
        let pendingController = makeController(store: pending)
        await pendingController.start()
        await pendingController.startFreeWeek()
        XCTAssertEqual(pendingController.plusAccess, .trial(daysLeft: 7))
        await pending.finishUpdates()
    }

    @MainActor
    func testCancellingTheFreeWeekKeepsTheWelcome() async {
        let store = InMemoryCommerceStore(products: products(), outcomeByProductID: [freeWeekID: .userCancelled])
        let controller = makeController(store: store)
        await controller.start()
        await controller.startFreeWeek()
        XCTAssertEqual(controller.status, .cancelled)
        XCTAssertEqual(controller.plusAccess, .trialNotStarted)
        XCTAssertTrue(controller.showsPaywall)
        await store.finishUpdates()
    }

    @MainActor
    func testBuyingFullAccessStillNeedsTheStore() async {
        let store = ScriptedCommerceStore(products: [])
        let controller = makeController(store: store)
        await controller.start()
        await controller.purchaseFullAccess()
        XCTAssertEqual(controller.status, .failed)
        XCTAssertEqual(controller.storeProblem, .productUnavailable)
        XCTAssertEqual(controller.plusAccess, .trialNotStarted)
    }

    // MARK: - The message names the real problem (bug report of 22 November 2026)

    @MainActor
    func testOnlyAnOfflineDeviceIsToldToCheckTheInternet() async {
        let offline = makeController(
            store: ScriptedCommerceStore(products: products(), answersProductRequests: false),
            storeRequestTimeout: .milliseconds(200),
            isOffline: { true }
        )
        await offline.start()
        XCTAssertEqual(offline.status, .failed)
        XCTAssertEqual(offline.storeProblem, .offline)

        let online = makeController(
            store: ScriptedCommerceStore(products: products(), answersProductRequests: false),
            storeRequestTimeout: .milliseconds(200),
            isOffline: { false }
        )
        await online.start()
        XCTAssertEqual(online.storeProblem, .notAnswering)
    }

    @MainActor
    func testAnEmptyAnswerSaysTheProductIsNotAvailableEvenWhenOffline() async {
        // The App Store did answer, so the device reached it: the product is what is missing.
        let controller = makeController(store: ScriptedCommerceStore(products: []), isOffline: { true })
        await controller.start()
        XCTAssertEqual(controller.storeProblem, .productUnavailable)
    }

    @MainActor
    func testAFailedPurchaseWithPurchasesTurnedOffSaysSo() async {
        // The products load; the purchase fails (no outcome configured, so it throws).
        let store = InMemoryCommerceStore(products: products())
        let restricted = makeController(store: store, canMakePayments: { false })
        await restricted.start()
        XCTAssertEqual(restricted.status, .ready)
        await restricted.purchaseFullAccess()
        XCTAssertEqual(restricted.status, .failed)
        XCTAssertEqual(restricted.storeProblem, .purchasesNotAllowed)
        await store.finishUpdates()

        let other = InMemoryCommerceStore(products: products())
        let allowed = makeController(store: other, canMakePayments: { true })
        await allowed.start()
        await allowed.purchaseFullAccess()
        XCTAssertEqual(allowed.storeProblem, .notAnswering)
        await other.finishUpdates()
    }

    @MainActor
    func testALaterAnswerReplacesTheEarlierProblem() async {
        let store = ScriptedCommerceStore(products: [])
        let controller = makeController(store: store)
        await controller.start()
        XCTAssertEqual(controller.storeProblem, .productUnavailable)
        await store.setProducts(products())
        await controller.reloadStore()
        XCTAssertEqual(controller.status, .ready)
        XCTAssertNotNil(controller.fullAccessProduct)
    }

    func testButtonLabelsMoveOnlyALittleToCenterTheirLetters() {
        XCTAssertEqual(MinikPretty.inkCenterOffset("", fontSize: 22), 0)
        for label in ["Unlock everything", "Continue", "פתחו את הכול", "המשך", "Открыть всё"] {
            let offset = MinikPretty.inkCenterOffset(label, fontSize: 22)
            XCTAssertLessThanOrEqual(abs(offset), 22 * 0.2, label)
        }
    }

    func testStoreDeadlinePassesAnswersAndErrorsAndStopsWaiting() async throws {
        let value = try await MinikStoreDeadline.value(within: .seconds(5)) { 42 }
        XCTAssertEqual(value, 42)

        do {
            _ = try await MinikStoreDeadline.value(within: .seconds(5)) { () async throws -> Int in
                throw CommerceError.verificationFailed
            }
            XCTFail("The error should pass through.")
        } catch {
            XCTAssertEqual(error as? CommerceError, .verificationFailed)
        }

        let began = Date()
        do {
            _ = try await MinikStoreDeadline.value(within: .milliseconds(100)) { () async throws -> Int in
                try await Task.sleep(for: .seconds(60))
                return 0
            }
            XCTFail("The deadline should end the wait.")
        } catch {
            XCTAssertTrue(error is MinikStoreDeadline.Expired)
        }
        XCTAssertLessThan(Date().timeIntervalSince(began), 10)
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
        store: any CommerceStore,
        clock: TestClock? = nil,
        reader: (any MinikFreeWeekStartReading)? = nil,
        calendar: Calendar? = nil,
        accessDefaults: UserDefaults? = nil,
        storeRequestTimeout: Duration = .seconds(12),
        isOffline: @escaping @Sendable () -> Bool = { false },
        canMakePayments: @escaping @Sendable () -> Bool = { true }
    ) -> MinikCommerceController {
        let resolvedClock = clock ?? TestClock(start)
        return MinikCommerceController(
            configuration: paywallConfiguration(),
            store: store,
            repository: MinikCommerceEntitlementRepository(userDefaults: makeDefaults()),
            accessRepository: MinikPlusAccessRepository(userDefaults: accessDefaults ?? makeDefaults()),
            freeWeekStartReader: reader,
            clock: { resolvedClock.now },
            calendar: calendar ?? self.calendar("Asia/Jerusalem"),
            storeRequestTimeout: storeRequestTimeout,
            isStoreScreenshotCapture: false,
            isOffline: isOffline,
            canMakePayments: canMakePayments
        )
    }

    private func calendar(_ timeZoneIdentifier: String) -> Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: timeZoneIdentifier)!
        return calendar
    }

    private func localDate(
        _ year: Int,
        _ month: Int,
        _ day: Int,
        _ hour: Int,
        _ minute: Int,
        in calendar: Calendar
    ) -> Date {
        calendar.date(from: DateComponents(year: year, month: month, day: day, hour: hour, minute: minute))!
    }

    private func dayKey(_ date: Date, _ calendar: Calendar) -> String {
        MinikPlusDailyWindowPolicy.dayKey(for: date, calendar: calendar)
    }

    private func opensByItself(
        _ access: MinikPlusAccess,
        lastShownDay: String?,
        now: Date,
        _ calendar: Calendar
    ) -> Bool {
        MinikPlusDailyWindowPolicy.opensByItself(
            access: access,
            lastShownDay: lastShownDay,
            now: now,
            calendar: calendar
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

/// A store whose product request can come back empty or never answer, like StoreKit before the
/// products are ready in App Store Connect, or on a network that does not answer.
private actor ScriptedCommerceStore: CommerceStore {
    private var products: [CommerceProduct]
    private let answersProductRequests: Bool

    init(products: [CommerceProduct], answersProductRequests: Bool = true) {
        self.products = products
        self.answersProductRequests = answersProductRequests
    }

    func setProducts(_ products: [CommerceProduct]) {
        self.products = products
    }

    func loadProducts() async throws -> [CommerceProduct] {
        if !answersProductRequests {
            try await Task.sleep(for: .seconds(60))
        }
        return products
    }

    func purchase(productID: CommerceProductID) async throws -> PurchaseOutcome {
        guard answersProductRequests, products.contains(where: { $0.id == productID }) else {
            throw CommerceError.productNotFound(productID)
        }
        return .userCancelled
    }

    func refreshEntitlements() async throws -> EntitlementState {
        EntitlementState()
    }

    func restorePurchases() async throws -> EntitlementState {
        EntitlementState()
    }

    func transactionUpdates() async -> AsyncStream<CommerceTransactionUpdate> {
        AsyncStream { continuation in
            continuation.finish()
        }
    }
}
