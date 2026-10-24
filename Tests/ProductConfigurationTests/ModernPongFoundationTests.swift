import XCTest
@testable import MinikPlus

/// Android MinikPingPong 739f2f8..29f5dc7 physics and pure logic. Expected numbers are golden vectors printed by the
/// compiled Android classes at 29f5dc7 (Kotlin 2.3.21, JBR); the rest are the Android unit tests (RankPromotionTest,
/// StandardRankTest, SpinServeRegressionTest, ServePresentationTest, PongArenaTest, NearPlayerProjectionTest,
/// LandscapeFloorTest), ported where they do not need the game screens.
final class ModernPongFoundationTests: XCTestCase {
    private let starter = MPTuning.values(.easy)          // Android Tuning.forDifficulty(STARTER)
    private let hard = MPTuning.values(.superHard)        // Android Tuning.forDifficulty(HARD)
    private var coach: MPTuning { MPRoster.find("coach67")!.profile.tuning(.easy, houseControls: true) } // controlTuning(STARTER)
    private func near(_ a: Double, _ b: Double, _ accuracy: Double = 1e-9, _ message: String = "", file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertEqual(a, b, accuracy: accuracy, message, file: file, line: line)
    }
    private func shot(_ s: MPShot, _ vx: Double, _ vy: Double, _ arc: Double, _ accuracy: Double = 1e-12, file: StaticString = #filePath, line: UInt = #line) {
        near(s.velocity.x, vx, accuracy, "vx", file: file, line: line); near(s.velocity.y, vy, accuracy, "vy", file: file, line: line)
        near(s.arc, arc, accuracy, "arc", file: file, line: line)
    }
    private func standardContact(_ point: MPPoint, _ velocity: MPPoint) -> MPContact {
        var c = MPContact(point: point, timing: 1, spatial: 1, velocity: velocity, direction: 0); c.standardSwipe = true; return c
    }

    // MARK: Difficulty and serve order (Android ModernEngine.Difficulty / Match, ServePresentationTest)

    func testEveryLevelOffersElevenPointsAndOnlyDeuceLevelsAlternateAtDeuce() {
        XCTAssertEqual(MPLevel.easy.targets, [3, 5, 7, 10, 11]); XCTAssertEqual(MPLevel.medium.targets, [3, 5, 7, 10, 11])
        XCTAssertEqual(MPLevel.beginner.targets, [3, 5, 7, 10, 11]); XCTAssertEqual(MPLevel.hard.targets, [3, 5, 7, 11])
        // Android Match(difficulty, 11): server before the first point and after each of 24 alternating points.
        let expected: [(MPLevel, String)] = [(.easy, "MMCCMMCCMMCCMMCCMMCCMMMMM"), (.medium, "CCMMCCMMCCMMCCMMCCMMCCCCC"),
            (.hard, "CCMMCCMMCCMMCCMMCCMMCMCMC"), (.superHard, "CCMMCCMMCCMMCCMMCCMMCMCMC"), (.beginner, "CCMMCCMMCCMMCCMMCCMMCCCCC")]
        for (level, servers) in expected {
            var score = MPScore(server: level == .easy ? .minik : .child), seen = [score.server]
            for i in 0..<24 { _ = score.award(i % 2 == 0 ? .child : .minik, level: level, target: level.target(11), first: nil); seen.append(score.server) }
            XCTAssertEqual(seen.map { $0 == .child ? "C" : "M" }.joined(), servers, "\(level)")
        }
        // ServePresentationTest.elevenIsPreservedForEveryDifficultyAndRoomType
        for level in MPLevel.allCases {
            for kind in MPSessionKind.allCases {
                let s = MPSession(code: "ABC234", kind: kind, host: MPIdentity(id: "host", name: "Happy"), capacity: 4, difficulty: level.rawValue, target: 11)
                XCTAssertEqual(s.target, 11)
                var score = MPScore(server: .child)
                for _ in 0..<10 { _ = score.award(.child, level: level, target: s.target, first: nil) }
                XCTAssertNil(score.winner)
                _ = score.award(.child, level: level, target: s.target, first: nil); XCTAssertEqual(score.winner, .child)
            }
        }
    }

    // MARK: Shots (Android Shots.standard / forgivingTap / aiReturn / riskyTapServe)

    func testStandardShotMatchesAndroid() {
        let t = coach, p = MPPoint(0.5, 0.92)
        shot(MPShots.standard(standardContact(p, .init(0, -0.25)), t, height: 0.15), 0.0, -0.5820000000000001, 1.5726942441399405)
        shot(MPShots.standard(standardContact(p, .init(0, -3.0)), t, height: 0.15), 0.0, -1.1400000000000001, 1.0862002567394096)
        shot(MPShots.standard(standardContact(p, .init(-0.35, -1.2)), t, height: 0.15), -0.275437037037037, -0.8300000000000001, 1.2794109772423026)
        shot(MPShots.standard(standardContact(p, .init(0.35, -1.2)), t, height: 0.15), 0.275437037037037, -0.8300000000000001, 1.2794109772423026)
        shot(MPShots.standard(standardContact(p, .init(0.9, -0.4)), t, height: 0.15), 0.8672230070104219, -0.7642516734845434, 1.3394182429668877)
    }

    func testStandardSwipeHitLandsAndIsMirroredForTheFarSide() {
        let t = coach
        let rows: [(MPPoint, MPPoint, Double, MPPoint, MPPoint, Double)] = [
            (.init(0, -0.25), .init(0.0, -0.5820000000000001), 1.0106523246592818, .init(0.5, 0.3609999999999967), .init(0, 0.5820000000000001), 1.5726942441399405),
            (.init(0, -3.0), .init(0.0, -1.1400000000000001), 0.8062413350449272, .init(0.5, 0.09999999999999856), .init(0, 1.1400000000000001), 1.0862002567394096),
            (.init(-0.35, -1.2), .init(-0.275437037037037, -0.8300000000000001), 0.8777927710843393, .init(0.275999999999995, 0.2449999999999979), .init(-0.275437037037037, 0.8300000000000001), 1.2794109772423026),
        ]
        for (velocity, after, liftAfterBounce, landing, farVelocity, farLift) in rows {
            var f = MPFlight(position: .init(0.5, 0.92), height: 0.15, velocity: .zero, lift: 0, striker: .minik)
            f.hit(standardContact(.init(0.5, 0.92), velocity), side: .child, tuning: t, rally: 0)
            var land: MPPoint?
            for _ in 0..<2000 where land == nil { let e = f.advance(1.0 / 240, t); if e?.bounced == true { land = e?.point } }
            near(f.velocity.x, after.x); near(f.velocity.y, after.y); near(f.lift, liftAfterBounce)
            near(land?.x ?? -1, landing.x); near(land?.y ?? -1, landing.y)
            var g = MPFlight(position: .init(0.3, 0.08), height: 0.15, velocity: .zero, lift: 0, striker: .child)
            g.hit(standardContact(.init(0.3, 0.08), velocity), side: .minik, tuning: t, rally: 0)
            near(g.velocity.x, farVelocity.x, 1e-12); near(g.velocity.y, farVelocity.y, 1e-12); near(g.lift, farLift, 1e-12)
        }
    }

