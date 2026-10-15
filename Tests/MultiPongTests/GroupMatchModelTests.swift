import XCTest
@testable import MinikMultiPingPong
import CoreGraphics
import CoreText

// Android app/src/test/.../multiplayer/GroupMatchModelTest.kt (MinikCrossPong 828c6fc).
// N-player match model: one fixture per table, seats, Ready/start, authority, results, simulation, wire.

/// Collects `MPTableSimulation.play` trace rallies (the trace closure escapes).
private final class GroupMatchRallyLog {
    var items: [MPTableSimulation.Rally] = []
}

final class GroupMatchModelTests: XCTestCase {
    /// Kotlin `listOf("flare","kyra","gaya","mia").map { BotRoster.selected(it) }`.
    private let house: [MPHousePlayer] = ["flare", "kyra", "gaya", "mia"].map { MPRoster.find($0) ?? MPRoster.all[0] }

    private func bot(_ i: Int) -> MPParticipant {
        MPParticipant(identity: MPIdentity(id: "bot_\(house[i].id)", name: house[i].english), bot: house[i].profile)
    }

    /// Kotlin `PongRules.create(code, kind, host, capacity, legs, win, loss, difficulty, target, format, tableSize)`: the
    /// MPSession initializer (which takes no loss points) with Kotlin's creation and activity time 0.
    private func createRoom(_ code: String, _ kind: MPSessionKind, _ host: MPIdentity, _ capacity: Int, _ legs: Int, _ win: Int,
                            _ loss: Int, _ difficulty: Int, _ target: Int, format: MPTournamentFormat = .roundRobin,
                            tableSize: Int = 2) -> MPSession {
        var s = MPSession(code: code, kind: kind, host: host, capacity: capacity, legs: legs, winPoints: win, difficulty: difficulty,
                          target: target, format: format, tableSize: tableSize)
        s.lossPoints = min(10, max(0, loss))
        s.createdAt = 0
        s.lastActivityAt = 0
        return s
    }

    /// Kotlin `Session(code, kind, host, capacity)` with every other field at its data-class default (MPSession has no
    /// memberwise initializer).
    private func bareSession(_ code: String, _ kind: MPSessionKind, _ host: String, capacity: Int = 2) -> MPSession {
        var s = MPSession(code: code, kind: kind, host: MPIdentity(id: host, name: host))
        s.capacity = capacity; s.legs = 1; s.winPoints = 3; s.lossPoints = 0; s.difficulty = 0; s.target = 7
        s.participants = [:]; s.matches = [:]; s.connections = [:]; s.departed = [:]
        s.state = "WAITING"; s.createdAt = 0; s.lastActivityAt = 0
        s.format = .roundRobin; s.rounds = [:]; s.tableSize = 2; s.seats = [:]; s.gameMode = .winnerTakesAll; s.advance = 2
        return s
    }

    /// Friendly table: host "host" at seat 0, then joining humans, then house players; humans online.
    private func room(_ size: Int, _ humans: [String] = [], bots: Int = 0, difficulty: Int = 0) throws -> MPSession {
        var s = createRoom("ABC234", .friendly, MPIdentity(id: "host", name: "GreenFrog"), 2, 1, 3, 0, difficulty, 5, tableSize: size)
        for uid in humans { s = try MPRules.join(s, MPIdentity(id: uid, name: "Player \(uid)")) }
        for i in 0..<bots { s = try MPRules.addFriendlyHousePlayer(s, actor: "host", bot: bot(i)) }
        var connections: [String: [String: Bool]] = [:]
        for (id, p) in s.participants where p.bot == nil { connections[id] = ["0": true] }
        s.connections = connections
        return s
    }

    private func only(_ s: MPSession, file: StaticString = #filePath, line: UInt = #line) throws -> MPFixture {
        XCTAssertEqual(1, s.matches.count, file: file, line: line)
        return try XCTUnwrap(s.matches.values.first, file: file, line: line)
    }

    private func play(_ s: MPSession) throws -> MPSession {
        let m = try only(s)
        var next = s
        for uid in m.players where s.human(uid) { next = try MPRules.ready(next, match: m.id, uid: uid, value: true) }
        return MPRules.startReady(next, match: m.id)
    }

    /// A Kotlin Long literal (`99L`) as Firebase hands it back: an NSNumber.
    private func wireLong(_ value: Int64) -> NSNumber { NSNumber(value: value) }

    /// Kotlin `PongCodec.session(s)`.
    private func encodeRoom(_ s: MPSession) throws -> MPWire { try MPCodec.session(s) }
    /// Kotlin `PongCodec.session(wire)`.
    private func decodeRoom(_ value: Any?) throws -> MPSession { try MPCodec.session(value) }
    private func roundTrip(_ s: MPSession) throws -> MPSession { try decodeRoom(try encodeRoom(s)) }

