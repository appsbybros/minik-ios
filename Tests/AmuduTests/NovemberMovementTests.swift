import XCTest
@testable import MinikAmudu

/// Port of Android `amudu/AttackHeightTest.kt`.
final class AttackHeightTests: XCTestCase {
    private typealias S = NovemberSupport

    private func world(_ seed: Int64 = 1, bot: Bool = false, scene: ArenaScene = .park) throws -> AmuduEngine {
        let members = [Member("a", "minik", "A"), Member("b", "gaya", "B", bot: bot), Member("c", "mia", "C")]
        return try AmuduEngine(members: members, config: GameConfig(scene: scene, participants: 3, width: 28.0, depth: 18.0, actionSeconds: 0),
                               seed: seed)
    }

    private func incoming(_ z: Double, bot: Bool = false, seed: Int64 = 1) throws -> AmuduEngine {
        let e = try world(seed, bot: bot)
        e.phase = .flight
        e.frozen = true
        e.thrower = "a"
        e.actor("a")!.position = V(3.0, 9.0)
        e.actor("c")!.position = V(24.0, 3.0)
        let b = e.actor("b")!
        b.position = V(12.0, 9.0)
        b.facing = V(-1.0, 0.0)
        b.nextThink = 0.0
        let duration = 0.5
        let vz = (z - 1.17 + 0.5 * e.config.scene.gravity * duration * duration) / duration
        e.ball = Ball(V(9.0, 9.0), 1.17, V(6.0, 0.0), vz, nil, bounces: 0, flightId: "f", launchAt: 0.0)
        return e
    }

    private func run(_ e: AmuduEngine, _ seconds: Double) { S.run(e, seconds, hz: 240) }

    func testCatchWindowExpiresAtHalfSecondAndDoesNotRefreshWhileHeld() throws {
        let e = try world()
        e.phase = .air
        e.called = "b"
        e.ball = Ball(V(4.0, 4.0), 15.0, V(0.0, 0.0), 0.0)
        XCTAssertTrue(e.command("b", "catch", .catchBall))
        XCTAssertEqual(0.5, e.actor("b")!.catchUntil, accuracy: 0.00001)
        run(e, 0.45)
        XCTAssertFalse(e.command("b", "held", .catchBall))
        run(e, 0.06)
        XCTAssertGreaterThan(e.time, e.actor("b")!.catchUntil)
        XCTAssertTrue(e.command("b", "fresh", .catchBall))
        XCTAssertEqual(e.time + 0.5, e.actor("b")!.catchUntil, accuracy: 0.00001)
    }

    func testHeightMixHasRequestedWeights() {
        let samples = (0..<1000).map { AttackPhysics.height((Double($0) + 0.5) / 1000) }
        XCTAssertEqual(700, samples.filter { $0 == 1.1 }.count)
        XCTAssertEqual(150, samples.filter { $0 == 0.55 }.count)
        XCTAssertEqual(150, samples.filter { $0 == 1.8 }.count)
    }

    func testActualBotAttacksVaryAtTheReceiverInEveryArenaAndThrowMode() throws {
        for scene in ArenaScene.allCases {
            for mode in ThrowMode.allCases {
                let heights = try (1...300).map { seed -> Double in
                    let members = [Member("a", "gaya", "Gaya", bot: true), Member("b", "miniko", "B")]
                    let e = try AmuduEngine(members: members,
                                            config: GameConfig(scene: scene, participants: 2, throwMode: mode, actionSeconds: 0),
                                            seed: Int64(seed))
                    e.phase = .aim
                    e.thrower = "a"
                    e.ball.holder = "a"
                    let a = e.actor("a")!
                    a.position = V(4.0, 8.0)
                    a.nextThink = 0.0
                    e.actor("b")!.position = V(8.5, 8.0)
                    e.tick(1.0 / 120)
                    XCTAssertEqual(.flight, e.phase)
                    let t = (8.5 - e.ball.position.x) / e.ball.velocity.x
                    return e.ball.height + e.ball.vz * t - 0.5 * scene.gravity * t * t
                }
                let low = heights.filter { $0 < 0.8 }.count
                let high = heights.filter { $0 > 1.6 }.count
                XCTAssertTrue((24...72).contains(low), "\(scene) \(mode) low=\(low)")
                XCTAssertTrue((24...72).contains(high), "\(scene) \(mode) high=\(high)")
            }
        }
    }

