import XCTest
@testable import MinikMultiPingPong

// Multi Ping Pong iOS stage 3 (2026-11-09): playing, from Android MinikCrossPong 5375378, af84f72, ab089c5, fcfd6b2, c93e760,
// 6fcb446, d0bed3b and 971e958 (at dd94c09). Kotlin SingleTapAndLooseBallTest, FarEndCoastTest, ClassicAimingRegressionTest,
// CrossSingleTapTest, CrossAimingRegressionTest, TutorialTapAndRestTest (all but its navigation test, stage 5),
// TeamLearningRegressionTest and CrossPracticeTest.aimingWaitsForDeliberateChoiceAndResumesAfterRestore, plus the checkpoint
// rules of the loose ball between phones. Kotlin seeds `kotlin.random.Random(seed)` for the classic engine; MPEngine draws from
// its own MPRandom(seed:), so those games are other seeded games checked by the same rules.
final class MultiStageThreeTests: XCTestCase {
    private let starter = MPTuning.values(.easy)

    // ---- Kotlin LooseBall (SingleTapAndLooseBallTest, FarEndCoastTest) ----

    // Kotlin: looseBallFallsBouncesAndSettlesOnFloor
    func testLooseBallFallsBouncesAndSettlesOnFloor() {
        let b = MPLooseBall(MPPoint(1.02, 0.8), 0.2, MPPoint(0.4, 0.2), 0.1, floor: -2.03)
        var fell = false, rebounded = false, old = b.height
        for _ in 0..<3000 {
            b.advance(1.0 / 120, starter)
            if b.height < -0.5 { fell = true }
            if fell && b.height > old { rebounded = true }
            old = b.height
        }
        XCTAssertTrue(fell); XCTAssertTrue(rebounded); XCTAssertTrue(b.settled)
        XCTAssertEqual(-2.03, b.height, accuracy: 0.001)
    }
    // Kotlin: farMissStopsDriftingAfterFourTenthsButStillFalls
    func testFarMissStopsDriftingAfterFourTenthsButStillFalls() {
        for speed in [0.2, 0.8, 2.0, 7.9] {
            let b = MPLooseBall(MPPoint(0.1, -0.001), 0.1, MPPoint(-speed * 0.1, -speed), -0.2, floor: -2.03, farEnd: 0)
            let start = b.position
            for _ in 0..<48 { b.advance(1.0 / 120, starter); XCTAssertGreaterThanOrEqual(b.position.y, -0.20) }
            let stopped = b.position, height = b.height
            XCTAssertGreaterThan(start.distance(stopped), 0.01)
            for _ in 0..<60 { b.advance(1.0 / 120, starter); XCTAssertEqual(stopped, b.position) }
            XCTAssertLessThan(b.height, height)
        }
    }
    // Kotlin: nearMissAndNetReboundKeepTheirExistingMotion
    func testNearMissAndNetReboundKeepTheirExistingMotion() {
        for start in [MPPoint(0.8, 1.01), MPPoint(0.8, 0.501)] {
            let before = MPLooseBall(start, 0.08, MPPoint(0.1, 0.4), -0.1, floor: -2.03)
            let after = MPLooseBall(start, 0.08, MPPoint(0.1, 0.4), -0.1, floor: -2.03, farEnd: 0)
            for _ in 0..<180 {
                before.advance(1.0 / 120, starter); after.advance(1.0 / 120, starter)
                XCTAssertEqual(before.position, after.position); XCTAssertEqual(before.height, after.height)
            }
        }
    }

    // ---- Kotlin SingleTapAndLooseBallTest: the classic engine ----

