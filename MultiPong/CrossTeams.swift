import Foundation

// Android cross/CrossTeams.kt, ReceptionAssist.kt, TeamLineup.kt and TeamPlayerIdentity.kt (MinikCrossPong 5c1aa4d).

/// Explicit seat membership: a human plus a chosen partner versus one or two opponents. Team 0 has two seats, team 1 one or
/// two (Android `require`: nil for any other shape).
struct CrossTeams: Equatable {
    let seats: [Int]
    init?(_ seats: [Int]) {
        guard (3...4).contains(seats.count), seats.allSatisfy({ $0 == 0 || $0 == 1 }), seats.filter({ $0 == 0 }).count == 2,
              (1...2).contains(seats.filter({ $0 == 1 }).count) else { return nil }
        self.seats = seats
    }
    func same(_ a: Int, _ b: Int) -> Bool { seats[a] == seats[b] }
    func partner(_ seat: Int) -> Int? { seats.indices.first { $0 != seat && same($0, seat) } }
    func opponents(_ seat: Int) -> [Int] { seats.indices.filter { !same($0, seat) } }
    /// Team 0 is seats 0 and 2 (the human and the partner across the table), team 1 the others (Android `(it % 2)`).
    static func across(_ players: Int) -> CrossTeams? { CrossTeams((0..<players).map { $0 % 2 }) }
}

/// Android `TeamFlight`: the team state of the live rally, saved separately from the established online protocol ("localTeam";
/// old individual matches have no team extension). `setReceiver` is the teammate a raised pass is travelling to.
struct CrossTeamFlight: Equatable {
    var members: [Int]
    var setReceiver: Int? = nil
    var passes = 0
    var sets = 0
    var smashes = 0
    var friendlyHits = 0
    /// Android's `init` checks: a valid team shape, a receiver inside it, no negative counter, at most one friendly hit.
    var valid: Bool {
        CrossTeams(members) != nil && (setReceiver.map { members.indices.contains($0) } ?? true) &&
            [passes, sets, smashes].allSatisfy { $0 >= 0 } && (0...1).contains(friendlyHits)
    }
    func wire() -> MPWire {
        var w: MPWire = ["members": members, "passes": passes, "sets": sets, "smashes": smashes, "friendlyHits": friendlyHits]
        if let setReceiver { w["receiver"] = setReceiver }
        return w
    }
    static func read(_ w: MPWire) throws -> CrossTeamFlight {
        let flight = CrossTeamFlight(members: CrossWire.ints(w["members"]), setReceiver: CrossWire.seat(w, "receiver"), passes: CrossWire.int(w, "passes"),
                                     sets: CrossWire.int(w, "sets"), smashes: CrossWire.int(w, "smashes"), friendlyHits: CrossWire.int(w, "friendlyHits"))
        guard flight.valid else { throw CrossStateError.invalid("Invalid team state") }
        return flight
    }
}