    func testLowJumpAndHighDuckAvoidActualContactButIdleAndCentreDoNot() throws {
        for (z, action) in [(0.55, GameCommand.jump), (1.8, GameCommand.duck)] {
            let idle = try incoming(z)
            run(idle, 0.8)
            XCTAssertEqual(1, idle.actor("b")!.penalties, "Idle at \(z)")
            let dodge = try incoming(z)
            run(dodge, 0.05)
            XCTAssertTrue(dodge.command("b", "avoid", action))
            run(dodge, 0.75)
            XCTAssertEqual(0, dodge.actor("b")!.penalties, "Avoid \(z)")
            XCTAssertFalse(dodge.infoCode == "tagged")
        }
        for action in [GameCommand.jump, GameCommand.duck] {
            let centre = try incoming(1.30)
            run(centre, 0.12)
            centre.command("b", "avoid", action)
            run(centre, 0.68)
            XCTAssertEqual(1, centre.actor("b")!.penalties)
        }
    }

    func testJumpingTooLateDoesNotGrantImmunity() throws {
        let e = try incoming(0.55)
        run(e, 0.12)
        e.command("b", "late", .jump)
        run(e, 0.68)
        XCTAssertEqual(1, e.actor("b")!.penalties)
    }

    func testAllThreeHeightsCanBeCaughtWithOneAttemptAndFailedCatchesStillTag() throws {
        for z in [0.55, 1.30, 1.8] {
            for success in [true, false] {
                let e = try incoming(z)
                run(e, 0.12)
                XCTAssertTrue(e.command("b", "catch", .catchBall))
                e.actor("b")!.catchProbability = 0.9
                e.actor("b")!.catchRoll = success ? 0.0 : 0.99
                run(e, 0.68)
                XCTAssertEqual(success ? "tag_catch" : "tagged", e.infoCode, "z=\(z) success=\(success)")
            }
        }
    }

    func testHeightAdjustsExistingSkillChanceWithoutGrantingPerfectCatches() throws {
        XCTAssertEqual(0.6, 0.9 * AttackPhysics.catchFactor(0.55), accuracy: 1e-6)
        XCTAssertEqual(0.8, 0.9 * AttackPhysics.catchFactor(1.8), accuracy: 1e-6)
        XCTAssertEqual(0.9, 0.9 * AttackPhysics.catchFactor(1.3), accuracy: 1e-6)
        let e = try world()
        var b = e.ball
        b.position = V(10.0, 9.0)
        b.height = 1.3
        b.velocity = V(5.0, 0.0)
        b.vz = 0.0
        b.holder = nil
        let weak = GameActor(member: Member("w", "miniko", "W", bot: true), position: V(12.0, 9.0))
        weak.facing = V(-1.0, 0.0)
        let strong = GameActor(member: Member("s", "gaya", "S", bot: true), position: weak.position)
        strong.facing = weak.facing
        XCTAssertGreaterThan(CatchPhysics.probability(strong, b, e.actor("a")), CatchPhysics.probability(weak, b, e.actor("a")))
        XCTAssertLessThan(CatchPhysics.probability(strong, b, e.actor("a")), 1)
    }

    func testBotsSometimesChooseWorkingDodgesAndOtherwiseTryCatching() throws {
        for z in [0.55, 1.8] {
            var avoided = 0
            var attemptedCatch = 0
            for seed in 1...100 {
                let e = try incoming(z, bot: true, seed: Int64(seed))
                run(e, 0.8)
                let b = e.actor("b")!
                if !e.events.contains(where: { $0.kind == "catch_attempt" }) {
                    XCTAssertEqual(0, b.penalties, "Unsafe dodge z=\(z) seed=\(seed)")
                    avoided += 1
                } else {
                    attemptedCatch += 1
                }
            }
            XCTAssertTrue((40...98).contains(avoided), "No real dodges at \(z) (\(avoided))")
            XCTAssertGreaterThan(attemptedCatch, 0)
        }
    }