    /// Kotlin `incoming`: Starter (iOS `.easy`) until Minik's live ball reaches depth 0.67 on its way to the child.
    private func incoming(seed: UInt64 = 21) -> MPEngine {
        let e = MPEngine(level: .easy, target: 7, seed: seed)
        for _ in 0..<6000 {
            if let f = e.flight, !f.resolved, f.striker == .minik, f.position.y >= 0.67 { return e }
            e.advance(1.0 / 120)
        }
        XCTFail("No incoming ball")
        return e
    }
    private static func childContacts(_ events: [MPEvent]) -> Int {
        events.filter { if case let .contact(side, _, _, _) = $0 { return side == .child }; return false }.count
    }
    // Kotlin: earlyTapAndLateTapEachReturnWithoutSecondPress
    func testEarlyTapAndLateTapEachReturnWithoutSecondPress() {
        for depth in [0.67, 0.82, 0.89] {
            let e = incoming()
            while let f = e.flight, f.position.y < depth, !f.resolved { e.advance(1.0 / 120) }
            guard let f = e.flight, !f.resolved else { XCTFail("ball decided before \(depth)"); continue }
            _ = e.drainEvents(); e.touch(MPPoint(f.position.x, 0.84)); e.endTouch()
            var events: [MPEvent] = []
            for _ in 0..<80 { e.advance(1.0 / 120); events += e.drainEvents() }
            XCTAssertEqual(1, MultiStageThreeTests.childContacts(events), "one return at \(depth)")
        }
    }
    // Kotlin: noTapOrCancelledTapNeverHitsInStandard
    func testNoTapOrCancelledTapNeverHitsInStandard() {
        for cancel in [false, true] {
            let e = incoming()
            if cancel { e.touch(MPPoint(e.ball.x, 0.84)); e.endTouch(cancelled: true) }
            _ = e.drainEvents()
            var events: [MPEvent] = []
            for _ in 0..<160 { e.advance(1.0 / 120); events += e.drainEvents() }
            XCTAssertEqual(0, MultiStageThreeTests.childContacts(events))
        }
    }
    // Kotlin: decidedBallContinuesWithoutAwardingMorePoints
    func testDecidedBallContinuesWithoutAwardingMorePoints() {
        let e = incoming()
        for _ in 0..<1200 where e.lastResolution == nil { e.advance(1.0 / 120) }
        XCTAssertNotNil(e.lastResolution)
        XCTAssertTrue(e.postPointBall)
        let point = e.renderedBall, height = e.renderHeight, score = e.score
        for _ in 0..<60 { e.advance(1.0 / 120) }
        XCTAssertTrue(point.distance(e.renderedBall) > 0.01 || abs(height - e.renderHeight) > 0.01)
        XCTAssertEqual(score, e.score)
    }
    // Kotlin: repeatedFinishedSnapshotsDoNotShiftTheCoastingBall (classic)
    func testClassicRepeatedFinishedSnapshotsDoNotShiftTheCoastingBall() {
        let e = incoming()
        for _ in 0..<1200 where e.lastResolution == nil { e.advance(1.0 / 120) }
        let remote = e.snapshot()
        for _ in 0..<3 {
            for _ in 0..<12 { e.advance(1.0 / 120) }
            let at = e.renderedBall
            e.restore(remote, preserveInput: true)
            XCTAssertEqual(0, at.distance(e.renderedBall), accuracy: 1e-8)
        }
    }
    /// A flight with the given state (Kotlin `FlightState(position, height, velocity, verticalVelocity, striker, receiverMayReturn,
    /// resolved, 0.0, null)`).
    private func flight(_ position: MPPoint, _ height: Double, _ velocity: MPPoint, _ lift: Double, _ striker: MPSide, receiver: Bool, resolved: Bool) -> MPFlight {
        var f = MPFlight(MPServe(server: .child, start: MPPoint(0.5, 0.87), first: MPPoint(0.5, 0.75), second: MPPoint(0.5, 0.25), speed: 0.4, arc: 0.1), starter)
        f.position = position; f.height = height; f.velocity = velocity; f.lift = lift; f.striker = striker
        f.receiver = receiver; f.resolved = resolved; f.spin = 0; f.serve = nil
        return f
    }
    // Kotlin: engineUsesFarStopWithoutRestartingItOnRepeatedFinishedSnapshots
    func testEngineUsesFarStopWithoutRestartingItOnRepeatedFinishedSnapshots() {
        let e = MPEngine(level: .easy, target: 7, seed: 5)
        let base = e.snapshot()
        var ended = base
        ended.flight = flight(MPPoint(0.12, -0.005), 0.1, MPPoint(-0.08, -1.2), -0.2, .child, receiver: true, resolved: true)
        ended.rally = 1; ended.pointDelay = 3.2; ended.serveDelay = nil; ended.status = "BALL_IN"
        e.restore(ended)
        for _ in 0..<60 { e.advance(1.0 / 120) }
        let stopped = e.renderedBall
        for _ in 0..<3 {
            e.restore(ended, preserveInput: true)
            for _ in 0..<20 { e.advance(1.0 / 120) }
            XCTAssertEqual(0, stopped.distance(e.renderedBall), accuracy: 1e-8)
        }
        XCTAssertGreaterThanOrEqual(stopped.y, -0.20)
        XCTAssertEqual(base.score, e.score)
    }

