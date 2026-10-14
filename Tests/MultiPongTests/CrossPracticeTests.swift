import XCTest
@testable import MinikMultiPingPong

// Android app/src/test/.../cross/CrossPracticeTest.kt (MinikCrossPong 5c1aa4d): the daily journey is completed from real
// contacts and landings only.

final class CrossPracticeTests: XCTestCase {
    /// Kotlin `drive`: serve to the target, choose the target (or the partner), double-tap a set, swipe a raised ball.
    private func drive(_ p: CrossPractice, _ seconds: Double = 100) {
        p.start()
        for _ in 0..<Int(seconds * 120) {
            if p.ended { return }
            let e = p.engine
            if !e.paused {
                if e.referee.mayServe(0) { e.touch(p.target); e.endTouch() }
                else if e.predictedReceiver == 0 {
                    if e.selectedAim != p.target && p.stage.skill != .pass { e.touch(p.target) }
                    if p.stage.skill == .set { e.liftToTeammate() }
                    if p.stage.skill == .pass {
                        let pass = e.geometry.fromLocal(p.stage.partnerSeat, 0, 0.88)
                        if e.selectedAim != pass { e.touch(pass) }
                    }
                    let at = e.ballPosition
                    if e.geometry.inStrikeZone(0, at) {
                        if e.receivingSet { e.touch(at + MPPoint(0, 0.08)); e.touch(at, velocity: MPPoint(0.2, -1.35), down: false) }
                        else { e.touch(at, down: false) }
                    }
                }
            }
            p.advance(CrossEngine.step)
        }
    }
    // Kotlin: everySingleBallStageCanBeCompletedFromRealContacts
    func testEverySingleBallStageCanBeCompletedFromRealContacts() {
        for cycle in [0, 3] {
            for (i, s) in CrossJourney.stages.enumerated() where !s.team {
                let p = CrossPractice(step: cycle * 30 + i)
                drive(p, 180)
                XCTAssertTrue(p.won, "\(s.id) cycle \(cycle): \(p.successes)/\(p.goal), misses=\(p.mistakes), \(String(describing: p.engine.trainingResult))")
            }
        }
    }
    // Kotlin: idleAndPausedPlayCannotWinOrAdvance
    func testIdleAndPausedPlayCannotWinOrAdvance() {
        let p = CrossPractice(step: 1)
        p.start(); p.paused = true
        let state = p.save()
        for _ in 0..<500 { p.advance(CrossEngine.step) }
        XCTAssertTrue(NSDictionary(dictionary: state).isEqual(to: p.save()))
        p.paused = false
        for _ in 0..<9000 { p.advance(CrossEngine.step) }
        XCTAssertTrue(p.ended); XCTAssertFalse(p.won); XCTAssertEqual(0, p.successes)
    }
    // Kotlin: passAndRaisedPassUseDifferentPhysicalGoals
    func testPassAndRaisedPassUseDifferentPhysicalGoals() {
        for i in [7, 8, 18, 19] {
            let p = CrossPractice(step: i)
            drive(p, 180)
            XCTAssertTrue(p.won, "\(p.stage.id): \(p.successes), \(p.mistakes)")
        }
    }
    // Kotlin: allSmashStagesNeedAndAcceptTimedSwipes
    func testAllSmashStagesNeedAndAcceptTimedSwipes() {
        for i in [9, 20, 28] {
            let p = CrossPractice(step: i)
            drive(p, 240)
            XCTAssertTrue(p.won, "\(p.stage.id): \(p.successes), \(p.mistakes), \(String(describing: p.engine.teamFlight))")
        }
    }
    // Kotlin: snapshotsKeepFlightProgressAndPaint
    func testSnapshotsKeepFlightProgressAndPaint() throws {
        let p = CrossPractice(step: 2)
        p.start()
        for _ in 0..<160 { p.advance(CrossEngine.step) }
        let copy = try CrossPractice.restore(p.save())
        XCTAssertEqual(p.engine.ballState, copy.engine.ballState); XCTAssertEqual(p.clock, copy.clock)
        XCTAssertEqual(p.successes, copy.successes); XCTAssertEqual(p.paint.owners, copy.paint.owners)
    }
    // Kotlin: areaIsClippedAndRepaintedNotAdded
    func testAreaIsClippedAndRepaintedNotAdded() {
        let g = CrossGeometry(4)
        let p = CrossPaint(g, teams: CrossTeams([0, 1, 0, 1]))
        XCTAssertEqual(0.0, p.coverage(0))
        let at = g.fromLocal(1, 0, 0.8)
        p.paint(at, team: 0)
        let area = p.coverage(0)
        XCTAssertGreaterThan(area, 0)
        for _ in 0..<10 { p.paint(at, team: 0) }
        XCTAssertEqual(area, p.coverage(0))
        p.paint(at, team: 1)
        XCTAssertEqual(0.0, p.coverage(0))
        p.paint(MPPoint(8, 8), team: 0)
        XCTAssertEqual(0.0, p.coverage(0))
    }
    // Kotlin: defenceAddsOneFeederAtATimeAndPaintNeedsHumanReturns
    func testDefenceAddsOneFeederAtATimeAndPaintNeedsHumanReturns() {
        for (step, count) in [(14, 1), (23, 2), (24, 3)] {
            let p = CrossPractice(step: step)
            p.start()
            var feeders = Set<Int>()
            for _ in 0..<30000 {
                if let server = p.engine.exercise?.server { feeders.insert(server) }
                let e = p.engine
                if !e.paused && e.predictedReceiver == 0 && e.geometry.inStrikeZone(0, e.ballPosition) { e.touch(e.ballPosition, down: false) }
                p.advance(CrossEngine.step)
            }
            XCTAssertEqual(count, feeders.count, "stage \(step)")
            XCTAssertTrue(p.won, "stage \(step)")
        }
        for step in [10, 15, 21] {
            let p = CrossPractice(step: step)
            p.start()
            for _ in 0..<11000 { p.advance(CrossEngine.step) }
            XCTAssertTrue(p.ended); XCTAssertFalse(p.won)
        }
    }
    // Kotlin: newStageNamesExistInEverySupportedLanguage
    func testNewStageNamesExistInEverySupportedLanguage() {
        for language in ["en", "he", "es", "ar", "hi", "nl"] {
            MPText.configure(language)
            for s in CrossJourney.stages {
                let name = MPText.t(s.en, s.he, MPText.language == "he")
                XCTAssertFalse(name.trimmingCharacters(in: .whitespaces).isEmpty)
                if language != "en" { XCTAssertNotEqual(s.en, name, "Untranslated \(s.id) in \(language)") }
            }
        }
        MPText.configure("en")
    }
    // Kotlin: stageIdentitiesAndBotRolesRemainStable
    func testStageIdentitiesAndBotRolesRemainStable() {
        XCTAssertEqual(30, Set(CrossJourney.stages.map { $0.id }).count)
        for s in CrossJourney.stages {
            let first = s.bot(0, exclude: ["miniko"]), later = s.bot(5, exclude: ["miniko"])
            if s.cooperative { XCTAssertGreaterThanOrEqual(s.quality(first.profile), s.quality(later.profile)) }
            else { XCTAssertLessThanOrEqual(s.quality(first.profile), s.quality(later.profile)) }
        }
    }
}