    // Kotlin: friendlyTablesSeatThreeOrFourPlayersAndRefuseLateJoins
    func testFriendlyTablesSeatThreeOrFourPlayersAndRefuseLateJoins() throws {
        for size in 3...4 {
            var s = try room(size)
            XCTAssertEqual(size, s.capacity)
            XCTAssertEqual(size, s.tableSize)
            XCTAssertEqual(["host": 0], s.seats)
            let guests = Array(["b", "c", "d"].prefix(size - 1))
            XCTAssertThrowsError(try MPRules.start(s, actor: "host"))
            for (i, uid) in guests.enumerated() {
                XCTAssertTrue(MPRules.acceptsNewPlayer(s))
                s = try MPRules.join(s, MPIdentity(id: uid, name: uid))
                XCTAssertEqual(i + 1, s.seats[uid])
            }
            XCTAssertEqual(size, s.participants.count)
            XCTAssertFalse(MPRules.acceptsNewPlayer(s))
            XCTAssertThrowsError(try MPRules.join(s, MPIdentity(id: "z", name: "Z")))
            let renamed = try MPRules.join(s, MPIdentity(id: "b", name: "Renamed"))
            XCTAssertEqual("Renamed", renamed.participants["b"]?.identity.name)
            XCTAssertEqual(s.seats, renamed.seats)
            let started = try MPRules.start(s, actor: "host")
            XCTAssertEqual("ACTIVE", started.state)
            XCTAssertEqual(1, started.matches.count)
            let m = try only(started)
            XCTAssertEqual("ABC234_0_0_1", m.id)
            XCTAssertEqual(["host"] + guests, m.players)
            XCTAssertEqual(Array(repeating: 0, count: size), m.scores)
            XCTAssertEqual(MPMatchPhase.waiting, m.phase)
            XCTAssertTrue(m.placement.isEmpty)
            let restarted = try MPRules.start(started, actor: "host")
            XCTAssertEqual(started, restarted)
            XCTAssertThrowsError(try MPRules.join(started, MPIdentity(id: "z", name: "Z")))
            let lateRename = try MPRules.join(started, MPIdentity(id: "b", name: "Late rename"))
            XCTAssertEqual(started, lateRename)
            XCTAssertFalse(MPRules.acceptsNewPlayer(started))
        }
    }

    // Kotlin: tableSizesAreClampedAndTournamentTablesSeatTheDecidedTwoToFourPlayers
    func testTableSizesAreClampedAndTournamentTablesSeatTheDecidedTwoToFourPlayers() {
        func friendlyRoom(_ size: Int) -> MPSession {
            createRoom("ABC234", .friendly, MPIdentity(id: "h", name: "H"), 9, 1, 3, 0, 0, 5, tableSize: size)
        }
        XCTAssertEqual(2, friendlyRoom(1).tableSize)
        XCTAssertEqual(4, friendlyRoom(9).tableSize)
        XCTAssertEqual(4, friendlyRoom(9).capacity)
        XCTAssertEqual(2, createRoom("ABC234", .friendly, MPIdentity(id: "h", name: "H"), 4, 1, 3, 0, 0, 5).capacity)
        // The user decided the 3/4-player tournament rules (MPGroupTournament): a tournament keeps its table size.
        XCTAssertEqual(4, MPGroupTournament.maxTable)
        for format in MPTournamentFormat.allCases {
            for size in 2...4 {
                let t = createRoom("ABC234", .tournament, MPIdentity(id: "h", name: "H"), 6, 1, 3, 0, 0, 5, format: format, tableSize: size)
                XCTAssertEqual(size, t.tableSize)
                XCTAssertEqual(size > 2, t.grouped)
                XCTAssertEqual(6, t.capacity)
                XCTAssertTrue(t.seats.isEmpty)
            }
        }
        for format in MPTournamentFormat.allCases {
            func tournamentRoom(_ players: Int, _ size: Int) -> MPSession {
                createRoom("ABC234", .tournament, MPIdentity(id: "h", name: "H"), players, 1, 3, 0, 0, 5, format: format, tableSize: size)
            }
            XCTAssertEqual(2, tournamentRoom(6, 1).tableSize)
            XCTAssertEqual(4, tournamentRoom(6, 9).tableSize)
            XCTAssertFalse(tournamentRoom(6, 1).grouped)
            XCTAssertEqual(2, tournamentRoom(1, 2).capacity)
            XCTAssertEqual(3, tournamentRoom(1, 3).capacity)
            XCTAssertEqual(3, tournamentRoom(2, 4).capacity)
            // User rule: a knockout at tables of 3 or 4 takes 3..32 players; classic pairs keep 2..9, a round robin 3..8.
            let knockout = format == .knockout
            XCTAssertEqual(knockout ? 9 : 8, tournamentRoom(12, 2).capacity)
            for size in 3...4 {
                XCTAssertEqual(knockout ? 12 : 8, tournamentRoom(12, size).capacity)
                XCTAssertEqual(knockout ? 32 : 8, tournamentRoom(40, size).capacity)
            }
        }
    }

    // Kotlin: aHumanMovesOnlyThemselvesIntoAFreeSeatBeforeTheStart
    func testAHumanMovesOnlyThemselvesIntoAFreeSeatBeforeTheStart() throws {
        var s = try MPRules.join(room(4), MPIdentity(id: "b", name: "B"))
        s = try MPRules.chooseSeat(s, actor: "b", seat: 3)
        XCTAssertEqual(["host": 0, "b": 3], s.seating())
        let same = try MPRules.chooseSeat(s, actor: "b", seat: 3)
        XCTAssertEqual(s, same)
        XCTAssertThrowsError(try MPRules.chooseSeat(s, actor: "b", seat: 0))                           // the host's seat
        for bad in [-1, 4] { XCTAssertThrowsError(try MPRules.chooseSeat(s, actor: "b", seat: bad)) }
        XCTAssertThrowsError(try MPRules.chooseSeat(s, actor: "outsider", seat: 1))
        s = try MPRules.chooseSeat(s, actor: "host", seat: 2)
        s = try MPRules.join(s, MPIdentity(id: "c", name: "C"))
        XCTAssertEqual(0, s.seats["c"])
        s = try MPRules.addFriendlyHousePlayer(s, actor: "host", bot: bot(0))
        XCTAssertEqual(1, s.seats[bot(0).id])
        XCTAssertThrowsError(try MPRules.chooseSeat(s, actor: bot(0).id, seat: 1))                     // house players do not choose; nobody moves them
        XCTAssertTrue(s.freeSeats().isEmpty)
        let started = try MPRules.start(s, actor: "host")
        XCTAssertEqual(["c", bot(0).id, "host", "b"], try only(started).players)
        XCTAssertThrowsError(try MPRules.chooseSeat(started, actor: "c", seat: 3))
        var waitingAgain = started
        waitingAgain.state = "WAITING"
        XCTAssertThrowsError(try MPRules.chooseSeat(waitingAgain, actor: "c", seat: 3))                // a fixture exists
        let tournament = createRoom("ABC234", .tournament, MPIdentity(id: "host", name: "H"), 4, 1, 3, 0, 0, 5)
        XCTAssertThrowsError(try MPRules.chooseSeat(tournament, actor: "host", seat: 1))
    }

