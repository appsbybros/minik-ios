import Foundation

/// Android `TeamLineup` (flexible lobby, `-lobby-v2`): playing positions are independent of connection slots, so
/// moving a friend never changes their identity. Slots are "empty", "b:<character>" or "u:<uid>".
struct MPTeamLineup: Equatable {
    static let empty = "empty"
    var slots: [String]
    var seen: Set<String>
    /// uid → playing position.
    var humans: [String: Int] {
        var out: [String: Int] = [:]
        for (index, value) in slots.enumerated() where value.hasPrefix("u:") { out[String(value.dropFirst(2))] = index }
        return out
    }
    var complete: Bool { !slots.contains(MPTeamLineup.empty) && humans.count == slots.filter { $0.hasPrefix("u:") }.count }
    /// Friends who left lose their place; newly connected friends take the first empty place, otherwise the first
    /// house player's. A friend the host deliberately benched is not reinserted (`seen`).
    func reconcile(members: Set<String>, arrivals: [String], order: [Int]) -> MPTeamLineup {
        var next = slots.map { $0.hasPrefix("u:") && !members.contains(String($0.dropFirst(2))) ? MPTeamLineup.empty : $0 }
        var admitted = seen.intersection(members)
        let pending = arrivals.filter { members.contains($0) && !admitted.contains($0) }
        for user in pending {
            if !next.contains("u:" + user) {
                let place = order.first { next[$0] == MPTeamLineup.empty } ?? order.first { next[$0].hasPrefix("b:") }
                guard let place else { continue }
                next[place] = "u:" + user
            }
            admitted.insert(user)
        }
        return MPTeamLineup(slots: next, seen: admitted)
    }
    /// Moving an already selected person swaps people; a displaced bot's old position becomes empty.
    func choose(_ seat: Int, _ value: String) -> MPTeamLineup {
        guard slots.indices.contains(seat) else { return self }
        var next = slots
        let old = next.firstIndex(of: value)
        if old == seat { return self }
        if value.hasPrefix("u:"), let old { next[old] = next[seat].hasPrefix("u:") ? next[seat] : MPTeamLineup.empty }
        if value.hasPrefix("b:"), let old { next[old] = MPTeamLineup.empty }
        next[seat] = value
        return MPTeamLineup(slots: next, seen: seen)
    }
    var wire: MPWire {
        var keyed: MPWire = [:]
        for (index, value) in slots.enumerated() { keyed[String(index)] = value }
        var visitors: MPWire = [:]
        for user in seen { visitors[user] = true }
        return ["slots": keyed, "seen": visitors]
    }
    static func initial(host: String, count: Int) -> MPTeamLineup {
        MPTeamLineup(slots: (0..<count).map { $0 == 0 ? "u:" + host : empty }, seen: [host])
    }
    /// Android `TeamLineup.read`: RTDB may return the slots as a list or as a keyed map.
    static func read(_ value: Any?, count: Int) -> MPTeamLineup? {
        guard let w = value as? [String: Any] else { return nil }
        let raw = w["slots"]
        var slots: [String] = []
        for index in 0..<count {
            let item: Any?
            if let list = raw as? [Any] { item = index < list.count ? list[index] : nil } else { item = MPCodec.map(raw)[String(index)] }
            guard let text = item as? String else { return nil }
            slots.append(text)
        }
        let seen = MPCodec.map(w["seen"]).filter { MPReceptionAssist.flag($0.value) == true }.map(\.key)
        return MPTeamLineup(slots: slots, seen: Set(seen))
    }
}

