import XCTest
@testable import MinikTripleShot

// Area s-team: TripleShotTeamMatchFragment / TripleShotLeagueFragment (Kotlin ui/TripleShotTeamMatchFragment.kt and
// ui/TripleShotLeagueFragment.kt, spec 17-teamfrag).
//
// Golden values marked "JVM" are spec 17 section 7.3 plus extra cases, all re-printed by
// work/s-team/harness/src/TeamRace.kt: a verbatim copy of the Kotlin `buildRace` body (TM:1424-1452) compiled with
// kotlinc 2.3.21 against the snapshot's model/TripleShotCharacters.kt, with the court's actor order
// (TripleShotTeamCourtView.configure: H0..H(n-1) = human + teammates, O0..O(n-1) = opponents, padded with woman_dark).
// Race rows are written "actorId,TEAM,delayMs,correct" in list order, joined by ";", exactly as the harness prints.

private typealias Team = TripleShotTeamCourtView.Team
private typealias Snapshot = TripleShotTeamCourtView.ActorSnapshot

final class TeamMatchTests: XCTestCase {

    // MARK: - Helpers

    /// The actor order of TripleShotTeamCourtView.configure (spec 11): the race order depends on it.
    private func snapshots(_ teamSize: Int, _ human: String, _ teammates: [String], _ opponents: [String]) -> [Snapshot] {
        var humans = [human] + teammates
        humans = humans.count >= teamSize ? Array(humans.prefix(teamSize))
            : humans + [String](repeating: TripleShotCharacterRoster.ID_WOMAN_DARK, count: teamSize - humans.count)
        let rivals = opponents.count >= teamSize ? Array(opponents.prefix(teamSize))
            : opponents + [String](repeating: TripleShotCharacterRoster.ID_WOMAN_DARK, count: teamSize - opponents.count)
        var out: [Snapshot] = []
        for (i, id) in humans.enumerated() {
            out.append(Snapshot(id: "H\(i)", team: .HUMAN, characterId: id, sourceX: 0, sourceY: 0, hasBall: false,
                                controlled: i == 0, boost01: 0))
        }
        for (i, id) in rivals.enumerated() {
            out.append(Snapshot(id: "O\(i)", team: .OPPONENT, characterId: id, sourceX: 0, sourceY: 0, hasBall: false,
                                controlled: false, boost01: 0))
        }
        return out
    }

    private func question(_ id: String) -> TripleShotQuestion {
        return TripleShotQuestion(id: id, category: .KIDS_ARITHMETIC, prompt: "2 + 2 = ?",
                                  answers: [AnswerOption(text: "4", qualityPercent: 100), AnswerOption(text: "5", qualityPercent: 0)],
                                  explanation: "")
    }

    private func race(_ seed: Int64, _ snaps: [Snapshot], _ questionId: String, _ defaultTeam: Team, _ serial: Int64) -> String {
        let attempts = TripleShotTeamMatchFragment.buildRace(seed: seed, snapshots: snaps, q: question(questionId),
                                                             defaultTeam: defaultTeam, serial: serial)
        return attempts.map { "\($0.actorId),\($0.team.name),\($0.delayMs),\($0.correct)" }.joined(separator: ";")
    }

    // MARK: - Raw generator and hash vectors (spec 17 section 7.3)

    func testKotlinRandomVectorsUsedByTheRace() {
        // JVM: fresh Random(seed) per column; then the race's own draw order (nextLong(0, 1700), nextFloat()).
        let rows: [(Int64, Int64, Int64, [Float], Int64, Float)] = [
            (42, 4174779793377534016, 1308, [0.22631526, 0.4052601, 0.90495676], 1308, 0.90495676),
            (31337, 1680326617120332127, 1263, [0.09109068, 0.81285626, 0.02042818], 1263, 0.02042818),
            (-7, 2119902869140302831, 1615, [0.11492014, 0.5056216, 0.71637964], 1615, 0.71637964),
            (1760000000000, -1450066263658712945, 335, [0.9213917, 0.49158, 0.18417567], 335, 0.18417567),
        ]
        for (seed, long, bounded, floats, raceLong, raceFloat) in rows {
            XCTAssertEqual(KotlinRandom(seed: seed).nextLong(), long, "nextLong seed \(seed)")
            XCTAssertEqual(KotlinRandom(seed: seed).nextLong(0, 1700), bounded, "nextLong(0, 1700) seed \(seed)")
            let r = KotlinRandom(seed: seed)
            XCTAssertEqual([r.nextFloat(), r.nextFloat(), r.nextFloat()], floats, "nextFloat x3 seed \(seed)")
            let s = KotlinRandom(seed: seed)
            XCTAssertEqual(s.nextLong(0, 1700), raceLong)
            XCTAssertEqual(s.nextFloat(), raceFloat)
        }
    }