    // Kotlin: theHostPlacesHousePlayersIntoFreeSeatsOnly
    func testTheHostPlacesHousePlayersIntoFreeSeatsOnly() throws {
        var s = try MPRules.addFriendlyHousePlayer(room(4), actor: "host", bot: bot(0), seat: 3)
        XCTAssertEqual(3, s.seats[bot(0).id])
        let taken = try MPRules.addFriendlyHousePlayer(s, actor: "host", bot: bot(1), seat: 3)
        XCTAssertEqual(s, taken)                                                                        // taken: the earlier choice stays
        XCTAssertThrowsError(try MPRules.addBot(s, actor: "host", bot: bot(1), seat: 3))
        XCTAssertThrowsError(try MPRules.addBot(s, actor: "host", bot: bot(1), seat: 7))
        XCTAssertThrowsError(try MPRules.addFriendlyHousePlayer(s, actor: "host", bot: bot(1), seat: 7))
        s = try MPRules.join(s, MPIdentity(id: "b", name: "B"))
        XCTAssertEqual(1, s.seats["b"])                                                                 // a human takes the lowest free seat
        XCTAssertThrowsError(try MPRules.addFriendlyHousePlayer(s, actor: "b", bot: bot(1)))
        XCTAssertThrowsError(try MPRules.addBot(s, actor: "host", bot: bot(0)))                         // same character twice
        s = try MPRules.addFriendlyHousePlayer(s, actor: "host", bot: bot(1))
        XCTAssertEqual(2, s.seats[bot(1).id])
        let full = try MPRules.addFriendlyHousePlayer(s, actor: "host", bot: bot(2))
        XCTAssertEqual(s, full)                                                                         // table full
        XCTAssertThrowsError(try MPRules.join(s, MPIdentity(id: "z", name: "Z")))
        let started = try MPRules.start(s, actor: "host")
        XCTAssertEqual(["host", "b", bot(1).id, bot(0).id], try only(started).players)
        let tournament = createRoom("ABC234", .tournament, MPIdentity(id: "host", name: "H"), 4, 1, 3, 0, 0, 5)
        XCTAssertThrowsError(try MPRules.addBot(tournament, actor: "host", bot: bot(0), seat: 1))
        let added = try MPRules.addBot(tournament, actor: "host", bot: bot(0))
        XCTAssertTrue(added.seats.isEmpty)
    }

    // Kotlin: allHumanTableStartsOnceWhenEveryHumanIsReadyAndConnected
    func testAllHumanTableStartsOnceWhenEveryHumanIsReadyAndConnected() throws {
        var s = try MPRules.start(room(4, ["b", "c", "d"]), actor: "host")
        let id = try only(s).id
        XCTAssertEqual("b", s.authority(try only(s)))                                                   // smallest human uid, not the host
        XCTAssertEqual(s, MPRules.friendlyHouseReady(s, actor: "host"))
        for uid in ["host", "b", "c"] {
            s = try MPRules.ready(s, match: id, uid: uid, value: true)
            XCTAssertEqual(s, MPRules.startReady(s, match: id))
        }
        XCTAssertEqual(MPMatchPhase.ready, try only(s).phase)
        s = try MPRules.ready(s, match: id, uid: "d", value: true)
        var away = s
        away.connections["c"] = nil
        XCTAssertEqual(away, MPRules.startReady(away, match: id))
        let playing = MPRules.startReady(s, match: id)
        let table = try only(playing)
        XCTAssertEqual(MPMatchPhase.playing, table.phase)
        XCTAssertEqual(1, table.starts)
        XCTAssertTrue(table.ready.isEmpty)
        for _ in 0..<5 { XCTAssertEqual(playing, MPRules.startReady(playing, match: id)) }
        let unready = try MPRules.ready(playing, match: id, uid: "d", value: false)
        XCTAssertEqual(playing, unready)
        let ready = try MPRules.ready(playing, match: id, uid: "b", value: true)
        XCTAssertEqual(playing, ready)
        XCTAssertTrue(["host", "b", "c", "d"].allSatisfy { !playing.needsLobbyPresence($0) })
    }

    // Kotlin: allHouseExceptOneTableStartsFromTheHostsStartAtAnySize
    func testAllHouseExceptOneTableStartsFromTheHostsStartAtAnySize() throws {
        for size in 3...4 {
            let s = try MPRules.start(room(size, bots: size - 1), actor: "host")
            let id = try only(s).id
            let expected = ["host"] + (0..<(size - 1)).map { bot($0).id }
            XCTAssertEqual(expected, try only(s).players)
            XCTAssertEqual("host", s.authority(try only(s)))
            XCTAssertThrowsError(try MPRules.ready(s, match: id, uid: bot(0).id, value: true))
            let ready = MPRules.friendlyHouseReady(s, actor: "host")
            XCTAssertEqual(Set(["host"]), try only(ready).readySet)
            XCTAssertEqual(MPMatchPhase.ready, try only(ready).phase)
            var offline = ready
            offline.connections = [:]
            XCTAssertEqual(offline, MPRules.startReady(offline, match: id))
            let playing = MPRules.startReady(ready, match: id)
            XCTAssertEqual(MPMatchPhase.playing, try only(playing).phase)
            XCTAssertEqual(1, try only(playing).starts)
            XCTAssertEqual(playing, MPRules.friendlyHouseReady(playing, actor: "host"))
            XCTAssertEqual(playing, MPRules.startReady(playing, match: id))
        }
    }

