import XCTest
@testable import MinikAmudu

/// Port of Android `amudu/RecallAndEliminationTest.kt`.
final class RecallAndEliminationTests: XCTestCase {
    private typealias S = NovemberSupport

    private func run(_ e: AmuduEngine, _ t: Double) { S.run(e, t, hz: 240) }

    private func world(bot: Bool = false, seed: Int64 = 41) throws -> AmuduEngine {
        let members = [Member("a", "minik", "A"), Member("b", "gaya", "B", bot: bot), Member("c", "mia", "C")]
        return try AmuduEngine(members: members,
                               config: GameConfig(participants: 3, width: 28.0, depth: 18.0, rules: .spud, actionSeconds: 0), seed: seed)
    }

    func testEliminatedHumansAndBotsRemainForContactThenWalkOutWithoutPlaying() throws {
        for bot in [false, true] {
            let e = try world(bot: bot)
            let a = e.actor("b")!
            a.penalties = 3
            a.position = V(12.0, 9.0)
            a.nextThink = 999.0
            e.actor("a")!.position = V(3.0, 9.0)
            e.actor("c")!.position = V(24.0, 3.0)
            e.phase = .flight
            e.thrower = "a"
            e.frozen = true
            e.ball = Ball(V(9.0, 9.0), 1.17, V(6.0, 0.0), (1.3 - 1.17 + 0.5 * 9.8 * 0.25) / 0.5, nil, bounces: 0, flightId: "hit", launchAt: 0.0)
            run(e, 0.8)
            XCTAssertEqual(4, a.penalties)
            XCTAssertFalse(a.active)
            XCTAssertTrue(EliminationExit.visible(a, e.time))
            XCTAssertLessThan(e.ball.velocity.x, 0)
            XCTAssertFalse(e.command("b", "still-out", .catchBall))
            run(e, 3.0)
            XCTAssertTrue(EliminationExit.visible(a, e.time))
            XCTAssertEqual(-1.0, a.exitAt)
            var guardSteps = 0
            while e.phase == .resolve && guardSteps < 100_000 {
                e.tick(0.01)
                guardSteps += 1
            }
            XCTAssertGreaterThanOrEqual(a.exitAt, 0)
            let start = EliminationExit.position(a, e.time)
            run(e, 0.8)
            XCTAssertGreaterThan((EliminationExit.position(a, e.time) - start).length(), 0.5)
            let restored = try AmuduCodec.create(AmuduCodec.checkpoint(e))
            XCTAssertEqual(EliminationExit.position(a, e.time), EliminationExit.position(restored.actor("b")!, restored.time))
            XCTAssertFalse(EliminationExit.visible(a, a.exitAt + EliminationExit.DURATION + 0.01))
            XCTAssertFalse(a.active)
        }
    }

    func testOnlyHumanRecipientsGetFifteenPercentHigherMinimumCall() throws {
        for scene in ArenaScene.allCases {
            for throwerBot in [false, true] {
                func apex(_ receiverBot: Bool, _ p: Double) throws -> Double {
                    let members = [Member("a", "minik", "A", bot: throwerBot), Member("b", "mia", "B", bot: receiverBot)]
                    let e = try AmuduEngine(members: members, config: GameConfig(scene: scene, participants: 2, actionSeconds: 0), seed: 2)
                    e.command("a", "select", .select(target: "b"))
                    XCTAssertTrue(e.command("a", "throw", .toss(power: p, drift: 0.0)))
                    return e.ball.height + e.ball.vz * e.ball.vz / (2 * scene.gravity)
                }
                let botMin = try apex(true, 0.0)
                let humanMin = try apex(false, 0.0)
                let botMax = try apex(true, 1.0)
                let humanMax = try apex(false, 1.0)
                XCTAssertEqual(botMin * 1.15, humanMin, accuracy: 1e-9)
                XCTAssertEqual(botMax, humanMax, accuracy: 1e-9)
            }
        }
    }

    func testBotRecallHasOneBoundedSavedDelayAndDoesNotRepeatTheOldPreparation() throws {
        var delays: [Double] = []
        for seed in Int64(1)...Int64(50) {
            let e = try world(bot: true, seed: seed)
            let a = e.actor("b")!
            e.phase = .air
            e.called = "b"
            e.thrower = "a"
            a.position = V(14.0, 9.0)
            e.landing = a.position
            e.ball = Ball(a.position, 1.9, V(0.0, 0.0), -0.2, nil, bounces: 0, flightId: "call", launchAt: 0.0)
            XCTAssertTrue(e.command("b", "catch", .catchBall))
            a.catchRoll = 0.0
            run(e, 0.02)
            XCTAssertEqual("air_catch", e.infoCode)
            let caught = e.phaseAt
            let delay = e.recallAt - caught
            XCTAssertTrue(delay >= 0.70 && delay <= 1.20, "delay \(delay)")
            delays.append(delay)
            let recovered = try AmuduCodec.create(AmuduCodec.checkpoint(e))
            XCTAssertEqual(e.recallAt, recovered.recallAt)
            var guardSteps = 0
            while e.phase == .resolve && guardSteps < 100_000 {
                e.tick(0.01)
                guardSteps += 1
            }
            run(e, 0.03)
            XCTAssertEqual(.air, e.phase)
            XCTAssertEqual("b", e.thrower)
            XCTAssertLessThan(e.time - caught, delay + 0.05)
            XCTAssertLessThanOrEqual(e.infoUntil, e.time)
        }
        XCTAssertGreaterThan((delays.max() ?? 0) - (delays.min() ?? 0), 0.3)
    }