    func testJavaHashesAndQuestionSeed() {
        // JVM String.hashCode().
        let hashes: [(String, Int32)] = [
            ("H0", 2280), ("H1", 2281), ("H2", 2282), ("O0", 2497), ("O1", 2498), ("O2", 2499),
            ("qa-seasons", -1170156749), ("words_fruits_a-0", -1693003846), ("\u{05E9}\u{05D0}\u{05DC}\u{05D4}-7", 1786553513),
        ]
        for (s, h) in hashes { XCTAssertEqual(s.javaHashCode, h, s) }
        // `config.seed xor 0x5445414D` ("TEAM"), the question-list seed of onCreate.
        XCTAssertEqual(Int64(31337) ^ 0x5445414D, 1413823268)
    }

    func testPerCharacterRaceConstantsUseFloatArithmetic() {
        // JVM: base = 1500 + ((1f - responseSpeed / 100f) * 4300f).toLong(); chance = (k - g * 0.22f).coerceIn(20f, 96f).
        // The same expressions as TripleShotTeamMatchFragment.buildRace (coach_67: Float gives 2278, Double would give 2279).
        let expected: [(String, Int64, Float)] = [
            ("bob", 3306, 64.04), ("woman_dark", 3091, 70.92), ("rooza", 1758, 39.239998), ("nova", 2016, 89.68),
            ("unicorn_32", 4337, 82.24), ("coach_67", 3778, 75.8), ("zephyr", 2101, 66.04), ("kyra", 2101, 66.04),
            ("kyra_original", 2101, 66.04), ("flare", 2274, 58.5), ("ace_23", 1628, 20.0), ("buddy_23", 2703, 20.0),
        ]
        XCTAssertEqual(TripleShotCharacterRoster.all.map { $0.id }, expected.map { $0.0 })
        for (id, base, chance) in expected {
            let profile = TripleShotCharacterRoster.find(id: id)!
            let speed01: Float = profile.quiz.responseSpeed.toFloat() / 100
            XCTAssertEqual(1500 + ((1 - speed01) * 4300).toLong(), base, id)
            let knowledgeChance: Float = (profile.quiz.knowledge.toFloat() - profile.quiz.guessiness.toFloat() * Float(0.22)).coerceIn(20, 96)
            XCTAssertEqual(knowledgeChance, chance, id)
        }
    }

    // MARK: - Race golden vectors (JVM)

    func testRaceSpecScenarioThreeOnThree() {
        let teams = snapshots(3, "woman_dark", ["coach_67", "zephyr"], ["nova", "flare", "woman_dark"])
        let expected: [Int64: String] = [
            1: "H1,HUMAN,4896,true;H2,HUMAN,3050,true;O0,OPPONENT,3291,true;O1,OPPONENT,2742,true;O2,OPPONENT,4463,true",
            2: "H1,HUMAN,3937,false;H2,HUMAN,3071,true;O0,OPPONENT,2228,true;O1,OPPONENT,3431,false;O2,OPPONENT,3752,true",
            3: "H1,HUMAN,5125,false;H2,HUMAN,2609,true;O0,OPPONENT,2158,true;O1,OPPONENT,2387,false;O2,OPPONENT,4324,true",
            4: "H1,HUMAN,5242,true;H2,HUMAN,3456,true;O0,OPPONENT,2025,true;O1,OPPONENT,3864,true;O2,OPPONENT,4585,true",
            5: "H1,HUMAN,4912,false;H2,HUMAN,2566,true;O0,OPPONENT,2567,true;O1,OPPONENT,3662,false;O2,OPPONENT,4375,true",
            6: "H1,HUMAN,4924,true;H2,HUMAN,3752,false;O0,OPPONENT,2581,true;O1,OPPONENT,2958,false;O2,OPPONENT,3555,true",
        ]
        for serial in Int64(1)...6 {
            XCTAssertEqual(race(31337, teams, "qa-seasons", .HUMAN, serial), expected[serial], "serial \(serial)")
        }
        // A teammate wins the race ("teammate first"): H2 2453 is the fastest correct attempt.
        XCTAssertEqual(race(31337, teams, "words_fruits_a-0", .HUMAN, 1),
                       "H1,HUMAN,5153,false;H2,HUMAN,2453,true;O0,OPPONENT,3618,true;O1,OPPONENT,2475,true;O2,OPPONENT,3440,true")
    }