    // ---- Kotlin ClassicAimingRegressionTest (fcfd6b2) ----

    // Kotlin: standardAimingDoesNotBecomeFootwork (Difficulty EASY and STARTER: iOS `.medium` and `.easy`)
    func testClassicStandardAimingDoesNotBecomeFootwork() {
        for level in [MPLevel.medium, .easy] {
            for sign in [-1.0, 1.0] {
                let e = MPEngine(level: level, target: 11, networked: true)
                var state = e.snapshot()
                state.flight = flight(MPPoint(0.5, 0.80), 0.10, MPPoint(0, 0.45), 0.25, .minik, receiver: true, resolved: false)
                state.rally = 1; state.status = "RETURN_BALL"
                e.restore(state)
                let start = e.restingPaddle
                XCTAssertTrue(e.aimReturn(sign * 0.05, movement: MPPoint(sign * 0.3, -0.1), start: true))
                XCTAssertEqual(start, e.restingPaddle)
                e.aimReturn(sign * 0.07, movement: MPPoint(sign * 0.3, -0.1), start: false); e.endTouch()
                for _ in 0..<100 where e.flight?.striker != .child { e.advance(1.0 / 120) }
                XCTAssertEqual(.child, e.flight?.striker, "\(level) \(sign)")
                XCTAssertGreaterThan((e.flight?.velocity.x ?? 0) * sign, 0, "\(level) \(sign)")
            }
        }
    }
    // Kotlin: movementWhileBallIsAwayNeverSwings
    func testClassicMovementWhileBallIsAwayNeverSwings() {
        let e = MPEngine(level: .easy, target: 11, networked: true)
        var state = e.snapshot()
        state.flight = flight(MPPoint(0.5, 0.3), 0.10, MPPoint(0, -0.45), 0.25, .child, receiver: true, resolved: false)
        state.rally = 1; state.status = "GOOD_RETURN"
        e.restore(state)
        e.moveOnly(MPPoint(0.2, 0.86)); e.moveOnly(MPPoint(0.7, 0.86))
        XCTAssertFalse(e.aimReturn(0.1, movement: MPPoint(0.3, 0), start: true))
        XCTAssertEqual(0.7, e.restingPaddle.x, accuracy: 1e-9)
        XCTAssertFalse(e.childStroke.active)
    }

    // ---- Kotlin CrossSingleTapTest (5375378, af84f72) ----