    private struct Sample {
        let speed: Double
        let chance: Double
        let height: Double
    }

    private func samples(_ id: String) throws -> [Sample] {
        return try (Int64(1)...Int64(160)).map { seed -> Sample in
            let members = [Member("a", id, "Bot", bot: true), Member("b", "mia", "B")]
            let e = try AmuduEngine(members: members, config: GameConfig(participants: 2, actionSeconds: 0), seed: seed)
            let a = e.actor("a")!
            let b = e.actor("b")!
            a.position = V(4.0, 8.0)
            a.nextThink = 0.0
            b.position = V(10.0, 8.0)
            b.facing = V(-1.0, 0.0)
            e.phase = .aim
            e.thrower = "a"
            e.ball.holder = "a"
            e.tick(1.0 / 120)
            XCTAssertEqual(.flight, e.phase)
            let t = (b.position.x - e.ball.position.x) / e.ball.velocity.x
            let h = e.ball.height + e.ball.vz * t - 0.5 * e.config.scene.gravity * t * t
            return Sample(speed: e.ball.velocity.length(),
                          chance: CatchPhysics.probability(b, e.ball, a, true) * AttackPhysics.catchFactor(h), height: h)
        }
    }

    func testPowerProducesFasterAttacksAndLowerCatchChancesWithoutChangingNameCalls() throws {
        let bob = try samples("moshiko")
        let minik = try samples("minik")
        XCTAssertGreaterThan(S.average(bob.map { $0.speed }), S.average(minik.map { $0.speed }) * 1.12)
        XCTAssertLessThan(S.average(bob.map { $0.chance }), S.average(minik.map { $0.chance }))
        XCTAssertLessThan(S.average(bob.filter { $0.height < 0.8 }.map { $0.chance }),
                          S.average(minik.filter { $0.height >= 1.0 && $0.height <= 1.5 }.map { $0.chance }) - 0.10)
        let a = GameActor(member: Member("x", "gaya", "Gaya", bot: true), position: V(5.0, 5.0))
        let ball = Ball(V(5.0, 6.0), 1.3, V(0.0, -8.0), 0.0)
        a.facing = V(0.0, 1.0)
        XCTAssertEqual(CatchPhysics.probability(a, ball, nil) * 0.94, CatchPhysics.probability(a, ball, nil, true), accuracy: 1e-9)
    }

    func testHebrewBobNameChangesWithoutRenamingIdentityOrEnglish() {
        XCTAssertEqual("קובי קפיץ", AmuduCharacters.get("moshiko").he)
        XCTAssertEqual("Bouncy Bob", AmuduCharacters.get("moshiko").en)
    }
}

/// Port of Android `amudu/ReturnMovementTest.kt`.
final class ReturnMovementTests: XCTestCase {
    private typealias S = NovemberSupport

    private func game(_ seed: Int64 = 1) throws -> AmuduEngine {
        let members = [Member("a", "miniko", "Alex"), Member("b", "mia", "Mia"), Member("c", "gaya", "Gaya", bot: true)]
        return try AmuduEngine(members: members,
                               config: GameConfig(scene: .andromeda, participants: 3, width: 28.0, depth: 18.0, actionSeconds: 0), seed: seed)
    }

    func testHolderStaysPutWhileOtherPlayersCanReturn() throws {
        for resolve in [false, true] {
            let e = try game()
            e.circle("a", regroup: false)
            e.actor("a")!.position = V(14.0, 9.0)
            e.actor("b")!.position = V(6.0, 9.0)
            e.actor("c")!.position = V(23.0, 9.0)
            e.ball.position = e.actor("a")!.position
            if resolve {
                e.phase = .resolve
                e.infoCode = "air_catch"
                e.regroupPending = false
                e.nextThrower = "a"
            }
            let holder = e.actor("a")!.position
            XCTAssertFalse(e.command("a", "move", .move(V(1.0, 0.0))), "Holder cannot run before a name call")
            XCTAssertTrue(e.command("b", "run", .move(V(1.0, 0.0))))
            for _ in 0..<60 { e.tick(1.0 / 60) }
            XCTAssertEqual(holder, e.actor("a")!.position)
            XCTAssertGreaterThan(e.actor("b")!.position.x, 6)
            XCTAssertLessThan(e.actor("c")!.position.x, 23)
            e.actor("b")!.position = holder + V(0.3, 0.0)
            e.tick(0.1)
            XCTAssertEqual(holder, e.actor("a")!.position, "Separation must not push the holder")
            XCTAssertTrue(e.command("a", "s", .select(target: "b")) || resolve)
            if !resolve {
                XCTAssertTrue(e.command("a", "t", .toss(power: 0.2, drift: 0.0)))
                XCTAssertTrue(e.command("a", "released", .move(V(1.0, 0.0))))
            }
        }
    }