    func testRaceSpecScenarioTwoOnTwo() {
        let teams = snapshots(2, "woman_dark", ["rooza"], ["nova", "flare"])
        let expected: [Int64: String] = [
            1: "H1,HUMAN,3287,true;O0,OPPONENT,2342,false;O1,OPPONENT,2901,false",
            2: "H1,HUMAN,2213,false;O0,OPPONENT,2820,true;O1,OPPONENT,3619,false",
            3: "H1,HUMAN,2260,false;O0,OPPONENT,3657,true;O1,OPPONENT,2374,false",
            4: "H1,HUMAN,2137,true;O0,OPPONENT,2504,false;O1,OPPONENT,3231,false",
        ]
        for serial in Int64(1)...4 {
            XCTAssertEqual(race(1760000000000, teams, "qa-seasons", .HUMAN, serial), expected[serial], "serial \(serial)")
        }
    }

    func testRaceFallbackMovesTheFastestAttemptToTheEnd() {
        // Nobody correct: the first minimum delay is removed and re-appended as correct with max(delay, 5200).
        let teams = snapshots(2, "woman_dark", ["buddy_23"], ["ace_23", "buddy_23"])
        let expected: [Int64: String] = [
            1: "H1,HUMAN,3137,true;O0,OPPONENT,2755,false;O1,OPPONENT,2775,false",
            2: "H1,HUMAN,2958,false;O1,OPPONENT,3004,false;O0,OPPONENT,5200,true",
            3: "H1,HUMAN,3178,false;O1,OPPONENT,2820,false;O0,OPPONENT,5200,true",
            4: "H1,HUMAN,3867,true;O0,OPPONENT,1845,false;O1,OPPONENT,3993,false",
            5: "H1,HUMAN,2953,false;O1,OPPONENT,3515,false;O0,OPPONENT,5200,true",
            6: "H1,HUMAN,2777,false;O1,OPPONENT,2851,false;O0,OPPONENT,5200,true",
        ]
        for serial in Int64(1)...6 {
            // defaultTeam only matters for the empty race: both values give the same lists (JVM).
            XCTAssertEqual(race(99, teams, "qa-seasons", .HUMAN, serial), expected[serial], "HUMAN serial \(serial)")
            XCTAssertEqual(race(99, teams, "qa-seasons", .OPPONENT, serial), expected[serial], "OPPONENT serial \(serial)")
        }
    }

    func testRacePaddingOverflowUnknownIdsAndHebrewIds() {
        // Missing ids are padded with woman_dark; a negative seed; `serial * 811L` wraps like a JVM Long.
        let padded = snapshots(3, "nova", [], ["bob"])
        XCTAssertEqual(race(-7, padded, "kids-1", .OPPONENT, 1),
                       "H1,HUMAN,3581,true;H2,HUMAN,3548,false;O0,OPPONENT,4445,true;O1,OPPONENT,4115,true;O2,OPPONENT,3887,true")
        XCTAssertEqual(race(-7, padded, "kids-1", .OPPONENT, Int64.max),
                       "H1,HUMAN,4173,true;H2,HUMAN,4194,true;O0,OPPONENT,3575,true;O1,OPPONENT,4355,true;O2,OPPONENT,3299,true")
        // An unknown character id races with woman_dark's quiz profile.
        let unknown = snapshots(2, "woman_dark", ["nobody"], ["unicorn_32", "kyra_original"])
        XCTAssertEqual(race(123456789, unknown, "q-x", .HUMAN, 3),
                       "H1,HUMAN,4530,true;O0,OPPONENT,5647,false;O1,OPPONENT,2502,false")
        // A Hebrew question id (UTF-16 String.hashCode).
        let teams = snapshots(3, "woman_dark", ["coach_67", "zephyr"], ["nova", "flare", "woman_dark"])
        XCTAssertEqual(race(42, teams, "\u{05E9}\u{05D0}\u{05DC}\u{05D4}-7", .HUMAN, 2),
                       "H1,HUMAN,3968,true;H2,HUMAN,3774,true;O0,OPPONENT,3435,true;O1,OPPONENT,3930,true;O2,OPPONENT,3475,true")
    }

    func testEmptyRaceGetsTheDefaultTeamFallback() {
        // Only the human on court: the race is empty, so one 5400 ms correct attempt for H1 / O0 is appended (JVM).
        let alone = [Snapshot(id: "H0", team: .HUMAN, characterId: "woman_dark", sourceX: 0, sourceY: 0, hasBall: false,
                              controlled: true, boost01: 0)]
        XCTAssertEqual(race(5, alone, "q", .HUMAN, 1), "H1,HUMAN,5400,true")
        XCTAssertEqual(race(5, alone, "q", .OPPONENT, 1), "O0,OPPONENT,5400,true")
    }

