import XCTest
@testable import MinikMultiPingPong

// Android app/src/test/.../multiplayer/GroupMatchAdversarialTest.kt (MinikCrossPong 828c6fc).
// Adversarial checks of the N-player match model (CROSS_DESIGN §7): transitions applied in every order, lobby departures, seat
// collisions, host transfer, house players filling seats, malformed results, classic tournaments step by step against the original
// two-player rules, records stored by the original codec, and the device-local stores (MPLocalRepository, MPPreferences).
//
// Porting notes:
// - Kotlin `PongRules.create` normalizes the code and leaves createdAt/lastActivityAt at 0; `gmaCreate` does the same around
//   Swift's `MPSession(code:kind:host:...)` (which stamps the clock and has no lossPoints parameter).
// - Kotlin `require` failures (IllegalArgumentException) are Swift `MPError` throws.
// - Swift `MPFixture` caches `authorityUid` (Kotlin MatchRecord has no such field; it is derived on the wire). Comparisons with
//   records that never carried it (the original codec, a fixture whose cached authority was refreshed) strip it, exactly as the
//   Kotlin test strips the N-player `placement` (`classic`).
// - Kotlin MemoryPreferences / MemoryContext are replaced by a throwaway `UserDefaults` suite.

private let gmaHouse: [MPHousePlayer] = MPRoster.all.filter { $0.id != "minik" }

/// Kotlin `bot(i)`: a house player with the stable id "bot_<character>".
private func gmaBot(_ i: Int) -> MPParticipant {
    let h = gmaHouse[i]
    return MPParticipant(identity: MPIdentity(id: "bot_\(h.id)", name: h.english), bot: h.profile)
}

/// Kotlin `PongRules.create(...)`: normalized code, createdAt = lastActivityAt = 0.
private func gmaCreate(_ code: String, _ kind: MPSessionKind, _ host: MPIdentity, _ capacity: Int, _ legs: Int, _ win: Int, _ loss: Int,
                       _ difficulty: Int, _ target: Int, format: MPTournamentFormat = .roundRobin, tableSize: Int = 2) throws -> MPSession {
    let normalized = try MPRules.normalize(code)
    var s = MPSession(code: normalized, kind: kind, host: host, capacity: capacity, legs: legs, winPoints: win, difficulty: difficulty,
                      target: target, format: format, tableSize: tableSize)
    s.lossPoints = min(10, max(0, loss))
    s.createdAt = 0
    s.lastActivityAt = 0
    return s
}

/// Kotlin `online(s, *away)`: every present human connected except `away`; house players need no connection.
private func gmaOnline(_ s: MPSession, _ away: String...) -> MPSession {
    var connections: [String: [String: Bool]] = [:]
    for (id, p) in s.participants where p.bot == nil && s.departed[id] != true && !away.contains(id) { connections[id] = ["0": true] }
    var n = s
    n.connections = connections
    return n
}

/// Kotlin `table(size, *guests, bots)`: friendly table, "host" at seat 0, then the guests, then house players; everybody online.
private func gmaTable(_ size: Int, _ guests: [String] = [], bots: Int = 0) throws -> MPSession {
    var s = try gmaCreate("ABC234", .friendly, MPIdentity(id: "host", name: "Host"), 2, 1, 3, 0, 0, 5, tableSize: size)
    for uid in guests { s = try MPRules.join(s, MPIdentity(id: uid, name: "Guest \(uid)")) }
    for i in 0..<bots { s = try MPRules.addFriendlyHousePlayer(s, actor: "host", bot: gmaBot(i)) }
    return gmaOnline(s)
}

/// Kotlin `only(s)` (`matches.values.single()`).
private func gmaOnly(_ s: MPSession, file: StaticString = #filePath, line: UInt = #line) -> MPFixture {
    XCTAssertEqual(s.matches.count, 1, "expected a single fixture", file: file, line: line)
    return s.matches.values.first ?? MPFixture(id: "", players: [], seed: 0)
}

/// Kotlin `orders(items)`: every permutation, in the same order.
private func gmaOrders<T>(_ items: [T]) -> [[T]] {
    if items.count <= 1 { return [items] }
    var result: [[T]] = []
    for i in items.indices {
        var rest = items
        rest.remove(at: i)
        for tail in gmaOrders(rest) { result.append([items[i]] + tail) }
    }
    return result
}

/// Kotlin `ranked(players, scores)`: by score descending, then seat.
private func gmaRanked(_ players: [String], _ scores: [Int]) -> [String] {
    let order = players.indices.sorted { a, b in
        if scores[a] != scores[b] { return scores[a] > scores[b] }
        return a < b
    }
    return order.map { players[$0] }
}

private func gmaBareFixture(_ m: MPFixture) -> MPFixture {
    var c = m
    c.authorityUid = nil
    return c
}

/// The session without Swift's cached fixture authorities (the original records never stored one).
private func gmaBare(_ s: MPSession) -> MPSession {
    var n = s
    for (id, m) in s.matches { n.matches[id] = gmaBareFixture(m) }
    return n
}

/// Kotlin `classic(s)`: placement is new in the N-player model; the original records never carried one (nor an authorityUid).
private func gmaClassic(_ s: MPSession) -> MPSession {
    var n = s
    for (id, m) in s.matches {
        var c = m
        c.placement = []
        c.authorityUid = nil
        n.matches[id] = c
    }
    return n
}

/// Kotlin `classicFinal(s, rng)`: a classic final (deuce on the levels that need a two-point lead), the winner's score first.
private func gmaClassicFinal(_ s: MPSession, _ rng: inout MPKotlinRandom) -> (Int, Int) {
    let t = s.target
    let deuce = s.level.needsTwoPointLead
    if deuce && rng.nextIndex(3) == 0 {
        let low = t - 1 + rng.nextIndex(4)
        return (low + 2, low)
    }
    return (t, rng.nextIndex(deuce ? t - 1 : t))
}

/// Kotlin `firebase(v, lists)`: what RTDB hands back — no nulls or empty containers, and dense integer keys as a list (or left as an
/// index map). Kotlin's Int -> Long widening has no Swift counterpart (numbers stay NSNumber-bridged).
private func gmaRtdb(_ v: Any?, lists: Bool) -> Any? {
    guard let value = v else { return nil }
    if value is NSNull { return nil }
    if let map = value as? [String: Any] {
        var m: [String: Any] = [:]
        for (k, x) in map {
            if let y = gmaRtdb(x, lists: lists) { m[k] = y }
        }
        if m.isEmpty { return nil }
        let index: [Int?] = m.keys.map { Int($0) }
        let numeric: [Int] = index.compactMap { $0 }
        if lists && numeric.count == index.count && numeric.allSatisfy({ $0 >= 0 }), let top = numeric.max(), top < 2 * m.count {
            var list: [Any] = []
            for i in 0...top { list.append(m[String(i)] ?? NSNull()) }
            return list
        }
        return m
    }
    if let list = value as? [Any] {
        var m: [String: Any] = [:]
        for (i, x) in list.enumerated() { m[String(i)] = x }
        return gmaRtdb(m, lists: lists)
    }
    return value
}

/// Kotlin `PongCodec.session(s)`.
private func gmaEncode(_ s: MPSession) throws -> MPWire {
    let w: MPWire = try MPCodec.session(s)
    return w
}

/// Kotlin `PongCodec.session(wire)!!`.
private func gmaDecode(_ w: Any?) throws -> MPSession {
    let s: MPSession = try MPCodec.session(w)
    return s
}

/// Kotlin `JsonWire.decode(JsonWire.encode(w))`.
private func gmaJson(_ w: MPWire) throws -> MPWire {
    let data = try JSONSerialization.data(withJSONObject: w)
    let decoded = try JSONSerialization.jsonObject(with: data)
    return MPCodec.map(decoded)
}

private final class GMABox<T> {
    var value: T
    init(_ value: T) { self.value = value }
}

/// Kotlin `SeatOp`.
private struct GMASeatOp {
    let name: String
    let mover: String?
    let apply: (MPSession) throws -> MPSession
}

/// Kotlin `Original`: the original two-player rules and codec of Modern Ping Pong, transcribed for step-by-step comparison. Its
/// `require` failures throw `MPError.permission` (Kotlin IllegalArgumentException); its records never carry a placement or an
/// authorityUid.
private enum GMAOriginal {
    static func authority(_ s: MPSession, _ m: MPFixture) -> String {
        let humans = [m.a, m.b].filter { s.participants[$0]?.bot == nil }
        return humans.min() ?? s.host
    }

    private static func pair(_ m: MPFixture, phase: MPMatchPhase? = nil, ready: [String: Bool]? = nil, a: Int? = nil, b: Int? = nil,
                             winner: String? = nil, starts: Int? = nil) -> MPFixture {
        var r = MPFixture(id: m.id, a: m.a, b: m.b, seed: m.seed)
        r.phase = phase ?? m.phase
        r.ready = ready ?? m.ready
        r.scores = [a ?? m.scoreA, b ?? m.scoreB]
        r.winner = winner ?? m.winner
        r.starts = starts ?? m.starts
        return r
    }

    static func create(_ code: String, _ kind: MPSessionKind, _ host: MPIdentity, _ capacity: Int, _ legs: Int, _ win: Int, _ loss: Int,
                       _ difficulty: Int, _ target: Int, _ format: MPTournamentFormat) throws -> MPSession {
        let normalized = try MPRules.normalize(code)
        let level = min(4, max(0, difficulty))
        var s = MPSession(code: normalized, kind: kind, host: host)
        s.capacity = kind == .friendly ? 2 : min(format == .knockout ? 9 : 8, max(2, capacity))
        s.legs = format == .knockout ? 1 : min(2, max(1, legs))
        s.winPoints = min(10, max(0, win))
        s.lossPoints = min(10, max(0, loss))
        s.difficulty = level
        s.target = (MPLevel(rawValue: level) ?? .easy).target(target)
        s.participants = [host.id: MPParticipant(identity: host.safe(), bot: nil)]
        s.matches = [:]
        s.connections = [:]
        s.departed = [:]
        s.state = "WAITING"
        s.createdAt = 0
        s.lastActivityAt = 0
        s.format = kind == .tournament ? format : .roundRobin
        s.rounds = [:]
        s.tableSize = 2
        s.seats = [:]
        s.gameMode = .winnerTakesAll
        s.advance = 2
        return s
    }

    static func join(_ s: MPSession, _ player: MPIdentity) throws -> MPSession {
        guard s.departed[player.id] != true else { throw MPError.permission }
        if let existing = s.participants[player.id] {
            if s.state != "WAITING" { return s }
            var n = s
            var p = existing
            p.identity = player.safe()
            n.participants[player.id] = p
            return n
        }
        guard s.state == "WAITING", s.matches.isEmpty, s.participants.count < s.capacity else { throw MPError.permission }
        var n = s
        n.participants[player.id] = MPParticipant(identity: player.safe(), bot: nil)
        return n
    }

