import XCTest
@testable import MinikPlus

/// Android Minik Math Plus PracticeHistoryTest (dc12a5c).
final class MathPracticeHistoryTests: XCTestCase {
    func testOldInstallAndMalformedRowsDoNotInventHistory() {
        XCTAssertTrue(MathPracticeHistory.decode("").isEmpty)
        XCTAssertTrue(MathPracticeHistory.decode("bad|data\nbuildNumber|M1|2|7|0|11").isEmpty)
        // Unscored activities, unknown levels and impossible recent answers are dropped too.
        XCTAssertTrue(MathPracticeHistory.decode("learnMath|M1|1|1|0|1").isEmpty)
        XCTAssertTrue(MathPracticeHistory.decode("buildNumber|M42|1|1|0|1").isEmpty)
        XCTAssertTrue(MathPracticeHistory.decode("buildNumber||1|1|0|1").isEmpty)
        XCTAssertTrue(MathPracticeHistory.decode("buildNumber|M1|1|1|0|11").isEmpty)
        XCTAssertTrue(MathPracticeHistory.decode("buildNumber|M1|2|1|0|12").isEmpty)
    }

    func testAccuracyWaitsForEvidenceAndUsesRecentTwenty() {
        var record = MathPracticeRecord(activity: .buildNumber, levelID: .m1)
        for _ in 0..<4 { record = record.answering(true) }
        XCTAssertNil(record.accuracy)
        record = record.answering(false)
        XCTAssertEqual(record.accuracy, 80)
        for _ in 0..<20 { record = record.answering(false) }
        XCTAssertEqual(record.accuracy, 0)
        XCTAssertEqual(record.attempts, 25)
        XCTAssertEqual(record.correct, 4)
    }

    func testRoundTripKeepsLevelsSeparate() {
        let rows = [
            MathPracticeRecord(activity: .mathSoccer, levelID: .m1, attempts: 7, correct: 5, rounds: 1, recent: "1111100"),
            MathPracticeRecord(activity: .mathSoccer, levelID: .m2, attempts: 5, correct: 4, rounds: 0, recent: "11110")
        ]
        XCTAssertEqual(MathPracticeHistory.decode(MathPracticeHistory.encode(rows)), rows)
    }

    func testRecommendationUsesRelevantLevelAndEnoughAttempts() {
        let old = MathPracticeRecord(activity: .buildNumber, levelID: .m1, attempts: 5, correct: 0, rounds: 0, recent: "00000")
        let small = MathPracticeRecord(activity: .mathSoccer, levelID: .m2, attempts: 1, correct: 0, rounds: 0, recent: "0")
        XCTAssertEqual(MathPracticeHistory.recommended([old, small], levelID: .m2), .visualToAnswer)
        let current = MathPracticeRecord(activity: .mathTower, levelID: .m2, attempts: 5, correct: 2, rounds: 0, recent: "11000")
        XCTAssertEqual(MathPracticeHistory.recommended([old, small, current], levelID: .m2), .mathTower)
        XCTAssertTrue(MathPracticeHistory.needsPractice(.mathTower, in: [current], levelID: .m2))
        XCTAssertFalse(MathPracticeHistory.needsPractice(.mathSoccer, in: [small], levelID: .m2))
    }

    func testRepositoryRecordsAnswersAndRoundsWithoutTouchingOtherActivities() throws {
        let suiteName = "MathPracticeHistoryTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let repository = MathPracticeHistoryRepository(userDefaults: defaults)

        XCTAssertTrue(repository.load().isEmpty)
        repository.recordAnswer(true, activity: .mathSoccer, levelID: .m1)
        repository.recordAnswer(false, activity: .buildNumber, levelID: .m1)
        repository.recordAnswer(true, activity: .mathSoccer, levelID: .m1)
        repository.recordRound(activity: .mathSoccer, levelID: .m1)
        repository.recordAnswer(true, activity: .learnMath, levelID: .m1)

        let records = repository.load()
        XCTAssertEqual(records.map(\.activity), [.buildNumber, .mathSoccer], "The latest change comes last.")
        XCTAssertEqual(records.last, MathPracticeRecord(
            activity: .mathSoccer, levelID: .m1, attempts: 2, correct: 2, rounds: 1, recent: "11"
        ))
    }

    func testFirstAnswersCountAndEveryMatchingAttemptInPairsAndMemory() throws {
        func attempt(_ index: Int, _ family: ActivityFamily) throws -> ActivityAttemptData {
            try XCTUnwrap(ActivityAttemptData(
                itemID: ActivityItemID(rawValue: "item"),
                attemptIndex: index,
                result: .incorrect,
                activityFamily: family
            ))
        }
        XCTAssertTrue(MathPracticeHistory.counts(try attempt(1, .multipleChoice)))
        XCTAssertFalse(MathPracticeHistory.counts(try attempt(2, .multipleChoice)))
        XCTAssertTrue(MathPracticeHistory.counts(try attempt(3, .pairs)))
        XCTAssertTrue(MathPracticeHistory.counts(try attempt(2, .memory)))
    }
}