    func testAnticipatoryRunnerDoesNotReverseRepeatedlyAtSixUnits() throws {
        var sawReturn = false
        for seed in Int64(1)...Int64(12) {
            let e = try game(seed)
            e.phase = .air
            e.called = "b"
            e.thrower = "a"
            e.ball = Ball(V(14.0, 9.0), 12.0, V(0.1, 0.0), 2.0, nil, bounces: 0, flightId: "flight-\(seed)", launchAt: 0.0)
            e.landing = V(14.0, 9.0)
            e.actor("a")!.position = V(3.0, 3.0)
            e.actor("b")!.position = V(14.0, 9.0)
            let c = e.actor("c")!
            c.position = V(21.0, 9.0)
            var previous = 0
            var reversals = 0
            for _ in 0..<150 {
                e.tick(1.0 / 60)
                let d = e.landing - c.position
                let dot = c.move.x * d.x + c.move.y * d.y
                let sign = dot > 0.01 ? 1 : (dot < -0.01 ? -1 : 0)
                if sign == 1 { sawReturn = true }
                if sign != 0 {
                    if previous != 0 && previous != sign { reversals += 1 }
                    previous = sign
                }
            }
            XCTAssertLessThanOrEqual(reversals, 1, "Runner reverses \(reversals) times at six-unit threshold (seed \(seed))")
        }
        XCTAssertTrue(sawReturn, "Scenario must include a deliberate early return")
    }

    func testAllowedStepsAfterSpudArePreserved() throws {
        let members = [Member("a", "miniko", "Alex"), Member("b", "mia", "Mia")]
        let e = try AmuduEngine(members: members, config: GameConfig(participants: 2, stepsAfterCall: 2), seed: 1)
        e.phase = .aim
        e.frozen = true
        e.stepRemaining = 0.6
        let p = e.actor("a")!.position
        XCTAssertTrue(e.command("a", "allowed", .move(V(1.0, 0.0))))
        for _ in 0..<60 { e.tick(1.0 / 60) }
        XCTAssertEqual(0.6, (e.actor("a")!.position - p).length(), accuracy: 0.001)
        XCTAssertFalse(e.command("a", "finished", .move(V(1.0, 0.0))))
    }

    func testStaleHolderVelocityCannotBePredictedAsMovement() throws {
        let e = try game()
        let a = e.actor("a")!
        a.position = V(14.0, 9.0)
        a.move = V(1.0, 0.0)
        a.actuallyMoving = true
        let raw = MotionPublication().encode(e, AmuduCodec.shared(e), true)
        let later = MotionState.materialize(raw, 1.0)
        XCTAssertEqual(a.position, AmuduCodec.vector(S.child(S.child(later, "actors"), "a")["position"]))
    }
}

/// Port of Android `amudu/RoundVarietyTest.kt`.
final class RoundVarietyTests: XCTestCase {
    private typealias S = NovemberSupport

    private func game(_ seed: Int64 = 7, wind: Wind = .none) throws -> AmuduEngine {
        let members = [Member("h", "minik", "Alex"), Member("m", "mia", "Mia"), Member("k", "kyra", "Kyra", bot: true),
                       Member("f", "flare", "Flare", bot: true), Member("b", "moshiko", "Bob", bot: true), Member("g", "gaya", "Gaya", bot: true)]
        return try AmuduEngine(members: members,
                               config: GameConfig(participants: 6, width: 28.0, depth: 18.0, wind: wind, actionSeconds: 0), seed: seed)
    }

    func testRosterQualitiesMatchTheRequestedChanges() {
        let expected: [(String, Skills)] = [("kyra", Skills(5, 4, 5, 4, 5)), ("flare", Skills(4, 5, 5, 4, 5)), ("gaya", Skills(5, 5, 4, 5, 4)),
                                            ("amber", Skills(3, 3, 2, 3, 2)), ("comet", Skills(3, 4, 5, 3, 5)), ("june", Skills(4, 3, 5, 4, 4)),
                                            ("moshiko", Skills(4, 5, 1, 3, 1)), ("coach67", Skills(2, 3, 3, 4, 2))]
        for (id, q) in expected { XCTAssertEqual(q, AmuduCharacters.get(id).qualities, id) }
    }