    /// StandardRankTest.speedChangesDepthAndPaceWithoutOwnSideBounce
    func testStandardSpeedChangesDepthAndPaceWithoutOwnSideBounce() throws {
        let t = coach
        func make(_ v: MPPoint) -> MPShot { MPShots.standard(standardContact(.init(0.5, 0.92), v), t, height: 0.15) }
        func land(_ s: MPShot) throws -> MPPoint {
            var f = MPFlight(position: .init(0.5, 0.92), height: 0.15, velocity: s.velocity, lift: s.arc, striker: .child)
            var landing: MPPoint?
            for _ in 0..<2000 where landing == nil {
                let e = f.advance(1.0 / 240, t)
                if e?.bounced == true { landing = e?.point } else if let r = e?.resolution { XCTFail("fault \(r) \(f.position)"); break }
            }
            return try XCTUnwrap(landing, "no landing")
        }
        let slow = make(.init(0, -0.25)), fast = make(.init(0, -3.0))
        XCTAssertGreaterThan(abs(fast.velocity.y), abs(slow.velocity.y))
        XCTAssertGreaterThan(try land(slow).y, 0.30); XCTAssertLessThan(try land(fast).y, 0.15)
        XCTAssertLessThan(try land(make(.init(-0.35, -1.2))).x, 0.4); XCTAssertGreaterThan(try land(make(.init(0.35, -1.2))).x, 0.6)
    }

    func testForgivingTapChoosesALegalLandingWhenAssisted() {
        let t = starter
        let rows: [(Double, Bool, MPPoint, Double)] = [
            (0, false, .init(0.9, 0.5), 0.25), (0, false, .init(-0.2, 0.6), -0.07766410256410257),
            (0, true, .init(0.9, 0.5), 0.25), (0, true, .init(-0.2, 0.6), -0.07766410256410257),
            (0.5, false, .init(0.9, 0.5), 0.4441602564102564), (0.5, false, .init(-0.2, 0.6), 0.11649615384615385),
            (0.5, true, .init(0.9, 0.5), 0.4441602564102564), (0.5, true, .init(-0.2, 0.6), 0.11649615384615385),
            (-1.5, false, .init(0.9, 0.5), -0.3324807692307692), (-1.5, false, .init(-0.2, 0.6), -0.6601448717948718),
            (-1.5, true, .init(0.9, 0.5), -0.0866786858974359), (-1.5, true, .init(-0.2, 0.6), -0.0866786858974359),
        ]
        for (direction, safe, incoming, vx) in rows {
            let c = MPContact(point: .init(0.2, 0.9), timing: 1, spatial: 1, velocity: .init(0.3, -0.4), direction: direction)
            shot(MPShots.tap(c, t, rally: 3, height: 0.2, incoming: incoming, safeAim: safe), vx, -0.5547435897435897, 1.9032777102481142)
        }
    }

    func testPoorHouseReturnCrossesTheNetAndGoesWide() {
        let t = starter
        let rows: [(Double, Double, Double?, Double)] = [
            (0.05, 0.2, nil, -0.5793103448275861), (0.05, 0.2, 0.7, -0.5793103448275861), (0.05, 0.8, nil, 0.579310344827586), (0.05, 0.8, 0.7, 0.579310344827586),
            (0.5, 0.2, nil, 0.1344), (0.5, 0.2, 0.7, 0.6034482758620687), (0.5, 0.8, nil, 0.1344), (0.5, 0.8, 0.7, -0.12068965517241388),
        ]
        for (quality, x, targetX, vx) in rows {
            let c = MPContact(point: .init(x, 0.2), timing: quality, spatial: quality, velocity: .init(0.3, 0.7), direction: 0.4, targetX: targetX)
            shot(MPShots.ai(c, t, height: 0.1), vx, 0.7, 1.3707389162561578)
        }
    }

    func testRiskyTapServesHaveRealOutcomes() {
        let t = coach
        // (y, roll) at x 0.3 -> plan and Android's resolution with the number of bounces on Minik's half.
        let rows: [(Double, Double, MPPoint, MPPoint, Double, Double, MPShot?, MPSide, MPFault, Int)] = [
            (0.45, 0.5, .init(0.4, 0.72), .init(0.3, 0.45), 0.25, 0.7, nil, .child, .secondBounce, 1),
            (0.45, 0.76, .init(0.4, 0.72), .init(0.3, 0.45), 0.25, 0.7, .init(velocity: .init(-0.03500000000000001, -0.45), arc: 0.88), .minik, .firstBounceOut, 0),
            (0.45, 0.9, .init(0.4, 0.72), .init(0.3, 0.45), 0.25, 0.7, .init(velocity: .init(-0.03500000000000001, -0.45), arc: 0.24), .minik, .firstBounceOut, 0),
            (0.42, 0.74, .init(0.4, 0.72), .init(0.3, 0.42), 0.25, 0.7, nil, .child, .secondBounce, 1),
            (0.05, 0.5, .init(0.435, 0.72), .init(0.3, 0.05), 0.72, 0.85, nil, .child, .unreturned, 1),
            (0.05, 0.76, .init(0.435, 0.72), .init(0.3, -0.16), 0.72, 0.85, nil, .minik, .leftTable, 0),
            (0.08, 0.74, .init(0.435, 0.72), .init(0.3, 0.08), 0.72, 0.85, nil, .child, .unreturned, 1),
            (0.25, 0.9, .init(0.435, 0.72), .init(0.37, 0.25), 0.4, 1.27, nil, .child, .unreturned, 1),
            (0.7, 0.5, .init(0.461, 0.7), .init(0.37, 0.28), 0.4, 1.27, nil, .child, .secondBounce, 1),
        ]
        for (y, roll, first, second, speed, arc, bounceShot, winner, fault, bounces) in rows {
            let plan = MPShots.riskyTapServe(.init(0.3, y), t, roll: roll)
            near(plan.first.x, first.x, 1e-12); near(plan.first.y, first.y, 1e-12); near(plan.second.x, second.x, 1e-12); near(plan.second.y, second.y, 1e-12)
            near(plan.speed, speed, 1e-12); near(plan.arc, arc, 1e-12)
            XCTAssertEqual(plan.shot == nil, bounceShot == nil, "y \(y) roll \(roll)")
            if let s = plan.shot, let b = bounceShot { shot(s, b.velocity.x, b.velocity.y, b.arc) }
            var f = MPFlight(plan, t), count = 0, result: MPResolution?
            for _ in 0..<3000 where result == nil { let e = f.advance(1.0 / 240, t); if e?.recipient == .minik { count += 1 }; result = e?.resolution }
            XCTAssertEqual(result, MPResolution(winner: winner, fault: fault), "y \(y) roll \(roll)"); XCTAssertEqual(count, bounces, "y \(y) roll \(roll)")
        }
    }