    static func addBot(_ s: MPSession, _ actor: String, _ bot: MPParticipant) throws -> MPSession {
        guard actor == s.host, s.state == "WAITING", s.participants.count < s.capacity, let profile = bot.bot else { throw MPError.permission }
        guard bot.id.hasPrefix("bot_"), s.participants[bot.id] == nil else { throw MPError.permission }
        let blank = profile.characterId.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        let taken = s.participants.values.contains(where: { $0.bot?.characterId == profile.characterId })
        guard blank || !taken else { throw MPError.permission }
        var n = s
        n.participants[bot.id] = MPParticipant(identity: bot.identity.safe(), bot: profile.safe())
        return n
    }

    private static func schedule(_ s: MPSession) throws -> [String: MPFixture] {
        let ids = s.participants.keys.sorted()
        guard (2...8).contains(ids.count) else { throw MPError.permission }
        var result: [String: MPFixture] = [:]
        for leg in 0..<s.legs {
            for i in 0..<ids.count {
                for j in (i + 1)..<ids.count {
                    let id = "\(s.code)_\(leg)_\(i)_\(j)"
                    let first = leg == 0 ? ids[i] : ids[j]
                    let second = leg == 0 ? ids[j] : ids[i]
                    result[id] = MPFixture(id: id, a: first, b: second, seed: crossFold(id, 17))
                }
            }
        }
        return result
    }

    static func start(_ s: MPSession, _ actor: String) throws -> MPSession {
        if s.state != "WAITING" { return s }
        guard actor == s.host, s.participants.count == s.capacity else { throw MPError.permission }
        if s.knockout {
            guard s.rounds.isEmpty else { throw MPError.permission }
            let drawn = try draw(s, Array(s.participants.keys), 0)
            return try settle(drawn)
        }
        var next = s
        next.matches = try schedule(s)
        next.state = "ACTIVE"
        for m in Array(next.matches.values) where next.participants[m.a]?.bot != nil && next.participants[m.b]?.bot != nil {
            let o = simulate(next, m)
            next.matches[m.id] = pair(m, phase: .finished, a: o.0, b: o.1, winner: o.0 > o.1 ? m.a : m.b)
        }
        next.state = next.complete ? "FINISHED" : "ACTIVE"
        return next
    }

    static func ready(_ s: MPSession, _ id: String, _ uid: String, _ value: Bool) throws -> MPSession {
        guard let m = s.matches[id] else { throw MPError.missing }
        guard m.contains(uid), s.human(uid) else { throw MPError.permission }
        if m.phase == .playing || m.terminal { return s }
        var flags = m.ready
        flags[uid] = value ? true : nil
        var n = s
        n.matches[id] = pair(m, phase: flags.isEmpty ? .waiting : .ready, ready: flags)
        return n
    }

    static func startReady(_ s: MPSession, _ id: String) -> MPSession {
        guard let m = s.matches[id] else { return s }
        if m.phase == .playing || m.terminal { return s }
        let humans = [m.a, m.b].filter { s.participants[$0]?.bot == nil }
        if humans.isEmpty || humans.contains(where: { m.ready[$0] != true || !s.connected($0) }) { return s }
        let busy = s.matches.values.contains(where: { o in o.id != id && o.phase == .playing && humans.contains(where: { o.contains($0) }) })
        if busy { return s }
        var n = s
        n.matches[id] = pair(m, phase: .playing, ready: [:], starts: m.starts + 1)
        return n
    }

    static func leaveTournament(_ s: MPSession, _ actor: String) throws -> MPSession {
        guard s.kind == .tournament, s.human(actor) else { throw MPError.permission }
        let others = s.connectedHumans.filter { $0 != actor }.sorted()
        guard let successor = others.first else { throw MPError.permission }
        var n = s
        n.host = s.host == actor ? successor : s.host
        n.connections[actor] = nil
        if s.state == "WAITING" {
            n.participants[actor] = nil
            return n
        }
        n.departed[actor] = true
        if !s.knockout {
            for (id, m) in s.matches where m.contains(actor) && !m.terminal { n.matches[id] = pair(m, phase: .cancelled, ready: [:]) }
        }
        if n.knockout { return try settle(n) }
        n.state = n.complete ? "FINISHED" : "ACTIVE"
        return n
    }

    static func finish(_ s: MPSession, _ id: String, _ actor: String, _ a: Int, _ b: Int) throws -> MPSession {
        guard let m = s.matches[id] else { throw MPError.missing }
        if m.phase == .finished { return s }
        guard authority(s, m) == actor, m.phase == .playing else { throw MPError.permission }
        guard validFinal(s, a, b) else { throw MPError.permission }
        var n = s
        n.matches[id] = pair(m, phase: .finished, a: a, b: b, winner: a > b ? m.a : m.b)
        if n.knockout { return try settle(n) }
        n.state = n.complete ? "FINISHED" : "ACTIVE"
        return n
    }

    private static func validFinal(_ s: MPSession, _ a: Int, _ b: Int) -> Bool {
        if a < 0 || b < 0 || a == b || max(a, b) < s.target { return false }
        if !s.level.needsTwoPointLead { return max(a, b) == s.target && min(a, b) < s.target }
        return min(a, b) < s.target - 1 ? max(a, b) == s.target : abs(a - b) == 2
    }

    static func standings(_ s: MPSession) -> [MPStanding] {
        var rows: [String: MPStanding] = [:]
        for id in s.participants.keys { rows[id] = MPStanding(id: id) }
        for m in s.matches.values where m.phase == .finished {
            for id in [m.a, m.b] {
                guard var row = rows[id] else { continue }
                let win = id == m.winner
                row.played += 1
                row.wins += win ? 1 : 0
                row.losses += win ? 0 : 1
                row.points += win ? s.winPoints : s.lossPoints
                row.pointsFor += id == m.a ? m.scoreA : m.scoreB
                row.pointsAgainst += id == m.a ? m.scoreB : m.scoreA
                rows[id] = row
            }
        }
        return rows.values.sorted { x, y in
            if x.points != y.points { return x.points > y.points }
            if x.wins != y.wins { return x.wins > y.wins }
            let dx = x.pointsFor - x.pointsAgainst
            let dy = y.pointsFor - y.pointsAgainst
            if dx != dy { return dx > dy }
            if x.pointsFor != y.pointsFor { return x.pointsFor > y.pointsFor }
            return x.id < y.id
        }
    }

    private static func simulate(_ s: MPSession, _ m: MPFixture) -> (Int, Int) {
        let a = s.participants[m.a]?.bot ?? MPRoster.all[0].profile
        let b = s.participants[m.b]?.bot ?? MPRoster.all[0].profile
        var rng = MPKotlinRandom(seed: m.seed)
        let edge: Double = (a.strength - b.strength) * 0.055
        let p = (0.5 + edge).mpClamp(0.12, 0.88)
        var x = 0
        var y = 0
        while !validFinal(s, x, y) {
            if rng.nextDouble() < p { x += 1 } else { y += 1 }
        }
        return (x, y)
    }

    private static func koId(_ code: String, _ round: Int, _ pair: Int) -> String { "\(code)_K\(round)_\(pair)" }

    private static func koMatches(_ s: MPSession, _ round: Int) -> [MPFixture] {
        guard let count = s.rounds[round]?.players.count else { return [] }
        return (0..<(count / 2)).compactMap { s.matches[koId(s.code, round, $0)] }
    }

    private static func current(_ s: MPSession) -> Int { s.rounds.keys.max() ?? 0 }

    private static func eligible(_ s: MPSession, _ id: String) -> Bool {
        !id.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && s.participants[id] != nil && s.departed[id] != true
    }

    private static func advancing(_ s: MPSession, _ round: Int) -> [String] {
        var candidates = koMatches(s, round).filter { $0.terminal }.map { $0.winner }
        if let bye = s.rounds[round]?.bye { candidates.append(bye) }
        var result: [String] = []
        for id in candidates where eligible(s, id) && !result.contains(id) { result.append(id) }
        return result
    }

    static func knockoutWinner(_ s: MPSession) -> String? {
        guard s.complete else { return nil }
        let remaining = advancing(s, current(s))
        return remaining.count == 1 ? remaining[0] : nil
    }

    private static func draw(_ s: MPSession, _ players: [String], _ round: Int) throws -> MPSession {
        guard (0..<4).contains(round), (2...9).contains(players.count) else { throw MPError.permission }
        let seed = crossFold("\(s.code):\(s.createdAt):\(round)", 29)
        var random = MPKotlinRandom(seed: seed)
        let ids = random.shuffled(players.sorted())
        var n = s
        for p in 0..<(ids.count / 2) {
            let key = koId(s.code, round, p)
            n.matches[key] = MPFixture(id: key, a: ids[p * 2], b: ids[p * 2 + 1], seed: crossFold(key, seed))
        }
        n.rounds[round] = MPKnockoutRound(players: ids)
        n.state = "ACTIVE"
        return n
    }

    private static func settle(_ initial: MPSession) throws -> MPSession {
        var s = initial
        for _ in 0..<5 {
            let round = current(s)
            let games = koMatches(s, round)
            guard games.count == (s.rounds[round]?.players.count ?? 0) / 2 else { throw MPError.permission }
            for m in games {
                if m.terminal { continue }
                let updated: MPFixture
                if [m.a, m.b].contains(where: { !eligible(s, $0) }) {
                    let survivor = [m.a, m.b].first(where: { eligible(s, $0) }) ?? ""
                    updated = pair(m, phase: .cancelled, ready: [:], winner: survivor)
                } else if s.participants[m.a]?.bot != nil && s.participants[m.b]?.bot != nil {
                    let o = simulate(s, m)
                    updated = pair(m, phase: .finished, a: o.0, b: o.1, winner: o.0 > o.1 ? m.a : m.b)
                } else {
                    updated = m
                }
                s.matches[m.id] = updated
            }
            if koMatches(s, round).contains(where: { !$0.terminal }) {
                s.state = "ACTIVE"
                return s
            }
            let remaining = advancing(s, round)
            if remaining.count <= 1 {
                s.state = "FINISHED"
                return s
            }
            s = try draw(s, remaining, round + 1)
        }
        throw MPError.permission                      // Kotlin error("Knockout exceeded its bounded round count")
    }

