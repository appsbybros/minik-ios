import XCTest
@testable import MinikMultiPingPong
import CoreGraphics
import CoreText

// Android app/src/test/.../multiplayer/GroupTournamentTest.kt (MinikCrossPong 828c6fc).
// Three/four-player tournaments as the user decided them: balanced round-robin tables with placement points
// (MPGroupTournament) and "top two advance" knockouts (MPKnockout group rounds), with durable seeded draws, departures,
// house-only tables, the wire, texts, completion and the classic pair formats.
final class GroupTournamentTests: XCTestCase {
    private let house = MPRoster.all

    private func bot(_ i: Int) -> MPParticipant {
        MPParticipant(identity: MPIdentity(id: "bot_\(house[i].id)", name: house[i].english), bot: house[i].profile)
    }

    /// Kotlin `online`: every human who has not left is connected.
    private func online(_ s: MPSession) -> MPSession {
        var next = s
        var connections: [String: [String: Bool]] = [:]
        for (id, p) in s.participants where p.bot == nil && s.departed[id] != true { connections[id] = ["0": true] }
        next.connections = connections
        return next
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

    /// "h0" hosts; `humans` humans in all ("h0".."h8"); house players fill the other seats; every human online.
    private func tournament(_ players: Int, _ size: Int, _ format: MPTournamentFormat, humans: Int = 1, legs: Int = 1,
                            createdAt: Int64 = 7, difficulty: Int = 0,
                            file: StaticString = #filePath, line: UInt = #line) throws -> MPSession {
        var s = createRoom("GRP234", .tournament, MPIdentity(id: "h0", name: "Host"), players, legs, 3, 0, difficulty, 5,
                           format: format, tableSize: size)
        s.createdAt = createdAt
        for i in 1..<max(1, humans) { s = try MPRules.join(s, MPIdentity(id: "h\(i)", name: "Player \(i)")) }
        for i in 0..<max(0, players - humans) { s = try MPRules.addBot(s, actor: "h0", bot: bot(i)) }
        XCTAssertEqual(players, s.participants.count, file: file, line: line)
        return online(s)
    }

    private func openTables(_ s: MPSession) -> [MPFixture] {
        s.matches.values.filter { !$0.terminal }.sorted(by: { $0.id < $1.id })
    }

    private func pairs(_ n: Int) -> [(Int, Int)] {
        var result: [(Int, Int)] = []
        for x in 0..<n {
            for y in (x + 1)..<n { result.append((x, y)) }
        }
        return result
    }

    /// Every human of the table chooses Ready, it starts once, and its authority finishes it in `placement` order: the winner
    /// reaches the target and the others follow below it (a pair: target and target-2).
    private func play(_ s: MPSession, _ id: String, _ placement: [String],
                      file: StaticString = #filePath, line: UInt = #line) throws -> MPSession {
        let m = try XCTUnwrap(s.matches[id], file: file, line: line)
        var next = s
        for uid in m.players where s.human(uid) { next = try MPRules.ready(next, match: id, uid: uid, value: true) }
        next = MPRules.startReady(next, match: id)
        XCTAssertEqual(MPMatchPhase.playing, next.matches[id]?.phase, file: file, line: line)
        var score: [String: Int] = [:]
        for (i, uid) in placement.enumerated() { score[uid] = i == 0 ? s.target : max(0, s.target - 1 - i) }
        let actor = next.authority(m)
        if m.players.count == 2 {
            return try MPRules.finish(next, match: id, actor: actor, a: score[m.a] ?? 0, b: score[m.b] ?? 0)
        }
        let scores = m.players.map { score[$0] ?? 0 }
        return try MPRules.finish(next, match: id, actor: actor, scores: scores, placement: placement)
    }

    /// Kotlin `PongCodec.session(s)`.
    private func encodeRoom(_ s: MPSession) throws -> MPWire { try MPCodec.session(s) }
    /// Kotlin `PongCodec.session(wire)`.
    private func decodeRoom(_ value: Any?) throws -> MPSession { try MPCodec.session(value) }
    private func roundTrip(_ s: MPSession) throws -> MPSession { try decodeRoom(try encodeRoom(s)) }

    /// What Firebase hands back: no empty containers, dense integer keys as a List or an index-keyed Map. (Kotlin also turns Ints
    /// into Longs; Firebase iOS and JSONSerialization both hand back NSNumber, so numbers stay as they are.)
    private func firebaseShape(_ value: Any?, lists: Bool) -> Any? {
        if let dict = value as? [String: Any] {
            var out: [String: Any] = [:]
            for (key, item) in dict {
                if let shaped = firebaseShape(item, lists: lists) { out[key] = shaped }
            }
            return out.isEmpty ? nil : out
        }
        if let list = value as? [Any] {
            let items: [Any?] = list.map { firebaseShape($0, lists: lists) }
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

    /// Shapes where equal table counts would cost the busiest player another table: counts differ by one.
    private func uneven(_ n: Int, _ size: Int) -> Bool {
        (n == 8 && size == 3) || (n == 5 && size == 4) || (n == 7 && size == 4)
    }

    // ---- Round robin: balanced tables ----

    // Kotlin: balancedDesignsMeetEveryPairWithEvenLoadsAndTheFewestTables
    func testBalancedDesignsMeetEveryPairWithEvenLoadsAndTheFewestTables() {
        // Tables per leg for 3..9 players: (tables of three) to (tables of four).
        let tablesPerLeg: [Int: (Int, Int)] = [3: (1, 1), 4: (4, 1), 5: (5, 3), 6: (6, 3), 7: (7, 5), 8: (11, 6), 9: (12, 9)]
        // The busiest player's table count: the least any covering allows.
        let busiest: [Int: (Int, Int)] = [3: (1, 1), 4: (3, 1), 5: (3, 3), 6: (3, 2), 7: (3, 3), 8: (5, 3), 9: (4, 4)]
        for n in 3...9 {
            for size in 3...4 {
                let tables = MPGroupTournament.design(n, size)
                let seats = min(size, n)
                let place = "\(n) players, tables of \(size)"
                let perLeg = tablesPerLeg[n] ?? (0, 0)
                XCTAssertEqual(size == 3 ? perLeg.0 : perLeg.1, tables.count, place)
                XCTAssertTrue(tables.allSatisfy { t in t.count == seats && Set(t).count == seats && t.allSatisfy { $0 >= 0 && $0 < n } }, place)
                XCTAssertEqual(tables.count, Set(tables.map { Set($0) }).count, place)                // no table twice in one leg
                XCTAssertTrue(pairs(n).allSatisfy { p in tables.contains(where: { $0.contains(p.0) && $0.contains(p.1) }) }, place)
                let loads = (0..<n).map { p in tables.filter { $0.contains(p) }.count }
                let most = loads.max() ?? 0
                let least = loads.min() ?? 0
                XCTAssertTrue(most - least <= 1, place)
                XCTAssertEqual(!uneven(n, size), Set(loads).count == 1, place)
                let busy = busiest[n] ?? (0, 0)
                XCTAssertEqual(size == 3 ? busy.0 : busy.1, most, place)
                XCTAssertTrue(least * (seats - 1) >= n - 1, place)                                      // everybody can meet everybody
                XCTAssertEqual(tables, MPGroupTournament.design(n, size), place)
            }
        }
        XCTAssertEqual([[0, 1, 2]], MPGroupTournament.design(3, 4))                                    // fewer players than seats: one table of 3
        XCTAssertEqual([[0, 1, 2, 3]], MPGroupTournament.design(4, 4))
        let fourAtThree: Set<Set<Int>> = [[0, 1, 2], [0, 1, 3], [0, 2, 3], [1, 2, 3]]
        XCTAssertEqual(fourAtThree, Set(MPGroupTournament.design(4, 3).map { Set($0) }))
        for n in [7, 9] {                                                                               // Fano plane, affine plane
            let design = MPGroupTournament.design(n, 3)
            XCTAssertTrue(pairs(n).allSatisfy { p in design.filter { $0.contains(p.0) && $0.contains(p.1) }.count == 1 }, "\(n)")
        }
        // Swift returns no tables instead of throwing (Kotlin `require`):
        XCTAssertTrue(MPGroupTournament.design(2, 3).isEmpty)
        XCTAssertTrue(MPGroupTournament.design(10, 3).isEmpty)
        XCTAssertTrue(MPGroupTournament.design(5, 2).isEmpty)
        XCTAssertTrue(MPGroupTournament.design(5, 5).isEmpty)
    }

    // Kotlin: roundRobinTablesAreStoredSeededBalancedAndRotatedForTheSecondLeg
    func testRoundRobinTablesAreStoredSeededBalancedAndRotatedForTheSecondLeg() throws {
        var labellings = Set<[[String]]>()
        let seeds: [Int64] = [7, 1234567, -99]
        for n in 3...8 {
            for size in 3...4 {
                for legs in 1...2 {
                    for seed in seeds {
                        let base = try tournament(n, size, .roundRobin, legs: legs, createdAt: seed)
                        let place = "\(n) players, tables of \(size), \(legs) legs, seed \(seed)"
                        let s = try MPRules.start(base, actor: "h0")
                        let again = try MPRules.start(base, actor: "h0")
                        XCTAssertEqual(s, again, place)                                                 // retries never reshuffle
                        let restarted = try MPRules.start(s, actor: "h0")
                        XCTAssertEqual(s, restarted, place)
                        let decoded = try roundTrip(s)
                        XCTAssertEqual(s, decoded, place)
                        let encoded = try encodeRoom(s)
                        let shaped = firebaseShape(encoded, lists: seed > 0)
                        let fromFirebase = try decodeRoom(shaped)
                        XCTAssertEqual(s, fromFirebase, place)
                        XCTAssertTrue(s.grouped && s.rounds.isEmpty, place)
                        XCTAssertEqual("ACTIVE", s.state, place)
                        let per = MPGroupTournament.design(n, size).count
                        XCTAssertEqual(per * legs, s.matches.count, place)
                        let ids = Array(s.participants.keys)
                        for leg in 0..<legs {
                            var tables: [MPFixture] = []
                            for i in 0..<per { tables.append(try XCTUnwrap(s.matches["GRP234_T\(leg)_\(i)"], place)) }
                            for m in tables {
                                XCTAssertEqual(min(size, n), m.players.count, place)
                                XCTAssertEqual(m.players.count, Set(m.players).count, place)
                                XCTAssertTrue(Set(ids).isSuperset(of: m.players), place)
                                XCTAssertEqual(crossFold(m.id, 17), m.seed, place)
                            }
                            for x in ids {
                                for y in ids where x < y {
                                    XCTAssertTrue(tables.contains(where: { $0.contains(x) && $0.contains(y) }), "\(place): \(x) and \(y) never share a table")
                                }
                            }
                            let loads = ids.map { p in tables.filter { $0.contains(p) }.count }
                            XCTAssertTrue((loads.max() ?? 0) - (loads.min() ?? 0) <= 1, place)
                            if leg == 1 {
                                for i in 0..<per {
                                    let first = try XCTUnwrap(s.matches["GRP234_T0_\(i)"], place).players
                                    XCTAssertEqual(Array(first.dropFirst()) + Array(first.prefix(1)), tables[i].players, place)
                                }
                            }
                        }
                        // House-only tables finish in the start transition; every table with the human waits for them.
                        for m in s.matches.values {
                            XCTAssertEqual(m.contains("h0") ? MPMatchPhase.waiting : MPMatchPhase.finished, m.phase, place)
                        }
                        if n == 6 && size == 3 && legs == 1 {
                            labellings.insert(s.matches.values.sorted(by: { $0.id < $1.id }).map { $0.players })
                        }
                    }
                }
            }
        }
        XCTAssertEqual(3, labellings.count, "the seats follow the code and creation time")
    }

    // Kotlin: placementPointsRankTheStandingsThenTablesWonThenTotalScoreThenId
    func testPlacementPointsRankTheStandingsThenTablesWonThenTotalScoreThenId() {
        var people: [String: MPParticipant] = [:]
        for id in ["a", "b", "c", "d"] { people[id] = MPParticipant(identity: MPIdentity(id: id, name: id.uppercased())) }
        func done(_ id: String, _ players: [String], _ scores: [Int], _ placement: [String]) -> MPFixture {
            var m = MPFixture(id: id, players: players, seed: 1)
            m.phase = .finished
            m.scores = scores
            m.winner = placement.first ?? ""
            m.starts = 1
            m.placement = placement
            return m
        }
        // Kotlin `Session("GRP234", TOURNAMENT, "a", 4, participants, matches, state = "ACTIVE", tableSize = 3)`.
        func groupSession(_ tables: [MPFixture]) -> MPSession {
            var s = MPSession(code: "GRP234", kind: .tournament, host: MPIdentity(id: "a", name: "a"))
            s.capacity = 4; s.legs = 1; s.winPoints = 3; s.lossPoints = 0; s.difficulty = 0; s.target = 7
            s.participants = people
            var matches: [String: MPFixture] = [:]
            for m in tables { matches[m.id] = m }
            s.matches = matches
            s.connections = [:]; s.departed = [:]; s.state = "ACTIVE"; s.createdAt = 0; s.lastActivityAt = 0
            s.format = .roundRobin; s.rounds = [:]; s.tableSize = 3; s.seats = [:]; s.gameMode = .winnerTakesAll; s.advance = 2
            return s
        }
        // Everybody wins once and scores six points: total score decides, then the id.
        let level = groupSession([done("t0", ["a", "b", "c"], [5, 3, 1], ["a", "b", "c"]), done("t1", ["a", "b", "d"], [4, 5, 0], ["b", "a", "d"]),
                                  done("t2", ["a", "c", "d"], [1, 5, 2], ["c", "d", "a"]), done("t3", ["b", "c", "d"], [0, 4, 5], ["d", "c", "b"])])
        let levelRows = [MPStanding(id: "a", played: 3, wins: 1, losses: 2, points: 6, pointsFor: 10),
                         MPStanding(id: "c", played: 3, wins: 1, losses: 2, points: 6, pointsFor: 10),
                         MPStanding(id: "b", played: 3, wins: 1, losses: 2, points: 6, pointsFor: 8),
                         MPStanding(id: "d", played: 3, wins: 1, losses: 2, points: 6, pointsFor: 7)]
        XCTAssertEqual(levelRows, MPRules.standings(level))
        // Equal points: a table won outranks the same total score.
        let wins = groupSession([done("t0", ["a", "b", "c"], [5, 4, 0], ["a", "b", "c"]), done("t1", ["a", "b", "c"], [3, 4, 5], ["c", "b", "a"])])
        let winRows = [MPStanding(id: "a", played: 2, wins: 1, losses: 1, points: 4, pointsFor: 8),
                       MPStanding(id: "c", played: 2, wins: 1, losses: 1, points: 4, pointsFor: 5),
                       MPStanding(id: "b", played: 2, wins: 0, losses: 2, points: 4, pointsFor: 8),
                       MPStanding(id: "d")]
        XCTAssertEqual(winRows, MPRules.standings(wins))
        // A table of four gives 3, 2, 1, 0; a cancelled or unplayed table counts for nobody.
        var cancelled = MPFixture(id: "t1", players: ["a", "b", "c"], seed: 2)
        cancelled.phase = .cancelled
        cancelled.winner = "a"
        let unplayed = MPFixture(id: "t2", players: ["a", "c", "d"], seed: 3)
        var four = groupSession([done("t0", ["a", "b", "c", "d"], [1, 5, 3, 2], ["b", "c", "d", "a"]), cancelled, unplayed])
        four.tableSize = 4
        let fourRows = [MPStanding(id: "b", played: 1, wins: 1, losses: 0, points: 3, pointsFor: 5),
                        MPStanding(id: "c", played: 1, wins: 0, losses: 1, points: 2, pointsFor: 3),
                        MPStanding(id: "d", played: 1, wins: 0, losses: 1, points: 1, pointsFor: 2),
                        MPStanding(id: "a", played: 1, wins: 0, losses: 1, points: 0, pointsFor: 1)]
        XCTAssertEqual(fourRows, MPRules.standings(four))
        // A friendly table keeps the generic row: no placement points.
        var friendly = four
        friendly.kind = .friendly
        XCTAssertEqual([MPStanding(id: "b", played: 1, wins: 1, losses: 0, points: 0, pointsFor: 5)], MPRules.standings(friendly).filter { $0.id == "b" })
        XCTAssertEqual([3, 2, 1, 0], MPGroupTournament.placePoints)
    }

    // Kotlin: aRoundRobinOfTablesPlaysToTheEndAndTheFinishedTournamentIsNotKept
    func testARoundRobinOfTablesPlaysToTheEndAndTheFinishedTournamentIsNotKept() throws {
        // Kotlin RoomBook over in-memory SharedPreferences -> iOS MPPreferences over a private UserDefaults suite; Kotlin's
        // SavedRoom is the session's id, `rooms()` the remembered rooms and `cached(saved)` the remembered copy.
        let suite = "GroupTournamentTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let book = MPPreferences(defaults)
        var s = try MPRules.start(tournament(5, 3, .roundRobin, humans: 2, legs: 2), actor: "h0")
        let started = s
        book.remember(s)
        XCTAssertEqual([s.id], book.rooms.map { $0.id })
        XCTAssertEqual(s, book.rooms.first(where: { $0.id == s.id }))
        XCTAssertEqual(10, s.matches.count)
        XCTAssertTrue(s.matches.values.allSatisfy { $0.players.count == 3 })
        var rng = MPKotlinRandom(intSeed: 5)
        while let m = openTables(s).first {
            XCTAssertFalse(s.complete)
            for uid in s.participants.keys { XCTAssertFalse(MPCompletionText.won(s, uid)) }
            s = try play(s, m.id, rng.shuffled(m.players))
            book.remember(s)                                                                            // Kotlin book.collect(saved, s, "h0", 0)
        }
        XCTAssertTrue(s.complete)
        XCTAssertEqual("FINISHED", s.state)
        XCTAssertFalse(s.state != "FINISHED")                                                           // Kotlin RoomPolicy.open(s)
        let rows = MPRules.standings(s)
        XCTAssertEqual(10 * 6, rows.reduce(0) { $0 + $1.points })
        XCTAssertEqual(10, rows.reduce(0) { $0 + $1.wins })
        XCTAssertTrue(rows.allSatisfy { $0.played == 6 && $0.losses == 6 - $0.wins })
        XCTAssertEqual(Set(s.participants.keys), Set(rows.map { $0.id }))
        let champion = try XCTUnwrap(rows.first).id
        XCTAssertTrue(MPCompletionText.won(s, champion))
        for r in rows.dropFirst() { XCTAssertFalse(MPCompletionText.won(s, r.id)) }
        for (i, r) in rows.enumerated() {
            XCTAssertEqual(i + 1, MPCompletionText.place(s, r.id))
            let english = i == 0 ? "You won the tournament!" : "Tournament finished. You placed \(MPCompletionText.ordinal(i + 1))."
            XCTAssertEqual(english, MPCompletionText.headline(s, r.id, hebrew: false))
            let hebrew = i == 0 ? "ניצחתם בטורניר!" : "הטורניר הסתיים. סיימתם במקום ה־\(i + 1)."
            XCTAssertEqual(hebrew, MPCompletionText.headline(s, r.id, hebrew: true))
            // iOS 2026-11-10: a translation takes the place number, not the English ordinal ("puesto 2", never "puesto 2nd").
            if i > 0 {
                MPText.configure("es")
                XCTAssertEqual("Torneo terminado. Quedaste en el puesto \(i + 1).", MPCompletionText.headline(s, r.id, hebrew: false))
                MPText.configure("en")
            }
        }
        // A completed tournament is never kept as an open entry, and a stale cached copy cannot revive it.
        XCTAssertTrue(book.completionKnown(s))
        XCTAssertTrue(book.rooms.isEmpty)
        XCTAssertNil(book.rooms.first(where: { $0.id == s.id }))
        book.remember(started)                                                                          // Kotlin book.add(saved)
        book.remember(s)
        XCTAssertTrue(book.rooms.isEmpty)
        XCTAssertTrue(book.firstCelebration(s))
        XCTAssertFalse(book.firstCelebration(s))
    }

    // ---- Knockout: top two advance (the default: winner takes all, two through per table) ----

    // Kotlin: knockoutRoundsSplitIntoTablesOfThreeAndFourWithoutByes
    /// Updated to the user's new rule: no byes; five players play 3+2, otherwise only tables of 3 and 4.
    func testKnockoutRoundsSplitIntoTablesOfThreeAndFourWithoutByes() {
        XCTAssertEqual([Int](), MPGroupTournament.split(1, 3))
        let fixed: [(Int, [Int])] = [(2, [2]), (3, [3]), (4, [4]), (5, [3, 2]), (6, [3, 3]), (7, [4, 3]), (8, [4, 4]), (9, [3, 3, 3])]
        for size in 3...4 {
            for (players, tables) in fixed {
                XCTAssertEqual(tables, MPGroupTournament.split(players, size), "\(players) at \(size)")
            }
            for m in 6...32 {
                let t = MPGroupTournament.split(m, size)
                var options: [[Int]] = []
                for f in 0...(m / 4) where (m - 4 * f) % 3 == 0 {
                    options.append(Array(repeating: 4, count: f) + Array(repeating: 3, count: (m - 4 * f) / 3))
                }
                XCTAssertTrue(t.allSatisfy { $0 == 3 || $0 == 4 })
                XCTAssertEqual(m, t.reduce(0, +), "\(m)")
                XCTAssertEqual(t.sorted(by: >), t, "\(m)")
                let best = options.map { o in o.filter { $0 == size }.count }.max() ?? 0
                XCTAssertEqual(best, t.filter { $0 == size }.count, "\(m)")
                XCTAssertEqual(2 * t.count, MPGroupTournament.advancing(m, size), "\(m)")
                XCTAssertEqual(t.count, MPGroupTournament.advancing(m, size, advance: 1), "\(m)")
            }
        }
        XCTAssertEqual([3, 3, 3, 3], MPGroupTournament.split(12, 3))
        XCTAssertEqual([4, 4, 4], MPGroupTournament.split(12, 4))
        XCTAssertEqual(Array(repeating: 3, count: 5), MPGroupTournament.split(15, 3))
        XCTAssertEqual([4, 4, 4, 3], MPGroupTournament.split(15, 4))
    }

    /// Winner takes all, two through: the winner and the runner-up, or the winner of the tie-break for that place.
    private func topTwo(_ s: MPSession, _ round: Int, _ table: Int, _ m: MPFixture,
                        file: StaticString = #filePath, line: UInt = #line) -> [String] {
        let rest = m.players.filter { $0 != m.winner }
        let best = rest.map { m.scoreOf($0) }.max() ?? 0
        let tied = rest.filter { m.scoreOf($0) == best }
        let tiebreak = s.matches[MPKnockout.tiebreakId(s.code, round, table)]
        XCTAssertEqual(tied.count > 1, tiebreak != nil, file: file, line: line)
        if let decider = tiebreak { return [m.winner, decider.winner] }
        XCTAssertEqual(1, tied.count, file: file, line: line)
        return [m.winner, tied.first ?? ""]
    }

    // Kotlin: everyKnockoutSizeDrawsTablesWithoutByesAdvancesTheTopTwoAndCrownsTheFinalTableWinner
    func testEveryKnockoutSizeDrawsTablesWithoutByesAdvancesTheTopTwoAndCrownsTheFinalTableWinner() throws {
        // Round sizes without departures (the same at tables of three or four) and the first round's played tables (five: a
        // table of three and a walkover pair).
        let progression: [Int: [Int]] = [3: [3], 4: [4], 5: [5, 4], 6: [6, 4], 7: [7, 4], 8: [8, 4], 9: [9, 6, 4]]
        let firstTables: [Int: [Int]] = [3: [3], 4: [4], 5: [3], 6: [3, 3], 7: [4, 3], 8: [4, 4], 9: [3, 3, 3]]
        for n in 3...9 {
            for size in 3...4 {
                for seed in Int64(1)...Int64(12) {
                    var rng = MPKotlinRandom(seed: seed * 31 + Int64(n))
                    let humans = min(n, 1 + Int(seed % 4))
                    var s = try MPRules.start(tournament(n, size, .knockout, humans: humans, createdAt: seed), actor: "h0")
                    let place = "\(n) players, tables of \(size), seed \(seed)"
                    XCTAssertTrue(s.grouped && s.knockout, place)
                    XCTAssertEqual(1, s.legs, place)
                    while !s.complete {                                                                // house-only tables finish when drawn
                        guard let g = openTables(s).first else { XCTFail("no open table: \(place)"); break }
                        let before = s.rounds
                        s = try play(s, g.id, rng.shuffled(g.players))
                        for (r, drawn) in before { XCTAssertEqual(drawn, s.rounds[r], place) }        // a stored draw never changes
                    }
                    let last = MPKnockout.current(s)
                    var counts: [Int] = []
                    var tables = 0
                    for r in 0...last {
                        let round = try XCTUnwrap(s.rounds[r], place)
                        counts.append(round.players.count)
                        let m = round.players.count
                        XCTAssertEqual(m, Set(round.players).count, place)
                        XCTAssertEqual(Array(round.groups.joined()) + Array(round.walkovers.joined()), round.players, place)
                        let sizes = round.groups.map { $0.count }
                        if m <= 4 {
                            XCTAssertEqual([m], sizes, place)                                          // one final table
                        } else {
                            XCTAssertTrue(sizes.allSatisfy { $0 == 3 || $0 == 4 }, place)
                            XCTAssertTrue(round.byes.isEmpty, place)
                            XCTAssertTrue(round.walkovers.allSatisfy { $0.count == 2 }, place)
                        }
                        XCTAssertEqual(m <= 4, round.isFinal, place)
                        XCTAssertEqual(r == last, round.isFinal, place)
                        XCTAssertEqual(Array(round.walkovers.joined()), round.resting, place)
                        let games = MPKnockout.matches(s, r)
                        tables += games.count + MPKnockout.tiebreaks(s, r).count
                        XCTAssertEqual(round.groups, games.map { $0.players }, place)
                        XCTAssertEqual(games.indices.map { MPKnockout.id(s.code, r, $0) }, games.map { $0.id }, place)
                        XCTAssertTrue(games.allSatisfy { $0.phase == .finished }, place)
                        var through: [String] = []
                        for (i, g) in games.enumerated() {
                            if round.isFinal { through += Array(g.placement.prefix(1)) } else { through += topTwo(s, r, i, g) }
                        }
                        through += Array(round.walkovers.joined())
                        XCTAssertEqual(through, MPKnockout.advancing(s, r), place)
                        if r == last {
                            XCTAssertEqual(1, through.count, place)
                            XCTAssertEqual(through.first, MPKnockout.winner(s), place)
                        } else {
                            let nextRound = try XCTUnwrap(s.rounds[r + 1], place)
                            XCTAssertEqual(Set(through), Set(nextRound.players), place)
                        }
                    }
                    XCTAssertEqual(progression[n] ?? [], counts, place)
                    XCTAssertEqual(tables, s.matches.count, place)
                    XCTAssertEqual(firstTables[n] ?? [], (s.rounds[0]?.groups ?? []).map { $0.count }, place)
                    let champion = try XCTUnwrap(MPKnockout.winner(s), place)
                    XCTAssertEqual("FINISHED", s.state, place)
                    XCTAssertFalse(s.state != "FINISHED", place)                                     // Kotlin RoomPolicy.open(s)
                    XCTAssertTrue(MPCompletionText.won(s, champion), place)
                    for uid in s.participants.keys where uid != champion { XCTAssertFalse(MPCompletionText.won(s, uid), place) }
                }
            }
        }
    }

    // Kotlin: knockoutDrawsSurviveRetriesResettlesAndEveryStoredShape
    func testKnockoutDrawsSurviveRetriesResettlesAndEveryStoredShape() throws {
        for n in 3...9 {
            for size in 3...4 {
                let base = try tournament(n, size, .knockout, humans: min(n, 4), createdAt: 381)
                let place = "\(n) players, tables of \(size)"
                var s = try MPRules.start(base, actor: "h0")
                let again = try MPRules.start(base, actor: "h0")
                XCTAssertEqual(s, again, place)
                let restarted = try MPRules.start(s, actor: "h0")
                XCTAssertEqual(s, restarted, place)
                let settled = try MPKnockout.settle(s)
                XCTAssertEqual(s, settled, place)
                var rng = MPKotlinRandom(seed: Int64(n) * 10 + Int64(size))
                while !s.complete {
                    let wire = try encodeRoom(s)
                    let rounds = (wire["rounds"] as? [String: Any]) ?? [:]
                    for (key, raw) in rounds {
                        let w = (raw as? [String: Any]) ?? [:]
                        let drawn = try XCTUnwrap(s.rounds[Int(key) ?? -1], place)
                        XCTAssertEqual(drawn.groups, w["tables"] as? [[String]], place)
                        XCTAssertEqual(drawn.byes, w["byes"] as? [String], place)
                        XCTAssertEqual(drawn.players, w["players"] as? [String], place)
                        XCTAssertEqual(drawn.players.count, w["count"] as? Int, place)
                        let walkovers: [[String]]? = drawn.walkovers.isEmpty ? nil : drawn.walkovers
                        XCTAssertEqual(walkovers, w["walkovers"] as? [[String]], place)
                    }
                    // Kotlin JsonWire.decode(JsonWire.encode(wire)): a JSON text round trip.
                    let json = try JSONSerialization.jsonObject(with: JSONSerialization.data(withJSONObject: wire))
                    let shapes: [Any?] = [wire, firebaseShape(wire, lists: true), firebaseShape(wire, lists: false), json]
                    for shape in shapes {
                        let fromShape = try decodeRoom(shape)
                        XCTAssertEqual(s, fromShape, place)
                    }
                    guard let m = openTables(s).first else { XCTFail("no open table: \(place)"); break }
                    let placement = rng.shuffled(m.players)
                    let decoded = try decodeRoom(firebaseShape(wire, lists: rng.nextBoolean()))
                    let next = try play(s, m.id, placement)
                    let replayed = try play(decoded, m.id, placement)
                    XCTAssertEqual(next, replayed, place)
                    let resettled = try MPKnockout.settle(next)
                    XCTAssertEqual(next, resettled, place)
                    for (r, drawn) in s.rounds { XCTAssertEqual(drawn, next.rounds[r], place) }               // a stored draw never changes
                    s = next
                }
            }
        }
        var draws = Set<Set<Set<String>>>()
        for seed in Int64(1)...Int64(60) {
            let started = try MPRules.start(tournament(9, 3, .knockout, createdAt: seed), actor: "h0")
            let groups = started.rounds[0]?.groups ?? []
            draws.insert(Set(groups.map { Set($0) }))
        }
        XCTAssertTrue(draws.count > 50, "\(draws.count) distinct first rounds")
        // Five players: no byes any more; the walkover pair is drawn at random too.
        var walkoverPairs = Set<Set<String>>()
        for seed in Int64(1)...Int64(200) {
            let started = try MPRules.start(tournament(5, 4, .knockout, createdAt: seed), actor: "h0")
            let round = try XCTUnwrap(started.rounds[0])
            XCTAssertTrue(round.byes.isEmpty)
            XCTAssertEqual(1, round.walkovers.count)
            walkoverPairs.insert(Set(round.walkovers.first ?? []))
        }
        XCTAssertEqual(5, Set(walkoverPairs.joined()).count, "anybody can be drawn to the walkover table")
        XCTAssertTrue(walkoverPairs.count > 5)
    }

    // Kotlin: departuresCancelTablesWithoutInventedResultsAndShrinkTheFinalToAClassicPair
    func testDeparturesCancelTablesWithoutInventedResultsAndShrinkTheFinalToAClassicPair() throws {
        // Eight humans at tables of four: a player leaves before their table is played.
        var s = try MPRules.start(tournament(8, 4, .knockout, humans: 8, createdAt: 3), actor: "h0")
        let firstRound = MPKnockout.matches(s, 0)
        XCTAssertEqual(2, firstRound.count)
        guard firstRound.count >= 2 else { return }
        let first = firstRound[0]
        let second = firstRound[1]
        XCTAssertEqual([4, 4], [first.players.count, second.players.count])
        let leaver = try XCTUnwrap(first.players.first(where: { $0 != "h0" }))
        s = try MPRules.leave(s, actor: leaver)
        let cancelled = try XCTUnwrap(s.matches[first.id])
        XCTAssertEqual(MPMatchPhase.cancelled, cancelled.phase)
        XCTAssertEqual([0, 0, 0, 0], cancelled.scores)
        XCTAssertTrue(cancelled.placement.isEmpty)
        XCTAssertEqual(first.players.first(where: { $0 != leaver }), cancelled.winner)
        XCTAssertTrue(cancelled.ready.isEmpty)
        XCTAssertEqual(second, s.matches[second.id])
        XCTAssertEqual(1, s.rounds.count)
        XCTAssertEqual("h0", s.host)
        let cancelledAuthority = s.authority(first)
        XCTAssertThrowsError(try MPRules.finish(s, match: first.id, actor: cancelledAuthority, scores: [5, 0, 0, 0], placement: first.players)) // a cancelled table takes no result
        s = try play(s, second.id, second.players)
        let next = try XCTUnwrap(s.rounds[1])
        let walkedOver = Set(first.players.filter { $0 != leaver }).union(second.players.prefix(2))
        XCTAssertEqual(walkedOver, Set(next.players), "a walkover for everybody left at the cancelled table, the top two of the played one")
        // Five go on: a table of three and a walkover pair (no byes).
        XCTAssertEqual([3], next.groups.map { $0.count })
        XCTAssertEqual([2], next.walkovers.map { $0.count })
        XCTAssertTrue(next.byes.isEmpty)
        XCTAssertFalse(next.players.contains(leaver))
        let decoded = try roundTrip(s)
        XCTAssertEqual(s, decoded)

        // Six humans at tables of three, MEDIUM (a pair needs a two-point lead).
        var t = try MPRules.start(tournament(6, 3, .knockout, humans: 6, createdAt: 5, difficulty: 2), actor: "h0")
        let sixRound = MPKnockout.matches(t, 0)
        XCTAssertEqual(2, sixRound.count)
        guard sixRound.count >= 2 else { return }
        let a = sixRound[0]
        let b = sixRound[1]
        t = try play(t, a.id, a.players)
        // A runner-up who leaves before the round ends does not advance, and nobody takes the place.
        let runner = a.players[1]
        t = try MPRules.leave(t, actor: runner)
        XCTAssertEqual(MPMatchPhase.finished, t.matches[a.id]?.phase)
        XCTAssertEqual(1, t.rounds.count)
        t = try play(t, b.id, b.players)
        let finalTable = try XCTUnwrap(t.rounds[1])
        XCTAssertEqual(Set([a.players[0]]).union(b.players.prefix(2)), Set(finalTable.players))
        XCTAssertEqual([3], finalTable.groups.map { $0.count })
        XCTAssertTrue(finalTable.isFinal)
        XCTAssertEqual("Final", MPKnockout.stage(t, hebrew: false))
        // A finalist leaves before the final table is played: two remain and play the classic pair final.
        let finals = MPKnockout.matches(t, 1)
        XCTAssertEqual(1, finals.count)
        let table = try XCTUnwrap(finals.first)
        let gone = try XCTUnwrap(table.players.first(where: { $0 != t.host }))
        t = try MPRules.leave(t, actor: gone)
        XCTAssertEqual(MPMatchPhase.cancelled, t.matches[table.id]?.phase)
        XCTAssertEqual([0, 0, 0], t.matches[table.id]?.scores)
        let pairTables = MPKnockout.matches(t, 2)
        XCTAssertEqual(1, pairTables.count)
        let pair = try XCTUnwrap(pairTables.first)
        let drawn = try XCTUnwrap(t.rounds[2])
        XCTAssertEqual(Set(table.players.filter { $0 != gone }), Set(pair.players))
        XCTAssertEqual([pair.players], drawn.groups)
        XCTAssertTrue(drawn.byes.isEmpty && drawn.isFinal)
        XCTAssertEqual([0, 0], pair.scores)
        XCTAssertEqual("Final", MPKnockout.stage(t, hebrew: false))
        XCTAssertEqual("הגמר", MPKnockout.stage(t, hebrew: true))
        let fromFirebase = try decodeRoom(firebaseShape(try encodeRoom(t), lists: true))
        XCTAssertEqual(t, fromFirebase)
        var p = t
        for uid in pair.players { p = try MPRules.ready(p, match: pair.id, uid: uid, value: true) }
        p = MPRules.startReady(p, match: pair.id)
        let authority = p.authority(pair)
        XCTAssertThrowsError(try MPRules.finish(p, match: pair.id, actor: authority, a: 5, b: 4))
        XCTAssertThrowsError(try MPRules.finish(p, match: pair.id, actor: authority, scores: [5, 4], placement: [pair.a, pair.b]))
        XCTAssertFalse(MPRules.validFinal(p, target: p.target, scores: [5, 4]))
        XCTAssertTrue(MPRules.validFinal(p, target: p.target, scores: [4, 6]))
        let done = try MPRules.finish(p, match: pair.id, actor: authority, a: 4, b: 6)
        XCTAssertTrue(done.complete)
        XCTAssertEqual(pair.b, MPKnockout.winner(done))
        XCTAssertEqual([pair.b, pair.a], done.matches[pair.id]?.placement)
        XCTAssertEqual("You won the tournament!", MPCompletionText.headline(done, pair.b, hebrew: false))
        XCTAssertEqual("Tournament finished. You placed 2nd.", MPCompletionText.headline(done, pair.a, hebrew: false))
        XCTAssertEqual([1, 2], [pair.b, pair.a].map { MPCompletionText.place(done, $0) })
        let out = a.players[2]
        XCTAssertEqual(0, MPCompletionText.place(done, out))
        let winnerName = done.participants[pair.b]?.identity.name ?? ""
        XCTAssertEqual("Tournament finished. Winner: \(winnerName)", MPCompletionText.headline(done, out, hebrew: false))
        let refinished = try MPRules.finish(done, match: pair.id, actor: authority, a: 6, b: 4)
        XCTAssertEqual(done, refinished)
        // ...or the pair's opponent leaves too: the last player standing takes the tournament without a score.
        let walkover = try MPRules.leave(p, actor: pair.b)
        XCTAssertTrue(walkover.complete)
        XCTAssertEqual(pair.a, MPKnockout.winner(walkover))
        XCTAssertTrue(MPCompletionText.won(walkover, pair.a))
        XCTAssertEqual(MPMatchPhase.cancelled, walkover.matches[pair.id]?.phase)
        XCTAssertEqual([0, 0], walkover.matches[pair.id]?.scores)
        XCTAssertEqual("You won the tournament!", MPCompletionText.headline(walkover, pair.a, hebrew: false))
    }

    // Kotlin: houseOnlyTablesAreSimulatedOnceInTheTransitionThatCreatesThem
    func testHouseOnlyTablesAreSimulatedOnceInTheTransitionThatCreatesThem() throws {
        var s = try MPRules.start(tournament(6, 4, .roundRobin, legs: 2), actor: "h0")
        let houseTables = s.matches.values.filter { MPRules.houseOnly(s, $0) }
        XCTAssertEqual(2, houseTables.count)                                                           // one per leg: 6 players, 3 tables of 4
        for m in houseTables {
            XCTAssertEqual(MPMatchPhase.finished, m.phase)
            XCTAssertEqual(0, m.starts)
            XCTAssertEqual(4, m.players.count)
            XCTAssertTrue(MPRules.validFinal(s, target: s.target, scores: m.scores))
            XCTAssertTrue(MPRules.validPlacement(m, m.scores, m.placement))
            XCTAssertEqual(m.placement.first, m.winner)
            var fresh = m
            fresh.phase = .waiting
            fresh.scores = Array(repeating: 0, count: 4)
            fresh.winner = ""
            fresh.placement = []
            XCTAssertEqual(m, MPRules.simulated(s, fresh))
        }
        var rng = MPKotlinRandom(intSeed: 9)
        while let m = openTables(s).first { s = try play(s, m.id, rng.shuffled(m.players)) }
        XCTAssertTrue(s.complete)
        for m in houseTables { XCTAssertEqual(m, s.matches[m.id]) }
        XCTAssertEqual(6 * (3 + 2 + 1 + 0), MPRules.standings(s).reduce(0) { $0 + $1.points })
        // Knockout: house-only tables finish when drawn; settling again never replays them.
        var k = try MPRules.start(tournament(9, 3, .knockout, createdAt: 4), actor: "h0")
        let settled = try MPKnockout.settle(k)
        XCTAssertEqual(k, settled)
        let r0 = MPKnockout.matches(k, 0)
        XCTAssertEqual(2, r0.filter { $0.phase == .finished }.count)
        XCTAssertEqual(1, r0.filter { !$0.terminal }.count)
        let mine = try XCTUnwrap(r0.first(where: { !$0.terminal }))
        k = try play(k, mine.id, ["h0"] + mine.players.filter { $0 != "h0" })
        for m in r0 where m.terminal { XCTAssertEqual(m, k.matches[m.id]) }
        let r1 = MPKnockout.matches(k, 1)
        XCTAssertEqual([3, 3], r1.map { $0.players.count })
        XCTAssertTrue(r1.filter { !$0.contains("h0") }.allSatisfy { $0.phase == .finished })
        XCTAssertEqual(MPMatchPhase.waiting, r1.first(where: { $0.contains("h0") })?.phase)
        // Once the human is out, the house players finish the tournament in that same transition.
        let last = try XCTUnwrap(r1.first(where: { $0.contains("h0") }))
        k = try play(k, last.id, last.players.filter { $0 != "h0" } + ["h0"])
        XCTAssertTrue(k.complete)
        XCTAssertEqual("FINISHED", k.state)
        XCTAssertEqual(3, k.rounds.count)
        let champion = try XCTUnwrap(MPKnockout.winner(k))
        XCTAssertTrue(champion.hasPrefix("bot_"))
        XCTAssertFalse(MPCompletionText.won(k, "h0"))
        let finals = MPKnockout.matches(k, 2)
        XCTAssertEqual(1, finals.count)
        XCTAssertEqual(MPMatchPhase.finished, finals.first?.phase)
        let championName = k.participants[champion]?.name(hebrew: false) ?? ""
        XCTAssertEqual("Tournament finished. Winner: \(championName)", MPCompletionText.headline(k, "h0", hebrew: false))
        // The finished knockout follows the no-save policy too.
        let suite = "GroupTournamentTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let book = MPPreferences(defaults)
        book.remember(try MPRules.start(tournament(9, 3, .knockout, createdAt: 4), actor: "h0"))
        XCTAssertEqual([k.id], book.rooms.map { $0.id })
        book.remember(k)                                                                                // Kotlin book.collect(saved, k, "h0", 0)
        XCTAssertTrue(book.completionKnown(k))
        XCTAssertTrue(book.rooms.isEmpty)
        XCTAssertNil(book.rooms.first(where: { $0.id == k.id }))
    }

    // Kotlin: classicTableSizeTwoTournamentsKeepTheirPairsDrawsAndWire
    func testClassicTableSizeTwoTournamentsKeepTheirPairsDrawsAndWire() throws {
        for format in MPTournamentFormat.allCases {
            let plain = createRoom("GRP234", .tournament, MPIdentity(id: "h0", name: "Host"), 6, 2, 3, 1, 0, 5, format: format)
            let sized = createRoom("GRP234", .tournament, MPIdentity(id: "h0", name: "Host"), 6, 2, 3, 1, 0, 5, format: format, tableSize: 2)
            XCTAssertEqual(plain, sized)
            XCTAssertFalse(plain.grouped)
            XCTAssertEqual(2, plain.tableSize)
            let s = try MPRules.start(tournament(6, 2, format, humans: 2, legs: 2), actor: "h0")
            XCTAssertFalse(s.grouped)
            XCTAssertTrue(s.matches.values.allSatisfy { $0.players.count == 2 })
            if format == .knockout {
                XCTAssertTrue(s.rounds.values.allSatisfy { $0.groups.isEmpty && $0.byes.isEmpty })
                let r0 = try XCTUnwrap(s.rounds[0])
                var chunks: [[String]] = []
                var index = 0
                while index < r0.players.count {
                    chunks.append(Array(r0.players[index..<min(index + 2, r0.players.count)]))
                    index += 2
                }
                XCTAssertEqual(chunks, r0.tables)
                let classicWire = try encodeRoom(s)
                let rounds = (classicWire["rounds"] as? [String: Any]) ?? [:]
                for raw in rounds.values {
                    let keys = Set(((raw as? [String: Any]) ?? [:]).keys)
                    XCTAssertEqual(Set(["count", "players"]), keys)
                }
                XCTAssertEqual("Quarterfinals", MPKnockout.stage(s, hebrew: false))
                XCTAssertEqual("Your match this round", MPKnockout.playerStatus(s, "h0", hebrew: false))
            } else {
                XCTAssertEqual(30, s.matches.count)
                let digits = ["0", "1", "2", "3", "4", "5"]
                for key in s.matches.keys {                                                            // Kotlin Regex("GRP234_[01]_[0-5]_[0-5]")
                    let parts = key.components(separatedBy: "_")
                    let matches = parts.count == 4 && parts[0] == "GRP234" && ["0", "1"].contains(parts[1])
                        && digits.contains(parts[2]) && digits.contains(parts[3])
                    XCTAssertTrue(matches, key)
                }
                let rows = MPRules.standings(s)
                XCTAssertTrue(rows.allSatisfy { $0.points == 3 * $0.wins })
                XCTAssertTrue(rows.contains(where: { $0.wins > 0 }))                                    // house pairs played at the start
            }
            let decoded = try roundTrip(s)
            XCTAssertEqual(s, decoded)
        }
    }

    // ---- Texts ----

    // Kotlin: groupStagesStatusesAndCompletionTextsInBothLanguages
    func testGroupStagesStatusesAndCompletionTextsInBothLanguages() throws {
        let stages = ["Round of 9", "Semifinal tables", "Semifinal tables", "Semifinal tables", "Semifinal tables", "Final", "Final", "Final"]
        XCTAssertEqual(stages, [9, 8, 7, 6, 5, 4, 3, 2].map { MPGroupTournament.stage($0, 3, hebrew: false) })
        XCTAssertEqual("סיבוב של 9 שחקנים", MPGroupTournament.stage(9, 4, hebrew: true))
        XCTAssertEqual("שולחנות חצי הגמר", MPGroupTournament.stage(6, 3, hebrew: true))
        XCTAssertEqual("הגמר", MPGroupTournament.stage(4, 4, hebrew: true))
        var s = try MPRules.start(tournament(9, 3, .knockout, humans: 9, createdAt: 11), actor: "h0")
        XCTAssertEqual("Round of 9", MPKnockout.stage(s, hebrew: false))
        XCTAssertEqual("סיבוב של 9 שחקנים", MPKnockout.stage(s, hebrew: true))
        let t = try XCTUnwrap(MPKnockout.matches(s, 0).first)
        XCTAssertEqual(3, t.players.count)
        guard t.players.count >= 3 else { return }
        let winner = t.players[0]
        let runner = t.players[1]
        let third = t.players[2]
        for uid in t.players {
            XCTAssertEqual("Your table this round: the top two advance.", MPKnockout.playerStatus(s, uid, hebrew: false))
            XCTAssertEqual("השולחן שלכם בסיבוב הזה: שני הראשונים עולים.", MPKnockout.playerStatus(s, uid, hebrew: true))
        }
        s = try play(s, t.id, t.players)
        for uid in [winner, runner] {
            XCTAssertEqual("You reached the semifinal tables! Waiting for the other tables.", MPKnockout.playerStatus(s, uid, hebrew: false))
            XCTAssertEqual("העפלת לשולחנות חצי הגמר! ממתינים לשאר השולחנות.", MPKnockout.playerStatus(s, uid, hebrew: true))
        }
        XCTAssertEqual("You have been eliminated. You can follow the remaining rounds.", MPKnockout.playerStatus(s, third, hebrew: false))
        XCTAssertEqual("סיימת את השתתפותך. אפשר לצפות בהמשך הטורניר.", MPKnockout.playerStatus(s, third, hebrew: true))
        for m in MPKnockout.matches(s, 0) where !m.terminal { s = try play(s, m.id, m.players) }
        XCTAssertEqual("Semifinal tables", MPKnockout.stage(s, hebrew: false))
        XCTAssertEqual(6, s.rounds[1]?.players.count)
        let semi = try XCTUnwrap(MPKnockout.matches(s, 1).first)
        s = try play(s, semi.id, semi.players)
        XCTAssertEqual("You reached the final! Waiting for the other tables.", MPKnockout.playerStatus(s, semi.players[0], hebrew: false))
        XCTAssertEqual("העפלת לגמר! ממתינים לשאר השולחנות.", MPKnockout.playerStatus(s, semi.players[1], hebrew: true))
        for m in MPKnockout.matches(s, 1) where !m.terminal { s = try play(s, m.id, m.players) }
        XCTAssertEqual("Final", MPKnockout.stage(s, hebrew: false))
        XCTAssertEqual("הגמר", MPKnockout.stage(s, hebrew: true))
        let finals = MPKnockout.matches(s, 2)
        XCTAssertEqual(1, finals.count)
        let finalTable = try XCTUnwrap(finals.first)
        XCTAssertEqual(4, finalTable.players.count)
        guard finalTable.players.count == 4 else { return }
        XCTAssertEqual("You reached the final!", MPKnockout.advanceText(s, semi, hebrew: false))
        s = try play(s, finalTable.id, finalTable.players)
        XCTAssertTrue(s.complete)
        let champion = finalTable.players[0]
        let second = finalTable.players[1]
        let bronze = finalTable.players[2]
        let fourth = finalTable.players[3]
        XCTAssertEqual("You won the tournament!", MPCompletionText.headline(s, champion, hebrew: false))
        XCTAssertEqual("ניצחת בטורניר!", MPCompletionText.headline(s, champion, hebrew: true))
        XCTAssertEqual(["Tournament finished. You placed 2nd.", "Tournament finished. You placed 3rd.", "Tournament finished. You placed 4th."],
                       [second, bronze, fourth].map { MPCompletionText.headline(s, $0, hebrew: false) })
        XCTAssertEqual("הטורניר הסתיים. סיימתם במקום ה־2.", MPCompletionText.headline(s, second, hebrew: true))
        XCTAssertEqual([1, 2, 3, 4], finalTable.players.map { MPCompletionText.place(s, $0) })
        XCTAssertEqual(0, MPCompletionText.place(s, third))
        let name = s.participants[champion]?.identity.name ?? ""
        XCTAssertEqual("Tournament finished. Winner: \(name)", MPCompletionText.headline(s, third, hebrew: false))
        XCTAssertEqual("הטורניר הסתיים. המנצח: \(name)", MPCompletionText.headline(s, third, hebrew: true))
        XCTAssertTrue(MPCompletionText.won(s, champion))
        XCTAssertFalse(MPCompletionText.won(s, second))
        // Five players: a table of three and a walkover pair that advances without playing (no byes).
        let five = try MPRules.start(tournament(5, 4, .knockout, humans: 5, createdAt: 2), actor: "h0")
        let walkovers = five.rounds[0]?.walkovers ?? []
        XCTAssertEqual(1, walkovers.count)
        let rest = walkovers.first ?? []
        XCTAssertEqual("Semifinal tables", MPKnockout.stage(five, hebrew: false))
        for uid in rest {
            XCTAssertEqual("Your table advances without playing. Waiting for the other tables.", MPKnockout.playerStatus(five, uid, hebrew: false))
            XCTAssertEqual("השולחן שלכם עולה לסיבוב הבא בלי לשחק. ממתינים לשאר השולחנות.", MPKnockout.playerStatus(five, uid, hebrew: true))
        }
        let fiveTables = MPKnockout.matches(five, 0)
        XCTAssertEqual(1, fiveTables.count)
        let table = try XCTUnwrap(fiveTables.first)
        let after = try play(five, table.id, table.players)
        XCTAssertEqual(Set(rest).union(table.players.prefix(2)), Set(after.rounds[1]?.players ?? []))
        XCTAssertEqual("Final", MPKnockout.stage(after, hebrew: false))
        XCTAssertEqual("You reached the final!", MPKnockout.advanceText(after, table, hebrew: false))
        XCTAssertEqual("העפלת לגמר!", MPKnockout.advanceText(after, table, hebrew: true))
        XCTAssertEqual("Your table this round: the winner takes the tournament.", MPKnockout.playerStatus(after, rest.first ?? "", hebrew: false))
        XCTAssertEqual("You have been eliminated. You can follow the remaining rounds.", MPKnockout.playerStatus(after, table.players[2], hebrew: false))
    }

    // Kotlin: anyTableSummaryKeepsSeatOrderBeforeItsStateInBothDirections
    func testAnyTableSummaryKeepsSeatOrderBeforeItsStateInBothDirections() {
        let lineups: [[String]] = [["Player", "שחקן", "מיניק"], ["שחקן", "Player", "Bob", "מיניק"], ["Player", "שחקן"]]
        for rtl in [false, true] {
            for names in lineups {
                for state in ["Finished", "הסתיים"] {
                    let line = visualOrder(MPMatchText.summary(names, state), rtl: rtl)
                    let at = names.map { (name: String) -> Int in
                        let first = name.unicodeScalars.first?.value ?? 0
                        let latin = first >= 0x41 && first <= 0x7A                                    // Kotlin 'A'..'z'
                        return offset(of: latin ? name : String(name.reversed()), in: line)
                    }
                    let ordered = zip(at, at.dropFirst()).allSatisfy { $0.0 < $0.1 }
                    XCTAssertTrue(at.allSatisfy { $0 >= 0 } && ordered, line)
                    let stateText = state == "Finished" ? state : String(state.reversed())
                    XCTAssertTrue((at.last ?? -1) < offset(of: stateText, in: line), line)
                }
            }
        }
        // Not ported: assertEquals(MatchText.summary("A","B","x"), MatchText.summary(listOf("A","B"),"x")) — MPMatchText has only the
        // list overload of summary (the two-name form is its names.count == 2 branch).
    }
}
