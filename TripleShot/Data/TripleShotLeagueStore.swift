import Foundation

// Port of data/TripleShotLeagueStore.kt (Android 6c38131), statement by statement.
// One active season as an org.json string (format version 1) in the preferences file
// "tripleshot_house_league", key "active", written with a synchronous commit like Android.
// `load`, `create` and `complete` throw (JSON errors, RuleError) because every Android caller
// catches; a corrupt or unknown-version value is never deleted here.

final class TripleShotLeagueStore {
    private let prefs = getSharedPreferences("tripleshot_house_league", MODE_PRIVATE)

    /// Android `TripleShotLeagueStore(context)`. The preferences are app-wide on iOS, so the
    /// context (activity or fragment) is accepted for call-site parity and not needed.
    init(context: AnyObject? = nil) {}

    func discard(id: String) {
        // Android lets a load failure escape here (the caller does not catch it).
        if (try! load())?.id == id {
            prefs.edit().remove("active").commit()
        }
    }

    func load() throws -> TripleShotLeague.Season? {
        guard let raw = prefs.getString("active", nil) else { return nil }
        let j = try AJSONObject(raw)
        try TripleShotLeague.require(j.getInt("version") == 1)
        let teamArray = try j.getJSONArray("teams")
        var teams: [TripleShotLeague.Team] = []
        for i in kuntil(0, teamArray.length()) {
            let t = try teamArray.getJSONObject(i)
            let id = try t.getInt("id")
            let name = try t.getString("name")
            let color = try t.getInt("color")
            let rosterArray = try t.getJSONArray("roster")
            var roster: [String] = []
            for k in kuntil(0, rosterArray.length()) {
                let member = try rosterArray.getString(k)
                roster.append(member)
            }
            let strength = try t.getInt("strength")
            teams.append(TripleShotLeague.Team(id: id, name: name, color: color, roster: roster, strength: strength))
        }
        let resultArray = try j.getJSONArray("results")
        var results: [TripleShotLeague.Result] = []
        for i in kuntil(0, resultArray.length()) {
            let r = try resultArray.getJSONObject(i)
            let fixture = try TripleShotLeague.Fixture(round: r.getInt("round"), home: r.getInt("home"), away: r.getInt("away"))
            let result = try TripleShotLeague.Result(fixture: fixture, homeScore: r.getInt("a"), awayScore: r.getInt("b"))
            results.append(result)
        }
        // A house roster that names the learner's own players gets free roster players instead (first unused of
        // the bot-selectable pool, in catalogue order), its strength recomputed; the repaired season is saved.
        // Kotlin `first {}` (NoSuchElementException) and `!!` (NullPointerException) reach the callers' catch.
        guard let ownTeam = teams.first(where: { $0.id == 0 }) else {
            throw TripleShotLeague.RuleError.illegalArgument("Collection contains no element matching the predicate.")
        }
        let own = Set(ownTeam.roster)
        let pool = TripleShotCharacterRoster.botSelectable().filter { !own.contains($0.id) && !$0.adaptiveBot }.map { $0.id }
        var fixed: [TripleShotLeague.Team] = []
        for t in teams {
            if t.id == 0 { fixed.append(t); continue }
            var used = Set(t.roster.filter { !own.contains($0) })
            var roster: [String] = []
            for id in t.roster {
                if !own.contains(id) { roster.append(id); continue }
                guard let free = pool.first(where: { !used.contains($0) }) else {
                    throw TripleShotLeague.RuleError.illegalArgument("Collection contains no element matching the predicate.")
                }
                used.insert(free)
                roster.append(free)
            }
            // `roster.map { (inside + midRange + defense + speed) / 4 }.average().toInt()`.
            var sum = 0.0
            for id in roster {
                guard let r = TripleShotCharacterRoster.find(id: id)?.ratings else {
                    throw TripleShotLeague.RuleError.nullPointer("TripleShotCharacterRoster.find(\(id))")
                }
                sum += Double((r.inside + r.midRange + r.defense + r.speed) / 4)
            }
            let average = roster.isEmpty ? Double.nan : sum / Double(roster.count)
            var copy = t
            copy.roster = roster
            copy.strength = average.toInt()
            fixed.append(copy)
        }
        let season = try TripleShotLeague.Season(
            id: j.getString("id"),
            seed: j.getLong("seed"),
            number: j.getInt("number"),
            createdAt: j.getLong("created"),
            teams: fixed,
            results: results,
            matchSeconds: j.optInt("matchSeconds", 0)
        )
        if fixed != teams { try save(s: season) }
        return season
    }