    private func standardTable() -> CrossEngine { CrossEngine(seats: localTable("minik", "kyra", "flare"), control: .standard, target: 7, seed: 21) }
    // Kotlin: oneTapReturnsLateWithoutAnimationDelay
    func testOneTapReturnsLateWithoutAnimationDelay() {
        let e = standardTable()
        e.incoming(from: 2, to: 0, v: 0.84)
        e.touch(e.ballPosition); e.endTouch()
        let events = e.drainEvents() + e.play(0.5)
        XCTAssertEqual(1, events.contacts(0).count)
    }
    // Kotlin: earlyTapSurvivesWindupAndCancellationStillCancels
    func testEarlyTapSurvivesWindupAndCancellationStillCancels() {
        for cancel in [false, true] {
            let e = standardTable()
            e.approaching(from: 2, to: 0, v: 0.8)
            e.play(3.0) { e.geometry.toLocal(0, e.ballPosition).v >= 0.67 }
            e.touch(e.geometry.fromLocal(0, 0, 0.84)); e.endTouch(cancelled: cancel)
            let events = e.drainEvents() + e.play(0.7)
            XCTAssertEqual(cancel ? 0 : 1, events.contacts(0).count)
        }
    }
    // Kotlin: crossDeadBallContinuesAndScoreDoesNotChange
    func testCrossDeadBallContinuesAndScoreDoesNotChange() {
        let e = standardTable()
        e.incoming(from: 2, to: 0, v: 0.84); e.play(3.0) { e.pointDelay != nil }
        XCTAssertNotNil(e.pointDelay); XCTAssertTrue(e.postPointBall)
        let at = e.renderBallPosition, h = e.renderHeight, score = e.referee.scores
        e.play(0.6)
        XCTAssertTrue(at.distance(e.renderBallPosition) > 0.01 || abs(h - e.renderHeight) > 0.01)
        XCTAssertEqual(score, e.referee.scores)
    }
    // Kotlin: repeatedFinishedSnapshotsDoNotShiftTheCoastingBall (cross)
    func testCrossRepeatedFinishedSnapshotsDoNotShiftTheCoastingBall() throws {
        let e = standardTable()
        e.incoming(from: 2, to: 0, v: 0.84); e.play(3.0) { e.pointDelay != nil }
        let remote = e.exportState()
        for _ in 0..<3 {
            e.play(0.1)
            let at = e.renderBallPosition
            try e.restoreState(remote, preserveInput: true)
            XCTAssertEqual(0, at.distance(e.renderBallPosition), accuracy: 1e-8)
        }
    }
    /// The decided ball crosses the network as Android writes it: a checkpoint keeps the ball state in which the point was
    /// decided (no extra field), and a phone that reads it builds the same loose ball as the phone that decided it.
    func testDecidedBallCheckpointRebuildsTheSameLooseBallOnAnotherPhone() throws {
        let e = standardTable()
        e.incoming(from: 2, to: 0, v: 0.84); e.play(3.0) { e.pointDelay != nil }
        let decided = e.ballState
        e.play(0.4)
        XCTAssertEqual(decided, e.ballState, "the simulated ball stays where the point was decided")
        let state = try CrossState.read(e.exportState().wire())
        XCTAssertEqual(decided, state.ball)
        let peer = standardTable()
        try peer.restoreState(state)
        XCTAssertTrue(peer.postPointBall)
        // Both continue the same deterministic loose ball; the peer's starts 0.4 s behind, so its correction blends away first.
        let fresh = standardTable()
        try fresh.restoreState(state)
        let replay = standardTable()
        try replay.restoreState(state)
        fresh.play(0.5); replay.play(0.5)
        XCTAssertEqual(fresh.renderBallPosition, replay.renderBallPosition)
        XCTAssertEqual(fresh.renderHeight, replay.renderHeight)
        // The classic checkpoint, through its JSON wire form.
        let c = incoming()
        for _ in 0..<1200 where c.lastResolution == nil { c.advance(1.0 / 120) }
        let flightAtPoint = c.flight
        for _ in 0..<30 { c.advance(1.0 / 120) }
        XCTAssertEqual(flightAtPoint, c.flight)
        let data = try JSONEncoder().encode(c.snapshot())
        let read = try JSONDecoder().decode(MPState.self, from: data)
        let a = MPEngine(level: .easy, target: 7, seed: 3), b = MPEngine(level: .easy, target: 7, seed: 4)
        a.restore(read); b.restore(read)
        XCTAssertTrue(a.postPointBall)
        for _ in 0..<60 { a.advance(1.0 / 120); b.advance(1.0 / 120) }
        XCTAssertEqual(a.renderedBall, b.renderedBall); XCTAssertEqual(a.renderHeight, b.renderHeight)
    }
    /// Android 5375378 `ballVisible`: no ball is drawn while a serve is awaited, until the server's swing starts.
    func testNoBallIsShownBeforeTheServeSwing() {
        let e = CrossEngine(seats: localTable("minik", "kyra"), control: .standard, target: 7, seed: 3)
        XCTAssertEqual(.awaitingServe, e.referee.phase)
        XCTAssertEqual(0, e.referee.server)
        XCTAssertFalse(e.ballVisible)
        e.touch(e.geometry.fromLocal(1, 0, 0.85)); e.endTouch()
        XCTAssertTrue(e.ballVisible)
        let classic = MPEngine(level: .easy, target: 7, seed: 3)
        XCTAssertNil(classic.flight); XCTAssertFalse(classic.ballVisible)
    }

    // ---- Kotlin CrossAimingRegressionTest (fcfd6b2) ----

