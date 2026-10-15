import XCTest
@testable import MinikMultiPingPong

// Android app/src/test/.../GameModeTournamentTest.kt (MinikCrossPong 828c6fc). The user's game types and knockout rules:
// WINNER_TAKES_ALL / ELIMINATION tables (an ELIMINATION table plays until two are left; when it must produce one winner they
// play a classic final duel), 1 or 2 through per knockout table, table splits without byes, walkover tables, one-point
// tie-breaks for a tied runner-up place, house-only simulations under each mode, mode-aware result validation, friendlies,
// repeated house characters, the wire (including records saved before these rules) and the texts.
//
// Port notes:
// - Kotlin PongRules/Knockout/GroupTournament/TableSimulation/CompletionText/MatchText/PongCodec are iOS MPRules/MPKnockout/
//   MPGroupTournament/MPTableSimulation/MPCompletionText/MPMatchText/MPCodec. Kotlin `require` failures are Swift throws.
// - Kotlin `PongRules.create` is `createRoom` (the MPSession init with Kotlin's createdAt = lastActivityAt = 0); a direct Kotlin
//   `Session(...)` is `rawRoom` plus field writes. Kotlin `fillWithBots(s, actor, ::house)` is `fillHouse`: iOS fillWithBots
//   takes no `make` closure and mints random "bot_<uuid>" ids, so the Kotlin "bot_<character>_<copy>" ids are added through
//   MPRules.addBot exactly as Kotlin's loop does (the iOS fillWithBots itself is tested in the repeated-characters test).
// - MPFixture carries a Swift-only cached `authorityUid` (Kotlin MatchRecord has none; both codecs write s.authority(m) for it),
//   which MPRules.schedule leaves nil while draws, starts and duels set it. Session comparisons across the wire therefore use
//   `plainSession`, which clears that one field.
// - Kotlin `firebase(wire, lists)` and `JsonWire` are `firebaseShape` and JSONSerialization round trips of the MPCodec wire.
final class GameModeTournamentTests: XCTestCase {
    private struct PortError: Error { let message: String }
    private final class StepLog { var steps: [MPTableSimulation.Step] = [] }

    private var roster: [MPHousePlayer] { MPRoster.all }

    // ---- Rooms ----

    /// Kotlin `PongRules.create(code, kind, host, capacity, legs, win, loss, difficulty, target, format, tableSize, gameMode, advance)`.
    private func createRoom(_ code: String, _ kind: MPSessionKind, _ host: MPIdentity, _ capacity: Int, _ legs: Int, _ win: Int,
                            _ loss: Int, _ difficulty: Int, _ target: Int, format: MPTournamentFormat = .roundRobin,
                            tableSize: Int = 2, gameMode: MPGameMode = .winnerTakesAll, advance: Int = 2) -> MPSession {
        var s = MPSession(code: code, kind: kind, host: host, capacity: capacity, legs: legs, winPoints: win, difficulty: difficulty,
                          target: target, format: format, tableSize: tableSize, gameMode: gameMode, advance: advance)
        s.lossPoints = min(10, max(0, loss))
        s.createdAt = 0
        s.lastActivityAt = 0
        return s
    }

    /// Kotlin `Session(code, kind, host)` with every other field at its Kotlin default.
    private func rawRoom(_ code: String, _ kind: MPSessionKind, _ host: String) -> MPSession {
        var s = MPSession(code: code, kind: kind, host: MPIdentity(id: host, name: host))
        s.capacity = 2
        s.legs = 1
        s.winPoints = 3
        s.lossPoints = 0
        s.difficulty = 0
        s.target = 7
        s.participants = [:]
        s.matches = [:]
        s.connections = [:]
        s.departed = [:]
        s.state = "WAITING"
        s.createdAt = 0
        s.lastActivityAt = 0
        s.format = .roundRobin
        s.rounds = [:]
        s.tableSize = 2
        s.seats = [:]
        s.gameMode = .winnerTakesAll
        s.advance = 2
        return s
    }

    /// Kotlin `house(c, copy)`.
    private func houseParticipant(_ c: MPHousePlayer, _ copy: Int) -> MPParticipant {
        MPParticipant(identity: MPIdentity(id: "bot_\(c.id)_\(copy)", name: c.english), bot: c.profile)
    }

    /// Kotlin `PongRules.fillWithBots(s, actor, ::house)`: the character with the fewest house copies (roster order on ties),
    /// numbered by `copyNumber`, added through MPRules.addBot until the room is full.
    private func fillHouse(_ s: MPSession, _ actor: String) throws -> MPSession {
        guard s.kind == .tournament, s.state == "WAITING", actor == s.host else { throw MPError.permission }
        var next = s
        while next.participants.count < next.capacity {
            let counts = roster.map { c in next.participants.values.filter { $0.bot?.characterId == c.id }.count }
            guard let fewest = counts.min(), let index = counts.firstIndex(of: fewest) else { break }
            let character = roster[index]
            let copy = MPRules.copyNumber(next, character.id)
            next = try MPRules.addBot(next, actor: actor, bot: houseParticipant(character, copy))
        }
        return next
    }

    /// Kotlin `online(s)`: every present human connected.
    private func onlineSession(_ s: MPSession) -> MPSession {
        var next = s
        var connections: [String: [String: Bool]] = [:]
        for (id, p) in s.participants where p.bot == nil && s.departed[id] != true { connections[id] = ["0": true] }
        next.connections = connections
        return next
    }

    /// A knockout hosted by "h0": `humans` humans "h0"..., house players for every other place, every human online.
    private func knockoutRoom(_ players: Int, _ size: Int, _ mode: MPGameMode, _ advance: Int, humans: Int = 1, createdAt: Int64 = 7,
                              difficulty: Int = 0, target: Int = 5, file: StaticString = #filePath, line: UInt = #line) throws -> MPSession {
        var s = createRoom("ELM234", .tournament, MPIdentity(id: "h0", name: "Host"), players, 1, 3, 0, difficulty, target,
                           format: .knockout, tableSize: size, gameMode: mode, advance: advance)
        s.createdAt = createdAt
        if humans > 1 {
            for i in 1..<humans { s = try MPRules.join(s, MPIdentity(id: "h\(i)", name: "Player \(i)")) }
        }
        s = try fillHouse(s, "h0")
        XCTAssertEqual(players, s.participants.count, file: file, line: line)
        return onlineSession(s)
    }

    private func openFixtures(_ s: MPSession) -> [MPFixture] {
        s.matches.values.filter { !$0.terminal }.sorted { $0.id < $1.id }
    }

    /// Every human of the fixture chooses Ready, it starts once, and its authority finishes it.
    private func playFixture(_ s: MPSession, _ id: String, _ scores: [Int], _ placement: [String],
                             file: StaticString = #filePath, line: UInt = #line) throws -> MPSession {
        let m = try XCTUnwrap(s.matches[id], "no fixture \(id)", file: file, line: line)
        var next = s
        for uid in m.players where s.human(uid) { next = try MPRules.ready(next, match: id, uid: uid, value: true) }
        next = MPRules.startReady(next, match: id)
        XCTAssertEqual(next.matches[id]?.phase, MPMatchPhase.playing, file: file, line: line)
        return try MPRules.finish(next, match: id, actor: next.authority(m), scores: scores, placement: placement)
    }

    private func playFixture(_ s: MPSession, _ id: String, _ result: (scores: [Int], placement: [String]),
                             file: StaticString = #filePath, line: UInt = #line) throws -> MPSession {
        try playFixture(s, id, result.scores, result.placement, file: file, line: line)
    }

    /// Ready and started, not finished: (session, authority).
    private func startFixture(_ s: MPSession, _ id: String, file: StaticString = #filePath, line: UInt = #line) throws -> (session: MPSession, authority: String) {
        let m = try XCTUnwrap(s.matches[id], "no fixture \(id)", file: file, line: line)
        var next = s
        for uid in m.players where s.human(uid) { next = try MPRules.ready(next, match: id, uid: uid, value: true) }
        next = MPRules.startReady(next, match: id)
        XCTAssertEqual(next.matches[id]?.phase, MPMatchPhase.playing, file: file, line: line)
        return (next, next.authority(m))
    }

    /// A valid result for `m` under `s`'s rules as (seat-ordered scores, placement); `tie` ties second and third place of a
    /// winner-takes-all table. Elimination: random elimination order down to two survivors. Pairs: classic.
    private func fixtureResult(_ s: MPSession, _ m: MPFixture, _ rng: inout MPKotlinRandom, tie: Bool = false) -> (scores: [Int], placement: [String]) {
        let target = MPRules.fixtureTarget(s, m)
        let order = rng.shuffled(m.players)
        var score: [String: Int] = [:]
        if MPRules.eliminates(s, m) {
            for uid in order.dropFirst(2) { score[uid] = rng.nextIndex(target) }      // the score they went out with
            for uid in order.prefix(2) { score[uid] = rng.nextIndex(target + 1) }     // the survivors: the last stage's scores
            let first = order[0], second = order[1]
            let top: [String] = (score[second] ?? 0) > (score[first] ?? 0) ? [second, first] : [first, second]
            return (m.players.map { score[$0] ?? 0 }, top + Array(order.dropFirst(2)))
        }
        score[order[0]] = target
        var v = target - 1
        for (i, uid) in order.dropFirst().enumerated() {
            if i == 0 { v = rng.nextIndex(target) } else if !(tie && i == 1) { v = rng.nextIndex(v + 1) }
            score[uid] = v
        }
        return (m.players.map { score[$0] ?? 0 }, order)
    }

    private func modeIndex(_ mode: MPGameMode) -> Int { mode == .elimination ? 1 : 0 }

    private func item<T>(_ list: [T], _ index: Int, file: StaticString = #filePath, line: UInt = #line) throws -> T {
        guard index >= 0 && index < list.count else {
            XCTFail("no element \(index) among \(list.count)", file: file, line: line)
            throw PortError(message: "index \(index)")
        }
        return list[index]
    }

    /// Kotlin `single()`.
    private func onlyOne<T>(_ list: [T], _ ctx: String = "", file: StaticString = #filePath, line: UInt = #line) throws -> T {
        guard list.count == 1, let first = list.first else {
            XCTFail("expected one element, found \(list.count) \(ctx)", file: file, line: line)
            throw PortError(message: "count \(list.count)")
        }
        return first
    }

    // ---- Wire ----

    private func encodeSession(_ s: MPSession) throws -> MPWire { try MPCodec.session(s) }

    private func decodeSession(_ value: Any?) throws -> MPSession { try MPCodec.session(value) }

    /// Clears the Swift-only cached `authorityUid` (see the port notes).
    private func plainMatches(_ matches: [String: MPFixture]) -> [String: MPFixture] {
        var out: [String: MPFixture] = [:]
        for (id, m) in matches {
            var copy = m
            copy.authorityUid = nil
            out[id] = copy
        }
        return out
    }

    private func plainSession(_ s: MPSession) -> MPSession {
        var copy = s
        copy.matches = plainMatches(s.matches)
        return copy
    }

    /// Kotlin `firebase(v, lists)`: what Firebase hands back: no empty containers, dense integer keys as a list or an index-keyed map.
    private func firebaseShape(_ value: Any?, lists: Bool) -> Any? {
        if let map = value as? [String: Any] {
            var out: [String: Any] = [:]
            for (key, item) in map {
                if let kept = firebaseShape(item, lists: lists) { out[key] = kept }
            }
            return out.isEmpty ? nil : out
        }
        if let list = value as? [Any] {
            if list.isEmpty { return nil }
            let items: [Any] = list.map { firebaseShape($0, lists: lists) ?? NSNull() }
            if lists { return items }
            var keyed: [String: Any] = [:]
            for (index, item) in items.enumerated() where !(item is NSNull) { keyed[String(index)] = item }
            return keyed
        }
        if value is NSNull { return nil }
        return value
    }

    /// Kotlin `JsonWire.decode(JsonWire.encode(wire))`.
    private func jsonRoundTrip(_ wire: MPWire) throws -> Any {
        let data = try JSONSerialization.data(withJSONObject: wire)
        return try JSONSerialization.jsonObject(with: data)
    }

    /// Kotlin `shapes(wire)`.
    private func wireShapes(_ wire: MPWire) throws -> [Any?] {
        let json = try jsonRoundTrip(wire)
        let shapes: [Any?] = [wire, firebaseShape(wire, lists: true), firebaseShape(wire, lists: false), json]
        return shapes
    }

    /// Kotlin `for(shape in shapes(PongCodec.session(s))) assertEquals(s, PongCodec.session(shape))`.
    private func assertShapesRoundTrip(_ s: MPSession, _ ctx: String = "", file: StaticString = #filePath, line: UInt = #line) throws {
        let wire = try encodeSession(s)
        for shape in try wireShapes(wire) {
            let decoded = try decodeSession(shape)
            XCTAssertEqual(plainSession(s), plainSession(decoded), ctx, file: file, line: line)
        }
    }

    // ---- Knockout checks ----

    private func progression(_ n: Int, _ size: Int, _ advance: Int) -> [Int] {
        var sizes = [n]
        var current = n
        while current > 4 {
            current = MPGroupTournament.advancing(current, size, advance: advance)
            sizes.append(current)
        }
        return sizes
    }

    private func roundCounts(_ s: MPSession) -> [Int] {
        (0...MPKnockout.current(s)).map { s.rounds[$0]?.players.count ?? -1 }
    }

