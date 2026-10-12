import XCTest
@testable import MinikAmudu

/// Port of Android `core/RevisionTest.kt`.
final class RevisionTests: XCTestCase {
    private func world(_ config: GameConfig? = nil, seed: Int64 = 11) throws -> AmuduEngine {
        let cfg = try config ?? GameConfig(participants: 3)
        let members = [Member("a", "miniko", "Alex"), Member("b", "gaya", "Gaya"), Member("c", "flare", "Flare")]
        return try AmuduEngine(members: members, config: cfg, seed: seed)
    }

    private func tick(_ e: AmuduEngine, _ seconds: Double) {
        let steps = Int(seconds * 120)
        for _ in 0..<steps { e.tick(1.0 / 120) }
    }

    private func retrieve(_ e: AmuduEngine) {
        e.phase = .retrieve
        e.called = "b"
        e.actor("b")!.position = V(5, 6)
        e.actor("a")!.position = V(11, 6)
        e.actor("c")!.position = V(13, 13)
        e.ball = Ball(V(5, 6), 0.23, V.zero, 0)
        XCTAssertTrue(e.command("b", "pickup", .catchBall))
    }

    func testRequiredDefaultsAndStarTable() throws {
        let c = try GameConfig()
        XCTAssertEqual(0, c.turns)
        XCTAssertEqual(10, try GameConfig(participants: 10).participants)
        XCTAssertEqual(0.7, c.catchWindow)
        XCTAssertEqual(.noon, c.daylight)
        XCTAssertEqual(Wind.none, c.wind)
        XCTAssertEqual(.standard, c.throwMode)
        let expected = [Skills(1, 3, 3, 1), Skills(2, 2, 3, 2), Skills(5, 5, 5, 4), Skills(4, 5, 5, 5), Skills(5, 5, 5, 5), Skills(5, 3, 4, 5),
                        Skills(4, 3, 2, 4), Skills(3, 4, 5, 4), Skills(4, 3, 5, 5), Skills(4, 5, 1, 4), Skills(2, 3, 4, 4)]
        XCTAssertEqual(expected, AmuduCharacters.all.map { $0.qualities })
        XCTAssertEqual("ברק", AmuduCharacters.get("flare").he)
        XCTAssertEqual("המאמן", AmuduCharacters.get("coach67").he)
        XCTAssertEqual("Coach", AmuduCharacters.get("coach67").en)
        XCTAssertEqual("מושיק", AmuduCharacters.get("moshiko").he)
    }

    func testRejectsElevenPlayers() {
        XCTAssertThrowsError(try GameConfig(participants: 11))
    }

    func testDirectThrowDoesNotFreezeOrSpeak() throws {
        let e = try world()
        retrieve(e)
        let p = e.actor("b")!.position
        XCTAssertTrue(e.command("c", "run", .move(V(-1, 0))))
        XCTAssertFalse(e.command("b", "move", .move(V(1, 0))))
        XCTAssertTrue(e.command("b", "aim", .aim(V(1, 0))))
        XCTAssertTrue(e.command("b", "throw", .throwBall(power: 0.65)))
        XCTAssertEqual(.flight, e.phase)
        XCTAssertFalse(e.frozen)
        XCTAssertFalse(e.events.contains { $0.kind == "freeze" })
        tick(e, 0.1)
        XCTAssertEqual(p, e.actor("b")!.position)
        XCTAssertLessThan(e.actor("c")!.position.x, 13)
    }

    func testChosenShoutFreezesOnceAndLocksPickup() throws {
        let e = try world()
        retrieve(e)
        e.command("b", "shout", .shout)
        XCTAssertTrue(e.frozen)
        XCTAssertFalse(e.command("c", "run", .move(V(1, 0))))
        XCTAssertFalse(e.command("b", "run", .move(V(1, 0))))
        XCTAssertFalse(e.command("b", "again", .shout))
        XCTAssertEqual(1, e.events.filter { $0.kind == "freeze" }.count)
    }

