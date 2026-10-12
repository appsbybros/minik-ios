import XCTest
@testable import MinikMath

/// An ad service that shows nothing: it counts presentations and dismissal waits.
private actor FakeAdService: MinikInterstitialAdService {
    private(set) var presentations = 0
    private(set) var dismissalWaits = 0
    private let result: MinikInterstitialPresentationResult

    init(result: MinikInterstitialPresentationResult = .presented) {
        self.result = result
    }

    func configure(_ configuration: MinikAdProviderConfiguration) async -> Bool { true }

    func presentInterstitial() async -> MinikInterstitialPresentationResult {
        presentations += 1
        return result
    }

    func waitUntilDismissed() async {
        dismissalWaits += 1
    }
}

private final class TestClock {
    var milliseconds: Int64 = 10_000_000
    var uptime: TimeInterval = 100
}

/// Android's AdCoordinator.finishActivity rules around MinikMathAdPolicy: free rounds, the ad
/// before the results, removed ads, leaving the app, and play time.
@MainActor
final class MinikMathAdCoordinatorTests: XCTestCase {
    /// A coordinator with its own defaults suite, removed after the test.
    private func makeCoordinator(
        _ service: FakeAdService,
        clock: TestClock = TestClock()
    ) -> (coordinator: MinikMathAdCoordinator, defaults: UserDefaults) {
        let suite = "minik-math-ads-\(UUID().uuidString)"
        addTeardownBlock { UserDefaults.standard.removePersistentDomain(forName: suite) }
        let defaults = UserDefaults(suiteName: suite)!
        let configuration = MinikAdsConfiguration(
            product: .minikMath,
            isEnabled: true,
            isPolicyApproved: true,
            applicationIdentifier: "ca-app-pub-1234567890123456~1234567890",
            interstitialAdUnitIdentifier: "ca-app-pub-1234567890123456/1234567890"
        )
        let coordinator = MinikMathAdCoordinator(
            configuration: configuration,
            service: service,
            defaults: defaults,
            noticeNanoseconds: 0,
            clock: { clock.milliseconds },
            uptime: { clock.uptime }
        )
        return (coordinator, defaults)
    }

    /// Finishes a round and returns once its results are released.
    private func finish(_ coordinator: MinikMathAdCoordinator, _ id: String, removed: Bool = false) async {
        let released = expectation(description: "results of \(id)")
        coordinator.finish(id, isRemoveAdsActive: removed) { released.fulfill() }
        await fulfillment(of: [released], timeout: 5)
    }

    func testTheFirstTwoRoundsShowNoAdAndTheirResultsAppearAtOnce() async {
        let service = FakeAdService()
        let coordinator = makeCoordinator(service).coordinator
        await coordinator.start(isRemoveAdsActive: false)
        XCTAssertTrue(coordinator.isProviderReady)
        var released = 0
        coordinator.finish("math/a", isRemoveAdsActive: false) { released += 1 }
        coordinator.finish("math/b", isRemoveAdsActive: false) { released += 1 }
        XCTAssertEqual(released, 2, "No ad: the results are released at once")
        let presentations = await service.presentations
        XCTAssertEqual(presentations, 0)
    }

    func testTheThirdRoundShowsOneAdAndItsResultsWaitUntilTheAdCloses() async {
        let service = FakeAdService()
        let clock = TestClock()
        let coordinator = makeCoordinator(service, clock: clock).coordinator
        await coordinator.start(isRemoveAdsActive: false)
        await finish(coordinator, "math/a")
        await finish(coordinator, "retro/b")
        var released = false
        let done = expectation(description: "results after the ad")
        coordinator.finish("math/c", isRemoveAdsActive: false) {
            released = true
            done.fulfill()
        }
        XCTAssertFalse(released, "The results wait for the ad")
        await fulfillment(of: [done], timeout: 5)
        let presentations = await service.presentations
        let waits = await service.dismissalWaits
        XCTAssertEqual(presentations, 1)
        XCTAssertEqual(waits, 1, "The results appear only after the ad has closed")
        XCTAssertEqual(coordinator.policy.lastAdAt, clock.milliseconds)
        XCTAssertEqual(coordinator.policy.completedSinceAd, 0)
    }

