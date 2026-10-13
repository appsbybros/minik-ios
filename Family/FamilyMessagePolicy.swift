import Foundation

/// Port of Android MinikFamilyServices FamilyMessagePolicy.java: the local-only cadence. A promotion
/// replaces one otherwise eligible ad break in 30, at most once a day; the remove-ads reminder is
/// due 14 days after the first launch, then at most every 14 days, with a permanent opt-out.
struct FamilyMessagePolicy: Codable, Equatable {
    static let day: Int64 = 86_400_000
    static let reminderInterval: Int64 = 14 * day
    static let promotionEvery: Int64 = 30

    var firstSeen: Int64
    var lastPromotion: Int64 = 0
    var lastReminder: Int64 = 0
    var opportunities: Int64 = 0
    var neverRemind = false
    /// Android `LinkedHashSet` of the ad-break ids already counted (the oldest leave after 512).
    var counted: [String] = []

    init(now: Int64) {
        firstSeen = now
    }

    /// Call only at an otherwise eligible ad break.
    mutating func opportunity(_ id: String, now: Int64, resolved: Bool, adFree: Bool) -> Bool {
        if !resolved || adFree || id.isEmpty || id.utf16.count > 200 || counted.contains(id) { return false }
        counted.append(id)
        while counted.count > 512 { counted.removeFirst() }
        opportunities = min(opportunities + 1, FamilyMessagePolicy.promotionEvery)
        return opportunities >= FamilyMessagePolicy.promotionEvery && (lastPromotion == 0 || now - lastPromotion >= FamilyMessagePolicy.day)
    }

    mutating func promotionShown(_ now: Int64) {
        lastPromotion = now
        opportunities = 0
    }

    func reminderDue(_ now: Int64, resolved: Bool, adFree: Bool, purchaseAvailable: Bool) -> Bool {
        return resolved && !adFree && purchaseAvailable && !neverRemind && now - max(firstSeen, lastReminder) >= FamilyMessagePolicy.reminderInterval
    }

    mutating func reminderShown(_ now: Int64) {
        lastReminder = now
    }

    mutating func stopReminding() {
        neverRemind = true
    }

    func encode() -> String {
        guard let data = try? JSONEncoder().encode(self), let text = String(data: data, encoding: .utf8) else { return "" }
        return text
    }

    /// Android `decode(raw, now)`: a missing or damaged record starts a new cadence.
    static func decode(_ raw: String?, now: Int64) -> FamilyMessagePolicy {
        guard let raw = raw, !raw.isEmpty, raw.utf16.count <= 150_000, let data = raw.data(using: .utf8),
              var s = try? JSONDecoder().decode(FamilyMessagePolicy.self, from: data) else { return FamilyMessagePolicy(now: now) }
        s.firstSeen = max(0, s.firstSeen)
        s.lastPromotion = max(0, s.lastPromotion)
        s.lastReminder = max(0, s.lastReminder)
        s.opportunities = min(promotionEvery, max(0, s.opportunities))
        s.counted = Array(s.counted.filter { $0.utf16.count <= 200 }.prefix(512))
        return s
    }
}