    /// Checks a finished knockout round by round against the user's rules; returns (tie-breaks, walkover tables, final duels).
    @discardableResult
    private func verifyKnockout(_ s: MPSession, _ ctx: String) throws -> (tiebreaks: Int, walkovers: Int, duels: Int) {
        let size = s.tableSize
        let advance = s.advance
        let last = MPKnockout.current(s)
        var fixtures = 0, tiebreaks = 0, walkovers = 0, duels = 0
        XCTAssertEqual("FINISHED", s.state, ctx)
        XCTAssertTrue(s.complete, ctx)
        for r in 0...last {
            let round = try XCTUnwrap(s.rounds[r], ctx)
            let n = round.players.count
            let isFinalRound = n <= 4
            XCTAssertEqual(n, Set(round.players).count, ctx)
            XCTAssertTrue(round.byes.isEmpty, ctx)
            XCTAssertEqual(round.groups.flatMap { $0 } + round.walkovers.flatMap { $0 }, round.players, ctx)
            XCTAssertEqual(MPGroupTournament.split(n, size), (round.groups + round.walkovers).map { $0.count }, ctx)
            XCTAssertTrue(round.walkovers.allSatisfy { !isFinalRound && $0.count <= advance }, ctx)
            XCTAssertTrue(round.groups.allSatisfy { isFinalRound || $0.count > advance }, ctx)
            XCTAssertEqual(isFinalRound, round.isFinal, ctx)
            XCTAssertEqual(r == last, isFinalRound, ctx)
            let games = MPKnockout.matches(s, r)
            let goal: MPMatchGoal = !isFinalRound && s.gameMode == .elimination && advance == 2 ? .topTwo : .win
            XCTAssertEqual(round.groups, games.map { $0.players }, ctx)
            for g in games {
                XCTAssertEqual(goal, g.goal, ctx)
                XCTAssertEqual(MPMatchPhase.finished, g.phase, ctx)
                XCTAssertEqual(g.placement.first, g.winner, ctx)
                XCTAssertTrue(MPRules.validFinal(s, g, g.scores) && MPRules.validPlacement(s, g, g.scores, g.placement), ctx)
            }
            var through: [String] = []
            for (i, g) in games.enumerated() { through += try throughTable(s, r, i, g, isFinalRound, ctx) }
            through += round.walkovers.flatMap { $0 }
            let breaks = MPKnockout.tiebreaks(s, r)
            let pairs = MPKnockout.duels(s, r)
            tiebreaks += breaks.count
            walkovers += round.walkovers.count
            duels += pairs.count
            fixtures += games.count + breaks.count + pairs.count
            XCTAssertEqual(games.compactMap { s.matches[MPRules.duelId($0.id)] }, pairs, ctx)
            XCTAssertTrue(pairs.allSatisfy { MPRules.isDuel($0) && $0.players.count == 2 }, ctx)
            if isFinalRound {
                let champions: [String?] = [MPKnockout.winner(s)]
                XCTAssertEqual(champions, through.map { Optional($0) }, ctx)
                let table = try onlyOne(games, ctx)
                let ranking = try XCTUnwrap(MPRules.ranking(s, table), ctx)              // places 1...n at the final table
                for (i, uid) in ranking.enumerated() { XCTAssertEqual(i + 1, MPCompletionText.place(s, uid), ctx) }
                XCTAssertEqual(through.first, ranking.first, ctx)
            } else {
                var expected = 0
                for g in games { expected += min(g.players.count, advance) }
                for w in round.walkovers { expected += w.count }
                XCTAssertEqual(expected, through.count, ctx)
                let nextRound = try XCTUnwrap(s.rounds[r + 1], ctx)
                XCTAssertEqual(Set(through), Set(nextRound.players), ctx)
            }
        }
        XCTAssertEqual(fixtures, s.matches.count, ctx)
        let champion = try XCTUnwrap(MPKnockout.winner(s), ctx)
        XCTAssertEqual(1, MPCompletionText.place(s, champion), ctx)
        XCTAssertTrue(MPCompletionText.won(s, champion), ctx)
        for uid in s.participants.keys where uid != champion { XCTAssertFalse(MPCompletionText.won(s, uid), ctx) }
        return (tiebreaks, walkovers, duels)
    }

    /// Who the user's rules send through from finished table `m` (index `table`) of `round`, checked independently.
    private func throughTable(_ s: MPSession, _ round: Int, _ table: Int, _ m: MPFixture, _ isFinalRound: Bool, _ ctx: String) throws -> [String] {
        let tiebreak = s.matches[MPKnockout.tiebreakId(s.code, round, table)]
        let duel = s.matches[MPRules.duelId(m.id)]
        let runnerUp = !isFinalRound && s.gameMode == .winnerTakesAll && s.advance == 2
        if !runnerUp { XCTAssertNil(tiebreak, ctx) }
        // An ELIMINATION table that must produce one winner: its two survivors played a classic final duel.
        XCTAssertEqual(s.gameMode == .elimination && m.goal == .win && m.players.count > 2, duel != nil, ctx)
        if let duel {
            XCTAssertEqual(Array(m.placement.prefix(2)), duel.players, ctx)
            XCTAssertEqual(MPMatchGoal.win, duel.goal, ctx)
            XCTAssertEqual(MPMatchPhase.finished, duel.phase, ctx)
            XCTAssertTrue(MPRules.validFinal(s, duel, duel.scores), ctx)
            XCTAssertEqual(s.target, duel.scoreOf(duel.winner), ctx)
            XCTAssertEqual(duel.winner, duel.placement.first, ctx)
            XCTAssertEqual(duel.winner, MPRules.finalWinner(s, m), ctx)
            let expectedRanking: [String] = [duel.winner] + duel.players.filter { $0 != duel.winner } + Array(m.placement.dropFirst(2))
            XCTAssertEqual(expectedRanking, MPRules.ranking(s, m), ctx)
            return [duel.winner]
        }
        if isFinalRound || (!runnerUp && m.goal == .win) { return Array(m.placement.prefix(1)) }
        if m.goal == .topTwo { return Array(m.placement.prefix(2)) }
        let rest = m.players.filter { $0 != m.winner }
        let best = rest.map { m.scoreOf($0) }.max() ?? 0
        let tied = rest.filter { m.scoreOf($0) == best }
        if tied.count == 1 {
            XCTAssertNil(tiebreak, ctx)
            return [m.winner, tied[0]]
        }
        let tb = try XCTUnwrap(tiebreak, ctx)
        XCTAssertEqual(tied, tb.players, ctx)
        XCTAssertEqual(MPMatchGoal.tiebreak, tb.goal, ctx)
        XCTAssertEqual(MPMatchPhase.finished, tb.phase, ctx)
        XCTAssertEqual(1, MPRules.fixtureTarget(s, tb), ctx)
        XCTAssertTrue(MPRules.validFinal(s, tb, tb.scores), ctx)
        XCTAssertTrue(tied.contains(tb.winner), ctx)
        return [m.winner, tb.winner]
    }

    // ---- Table splits and round sizes ----

    // Kotlin: tablesSplitWithoutByesPreferringTheChosenSize
    func testTablesSplitWithoutByesPreferringTheChosenSize() {
        let four: [Int: [Int]] = [
            5: [3, 2], 6: [3, 3], 7: [4, 3], 8: [4, 4], 9: [3, 3, 3], 10: [4, 3, 3], 11: [4, 4, 3],
            12: [4, 4, 4], 13: [4, 3, 3, 3], 14: [4, 4, 3, 3], 15: [4, 4, 4, 3], 16: [4, 4, 4, 4], 17: [4, 4, 3, 3, 3],
            18: [4, 4, 4, 3, 3], 19: [4, 4, 4, 4, 3], 20: [4, 4, 4, 4, 4], 21: [4, 4, 4, 3, 3, 3]]
        for (n, tables) in four { XCTAssertEqual(tables, MPGroupTournament.split(n, 4), "\(n) at tables of 4") }
        var three: [Int: [Int]] = [
            5: [3, 2], 6: [3, 3], 7: [4, 3], 8: [4, 4], 9: [3, 3, 3], 10: [4, 3, 3], 11: [4, 4, 3],
            12: [3, 3, 3, 3], 13: [4, 3, 3, 3], 14: [4, 4, 3, 3], 16: [4, 3, 3, 3, 3]]
        three[15] = Array(repeating: 3, count: 5)
        three[21] = Array(repeating: 3, count: 7)
        three[32] = [4, 4] + Array(repeating: 3, count: 8)
        for (n, tables) in three { XCTAssertEqual(tables, MPGroupTournament.split(n, 3), "\(n) at tables of 3") }
        for size in 3...4 {
            XCTAssertEqual([Int](), MPGroupTournament.split(0, size))
            XCTAssertEqual([Int](), MPGroupTournament.split(1, size))
            for n in 2...4 { XCTAssertEqual([n], MPGroupTournament.split(n, size)) }              // one final table; two play a pair
            for n in 6...MPKnockout.maxPlayers {
                let t = MPGroupTournament.split(n, size)
                XCTAssertEqual(n, t.reduce(0, +), "\(n)")
                XCTAssertTrue(t.allSatisfy { $0 == 3 || $0 == 4 }, "\(n)")
                XCTAssertEqual(t.sorted(by: >), t, "\(n)")
                let options = (0...(n / 4)).filter { (n - 4 * $0) % 3 == 0 }
                let best = options.map { fours in size == 4 ? fours : (n - 4 * fours) / 3 }.max() ?? -1
                XCTAssertEqual(best, t.filter { $0 == size }.count, "\(n): as many tables of \(size) as possible")
            }
        }
    }

    // Kotlin: roundSizesFollowTheSplitAndTheNumberGoingThrough
    func testRoundSizesFollowTheSplitAndTheNumberGoingThrough() throws {
        let expected: [(n: Int, size: Int, advance: Int, sizes: [Int])] = [
            (32, 4, 2, [32, 16, 8, 4]), (32, 3, 2, [32, 20, 12, 8, 4]), (32, 4, 1, [32, 8, 2]),
            (32, 3, 1, [32, 10, 3]), (5, 4, 2, [5, 4]), (5, 3, 1, [5, 2]), (9, 3, 2, [9, 6, 4]),
            (9, 4, 1, [9, 3]), (21, 4, 2, [21, 12, 6, 4]), (21, 4, 1, [21, 6, 2]), (3, 4, 2, [3]), (4, 3, 1, [4])]
        for key in expected {
            for mode in MPGameMode.allCases {
                let seed: Int64 = Int64(key.n) * 7 + Int64(key.advance)
                var rng = MPKotlinRandom(seed: seed)
                let ctx = "(\(key.n), \(key.size), \(key.advance)) \(mode.rawValue)"
                XCTAssertEqual(key.sizes, progression(key.n, key.size, key.advance), ctx)
                let room = try knockoutRoom(key.n, key.size, mode, key.advance, createdAt: Int64(key.n))
                var s = try MPRules.start(room, actor: "h0")
                var guardCount = 0
                while !s.complete {
                    guardCount += 1
                    guard guardCount < 500, let m = openFixtures(s).first else { XCTFail("no open fixture: \(ctx)"); break }
                    s = try playFixture(s, m.id, fixtureResult(s, m, &rng))
                }
                XCTAssertEqual(key.sizes, roundCounts(s), ctx)
                try verifyKnockout(s, ctx)
            }
        }
        XCTAssertEqual(1, MPGroupTournament.advancing(4, 4, advance: 2))
        XCTAssertEqual(1, MPGroupTournament.advancing(2, 3, advance: 1))
        XCTAssertEqual(0, MPGroupTournament.advancing(0, 3))
    }

    // ---- Knockouts to the champion ----

    // Kotlin: knockoutsOfEverySizeModeAndAdvanceRunToOneChampionDurably
    func testKnockoutsOfEverySizeModeAndAdvanceRunToOneChampionDurably() throws {
        var tiebreaks = 0, walkovers = 0, duels = 0, played = 0, playedDuels = 0
        for n in 3...MPKnockout.maxPlayers {
            for size in 3...4 {
                for mode in MPGameMode.allCases {
                    for advance in 1...2 {
                        let nPart: Int64 = Int64(n) * 1000
                        let sizePart: Int64 = Int64(size) * 100
                        let modePart: Int64 = Int64(modeIndex(mode)) * 10
                        let seed: Int64 = nPart + sizePart + modePart + Int64(advance)
                        var rng = MPKotlinRandom(seed: seed)
                        let ctx = "\(n) players, tables of \(size), \(mode.rawValue), advance \(advance)"
                        let humans = min(n, 1 + (n + advance) % 4)
                        let base = try knockoutRoom(n, size, mode, advance, humans: humans, createdAt: seed)
                        var s = try MPRules.start(base, actor: "h0")
                        XCTAssertEqual(s, try MPRules.start(base, actor: "h0"), ctx)
                        XCTAssertEqual(s, try MPRules.start(s, actor: "h0"), ctx)
                        XCTAssertEqual(s, try MPKnockout.settle(s), ctx)
                        var guardCount = 0
                        while !s.complete {
                            guardCount += 1
                            guard guardCount < 500, let m = openFixtures(s).first else { XCTFail("no open fixture: \(ctx)"); break }
                            let tie = rng.nextIndex(3) == 0
                            let r = fixtureResult(s, m, &rng, tie: tie)
                            let wire = try encodeSession(s)
                            for shape in try wireShapes(wire) {
                                let decodedShape = try decodeSession(shape)
                                XCTAssertEqual(plainSession(s), plainSession(decodedShape), ctx)
                            }
                            let lists = rng.nextBoolean()
                            let decoded = try decodeSession(firebaseShape(wire, lists: lists))
                            let next = try playFixture(s, m.id, r)
                            let replayed = try playFixture(decoded, m.id, r)
                            XCTAssertEqual(plainSession(next), plainSession(replayed), ctx)
                            XCTAssertEqual(next, try MPKnockout.settle(next), ctx)
                            for (round, drawn) in s.rounds { XCTAssertEqual(drawn, next.rounds[round], ctx) }      // a stored draw never changes
                            let again = try MPRules.finish(next, match: m.id, actor: next.authority(m), scores: r.scores, placement: r.placement)
                            XCTAssertEqual(next, again, ctx)                                                         // a result is written once
                            // A finished elimination table that must produce one winner carries its duel from this same transition.
                            if let table = next.matches[m.id], MPRules.needsDuel(next, table) { XCTAssertNotNil(MPRules.duelOf(next, table), ctx) }
                            s = next
                            played += 1
                            if MPRules.isDuel(m) { playedDuels += 1 }
                        }
                        XCTAssertEqual(progression(n, size, advance), roundCounts(s), ctx)
                        let counted = try verifyKnockout(s, ctx)
                        tiebreaks += counted.tiebreaks
                        walkovers += counted.walkovers
                        duels += counted.duels
                        let json = try jsonRoundTrip(try encodeSession(s))
                        let fromJson = try decodeSession(json)
                        XCTAssertEqual(plainSession(s), plainSession(fromJson), ctx)
                    }
                }
            }
        }
        print("knockouts: \(played) results by people (\(playedDuels) final duels), \(tiebreaks) tie-breaks, \(walkovers) walkover tables, \(duels) final duels")
        XCTAssertTrue(tiebreaks > 50, "\(tiebreaks) tie-breaks")
        XCTAssertEqual(4, walkovers, "five players, two through")
        XCTAssertTrue(played > 300, "\(played)")
        XCTAssertTrue(duels > 300, "\(duels) duels")
        XCTAssertTrue(playedDuels > 30, "\(playedDuels) duels played by people")
    }

    // Kotlin: allHumanKnockoutsPlayEveryTableTieBreakAndDuelToTheChampion
    func testAllHumanKnockoutsPlayEveryTableTieBreakAndDuelToTheChampion() throws {
        var tiebreaks = 0, duels = 0
        for n in [3, 4, 5, 6, 7, 8, 9, 11, 13, 16, 21, 32] {
            for size in 3...4 {
                for mode in MPGameMode.allCases {
                    for advance in 1...2 {
                        let nPart: Int64 = Int64(n) * 97
                        let sizePart: Int64 = Int64(size) * 13
                        let modePart: Int64 = Int64(modeIndex(mode)) * 5
                        let seed: Int64 = nPart + sizePart + modePart + Int64(advance)
                        var rng = MPKotlinRandom(seed: seed)
                        let ctx = "\(n) people, tables of \(size), \(mode.rawValue), advance \(advance)"
                        let room = try knockoutRoom(n, size, mode, advance, humans: n, createdAt: seed)
                        var s = try MPRules.start(room, actor: "h0")
                        var guardCount = 0
                        while !s.complete {
                            guardCount += 1
                            guard guardCount < 500, let m = openFixtures(s).first else { XCTFail("no open fixture: \(ctx)"); break }
                            let tie = rng.nextBoolean()
                            s = try playFixture(s, m.id, fixtureResult(s, m, &rng, tie: tie))
                        }
                        XCTAssertEqual(progression(n, size, advance), roundCounts(s), ctx)
                        let counted = try verifyKnockout(s, ctx)
                        tiebreaks += counted.tiebreaks
                        duels += counted.duels
                        XCTAssertTrue(s.matches.values.allSatisfy { $0.starts == 1 }, ctx)                 // people played every fixture
                    }
                }
            }
        }
        XCTAssertTrue(tiebreaks > 40, "\(tiebreaks) tie-breaks")
        XCTAssertTrue(duels > 40, "\(duels) duels")
    }

