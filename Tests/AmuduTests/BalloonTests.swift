import XCTest
@testable import MinikAmudu

/// Port of Android `amudu/BalloonCadenceTest.kt`.
final class BalloonCadenceTests: XCTestCase {
    func testFullCyclesCountEveryStrengthButOnlyArmAfterTheExtraThrows() {
        for seed in Int64(0)...Int64(50) {
            let c = BalloonBurstCycle(seed)
            for _ in 0..<5 {
                for i in 0..<10 { XCTAssertFalse(c.released(i % 2 == 0)) }
                XCTAssertTrue((1...3).contains(c.extra))
                for _ in 0..<c.extra { XCTAssertFalse(c.released(true)) }
                for _ in 0..<4 { XCTAssertFalse(c.released(false)) }
                XCTAssertTrue(c.released(true))
                XCTAssertFalse(c.released(false))
                XCTAssertTrue(c.released(true))
                c.burst()
                XCTAssertEqual(0, c.`throws`)
            }
        }
    }

    private func game() throws -> AmuduEngine {
        return try AmuduEngine(members: [Member("h", "miniko", "Alex"), Member("v", "kyra", "Kyra")],
                               config: GameConfig(ball: .paint, participants: 2, width: 28.0, depth: 18.0, wind: .none, actionSeconds: 0),
                               seed: 12)
    }

    func testNormalBodyContactsBurstWithoutResettingCatchCooldown() throws {
        let e = try game()
        e.actors[0].position = V(3.0, 9.0)
        e.actors[1].position = V(13.0, 9.0)
        e.phase = .aim
        e.thrower = "h"
        e.ball = Ball(V(3.0, 9.0), 1.2, V(0.0, 0.0), 0.0, "h")
        e.command("h", "throw", .pointThrow(point: V(13.0, 9.0), height: 1.1))
        for _ in 0..<150 { e.tick(0.01) }
        XCTAssertTrue(e.ball.burst)
        XCTAssertEqual(1, e.actors[1].penalties)
        XCTAssertEqual(1, e.actors[1].paintHits.count)
        XCTAssertEqual(1, e.attackBursts.`throws`)
        for _ in 0..<13 { _ = e.callBursts.released(false) }
        let r = try AmuduCodec.create(AmuduCodec.checkpoint(e))
        XCTAssertEqual(e.callBursts.`throws`, r.callBursts.`throws`)
        XCTAssertEqual(e.callBursts.extra, r.callBursts.extra)
        XCTAssertEqual(e.attackBursts.`throws`, r.attackBursts.`throws`)
        XCTAssertTrue(r.callBursts.released(true))
        XCTAssertFalse(r.attackBursts.released(true))
    }

    func testCallBodyReboundsWithoutAnArmedBurst() throws {
        let e = try game()
        e.phase = .air
        e.circleFormation = false
        e.called = "v"
        e.actors[1].position = V(14.0, 9.0)
        e.actors[0].position = V(3.0, 3.0)
        e.ball = Ball(V(14.0, 9.0), 1.3, V(0.0, 0.0), -2.0, nil, bounces: 0, flightId: "call")
        e.tick(0.01)
        XCTAssertFalse(e.ball.burst)
        XCTAssertEqual(.retrieve, e.phase)
        XCTAssertEqual(0, e.actors[1].penalties)
    }

    func testMinimumAndMaximumApexAndDirectionArePhysical() throws {
        for scene in ArenaScene.allCases {
            for human in [false, true] {
                let old = (scene == .beach ? 3.08 : 2.8) * (human ? 1.15 : 1.0)
                let v = CallLob.velocity(scene, human, 0.0)
                XCTAssertEqual(old * 1.20 * 1.10 * 1.15, 1.2 + v * v / (2 * scene.gravity), accuracy: 1e-8)
                XCTAssertFalse(CallLob.high(scene, v))
                XCTAssertTrue(CallLob.high(scene, CallLob.velocity(scene, human, 1.0)))
            }
        }
        for d in [-1.0, -0.6, 0.6, 1.0] {
            let e = try game()
            e.thrower = "h"
            e.selected = "v"
            e.ball.holder = "h"
            XCTAssertTrue(e.command("h", "call", .toss(power: 0.0, drift: d)))
            let landing = e.landing - V(e.config.width / 2, e.config.depth / 2)
            XCTAssertEqual(d * (CircleFormation.RADIUS - 0.35) * 0.85, landing.x, accuracy: 1e-8)
            XCTAssertLessThanOrEqual(landing.length(), CircleFormation.RADIUS - 0.35 + 1e-8)
        }
    }

