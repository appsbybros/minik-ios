import XCTest
@testable import MinikTripleShot

// Parity tests for the s-progress area (spec 25): TripleShotProgressFragment's trend labels and grouping, and
// BasketballJourneyActivity's team picks.
// - Spec vectors: the week/month label table of spec 25 section 8.6 (the ISO week number with the CALENDAR year, kept
//   as on Android) and the bot-pick tables of section 7.3.
// - JVM golden vectors, printed by the real Kotlin code on the JVM (scratch harness over Android snapshot dd722e5:
//   verbatim copies of the fragment's private weekKey / monthKey / groupAttempts / sumBuckets and of the repository's
//   KnowledgeBucket, plus the app's own BasketballJourney / TripleShotCharacterRoster classes driven like start()):
//   29 label instants, the grouping of 12 attempts (filter, stable ascending sort, insertion-ordered merge), bucket
//   accuracies in Float maths, and the lineup and goals of all 23 stages for cycles 0-7 (184 steps).

final class ProgressJourneyTests: XCTestCase {

    // MARK: - Week / month labels (spec 25 section 8.6)

    func testSpecWeekAndMonthLabelTable() {
        let fragment = TripleShotProgressFragment()
        let utc = ATimeZone.getTimeZone("UTC")
        // (instant (UTC), ms, fragment week, fragment month)
        let rows: [(String, Int64, String, String)] = [
            ("2024-01-01T00:00", 1704067200000, "W01/24", "01/24"),
            ("2024-12-29T23:59:59", 1735516799000, "W52/24", "12/24"),
            ("2024-12-30T00:00", 1735516800000, "W01/24", "12/24"),
            ("2024-12-31T10:00", 1735639200000, "W01/24", "12/24"),
            ("2025-01-01T00:00", 1735689600000, "W01/25", "01/25"),
            ("2026-10-17T09:30", 1792229400000, "W42/26", "10/26"),
            ("2026-12-31T12:00", 1798718400000, "W53/26", "12/26"),
            ("2027-01-01T00:00", 1798761600000, "W53/27", "01/27"),
            ("2027-01-04T00:00", 1799020800000, "W01/27", "01/27"),
            ("2021-01-03T00:00", 1609632000000, "W53/21", "01/21")
        ]
        for (instant, ms, week, month) in rows {
            XCTAssertEqual(fragment.weekKey(ms: ms, tz: utc), week, instant)
            XCTAssertEqual(fragment.monthKey(ms: ms, tz: utc), month, instant)
        }
    }

    func testGoldenWeekAndMonthLabels() {
        let fragment = TripleShotProgressFragment()
        let utc = ATimeZone.getTimeZone("UTC")
        let rows = ProgressJourneyGolden.rows(ProgressJourneyGolden.weeks)
        XCTAssertEqual(rows.count, 29)
        for f in rows {
            let ms = Int64(f[0])!
            XCTAssertEqual(fragment.weekKey(ms: ms, tz: utc), f[1], "week of \(ms)")
            XCTAssertEqual(fragment.monthKey(ms: ms, tz: utc), f[2], "month of \(ms)")
        }
    }

    // MARK: - Trend grouping and buckets

