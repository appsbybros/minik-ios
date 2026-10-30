import XCTest
@testable import MinikPlus

/// Android Minik Math Plus's daily route (2026-10-13).
final class MinikDailyLearningTests: XCTestCase {
    func testLearningDayIsTheDeviceCalendarDay() throws {
        // 2026-10-09 00:30 UTC is still 8 October in California.
        let instant = Date(timeIntervalSince1970: 1_791_505_800)
        XCTAssertEqual(MinikLearningDay.string(for: instant, timeZone: try XCTUnwrap(TimeZone(identifier: "UTC"))), "2026-10-09")
        XCTAssertEqual(
            MinikLearningDay.string(for: instant, timeZone: try XCTUnwrap(TimeZone(identifier: "America/Los_Angeles"))),
            "2026-10-08"
        )
    }

    func testMathJourneyVisitsTenScoredActivitiesAndRaisesItsGoal() {
        XCTAssertEqual(MathDailyJourneyPolicy.activities.count, 10)
        XCTAssertEqual(MathDailyJourneyPolicy.activity(forStep: 0), .visualToAnswer)
        XCTAssertEqual(MathDailyJourneyPolicy.activity(forStep: 9), .mathMixed)
        XCTAssertEqual(MathDailyJourneyPolicy.activity(forStep: 10), .visualToAnswer)
        XCTAssertEqual(MathDailyJourneyPolicy.goal(forStep: 0), 3)
        XCTAssertEqual(MathDailyJourneyPolicy.goal(forStep: 9), 3)
        XCTAssertEqual(MathDailyJourneyPolicy.goal(forStep: 10), 4)
        XCTAssertEqual(MathDailyJourneyPolicy.goal(forStep: 20), 5)
        XCTAssertEqual(MathDailyJourneyPolicy.goal(forStep: 95), 5)
        for unscored in [MathProductionActivityID.learnMath, .mathCards, .pingPong] {
            XCTAssertFalse(MathDailyJourneyPolicy.activities.contains(unscored))
        }
    }

    func testMathJourneyPaysEachStageOnceWithTheFirstStageOfTheDayBonus() {
        var state = MathDailyJourneyState()
        XCTAssertFalse(state.recordCountedAnswer(on: "2026-10-09"))
        XCTAssertFalse(state.recordCountedAnswer(on: "2026-10-09"))
        XCTAssertTrue(state.recordCountedAnswer(on: "2026-10-09"))
        XCTAssertEqual(state.step, 1)
        XCTAssertEqual(state.answers, 0)
        XCTAssertEqual(state.stars, 70)
        XCTAssertEqual(state.activity, .answerToRepresentation)

        XCTAssertFalse(state.recordCountedAnswer(on: "2026-10-09"))
        XCTAssertFalse(state.recordCountedAnswer(on: "2026-10-09"))
        XCTAssertTrue(state.recordCountedAnswer(on: "2026-10-09"))
        XCTAssertEqual(state.stars, 110)

        XCTAssertFalse(state.recordCountedAnswer(on: "2026-10-10"))
        XCTAssertFalse(state.recordCountedAnswer(on: "2026-10-10"))
        XCTAssertTrue(state.recordCountedAnswer(on: "2026-10-10"))
        XCTAssertEqual(state.stars, 180)
        XCTAssertEqual(state.receipts, ["0/visualToAnswer", "0/answerToRepresentation", "0/buildQuantity"])
    }

    func testMathJourneyCountsCorrectFirstAnswersAndEveryMatchedPair() throws {
        func attempt(_ index: Int, _ result: GradedAttemptResult, _ family: ActivityFamily) throws -> ActivityAttemptData {
            try XCTUnwrap(ActivityAttemptData(
                itemID: ActivityItemID(rawValue: "item-1"),
                attemptIndex: index,
                result: result,
                activityFamily: family
            ))
        }
        XCTAssertTrue(MathDailyJourneyPolicy.counts(try attempt(1, .correct, .multipleChoice)))
        XCTAssertFalse(MathDailyJourneyPolicy.counts(try attempt(2, .correct, .multipleChoice)))
        XCTAssertFalse(MathDailyJourneyPolicy.counts(try attempt(1, .incorrect, .buildNumber)))
        XCTAssertTrue(MathDailyJourneyPolicy.counts(try attempt(3, .correct, .pairs)))
        XCTAssertTrue(MathDailyJourneyPolicy.counts(try attempt(2, .correct, .memory)))
        XCTAssertFalse(MathDailyJourneyPolicy.counts(try attempt(1, .incorrect, .memory)))
    }

    func testMathJourneyIsKeptAcrossLaunches() throws {
        let suiteName = "MinikDailyLearningTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let repository = MathDailyJourneyRepository(userDefaults: defaults, storageKey: "math.daily")
        XCTAssertEqual(repository.load(), MathDailyJourneyState())

        var state = MathDailyJourneyState()
        _ = state.recordCountedAnswer(on: "2026-10-09")
        repository.save(state)

        XCTAssertEqual(MathDailyJourneyRepository(userDefaults: defaults, storageKey: "math.daily").load(), state)
        XCTAssertEqual(state.answers, 1)
    }
}