    // Kotlin: mixedTableNeedsEveryHumanReadyAndHousePlayersNeverBlock
    func testMixedTableNeedsEveryHumanReadyAndHousePlayersNeverBlock() throws {
        var s = try MPRules.start(room(4, ["b"], bots: 2), actor: "host")
        let id = try only(s).id
        XCTAssertEqual(["host", "b", bot(0).id, bot(1).id], try only(s).players)
        XCTAssertEqual("b", s.authority(try only(s)))
        XCTAssertEqual(s, MPRules.friendlyHouseReady(s, actor: "host"))                                  // another human must choose Ready
        s = try MPRules.ready(s, match: id, uid: "host", value: true)
        XCTAssertEqual(s, MPRules.startReady(s, match: id))
        s = try MPRules.ready(s, match: id, uid: "b", value: true)
        var away = s
        away.connections["b"] = nil
        XCTAssertEqual(away, MPRules.startReady(away, match: id))
        let playing = MPRules.startReady(s, match: id)
        XCTAssertEqual(MPMatchPhase.playing, try only(playing).phase)
        XCTAssertEqual(1, try only(playing).starts)
        XCTAssertThrowsError(try MPRules.ready(s, match: id, uid: "outsider", value: true))
    }

    // Kotlin: noHumanIsInTwoPlayingTablesAtOnce
    func testNoHumanIsInTwoPlayingTablesAtOnce() throws {
        var people: [String: MPParticipant] = [:]
        for id in ["a", "b", "c", "d", "e", "f"] { people[id] = MPParticipant(identity: MPIdentity(id: id, name: id)) }
        let seatings: [[String]] = [["a", "b", "c"], ["c", "d", "e"], ["d", "e", "f"]]
        var tables: [MPFixture] = []
        for (i, players) in seatings.enumerated() { tables.append(MPFixture(id: "m\(i)", players: players, seed: Int64(i))) }
        var s = bareSession("ABC234", .tournament, "a", capacity: 6)
        s.participants = people
        var matches: [String: MPFixture] = [:]
        for m in tables { matches[m.id] = m }
        s.matches = matches
        var connections: [String: [String: Bool]] = [:]
        for id in people.keys { connections[id] = ["0": true] }
        s.connections = connections
        s.state = "ACTIVE"
        s.tableSize = 3
        for m in tables {
            for uid in m.players { s = try MPRules.ready(s, match: m.id, uid: uid, value: true) }
        }
        s = MPRules.startReady(s, match: "m0")
        XCTAssertEqual(MPMatchPhase.playing, s.matches["m0"]?.phase)
        XCTAssertEqual(s, MPRules.startReady(s, match: "m1"))                                          // c is still at table m0
        s = MPRules.startReady(s, match: "m2")
        XCTAssertEqual(MPMatchPhase.playing, s.matches["m2"]?.phase)
        XCTAssertEqual(s, MPRules.startReady(s, match: "m1"))                                          // now d and e are playing too
        for uid in people.keys {
            XCTAssertTrue(s.matches.values.filter { $0.phase == .playing && $0.contains(uid) }.count <= 1)
        }
        XCTAssertEqual([1, 0, 1], ["m0", "m1", "m2"].map { s.matches[$0]?.starts ?? -1 })
    }

    // Kotlin: authorityIsTheSmallestHumanUidOrTheHostForHouseOnlyTables
    func testAuthorityIsTheSmallestHumanUidOrTheHostForHouseOnlyTables() {
        var people: [String: MPParticipant] = [:]
        let everyone = [MPParticipant(identity: MPIdentity(id: "zed", name: "Zed")), MPParticipant(identity: MPIdentity(id: "amy", name: "Amy")),
                        bot(0), bot(1), bot(2)]
        for p in everyone { people[p.id] = p }
        var s = bareSession("ABC234", .friendly, "zed", capacity: 4)
        s.participants = people
        s.tableSize = 4
        XCTAssertEqual("amy", s.authority(MPFixture(id: "m", players: [bot(0).id, "zed", "amy", bot(1).id], seed: 1)))
        XCTAssertEqual("zed", s.authority(MPFixture(id: "m", players: [bot(0).id, "zed", bot(1).id], seed: 1)))
        XCTAssertEqual("zed", s.authority(MPFixture(id: "m", players: [bot(0).id, bot(1).id, bot(2).id], seed: 1)))
        var renamed = s
        renamed.participants = s.participants.mapValues { (p: MPParticipant) -> MPParticipant in
            var copy = p
            copy.identity.name = "Same"
            return copy
        }
        renamed.host = "amy"
        XCTAssertEqual("amy", renamed.authority(MPFixture(id: "m", players: ["zed", "amy", bot(0).id], seed: 1)))
        XCTAssertEqual("amy", renamed.authority(MPFixture(id: "m", players: [bot(0).id, bot(1).id, bot(2).id], seed: 1)))
    }

