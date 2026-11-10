import Foundation

// Android multiplayer/GroupMatch.kt and multiplayer/CrossFixture.kt (MinikCrossPong 828c6fc). Simulations and shuffles use
// Kotlin's random sequence (MPKotlinRandom), so a house-only table or a stored round-robin draw equals Android's for the same
// seed / room code and creation time.

/// House-only 3/4-player fixture under the cross scoring rules (CROSS_DESIGN §3), deterministic from the seed. Every rally ends
/// exactly once: a fault (net, out, bad serve) costs that player one point, floored at zero; a missed return gives the striker
/// one point and costs the responsible receiver one, floored at zero. The serve rotates every rally from seat `seed mod n`; the
/// first player to reach the target wins at once. Each house player's strength weights how often a player faults and how often
/// they return a ball.
enum MPTableSimulation {
    /// One simulated rally for rule checks: a fault by `striker`, or `receiver` missed `striker`'s ball.
    struct Rally: Equatable {
        var server: Int; var striker: Int; var receiver: Int?; var fault: Bool; var before: [Int]; var after: [Int]
    }
    /// Safety bound only; past it the current leader converts the remaining points as missed returns.
    static let maxRallies = 5000
    private static let maxHits = 40
    static func faultChance(_ skill: Double) -> Double { (0.08 - 0.006 * skill).mpClamp(0.015, 0.09) }
    static func returnChance(_ receiver: Double, _ striker: Double) -> Double { (0.55 + 0.035 * receiver - 0.01 * (striker - 6)).mpClamp(0.35, 0.92) }
    static func play(_ players: [String], _ bots: [MPBot], target: Int, seed: Int64, trace: ((Rally) -> Void)? = nil) -> MPTableResult {
        let n = players.count
        guard (3...4).contains(n), bots.count == n else { return MPTableResult(scores: Array(repeating: 0, count: n), placement: players) }
        let goal = max(1, target)
        var rng = MPKotlinRandom(seed: seed)
        let skill = bots.map { $0.safe().strength }
        var scores = Array(repeating: 0, count: n), faults = scores, won = scores
        // Ties: fewer faults, then more points won, then seat order.
        func ranking() -> [Int] {
            (0..<n).sorted { a, b in
                if scores[a] != scores[b] { return scores[a] > scores[b] }
                if faults[a] != faults[b] { return faults[a] < faults[b] }
                if won[a] != won[b] { return won[a] > won[b] }
                return a < b
            }
        }
        var server = Int(crossMod(seed, Int64(n))), rallies = 0
        while !scores.contains(where: { $0 >= goal }) {
            let before = scores
            var striker = server, receiver: Int?, fault = false, hits = 0
            if rallies >= maxRallies { striker = ranking()[0]; receiver = (striker + 1) % n }
            else {
                while true {
                    if rng.nextDouble() < faultChance(skill[striker]) { fault = true; break }
                    let next = (striker + 1 + rng.nextIndex(n - 1)) % n
                    if hits >= maxHits || rng.nextDouble() >= returnChance(skill[next], skill[striker]) { receiver = next; break }
                    striker = next; hits += 1
                }
            }
            if fault { scores[striker] = max(0, scores[striker] - 1); faults[striker] += 1 }
            else if let r = receiver { scores[striker] += 1; won[striker] += 1; scores[r] = max(0, scores[r] - 1) }
            trace?(Rally(server: server, striker: striker, receiver: receiver, fault: fault, before: before, after: scores))
            rallies += 1; server = (server + 1) % n
        }
        return MPTableResult(scores: scores, placement: ranking().map { players[$0] })
    }