    func testRevisedBoundsReachEveryCallerReceiverAndBall() throws {
        for scene in ArenaScene.allCases {
            for ball in BallKind.allCases {
                for callerBot in [false, true] {
                    for receiverBot in [false, true] {
                        func launch(_ power: Double) throws -> AmuduEngine {
                            let members = [Member("a", "miniko", "Alex", bot: callerBot), Member("b", "mia", "Mia", bot: receiverBot)]
                            let config = try GameConfig(scene: scene, ball: ball, participants: 2, wind: .none, actionSeconds: 0)
                            let e = try AmuduEngine(members: members, config: config, seed: 31)
                            e.circle("a", regroup: false)
                            XCTAssertTrue(e.command("a", "select", .select(target: "b")))
                            XCTAssertTrue(e.command("a", "toss", .toss(power: power, drift: 0.0)))
                            return e
                        }
                        let e = try launch(0.0)
                        let old = (scene == .beach ? 3.08 : 2.8) * (receiverBot ? 1.0 : 1.15) * 1.20
                        XCTAssertEqual(old * 1.10 * 1.15, e.ball.height + e.ball.vz * e.ball.vz / (2 * scene.gravity), accuracy: 1e-8)
                        let remote = try AmuduCodec.create(AmuduCodec.shared(e))
                        XCTAssertEqual(e.ball.vz, remote.ball.vz)
                        XCTAssertEqual(CallLob.maximumVz(scene), try launch(1.0).ball.vz, accuracy: 1e-8)
                    }
                }
            }
        }
    }

    func testGroundPaintAreaIsBoundedAndMonotonic() {
        XCTAssertEqual(1.0, PaintBalloon.splashArea(0.0))
        XCTAssertEqual(1.25, PaintBalloon.splashArea(50.0))
        XCTAssertGreaterThan(PaintBalloon.splashArea(12.0), PaintBalloon.splashArea(5.0))
    }

    func testRemoteRenderingKeepsBurstStateAndAnchorChanges() throws {
        let host = try game()
        host.phase = .flight
        host.ball = Ball(V(5.0, 9.0), 1.2, V(8.0, 0.0), 2.0, nil, bounces: 0, flightId: "flight")
        let publication = MotionPublication()
        let guest = try AmuduCodec.create(AmuduCodec.shared(host))
        let playback = SnapshotPlayback()
        func frame(_ now: Int64) {
            let n = publication.encode(host, AmuduCodec.shared(host), true)
            playback.accept(guest, n, now, 0.0)
            playback.render(guest, now)
        }
        frame(1000)
        XCTAssertFalse(guest.ball.burstOnGround)
        XCTAssertFalse(guest.ball.burst)
        host.ball.burstOnGround = true
        frame(1100)
        XCTAssertTrue(guest.ball.burstOnGround)
        XCTAssertFalse(guest.ball.burst)
        host.ball.burst = true
        frame(1200)
        XCTAssertTrue(guest.ball.burst)
        XCTAssertTrue(guest.ball.burstOnGround)
        var next = host.ball
        next.flightId = "next"
        next.burst = false
        next.burstOnGround = false
        host.ball = next
        frame(1300)
        XCTAssertFalse(guest.ball.burst)
        XCTAssertFalse(guest.ball.burstOnGround)
    }
}

/// Port of Android `amudu/CatchBurstRulesTest.kt`.
final class CatchBurstRulesTests: XCTestCase {
    private func game(bot: Bool = false) throws -> AmuduEngine {
        let members = [Member("h", "miniko", "Thrower"), Member("v", "mia", "Receiver", bot: bot)]
        let config = try GameConfig(ball: .paint, participants: 2, width: 28.0, depth: 18.0, wind: .none, actionSeconds: 0, allowGroundHit: true)
        let e = try AmuduEngine(members: members, config: config, seed: 12)
        e.phase = .aim
        e.thrower = "h"
        e.called = "h"
        e.frozen = true
        e.actor("h")!.position = V(3.0, 9.0)
        e.actor("v")!.position = V(20.0, 9.0)
        e.ball = Ball(V(3.0, 9.0), 1.2, V(0.0, 0.0), 0.0, "h")
        return e
    }