    func testGoldenGroupAttemptsMergesByLabelInFirstAttemptOrder() {
        typealias Record = TripleShotFirebaseRepository.KnowledgeAttemptRecord
        let fragment = TripleShotProgressFragment()
        // Newest first, as loadKnowledgeDashboard delivers them; answeredAt 0 is filtered out.
        let attempts: [Record] = [
            Record(id: "a", correct: true, answeredAt: 1799020800000),
            Record(id: "b", correct: false, answeredAt: 1798761600000),
            Record(id: "c", correct: true, answeredAt: 1798718400000),
            Record(id: "d", correct: true, answeredAt: 1792229400000),
            Record(id: "e", correct: false, answeredAt: 1792229400000),
            Record(id: "f", correct: true, answeredAt: 0),
            Record(id: "g", correct: true, answeredAt: 1735689600000),
            Record(id: "h", correct: false, answeredAt: 1735639200000),
            Record(id: "i", correct: true, answeredAt: 1735516800000),
            Record(id: "j", correct: true, answeredAt: 1735516799000),
            Record(id: "k", correct: false, answeredAt: 1704067200000),
            Record(id: "l", correct: true, answeredAt: 1704067200001)
        ]
        let rows = ProgressJourneyGolden.rows(ProgressJourneyGolden.groups)
        XCTAssertEqual(rows.count, 2)
        for f in rows {
            let weekly = f[0] == "true"
            let groups = fragment.groupAttempts(attempts: attempts, weekly: weekly)
            let text = groups.map { "\($0.first)=\($0.second.total)/\($0.second.correct)/\($0.second.accuracyPercent)" }
                .joined(separator: ";")
            XCTAssertEqual(text, f[1], "weekly \(weekly)")
        }
        XCTAssertTrue(fragment.groupAttempts(attempts: [], weekly: true).isEmpty)
        XCTAssertTrue(fragment.groupAttempts(attempts: [Record(id: "z", correct: true, answeredAt: 0)], weekly: false).isEmpty)
    }

    func testGoldenAccuracyUsesFloatMathsAndSumBucketsAddsEverything() {
        typealias Bucket = TripleShotFirebaseRepository.KnowledgeBucket
        let fragment = TripleShotProgressFragment()
        var buckets: [Bucket] = []
        var sums = 0
        for f in ProgressJourneyGolden.rows(ProgressJourneyGolden.accuracy) {
            let bucket = Bucket(total: Int(f[1])!, correct: Int(f[2])!)
            if f[0] == "ACC" {
                XCTAssertEqual(bucket.accuracyPercent, Int(f[3])!, "\(f[1]) answers, \(f[2]) correct")
                buckets.append(bucket)
            } else {
                let sum = fragment.sumBuckets(values: buckets)
                XCTAssertEqual(sum, bucket)
                XCTAssertEqual(sum.accuracyPercent, Int(f[3])!)
                sums += 1
            }
        }
        XCTAssertEqual(buckets.count, 9)
        XCTAssertEqual(sums, 1)
        XCTAssertEqual(fragment.sumBuckets(values: []), Bucket(total: 0, correct: 0))
    }

    // MARK: - Journey team picks (spec 25 section 7.3)

    private func assertLineup(_ stageId: String, cycle: Int, _ helpers: [String], _ opponents: [String],
                              file: StaticString = #filePath, line: UInt = #line) {
        guard let stage = BasketballJourney.stages.first(where: { $0.id == stageId }) else {
            XCTFail("no stage \(stageId)", file: file, line: line)
            return
        }
        let lineup = BasketballJourneyActivity.lineup(stage: stage, cycle: cycle)
        XCTAssertEqual(lineup.helpers, helpers, "\(stageId) cycle \(cycle) helpers", file: file, line: line)
        XCTAssertEqual(lineup.opponents, opponents, "\(stageId) cycle \(cycle) opponents", file: file, line: line)
    }

