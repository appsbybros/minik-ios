import XCTest
@testable import MinikSquash

/// Android core/SquashRefinementTest.kt.
final class SquashRefinementTests: XCTestCase {
    private func game(_ c: SportsConfig = sportsConfig()) -> SportsEngine {
        return SportsEngine(c, [Participant("you", "miniko", 0, false), Participant("other", "minik", 1, false)], matchId: "acceptance")
    }

    private func ready(_ e: SportsEngine) {
        e.countdown = 0.0
        e.beginServeQuestions()
    }

    private func contact(_ e: SportsEngine) {
        e.phase = .rally
        e.expected = 0
        e.ball.active = true
        e.ball.front = true
        e.ball.p = e.players[0].p
        e.ball.z = 1.0
        e.ball.hitter = "other"
    }

    private func index(_ q: Question) -> Int { return q.options.firstIndex(of: q.answer) ?? -1 }

    func testQuestionDefaultsAndValidation() {
        let c = SportsConfig()
        XCTAssertEqual(c.answerMode, .serves)
        XCTAssertEqual(c.serveQuestions, .fullTime)
        XCTAssertEqual(c.answerSeconds, 15)
        XCTAssertTrue(c.questionsEnabled)
        for time in [5, 10, 15, 30] { XCTAssertTrue(sportsConfig(answerSeconds: time).isValid) }
    }

    func testMatchPointsDoNotIncreaseOnCorrectWallContact() throws {
        let e = game()
        ready(e)
        let p = e.players[0]
        let q = try XCTUnwrap(e.answers["you"]).question
        e.phase = .rally
        e.ball.active = true
        e.launchSquash(p, index(q))
        advance(e, seconds: 0.86)
        XCTAssertEqual(p.correct, 1)
        XCTAssertEqual(e.scores, [0, 0])
        e.point(1, "two_bounces")
        XCTAssertEqual(e.scores[1], 1)
        XCTAssertEqual(p.correct, 1)
    }

    func testAnswerIsRecordedOnlyOnceAndWrongAnswerDoesNotAwardPoint() throws {
        let e = game()
        ready(e)
        let q = try XCTUnwrap(e.answers["other"]).question
        let wrong = try XCTUnwrap(q.options.indices.first { q.options[$0] != q.answer })
        e.command("other", "a", "answer", Double(wrong))
        XCTAssertEqual(e.players[1].mistakes, 1)
        XCTAssertFalse(e.command("other", "b", "answer", Double(index(q))))
        XCTAssertEqual(e.players[1].correct, 0)
        XCTAssertEqual(e.scores, [0, 0])
    }

    func testFullWindowAllowsReceiverToAnswerAfterServerHasChosen() throws {
        let e = game(sportsConfig(answerSeconds: 5))
        ready(e)
        e.command("you", "target", "wall", 2.22, 2.6)
        advance(e, seconds: 3.0)
        XCTAssertEqual(e.phase, .ready)
        let q = try XCTUnwrap(e.answers["other"]).question
        e.command("other", "answer", "answer", Double(index(q)))
        XCTAssertEqual(e.players[1].correct, 1)
        advance(e, seconds: 2.1)
        XCTAssertEqual(e.phase, .rally)
        XCTAssertNil(e.answerFor("other"))
    }

    func testUntilServeClosesReceiverWindowEarly() {
        let e = game(sportsConfig(serveQuestions: .untilServe))
        ready(e)
        e.command("you", "target", "wall", 2.22, 2.6)
        advance(e, seconds: 0.45)
        XCTAssertEqual(e.phase, .rally)
        XCTAssertTrue(e.serveElapsed < 15)
        XCTAssertNil(e.answerFor("other"))
    }

    func testOwnServeNeverOpensAReceiverQuestion() {
        let e = game(sportsConfig(serveQuestions: .own))
        ready(e)
        XCTAssertNotNil(e.answerFor("you"))
        XCTAssertNil(e.answerFor("other"))
    }

    func testParentOffRemovesQuestionsAndWaiting() {
        let e = game(sportsConfig(questionsEnabled: false))
        ready(e)
        XCTAssertTrue(e.answers.isEmpty)
        e.command("you", "target", "wall", 2.22, 2.6)
        advance(e, seconds: 0.45)
        XCTAssertEqual(e.phase, .rally)
        XCTAssertEqual(e.players.reduce(0) { $0 + $1.correct }, 0)
    }