    /// Internal (Kotlin private) so an App Store capture can stage a season (TripleShotScreenshot).
    func save(s: TripleShotLeague.Season) throws {
        let j = AJSONObject().put("version", 1).put("id", s.id).put("seed", s.seed).put("number", s.number)
            .put("created", s.createdAt).put("matchSeconds", s.matchSeconds)
        let teamArray = AJSONArray()
        for t in s.teams {
            let rosterArray = AJSONArray()
            for member in t.roster { _ = rosterArray.put(member) }
            _ = teamArray.put(
                AJSONObject().put("id", t.id).put("name", t.name).put("color", t.color).put("strength", t.strength)
                    .put("roster", rosterArray)
            )
        }
        _ = j.put("teams", teamArray)
        let resultArray = AJSONArray()
        for r in s.results {
            _ = resultArray.put(
                AJSONObject().put("round", r.fixture.round).put("home", r.fixture.home).put("away", r.fixture.away)
                    .put("a", r.homeScore).put("b", r.awayScore)
            )
        }
        _ = j.put("results", resultArray)
        try TripleShotLeague.check(prefs.edit().putString("active", j.toString()).commit(), "Could not save league")
    }

    func create(name: String, color: Int, roster: [String], houseNames: [String], matchSeconds: Int = 0) throws -> TripleShotLeague.Season {
        let old = try load()
        try TripleShotLeague.require(old == nil || old!.finished)
        try TripleShotLeague.require(houseNames.count == 7)
        let clean = TripleShotLeague.cleanName(raw: name)
        try TripleShotLeague.require(
            !clean.kotlinIsBlank && TripleShotLeague.palette.contains(color) &&
                roster.count >= 2 && roster.count <= 3 && roster.kDistinct().count == roster.count
        )
        let choices = TripleShotCharacterRoster.botSelectable().filter { !roster.contains($0.id) && !$0.adaptiveBot }
        try TripleShotLeague.require(choices.count >= roster.count)
        let seed = ASystem.currentTimeMillis()
        // (Android also builds `Random(seed)` here and never uses it.)
        func strength(_ ids: [String]) throws -> Int {
            var values: [Int] = []
            for id in ids {
                // `find(it)!!`: the NullPointerException reaches the caller's runCatching on Android.
                guard let profile = TripleShotCharacterRoster.find(id) else {
                    throw TripleShotLeague.RuleError.nullPointer("Unknown character id \(id)")
                }
                let r = profile.ratings
                values.append((r.inside + r.midRange + r.defense + r.speed) / 4)
            }
            // Iterable<Int>.average(): Double sum / count (NaN when empty), then toInt() truncates.
            var sum = 0.0
            for value in values { sum += Double(value) }
            let average = values.isEmpty ? Double.nan : sum / Double(values.count)
            return average.toInt()
        }
        let ownStrength = try strength(roster)
        var teams = [TripleShotLeague.Team(id: 0, name: clean, color: color, roster: roster, strength: ownStrength)]
        let colors = TripleShotLeague.palette.filter { $0 != color }
        let squads = try TripleShotLeague.houseRosters(available: choices.map { $0.id }, size: roster.count, count: 7, seed: seed)
        for i in kuntil(0, 7) {
            let ids = squads[i]
            let houseStrength = try strength(ids)
            teams.append(TripleShotLeague.Team(id: i + 1, name: houseNames[i], color: colors[i % colors.count], roster: ids, strength: houseStrength))
        }
        let season = try TripleShotLeague.Season(
            id: UUID().uuidString.lowercased(),
            seed: seed,
            number: (old?.number ?? 0) + 1,
            createdAt: seed,
            teams: teams,
            matchSeconds: matchSeconds
        )
        try save(s: season)
        return season
    }

    /** UI thread calls this only after the normal eleven-point match has ended. */
    func complete(seasonId: String, fixtureKey: String, own: Int, rival: Int) throws -> TripleShotLeague.Season? {
        guard let s = try load() else { return nil }
        if s.id != seasonId { return s }
        let next = try TripleShotLeague.complete(season: s, fixtureKey: fixtureKey, ownScore: own, rivalScore: rival)
        if next != s { try save(s: next) }
        return next
    }
}

// MARK: - Positional (Kotlin call-site) forms

extension TripleShotLeagueStore {
    convenience init(_ context: AnyObject?) { self.init(context: context) }

    func discard(_ id: String) { discard(id: id) }

    func create(_ name: String, _ color: Int, _ roster: [String], _ houseNames: [String], _ matchSeconds: Int = 0) throws -> TripleShotLeague.Season {
        return try create(name: name, color: color, roster: roster, houseNames: houseNames, matchSeconds: matchSeconds)
    }

    func complete(_ seasonId: String, _ fixtureKey: String, _ own: Int, _ rival: Int) throws -> TripleShotLeague.Season? {
        return try complete(seasonId: seasonId, fixtureKey: fixtureKey, own: own, rival: rival)
    }
}