    func testActualLowCatchIsHarderEvenWhenHandsMeetItEarlierInItsArc() throws {
        for z in [0.55, 1.30, 1.8] {
            let e = try incoming(z)
            run(e, 0.12)
            e.command("b", "catch", .catchBall)
            e.actor("b")!.catchProbability = 0.9
            e.actor("b")!.catchRoll = 0.75
            run(e, 0.68)
            XCTAssertEqual(z < 1 ? "tagged" : "tag_catch", e.infoCode)
        }
    }

    func testJumpLandsDuringOutcomeBothLocallyAndInRemotePrediction() throws {
        let e = try incoming(0.55)
        run(e, 0.05)
        e.command("b", "jump", .jump)
        run(e, 0.55)
        XCTAssertEqual(.resolve, e.phase)
        XCTAssertGreaterThan(e.actor("b")!.jumpHeight, 0)
        let raw = MotionPublication().encode(e, AmuduCodec.shared(e), true)
        let predicted = S.child(S.child(MotionState.materialize(raw, e.time + 0.8), "actors"), "b")
        XCTAssertEqual(0.0, predicted.num("jumpHeight"), accuracy: 0.001)
        run(e, 0.8)
        XCTAssertEqual(0.0, e.actor("b")!.jumpHeight, accuracy: 0.001)
    }

    func testPreparationHeightSurvivesOnlineCheckpoint() throws {
        let e = try incoming(0.55)
        run(e, 0.12)
        e.command("b", "catch", .catchBall)
        let restored = try AmuduCodec.create(AmuduCodec.checkpoint(e))
        XCTAssertEqual(e.actor("b")!.catchHeight, restored.actor("b")!.catchHeight)
        XCTAssertEqual(e.actor("b")!.catchUntil, restored.actor("b")!.catchUntil)
    }
}

/// Port of Android `amudu/BlockedMovementTest.kt`.
final class BlockedMovementTests: XCTestCase {
    private typealias S = NovemberSupport

    private func crowded(_ seed: Int64) throws -> AmuduEngine {
        let ids = ["comet", "coach67", "mia", "moshiko", "june", "kyra", "miniko", "amber"]
        let members = ids.enumerated().map { Member("p\($0.offset)", $0.element, "Player \($0.offset)", bot: $0.offset > 0) }
        let e = try AmuduEngine(members: members,
                                config: GameConfig(scene: .beach, participants: 8, width: 28.0, depth: 18.0, actionSeconds: 0), seed: seed)
        e.phase = .shout
        e.thrower = "p0"
        e.called = "p0"
        e.frozen = false
        e.actor("p0")!.position = V(16.0, 12.0)
        e.ball.position = e.actor("p0")!.position
        var placement = JavaRandom(seed)
        for a in e.actors.dropFirst() {
            let x = 26 + placement.nextDouble() * 1.4
            let y = 1 + placement.nextDouble() * 15
            a.position = V(x, y)
        }
        return e
    }

    private func pose(_ a: GameActor) -> String {
        let d = a.facing
        let facing: String
        if abs(d.x) > abs(d.y) * 0.85 {
            facing = d.x < 0 ? "left" : "right"
        } else {
            facing = d.y < 0 ? "back" : "front"
        }
        return "\(facing):\(a.actuallyMoving)"
    }