    private func kyraTable(_ n: Int, _ control: CrossControl) -> CrossEngine {
        CrossEngine(seats: [humanSeat(0)] + (1..<n).map { houseSeat($0, "kyra") }, control: control, target: 11, seed: 91)
    }
    // Kotlin: footworkOnOppositeFlightHasNoSwingOrContact
    func testFootworkOnOppositeFlightHasNoSwingOrContact() {
        for n in 2...4 {
            for c in [CrossControl.starter, .standard] {
                let e = kyraTable(n, c)
                e.approaching(from: 0, to: 1)
                for u in [-0.4, 0.3, -0.2] { e.moveOnly(e.geometry.fromLocal(0, u, CrossGeometry.homeDepth)) }
                XCTAssertFalse(e.aimReturn(drag: 70, speed: 0.8, start: true))
                XCTAssertEqual(-0.2, e.geometry.toLocal(0, e.restingPaddle).u, accuracy: 1e-9)
                XCTAssertTrue(e.drainEvents().swings(0).isEmpty); XCTAssertFalse(e.stroke(0).active)
            }
        }
    }
    // Kotlin: aimedReturnKeepsStanceAndUsesChosenSide
    func testAimedReturnKeepsStanceAndUsesChosenSide() {
        for n in 2...4 {
            for c in [CrossControl.starter, .standard] {
                for drag in [-65.0, 65.0] {
                    let e = kyraTable(n, c)
                    e.incoming(from: n == 4 ? 2 : 1, to: 0); e.waitForBall(0, depth: 0.82)
                    let start = e.restingPaddle
                    XCTAssertTrue(e.aimReturn(drag: drag, speed: 0.8, start: true), "\(n)/\(c)")
                    XCTAssertEqual(start, e.restingPaddle)
                    e.aimReturn(drag: drag, speed: 1.0, start: false); e.endTouch()
                    let events = e.play(1.2) { e.referee.striker == 0 }
                    XCTAssertEqual(1, events.contacts(0).count, "\(n)/\(c)/\(drag)")
                    XCTAssertEqual(e.aims.aim(0, dragDp: drag).opponent, e.predictedReceiver)
                    if n == 2, case let .bounce(point, _)? = CrossBall(e.geometry, tuning: e.physics, initial: e.ballState).forecast()?.event {
                        XCTAssertGreaterThan(e.geometry.toView(0, point).x * drag, 0, "Aim sign \(drag): \(point)")
                    } else if n == 2 { XCTFail("no landing bounce") }
                }
            }
        }
    }
    // Kotlin: outOfReachSwipeDoesNotReachForPlayer
    func testOutOfReachSwipeDoesNotReachForPlayer() {
        let e = CrossEngine(seats: localTable("kyra"), control: .standard, target: 11, seed: 9)
        e.incoming(from: 1, to: 0, u: 0.3); e.waitForBall(0, depth: 0.82)
        e.moveOnly(e.geometry.fromLocal(0, -0.5, CrossGeometry.homeDepth))
        let start = e.restingPaddle
        XCTAssertFalse(e.aimReturn(drag: 60, speed: 1, start: true)); XCTAssertEqual(start, e.restingPaddle)
        XCTAssertTrue(e.play(2.0) { e.referee.resolved }.contacts(0).isEmpty)
    }

    // ---- Kotlin TutorialTapAndRestTest (d0bed3b; its navigation test is stage 5) ----

