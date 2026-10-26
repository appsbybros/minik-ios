import XCTest
@testable import MinikPlus

/// Android Minik Math Plus LearningFeedbackTest (ab3e427), for what iOS ports: every object
/// fits its card, Visual → Answer counts a picture at every level, the soccer swipe needs an
/// upward gesture and uses its direction and speed, and the sixteen Math Cards rules. Also the
/// hands-on examples of dc12a5c.
final class MathLearningFeedbackTests: XCTestCase {
    func testCompactCardsNeverClipTheirLastObjects() throws {
        let layout = MathQuantityLayout()
        for width in [55.0, 72, 90, 130, 200] {
            for height in [45.0, 70, 100, 150] {
                for count in 1...30 {
                    let result = try XCTUnwrap(
                        layout.layout(count: count, inWidth: width, height: height, mode: .individual),
                        "\(count) in \(width) x \(height)"
                    )
                    XCTAssertEqual(result.items.count, count)
                    for item in result.items {
                        XCTAssertGreaterThan(item.diameter, 0)
                        XCTAssertGreaterThanOrEqual(item.centerX - item.diameter / 2, -0.001)
                        XCTAssertLessThanOrEqual(item.centerX + item.diameter / 2, width + 0.001)
                        XCTAssertGreaterThanOrEqual(item.centerY - item.diameter / 2, -0.001)
                        XCTAssertLessThanOrEqual(item.centerY + item.diameter / 2, height + 0.001)
                    }
                }
            }
        }
    }

    func testPictureActivityAlwaysHasAnActualPictureAtEveryLevel() throws {
        for level in MathCurriculumPolicy.levels.map(\.id) {
            for _ in 0..<20 {
                let session = try XCTUnwrap(MathPictureQuestions.session(for: level), level.rawValue)
                XCTAssertEqual(session.challenges.count, MathPictureQuestions.challengeCount)
                for challenge in session.challenges {
                    guard case .math(.quantity(let quantity))? = challenge.prompt.representations.first else {
                        return XCTFail("\(level.rawValue) shows no picture to count")
                    }
                    XCTAssertTrue((1...MathPictureQuestions.countLimit(for: level)).contains(quantity.count))
                    XCTAssertLessThanOrEqual(quantity.count, 30)
                    XCTAssertEqual(challenge.expectedAnswer, .semanticValue(.integer(quantity.count)))
                    XCTAssertEqual(challenge.choices.count, 4)
                    XCTAssertEqual(challenge.choices.filter { $0.semanticValue == .integer(quantity.count) }.count, 1)
                }
            }
        }
        XCTAssertEqual(MathPictureQuestions.countLimit(for: .m1), 10)
        XCTAssertEqual(MathPictureQuestions.countLimit(for: .m3), 20)
        XCTAssertEqual(MathPictureQuestions.countLimit(for: .m4), 30)
    }

    func testVisualToAnswerCountsAPictureAboveTheFirstLevel() throws {
        let factory = MathM5ActivitySessionFactory(configuration: .configuration(for: .minikMath))
        guard case .visualToAnswer(let session)? = factory.makeSession(for: .visualToAnswer) else {
            return XCTFail("Expected a Visual → Answer session")
        }
        for challenge in session.challenges {
            guard case .math(.quantity)? = challenge.prompt.representations.first else {
                return XCTFail("Level 5 Visual → Answer shows no picture")
            }
        }
        let rejecting = MathM8ActivitySessionFactory(
            configuration: .configuration(for: .minikMath),
            fitGate: .rejectingForTests
        )
        XCTAssertNil(rejecting.makeSession(for: .visualToAnswer))
    }

    func testSoccerRequiresAnUpwardGestureAndUsesItsDirectionAndSpeed() throws {
        XCTAssertNil(MathSoccerShot.make(startX: 0.5, startY: 0.9, dx: 0, dy: 0, elapsedMilliseconds: 100))
        XCTAssertNil(MathSoccerShot.make(startX: 0.5, startY: 0.9, dx: 0, dy: 0.3, elapsedMilliseconds: 200))
        let straight = try XCTUnwrap(MathSoccerShot.make(startX: 0.5, startY: 0.9, dx: 0, dy: -0.4, elapsedMilliseconds: 400))
        XCTAssertTrue(straight.isInsideGoal)
        let fast = try XCTUnwrap(MathSoccerShot.make(startX: 0.5, startY: 0.9, dx: 0, dy: -0.4, elapsedMilliseconds: 100))
        XCTAssertLessThan(fast.durationMilliseconds, straight.durationMilliseconds)
        XCTAssertFalse(try XCTUnwrap(MathSoccerShot.make(startX: 0.25, startY: 0.9, dx: -0.4, dy: -0.2, elapsedMilliseconds: 200)).isInsideGoal)
        XCTAssertTrue(try XCTUnwrap(MathSoccerShot.make(startX: 0.25, startY: 0.9, dx: 0.14, dy: -0.4, elapsedMilliseconds: 200)).isInsideGoal)
        XCTAssertTrue(MathSoccerShot.straight.isInsideGoal)
    }

    func testMathCardsHaveSixteenRulesFourToAPage() {
        XCTAssertEqual(MathRuleCard.allCases.count, 16)
        XCTAssertEqual(MathRuleCard.pageCount, 4)
        let pages = (0..<MathRuleCard.pageCount).map(MathRuleCard.page)
        XCTAssertTrue(pages.allSatisfy { $0.count == MathRuleCard.pageSize })
        XCTAssertEqual(Set(pages.flatMap { $0 }), Set(MathRuleCard.allCases))
        XCTAssertEqual(Set(MathRuleCard.allCases.map(\.rule)).count, 16)
        XCTAssertEqual(Set(MathRuleCard.allCases.map(\.example)).count, 16)
        XCTAssertTrue(MathRuleCard.allCases.allSatisfy { !$0.rule.isEmpty && !$0.example.isEmpty })
    }

    func testExamplesAreOfferedOnceForNumberBuildingAndSoccerOnly() throws {
        let suiteName = "MathLearningFeedbackTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let repository = MathActivityDemoRepository(userDefaults: defaults)

        XCTAssertTrue(repository.needsDemo(.mathSoccer))
        XCTAssertTrue(repository.needsDemo(.buildNumber))
        XCTAssertFalse(repository.needsDemo(.visualToAnswer))
        repository.finishDemo(.mathSoccer)
        XCTAssertFalse(repository.needsDemo(.mathSoccer))
        XCTAssertTrue(repository.needsDemo(.buildNumber))
    }

    func testExampleContentMatchesAndroid() throws {
        let round = try XCTUnwrap(MathActivityDemoContent.soccerRound())
        XCTAssertEqual(round.answerBalls.map(\.semanticValue), [.integer(1), .integer(2), .integer(3)])
        let first = try XCTUnwrap(round.challengeTargets.first)
        XCTAssertEqual(first.challenge.expectedAnswer, .semanticValue(.integer(2)))
        XCTAssertEqual(MathReadAloud.exercise(first.challenge.prompt.representations), "1 + 1")

        let build = try XCTUnwrap(MathActivityDemoContent.buildNumberSession())
        let challenge = build.currentChallenge
        let tokensByID = Dictionary(uniqueKeysWithValues: challenge.availableTokens.map { ($0.id, $0) })
        let expected = challenge.expectedTokenSequence.compactMap { id -> String? in
            guard case .mathExpression(let value)? = tokensByID[id]?.representation else { return nil }
            return value.expression
        }
        XCTAssertEqual(expected, ["1", "2"])
    }
}