    // ---- Tie-breaks (winner takes all, two through) ----

    // Kotlin: aTieForSecondPlaysAOnePointTieBreakAmongExactlyTheTiedPlayers
    func testATieForSecondPlaysAOnePointTieBreakAmongExactlyTheTiedPlayers() throws {
        let room = try knockoutRoom(8, 4, .winnerTakesAll, 2, humans: 8, createdAt: 3)
        var s = try MPRules.start(room, actor: "h0")
        let firstRound = MPKnockout.matches(s, 0)
        let a = try item(firstRound, 0)
        let b = try item(firstRound, 1)
        let w = try item(a.players, 0), x = try item(a.players, 1), y = try item(a.players, 2), z = try item(a.players, 3)
        s = try playFixture(s, a.id, [5, 3, 3, 1], [w, x, y, z])
        let key = MPKnockout.tiebreakId(s.code, 0, 0)
        let tb = try XCTUnwrap(s.matches[key])
        XCTAssertEqual([x, y], tb.players)
        XCTAssertEqual(MPMatchGoal.tiebreak, tb.goal)
        XCTAssertEqual(MPMatchPhase.waiting, tb.phase)
        XCTAssertEqual([0, 0], tb.scores)
        let aTable = try XCTUnwrap(s.matches[a.id])
        XCTAssertEqual(1, MPRules.fixtureTarget(s, tb))
        XCTAssertEqual(5, MPRules.fixtureTarget(s, aTable))
        XCTAssertEqual([tb], MPKnockout.tiebreaks(s, 0))
        XCTAssertEqual([a.id, b.id, key], MPKnockout.fixtures(s, 0).map { $0.id })
        XCTAssertEqual([a.id, b.id], MPKnockout.matches(s, 0).map { $0.id })
        let table = aTable
        for uid in [x, y] {
            XCTAssertEqual("Tie-break for the last place: the first point decides who advances.", MPKnockout.playerStatus(s, uid, hebrew: false))
            XCTAssertEqual("שובר שוויון על המקום האחרון: הנקודה הראשונה מכריעה מי עולה.", MPKnockout.playerStatus(s, uid, hebrew: true))
            XCTAssertEqual(MPKnockout.tiebreakStatus(hebrew: false), MPCompletionText.matchHeadline(s, table, uid, hebrew: false))
        }
        XCTAssertEqual("You reached the final! Waiting for the other tables.", MPKnockout.playerStatus(s, w, hebrew: false))
        XCTAssertEqual("You reached the final!", MPCompletionText.matchHeadline(s, table, w, hebrew: false))
        XCTAssertEqual(MPKnockout.eliminatedText(hebrew: false), MPKnockout.playerStatus(s, z, hebrew: false))
        XCTAssertEqual(MPKnockout.eliminatedText(hebrew: true), MPCompletionText.matchHeadline(s, table, z, hebrew: true))
        // The other table finishes with a clear runner-up; the round still waits for the tie-break.
        s = try playFixture(s, b.id, [5, 4, 2, 0], b.players)
        XCTAssertEqual(1, s.rounds.count)
        XCTAssertEqual("ACTIVE", s.state)
        let bTable = try XCTUnwrap(s.matches[b.id])
        XCTAssertEqual("You reached the final!", MPCompletionText.matchHeadline(s, bTable, try item(b.players, 1), hebrew: false))   // a runner-up goes through too
        XCTAssertEqual(s, try MPKnockout.settle(s))
        try assertShapesRoundTrip(s)
        let sWire = try encodeSession(s)
        XCTAssertEqual("TIEBREAK", MPCodec.map(MPCodec.map(sWire["matches"])[key])["goal"] as? String)
        // One point decides it: a result at the room target is refused.
        let started = try startFixture(s, key)
        let p = started.session
        let auth = started.authority
        XCTAssertThrowsError(try MPRules.finish(p, match: key, actor: auth, a: 5, b: 3))
        XCTAssertThrowsError(try MPRules.finish(p, match: key, actor: auth, a: 1, b: 1))
        XCTAssertThrowsError(try MPRules.finish(p, match: key, actor: auth, a: 2, b: 1))
        XCTAssertThrowsError(try MPRules.finish(p, match: key, actor: auth, scores: [1, 0], placement: [y, x]))
        let done = try MPRules.finish(p, match: key, actor: auth, a: 0, b: 1)
        XCTAssertEqual(y, done.matches[key]?.winner)
        XCTAssertEqual([y, x], done.matches[key]?.placement)
        XCTAssertEqual(done, try MPRules.finish(done, match: key, actor: auth, a: 1, b: 0))                   // immutable
        let finalRound = try XCTUnwrap(done.rounds[1])
        XCTAssertTrue(finalRound.isFinal)
        let finalists: [String] = [w, y] + Array(b.players.prefix(2))
        XCTAssertEqual(Set(finalists), Set(finalRound.players))
        let doneTiebreak = try XCTUnwrap(done.matches[key])
        XCTAssertEqual("You reached the final!", MPCompletionText.matchHeadline(done, doneTiebreak, y, hebrew: false))
        XCTAssertEqual(MPKnockout.eliminatedText(hebrew: false), MPCompletionText.matchHeadline(done, doneTiebreak, x, hebrew: false))
        XCTAssertEqual(MPKnockout.eliminatedText(hebrew: false), MPKnockout.playerStatus(done, x, hebrew: false))

        // Three tied for second at a table of four: a three-player tie-break at one point.
        let room5 = try knockoutRoom(8, 4, .winnerTakesAll, 2, humans: 8, createdAt: 5)
        var t = try MPRules.start(room5, actor: "h0")
        let tRound = MPKnockout.matches(t, 0)
        let c = try item(tRound, 0)
        let d = try item(tRound, 1)
        let c0 = try item(c.players, 0), c1 = try item(c.players, 1), c2 = try item(c.players, 2), c3 = try item(c.players, 3)
        t = try playFixture(t, c.id, [2, 5, 2, 2], [c1, c0, c2, c3])
        let three = try XCTUnwrap(t.matches[MPKnockout.tiebreakId(t.code, 0, 0)])
        XCTAssertEqual(c.players.filter { $0 != c1 }, three.players)
        XCTAssertEqual(MPMatchGoal.tiebreak, three.goal)
        let startedThree = try startFixture(t, three.id)
        let q = startedThree.session
        let auth3 = startedThree.authority
        let badThree: [[Int]] = [[1, 1, 0], [5, 0, 0], [0, 1, 0], [0, 0, 0]]
        for scores in badThree {
            XCTAssertThrowsError(try MPRules.finish(q, match: three.id, actor: auth3, scores: scores, placement: three.players), "\(scores)")
        }
        let t0 = try item(three.players, 0), t1 = try item(three.players, 1), t2 = try item(three.players, 2)
        t = try MPRules.finish(q, match: three.id, actor: auth3, scores: [0, 1, 0], placement: [t1, t0, t2])
        XCTAssertEqual(1, t.rounds.count)                                                                    // table d is still open
        let d0 = try item(d.players, 0), d1 = try item(d.players, 1), d2 = try item(d.players, 2), d3 = try item(d.players, 3)
        t = try playFixture(t, d.id, [5, 1, 0, 3], [d0, d3, d1, d2])
        XCTAssertEqual(Set([c1, t1, d0, d3]), Set(t.rounds[1]?.players ?? []))
        XCTAssertTrue(MPKnockout.tiebreaks(t, 0).count == 1 && MPKnockout.tiebreaks(t, 1).isEmpty)
        // The final table never plays a tie-break: ties below the winner do not matter there.
        let fin = try onlyOne(MPKnockout.matches(t, 1))
        let fin0 = try item(fin.players, 0)
        t = try playFixture(t, fin.id, [5, 0, 0, 0], [fin0] + Array(fin.players.dropFirst()))
        XCTAssertTrue(t.complete)
        XCTAssertEqual(fin0, MPKnockout.winner(t))
        XCTAssertTrue(MPKnockout.tiebreaks(t, 1).isEmpty)
    }

    // Kotlin: aPairTieBreakIsDecidedByItsFirstPointEvenWhereClassicPairsNeedATwoPointLead
    func testAPairTieBreakIsDecidedByItsFirstPointEvenWhereClassicPairsNeedATwoPointLead() throws {
        // Pro (difficulty 3) gives classic pairs a two-point lead; a tie-break pair is a classic pair to one point with no
        // two-point lead: the first point decides, so only 1:0 is a result.
        let room = try knockoutRoom(8, 4, .winnerTakesAll, 2, humans: 8, createdAt: 3, difficulty: 3)
        var s = try MPRules.start(room, actor: "h0")
        let a = try XCTUnwrap(MPKnockout.matches(s, 0).first)
        let w = try item(a.players, 0), x = try item(a.players, 1), y = try item(a.players, 2), z = try item(a.players, 3)
        s = try playFixture(s, a.id, [5, 3, 3, 1], [w, x, y, z])
        let key = MPKnockout.tiebreakId(s.code, 0, 0)
        let started = try startFixture(s, key)
        let p = started.session
        let auth = started.authority
        let tb = try XCTUnwrap(p.matches[key])
        let oks: [[Int]] = [[1, 0], [0, 1]]
        for ok in oks { XCTAssertTrue(MPRules.validFinal(p, tb, ok), "\(ok)") }
        let bads: [[Int]] = [[0, 0], [1, 1], [2, 0], [3, 1], [5, 3], [2, 1], [1, 2], [-1, 1]]
        for bad in bads { XCTAssertFalse(MPRules.validFinal(p, tb, bad), "\(bad)") }
        XCTAssertThrowsError(try MPRules.finish(p, match: key, actor: auth, a: 2, b: 0))
        XCTAssertThrowsError(try MPRules.finish(p, match: key, actor: auth, a: 3, b: 1))
        let decided = try MPRules.finish(p, match: key, actor: auth, a: 0, b: 1)
        XCTAssertEqual(y, decided.matches[key]?.winner)
        XCTAssertFalse(MPRules.validFinal(p, target: p.target, scores: [5, 4]))
        XCTAssertTrue(MPRules.validFinal(p, target: p.target, scores: [6, 4]))                            // a classic pair keeps its deuce
        // House-only pair tie-breaks end on their first point; the same pair as a classic match keeps the deuce rule.
        let bots = [houseParticipant(roster[1], 1), houseParticipant(roster[2], 1)]
        var houseRoom = rawRoom("ELM234", .tournament, "h")
        houseRoom.capacity = 4
        houseRoom.difficulty = 3
        houseRoom.target = 5
        houseRoom.tableSize = 4
        var people: [String: MPParticipant] = [:]
        for bot in bots { people[bot.id] = bot }
        houseRoom.participants = people
        for seed in Int64(1)...Int64(40) {
            let m = MPFixture(id: "TB\(seed)", players: bots.map { $0.id }, seed: seed, goal: .tiebreak)
            let r = try XCTUnwrap(MPRules.simulate(houseRoom, m))
            XCTAssertEqual([0, 1], r.scores.sorted())
            let pointAt = try XCTUnwrap(r.scores.firstIndex(of: 1))
            XCTAssertEqual(m.players[pointAt], r.placement.first)
            var asPair = m
            asPair.goal = .win
            let pair = try XCTUnwrap(MPRules.simulate(houseRoom, asPair))
            XCTAssertTrue(MPRules.validFinal(houseRoom, pair.scores[0], pair.scores[1]))
        }
    }

    // Kotlin: houseOnlyTieBreaksAreSimulatedAtOnceToOnePoint
    func testHouseOnlyTieBreaksAreSimulatedAtOnceToOnePoint() throws {
        var found = 0, pairs = 0
        for seed in Int64(1)...Int64(80) {
            let room = try knockoutRoom(12, 4, .winnerTakesAll, 2, createdAt: seed)
            let s = try MPRules.start(room, actor: "h0")
            XCTAssertEqual(s, try MPKnockout.settle(s))
            for tb in MPKnockout.tiebreaks(s, 0) {
                found += 1
                if tb.players.count == 2 { pairs += 1 }
                XCTAssertEqual(MPMatchPhase.finished, tb.phase)
                XCTAssertEqual(0, tb.starts)
                XCTAssertEqual(MPMatchGoal.tiebreak, tb.goal)
                XCTAssertTrue(MPRules.houseOnly(s, tb))
                XCTAssertEqual(1, tb.scores.filter { $0 == 1 }.count)
                XCTAssertTrue(tb.scores.allSatisfy { $0 == 0 || $0 == 1 })
                XCTAssertEqual(tb.placement.first, tb.winner)
                XCTAssertTrue(MPRules.validFinal(s, tb, tb.scores) && MPRules.validPlacement(s, tb, tb.scores, tb.placement))
                var reset = tb
                reset.phase = .waiting
                reset.scores = Array(repeating: 0, count: tb.players.count)
                reset.winner = ""
                reset.placement = []
                XCTAssertEqual(tb, MPRules.simulated(s, reset))
            }
        }
        XCTAssertTrue(found > 10, "\(found) house tie-breaks")
        XCTAssertTrue(pairs > 3, "\(pairs) pair tie-breaks")
    }