    // MARK: Pro spin (Android PongStroke / PongSpinShot / Flight spin, SpinServeRegressionTest)

    private let arcGesture = [MPPoint(0.2, 0.8), MPPoint(0.22, 0.65), MPPoint(0.35, 0.5), MPPoint(0.53, 0.43), MPPoint(0.7, 0.4)]
    private let weaveGesture = [MPPoint(0.5, 0.8), MPPoint(0.3, 0.75), MPPoint(0.25, 0.65), MPPoint(0.45, 0.55), MPPoint(0.7, 0.4)]

    func testStrokeReadingMatchesAndroid() throws {
        let straight = [MPPoint(0.2, 0.8), MPPoint(0.4, 0.6), MPPoint(0.6, 0.4)]
        let mirror = weaveGesture.map { MPPoint(1 - $0.x, $0.y) }
        let rows: [([MPPoint], Int64, Double, Double, Double, Double)] = [
            (arcGesture, 80, 1.0, 0.9995811720706923, 0.99972776184595, 0), (arcGesture, 220, 1.0, 0.9408915839311555, 0.9615795295552511, 0),
            (arcGesture, 900, 1.0, 0.4991167590696469, 0.6744258933952705, 0),
            (weaveGesture, 180, 1.0, 0.9821312309189384, 0, -0.98838530009731), (weaveGesture, 900, 1.0, 0.5528853219433805, 0, -0.7093754592631973),
            (straight, 180, 0.9999999999999999, 0.9349617571573949, 0, 0), (straight, 900, 0.9999999999999999, 0.4210597292949684, 0, 0),
            (mirror, 180, -1.0, 0.9821312309189384, 0, 0.98838530009731), (mirror, 80, -1.0, 0.999883261816276, 0, 0.9999241201805794),
        ]
        for (points, ms, aim, power, top, side) in rows {
            let s = try XCTUnwrap(MPPongStroke.read(points, durationMs: ms))
            near(s.aim, aim); near(s.power, power); near(s.top, top); near(s.side, side); XCTAssertTrue(s.valid)
        }
        // SpinServeRegressionTest.gesturesDistinguishStraightArcAndDirectionReversal
        XCTAssertNil(MPPongStroke.read([MPPoint(0.5, 0.5), MPPoint(0.501, 0.499)], durationMs: 70))
        let side = try XCTUnwrap(MPPongStroke.read(weaveGesture, durationMs: 180)); XCTAssertTrue(side.aim > 0 && side.side < 0)
        let flipped = try XCTUnwrap(MPPongStroke.read(mirror, durationMs: 180)); near(flipped.aim, -side.aim, 1e-8); near(flipped.side, -side.side, 1e-8)
        XCTAssertGreaterThan(try XCTUnwrap(MPPongStroke.read(arcGesture, durationMs: 80)).top, try XCTUnwrap(MPPongStroke.read(arcGesture, durationMs: 900)).top)
        XCTAssertEqual(side.reflected, MPPongStroke(aim: -side.aim, power: side.power, top: side.top, side: -side.side))
        XCTAssertFalse(MPPongStroke(aim: 0, power: 9).valid)
    }

    func testSpinShotSolveMatchesAndroid() {
        let rows: [(MPPongStroke, Double, Double, Double)] = [
            (.init(aim: 0.8, power: 0.8, top: 0.8, side: -0.8), 0.8821266499835987, 1.21, 1.353084251606979),
            (.init(aim: -1.0, power: 0.0, top: 1.0, side: 1.0), -0.3578137666271371, 0.85, 2.415449346405229),
            (.init(aim: 0.0, power: 1.0, top: 0.0, side: 0.0), 0.36111111111111116, 1.3, 0.7116880341880341),
        ]
        for (stroke, vx, pace, arc) in rows {
            shot(MPPongSpinShot.solve(.init(0.3, 0.96), height: 0.25, stroke: stroke, tuning: hard, side: .child), vx, -pace, arc)
            shot(MPPongSpinShot.solve(.init(0.3, 0.04), height: 0.25, stroke: stroke, tuning: hard, side: .minik), vx, pace, arc)
        }
    }