/// Android `ReceptionAssist`: one simulation clock for the complete match. As the ball approaches a receiving human whose own
/// setting asks for it, the whole game slows smoothly (to 45 %) and speeds up again; the authority decides the pace and its
/// peers follow its `scale`. Camera preferences never enter physics.
final class CrossReception {
    /// Production owners enable this after loading preferences; pure physics callers stay unmodified.
    var enabled = false
    /// Seat → that player's "slow motion for my return" preference.
    var slow: [Int: Bool] = [:]
    private(set) var scale = 1.0
    private(set) var receiver = -1
    private(set) var strength = 0.0
    /// Real seconds → simulated seconds (at most 1/30 s of real time per call).
    func advance(_ realSeconds: Double, seat: Int?, eta: Double?, authority: Bool = true) -> Double {
        let dt = realSeconds.isNaN ? 0 : min(1.0 / 30, max(0, realSeconds))
        if dt <= 0 { return 0 }
        if !authority { return dt * scale }
        receiver = seat ?? -1
        if enabled, seat != nil, let eta, eta.isFinite, eta >= -0.12, eta <= 1.1 {
            let t = (1 - max(eta, 0) / 1.1).mpClamp(0, 1)
            strength = t * t * (3 - 2 * t)
        } else { strength = 0 }
        let target: Double
        if enabled, let seat, slow[seat] == true { target = 1 - 0.55 * strength } else { target = 1 }
        scale += (target - scale) * (1 - exp(-dt * 5))
        if abs(scale - 1) < 0.00001 { scale = 1 }
        return dt * scale
    }
    func wire() -> MPWire {
        var options: MPWire = [:]
        for (seat, value) in slow { options[String(seat)] = value }
        return ["enabled": enabled, "scale": scale, "receiver": receiver, "strength": strength, "slow": options]
    }
    /// Android `restore`: an empty wire is normal speed; invalid values throw and change nothing.
    func restore(_ w: MPWire) throws {
        let s = (w["scale"] as? NSNumber)?.doubleValue ?? 1
        let f = (w["strength"] as? NSNumber)?.doubleValue ?? 0
        let r = (w["receiver"] as? NSNumber).map { Int($0.int64Value) } ?? -1
        guard s.isFinite, s >= 0.45, s <= 1, f.isFinite, f >= 0, f <= 1, (-1...3).contains(r) else { throw CrossStateError.invalid("Invalid reception state") }
        var options: [Int: Bool] = [:]
        for (key, value) in MPCodec.map(w["slow"]) {
            guard let seat = Int(key), (0...3).contains(seat), let flag = value as? Bool else { throw CrossStateError.invalid("Invalid reception option") }
            options[seat] = flag
        }
        enabled = CrossWire.flag(w, "enabled"); scale = s; strength = f; receiver = r; slow = options
    }
    /// Android `canonical`: an empty wire stays empty; anything else is validated and rewritten in full.
    static func canonical(_ w: MPWire) throws -> MPWire {
        if w.isEmpty { return w }
        let r = CrossReception()
        try r.restore(w)
        return r.wire()
    }
    /// Android `reflected`: the classic two-player match mirrors seats 0 and 1 for the other phone.
    static func reflected(_ w: MPWire) -> MPWire {
        if w.isEmpty { return w }
        var out = w
        let r = CrossWire.int(w, "receiver", -1)
        out["receiver"] = (0...1).contains(r) ? 1 - r : -1
        var options: MPWire = [:]
        for (key, value) in MPCodec.map(w["slow"]) { if let seat = Int(key) { options[String(1 - seat)] = value } }
        out["slow"] = options
        return out
    }
    /// Seconds until the ball (moving in a straight line) passes `at`, when it passes within 0.35 of it; nil otherwise.
    static func eta(_ ball: MPPoint, _ velocity: MPPoint, _ at: MPPoint) -> Double? {
        let speed2 = velocity.x * velocity.x + velocity.y * velocity.y
        if speed2 < 0.000001 { return nil }
        let x = at.x - ball.x, y = at.y - ball.y
        let t = (x * velocity.x + y * velocity.y) / speed2
        return hypot(x - velocity.x * t, y - velocity.y * t) < 0.35 ? t : nil
    }
}