    func testBotCatchReductionAppliesToAllQualityLevelsAndSituationsOnly() {
        for c in AmuduCharacters.all {
            for attack in [false, true] {
                for moving in [false, true] {
                    let a = GameActor(member: Member("b", c.id, "Bot", bot: true), position: V(8.0, 12.0))
                    a.facing = V(0.0, -1.0)
                    a.actuallyMoving = moving
                    let b = Ball(V(8.0, 11.0), 1.3, V(0.0, 4.0), 0.0)
                    let from = GameActor(member: Member("t", "miniko", "T"), position: V(8.0, 4.0))
                    let q = Double(c.qualities.catching - 1) / 4.0
                    let low = 0.12 + 0.18 * q
                    let high = 0.78 + 0.19 * q
                    let original = low + (high - low) * (moving ? 0.80 : 1.0)
                    XCTAssertEqual(original * 0.90 * (attack ? 0.94 : 1.0), CatchPhysics.probability(a, b, from, attack), accuracy: 1e-9)
                    let human = GameActor(member: a.member.copy(bot: false), position: a.position)
                    human.facing = a.facing
                    XCTAssertEqual(0.95 * (attack ? 0.94 : 1.0), CatchPhysics.probability(human, b, from, attack), accuracy: 1e-9)
                }
            }
        }
    }

    func testCircleStartsVaryButRetainEvenSpacingAndSavedFormation() throws {
        let worlds = try (Int64(1)...Int64(12)).map { try game($0) }
        XCTAssertGreaterThan(Set(worlds.map { $0.actor("b")!.position }).count, 8)
        XCTAssertEqual(try game(2).actors.map { $0.position }, try game(2).actors.map { $0.position })
        for e in worlds {
            let ring = e.actors.dropFirst().map { $0.position }
            let center = V(14.0, 9.0)
            for p in ring { XCTAssertEqual(4.5, (p - center).length(), accuracy: 1e-9) }
            let sorted = ring.map { atan2($0.y - center.y, $0.x - center.x) }.sorted()
            for i in sorted.indices {
                let gap = (sorted[(i + 1) % ring.count] - sorted[i] + 2 * Double.pi).truncatingRemainder(dividingBy: 2 * Double.pi)
                XCTAssertEqual(2 * Double.pi / Double(ring.count), gap, accuracy: 1e-9)
            }
            // Kotlin keeps the checkpoint map in roster order (LinkedHashMap); a Swift dictionary has none, so the
            // round trip passes the roster order exactly as the saved local game does (AppModel `{checkpoint, order}`).
            let copy = try AmuduCodec.create(AmuduCodec.checkpoint(e), order: e.actors.map { $0.member.id })
            XCTAssertEqual(e.circleAngle, copy.circleAngle)
            XCTAssertEqual(e.actors.map { $0.position }, copy.actors.map { $0.position })
        }
    }

    func testPointRegroupUsesNearbyPlacesInsteadOfOriginalRosterOrder() throws {
        let e = try game()
        let ring = Array(e.actors.dropFirst())
        let spots = ring.map { $0.position }
        for (i, a) in ring.enumerated() { a.position = spots[(i + 2) % spots.count] + V(0.12, 0.08) }
        e.time = 5.0
        e.circle("h")
        for (i, a) in ring.enumerated() { XCTAssertEqual(spots[(i + 2) % spots.count], a.position) }
        let places = [V(0.0, 0.0), V(4.0, 0.0), V(8.0, 0.0)]
        XCTAssertEqual([places[1], places[0], places[2]], CircleFormation.nearest([V(3.9, 0.0), V(0.1, 0.0), V(7.0, 0.0)], places))
    }

    func testLightWindCallsLandAcrossBothAxesInsideCircleAndKeepTheirSeededBounceDirection() throws {
        var offsets: [V] = []
        for seed in Int64(1)...Int64(160) {
            let e = try game(seed, wind: .slow)
            XCTAssertTrue(e.command("h", "select", .select(target: "m")))
            XCTAssertTrue(e.command("h", "toss", .toss(power: 0.1, drift: 0.0)))
            let offset = e.landing - V(14.0, 9.0)
            offsets.append(offset)
            XCTAssertLessThanOrEqual(offset.length(), 4.15 * 0.85 + 0.001)
            e.actor("m")!.position = V(1.0, 1.0)
            var last = e.ball.position
            var guardSteps = 0
            while e.phase == .air && guardSteps < 240 * 60 {
                last = e.ball.position
                e.tick(1.0 / 240)
                guardSteps += 1
            }
            XCTAssertEqual(.retrieve, e.phase)
            XCTAssertLessThan((e.ball.position - e.landing).length(), 0.03)
            XCTAssertTrue(e.ball.velocity.finite())
            XCTAssertLessThan((e.ball.position - last).length(), 0.03)
        }
        XCTAssertLessThan(offsets.map { $0.x }.min() ?? 0, -3.5 * 0.85)
        XCTAssertGreaterThan(offsets.map { $0.x }.max() ?? 0, 3.5 * 0.85)
        XCTAssertLessThan(offsets.map { $0.y }.min() ?? 0, -3.5 * 0.85)
        XCTAssertGreaterThan(offsets.map { $0.y }.max() ?? 0, 3.5 * 0.85)
    }