    func testTopspinFlightTrajectoryWireAndContinuation() throws {
        var f = MPFlight(position: .init(0.3, 0.96), height: 0.25, velocity: .zero, lift: 0, striker: .minik)
        var c = MPContact(point: f.position, timing: 1, spatial: 1, velocity: .init(1, -1), direction: 1)
        c.stroke = MPPongStroke(aim: 0.8, power: 0.8, top: 0.8, side: -0.8)
        f.hit(c, side: .child, tuning: hard, rally: 0)
        var bounce: MPPoint?
        for i in 1...80 {
            let e = f.advance(1.0 / 120, hard)
            if e?.bounced == true { bounce = e?.point; XCTAssertEqual(i, 72); XCTAssertEqual(e?.recipient, .minik) }
            XCTAssertNil(e?.resolution)
            if i == 10 {
                near(f.position.x, 0.3712258045314695); near(f.position.y, 0.8591666666666666); near(f.height, 0.34206257652280386)
                near(f.velocity.x, 0.8283280447175605); near(f.lift, 0.8564175849403118); near(f.spin, -0.6051196042718563)
                near(f.topSpin, 1.7600000000000002); near(f.spinAngle, 144.33499579154739, 1e-7)
            }
        }
        near(bounce?.x ?? -1, 0.7314592555862208); near(bounce?.y ?? -1, 0.2400000000000001)
        near(f.position.x, 0.7741239036878662); near(f.position.y, 0.15333333333333332); near(f.height, 0.07629076622726147)
        near(f.velocity.x, 0.5856994477477976); near(f.velocity.y, -1.21); near(f.lift, 0.8800565771349863)
        near(f.spin, -0.2674036901906469); near(f.topSpin, 0.9680000000000002, 1e-12); near(f.spinAngle, 304.72797822206974, 1e-7)
        // Android FlightState wire: "top" and "angle"; older checkpoints without them read as no spin.
        let wire = try MPCodec.encode(f)
        near((wire["top"] as? NSNumber)?.doubleValue ?? -1, f.topSpin, 0); near((wire["angle"] as? NSNumber)?.doubleValue ?? -1, f.spinAngle, 0)
        XCTAssertNil(wire["topSpin"]); XCTAssertNil(wire["spinAngle"])
        var copy = try MPCodec.decode(MPFlight.self, wire)
        func same(_ a: MPFlight, _ b: MPFlight) {
            for (x, y) in [(a.position.x, b.position.x), (a.position.y, b.position.y), (a.height, b.height), (a.velocity.x, b.velocity.x), (a.velocity.y, b.velocity.y),
                           (a.lift, b.lift), (a.spin, b.spin), (a.topSpin, b.topSpin), (a.spinAngle, b.spinAngle)] { near(x, y, 1e-9) }
            XCTAssertEqual(a.striker, b.striker); XCTAssertEqual(a.receiver, b.receiver); XCTAssertEqual(a.resolved, b.resolved)
        }
        same(copy, f)
        let twice = copy.reflected.reflected; near(twice.position.x, copy.position.x, 1e-12); XCTAssertEqual(twice.topSpin, copy.topSpin); XCTAssertEqual(twice.spin, copy.spin)
        for _ in 0..<40 { _ = f.advance(1.0 / 120, hard); _ = copy.advance(1.0 / 120, hard); same(f, copy) }
        var legacy = wire; legacy["top"] = nil; legacy["angle"] = nil
        let old = try MPCodec.decode(MPFlight.self, legacy)
        XCTAssertEqual(old.topSpin, 0); XCTAssertEqual(old.spinAngle, 0); XCTAssertTrue(old.valid)
        var bad = old; bad.topSpin = 2.3; XCTAssertFalse(bad.valid)
        bad = old; bad.spin = 1.01; XCTAssertFalse(bad.valid)
    }

    /// SpinServeRegressionTest.fastAndSlowSpinLandLegallyOnTheOtherHalf
    func testFastAndSlowSpinLandLegallyOnTheOtherHalf() {
        let t = hard
        for player in [MPSide.child, .minik] { for x in [0.12, 0.5, 0.88] { for h in [0.06, 0.3, 0.8] { for top in [0.0, 1.0] { for side in [-1.0, 0, 1] { for power in [0.0, 1.0] {
            let at = MPPoint(x, player == .child ? 0.96 : 0.04)
            var f = MPFlight(position: at, height: h, velocity: .zero, lift: 0, striker: player.other)
            var c = MPContact(point: at, timing: 1, spatial: 1, velocity: .init(0, -1), direction: side)
            c.stroke = MPPongStroke(aim: side, power: power, top: top, side: side)
            f.hit(c, side: player, tuning: t, rally: 0)
            XCTAssertLessThanOrEqual(abs(f.velocity.y), 1.31)
            var bounce: MPFlight.Event?
            for _ in 0..<360 where bounce == nil { if let e = f.advance(1.0 / 240, t), e.bounced || e.resolution != nil { bounce = e } }
            let label = "\(player) x=\(x) height=\(h) top=\(top) side=\(side) power=\(power)"
            XCTAssertEqual(bounce?.bounced, true, label); XCTAssertEqual(bounce?.recipient, player.other, label)
            near(bounce?.point?.x ?? -1, 0.5 + side * 0.29, 0.004, label)
        } } } } } }
    }

    func testOverTableGrazeAndBounceClampKeepTheVisibleEdge() {
        // Before its bounce a ball may pass one ball radius beyond the edge; the recorded bounce stays on the table.
        var f = MPFlight(position: .init(1.005, 0.30), height: 0.002, velocity: .init(-0.05, -0.2), lift: -0.2, striker: .child)
        let e = f.advance(1.0 / 60, starter)
        XCTAssertNil(e?.resolution); XCTAssertEqual(e?.bounced, true); XCTAssertEqual(e?.point?.x, 1.0)
        var out = MPFlight(position: .init(1.02, 0.30), height: 0.3, velocity: .init(0.05, -0.2), lift: 0, striker: .child)
        XCTAssertEqual(out.advance(1.0 / 60, starter)?.resolution, MPResolution(winner: .minik, fault: .leftTable))
    }

    // MARK: Loose ball, projections, placement

    func testLooseBallSettlesAsAndroid() {
        let ball = MPLooseBall(position: .init(0.5, 0.9), height: 0.3, velocity: .init(0.2, 0.4), lift: 0.8)
        let bodies = [MPLooseBall.Body(x: 0.62, y: 1.12, radiusX: 0.08, radiusY: 0.06, bottom: -1, top: 1)]
        var steps = 0
        while !ball.settled && steps < 2000 {
            ball.advance(1.0 / 60, starter, bodies: bodies); steps += 1
            if steps == 30 { near(ball.position.x, 0.5807264878418651); near(ball.position.y, 1.0529102015473255); near(ball.height, 0.24999999999999967) }
        }
        XCTAssertEqual(steps, 135); near(ball.position.x, 0.534229403659516); near(ball.position.y, 0.8004076776420557)
        near(ball.height, -0.85); XCTAssertEqual(ball.bodyHits, 1); XCTAssertEqual(ball.tableBounces, 0); XCTAssertTrue(ball.settled)
        let table = MPLooseBall(position: .init(0.3, 0.6), height: 0.05, velocity: .init(0.1, -1.2), lift: 0.2)
        steps = 0
        while !table.settled && steps < 2000 { table.advance(1.0 / 60, starter, bodies: []); steps += 1 }
        XCTAssertEqual(steps, 38); near(table.position.x, 0.3360300350756753); near(table.position.y, 0.5947554001219995)
        near(table.height, 0); XCTAssertEqual(table.bodyHits, 0); XCTAssertEqual(table.tableBounces, 9)
    }