    func testBeginnerPositionsButNeverHitsWithoutTap() {
        let e = game(sportsConfig(questionsEnabled: false))
        contact(e)
        advance(e, seconds: 0.1)
        XCTAssertEqual(e.players[0].contacts, 0)
        XCTAssertTrue(e.command("you", "hit", "wall", 1.4, 2.7))
        XCTAssertEqual(e.players[0].contacts, 1)
    }

    func testEarlyTapExpiresInsteadOfStayingQueued() {
        for c in Control.allCases {
            let e = game(sportsConfig(control: c, questionsEnabled: false))
            contact(e)
            e.ball.p = Vec(2.8, -1.0)
            e.ball.velocity = Vec()
            e.ball.z = 1.5
            e.ball.vz = 0.0
            e.command("you", "early", c == .pro ? "stroke" : "wall", 1.1, 2.5)
            advance(e, seconds: 0.65)
            e.ball.p = e.players[0].p
            e.ball.z = 1.0
            e.ball.active = true
            e.ball.front = true
            e.phase = .rally
            e.expected = 0
            advance(e, seconds: 0.02)
            XCTAssertEqual(e.players[0].contacts, 0, c.name)
        }
    }

    func testExactTargetsInAssistedModes() {
        for c in [Control.beginner, Control.standard] {
            for x in [-2.22, -0.74, 0.74, 2.22] {
                let e = game(sportsConfig(control: c, questionsEnabled: false))
                contact(e)
                e.command("you", "target", "wall", x, 2.6)
                let t = (-e.config.halfDepth - e.ball.p.y) / e.ball.velocity.y
                XCTAssertEqual(e.ball.p.x + e.ball.velocity.x * t, x, accuracy: 0.00001)
                XCTAssertEqual(e.ball.z + e.ball.vz * t - 0.5 * e.config.gravity * t * t, 2.6, accuracy: 0.00001)
            }
        }
    }

    func testServeUsesChosenWallPoint() {
        let e = game(sportsConfig(serveQuestions: .own))
        ready(e)
        e.command("you", "target", "wall", -0.74, 2.6)
        advance(e, seconds: 2.0)
        XCTAssertNotNil(e.events.first { $0.type == "hit" }, "phase \(e.phase) events \(e.events)")
        XCTAssertEqual(e.players[0].pendingTarget.x, -0.74, accuracy: 0.0001)
    }

    func testFloorAimIsAnActualFault() {
        let e = game(sportsConfig(control: .standard, questionsEnabled: false))
        contact(e)
        e.command("you", "floor", "floor", 1.0, 0.0)
        advance(e, seconds: 1.2)
        XCTAssertEqual(e.reason, "floor_before_wall")
        XCTAssertEqual(e.scores[1], 1)
    }

    func testProRejectsTapAndPowerChangesBallSpeed() {
        var speeds: [Double] = []
        for power in [0.1, 0.95] {
            let e = game(sportsConfig(control: .pro, questionsEnabled: false))
            contact(e)
            XCTAssertFalse(e.command("you", "tap", "wall", 1.0, 2.5))
            e.command("you", "stroke", "stroke", 1.0, 2.5, power)
            XCTAssertEqual(e.players[0].contacts, 1)
            speeds.append(e.ball.velocity.length())
        }
        XCTAssertTrue(speeds[1] > speeds[0] * 1.5)
    }

    func testSlowMotionUsesRealAnswerSecondsAndRestoresAfterContact() throws {
        let e = game(sportsConfig(answerMode: .everyHit, answerSeconds: 5))
        ready(e)
        e.phase = .rally
        e.ball.active = true
        e.launchSquash(e.players[1], 1)
        advance(e, seconds: 1.5)
        XCTAssertTrue(e.timeScale < 0.06, "scale \(e.timeScale)")
        XCTAssertEqual(try XCTUnwrap(e.answerFor("you")).remaining, 4.2, accuracy: 0.03)
        e.ball.p = e.players[0].p
        e.ball.z = 1.0
        e.ball.front = true
        e.command("you", "return", "wall", 1.1, 2.6)
        XCTAssertEqual(e.players[0].contacts, 1)
        advance(e, seconds: 0.65)
        XCTAssertTrue(e.timeScale > 0.88, "scale \(e.timeScale)")
    }