    func testCrowdedEdgesSettleWithoutAlternatingWalkAndIdleAtVariableFrameRates() throws {
        for seed in Int64(1)...Int64(20) {
            let e = try crowded(seed)
            let cadence = [0.016, 0.017, 0.025, 0.014, 0.018, 0.021]
            for i in 0..<840 { e.tick(cadence[i % cadence.count]) }
            let settled = e.actors.map { (position: $0.position, gait: $0.gait, pose: pose($0)) }
            for i in 0..<360 {
                e.tick(cadence[i % cadence.count])
                for (k, a) in e.actors.enumerated() {
                    XCTAssertEqual(settled[k].pose, pose(a), "seed \(seed) actor \(k) changes pose while blocked")
                    XCTAssertLessThan((settled[k].position - a.position).length(), 0.015, "blocked actor jitters")
                    XCTAssertEqual(settled[k].gait, a.gait, accuracy: 0.02, "blocked actor strides")
                }
            }
            let holder = e.actor("p0")!
            XCTAssertEqual(V(16.0, 12.0), holder.position)
            for i in e.actors.indices {
                for j in (i + 1)..<e.actors.count {
                    XCTAssertGreaterThanOrEqual((e.actors[i].position - e.actors[j].position).length(), 1.099, "Bodies overlap")
                }
            }
        }
    }

    func testRestoredAndRemoteSettledActorsStayStillThenReturnWhenPlayChanges() throws {
        let e = try crowded(3)
        for _ in 0..<1500 { e.tick(1.0 / 60) }
        let copy = try AmuduCodec.create(AmuduCodec.checkpoint(e))
        let positions = copy.actors.map { $0.position }
        for _ in 0..<180 { copy.tick(1.0 / 60) }
        XCTAssertEqual(positions, copy.actors.map { $0.position })
        let anchor = MotionPublication().encode(copy, AmuduCodec.shared(copy), true)
        let remote = S.child(MotionState.materialize(anchor, copy.time + 1.0), "actors")
        for a in copy.actors {
            let node = S.child(remote, a.member.id)
            XCTAssertEqual(a.position, AmuduCodec.vector(node["position"]))
            XCTAssertFalse(node.flag("actuallyMoving"))
        }
        copy.circle("p0", regroup: false)
        for _ in 0..<900 { copy.tick(1.0 / 60) }
        for a in copy.actors.dropFirst() {
            let spot = try XCTUnwrap(a.circleSpot)
            XCTAssertLessThanOrEqual((a.position - spot).length(), 0.11, "Bot remains stuck after next circle")
        }
    }

    func testSweptContactStopsHeadOnAndAllowsSlidingWithoutCrossingBodies() throws {
        let c = try GameConfig()
        let blocker = V(8.0, 8.0)
        let head = ActorMovement.advance(V(5.0, 8.0), V(6.0, 0.0), [blocker], c)
        XCTAssertEqual(6.9, head.x, accuracy: 1e-7)
        XCTAssertEqual(8.0, head.y, accuracy: 1e-7)
        var p = V(6.9, 8.0)
        for _ in 0..<120 {
            let next = ActorMovement.advance(p, V(0.02, 0.02), [blocker], c)
            XCTAssertGreaterThanOrEqual((next - blocker).length(), 1.099999)
            XCTAssertLessThanOrEqual((next - p).length(), (0.0008).squareRoot() + 1e-8)
            p = next
        }
        XCTAssertGreaterThan(p.y, 10.0, "Tangent motion should not lock a player")
    }

    func testBlockedRoutesAreAvoidedWithoutDisablingBoundaryEscape() throws {
        let c = try GameConfig(width: 28.0, depth: 18.0)
        let a = GameActor(member: Member("a", "coach67", "Coach", bot: true), position: V(27.4, 8.0))
        let other = GameActor(member: Member("b", "moshiko", "Bob", bot: true), position: V(27.4, 6.9))
        let ball = Ball(V(24.0, 8.0), 1.2, V(0.0, 0.0), 0.0, "h")
        for i in 0..<60 {
            FleeMovement.update(a, ball, V(0.0, 0.0), c, Double(i) / 60.0, 1.0 / 60, 3, .shout, [a, other])
        }
        XCTAssertGreaterThan(a.move.y, 0.5, "Should escape down, not push into Bob above")
    }
}

/// Port of Android `amudu/CircleMotionTest.kt`.
final class CircleMotionTests: XCTestCase {
    private typealias S = NovemberSupport
    private let cadence = [0.016, 0.017, 0.025]

