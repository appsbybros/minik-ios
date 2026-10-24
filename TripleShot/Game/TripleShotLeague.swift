import Foundation

// Port of game/TripleShotLeague.kt (Android snapshot dd722e5), statement by statement.
// Kotlin `require` (IllegalArgumentException) becomes a thrown `RuleError`: every Android caller
// (league screen, team-match result, store) catches it. `Season` and `Result` validate in their
// throwing initialisers, and `Season.copy` re-validates like the Kotlin data-class `copy`.
// Sorting is stable, `minWith` keeps the first minimum, random draws follow the Kotlin order.

/** Local house-team league. Only finished on-court games advance the owner's fixtures. */
enum TripleShotLeague {

    /// Kotlin `IllegalArgumentException` (`require`), `IllegalStateException` (`check`) and the
    /// `NullPointerException` of `!!`, as thrown inside callers that catch them.
    enum RuleError: Error, Equatable {
        case illegalArgument(String)
        case illegalState(String)
        case nullPointer(String)
    }

    /// Kotlin `require(value)`.
    static func require(_ value: Bool, _ message: @autoclosure () -> String = "Failed requirement.") throws {
        if !value { throw RuleError.illegalArgument(message()) }
    }

    /// Kotlin `check(value) { message }`.
    static func check(_ value: Bool, _ message: @autoclosure () -> String = "Check failed.") throws {
        if !value { throw RuleError.illegalState(message()) }
    }

    static let palette: [Int] = [
        Int(Int32(bitPattern: 0xff76d8ff)), Int(Int32(bitPattern: 0xffffb779)), Int(Int32(bitPattern: 0xffc6a0ff)),
        Int(Int32(bitPattern: 0xff80e4bd)), Int(Int32(bitPattern: 0xffff97bd)), Int(Int32(bitPattern: 0xfff5d66f))
    ]

    struct Team: Hashable {
        var id: Int
        var name: String
        var color: Int
        var roster: [String]
        var strength: Int
    }

    struct Fixture: Hashable {
        var round: Int
        var home: Int
        var away: Int

        var key: String { return "\(round)-\(home)-\(away)" }
    }

    /// Immutable like the Kotlin data class: an instance is always valid.
    struct Result: Hashable {
        let fixture: Fixture
        let homeScore: Int
        let awayScore: Int

        init(fixture: Fixture, homeScore: Int, awayScore: Int) throws {
            self.fixture = fixture
            self.homeScore = homeScore
            self.awayScore = awayScore
            try TripleShotLeague.require(
                homeScore >= 0 && homeScore <= 999 && awayScore >= 0 && awayScore <= 999 && homeScore != awayScore
            )
        }
    }

    /// Immutable like the Kotlin data class; `copy(...)` runs the validation again.
    struct Season: Hashable {
        let id: String
        let seed: Int64
        let number: Int
        let createdAt: Int64
        let teams: [Team]
        let results: [Result]
        let matchSeconds: Int

        init(
            id: String,
            seed: Int64,
            number: Int,
            createdAt: Int64,
            teams: [Team],
            results: [Result] = [],
            matchSeconds: Int = 0
        ) throws {
            self.id = id
            self.seed = seed
            self.number = number
            self.createdAt = createdAt
            self.teams = teams
            self.results = results
            self.matchSeconds = matchSeconds
            try TripleShotLeague.require([0, 120, 180, 300].contains(matchSeconds))
            try TripleShotLeague.require(matchSeconds != 0 || results.allSatisfy { max($0.homeScore, $0.awayScore) >= 11 })
            try TripleShotLeague.require(!id.kotlinIsBlank && teams.count == 8 && teams.map { $0.id } == Array(0...7))
            try TripleShotLeague.require(teams.allSatisfy { $0.roster.count >= 2 && $0.roster.count <= 3 && $0.roster.kDistinct().count == $0.roster.count })
            try TripleShotLeague.require(teams.map { $0.roster.count }.kDistinct().count == 1)
            try TripleShotLeague.require(results.map { $0.fixture.key }.kDistinct().count == results.count)
            try TripleShotLeague.require(results.allSatisfy { TripleShotLeague.schedule().contains($0.fixture) })
        }

        var played: Int { return results.filter { $0.fixture.home == 0 || $0.fixture.away == 0 }.count }

        var finished: Bool { return played == 14 }

        func next() -> Fixture? {
            return TripleShotLeague.schedule().first { fixture in
                (fixture.home == 0 || fixture.away == 0) && !results.contains { r in r.fixture == fixture }
            }
        }

        /// Kotlin data-class `copy`: unspecified properties keep their values; the result is validated.
        func copy(
            id: String? = nil,
            seed: Int64? = nil,
            number: Int? = nil,
            createdAt: Int64? = nil,
            teams: [Team]? = nil,
            results: [Result]? = nil,
            matchSeconds: Int? = nil
        ) throws -> Season {
            return try Season(
                id: id ?? self.id,
                seed: seed ?? self.seed,
                number: number ?? self.number,
                createdAt: createdAt ?? self.createdAt,
                teams: teams ?? self.teams,
                results: results ?? self.results,
                matchSeconds: matchSeconds ?? self.matchSeconds
            )
        }
    }