    func testCatchStanceLocksFor700msAndCannotBeExtendedBySpam() throws {
        let e = try world()
        e.phase = .air
        e.called = "b"
        e.ball = Ball(V(1, 1), 15, V.zero, 0)
        e.command("b", "move", .move(V(1, 0)))
        tick(e, 0.1)
        let p = e.actor("b")!.position
        XCTAssertTrue(e.command("b", "catch", .catchBall))
        let deadline = e.actor("b")!.catchUntil
        for i in 0..<5 {
            XCTAssertFalse(e.command("b", "catch\(i)", .catchBall))
            e.command("b", "m\(i)", .move(V(1, 0)))
            tick(e, 0.1)
        }
        XCTAssertEqual(deadline, e.actor("b")!.catchUntil)
        XCTAssertEqual(p, e.actor("b")!.position)
        tick(e, 0.21)
        XCTAssertTrue(e.command("b", "resume", .move(V(1, 0))))
        tick(e, 0.05)
        XCTAssertGreaterThan(e.actor("b")!.position.x, p.x)
    }

    func testCatchingWithoutTapNeverAttachesBall() throws {
        let e = try world()
        e.phase = .flight
        e.thrower = "a"
        e.called = "a"
        e.actor("a")!.position = V(3, 8)
        e.actor("b")!.position = V(5, 8)
        e.actor("c")!.position = V(13, 13)
        e.ball = Ball(V(4.7, 8), 1.1, V(9, 0), 0)
        tick(e, 0.03)
        XCTAssertEqual(1, e.actor("b")!.penalties)
        XCTAssertNil(e.ball.holder)
        XCTAssertLessThan(e.ball.velocity.x, 0)
        XCTAssertFalse(e.events.contains { $0.kind == "catch" })
        tick(e, 0.5)
        XCTAssertEqual(1, e.actor("b")!.penalties)
    }

    func testCatchAwardsThrowerAndNotTarget() throws {
        let e = try world()
        e.phase = .flight
        e.thrower = "a"
        e.called = "a"
        e.actor("b")!.position = V(5, 8)
        e.actor("a")!.position = V(2, 8)
        e.actor("c")!.position = V(14, 14)
        e.ball = Ball(V(4.3, 8), 1.2, V(8, 0), 0)
        e.command("b", "catch", .catchBall)
        tick(e, 0.08)
        XCTAssertEqual("b", e.ball.holder)
        XCTAssertEqual(1, e.actor("a")!.penalties)
        XCTAssertEqual(0, e.actor("b")!.penalties)
    }

    func testSuccessfulAirCatchPreservesFarPositions() throws {
        let e = try world()
        e.phase = .air
        e.called = "b"
        e.actor("b")!.position = V(5, 8)
        e.actor("c")!.position = V(15, 15)
        e.ball = Ball(V(5, 8), 1.5, V.zero, -1)
        e.command("b", "catch", .catchBall)
        tick(e, 0.03)
        XCTAssertEqual(.resolve, e.phase)
        tick(e, 2.3)
        XCTAssertEqual(.circle, e.phase)
        XCTAssertEqual(V(15, 15), e.actor("c")!.position)
        XCTAssertEqual(V(5, 8), e.actor("b")!.position)
        XCTAssertFalse(e.circleFormation)
        XCTAssertTrue(e.command("b", "select", .select(target: "c")))
        XCTAssertTrue(e.command("b", "toss", .toss(power: 0.8, drift: 0)))
        XCTAssertEqual(e.config.width / 2, e.landing.x, accuracy: 0.001)
        XCTAssertEqual(e.config.depth / 2, e.landing.y, accuracy: 0.36)
    }

    func testGroundContactFailsStandardButEasyBounces() throws {
        for mode in ThrowMode.allCases {
            let e = try world(GameConfig(participants: 3, throwMode: mode))
            e.phase = .flight
            e.thrower = "a"
            e.called = "a"
            for (i, a) in e.actors.enumerated() { a.position = V(12, 3 + Double(i) * 3) }
            e.ball = Ball(V(2, 2), 0.26, V(4, 0), -2)
            tick(e, 0.05)
            if mode == .standard {
                XCTAssertEqual(.resolve, e.phase)
                XCTAssertEqual(1, e.actor("a")!.penalties)
            } else {
                XCTAssertEqual(.flight, e.phase)
                XCTAssertEqual(0, e.actor("a")!.penalties)
                XCTAssertGreaterThan(e.ball.bounces, 0)
            }
        }
    }