    func testBotsNeverCauseReadingSlowdown() {
        let e = SportsEngine(sportsConfig(answerMode: .everyHit), [Participant("a", "minik", 0, true), Participant("b", "mia", 1, true)])
        advance(e, seconds: 20.0)
        XCTAssertEqual(e.timeScale, 1.0, accuracy: 0.001)
    }

    func testAllFourAnswerServeTargetsRespectOppositeQuarter() throws {
        for i in 0...3 {
            let e = game(sportsConfig(serveQuestions: .own))
            ready(e)
            let q = try XCTUnwrap(e.answers["you"]).question
            e.command("you", "target", "wall", e.targetX(i), e.targetZ(i))
            advance(e, seconds: 4.0)
            XCTAssertNotEqual(e.reason, "serve_fault", "target \(i) events \(e.events)")
            XCTAssertEqual(e.players[0].correct, q.options[i] == q.answer ? 1 : 0)
        }
    }

    func testDelayedAnswerCannotApplyToAnotherQuestion() throws {
        let e = game()
        ready(e)
        let q = try XCTUnwrap(e.answers["other"]).question
        XCTAssertFalse(e.command("other", "old", "answer", Double(index(q)), questionId: "older-question"))
        XCTAssertEqual(e.players[1].correct, 0)
        XCTAssertTrue(e.command("other", "current", "answer", Double(index(q)), questionId: q.id))
        XCTAssertEqual(e.players[1].correct, 1)
    }

    func testTimelyChoiceRemainsEligibleWhenPhysicalContactIsLater() throws {
        let e = game(sportsConfig(answerMode: .everyHit, answerSeconds: 5))
        ready(e)
        let q = try XCTUnwrap(e.answers["you"]).question
        let i = index(q)
        e.command("you", "choice", "answer", Double(i))
        try XCTUnwrap(e.answers["you"]).remaining = 0.0
        e.phase = .rally
        e.ball.active = true
        e.launchSquash(e.players[0], i)
        XCTAssertTrue(e.shotHasQuestion)
        advance(e, seconds: 0.9)
        XCTAssertEqual(e.players[0].correct, 1)
    }

    func testMovementLessonDoesNotServeBeforeThePlayerTriesMoving() {
        let e = game(sportsConfig(tutorial: true))
        advance(e, seconds: 35.0)
        XCTAssertEqual(e.phase, .ready)
        XCTAssertTrue(e.answers.isEmpty)
        e.command("you", "walk", "move", 0.0, 1.0)
        XCTAssertEqual(e.tutorialStage, 1)
        advance(e, seconds: 0.1)
        XCTAssertNotNil(e.answerFor("you"))
    }
}

/// Android core/VolleyRefinementTest.kt.
final class VolleyRefinementTests: XCTestCase {
    private func game(_ mode: Control = .standard, _ serve: Control? = nil, seed: Int = 12) -> SportsEngine {
        return SportsEngine(sportsConfig(.volley, control: mode, seed: seed, serveControl: serve ?? mode),
                            [Participant("you", "miniko", 0, false), Participant("mate", "june", 0, false),
                             Participant("one", "gaya", 1, false), Participant("two", "minik", 1, false)])
    }

    private func incoming(_ e: SportsEngine, z: Double = 1.4, distance: Double = 0.0, touches: Int = 1) {
        e.phase = .rally
        e.countdown = 0.0
        e.clock = 5.0
        e.returnTeam = 0
        let p = e.players[0]
        p.p = Vec(0.0, 4.0)
        p.goal = p.p
        let b = e.ball
        b.active = true
        b.hitter = touches > 1 ? "mate" : "one"
        b.previousTeam = touches > 1 ? 0 : 1
        b.touches = touches > 1 ? touches : 1
        b.receiver = "you"
        b.z = z
        b.p = p.p + Vec(distance, 0.0)
        b.shot = 3
        b.velocity = Vec()
        b.vz = 0.0
    }

