import XCTest
@testable import MinikSquash

/// Android core/SportsEngineTest.kt, PlayerContactTest.kt and SportsReceptionTest.kt.
final class SportsEngineTests: XCTestCase {
    private func game(_ s: Sport, _ n: Int = 2, seed: Int = 3) -> SportsEngine {
        let size = s == .squash ? 2 : n * 2
        return SportsEngine(sportsConfig(s, teamSize: n, target: 5, seed: seed),
                            (0..<size).map { i in Participant("p\(i)", Characters.all[i].id, i < size / 2 ? 0 : 1, true) })
    }

    func testQuestionsAlwaysHaveFourDistinctAnswers() {
        for skill in Skill.allCases {
            for level in 0...5 {
                for seed in 0...80 {
                    let q = QuestionBank.generate("q", skill, level, KotlinRandom(seed: Int64(seed)))
                    XCTAssertEqual(Set(q.options).count, 4)
                    XCTAssertEqual(q.options.filter { $0 == q.answer }.count, 1)
                }
            }
        }
    }

    func testDuplicateCommandCannotHitTwice() {
        let e = game(.squash)
        XCTAssertTrue(e.command("p0", "once", "move", 1.0, 2.0))
        XCTAssertFalse(e.command("p0", "once", "move", -2.0, 1.0))
        XCTAssertEqual(Vec(1.0, 2.0), e.players[0].goal)
    }

    func testUnknownAndNonFiniteInputsAreRejected() {
        let e = game(.squash)
        XCTAssertFalse(e.command("outsider", "x", "hit"))
        XCTAssertFalse(e.command("p0", "x", "move", Double.nan))
        XCTAssertFalse(e.command("p0", "x", "move", Double.infinity))
    }

    func testCompleteSquashMatches() {
        for seed in 0...14 {
            let e = game(.squash, seed: seed)
            advance(e, steps: 120 * 360, dt: 1.0 / 120)
            XCTAssertEqual(e.phase, .finished, "seed \(seed) scores \(e.scores)")
            XCTAssertTrue(e.players.reduce(0) { $0 + $1.contacts } > 3)
        }
    }

    func testBothVolleyballTeamSizesComplete() {
        for n in 2...3 {
            for seed in 0...8 {
                let e = game(.volley, n, seed: seed)
                advance(e, steps: 120 * 480, dt: 1.0 / 120)
                XCTAssertEqual(e.phase, .finished, "\(n) seed \(seed) scores \(e.scores)")
                XCTAssertTrue(e.players.reduce(0) { $0 + $1.contacts } > 4)
            }
        }
    }

    func testVolleyballStaysInOwnHalf() {
        let e = game(.volley, 3)
        for _ in 0..<8000 {
            e.update(0.016)
            for p in e.players { XCTAssertTrue(p.member.team == 0 ? p.p.y >= 0.48 : p.p.y <= -0.48) }
        }
    }

    func testTargetCannotScoreTwiceForOneShot() {
        let e = game(.squash)
        e.phase = .rally
        e.countdown = 0.0
        e.ball.active = true
        let p = e.players[0]
        let choice = e.question.options.firstIndex(of: e.question.answer) ?? -1
        e.launchSquash(p, choice)
        advance(e, steps: 105, dt: 1.0 / 120)
        XCTAssertTrue(e.scores[0] <= 1)
        XCTAssertTrue(p.correct <= 1)
    }

    func testPausedGameDoesNotAdvance() {
        let e = game(.squash)
        e.paused = true
        advance(e, steps: 200, dt: 0.016)
        XCTAssertEqual(e.clock, 0.0, accuracy: 0.0001)
    }

    func testTutorialDoesNotEndOrAwardRank() {
        let e = SportsEngine(sportsConfig(tutorial: true), [Participant("p0", "minik", 0, true), Participant("p1", "mia", 1, true)])
        advance(e, steps: 20000, dt: 0.016)
        XCTAssertNotEqual(e.phase, .finished)
        XCTAssertEqual(e.earned("p0"), 0)
    }

    func testRanksAndReceiptsAreMonotonic() {
        let l = RewardLedger()
        XCTAssertEqual(l.record("m", 40), 40)
        XCTAssertEqual(l.record("m", 40), 0)
        XCTAssertEqual(l.record("m", 3), 0)
        XCTAssertEqual(l.record("m", 50), 10)
        XCTAssertEqual(l.points, 50)
        var prior = 0
        for p in 0...20000 {
            let r = ProgressRanks.at(p)
            XCTAssertTrue(r.threshold >= prior)
            prior = r.threshold
        }
        XCTAssertEqual(ProgressRanks.at(18000).en, "Gold")
    }

    func testDeterministicPhysics() {
        for s in Sport.allCases {
            let a = game(s)
            let b = game(s)
            for _ in 0..<8000 {
                a.update(0.016)
                b.update(0.016)
            }
            XCTAssertEqual(a.scores, b.scores)
            XCTAssertEqual(a.ball.p, b.ball.p)
        }
    }

