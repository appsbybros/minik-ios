import XCTest
@testable import MinikMultiPingPong

// Android cross/CrossExerciseTest.kt (MinikCrossPong 828c6fc): the tutorial hook — real input, contact and landing rules
// decide success; nothing ever scores. Android `CrossDrill.RETURN` = iOS `.returning`.
final class CrossExerciseTests: XCTestCase {
    private func drill(_ players: Int, _ exercise: CrossExercise, _ control: CrossControl = .beginner) -> CrossEngine {
        let seats = players == 3 ? localTable("mia", "june") : localTable("mia", "june", "amber")
        return CrossEngine(seats: seats, control: control, target: 7, seed: 2, exercise: exercise)
    }

    private func tapServe(_ e: CrossEngine, _ drag: Double) {
        let at = e.geometry.fromLocal(0, 0, 0.8)
        e.touch(at)
        e.touch(at, drag: MPPoint(drag, 0), down: false)
        e.endTouch()
    }

    private func isRally(_ event: CrossEvent) -> Bool {
        if case .rally = event { return true }
        return false
    }

    private func isContactOrServe(_ event: CrossEvent) -> Bool {
        switch event {
        case .contact, .served: return true
        default: return false
        }
    }

    // Kotlin: aServeDrillSucceedsOnlyWhenTheServeReachesTheExpectedOpponent
    func testAServeDrillSucceedsOnlyWhenTheServeReachesTheExpectedOpponent() {
        for players in 3...4 {
            let opponents = CrossAimMap(CrossGeometry(players)).opponents(0)
            guard let left = opponents.first, let right = opponents.last else { return XCTFail("no opponents") }
            let cases: [(Int?, Bool)] = [(right, true), (left, false), (nil, true)]
            for (expected, success) in cases {
                let e = drill(players, CrossExercise(drill: .serve, expected: expected))
                XCTAssertEqual(CrossStatus.yourServe, e.status)
                tapServe(e, 60)
                let events = e.play(5) { e.trainingResult != nil }
                guard let result = e.trainingResult else {
                    XCTFail("\(players) \(String(describing: expected)): no training result")
                    continue
                }
                XCTAssertEqual(success, result.success, "\(players) \(String(describing: expected))")
                XCTAssertNil(result.kind)
                XCTAssertEqual(right, result.receiver)
                XCTAssertEqual(CrossStatus.practiceDone, e.status)
                XCTAssertFalse(events.contains { self.isRally($0) })
                XCTAssertTrue(e.referee.scores.allSatisfy { $0 == 0 })
                // The drill is over: nothing more happens until the tutorial starts a new one.
                XCTAssertFalse(e.play(5).contains { self.isContactOrServe($0) })
            }
        }
    }

    // Kotlin: aReturnDrillServesToTheLearnerAndJudgesTheReturn
    func testAReturnDrillServesToTheLearnerAndJudgesTheReturn() {
        for players in 3...4 {
            guard let left = CrossAimMap(CrossGeometry(players)).opponents(0).first else { return XCTFail("no opponents") }
            let e = drill(players, CrossExercise(drill: .returning, expected: left, server: 1))
            XCTAssertEqual(1, e.referee.server)
            // The house player always serves legally to the learner.
            e.play(4) { e.referee.phase == .receivable }
            XCTAssertEqual(0, e.referee.receiver)
            let path = e.ballAfter(25)
            e.touch(path)
            e.touch(path, drag: MPPoint(-60, 0), down: false)
            e.endTouch()
            e.play(5) { e.trainingResult != nil }
            XCTAssertEqual(CrossTrainingResult(success: true, kind: nil, receiver: left), e.trainingResult)
            XCTAssertTrue(e.referee.scores.allSatisfy { $0 == 0 })
        }
    }

    // Kotlin: missesAndBadServesFailADrillWithoutScoring
    func testMissesAndBadServesFailADrillWithoutScoring() {
        let missed = drill(4, CrossExercise(drill: .returning, server: 2))
        missed.play(5) { missed.referee.phase == .receivable }
        // Keep the paddle on the far side of the arm from the ball.
        let side: Double = missed.geometry.toLocal(0, missed.ballPosition).u > 0 ? -0.6 : 0.6
        missed.touch(missed.geometry.fromLocal(0, side, CrossGeometry.homeDepth))
        missed.endTouch()
        missed.play(10) { missed.trainingResult != nil }
        XCTAssertEqual(CrossTrainingResult(success: false, kind: .missed), missed.trainingResult)
        let pro = drill(4, CrossExercise(drill: .serve), .pro)
        let spot = pro.geometry.toView(0, pro.serveSpot(0))
        pro.touch(pro.geometry.fromView(0, spot - MPPoint(0, 0.08)))
        pro.touch(pro.geometry.fromView(0, spot + MPPoint(0, 0.08)), velocity: MPPoint(0, 0.6), down: false)
        // Android 47ad0c9: a downward swipe is reported as a backward serve.
        XCTAssertEqual(CrossTrainingResult(success: false, kind: .badServe, serveFault: .backward), pro.trainingResult)
        for e in [missed, pro] {
            XCTAssertTrue(e.referee.scores.allSatisfy { $0 == 0 })
            XCTAssertEqual(0, e.referee.ralliesPlayed)
        }
    }
}