    private func untilPoint(_ e: SportsEngine) {
        for _ in 0..<600 where e.phase == .rally { e.update(1.0 / 120) }
    }

    func testExactUserRatings() {
        XCTAssertEqual(VolleySkills.of("moshiko").values(), [2, 4, 5, 4, 3, 3])
        XCTAssertEqual(VolleySkills.of("gaya").values(), [5, 5, 5, 5, 5, 4])
        XCTAssertEqual(VolleySkills.all.count, 17)
    }

    func testBeginnerStillContactsAutomatically() {
        let e = game(.beginner)
        incoming(e)
        e.update(0.02)
        XCTAssertEqual(e.players[0].contacts, 1)
    }

    func testManualControlsDoNotAutoHit() {
        for m in [Control.standard, Control.pro] {
            let e = game(m)
            incoming(e)
            e.update(0.02)
            XCTAssertEqual(e.players[0].contacts, 0)
        }
    }

    func testTappedOpponentTargetIsExact() {
        let e = game()
        incoming(e)
        e.command("you", "a", "volley_tap", 2.7, -5.0)
        untilPoint(e)
        XCTAssertEqual(e.ball.p.x, 2.7, accuracy: 0.08)
        XCTAssertEqual(e.ball.p.y, -5.0, accuracy: 0.08)
        XCTAssertEqual(e.reason, "ground")
    }

    func testFirstTouchCanAttack() {
        let e = game()
        incoming(e)
        e.command("you", "a", "volley_tap", -2.0, -4.0)
        XCTAssertEqual(e.returnTeam, 1)
        XCTAssertEqual(e.ball.touches, 1)
    }

    func testTapCanPassToOwnCourt() {
        let e = game()
        incoming(e)
        e.command("you", "a", "volley_tap", -2.0, 2.8)
        XCTAssertEqual(e.returnTeam, 0)
        XCTAssertEqual(e.ball.receiver, "mate")
    }

    func testDuplicateInputCannotContactTwice() {
        let e = game()
        incoming(e)
        XCTAssertTrue(e.command("you", "a", "volley_tap", 0.0, -4.0))
        XCTAssertFalse(e.command("you", "a", "volley_tap", 0.0, -4.0))
        e.update(0.1)
        XCTAssertEqual(e.players[0].contacts, 1)
    }

    func testLowDoubleTapSetsFirstContact() {
        let e = game()
        incoming(e, z: 1.0)
        e.command("you", "a", "volley_spike", 0.0, -4.0)
        XCTAssertEqual(e.returnTeam, 0)
        XCTAssertTrue(e.events.contains { $0.type == "high_set" })
        XCTAssertTrue(e.ball.vz > 7)
    }

    func testStandardLowThirdSpikeFails() {
        let e = game()
        incoming(e, z: 1.0, touches: 2)
        e.command("you", "a", "volley_spike", 0.0, -4.0)
        XCTAssertEqual(e.players[0].contacts, 0)
        XCTAssertTrue(e.events.contains { $0.detail == "low_spike" })
    }

    func testBeginnerLowThirdDoubleTapSucceeds() {
        let e = game(.beginner)
        incoming(e, z: 1.0, touches: 2)
        e.command("you", "a", "volley_spike", 0.0, -4.0)
        XCTAssertEqual(e.players[0].contacts, 1)
        XCTAssertEqual(e.returnTeam, 1)
    }

    func testProLowDoubleTapFails() {
        let e = game(.pro)
        incoming(e, z: 1.0)
        e.command("you", "a", "volley_spike", 0.0, -1.0)
        XCTAssertEqual(e.players[0].contacts, 0)
    }

    func testStandardOrdinaryTapCannotContactHighSet() {
        let e = game()
        incoming(e, z: 3.0)
        e.command("you", "a", "volley_tap", 0.0, -4.0)
        XCTAssertEqual(e.players[0].contacts, 0)
    }

    func testProTapIsNotSwipe() {
        let e = game(.pro)
        incoming(e)
        XCTAssertFalse(e.command("you", "a", "volley_tap", 0.0, -4.0))
        XCTAssertEqual(e.players[0].contacts, 0)
    }

