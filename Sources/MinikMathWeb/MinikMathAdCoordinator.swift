#if MINIK_MATH_WEB
import Foundation

enum MinikMathAds {
    static let storageKey = "minik.math.ads.schedule.v1"
    /// Android shows "Round finished" for 0.7 seconds before the ad; the web app's own
    /// "Round finished" notice covers the screen meanwhile.
    static let noticeNanoseconds: UInt64 = 700_000_000
}

/// Android Minik Math's AdCoordinator (com.appsbybros.minik.monetization) on iOS: the one owner
/// of the ad schedule (MinikMathAdPolicy). Only a finished round or Ping Pong match may show an
/// ad; lifecycle changes never do. The ad itself comes from the shared Google Mobile Ads service,
/// with the settings every Minik app uses (child-directed, non-personalized, rated G).
@MainActor
final class MinikMathAdCoordinator {
    private let configuration: MinikAdsConfiguration
    private let service: any MinikInterstitialAdService
    private let defaults: UserDefaults
    private let noticeNanoseconds: UInt64
    /// Wall clock in milliseconds since 1970, as Android's System.currentTimeMillis.
    private let clock: () -> Int64
    /// Seconds for play time. Android uses SystemClock.elapsedRealtime; the wall clock serves here
    /// (the boot-time clock would need a declared reason in the privacy manifest), because a tick counts
    /// at most five seconds and ignores negative time, so clock changes cannot add play time.
    private let uptime: () -> TimeInterval
    private(set) var policy: MinikMathAdPolicy
    private(set) var isProviderReady = false
    private var hasStarted = false
    private var playing = false
    private var foreground = true
    private var showing = false
    private var tickAt: TimeInterval
    private var ticker: Task<Void, Never>?
    /// The round whose ad is about to show, and the results waiting for it.
    private var boundary: String?
    private var waiting: [() -> Void] = []

    init(
        configuration: MinikAdsConfiguration,
        service: any MinikInterstitialAdService,
        defaults: UserDefaults = .standard,
        noticeNanoseconds: UInt64 = 700_000_000,
        clock: @escaping () -> Int64 = { Int64((Date().timeIntervalSince1970 * 1000).rounded()) },
        uptime: @escaping () -> TimeInterval = { Date().timeIntervalSinceReferenceDate }
    ) {
        self.configuration = configuration
        self.service = service
        self.defaults = defaults
        self.noticeNanoseconds = noticeNanoseconds
        self.clock = clock
        self.uptime = uptime
        policy = MinikMathAdPolicy.decode(defaults.data(forKey: MinikMathAds.storageKey))
        tickAt = uptime()
    }

    static func make() -> MinikMathAdCoordinator {
        MinikMathAdCoordinator(
            configuration: MinikAdsConfiguration.load(product: .minikMath),
            service: ProductionMinikInterstitialAdServiceFactory.make(),
            noticeNanoseconds: MinikMathAds.noticeNanoseconds
        )
    }

    /// Called after the purchase check, as Android waits for it: ads are never set up once they
    /// are removed.
    func start(isRemoveAdsActive: Bool) async {
        guard !hasStarted, !isRemoveAdsActive else { return }
        hasStarted = true
        startTicking()
        guard let provider = configuration.providerConfiguration else { return }
        isProviderReady = await service.configure(provider)
    }

    /// The web app reports about once a second whether a game is being played.
    func setPlaying(_ value: Bool) {
        if value && !foreground { return }
        if playing != value { tickAt = uptime() }
        playing = value
    }

    /// The app is on screen and active, or not (Android's onActivityResumed and onActivityPaused).
    func setForeground(_ value: Bool) {
        guard foreground != value else { return }
        foreground = value
        tickAt = uptime()
        if !value {
            playing = false
            save()
        }
    }

    /// A finished round or Ping Pong match, by its unique ID. `results` runs once the results may
    /// appear: at once, or after the ad has closed.
    func finish(_ id: String, isRemoveAdsActive: Bool, results: @escaping () -> Void) {
        setPlaying(false)
        if boundary == id {
            // The same round reported again while its ad is pending: one ad, both results.
            waiting.append(results)
            return
        }
        let fresh = policy.complete(id)
        save()
        guard fresh, boundary == nil, !showing, foreground, !isRemoveAdsActive, isProviderReady,
              policy.due(now: clock()) else {
            results()
            return
        }
        boundary = id
        waiting = [results]
        Task { await showAd() }
    }

    private func showAd() async {
        try? await Task.sleep(nanoseconds: noticeNanoseconds)
        // Leaving the app during the notice skips the ad, as on Android.
        if foreground {
            showing = true
            if await service.presentInterstitial() == .presented {
                policy.shown(now: clock())
                save()
                await service.waitUntilDismissed()
            }
            showing = false
        }
        let callbacks = waiting
        boundary = nil
        waiting = []
        callbacks.forEach { $0() }
    }

    private func startTicking() {
        guard ticker == nil else { return }
        tickAt = uptime()
        ticker = Task { @MainActor [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 1_000_000_000)
                guard let self else { return }
                self.tick()
            }
        }
    }

    /// Android's one-second tick: play time counts while a game is on screen and no ad shows.
    func tick() {
        let now = uptime()
        let elapsed = now - tickAt
        tickAt = now
        guard playing, foreground, !showing else { return }
        policy.active(Int64((elapsed * 1000).rounded()), now: clock())
        save()
    }

    private func save() {
        if let data = policy.encoded() {
            defaults.set(data, forKey: MinikMathAds.storageKey)
        }
    }
}
#endif