    // Kotlin: onlyTheAuthorityWritesAValidTableResultOnceAndItIsImmutable
    func testOnlyTheAuthorityWritesAValidTableResultOnceAndItIsImmutable() throws {
        let waiting = try MPRules.start(room(3, ["b"], bots: 1), actor: "host")
        let m = try only(waiting)
        let id = m.id
        let players = m.players
        XCTAssertEqual(["host", "b", bot(0).id], players)
        XCTAssertThrowsError(try MPRules.finish(waiting, match: id, actor: "b", scores: [2, 5, 2], placement: ["b", "host", bot(0).id])) // not PLAYING yet
        let s = try play(waiting)
        XCTAssertEqual("b", s.authority(try only(s)))
        let valid = [2, 5, 2]
        let ranked = ["b", "host", bot(0).id]
        for actor in ["host", bot(0).id, "outsider"] {
            XCTAssertThrowsError(try MPRules.finish(s, match: id, actor: actor, scores: valid, placement: ranked))
        }
        let badScores: [[Int]] = [[5, 5, 0], [4, 3, 0], [6, 0, 0], [5, -1, 0], [5, 0], [5, 0, 0, 0], [2, 5, 9]]
        for scores in badScores {
            XCTAssertThrowsError(try MPRules.finish(s, match: id, actor: "b", scores: scores, placement: Array(ranked.prefix(scores.count))))
        }
        let badPlacements: [[String]] = [["b", "host", "host"], ["b", "host"], ["b", "host", bot(0).id, "z"], ["b", "host", "z"],
                                         ["host", "b", bot(0).id], [bot(0).id, "host", "b"]]
        for placement in badPlacements {
            XCTAssertThrowsError(try MPRules.finish(s, match: id, actor: "b", scores: valid, placement: placement))
        }
        XCTAssertThrowsError(try MPRules.finish(s, match: id, actor: "b", scores: [0, 5, 3], placement: ["b", "host", bot(0).id])) // host 0 above house 3
        XCTAssertThrowsError(try MPRules.finish(s, match: id, actor: "b", a: 5, b: 0))                // classic overload needs a pair
        XCTAssertTrue(MPRules.validPlacement(try only(s), valid, ["b", bot(0).id, "host"]))           // tied places in any order
        let done = try MPRules.finish(s, match: id, actor: "b", scores: valid, placement: ranked)
        let finished = try only(done)
        XCTAssertEqual(MPMatchPhase.finished, finished.phase)
        XCTAssertEqual("b", finished.winner)
        XCTAssertEqual(valid, finished.scores)
        XCTAssertEqual(ranked, finished.placement)
        XCTAssertEqual(1, finished.starts)
        XCTAssertEqual("FINISHED", done.state)
        XCTAssertTrue(done.complete)
        let byAuthority = try MPRules.finish(done, match: id, actor: "b", scores: [5, 0, 0], placement: ["host", "b", bot(0).id])
        XCTAssertEqual(done, byAuthority)
        let byHost = try MPRules.finish(done, match: id, actor: "host", scores: [5, 0, 0], placement: ["host", "b", bot(0).id])
        XCTAssertEqual(done, byHost)
        XCTAssertEqual(done, MPRules.startReady(done, match: id))
        let readyAgain = try MPRules.ready(done, match: id, uid: "host", value: true)
        XCTAssertEqual(done, readyAgain)
        let decoded = try roundTrip(done)
        XCTAssertEqual(done, decoded)
        XCTAssertTrue(MPCompletionText.won(done, "b"))
        XCTAssertFalse(MPCompletionText.won(done, "host"))
        XCTAssertEqual("You won the match!", MPCompletionText.headline(done, "b", hebrew: false))
        XCTAssertTrue(MPCompletionText.headline(done, "host", hebrew: false).hasSuffix(" won this match!"))
        var rows: [String: MPStanding] = [:]
        for row in MPRules.standings(done) { rows[row.id] = row }
        XCTAssertEqual(MPStanding(id: "b", played: 1, wins: 1, pointsFor: 5), rows["b"])               // no invented placement points
        XCTAssertEqual(MPStanding(id: "host", played: 1, losses: 1, pointsFor: 2), rows["host"])
        XCTAssertEqual(MPStanding(id: bot(0).id, played: 1, losses: 1, pointsFor: 2), rows[bot(0).id])
    }

    // Kotlin: classicPairsKeepTheirAccessorsDeuceRuleAndStandings
    func testClassicPairsKeepTheirAccessorsDeuceRuleAndStandings() throws {
        var pair = MPFixture(id: "m", a: "a", b: "b", seed: 7)
        pair.phase = .finished
        pair.scores = [3, 1]
        pair.winner = "a"
        XCTAssertEqual(["a", "b"], pair.players)
        XCTAssertEqual([3, 1], pair.scores)
        XCTAssertEqual("a", pair.a)
        XCTAssertEqual("b", pair.b)
        XCTAssertEqual(3, pair.scoreA)
        XCTAssertEqual(1, pair.scoreB)
        XCTAssertEqual(1, pair.scoreOf("b"))
        XCTAssertEqual(0, pair.scoreOf("z"))
        XCTAssertTrue(pair.contains("b"))
        XCTAssertFalse(pair.contains("z"))
        var listed = MPFixture(id: "m", players: ["a", "b"], seed: 7)
        listed.phase = .finished
        listed.scores = [3, 1]
        listed.winner = "a"
        XCTAssertEqual(pair, listed)
        var s = createRoom("ABC234", .tournament, MPIdentity(id: "a", name: "A"), 2, 1, 3, 0, 2, 5)  // MEDIUM: win by two
        s = try MPRules.join(s, MPIdentity(id: "b", name: "B"))
        s.connections = ["a": ["0": true], "b": ["0": true]]
        s = try MPRules.start(s, actor: "a")
        let id = try only(s).id
        s = try play(s)
        XCTAssertFalse(MPRules.validFinal(s, target: s.target, scores: [5, 4]))
        XCTAssertTrue(MPRules.validFinal(s, target: s.target, scores: [6, 4]))
        XCTAssertFalse(MPRules.validFinal(s, target: s.target, scores: [5]))
        XCTAssertFalse(MPRules.validFinal(s, target: s.target, scores: [5, 0, 0, 0, 0]))
        XCTAssertThrowsError(try MPRules.finish(s, match: id, actor: "a", a: 5, b: 4))
        let done = try MPRules.finish(s, match: id, actor: "a", a: 4, b: 6)
        let table = try only(done)
        XCTAssertEqual("b", table.winner)
        XCTAssertEqual(["b", "a"], table.placement)
        XCTAssertEqual([4, 6], table.scores)
        let rows = [MPStanding(id: "b", played: 1, wins: 1, losses: 0, points: 3, pointsFor: 6, pointsAgainst: 4),
                    MPStanding(id: "a", played: 1, wins: 0, losses: 1, points: 0, pointsFor: 4, pointsAgainst: 6)]
        XCTAssertEqual(rows, MPRules.standings(done))
    }

