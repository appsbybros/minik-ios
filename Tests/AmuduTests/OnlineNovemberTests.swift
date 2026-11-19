import XCTest
@testable import MinikAmudu

/// Kotlin `(i * 1000.0 / 120).roundToLong()` added to a millisecond base.
private func frameAt(_ base: Int64, _ i: Int) -> Int64 {
    return base + Int64((Double(i) * 1000.0 / 120).rounded())
}

/// Port of Android `LeagueStandingsTest.kt`.
final class LeagueStandingsTests: XCTestCase {
    func testAbsentMembersStayUnchangedAndTiesUseFewerPenalties() {
        let roster = [Member("a", "mia", "A"), Member("b", "kyra", "B"), Member("c", "flare", "C")]
        var members: Node = [:]
        for m in roster { members[m.id] = AmuduCodec.member(m) }
        let participants: Node = ["a": ["won": true, "penalties": 2, "nicknames": ["frog"]] as Node, "b": ["won": true, "penalties": 1] as Node]
        let data: Node = ["members": members, "rounds": ["one": ["participants": participants] as Node] as Node]
        let rows = LeagueStandings.rows(data)
        XCTAssertEqual(["b", "a", "c"], rows.map { $0.member.id })
        XCTAssertEqual(3, rows[0].points)
        XCTAssertEqual(1, rows[1].games)
        XCTAssertEqual(0, rows[2].games)
        XCTAssertEqual(["frog"], rows[1].nicknames)
    }

    func testLowGravityRaisesTheSameJump() throws {
        func peak(_ scene: ArenaScene) throws -> Double {
            let e = try AmuduEngine(members: [Member("a", "miniko", "A"), Member("b", "kyra", "B")], config: GameConfig(scene: scene, participants: 2))
            e.phase = .air
            e.called = "b"
            e.ball = Ball(V(2.0, 2.0), 10.0, V(0.0, 0.0), 0.0)
            XCTAssertTrue(e.command("a", "jump", .jump))
            var height = 0.0
            for _ in 0..<120 {
                e.tick(1.0 / 120)
                height = max(height, e.actor("a")!.jumpHeight)
            }
            return height
        }
        XCTAssertTrue(try peak(.andromeda) > peak(.park) * 1.4)
    }
}

/// Port of Android `MotionStateTest.kt`.
final class MotionStateTests: XCTestCase {
    private func game(_ scene: ArenaScene = .beach, _ wind: Wind = Wind.none) throws -> AmuduEngine {
        return try AmuduEngine(members: [Member("a", "minik", "A"), Member("b", "mia", "B")],
                               config: GameConfig(scene: scene, participants: 2, wind: wind), seed: 17)
    }

    func testFlightUsesOneAnchorThroughLongGapsWithExactGravityAndWind() throws {
        for scene in ArenaScene.allCases {
            for wind in Wind.allCases {
                let e = try game(scene, wind)
                e.phase = .air
                e.called = "b"
                e.ball = Ball(V(7.0, 7.0), 15.0, V(0.8, 0.3), 6.0, nil, bounces: 0, flightId: "flight", launchAt: 0.0)
                let pub = MotionPublication()
                let anchor = pub.encode(e, AmuduCodec.shared(e), true)
                let b0 = anchor["ball"]
                let guest = try AmuduCodec.create(anchor)
                let p = SnapshotPlayback()
                p.accept(guest, anchor, 1000, 0.0)
                for i in 1...120 {
                    e.time += 1.0 / 120
                    BallFlight.advance(&e.ball, 1.0 / 120, e.config.scene.gravity, e.windVector)
                    let wire = pub.encode(e, AmuduCodec.shared(e), true)
                    XCTAssertTrue(NodeEquality.same(b0, wire["ball"]), "Uninterrupted flight must not publish ball coordinates again")
                    p.render(guest, frameAt(1000, i))
                    XCTAssertEqual(e.ball.position.x, guest.ball.position.x, accuracy: 0.003)
                    XCTAssertEqual(e.ball.height, guest.ball.height, accuracy: 0.012)
                }
                XCTAssertEqual(0, guest.actors.reduce(0) { $0 + $1.penalties })
                XCTAssertNil(guest.result)
            }
        }
    }