/// Android `TeamLineup`: lobby positions independent of connection slots, so moving a friend never changes their identity.
/// A slot is "u:<uid>", "b:<character>" or "empty".
struct CrossLineup: Equatable {
    static let empty = "empty"
    var slots: [String]
    var seen: Set<String>
    var humans: [String: Int] {
        var result: [String: Int] = [:]
        for (i, value) in slots.enumerated() where value.hasPrefix("u:") { result[String(value.dropFirst(2))] = i }
        return result
    }
    var complete: Bool { !slots.contains(CrossLineup.empty) && humans.count == slots.filter { $0.hasPrefix("u:") }.count }
    func reconcile(_ members: Set<String>, arrivals: [String], order: [Int]) -> CrossLineup {
        var next = slots.map { $0.hasPrefix("u:") && !members.contains(String($0.dropFirst(2))) ? CrossLineup.empty : $0 }
        var admitted = seen.intersection(members)
        for user in arrivals where members.contains(user) && !admitted.contains(user) {
            if !next.contains("u:" + user) {
                let free = order.first(where: { $0 < next.count && next[$0] == CrossLineup.empty })
                guard let place = free ?? order.first(where: { $0 < next.count && next[$0].hasPrefix("b:") }) else { continue }
                next[place] = "u:" + user
            }
            admitted.insert(user)
        }
        return CrossLineup(slots: next, seen: admitted)
    }
    /// Host membership is required at Start, not while arranging places.
    func choose(_ seat: Int, _ value: String) -> CrossLineup {
        guard slots.indices.contains(seat) else { return self }
        var next = slots
        let old = next.firstIndex(of: value)
        if old == seat { return self }
        // Moving an already selected person swaps people, but clears a displaced bot's old position.
        if value.hasPrefix("u:"), let old { next[old] = next[seat].hasPrefix("u:") ? next[seat] : CrossLineup.empty }
        if value.hasPrefix("b:"), let old { next[old] = CrossLineup.empty }
        next[seat] = value
        var copy = self
        copy.slots = next
        return copy
    }
    func wire() -> MPWire {
        var slotWire: MPWire = [:]
        for (i, value) in slots.enumerated() { slotWire[String(i)] = value }
        var seenWire: MPWire = [:]
        for user in seen { seenWire[user] = true }
        return ["slots": slotWire, "seen": seenWire]
    }
    static func initial(_ host: String, count: Int) -> CrossLineup {
        CrossLineup(slots: (0..<count).map { $0 == 0 ? "u:" + host : empty }, seen: [host])
    }
    static func read(_ value: Any?, count: Int) -> CrossLineup? {
        guard let w = value as? MPWire else { return nil }
        let raw = MPCodec.map(w["slots"])
        var slots: [String] = []
        for i in 0..<count {
            guard let slot = raw[String(i)] as? String else { return nil }
            slots.append(slot)
        }
        let seen = Set(MPCodec.map(w["seen"]).compactMap { ($0.value as? Bool) == true ? $0.key : nil })
        return CrossLineup(slots: slots, seen: seen)
    }
}

/// Android `TeamPlayerIdentity`: a player's own public game name and avatar (and, in old rooms, a chosen house teammate). No
/// email or account identifier is ever shown.
struct CrossTeamIdentity: Equatable {
    var name: String
    var character: String
    var teammate: String? = nil
    func wire() -> MPWire {
        var w: MPWire = ["name": name, "character": character]
        if let teammate { w["teammate"] = teammate }
        return w
    }
    /// This phone's player: the saved nickname, else a generated one for the avatar (a character, Miniko by default).
    static func own(_ identity: MPIdentity?, hebrew: Bool) -> CrossTeamIdentity {
        let character = MPRoster.find(identity?.characterId ?? "")?.id ?? "miniko"
        let trimmed = (identity?.name ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        let saved = String(trimmed.prefix(32))
        return CrossTeamIdentity(name: saved.isEmpty ? MPNames.candidate(0, hebrew: hebrew, character: character) : saved, character: character)
    }
    static func from(_ value: Any?) -> CrossTeamIdentity? {
        let w = MPCodec.map(value)
        let name = CrossWire.text(w, "name").trimmingCharacters(in: .whitespacesAndNewlines)
        let character = CrossWire.text(w, "character")
        guard !name.isEmpty, name.utf16.count <= 32, MPRoster.find(character) != nil else { return nil }
        return CrossTeamIdentity(name: name, character: character, teammate: MPRoster.find(CrossWire.text(w, "teammate"))?.id)
    }
}
