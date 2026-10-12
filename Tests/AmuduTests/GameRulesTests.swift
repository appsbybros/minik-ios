import XCTest
@testable import MinikAmudu

/// Port of Android `core/GameRulesTest.kt`: SPUD letters, the required call, the step allowance, the action timer,
/// idle strikes, return votes, the shared pause and restores.
final class GameRulesTests: XCTestCase {
    private var serial = 0

    private func game(_ rules: RuleSet = .nicknames, steps: Int = 0, required: Bool = false, seconds: Int = 30) throws -> AmuduEngine {
        let members = [Member("a", "minik", "Anna"), Member("b", "kyra", "Ben"), Member("c", "mia", "Cara")]
        return try AmuduEngine(members: members, config: GameConfig(participants: 3, rules: rules, requireCall: required, stepsAfterCall: steps,
                                                                  actionSeconds: seconds))
    }

    @discardableResult
    private func send(_ e: AmuduEngine, _ id: String, _ c: GameCommand) -> Bool {
        serial += 1
        return e.command(id, "test-\(serial)", c)
    }

    private func advance(_ e: AmuduEngine, _ seconds: Double) {
        for _ in 0..<Int(seconds * 100) { e.tick(0.01) }
    }

    private func pickup(_ e: AmuduEngine) {
        guard let a = e.actor("a") else { return XCTFail("a") }
        e.phase = .retrieve
        e.called = "a"
        e.ball = Ball(a.position, 0.23, V(0.0, 0.0), 0.0)
        XCTAssertTrue(send(e, "a", .catchBall))
    }

    private func tag(_ e: AmuduEngine, _ id: String = "b") {
        guard let a = e.actor(id) else { return XCTFail(id) }
        a.position = V(8.0, 10.0)
        a.catchUntil = 0.0
        e.actor("a")?.position = V(3.0, 3.0)
        e.actor("c")?.position = V(13.0, 13.0)
        e.phase = .flight
        e.phaseAt = e.time
        e.thrower = "a"
        e.called = id
        serial += 1
        e.ball = Ball(a.position, 1.0, V(0.0, 1.0), 0.0, flightId: "tag-\(serial)")
        e.tick(0.01)
    }

    func testTenHousePlayersFinishSpudInEveryArenaWithSteps() throws {
        for scene in ArenaScene.allCases {
            let players = AmuduCharacters.all.prefix(10).enumerated().map { i, c in Member("p\(i)", c.id, c.en, bot: true) }
            let e = try AmuduEngine(members: players, config: GameConfig(scene: scene, participants: 10, rules: .spud, requireCall: true,
                                                                         stepsAfterCall: 4), seed: 52)
            for _ in 0..<(120 * 1600) where e.result == nil { e.tick(1.0 / 120) }
            XCTAssertNotNil(e.result, "\(scene) stalled in \(e.phase)")
            XCTAssertEqual(1, e.result?.winners.count)
            XCTAssertEqual(1, e.activeActors.count)
            XCTAssertTrue(e.actors.filter { !$0.active }.allSatisfy { $0.penalties == 4 && $0.spectator == .letters })
        }
    }

    func testDefaultAndOldSavedGamesKeepNicknameRules() throws {
        XCTAssertEqual(.nicknames, try GameConfig().rules)
        var old = AmuduCodec.config(try GameConfig())
        for key in ["rules", "stepsAfterCall", "requireCall", "actionSeconds"] { old.removeValue(forKey: key) }
        let restored = try AmuduCodec.readConfig(old)
        XCTAssertEqual(.nicknames, restored.rules)
        XCTAssertFalse(restored.requireCall)
        XCTAssertEqual(0, restored.stepsAfterCall)
    }

    func testSpudFourthLetterRemovesActorAndCannotReturn() throws {
        let e = try game(.spud)
        e.actor("b")?.penalties = 3
        tag(e)
        XCTAssertEqual(4, e.actor("b")?.penalties)
        XCTAssertEqual(.letters, e.actor("b")?.spectator)
        XCTAssertTrue(e.pendingHuddles.isEmpty)
        XCTAssertFalse(send(e, "b", .requestReturn))
        advance(e, 6.0)
        XCTAssertFalse(send(e, "a", .select(target: "b")))
        XCTAssertFalse(send(e, "b", .move(V(1.0, 0.0))))
    }