    func testNearPlayerProjectionMatchesAndroid() {
        let rows: [(Double, Double, Double, Double)] = [
            (-0.2, 150.03199999999998, -0.20000000000000004, 539.5200000000001), (0.25, 256.25, 0.25, 843.0), (0.5, 748.0, 0.5, 3169.3999999999996),
            (0.51, 779.1601628, 0.5100000000020373, 3062.9908399999995), (0.75, 1260.44375, 0.749999999992724, 1154.0749999999998),
            (0.9, 1385.1872, 0.9000000000014552, 589.7839999999999), (1.0, 1437.0, 0.999999999992724, 482.29999999999995), (1.2, 1533.46, 1.2000000000000002, 482.29999999999995),
        ]
        for (y, image, table, slope) in rows {
            near(MPNearPlayerProjection.imageY(y), image, 1e-9); near(MPNearPlayerProjection.tableY(image), table, 1e-9); near(MPNearPlayerProjection.slope(y), slope, 1e-9)
        }
        // NearPlayerProjectionTest
        for i in -20...140 { let y = Double(i) / 100; near(MPNearPlayerProjection.tableY(MPNearPlayerProjection.imageY(y)), y, 1e-8) }
        for y in [0.0, 0.13, 0.25, 0.5, 1.0] { near(MPNearPlayerProjection.imageY(y), MPProjection.imageY(y), 1e-9) }
        for i in 51...120 {
            let y = Double(i) / 100, delta = 1e-6
            near((MPNearPlayerProjection.imageY(y + delta) - MPNearPlayerProjection.imageY(y - delta)) / (2 * delta), MPNearPlayerProjection.slope(y), 0.01)
        }
    }

    func testTableBallProjectionMatchesAndroid() {
        let rows: [(Double, Double, Double)] = [(-0.1, -0.22222222222222224, -0.045000000000000005), (0.0, 4.547473508864641e-13, 0.0),
            (0.01, 0.007459500210984515, 0.013088847284541273), (0.05, 0.05722050158726688, 0.04624843911799904),
            (0.2, 3.2499999999990905, 0.0767179052777886), (0.5, 10.749999999997044, 0.08999682200491664)]
        for (amount, height, rise) in rows { near(MPTableBallProjection.height(amount), height, 1e-9); near(MPTableBallProjection.rise(amount), rise, 1e-12) }
    }

    func testPracticeTableLayoutMatchesAndroid() {
        let rows: [(Double, Double, [Double], MPPoint)] = [
            (360, 600, [16.19999999999999, 97.76736000000001, 327.6, 366.0, 111.38400000000001, 44.55360000000001, 203.11200000000002], .init(103.833, 347.89392)),
            (600, 360, [15.0, 71.8248115942029, 570.0, 216.02318840579713, 97.2, 38.88, 133.9343768115942], .init(167.47500000000002, 217.77007768115942)),
            (800, 1130, [36.0, 193.91180000000003, 728.0, 689.3, 247.52, 99.00800000000001, 427.366], .init(230.74, 659.60288)),
            (1200, 650, [30.0, 126.78835748792271, 1140.0, 399.38164251207735, 175.5, 70.2, 247.61661835748797], .init(334.95000000000005, 396.61059516908216)),
        ]
        for (w, h, values, projected) in rows {
            let g = MPPracticeTableLayout.fit(w, h, density: 1)
            for (a, b) in zip([g.left, g.top, g.width, g.depth, g.actorHeight, g.floorDrop, g.lift], values) { near(a, b, 1e-9) }
            let p = g.project(.init(0.25, 0.75), 0.12); near(p.x, projected.x, 1e-9); near(p.y, projected.y, 1e-9)
            // PongArenaTest.tableTouchProjectionRoundTripsAcrossSizes
            for x in [0.01, 0.25, 0.5, 0.75, 0.99] { for y in [0.01, 0.25, 0.5, 0.75, 0.99] { for z in [0.0, 0.12, 0.28] {
                let q = g.project(.init(x, y), z), v = g.ground(x: q.x, y: q.y, z: z); near(v.x, x); near(v.y, y)
            } } }
            XCTAssertGreaterThanOrEqual(g.left, 0); XCTAssertLessThanOrEqual(g.left + g.width, w)
        }
        // LandscapeFloorTest
        for (w, h, d) in [(1220.0, 980.0, 2.625), (1240.0, 950.0, 1.8), (1390.0, 1000.0, 1.35)] {
            let g = MPPracticeTableLayout.fit(w, h, density: d)
            XCTAssertGreaterThan(g.depth, min(h * 0.61, (h - g.actorHeight - 40 * d) / 1.14), "Taller than the previous landscape fit")
            XCTAssertGreaterThanOrEqual(g.top + g.floorDrop - g.actorHeight, 0, "Far team head stays visible")
            XCTAssertLessThan(g.top + g.depth + g.actorHeight * 0.66, h, "Friendly feet stay on screen")
            XCTAssertLessThan(g.top + g.depth + g.floorDrop + g.actorHeight * 0.06 + 20 * d, h, "Team label has floor room")
            near(g.left + g.width / 2, w / 2, 1e-8)
        }
    }