    private func game() throws -> AmuduEngine {
        let members = [Member("a", "miniko", "Alex"), Member("b", "mia", "Mia"), Member("c", "gaya", "Gaya", bot: true),
                       Member("d", "kyra", "Kyra", bot: true), Member("e", "amber", "Amber", bot: true), Member("f", "june", "June", bot: true)]
        return try AmuduEngine(members: members,
                               config: GameConfig(scene: .andromeda, participants: 6, width: 28.0, depth: 18.0, actionSeconds: 0), seed: 4)
    }

    func testReadyBotsStayOnTheMarkedCircleWithoutWalking() throws {
        let e = try game()
        var before: [String: V] = [:]
        for a in e.actors { before[a.member.id] = a.position }
        for i in 0..<600 {
            e.tick(cadence[i % 3])
            for a in e.actors where a.member.bot {
                XCTAssertEqual(before[a.member.id], a.position, "Ready bot left the circle")
                XCTAssertFalse(a.actuallyMoving, "Stationary bot still walks")
                XCTAssertEqual(0.0, a.gait, accuracy: 1e-6)
            }
        }
    }

    func testBlockedPlayerDoesNotAnimateRunningInPlace() throws {
        let e = try game()
        let holder = e.actor("a")!
        let b = e.actor("b")!
        b.position = holder.position + V(1.1, 0.0)
        let p = b.position
        e.command("b", "move", .move(V(-1.0, 0.0)))
        for _ in 0..<120 { e.tick(1.0 / 60) }
        XCTAssertEqual(p.x, b.position.x, accuracy: 0.001)
        XCTAssertFalse(b.actuallyMoving, "Collision-stopped player keeps a walk pose")
        XCTAssertEqual(0.0, b.gait, accuracy: 0.01, "No stride without travel")
    }

    func testSlowTravelHasSlowStrides() throws {
        let e = try game()
        let b = e.actor("b")!
        b.position = V(3.0, 3.0)
        e.command("b", "move", .move(V(0.1, 0.0)))
        for _ in 0..<60 { e.tick(1.0 / 60) }
        XCTAssertEqual(0.9, b.gait, accuracy: 0.01)
    }

    func testReturnsKeepSeparatePerimeterPlacesAcrossCatchAndRestore() throws {
        let e = try game()
        let old = e.actor("b")!.circleSpot
        e.command("a", "select", .select(target: "b"))
        e.command("a", "toss", .toss(power: 0.2, drift: 0.0))
        XCTAssertEqual(old, e.actor("a")!.circleSpot)
        XCTAssertNil(e.actor("b")!.circleSpot)
        e.ball.holder = "b"
        e.phase = .resolve
        e.phaseAt = e.time
        e.infoCode = "air_catch"
        e.nextThrower = "b"
        e.regroupPending = false
        let center = V(14.0, 9.0)
        e.actor("b")!.position = center
        e.ball.position = center
        for a in e.actors where a.member.bot {
            let spot = try XCTUnwrap(a.circleSpot)
            a.position = center + (spot - center) * 1.8
        }
        for i in 0..<600 { e.tick(cadence[i % 3]) }
        for a in e.actors where a.member.bot {
            let spot = try XCTUnwrap(a.circleSpot)
            XCTAssertLessThanOrEqual((a.position - spot).length(), 0.11)
            XCTAssertEqual(4.5, (a.position - center).length(), accuracy: 0.11)
            XCTAssertFalse(a.actuallyMoving)
        }
        let spots = e.actors.compactMap { $0.circleSpot }
        for i in spots.indices {
            for j in (i + 1)..<spots.count { XCTAssertGreaterThan((spots[i] - spots[j]).length(), 1.1) }
        }
        // Roster order kept like Kotlin's in-memory LinkedHashMap (the saved local game passes it the same way).
        let restored = try AmuduCodec.create(AmuduCodec.checkpoint(e), order: e.actors.map { $0.member.id })
        XCTAssertEqual(e.actors.map { $0.circleSpot }, restored.actors.map { $0.circleSpot })
        let positions = restored.actors.map { $0.position }
        let gaits = restored.actors.map { $0.gait }
        for _ in 0..<120 { restored.tick(1.0 / 60) }
        XCTAssertEqual(positions, restored.actors.map { $0.position })
        XCTAssertEqual(gaits, restored.actors.map { $0.gait })
    }