    // Kotlin: tapServesLandOnChosenCourtWithoutMovingRest
    func testTapServesLandOnChosenCourtWithoutMovingRest() {
        for n in 2...4 {
            for c in [CrossControl.beginner, .starter, .standard] {
                for target in 1..<n {
                    let e = CrossEngine(seats: [humanSeat(0)] + (1..<n).map { houseSeat($0, "kyra") }, control: c, target: 11, seed: 91,
                                        exercise: CrossExercise(drill: .serve, expected: target))
                    let rest = e.geometry.fromLocal(0, 0.15, CrossGeometry.homeDepth); e.moveOnly(rest); e.endTouch()
                    e.touch(e.geometry.fromLocal(target, 0.08, 0.85)); e.endTouch()
                    e.play(5.0) { e.trainingResult != nil }
                    XCTAssertEqual(true, e.trainingResult?.success, "\(n)/\(c)/\(target): \(String(describing: e.trainingResult))")
                    XCTAssertEqual(rest, e.restingPaddle)
                }
            }
        }
    }
    // Kotlin: tapReturnsKeepStanceAndReachChosenRecipient
    func testTapReturnsKeepStanceAndReachChosenRecipient() {
        for n in 2...4 {
            for c in [CrossControl.starter, .standard] {
                for target in 1..<n {
                    let e = kyraTable(n, c)
                    e.incoming(from: 1, to: 0); e.waitForBall(0, depth: 0.82); let rest = e.restingPaddle
                    XCTAssertTrue(e.aimReturn(drag: 0, speed: 0, start: true, target: e.geometry.fromLocal(target, 0.08, 0.85))); e.endTouch()
                    let events = e.play(1.2) { e.referee.striker == 0 }
                    XCTAssertEqual(1, events.contacts(0).count, "\(n)/\(c)/\(target)")
                    XCTAssertEqual(rest, e.restingPaddle); XCTAssertEqual(target, e.predictedReceiver)
                    e.play(0.9); XCTAssertEqual(rest, e.restingPaddle)
                }
            }
        }
    }
    // Kotlin: paddleReturnsSmoothlyAndExactlyToRest
    func testPaddleReturnsSmoothlyAndExactlyToRest() {
        var s = MPStroke()
        let contact = MPPoint(0.3, 0.8), rest = MPPoint(0.1, 1.0)
        s.start(1, contact, 0.12, false); s.advance(0.1); s.contact(contact, 0.12)
        XCTAssertEqual(contact, CrossPaddlePose.at(s, rest).point)
        var previous = contact.distance(rest)
        for _ in 0..<55 {
            s.advance(0.01)
            let pose = CrossPaddlePose.at(s, rest)
            XCTAssertLessThanOrEqual(pose.point.distance(rest), previous + 1e-9); previous = pose.point.distance(rest)
            XCTAssertTrue((0...0.12).contains(pose.height))
        }
        let end = CrossPaddlePose.at(s, rest)
        XCTAssertEqual(rest, end.point); XCTAssertEqual(0, end.height)
    }
    // Kotlin: cancelledTapNeverFiresAndSwipeCanChangeItsTarget
    func testCancelledTapNeverFiresAndSwipeCanChangeItsTarget() {
        for cancel in [true, false] {
            let e = CrossEngine(seats: localTable("minik", "kyra", "flare"), control: .standard, target: 11, seed: 91)
            e.incoming(from: 2, to: 0); e.waitForBall(0, depth: 0.82)
            XCTAssertTrue(e.aimReturn(drag: 0, speed: 0, start: true, target: e.geometry.fromLocal(1, 0, 0.85)))
            e.aimReturn(drag: 65, speed: 0.8, start: false); e.endTouch(cancelled: cancel)
            let events = e.play(1.2) { e.referee.striker == 0 }
            XCTAssertEqual(cancel ? 0 : 1, events.contacts(0).count)
            if !cancel { XCTAssertEqual(e.aims.aim(0, dragDp: 65).opponent, e.predictedReceiver) }
        }
    }

    // ---- Kotlin TeamLearningRegressionTest (971e958) ----