    func testFasterProSwipeAddsSpeed() {
        let speeds = [0.1, 0.9].map { v -> Double in
            let e = game(.pro)
            incoming(e)
            e.command("you", "a", "volley_swipe", 1.0, -1.0, v)
            return e.ball.velocity.length()
        }
        XCTAssertTrue(speeds[1] > speeds[0] * 1.8)
    }

    func testUpwardProStrokeMakesHigherSet() {
        let e = game(.pro)
        incoming(e)
        e.command("you", "a", "volley_up", -1.0, 0.0, 0.8)
        XCTAssertTrue(e.ball.vz > 9)
        XCTAssertTrue(e.ball.velocity.x < 0)
    }

    func testProCanHitOut() {
        let e = game(.pro)
        incoming(e)
        e.command("you", "a", "volley_swipe", 1.0, 0.0, 1.0)
        untilPoint(e)
        XCTAssertEqual(e.reason, "out")
        XCTAssertEqual(e.scores[1], 1)
    }

    func testWeakDownwardProShotCanFault() {
        let e = game(.pro)
        incoming(e)
        e.command("you", "a", "volley_down", 0.0, -1.0, 0.05)
        untilPoint(e)
        XCTAssertEqual(e.scores[1], 1)
    }

    func testStandardServeAutoTossesBehindBaseline() {
        let e = game()
        e.countdown = 0.0
        advance(e, steps: 90, dt: 0.01)
        XCTAssertTrue(e.volley.toss)
        XCTAssertTrue(e.players[e.server].p.y > 8)
        XCTAssertTrue(e.ball.z > 1.2)
    }

    func testStandardServeAllowsOneRetryThenFault() {
        let e = game()
        e.countdown = 0.0
        advance(e, steps: 600, dt: 0.01)
        XCTAssertEqual(e.scores[1], 1)
        XCTAssertTrue(e.events.contains { $0.type == "serve_retry" })
        XCTAssertEqual(e.reason, "serve_fault")
    }

    func testStandardTimedServeHitsTarget() {
        let e = game()
        e.countdown = 0.0
        advance(e, steps: 95, dt: 0.01)
        e.command("you", "serve", "volley_tap", 2.0, -5.0)
        XCTAssertTrue(e.volley.serveQueued)
        advance(e, steps: 24, dt: 0.01)
        XCTAssertEqual(e.phase, .rally)
        untilPoint(e)
        XCTAssertEqual(e.ball.p.x, 2.0, accuracy: 0.08)
        XCTAssertEqual(e.ball.p.y, -5.0, accuracy: 0.08)
    }

    func testProHasTenSecondDeadline() {
        let e = game(.beginner, .pro)
        e.countdown = 0.0
        advance(e, steps: 1210, dt: 1.0 / 120)
        XCTAssertEqual(e.scores[1], 1)
        XCTAssertEqual(e.reason, "serve_timeout")
    }

    func testProTossRequiresSwipe() {
        let e = game(.pro)
        e.countdown = 0.0
        e.command("you", "tap", "volley_tap", 0.0, -5.0)
        XCTAssertTrue(e.volley.toss)
        XCTAssertEqual(e.phase, .ready)
        advance(e, steps: 35, dt: 0.01)
        e.command("you", "swipe", "volley_up", 0.0, -1.0, 0.5)
        advance(e, steps: 24, dt: 0.01)
        XCTAssertEqual(e.phase, .rally)
    }

    func testServeControlIndependentFromRally() {
        XCTAssertEqual(game(.beginner, .pro).volley.serveMode, .pro)
        XCTAssertEqual(game(.standard, .beginner).effectiveControl, .standard)
    }

    func testNearNetTapJumpsAndBlocks() {
        let e = game()
        incoming(e, z: 2.5)
        let p = e.players[0]
        p.p = Vec(0.0, 0.6)
        p.goal = p.p
        e.command("you", "block", "volley_block", 0.0, 0.0)
        XCTAssertEqual(p.pose, "block")
        XCTAssertTrue(p.jumpV > 5)
        XCTAssertEqual(p.contacts, 0)
    }