    /// The record exactly as the original PongCodec wrote it: a/b/scoreA/scoreB, no seat lists, table size or seats.
    static func wire(_ s: MPSession) throws -> MPWire {
        var participants: MPWire = [:]
        for (id, p) in s.participants {
            var entry: MPWire = [:]
            entry["identity"] = try MPCodec.encode(p.identity)
            if let bot = p.bot { entry["bot"] = try MPCodec.encode(bot) } else { entry["bot"] = NSNull() }
            participants[id] = entry
        }
        var matches: MPWire = [:]
        for (id, m) in s.matches {
            var ready: [String: Bool] = [:]
            for (uid, flag) in m.ready where flag { ready[uid] = true }
            var entry: MPWire = [:]
            entry["id"] = m.id
            entry["a"] = m.a
            entry["b"] = m.b
            entry["seed"] = m.seed
            entry["phase"] = m.phase.rawValue
            entry["ready"] = ready
            entry["scoreA"] = m.scoreA
            entry["scoreB"] = m.scoreB
            entry["winner"] = m.winner
            entry["starts"] = m.starts
            entry["authorityUid"] = authority(s, m)
            matches[id] = entry
        }
        var connections: [String: [String: Bool]] = [:]
        for (uid, slots) in s.connections { connections[uid] = slots.filter { $0.value } }
        var w: MPWire = [:]
        w["code"] = s.code
        w["kind"] = s.kind.rawValue
        w["host"] = s.host
        w["capacity"] = s.capacity
        w["legs"] = s.legs
        w["winPoints"] = s.winPoints
        w["lossPoints"] = s.lossPoints
        w["difficulty"] = s.difficulty
        w["target"] = s.target
        w["roster"] = s.participants.keys.sorted()
        w["rosterSize"] = s.participants.count
        w["participants"] = participants
        w["matches"] = matches
        w["connections"] = connections
        w["departed"] = s.departed.filter { $0.value }
        w["state"] = s.state
        w["createdAt"] = s.createdAt
        w["lastActivityAt"] = s.lastActivityAt
        if s.knockout {
            w["format"] = s.format.rawValue
            var rounds: MPWire = [:]
            for (index, r) in s.rounds {
                var round: MPWire = [:]
                round["count"] = r.players.count
                round["players"] = r.players
                rounds[String(index)] = round
            }
            w["rounds"] = rounds
        }
        return w
    }
}

final class GroupMatchAdversarialTests: XCTestCase {

    // ---- Ready / start races ----

    // Kotlin: everyReadyOrderStartsAFourHumanTableExactlyOnce
    func testEveryReadyOrderStartsAFourHumanTableExactlyOnce() throws {
        let base = try MPRules.start(gmaTable(4, ["b", "c", "d"]), actor: "host")
        let id = gmaOnly(base).id
        var outcomes: [MPSession] = []
        for order in gmaOrders(["host", "b", "c", "d"]) {
            var s = base
            // Not ported: the LobbyEvents cue count ("one cue per peer, none for the host's own Ready or the start") — the Swift
            // equivalent is MPController.lobbyCues, which is private.
            for (i, uid) in order.enumerated() {
                // Every client that observes a change may race to start; nothing starts before the last Ready.
                for _ in 0..<2 { XCTAssertEqual(MPRules.startReady(s, match: id), s, "\(order)") }
                s = try MPRules.ready(s, match: id, uid: uid, value: true)
                XCTAssertEqual(gmaOnly(s).phase, .ready)
                XCTAssertEqual(gmaOnly(s).readySet, Set(order.prefix(i + 1)))
                let raced = MPRules.startReady(s, match: id)
                if i < order.count - 1 { XCTAssertEqual(raced, s, "\(order)") } else { s = raced }
            }
            for _ in 0..<3 { XCTAssertEqual(MPRules.startReady(s, match: id), s) }
            for uid in order { XCTAssertEqual(try MPRules.ready(s, match: id, uid: uid, value: false), s) }
            outcomes.append(s)
        }
        XCTAssertFalse(outcomes.isEmpty)
        let playing = outcomes[0]
        XCTAssertTrue(outcomes.allSatisfy { $0 == playing }, "every order ends in the same room")
        XCTAssertEqual(gmaOnly(playing).phase, .playing)
        XCTAssertEqual(gmaOnly(playing).starts, 1)
        XCTAssertTrue(gmaOnly(playing).ready.isEmpty)
    }

    // Kotlin: randomReadyCancelPresenceAndResultRacesNeverStartEarlyTwiceOrRewriteAResult
    func testRandomReadyCancelPresenceAndResultRacesNeverStartEarlyTwiceOrRewriteAResult() throws {
        var rng = MPKotlinRandom(intSeed: 73)
        var starts = 0
        var results = 0
        var refused = 0
        for trial in 0..<400 {
            let size = 3 + trial % 2
            let people = 1 + rng.nextIndex(size)
            let guests = Array(["b", "c", "d"].prefix(people - 1))
            let humans = ["host"] + guests
            var s = try MPRules.start(gmaTable(size, guests, bots: size - people), actor: "host")
            let first = gmaOnly(s)
            let id = first.id
            let authority = s.authority(first)
            XCTAssertEqual(humans.min(), authority)
            for _ in 0..<80 {
                let before = s
                let was = gmaOnly(before)
                let uid = rng.element(humans)
                let op: String
                switch rng.nextIndex(12) {
                case 0...2: op = "ready"
                case 3...4: op = "start"
                case 5: op = "house"
                case 6: op = "away"
                case 7...8: op = "back"
                default: op = "finish"
                }
                let value = rng.nextIndex(4) > 0
                let actor = rng.element(first.players + ["outsider"])
                let winner = rng.nextIndex(size)
                var scores: [Int] = []
                for i in 0..<size { scores.append(i == winner ? before.target : rng.nextIndex(before.target)) }
                var outcome: MPSession? = nil
                var failure: Error? = nil
                do {
                    switch op {
                    case "ready": outcome = try MPRules.ready(before, match: id, uid: uid, value: value)
                    case "start": outcome = MPRules.startReady(before, match: id)
                    case "house": outcome = MPRules.friendlyHouseReady(before, actor: "host")
                    case "away":
                        var n = before
                        n.connections[uid] = nil
                        outcome = n
                    case "back":
                        var n = before
                        n.connections[uid] = ["\(trial)": true]
                        outcome = n
                    default:
                        outcome = try MPRules.finish(before, match: id, actor: actor, scores: scores, placement: gmaRanked(first.players, scores))
                    }
                } catch {
                    failure = error
                }
                if op != "finish" {
                    XCTAssertNil(failure, "\(op) \(String(describing: failure))")
                } else if was.phase == .finished {
                    XCTAssertEqual(outcome, before)
                } else if actor == authority && was.phase == .playing {
                    if let result = outcome {
                        let done = gmaOnly(result)
                        results += 1
                        XCTAssertEqual(done.phase, .finished)
                        XCTAssertEqual(done.scores, scores)
                        XCTAssertEqual(done.placement.first, done.winner)
                    } else {
                        XCTFail("the authority's valid result was refused: \(String(describing: failure))")
                    }
                } else {
                    XCTAssertTrue(failure is MPError, "\(op) \(actor) \(was.phase)")
                    refused += 1
                }
                s = outcome ?? before
                let now = gmaOnly(s)
                XCTAssertEqual(now.players, first.players)
                XCTAssertTrue(now.starts <= 1)
                XCTAssertEqual(now.starts == 1, now.phase == .playing || now.phase == .finished)
                if was.phase != .playing && now.phase == .playing {
                    starts += 1
                    XCTAssertEqual(op, "start")
                    XCTAssertTrue(now.ready.isEmpty)
                    XCTAssertTrue(humans.allSatisfy { was.ready[$0] == true && before.connected($0) }, "only when every human is Ready and connected")
                }
                if now.phase == .waiting || now.phase == .ready {
                    XCTAssertEqual(now.ready.isEmpty, now.phase == .waiting)
                    XCTAssertTrue(now.readySet.isSubset(of: Set(humans)))
                }
                if op == "house" && humans.count > 1 { XCTAssertEqual(s, before, "house Ready never speaks for another human") }
                if was.phase == .finished { XCTAssertEqual(now, was) }
            }
        }
        print("table races: \(starts) starts, \(results) results, \(refused) refusals")
        XCTAssertTrue(starts > 250, "\(starts) starts")
        XCTAssertTrue(results > 150, "\(results) results")
        XCTAssertTrue(refused > 1000, "\(refused) refusals")
    }

    // Kotlin: classicRoundRobinStartsInAnyOrderNeverPutAPlayerInTwoLiveMatches
    func testClassicRoundRobinStartsInAnyOrderNeverPutAPlayerInTwoLiveMatches() throws {
        var s = try gmaCreate("ABC234", .tournament, MPIdentity(id: "a", name: "A"), 4, 1, 3, 0, 0, 3)
        for uid in ["b", "c", "d"] { s = try MPRules.join(s, MPIdentity(id: uid, name: uid)) }
        s = try MPRules.start(gmaOnline(s), actor: "a")
        for m in Array(s.matches.values) {
            for uid in m.players { s = try MPRules.ready(s, match: m.id, uid: uid, value: true) }
        }
        for order in gmaOrders(s.matches.keys.sorted()) {
            var x = s
            for id in order {
                x = MPRules.startReady(x, match: id)
                for uid in x.participants.keys {
                    let live = x.matches.values.filter { $0.phase == .playing && $0.contains(uid) }.count
                    XCTAssertTrue(live <= 1, "\(order)")
                }
            }
            let playing = x.matches.values.filter { $0.phase == .playing }
            XCTAssertEqual(playing.count, 2, "\(order)")
            XCTAssertEqual(Set(playing.flatMap { $0.players }).count, 4)
            XCTAssertTrue(playing.map { $0.id }.contains(order[0]))
            XCTAssertTrue(playing.allSatisfy { $0.starts == 1 })
        }
    }

    // ---- Lobby departures, seats, host transfer, house players ----

    // Kotlin: aHumanWhoLeavesTheLobbyBeforeTheStartKeepsTheSeatAndTheTableWaitsForThem
    func testAHumanWhoLeavesTheLobbyBeforeTheStartKeepsTheSeatAndTheTableWaitsForThem() throws {
        var s = try gmaTable(4, ["b"])
        s.connections["b"] = nil                                            // b joined, then closed the app
        XCTAssertEqual(s.seating(), ["host": 0, "b": 1])
        XCTAssertThrowsError(try MPRules.leave(s, actor: "b"))
        XCTAssertFalse(MPRules.canDelete(s, actor: "b"))
        XCTAssertThrowsError(try MPRules.chooseSeat(MPRules.join(s, MPIdentity(id: "c", name: "C")), actor: "c", seat: 1))
        s = try MPRules.join(MPRules.join(s, MPIdentity(id: "c", name: "C")), MPIdentity(id: "d", name: "D"))
        XCTAssertEqual(s.seating(), ["host": 0, "b": 1, "c": 2, "d": 3])
        XCTAssertFalse(MPRules.acceptsNewPlayer(s))
        XCTAssertThrowsError(try MPRules.join(s, MPIdentity(id: "e", name: "E")))
        XCTAssertEqual(try MPRules.addFriendlyHousePlayer(s, actor: "host", bot: gmaBot(0)), s)
        s = try MPRules.start(gmaOnline(s, "b"), actor: "host")
        let id = gmaOnly(s).id
        XCTAssertEqual(gmaOnly(s).players, ["host", "b", "c", "d"])
        XCTAssertEqual(s.authority(gmaOnly(s)), "b")
        for uid in ["host", "c", "d"] { s = try MPRules.ready(s, match: id, uid: uid, value: true) }
        XCTAssertEqual(MPRules.startReady(s, match: id), s)
        s = try MPRules.ready(s, match: id, uid: "b", value: true)          // a Ready saved while away does not start the table
        XCTAssertEqual(MPRules.startReady(s, match: id), s)
        XCTAssertTrue(MPRules.canFinishFriendly(s, actor: "b"))
        XCTAssertFalse(MPRules.canFinishFriendly(s, actor: "e"))
        var back = s
        back.connections["b"] = ["1": true]
        let playing = MPRules.startReady(back, match: id)
        XCTAssertEqual(gmaOnly(playing).phase, .playing)
        XCTAssertEqual(gmaOnly(playing).starts, 1)
        XCTAssertEqual(try MPRules.join(playing, MPIdentity(id: "b", name: "B again")), playing)   // re-entry never re-seats or resets
        XCTAssertThrowsError(try MPRules.chooseSeat(playing, actor: "b", seat: 0))
    }