    func testFleeingStaysOutwardVariesLaterallyAndEscapesAlongBoundary() throws {
        let c = try GameConfig(participants: 2, width: 28.0, depth: 18.0)
        var moves: [V] = []
        for seed in Int64(1)...Int64(16) {
            let a = GameActor(member: Member("b", "kyra", "Bot", bot: true), position: V(14.0, 4.5))
            let ball = Ball(V(14.0, 9.0), 5.0, V(-0.8, -0.3), 1.0, nil, bounces: 0, flightId: "call")
            for i in 0..<60 {
                FleeMovement.update(a, ball, V(0.0, 0.0), c, Double(i) / 60.0, 1.0 / 60, seed, .air)
                XCTAssertLessThanOrEqual(a.move.length(), 1.00001)
            }
            XCTAssertLessThan(a.move.y, -0.3)
            moves.append(a.move)
        }
        XCTAssertTrue(moves.contains { $0.x > 0.2 })
        XCTAssertTrue(moves.contains { $0.x < -0.2 })
        let edge = GameActor(member: Member("b", "kyra", "Bot", bot: true), position: V(0.6, 9.0))
        let approaching = Ball(V(3.0, 9.2), 0.5, V(-2.0, 0.0), -0.2, nil, bounces: 2, flightId: "call")
        for i in 0..<60 { FleeMovement.update(edge, approaching, V(0.0, 0.0), c, Double(i) / 60.0, 1.0 / 60, 5, .retrieve) }
        XCTAssertGreaterThan(abs(edge.move.y), 0.5)
        XCTAssertGreaterThanOrEqual(edge.move.x, -0.01)
    }

    func testFleeCommandsChangeSmoothlyAndSurviveCheckpoint() throws {
        let e = try game()
        let a = e.actor("k")!
        e.phase = .air
        e.called = "m"
        e.ball = Ball(V(14.0, 9.0), 8.0, V(1.0, -0.7), 2.0, nil, bounces: 0, flightId: "call")
        var previous = a.move
        for i in 0..<90 {
            FleeMovement.update(a, e.ball, V(0.0, 0.0), e.config, Double(i) / 60.0, 1.0 / 60, e.seed, e.phase)
            XCTAssertLessThan((a.move - previous).length(), 0.29)
            previous = a.move
        }
        let copy = try AmuduCodec.create(AmuduCodec.checkpoint(e)).actor("k")!
        XCTAssertEqual(a.fleeFlight, copy.fleeFlight)
        XCTAssertEqual(a.fleeDirection, copy.fleeDirection)
        XCTAssertEqual(a.fleeNextAt, copy.fleeNextAt)
    }

    func testNoWindStaysWithinThirtyPercentAndStrongWindRetainsItsWindDrift() throws {
        for seed in Int64(1)...Int64(100) {
            let e = try game(seed)
            e.command("h", "s", .select(target: "m"))
            e.command("h", "t", .toss(power: 0.7, drift: 0.0))
            XCTAssertLessThanOrEqual((e.landing - V(14.0, 9.0)).length(), 1.246)
        }
        let e = try game(20, wind: .fast)
        e.command("h", "s", .select(target: "m"))
        e.command("h", "t", .toss(power: 0.9, drift: 0.0))
        XCTAssertGreaterThan(e.landing.x, 16.0)
    }

    func testSurfaceBounceIsUsuallyStraightAndRemotePredictsTheSameGlancingBounce() throws {
        let original = V(-3.0, 0.3)
        var straight = 0
        for i in 0..<2000 {
            let changed = GroundBounce.direction(original, "call-\(i)", 0)
            if changed == original { straight += 1 }
            XCTAssertEqual(original.length(), changed.length(), accuracy: 1e-9)
        }
        XCTAssertTrue((1640...1760).contains(straight), "straight=\(straight)")
        for i in 0..<40 {
            let e = try game()
            e.phase = .retrieve
            e.called = "m"
            e.actor("m")!.position = V(1.0, 1.0)
            e.ball = Ball(V(14.0, 9.0), 0.25, V(-3.0, 0.3), -0.2, nil, bounces: 0, flightId: "call-\(i)")
            let anchor = MotionPublication().encode(e, AmuduCodec.shared(e), true)
            for _ in 0..<48 { e.tick(1.0 / 240) }
            let predicted = S.child(MotionState.materialize(anchor, e.time), "ball")
            XCTAssertLessThan((AmuduCodec.vector(predicted["position"]) - e.ball.position).length(), 0.04)
            XCTAssertLessThan((AmuduCodec.vector(predicted["velocity"]) - e.ball.velocity).length(), 0.04)
        }
        var b = Ball(V(0.20, 8.0), 0.4, V(-3.0, 0.5), 0.2)
        let config = try game().config
        GroundBounce.contain(&b, config)
        XCTAssertEqual(0.0, b.velocity.x)
        XCTAssertEqual(0.5, b.velocity.y)
    }
}

/// Port of Android `amudu/EighteenIssueRegressionTest.kt`.
final class EighteenIssueRegressionTests: XCTestCase {
    func testShortFastFlickDoesNotBecomeFullPower() {
        XCTAssertLessThan(TossGesture.power(35.0, 60), 0.1)
        XCTAssertGreaterThan(TossGesture.power(220.0, 150), 0.7)
        XCTAssertLessThan(TossGesture.power(220.0, 1200), 0.1)
    }