    func testLastSpudPlayerWinsExactlyOnce() throws {
        let e = try game(.spud)
        e.actor("c")?.spectator = .letters
        e.actor("b")?.penalties = 3
        tag(e)
        advance(e, 6.0)
        XCTAssertEqual(["a"], e.result?.winners)
        advance(e, 10.0)
        XCTAssertEqual(1, e.events.filter { $0.kind == "finish" }.count)
    }

    func testNicknameThirdPenaltyCreatesHuddleAndKeepsPlayer() throws {
        let e = try game()
        e.actor("b")?.penalties = 2
        tag(e)
        advance(e, 6.0)
        XCTAssertEqual(.huddle, e.phase)
        XCTAssertTrue(e.actor("b")?.active == true)
        XCTAssertTrue(e.propose("a", "Frog"))
        XCTAssertTrue(e.vote("a", "a"))
    }

    func testRequiredCallBlocksThrowButOptionalAllowsIt() throws {
        let e = try game(.spud, required: true)
        pickup(e)
        XCTAssertFalse(send(e, "a", .throwBall(power: 0.5)))
        XCTAssertTrue(send(e, "a", .shout))
        XCTAssertTrue(send(e, "a", .throwBall(power: 0.5)))
        let other = try game()
        pickup(other)
        XCTAssertTrue(send(other, "a", .throwBall(power: 0.5)))
    }

    func testStepsAreDistanceBudgetAndCannotBeRefilled() throws {
        let e = try game(steps: 4, required: true)
        pickup(e)
        let origin = try XCTUnwrap(e.actor("a")).position
        XCTAssertFalse(send(e, "a", .move(V(1.0, 0.0))))
        send(e, "a", .shout)
        XCTAssertEqual(2.0, e.stepRemaining, accuracy: 0.000001)
        XCTAssertTrue(send(e, "a", .move(V(1.0, 0.0))))
        advance(e, 1.0)
        XCTAssertEqual(2.0, (try XCTUnwrap(e.actor("a")).position - origin).length(), accuracy: 0.0001)
        XCTAssertEqual(0.0, e.stepRemaining, accuracy: 0.0001)
        XCTAssertFalse(send(e, "a", .shout))
        XCTAssertFalse(send(e, "a", .move(V(-1.0, 0.0))))
        XCTAssertEqual(0, e.actor("a")?.penalties)
    }

    func testChangingDirectionSpendsRemainingDistance() throws {
        let e = try game(steps: 4)
        pickup(e)
        send(e, "a", .shout)
        send(e, "a", .move(V(1.0, 0.0)))
        advance(e, 0.2)
        let remaining = e.stepRemaining
        send(e, "a", .move(V(-1.0, 0.0)))
        advance(e, 0.2)
        XCTAssertLessThan(e.stepRemaining, remaining)
        XCTAssertLessThan(e.stepRemaining, 0.25)
    }

    func testTimerIsThirtyTotalAndOnlyLastFiveAreCountdown() throws {
        let e = try game()
        e.tick(0.01)
        XCTAssertEqual(30, e.countdownSeconds())
        advance(e, 24.0)
        XCTAssertEqual(6, e.countdownSeconds())
        advance(e, 1.0)
        XCTAssertEqual(5, e.countdownSeconds())
        advance(e, 5.1)
        XCTAssertEqual(1, e.actor("a")?.penalties)
        XCTAssertEqual(.resolve, e.phase)
        advance(e, 1.0)
        XCTAssertEqual(1, e.actor("a")?.penalties)
    }