/// Android `TeamPlayerIdentity`: a player's own public game name and character; never an email or account id.
struct MPTeamIdentity: Equatable {
    var name: String
    var character: String
    var teammate: String? = nil
    var wire: MPWire {
        var w: MPWire = ["name": name, "character": character]
        if let teammate { w["teammate"] = teammate }
        return w
    }
    static func from(_ value: Any?) -> MPTeamIdentity? {
        let w = MPCodec.map(value)
        let name = ((w["name"] as? String) ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        let character = (w["character"] as? String) ?? ""
        guard !name.isEmpty, name.count <= 32, MPRoster.find(character) != nil else { return nil }
        return MPTeamIdentity(name: name, character: character, teammate: MPRoster.find((w["teammate"] as? String) ?? "")?.id)
    }
    /// The player's Ping Pong nickname and avatar character (Android `TeamPlayerIdentity.read`).
    static func local(_ identity: MPIdentity?, hebrew: Bool) -> MPTeamIdentity {
        let character = MPRoster.find(identity?.characterId ?? "")?.id ?? "miniko"
        let stored = String((identity?.name ?? "").trimmingCharacters(in: .whitespacesAndNewlines).prefix(32))
        return MPTeamIdentity(name: stored.isEmpty ? MPNames.candidate(0, hebrew: hebrew, character: character) : stored, character: character)
    }
}

/// Android `PongTeamAuthority`: only the room's host advances the table. Others send bounded inputs, never scores.
final class MPTeamAuthority {
    static let protocolName = "pong-doubles-v1"
    let game: MPPlay
    let seats: [String: Int]
    private var seen: [String: Int64] = [:]
    private var revision: Int64 = 0
    init(game: MPPlay, seats: [String: Int]) throws {
        guard game.stage == nil, game.team, seats.keys.allSatisfy({ !$0.isEmpty }), Set(seats.values).count == seats.count,
              Set(seats.values) == game.humanSeats else { throw MPError.permission }
        self.game = game; self.seats = seats
    }
    @discardableResult func receive(_ uid: String, sequence: Int64, kind: String, x: Double, y: Double) -> Bool {
        guard let seat = seats[uid] else { return false }
        if sequence <= 0 || sequence <= (seen[uid] ?? 0) || (kind != "move" && kind != "tap") { return false }
        if !x.isFinite || !y.isFinite || x < 0 || x > 1 || y < 0 || y > 1 { return false }
        if game.paused || game.ended { return false }
        seen[uid] = sequence
        if kind == "move" { game.moveSeat(seat, .init(x, y)) } else { game.tapSeat(seat, .init(x, y)) }
        return true
    }
    func checkpoint() -> MPWire {
        revision += 1
        var acknowledged: MPWire = [:]
        for (uid, sequence) in seen { acknowledged[uid] = NSNumber(value: sequence) }
        var positions: MPWire = [:]
        for (uid, seat) in seats { positions[uid] = seat }
        return ["protocol": MPTeamAuthority.protocolName, "revision": NSNumber(value: revision), "seats": positions, "seen": acknowledged, "game": game.save()]
    }
    static func restore(_ w: MPWire, expectedSeats: [String: Int]) throws -> MPTeamAuthority {
        guard w["protocol"] as? String == protocolName else { throw MPError.configuration }
        var seats: [String: Int] = [:]
        for (uid, value) in MPCodec.map(w["seats"]) {
            guard let seat = value as? NSNumber else { throw MPError.permission }
            seats[uid] = seat.intValue
        }
        // The saved match belongs to exactly this roster.
        guard seats == expectedSeats else { throw MPError.permission }
        let authority = try MPTeamAuthority(game: try MPPlay.restore(MPCodec.map(w["game"])), seats: seats)
        let revision = MPPlayWire.int64(w, "revision")
        guard revision >= 0 else { throw MPError.permission }
        authority.revision = revision
        for (uid, value) in MPCodec.map(w["seen"]) {
            guard seats[uid] != nil, let sequence = (value as? NSNumber)?.int64Value, sequence >= 0 else { throw MPError.permission }
            authority.seen[uid] = sequence
        }
        return authority
    }
}

/// Android `JsonWire`: the doubles snapshot body is JSON text.
enum MPJSON {
    static func encode(_ w: MPWire) -> String? {
        guard JSONSerialization.isValidJSONObject(w), let data = try? JSONSerialization.data(withJSONObject: w) else { return nil }
        return String(data: data, encoding: .utf8)
    }
    static func decode(_ text: String) throws -> MPWire {
        guard let data = text.data(using: .utf8), let value = try JSONSerialization.jsonObject(with: data) as? [String: Any] else { throw MPError.permission }
        return value
    }
}