    func testIncomingPacketsDoNotAddTransitDistanceToActors() throws {
        let e = try game()
        e.phase = .air
        e.called = "b"
        e.ball = Ball(V(7.0, 7.0), 12.0, V(0.3, 0.0), 2.0, nil, bounces: 0, flightId: "f", launchAt: 0.0)
        let a = e.actor("a")!
        a.position = V(3.0, 5.0)
        a.move = V(1.0, 0.0)
        a.actuallyMoving = true
        let p = SnapshotPlayback()
        let pub = MotionPublication()
        let guest = try AmuduCodec.create(AmuduCodec.shared(e))
        p.accept(guest, pub.encode(e, AmuduCodec.shared(e), true), 1000, 0.12)
        p.render(guest, 1000)
        let speed = e.config.moveSpeed * e.config.scene.run
        var previous = guest.actor("a")!.position.x
        for i in 1...120 {
            e.time = Double(i) / 120.0
            a.position = V(3.0 + speed * e.time, 5.0)
            a.gait = e.time * 9
            let at = frameAt(1000, i)
            if i % 12 == 0 {
                let before = guest.actor("a")!.position.x
                p.accept(guest, pub.encode(e, AmuduCodec.shared(e), true), at, 0.12)
                p.render(guest, at)
                XCTAssertTrue(abs(guest.actor("a")!.position.x - before) < speed * 0.02)
            } else {
                p.render(guest, at)
            }
            let now = guest.actor("a")!.position.x
            XCTAssertTrue(now >= previous - 0.003, "No backwards correction kicks")
            XCTAssertTrue(now - previous < speed * 0.02)
            previous = now
        }
    }

    func testSnapshotAndCheckpointRestoreMotionAtCurrentTimeAndLegacyRemainsCompatible() throws {
        let e = try game()
        e.phase = .air
        e.called = "b"
        e.ball = Ball(V(7.0, 7.0), 15.0, V(1.0, 0.0), 2.0, nil, bounces: 0, flightId: "f", launchAt: 0.0)
        let pub = MotionPublication()
        _ = pub.encode(e, AmuduCodec.shared(e), true)
        e.time = 0.5
        BallFlight.advance(&e.ball, 0.5, e.config.scene.gravity, e.windVector)
        let encoded = pub.encode(e, AmuduCodec.shared(e), true)
        let restored = try AmuduCodec.create(AmuduCodec.checkpoint(e, shared: encoded))
        XCTAssertEqual(e.ball.height, restored.ball.height, accuracy: 1e-8)
        XCTAssertEqual(e.ball.position, restored.ball.position)
        let legacy = pub.encode(e, AmuduCodec.shared(e), false)
        XCTAssertNil(legacy["motionProtocol"])
        XCTAssertEqual(e.ball.position, try AmuduCodec.create(legacy).ball.position)
    }

    func testCatchBouncePauseAndNewFlightReplaceTheOldAnchor() throws {
        let e = try game()
        let pub = MotionPublication()
        e.phase = .air
        e.ball = Ball(V(7.0, 7.0), 4.0, V(0.8, 0.3), -2.0, nil, bounces: 0, flightId: "f", launchAt: 0.0)
        let old = pub.encode(e, AmuduCodec.shared(e), true)["ball"]
        e.ball.vz = 2.0
        e.ball.bounces += 1
        e.time += 0.2
        let bounced = pub.encode(e, AmuduCodec.shared(e), true)
        XCTAssertFalse(NodeEquality.same(old, bounced["ball"]))
        e.ball.holder = "b"
        let caught = pub.encode(e, AmuduCodec.shared(e), true)
        XCTAssertEqual("b", AmuduCodec.node(caught["ball"]).str("holder"))
        e.sharedPause = true
        let pause = pub.encode(e, AmuduCodec.shared(e), true)
        let g = try AmuduCodec.create(pause)
        let p = SnapshotPlayback()
        p.accept(g, pause, 1000, 0.1)
        p.render(g, 3000)
        XCTAssertEqual(e.time, g.time, accuracy: 0.0)
    }