    // Kotlin: corruptedSeatMapsAlwaysSeatEveryoneOnceInRangeWhateverTheirOrder
    func testCorruptedSeatMapsAlwaysSeatEveryoneOnceInRangeWhateverTheirOrder() {
        var rng = MPKotlinRandom(intSeed: 11)
        // Kotlin `associateBy` keeps insertion order: the four humans, then three house players.
        let peopleOrder = ["host", "amy", "zed", "bob"] + (0...2).map { gmaBot($0).id }
        var people: [String: MPParticipant] = [:]
        for uid in ["host", "amy", "zed", "bob"] { people[uid] = MPParticipant(identity: MPIdentity(id: uid, name: uid), bot: nil) }
        for i in 0...2 { people[gmaBot(i).id] = gmaBot(i) }
        for _ in 0..<3000 {
            let size = 2 + rng.nextIndex(3)
            let shuffledOthers = rng.shuffled(peopleOrder.filter { $0 != "host" })
            let members = ["host"] + Array(shuffledOthers.prefix(rng.nextIndex(size)))
            let memberOrder = rng.shuffled(members)
            var participants: [String: MPParticipant] = [:]
            for uid in memberOrder { participants[uid] = people[uid] }
            let candidates = rng.shuffled(peopleOrder + ["ghost"])
            let claimers = Array(candidates.prefix(rng.nextIndex(peopleOrder.count + 2)))
            var claims: [(String, Int)] = []
            for uid in claimers { claims.append((uid, -2 + rng.nextIndex(size + 5))) }      // Kotlin nextInt(-2, size + 3)
            var s = MPSession(code: "ABC234", kind: .friendly, host: MPIdentity(id: "host", name: "host"), capacity: size, tableSize: size)
            s.capacity = size
            s.tableSize = size
            s.participants = participants
            s.seats = Dictionary(uniqueKeysWithValues: claims)
            s.createdAt = 0
            s.lastActivityAt = 0
            let seating = s.seating()
            XCTAssertEqual(Set(participants.keys), Set(seating.keys))
            XCTAssertEqual(seating.count, Set(seating.values).count)
            XCTAssertTrue(seating.values.allSatisfy { $0 >= 0 && $0 < size }, "\(claims) -> \(seating)")
            let reclaimed = rng.shuffled(claims)
            let reordered = rng.shuffled(memberOrder)
            var copy = s
            copy.seats = Dictionary(uniqueKeysWithValues: reclaimed)
            var shuffledParticipants: [String: MPParticipant] = [:]
            for uid in reordered { shuffledParticipants[uid] = people[uid] }
            copy.participants = shuffledParticipants
            XCTAssertEqual(seating, copy.seating())
            // Every valid claim is honoured; a doubly claimed seat goes to the smaller uid, the other player moves to a free seat.
            for seat in 0..<size {
                let claimants = claims.filter { $0.1 == seat && participants[$0.0] != nil }.map { $0.0 }
                if let owner = claimants.min() { XCTAssertEqual(seating[owner], seat) }
            }
            XCTAssertEqual((0..<size).filter { !seating.values.contains($0) }, s.freeSeats())
            if participants.count < size {
                var roomy = s
                roomy.capacity = size
                XCTAssertTrue(MPRules.acceptsNewPlayer(roomy))
            }
        }
    }

    // Kotlin: seatRacesResolveLikeSerialTransactionsAndNobodyIsMovedByAnotherPlayer
    func testSeatRacesResolveLikeSerialTransactionsAndNobodyIsMovedByAnotherPlayer() throws {
        let ops: [GMASeatOp] = [
            GMASeatOp(name: "c joins", mover: nil, apply: { try MPRules.join($0, MPIdentity(id: "c", name: "C")) }),
            GMASeatOp(name: "b moves to 2", mover: "b", apply: { try MPRules.chooseSeat($0, actor: "b", seat: 2) }),
            GMASeatOp(name: "house to 2", mover: nil, apply: { try MPRules.addFriendlyHousePlayer($0, actor: "host", bot: gmaBot(0), seat: 2) }),
            GMASeatOp(name: "house anywhere", mover: nil, apply: { try MPRules.addFriendlyHousePlayer($0, actor: "host", bot: gmaBot(1)) }),
            GMASeatOp(name: "host moves to 3", mover: "host", apply: { try MPRules.chooseSeat($0, actor: "host", seat: 3) }),
        ]
        var endings = Set<[String: Int]>()
        for order in gmaOrders(ops) {
            var s = try gmaTable(4, ["b"])
            let path = order.map { $0.name }
            for op in order {
                let before = s
                var outcome: MPSession? = nil
                var failure: Error? = nil
                do { outcome = try op.apply(before) } catch { failure = error }
                if let error = failure { XCTAssertTrue(error is MPError, "\(path) \(op.name): \(error)") }
                s = outcome ?? before
                let was = before.seating()
                let now = s.seating()
                XCTAssertEqual(Set(s.participants.keys), Set(now.keys))
                XCTAssertEqual(now.count, Set(now.values).count)
                XCTAssertTrue(now.values.allSatisfy { $0 >= 0 && $0 <= 3 })
                for (uid, seat) in was where uid != op.mover { XCTAssertEqual(now[uid], seat, "\(path) \(op.name) moved \(uid)") }
                if let mover = op.mover, outcome != nil, let digit = op.name.last { XCTAssertEqual(now[mover], Int(String(digit))) }
                if op.name == "house to 2" && s != before { XCTAssertEqual(now[gmaBot(0).id], 2) }
            }
            XCTAssertEqual(s.participants.count, 4)                         // two of the three newcomers always fit
            let m = try gmaOnly(MPRules.start(s, actor: "host"))
            let seatOrder = s.seating().sorted { $0.value < $1.value }.map { $0.key }
            XCTAssertEqual(m.players, seatOrder)
            XCTAssertEqual(Set(m.players).count, 4)
            endings.insert(s.seating())
        }
        XCTAssertTrue(endings.count > 1, "the order decides who gets a contested seat")
    }

    // Kotlin: hostTransferMovesManagementButNeverTheAuthorityOfAHumanFixture
    func testHostTransferMovesManagementButNeverTheAuthorityOfAHumanFixture() throws {
        var w = try gmaCreate("ABC234", .tournament, MPIdentity(id: "host", name: "Host"), 4, 1, 3, 0, 0, 3)
        for uid in ["zed", "amy"] { w = try MPRules.join(w, MPIdentity(id: uid, name: uid)) }
        w = try gmaOnline(MPRules.addBot(w, actor: "host", bot: gmaBot(0)))
        let moved = try MPRules.leave(w, actor: "host")
        XCTAssertEqual(moved.host, "amy")
        XCTAssertNil(moved.participants["host"])
        XCTAssertTrue(moved.seats.isEmpty)
        XCTAssertEqual(moved.tableSize, 2)
        XCTAssertThrowsError(try MPRules.addBot(moved, actor: "host", bot: gmaBot(1)))
        XCTAssertThrowsError(try MPRules.start(moved, actor: "amy"))
        let full = try MPRules.addBot(moved, actor: "amy", bot: gmaBot(1))
        XCTAssertThrowsError(try MPRules.start(full, actor: "zed"))
        let started = try MPRules.start(full, actor: "amy")
        XCTAssertEqual(started.matches.count, 6)
        let simulatedPairs = started.matches.values.filter { MPRules.houseOnly(started, $0) }
        XCTAssertEqual(simulatedPairs.count, 1)
        guard let simulatedPair = simulatedPairs.first else { return }
        XCTAssertEqual(simulatedPair.phase, .finished)
        XCTAssertEqual(started.authority(simulatedPair), "amy")
        var before: [String: String] = [:]
        for m in started.matches.values { before[m.id] = started.authority(m) }
        let left = try MPRules.leave(started, actor: "amy")
        XCTAssertEqual(left.host, "zed")
        XCTAssertEqual(left.departed["amy"], true)
        let encoded = try gmaEncode(left)
        let wire = MPCodec.map(encoded["matches"])
        for m in left.matches.values {
            let expected = m.id == simulatedPair.id ? "zed" : (before[m.id] ?? "")
            XCTAssertEqual(left.authority(m), expected)
            XCTAssertEqual(MPCodec.map(wire[m.id])["authorityUid"] as? String, left.authority(m))
            if m.contains("amy") {
                XCTAssertEqual(m.phase, .cancelled)
                XCTAssertEqual(m.scores, [0, 0])
                XCTAssertEqual(m.winner, "")
                XCTAssertTrue(m.placement.isEmpty)
            }
        }
        // Swift's leave refreshes every fixture's cached authorityUid (here "amy" -> "zed"); the record is otherwise unchanged.
        XCTAssertEqual(left.matches[simulatedPair.id].map { gmaBareFixture($0) }, gmaBareFixture(simulatedPair))
        XCTAssertThrowsError(try MPRules.leave(left, actor: "zed"))
        XCTAssertTrue(MPRules.canDelete(left, actor: "zed"))
        // A friendly table has no host transfer: nobody leaves it, and only the host manages it.
        let f = try gmaTable(3, ["b"])
        XCTAssertThrowsError(try MPRules.leave(f, actor: "host"))
        XCTAssertThrowsError(try MPRules.leave(f, actor: "b"))
        XCTAssertThrowsError(try MPRules.addFriendlyHousePlayer(f, actor: "b", bot: gmaBot(0)))
        XCTAssertThrowsError(try MPRules.addBot(f, actor: "b", bot: gmaBot(0)))
        let full3 = try MPRules.addFriendlyHousePlayer(f, actor: "host", bot: gmaBot(0))
        XCTAssertThrowsError(try MPRules.start(full3, actor: "b"))
        var hostAway = full3
        hostAway.connections["host"] = nil
        let active = try MPRules.start(hostAway, actor: "host")
        XCTAssertEqual(active.authority(gmaOnly(active)), "b")
        XCTAssertEqual(MPRules.friendlyHouseReady(active, actor: "b"), active)
        XCTAssertEqual(MPRules.friendlyHouseReady(active, actor: "host"), active)    // another human must choose Ready
    }