    // Kotlin: departuresForfeitTablesAndTieBreaksWithoutInventedScores
    func testDeparturesForfeitTablesAndTieBreaksWithoutInventedScores() throws {
        // A tied player leaves: the tie-break is cancelled without a score and the other tied player takes the place.
        let room3 = try knockoutRoom(8, 4, .winnerTakesAll, 2, humans: 8, createdAt: 3)
        var s = try MPRules.start(room3, actor: "h0")
        let sRound = MPKnockout.matches(s, 0)
        let a = try item(sRound, 0)
        let b = try item(sRound, 1)
        let w = try item(a.players, 0), x = try item(a.players, 1), y = try item(a.players, 2)
        s = try playFixture(s, a.id, [5, 3, 3, 1], a.players)
        let key = MPKnockout.tiebreakId(s.code, 0, 0)
        s = try MPRules.leave(s, actor: x)                                                     // Kotlin leaveTournament
        let tb = try XCTUnwrap(s.matches[key])
        XCTAssertEqual(MPMatchPhase.cancelled, tb.phase)
        XCTAssertEqual([0, 0], tb.scores)
        XCTAssertTrue(tb.placement.isEmpty)
        XCTAssertEqual(y, tb.winner)
        s = try playFixture(s, b.id, [5, 4, 2, 0], b.players)
        let goingOn: [String] = [w, y] + Array(b.players.prefix(2))
        XCTAssertEqual(Set(goingOn), Set(s.rounds[1]?.players ?? []))
        // Three tied and one leaves: like a cancelled table, everybody left in it goes through (five go on: 3+2, no byes).
        let room5 = try knockoutRoom(8, 4, .winnerTakesAll, 2, humans: 8, createdAt: 5)
        var t = try MPRules.start(room5, actor: "h0")
        let tRound = MPKnockout.matches(t, 0)
        let c = try item(tRound, 0)
        let d = try item(tRound, 1)
        t = try playFixture(t, c.id, [5, 2, 2, 2], c.players)
        let three = try onlyOne(MPKnockout.tiebreaks(t, 0))
        t = try MPRules.leave(t, actor: try item(three.players, 0))
        XCTAssertEqual(MPMatchPhase.cancelled, t.matches[three.id]?.phase)
        XCTAssertEqual([0, 0, 0], t.matches[three.id]?.scores)
        t = try playFixture(t, d.id, [5, 4, 2, 0], d.players)
        let next = try XCTUnwrap(t.rounds[1])
        let cWinner = try item(c.players, 0)
        let expectedNext: [String] = [cWinner] + Array(three.players.dropFirst()) + Array(d.players.prefix(2))
        XCTAssertEqual(Set(expectedNext), Set(next.players))
        XCTAssertEqual([3], next.groups.map { $0.count })
        XCTAssertEqual([2], next.walkovers.map { $0.count })
        // Elimination, one through: a player who leaves before the table cancels it; nobody gets a score.
        let room9 = try knockoutRoom(8, 4, .elimination, 1, humans: 8, createdAt: 9)
        var e = try MPRules.start(room9, actor: "h0")
        let eRound = MPKnockout.matches(e, 0)
        let f = try item(eRound, 0)
        let g = try item(eRound, 1)
        let host = e.host
        let leaver = try XCTUnwrap(f.players.first(where: { $0 != host }))
        e = try MPRules.leave(e, actor: leaver)
        let fNow = try XCTUnwrap(e.matches[f.id])
        XCTAssertEqual(MPMatchPhase.cancelled, fNow.phase)
        XCTAssertEqual([0, 0, 0, 0], fNow.scores)
        XCTAssertNil(MPRules.duelOf(e, fNow), "a cancelled table has no final duel")
        var random4 = MPKotlinRandom(intSeed: 4)
        e = try playFixture(e, g.id, fixtureResult(e, g, &random4))
        // The other table's survivors play their final duel; one of them leaves before it: the other goes through.
        let gNow = try XCTUnwrap(e.matches[g.id])
        let duel = try XCTUnwrap(MPRules.duelOf(e, gNow))
        XCTAssertEqual(Array(gNow.placement.prefix(2)), duel.players)
        XCTAssertEqual(1, e.rounds.count)
        let eHost = e.host
        let quitter = try XCTUnwrap(duel.players.first(where: { $0 != eHost }))
        let stayer = try onlyOne(duel.players.filter { $0 != quitter })
        e = try MPRules.leave(e, actor: quitter)
        let cancelled = try XCTUnwrap(e.matches[duel.id])
        XCTAssertEqual(MPMatchPhase.cancelled, cancelled.phase)
        XCTAssertEqual([0, 0], cancelled.scores)
        XCTAssertTrue(cancelled.placement.isEmpty)
        XCTAssertEqual(stayer, cancelled.winner)
        let departed = e.departed
        let staying: [String] = f.players.filter { departed[$0] != true } + [stayer]
        XCTAssertEqual(Set(staying), Set(e.rounds[1]?.players ?? []))
        let eDecoded = try decodeSession(try encodeSession(e))
        XCTAssertEqual(plainSession(e), plainSession(eDecoded))
        // The same in a round robin: the duelist who stays takes first place at that table; nobody gets a duel score.
        var rr = createRoom("RRB234", .tournament, MPIdentity(id: "h0", name: "Host"), 3, 1, 3, 0, 0, 5,
                            format: .roundRobin, tableSize: 3, gameMode: .elimination)
        for i in 1...2 { rr = try MPRules.join(rr, MPIdentity(id: "h\(i)", name: "Player \(i)")) }
        rr = try MPRules.start(onlineSession(rr), actor: "h0")
        let rrTable = try onlyOne(Array(rr.matches.values))
        let held: [String: Int] = ["h0": 1, "h1": 2, "h2": 0]                                       // h2 out first; h1 and h0 survive
        rr = try playFixture(rr, rrTable.id, rrTable.players.map { held[$0] ?? 0 }, ["h1", "h0", "h2"])
        let rrTableNow = try XCTUnwrap(rr.matches[rrTable.id])
        let rrDuel = try XCTUnwrap(MPRules.duelOf(rr, rrTableNow))
        XCTAssertEqual(["h1", "h0"], rrDuel.players)
        XCTAssertEqual("ACTIVE", rr.state)
        XCTAssertTrue(MPRules.standings(rr).allSatisfy { $0.played == 0 })                         // the table counts once decided
        rr = try MPRules.leave(rr, actor: "h1")
        XCTAssertEqual(MPMatchPhase.cancelled, rr.matches[rrDuel.id]?.phase)
        XCTAssertEqual([0, 0], rr.matches[rrDuel.id]?.scores)
        XCTAssertEqual("FINISHED", rr.state)
        let rrFinal = try XCTUnwrap(rr.matches[rrTable.id])
        XCTAssertEqual(["h0", "h1", "h2"], MPRules.ranking(rr, rrFinal))
        var pointsById: [String: Int] = [:]
        for row in MPRules.standings(rr) { pointsById[row.id] = row.points }
        XCTAssertEqual(["h0": 3, "h1": 2, "h2": 1], pointsById)
    }

    // ---- Walkover tables ----

    // Kotlin: aTableNoLargerThanTheNumberGoingThroughIsAStoredWalkover
    func testATableNoLargerThanTheNumberGoingThroughIsAStoredWalkover() throws {
        for mode in MPGameMode.allCases {
            let room = try knockoutRoom(5, 4, mode, 2, humans: 5, createdAt: 21)
            var s = try MPRules.start(room, actor: "h0")
            let round = try XCTUnwrap(s.rounds[0])
            let table = try onlyOne(MPKnockout.matches(s, 0))
            let pair = try onlyOne(round.walkovers)
            XCTAssertEqual(3, table.players.count)
            XCTAssertEqual(2, pair.count)
            XCTAssertTrue(round.byes.isEmpty)
            XCTAssertFalse(round.isFinal)
            XCTAssertEqual(table.players + pair, round.players)
            XCTAssertEqual(pair, round.resting)
            XCTAssertEqual(1, s.matches.count)
            XCTAssertEqual(mode == .elimination ? MPMatchGoal.topTwo : MPMatchGoal.win, table.goal)
            XCTAssertEqual("Semifinal tables", MPKnockout.stage(s, hebrew: false))
            let wire = try encodeSession(s)
            let roundWire = MPCodec.map(MPCodec.map(wire["rounds"])["0"])
            XCTAssertEqual([pair], roundWire["walkovers"] as? [[String]])
            try assertShapesRoundTrip(s, mode.rawValue)
            for uid in pair {
                XCTAssertEqual("Your table advances without playing. Waiting for the other tables.", MPKnockout.playerStatus(s, uid, hebrew: false))
                XCTAssertEqual("השולחן שלכם עולה לסיבוב הבא בלי לשחק. ממתינים לשאר השולחנות.", MPKnockout.playerStatus(s, uid, hebrew: true))
            }
            XCTAssertEqual("Advance without playing", MPKnockout.walkoverTitle(hebrew: false))
            XCTAssertEqual("עולים בלי לשחק", MPKnockout.walkoverTitle(hebrew: true))
            // Winner takes all 5:3:1; elimination: the third player out holding 3, the survivors on 4 and 2.
            let scores: [Int] = mode == .elimination ? [4, 2, 3] : [5, 3, 1]
            s = try playFixture(s, table.id, scores, table.players)
            let finalRound = try XCTUnwrap(s.rounds[1])
            XCTAssertTrue(finalRound.isFinal)
            let finalists: [String] = pair + Array(table.players.prefix(2))
            XCTAssertEqual(Set(finalists), Set(finalRound.players))
            let finalTable = try onlyOne(MPKnockout.matches(s, 1))
            XCTAssertEqual(MPMatchGoal.win, finalTable.goal)
        }
        // One through per table: the pair is no walkover but a classic pair match.
        let roomOne = try knockoutRoom(5, 4, .elimination, 1, humans: 5, createdAt: 21)
        var one = try MPRules.start(roomOne, actor: "h0")
        XCTAssertTrue(one.rounds[0]?.walkovers.isEmpty == true)
        XCTAssertEqual([3, 2], MPKnockout.matches(one, 0).map { $0.players.count })
        XCTAssertTrue(MPKnockout.matches(one, 0).allSatisfy { $0.goal == .win })
        let oneRound = MPKnockout.matches(one, 0)
        let oneThree = try item(oneRound, 0)
        let onePair = try item(oneRound, 1)
        let startedPair = try startFixture(one, onePair.id)
        let q = startedPair.session
        let auth = startedPair.authority
        XCTAssertThrowsError(try MPRules.finish(q, match: onePair.id, actor: auth, a: 5, b: 5))
        XCTAssertThrowsError(try MPRules.finish(q, match: onePair.id, actor: auth, a: 6, b: 3))
        one = try MPRules.finish(q, match: onePair.id, actor: auth, a: 3, b: 5)
        XCTAssertEqual(onePair.b, one.matches[onePair.id]?.winner)
        let pairNow = try XCTUnwrap(one.matches[onePair.id])
        XCTAssertNil(MPRules.duelOf(one, pairNow), "a pair has no final duel: it is one")
        var random2 = MPKotlinRandom(intSeed: 2)
        one = try playFixture(one, oneThree.id, fixtureResult(one, oneThree, &random2))
        let threeNow = try XCTUnwrap(one.matches[oneThree.id])
        let duel = try XCTUnwrap(MPRules.duelOf(one, threeNow))
        XCTAssertEqual(1, one.rounds.count)                                                                  // the duel decides the table
        one = try playFixture(one, duel.id, [5, 1], duel.players)
        let oneFinal = try onlyOne(MPKnockout.matches(one, 1))
        XCTAssertEqual(Set([onePair.b, duel.a]), Set(oneFinal.players))
        XCTAssertTrue(one.rounds[1]?.isFinal == true)
        XCTAssertEqual(2, oneFinal.players.count)
        let startedFinal = try startFixture(one, oneFinal.id)
        one = try MPRules.finish(startedFinal.session, match: oneFinal.id, actor: startedFinal.authority, a: 5, b: 2)
        XCTAssertTrue(one.complete)
        XCTAssertEqual(oneFinal.a, MPKnockout.winner(one))
    }

    // ---- Final duels in elimination knockouts ----

    // Kotlin: eliminationKnockoutTablesSendOneThroughByAClassicFinalDuel
    func testEliminationKnockoutTablesSendOneThroughByAClassicFinalDuel() throws {
        // Eight players at tables of four, one through, two people: the house-only table and its duel finish at once.
        let room = try knockoutRoom(8, 4, .elimination, 1, humans: 2, createdAt: 17)
        var s = try MPRules.start(room, actor: "h0")
        let games = MPKnockout.matches(s, 0)
        let mine = try onlyOne(games.filter { $0.contains("h0") })
        let other = try onlyOne(games.filter { $0.id != mine.id })
        if MPRules.houseOnly(s, other) {
            let done = try XCTUnwrap(s.matches[other.id])
            let houseDuel = try XCTUnwrap(MPRules.duelOf(s, done))
            XCTAssertEqual(MPMatchPhase.finished, done.phase)
            XCTAssertEqual(Array(done.placement.prefix(2)), houseDuel.players)
            XCTAssertEqual(MPMatchPhase.finished, houseDuel.phase)
            XCTAssertEqual(0, houseDuel.starts)
            XCTAssertTrue(MPRules.validFinal(s, houseDuel, houseDuel.scores))
            XCTAssertEqual([houseDuel.winner], MPKnockout.through(s, 0, done))
        } else {
            XCTAssertTrue(other.contains("h1"))
        }
        XCTAssertEqual("Your table this round: the final duel's winner advances.", MPKnockout.playerStatus(s, "h0", hebrew: false))
        // h0 survives with a house player: their classic duel waits for h0; the others at the table are out.
        let houseIds = mine.players.filter { s.participants[$0]?.bot != nil }
        let house0 = try item(houseIds, 0)
        let order: [String] = ["h0", house0] + mine.players.filter { $0 != "h0" && $0 != house0 }
        let points = [3, 1, 2, 0]
        var held: [String: Int] = [:]
        for (i, uid) in order.enumerated() { held[uid] = i < points.count ? points[i] : 0 }
        s = try playFixture(s, mine.id, mine.players.map { held[$0] ?? 0 }, order)
        let duelId = MPRules.duelId(mine.id)
        let duel = try XCTUnwrap(s.matches[duelId])
        let mineNow = try XCTUnwrap(s.matches[mine.id])
        let tableIndex = try XCTUnwrap(MPKnockout.matches(s, 0).firstIndex(of: mineNow))
        XCTAssertEqual("ELM234_K0_\(tableIndex)_D", duelId)
        XCTAssertEqual(["h0", house0], duel.players)
        XCTAssertEqual(MPMatchPhase.waiting, duel.phase)
        XCTAssertEqual("h0", s.authority(duel))
        XCTAssertTrue(MPKnockout.duels(s, 0).contains(duel) && MPKnockout.fixtures(s, 0).contains(duel))
        XCTAssertFalse(MPKnockout.matches(s, 0).contains(duel))
        XCTAssertEqual("You are in the final duel: the winner advances.", MPKnockout.playerStatus(s, "h0", hebrew: false))
        XCTAssertEqual("אתם בקרב הגמר: הניצחון מעלה לסיבוב הבא.", MPKnockout.playerStatus(s, "h0", hebrew: true))
        let order2 = try item(order, 2)
        XCTAssertEqual(MPKnockout.eliminatedText(hebrew: false), MPCompletionText.matchHeadline(s, mine, order2, hebrew: false))   // out before the final: no waiting
        XCTAssertEqual(MPCompletionText.duelStatus(s, hebrew: false), MPCompletionText.matchHeadline(s, mine, "h0", hebrew: false))
        XCTAssertTrue(MPKnockout.through(s, 0, mineNow).isEmpty)
        XCTAssertEqual(1, s.rounds.count)
        XCTAssertEqual(s, try MPKnockout.settle(s))
        try assertShapesRoundTrip(s)
        // The duel is a classic pair: the room target, the classic validation; the winner goes through.
        let startedDuel = try startFixture(s, duelId)
        let q = startedDuel.session
        let auth = startedDuel.authority
        XCTAssertThrowsError(try MPRules.finish(q, match: duelId, actor: auth, a: 4, b: 2))
        XCTAssertThrowsError(try MPRules.finish(q, match: duelId, actor: auth, a: 1, b: 0))
        s = try MPRules.finish(q, match: duelId, actor: auth, a: 5, b: 3)
        let duelDone = try XCTUnwrap(s.matches[duelId])
        let mineAfter = try XCTUnwrap(s.matches[mine.id])
        XCTAssertEqual("h0", duelDone.winner)
        XCTAssertEqual(["h0"], MPKnockout.through(s, 0, mineAfter))
        XCTAssertTrue(MPKnockout.goesThrough(s, duelDone, "h0"))
        XCTAssertFalse(MPKnockout.goesThrough(s, duelDone, house0))
        XCTAssertEqual(MPKnockout.advanceText(s, duelDone, hebrew: false), MPCompletionText.matchHeadline(s, duelDone, "h0", hebrew: false))
        XCTAssertEqual(MPKnockout.eliminatedText(hebrew: false), MPCompletionText.matchHeadline(s, duelDone, house0, hebrew: false))
        if s.rounds.count > 1 { XCTAssertTrue(s.rounds[1]?.players.contains("h0") == true) }
        // Losing the duel is going out.
        let lost = try MPRules.finish(q, match: duelId, actor: auth, a: 2, b: 5)
        XCTAssertFalse(MPKnockout.advancing(lost, 0).contains("h0"))
        if !lost.complete { XCTAssertEqual(MPKnockout.eliminatedText(hebrew: false), MPKnockout.playerStatus(lost, "h0", hebrew: false)) }
    }