    func testBeachMinimumApexIsTenPercentHigherAndFullPowerUnchanged() throws {
        func toss(_ s: ArenaScene, _ power: Double) throws -> AmuduEngine {
            let e = try game(s)
            e.circle("a", regroup: false)
            _ = e.command("a", "s", .select(target: "b"))
            _ = e.command("a", "t", .toss(power: power, drift: 0.0))
            return e
        }
        func apex(_ e: AmuduEngine) -> Double {
            return e.ball.height + e.ball.vz * e.ball.vz / (2 * e.config.scene.gravity)
        }
        let beach = try toss(.beach, 0.0)
        let park = try toss(.park, 0.0)
        XCTAssertEqual(apex(park) * 1.10, apex(beach), accuracy: 1e-9)
        for scene in [ArenaScene.park, ArenaScene.beach] {
            let oldVz = (9.8 * 4 / 2 - 1.2 / 4) * (0.75).squareRoot()
            XCTAssertEqual((1.2 + oldVz * oldVz / (2 * scene.gravity)) * 0.9, apex(try toss(scene, 1.0)), accuracy: 1e-8)
        }
    }
}

/// Port of Android `SnapshotWireTest.kt`.
final class SnapshotWireTests: XCTestCase {
    func testPresentationCompressionDoesNotChangeAuthoritativeCheckpointOrDiscreteState() {
        let raw: Node = ["position": [12.123456789, 3.987654321], "event": Int64(4), "publishedAt": Int64(1794509240176),
                         "holder": "user", "finished": false]
        let presented = SnapshotWire.presentation(raw)
        XCTAssertEqual([12.1235, 3.9877], presented["position"] as? [Double])
        XCTAssertEqual([12.123456789, 3.987654321], raw["position"] as? [Double])
        for key in ["event", "publishedAt", "holder", "finished"] {
            XCTAssertTrue(NodeEquality.same(raw[key], presented[key]), key)
        }
        XCTAssertEqual(Int64(1794509240176), presented["publishedAt"] as? Int64)
        XCTAssertTrue(AmuduCodec.describe(presented).count < AmuduCodec.describe(raw).count)
    }
}

/// Port of Android `NovemberNetworkRegressionTest.kt`.
final class NovemberNetworkRegressionTests: XCTestCase {
    private func game() throws -> AmuduEngine {
        return try AmuduEngine(members: [Member("a", "minik", "A"), Member("b", "mia", "B")], config: GameConfig(participants: 2), seed: 17)
    }

    func testGuestsKeepBallMovingDuringDelayedSnapshotsWithoutAwardingPoints() throws {
        let e = try game()
        e.phase = .air
        e.called = "b"
        e.ball = Ball(V(8.0, 8.0), 5.0, V(1.0, 0.0), 2.0, nil, bounces: 0, flightId: "flight", launchAt: 0.0)
        let receiver = try AmuduCodec.create(AmuduCodec.shared(e))
        let playback = SnapshotPlayback()
        playback.accept(receiver, AmuduCodec.shared(e), 1000, 0.0)
        playback.render(receiver, 1120)
        let first = receiver.ball.position.x
        playback.render(receiver, 1280)
        XCTAssertTrue(receiver.ball.position.x > first + 0.1)
        XCTAssertEqual(0, receiver.actors.reduce(0) { $0 + $1.penalties })
        XCTAssertNil(receiver.result)
        playback.render(receiver, 1600)
        XCTAssertTrue(receiver.ball.position.x > 8.55, "Known flight must not freeze at 400ms")
    }

    func testGroundedPredictionDoesNotShootBelowFloorOrAwardAnInventedCatch() throws {
        let e = try game()
        e.phase = .retrieve
        e.called = "b"
        e.ball = Ball(V(8.0, 8.0), 0.3, V(0.0, 0.0), -3.0)
        let play = SnapshotPlayback()
        play.accept(e, AmuduCodec.shared(e), 100, 0.0)
        play.render(e, 400)
        XCTAssertTrue(e.ball.height >= 0.23)
        XCTAssertNil(e.ball.holder)
    }