    func testSpecBotPickTableCycle0() {
        for id in ["move", "move_pass"] { assertLineup(id, cycle: 0, ["rooza"], ["coach_67", "unicorn_32"]) }
        assertLineup("pass", cycle: 0, ["rooza"], ["unicorn_32", "coach_67"])
        for id in ["release", "basket", "shoot"] { assertLineup(id, cycle: 0, ["rooza"], ["buddy_23", "ace_23"]) }
        for id in ["switch", "steal", "defend"] { assertLineup(id, cycle: 0, ["nova"], ["unicorn_32", "coach_67"]) }
        for id in ["screen", "screen_pass"] { assertLineup(id, cycle: 0, ["flare"], ["ace_23", "buddy_23"]) }
        for id in ["alley", "alley_twice"] { assertLineup(id, cycle: 0, ["zephyr"], ["buddy_23", "rooza"]) }
        for id in ["three_pass", "three_alley"] {
            assertLineup(id, cycle: 0, ["rooza", "buddy_23"], ["unicorn_32", "coach_67", "flare"])
        }
        for id in ["three_move", "final"] {
            assertLineup(id, cycle: 0, ["rooza", "buddy_23"], ["coach_67", "unicorn_32", "ace_23"])
        }
        assertLineup("three_screen", cycle: 0, ["flare", "nova"], ["ace_23", "buddy_23", "coach_67"])
        assertLineup("three_defend", cycle: 0, ["nova", "zephyr"], ["unicorn_32", "coach_67", "flare"])
        assertLineup("three_shoot", cycle: 0, ["rooza", "ace_23"], ["buddy_23", "flare", "kyra"])
    }

    func testSpecBotPickTableCycles1And5() {
        assertLineup("move", cycle: 1, ["buddy_23"], ["unicorn_32", "ace_23"])
        assertLineup("pass", cycle: 1, ["buddy_23"], ["coach_67", "flare"])
        assertLineup("release", cycle: 1, ["ace_23"], ["rooza", "flare"])
        assertLineup("switch", cycle: 1, ["zephyr"], ["coach_67", "flare"])
        assertLineup("screen", cycle: 1, ["nova"], ["buddy_23", "coach_67"])
        assertLineup("alley", cycle: 1, ["kyra_original"], ["rooza", "ace_23"])
        assertLineup("three_pass", cycle: 1, ["buddy_23", "ace_23"], ["coach_67", "flare", "nova"])
        assertLineup("three_move", cycle: 1, ["buddy_23", "ace_23"], ["unicorn_32", "rooza", "flare"])
        assertLineup("three_screen", cycle: 1, ["nova", "unicorn_32"], ["buddy_23", "coach_67", "rooza"])
        assertLineup("three_defend", cycle: 1, ["zephyr", "kyra_original"], ["coach_67", "flare", "kyra"])
        assertLineup("three_shoot", cycle: 1, ["ace_23", "buddy_23"], ["flare", "kyra", "kyra_original"])

        assertLineup("move", cycle: 5, ["zephyr"], ["flare", "kyra"])
        assertLineup("pass", cycle: 5, ["zephyr"], ["rooza", "kyra"])
        assertLineup("release", cycle: 5, ["zephyr"], ["kyra_original", "nova"])
        assertLineup("switch", cycle: 5, ["rooza"], ["zephyr", "nova"])
        assertLineup("screen", cycle: 5, ["kyra_original"], ["flare", "kyra"])
        assertLineup("alley", cycle: 5, ["rooza"], ["kyra_original", "zephyr"])
        assertLineup("three_defend", cycle: 5, ["rooza", "coach_67"], ["nova", "ace_23", "buddy_23"])
        assertLineup("three_shoot", cycle: 5, ["zephyr", "kyra_original"], ["nova", "coach_67", "unicorn_32"])
        assertLineup("final", cycle: 5, ["zephyr", "kyra_original"], ["flare", "kyra", "nova"])
    }