    /// Kotlin `houseTable(ids, target, seed)`: a tournament with one human host and a house-only table of `ids`.
    private func simulatedTable(_ ids: [String], _ target: Int, _ seed: Int64) -> (MPSession, MPFixture) {
        var people: [MPParticipant] = []
        for c in ids {
            let character = MPRoster.find(c) ?? MPRoster.all[0]
            people.append(MPParticipant(identity: MPIdentity(id: "bot_\(character.id)", name: character.english), bot: character.profile))
        }
        let m = MPFixture(id: "T\(seed)", players: people.map { $0.id }, seed: seed)
        var s = bareSession("ABC234", .tournament, "human")
        s.target = target
        s.tableSize = ids.count
        s.matches = [m.id: m]
        var all: [String: MPParticipant] = [:]
        for p in people { all[p.id] = p }
        all["human"] = MPParticipant(identity: MPIdentity(id: "human", name: "Host"))
        s.participants = all
        return (s, m)
    }

    // Kotlin: houseOnlyTablesAreSimulatedDeterministicallyUnderCrossScoring
    func testHouseOnlyTablesAreSimulatedDeterministicallyUnderCrossScoring() throws {
        var rallies = 0
        var faults = 0
        var floored = 0
        let lineups: [[String]] = [["kyra", "minik", "moshiko"], ["flare", "gaya", "mia", "amber"]]
        for ids in lineups {
            for target in [3, 5, 7, 10, 11] {
                for seed in Int64(0)...Int64(59) {
                    let (s, m) = simulatedTable(ids, target, seed * 7919 - 120)
                    let n = ids.count
                    let r = try XCTUnwrap(MPRules.simulate(s, m))
                    XCTAssertEqual(r, MPRules.simulate(s, m))
                    XCTAssertEqual(1, r.scores.filter { $0 == target }.count)
                    XCTAssertTrue(r.scores.allSatisfy { $0 >= 0 && $0 <= target })
                    XCTAssertTrue(MPRules.validFinal(s, target: s.target, scores: r.scores))
                    XCTAssertTrue(MPRules.validPlacement(m, r.scores, r.placement))
                    let log = GroupMatchRallyLog()
                    let bots = m.players.compactMap { s.participants[$0]?.bot }
                    XCTAssertEqual(n, bots.count)
                    let traced = MPTableSimulation.play(m.players, bots, target: target, seed: m.seed, trace: { log.items.append($0) })
                    XCTAssertEqual(r, traced)
                    var fouls = Array(repeating: 0, count: n)
                    var won = Array(repeating: 0, count: n)
                    for (i, x) in log.items.enumerated() {
                        XCTAssertEqual(Int(crossMod(m.seed + Int64(i), Int64(n))), x.server)          // the serve rotates every rally
                        XCTAssertTrue(x.before.allSatisfy { $0 < target })
                        XCTAssertTrue(x.after.allSatisfy { $0 >= 0 })
                        let changed = (0..<n).filter { x.before[$0] != x.after[$0] }
                        if x.fault {
                            XCTAssertNil(x.receiver)
                            fouls[x.striker] += 1
                            faults += 1
                            XCTAssertEqual(max(0, x.before[x.striker] - 1), x.after[x.striker])
                            XCTAssertTrue(changed.allSatisfy { $0 == x.striker })
                            if x.before[x.striker] == 0 { floored += 1 }
                        } else {
                            let receiver = try XCTUnwrap(x.receiver)
                            XCTAssertNotEqual(x.striker, receiver)
                            won[x.striker] += 1
                            XCTAssertEqual(x.before[x.striker] + 1, x.after[x.striker])
                            XCTAssertEqual(max(0, x.before[receiver] - 1), x.after[receiver])
                            XCTAssertTrue(changed.allSatisfy { $0 == x.striker || $0 == receiver })
                        }
                        if i > 0 { XCTAssertEqual(log.items[i - 1].after, x.before) }
                    }
                    rallies += log.items.count
                    XCTAssertEqual(r.scores, log.items.last?.after)
                    XCTAssertEqual(false, log.items.last?.fault)
                    let order = (0..<n).sorted { (a: Int, b: Int) -> Bool in
                        if r.scores[a] != r.scores[b] { return r.scores[a] > r.scores[b] }
                        if fouls[a] != fouls[b] { return fouls[a] < fouls[b] }
                        if won[a] != won[b] { return won[a] > won[b] }
                        return a < b
                    }
                    XCTAssertEqual(order.map { m.players[$0] }, r.placement)
                    let finished = MPRules.simulated(s, m)
                    XCTAssertEqual(MPMatchPhase.finished, finished.phase)
                    XCTAssertEqual(r.scores, finished.scores)
                    XCTAssertEqual(r.placement, finished.placement)
                    XCTAssertEqual(r.placement.first, finished.winner)
                    XCTAssertTrue(MPRules.houseOnly(s, m))
                }
            }
        }
        XCTAssertTrue(rallies > 1000)
        XCTAssertTrue(faults > 100)
        XCTAssertTrue(floored > 10, "a fault at zero leaves the score at zero")
    }

    // Kotlin: strongerHousePlayersWinMoreTablesWithoutCertainty
    func testStrongerHousePlayersWinMoreTablesWithoutCertainty() {
        var wins: [String: Int] = [:]
        for seed in Int64(0)..<Int64(900) {
            let (s, m) = simulatedTable(["gaya", "kyra", "flare"], 3, seed)
            let winner = MPRules.simulate(s, m)?.placement.first ?? ""
            wins[winner, default: 0] += 1
        }
        let kyra = wins["bot_kyra"] ?? 0
        let flare = wins["bot_flare"] ?? 0
        let gaya = wins["bot_gaya"] ?? 0
        XCTAssertTrue(kyra > flare && flare > gaya && gaya > 0, "\(wins)")
    }