    func testStandardPowerHasLowUsefulAndOvershootingTrajectories() throws {
        let e = try world()
        let a = e.actors[0]
        let values = [0.1, 0.68, 1.0].map { p -> Double in
            let profile = e.throwProfile(a, p)
            let t = 4.5 / profile.speed
            return 1.17 + profile.vz * t - 0.5 * e.config.scene.gravity * t * t
        }
        XCTAssertLessThan(values[0], 0.23)
        XCTAssertTrue(values[1] >= 0.5 && values[1] <= 1.75)
        XCTAssertGreaterThan(values[2], 1.75)
    }

    func testWindChangesAirborneFlightInOneConsistentDirection() throws {
        var xs: [Double] = []
        for w in Wind.allCases {
            let e = try world(GameConfig(participants: 3, wind: w), seed: 12)
            e.command("a", "s", .select(target: "b"))
            e.command("a", "t", .toss(power: 0.9, drift: 0))
            tick(e, 1.0)
            xs.append(e.ball.position.x)
        }
        XCTAssertGreaterThan(xs[1], xs[0] + 0.15)
        XCTAssertGreaterThan(xs[2], xs[1] + 0.4)
    }

    func testReplacementThenSingleWordSuffixesExcludeOriginal() throws {
        let e = try world()
        e.phase = .huddle
        e.huddleTarget = "a"
        XCTAssertFalse(e.propose("b", "dancing frog"))
        XCTAssertTrue(e.propose("b", "frog"))
        XCTAssertTrue(e.applyHuddle("frog"))
        XCTAssertEqual("frog", e.actor("a")!.fullName())
        e.phase = .huddle
        e.huddleTarget = "a"
        e.applyHuddle("sparkly")
        XCTAssertEqual("frog sparkly", e.actor("a")!.fullName())
        e.circle("b")
        XCTAssertFalse(e.command("b", "bad", .select(target: "a", typedName: "Alex frog sparkly")))
        XCTAssertEqual(1, e.actor("b")!.penalties)
        tick(e, 5.4)
        XCTAssertTrue(e.command("b", "good", .select(target: "a", typedName: "frog sparkly")))
    }

    func testInfiniteLimitSurvivesFiftyTurnsButFiniteStops() throws {
        for limit in [0, 50] {
            let e = try world(GameConfig(participants: 3, turns: limit))
            e.turn = 50
            e.phase = .resolve
            e.phaseAt = e.time
            e.nextThrower = "a"
            tick(e, 2.4)
            if limit == 0 {
                XCTAssertNil(e.result)
                XCTAssertEqual(51, e.turn)
            } else {
                XCTAssertNotNil(e.result)
            }
        }
    }

    func testRosterExcludesAllHumanAvatarsAndDuplicateBots() throws {
        let humans = [Member("a", "flare", "Alex"), Member("b", "flare", "Sam")]
        let ids = AmuduCharacters.availableBots(humans: humans, requested: ["flare", "gaya", "gaya"], fillTo: 8)
        XCTAssertEqual(8, ids.count)
        XCTAssertFalse(ids.contains("flare"))
        XCTAssertEqual(ids.count, Set(ids).count)
        let members = humans + ids.enumerated().map { Member("bot\($0.offset)", $0.element, AmuduCharacters.get($0.element).en, bot: true) }
        XCTAssertEqual(10, try AmuduEngine(members: members, config: GameConfig(participants: 10)).actors.count)
    }