    struct Row: Hashable {
        var team: Team
        var played: Int
        var wins: Int
        var scored: Int
        var conceded: Int

        var points: Int { return wins * 3 }
        var difference: Int { return scored - conceded }
    }

    /// Two legs; every team plays exactly once in each round and every pair twice.
    /// The Kotlin function rebuilds the same list on every call; the value is computed once here.
    static func schedule() -> [Fixture] { return scheduleFixtures }

    private static let scheduleFixtures: [Fixture] = {
        var ring = Array(0...7)
        var first: [Fixture] = []
        for round in 0..<7 {
            for i in 0..<4 {
                let a = ring[i]
                let b = ring[7 - i]
                first.append((round + i) % 2 == 0 ? Fixture(round: round, home: a, away: b) : Fixture(round: round, home: b, away: a))
            }
            let moved = ring.remove(at: 7)
            ring.insert(moved, at: 1)
        }
        return first + first.map { Fixture(round: $0.round + 7, home: $0.away, away: $0.home) }
    }()

    /// Kotlin `raw.filter { !it.isISOControl() && it !in U+202A..U+202E && it !in U+2066..U+2069 }.trim().take(24)`,
    /// on UTF-16 code units like Kotlin. (A 24th unit that splits a surrogate pair decodes to U+FFFD
    /// where Kotlin keeps the lone surrogate; the 24-unit name field never produces that case.)
    static func cleanName(raw: String) -> String {
        var units: [UInt16] = []
        for unit in raw.utf16 where !isISOControl(unit) && !(unit >= 0x202A && unit <= 0x202E) && !(unit >= 0x2066 && unit <= 0x2069) {
            units.append(unit)
        }
        var start = 0
        var end = units.count
        while start < end && isKotlinWhitespace(units[start]) { start += 1 }
        while end > start && isKotlinWhitespace(units[end - 1]) { end -= 1 }
        let trimmed = units[start..<end]
        return String(decoding: trimmed.prefix(24), as: UTF16.self)
    }

    /// Kotlin `Char.isISOControl()`.
    private static func isISOControl(_ unit: UInt16) -> Bool {
        return unit <= 0x001F || (unit >= 0x007F && unit <= 0x009F)
    }

    /// Kotlin `Char.isWhitespace()` on the JVM: `Character.isWhitespace || Character.isSpaceChar`.
    private static func isKotlinWhitespace(_ unit: UInt16) -> Bool {
        switch unit {
        case 0x0009...0x000D, 0x001C...0x0020, 0x00A0, 0x1680, 0x2000...0x200A, 0x2028, 0x2029, 0x202F, 0x205F, 0x3000:
            return true
        default:
            return false
        }
    }

    /** Duplicate or stale result callbacks do nothing; no skipped or replayed fixtures. */
    static func complete(season: Season, fixtureKey: String, ownScore: Int, rivalScore: Int) throws -> Season {
        guard let next = season.next() else { return season }
        if next.key != fixtureKey { return season }
        try require(season.matchSeconds != 0 || max(ownScore, rivalScore) >= 11)
        let owner: Result
        if next.home == 0 {
            owner = try Result(fixture: next, homeScore: ownScore, awayScore: rivalScore)
        } else {
            owner = try Result(fixture: next, homeScore: rivalScore, awayScore: ownScore)
        }
        var rest: [Result] = []
        for fixture in schedule() where fixture.round == next.round && fixture != next {
            let a = season.teams[fixture.home]
            let b = season.teams[fixture.away]
            let random = KotlinRandom(seed: season.seed ^ Int64(fixture.key.javaHashCode))
            let aWins = random.nextInt(100) < (50 + (a.strength - b.strength) / 2).coerceIn(20, 80)
            let winner = season.matchSeconds == 0 ? 11 : (season.matchSeconds / 9 + random.nextInt(3, 10))
            let loser = random.nextInt(max(0, winner - 10), winner)
            let result = try Result(fixture: fixture, homeScore: aWins ? winner : loser, awayScore: aWins ? loser : winner)
            rest.append(result)
        }
        return try season.copy(results: season.results + [owner] + rest)
    }