    func testRemoteBotStopsAtItsReturnDestination() throws {
        let e = try game()
        let a = e.actor("c")!
        let spot = try XCTUnwrap(a.circleSpot)
        a.position = spot + V(3.0, 0.0)
        a.move = V(-1.0, 0.0)
        a.actuallyMoving = true
        let pub = MotionPublication()
        let raw = pub.encode(e, AmuduCodec.shared(e), true)
        let end = S.child(S.child(MotionState.materialize(raw, 5.0), "actors"), "c")
        XCTAssertLessThanOrEqual((AmuduCodec.vector(end["position"]) - spot).length(), 0.11)
        XCTAssertFalse(end.flag("actuallyMoving"))
    }

    func testNewReturnDecisionPublishesItsStoppingPlaceEvenWithTheSameVelocity() throws {
        let e = try game()
        e.phase = .air
        e.called = "b"
        e.ball = Ball(V(14.0, 9.0), 10.0, V(0.1, 0.0), 1.0, nil, bounces: 0, flightId: "flight")
        let a = e.actor("c")!
        a.move = V(-1.0, 0.0)
        a.actuallyMoving = true
        let pub = MotionPublication()
        let old = pub.encode(e, AmuduCodec.shared(e), true)
        XCTAssertTrue(S.isNull(S.child(S.child(old, "actors"), "c")["motionTarget"]))
        a.anticipationFlight = "flight"
        let now = pub.encode(e, AmuduCodec.shared(e), true)
        XCTAssertFalse(S.isNull(S.child(S.child(now, "actors"), "c")["motionTarget"]))
    }
}

/// Port of Android `amudu/FollowupPhysicsTest.kt`.
final class FollowupPhysicsTests: XCTestCase {
    private typealias S = NovemberSupport

    private func game() throws -> AmuduEngine {
        let members = [Member("a", "minik", "A"), Member("b", "mia", "B"), Member("c", "june", "C", bot: true)]
        return try AmuduEngine(members: members, config: GameConfig(scene: .beach, participants: 3), seed: 19)
    }

    func testMissedAttackContinuesBeyondCourtWithoutReflecting() throws {
        let e = try game()
        e.phase = .flight
        e.phaseAt = e.time
        e.thrower = "a"
        for a in e.actors { a.position = V(5.0, 5.0) }
        e.ball = Ball(V(15.6, 10.0), 1.3, V(7.0, 0.0), 0.0, nil, bounces: 0, flightId: "f", launchAt: e.time)
        for _ in 0..<25 { e.tick(0.04) }
        XCTAssertGreaterThan(e.ball.position.x, 16)
        XCTAssertGreaterThanOrEqual(e.ball.velocity.x, 0)
        XCTAssertEqual("miss", e.infoCode)
        let raw = MotionPublication().encode(e, AmuduCodec.shared(e), true)
        let ball = S.child(MotionState.materialize(raw, e.time + 0.3), "ball")
        XCTAssertGreaterThan(AmuduCodec.vector(ball["position"]).x, 16)
    }

    func testRunnersMoveWhileNextCallIsPreparedAndDuringAirCatchNotice() throws {
        let e = try game()
        e.circle("a", regroup: false)
        e.actor("b")!.position = V(3.0, 3.0)
        XCTAssertTrue(e.command("b", "run", .move(V(1.0, 0.0))))
        e.tick(0.1)
        XCTAssertGreaterThan(e.actor("b")!.position.x, 3)
        e.phase = .resolve
        e.infoCode = "air_catch"
        e.regroupPending = false
        e.phaseAt = e.time
        e.nextThrower = "a"
        let x = e.actor("b")!.position.x
        XCTAssertTrue(e.command("b", "return", .move(V(1.0, 0.0))))
        e.tick(0.1)
        XCTAssertGreaterThan(e.actor("b")!.position.x, x)
        e.phase = .aim
        e.frozen = true
        e.thrower = "a"
        XCTAssertFalse(e.command("b", "frozen", .move(V(1.0, 0.0))))
    }