    private func game() -> CrossEngine {
        var seats = localTable("flare", "minik", "kyra")
        seats[0].characterId = "miniko"
        return CrossEngine(seats: seats, control: .beginner, target: 7, seed: 15, teams: CrossTeams([0, 1, 0, 1])!, tapTargets: true)
    }
    // Kotlin: alreadyPlacedPlayerCanSetWithoutAnotherMovement
    func testAlreadyPlacedPlayerCanSetWithoutAnotherMovement() {
        let e = game(); e.incoming(from: 1, to: 0)
        e.moveOnly(e.ballPosition) // footwork, no prior touch in this rally
        XCTAssertTrue(e.liftToTeammate()); e.play(0.02)
        XCTAssertEqual(1, e.teamFlight?.sets); XCTAssertEqual(2, e.teamFlight?.setReceiver)
    }
    // Kotlin: secondTapAfterFirstReleaseStillSetsInsteadOfAutomaticReturn
    func testSecondTapAfterFirstReleaseStillSetsInsteadOfAutomaticReturn() {
        for gap in [0.06, 0.16, 0.28] {
            let e = game(); e.incoming(from: 1, to: 0, v: 0.7, pace: 0.65)
            let intercept = e.ballAfter(42)
            e.touch(intercept, down: true)
            e.play(0.08); e.endTouch(); e.play(gap)
            XCTAssertEqual(1, e.referee.hits, "No early automatic hit before second tap \(gap)")
            XCTAssertTrue(e.liftToTeammate())
            e.play(0.9) { e.referee.hits > 1 || e.referee.resolved }
            XCTAssertEqual(1, e.teamFlight?.sets, "A double tap should raise this reachable ball \(gap)")
        }
    }
    // Kotlin: teamAndDailyFootworkReachRightWithoutChangingStrikeBoundary
    func testTeamAndDailyFootworkReachRightWithoutChangingStrikeBoundary() throws {
        let e = game(); e.incoming(from: 1, to: 0)
        XCTAssertEqual(CrossGeometry.strikeHalf + 0.50, e.localFootworkRight, accuracy: 1e-12)
        let at = e.geometry.fromLocal(0, 1.1, 1.1); e.moveOnly(at)
        XCTAssertEqual(at, e.restingPaddle); XCTAssertFalse(e.geometry.inStrikeZone(0, at))
        var state = e.exportState()
        state.team = CrossTeamFlight(members: e.teams!.seats, setReceiver: 0, friendlyHits: 1)
        try e.restoreState(state)
        let left = e.geometry.fromLocal(0, -0.55, 1.1); e.moveOnly(left); e.moveOnly(at)
        XCTAssertEqual(at, e.restingPaddle)
    }
    // Kotlin: raisedPassReachesPartnerForARealSmash
    func testRaisedPassReachesPartnerForARealSmash() {
        let e = game(); e.incoming(from: 1, to: 0); e.moveOnly(e.ballPosition); XCTAssertTrue(e.liftToTeammate()); e.play(0.02)
        var high = 0.0, elapsed = 0.0
        var events: [CrossEvent] = []
        while elapsed < 6 && e.referee.hits < 3 && !e.referee.resolved {
            e.advance(CrossEngine.step); events += e.drainEvents(); high = max(high, e.ballState.height); elapsed += CrossEngine.step
        }
        XCTAssertGreaterThan(high, 0.7, "High pass must visibly rise")
        XCTAssertTrue(events.contains { if case let .bounce(owner, _) = $0 { return owner == 2 }; return false }, "Partner's side must get a bounce")
        XCTAssertFalse(events.contacts(2).isEmpty, "Real partner contact: height=\(high) time=\(elapsed) state=\(e.ballState)")
        XCTAssertEqual(1, e.teamFlight?.smashes)
    }
    /// Android 971e958 default: a learning court's local player with a character walks 0.50 further right; others keep the strike
    /// zone's edge.
    func testFootworkReachDefaults() {
        XCTAssertEqual(CrossGeometry.strikeHalf, CrossEngine(seats: localTable("minik", "kyra"), control: .beginner, target: 7, seed: 1).localFootworkRight)
        XCTAssertEqual(CrossGeometry.strikeHalf, CrossEngine(seats: localTable("minik", "kyra"), control: .beginner, target: 7, seed: 1, tapTargets: true).localFootworkRight)
        XCTAssertEqual(CrossGeometry.strikeHalf + 0.50, CrossPractice(step: 2).engine.localFootworkRight, accuracy: 1e-12)
    }

    // ---- Kotlin CrossPracticeTest (c93e760) ----

    // Kotlin: aimingWaitsForDeliberateChoiceAndResumesAfterRestore
    func testAimingWaitsForDeliberateChoiceAndResumesAfterRestore() throws {
        let p = CrossPractice(step: 2); p.start()
        XCTAssertTrue(p.stage.aimed)
        for _ in 0..<600 { p.advance(CrossEngine.step) }
        XCTAssertEqual(0, p.clock); XCTAssertEqual(0, p.mistakes)
        p.engine.touch(p.target); p.engine.endTouch(); p.advance(CrossEngine.step)
        XCTAssertGreaterThan(p.clock, 0)
        let copy = try CrossPractice.restore(p.save()); copy.start()
        XCTAssertEqual(p.engine.selectedAim, copy.engine.selectedAim)
        let clock = copy.clock; copy.advance(CrossEngine.step); XCTAssertGreaterThan(copy.clock, clock)
    }
}