    // Kotlin: theFinalTableOfAnEliminationKnockoutEndsWithAFinalDuel
    func testTheFinalTableOfAnEliminationKnockoutEndsWithAFinalDuel() throws {
        for advance in 1...2 {
            let room = try knockoutRoom(4, 4, .elimination, advance, humans: 4, createdAt: 8)
            var s = try MPRules.start(room, actor: "h0")
            let table = try onlyOne(MPKnockout.matches(s, 0))
            XCTAssertTrue(s.rounds[0]?.isFinal == true)
            XCTAssertEqual(MPMatchGoal.win, table.goal)
            // h2 and h0 survive (2 and 1), h3 went out second holding 3 points, h1 first.
            let held: [String: Int] = ["h0": 1, "h1": 0, "h2": 2, "h3": 3]
            s = try playFixture(s, table.id, table.players.map { held[$0] ?? 0 }, ["h2", "h0", "h3", "h1"])
            let tableNow = try XCTUnwrap(s.matches[table.id])
            let duel = try XCTUnwrap(MPRules.duelOf(s, tableNow))
            XCTAssertEqual(["h2", "h0"], duel.players)
            XCTAssertFalse(s.complete)
            XCTAssertNil(MPKnockout.winner(s))
            XCTAssertEqual("ACTIVE", s.state)
            for uid in duel.players {
                XCTAssertEqual("You are in the final duel: the winner takes the tournament.", MPKnockout.playerStatus(s, uid, hebrew: false))
            }
            XCTAssertEqual("אתם בקרב הגמר: הניצחון מכריע את הטורניר.", MPKnockout.playerStatus(s, "h0", hebrew: true))
            for uid in ["h1", "h3"] {
                XCTAssertEqual("Waiting for the final duel.", MPKnockout.playerStatus(s, uid, hebrew: false))
                XCTAssertEqual("ממתינים לקרב הגמר.", MPKnockout.playerStatus(s, uid, hebrew: true))
                XCTAssertEqual("Waiting for the final duel.", MPCompletionText.matchHeadline(s, table, uid, hebrew: false))
            }
            for uid in s.participants.keys { XCTAssertEqual(0, MPCompletionText.place(s, uid)) }
            // h0 wins the duel and the tournament; h2 is second, then h3 (out last), then h1.
            s = try playFixture(s, duel.id, [3, 5], Array(duel.players.reversed()))
            XCTAssertTrue(s.complete)
            XCTAssertEqual("FINISHED", s.state)
            XCTAssertEqual("h0", MPKnockout.winner(s))
            let tableDone = try XCTUnwrap(s.matches[table.id])
            XCTAssertEqual(["h0", "h2", "h3", "h1"], MPRules.ranking(s, tableDone))
            let finished = s
            XCTAssertEqual([1, 2, 3, 4], ["h0", "h2", "h3", "h1"].map { MPCompletionText.place(finished, $0) })
            XCTAssertTrue(MPCompletionText.won(s, "h0"))
            XCTAssertFalse(MPCompletionText.won(s, "h2"))
            XCTAssertEqual("You won the tournament!", MPCompletionText.headline(s, "h0", hebrew: false))
            XCTAssertEqual("Tournament finished. You placed 2nd.", MPCompletionText.headline(s, "h2", hebrew: false))
            XCTAssertEqual("Tournament finished. You placed 4th.", MPCompletionText.headline(s, "h1", hebrew: false))
            let decoded = try decodeSession(try encodeSession(s))
            XCTAssertEqual(plainSession(s), plainSession(decoded))
        }
        // A finalist who leaves before the final duel hands the tournament to the other.
        let leaveRoom = try knockoutRoom(4, 3, .elimination, 1, humans: 4, createdAt: 8)
        var t = try MPRules.start(leaveRoom, actor: "h0")
        let leaveTable = try onlyOne(MPKnockout.matches(t, 0))
        let leaveHeld: [String: Int] = ["h0": 1, "h1": 0, "h2": 2, "h3": 3]
        t = try playFixture(t, leaveTable.id, leaveTable.players.map { leaveHeld[$0] ?? 0 }, ["h2", "h3", "h0", "h1"])
        let leaveTableNow = try XCTUnwrap(t.matches[leaveTable.id])
        let leaveDuel = try XCTUnwrap(MPRules.duelOf(t, leaveTableNow))
        XCTAssertEqual(["h2", "h3"], leaveDuel.players)
        t = try MPRules.leave(t, actor: "h2")
        XCTAssertEqual(MPMatchPhase.cancelled, t.matches[leaveDuel.id]?.phase)
        XCTAssertEqual([0, 0], t.matches[leaveDuel.id]?.scores)
        XCTAssertTrue(t.complete)
        XCTAssertEqual("h3", MPKnockout.winner(t))
        let leaveTableDone = try XCTUnwrap(t.matches[leaveTable.id])
        XCTAssertEqual(["h3", "h2", "h0", "h1"], MPRules.ranking(t, leaveTableDone))
        XCTAssertEqual("You won the tournament!", MPCompletionText.headline(t, "h3", hebrew: false))
    }

    // ---- House-only simulation ----

    // Kotlin: houseOnlyEliminationTablesObeyTheModeRules
    func testHouseOnlyEliminationTablesObeyTheModeRules() throws {
        var dropouts = 0, lowest = 0, resets = 0, tables = 0
        // Everybody starts a stage at 0, so the first point lost there is a drop-out. Target 1 is reached on such a drop-out,
        // which then also restarts the stage from 0 (see the counts below); the room targets are 3...11.
        let seeds: [Int64] = Array(Int64(-30)...Int64(30)) + [Int64.min, Int64.min + 1, Int64.max]
        for n in 3...4 {
            for target in [1, 2, 3, 5, 7, 10] {
                for seed in seeds {
                    var castRandom = MPKotlinRandom(seed: seed &* 31 &+ Int64(n))
                    let cast = Array(castRandom.shuffled(roster).prefix(n))
                    let players = cast.map { "bot_\($0.id)" }
                    let bots = cast.map { $0.profile }
                    let ctx = "\(n) seats, target \(target), seed \(seed)"
                    let log = StepLog()
                    let r = MPTableSimulation.elimination(players, bots, target: target, seed: seed, trace: { log.steps.append($0) })
                    XCTAssertEqual(r, MPTableSimulation.elimination(players, bots, target: target, seed: seed), ctx)
                    tables += 1
                    var gone: [Int] = []
                    var armed = false
                    for (i, x) in log.steps.enumerated() {
                        if i > 0 { XCTAssertEqual(log.steps[i - 1].after, x.before, ctx) }
                        XCTAssertTrue((x.before + x.after).allSatisfy { $0 >= 0 && $0 <= target }, ctx)     // never below 0 or above the target
                        let aliveClean = !x.alive.contains(where: { gone.contains($0) })
                        let loserIn = x.alive.contains(x.loser)
                        var scorerOk = true
                        if let scorer = x.scorer { scorerOk = x.alive.contains(scorer) && scorer != x.loser }
                        XCTAssertTrue(aliveClean && loserIn && scorerOk, ctx)
                        let changed = (0..<n).filter { x.before[$0] != x.after[$0] }
                        XCTAssertTrue(changed.allSatisfy { x.alive.contains($0) }, ctx)                     // a player who is out keeps their score
                        XCTAssertTrue(x.alive.count >= 3, ctx)                                              // the table stops at two
                        var pre = x.before
                        if let scorer = x.scorer { pre[scorer] = min(target, pre[scorer] + 1) }
                        if pre[x.loser] > 0 { pre[x.loser] -= 1 }
                        let reached = armed || x.alive.contains(where: { pre[$0] >= target })
                        let out = x.out
                        if x.before[x.loser] == 0 {
                            XCTAssertEqual(x.loser, out, "\(ctx): below 0 is out at once")
                            dropouts += 1
                        } else if let leaving = out {                                                       // the target was reached: the unique lowest is out
                            XCTAssertTrue(reached, ctx)
                            XCTAssertTrue(x.alive.filter { $0 != leaving }.allSatisfy { pre[$0] > pre[leaving] }, ctx)
                            lowest += 1
                        } else if reached {
                            let low = x.alive.map { pre[$0] }.min() ?? 0
                            XCTAssertTrue(x.alive.filter { pre[$0] == low }.count > 1, "\(ctx): a tie for the lowest plays on")
                        }
                        if let leaving = out { XCTAssertEqual(pre[leaving], x.after[leaving], "\(ctx): out with the score they had") }
                        let left = x.alive.count - (out != nil ? 1 : 0)
                        XCTAssertEqual(out != nil && left > 2 && reached, x.reset, ctx)                    // a new stage restarts; the last two keep their scores
                        if x.reset {
                            resets += 1
                            XCTAssertTrue(x.alive.filter { $0 != out }.allSatisfy { x.after[$0] == 0 }, ctx)
                        } else {
                            let kept = pre.indices.filter { x.alive.contains($0) && $0 != out }
                            XCTAssertEqual(kept.map { pre[$0] }, kept.map { x.after[$0] }, ctx)
                        }
                        if let leaving = out { gone.append(leaving) }
                        armed = out == nil && reached
                    }
                    XCTAssertEqual(n - 2, gone.count, ctx)
                    XCTAssertEqual(gone.reversed().map { players[$0] }, Array(r.placement.dropFirst(2)), ctx)       // the last out ranks highest
                    for p in gone {
                        let lastOut = log.steps.last(where: { $0.out == p })
                        XCTAssertEqual(lastOut?.after[p], r.scores[p], ctx)                                 // the score they went out with
                    }
                    var score: [String: Int] = [:]                                                          // the two survivors by score
                    for (i, id) in players.enumerated() { score[id] = r.scores[i] }
                    let first = try item(r.placement, 0), second = try item(r.placement, 1)
                    XCTAssertTrue((score[first] ?? 0) >= (score[second] ?? 0), ctx)
                    let survivors = Set(players.indices.filter { !gone.contains($0) }.map { players[$0] })
                    XCTAssertEqual(survivors, Set(r.placement.prefix(2)), ctx)
                    XCTAssertEqual(log.steps.last?.after, r.scores, ctx)
                    // The same table result for both goals; only a WIN table then hands its survivors to a classic duel.
                    for goal in [MPMatchGoal.win, MPMatchGoal.topTwo] {
                        let m = MPFixture(id: "ELM234_T0_0", players: players, seed: seed, goal: goal)
                        var s = rawRoom("ELM234", .tournament, "h")
                        s.capacity = n
                        s.target = target
                        s.tableSize = n
                        s.gameMode = .elimination
                        s.state = "ACTIVE"
                        var people: [String: MPParticipant] = [:]
                        for (i, id) in players.enumerated() { people[id] = MPParticipant(identity: MPIdentity(id: id, name: id), bot: bots[i]) }
                        s.participants = people
                        s.matches = [m.id: m]
                        XCTAssertTrue(MPRules.validFinal(s, m, r.scores) && MPRules.validPlacement(s, m, r.scores, r.placement), ctx)
                        XCTAssertEqual(MPRules.simulate(s, m), r, ctx)
                        let done = MPRules.simulated(s, m)
                        var expected = m
                        expected.phase = .finished
                        expected.scores = r.scores
                        expected.winner = r.placement.first ?? ""
                        expected.placement = r.placement
                        XCTAssertEqual(expected, done, ctx)
                        var withTable = s
                        withTable.matches = [m.id: done]
                        let decided = MPRules.withDuel(withTable, done)
                        let duel = MPRules.duelOf(decided, done)
                        if goal == .topTwo {
                            XCTAssertNil(duel, ctx)
                            XCTAssertEqual(r.placement, MPRules.ranking(decided, done), ctx)
                        } else {
                            let d = try XCTUnwrap(duel, ctx)
                            XCTAssertEqual("ELM234_T0_0_D", d.id, ctx)
                            XCTAssertEqual(Array(r.placement.prefix(2)), d.players, ctx)
                            XCTAssertEqual(MPMatchPhase.finished, d.phase, ctx)
                            XCTAssertEqual(0, d.starts, ctx)
                            XCTAssertTrue(MPRules.validFinal(decided, d, d.scores), ctx)                    // a classic pair result
                            XCTAssertEqual(target, d.scoreOf(d.winner), ctx)
                            XCTAssertEqual(d.winner, MPRules.finalWinner(decided, done), ctx)
                            XCTAssertEqual(decided, MPRules.withDuel(decided, done), ctx)                   // added once
                        }
                    }
                }
            }
        }
        print("elimination: \(tables) tables, \(dropouts) drop-outs, \(lowest) lowest-at-target, \(resets) restarts")
        // A stage starts at 0 for everybody and gains a point only when a missed return knocks out a player at 0, so the
        // players still in never hold more points than the stage has had drop-outs: at tables of 3 or 4 nobody reaches a
        // target >= 2 before two are left, and target 1 is reached only on a drop-out. The lowest-at-target rule therefore
        // never fires here: the elimination order is the drop-out order.
        XCTAssertTrue(dropouts > 500, "\(dropouts)")
        XCTAssertEqual(0, lowest)
        XCTAssertTrue(resets > 10, "\(resets)")
        // Swift returns an empty result instead of throwing for a two-seat table.
        let plainBot = MPBot(speed: 5, reaction: 5, accuracy: 5, power: 5, agility: 5, characterId: "", forehandSkill: 5, backhandSkill: 5, serveSkill: 5)
        XCTAssertEqual(MPTableResult(scores: [0, 0], placement: ["a", "b"]),
                       MPTableSimulation.elimination(["a", "b"], [plainBot, plainBot], target: 3, seed: 1))
        // Skill still matters: the strongest character survives an elimination table more often than a weaker one.
        var survived: [String: Int] = [:]
        let skillCast = ["gaya", "kyra", "flare"].map { MPRoster.find($0) ?? MPRoster.all[0] }
        let castIds = skillCast.map { $0.id }
        let castBots = skillCast.map { $0.profile }
        for seed in Int64(0)..<Int64(600) {
            let result = MPTableSimulation.elimination(castIds, castBots, target: 5, seed: seed)
            for uid in result.placement.prefix(2) { survived[uid, default: 0] += 1 }
        }
        XCTAssertTrue((survived["kyra"] ?? 0) > (survived["gaya"] ?? 0) && (survived["gaya"] ?? 0) > 0, "\(survived)")
    }

    // ---- Results ----

    /// A four-seat friendly hosted by "host" with b, c and d, started.
    private func friendlyFour(_ mode: MPGameMode) throws -> MPSession {
        var f = createRoom("FRN234", .friendly, MPIdentity(id: "host", name: "Host"), 4, 1, 3, 0, 0, 5, tableSize: 4, gameMode: mode)
        for uid in ["b", "c", "d"] { f = try MPRules.join(f, MPIdentity(id: uid, name: uid.uppercased())) }
        return try MPRules.start(onlineSession(f), actor: "host")
    }