    func testPickupResetsTimerButAimShoutAndStepsDoNot() throws {
        let e = try game(steps: 4)
        e.phase = .retrieve
        e.called = "a"
        e.ball = Ball(try XCTUnwrap(e.actor("a")).position, 0.23, V(0.0, 0.0), 0.0)
        advance(e, 24.0)
        XCTAssertLessThanOrEqual(e.countdownSeconds(), 7)
        XCTAssertTrue(send(e, "a", .catchBall))
        e.tick(0.01)
        XCTAssertEqual(30, e.countdownSeconds())
        advance(e, 2.0)
        let deadline = e.actionDeadline
        send(e, "a", .aim(V(1.0, 0.0)))
        send(e, "a", .shout)
        send(e, "a", .move(V(1.0, 0.0)))
        advance(e, 1.0)
        XCTAssertEqual(deadline, e.actionDeadline, accuracy: 0.00001)
    }

    func testInactiveHumansStopCountingButDisconnectedParticipantsStillCount() throws {
        let e = try game()
        e.actor("c")?.spectator = .inactive
        e.tick(0.01)
        // b still participates, regardless of network connected state.
        XCTAssertEqual(30, e.countdownSeconds())
        e.actor("b")?.spectator = .inactive
        advance(e, 40.0)
        XCTAssertEqual(-1, e.countdownSeconds())
        XCTAssertEqual(0, e.actor("a")?.penalties)
    }

    func testNoLimitNeverTimesOut() throws {
        let e = try game(seconds: 0)
        advance(e, 100.0)
        XCTAssertEqual(0, e.actor("a")?.penalties)
        XCTAssertEqual(.circle, e.phase)
    }

    func testThreeUnfinishedOpportunitiesRemoveIdleActor() throws {
        let e = try game()
        for _ in 0..<3 {
            e.circle("a")
            advance(e, 30.2)
        }
        XCTAssertEqual(3, e.actor("a")?.idleStrikes)
        XCTAssertEqual(.inactive, e.actor("a")?.spectator)
        XCTAssertFalse(e.pendingHuddles.contains("a"), "No nickname vote for removed actor")
        XCTAssertFalse(send(e, "a", .select(target: "b")))
    }

    func testSuccessfulThrowClearsConsecutiveIdleStreak() throws {
        let e = try game()
        e.actor("a")?.idleStrikes = 2
        send(e, "a", .select(target: "b"))
        XCTAssertTrue(send(e, "a", .toss(power: 0.4, drift: 0.0)))
        XCTAssertEqual(0, e.actor("a")?.idleStrikes)
    }

    private func returnVote(_ e: AmuduEngine) {
        guard let b = e.actor("b") else { return XCTFail("b") }
        b.spectator = .inactive
        b.penalties = 8
        b.suffixes.append("Frog")
        XCTAssertTrue(send(e, "b", .requestReturn))
        e.breakSerial += 1
        e.phase = .resolve
        e.phaseAt = e.time - 6
        e.tick(0.01)
        XCTAssertEqual(.returnVote, e.phase)
    }

    func testReturnVotePausesPhysicsAndOneYesWins() throws {
        let e = try game()
        returnVote(e)
        let before = e.ball.position
        let a = try XCTUnwrap(e.actor("a")).position
        XCTAssertFalse(send(e, "b", .returnVote(serial: e.returnSerial, yes: true)))
        XCTAssertTrue(send(e, "a", .returnVote(serial: e.returnSerial, yes: true)))
        XCTAssertFalse(send(e, "a", .returnVote(serial: e.returnSerial, yes: false)))
        advance(e, 10.0)
        XCTAssertEqual(before, e.ball.position)
        XCTAssertEqual(a, e.actor("a")?.position)
        XCTAssertEqual(.returnVote, e.phase)
        advance(e, 5.2)
        let b = try XCTUnwrap(e.actor("b"))
        XCTAssertTrue(b.active)
        XCTAssertEqual(8, b.penalties)
        XCTAssertEqual("Frog", b.fullName())
        XCTAssertEqual(0, b.returnAttempts)
    }