    /// One ELIMINATION rally: the seats still in before it, who won a point (`scorer`: the striker of a missed return) and who lost
    /// one (`loser`: a fault's striker or the receiver who missed), every score before and after it (a player who is out keeps the
    /// score they went out with), who went out on it, and whether the seats left restarted from 0.
    struct Step: Equatable {
        var alive: [Int]; var scorer: Int?; var loser: Int; var before: [Int]; var after: [Int]; var out: Int?; var reset: Bool
    }
    /// House-only ELIMINATION table ("losers drop out"), deterministic from the seed, played until two are left (a table that must
    /// produce one winner then hands them to a classic duel, `MPRules.withDuel`). Rallies are drawn like `play` among the seats
    /// still in, and the serve rotates among them. A player whose score would drop below 0 is out at once. When anybody reaches
    /// the target, the unique lowest score is out (a tie for the lowest plays on, scores capped at the target, until it breaks) and
    /// the others restart from 0; a drop-out in that same rally is the stage's elimination. Placement: the two survivors by score
    /// (the last stage's scores), then everybody else from the last out to the first.
    static func elimination(_ players: [String], _ bots: [MPBot], target: Int, seed: Int64, trace: ((Step) -> Void)? = nil) -> MPTableResult {
        let n = players.count
        guard (3...4).contains(n), bots.count == n else { return MPTableResult(scores: Array(repeating: 0, count: n), placement: players) }
        let goal = max(1, target)
        var rng = MPKotlinRandom(seed: seed)
        let skill = bots.map { $0.safe().strength }
        var scores = Array(repeating: 0, count: n)
        var alive = Array(0..<n)
        var out: [Int] = []
        var server = Int(crossMod(seed, Int64(n))), rallies = 0, decider = false
        func nextSeat(_ from: Int) -> Int {
            for step in 1...n where alive.contains((from + step) % n) { return (from + step) % n }
            return from
        }
        while alive.count > 2 {
            if !alive.contains(server) { server = nextSeat(server) }
            let before = scores, seated = alive
            var striker = server, receiver: Int?, fault = false, hits = 0
            if rallies >= maxRallies {
                // Safety bound only: the leader wins a point off the lowest score.
                let order = alive.sorted { scores[$0] != scores[$1] ? scores[$0] > scores[$1] : $0 < $1 }
                striker = order[0]; receiver = order[order.count - 1]
            } else {
                while true {
                    if rng.nextDouble() < faultChance(skill[striker]) { fault = true; break }
                    let others = alive.filter { $0 != striker }
                    let next = others[rng.nextIndex(others.count)]
                    if hits >= maxHits || rng.nextDouble() >= returnChance(skill[next], skill[striker]) { receiver = next; break }
                    striker = next; hits += 1
                }
            }
            let loser = fault ? striker : (receiver ?? striker)
            if !fault { scores[striker] = min(goal, scores[striker] + 1) }
            var gone: Int?
            if scores[loser] == 0 { gone = loser } else { scores[loser] -= 1 }
            let stage = decider || alive.contains { scores[$0] >= goal }
            if let leaving = gone { alive.removeAll { $0 == leaving } }
            else if stage {
                decider = true
                let low = alive.map { scores[$0] }.min() ?? 0
                let lowest = alive.filter { scores[$0] == low }
                if lowest.count == 1 { gone = lowest[0]; alive.removeAll { $0 == lowest[0] } }
            }
            var reset = false
            if let leaving = gone {
                out.append(leaving)
                if stage { decider = false }
                // A new stage starts from 0; the two survivors keep the last stage's scores.
                if alive.count > 2 && stage { for p in alive { scores[p] = 0 }; reset = true }
            }
            trace?(Step(alive: seated, scorer: fault ? nil : striker, loser: loser, before: before, after: scores, out: gone, reset: reset))
            rallies += 1; server = nextSeat(server)
        }
        let survivors = alive.sorted { scores[$0] != scores[$1] ? scores[$0] > scores[$1] : $0 < $1 }
        return MPTableResult(scores: scores, placement: (survivors + out.reversed()).map { players[$0] })
    }
}