    // Kotlin: resultsAreValidatedByTheFixturesModeAndGoal
    func testResultsAreValidatedByTheFixturesModeAndGoal() throws {
        // A four-seat ELIMINATION friendly: the table plays until two are left (elimination order, no target needed), then
        // those two play the classic final duel for the game.
        let f = try friendlyFour(.elimination)
        let m = try onlyOne(Array(f.matches.values))
        let id = m.id
        XCTAssertEqual(MPMatchGoal.win, m.goal)
        XCTAssertEqual(["host", "b", "c", "d"], m.players)
        XCTAssertTrue(MPRules.eliminates(f, m))
        let started = try startFixture(f, id)
        let p = started.session
        let auth = started.authority
        XCTAssertEqual("b", auth)
        // b and host survive (4 and 2); c went out second holding 3 points, d first with 0. Nobody needs the target.
        let scores = [2, 4, 3, 0]
        let placement = ["b", "host", "c", "d"]
        XCTAssertTrue(MPRules.validFinal(p, m, scores))
        XCTAssertTrue(MPRules.validPlacement(p, m, scores, placement))
        XCTAssertFalse(MPRules.validPlacement(m, scores, placement))
        let oks: [[Int]] = [[0, 0, 0, 0], [5, 5, 1, 0], [2, 4, 5, 0]]
        for ok in oks { XCTAssertTrue(MPRules.validFinal(p, m, ok), "\(ok)") }
        let badScores: [[Int]] = [[2, 4, 6, 0], [-1, 4, 3, 0], [2, 4, 3], [2, 4, 3, 0, 0]]
        for bad in badScores { XCTAssertThrowsError(try MPRules.finish(p, match: id, actor: auth, scores: bad, placement: placement), "\(bad)") }
        let badPlacements: [[String]] = [["b", "host", "c", "c"], ["b", "host", "c"], ["b", "host", "c", "z"]]
        for bad in badPlacements { XCTAssertThrowsError(try MPRules.finish(p, match: id, actor: auth, scores: scores, placement: bad), "\(bad)") }
        for who in ["host", "c", "outsider"] { XCTAssertThrowsError(try MPRules.finish(p, match: id, actor: who, scores: scores, placement: placement), who) }
        var done = try MPRules.finish(p, match: id, actor: auth, scores: scores, placement: placement)
        let table = try XCTUnwrap(done.matches[id])
        let duelId = MPRules.duelId(id)
        XCTAssertEqual("b", table.winner)
        XCTAssertEqual(placement, table.placement)
        XCTAssertEqual(MPMatchPhase.finished, table.phase)
        // The final duel came with the table result: b against host, the room target, a classic pair.
        let duel = try XCTUnwrap(done.matches[duelId])
        XCTAssertEqual("FRN234_0_0_1_D", duel.id)
        XCTAssertEqual(["b", "host"], duel.players)
        XCTAssertEqual(MPMatchGoal.win, duel.goal)
        XCTAssertEqual(MPMatchPhase.waiting, duel.phase)
        XCTAssertEqual([0, 0], duel.scores)
        XCTAssertTrue(MPRules.isDuel(duel))
        XCTAssertFalse(MPRules.isDuel(table))
        XCTAssertEqual(table, MPRules.tableOf(done, duel))
        XCTAssertEqual(duel, MPRules.duelOf(done, table))
        XCTAssertNil(MPRules.tableOf(done, table))
        XCTAssertEqual("b", done.authority(duel))
        XCTAssertFalse(done.complete)
        XCTAssertEqual("ACTIVE", done.state)
        XCTAssertNil(MPRules.finalWinner(done, table))
        XCTAssertNil(MPRules.ranking(done, table))
        for uid in done.participants.keys { XCTAssertFalse(MPCompletionText.won(done, uid)) }
        XCTAssertEqual("You are in the final duel: the winner takes the game.", MPCompletionText.matchHeadline(done, table, "host", hebrew: false))
        XCTAssertEqual("אתם בקרב הגמר: הניצחון מכריע את המשחק.", MPCompletionText.matchHeadline(done, table, "b", hebrew: true))
        XCTAssertEqual("Waiting for the final duel.", MPCompletionText.matchHeadline(done, table, "c", hebrew: false))
        XCTAssertEqual("ממתינים לקרב הגמר.", MPCompletionText.matchHeadline(done, table, "d", hebrew: true))
        XCTAssertEqual(done, try MPRules.finish(done, match: id, actor: auth, scores: [5, 0, 0, 0], placement: ["host", "b", "c", "d"]))   // immutable
        let doneDecoded = try decodeSession(try encodeSession(done))
        XCTAssertEqual(plainSession(done), plainSession(doneDecoded))
        let doneWire = try encodeSession(done)
        XCTAssertNil(MPCodec.map(MPCodec.map(doneWire["matches"])[duelId])["goal"])
        // The duel follows the classic rules (no target 1, no score at the table's scale) and decides the game.
        let startedDuel = try startFixture(done, duelId)
        let dq = startedDuel.session
        let dAuth = startedDuel.authority
        let badDuels: [[Int]] = [[5, 5], [4, 3], [6, 3], [1, 0]]
        for bad in badDuels {
            XCTAssertThrowsError(try MPRules.finish(dq, match: duelId, actor: dAuth, scores: bad, placement: ["b", "host"]), "\(bad)")
        }
        done = try MPRules.finish(dq, match: duelId, actor: dAuth, a: 3, b: 5)
        XCTAssertTrue(done.complete)
        XCTAssertEqual("FINISHED", done.state)
        XCTAssertEqual("host", MPRules.finalWinner(done, table))
        XCTAssertEqual(["host", "b", "c", "d"], MPRules.ranking(done, table))
        XCTAssertTrue(MPCompletionText.won(done, "host"))
        for uid in ["b", "c", "d"] { XCTAssertFalse(MPCompletionText.won(done, uid)) }
        XCTAssertEqual("You won the match!", MPCompletionText.headline(done, "host", hebrew: false))
        XCTAssertTrue(MPCompletionText.headline(done, "b", hebrew: false).hasSuffix(" won this match!"))
        XCTAssertEqual("You won the match!", MPCompletionText.matchHeadline(done, duel, "host", hebrew: false))
        let finalDecoded = try decodeSession(try encodeSession(done))
        XCTAssertEqual(plainSession(done), plainSession(finalDecoded))
        // The same table result is no winner-takes-all result: those rank by score with one player at the target.
        let wtaRoom = try friendlyFour(.winnerTakesAll)
        let wtaStarted = try startFixture(wtaRoom, id)
        let wta = wtaStarted.session
        let wtaAuth = wtaStarted.authority
        XCTAssertThrowsError(try MPRules.finish(wta, match: id, actor: wtaAuth, scores: scores, placement: placement))
        let wtaDone = try MPRules.finish(wta, match: id, actor: wtaAuth, scores: [2, 4, 5, 0], placement: ["c", "b", "host", "d"])
        XCTAssertEqual("c", wtaDone.matches[id]?.winner)
        XCTAssertTrue(wtaDone.complete)
        XCTAssertEqual(1, wtaDone.matches.count)                                                            // no duel
        // TOP_TWO: two survivors, any scores in [0, target], no target required.
        let kRoom = try knockoutRoom(8, 4, .elimination, 2, humans: 8, createdAt: 9)
        let k = try MPRules.start(kRoom, actor: "h0")
        let t = try XCTUnwrap(MPKnockout.matches(k, 0).first)
        XCTAssertEqual(MPMatchGoal.topTwo, t.goal)
        let tStarted = try startFixture(k, t.id)
        let q = tStarted.session
        let tAuth = tStarted.authority
        let t0 = try item(t.players, 0), t1 = try item(t.players, 1), t2 = try item(t.players, 2), t3 = try item(t.players, 3)
        let topOks: [[Int]] = [[3, 3, 1, 0], [0, 0, 0, 0], [5, 5, 4, 0], [1, 2, 4, 3]]
        for ok in topOks { XCTAssertTrue(MPRules.validFinal(q, t, ok) && MPRules.validPlacement(q, t, ok, t.players), "\(ok)") }
        let topBads: [[Int]] = [[6, 0, 0, 0], [-1, 0, 0, 0], [1, 1, 1]]
        for bad in topBads { XCTAssertThrowsError(try MPRules.finish(q, match: t.id, actor: tAuth, scores: bad, placement: t.players), "\(bad)") }
        XCTAssertThrowsError(try MPRules.finish(q, match: t.id, actor: tAuth, scores: [3, 3, 1, 0], placement: [t0, t1, t2, t2]))
        let topTwo = try MPRules.finish(q, match: t.id, actor: tAuth, scores: [2, 5, 4, 0], placement: [t1, t0, t2, t3])
        let topTable = try XCTUnwrap(topTwo.matches[t.id])
        XCTAssertEqual([t1, t0], MPKnockout.through(topTwo, 0, topTable))
        XCTAssertTrue(MPKnockout.goesThrough(topTwo, t, t0))
        XCTAssertEqual("You reached the final!", MPCompletionText.matchHeadline(topTwo, t, t0, hebrew: false))
        XCTAssertEqual(MPKnockout.eliminatedText(hebrew: false), MPCompletionText.matchHeadline(topTwo, t, t2, hebrew: false))
        // Winner takes all keeps exactly one player at the target; one through: no tie-break for a tied second place.
        let wRoom = try knockoutRoom(8, 4, .winnerTakesAll, 1, humans: 8, createdAt: 9)
        let wSession = try MPRules.start(wRoom, actor: "h0")
        let wm = try XCTUnwrap(MPKnockout.matches(wSession, 0).first)
        let wStarted = try startFixture(wSession, wm.id)
        let wq = wStarted.session
        let wAuth = wStarted.authority
        let wBads: [[Int]] = [[5, 5, 0, 0], [4, 3, 0, 0], [5, 2, 3, 0]]
        for bad in wBads { XCTAssertThrowsError(try MPRules.finish(wq, match: wm.id, actor: wAuth, scores: bad, placement: wm.players), "\(bad)") }
        let wDone = try MPRules.finish(wq, match: wm.id, actor: wAuth, scores: [5, 3, 3, 0], placement: wm.players)
        let wTable = try XCTUnwrap(wDone.matches[wm.id])
        let wWinner = try item(wm.players, 0)
        XCTAssertEqual([wWinner], MPKnockout.through(wDone, 0, wTable))
        XCTAssertTrue(MPKnockout.tiebreaks(wDone, 0).isEmpty)
    }

    // ---- Friendly tables and creation ----

    // Kotlin: friendlyTablesCarryTheirGameMode
    func testFriendlyTablesCarryTheirGameMode() throws {
        for size in 2...4 {
            for mode in MPGameMode.allCases {
                let created = createRoom("FRN234", .friendly, MPIdentity(id: "host", name: "Host"), 9, 1, 3, 0, 0, 5,
                                         format: .knockout, tableSize: size, gameMode: mode, advance: 1)
                XCTAssertEqual(size, created.capacity)
                XCTAssertEqual(MPTournamentFormat.roundRobin, created.format)
                XCTAssertEqual(2, created.advance)
                XCTAssertEqual(size == 2 ? MPGameMode.winnerTakesAll : mode, created.gameMode, "a pair plays the classic game")
                let createdWire = try encodeSession(created)
                XCTAssertEqual(created.gameMode != .winnerTakesAll, createdWire["gameMode"] != nil)
                XCTAssertNil(createdWire["advance"])
                try assertShapesRoundTrip(created, "\(size) \(mode.rawValue)")
            }
        }
        // A three-seat elimination table with two house players; the host's Start is their Ready (the table, then the duel).
        var room = createRoom("FRN234", .friendly, MPIdentity(id: "host", name: "Host"), 3, 1, 3, 0, 0, 5, tableSize: 3, gameMode: .elimination)
        for c in roster[1..<3] { room = try MPRules.addFriendlyHousePlayer(room, actor: "host", bot: houseParticipant(c, 1)) }
        var wider = room
        wider.capacity = 4
        wider.tableSize = 4
        XCTAssertThrowsError(try MPRules.addBot(wider, actor: "host", bot: houseParticipant(roster[1], 2)))     // a friendly seats a character once
        let active = try MPRules.start(onlineSession(room), actor: "host")
        XCTAssertEqual(1, active.matches.count)
        XCTAssertEqual(MPRules.schedule(onlineSession(room)), plainMatches(active.matches))                 // the start creates only the table
        let m = try onlyOne(Array(active.matches.values))
        XCTAssertEqual(MPMatchGoal.win, m.goal)
        XCTAssertEqual(MPGameMode.elimination, active.gameMode)
        let host = try item(m.players, 0), b1 = try item(m.players, 1), b2 = try item(m.players, 2)
        let playing = MPRules.startReady(MPRules.friendlyHouseReady(active, actor: "host"), match: m.id)
        XCTAssertEqual(MPMatchPhase.playing, playing.matches[m.id]?.phase)
        XCTAssertThrowsError(try MPRules.finish(playing, match: m.id, actor: "host", scores: [3, 6, 4], placement: [b1, b2, host]))
        // The host goes out first holding 3: the two house players' duel is simulated in the same transition and decides the game.
        var s = try MPRules.finish(playing, match: m.id, actor: "host", scores: [3, 5, 4], placement: [b1, b2, host])
        let houseDuel = try XCTUnwrap(s.matches[MPRules.duelId(m.id)])
        XCTAssertEqual([b1, b2], houseDuel.players)
        XCTAssertEqual(MPMatchPhase.finished, houseDuel.phase)
        XCTAssertEqual(0, houseDuel.starts)
        XCTAssertTrue(MPRules.validFinal(s, houseDuel, houseDuel.scores))
        XCTAssertEqual(houseDuel.winner, houseDuel.placement.first)
        XCTAssertTrue(s.complete)
        XCTAssertEqual("FINISHED", s.state)
        XCTAssertTrue(MPCompletionText.won(s, houseDuel.winner))
        XCTAssertFalse(MPCompletionText.won(s, host))
        let tableAfterHouseDuel = try XCTUnwrap(s.matches[m.id])
        XCTAssertTrue(MPCompletionText.matchHeadline(s, tableAfterHouseDuel, host, hebrew: false).hasSuffix(" won this match!"))
        XCTAssertEqual(s, MPRules.friendlyHouseReady(s, actor: "host"))
        // The host survives: the duel against a house player waits for the host's Start, and the room only finishes with it.
        s = try MPRules.finish(playing, match: m.id, actor: "host", scores: [4, 1, 3], placement: [host, b2, b1])
        let duelId = MPRules.duelId(m.id)
        let duel = try XCTUnwrap(s.matches[duelId])
        XCTAssertEqual([host, b2], duel.players)
        XCTAssertEqual(MPMatchPhase.waiting, duel.phase)
        XCTAssertFalse(s.complete)
        XCTAssertEqual("ACTIVE", s.state)
        XCTAssertEqual("host", s.authority(duel))
        XCTAssertEqual(s, MPRules.startReady(s, match: duelId))                                             // nobody is Ready yet
        let tableWithDuel = try XCTUnwrap(s.matches[m.id])
        XCTAssertEqual("You are in the final duel: the winner takes the game.", MPCompletionText.matchHeadline(s, tableWithDuel, host, hebrew: false))
        s = MPRules.friendlyHouseReady(s, actor: "host")
        XCTAssertEqual(Set(["host"]), s.matches[duelId]?.readySet)                                         // Start picks the duel
        XCTAssertEqual(s, MPRules.friendlyHouseReady(s, actor: "host"))
        s = MPRules.startReady(s, match: duelId)
        XCTAssertEqual(MPMatchPhase.playing, s.matches[duelId]?.phase)
        XCTAssertEqual(1, s.matches[duelId]?.starts)
        XCTAssertFalse(s.needsLobbyPresence("host"))
        XCTAssertEqual(s, MPRules.friendlyHouseReady(s, actor: "host"))
        s = try MPRules.finish(s, match: duelId, actor: "host", a: 5, b: 2)
        XCTAssertTrue(s.complete)
        XCTAssertEqual("FINISHED", s.state)
        XCTAssertTrue(MPCompletionText.won(s, host))
        XCTAssertEqual("You won the match!", MPCompletionText.headline(s, host, hebrew: false))
        let expectedRows = [MPStanding(id: host, played: 1, wins: 1, losses: 0, points: 0, pointsFor: 4),
                            MPStanding(id: b2, played: 1, wins: 0, losses: 1, points: 0, pointsFor: 3),
                            MPStanding(id: b1, played: 1, wins: 0, losses: 1, points: 0, pointsFor: 1)]
        XCTAssertEqual(expectedRows, MPRules.standings(s))                                                  // the table counts once
        // Winner takes all: ties among the others do not matter, and there is no duel.
        var tie = createRoom("FRN234", .friendly, MPIdentity(id: "host", name: "Host"), 3, 1, 3, 0, 0, 5, tableSize: 3)
        for c in roster[1..<3] { tie = try MPRules.addFriendlyHousePlayer(tie, actor: "host", bot: houseParticipant(c, 1)) }
        let tieStarted = try MPRules.start(onlineSession(tie), actor: "host")
        tie = MPRules.startReady(MPRules.friendlyHouseReady(tieStarted, actor: "host"), match: m.id)
        tie = try MPRules.finish(tie, match: m.id, actor: "host", scores: [5, 2, 2], placement: [host, b2, b1])
        XCTAssertTrue(tie.complete)
        XCTAssertEqual(1, tie.matches.count)
    }