    func testDeltaDoesNotResendHistoryOrRosterAndPreservesDeletions() throws {
        let e = try game()
        for i in 0..<1000 { _ = e.consumed.insert("event-\(i)") }
        let before: Node = ["public": AmuduCodec.shared(e), "checkpoint": AmuduCodec.checkpoint(e)]
        e.time += 0.1
        _ = e.consumed.insert("next")
        e.selected = "b"
        let after: Node = ["public": AmuduCodec.shared(e), "checkpoint": AmuduCodec.checkpoint(e)]
        let patch = SnapshotDelta.between(before, after)
        XCTAssertEqual(true, AmuduCodec.boolean(patch["checkpoint/consumed/next"]))
        XCTAssertFalse(patch.keys.contains { $0.contains("member") })
        XCTAssertTrue(patch.count < 10)
        let removal = SnapshotDelta.between(["x": 4], [:])
        XCTAssertNotNil(removal["x"])
        XCTAssertTrue(AmuduCodec.isNull(removal["x"]))
    }

    func testBouncedNameCallCanBeCaughtAndFarGroundPickupIsForgiving() throws {
        let e = try game()
        e.phase = .retrieve
        e.called = "b"
        let a = e.actor("b")!
        a.position = V(8.0, 8.0)
        e.ball = Ball(a.position, 1.5, V(0.0, 0.0), -1.0, nil, bounces: 1)
        XCTAssertTrue(e.command("b", "catch", .catchBall))
        a.catchRoll = 0.0
        e.tick(0.02)
        XCTAssertEqual("b", e.ball.holder)
        XCTAssertEqual(0, a.penalties)
        let ground = try game()
        ground.phase = .retrieve
        ground.called = "b"
        ground.ball = Ball(ground.actor("b")!.position + V(1.0, 0.0), 0.23, V(0.0, 0.0), 0.0)
        XCTAssertTrue(ground.command("b", "pickup", .catchBall))
        XCTAssertEqual("b", ground.ball.holder)
    }

    func testOnePersonMayOfferDistinctWordsAndDuplicateWordsNeverSplitVotes() throws {
        let e = try game()
        e.phase = .huddle
        e.huddleTarget = "b"
        XCTAssertTrue(e.propose("a", "Sun"))
        XCTAssertEqual("a", e.votes["a"])
        XCTAssertFalse(e.propose("a", "SUN"))
        XCTAssertTrue(e.propose("a", "Moon"))
        XCTAssertEqual(2, e.suggestions.count)
        XCTAssertTrue(e.vote("a", "a"))
        XCTAssertEqual("a", e.votes["a"])
    }

    func testUpwardReboundIsCatchableBeforeItsApex() throws {
        let e = try game()
        e.phase = .retrieve
        e.called = "b"
        let a = e.actor("b")!
        e.ball = Ball(a.position, 1.6, V(0.0, 0.0), 2.0, nil, bounces: 1)
        XCTAssertTrue(e.command("b", "rebound", .catchBall))
        a.catchRoll = 0.0
        e.tick(0.02)
        XCTAssertEqual("b", e.ball.holder)
        XCTAssertEqual(Phase.shout, e.phase)
    }

    func testEarthMaximumAndSpaceMaximumStayCappedWhileGentleEarthCallsAreLowered() throws {
        func vz(_ scene: ArenaScene, _ power: Double) throws -> Double {
            let e = try AmuduEngine(members: [Member("a", "minik", "A"), Member("b", "mia", "B")],
                                    config: GameConfig(scene: scene, participants: 2), seed: 17)
            let who = e.thrower
            let other = e.actors.first { $0.member.id != who }!.member.id
            XCTAssertTrue(e.command(who, "choose", .select(target: other)))
            XCTAssertTrue(e.command(who, "toss", .toss(power: power, drift: 0.0)))
            return e.ball.vz
        }
        let formerMax = 9.8 * 4.0 / 2 - 1.2 / 4.0
        let parkMax = try vz(.park, 1.0)
        XCTAssertEqual((1.2 + formerMax * formerMax * 0.75 / (2 * 9.8)) * 0.90, 1.2 + parkMax * parkMax / (2 * 9.8), accuracy: 0.0001)
        XCTAssertEqual((2 * 9.8 * (2.8 * 1.15 * 1.20 * 1.10 * 1.15 - 1.2)).squareRoot(), try vz(.park, 0.0), accuracy: 0.0001)
        let spaceMax = try vz(.andromeda, 1.0)
        XCTAssertEqual((1.2 + formerMax * formerMax / (2 * 4.8)) * 0.90, 1.2 + spaceMax * spaceMax / (2 * 4.8), accuracy: 0.0001)
    }
}