    func testThirdBotCallSurvivesCheckpointAndNextCallReachesConnectedHuman() throws {
        for seed in 0..<80 {
            let members = [Member("b0", "kyra", "Kyra", bot: true), Member("b1", "flare", "Flare", bot: true), Member("b2", "mia", "Mia", bot: true),
                           Member("human", "miniko", "Human"), Member("away", "june", "Away")]
            var e = try AmuduEngine(members: members, config: GameConfig(participants: 5, actionSeconds: 0), seed: Int64(seed))
            e.circle("b0", regroup: false)
            e.botCallStreak = 3
            e = try AmuduCodec.create(AmuduCodec.checkpoint(e))
            e.connectedHumanIds = ["human"]
            e.actor("b0")!.nextThink = -1.0
            e.tick(0.02)
            XCTAssertEqual("human", e.called, "seed \(seed)")
            XCTAssertEqual(0, e.botCallStreak)
        }
    }

    func testGentleMediumAndStrongCallsAreDifferentInEveryArena() throws {
        for scene in ArenaScene.allCases {
            let peaks = try [0.0, 0.5, 1.0].map { power -> Double in
                let e = try AmuduEngine(members: [Member("a", "minik", "A"), Member("b", "mia", "B")],
                                        config: GameConfig(scene: scene, participants: 2), seed: 9)
                e.circle("a", regroup: false)
                e.command("a", "s", .select(target: "b"))
                e.command("a", "t", .toss(power: power, drift: 0.0))
                return e.ball.height + e.ball.vz * e.ball.vz / (2 * scene.gravity)
            }
            XCTAssertEqual((scene == .beach ? 3.08 : 2.8) * 1.15 * 1.20 * 1.10 * 1.15, peaks[0], accuracy: 0.001)
            XCTAssertGreaterThan(peaks[1], peaks[0] + 1)
            XCTAssertGreaterThan(peaks[2], peaks[1] + 2)
        }
    }

    func testLeadingBallEdgeHitsBeforeGroundEvenWhenItsCenterWouldArriveLate() throws {
        let t = try XCTUnwrap(BallContact.first(V(0.0, 0.0), V(2.0, 0.0), 0.6, 0.1, V(1.8, 0.0), 0.58, -0.15, 1.9))
        XCTAssertLessThan(t, 0.74)
        XCTAssertEqual(0.61, t, accuracy: 0.001)
        XCTAssertNil(BallContact.first(V(0.0, 0.0), V(2.0, 0.0), 3.0, 2.5, V(1.0, 0.0), 0.58, -0.15, 1.9))
        XCTAssertNil(BallContact.first(V(0.0, 0.0), V(2.0, 0.0), 1.0, 1.0, V(1.0, 1.0), 0.58, -0.15, 1.9))
    }

    func testFreeRunnerCannotCollectCalledPlayersBall() throws {
        let e = try AmuduEngine(members: [Member("a", "minik", "A"), Member("b", "mia", "B")], config: GameConfig(participants: 2), seed: 4)
        e.phase = .retrieve
        e.called = "b"
        e.ball.holder = nil
        e.ball.position = e.actor("a")!.position
        e.ball.height = 0.23
        XCTAssertTrue(e.command("a", "collect", .catchBall))
        XCTAssertNil(e.ball.holder)
    }

    func testNicknameOptionsPersistWithoutSkippingIncorrectChoicePenalties() throws {
        for mode in NicknameAnswer.allCases {
            let e = try AmuduEngine(members: [Member("a", "minik", "A"), Member("b", "mia", "B")],
                                    config: GameConfig(participants: 2, nicknameAnswer: mode), seed: 4)
            e.circle("a", regroup: false)
            e.actor("b")!.suffixes.append("Moon")
            XCTAssertEqual(mode, try AmuduCodec.create(AmuduCodec.checkpoint(e)).config.nicknameAnswer)
            let accepted = e.command("a", "choose", .select(target: "b", typedName: "Wrong"))
            XCTAssertEqual(mode == .automatic, accepted)
        }
    }

    func testCompactLandscapeContainsActualFieldAndActorHeads() {
        let points: [(Double, Double, Double)] = [(0.5, 0.5, 0.0), (27.5, 0.5, 0.0), (0.5, 17.5, 0.0), (27.5, 17.5, 0.0), (14.0, 9.0, 4.0)]
        let cam = TightFraming.fit(ArenaCamera(x: 14.0, y: 9.0, tilt: 0.76), points, 740, 360, 190.0, 724.0, 64.0, 280.0)
        let p = points.map { cam.project($0.0, $0.1, $0.2, 740, 360) }
        XCTAssertTrue(p.allSatisfy { $0.x >= 190 && $0.x <= 724 && $0.y >= 64 && $0.y <= 280 })
        let xs = p.map { $0.x }
        XCTAssertGreaterThan((xs.max() ?? 0) - (xs.min() ?? 0), 380)
    }
}

/// Port of Android `amudu/EnvironmentFeedbackTest.kt`.
final class EnvironmentFeedbackTests: XCTestCase {
    private typealias S = NovemberSupport