    func testReturnPlacementAndServeDifficultyMatchAndroid() {
        let rows: [(Double, Double, Double, Double)] = [(0, 1.05, 0.8400000000000001, 0.63), (0.05, 1.05, 0.8400000000000001, 0.63),
            (0.2, 1.0233333333333334, 0.8186666666666668, 0.614), (0.4, 0.97, 0.776, 0.582), (0.55, 0.96, 0.768, 0.576), (0.9, 0.95, 0.76, 0.57)]
        for (d, factor, answer, good) in rows {
            near(MPReturnPlacement.multiplier(startX: 0.5, contactX: 0.5 + d), factor, 1e-12)
            let c = MPReturnPlacement.adjust(MPChance(0.8, 0.6), startX: 0.5, contactX: 0.5 + d); near(c.answer, answer, 1e-12); near(c.good, good, 1e-12)
        }
        let serves: [(MPPoint, Int, Double, Double, MPZone)] = [(.init(0.9, 0.3), 1, 0.7481828571428571, 0.63358, .backhand), (.init(0.1, 0.9), 0, 0.7815085714285714, 0.64816, .backhand),
            (.init(0.5, 0.2), 1, 0.9, 0.7, .middle), (.init(0.8, 0.6), 0, 0.82512, 0.6672399999999999, .forehand)]
        for (landing, team, answer, good, zone) in serves {
            let c = MPServeDifficulty.adjust(MPChance(0.9, 0.7), landing: landing, receivingTeam: team); near(c.answer, answer, 1e-12); near(c.good, good, 1e-12)
            XCTAssertEqual(MPServeDifficulty.zone(ballX: landing.x, playerX: 0.5, team: team), zone)
        }
    }

    func testGaitHoldsEachPoseAndStopsWhenQuiet() {
        let gait = MPGait()
        for _ in 0..<6 { gait.update(0.05, travel: 0.02, stroke: false) }
        XCTAssertTrue(gait.walking); XCTAssertEqual(gait.phase, 1)
        for _ in 0..<4 { gait.update(0.05, travel: 0, stroke: false) }
        XCTAssertFalse(gait.walking)
        gait.update(0.05, travel: 0.02, stroke: true); XCTAssertFalse(gait.walking)
    }

    // MARK: Colour ranks (Android PongRanks, RankPromotion, PongRanking; RankPromotionTest, StandardRankTest)

    func testRankLadderAndRewardsMatchAndroid() {
        XCTAssertEqual(MPRanks.all.count, 12); XCTAssertTrue(zip(MPRanks.all, MPRanks.all.dropFirst()).allSatisfy { $1.threshold > $0.threshold })
        XCTAssertEqual(MPRanks.all.last?.en, "Gold")
        XCTAssertEqual([-5, 0, 199, 200, 1449, 1450, 3100, 99999].map(MPRanks.index), [0, 0, 0, 1, 5, 6, 11, 11])
        XCTAssertEqual([-1, 0, 4, 5, 9, 10, 19, 20, 29, 30, 39, 40, 100].map(MPRanks.daily), [15, 3, 3, 5, 5, 7, 7, 10, 10, 12, 12, 15, 15])
        XCTAssertEqual([1, 2, 3, 4].map(MPRanks.podium), [15, 10, 5, 0])
        let expected: [String: [Int]] = ["minik": [4, 7, 2, 2], "flare": [6, 9, 4, 4], "kyra": [7, 10, 5, 5], "gaya": [6, 8, 4, 4], "mia": [5, 8, 3, 3],
            "amber": [4, 6, 2, 2], "comet": [4, 6, 2, 2], "june": [4, 6, 2, 2], "moshiko": [3, 5, 1, 1], "miniko": [4, 7, 2, 2], "coach67": [4, 7, 2, 2]]
        for player in MPRoster.all { XCTAssertEqual([0, 3, 4, 1].map { MPRanks.bot(player.profile, control: $0) }, expected[player.id], player.id) }
        XCTAssertEqual((0...11).map { MPRanks.humanLevel($0, control: 0) }, [5, 6, 7, 8, 9, 10, 10, 11, 12, 13, 14, 15])
        XCTAssertEqual((0...11).map { MPRanks.humanLevel($0, control: 3) }, [8, 9, 10, 11, 12, 13, 15, 16, 17, 18, 19, 20])
        XCTAssertEqual((0...11).map { MPRanks.humanLevel($0, control: 4) }, [3, 4, 4, 5, 6, 6, 7, 7, 8, 9, 9, 10])
        XCTAssertEqual(MPRanks.human(0), 5); XCTAssertEqual(MPRanks.human(18000), 15)
        let bots = MPRoster.all.sorted { $0.profile.strength < $1.profile.strength }
        XCTAssertEqual(MPRanks.bot(bots.first!.profile), 3); XCTAssertEqual(MPRanks.bot(bots.last!.profile), 7)
        XCTAssertEqual(MPRanks.all[7].ink, 0xffffffff); XCTAssertEqual(MPRanks.ink(0xff8b54c5), 0xffffffff); XCTAssertEqual(MPRanks.ink(0xffffcf40), 0xff17283f)
        XCTAssertEqual([0, 1, 2, 3, 4, 7].map(MPControlChoice.normalize), [0, 1, 0, 3, 4, 4])
    }

    func testRankRequirementsChallengersAndChampionsMatchAndroid() {
        XCTAssertEqual(MPRankPromotion.strongest.map(\.id), ["kyra", "flare", "gaya"])
        let requirements: [(Int, Bool, Int, Int, [String], [Bool])] = [
            (0, false, 0, 1, ["kyra", "flare", "gaya"], [true, true, true, false]), (2, false, 0, 1, ["kyra", "flare", "gaya"], [true, true, true, false]),
            (5, false, 1, 1, ["kyra", "flare", "gaya"], [true, true, true, false]), (7, false, 1, 0, ["kyra", "flare", "gaya"], [true, false, true, false]),
            (8, true, 2, 0, ["kyra"], [true, false, true, false]), (10, true, 3, 3, ["kyra"], [false, false, true, false]), (11, true, 5, 3, ["kyra"], [false, false, true, false]),
        ]
        for (target, streak, champions, control, bots, allowed) in requirements {
            let r = MPRankPromotion.requirement(target)
            XCTAssertEqual(r.streak, streak); XCTAssertEqual(r.champions, champions); XCTAssertEqual(MPRankPromotion.minimumControl(target), control)
            XCTAssertEqual(MPRankPromotion.bots(target).map(\.id), bots); XCTAssertEqual([0, 1, 3, 4].map { MPRankPromotion.allowedControl(target, $0) }, allowed)
        }
        XCTAssertEqual(MPRankPromotion.requirement(2).bots, 3); XCTAssertEqual(MPRankPromotion.requirement(10).bots, 5); XCTAssertEqual(MPRankPromotion.requirement(1).bots, 0)
        let champions: [(Int, Int, String)] = [(4, 7, "gaya"), (5, 7, "gaya"), (6, 7, "flare"), (7, 8, "kyra"), (8, 8, "gaya"), (9, 9, "flare"), (10, 9, "kyra"), (11, 10, "gaya"), (12, 10, "flare")]
        for (target, skill, character) in champions {
            XCTAssertEqual(MPRankPromotion.championProfile(target), MPBot(speed: skill, reaction: skill, accuracy: skill, power: skill, agility: skill, characterId: character, forehandSkill: skill, backhandSkill: skill, serveSkill: skill))
        }
    }