    /// Every stage of cycles 0-7 as start() builds it from the absolute step (cycle * 23 + index): the practice's stage,
    /// cycle and goals, and the lineup passed to the court.
    func testGoldenLineupsAndGoalsForEveryStageOfCycles0To7() {
        let rows = ProgressJourneyGolden.rows(ProgressJourneyGolden.picks)
        XCTAssertEqual(rows.count, 8 * BasketballJourney.stages.count)
        for (n, f) in rows.enumerated() {
            let p = BasketballPractice(step: n)
            XCTAssertEqual(p.cycle, Int(f[0])!, "step \(n)")
            XCTAssertEqual(p.stage.id, f[1], "step \(n)")
            let lineup = BasketballJourneyActivity.lineup(stage: p.stage, cycle: p.cycle)
            XCTAssertEqual(lineup.helpers.joined(separator: ","), f[2], "step \(n) helpers")
            XCTAssertEqual(lineup.opponents.joined(separator: ","), f[3], "step \(n) opponents")
            XCTAssertEqual(p.stage.goals.indices.map { String(p.goal(i: $0)) }.joined(separator: ","), f[4], "step \(n) goals")
            XCTAssertEqual(lineup.helpers.count, p.stage.teamSize - 1, "step \(n)")
            XCTAssertEqual(lineup.opponents.count, p.stage.teamSize, "step \(n)")
            XCTAssertFalse((lineup.helpers + lineup.opponents).contains("woman_dark"), "step \(n)")
            XCTAssertEqual(Set(lineup.helpers + lineup.opponents).count, 2 * p.stage.teamSize - 1, "step \(n) distinct")
        }
    }
}

/// The JVM golden rows ("|"-separated fields, one row per line).
private enum ProgressJourneyGolden {
    static func rows(_ text: String) -> [[String]] {
        return text.split(separator: "\n").map { line in
            line.split(separator: "|", omittingEmptySubsequences: false).map(String.init)
        }
    }

    /// ms | weekKey | monthKey (UTC).
    static let weeks = """
        1704067200000|W01/24|01/24
        1735516799000|W52/24|12/24
        1735516800000|W01/24|12/24
        1735639200000|W01/24|12/24
        1735689600000|W01/25|01/25
        1792229400000|W42/26|10/26
        1798718400000|W53/26|12/26
        1798761600000|W53/27|01/27
        1799020800000|W01/27|01/27
        1609632000000|W53/21|01/21
        1|W01/70|01/70
        951782400000|W09/00|02/00
        1078012800000|W09/04|02/04
        1230768000000|W01/09|01/09
        1262217600000|W53/09|12/09
        1262304000000|W53/10|01/10
        1293753600000|W52/10|12/10
        1451606400000|W53/16|01/16
        1483142400000|W52/16|12/16
        1609459200000|W53/21|01/21
        1640995199000|W52/21|12/21
        1640995200000|W52/22|01/22
        1672444800000|W52/22|12/22
        1704038399000|W52/23|12/23
        1735603200000|W01/24|12/24
        1767225600000|W01/26|01/26
        1767139200000|W01/25|12/25
        1830297600000|W52/28|01/28
        1861833600000|W52/28|12/28
        """

    /// weekly | label=total/correct/accuracyPercent;... for the attempts of testGoldenGroupAttempts...
    static let groups = """
        true|W01/24=4/2/50;W52/24=1/1/100;W01/25=1/1/100;W42/26=2/1/50;W53/26=1/1/100;W53/27=1/0/0;W01/27=1/1/100
        false|01/24=2/1/50;12/24=3/2/66;01/25=1/1/100;10/26=2/1/50;12/26=1/1/100;01/27=2/1/50
        """

    /// ACC | total | correct | accuracyPercent for each bucket, then SUM | total | correct | accuracyPercent of their sum.
    static let accuracy = """
        ACC|3|1|33
        ACC|0|0|0
        ACC|9|7|77
        ACC|16777217|16777216|100
        ACC|1000|999|99
        ACC|7|9|100
        ACC|-1|5|0
        ACC|3|2|66
        ACC|300001|100000|33
        SUM|17078239|16878239|98
        """