    func testBeginnerAssistsButStandardAndProRequireContactIntent() {
        for c in Control.allCases {
            let e = SportsEngine(sportsConfig(control: c), [Participant("p0", "minik", 0, false), Participant("p1", "mia", 1, false)])
            e.phase = .rally
            e.countdown = 0.0
            e.expected = 0
            e.ball.active = true
            e.ball.front = true
            e.ball.p = e.players[0].p
            e.ball.z = 1.0
            e.ball.hitter = "p1"
            e.update(0.02)
            XCTAssertFalse(e.players[0].contacts > 0, c.name)
        }
    }

    func testTutorialActuallyChangesControlModel() {
        let e = SportsEngine(sportsConfig(tutorial: true), [Participant("a", "minik", 0, false), Participant("b", "mia", 1, true)])
        e.tutorialStage = 0
        XCTAssertEqual(e.effectiveControl, .beginner)
        e.tutorialStage = 3
        XCTAssertEqual(e.effectiveControl, .standard)
        e.tutorialStage = 4
        XCTAssertEqual(e.effectiveControl, .pro)
    }

    func testSquashFaultsAndScoringUsePhysicalWallIntersection() {
        for z in [0.2, 4.8] {
            let e = game(.squash)
            e.phase = .rally
            e.ball.active = true
            e.ball.hitter = "p0"
            e.ball.p = Vec(0.0, -4.87)
            e.ball.z = z
            e.ball.velocity = Vec(0.0, -4.0)
            e.update(0.02)
            XCTAssertEqual(e.scores[1], 1)
            XCTAssertEqual(e.reason, z < 1 ? "tin" : "out")
        }
        let e = game(.squash)
        e.phase = .rally
        e.ball.active = true
        e.ball.hitter = "p0"
        e.ball.front = true
        e.ball.bounces = 1
        e.ball.p = Vec(0.0, 3.5)
        e.ball.z = 0.01
        e.ball.vz = -1.0
        e.update(0.02)
        XCTAssertEqual(e.reason, "two_bounces")
        XCTAssertEqual(e.scores[0], 1)
    }

    func testCorrectCircleRecordsLearningOnceAndKeepsItsExplanation() throws {
        let e = game(.squash)
        e.phase = .rally
        e.countdown = 0.0
        e.ball.active = true
        let p = e.players[0]
        e.beginServeQuestions()
        let q = try XCTUnwrap(e.answers[p.member.id]).question
        e.launchSquash(p, q.options.firstIndex(of: q.answer) ?? -1)
        advance(e, steps: 90, dt: 1.0 / 120)
        XCTAssertEqual(p.correct, 1)
        XCTAssertTrue(e.feedbackEn.contains(q.answer))
        XCTAssertEqual(e.profiles["p0"]?.state(q.skill).independent, 1)
    }

    func testVolleyballTeamsSetAndAttackWithoutFourContacts() {
        let e = game(.volley, 3, seed: 7)
        var receives = 0
        var sets = 0
        var attacks = 0
        var seen = 0
        for _ in 0..<(120 * 90) {
            e.update(1.0 / 120)
            for v in e.events where v.id > seen {
                switch v.type {
                case "receive": receives += 1
                case "set": sets += 1
                case "attack": attacks += 1
                default: break
                }
                seen = v.id
            }
            XCTAssertTrue(e.ball.touches <= 3)
        }
        XCTAssertTrue(receives > 0 && sets > 0 && attacks > 0, "receives \(receives) sets \(sets) attacks \(attacks)")
    }

    func testVolleyballNetAndOutAwardOpponent() {
        for net in [true, false] {
            let e = game(.volley, 3)
            e.phase = .rally
            e.ball.active = true
            e.ball.hitter = "p0"
            e.ball.p = net ? Vec(0.0, 0.01) : Vec(6.1, 2.0)
            e.ball.z = 1.0
            e.ball.velocity = Vec(0.0, -3.0)
            e.update(0.02)
            XCTAssertEqual(e.scores[1], 1)
            XCTAssertEqual(e.reason, net ? "net" : "out")
        }
    }

    // MARK: PlayerContactTest

    private func contactGame(_ sport: Sport = .squash) -> SportsEngine {
        let n = sport == .squash ? 2 : 4
        return SportsEngine(sportsConfig(sport, questionsEnabled: false),
                            (0..<n).map { i in Participant("p\(i)", Characters.all[i].id, sport == .squash ? i : i / 2, false) })
    }

    func testHeadOnContactStopsClosingVelocityAndNetworkExtrapolationOverlap() {
        let e = contactGame()
        e.countdown = 1000.0
        e.players[0].p = Vec(-0.6, 1.0)
        e.players[1].p = Vec(0.6, 1.0)
        for p in e.players { p.goal = Vec(0.0, 1.0) }
        advance(e, steps: 360, dt: 1.0 / 120)
        let a = e.players[0]
        let b = e.players[1]
        let before = a.p
        XCTAssertEqual((a.p - b.p).length(), 1.05, accuracy: 0.00001)
        XCTAssertTrue(a.velocity.length() < 0.001 && b.velocity.length() < 0.001, "Blocked players must not retain inward motion")
        XCTAssertTrue(((a.p + a.velocity * 0.15) - (b.p + b.velocity * 0.15)).length() >= 1.0499, "Remote prediction must not move bodies through each other")
        for _ in 0..<120 {
            e.update(1.0 / 120)
            XCTAssertTrue((a.p - before).length() < 0.0001, "No sustained contact jitter")
        }
    }