    /// Kotlin `t(players, size, format, mode, advance)` of creationNormalisesCapacityGameModeAndAdvance.
    private func creationRoom(_ players: Int, _ size: Int, _ format: MPTournamentFormat, mode: MPGameMode = .elimination, advance: Int = 1) -> MPSession {
        createRoom("ELM234", .tournament, MPIdentity(id: "h", name: "H"), players, 2, 3, 0, 0, 5,
                   format: format, tableSize: size, gameMode: mode, advance: advance)
    }

    // Kotlin: creationNormalisesCapacityGameModeAndAdvance
    func testCreationNormalisesCapacityGameModeAndAdvance() {
        let ko = MPTournamentFormat.knockout
        let rr = MPTournamentFormat.roundRobin
        for size in 3...4 {
            XCTAssertEqual(3, creationRoom(1, size, ko).capacity)
            XCTAssertEqual(21, creationRoom(21, size, ko).capacity)
            XCTAssertEqual(32, creationRoom(99, size, ko).capacity)
            XCTAssertEqual(8, creationRoom(99, size, rr).capacity)
            XCTAssertEqual(1, creationRoom(9, size, ko, advance: 0).advance)
            XCTAssertEqual(1, creationRoom(9, size, ko, advance: 1).advance)
            XCTAssertEqual(2, creationRoom(9, size, ko, advance: 7).advance)
            XCTAssertEqual(2, creationRoom(9, size, rr, advance: 1).advance, "only a knockout sends players through")
            XCTAssertEqual(MPGameMode.elimination, creationRoom(9, size, ko).gameMode)
            XCTAssertEqual(MPGameMode.elimination, creationRoom(9, size, rr).gameMode)
            XCTAssertEqual(1, creationRoom(9, size, ko).legs)
        }
        // Classic pairs keep their sizes and the classic game.
        XCTAssertEqual(9, creationRoom(99, 2, ko).capacity)
        XCTAssertEqual(8, creationRoom(99, 2, rr).capacity)
        XCTAssertEqual(MPGameMode.winnerTakesAll, creationRoom(9, 2, ko).gameMode)
        XCTAssertEqual(2, creationRoom(9, 2, ko).advance)
        // The original call creates exactly what it did.
        let plain = createRoom("ELM234", .tournament, MPIdentity(id: "h", name: "H"), 9, 1, 3, 0, 0, 5, format: ko, tableSize: 4)
        XCTAssertEqual(MPGameMode.winnerTakesAll, plain.gameMode)
        XCTAssertEqual(2, plain.advance)
        var same = creationRoom(9, 4, ko, mode: .winnerTakesAll, advance: 2)
        same.legs = 1
        XCTAssertEqual(plain, same)
        XCTAssertEqual(32, MPKnockout.maxPlayers)
        XCTAssertEqual(9, MPKnockout.maxPairPlayers)
        XCTAssertEqual(16, MPKnockout.maxGroupRounds)
    }

    // ---- House players beyond the roster ----

    /// Every house player as "<characterId>:<name>", sorted.
    private func houseNames(_ s: MPSession) -> [String] {
        s.participants.values.filter { $0.bot != nil }.map { "\($0.bot?.characterId ?? ""):\($0.identity.name)" }.sorted()
    }

    // Kotlin: tournamentsRepeatHouseCharactersWithNumberedNames
    func testTournamentsRepeatHouseCharactersWithNumberedNames() throws {
        var s = createRoom("ELM234", .tournament, MPIdentity(id: "h0", name: "Host"), 21, 1, 3, 0, 0, 5, format: .knockout, tableSize: 4)
        s = try MPRules.addBot(s, actor: "h0", bot: houseParticipant(roster[2], 1))                         // Kyra chosen by hand first
        XCTAssertThrowsError(try MPRules.fillWithBots(s, actor: "h1"))
        var active = s
        active.state = "ACTIVE"
        XCTAssertThrowsError(try MPRules.fillWithBots(active, actor: "h0"))
        // iOS fillWithBots has no `make` closure to record (character, copy): one seat more per call reads its order back.
        var copies: [String] = []
        var stepwise = s
        while stepwise.participants.count < s.capacity {
            var oneMore = stepwise
            oneMore.capacity = stepwise.participants.count + 1
            let next = try MPRules.fillWithBots(oneMore, actor: "h0")
            let added = next.participants.values.filter { oneMore.participants[$0.id] == nil }
            XCTAssertEqual(1, added.count)
            guard let newcomer = added.first, let character = newcomer.bot?.characterId else { break }
            copies.append("\(character):\(MPRules.copyNumber(oneMore, character))")
            stepwise = next
        }
        let filled = try MPRules.fillWithBots(s, actor: "h0")
        XCTAssertEqual(houseNames(stepwise), houseNames(filled))
        s = filled
        XCTAssertEqual(21, s.participants.count)
        // Characters not yet there come first in roster order, then repeats, always the one with the fewest copies.
        let fresh = roster.map { $0.id }.filter { $0 != "kyra" }
        let repeats = ["minik", "flare", "kyra", "gaya", "mia", "amber", "comet", "june", "moshiko"]
        XCTAssertEqual(fresh.map { "\($0):1" } + repeats.map { "\($0):2" }, copies)
        let byId = s.participants
        XCTAssertEqual("Kyra", byId["bot_kyra_1"]?.identity.name)
        let kyra2 = try XCTUnwrap(byId.values.first(where: { $0.bot?.characterId == "kyra" && $0.id != "bot_kyra_1" }))
        XCTAssertEqual("Kyra 2", kyra2.identity.name)
        XCTAssertEqual(["Bouncy Bob", "Bouncy Bob 2"], byId.values.filter { $0.bot?.characterId == "moshiko" }.map { $0.identity.name }.sorted())
        let moshiko2 = try XCTUnwrap(byId.values.first(where: { $0.bot?.characterId == "moshiko" && $0.identity.name != "Bouncy Bob" }))
        XCTAssertEqual("Bouncy Bob 2", moshiko2.identity.name)
        XCTAssertEqual("ספיר 2", kyra2.name(hebrew: true))
        XCTAssertEqual("Kyra 2", kyra2.name(hebrew: false))
        XCTAssertEqual("ספיר", byId["bot_kyra_1"]?.name(hebrew: true))
        XCTAssertEqual("מושיקו 2", moshiko2.name(hebrew: true))
        XCTAssertEqual(s, try MPRules.fillWithBots(s, actor: "h0"))
        let decoded = try decodeSession(try encodeSession(s))
        XCTAssertEqual(plainSession(s), plainSession(decoded))
        // The next free number: a removed copy's number is reused; names stay within 18 characters.
        let minik2 = try XCTUnwrap(s.participants.values.first(where: { $0.bot?.characterId == "minik" && $0.identity.name == "Minik 2" }))
        var gone = s
        gone.participants[minik2.id] = nil
        XCTAssertEqual(2, MPRules.copyNumber(gone, "minik"))
        XCTAssertEqual(3, MPRules.copyNumber(s, "minik"))
        XCTAssertEqual(1, MPRules.copyNumber(s, ""))
        let again = try MPRules.addBot(gone, actor: "h0", bot: MPParticipant(identity: MPIdentity(id: "bot_x", name: "Minik"), bot: roster[0].profile))
        XCTAssertEqual("Minik 2", again.participants["bot_x"]?.identity.name)
        let long = MPBot(speed: 5, reaction: 5, accuracy: 5, power: 5, agility: 5, characterId: "custom_long", forehandSkill: 5, backhandSkill: 5, serveSkill: 5)
        let firstLong = MPParticipant(identity: MPIdentity(id: "bot_l1", name: "A very long house name"), bot: long)
        let smallRoom = createRoom("ELM234", .tournament, MPIdentity(id: "h0", name: "Host"), 4, 1, 3, 0, 0, 5)
        var custom = try MPRules.addBot(smallRoom, actor: "h0", bot: firstLong)
        var secondLong = firstLong
        secondLong.identity = MPIdentity(id: "bot_l2", name: "A very long house name")
        custom = try MPRules.addBot(custom, actor: "h0", bot: secondLong)
        XCTAssertEqual("A very long hous 2", custom.participants["bot_l2"]?.identity.name)
        XCTAssertEqual("A very long hous 2", custom.participants["bot_l2"]?.name(hebrew: true))           // unknown characters keep their name
        // 32 players: every character twice, nine three times; the knockout plays to a champion on one phone.
        let bigRoom = createRoom("BGT234", .tournament, MPIdentity(id: "h0", name: "Host"), 40, 1, 3, 0, 0, 5, format: .knockout, tableSize: 4)
        let swiftBig = try MPRules.fillWithBots(bigRoom, actor: "h0")
        XCTAssertEqual(32, swiftBig.participants.count)
        let perCharacter = roster.map { c in swiftBig.participants.values.filter { $0.bot?.characterId == c.id }.count }
        XCTAssertEqual([3, 3, 3, 3, 3, 3, 3, 3, 3, 2, 2], perCharacter)
        XCTAssertEqual(["Minik", "Minik 2", "Minik 3"], swiftBig.participants.values.filter { $0.bot?.characterId == "minik" }.map { $0.identity.name }.sorted())
        XCTAssertEqual(swiftBig.participants.count, Set(swiftBig.participants.values.map { $0.name(hebrew: false) }).count, "every player has a distinct name")
        // Kotlin's `::house` ids ("bot_<character>_<copy>") replay Android's draws; same characters and names as iOS fillWithBots.
        var big = try fillHouse(bigRoom, "h0")
        XCTAssertEqual(houseNames(swiftBig), houseNames(big))
        XCTAssertEqual("Minik 3", big.participants["bot_minik_3"]?.identity.name)
        big = try MPRules.start(onlineSession(big), actor: "h0")
        var guardCount = 0
        while !big.complete {
            guardCount += 1
            guard guardCount < 500, let m = openFixtures(big).first else { XCTFail("no open fixture: 32 on one phone"); break }
            var rng = MPKotlinRandom(seed: m.seed)
            big = try playFixture(big, m.id, fixtureResult(big, m, &rng))
        }
        try verifyKnockout(big, "32 on one phone")
        // Plain house players without a character are never numbered; friendlies still seat a character once.
        let plainBot = MPBot(speed: 5, reaction: 5, accuracy: 5, power: 5, agility: 5, characterId: "", forehandSkill: 5, backhandSkill: 5, serveSkill: 5)
        let genericRoom = createRoom("ELM234", .tournament, MPIdentity(id: "h0", name: "Host"), 4, 1, 3, 0, 0, 5)
        let genericOne = try MPRules.addBot(genericRoom, actor: "h0", bot: MPParticipant(identity: MPIdentity(id: "bot_g1", name: "House"), bot: plainBot))
        let generic = try MPRules.addBot(genericOne, actor: "h0", bot: MPParticipant(identity: MPIdentity(id: "bot_g2", name: "House"), bot: plainBot))
        XCTAssertEqual(["House", "House"], generic.participants.values.filter { $0.bot != nil }.map { $0.identity.name })
        let friendlyRoom = createRoom("FRN234", .friendly, MPIdentity(id: "h0", name: "Host"), 4, 1, 3, 0, 0, 5, tableSize: 4)
        let friendly = try MPRules.addFriendlyHousePlayer(friendlyRoom, actor: "h0", bot: houseParticipant(roster[2], 1))
        XCTAssertThrowsError(try MPRules.addFriendlyHousePlayer(friendly, actor: "h0", bot: houseParticipant(roster[2], 2)))
        XCTAssertThrowsError(try MPRules.fillWithBots(friendly, actor: "h0"))
    }

    // ---- Wire ----