    /// What Firebase hands back: no empty containers, and a dense list as a List or an index-keyed Map. (Kotlin also turns Ints
    /// into Longs; Firebase iOS and JSONSerialization both hand back NSNumber, so numbers stay as they are.)
    private func rtdb(_ value: Any?, lists: Bool) -> Any? {
        if let dict = value as? [String: Any] {
            var out: [String: Any] = [:]
            for (key, item) in dict {
                if let shaped = rtdb(item, lists: lists) { out[key] = shaped }
            }
            return out.isEmpty ? nil : out
        }
        if let list = value as? [Any] {
            let items: [Any?] = list.map { rtdb($0, lists: lists) }
            if items.isEmpty { return nil }
            if lists {
                var filled: [Any] = []
                for item in items {
                    if let present = item { filled.append(present) } else { filled.append(NSNull()) }
                }
                return filled
            }
            var keyed: [String: Any] = [:]
            for (i, item) in items.enumerated() {
                if let present = item { keyed[String(i)] = present }
            }
            return keyed
        }
        return value
    }

    // Kotlin: tablesRoundTripThroughTheWireIncludingFirebaseShapes
    func testTablesRoundTripThroughTheWireIncludingFirebaseShapes() throws {
        let waiting = try MPRules.chooseSeat(room(4, ["b"], bots: 1), actor: "b", seat: 3)
        let active = try MPRules.start(MPRules.addFriendlyHousePlayer(waiting, actor: "host", bot: bot(1)), actor: "host")
        let activeId = try only(active).id
        let ready = try MPRules.ready(active, match: activeId, uid: "host", value: true)
        let playing = try play(active)
        let playingId = try only(playing).id
        let done = try MPRules.finish(playing, match: playingId, actor: "b", scores: [1, 0, 1, 5], placement: ["b", "host", bot(0).id, bot(1).id])
        for s in [waiting, active, ready, playing, done] {
            let wire = try encodeRoom(s)
            let direct = try decodeRoom(wire)
            XCTAssertEqual(s, direct)
            let asLists = try decodeRoom(rtdb(wire, lists: true))
            XCTAssertEqual(s, asLists)
            let asMaps = try decodeRoom(rtdb(wire, lists: false))
            XCTAssertEqual(s, asMaps)
            XCTAssertEqual(4, wire["tableSize"] as? Int)
            XCTAssertEqual(s.seats, wire["seats"] as? [String: Int])
            let matches = (wire["matches"] as? [String: Any]) ?? [:]
            for m in s.matches.values {
                let w = (matches[m.id] as? [String: Any]) ?? [:]
                XCTAssertEqual(m.players, w["players"] as? [String])
                XCTAssertEqual(m.scores, w["scores"] as? [Int])
                XCTAssertEqual(4, w["matchSize"] as? Int)
                XCTAssertEqual("b", w["authorityUid"] as? String)
                XCTAssertNil(w["a"])
            }
        }
        XCTAssertEqual(["host", bot(1).id, bot(0).id, "b"], try only(active).players)
        // Kotlin PongCodec.match(sparse wire): iOS reads a fixture's wire through MPCodec.session (MPCodec has no match reader).
        let sparseWire: [String: Any] = ["id": "m", "players": ["x", "y", "z"], "scores": ["0": wireLong(2)], "phase": "PLAYING"]
        let sparseRoom: [String: Any] = ["code": "ABC234", "host": "x", "matches": ["m": sparseWire]]
        let sparse = try XCTUnwrap(try decodeRoom(sparseRoom).matches["m"])
        XCTAssertEqual([2, 0, 0], sparse.scores)
        XCTAssertEqual(MPMatchPhase.playing, sparse.phase)
    }

    // Kotlin: legacyPairRecordsAndRoomsStillLoad
    func testLegacyPairRecordsAndRoomsStillLoad() throws {
        let match: [String: Any] = ["id": "ABC234_0_0_1", "a": "guest", "b": "host", "seed": wireLong(99), "phase": "FINISHED",
                                    "ready": ["host": true], "scoreA": wireLong(1), "scoreB": wireLong(3), "winner": "host",
                                    "starts": wireLong(1), "authorityUid": "guest"]
        // Kotlin PongCodec.match(wire): iOS decodes one record with MPFixture's Codable reader (MPCodec has no match reader).
        let m = try MPCodec.decode(MPFixture.self, match)
        var expected = MPFixture(id: "ABC234_0_0_1", a: "guest", b: "host", seed: 99)
        expected.phase = .finished
        expected.ready = ["host": true]
        expected.scores = [1, 3]
        expected.winner = "host"
        expected.starts = 1
        expected.authorityUid = "guest"                                                                // iOS keeps the wire's authorityUid in the record
        XCTAssertEqual(expected, m)
        XCTAssertEqual(["guest", "host"], m.players)
        XCTAssertEqual([1, 3], m.scores)
        XCTAssertTrue(m.placement.isEmpty)
        let hostIdentity: [String: Any] = ["id": "host", "name": "GreenFrog", "avatar": wireLong(1)]
        let guestIdentity: [String: Any] = ["id": "guest", "name": "BlueFox", "avatar": wireLong(2)]
        let hostEntry: [String: Any] = ["identity": hostIdentity]
        let guestEntry: [String: Any] = ["identity": guestIdentity]
        let people: [String: Any] = ["host": hostEntry, "guest": guestEntry]
        let old: [String: Any] = ["code": "ABC234", "kind": "FRIENDLY", "host": "host", "capacity": wireLong(2), "legs": wireLong(1),
                                  "winPoints": wireLong(3), "lossPoints": wireLong(0), "difficulty": wireLong(0),
                                  "target": wireLong(3), "roster": ["guest", "host"], "rosterSize": wireLong(2),
                                  "participants": people, "matches": ["ABC234_0_0_1": match], "state": "FINISHED",
                                  "createdAt": wireLong(5), "lastActivityAt": wireLong(6)]
        let s = try decodeRoom(old)
        XCTAssertEqual(2, s.tableSize)
        XCTAssertTrue(s.seats.isEmpty)
        XCTAssertEqual(["host": 0, "guest": 1], s.seating())
        XCTAssertEqual(1, s.matches.count)
        XCTAssertEqual(m, s.matches.values.first)
        XCTAssertTrue(s.complete)
        XCTAssertTrue(MPCompletionText.won(s, "host"))
        let decoded = try roundTrip(s)
        XCTAssertEqual(s, decoded)
        // An older waiting room without seats: the host keeps seat 0 and a guest takes seat 1.
        var waitingWire = old
        waitingWire.removeValue(forKey: "matches")
        let hostOnly: [String: Any] = ["host": hostEntry]
        waitingWire["state"] = "WAITING"
        waitingWire["participants"] = hostOnly
        waitingWire["roster"] = ["host"]
        waitingWire["rosterSize"] = wireLong(1)
        let waiting = try decodeRoom(waitingWire)
        let joined = try MPRules.join(waiting, MPIdentity(id: "guest", name: "BlueFox"))
        XCTAssertEqual(["host": 0, "guest": 1], joined.seats)
        let started = try MPRules.start(joined, actor: "host")
        XCTAssertEqual(["host", "guest"], try only(started).players)
    }