    func testExactCoincidenceResolvesWithoutNaNOrPassingThrough() {
        let e = contactGame()
        e.countdown = 1000.0
        for p in e.players {
            p.p = Vec(0.0, 1.0)
            p.goal = p.p
        }
        e.update(1.0 / 120)
        XCTAssertTrue((e.players[0].p - e.players[1].p).length() >= 1.0499)
    }

    func testPressureAgainstWallKeepsBothBodiesInBoundsAndAtRest() {
        let e = contactGame()
        e.countdown = 1000.0
        e.players[0].p = Vec(2.92, 1.0)
        e.players[1].p = Vec(2.0, 1.0)
        for p in e.players { p.goal = Vec(2.92, 1.0) }
        advance(e, steps: 500, dt: 1.0 / 120)
        XCTAssertTrue(e.players.allSatisfy { $0.p.x <= 2.92 && $0.velocity.length() < 0.001 })
        XCTAssertTrue((e.players[0].p - e.players[1].p).length() >= 1.0499)
    }

    func testTeammatesCanSlideAlongContactInsteadOfBecomingGlued() {
        let e = contactGame(.volley)
        e.countdown = 1000.0
        e.players[0].p = Vec(-0.525, 4.0)
        e.players[1].p = Vec(0.525, 4.0)
        e.players[0].goal = Vec(0.0, 6.0)
        e.players[1].goal = Vec(0.0, 6.0)
        advance(e, steps: 90, dt: 1.0 / 120)
        XCTAssertTrue(e.players.prefix(2).allSatisfy { $0.p.y > 4.5 })
        XCTAssertTrue((e.players[0].p - e.players[1].p).length() >= 1.049)
    }

    // MARK: SportsReceptionTest

    private func match(receiverBot: Bool = false) -> SportsEngine {
        let e = SportsEngine(sportsConfig(.squash, control: .pro, questionsEnabled: false),
                             [Participant("a", "minik", 0, false), Participant("b", "kyra", 1, receiverBot)])
        e.phase = .rally
        e.expected = 1
        e.countdown = 0.0
        e.players[0].p = Vec(-2.0, -2.0)
        e.players[0].goal = e.players[0].p
        e.players[1].p = Vec(0.0, 2.0)
        e.players[1].goal = e.players[1].p
        e.ball.p = Vec(0.0, 0.0)
        e.ball.z = 1.3
        e.ball.vz = 2.0
        e.ball.velocity = Vec(0.0, 4.0)
        e.ball.front = true
        e.ball.active = true
        e.ball.hitter = "a"
        return e
    }

    func testReceiverMustBeHumanAndInTheIncomingCorridor() {
        let e = match()
        XCTAssertEqual(SportsReception.incoming(e)?.id, "b")
        e.ball.velocity = Vec(0.0, -4.0)
        XCTAssertNil(SportsReception.incoming(e))
        XCTAssertNil(SportsReception.incoming(match(receiverBot: true)))
    }

    func testOnlyTheReceivingHumansPreferenceControlsSlowMotion() {
        let e = match()
        e.receptionSlowEnabled["a"] = false
        e.update(0.1)
        XCTAssertTrue(e.receptionScale < 1.0)
        let disabled = match()
        disabled.receptionSlowEnabled["b"] = false
        disabled.update(0.1)
        XCTAssertEqual(disabled.receptionScale, 1.0, accuracy: 1e-12)
    }

    func testWorldClockPlayersAndBallShareTheSameScale() {
        let e = match()
        e.players[0].goal = Vec(-1.0, -2.0)
        var elapsed = 0.0
        var shared = 0.0
        for _ in 0..<24 {
            e.update(1.0 / 120)
            elapsed += 1.0 / 120
            shared += e.receptionScale / 120
        }
        XCTAssertEqual(e.clock, shared, accuracy: 1e-9)
        XCTAssertTrue(e.clock < elapsed)
        XCTAssertEqual(e.ball.p.y, 4.0 * shared, accuracy: 1e-7)
        XCTAssertTrue(e.players[0].p.x > -2.0)
    }

    func testTimeReturnsSmoothlyAfterTheRally() {
        let e = match()
        advance(e, steps: 18, dt: 1.0 / 120)
        let low = e.receptionScale
        XCTAssertTrue(low < 0.99)
        e.ball.active = false
        e.phase = .point
        e.update(1.0 / 120)
        XCTAssertTrue(e.receptionScale > low)
        XCTAssertTrue(e.receptionScale < 1.0)
        advance(e, steps: 300, dt: 1.0 / 120)
        XCTAssertTrue(e.receptionScale > 0.99)
    }

    func testPausedMatchDoesNotAdvance() {
        let e = match()
        e.paused = true
        e.update(0.1)
        XCTAssertEqual(e.clock, 0.0)
    }
}
