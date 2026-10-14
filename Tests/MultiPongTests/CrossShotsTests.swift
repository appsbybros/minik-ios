import XCTest
@testable import MinikMultiPingPong

// Android app/src/test/.../cross/CrossShotsTest.kt (MinikCrossPong 828c6fc).
final class CrossShotsTests: XCTestCase {
    /// Kotlin `Tuning.forDifficulty(Difficulty.STARTER)`.
    private let starter = MPTuning.values(.easy)
    /// Kotlin `Tuning.forDifficulty(Difficulty.HARD)`.
    private let hard = MPTuning.values(.superHard)
    private let tables = [CrossGeometry(3), CrossGeometry(4)]

    private func fly(_ g: CrossGeometry, _ t: MPTuning, _ from: MPPoint, _ h: Double, _ launch: CrossLaunch,
                     _ rebound: CrossLaunch? = nil) -> CrossBall {
        let state = CrossBallState(position: from, height: h, velocity: launch.velocity, lift: launch.lift, rebound: rebound)
        return CrossBall(g, tuning: t, initial: state)
    }

    private func bounceOf(_ event: CrossBallEvent?) -> (point: MPPoint, owner: Int)? {
        if case let .bounce(point, owner)? = event { return (point, owner) }
        return nil
    }

    private func isNet(_ event: CrossBallEvent?) -> Bool {
        if case .net? = event { return true }
        return false
    }

    private func isLanded(_ event: CrossBallEvent?) -> Bool {
        if case .landed? = event { return true }
        return false
    }

    /// Kotlin `sign(x)`.
    private func signum(_ x: Double) -> Double {
        if x > 0 { return 1 }
        if x < 0 { return -1 }
        return 0
    }

    /// Kotlin local `band(dp)` of inBandAimsStayInsideTheTargetArmAndAreFinelyAdjustable.
    private func aimBand(_ aims: CrossAimMap, _ dp: Double) -> Int {
        let gesture = aims.gesture(dp)
        if abs(gesture) < aims.bandStart { return 0 }
        return Int(signum(gesture))
    }

    // Kotlin: basePaceAndStandardPower (5c1aa4d: PACE_SCALE 2.45, so the base pace is 0.98)
    func testBasePaceAndStandardPower() {
        XCTAssertEqual(0.98, CrossShots.basePace(starter), accuracy: 1e-12)
        XCTAssertEqual(0.98, CrossShots.pace(starter), accuracy: 1e-12)
        XCTAssertEqual(0.98 * 1.35, CrossShots.pace(starter, power: 1.0), accuracy: 1e-12)
        XCTAssertEqual(0.98 * 1.35, CrossShots.pace(starter, power: 7.0), accuracy: 1e-12)
    }