    // Kotlin: newFieldsRoundTripAndOlderRecordsReadAsTheDefaults
    func testNewFieldsRoundTripAndOlderRecordsReadAsTheDefaults() throws {
        // Set values are written and read back in every stored shape; the defaults are not written at all.
        let kRoom = try knockoutRoom(5, 4, .elimination, 2, humans: 5, createdAt: 4)
        let k = try MPRules.start(kRoom, actor: "h0")
        let wire = try encodeSession(k)
        XCTAssertEqual("ELIMINATION", wire["gameMode"] as? String)
        XCTAssertNil(wire["advance"])
        let kMatches = MPCodec.map(wire["matches"])
        XCTAssertEqual(1, kMatches.count)
        XCTAssertEqual("TOP_TWO", MPCodec.map(kMatches.values.first)["goal"] as? String)
        try assertShapesRoundTrip(k)
        let oneRoom = try knockoutRoom(9, 3, .winnerTakesAll, 1, humans: 9, createdAt: 4)
        let one = try MPRules.start(oneRoom, actor: "h0")
        let w1 = try encodeSession(one)
        XCTAssertEqual(1, w1["advance"] as? Int)
        XCTAssertNil(w1["gameMode"])
        XCTAssertTrue(MPCodec.map(w1["matches"]).values.allSatisfy { MPCodec.map($0)["goal"] == nil })
        XCTAssertTrue(MPCodec.map(w1["rounds"]).values.allSatisfy { MPCodec.map($0)["walkovers"] == nil })
        try assertShapesRoundTrip(one)
        // A record without the new keys reads as winner takes all, two through, every fixture for one winner.
        var stripped = wire
        stripped["gameMode"] = nil
        var strippedMatches: [String: Any] = [:]
        for (id, value) in MPCodec.map(wire["matches"]) {
            var m = MPCodec.map(value)
            m["goal"] = nil
            strippedMatches[id] = m
        }
        stripped["matches"] = strippedMatches
        var strippedRounds: [String: Any] = [:]
        for (id, value) in MPCodec.map(wire["rounds"]) {
            var r = MPCodec.map(value)
            r["walkovers"] = nil
            strippedRounds[id] = r
        }
        stripped["rounds"] = strippedRounds
        let old = try decodeSession(stripped)
        XCTAssertEqual(MPGameMode.winnerTakesAll, old.gameMode)
        XCTAssertEqual(2, old.advance)
        XCTAssertTrue(old.matches.values.allSatisfy { $0.goal == .win })
        XCTAssertTrue(old.rounds.values.allSatisfy { $0.walkovers.isEmpty })
        var advanceNine = wire
        advanceNine["advance"] = 9
        XCTAssertEqual(2, try decodeSession(advanceNine).advance)
        var advanceNegative = wire
        advanceNegative["advance"] = -3
        XCTAssertEqual(1, try decodeSession(advanceNegative).advance)
        var unknownMode = wire
        unknownMode["gameMode"] = "SOMETHING_NEW"
        XCTAssertEqual(MPGameMode.winnerTakesAll, try decodeSession(unknownMode).gameMode)
        let unknownGoalWire: [String: Any] = ["id": "m", "players": ["a", "b", "c"], "goal": "UNKNOWN"]
        let unknownGoal = try MPCodec.decode(MPFixture.self, unknownGoalWire)
        XCTAssertEqual(MPMatchGoal.win, unknownGoal.goal)
        // A knockout saved by the previous version (a table of four and a bye for five players) still plays to its champion.
        var people: [String: MPParticipant] = [:]
        for uid in ["a", "b", "c", "d", "e"] { people[uid] = MPParticipant(identity: MPIdentity(id: uid, name: uid.uppercased())) }
        let table = MPFixture(id: "LGC234_K0_0", players: ["a", "b", "c", "d"], seed: 11)
        var legacy = rawRoom("LGC234", .tournament, "a")
        legacy.capacity = 5
        legacy.target = 5
        legacy.participants = people
        legacy.matches = [table.id: table]
        var connections: [String: [String: Bool]] = [:]
        for uid in people.keys { connections[uid] = ["0": true] }
        legacy.connections = connections
        legacy.state = "ACTIVE"
        legacy.format = .knockout
        legacy.rounds = [0: MPKnockoutRound(players: ["a", "b", "c", "d", "e"], groups: [["a", "b", "c", "d"]], byes: ["e"])]
        legacy.tableSize = 4
        let stored = try encodeSession(legacy)
        for key in ["gameMode", "advance"] { XCTAssertNil(stored[key], key) }
        let loaded = try decodeSession(firebaseShape(stored, lists: true))
        XCTAssertEqual(plainSession(legacy), plainSession(loaded))
        XCTAssertEqual(["e"], loaded.rounds[0]?.resting)
        XCTAssertEqual(MPMatchGoal.win, loaded.matches[table.id]?.goal)
        XCTAssertEqual("You have a bye to the next round. Waiting for the other tables.", MPKnockout.playerStatus(loaded, "e", hebrew: false))
        var next = try playFixture(loaded, table.id, [5, 3, 1, 0], ["a", "b", "c", "d"])
        XCTAssertEqual(Set(["a", "b", "e"]), Set(next.rounds[1]?.players ?? []))
        XCTAssertTrue(next.rounds[1]?.isFinal == true)
        let fin = try onlyOne(MPKnockout.matches(next, 1))
        let f0 = try item(fin.players, 0), f1 = try item(fin.players, 1), f2 = try item(fin.players, 2)
        next = try playFixture(next, fin.id, [5, 0, 1], [f0, f2, f1])
        XCTAssertTrue(next.complete)
        XCTAssertEqual(f0, MPKnockout.winner(next))
    }

    // ---- Round robin ----

    // Kotlin: roundRobinTablesInEliminationModeScorePlacementPointsAfterTheirFinalDuels
    func testRoundRobinTablesInEliminationModeScorePlacementPointsAfterTheirFinalDuels() throws {
        var rng = MPKotlinRandom(intSeed: 12)
        for size in 3...4 {
            for humans in [1, 2] {
                let ctx = "tables of \(size), \(humans) humans"
                var s = createRoom("RRB234", .tournament, MPIdentity(id: "h0", name: "Host"), 6, 2, 3, 0, 0, 5,
                                   format: .roundRobin, tableSize: size, gameMode: .elimination)
                s.createdAt = 3
                if humans == 2 { s = try MPRules.join(s, MPIdentity(id: "h1", name: "One")) }
                s = try fillHouse(s, "h0")
                s = try MPRules.start(onlineSession(s), actor: "h0")
                let scheduled = MPGroupTournament.schedule(s)
                let started = s
                let houseTables = scheduled.values.filter { MPRules.houseOnly(started, $0) }
                if humans == 1 { XCTAssertFalse(houseTables.isEmpty, ctx) }
                for m in scheduled.values { XCTAssertEqual(MPMatchGoal.win, m.goal, ctx) }
                // House-only tables and their house-only duels finish in the start transition.
                for t in houseTables {
                    let m = try XCTUnwrap(s.matches[t.id], ctx)
                    let duel = try XCTUnwrap(MPRules.duelOf(s, m), ctx)
                    XCTAssertEqual(MPMatchPhase.finished, m.phase, ctx)
                    XCTAssertTrue(MPRules.validFinal(s, m, m.scores) && MPRules.validPlacement(s, m, m.scores, m.placement), ctx)
                    XCTAssertEqual(Array(m.placement.prefix(2)), duel.players, ctx)
                    XCTAssertEqual(MPMatchPhase.finished, duel.phase, ctx)
                    XCTAssertEqual(0, duel.starts, ctx)
                    XCTAssertTrue(MPRules.validFinal(s, duel, duel.scores), ctx)
                    XCTAssertEqual(s.target, duel.scoreOf(duel.winner), ctx)
                }
                var guardCount = 0
                while !openFixtures(s).isEmpty {
                    guardCount += 1
                    guard guardCount < 500, let m = openFixtures(s).first else { XCTFail("stuck: \(ctx)"); break }
                    let before = MPRules.standings(s)
                    s = try playFixture(s, m.id, fixtureResult(s, m, &rng))
                    // A table whose final duel is still open counts for nobody yet.
                    if !MPRules.isDuel(m), let now = s.matches[m.id], MPRules.duelOf(s, now)?.terminal == false {
                        XCTAssertEqual(before, MPRules.standings(s), ctx)
                    }
                }
                XCTAssertTrue(s.complete, ctx)
                XCTAssertEqual("FINISHED", s.state, ctx)
                let tables = s.matches.values.filter { $0.phase == .finished && !MPRules.isDuel($0) }
                let rows = MPRules.standings(s)
                XCTAssertEqual(Set(scheduled.keys), Set(tables.map { $0.id }), ctx)
                XCTAssertEqual(Set(tables.map { MPRules.duelId($0.id) }), Set(s.matches.keys).subtracting(scheduled.keys), ctx)
                // Placement points: the duel's winner first, its loser second, then the others as the table stored them.
                var ranking: [String: [String]] = [:]
                for m in tables {
                    let duel = try XCTUnwrap(MPRules.duelOf(s, m), ctx)
                    ranking[m.id] = [duel.winner] + duel.players.filter { $0 != duel.winner } + Array(m.placement.dropFirst(2))
                }
                var points: [String: Int] = [:], wins: [String: Int] = [:], played: [String: Int] = [:]
                for uid in s.participants.keys {
                    var total = 0, first = 0, count = 0
                    for m in tables where m.players.contains(uid) {
                        let order = ranking[m.id] ?? []
                        if let place = order.firstIndex(of: uid), place < MPGroupTournament.placePoints.count { total += MPGroupTournament.placePoints[place] }
                        if order.first == uid { first += 1 }
                        count += 1
                    }
                    points[uid] = total
                    wins[uid] = first
                    played[uid] = count
                }
                var rowPoints: [String: Int] = [:], rowWins: [String: Int] = [:], rowPlayed: [String: Int] = [:]
                var rowTotal = 0
                for row in rows {
                    rowPoints[row.id] = row.points
                    rowWins[row.id] = row.wins
                    rowPlayed[row.id] = row.played
                    rowTotal += row.points
                }
                XCTAssertEqual(points, rowPoints, ctx)
                XCTAssertEqual(wins, rowWins, ctx)
                XCTAssertEqual(played, rowPlayed, ctx)
                var tableTotal = 0
                for m in tables {
                    for value in MPGroupTournament.placePoints.prefix(m.players.count) { tableTotal += value }
                }
                XCTAssertEqual(tableTotal, rowTotal, ctx)
                let leader = try XCTUnwrap(rows.first, ctx)
                XCTAssertTrue(MPCompletionText.won(s, leader.id), ctx)
            }
        }
    }

    // ---- Texts ----

    // Kotlin: gameModeKnockoutAndResultTextsInBothLanguages
    func testGameModeKnockoutAndResultTextsInBothLanguages() throws {
        XCTAssertEqual("Winner takes all", MPGameMode.winnerTakesAll.title(false))
        XCTAssertEqual("המנצח לוקח הכל", MPGameMode.winnerTakesAll.title(true))
        XCTAssertEqual("Elimination", MPGameMode.elimination.title(false))
        XCTAssertEqual("הדחה", MPGameMode.elimination.title(true))
        for he in [false, true] {
            let texts = MPGameMode.allCases.map { $0.explanation(he) }
            XCTAssertEqual(2, Set(texts).count)
            XCTAssertTrue(texts.allSatisfy { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !$0.contains("\n") })
        }
        XCTAssertEqual("Round of 16", MPGroupTournament.stage(16, 4, hebrew: false, advance: 2))
        XCTAssertEqual("Semifinal tables", MPGroupTournament.stage(16, 4, hebrew: false, advance: 1))
        XCTAssertEqual("שולחנות חצי הגמר", MPGroupTournament.stage(8, 4, hebrew: true, advance: 2))
        XCTAssertEqual("Final", MPGroupTournament.stage(2, 3, hebrew: false, advance: 1))
        let rules: [(mode: MPGameMode, advance: Int, rule: String, table: String)] = [
            (.winnerTakesAll, 2, "The top two of every table advance; a tie for second place is settled by a one-point tie-break.", "the top two advance"),
            (.winnerTakesAll, 1, "The winner of every table advances.", "the winner advances"),
            (.elimination, 2, "The last two players left at every table advance.", "the last two left advance"),
            (.elimination, 1, "At every table the last two left play a final duel; its winner advances.", "the final duel's winner advances")]
        for entry in rules {
            let room = try knockoutRoom(8, 4, entry.mode, entry.advance, humans: 8, createdAt: 2)
            let s = try MPRules.start(room, actor: "h0")
            XCTAssertEqual(entry.rule, MPKnockout.rule(s, hebrew: false))
            XCTAssertFalse(MPKnockout.rule(s, hebrew: true).trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            XCTAssertEqual("Your table this round: \(entry.table).", MPKnockout.playerStatus(s, "h0", hebrew: false))
            XCTAssertEqual("Semifinal tables", MPKnockout.stage(s, hebrew: false))
        }
        let wtaOne = try MPRules.start(try knockoutRoom(8, 4, .winnerTakesAll, 1, humans: 8), actor: "h0")
        XCTAssertEqual("השולחן שלכם בסיבוב הזה: רק המקום הראשון עולה.", MPKnockout.playerStatus(wtaOne, "h0", hebrew: true))
        let elimOne = try MPRules.start(try knockoutRoom(8, 4, .elimination, 1, humans: 8), actor: "h0")
        XCTAssertEqual("השולחן שלכם בסיבוב הזה: הניצחון בקרב הגמר מעלה לסיבוב הבא.", MPKnockout.playerStatus(elimOne, "h0", hebrew: true))
        let elimTwo = try MPRules.start(try knockoutRoom(8, 4, .elimination, 2, humans: 8), actor: "h0")
        XCTAssertEqual("השולחן שלכם בסיבוב הזה: שני האחרונים שנשארים עולים.", MPKnockout.playerStatus(elimTwo, "h0", hebrew: true))
        let finalRoom = try MPRules.start(try knockoutRoom(4, 4, .elimination, 2, humans: 4), actor: "h0")
        XCTAssertEqual("The last two left at the final table play the final duel for the tournament.", MPKnockout.rule(finalRoom, hebrew: false))
        XCTAssertEqual("Final", MPKnockout.stage(finalRoom, hebrew: false))
        XCTAssertEqual("Your table this round: the winner takes the tournament.", MPKnockout.playerStatus(finalRoom, "h0", hebrew: false))
        let waitingFinal = try knockoutRoom(4, 3, .winnerTakesAll, 1, humans: 4)
        XCTAssertEqual("The winner of the final table takes the tournament.", MPKnockout.rule(waitingFinal, hebrew: false))
        XCTAssertEqual("Final duel", MPMatchText.duelTitle(hebrew: false))
        XCTAssertEqual("קרב גמר", MPMatchText.duelTitle(hebrew: true))
        XCTAssertEqual("קרב גמר", MPMatchText.label(MPFixture(id: "X_K0_0_D", players: ["a", "b"], seed: 1), hebrew: true))
        XCTAssertNil(MPMatchText.label(MPFixture(id: "X_K0_0", players: ["a", "b", "c"], seed: 1), hebrew: false))
        XCTAssertEqual("Tie-break for the last place", MPMatchText.label(MPFixture(id: "X_K0_0_T", players: ["a", "b"], seed: 1, goal: .tiebreak), hebrew: false))
        let pairKnockout = createRoom("ELM234", .tournament, MPIdentity(id: "h0", name: "Host"), 8, 1, 3, 0, 0, 5, format: .knockout)
        XCTAssertEqual("The winner of every match advances.", MPKnockout.rule(pairKnockout, hebrew: false))
        XCTAssertEqual("Tie-break for the last place", MPKnockout.tiebreakTitle(hebrew: false))
        XCTAssertEqual("שובר שוויון על המקום האחרון", MPKnockout.tiebreakTitle(hebrew: true))
        // A table result's headline in a friendly and in a knockout.
        var fRoom = createRoom("FRN234", .friendly, MPIdentity(id: "host", name: "Host"), 3, 1, 3, 0, 0, 5, tableSize: 3)
        fRoom = try MPRules.join(fRoom, MPIdentity(id: "b", name: "B"))
        fRoom = try MPRules.addFriendlyHousePlayer(fRoom, actor: "host", bot: houseParticipant(roster[1], 1))
        let f = try MPRules.start(onlineSession(fRoom), actor: "host")
        let fm = try onlyOne(Array(f.matches.values))
        let fStarted = try startFixture(f, fm.id)
        let fHouse = try item(fm.players, 2)
        let fdone = try MPRules.finish(fStarted.session, match: fm.id, actor: fStarted.authority, scores: [1, 5, 0], placement: ["b", "host", fHouse])
        let fTable = try XCTUnwrap(fdone.matches[fm.id])
        XCTAssertEqual("You won the match!", MPCompletionText.matchHeadline(fdone, fTable, "b", hebrew: false))
        XCTAssertTrue(MPCompletionText.matchHeadline(fdone, fTable, "host", hebrew: true).hasPrefix("כל הכבוד ל־"))
    }
}