    /// cycle | stage id | helpers | opponents | goals, steps 0...183 in order (Android 6c38131, 23 stages; JVM).
    static let picks = """
        0|move|rooza|coach_67,unicorn_32|8
        0|pass|rooza|unicorn_32,coach_67|2
        0|release|rooza|buddy_23,ace_23|3
        0|basket|rooza|buddy_23,ace_23|2
        0|switch|nova|unicorn_32,coach_67|3
        0|steal|nova|unicorn_32,coach_67|1
        0|screen|flare|ace_23,buddy_23|1
        0|alley|zephyr|buddy_23,rooza|1
        0|move_pass|rooza|coach_67,unicorn_32|10,3
        0|shoot|rooza|buddy_23,ace_23|4,2
        0|defend|nova|unicorn_32,coach_67|2,2
        0|screen_pass|flare|ace_23,buddy_23|2,3
        0|alley_twice|zephyr|buddy_23,rooza|2
        0|three_pass|rooza,buddy_23|unicorn_32,coach_67,flare|5
        0|three_move|rooza,buddy_23|coach_67,unicorn_32,ace_23|15,4
        0|three_screen|flare,nova|ace_23,buddy_23,coach_67|2,2
        0|three_defend|nova,zephyr|unicorn_32,coach_67,flare|3,2
        0|three_shoot|rooza,ace_23|buddy_23,flare,kyra|5,3
        0|three_alley|rooza,buddy_23|unicorn_32,coach_67,flare|4,2
        0|final|rooza,buddy_23|coach_67,unicorn_32,ace_23|12,4,3
        0|cross|rooza|coach_67,unicorn_32|2
        0|behind_back|rooza|coach_67,unicorn_32|2
        0|spin|rooza|coach_67,unicorn_32|3
        1|move|buddy_23|unicorn_32,ace_23|10
        1|pass|buddy_23|coach_67,flare|3
        1|release|ace_23|rooza,flare|4
        1|basket|ace_23|rooza,flare|3
        1|switch|zephyr|coach_67,flare|4
        1|steal|zephyr|coach_67,flare|2
        1|screen|nova|buddy_23,coach_67|2
        1|alley|kyra_original|rooza,ace_23|2
        1|move_pass|buddy_23|unicorn_32,ace_23|12,4
        1|shoot|ace_23|rooza,flare|5,3
        1|defend|zephyr|coach_67,flare|3,3
        1|screen_pass|nova|buddy_23,coach_67|3,4
        1|alley_twice|kyra_original|rooza,ace_23|3
        1|three_pass|buddy_23,ace_23|coach_67,flare,nova|6
        1|three_move|buddy_23,ace_23|unicorn_32,rooza,flare|17,5
        1|three_screen|nova,unicorn_32|buddy_23,coach_67,rooza|3,3
        1|three_defend|zephyr,kyra_original|coach_67,flare,kyra|4,3
        1|three_shoot|ace_23,buddy_23|flare,kyra,kyra_original|6,4
        1|three_alley|buddy_23,ace_23|coach_67,flare,nova|5,3
        1|final|buddy_23,ace_23|unicorn_32,rooza,flare|14,5,4
        1|cross|buddy_23|unicorn_32,ace_23|3
        1|behind_back|buddy_23|unicorn_32,ace_23|3
        1|spin|buddy_23|unicorn_32,ace_23|4
        2|move|ace_23|buddy_23,rooza|12
        2|pass|ace_23|flare,nova|4
        2|release|buddy_23|flare,kyra|5
        2|basket|buddy_23|flare,kyra|4
        2|switch|kyra_original|flare,kyra|5
        2|steal|kyra_original|flare,kyra|3
        2|screen|unicorn_32|coach_67,rooza|3
        2|alley|kyra|ace_23,flare|3
        2|move_pass|ace_23|buddy_23,rooza|14,5
        2|shoot|buddy_23|flare,kyra|6,4
        2|defend|kyra_original|flare,kyra|4,4
        2|screen_pass|unicorn_32|coach_67,rooza|4,5
        2|alley_twice|kyra|ace_23,flare|4
        2|three_pass|ace_23,nova|flare,rooza,kyra|7
        2|three_move|ace_23,nova|buddy_23,rooza,flare|19,6
        2|three_screen|unicorn_32,coach_67|rooza,flare,kyra|4,4
        2|three_defend|kyra_original,kyra|flare,zephyr,nova|5,4
        2|three_shoot|buddy_23,nova|flare,kyra,kyra_original|7,5
        2|three_alley|ace_23,nova|flare,rooza,kyra|6,4
        2|final|ace_23,nova|buddy_23,rooza,flare|16,6,5
        2|cross|ace_23|buddy_23,rooza|4
        2|behind_back|ace_23|buddy_23,rooza|4
        2|spin|ace_23|buddy_23,rooza|5
        3|move|nova|buddy_23,rooza|14
        3|pass|nova|ace_23,rooza|5
        3|release|nova|flare,kyra|6
        3|basket|nova|flare,kyra|5
        3|switch|kyra|kyra_original,zephyr|6
        3|steal|kyra|kyra_original,zephyr|4
        3|screen|coach_67|rooza,flare|4
        3|alley|flare|coach_67,kyra|4
        3|move_pass|nova|buddy_23,rooza|16,6
        3|shoot|nova|flare,kyra|7,5
        3|defend|kyra|kyra_original,zephyr|5,5
        3|screen_pass|coach_67|rooza,flare|5,6
        3|alley_twice|flare|coach_67,kyra|5
        3|three_pass|nova,flare|rooza,kyra,kyra_original|8
        3|three_move|nova,flare|buddy_23,rooza,kyra|21,7
        3|three_screen|coach_67,zephyr|rooza,flare,kyra|5,5
        3|three_defend|kyra,flare|zephyr,nova,ace_23|6,5
        3|three_shoot|nova,flare|kyra,kyra_original,zephyr|8,6
        3|three_alley|nova,flare|rooza,kyra,kyra_original|7,5
        3|final|nova,flare|buddy_23,rooza,kyra|18,7,6
        3|cross|nova|buddy_23,rooza|5
        3|behind_back|nova|buddy_23,rooza|5
        3|spin|nova|buddy_23,rooza|6
        4|move|flare|rooza,kyra|16
        4|pass|flare|rooza,kyra|6
        4|release|flare|kyra_original,zephyr|7
        4|basket|flare|kyra_original,zephyr|6
        4|switch|flare|zephyr,nova|7
        4|steal|flare|zephyr,nova|5
        4|screen|zephyr|rooza,flare|5
        4|alley|nova|coach_67,kyra|5
        4|move_pass|flare|rooza,kyra|18,7
        4|shoot|flare|kyra_original,zephyr|8,6
        4|defend|flare|zephyr,nova|6,6
        4|screen_pass|zephyr|rooza,flare|6,7
        4|alley_twice|nova|coach_67,kyra|6
        4|three_pass|flare,zephyr|rooza,kyra,kyra_original|9
        4|three_move|flare,zephyr|rooza,kyra,kyra_original|23,8
        4|three_screen|zephyr,kyra_original|rooza,flare,kyra|6,6
        4|three_defend|flare,rooza|zephyr,nova,ace_23|7,6
        4|three_shoot|flare,zephyr|kyra_original,nova,coach_67|9,7
        4|three_alley|flare,zephyr|rooza,kyra,kyra_original|8,6
        4|final|flare,zephyr|rooza,kyra,kyra_original|20,8,7
        4|cross|flare|rooza,kyra|6
        4|behind_back|flare|rooza,kyra|6
        4|spin|flare|rooza,kyra|7
        5|move|zephyr|flare,kyra|18
        5|pass|zephyr|rooza,kyra|7
        5|release|zephyr|kyra_original,nova|8
        5|basket|zephyr|kyra_original,nova|7
        5|switch|rooza|zephyr,nova|8
        5|steal|rooza|zephyr,nova|6
        5|screen|kyra_original|flare,kyra|6
        5|alley|rooza|kyra_original,zephyr|6
        5|move_pass|zephyr|flare,kyra|20,8
        5|shoot|zephyr|kyra_original,nova|9,7
        5|defend|rooza|zephyr,nova|7,7
        5|screen_pass|kyra_original|flare,kyra|7,8
        5|alley_twice|rooza|kyra_original,zephyr|7
        5|three_pass|zephyr,kyra_original|rooza,kyra,buddy_23|10
        5|three_move|zephyr,kyra_original|flare,kyra,nova|25,9
        5|three_screen|kyra_original,kyra|flare,zephyr,nova|7,7
        5|three_defend|rooza,coach_67|nova,ace_23,buddy_23|8,7
        5|three_shoot|zephyr,kyra_original|nova,coach_67,unicorn_32|10,8
        5|three_alley|zephyr,kyra_original|rooza,kyra,buddy_23|9,7
        5|final|zephyr,kyra_original|flare,kyra,nova|22,9,8
        5|cross|zephyr|flare,kyra|7
        5|behind_back|zephyr|flare,kyra|7
        5|spin|zephyr|flare,kyra|8
        6|move|kyra_original|kyra,zephyr|20
        6|pass|kyra_original|kyra,zephyr|8
        6|release|kyra_original|nova,coach_67|9
        6|basket|kyra_original|nova,coach_67|8
        6|switch|coach_67|ace_23,rooza|9
        6|steal|coach_67|ace_23,rooza|7
        6|screen|kyra|kyra_original,zephyr|7
        6|alley|ace_23|zephyr,nova|7
        6|move_pass|kyra_original|kyra,zephyr|22,9
        6|shoot|kyra_original|nova,coach_67|10,8
        6|defend|coach_67|ace_23,rooza|8,8
        6|screen_pass|kyra|kyra_original,zephyr|8,9
        6|alley_twice|ace_23|zephyr,nova|8
        6|three_pass|kyra_original,kyra|zephyr,buddy_23,rooza|11
        6|three_move|kyra_original,kyra|zephyr,nova,flare|27,10
        6|three_screen|kyra,ace_23|zephyr,nova,kyra_original|8,8
        6|three_defend|coach_67,unicorn_32|rooza,buddy_23,ace_23|9,8
        6|three_shoot|kyra_original,kyra|coach_67,unicorn_32,nova|11,9
        6|three_alley|kyra_original,kyra|zephyr,buddy_23,rooza|10,8
        6|final|kyra_original,kyra|zephyr,nova,flare|24,10,9
        6|cross|kyra_original|kyra,zephyr|8
        6|behind_back|kyra_original|kyra,zephyr|8
        6|spin|kyra_original|kyra,zephyr|9
        7|move|kyra|zephyr,nova|20
        7|pass|kyra|zephyr,buddy_23|8
        7|release|kyra|coach_67,unicorn_32|9
        7|basket|kyra|coach_67,unicorn_32|8
        7|switch|unicorn_32|rooza,buddy_23|9
        7|steal|unicorn_32|rooza,buddy_23|7
        7|screen|ace_23|zephyr,nova|7
        7|alley|buddy_23|nova,unicorn_32|7
        7|move_pass|kyra|zephyr,nova|22,9
        7|shoot|kyra|coach_67,unicorn_32|10,8
        7|defend|unicorn_32|rooza,buddy_23|8,8
        7|screen_pass|ace_23|zephyr,nova|8,9
        7|alley_twice|buddy_23|nova,unicorn_32|8
        7|three_pass|kyra,coach_67|buddy_23,zephyr,kyra_original|11
        7|three_move|kyra,unicorn_32|nova,zephyr,kyra_original|27,10
        7|three_screen|ace_23,rooza|nova,zephyr,kyra_original|8,8
        7|three_defend|unicorn_32,buddy_23|rooza,ace_23,nova|9,8
        7|three_shoot|kyra,unicorn_32|coach_67,nova,zephyr|11,9
        7|three_alley|kyra,coach_67|buddy_23,zephyr,kyra_original|10,8
        7|final|kyra,unicorn_32|nova,zephyr,kyra_original|24,10,9
        7|cross|kyra|zephyr,nova|8
        7|behind_back|kyra|zephyr,nova|8
        7|spin|kyra|zephyr,nova|9
        """
}
