import Foundation

/// Minik Plus and Minik Plus English (owner, 12 November 2026): no ads; a free week, then the whole
/// app is locked until the one-time full-access purchase. App Review Guideline 3.1.1 wants a free
/// time-based trial to be a free Non-Consumable "7-day Trial" product, so the week starts when a
/// grown-up takes that product. See docs/minik-plus-paywall-ios.md.
enum MinikPlusAccess: Equatable, Sendable {
    /// Full access was bought, or the earlier Remove Ads purchase: everything, forever.
    case fullAccess
    /// The free week has not been started: the welcome screen covers the app.
    case trialNotStarted
    /// The free week runs, with 1...7 days left.
    case trial(daysLeft: Int)
    /// The free week is over and nothing was bought: the buy wall covers the app.
    case trialEnded

    /// No activity, game or practice may open.
    var isLocked: Bool {
        switch self {
        case .trialNotStarted, .trialEnded:
            return true
        case .fullAccess, .trial:
            return false
        }
    }
}

/// The trial and lock decision, free of StoreKit and of the device clock.
enum MinikPlusAccessPolicy {
    static let day: TimeInterval = 24 * 60 * 60
    static let trialDays = 7
    static let trialLength: TimeInterval = TimeInterval(trialDays) * day

    /// - Parameters:
    ///   - ownsFullAccess: the full-access product or the earlier Remove Ads product is owned.
    ///   - freeWeekStartedAt: when the free 7-day Trial product was taken, if it was.
    ///   - now: the device clock.
    ///   - latestSeenAt: the latest time this device has seen. A clock set back never adds time:
    ///     the week counts from the later of the two.
    static func access(
        ownsFullAccess: Bool,
        freeWeekStartedAt: Date?,
        now: Date,
        latestSeenAt: Date? = nil
    ) -> MinikPlusAccess {
        if ownsFullAccess { return .fullAccess }
        guard let start = freeWeekStartedAt else { return .trialNotStarted }
        let end = start.addingTimeInterval(trialLength)
        let counted = max(now, latestSeenAt ?? now)
        guard counted < end else { return .trialEnded }
        // A clock before the start (set back) leaves the week whole, never longer.
        let remaining = end.timeIntervalSince(max(counted, start))
        let days = Int((remaining / day).rounded(.up))
        return .trial(daysLeft: min(trialDays, max(1, days)))
    }
}

/// What the device remembers between launches, so a purchase the App Store verified earlier and
/// the free week's start hold offline.
struct MinikPlusAccessRecord: Codable, Equatable, Sendable {
    var ownsFullAccess = false
    var freeWeekStartedAt: Date?
    var latestSeenAt: Date?

    /// The free week's start only ever moves earlier: a later report (a restore, another device,
    /// a reinstall) never gives a new week.
    mutating func recordFreeWeekStart(_ date: Date) {
        freeWeekStartedAt = min(freeWeekStartedAt ?? date, date)
    }

    mutating func recordSeen(_ date: Date) {
        latestSeenAt = max(latestSeenAt ?? date, date)
    }

    func access(now: Date) -> MinikPlusAccess {
        MinikPlusAccessPolicy.access(
            ownsFullAccess: ownsFullAccess,
            freeWeekStartedAt: freeWeekStartedAt,
            now: now,
            latestSeenAt: latestSeenAt
        )
    }
}

struct MinikPlusAccessRepository: @unchecked Sendable {
    private let userDefaults: UserDefaults
    private let keyPrefix: String

    init(
        userDefaults: UserDefaults = .standard,
        keyPrefix: String = "minik.plus-access.v1"
    ) {
        self.userDefaults = userDefaults
        self.keyPrefix = keyPrefix
    }

    func load(for product: ProductVariant) -> MinikPlusAccessRecord {
        guard let data = userDefaults.data(forKey: key(for: product)),
              let record = try? JSONDecoder().decode(MinikPlusAccessRecord.self, from: data) else {
            return MinikPlusAccessRecord()
        }
        return record
    }

    func save(_ record: MinikPlusAccessRecord, for product: ProductVariant) {
        guard let data = try? JSONEncoder().encode(record) else { return }
        userDefaults.set(data, forKey: key(for: product))
    }

    private func key(for product: ProductVariant) -> String {
        "\(keyPrefix).\(product.rawValue)"
    }
}