    // Kotlin: housePlayersFillOnlyFreeSeatsInAnyOrderAndTheHostStartsAFullHouseTable
    func testHousePlayersFillOnlyFreeSeatsInAnyOrderAndTheHostStartsAFullHouseTable() throws {
        for size in 2...4 {
            for order in gmaOrders(Array(1..<size)) {
                var s = try gmaTable(size)
                for (i, seat) in order.enumerated() {
                    XCTAssertEqual(try MPRules.addFriendlyHousePlayer(s, actor: "host", bot: gmaBot(9), seat: 0), s)
                    XCTAssertThrowsError(try MPRules.addBot(s, actor: "host", bot: gmaBot(9), seat: 0))
                    XCTAssertThrowsError(try MPRules.addFriendlyHousePlayer(s, actor: "host", bot: gmaBot(9), seat: size))
                    XCTAssertThrowsError(try MPRules.addFriendlyHousePlayer(s, actor: "guest", bot: gmaBot(9), seat: seat))
                    s = try MPRules.addFriendlyHousePlayer(s, actor: "host", bot: gmaBot(i), seat: seat)
                    XCTAssertEqual(s.seating()[gmaBot(i).id], seat)
                    if !s.freeSeats().isEmpty { XCTAssertThrowsError(try MPRules.addFriendlyHousePlayer(s, actor: "host", bot: gmaBot(i))) }
                }
                XCTAssertTrue(s.freeSeats().isEmpty)
                XCTAssertFalse(MPRules.acceptsNewPlayer(s))
                XCTAssertEqual(try MPRules.addFriendlyHousePlayer(s, actor: "host", bot: gmaBot(8)), s)
                XCTAssertThrowsError(try MPRules.join(s, MPIdentity(id: "late", name: "Late")))
                let started = try MPRules.start(s, actor: "host")
                let m = gmaOnly(started)
                var expectedPlayers = ["host"]
                for seat in 1..<size { expectedPlayers.append(gmaBot(order.firstIndex(of: seat) ?? -1).id) }
                XCTAssertEqual(m.players, expectedPlayers)
                XCTAssertEqual(started.authority(m), "host")
                XCTAssertFalse(MPRules.houseOnly(started, m))
                for b in m.players.dropFirst() { XCTAssertThrowsError(try MPRules.ready(started, match: m.id, uid: b, value: true)) }
                let readyRoom = MPRules.friendlyHouseReady(started, actor: "host")
                XCTAssertEqual(gmaOnly(readyRoom).readySet, ["host"])
                XCTAssertEqual(MPRules.friendlyHouseReady(readyRoom, actor: "host"), readyRoom)
                let playing = MPRules.startReady(readyRoom, match: m.id)
                XCTAssertEqual(gmaOnly(playing).phase, .playing)
                XCTAssertEqual(gmaOnly(playing).starts, 1)
                var scores: [Int] = []
                if size == 2 { scores = [2, 5] } else { for i in 0..<size { scores.append(i == size - 1 ? 5 : size - 2 - i) } }
                let done = try MPRules.finish(playing, match: m.id, actor: "host", scores: scores, placement: gmaRanked(m.players, scores))
                XCTAssertTrue(done.complete)
                XCTAssertEqual(gmaOnly(done).winner, m.players.last)
                XCTAssertFalse(MPCompletionText.won(done, "host"))
            }
        }
    }

    // ---- Results ----

    // Kotlin: everyMalformedTableResultIsRejectedAndAFinishedTableNeverChanges
    func testEveryMalformedTableResultIsRejectedAndAFinishedTableNeverChanges() throws {
        for size in 3...4 {
            var s = try MPRules.start(gmaTable(size, ["b", "c"], bots: size - 3), actor: "host")
            let m = gmaOnly(s)
            let id = m.id
            let players = m.players
            XCTAssertEqual(s.authority(m), "b")
            let good = Array([1, 5, 3, 3].prefix(size))
            let best = gmaRanked(players, good)
            let target = s.target
            for uid in ["host", "b", "c"] { s = try MPRules.ready(s, match: id, uid: uid, value: true) }
            XCTAssertThrowsError(try MPRules.finish(s, match: id, actor: "b", scores: good, placement: best))   // READY, not playing
            let playing = MPRules.startReady(s, match: id)
            XCTAssertEqual(gmaOnly(playing).phase, .playing)
            var cancelledFixture = gmaOnly(playing)
            cancelledFixture.phase = .cancelled
            var cancelled = playing
            cancelled.matches = [id: cancelledFixture]
            XCTAssertThrowsError(try MPRules.finish(cancelled, match: id, actor: "b", scores: good, placement: best))
            for actor in players.filter({ $0 != "b" }) + ["outsider", "", "B"] {
                XCTAssertThrowsError(try MPRules.finish(playing, match: id, actor: actor, scores: good, placement: best))
            }
            for n in 0...6 where n != size {
                var scores: [Int] = []
                for i in 0..<n { scores.append(i == 1 ? target : 0) }
                let cut = Array(best.prefix(n))
                var padded = cut
                for i in 0..<max(0, n - size) { padded.append("z\(i)") }
                XCTAssertThrowsError(try MPRules.finish(playing, match: id, actor: "b", scores: scores, placement: best))
                XCTAssertThrowsError(try MPRules.finish(playing, match: id, actor: "b", scores: scores, placement: cut))
                XCTAssertThrowsError(try MPRules.finish(playing, match: id, actor: "b", scores: good, placement: padded))
            }
            XCTAssertThrowsError(try MPRules.finish(playing, match: id, actor: "b", a: 5, b: 0))         // the classic overload needs a pair
            var badScores: [[Int]] = []
            badScores.append(good.enumerated().map { $0.offset == 2 ? target : $0.element })            // two players at the target
            badScores.append(good.map { min($0, target - 1) })                                          // nobody at the target
            badScores.append(good.enumerated().map { $0.offset == 1 ? target + 1 : $0.element })        // beyond the target
            badScores.append(good.enumerated().map { $0.offset == 0 ? -1 : $0.element })                // negative
            badScores.append(Array(repeating: target, count: size))
            badScores.append(Array(repeating: 0, count: size))
            for scores in badScores {
                XCTAssertThrowsError(try MPRules.finish(playing, match: id, actor: "b", scores: scores, placement: gmaRanked(players, scores)))
            }
            var badPlacements: [[String]] = []
            badPlacements.append(Array(best.dropFirst()))
            badPlacements.append(best + ["z"])
            badPlacements.append(best.map { $0 == "c" ? "z" : $0 })
            badPlacements.append(best.map { $0 == "c" ? "host" : $0 })
            badPlacements.append(best.map { $0 == "host" ? "b" : $0 })
            badPlacements.append(Array(best.reversed()))
            badPlacements.append([best[1], best[0]] + Array(best.dropFirst(2)))
            badPlacements.append([best[best.count - 1]] + Array(best.dropLast()))
            badPlacements.append(best + best)
            for placement in badPlacements {
                XCTAssertThrowsError(try MPRules.finish(playing, match: id, actor: "b", scores: good, placement: placement))
            }
            if size == 4 { XCTAssertTrue(MPRules.validPlacement(m, good, ["b", gmaBot(0).id, "c", "host"])) }   // tied places in either order
            let done = try MPRules.finish(playing, match: id, actor: "b", scores: good, placement: best)
            XCTAssertEqual(gmaOnly(done).scores, good)
            XCTAssertEqual(gmaOnly(done).placement, best)
            XCTAssertEqual(gmaOnly(done).winner, "b")
            XCTAssertTrue(done.complete)
            for actor in players + ["outsider"] {
                for scores in badScores + [good, [target]] {
                    let ranking = gmaRanked(Array(players.prefix(scores.count)), scores)
                    XCTAssertEqual(try MPRules.finish(done, match: id, actor: actor, scores: scores, placement: ranking), done)
                }
            }
            XCTAssertEqual(try MPRules.finish(done, match: id, actor: "b", a: 5, b: 0), done)
            XCTAssertEqual(MPRules.startReady(done, match: id), done)
            for uid in ["host", "b", "c"] { XCTAssertEqual(try MPRules.ready(done, match: id, uid: uid, value: true), done) }
            XCTAssertEqual(try gmaDecode(gmaEncode(done)), done)
        }
        // A classic pair through the seat-list API keeps the same checks plus the deuce rule (MEDIUM: win by two).
        var p = try gmaCreate("ABC234", .tournament, MPIdentity(id: "a", name: "A"), 2, 1, 3, 0, 2, 5)
        p = try MPRules.start(gmaOnline(MPRules.join(p, MPIdentity(id: "b", name: "B"))), actor: "a")
        let pid = gmaOnly(p).id
        p = try MPRules.startReady(MPRules.ready(MPRules.ready(p, match: pid, uid: "a", value: true), match: pid, uid: "b", value: true), match: pid)
        let pairCases: [([Int], [String])] = [([5], ["a"]), ([5, 0, 0], ["a", "b", "b"]), ([5, 0], ["a", "a"]), ([5, 0], ["b", "a"]),
                                              ([5, 4], ["a", "b"]), ([6, 6], ["a", "b"]), ([5, -1], ["a", "b"])]
        for (scores, placement) in pairCases {
            XCTAssertThrowsError(try MPRules.finish(p, match: pid, actor: "a", scores: scores, placement: placement))
        }
        XCTAssertThrowsError(try MPRules.finish(p, match: pid, actor: "b", scores: [5, 0], placement: ["a", "b"]))
        let pair = try MPRules.finish(p, match: pid, actor: "a", scores: [7, 9], placement: ["b", "a"])
        XCTAssertEqual(gmaOnly(pair).winner, "b")
        XCTAssertEqual(gmaOnly(pair).scores, [7, 9])
        XCTAssertEqual(try MPRules.finish(pair, match: pid, actor: "a", scores: [5, 0], placement: ["a", "b"]), pair)
        XCTAssertEqual(try MPRules.finish(pair, match: pid, actor: "b", a: 5, b: 0), pair)
        // A malformed stored fixture (one uid in two seats; there are no RTDB rules for it yet) never takes a ranking that is not a
        // permutation of its players.
        let raw: MPWire = ["id": "T", "players": ["b", "b", "c"], "seed": Int64(1), "phase": "PLAYING", "scores": [Int64(0), Int64(0), Int64(0)]]
        let twice = try MPCodec.decode(MPFixture.self, raw)
        var bad = try gmaTable(3, ["b", "c"])
        bad.state = "ACTIVE"
        bad.matches = ["T": twice]
        for placement in [["b", "c", "c"], ["b", "b", "c"]] {
            XCTAssertThrowsError(try MPRules.finish(bad, match: "T", actor: "b", scores: [1, 5, 0], placement: placement))
        }
        XCTAssertFalse(MPRules.validPlacement(twice, [1, 5, 0], ["b", "c", "c"]))
    }