    func testChampionTuningMatchesAndroid() {
        for target in [-1, 4, 5, 12] {
            let t = MPRankPromotion.championTuning(starter, target)
            XCTAssertEqual(t.minikReactionInterval, starter.minikReactionInterval); XCTAssertEqual(t.profile.maxSpeed, starter.profile.maxSpeed)
        }
        let eight = MPRankPromotion.championTuning(starter, 8), p = eight.profile
        near(eight.minikReactionInterval, 0.3822, 1e-12); near(eight.minikAimError, 0.204, 1e-12)
        let receive: [(Double, Double)] = [(0.89125, 0.8400000000000001), (0.9275, 0.88), (0.96375, 0.92)]
        XCTAssertEqual(p.serveReceive.count, 3)
        for i in receive.indices { near(p.serveReceive[i].answer, receive[i].0, 1e-12); near(p.serveReceive[i].good, receive[i].1, 1e-12) }
        near(p.forehandSame.answer, 0.9275, 1e-12); near(p.forehandSame.good, 0.88, 1e-12); near(p.forehandCross.answer, 0.855, 1e-12); near(p.forehandCross.good, 0.76, 1e-12)
        near(p.backhandSame.answer, 0.855, 1e-12); near(p.backhandSame.good, 0.8, 1e-12); near(p.backhandCross.answer, 0.7825, 1e-12); near(p.backhandCross.good, 0.6, 1e-12)
        near(p.firstForehandSpeed, 1.0918, 1e-12); near(p.firstBackhandSpeed, 1.0388, 1e-12); near(p.maxSpeed, 1.2932000000000001, 1e-12)
        let eleven = MPRankPromotion.championTuning(starter, 11)
        near(eleven.minikReactionInterval, 0.34440000000000004, 1e-12); near(eleven.minikAimError, 0.16799999999999998, 1e-12)
        near(eleven.profile.backhandCross.answer, 0.865, 1e-12); near(eleven.profile.maxSpeed, 1.3664, 1e-12)
        // RankPromotionTest.championsGrowStrongerWithoutUnlimitedReachOrPace
        let all = (5...11).map { MPRankPromotion.championTuning(MPRankPromotion.championProfile($0).tuning(.easy, houseControls: true), $0) }
        XCTAssertGreaterThan(all.last!.profile.forehandSame.answer, all.first!.profile.forehandSame.answer)
        XCTAssertLessThan(all.last!.minikReactionInterval, all.first!.minikReactionInterval)
        XCTAssertTrue(all.allSatisfy { $0.profile.maxSpeed <= 2.8 && $0.profile.forehandSame.answer < 1 })
        // Android ModernGame: a champion trial strengthens the house player; any other match keeps its tuning.
        let bot = MPRankPromotion.championProfile(8)
        XCTAssertLessThan(MPEngine(level: .easy, bot: bot, championLevel: 8).tuning.minikReactionInterval, MPEngine(level: .easy, bot: bot).tuning.minikReactionInterval)
        XCTAssertEqual(MPEngine(level: .easy, bot: bot, championLevel: -1).tuning.minikAimError, MPEngine(level: .easy, bot: bot).tuning.minikAimError)
    }

    /// RankPromotionTest
    func testRankPromotionQualification() {
        var s = MPRankPromotion.advance(MPRankProgress(points: 10000)); XCTAssertEqual(s.level, 1); XCTAssertEqual(MPRankPromotion.advance(s), s)
        for target in 2...11 {
            s = MPRankProgress(points: MPRanks.all[target].threshold, level: target - 1)
            let req = s.requirement, bot = MPRankPromotion.bots(target)[0].profile
            for _ in 0..<req.bots { s = MPRankPromotion.result(s, points: 0, won: true, trial: target, bot: bot) }
            if req.champions > 0 { XCTAssertEqual(s.level, target - 1) }
            for _ in 0..<req.champions { s = MPRankPromotion.result(s, points: 0, won: true, trial: target, bot: MPRankPromotion.championProfile(target), champion: true) }
            XCTAssertEqual(s.level, target, "target \(target)"); XCTAssertEqual(s.botWins, 0); XCTAssertEqual(s.streak, 0); XCTAssertEqual(s.championWins, 0)
        }
        let low = MPRankPromotion.result(MPRankProgress(points: 500, level: 1, botWins: 2), points: 0, won: false, trial: nil, bot: nil)
        XCTAssertEqual(low.botWins, 2); XCTAssertEqual(low.points, 500)
        let high = MPRankPromotion.result(MPRankProgress(points: 3000, level: 9, streak: 4, championWins: 2), points: 0, won: false, trial: nil, bot: nil)
        XCTAssertEqual(high.streak, 0); XCTAssertEqual(high.championWins, 2)
        let done = MPRankProgress(points: 3000, level: 9, streak: 5, championWins: 2)
        XCTAssertEqual(MPRankPromotion.result(done, points: 0, won: false, trial: 10, bot: MPRankPromotion.championProfile(10), champion: true), done)
        let start = MPRankProgress(points: 500, level: 1), strongest = MPRankPromotion.strongest[0].profile
        XCTAssertEqual(MPRankPromotion.result(start, points: 5, won: true, trial: nil, bot: strongest).botWins, 0)
        var weak = strongest; weak.accuracy = 1
        XCTAssertEqual(MPRankPromotion.result(start, points: 5, won: true, trial: 2, bot: weak).botWins, 0)
        XCTAssertEqual(MPRankPromotion.result(start, points: 5, won: true, trial: 2, bot: strongest).botWins, 1)
        var early = start; early.points = 200
        XCTAssertEqual(MPRankPromotion.result(early, points: 5, won: true, trial: 2, bot: strongest).botWins, 0)
    }

