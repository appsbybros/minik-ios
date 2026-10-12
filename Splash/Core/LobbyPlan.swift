import Foundation

/// Port of Android core/LobbyPlan.kt: capacity is a lobby choice; the six-player engine limit
/// is absolute.
enum LobbyPlan {
    static let limit = 6

    /// A room builds its world only once the announced roster has fully arrived.
    static func readyRoster(_ teams: [Int], _ teamGame: Bool, _ expected: Int) -> Bool {
        if teams.count < 2 || teams.count > limit || (expected > 0 && teams.count != expected) { return false }
        if !teamGame { return true }
        let half = teams.count / 2
        return teams.count >= 4 && teams.count % 2 == 0 && teams.filter({ $0 == 0 }).count == half && teams.filter({ $0 == 1 }).count == half
    }

    /// "limit", "minimum", "teams", "selected" (more players than chosen) or nil.
    static func problem(_ humans: Int, _ house: Int, _ selected: Int, _ teams: Bool) -> String? {
        let total = humans + house
        if total > limit { return "limit" }
        if total < 2 { return "minimum" }
        if teams && total != 4 && total != 6 { return "teams" }
        if total > selected { return "selected" }
        return nil
    }
}

/// Port of Android core/RoomInputPolicy.kt: RTDB metadata, the result receipt and the
/// interpolated snapshot arrive independently; input stops at the first sign of the end.
enum RoomInputPolicy {
    static func accepts(_ phase: String, _ localFinished: Bool, _ storedResult: Bool) -> Bool {
        return phase == "playing" && !localFinished && !storedResult
    }
}