    // Kotlin: houseOnlyTablesFinishValidlyForExtremeSeedsAndTargets
    func testHouseOnlyTablesFinishValidlyForExtremeSeedsAndTargets() {
        let seeds: [Int64] = [Int64.min, Int64.min + 1, -1, 0, 1, Int64.max]
        for n in 3...4 {
            for seed in seeds {
                for target in [1, 3, 5, 7, 10, 11] {
                    let players = gmaHouse.prefix(n).map { "bot_\($0.id)" }
                    let bots = gmaHouse.prefix(n).map { $0.profile }
                    let log = GMABox<[MPTableSimulation.Rally]>([])
                    let r = MPTableSimulation.play(players, bots, target: target, seed: seed, trace: { log.value.append($0) })
                    XCTAssertEqual(r, MPTableSimulation.play(players, bots, target: target, seed: seed))
                    XCTAssertEqual(r.scores.filter { $0 == target }.count, 1)
                    XCTAssertTrue(r.scores.allSatisfy { $0 >= 0 && $0 <= target })
                    XCTAssertEqual(Set(players), Set(r.placement))
                    if let at = r.scores.firstIndex(of: target) { XCTAssertEqual(r.placement.first, players[at]) } else { XCTFail("nobody reached \(target)") }
                    XCTAssertEqual(log.value.first?.server, Int(crossMod(seed, Int64(n))))
                    var s = MPSession(code: "ABC234", kind: .friendly, host: MPIdentity(id: "h", name: "h"), capacity: n, tableSize: n)
                    s.capacity = n
                    s.target = target                                           // Kotlin Session(target = target): not normalized
                    s.tableSize = n
                    XCTAssertTrue(MPRules.validFinal(s, target: s.target, scores: r.scores))
                    XCTAssertTrue(MPRules.validPlacement(MPFixture(id: "m", players: players, seed: seed), r.scores, r.placement))
                }
            }
        }
        // Swift returns an all-zero result instead of throwing (Kotlin `require` on 3...4 players and one profile each):
        let plain = MPBot(speed: 5, reaction: 5, accuracy: 5, power: 5, agility: 5, characterId: "", forehandSkill: 5, backhandSkill: 5, serveSkill: 5)
        XCTAssertEqual(MPTableSimulation.play(["a", "b"], [plain, plain], target: 3, seed: 1), MPTableResult(scores: [0, 0], placement: ["a", "b"]))
        XCTAssertEqual(MPTableSimulation.play(["a", "b", "c"], [plain, plain], target: 3, seed: 1),
                       MPTableResult(scores: [0, 0, 0], placement: ["a", "b", "c"]))
    }

    // ---- Classic two-player behaviour against the original rules ----

    // Kotlin: classicTournamentsFollowTheOriginalTwoPlayerRulesStepByStep
    func testClassicTournamentsFollowTheOriginalTwoPlayerRulesStepByStep() throws {
        var rng = MPKotlinRandom(intSeed: 20261002)
        var compared = 0
        var completed = 0
        var legacyLoads = 0
        var results = 0
        var aborted = false                                               // Kotlin aborts the test on a success/failure mismatch
        for trial in 0..<240 {
            let knockout = trial % 2 == 1
            let format: MPTournamentFormat = knockout ? .knockout : .roundRobin
            let size = 2 + rng.nextIndex(knockout ? 8 : 7)
            let difficulty = rng.nextIndex(5)
            let target = rng.element([3, 5, 7, 10, 11, 6])
            let legs = 1 + rng.nextIndex(2)
            let win = rng.nextIndex(6)
            let loss = rng.nextIndex(3)
            var codeLetters: [Character] = []
            for _ in 0..<6 { codeLetters.append(MPRules.alphabet[rng.nextIndex(MPRules.alphabet.count)]) }     // Kotlin PongRules.code(rng)
            let code = String(codeLetters)
            let host = "u\(rng.nextIndex(100))"
            var now = try gmaCreate(code, .tournament, MPIdentity(id: host, name: "Host"), size, legs, win, loss, difficulty, target, format: format)
            now.createdAt = Int64(trial)
            var old = try GMAOriginal.create(code, .tournament, MPIdentity(id: host, name: "Host"), size, legs, win, loss, difficulty, target, format)
            old.createdAt = Int64(trial)
            XCTAssertEqual(old, now)
            // Kotlin picks random members from old.participants in insertion order (LinkedHashMap); Swift tracks that order.
            var oldOrder = [host]
            func step(_ label: String, _ next: (MPSession) throws -> MPSession, _ original: (MPSession) throws -> MPSession) {
                let place = "trial \(trial), \(label)"
                var x: MPSession? = nil
                var xError: Error? = nil
                do { x = try next(now) } catch { xError = error }
                var y: MPSession? = nil
                var yError: Error? = nil
                do { y = try original(old) } catch { yError = error }
                XCTAssertEqual(y != nil, x != nil, "\(place): \(String(describing: xError)) vs \(String(describing: yError))")
                if (y != nil) != (x != nil) {
                    aborted = true
                    return
                }
                if let originalError = yError {
                    if let nextError = xError {
                        XCTAssertEqual(String(describing: type(of: originalError)), String(describing: type(of: nextError)), place)
                    }
                } else if let nextRoom = x, let oldRoom = y {
                    now = nextRoom
                    old = oldRoom
                    let previous = oldOrder
                    let added = oldRoom.participants.keys.filter { !previous.contains($0) }.sorted()
                    oldOrder = previous.filter { oldRoom.participants[$0] != nil } + added
                }
                XCTAssertEqual(old, gmaClassic(now), place)
                XCTAssertEqual(GMAOriginal.standings(old), MPRules.standings(now), place)
                if knockout { XCTAssertEqual(GMAOriginal.knockoutWinner(old), MPKnockout.winner(now), place) }
                for m in now.matches.values where !m.placement.isEmpty {
                    XCTAssertEqual(m.phase, .finished, place)
                    let others = m.players.filter { $0 != m.winner }
                    XCTAssertEqual(others.count, 1, place)
                    XCTAssertEqual([m.winner] + others, m.placement, place)
                }
                compared += 1
            }
            var generic = 0
            while !aborted && old.participants.count < old.capacity {
                switch rng.nextIndex(4) {
                case 0:
                    let p = MPIdentity(id: "u\(rng.nextIndex(100))", name: "Player")
                    step("join", { try MPRules.join($0, p) }, { try GMAOriginal.join($0, p) })
                case 1:
                    let b = gmaBot(rng.nextIndex(gmaHouse.count))
                    step("house player", { try MPRules.addBot($0, actor: $0.host, bot: b) }, { try GMAOriginal.addBot($0, $0.host, b) })
                case 2:
                    let houseId = "bot_g\(generic)"
                    generic += 1
                    let speed = 1 + rng.nextIndex(10)
                    let reaction = 1 + rng.nextIndex(10)
                    let accuracy = 1 + rng.nextIndex(10)
                    let power = 1 + rng.nextIndex(10)
                    let agility = 1 + rng.nextIndex(10)
                    // Kotlin BotProfile(speed, reaction, accuracy, power, agility): no character, skills default to accuracy.
                    let profile = MPBot(speed: speed, reaction: reaction, accuracy: accuracy, power: power, agility: agility, characterId: "",
                                        forehandSkill: accuracy, backhandSkill: accuracy, serveSkill: accuracy)
                    let b = MPParticipant(identity: MPIdentity(id: houseId, name: "House"), bot: profile)
                    step("generic house player", { try MPRules.addBot($0, actor: $0.host, bot: b) }, { try GMAOriginal.addBot($0, $0.host, b) })
                default:
                    let humans = oldOrder.filter { old.human($0) }
                    let uid = rng.element(humans)
                    step("online", { gmaOnline($0) }, { gmaOnline($0) })
                    step("leave before the start", { try MPRules.leave($0, actor: uid) }, { try GMAOriginal.leaveTournament($0, uid) })
                }
            }
            if aborted { return }
            step("online", { gmaOnline($0) }, { gmaOnline($0) })
            step("start by a guest", { try MPRules.start($0, actor: "outsider") }, { try GMAOriginal.start($0, "outsider") })
            step("start", { try MPRules.start($0, actor: $0.host) }, { try GMAOriginal.start($0, $0.host) })
            if aborted { return }
            var rounds = 0
            while !aborted && !old.complete && rounds < 500 {
                rounds += 1
                let unfinished = old.matches.values.filter { !$0.terminal }.sorted { $0.id < $1.id }
                if unfinished.isEmpty { break }
                let m = rng.element(unfinished)
                switch rng.nextIndex(14) {
                case 0, 1:
                    let uid = rng.element(m.players + ["outsider"])
                    let v = rng.nextIndex(4) > 0
                    step("ready \(uid) \(v)", { try MPRules.ready($0, match: m.id, uid: uid, value: v) }, { try GMAOriginal.ready($0, m.id, uid, v) })
                case 2:
                    step("start ready", { MPRules.startReady($0, match: m.id) }, { GMAOriginal.startReady($0, m.id) })
                case 3, 4:
                    let actor: String
                    if rng.nextIndex(4) > 0 { actor = GMAOriginal.authority(old, m) } else { actor = rng.element(m.players + [old.host, "outsider"]) }
                    let proposal: (Int, Int)
                    if rng.nextIndex(5) > 0 {
                        proposal = gmaClassicFinal(old, &rng)
                    } else {
                        let t = old.target
                        let options: [(Int, Int)] = [(t, t), (t - 1, 0), (t + 1, 0), (t, -1), (t + 3, t), (0, 0)]
                        proposal = rng.element(options)
                    }
                    let (a, b) = rng.nextBoolean() ? proposal : (proposal.1, proposal.0)
                    step("finish \(a):\(b) by \(actor)", { try MPRules.finish($0, match: m.id, actor: actor, a: a, b: b) },
                         { try GMAOriginal.finish($0, m.id, actor, a, b) })
                case 5:
                    let candidates = oldOrder.filter { old.human($0) }
                    if !candidates.isEmpty {
                        let uid = rng.element(candidates)
                        if rng.nextIndex(3) == 0 {
                            step("leave \(uid)", { try MPRules.leave($0, actor: uid) }, { try GMAOriginal.leaveTournament($0, uid) })
                        }
                    }
                case 6:
                    let uid = rng.element(oldOrder.filter { old.participants[$0]?.bot == nil })
                    let flip: (MPSession) -> MPSession = { room in
                        var n = room
                        if room.connected(uid) { n.connections[uid] = nil } else { n.connections[uid] = ["1": true] }
                        return n
                    }
                    step("presence \(uid)", flip, flip)
                case 7:
                    let original = try GMAOriginal.wire(old)
                    let shape = gmaRtdb(original, lists: rng.nextBoolean())
                    now = try gmaDecode(shape)
                    legacyLoads += 1
                    step("stored by the original app", { $0 }, { $0 })
                case 8:
                    let current = try gmaEncode(now)
                    let shape = gmaRtdb(current, lists: rng.nextBoolean())
                    now = try gmaDecode(shape)
                    step("stored by this app", { $0 }, { $0 })
                default:
                    let readyHumans = m.players.filter { old.human($0) }
                    for uid in readyHumans {
                        step("ready all", { try MPRules.ready($0, match: m.id, uid: uid, value: true) }, { try GMAOriginal.ready($0, m.id, uid, true) })
                    }
                    step("online", { gmaOnline($0) }, { gmaOnline($0) })
                    step("start ready", { MPRules.startReady($0, match: m.id) }, { GMAOriginal.startReady($0, m.id) })
                    let decided = gmaClassicFinal(old, &rng)
                    let (a, b) = rng.nextBoolean() ? decided : (decided.1, decided.0)
                    let actor = GMAOriginal.authority(old, m)
                    let finished = old.matches.values.filter({ $0.phase == .finished }).count
                    step("play \(a):\(b)", { try MPRules.finish($0, match: m.id, actor: actor, a: a, b: b) }, { try GMAOriginal.finish($0, m.id, actor, a, b) })
                    let finishedAfter = old.matches.values.filter({ $0.phase == .finished }).count
                    if finishedAfter > finished { results += 1 }
                }
            }
            if aborted { return }
            if old.complete { completed += 1 }
        }
        print("classic: \(completed) completed, \(legacyLoads) original-format loads, \(results) results, \(compared) comparisons")
        XCTAssertTrue(completed > 150, "\(completed) tournaments completed")
        XCTAssertTrue(legacyLoads > 200, "\(legacyLoads)")
        XCTAssertTrue(results > 500, "\(results)")
        XCTAssertTrue(compared > 10000, "\(compared)")
    }