    func testRankingPersistsReceiptsOnceAndRecordsPromotion() throws {
        let defaults = try XCTUnwrap(UserDefaults(suiteName: "modern-ranking-" + UUID().uuidString))
        let ranking = MPRanking(defaults)
        XCTAssertEqual(ranking.rank.en, "White"); XCTAssertNil(ranking.promotion())
        XCTAssertTrue(ranking.award("daily/0/serve", 250)); XCTAssertFalse(ranking.award("daily/0/serve", 250)); XCTAssertFalse(ranking.award("zero", 0))
        XCTAssertEqual(ranking.points, 250); XCTAssertEqual(ranking.rank.en, "Yellow"); XCTAssertEqual(ranking.promotion(), 1)
        XCTAssertEqual(defaults.integer(forKey: "modern.pong.ranking.points"), 250); XCTAssertTrue(defaults.bool(forKey: "modern.pong.ranking.paid/daily/0/serve"))
        ranking.acknowledgePromotion(); XCTAssertNil(ranking.promotion())
        let kyra = try XCTUnwrap(MPRoster.find("kyra")).profile
        XCTAssertTrue(ranking.localResult("modern/1", won: true, bot: kyra, control: 3)); XCTAssertFalse(ranking.localResult("modern/1", won: true, bot: kyra, control: 3))
        XCTAssertEqual(ranking.points, 260)
        XCTAssertEqual(ranking.badge, MPRankBadge(points: 260, level: 1))
        XCTAssertEqual(MPRankBadge(wire: ["rankPoints": 99, "rankLevel": 40]), MPRankBadge(points: 99, level: 11))
        XCTAssertEqual(MPRankBadge(points: -3, level: 2).wire["rankPoints"] as? Int, 0)
    }

    func testRankAndCourtColours() {
        XCTAssertEqual(MPRankPresentation.face(MPRanks.all[10]).stops, [0xffe2e8f0, 0xffb8c4d2, 0xff94a5ba])
        XCTAssertEqual(MPRankPresentation.stroke(MPRanks.all[0]), 0xff7993ab)
        // Kotlin Color.rgb((r*(1-f)+255*f).toInt(), …) in Float math: Red (0xef5350) toward white at 0.14, toward black at 0.2.
        XCTAssertEqual(MPColor.mix(0xffef5350, 0xffffffff, 0.14), 0xfff16b68); XCTAssertEqual(MPRankPresentation.stroke(MPRanks.all[6]), 0xffbf4240)
        XCTAssertEqual(MPCourtStyle.teamFace(0).middle, 0xff80d7ff); XCTAssertEqual(MPCourtStyle.teamFace(1).middle, 0xffffafcf)
        let seeds: [(Int64, UInt32, UInt32)] = [(0, 0xff80d7ff, 0xffffafcf), (1, 0xffffb46a, 0xff80d7ff), (42, 0xffffdf75, 0xffffafcf), (-7, 0xffffb46a, 0xff80d7ff),
            (123456789, 0xff80d7ff, 0xffffafcf), (Int64.min, 0xffffdf75, 0xffffafcf)]
        for (seed, a, b) in seeds { XCTAssertEqual(MPTeamColors.fill(0, seed: seed), a, "\(seed)"); XCTAssertEqual(MPTeamColors.fill(1, seed: seed), b, "\(seed)") }
        XCTAssertEqual(MPTeamColors.score(7, 3).string, "7 : 3"); XCTAssertEqual(MPTeamColors.named("A", "B").string, "A · B")
    }

    // MARK: Arenas and tips

    func testArenasMatchAndroid() {
        XCTAssertEqual(MPArena.choices.filter(\.largeTable), [.indoors, .park])
        XCTAssertEqual(MPArena.choices.map(\.wire), ["beach", "indoors", "park", "castle"])
        XCTAssertEqual(MPArena.read(""), .legacy); XCTAssertEqual(MPArena.read(nil), .legacy); XCTAssertEqual(MPArena.read("other-app"), .legacy); XCTAssertEqual(MPArena.read("castle"), .castle)
        XCTAssertEqual(MPArena.castle.title(he: false), "Ping Pong Castle"); XCTAssertEqual(MPArena.beach.title(he: true), "חוף הים")
        XCTAssertNil(MPArena.indoors.backdropFile(wide: true)); XCTAssertEqual(MPArena.castle.backdropFile(wide: false), "arenas/arena_castle_portrait.jpg")
        XCTAssertEqual(MPPlay(arena: "castle").arena, "castle"); XCTAssertEqual(MPPlay(step: 0).arena, "")
        // 4bd6758: Mega Minik / Mega Miniko on screen; registered nickname bases unchanged.
        XCTAssertEqual(MPRoster.find("minik")?.english, "Mega Minik"); XCTAssertEqual(MPRoster.find("miniko")?.hebrew, "מגה מיניקו")
        XCTAssertEqual(MPNames.candidate(0, hebrew: false, character: "minik"), "BestMinik"); XCTAssertEqual(MPNames.candidate(1, hebrew: true, character: "miniko"), "מיניקו בכיף")
    }

    func testHelpTipsShowThreeTimesAndSessionTipsCountEvents() throws {
        let defaults = try XCTUnwrap(UserDefaults(suiteName: "modern-tips-" + UUID().uuidString))
        XCTAssertEqual(MPHelpTips.next(he: false, eligible: false, defaults: defaults), "")
        for _ in 0..<3 { XCTAssertTrue(MPHelpTips.next(he: false, defaults: defaults).hasPrefix("\n\nDid you know? Contrary to a common belief")) }
        XCTAssertEqual(MPHelpTips.next(he: true, defaults: defaults), "")
        XCTAssertEqual(MPHelpTips.diagonal(he: false, ownPoint: true), "Serve fault: serve diagonally. Your team's point")
        // StandardRankTest.tipBudgetCountsEventsNotFrames
        MPSessionTips.reset(); let owner = UUID()
        for point in 0..<3 { for _ in 0..<100 { XCTAssertTrue(MPSessionTips.allow(owner, point: point, eligible: true)) } }
        XCTAssertFalse(MPSessionTips.allow(owner, point: 3, eligible: true)); XCTAssertFalse(MPSessionTips.allow(UUID(), point: 1, eligible: true))
        MPSessionTips.reset()
    }
}