    func testBotBoundaryStopsGaitAndFacesBall() throws {
        let members = [Member("a", "miniko", "Alex"), Member("b", "gaya", "Gaya", bot: true)]
        let e = try AmuduEngine(members: members, config: GameConfig(participants: 2))
        e.phase = .shout
        e.called = "a"
        e.thrower = "a"
        e.ball.holder = "a"
        e.actor("a")!.position = V(8, 8)
        e.actor("b")!.position = V(0.6, 0.6)
        tick(e, 0.2)
        let b = e.actor("b")!
        XCTAssertEqual(V.zero, b.move)
        XCTAssertFalse(b.actuallyMoving)
        XCTAssertEqual(0.0, b.gait, accuracy: 0.001)
        XCTAssertTrue(b.facing.x > 0 && b.facing.y > 0)
    }

    func testStarsProduceMeasuredCatchRatesAndRunningPenalty() {
        var counts: [Int] = []
        for stars in 1...5 {
            var successes = 0
            for seed in 0..<3000 {
                var random = KotlinRandom(seed: Int64(seed))
                if random.nextDouble() < Skills(1, 1, 1, stars).catchProbability(wasRunning: false) { successes += 1 }
            }
            counts.append(successes)
            XCTAssertEqual(Double(stars) / 5.0, Double(successes) / 3000.0, accuracy: 0.04)
        }
        XCTAssertEqual(3000, counts.last)
        XCTAssertTrue(zip(counts, counts.dropFirst()).allSatisfy { $0.0 < $0.1 })
        XCTAssertEqual(0.4, Skills(4, 4, 4, 4).catchProbability(wasRunning: true))
    }

    func testActualPreparedFiveStarBotCatchesEveryValidContact() throws {
        for seed in 0..<100 {
            let members = [Member("a", "miniko", "Alex"), Member("b", "gaya", "Gaya", bot: true)]
            let e = try AmuduEngine(members: members, config: GameConfig(participants: 2), seed: Int64(seed))
            e.phase = .flight
            e.thrower = "a"
            e.called = "a"
            e.actor("b")!.position = V(5, 8)
            e.actor("a")!.position = V(2, 8)
            e.ball = Ball(V(4.6, 8), 1.2, V(8, 0), 0)
            e.command("b", "c", .catchBall)
            tick(e, 0.02)
            XCTAssertEqual("b", e.ball.holder, "seed \(seed)")
        }
    }

    func testSnapshotRetainsSettingsLockStanceAndNoDuplicateResult() throws {
        let e = try world(GameConfig(participants: 3, daylight: .night, throwMode: .easy, wind: .fast))
        retrieve(e)
        e.command("b", "s", .shout)
        let r = try AmuduCodec.create(AmuduCodec.checkpoint(e))
        XCTAssertEqual(e.config, r.config)
        XCTAssertEqual(e.pickupAnchor, r.pickupAnchor)
        XCTAssertTrue(r.frozen)
        XCTAssertFalse(r.command("b", "m", .move(V(1, 0))))
        r.finish()
        let result = r.result
        r.finish()
        XCTAssertEqual(result, r.result)
        XCTAssertEqual(1, r.events.filter { $0.kind == "finish" }.count)
    }

    func testRunningHumanCatchHasASettlingDelayAndSmallerReach() throws {
        let e = try world()
        e.phase = .air
        e.called = "b"
        e.ball = Ball(V(1, 1), 20, V.zero, 0)
        e.command("b", "move", .move(V(1, 0)))
        tick(e, 0.1)
        e.command("b", "catch", .catchBall)
        XCTAssertEqual(e.time + 0.1, e.actor("b")!.catchReadyAt, accuracy: 0.0001)
        XCTAssertEqual(0.82, e.actor("b")!.catchReach)
    }

    func testSettledBallDoesNotCreateRepeatedGroundContacts() throws {
        let e = try world()
        e.phase = .retrieve
        e.called = "b"
        e.ball = Ball(V(1, 1), 0.23, V.zero, 0, nil, bounces: 4)
        tick(e, 3.0)
        XCTAssertEqual(4, e.ball.bounces)
        XCTAssertEqual(0.23, e.ball.height)
        XCTAssertFalse(e.events.contains { $0.kind == "bounce" })
    }
}