    func testBotReturnsImmediatelyAfterAirCatchInsteadOfWaitingForLaunch() throws {
        let e = try game()
        e.phase = .resolve
        e.infoCode = "air_catch"
        e.regroupPending = false
        e.nextThrower = "a"
        e.ball.holder = "a"
        e.actor("a")!.position = V(8.0, 8.0)
        e.actor("c")!.position = V(14.0, 14.0)
        e.ball.position = V(8.0, 8.0)
        let before = (e.actor("c")!.position - e.ball.position).length()
        e.tick(0.1)
        XCTAssertLessThan((e.actor("c")!.position - e.ball.position).length(), before)
    }

    func testLowBallCannotBecomeAnAirCatchAtFeet() throws {
        let e = try game()
        e.phase = .air
        e.called = "b"
        e.thrower = "a"
        let b = e.actor("b")!
        b.position = V(8.0, 8.0)
        b.catchReadyAt = 0.0
        b.catchUntil = 5.0
        b.catchRoll = 0.0
        b.catchProbability = 1.0
        e.ball = Ball(V(8.5, 8.0), 0.65, V(0.0, 0.0), -1.0, nil)
        e.tick(0.01)
        XCTAssertNil(e.ball.holder)
        XCTAssertFalse(e.events.contains { $0.kind == "catch" })
    }

    func testReachingHandTouchIsTagWhenCatchFails() throws {
        let e = try game()
        e.phase = .flight
        e.thrower = "a"
        e.actor("a")!.position = V(3.0, 3.0)
        e.actor("c")!.position = V(3.0, 13.0)
        let b = e.actor("b")!
        b.position = V(9.0, 8.0)
        b.facing = V(-1.0, 0.0)
        b.catchUntil = 5.0
        b.catchProbability = 0.0
        b.catchRoll = 0.9
        e.ball = Ball(V(7.4, 8.1), 1.3, V(8.0, 0.0), 1.0, nil)
        for _ in 0..<12 { e.tick(0.01) }
        XCTAssertEqual("tagged", e.infoCode)
        XCTAssertEqual(1, b.penalties)
        XCTAssertEqual(0, e.actor("a")!.penalties)
    }

    func testExplicitDepartureSkipsCalledTurnWithoutPenaltyOrTimeout() throws {
        let e = try game()
        e.circle("b")
        e.depart("b")
        XCTAssertFalse(e.actor("b")!.active)
        XCTAssertNotEqual("b", e.thrower)
        XCTAssertEqual(0, e.actor("b")!.penalties)
        let restore = try AmuduCodec.create(AmuduCodec.checkpoint(e))
        XCTAssertTrue(restore.actor("b")!.departed)
        XCTAssertFalse(restore.actor("b")!.active)
    }

    func testNewThrowDoesNotInheritAnAheadPresentationClock() throws {
        let e = try game()
        let pub = MotionPublication()
        let p = SnapshotPlayback()
        let guest = try AmuduCodec.create(AmuduCodec.shared(e))
        p.accept(guest, pub.encode(e, AmuduCodec.shared(e), true), 1000, 0.1)
        for i in 1...240 { p.render(guest, 1000 + Int64(i) * 16) }
        e.command("a", "select", .select(target: "b"))
        e.command("a", "throw", .toss(power: 0.7, drift: 0.0))
        e.tick(0.03)
        p.accept(guest, pub.encode(e, AmuduCodec.shared(e), true), 5000, 0.25)
        p.render(guest, 5000)
        XCTAssertLessThan(guest.ball.height, 3.2, "First visible launch stays near the thrower")
    }
}