    func testCatchPreparedBeforeReleaseUsesActualThrowWithoutExtraTimeOrRoll() throws {
        for point in [false, true] {
            let e = try AmuduEngine(members: [Member("a", "minik", "A"), Member("b", "mia", "B")],
                                    config: GameConfig(participants: 2, throwMode: .easy), seed: 3)
            e.phase = .aim
            e.frozen = true
            e.thrower = "a"
            e.called = "a"
            let a = e.actor("a")!
            let b = e.actor("b")!
            a.position = V(8.0, 5.0)
            b.position = V(8.0, 10.0)
            a.direction = V(0.0, 1.0)
            e.ball = Ball(a.position, 1.17, V(0.0, 0.0), 0.0, "a")
            XCTAssertTrue(e.command("b", "prepare", .catchBall))
            let deadline = b.catchUntil
            let roll = b.catchRoll
            let command: GameCommand = point ? .pointThrow(point: b.position, height: 1.2) : .throwBall(power: 1.0)
            XCTAssertTrue(e.command("a", "throw", command))
            XCTAssertEqual(deadline, b.catchUntil)
            XCTAssertEqual(roll, b.catchRoll)
            XCTAssertEqual(CatchPhysics.probability(b, e.ball, a, true), b.catchProbability, accuracy: 1e-9)
        }
    }

    private func game(_ wind: Wind = .fast) throws -> AmuduEngine {
        let members = [Member("h", "miniko", "Alex"), Member("b", "mia", "Mia"), Member("c", "coach67", "Coach")]
        return try AmuduEngine(members: members,
                               config: GameConfig(participants: 3, width: 28.0, depth: 18.0, wind: wind, actionSeconds: 0), seed: 44)
    }

    func testRevisedCallBoundsAndSpreadArePhysicalForEveryArenaAndReceiver() {
        for scene in ArenaScene.allCases {
            for human in [true, false] {
                let beforeMin = (scene == .beach ? 3.08 : 2.8) * (human ? 1.15 : 1.0) * 1.20 * 1.10
                let beforeMaxVz = (9.8 * 4 / 2 - 1.2 / 4) * (scene == .andromeda ? 1.0 : (0.75).squareRoot())
                func apex(_ power: Double) -> Double {
                    let v = CallLob.velocity(scene, human, power)
                    return 1.2 + v * v / (2 * scene.gravity)
                }
                XCTAssertEqual(beforeMin * 1.15, apex(0.0), accuracy: 1e-8)
                XCTAssertEqual((1.2 + beforeMaxVz * beforeMaxVz / (2 * scene.gravity)) * 0.9, apex(1.0), accuracy: 1e-8)
                XCTAssertEqual(0.85, CallLob.spreadFactor(scene, CallLob.velocity(scene, human, 0.0)))
                XCTAssertEqual(0.95, CallLob.spreadFactor(scene, CallLob.velocity(scene, human, 1.0)))
            }
        }
    }

    func testCallPredictionMatchesReducedWindAndAttackKeepsOriginalWind() throws {
        let e = try game()
        e.circle("h", regroup: false)
        e.command("h", "s", .select(target: "b"))
        e.command("h", "t", .toss(power: 0.0, drift: 0.8))
        XCTAssertEqual(e.baseWind.length() * 0.9, e.windVector.length(), accuracy: 1e-9)
        let anchor = MotionPublication().encode(e, AmuduCodec.shared(e), true)
        let expected = S.child(MotionState.materialize(anchor, e.time + 0.1), "ball")
        for _ in 0..<10 { e.tick(0.01) }
        XCTAssertEqual(e.ball.position.x, AmuduCodec.vector(expected["position"]).x, accuracy: 1e-7)
        XCTAssertEqual(e.ball.height, expected.num("height"), accuracy: 1e-7)
        e.phase = .flight
        XCTAssertEqual(e.baseWind, e.windVector)
    }

    func testDefendersCanPrepareBeforeThrowButNeverWhileHoldingOrDuringOutcome() throws {
        let e = try game()
        e.thrower = "b"
        e.called = "b"
        e.ball.holder = "b"
        for phase in [Phase.retrieve, .shout, .aim, .flight] {
            e.phase = phase
            e.time += 1
            XCTAssertTrue(e.command("h", phase.rawValue, .catchBall), phase.rawValue)
            XCTAssertGreaterThan(e.actor("h")!.catchUntil, e.time)
        }
        e.phase = .resolve
        e.time += 1
        XCTAssertFalse(e.command("h", "outcome", .catchBall))
        e.phase = .shout
        XCTAssertFalse(e.command("b", "holder", .catchBall))
    }