    private func launch(_ e: AmuduEngine, armed: Bool, catching: Bool, miss: Bool = false) {
        if armed {
            e.attackBursts.`throws` = 13
            e.attackBursts.extra = 1
        }
        XCTAssertTrue(e.command("h", "throw", .pointThrow(point: V(20.0, miss ? 13.0 : 9.0), height: 1.1)))
        XCTAssertTrue(e.ball.burstOnGround)
        XCTAssertEqual(armed, e.ball.burstOnCatch)
        let v = e.actor("v")!
        v.nextThink = 1000.0
        v.facing = V(-1.0, 0.0)
        v.catchReadyAt = 0.0
        v.catchUntil = catching ? 10.0 : 0.0
        v.catchRoll = 0.0
        v.catchProbability = 1.0
        v.catchHeight = 1.1
        for _ in 0..<230 { e.tick(0.01) }
    }

    func testHitsAndMissesAlwaysBurstWithoutResettingRareCatchCounter() throws {
        for miss in [false, true] {
            for armed in [false, true] {
                let e = try game()
                launch(e, armed: armed, catching: false, miss: miss)
                XCTAssertTrue(e.ball.burst)
                XCTAssertEqual(armed ? 14 : 1, e.attackBursts.`throws`)
                XCTAssertEqual(miss ? 1 : 0, e.actor("h")!.penalties)
                XCTAssertEqual(miss ? 0 : 1, e.actor("v")!.penalties)
                XCTAssertEqual(miss ? 0 : 1, e.actor("v")!.paintHits.count)
                XCTAssertEqual(1, e.events.filter { $0.kind == "paint" }.count)
            }
        }
    }

    func testSuccessfulCatchOnlyBurstsWhenDueForHumanOrBot() throws {
        for bot in [false, true] {
            for armed in [false, true] {
                let e = try game(bot: bot)
                launch(e, armed: armed, catching: true)
                XCTAssertEqual(armed, e.ball.burst)
                XCTAssertEqual(armed ? 0 : 1, e.actor("h")!.penalties)
                XCTAssertEqual(armed ? 1 : 0, e.actor("v")!.penalties)
                XCTAssertEqual(armed ? 1 : 0, e.actor("v")!.paintHits.count)
                XCTAssertEqual(armed ? 0 : 1, e.attackBursts.`throws`)
                XCTAssertEqual(armed ? "catch_burst" : "tag_catch", e.infoCode)
                XCTAssertEqual(armed ? 1 : 0, e.events.filter { $0.kind == "paint" }.count)
            }
        }
    }

    func testLowPowerCatchKeepsDueCounterAndHostHandoverKeepsMeaning() throws {
        let e = try game()
        e.actor("v")!.position = V(8.0, 9.0)
        e.attackBursts.`throws` = 13
        e.attackBursts.extra = 1
        XCTAssertTrue(e.command("h", "low", .pointThrow(point: V(8.0, 9.0), height: 1.1)))
        XCTAssertTrue(e.ball.burstOnGround)
        XCTAssertFalse(e.ball.burstOnCatch)
        let restored = try AmuduCodec.create(AmuduCodec.checkpoint(e))
        XCTAssertEqual(14, restored.attackBursts.`throws`)
        XCTAssertFalse(restored.ball.burstOnCatch)
        e.ball.burstOnCatch = true
        let raw = MotionPublication().encode(e, AmuduCodec.shared(e), true)
        let guest = try AmuduCodec.create(raw)
        let playback = SnapshotPlayback()
        playback.accept(guest, raw, 1000, 0.0)
        playback.render(guest, 1100)
        XCTAssertTrue(guest.ball.burstOnCatch)
        XCTAssertTrue(guest.ball.burstOnGround)
    }
}

/// Port of Android `amudu/TargetBalloonTest.kt`.
final class TargetBalloonTests: XCTestCase {
    private func game(_ mode: ThrowMode = .easy, kind: BallKind = .foam, ground: Bool = false, rules: RuleSet = .spud) throws -> AmuduEngine {
        let config = try GameConfig(ball: kind, participants: 2, width: 28.0, depth: 18.0, throwMode: mode, rules: rules, actionSeconds: 0,
                                    allowGroundHit: ground)
        return try AmuduEngine(members: [Member("h", "miniko", "Alex"), Member("v", "kyra", "Kyra")], config: config, seed: 12)
    }