/// Three/four-player TOURNAMENT tables. A tournament's tableSize 2 keeps the classic pair formats exactly; 3 or 4 seats every
/// fixture at one cross table (`MPSession.grouped`).
/// - Round robin, "balanced tables": a stored, seeded set of tables of tableSize players (one smaller table only when there are
///   fewer players) in which every pair shares a table and everybody plays the same number of tables when possible, otherwise
///   within one. Two legs repeat the set with every table's seats rotated. Standings award placement points per finished table:
///   3, 2, 1, 0, from each table's stored placement (an ELIMINATION table's two survivors are ordered by their final duel).
/// - Knockout (`MPKnockout`): every round is redrawn into tables of 3 and 4 without byes (`split`); each table sends
///   `MPSession.advance` players through (1 or 2), a table no larger than that is a walkover; 2...4 players play one final table
///   (2 a classic pair final) whose winner takes the tournament.
enum MPGroupTournament {
    static let maxTable = 4
    static let minPlayers = 3
    static let maxRoundRobin = 8
    /// The balanced round-robin covering is searched for at most this many players.
    static let maxDesign = 9
    /// Standings points for 1st, 2nd, 3rd and 4th place at a finished table.
    static let placePoints = [3, 2, 1, 0]
    static func tableSize(_ requested: Int) -> Int { min(maxTable, max(2, requested)) }
    static func capacity(_ requested: Int, _ format: MPTournamentFormat) -> Int {
        min(format == .knockout ? MPKnockout.maxPlayers : maxRoundRobin, max(minPlayers, requested))
    }
    private static var designs: [Int: [[Int]]] = [:]
    /// Seat indices of a balanced round-robin set for `players` (3...9) at tables of min(`size`, players): every pair shares a
    /// table; nobody plays more tables than the covering needs; everybody plays the same number when that adds no table for the
    /// busiest player, otherwise within one; then the fewest tables and the fewest repeated meetings. Deterministic and computed
    /// once per shape.
    static func design(_ players: Int, _ size: Int) -> [[Int]] {
        guard (minPlayers...maxDesign).contains(players), (3...maxTable).contains(size) else { return [] }
        let key = players * 10 + size
        if let cached = designs[key] { return cached }
        let value = balanced(players, min(size, players))
        designs[key] = value
        return value
    }
    private static func balanced(_ n: Int, _ k: Int) -> [[Int]] {
        if n == k { return [Array(0..<n)] }
        let least = (n + k - 3) / (k - 1)                       // everybody meets n-1 others, k-1 per table
        for load in least...(least + n) {
            let low = max(least, load - 1)
            var shapes: [(tables: Int, low: Int, high: Int)] = []
            if n * load % k == 0 { shapes.append((n * load / k, load, load)) }
            if low < load {
                for tables in stride(from: (n * low + k - 1) / k, through: n * load / k, by: 1) where tables * k != n * low && tables * k != n * load {
                    shapes.append((tables, low, load))
                }
            }
            for shape in shapes where shape.tables >= 1 {
                for meetings in 1...shape.tables {
                    if shape.tables * k * (k - 1) > meetings * n * (n - 1) { continue }   // more pair slots than allowed meetings
                    if let found = cover(n, k, tables: shape.tables, low: shape.low, high: shape.high, meetings: meetings) { return found }
                }
            }
        }
        return [Array(0..<n)]
    }
    /// Depth-first search: the first unmet pair chooses the next table; once everybody has met, the remaining tables follow in
    /// index order. The first table is seats 0..k-1 by symmetry.
    private static func cover(_ n: Int, _ k: Int, tables: Int, low: Int, high: Int, meetings: Int) -> [[Int]]? {
        let blocks = combinations(n, k, 0)
        var load = Array(repeating: 0, count: n)
        var meet = Array(repeating: Array(repeating: 0, count: n), count: n)
        var chosen: [Int] = []
        func put(_ b: Int, _ d: Int) {
            for x in blocks[b] {
                load[x] += d
                for y in blocks[b] where x != y { meet[x][y] += d }
            }
        }
        func fits(_ b: Int) -> Bool {
            !chosen.contains(b) && blocks[b].allSatisfy { x in load[x] < high && blocks[b].allSatisfy { y in x == y || meet[x][y] < meetings } }
        }
        func hopeful() -> Bool {
            let left = tables - chosen.count
            var seats = 0, open = 0
            for x in 0..<n {
                let unmet = (0..<n).filter { $0 != x && meet[x][$0] == 0 }.count
                open += unmet
                let more = max(low - load[x], (unmet + k - 2) / (k - 1))
                if more > high - load[x] { return false }
                seats += more
            }
            return seats <= left * k && open / 2 <= left * k * (k - 1) / 2
        }
        func search(_ from: Int) -> Bool {
            if chosen.count == tables {
                return load.allSatisfy { $0 >= low } && (0..<n).allSatisfy { x in (0..<n).allSatisfy { y in x == y || meet[x][y] > 0 } }
            }
            if !hopeful() { return false }
            var gap: (Int, Int)?
            outer: for x in 0..<n {
                for y in (x + 1)..<max(x + 1, n) where meet[x][y] == 0 { gap = (x, y); break outer }
            }
            let options: [Int]
            if let gap { options = blocks.indices.filter { blocks[$0].contains(gap.0) && blocks[$0].contains(gap.1) } }
            else { options = from < blocks.count ? Array(from..<blocks.count) : [] }
            for b in options {
                if (chosen.isEmpty && b != 0) || !fits(b) { continue }
                put(b, 1); chosen.append(b)
                if search(gap == nil ? b + 1 : 0) { return true }
                chosen.removeLast(); put(b, -1)
            }
            return false
        }
        return search(0) ? chosen.map { blocks[$0] } : nil
    }
    private static func combinations(_ n: Int, _ k: Int, _ from: Int) -> [[Int]] {
        if k == 0 { return [[]] }
        guard from <= n - k else { return [] }
        return (from...(n - k)).flatMap { first in combinations(n, k - 1, first + 1).map { [first] + $0 } }
    }
    /// The stored round-robin tables: the balanced set relabelled by a shuffle seeded by the code and creation time; a second leg
    /// repeats every table with its seats rotated by one.
    static func schedule(_ s: MPSession) -> [String: MPFixture] {
        let ids = s.roster
        guard s.grouped, (minPlayers...maxRoundRobin).contains(ids.count) else { return [:] }
        var random = MPKotlinRandom(seed: crossFold("\(s.code):\(s.createdAt):tables", 29))
        let order = random.shuffled(ids)
        let tables = design(ids.count, s.tableSize).map { t in t.map { order[$0] } }
        var result: [String: MPFixture] = [:]
        for leg in 0..<s.legs {
            for (i, t) in tables.enumerated() where !t.isEmpty {
                let id = "\(s.code)_T\(leg)_\(i)"
                let turn = leg % t.count
                result[id] = MPFixture(id: id, players: Array(t.dropFirst(turn)) + Array(t.prefix(turn)), seed: crossFold(id, 17))
            }
        }
        return result
    }
    /// Placement points per finished table; ties: tables won, then total score, then participant id (fault counts are not stored
    /// with a result). Cancelled tables count for nobody. A table with a final duel counts once the duel is over: its winner 1st,
    /// its loser 2nd, then the others as stored.
    static func standings(_ s: MPSession) -> [MPStanding] {
        var rows = Dictionary(uniqueKeysWithValues: s.participants.keys.map { ($0, MPStanding(id: $0)) })
        for m in s.matches.values where m.phase == .finished && !MPRules.isDuel(m) {
            guard let ranking = MPRules.ranking(s, m) else { continue }
            let first = MPRules.finalWinner(s, m)
            for id in m.players {
                guard var row = rows[id] else { continue }
                let win = id == first
                let place = ranking.firstIndex(of: id) ?? -1
                row.played += 1; row.wins += win ? 1 : 0; row.losses += win ? 0 : 1
                row.points += place >= 0 && place < placePoints.count ? placePoints[place] : 0
                row.pointsFor += m.scoreOf(id)
                rows[id] = row
            }
        }
        return rows.values.sorted {
            if $0.points != $1.points { return $0.points > $1.points }
            if $0.wins != $1.wins { return $0.wins > $1.wins }
            if $0.pointsFor != $1.pointsFor { return $0.pointsFor > $1.pointsFor }
            return $0.id < $1.id
        }
    }
    /// Knockout table sizes for `players`, largest first, nobody resting: 2...4 players share one final table (2 play a classic
    /// pair); five play 3+2; from six on only tables of 3 and 4, with as many tables of the preferred `size` as possible (4: the
    /// fewest tables; 3: fours only where threes would leave a remainder).
    static func split(_ players: Int, _ size: Int) -> [Int] {
        if players <= 4 { return players >= 2 ? [players] : [] }
        if players == 5 { return [3, 2] }
        let options = (0...(players / 4)).filter { (players - 4 * $0) % 3 == 0 }
            .map { fours in Array(repeating: 4, count: fours) + Array(repeating: 3, count: (players - 4 * fours) / 3) }
        var best: [Int] = options.first ?? [players]
        var bestCount = best.filter { $0 == size }.count
        for option in options.dropFirst() {
            let count = option.filter { $0 == size }.count
            if count > bestCount { best = option; bestCount = count }
        }
        return best
    }
    /// Players in the next knockout round when every table of `players` finishes: `advance` per table, every player of a smaller
    /// table (a walkover); the final table produces one champion.
    static func advancing(_ players: Int, _ size: Int, advance: Int = 2) -> Int {
        if players <= 4 { return min(players, 1) }
        return split(players, size).reduce(0) { $0 + min($1, advance) }
    }
    static func stage(_ players: Int, _ size: Int, hebrew he: Bool, advance: Int = 2) -> String {
        if players <= 4 { return MPText.t("Final", "הגמר", he) }
        if advancing(players, size, advance: advance) <= 4 { return MPText.t("Semifinal tables", "שולחנות חצי הגמר", he) }
        return MPText.t("Round of \(players)", "סיבוב של \(players) שחקנים", he)
    }
}

/// How a room fixture is played on the cross table: the room's game type, the fixture's goal and its target. Every fixture of 3
/// or 4 players and (Android b0cdeb3) the elimination final duel use the cross table; other two-player fixtures (pairs,
/// two-player tie-breaks) are the classic game.
enum MPCrossFixture {
    static func mode(_ s: MPSession) -> CrossMode { s.gameMode == .elimination ? .elimination : .winnerTakesAll }
    /// An elimination table always plays until two are left: they go through together, or meet in the final duel, which is won
    /// outright (Android 1fc4bc2).
    static func goal(_ s: MPSession, _ m: MPFixture) -> CrossGoal {
        if m.goal == .tiebreak { return .tiebreak }
        if m.players.count == 2 { return .win }
        if s.gameMode == .elimination { return .topTwo }
        return .win
    }
    static func target(_ s: MPSession, _ m: MPFixture) -> Int { MPRules.fixtureTarget(s, m) }
    static func usesCross(_ m: MPFixture) -> Bool { m.players.count >= 3 || MPRules.isDuel(m) }
}