    private struct VisualGlyph {
        let x: Double
        let order: Int
        let index: Int
    }

    /// Kotlin `visual` (java.text.Bidi.reorderVisually): the text's characters in display order for a paragraph of the given
    /// direction, without format characters (the isolates). iOS has no java.text.Bidi: CoreText lays the text out as one line
    /// and its glyphs, ordered by position, give the visual order.
    private func visualOrder(_ text: String, rtl: Bool) -> String {
        var direction: CTWritingDirection = rtl ? .rightToLeft : .leftToRight
        let style: CTParagraphStyle = withUnsafeBytes(of: &direction) { raw -> CTParagraphStyle in
            var setting = CTParagraphStyleSetting(spec: .baseWritingDirection, valueSize: MemoryLayout<CTWritingDirection>.size,
                                                  value: raw.baseAddress!)
            return CTParagraphStyleCreate(&setting, 1)
        }
        let key = NSAttributedString.Key(rawValue: kCTParagraphStyleAttributeName as String)
        let attributed = NSAttributedString(string: text, attributes: [key: style])
        let line = CTLineCreateWithAttributedString(attributed as CFAttributedString)
        let runs = CTLineGetGlyphRuns(line) as! [CTRun]
        var glyphs: [VisualGlyph] = []
        for run in runs {
            let count = CTRunGetGlyphCount(run)
            if count <= 0 { continue }
            var indices = [CFIndex](repeating: 0, count: count)
            var positions = [CGPoint](repeating: CGPoint.zero, count: count)
            CTRunGetStringIndices(run, CFRange(location: 0, length: 0), &indices)
            CTRunGetPositions(run, CFRange(location: 0, length: 0), &positions)
            for i in 0..<count {
                let order = glyphs.count
                glyphs.append(VisualGlyph(x: Double(positions[i].x), order: order, index: indices[i]))
            }
        }
        glyphs.sort { $0.x != $1.x ? $0.x < $1.x : $0.order < $1.order }
        let units = Array(text.utf16)
        var used = Set<Int>()
        var visual: [UInt16] = []
        for glyph in glyphs where glyph.index >= 0 && glyph.index < units.count && !used.contains(glyph.index) {
            used.insert(glyph.index)
            visual.append(units[glyph.index])
        }
        var result = ""
        for scalar in String(decoding: visual, as: UTF16.self).unicodeScalars where scalar.properties.generalCategory != .format {
            result.unicodeScalars.append(scalar)
        }
        return result
    }

    /// Kotlin `String.indexOf`: the character offset of `needle` in `text`, or -1.
    private func offset(of needle: String, in text: String) -> Int {
        guard let range = text.range(of: needle) else { return -1 }
        return text.distance(from: text.startIndex, to: range.lowerBound)
    }

    // Kotlin: tableTextKeepsSeatOrderInBothDirections
    func testTableTextKeepsSeatOrderInBothDirections() {
        let lineups: [[String]] = [["Player", "שחקן", "מיניק"], ["שחקן", "Player", "Bob", "מיניק"]]
        for rtl in [false, true] {
            for names in lineups {
                let scores = Array([5, 3, 0, 1].prefix(names.count))
                let line = visualOrder(MPMatchText.table(names, scores), rtl: rtl)
                let at = scores.map { offset(of: " \($0)", in: line) }
                let ordered = zip(at, at.dropFirst()).allSatisfy { $0.0 < $0.1 }
                XCTAssertTrue(at.allSatisfy { $0 >= 0 } && ordered, line)
                let first = offset(of: names[0] == "Player" ? "Player" : "ןקחש", in: line)
                XCTAssertTrue(first >= 0 && first < (at.first ?? 0), line)
                let group = visualOrder(MPMatchText.group(names), rtl: rtl)
                XCTAssertTrue(offset(of: "Player", in: group) >= 0 && offset(of: "·", in: group) >= 0, group)
                XCTAssertEqual(names[0] == "Player", offset(of: "Player", in: group) < offset(of: "·", in: group))
                // Kotlin MatchText.score(listOf(5, 3, 0)) is MPMatchText.scoreboard.
                XCTAssertEqual("5 : 3 : 0", visualOrder(MPMatchText.scoreboard([5, 3, 0]), rtl: rtl))
            }
        }
    }

    // Not ported: lobbyReadyCueListensToEverySeat — Android LobbyEvents/LobbyCue is the private, @MainActor
    // MPController.lobbyCues(_:) on iOS (it reads the repository's uid and plays audio); there is no accessible equivalent.
}