    func testZeroVotesAndTieFailAndOnlyThreeAttempts() throws {
        let e = try game()
        returnVote(e)
        advance(e, 15.2)
        XCTAssertFalse(try XCTUnwrap(e.actor("b")).active)
        XCTAssertTrue(send(e, "b", .requestReturn))
        e.breakSerial += 1
        e.phase = .resolve
        e.phaseAt = e.time - 6
        e.tick(0.01)
        send(e, "a", .returnVote(serial: e.returnSerial, yes: true))
        send(e, "c", .returnVote(serial: e.returnSerial, yes: false))
        advance(e, 15.2)
        XCTAssertFalse(try XCTUnwrap(e.actor("b")).active)
        XCTAssertTrue(send(e, "b", .requestReturn))
        e.breakSerial += 1
        e.phase = .resolve
        e.phaseAt = e.time - 6
        e.tick(0.01)
        advance(e, 15.2)
        XCTAssertEqual(3, e.actor("b")?.returnAttempts)
        XCTAssertFalse(send(e, "b", .requestReturn))
    }

    func testStaleVoteAndDuplicateCommandCannotChangeScoreOrVote() throws {
        let e = try game()
        returnVote(e)
        XCTAssertFalse(send(e, "a", .returnVote(serial: e.returnSerial - 1, yes: true)))
        XCTAssertTrue(e.command("a", "vote", .returnVote(serial: e.returnSerial, yes: true)))
        XCTAssertFalse(e.command("a", "vote", .returnVote(serial: e.returnSerial, yes: false)))
        XCTAssertEqual(["a": true], e.returnVotes)
    }

    func testOnlyLastActiveHumanCanPauseAndRestoreSharedPause() throws {
        let e = try game()
        XCTAssertFalse(send(e, "a", .pause(value: true)))
        e.actor("b")?.spectator = .inactive
        e.actor("c")?.spectator = .inactive
        XCTAssertFalse(send(e, "b", .pause(value: true)))
        XCTAssertTrue(send(e, "a", .pause(value: true)))
        let restored = try AmuduCodec.create(AmuduCodec.checkpoint(e))
        let time = restored.time
        advance(restored, 30.0)
        XCTAssertEqual(time, restored.time)
        XCTAssertFalse(send(restored, "a", .select(target: "b")))
        XCTAssertTrue(send(restored, "a", .pause(value: false)))
        advance(restored, 0.1)
        XCTAssertGreaterThan(restored.time, time)
    }

    func testSaveAndAuthorityRestoreKeepsVoteAndTimerBudget() throws {
        let e = try game(steps: 3, required: true)
        pickup(e)
        send(e, "a", .shout)
        e.tick(0.01)
        send(e, "a", .move(V(1.0, 0.0)))
        advance(e, 0.1)
        let restored = try AmuduCodec.create(AmuduCodec.checkpoint(e))
        XCTAssertEqual(e.config, restored.config)
        XCTAssertEqual(e.stepRemaining, restored.stepRemaining)
        XCTAssertEqual(e.actionDeadline, restored.actionDeadline)
        returnVote(e)
        send(e, "a", .returnVote(serial: e.returnSerial, yes: true))
        let resumed = try AmuduCodec.create(AmuduCodec.checkpoint(e))
        XCTAssertEqual(e.returnVotes, resumed.returnVotes)
        XCTAssertEqual(e.actor("b")?.returnAttempts, resumed.actor("b")?.returnAttempts)
        advance(resumed, 15.2)
        XCTAssertTrue(resumed.actor("b")?.active == true)
    }
}

/// Ports of Android `core/ProgressRanksTest.kt`, `ConnectionRegressionTest.kt`, `StopCallVoiceTest.kt` and the
/// rectangular-court case of `NetworkStateTest.kt`.
final class RanksVoiceAndCourtTests: XCTestCase {
    func testSamePaletteAndBoundaries() {
        XCTAssertEqual([0, 100, 250, 500, 1000, 1800, 3000, 5000, 8000, 12000, 18000], ProgressRanks.all.map { $0.threshold })
        for r in ProgressRanks.all {
            XCTAssertEqual(r, ProgressRanks.at(r.threshold))
            if r.threshold > 0 { XCTAssertNotEqual(r, ProgressRanks.at(r.threshold - 1)) }
        }
    }