    func testRaceSkipsTheHumanAndKeepsSnapshotOrder() {
        let teams = snapshots(3, "woman_dark", ["coach_67", "zephyr"], ["nova", "flare", "woman_dark"])
        let attempts = TripleShotTeamMatchFragment.buildRace(seed: 31337, snapshots: teams, q: question("qa-seasons"),
                                                             defaultTeam: .HUMAN, serial: 1)
        XCTAssertEqual(attempts.map { $0.actorId }, ["H1", "H2", "O0", "O1", "O2"])
        XCTAssertEqual(attempts.map { $0.team }, [.HUMAN, .HUMAN, .OPPONENT, .OPPONENT, .OPPONENT])
        // Spec 7.3 bot winner of this row (first correct attempt with the minimum delay): O1 2742.
        let winner = attempts.filter { $0.correct }.kMinBy { $0.delayMs }!
        XCTAssertEqual(winner.actorId, "O1")
        XCTAssertEqual(winner.delayMs, 2742)
        // Every delay stays inside the Kotlin clamp.
        for serial in Int64(1)...40 {
            for a in TripleShotTeamMatchFragment.buildRace(seed: 7 &* serial, snapshots: teams, q: question("q\(serial)"),
                                                          defaultTeam: .OPPONENT, serial: serial) {
                XCTAssertTrue(a.delayMs >= 1000 && a.delayMs <= 7200, "\(a)")
            }
        }
    }

    // MARK: - newInstance (TM:1695-1716)

    func testNewInstancePacksTheConfigLikeKotlin() {
        let config = TripleShotGameConfig(
            playerName: "Sky Comets", gameType: .TEAM_MATCH, selectedCategories: KLinkedSet([QuestionCategory.MATH, .ENGLISH]),
            botMatch: true, playerCharacterId: "nova", botCharacterId: "bob", teamSize: 3,
            teammateCharacterIds: ["rooza", "flare"], opponentCharacterIds: ["ace_23", "kyra"],
            gameOrientation: .LANDSCAPE, courtId: "neon_tide", seed: 1760000000123, timeLimitSeconds: 180,
            leagueSeasonId: "season-1", leagueFixtureKey: "3-0-5", teamName: "Sky Comets", opponentTeamName: "Moon Dragons",
            teamColor: argbInt(0xffc6a0ff), opponentTeamColor: argbInt(0xff80e4bd)
        )
        let args = TripleShotTeamMatchFragment.newInstance(config: config).arguments!
        XCTAssertEqual(args.getString("team_name"), "Sky Comets")
        XCTAssertEqual(args.getStringArrayList("team_categories"), ["MATH", "ENGLISH"])
        XCTAssertEqual(args.getString("team_player_id"), "nova")
        // Primary opponent = opponentCharacterIds.firstOrNull() ?: botCharacterId.
        XCTAssertEqual(args.getString("team_primary_opponent"), "ace_23")
        XCTAssertEqual(args.getInt("team_size", 0), 3)
        XCTAssertEqual(args.getStringArrayList("team_teammates"), ["rooza", "flare"])
        XCTAssertEqual(args.getStringArrayList("team_opponents"), ["ace_23", "kyra"])
        XCTAssertEqual(args.getString("team_game_orientation"), "LANDSCAPE")
        XCTAssertEqual(args.getString("team_court_id"), "neon_tide")
        XCTAssertEqual(args.getLong("team_seed", 0), 1760000000123)
        XCTAssertEqual(args.getInt("match_seconds", -1), 180)
        XCTAssertEqual(args.getString("league_season"), "season-1")
        XCTAssertEqual(args.getString("league_fixture"), "3-0-5")
        XCTAssertEqual(args.getString("league_team_name"), "Sky Comets")
        XCTAssertEqual(args.getString("league_opponent_name"), "Moon Dragons")
        XCTAssertEqual(args.getInt("league_team_color", 0), argbInt(0xffc6a0ff))
        XCTAssertEqual(args.getInt("league_opponent_color", 0), argbInt(0xff80e4bd))

        var solo = config
        solo.opponentCharacterIds = []
        XCTAssertEqual(TripleShotTeamMatchFragment.newInstance(config: solo).arguments!.getString("team_primary_opponent"), "bob")
    }
}