    private func ready(_ e: AmuduEngine) {
        e.actor("h")!.position = V(3.0, 9.0)
        e.actor("v")!.position = V(13.0, 9.0)
        e.phase = .aim
        e.thrower = "h"
        e.called = "h"
        e.ball = Ball(V(3.0, 9.0), 1.2, V(0.0, 0.0), 0.0, "h")
        e.frozen = true
    }

    func testExactPointHasChosenHeightAtShortAndLongRange() throws {
        for scene in ArenaScene.allCases {
            for kind in BallKind.allCases {
                for distance in [2.0, 10.0, 24.0] {
                    for z in [0.35, 1.15, 1.85, 2.8] {
                        let c = try GameConfig(scene: scene, ball: kind, width: 28.0, depth: 18.0)
                        let a = GameActor(member: Member("h", "minik", "Alex"), position: V(1.0, 9.0))
                        let point = V(1 + distance, 9.0)
                        let wind = V(0.4, 0.1)
                        var b = TargetThrow.launch(a, point, z, c, wind, "f", 0.0)
                        let t = min(max(max(distance - 0.52, 0.2) / (kind.speed * 1.22), 0.14), 1.32)
                        BallFlight.advance(&b, t, scene.gravity, wind)
                        XCTAssertLessThan((b.position - point).length(), 1e-8, "\(scene) \(kind) \(distance) \(z)")
                        XCTAssertEqual(z, b.height, accuracy: 1e-8)
                    }
                }
            }
        }
    }

    func testLiteralBodyAndSideAndAboveShotsHaveDifferentOutcomes() throws {
        for mode in [ThrowMode.easy, ThrowMode.target] {
            for side in [0.0, 2.0] {
                let e = try game(mode)
                ready(e)
                XCTAssertTrue(e.command("h", "p", .pointThrow(point: V(13.0, 9 + side), height: 1.1)))
                for _ in 0..<400 { e.tick(0.01) }
                XCTAssertEqual(side == 0.0 ? 1 : 0, e.actor("v")!.penalties)
                XCTAssertEqual(side == 0.0 ? 0 : 1, e.actor("h")!.penalties)
            }
        }
        let e = try game()
        ready(e)
        e.command("h", "p", .pointThrow(point: V(13.0, 9.0), height: 3.0))
        for _ in 0..<400 { e.tick(0.01) }
        XCTAssertEqual(0, e.actor("v")!.penalties)
    }

    func testPointThrowsCannotBypassProPossessionOrFiniteLimits() throws {
        let e = try game(.standard)
        ready(e)
        XCTAssertFalse(e.command("h", "p", .pointThrow(point: V(13.0, 9.0), height: 1.1)))
        let a = try game()
        ready(a)
        XCTAssertFalse(a.command("v", "p", .pointThrow(point: V(3.0, 9.0), height: 1.1)))
        XCTAssertFalse(a.command("h", "nan", .pointThrow(point: V(Double.nan, 9.0), height: 1.1)))
        let cmd = GameCommand.pointThrow(point: V(12.4, 8.6), height: 0.4)
        XCTAssertEqual(cmd, AmuduCodec.readCommand(AmuduCodec.command(cmd)))
    }

    func testGroundRuleAppliesRegardlessOfControlOrHumanBotRole() throws {
        for mode in ThrowMode.allCases {
            for allowed in [false, true] {
                let e = try game(mode, ground: allowed)
                ready(e)
                e.phase = .flight
                e.ball = Ball(V(7.0, 9.0), 0.24, V(2.0, 0.0), -2.0, nil, bounces: 0, flightId: "tag")
                e.tick(0.02)
                XCTAssertEqual(allowed ? Phase.flight : Phase.resolve, e.phase)
                XCTAssertEqual(allowed, try AmuduCodec.create(AmuduCodec.checkpoint(e)).config.allowGroundHit)
            }
        }
    }

