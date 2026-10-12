#if MINIK_MATH_WEB
import Foundation

/// Android Minik Math's ad schedule (com.appsbybros.minik.monetization.AdPolicy), unchanged:
/// no ad for the first two finished rounds; then one after two more rounds or 3.5 minutes of
/// play, or after three rounds and five minutes once the last five visits averaged 15 minutes
/// or more; never within two minutes of the last ad. Times are milliseconds since 1970, as on
/// Android. Play time counts only while a game is on screen, at most five seconds per report,
/// so time in the background never becomes play time.
struct MinikMathAdPolicy: Codable, Equatable, Sendable {
    static let minute: Int64 = 60_000
    static let sessionGap: Int64 = 30 * minute

    var totalCompleted: Int64 = 0
    var completedSinceAd: Int64 = 0
    var activeSinceAd: Int64 = 0
    var lastAdAt: Int64 = 0
    var sessionActive: Int64 = 0
    var lastActiveAt: Int64 = 0
    /// Play time of the last five visits, oldest first.
    var sessions: [Int64] = []
    /// Finished round IDs, oldest first (at most 512), so a result never counts twice.
    var completed: [String] = []

    mutating func active(_ milliseconds: Int64, now: Int64) {
        if milliseconds <= 0 { return }
        if lastActiveAt > 0 && now - lastActiveAt >= Self.sessionGap { closeSession() }
        let elapsed = min(milliseconds, 5_000)
        activeSinceAd += elapsed
        sessionActive += elapsed
        lastActiveAt = now
    }

    private mutating func closeSession() {
        if sessionActive > 0 {
            sessions.append(sessionActive)
            while sessions.count > 5 { sessions.removeFirst() }
        }
        sessionActive = 0
    }

    var longSessions: Bool {
        sessions.count == 5 && sessions.reduce(0, +) / 5 >= 15 * Self.minute
    }

    /// Counts a finished round once; false for an invalid or already counted ID.
    @discardableResult
    mutating func complete(_ id: String?) -> Bool {
        guard let id, !id.isEmpty, id.utf16.count <= 200, !id.contains(","), !completed.contains(id) else {
            return false
        }
        completed.append(id)
        while completed.count > 512 { completed.removeFirst() }
        totalCompleted += 1
        completedSinceAd += 1
        return true
    }

    func due(now: Int64) -> Bool {
        if totalCompleted <= 2 { return false }
        // Backwards wall-clock changes postpone ads; they never accelerate them.
        if lastAdAt > 0 && now - lastAdAt < 2 * Self.minute { return false }
        return longSessions
            ? completedSinceAd >= 3 && activeSinceAd >= 5 * Self.minute
            : completedSinceAd >= 2 || activeSinceAd >= 210_000
    }

    mutating func shown(now: Int64) {
        lastAdAt = now
        completedSinceAd = 0
        activeSinceAd = 0
    }

    func encoded() -> Data? {
        try? JSONEncoder().encode(self)
    }

    /// Saved state, with Android's limits re-applied; unreadable state starts afresh, which
    /// gives the two free rounds again rather than an ad.
    static func decode(_ data: Data?) -> MinikMathAdPolicy {
        guard let data, var policy = try? JSONDecoder().decode(MinikMathAdPolicy.self, from: data) else {
            return MinikMathAdPolicy()
        }
        policy.totalCompleted = max(0, policy.totalCompleted)
        policy.completedSinceAd = max(0, policy.completedSinceAd)
        policy.activeSinceAd = max(0, policy.activeSinceAd)
        policy.lastAdAt = max(0, policy.lastAdAt)
        policy.sessionActive = max(0, policy.sessionActive)
        policy.lastActiveAt = max(0, policy.lastActiveAt)
        policy.sessions = Array(policy.sessions.map { max(0, $0) }.suffix(5))
        policy.completed = Array(policy.completed.filter { !$0.isEmpty }.suffix(512))
        return policy
    }
}
#endif