    func testBlockerCannotTeleportFromBaseline() {
        let e = game()
        incoming(e)
        e.command("you", "block", "volley_block", 0.0, 0.0)
        XCTAssertEqual(e.players[0].jumpV, 0.0, accuracy: 0.001)
    }

    func testDiveIsLessReliableThanNormalContact() {
        func successes(_ distance: Double) -> Int {
            return (1...100).filter { seed in
                let e = game(seed: seed)
                incoming(e, z: 1.0, distance: distance)
                e.command("you", "a", "volley_tap", 0.0, -4.0)
                return e.players[0].contacts > 0
            }.count
        }
        XCTAssertEqual(successes(0.7), 100)
        XCTAssertTrue((45...80).contains(successes(1.65)))
    }

    func testSixPlayersCompleteAcrossSeeds() {
        // Android `VolleySkills.all.keys.elementAt(it + 4)` in its declaration order.
        let characters = ["mia", "gaya", "flare", "kyra", "minik", "miniko"]
        for seed in 1...12 {
            let roster = (0..<6).map { Participant("p\($0)", characters[$0], $0 / 3, true) }
            let e = SportsEngine(sportsConfig(.volley, teamSize: 3, target: 3, seed: seed), roster)
            advance(e, steps: 36000, dt: 0.01)
            XCTAssertEqual(e.phase, .finished)
            XCTAssertTrue(e.players.reduce(0) { $0 + $1.contacts } > 5)
        }
    }

    func testTutorialsNeverFinishOrAwardRanks() {
        let base = game()
        var c = base.config
        c.tutorial = true
        let e = SportsEngine(c, base.roster)
        e.phase = .rally
        e.scores[0] = 100
        e.point(0, "test")
        XCTAssertNotEqual(e.phase, .finished)
        XCTAssertEqual(e.earned("you"), 0)
    }

    func testJumpServeHasPreparationAirborneContactAndSingleRelease() {
        let e = game(.beginner)
        e.countdown = 0.0
        XCTAssertTrue(e.command("you", "serve1", "volley_tap", 1.0, -5.0))
        XCTAssertEqual(e.players[0].pose, "serve_prepare")
        XCTAssertEqual(e.players[0].contacts, 0)
        XCTAssertFalse(e.command("you", "serve2", "volley_tap", -3.0, -4.0))
        advance(e, steps: 23, dt: 0.01)
        XCTAssertEqual(e.phase, .rally)
        XCTAssertTrue(e.players[0].jump > 0.65)
        XCTAssertTrue(e.ball.z > 3.0)
        XCTAssertEqual(e.players[0].pose, "serve")
        XCTAssertEqual(e.players[0].contacts, 1)
        XCTAssertEqual(e.events.filter { $0.type == "serve_launch" }.count, 1)
        XCTAssertEqual(e.events.filter { $0.type == "swing" }.count, 1)
        advance(e, steps: 70, dt: 0.01)
        XCTAssertEqual(e.events.filter { $0.type == "serve_launch" }.count, 1)
    }

    func testProServeRetainsRequestedPowerAfterWindup() {
        let speeds = [0.15, 0.95].map { power -> Double in
            let e = game(.pro)
            e.countdown = 0.0
            e.command("you", "toss", "volley_tap")
            advance(e, steps: 35, dt: 0.01)
            e.command("you", "swipe", "volley_swipe", 0.0, -1.0, power)
            advance(e, steps: 23, dt: 0.01)
            XCTAssertEqual(e.phase, .rally)
            return e.ball.velocity.length()
        }
        XCTAssertTrue(speeds[1] > speeds[0] * 1.8)
    }

    func testSurfersAreDistinctMidTierAndVolleyballOnly() {
        XCTAssertEqual(VolleySkills.of("kai").values(), [4, 3, 3, 3, 2, 3])
        XCTAssertEqual(VolleySkills.of("skye").values(), [4, 4, 2, 3, 3, 3])
        for id in ["kai", "skye"] {
            XCTAssertTrue(Characters.forSport(.volley).contains { $0.id == id })
            XCTAssertFalse(Characters.forSport(.squash).contains { $0.id == id })
            XCTAssertTrue(VolleySkills.of(id).values().reduce(0, +) < VolleySkills.of("gaya").values().reduce(0, +))
        }
    }
}