    func testBalloonTagsPersistPaintAndGroundMissesBurstOnce() throws {
        let e = try game(kind: .paint)
        ready(e)
        e.attackBursts.`throws` = 20
        e.attackBursts.extra = 1
        e.command("h", "p", .pointThrow(point: V(13.0, 9.0), height: 1.1))
        e.ball.burstOnGround = true
        for _ in 0..<150 { e.tick(0.01) }
        XCTAssertTrue(e.ball.burst)
        XCTAssertEqual(1, e.actor("v")!.penalties)
        XCTAssertEqual([e.paintColor], e.actor("v")!.paintHits)
        let restored = try AmuduCodec.create(AmuduCodec.checkpoint(e))
        XCTAssertEqual(e.paintSplashes, restored.paintSplashes)
        XCTAssertEqual(e.actor("v")!.paintHits, restored.actor("v")!.paintHits)
        XCTAssertTrue(restored.ball.burst)
        let miss = try game(kind: .paint, ground: true)
        ready(miss)
        miss.attackBursts.`throws` = 20
        miss.attackBursts.extra = 1
        miss.command("h", "p", .pointThrow(point: V(13.0, 12.0), height: -0.4))
        miss.ball.burstOnGround = true
        for _ in 0..<100 { miss.tick(0.01) }
        XCTAssertTrue(miss.ball.burst)
        XCTAssertEqual(1, miss.actor("h")!.penalties)
        XCTAssertEqual(1, miss.paintSplashes.count)
    }

    func testHighCallBurstOnlyOccursWhenArmed() throws {
        for burst in [false, true] {
            let e = try game(kind: .paint)
            e.phase = .air
            e.called = "v"
            e.ball = Ball(V(14.0, 9.0), 0.24, V(0.4, 0.0), -2.0, nil, bounces: 0, flightId: "high", launchAt: 0.0, burstOnGround: burst)
            e.actor("v")!.position = V(1.0, 1.0)
            e.tick(0.02)
            XCTAssertEqual(burst, e.ball.burst)
            XCTAssertEqual(burst ? 1 : 0, e.actor("v")!.penalties)
            XCTAssertEqual(burst ? Phase.resolve : Phase.retrieve, e.phase)
        }
    }

    func testPaintCoverageAndRepeatedColoursFollowHitProportions() throws {
        let c = PaintBalloon.colors
        XCTAssertEqual(0.5, PaintBalloon.coverage(2, .spud))
        XCTAssertEqual(1.0, PaintBalloon.coverage(4, .spud))
        XCTAssertEqual(1.0, PaintBalloon.coverage(6, .nicknames))
        let hits = Array(c.prefix(7)) + [c[0]]
        let shares = PaintBalloon.shares(hits, .nicknames)
        XCTAssertEqual(0.25, try XCTUnwrap(shares[c[0]]), accuracy: 1e-9)
        XCTAssertEqual(1.0, shares.values.reduce(0.0, +), accuracy: 1e-9)
    }

    func testMovingDotGetsFasterAtRangeAndIncludesMissAndFootAreas() {
        func crosses(_ d: Double) -> Int {
            return (1...600).filter { TargetThrow.dot(Double($0 - 1) / 60.0, d).first * TargetThrow.dot(Double($0) / 60.0, d).first < 0 }.count
        }
        XCTAssertGreaterThan(crosses(24.0), crosses(3.0) * 2)
        let dots = (0...600).map { TargetThrow.dot(Double($0) / 60.0, 8.0) }
        XCTAssertTrue(dots.contains { abs($0.first) > 1.1 })
        XCTAssertTrue(dots.contains { $0.second < 0 })
        XCTAssertTrue(dots.contains { $0.second > 2.3 })
        XCTAssertTrue(dots.contains { $0.second >= 0.3 && $0.second <= 0.5 })
    }

    func testTennisAndBalloonHaveIntendedPhysicalOrder() {
        XCTAssertGreaterThan(BallKind.tennis.restitution, BallKind.beach.restitution)
        XCTAssertLessThan(BallKind.paint.restitution, BallKind.foam.restitution)
        XCTAssertTrue(BallKind.paint.speed >= BallKind.beach.speed && BallKind.paint.speed <= BallKind.tennis.speed)
        XCTAssertGreaterThan(BallContact.radius(.paint), BallContact.radius(.tennis))
        XCTAssertLessThan(BallContact.radius(.paint), BallContact.radius(.foam))
    }
}