    func testReceiptDoesNotAwardTwice() {
        let l = RewardLedger()
        XCTAssertEqual(5, l.record("match/p0", 5))
        XCTAssertEqual(0, l.record("match/p0", 5))
        XCTAssertEqual(10, l.record("match/p0", 15))
        XCTAssertEqual(15, l.points)
    }

    func testCatchIsPositiveProgress() throws {
        let e = try AmuduEngine(members: [Member("p0", "miniko", "Player"), Member("b", "minik", "Minik", bot: true)])
        e.emit("catch", "p0")
        XCTAssertEqual(5, e.actor("p0")?.rankEarned)
    }

    func testEmptySnapshotsCannotResetBall() {
        XCTAssertFalse(SnapshotGuard.playable([:]))
        XCTAssertFalse(SnapshotGuard.playable(["time": 8.0]))
    }

    func testCompleteSnapshotsRemainUsable() throws {
        let e = try AmuduEngine(members: [Member("a", "mia", "Player"), Member("b", "minik", "Minik", bot: true)], config: GameConfig(participants: 2))
        XCTAssertTrue(SnapshotGuard.playable(AmuduCodec.shared(e)))
    }

    func testEveryPenaltyWordHasFourVisibleLetters() {
        for l in ["en", "he", "es", "ar", "hi", "nl"] {
            let w = RuleText.penaltyWord(l)
            XCTAssertEqual(4, w.unicodeScalars.count, l)
            XCTAssertTrue(w.unicodeScalars.allSatisfy { Words.isLetter($0) }, l)
        }
    }

    func testBothMinikAvatarsUseFunnyRecording() {
        for id in ["minik", "miniko"] { XCTAssertEqual(StopCallVoice.funny, StopCallVoice.forCaller("he", id)) }
    }

    func testEveryOtherCharacterUsesRegularRecording() {
        for character in AmuduCharacters.all where character.id != "minik" && character.id != "miniko" {
            XCTAssertEqual(StopCallVoice.regular, StopCallVoice.forCaller("he", character.id), character.id)
        }
    }

    func testOtherLanguagesKeepTheirExistingSpokenCall() {
        for language in ["en", "es", "ar", "hi", "nl", "en-US", "es-ES"] {
            for id in ["minik", "miniko", "gaya"] { XCTAssertNil(StopCallVoice.forCaller(language, id)) }
        }
    }

    func testHebrewLocaleVariantsAndUnknownAvatarAreSafe() {
        for language in ["he", "he-IL", "iw", "iw_IL", "HE"] {
            XCTAssertEqual(StopCallVoice.regular, StopCallVoice.forCaller(language, nil), language)
        }
    }

    func testRectangularCourtIsSharedAndOldSavesKeepTheirOriginalBoundaries() throws {
        let members = (0...5).map { Member("p\($0)", AmuduCharacters.all[$0].id, "Player \($0)", bot: $0 > 1) }
        let c = try GameConfig(participants: 6, width: 28.0, depth: 18.0, stepLengthFraction: 0.5 / 18.0)
        let e = try AmuduEngine(members: members, config: c, seed: 123)
        e.actor("p0")?.position = V(25.0, 15.0)
        let restored = try AmuduCodec.create(AmuduCodec.checkpoint(e))
        XCTAssertEqual(c, restored.config)
        XCTAssertEqual(e.actor("p0")?.position, restored.actor("p0")?.position)
        var legacy = AmuduCodec.config(c)
        for key in ["width", "depth", "stepLengthFraction"] { legacy.removeValue(forKey: key) }
        XCTAssertEqual(16.0, try AmuduCodec.readConfig(legacy).width)
        XCTAssertEqual(16.0, try AmuduCodec.readConfig(legacy).depth)
        XCTAssertEqual(2.0, 4 * min(c.width, c.depth) * c.stepLengthFraction, accuracy: 0.0001)
    }
}