    // Kotlin: classicFriendlyPairsKeepTheOriginalIdSeedAuthorityAndResultWhileFollowingSeats
    func testClassicFriendlyPairsKeepTheOriginalIdSeedAuthorityAndResultWhileFollowingSeats() throws {
        var rng = MPKotlinRandom(intSeed: 5)
        let pairs: [(String, String)] = [("host", "guest"), ("zed", "amy"), ("amy", "zed"), ("m", "m2")]
        for (host, guest) in pairs {
            for difficulty in 0...4 {
                let target = rng.element([3, 5, 7])
                let created = try gmaCreate("ABC234", .friendly, MPIdentity(id: host, name: "H"), 2, 1, 3, 0, difficulty, target)
                var now = try gmaOnline(MPRules.join(created, MPIdentity(id: guest, name: "G")))
                let original = try GMAOriginal.create("ABC234", .friendly, MPIdentity(id: host, name: "H"), 2, 1, 3, 0, difficulty, target, .roundRobin)
                var old = try gmaOnline(GMAOriginal.join(original, MPIdentity(id: guest, name: "G")))
                var unseated = now
                unseated.seats = [:]
                XCTAssertEqual(gmaClassic(old), unseated)
                now = try MPRules.start(now, actor: host)
                old = try GMAOriginal.start(old, host)
                let n = gmaOnly(now)
                let o = gmaOnly(old)
                XCTAssertEqual(o.id, n.id)
                XCTAssertEqual(o.seed, n.seed)
                XCTAssertEqual(n.players, [host, guest])
                XCTAssertEqual(o.players, [host, guest].sorted())
                XCTAssertEqual(GMAOriginal.authority(old, o), now.authority(n))
                for uid in [guest, host] {
                    now = try MPRules.ready(now, match: n.id, uid: uid, value: true)
                    old = try GMAOriginal.ready(old, o.id, uid, true)
                }
                now = MPRules.startReady(now, match: n.id)
                old = GMAOriginal.startReady(old, o.id)
                XCTAssertEqual(gmaOnly(now).phase, .playing)
                XCTAssertEqual(gmaOnly(old).phase, .playing)
                let (w, l) = gmaClassicFinal(now, &rng)
                let winner = rng.element([host, guest])
                let loser = winner == host ? guest : host
                let per: [String: Int] = [winner: w, loser: l]
                let authority = now.authority(n)
                let wrongActor = authority == host ? guest : host
                XCTAssertThrowsError(try MPRules.finish(now, match: n.id, actor: wrongActor, a: per[n.a] ?? -1, b: per[n.b] ?? -1))
                now = try MPRules.finish(now, match: n.id, actor: authority, a: per[n.a] ?? -1, b: per[n.b] ?? -1)
                old = try GMAOriginal.finish(old, o.id, authority, per[o.a] ?? -1, per[o.b] ?? -1)
                XCTAssertEqual(gmaOnly(now).winner, winner)
                XCTAssertEqual(gmaOnly(now).winner, gmaOnly(old).winner)
                for uid in [host, guest] { XCTAssertEqual(gmaOnly(now).scoreOf(uid), per[uid]) }
                XCTAssertEqual(GMAOriginal.standings(old), MPRules.standings(now))
                XCTAssertEqual(old.state, now.state)
                XCTAssertTrue(now.complete)
                XCTAssertEqual(gmaOnly(now).placement, [winner, loser])
                XCTAssertTrue(MPCompletionText.won(now, winner))
                XCTAssertFalse(MPCompletionText.won(now, loser))
            }
        }
    }

    // Kotlin: recordsStoredByTheOriginalClassicCodecLoadExactlyInEveryShapeAndKeepPlaying
    func testRecordsStoredByTheOriginalClassicCodecLoadExactlyInEveryShapeAndKeepPlaying() throws {
        var rng = MPKotlinRandom(intSeed: 99)
        var samples: [MPSession] = []
        var f = try GMAOriginal.create("FRNDLY", .friendly, MPIdentity(id: "zed", name: "Zed"), 2, 1, 3, 0, 2, 5, .roundRobin)
        f.createdAt = 7
        samples.append(f)
        f = try gmaOnline(GMAOriginal.join(f, MPIdentity(id: "amy", name: "Amy")))
        samples.append(f)
        f = try GMAOriginal.start(f, "zed")
        samples.append(f)
        let fid = gmaOnly(f).id
        f = try GMAOriginal.ready(f, fid, "amy", true)
        samples.append(f)
        f = try GMAOriginal.startReady(GMAOriginal.ready(f, fid, "zed", true), fid)
        samples.append(f)
        let playingFriendly = f
        let finishedFriendly = try GMAOriginal.finish(f, fid, "amy", 6, 8)                // MEDIUM deuce 6:8
        samples.append(finishedFriendly)
        for knockout in [false, true] {
            let format: MPTournamentFormat = knockout ? .knockout : .roundRobin
            var t = try GMAOriginal.create("TRNMNT", .tournament, MPIdentity(id: "u1", name: "Host"), knockout ? 5 : 4, 2, 3, 1, 3, 5, format)
            t.createdAt = 3
            samples.append(t)
            t = try GMAOriginal.addBot(GMAOriginal.addBot(GMAOriginal.join(t, MPIdentity(id: "u2", name: "Two")), "u1", gmaBot(0)), "u1", gmaBot(1))
            if knockout { t = try GMAOriginal.join(t, MPIdentity(id: "u3", name: "Three")) }
            t = try GMAOriginal.start(gmaOnline(t), "u1")
            samples.append(t)
            if !knockout {
                t = try GMAOriginal.leaveTournament(t, "u2")
                samples.append(t)
            }
            var steps = 0
            while !t.complete && steps < 30 {
                steps += 1
                guard let m = t.matches.values.filter({ !$0.terminal }).min(by: { $0.id < $1.id }) else { break }
                let humans = m.players.filter { t.human($0) }
                for uid in humans { t = try GMAOriginal.ready(t, m.id, uid, true) }
                samples.append(t)
                t = GMAOriginal.startReady(t, m.id)
                samples.append(t)
                let (w, l) = gmaClassicFinal(t, &rng)
                t = try GMAOriginal.finish(t, m.id, GMAOriginal.authority(t, m), w, l)
                samples.append(t)
            }
            XCTAssertTrue(t.complete)
        }
        for old in samples {
            let wire = try GMAOriginal.wire(old)
            for (_, m) in MPCodec.map(wire["matches"]) { XCTAssertNil(MPCodec.map(m)["players"]) }
            let json = try gmaJson(wire)
            let shapes: [MPWire] = [wire, MPCodec.map(gmaRtdb(wire, lists: true)), MPCodec.map(gmaRtdb(wire, lists: false)), json]
            for shape in shapes {
                let loaded = try gmaDecode(shape)
                // The original records never carried an authorityUid; Swift keeps the wire's on each fixture.
                XCTAssertEqual(old, gmaBare(loaded))
                XCTAssertEqual(loaded.tableSize, 2)
                XCTAssertTrue(loaded.seats.isEmpty)
                for m in loaded.matches.values {
                    XCTAssertEqual(m.players, [m.a, m.b])
                    XCTAssertEqual(m.scores.count, 2)
                    XCTAssertTrue(m.placement.isEmpty)
                }
            }
            let rewritten = try gmaEncode(old)
            for (_, raw) in MPCodec.map(rewritten["matches"]) {
                let m = MPCodec.map(raw)
                XCTAssertNil(m["a"])
                XCTAssertNil(m["scoreA"])
                XCTAssertEqual(m["matchSize"] as? Int, 2)
            }
            XCTAssertEqual(old, try gmaBare(gmaDecode(gmaRtdb(rewritten, lists: true))))
            XCTAssertEqual(old, try gmaBare(gmaDecode(gmaJson(rewritten))))
        }
        // A classic friendly that was mid-match in the original shape is finished by its authority.
        let playingWire = try GMAOriginal.wire(playingFriendly)
        let loadedFriendly = try gmaDecode(gmaRtdb(playingWire, lists: true))
        XCTAssertThrowsError(try MPRules.finish(loadedFriendly, match: fid, actor: "zed", a: 6, b: 8))
        let done = try MPRules.finish(loadedFriendly, match: fid, actor: "amy", a: 6, b: 8)
        XCTAssertEqual(try GMAOriginal.finish(playingFriendly, fid, "amy", 6, 8), gmaClassic(done))
        XCTAssertEqual(gmaOnly(done).placement, ["zed", "amy"])
        XCTAssertTrue(MPCompletionText.won(done, "zed"))
    }