    func testAnUnavailableAdKeepsTheNextRoundDue() async {
        let service = FakeAdService(result: .unavailable)
        let coordinator = makeCoordinator(service).coordinator
        await coordinator.start(isRemoveAdsActive: false)
        for id in ["math/a", "math/b", "math/c", "math/d"] {
            await finish(coordinator, id)
        }
        let presentations = await service.presentations
        let waits = await service.dismissalWaits
        XCTAssertEqual(presentations, 2, "Rounds c and d both try to show an ad")
        XCTAssertEqual(waits, 0)
        XCTAssertEqual(coordinator.policy.lastAdAt, 0)
    }

    func testRemovedAdsNeverShowAnAd() async {
        let service = FakeAdService()
        let coordinator = makeCoordinator(service).coordinator
        await coordinator.start(isRemoveAdsActive: true)
        XCTAssertFalse(coordinator.isProviderReady, "Ads are not even set up")
        for id in ["math/a", "math/b", "math/c", "math/d"] {
            await finish(coordinator, id, removed: true)
        }
        let presentations = await service.presentations
        XCTAssertEqual(presentations, 0)
    }

    func testARoundFinishedOutsideTheAppShowsNoAd() async {
        let service = FakeAdService()
        let coordinator = makeCoordinator(service).coordinator
        await coordinator.start(isRemoveAdsActive: false)
        await finish(coordinator, "math/a")
        await finish(coordinator, "math/b")
        coordinator.setForeground(false)
        var released = false
        coordinator.finish("math/c", isRemoveAdsActive: false) { released = true }
        XCTAssertTrue(released)
        let presentations = await service.presentations
        XCTAssertEqual(presentations, 0)
    }

    func testTheSameRoundTwiceGetsOneAdAndBothResults() async {
        let service = FakeAdService()
        let coordinator = makeCoordinator(service).coordinator
        await coordinator.start(isRemoveAdsActive: false)
        await finish(coordinator, "math/a")
        await finish(coordinator, "math/b")
        let first = expectation(description: "first report")
        let second = expectation(description: "second report")
        coordinator.finish("math/c", isRemoveAdsActive: false) { first.fulfill() }
        coordinator.finish("math/c", isRemoveAdsActive: false) { second.fulfill() }
        await fulfillment(of: [first, second], timeout: 5)
        let presentations = await service.presentations
        XCTAssertEqual(presentations, 1)
        XCTAssertEqual(coordinator.policy.totalCompleted, 3)
    }

    func testPlayTimeCountsOnlyWhilePlayingOnScreen() async {
        let clock = TestClock()
        let coordinator = makeCoordinator(FakeAdService(), clock: clock).coordinator
        coordinator.setPlaying(true)
        clock.uptime += 2
        coordinator.tick()
        XCTAssertEqual(coordinator.policy.activeSinceAd, 2000)
        coordinator.setPlaying(false)
        clock.uptime += 3
        coordinator.tick()
        XCTAssertEqual(coordinator.policy.activeSinceAd, 2000, "Menus do not count")
        coordinator.setForeground(false)
        coordinator.setPlaying(true)
        clock.uptime += 3
        coordinator.tick()
        XCTAssertEqual(coordinator.policy.activeSinceAd, 2000, "Nothing counts outside the app")
        coordinator.setForeground(true)
        coordinator.setPlaying(true)
        clock.uptime += 60
        coordinator.tick()
        XCTAssertEqual(coordinator.policy.activeSinceAd, 7000, "At most five seconds per tick")
    }

    func testTheScheduleIsSavedAcrossLaunches() async {
        let (coordinator, defaults) = makeCoordinator(FakeAdService())
        await coordinator.start(isRemoveAdsActive: false)
        await finish(coordinator, "math/a")
        let saved = MinikMathAdPolicy.decode(defaults.data(forKey: MinikMathAds.storageKey))
        XCTAssertEqual(saved.totalCompleted, 1)
        XCTAssertEqual(saved.completed, ["math/a"])
    }
}