    // Kotlin: targetedShotsFromEverySeatLandInEveryOtherTerritoryClearingTheNets
    func testTargetedShotsFromEverySeatLandInEveryOtherTerritoryClearingTheNets() {
        var crossings = 0
        for t in [starter, hard] {
            for g in tables {
                for s in g.seats {
                    for r in g.seats {
                        if r == s { continue }
                        for u in [-0.3, 0.0, 0.3] {
                            for v in [0.62, 0.8, 0.98] {
                                for h in [0.055, 0.25] {
                                    for power in [0.0, 1.0] {
                                        let from = g.home(s)
                                        let target = g.fromLocal(r, u, v)
                                        let pace = CrossShots.pace(t, power: power)
                                        let launch = CrossShots.targeted(g, t, from: from, height: h, target: target, pace: pace)
                                        let time: Double = (target - from).length / launch.velocity.length
                                        XCTAssertTrue(time >= CrossShots.minTime - 1e-9 && time <= CrossShots.maxTime + 1e-9, "\(time)")
                                        for span in g.netSpans(from, target) {
                                            for f in [span.start, span.end] {
                                                crossings += 1
                                                let tau: Double = f * time
                                                let rise: Double = launch.lift * tau
                                                let fall: Double = 0.5 * t.gravity * tau * tau
                                                let height: Double = h + rise - fall
                                                let need: Double = t.netHeight + CrossShots.clearance - 1e-9
                                                XCTAssertTrue(height >= need, "\(s)->\(r) clearance \(height)")
                                            }
                                        }
                                        let event = fly(g, t, from, h, launch).firstEvent().event
                                        let bounce = bounceOf(event)
                                        XCTAssertNotNil(bounce, "\(s)->\(r) (\(u),\(v)) \(String(describing: event))")
                                        if let found = bounce {
                                            XCTAssertEqual(r, found.owner)
                                            assertNear(target, found.point, 1e-9)
                                        }
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }
        XCTAssertTrue(crossings > 500, "The sample must exercise net clearance: \(crossings)")
    }

    // Kotlin: fasterPaceShortensTheFlightUntilTheNetDecides
    func testFasterPaceShortensTheFlightUntilTheNetDecides() {
        let g = CrossGeometry(4)
        let from = g.home(0)
        let target = g.fromLocal(1, 0, 0.62)
        let slow = CrossShots.flightTime(g, starter, from: from, height: 0.055, target: target, pace: 0.88)
        let fast = CrossShots.flightTime(g, starter, from: from, height: 0.055, target: target, pace: 1.5)
        let net = CrossShots.flightTime(g, starter, from: from, height: 0.055, target: target, pace: 50.0)
        XCTAssertTrue(slow > fast && fast > net)
        XCTAssertEqual((target - from).length / 1.5, fast, accuracy: 1e-12)
        // At extreme pace the net crossing sets the time: exactly CLEARANCE above the net.
        let spans = g.netSpans(from, target)
        XCTAssertEqual(1, spans.count)
        guard spans.count == 1 else { return }
        let f = spans[0].start
        let expected: Double = starter.netHeight + CrossShots.clearance
        let carried: Double = 0.055 * (1 - f)
        let arc: Double = 0.5 * starter.gravity * net * net * f * (1 - f)
        XCTAssertEqual(expected, carried + arc, accuracy: 1e-12)
        XCTAssertTrue(net > CrossShots.minTime)
        // A wall-free short path is limited by MIN_TIME only.
        let short = CrossShots.flightTime(g, starter, from: from, height: 0.055, target: g.fromLocal(0, 0, 0.8), pace: 50.0)
        XCTAssertEqual(CrossShots.minTime, short)
    }

    // Kotlin: qualityLossLowersTheLiftAndAFlatPoorShotNets
    func testQualityLossLowersTheLiftAndAFlatPoorShotNets() {
        let g = CrossGeometry(4)
        let from = g.home(0)
        let target = g.fromLocal(1, 0, 0.62)
        let good = CrossShots.targeted(g, starter, from: from, height: 0.055, target: target, pace: 50.0)
        let poor = CrossShots.targeted(g, starter, from: from, height: 0.055, target: target, pace: 50.0, quality: 0.0)
        XCTAssertEqual(good.velocity, poor.velocity)
        XCTAssertEqual(good.lift - CrossShots.qualityLift, poor.lift, accuracy: 1e-12)
        XCTAssertNotNil(bounceOf(fly(g, starter, from, 0.055, good).firstEvent().event))
        XCTAssertTrue(isNet(fly(g, starter, from, 0.055, poor).firstEvent().event))
    }

    // Kotlin: aWideDrivenSwipeGoesOut
    func testAWideDrivenSwipeGoesOut() {
        for g in tables {
            for s in g.seats {
                for side in [-1.0, 1.0] {
                    let launch = CrossShots.driven(g, hard, striker: s, swipe: MPPoint(3.0 * side, -0.5), height: 0.1, incoming: MPPoint(0, 0))
                    let view = g.toView(s, launch.velocity)
                    let degrees: Double = atan2(abs(view.x), -view.y) * 180 / Double.pi
                    XCTAssertEqual(70.0, degrees, accuracy: 1e-9)
                    XCTAssertEqual(side, signum(view.x))
                    let forecast = fly(g, hard, g.home(s), 0.1, launch).forecast()
                    XCTAssertNotNil(forecast)
                    guard let event = forecast?.event else { continue }
                    XCTAssertTrue(isLanded(event), "\(s) \(side) \(event)")
                    XCTAssertFalse(g.onTable(event.point))
                }
            }
        }
    }

    // Kotlin: aDrivenSwipeAimedAtAnArmLandsInThatTerritory
    func testADrivenSwipeAimedAtAnArmLandsInThatTerritory() {
        for g in tables {
            for s in g.seats {
                for r in g.seats {
                    if r == s { continue }
                    let delta = g.toView(s, g.fromLocal(r, 0, 0.8)) - g.toView(s, g.home(s))
                    let psi = atan2(delta.x, -delta.y)
                    let forward: Double = hard.maximumSwipeSpeed * 0.9
                    let lateral: Double = forward * tan(psi / 1.25)
                    let launch = CrossShots.driven(g, hard, striker: s, swipe: MPPoint(lateral, -forward), height: 0.1, incoming: MPPoint(0, 0))
                    let event = fly(g, hard, g.home(s), 0.1, launch).firstEvent().event
                    XCTAssertEqual(r, bounceOf(event)?.owner, "\(s)->\(r) \(String(describing: event))")
                }
            }
        }
    }

    // Kotlin: drivenPortKeepsTheClassicPowerLiftAndQualityTerms
    func testDrivenPortKeepsTheClassicPowerLiftAndQualityTerms() {
        let g = CrossGeometry(4)
        let weakShot = CrossShots.driven(g, hard, striker: 0, swipe: MPPoint(0, 0), height: 0.055, incoming: MPPoint(0, 0))
        assertNear(MPPoint(0, -1.66 * 0.18), weakShot.velocity, 1e-12)
        XCTAssertEqual(0.25 - 0.055 * 0.45, weakShot.lift, accuracy: 1e-12)
        let power = 1.5
        let swipe = MPPoint(0, -power * hard.maximumSwipeSpeed)
        let strong = CrossShots.driven(g, hard, striker: 2, swipe: swipe, height: 0.2, incoming: MPPoint(0, 3.0), quality: 0.5)
        let pace: Double = 1.66 * (0.18 + 1.28 * power + 0.06)
        assertNear(g.fromView(2, MPPoint(0, -pace)), strong.velocity, 1e-12)
        let boost: Double = 1.55 * (1 - exp(-4 * power))
        let drop: Double = 0.2 * power + 0.2 * 0.45 + 0.5 * 0.16
        XCTAssertEqual(0.25 + boost - drop, strong.lift, accuracy: 1e-12)
        // Power is capped at 3, a backward swipe has no forward power.
        let capped = CrossShots.driven(g, hard, striker: 0, swipe: MPPoint(0, -9.0), height: 0, incoming: MPPoint(0, 0))
        let huge = CrossShots.driven(g, hard, striker: 0, swipe: MPPoint(0, -30.0), height: 0, incoming: MPPoint(0, 0))
        XCTAssertEqual(capped, huge)
        let backward = CrossShots.driven(g, hard, striker: 0, swipe: MPPoint(0, 2.0), height: 0.055, incoming: MPPoint(0, 0))
        XCTAssertEqual(weakShot.velocity, backward.velocity)
    }

    // Kotlin: servesBounceInTheOwnServeZoneThenInTheChosenTerritory
    func testServesBounceInTheOwnServeZoneThenInTheChosenTerritory() {
        for g in tables {
            for s in g.seats {
                for r in g.seats {
                    if r == s { continue }
                    for lateral in [-0.3, 0.0, 0.3] {
                        let plan = CrossShots.serve(g, starter, server: s, start: g.home(s), first: g.fromLocal(s, lateral, 0.78),
                                                    second: g.fromLocal(r, 0, 0.8), pace: CrossShots.basePace(starter))
                        let ball = fly(g, starter, plan.start, plan.height, plan.launch, plan.rebound)
                        let referee = CrossReferee(g, target: 11, firstServer: s)
                        XCTAssertTrue(referee.serve(s, plan.start))
                        var events: [CrossBallEvent] = []
                        var steps = 0
                        while events.count < 2 && steps < 1200 {
                            steps += 1
                            if let event = ball.step(CrossBall.substep) {
                                events.append(event)
                                XCTAssertNil(referee.ball(event))
                            }
                        }
                        XCTAssertEqual(2, events.count)
                        guard events.count >= 2, let first = bounceOf(events[0]), let second = bounceOf(events[1]) else {
                            XCTFail("\(s)->\(r) \(events)")
                            continue
                        }
                        XCTAssertEqual(s, first.owner)
                        XCTAssertTrue(g.inServeZone(s, first.point))
                        assertNear(plan.first, first.point, 1e-9)
                        XCTAssertEqual(r, second.owner)
                        XCTAssertNotNil(plan.second)
                        if let planned = plan.second { assertNear(planned, second.point, 1e-9) }
                        XCTAssertEqual(CrossRallyPhase.receivable, referee.phase)
                        XCTAssertEqual(r, referee.receiver)
                    }
                }
            }
        }
    }

    // Kotlin: tapServeKeepsTheFirstBounceSafelyInsideTheServeZone
    func testTapServeKeepsTheFirstBounceSafelyInsideTheServeZone() {
        let g = CrossGeometry(4)
        let second = g.fromLocal(2, 0, 0.8)
        let taps: [MPPoint?] = [g.fromLocal(1, 0.45, 0.2), g.fromLocal(1, 0.4, 1.05), g.fromLocal(1, -0.49, 0.6),
                                g.fromLocal(1, 0.1, 0.8), nil, g.fromLocal(2, 0, 0.8)]
        for tap in taps {
            let plan = CrossShots.tapServe(g, starter, server: 1, start: g.home(1), tap: tap, second: second, pace: CrossShots.basePace(starter))
            XCTAssertTrue(g.inServeZone(1, plan.first), "\(String(describing: tap))")
            let local = g.toLocal(1, plan.first)
            let lateralOk: Bool = abs(local.u) <= 0.30 + 1e-12
            let nearOk: Bool = local.v >= 0.62 - 1e-12
            let farOk: Bool = local.v <= 0.92 + 1e-12
            XCTAssertTrue(lateralOk && nearOk && farOk)
        }
        let tapped = CrossShots.tapServe(g, starter, server: 1, start: g.home(1), tap: g.fromLocal(1, 0.1, 0.8), second: second, pace: 0.88)
        assertNear(g.fromLocal(1, 0.1, 0.8), tapped.first, 1e-12)
        let central = CrossShots.tapServe(g, starter, server: 1, start: g.home(1), tap: nil, second: second, pace: 0.88)
        assertNear(g.fromLocal(1, 0, 0.78), central.first, 1e-12)
    }

    // Kotlin: swipeServeRejectsWeakOrBackwardSwipesAndDrivesTheRebound
    func testSwipeServeRejectsWeakOrBackwardSwipesAndDrivesTheRebound() throws {
        let g = CrossGeometry(4)
        let start = g.home(0)
        XCTAssertNil(CrossShots.swipeServe(g, hard, server: 0, start: start, swipe: MPPoint(0.01, -0.02)))
        XCTAssertNil(CrossShots.swipeServe(g, hard, server: 0, start: start, swipe: MPPoint(0.5, 0.3)))
        XCTAssertNil(CrossShots.swipeServe(g, hard, server: 0, start: start, swipe: MPPoint(0.5, -0.03)))
        let swipe = MPPoint(0.2, -1.0)
        let plan = try XCTUnwrap(CrossShots.swipeServe(g, hard, server: 0, start: start, swipe: swipe))
        XCTAssertTrue(g.inServeZone(0, plan.first))
        XCTAssertNil(plan.second)
        XCTAssertEqual(CrossShots.driven(g, hard, striker: 0, swipe: swipe, height: 0, incoming: MPPoint(0, 0)), plan.rebound)
        let ball = fly(g, hard, plan.start, plan.height, plan.launch, plan.rebound)
        let own = try XCTUnwrap(bounceOf(ball.firstEvent().event))
        XCTAssertEqual(0, own.owner)
        assertNear(plan.first, own.point, 1e-9)
        // The same plan rotates with the server.
        let turned = try XCTUnwrap(CrossShots.swipeServe(g, hard, server: 3, start: g.home(3), swipe: swipe))
        assertNear(g.fromView(3, g.toView(0, plan.first)), turned.first, 1e-12)
        // Weak assistance lets a wild swipe from the edge miss the serve zone: a genuine bad serve.
        let wild = try XCTUnwrap(CrossShots.swipeServe(g, hard, server: 0, start: g.fromLocal(0, 0.6, 1.1), swipe: MPPoint(4.0, -1.0)))
        XCTAssertFalse(g.inServeZone(0, wild.first))
    }

    // Kotlin: fourPlayerBandsKeepTheOpponentUntilADeliberateDrag
    func testFourPlayerBandsKeepTheOpponentUntilADeliberateDrag() {
        let g = CrossGeometry(4)
        let aims = CrossAimMap(g)
        for s in g.seats {
            let order = aims.opponents(s)
            XCTAssertEqual(3, order.count)
            guard order.count == 3 else { continue }
            let left = order[0], ahead = order[1], right = order[2]
            XCTAssertEqual([g.wrap(s + 3), g.wrap(s + 2), g.wrap(s + 1)], [left, ahead, right])
            var dp = -160.0
            while dp <= 160.0 {
                let expected: Int
                if dp <= -32.0 { expected = left } else if dp >= 32.0 { expected = right } else { expected = ahead }
                XCTAssertEqual(expected, aims.aim(s, dragDp: dp).opponent, "drag \(dp)")
                dp += 0.25
            }
            XCTAssertEqual(ahead, aims.aim(s, dragDp: 31.9).opponent)
            XCTAssertEqual(right, aims.aim(s, dragDp: 32.0).opponent)
            XCTAssertEqual(ahead, aims.aim(s, dragDp: -31.9).opponent)
            XCTAssertEqual(left, aims.aim(s, dragDp: -32.0).opponent)
            // Ahead: lateral g/0.8 x 0.30 as seen by the striker, depth R-0.38 (+0.15 x power).
            let aim = aims.aim(s, dragDp: 20.0, power: 1.0)
            let depth: Double = CrossGeometry.reach - 0.38 + 0.15
            assertNear(MPPoint(0.5 / 0.8 * 0.30, -depth), g.toView(s, aim.point), 1e-12)
            assertNear(MPPoint(0, -(CrossGeometry.reach - 0.38)), g.toView(s, aims.aim(s, dragDp: 0.0).point), 1e-12)
        }
    }

    // Kotlin: threePlayerNeutralReturnsToTheSender
    func testThreePlayerNeutralReturnsToTheSender() {
        let g = CrossGeometry(3)
        let aims = CrossAimMap(g)
        for s in g.seats {
            let order = aims.opponents(s)
            XCTAssertEqual(2, order.count)
            guard order.count == 2 else { continue }
            let left = order[0], right = order[1]
            XCTAssertEqual(g.wrap(s + 2), left)
            XCTAssertEqual(g.wrap(s + 1), right)
            for sender in [left, right] {
                for dp in [-9.9, -5.0, 0.0, 5.0, 9.9] {
                    let aim = aims.aim(s, dragDp: dp, sender: sender)
                    XCTAssertEqual(sender, aim.opponent)
                    assertNear(g.fromLocal(sender, 0, CrossGeometry.reach - 0.38), aim.point, 1e-12)
                }
            }
            for sender in [left, right] {
                XCTAssertEqual(left, aims.aim(s, dragDp: -10.0, sender: sender).opponent)
                XCTAssertEqual(right, aims.aim(s, dragDp: 10.0, sender: sender).opponent)
            }
            // Serve: the tap's side picks the neutral opponent, otherwise seat+1.
            XCTAssertEqual(left, aims.aim(s, dragDp: 0.0, serveLateral: -0.2).opponent)
            XCTAssertEqual(right, aims.aim(s, dragDp: 0.0, serveLateral: 0.2).opponent)
            XCTAssertEqual(right, aims.aim(s, dragDp: 0.0).opponent)
            XCTAssertEqual(right, aims.aim(s, dragDp: 0.0, sender: s).opponent)
        }
    }

    // Kotlin: inBandAimsStayInsideTheTargetArmAndAreFinelyAdjustable
    func testInBandAimsStayInsideTheTargetArmAndAreFinelyAdjustable() {
        for g in tables {
            let aims = CrossAimMap(g)
            for s in g.seats {
                for sender in g.seats where sender != s {
                    var previous: (band: Int, aim: CrossAim)? = nil
                    for k in -1040...1040 {
                        let dp = Double(k) / 10.0 // |g| <= 2.6: every in-band aim
                        let aim = aims.aim(s, dragDp: dp, sender: sender)
                        XCTAssertFalse(aim.wide)
                        let local = g.toLocal(aim.opponent, aim.point)
                        XCTAssertTrue(abs(local.u) <= CrossAimMap.edgeU + 1e-12, "\(dp) \(local)")
                        let far: Double = CrossGeometry.reach - 0.12 + 1e-12
                        XCTAssertTrue(local.v >= CrossAimMap.sideNear - 1e-12 && local.v <= far, "\(dp) \(local)")
                        XCTAssertEqual(aim.opponent, g.owner(aim.point))
                        // Fine adjustment inside a band keeps the opponent and moves the target only a little.
                        let band = aimBand(aims, dp)
                        if let last = previous, last.band == band {
                            XCTAssertEqual(last.aim.opponent, aim.opponent)
                            XCTAssertTrue((aim.point - last.aim.point).length < 0.002)
                        }
                        previous = (band: band, aim: aim)
                    }
                }
            }
        }
    }

    // Kotlin: everyInBandAimReachesItsOpponent
    func testEveryInBandAimReachesItsOpponent() {
        for g in tables {
            let aims = CrossAimMap(g)
            for s in g.seats {
                for dp in [-104.0, -70.0, -40.0, -12.0, 0.0, 12.0, 40.0, 70.0, 104.0] {
                    let aim = aims.aim(s, dragDp: dp, sender: g.wrap(s + 1))
                    let launch = CrossShots.targeted(g, starter, from: g.home(s), height: 0.1, target: aim.point, pace: CrossShots.basePace(starter))
                    let event = fly(g, starter, g.home(s), 0.1, launch).firstEvent().event
                    XCTAssertEqual(aim.opponent, bounceOf(event)?.owner, "\(s) \(dp) \(String(describing: event))")
                }
            }
        }
    }

    // Kotlin: extremeDragAimsBeyondTheArmEndAndGoesOut
    func testExtremeDragAimsBeyondTheArmEndAndGoesOut() {
        for g in tables {
            let aims = CrossAimMap(g)
            for s in g.seats {
                for dp in [-120.0, 120.0, -200.0, 200.0, -110.0, 110.0] {
                    let aim = aims.aim(s, dragDp: dp)
                    XCTAssertTrue(aim.wide)
                    XCTAssertTrue(g.toLocal(aim.opponent, aim.point).v > CrossGeometry.reach)
                    XCTAssertNil(g.owner(aim.point))
                    let launch = CrossShots.targeted(g, starter, from: g.home(s), height: 0.1, target: aim.point, pace: CrossShots.basePace(starter))
                    let event = fly(g, starter, g.home(s), 0.1, launch).firstEvent().event
                    XCTAssertTrue(isLanded(event), "\(s) \(dp) \(String(describing: event))")
                }
            }
            XCTAssertFalse(aims.aim(0, dragDp: 104.0).wide)
            let far = aims.aim(0, dragDp: 120.0)
            let expected: Double = CrossGeometry.reach - 0.12 + 0.4 * 0.9
            XCTAssertEqual(expected, g.toLocal(far.opponent, far.point).v, accuracy: 1e-12)
            XCTAssertEqual(far, aims.aim(0, dragDp: 500.0))
        }
    }
}
