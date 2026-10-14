import XCTest
@testable import MinikPlus

/// Android Minik DailyLearningDeviceTest and Android Minik Math Plus's daily route (2026-10-13).
final class MinikDailyLearningTests: XCTestCase {
    func testOnlyRealIncreasesCountAndLanguagesDaysAndProductsStaySeparate() throws {
        let suiteName = "MinikDailyLearningTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let repository = MinikDailyLearningRepository(product: .minikPlus, userDefaults: defaults)
        let day = "2026-10-09"

        XCTAssertFalse(repository.record(language: .english, previousPoints: 10, nextPoints: 10, day: day))
        XCTAssertFalse(repository.record(language: .english, previousPoints: 10, nextPoints: 0, day: day))
        for points in 0..<4 {
            XCTAssertFalse(repository.record(
                language: .english,
                previousPoints: Int64(points),
                nextPoints: Int64(points + 1),
                day: day
            ))
        }
        XCTAssertTrue(repository.record(language: .english, previousPoints: 4, nextPoints: 5, day: day))
        XCTAssertFalse(repository.record(language: .english, previousPoints: 5, nextPoints: 6, day: day))

        XCTAssertEqual(repository.count(language: .english, day: day), 5)
        XCTAssertEqual(repository.count(language: .hebrew, day: day), 0)
        XCTAssertEqual(repository.count(language: .english, day: "2026-10-10"), 0)
        let englishOnly = MinikDailyLearningRepository(product: .minikPlusEnglish, userDefaults: defaults)
        XCTAssertEqual(englishOnly.count(language: .english, day: day), 0)
    }

    func testANewDayStartsAgainFromOne() throws {
        let suiteName = "MinikDailyLearningTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let repository = MinikDailyLearningRepository(product: .minikPlus, userDefaults: defaults)

        repository.record(language: .hebrew, previousPoints: 0, nextPoints: 2, day: "2026-10-09")
        repository.record(language: .hebrew, previousPoints: 2, nextPoints: 4, day: "2026-10-10")

        XCTAssertEqual(repository.count(language: .hebrew, day: "2026-10-10"), 1)
    }

    func testDailyLearningBelongsToThePlayingChild() {
        for product in [ProductVariant.minikPlus, .minikPlusEnglish] {
            XCTAssertTrue(ChildProfileStoredKey.learnerKeys(for: product).contains(ChildProfileStoredKey(
                name: MinikDailyLearningRepository.storageKey(for: product),
                kind: .data
            )))
        }
    }

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