    func testLegacyHonorSaveFreezesWithoutPunishingMovement() throws {
        let e = try game()
        var n = AmuduCodec.checkpoint(e)
        var config = AmuduCodec.config(e.config)
        config["freeze"] = "HONOR"
        n["config"] = config
        let restored = try AmuduCodec.create(n)
        XCTAssertEqual(.freeze, restored.config.freezeRule)
        restored.phase = .aim
        restored.thrower = "b"
        restored.ball.holder = "b"
        restored.frozen = true
        let before = restored.actor("h")!.position
        XCTAssertFalse(restored.command("h", "move", .move(V(1.0, 0.0))))
        restored.tick(0.1)
        XCTAssertEqual(before, restored.actor("h")!.position)
        XCTAssertEqual(0, restored.actor("h")!.penalties)
    }

    func testMigrationKeepsOriginalMasteryAndPointsButDoesNotGiftNewChallenges() throws {
        let p = SpudProgress.migrate(completed: 65, points: 900, bonusDay: "2026-11-17", receipts: ["paid"])
        XCTAssertEqual(900, p.points)
        XCTAssertEqual(10, p.completed)
        for old in 0..<65 { XCTAssertTrue(p.done(SpudJourney.legacyStep(old)), "old \(old)") }
        XCTAssertFalse(p.done(10))
        let next = p.finish("new", 10, true, "2026-11-17")
        XCTAssertEqual(16, next.completed)
        XCTAssertEqual(940, next.points)
        XCTAssertEqual(next, next.finish("duplicate", 10, true, "2026-11-18"))
        let members = [Member("h", "miniko", "Alex"), Member("b", "mia", "Mia", bot: true), Member("c", "coach67", "Coach", bot: true)]
        let e = try AmuduEngine(members: members, config: GameConfig(participants: 3), seed: 44)
        var n = AmuduCodec.checkpoint(e)
        var config = AmuduCodec.config(try GameConfig(participants: 3, challengeStep: 28))
        config.removeValue(forKey: "curriculumRevision")
        n["config"] = config
        XCTAssertEqual("call", try AmuduCodec.create(n).practice?.stage.id)
    }

    func testEnvironmentVariantsAreInterspersedWithClearDefaults() throws {
        XCTAssertEqual(40, SpudJourney.stages.count)
        XCTAssertEqual(40, Set(SpudJourney.stages.map { $0.id }).count)
        for i in SpudJourney.stages.indices {
            let c = PracticeCurriculum.conditions(i)
            XCTAssertEqual(.foam, PracticeCurriculum.ball(i, "AUTO"))
            XCTAssertEqual(PracticeCurriculum.balls(i).count, Set(PracticeCurriculum.balls(i)).count)
            if c != .calm {
                XCTAssertGreaterThan(i, 9)
                let config = try PracticeCurriculum.config(i, .easy, .foam, c, 2)
                XCTAssertEqual(c.daylight, config.daylight)
                XCTAssertEqual(c.wind, config.wind)
            }
        }
        let evening = try XCTUnwrap(SpudJourney.stages.firstIndex { $0.id == "tree_evening" })
        let night = try XCTUnwrap(SpudJourney.stages.firstIndex { $0.id == "tree_night" })
        XCTAssertEqual(.breezeEvening, PracticeCurriculum.conditions(evening))
        XCTAssertEqual(.windNight, PracticeCurriculum.conditions(night))
    }

    private func single(_ list: [BallShadow.Footprint]) throws -> BallShadow.Footprint {
        XCTAssertEqual(1, list.count)
        return try XCTUnwrap(list.first)
    }

    func testShadowRespectsAltitudeSizeLightAndBurst() throws {
        let b = Ball(V(14.0, 9.0), 1.2, V(1.0, 0.0), 0.0)
        let c = try GameConfig()
        let noon = try single(BallShadow.project(b, c, 0.0))
        let evening = try single(BallShadow.project(b, try c.copy(daylight: .evening), 0.0))
        XCTAssertGreaterThan((evening.center - b.position).length(), (noon.center - b.position).length())
        var raised = b
        raised.height = 5.0
        let high = try single(BallShadow.project(raised, c, 0.0))
        XCTAssertGreaterThan(high.softness, noon.softness)
        XCTAssertLessThan(high.opacity, noon.opacity)
        let small = try single(BallShadow.project(b, try c.copy(ball: .tennis), 0.0))
        let large = try single(BallShadow.project(b, try c.copy(ball: .beach), 0.0))
        XCTAssertGreaterThan(large.radiusX, small.radiusX)
        let night = BallShadow.project(b, try c.copy(daylight: .night), 0.0)
        XCTAssertEqual(2, night.count)
        XCTAssertTrue(night.allSatisfy { $0.opacity < noon.opacity })
        var burst = b
        burst.burst = true
        XCTAssertTrue(BallShadow.project(burst, c, 0.0).isEmpty)
    }

    func testBalloonWordingDoesNotChangeBallCopy() {
        XCTAssertEqual("The balloon hit you.", ProjectileText.apply("The ball hit you.", kind: .paint, language: "en"))
        XCTAssertEqual("הבלון פגע בכם", ProjectileText.apply("הכדור פגע בכם", kind: .paint, language: "he"))
        for kind in BallKind.allCases where kind != .paint {
            XCTAssertEqual("The ball missed.", ProjectileText.apply("The ball missed.", kind: kind, language: "en"))
        }
    }
}