    /** Exhaust unique combinations before reusing a squad; balance repeated pairs and players. */
    static func houseRosters(available: [String], size: Int, count: Int, seed: Int64) throws -> [[String]] {
        let ids = available.kDistinct()
        try require(size >= 2 && size <= 3 && ids.count >= size && count >= 0)
        var combinations: [[String]] = []
        func choose(_ start: Int, _ selected: [String]) {
            if selected.count == size { combinations.append(selected); return }
            for i in kuntil(start, ids.count) { choose(i + 1, selected + [ids[i]]) }
        }
        choose(0, [])
        let random = KotlinRandom(seed: seed)
        var used: [Set<String>: Int] = [:]
        var pairs: [Set<String>: Int] = [:]
        var players: [String: Int] = [:]
        func squadPairs(_ s: [String]) -> [Set<String>] {
            var out: [Set<String>] = []
            for i in s.indices {
                for j in kuntil(i + 1, s.count) { out.append([s[i], s[j]]) }
            }
            return out
        }
        // compareBy(used count).thenBy(sum of squared pair counts).thenBy(sum of squared player counts), read at comparison time.
        func rank(_ squad: [String]) -> (Int, Int, Int) {
            let usedCount = used[Set(squad)] ?? 0
            let pairScore = squadPairs(squad).reduce(0) { sum, p in let n = pairs[p] ?? 0; return sum + n * n }
            let playerScore = squad.reduce(0) { sum, id in let n = players[id] ?? 0; return sum + n * n }
            return (usedCount, pairScore, playerScore)
        }
        var squads: [[String]] = []
        for _ in kuntil(0, count) {
            let shuffled = combinations.kShuffled(random)
            // Kotlin `minWith`: the first element wins, a later one only when strictly smaller.
            var selected = shuffled[0]
            var best = rank(selected)
            for candidate in shuffled.dropFirst() {
                let r = rank(candidate)
                if r < best {
                    selected = candidate
                    best = r
                }
            }
            used[Set(selected)] = (used[Set(selected)] ?? 0) + 1
            for p in squadPairs(selected) { pairs[p] = (pairs[p] ?? 0) + 1 }
            for id in selected { players[id] = (players[id] ?? 0) + 1 }
            squads.append(selected)
        }
        return squads
    }

    static func standings(season: Season) -> [Row] {
        return season.teams.map { team -> Row in
            let matches = season.results.filter { $0.fixture.home == team.id || $0.fixture.away == team.id }
            let scored = matches.reduce(0) { $0 + ($1.fixture.home == team.id ? $1.homeScore : $1.awayScore) }
            let conceded = matches.reduce(0) { $0 + ($1.fixture.home == team.id ? $1.awayScore : $1.homeScore) }
            let wins = matches.filter { $0.fixture.home == team.id ? $0.homeScore > $0.awayScore : $0.awayScore > $0.homeScore }.count
            return Row(team: team, played: matches.count, wins: wins, scored: scored, conceded: conceded)
        }.stableSorted { x, y in
            // compareByDescending(points).thenByDescending(difference).thenByDescending(scored).thenBy(team.id)
            if x.points != y.points { return x.points > y.points }
            if x.difference != y.difference { return x.difference > y.difference }
            if x.scored != y.scored { return x.scored > y.scored }
            return x.team.id < y.team.id
        }
    }
}

// MARK: - Positional (Kotlin call-site) forms

extension TripleShotLeague {
    static func cleanName(_ raw: String) -> String { return cleanName(raw: raw) }

    static func complete(_ season: Season, _ fixtureKey: String, _ ownScore: Int, _ rivalScore: Int) throws -> Season {
        return try complete(season: season, fixtureKey: fixtureKey, ownScore: ownScore, rivalScore: rivalScore)
    }

    static func houseRosters(_ available: [String], _ size: Int, _ count: Int, _ seed: Int64) throws -> [[String]] {
        return try houseRosters(available: available, size: size, count: count, seed: seed)
    }

    static func standings(_ season: Season) -> [Row] { return standings(season: season) }
}

extension TripleShotLeague.Team {
    init(_ id: Int, _ name: String, _ color: Int, _ roster: [String], _ strength: Int) {
        self.init(id: id, name: name, color: color, roster: roster, strength: strength)
    }
}

extension TripleShotLeague.Fixture {
    init(_ round: Int, _ home: Int, _ away: Int) {
        self.init(round: round, home: home, away: away)
    }
}

extension TripleShotLeague.Result {
    init(_ fixture: TripleShotLeague.Fixture, _ homeScore: Int, _ awayScore: Int) throws {
        try self.init(fixture: fixture, homeScore: homeScore, awayScore: awayScore)
    }
}

extension TripleShotLeague.Season {
    init(
        _ id: String, _ seed: Int64, _ number: Int, _ createdAt: Int64, _ teams: [TripleShotLeague.Team],
        _ results: [TripleShotLeague.Result] = [], _ matchSeconds: Int = 0
    ) throws {
        try self.init(id: id, seed: seed, number: number, createdAt: createdAt, teams: teams, results: results, matchSeconds: matchSeconds)
    }
}

extension TripleShotLeague.Row {
    init(_ team: TripleShotLeague.Team, _ played: Int, _ wins: Int, _ scored: Int, _ conceded: Int) {
        self.init(team: team, played: played, wins: wins, scored: scored, conceded: conceded)
    }
}