    // ---- Device-local stores ----

    // Kotlin: localRepositoryCreatesMutatesAndObservesAFourSeatFriendly
    @MainActor
    func testLocalRepositoryCreatesMutatesAndObservesAFourSeatFriendly() async throws {
        let defaults = UserDefaults(suiteName: "test-\(UUID())")!
        let repo = MPLocalRepository(defaults: defaults)
        let me = repo.uid
        let code = "ABC234"
        XCTAssertTrue(me.hasPrefix("local_"))
        let sameUid = MPLocalRepository(defaults: defaults).uid
        XCTAssertEqual(sameUid, me)
        func change(_ action: @escaping (MPSession) throws -> MPSession) async -> Result<MPSession, Error> {
            do { return .success(try await repo.mutate(.friendly, code, action)) } catch { return .failure(error) }
        }
        func stored() async throws -> MPSession? { try await repo.get(.friendly, code) }
        let draft = try gmaCreate(code, .friendly, MPIdentity(id: me, name: "Host"), 2, 1, 3, 0, 0, 5, tableSize: 4)
        let created = try await repo.create(draft)
        var unstamped = created
        unstamped.createdAt = 0
        unstamped.lastActivityAt = 0
        XCTAssertEqual(unstamped, draft)
        let firstRead = try await stored()
        XCTAssertEqual(firstRead, created)
        var duplicateRefused = false
        do { _ = try await repo.create(draft) } catch { duplicateRefused = true }
        XCTAssertTrue(duplicateRefused, "a second room with the same code is refused")
        // The lobby starts the table as soon as it is full (like PlayActivity); a second screen only watches. Kotlin starts it
        // re-entrantly inside the save; MPLocalRepository.mutate is async, so the lobby starts it in a task awaited below.
        let lobby = GMABox<[MPSession]>([])
        let court = GMABox<[MPSession]>([])
        let starting = GMABox<Task<Void, Never>?>(nil)
        let first = repo.observe(.friendly, code) { r in
            guard case let .success(s) = r else { XCTFail("lobby observer failed"); return }
            lobby.value.append(s)
            if s.state == "WAITING" && s.participants.count == s.capacity {
                starting.value = Task { @MainActor in
                    _ = try? await repo.mutate(.friendly, code) { try MPRules.start($0, actor: me) }
                }
            }
        }
        let second = repo.observe(.friendly, code) { r in
            guard case let .success(s) = r else { XCTFail("court observer failed"); return }
            court.value.append(s)
        }
        XCTAssertEqual(lobby.value, [created])
        XCTAssertEqual(court.value, [created])
        _ = try await change { try MPRules.join($0, MPIdentity(id: "friend", name: "Friend")) }.get()   // a remote friend through the same store
        _ = try await change { try MPRules.chooseSeat($0, actor: "friend", seat: 2) }.get()
        let heard = court.value.count
        let beforeRefusal = try await stored()
        let refusal = await change { try MPRules.chooseSeat($0, actor: "friend", seat: 0) }
        if case .failure(let error) = refusal { XCTAssertTrue(error is MPError) } else { XCTFail("seat 0 is the host's") }
        XCTAssertEqual(court.value.count, heard, "a refused change is neither stored nor announced")
        let afterRefusal = try await stored()
        XCTAssertEqual(afterRefusal, beforeRefusal)
        _ = try await change { try MPRules.addFriendlyHousePlayer($0, actor: me, bot: gmaBot(0), seat: 3) }.get()
        let full = try await change { try MPRules.addFriendlyHousePlayer($0, actor: me, bot: gmaBot(1)) }.get()
        XCTAssertEqual(full.seating(), [me: 0, "friend": 2, gmaBot(0).id: 3, gmaBot(1).id: 1])
        if let task = starting.value { await task.value }
        guard let active = try await stored() else { XCTFail("the room is missing"); return }
        let id = gmaOnly(active).id
        XCTAssertEqual(active.state, "ACTIVE")
        XCTAssertEqual(gmaOnly(active).players, [me, gmaBot(1).id, "friend", gmaBot(0).id])
        XCTAssertEqual(lobby.value.last, active, "every observer ends on the stored room")
        XCTAssertEqual(court.value.last, active, "every observer ends on the stored room")
        let presence = repo.presence(.friendly, code)
        let present = try await stored()
        XCTAssertEqual(present?.connected(me), true)
        XCTAssertEqual(present?.connected("friend"), false)
        _ = try await change { try MPRules.ready($0, match: id, uid: me, value: true) }.get()
        _ = try await change { try MPRules.ready($0, match: id, uid: "friend", value: true) }.get()
        let beforeStart = try await stored()
        let unchanged = try await change { MPRules.startReady($0, match: id) }.get()
        XCTAssertEqual(beforeStart, unchanged, "the friend is not connected")
        _ = try await change { room in
            var n = room
            n.connections["friend"] = ["phone": true]
            return n
        }.get()
        let playing = try await change { MPRules.startReady($0, match: id) }.get()
        XCTAssertEqual(gmaOnly(playing).phase, .playing)
        XCTAssertEqual(gmaOnly(playing).starts, 1)
        XCTAssertEqual(playing.authority(gmaOnly(playing)), "friend")
        try await repo.checkpoint(id, ["kind": "friendlyRooms", "code": code, "protocol": 2])
        let live = GMABox<MPWire?>(nil)
        repo.watchLive(id, actions: false, { live.value = $0 }, { XCTFail("\($0)") }).close()
        XCTAssertEqual(MPCodec.number(live.value ?? [:], "revision"), 1)
        let scores = [2, 0, 5, 4]
        let placement = ["friend", gmaBot(0).id, me, gmaBot(1).id]
        let wrongActor = await change { try MPRules.finish($0, match: id, actor: me, scores: scores, placement: placement) }
        if case .failure(let error) = wrongActor { XCTAssertTrue(error is MPError) } else { XCTFail("only the authority finishes") }
        let done = try await change { try MPRules.finish($0, match: id, actor: "friend", scores: scores, placement: placement) }.get()
        let afterDone = try await stored()
        XCTAssertTrue(done.complete)
        XCTAssertEqual(afterDone, done)
        XCTAssertEqual(court.value.last, done)
        XCTAssertEqual(afterDone.map { gmaOnly($0).placement }, placement)
        presence.close()
        let afterPresence = try await stored()
        XCTAssertEqual(afterPresence?.connected(me), false)
        XCTAssertEqual(afterPresence.map { gmaOnly($0) }, gmaOnly(done))
        // A restarted process reads the same room without stale presence.
        guard let beforeRestart = try await stored() else { XCTFail("the room is missing"); return }
        XCTAssertTrue(beforeRestart.connected("friend"))
        let restarted = MPLocalRepository(defaults: defaults)
        let reloaded = try await restarted.get(.friendly, code)
        var withoutPresence = beforeRestart
        withoutPresence.connections = [:]
        XCTAssertEqual(reloaded, withoutPresence)
        first.close()
        second.close()
        let quiet = court.value.count
        if let room = reloaded { try await restarted.leave(room, delete: true) } else { XCTFail("the restarted repository lost the room") }   // Kotlin closeFriendly
        let afterClose = try await stored()
        XCTAssertNil(afterClose)
        XCTAssertEqual(court.value.count, quiet)
        let after = GMABox<MPWire?>(nil)
        repo.watchLive(id, actions: false, { after.value = $0 }, { XCTFail("\($0)") }).close()
        XCTAssertEqual(after.value?.isEmpty, true)
    }

    // Kotlin: roomBookAndCompletionTextHandleAFourSeatFriendlyResult
    // Kotlin RoomBook keys rooms by SavedRoom(online, kind, code); iOS MPPreferences keys them by the session id (kind path + code),
    // so `book.cached(saved)` is the stored room with that id and `book.collect` is `remember`.
    func testRoomBookAndCompletionTextHandleAFourSeatFriendlyResult() throws {
        let book = MPPreferences(UserDefaults(suiteName: "test-\(UUID())")!)
        var s = try MPRules.start(gmaTable(4, ["b", "c"], bots: 1), actor: "host")
        let id = gmaOnly(s).id
        // Not ported: RoomBook.title(saved, false) == "Friendly game (ABC234)" — the iOS title is ModernPongView.roomTitle, a view method.
        book.remember(s)
        XCTAssertEqual(book.rooms.map { $0.id }, [s.id])
        XCTAssertEqual(book.rooms.first(where: { $0.id == s.id }), s)
        XCTAssertFalse(book.completionKnown(s))
        for uid in ["host", "b", "c"] { s = try MPRules.ready(s, match: id, uid: uid, value: true) }
        s = MPRules.startReady(s, match: id)
        book.remember(s)                                                    // Kotlin book.collect(saved, s, "b", 0)
        XCTAssertEqual(book.rooms.first(where: { $0.id == s.id }), s)
        for uid in s.participants.keys { XCTAssertFalse(MPCompletionText.won(s, uid)) }
        let players = gmaOnly(s).players
        XCTAssertEqual(players, ["host", "b", "c", gmaBot(0).id])
        let done = try MPRules.finish(s, match: id, actor: "b", scores: [1, 5, 3, 3], placement: ["b", gmaBot(0).id, "c", "host"])   // a tie in either order
        XCTAssertTrue(MPCompletionText.won(done, "b"))
        for uid in ["host", "c", gmaBot(0).id, "outsider"] { XCTAssertFalse(MPCompletionText.won(done, uid)) }
        XCTAssertEqual(MPCompletionText.headline(done, "b", hebrew: false), "You won the match!")
        XCTAssertEqual(MPCompletionText.headline(done, "b", hebrew: true), "ניצחתם במשחק!")
        XCTAssertTrue(MPCompletionText.headline(done, "c", hebrew: false).hasSuffix(" won this match!"))
        XCTAssertTrue(MPCompletionText.headline(done, "host", hebrew: true).hasPrefix("כל הכבוד ל־"))
        // A completed friendly is never kept as an open entry, and a stale cached copy cannot revive it.
        book.remember(done)
        XCTAssertTrue(book.completionKnown(done))
        XCTAssertTrue(book.rooms.isEmpty)
        XCTAssertNil(book.rooms.first(where: { $0.id == s.id }))
        // Kotlin book.add(saved) has no separate iOS call (remember lists an open room); then book.collect(saved, s, "b", 0).
        book.remember(s)
        XCTAssertTrue(book.rooms.isEmpty)
        XCTAssertTrue(book.firstCelebration(done))
        XCTAssertFalse(book.firstCelebration(done))
        var other = s                                                       // Kotlin SavedRoom(false, FRIENDLY, "XYZ234")
        other.code = "XYZ234"
        book.remember(other)
        book.dismissResult(other)
        XCTAssertTrue(book.rooms.isEmpty)
        XCTAssertTrue(book.completionKnown(other))
    }
}
