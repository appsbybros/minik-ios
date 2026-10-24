import XCTest
@testable import MinikTripleShot

// Area t-physics parity tests.
// 1. Ports of the Android unit tests (app/src/test/.../game): BasketballFeelTest, BasketballMovementTest,
//    BasketballVisualMotionTest, DribbleGestureTest — same assertions.
// 2. Spec 02 Appendix A golden vectors (A.1-A.10) with exact Float bit patterns. The expected values were
//    produced on the JVM by compiling the snapshot's own Kotlin (game/*.kt + model/*.kt, dd722e5) with the
//    harness work/t-physics/harness/PhysicsGolden.kt; every A.3/A.4 value printed in the spec is reproduced.
//    Regenerated for Android 6c38131 with the same harness compiled against the 6c38131 Kotlin (1ddda77 changed
//    TripleShotPhysics.step to exact constant-acceleration travel; 938db79 DribbleGesture needs two reversals).
//    The spec's printed A.3/A.4 values are dd722e5 values and no longer apply to the trajectories.
// The golden cases that need TripleShotCourtView helpers (backgroundTransform, buildPhysicsGeometry, the
// frame loop and the 1v1 hooks) use GoldenCourt below: a faithful test-only copy of those helpers
// (TripleShotCourtView.kt 516-603, 7008-7115, 7216-7360, 7376-7384, 5580-5601).

// MARK: - BasketballFeelTest.kt

final class BasketballFeelTest: XCTestCase {
    func testGentlePullHasBroaderSweetSpotWithoutRemovingMisses() {
        XCTAssertEqual(0, BasketballTouchShot.powerError(0.70), accuracy: 0.0001)
        XCTAssertTrue(abs(BasketballTouchShot.powerError(0.60)) < 0.06)
        XCTAssertTrue(abs(BasketballTouchShot.powerError(0.80)) < 0.06)
        XCTAssertTrue(BasketballTouchShot.powerError(0.15) < -0.5)
        XCTAssertTrue(BasketballTouchShot.powerError(1.2) > 0.45)
    }

    func testPreviewAndTouchReleaseUseTheSamePowerCurve() {
        var previous: Float = -10
        for i in 0...120 {
            let pull = Float(i) / Float(100)
            let s = BasketballTouchShot.skill(0.3, pull)
            XCTAssertEqual(0.3, s.aimError, accuracy: 0.0001)
            XCTAssertEqual(BasketballTouchShot.powerError(pull), (s.rawPeakGyro - 3.05) / 1.35, accuracy: 0.0001)
            XCTAssertTrue(s.powerError >= previous); previous = s.powerError
        }
        XCTAssertTrue(BasketballTouchShot.skill(0, 0.7, 0.5).powerError > 0)
    }

    func testCutsAllowTheTravelTimeAndRespectAthleticRatings() {
        let short = BasketballMovement.cutDurationMillis(30, 20, 70, 70)
        let far = BasketballMovement.cutDurationMillis(300, 230, 70, 70)
        XCTAssertTrue(far > short); XCTAssertTrue(far >= 2400)
        XCTAssertTrue(BasketballMovement.cutDurationMillis(300, 230, 95, 95) < BasketballMovement.cutDurationMillis(300, 230, 30, 30))
        XCTAssertEqual(3800 as Int64, BasketballMovement.cutDurationMillis(5000, 5000, 0, 0))
    }
}

// MARK: - BasketballMovementTest.kt

final class BasketballMovementTest: XCTestCase {
    func testSameDistanceAtThirtyAndSixtyFrames() {
        func run(_ frames: Int) -> Float {
            let dt = Float(1) / Float(frames)
            var x: Float = 0
            for _ in 0..<frames { x += BasketballMovement.step(1000 - x, 0, 70, 60, 1, dt).x }
            return x * 0.014
        }
        XCTAssertEqual(run(30), run(60), accuracy: 0.002)
        XCTAssertTrue(run(60) > 4)
    }

    func testDiagonalAndVerticalUseSameWorldSpeed() {
        let a = BasketballMovement.step(1000, 0, 70, 60, 1, 0.032)
        let b = BasketballMovement.step(0, 1000, 70, 60, 1, 0.032)
        XCTAssertEqual(a.x * 0.014, b.y * 0.034, accuracy: 0.0001)
    }

    func testArrivesWithoutOvershootingAndDoesNotTeleportAfterPause() {
        XCTAssertEqual(0.8, BasketballMovement.step(0.8, 2, 100, 100, 1, 0.08).x, accuracy: 0.001)
        XCTAssertTrue(BasketballMovement.step(1000, 1000, 100, 100, 1, 300).x < 30)
    }

    func testStrongerSpeedRatingActuallyMovesFurther() {
        XCTAssertTrue(BasketballMovement.step(1000, 0, 90, 50, 1, 0.04).x > BasketballMovement.step(1000, 0, 20, 50, 1, 0.04).x)
    }
}

// MARK: - BasketballVisualMotionTest.kt

final class BasketballVisualMotionTest: XCTestCase {
    func testFrontAndBackNeverMirrorWithSteeringCorrections() {
        let v = BasketballVisualMotion()
        for i in 0...80 { v.update(Int64(i) * 32, Float(i) * 2, 0, 0, 2, i % 2 == 0, false); XCTAssertFalse(v.mirror) }
    }

    func testTinyCorrectionsDoNotWalkOrFlipFacing() {
        let v = BasketballVisualMotion(); v.update(0, 0, 0, 0, 2, false, false)
        for i in 1...100 { v.update(Int64(i) * 32, i % 2 == 0 ? 0.1 : 0, 0, i % 2, 2, false, false) }
        XCTAssertEqual(0, v.facing); XCTAssertFalse(v.moving); XCTAssertEqual(0, v.frameIndex)
    }

    func testWalkingFollowsDistanceAndStopsWhenMovementStops() {
        let v = BasketballVisualMotion(); v.update(0, 0, 0, 0, 2, false, false)
        var changes = 0; var previous = 0
        for i in 1...30 {
            v.update(Int64(i) * 32, Float(i) * 2, 0, 0, 2, false, false)
            if previous != v.frameIndex { changes += 1 }
            previous = v.frameIndex
        }
        XCTAssertTrue(v.moving); XCTAssertTrue((1...5).contains(changes))
        v.update(1400, 60, 0, 0, 2, false, false); XCTAssertFalse(v.moving)
    }

    func testRealTurnSettlesAndActionPoseIsImmediate() {
        let v = BasketballVisualMotion(); v.update(0, 0, 0, 0, 2, false, false)
        v.update(100, 0, 0, 1, 2, false, false); v.update(350, 0, 0, 1, 2, false, false); XCTAssertEqual(1, v.facing)
        v.update(351, 0, 0, 2, 2, true, true); XCTAssertEqual(2, v.facing); XCTAssertTrue(v.mirror)
    }
}

// MARK: - DribbleGestureTest.kt

final class DribbleGestureTest: XCTestCase {
    // Android 6c38131: smoothSmallEventsRequireThreeLegs (two reversals form left-right-left).
    func testSmoothSmallEventsRequireThreeLegs() {
        let g = DribbleGesture(18); var time: Int64 = 1000
        for _ in 0..<12 { let t = time; time += 8; XCTAssertEqual(0, g.move(2, t)) }
        var results: [Int] = []
        for _ in 0..<12 { let t = time; time += 8; results.append(g.move(-2, t)) }
        XCTAssertTrue(results.allSatisfy { $0 == 0 })
        var third: [Int] = []
        for _ in 0..<12 { let t = time; time += 8; third.append(g.move(2, t)) }
        XCTAssertEqual(1, third.filter { $0 == 1 }.count)
    }

    func testJitterAndStraightMotionDoNotTrigger() {
        let g = DribbleGesture(18)
        for it in 0..<100 { XCTAssertEqual(0, g.move(it % 2 == 0 ? 2 : -2, 1000 + Int64(it) * 8)) }
        for it in 0..<100 { XCTAssertEqual(0, g.move(2, 2000 + Int64(it) * 8)) }
    }

    func testCancelAndLongPauseDoNotCarryOldGesture() {
        let g = DribbleGesture(18)
        _ = g.move(25, 1000); g.reset(); XCTAssertEqual(0, g.move(-25, 1200))
        XCTAssertEqual(0, g.move(25, 2500))
    }
}

// MARK: - Spec 02 Appendix A golden vectors

final class TripleShotPhysicsGoldenTests: XCTestCase {

    // A.1
    func testA1GeometriesFromTheCourtTransform() {
        for row in PhysicsGolden.geometries {
            let court = GoldenCourt(view: row.view)
            let t = court.backgroundTransform()
            let transform = [t.scaleX, t.scaleY, t.offsetX, t.offsetY]
            for (i, value) in transform.enumerated() { assertBits(value, row.transform[i], "\(row.view) transform[\(i)]") }
            let g = court.buildPhysicsGeometry()
            let fields = [g.gravityPxPerSec2, g.hoopCenterX, g.hoopY, g.leftRimX, g.rightRimX, g.rimColliderRadius, g.backboardX,
                          g.backboardTopY, g.backboardBottomY, g.netBottomY, g.netBottomLeftX, g.netBottomRightX, g.ballRadius]
            for (i, value) in fields.enumerated() { assertBits(value, row.geometry[i], "\(row.view) geometry[\(i)]") }
            assertBits(court.aimRangePx(), row.aimRange, "\(row.view) aimRangePx")
        }
        // Decimal cross-check with the spec table A.1 (portrait 1080 x 2400, density 2.625).
        let p = GoldenCourt(view: .P).buildPhysicsGeometry()
        XCTAssertEqual(p, TripleShotPhysics.Geometry(3648.0, 686.125, 531.25, 549.5625, 822.6875, 7.90625, 844.25, 335.9375,
                                                     620.3125, 789.0625, 620.0, 746.5, 32.8125))
    }

    // A.2
    func testA2SubstepSequences() {
        for row in PhysicsGolden.substeps {
            var remaining = gCoerceIn(fl(row.dt), 0.001, 0.045)
            var steps: [UInt32] = []
            while remaining > 0 {
                let step = gMin(remaining, GoldenCourt.MAX_PHYSICS_SUBSTEP_SECONDS)
                steps.append(step.bitPattern)
                remaining -= step
            }
            XCTAssertEqual(steps, row.steps, "substeps for frame dt \(fl(row.dt))")
        }
        XCTAssertEqual(GoldenCourt.MAX_PHYSICS_SUBSTEP_SECONDS.bitPattern, 0x3BB60B61)
    }

    // A.3: inputs, start points and launch.
    func testA3LaunchStateBits() {
        for c in PhysicsGolden.flightCases() {
            let court = GoldenCourt(view: c.view)
            let geometry = court.geometry()
            let start = court.start(c.start, geometry)
            assertBits(start.x, c.startX, "\(c.id) startX")
            assertBits(start.y, c.startY, "\(c.id) startY")
            let state = court.launch(c, geometry)
            assertBits(state.targetX, c.targetX, "\(c.id) targetX")
            XCTAssertEqual(state.pathMode, c.mode, "\(c.id) path mode")
            assertBits(state.expectedFlightSeconds, c.flightSeconds, "\(c.id) T")
            assertBits(state.vx, c.vx, "\(c.id) vx")
            assertBits(state.vy, c.vy, "\(c.id) vy")
            assertBits(state.initialVx, c.vx, "\(c.id) initialVx")
            assertBits(state.initialVy, c.vy, "\(c.id) initialVy")
            assertBits(state.curveAccelerationX, c.curve, "\(c.id) curve")
            assertBits(state.initialCurveAccelerationX, c.curve, "\(c.id) initial curve")
            assertBits(state.gravity, c.gravity, "\(c.id) gravity")
            XCTAssertEqual(state.rejectUpwardBasketEntry, c.reject, "\(c.id) reject flag")
        }
    }

    func testA3Flights60Hz() {
        for c in PhysicsGolden.flightCases() {
            let court = GoldenCourt(view: c.view)
            let geometry = court.geometry()
            let traceFrames: Set<Int> = Set(c.trace.map { $0.frame })
            let flight = court.run(court.launch(c, geometry), geometry, Float(1) / Float(60), c.reject, traceFrames)
            assertFlight(flight, c.hz60, "\(c.id) 60 Hz")
            // U1 60 Hz trace (frame, elapsed, x, y).
            XCTAssertEqual(flight.trace.count, c.trace.count, "\(c.id) trace count")
            for (i, expected) in c.trace.enumerated() where i < flight.trace.count {
                XCTAssertEqual(flight.trace[i].0, expected.frame)
                assertBits(flight.trace[i].1.elapsedSeconds, expected.elapsed, "\(c.id) f\(expected.frame) t")
                assertBits(flight.trace[i].1.x, expected.x, "\(c.id) f\(expected.frame) x")
                assertBits(flight.trace[i].1.y, expected.y, "\(c.id) f\(expected.frame) y")
            }
            // toOutcome at the end of the 60 Hz flight.
            let outcome = TripleShotPhysics.toOutcome(flight.state, geometry)
            XCTAssertEqual(outcome.made, c.outcome60.made, "\(c.id) outcome made")
            assertBits(outcome.targetOffsetX, c.outcome60.x, "\(c.id) outcome targetOffsetX")
            assertBits(outcome.targetOffsetY, c.outcome60.y, "\(c.id) outcome targetOffsetY")
            assertBits(outcome.quality, c.outcome60.quality, "\(c.id) outcome quality")
        }
    }

    func testA3Flights120Hz() {
        for c in PhysicsGolden.flightCases() {
            let court = GoldenCourt(view: c.view)
            let geometry = court.geometry()
            let flight = court.run(court.launch(c, geometry), geometry, Float(1) / Float(120), c.reject)
            assertFlight(flight, c.hz120, "\(c.id) 120 Hz")
        }
    }

    func testA3FlightsWithOneOnOneHooks() {
        var checked = 0
        for c in PhysicsGolden.flightCases() {
            guard let expected = c.oneOnOne else { continue }
            let court = GoldenCourt(view: c.view)
            court.oneOnOneEnabled = true
            let geometry = court.geometry()
            let flight = court.run(court.launch(c, geometry), geometry, Float(1) / Float(60), c.reject)
            assertFlight(flight, expected, "\(c.id) 1v1 hooks")
            checked += 1
        }
        XCTAssertEqual(checked, 14)   // P12-P16, P19-P22, L1 and the extra X2-X5
    }

    func testA3PreviewPositions() {
        for c in PhysicsGolden.flightCases() {
            let court = GoldenCourt(view: c.view)
            let geometry = court.geometry()
            let state = court.launch(c, geometry)
            let quarter = TripleShotPhysics.previewPosition(state, 0.25)
            assertBits(quarter.first, c.preview025.0, "\(c.id) preview(0.25).x")
            assertBits(quarter.second, c.preview025.1, "\(c.id) preview(0.25).y")
            let (x, y) = TripleShotPhysics.previewPosition(state: state, tSeconds: state.expectedFlightSeconds)
            assertBits(x, c.previewT.0, "\(c.id) preview(T).x")
            assertBits(y, c.previewT.1, "\(c.id) preview(T).y")
        }
    }

    /// Spec A.3 decimal summary (kind, contact counts, event times) as printed in the spec, 60 Hz loop. Android 6c38131
    /// (1ddda77, exact constant-acceleration travel) changes P5, P14, P18 and P21; the rows are the 6c38131 JVM harness
    /// values (the dd722e5 run of the same harness reproduces the spec's table).
    func testA3SpecSummaryTable() {
        let summary: [String: (kind: String, rim: Int, board: Int, end: String)] = [
            "P1": ("INVALID_BELOW", 0, 0, "outside"), "P2": ("INVALID_BELOW", 0, 0, "outside"),
            "P3": ("INVALID_BELOW", 0, 0, "outside"), "P4": ("INVALID_BELOW", 0, 0, "outside"),
            "P5": ("RIM_OUT", 1, 1, "outside"), "P6": ("RIM_IN", 1, 0, "madeExitedNet"),
            "P7": ("SWISH", 0, 0, "madeExitedNet"), "P8": ("INVALID_BELOW", 0, 0, "outside"),
            "P9": ("INVALID_BELOW", 0, 0, "outside"), "P10": ("BACKBOARD_OUT", 0, 1, "outside"),
            "P11": ("SWISH", 0, 0, "madeExitedNet"), "P12": ("RIM_OUT", 1, 0, "outside"),
            "P13": ("INVALID_BELOW", 1, 0, "outside"), "P14": ("SWISH", 0, 0, "madeExitedNet"),
            "P15": ("RIM_OUT", 1, 0, "outside"), "P16": ("INVALID_BELOW", 1, 0, "outside"),
            "P17": ("INVALID_BELOW", 1, 1, "outside"), "P18": ("RIM_OUT", 1, 0, "outside"),
            "P19": ("RIM_OUT", 1, 0, "outside"), "P20": ("BACKBOARD_OUT", 0, 1, "outside"),
            "P21": ("SWISH", 0, 0, "madeExitedNet"), "P22": ("RIM_OUT", 1, 0, "outside"),
            "L1": ("SWISH", 0, 0, "madeExitedNet"), "L2": ("SWISH", 0, 0, "madeExitedNet"),
            "U1": ("SWISH", 0, 0, "madeExitedNet"),
        ]
        var specCases = 0
        for c in PhysicsGolden.flightCases() where !c.id.hasPrefix("X") {
            specCases += 1
            let court = GoldenCourt(view: c.view)
            let geometry = court.geometry()
            let flight = court.run(court.launch(c, geometry), geometry, Float(1) / Float(60), c.reject)
            guard let row = summary[c.id] else { XCTFail("missing summary for \(c.id)"); continue }
            XCTAssertEqual(flight.kind, row.kind, c.id)
            XCTAssertEqual(flight.state.rimHits, row.rim, c.id)
            XCTAssertEqual(flight.state.backboardHits, row.board, c.id)
            XCTAssertEqual(flight.end, row.end, c.id)
        }
        XCTAssertEqual(specCases, 25)
        // Spec extra checks (6 decimals).
        let p1 = PhysicsGolden.flightCases()[0]
        let court = GoldenCourt(view: .P)
        let geometry = court.geometry()
        let state = court.launch(p1, geometry)
        XCTAssertEqual(state.expectedFlightSeconds, 1.062857, accuracy: 0.000001)
        let quarter = TripleShotPhysics.previewPosition(state, 0.25)
        XCTAssertEqual(quarter.first, 620.133911, accuracy: 0.0001)
        XCTAssertEqual(quarter.second, 790.809875, accuracy: 0.0001)
    }

    // A.4
    func testA4AimGuidePreview() {
        for row in PhysicsGolden.guides {
            let court = GoldenCourt(view: .P)
            let geometry = court.buildPhysicsGeometry()
            let start = court.start(.hand(690, 1085, 130), geometry)
            let pull = fl(row.pull)
            let aim = fl(row.aim)
            let skill = BasketballTouchShot.skill(aim, pull)
            let skillBits = [skill.aimError, skill.powerError, skill.arcError, skill.rawPeakGyro, skill.rawReleasePitchDeg]
            for (i, value) in skillBits.enumerated() { assertBits(value, row.skill[i], "guide \(pull) skill[\(i)]") }
            let preview = TripleShotPhysics.createLaunch(
                skill: skill,
                startX: start.x,
                startY: start.y,
                targetX: geometry.hoopCenterX + aim * court.aimRangePx(),
                targetY: geometry.hoopY,
                pullBack01: gCoerceAtLeast(pull, 0.08),
                geometry: geometry,
                distanceDifficulty: 0.54
            )
            assertBits(preview.expectedFlightSeconds, row.flightSeconds, "guide \(pull) T")
            let fractions: [Float] = [1.04, 0.88, 0.66, 0.46, 0.30, 0.18]
            let fraction = court.lerp(fractions[0], fractions[1], 0)
            let total = preview.expectedFlightSeconds * fraction
            assertBits(total, row.total, "guide \(pull) total")
            var bankTime: Float? = nil
            var points: [(Float, Float)] = []
            var reason = "reachedTotal"
            var hash = goldenFnvOffset
            while preview.elapsedSeconds < total {
                let result = TripleShotPhysics.step(preview, geometry, gMin(0.04, total - preview.elapsedSeconds))
                points.append((preview.x, preview.y))
                hash = goldenFnv(hash, preview.x); hash = goldenFnv(hash, preview.y)
                if result.backboardImpactSpeed > 0 && bankTime == nil { bankTime = preview.elapsedSeconds }
                var bankTailDone = false
                if let bank = bankTime { bankTailDone = preview.elapsedSeconds - bank >= GoldenCourt.BANK_PREVIEW_AFTER_HIT_SECONDS }
                if result.rimImpactSpeed > 0 || preview.enteredBasketFromBelow || bankTailDone {
                    reason = result.rimImpactSpeed > 0 ? "rim" : (preview.enteredBasketFromBelow ? "enteredBasketFromBelow" : "bank")
                    break
                }
            }
            XCTAssertEqual(points.count, row.points, "guide \(pull) point count")
            XCTAssertEqual(reason, row.reason, "guide \(pull) stop reason")
            if let first = points.first, let last = points.last {
                assertBits(first.0, row.first.0, "guide \(pull) first x"); assertBits(first.1, row.first.1, "guide \(pull) first y")
                assertBits(last.0, row.last.0, "guide \(pull) last x"); assertBits(last.1, row.last.1, "guide \(pull) last y")
            }
            XCTAssertEqual(hash, row.hash, "guide \(pull) point hash")
        }
    }

    // A.5
    func testA5PowerErrorTable() {
        for (pull, expected) in PhysicsGolden.powerErrors {
            assertBits(BasketballTouchShot.powerError(fl(pull)), expected, "powerError(\(fl(pull)))")
            assertBits(BasketballTouchShot.powerError(pull: fl(pull)), expected, "powerError(pull: \(fl(pull)))")
        }
        XCTAssertEqual(BasketballTouchShot.IDEAL_PULL.bitPattern, 0x3F333333)
        // Spec A.5 decimals.
        XCTAssertEqual(BasketballTouchShot.powerError(0.00), -0.790815, accuracy: 0.000001)
        XCTAssertEqual(BasketballTouchShot.powerError(0.85), 0.098222, accuracy: 0.000001)
        XCTAssertEqual(BasketballTouchShot.powerError(1.50), 0.538963, accuracy: 0.000001)
        XCTAssertEqual(BasketballTouchShot.powerError(-0.50), -0.790815, accuracy: 0.000001)
        XCTAssertEqual(BasketballTouchShot.powerError(0.58), -0.060444, accuracy: 0.000001)
    }

    func testA5SkillVectors() {
        for row in PhysicsGolden.skills {
            let s = BasketballTouchShot.skill(fl(row.input[0]), fl(row.input[1]), fl(row.input[2]))
            let fields = [s.aimError, s.powerError, s.arcError, s.rawPeakGyro, s.rawReleasePitchDeg]
            for (i, value) in fields.enumerated() {
                assertBits(value, row.output[i], "skill(\(fl(row.input[0])), \(fl(row.input[1])), \(fl(row.input[2])))[\(i)]")
            }
        }
        let labeled = BasketballTouchShot.skill(aim: 0.3, pull: 0.70)
        let positional = BasketballTouchShot.skill(0.3, 0.70, 0)
        XCTAssertEqual([labeled.aimError, labeled.powerError, labeled.arcError, labeled.rawPeakGyro, labeled.rawReleasePitchDeg].map { $0.bitPattern },
                       [positional.aimError, positional.powerError, positional.arcError, positional.rawPeakGyro,
                        positional.rawReleasePitchDeg].map { $0.bitPattern })
        for i in 0...120 {
            let pull = Float(i) / Float(100)
            let s = BasketballTouchShot.skill(0.3, pull)
            assertBits(s.powerError, PhysicsGolden.skillLoop[i].0, "loop \(i) powerError")
            assertBits(s.rawPeakGyro, PhysicsGolden.skillLoop[i].1, "loop \(i) rawPeakGyro")
        }
    }

    // A.6
    func testA6ScoringEngine() {
        let engine = TripleShotScoringEngine()
        for row in PhysicsGolden.scoring {
            let d = engine.score(row.quality, row.made)
            let call = "score(\(row.quality), \(row.made))"
            XCTAssertEqual(d.answerQualityPercent, row.answerQualityPercent, call)
            XCTAssertEqual(d.answerCorrect, row.answerCorrect, call)
            XCTAssertEqual(d.knowledgeMultiplier, row.knowledgeMultiplier, call)
            XCTAssertEqual(d.knowledgePoints, row.knowledgePoints, call)
            XCTAssertEqual(d.basketPoints, row.basketPoints, call)
            XCTAssertEqual(d.totalPoints, row.totalPoints, call)
            XCTAssertEqual(d.knowledgeStreak, row.knowledgeStreak, call)
            XCTAssertEqual(d.shootingStreak, row.shootingStreak, call)
            XCTAssertEqual(d.bestKnowledgeStreak, row.bestKnowledgeStreak, call)
            XCTAssertEqual(d.bestShootingStreak, row.bestShootingStreak, call)
            XCTAssertEqual(engine.totalScore, row.totalScore, call)
            XCTAssertEqual(engine.correctAnswers, row.correctAnswers, call)
            XCTAssertEqual(engine.madeShots, row.madeShots, call)
            XCTAssertEqual(engine.shots, row.shots, call)
            XCTAssertEqual(engine.knowledgeStreak, row.knowledgeStreak, call)
            XCTAssertEqual(engine.shootingStreak, row.shootingStreak, call)
            XCTAssertEqual(engine.bestKnowledgeStreak, row.bestKnowledgeStreak, call)
            XCTAssertEqual(engine.bestShootingStreak, row.bestShootingStreak, call)
        }
        let labeled = TripleShotScoringEngine().score(answerQualityPercent: 67, made: true)
        XCTAssertEqual(labeled.knowledgePoints, 2)
        XCTAssertEqual(labeled.totalPoints, 4)
    }

    // A.7
    func testA7MovementSteps() {
        for m in PhysicsGolden.movementSteps {
            let s = BasketballMovement.step(fl(m.dx), fl(m.dy), m.speed, m.agility, fl(m.scale), fl(m.dt))
            let call = "step(\(fl(m.dx)), \(fl(m.dy)), \(m.speed), \(m.agility), \(fl(m.scale)), \(fl(m.dt)))"
            assertBits(s.x, m.x, "\(call).x")
            assertBits(s.y, m.y, "\(call).y")
            XCTAssertEqual(s, BasketballMovement.step(dx: fl(m.dx), dy: fl(m.dy), speed: m.speed, agility: m.agility,
                                                      scale: fl(m.scale), dtSeconds: fl(m.dt)), call)
        }
        func run(_ frames: Int) -> Float {
            let dt = Float(1) / Float(frames)
            var x: Float = 0
            for _ in 0..<frames { x += BasketballMovement.step(1000 - x, 0, 70, 60, 1, dt).x }
            return x * 0.014
        }
        assertBits(run(30), PhysicsGolden.movementRun30, "run(30)")
        assertBits(run(60), PhysicsGolden.movementRun60, "run(60)")
    }

    func testA7CutDurations() {
        for c in PhysicsGolden.cutDurations {
            XCTAssertEqual(BasketballMovement.cutDurationMillis(Float(c.dx), Float(c.dy), c.speed, c.agility), c.millis,
                           "cutDurationMillis(\(c.dx), \(c.dy), \(c.speed), \(c.agility))")
            XCTAssertEqual(BasketballMovement.cutDurationMillis(dx: Float(c.dx), dy: Float(c.dy), speed: c.speed, agility: c.agility), c.millis)
        }
    }

    // A.8
    func testA8DribbleGesture() {
        do {
            let g = DribbleGesture(18); var time: Int64 = 1000
            var rows: [[Int]] = []
            for (dx, period) in [(Float(2), Int64(8)), (Float(-2), Int64(8)), (Float(2), Int64(8)), (Float(-2), Int64(40))] {
                var row: [Int] = []
                for _ in 0..<12 { let t = time; time += period; row.append(g.move(dx, t)) }
                rows.append(row)
            }
            XCTAssertEqual(rows, PhysicsGolden.dribble1)
        }
        do {
            let g = DribbleGesture(47.25)
            let dxs: [Float] = [20, 20, 20, -10, -20, -20, -20, 30, 30, 0, 30]
            var r: [Int] = []
            for (i, dx) in dxs.enumerated() { r.append(g.move(dx, 100 * Int64(i + 1))) }
            XCTAssertEqual(r, PhysicsGolden.dribble2)
            let then = [g.move(50, 1000), g.move(-50, 1700), g.move(50, 1800)]
            XCTAssertEqual(then, PhysicsGolden.dribble2Then)
        }
        do {
            let g = DribbleGesture(18)
            var r: [Int] = []
            for k in 0..<6 { r.append(g.move(k % 2 == 0 ? 20 : -20, 1000 + Int64(k) * 100)) }
            XCTAssertEqual(r, PhysicsGolden.dribble3)
        }
        do {
            let g = DribbleGesture(18)
            var r: [Int] = []
            let script: [(Float, Int64)] = [(20, 1000), (-20, 1100), (20, 1700), (-20, 2400), (20, 2500), (20, 2600)]
            for (dx, t) in script { r.append(g.move(dx, t)) }
            XCTAssertEqual(r, PhysicsGolden.dribble4)
        }
        do {
            let g = DribbleGesture(18, 100)
            var r: [Int] = []
            for k in 0..<6 { r.append(g.move(k % 2 == 0 ? 20 : -20, 1000 + Int64(k) * 150)) }
            g.reset(); r.append(g.move(-20, 1950)); r.append(g.move(20, 2000))
            XCTAssertEqual(r, PhysicsGolden.dribble5)
            let labeled = DribbleGesture(legDistance: 18, cooldownMs: 100)
            XCTAssertEqual(labeled.move(dx: 20, now: 1000), 0)
            XCTAssertEqual(labeled.move(dx: -20, now: 1150), 0)
            XCTAssertEqual(labeled.move(dx: 20, now: 1300), 1)
        }
    }

    // A.9
    func testA9VisualMotionScript() {
        let v = BasketballVisualMotion()
        var rows: [(Int, Bool, Bool, Int)] = []
        func snap() { rows.append((v.facing, v.mirror, v.moving, v.frameIndex)) }
        v.update(0, 0, 0, 0, 1, false, false); snap()
        for i in 1...40 {
            v.update(Int64(i) * 32, Float(i) * 2, 0, i < 10 ? 0 : 1, 1, i >= 20, false); snap()
        }
        v.update(1512, 80, 0, 1, 1, true, false); snap()
        v.update(1522, 80, 0, 2, 1, false, true); snap()
        v.update(1532, 300, 0, 2, 1, false, false); snap()
        assertRows(rows, PhysicsGolden.visual, "visual motion")

        let t = BasketballVisualMotion()
        var turn: [(Int, Bool, Bool, Int)] = []
        let script: [(Int64, Int, Bool, Bool)] = [
            (0, 0, false, false), (100, 1, false, false), (319, 1, false, false), (320, 1, false, false),
            (350, 2, true, false), (500, 2, true, false), (570, 2, true, false), (679, 2, true, false), (680, 2, true, false),
            (700, 2, false, false), (879, 2, false, false), (880, 2, false, false), (881, 0, true, true), (882, 2, true, true),
        ]
        for (now, wanted, mirror, committed) in script {
            t.update(now: now, nextX: 0, nextY: 0, wantedFacing: wanted, sideFacing: 2, wantedMirror: mirror, committedAction: committed)
            turn.append((t.facing, t.mirror, t.moving, t.frameIndex))
        }
        assertRows(turn, PhysicsGolden.visualTurn, "visual turn")
    }

    // ShotState / API semantics the callers rely on.
    func testShotStateIsAReferenceTypeAndCopyCopiesEveryProperty() {
        let court = GoldenCourt(view: .P)
        let geometry = court.geometry()
        let state = court.launch(PhysicsGolden.flightCases()[4], geometry)   // P5: rim contacts
        for _ in 0..<150 { TripleShotPhysics.step(state, geometry, GoldenCourt.MAX_PHYSICS_SUBSTEP_SECONDS) }
        let alias = state
        alias.vx = 1
        XCTAssertEqual(state.vx, 1)
        let copy = state.copy()
        XCTAssertFalse(copy === state)
        XCTAssertTrue(sameState(copy, state))
        copy.x += 10
        copy.rimHits += 1
        XCTAssertFalse(sameState(copy, state))
        let moved = state.copy(x: 5, made: true)
        XCTAssertEqual(moved.x, 5)
        XCTAssertTrue(moved.made)
        XCTAssertEqual(moved.previousX.bitPattern, state.previousX.bitPattern)
        XCTAssertEqual(moved.elapsedSeconds.bitPattern, state.elapsedSeconds.bitPattern)
    }

    func testLaunchDefaultsMatchTheKotlinConstructorDefaults() {
        let court = GoldenCourt(view: .P)
        let geometry = court.geometry()
        let state = court.launch(PhysicsGolden.flightCases()[7], geometry)   // P8: SIDE_ARC with a curve
        XCTAssertEqual(state.previousX.bitPattern, state.x.bitPattern)
        XCTAssertEqual(state.previousY.bitPattern, state.y.bitPattern)
        XCTAssertEqual(state.x.bitPattern, state.startX.bitPattern)
        XCTAssertEqual(state.maxHeightReachedY.bitPattern, state.startY.bitPattern)
        XCTAssertEqual(state.curveAccelerationX.bitPattern, state.initialCurveAccelerationX.bitPattern)
        XCTAssertEqual(state.closestDistanceToHoop, Float.greatestFiniteMagnitude)
        XCTAssertEqual(state.elapsedSeconds, 0)
        XCTAssertFalse(state.made); XCTAssertFalse(state.touchingNet); XCTAssertFalse(state.enteredBasketFromBelow)
        XCTAssertEqual(state.rimHits, 0); XCTAssertEqual(state.backboardHits, 0)
        // Kotlin positional constructor (TripleShotShotPresentationTest form).
        let unit = TripleShotPhysics.Geometry(1200, 750, 340, 655, 845, 5, 860, 215, 397, 505, 704, 792, 20)
        XCTAssertEqual(unit, TripleShotPhysics.Geometry(gravityPxPerSec2: 1200, hoopCenterX: 750, hoopY: 340, leftRimX: 655,
                                                        rightRimX: 845, rimColliderRadius: 5, backboardX: 860, backboardTopY: 215,
                                                        backboardBottomY: 397, netBottomY: 505, netBottomLeftX: 704,
                                                        netBottomRightX: 792, ballRadius: 20))
        let positional = TripleShotPhysics.ShotState(430, 700, 0, -500, 430, 700, 750, 340, 0, -500, 1200, 1, .NORMAL, 0)
        XCTAssertEqual(positional.previousX, 430); XCTAssertEqual(positional.previousY, 700)
        XCTAssertEqual(positional.maxHeightReachedY, 700); XCTAssertEqual(positional.curveAccelerationX, 0)
        XCTAssertFalse(positional.rejectUpwardBasketEntry)
        XCTAssertEqual(TripleShotPhysics.ShotPathMode.allCases.map { $0.name }, ["NORMAL", "SIDE_ARC", "HIGH_LOB"])
        XCTAssertEqual(TripleShotPhysics.ShotPathMode.HIGH_LOB.ordinal, 2)
    }

    func testStepWithNonPositiveDtChangesNothing() {
        let court = GoldenCourt(view: .P)
        let geometry = court.geometry()
        let state = court.launch(PhysicsGolden.flightCases()[0], geometry)
        for _ in 0..<20 { TripleShotPhysics.step(state, geometry, GoldenCourt.MAX_PHYSICS_SUBSTEP_SECONDS) }
        let before = state.copy()
        XCTAssertEqual(TripleShotPhysics.step(state, geometry, 0), TripleShotPhysics.StepResult())
        XCTAssertEqual(TripleShotPhysics.step(state: state, geometry: geometry, dtSeconds: -1), TripleShotPhysics.StepResult())
        XCTAssertTrue(sameState(before, state))
        // previewPosition clamps negative time to the release point.
        let origin = TripleShotPhysics.previewPosition(state, -1)
        XCTAssertEqual(origin.first.bitPattern, state.startX.bitPattern)
        XCTAssertEqual(origin.second.bitPattern, state.startY.bitPattern)
    }

    // MARK: helpers

    private func assertFlight(_ flight: GoldenFlightResult, _ expected: GoldenFlightExpect, _ what: String,
                              file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertEqual(flight.kind, expected.kind, "\(what) kind", file: file, line: line)
        XCTAssertEqual(flight.end, expected.end, "\(what) end reason", file: file, line: line)
        XCTAssertEqual(flight.frames, expected.frames, "\(what) frames", file: file, line: line)
        XCTAssertEqual(flight.substeps, expected.substeps, "\(what) substeps", file: file, line: line)
        XCTAssertEqual(flight.madeAt?.bitPattern, expected.madeAt, "\(what) madeAt", file: file, line: line)
        XCTAssertEqual(flight.events.count, expected.eventCount, "\(what) event count", file: file, line: line)
        for (i, event) in expected.events.enumerated() where i < flight.events.count {
            XCTAssertEqual(flight.events[i].0, event.0, "\(what) event \(i) name", file: file, line: line)
            assertBits(flight.events[i].1, event.1, "\(what) event \(i) (\(event.0)) time", file: file, line: line)
        }
        XCTAssertEqual(flight.hash, expected.hash, "\(what) trajectory hash", file: file, line: line)
        XCTAssertEqual(flight.loose?.0.bitPattern, expected.loose?.0, "\(what) loose vx", file: file, line: line)
        XCTAssertEqual(flight.loose?.1.bitPattern, expected.loose?.1, "\(what) loose vy", file: file, line: line)
        let s = flight.state
        let e = expected.finalState
        assertBits(s.x, e.x, "\(what) final x", file: file, line: line)
        assertBits(s.y, e.y, "\(what) final y", file: file, line: line)
        assertBits(s.vx, e.vx, "\(what) final vx", file: file, line: line)
        assertBits(s.vy, e.vy, "\(what) final vy", file: file, line: line)
        assertBits(s.previousX, e.previousX, "\(what) final previousX", file: file, line: line)
        assertBits(s.previousY, e.previousY, "\(what) final previousY", file: file, line: line)
        assertBits(s.elapsedSeconds, e.elapsed, "\(what) final elapsed", file: file, line: line)
        assertBits(s.curveAccelerationX, e.curve, "\(what) final curve", file: file, line: line)
        assertBits(s.maxHeightReachedY, e.maxHeight, "\(what) final maxHeightReachedY", file: file, line: line)
        assertBits(s.closestDistanceToHoop, e.closest, "\(what) final closestDistanceToHoop", file: file, line: line)
        XCTAssertEqual(s.made, e.made, "\(what) final made", file: file, line: line)
        XCTAssertEqual(s.rimHits, e.rimHits, "\(what) final rimHits", file: file, line: line)
        XCTAssertEqual(s.backboardHits, e.backboardHits, "\(what) final backboardHits", file: file, line: line)
        XCTAssertEqual(s.touchingNet, e.touchingNet, "\(what) final touchingNet", file: file, line: line)
        XCTAssertEqual(s.enteredBasketFromBelow, e.below, "\(what) final enteredBasketFromBelow", file: file, line: line)
    }

    private func assertRows(_ actual: [(Int, Bool, Bool, Int)], _ expected: [(Int, Bool, Bool, Int)], _ what: String,
                            file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertEqual(actual.count, expected.count, "\(what) row count", file: file, line: line)
        for (i, row) in expected.enumerated() where i < actual.count {
            let a = actual[i]
            XCTAssertTrue(a.0 == row.0 && a.1 == row.1 && a.2 == row.2 && a.3 == row.3,
                          "\(what) row \(i): got \(a), expected \(row)", file: file, line: line)
        }
    }

    private func sameState(_ a: TripleShotPhysics.ShotState, _ b: TripleShotPhysics.ShotState) -> Bool {
        let floatsA = [a.x, a.y, a.vx, a.vy, a.startX, a.startY, a.targetX, a.targetY, a.initialVx, a.initialVy, a.gravity,
                       a.expectedFlightSeconds, a.initialCurveAccelerationX, a.curveAccelerationX, a.previousX, a.previousY,
                       a.elapsedSeconds, a.maxHeightReachedY, a.closestDistanceToHoop]
        let floatsB = [b.x, b.y, b.vx, b.vy, b.startX, b.startY, b.targetX, b.targetY, b.initialVx, b.initialVy, b.gravity,
                       b.expectedFlightSeconds, b.initialCurveAccelerationX, b.curveAccelerationX, b.previousX, b.previousY,
                       b.elapsedSeconds, b.maxHeightReachedY, b.closestDistanceToHoop]
        return floatsA.map { $0.bitPattern } == floatsB.map { $0.bitPattern } &&
            a.pathMode == b.pathMode && a.made == b.made && a.rimHits == b.rimHits && a.backboardHits == b.backboardHits &&
            a.touchingNet == b.touchingNet && a.rejectUpwardBasketEntry == b.rejectUpwardBasketEntry &&
            a.enteredBasketFromBelow == b.enteredBasketFromBelow
    }
}

// MARK: - A.10 kotlin.random parity used by the physics callers (1v1 roll, steal deflection, bot reads)

final class TripleShotPhysicsRandomParityTests: XCTestCase {
    func testA10KotlinRandomDraws() {
        let r = KotlinRandom(seed: Int64(12345))
        XCTAssertEqual([r.nextInt(100), r.nextInt(100), r.nextInt(100)], PhysicsGolden.random12345Ints)
        XCTAssertEqual([r.nextBoolean(), r.nextBoolean(), r.nextBoolean()], PhysicsGolden.random12345Booleans)
        XCTAssertEqual([r.nextFloat().bitPattern, r.nextFloat().bitPattern, r.nextFloat().bitPattern], PhysicsGolden.random12345Floats)
        let ri = KotlinRandom(seed: Int(-7))   // Kotlin Random(-7) (Int seed) == Random(-7L)
        XCTAssertEqual(ri.nextFloat().bitPattern, PhysicsGolden.randomMinus7.0)
        XCTAssertEqual(ri.nextFloat().bitPattern, PhysicsGolden.randomMinus7.1)
        XCTAssertEqual(ri.nextBoolean(), PhysicsGolden.randomMinus7.2)
    }

    func testA10OneOnOneRollSeeds() {
        // TripleShotOneOnOneFragment.kt 1269: Random(seed xor (sequence * salt) xor chance.toLong().shl(17)).
        let seed: Int64 = 1_760_000_000_000
        let sequence: Int64 = 1
        let salt: Int64 = 0x53484F5448554D41
        for row in PhysicsGolden.rolls {
            let r = KotlinRandom(seed: seed ^ (sequence &* salt) ^ (Int64(row.chance) << 17))
            XCTAssertEqual(r.nextInt(100), row.roll, "chance \(row.chance)")
            XCTAssertEqual(r.nextBoolean(), row.dir, "chance \(row.chance)")
            XCTAssertEqual(r.nextFloat().bitPattern, row.u, "chance \(row.chance)")
        }
    }

    func testA10BooleanListHashAndStealDeflectionSeed() {
        for (list, expected) in PhysicsGolden.listHashes {
            XCTAssertEqual(JavaHash.ofList(list.map { JavaHash.of($0) }), expected, "\(list)")
        }
        // TripleShotCourtView.kt 4340: serial * 1103515245L + x.toBits().toLong() * 31L + y.toBits().toLong().
        let s = PhysicsGolden.steal
        let x = Float(bitPattern: s.x)
        let y = Float(bitPattern: s.y)
        let serial: Int64 = 3
        let seedBits = serial &* 1_103_515_245 &+ Int64(x.toBits()) &* 31 &+ Int64(y.toBits())
        XCTAssertEqual(seedBits, s.seedBits)
        XCTAssertEqual(seedBits.toInt(), s.seed)
        let random = KotlinRandom(seed: seedBits.toInt())
        XCTAssertEqual(random.nextBoolean(), s.side)
        XCTAssertEqual(random.nextFloat().bitPattern, s.bucket)
        XCTAssertEqual(random.nextFloat().bitPattern, s.speed)
    }
}

// MARK: - Golden harness: test-only copy of the TripleShotCourtView helpers used to produce the vectors

private func fl(_ bits: UInt32) -> Float { return Float(bitPattern: bits) }

private func hex32(_ bits: UInt32) -> String { return String(format: "0x%08X", bits) }

private func assertBits(_ actual: Float, _ expected: UInt32, _ what: @autoclosure () -> String,
                        file: StaticString = #filePath, line: UInt = #line) {
    XCTAssertEqual(actual.bitPattern, expected,
                   "\(what()): got \(actual) [\(hex32(actual.bitPattern))], expected \(fl(expected)) [\(hex32(expected))]",
                   file: file, line: line)
}

/// Kotlin `Float.coerceIn` (comparisons in this order; NaN passes through).
private func gCoerceIn(_ v: Float, _ lo: Float, _ hi: Float) -> Float {
    if v < lo { return lo }
    if v > hi { return hi }
    return v
}

private func gCoerceAtLeast(_ v: Float, _ lo: Float) -> Float { return v < lo ? lo : v }

/// Java `Math.min(float, float)` / `Math.max(float, float)`.
private func gMin(_ a: Float, _ b: Float) -> Float {
    if a.isNaN || b.isNaN { return Float.nan }
    if a == 0 && b == 0 { return a.sign == .minus ? a : b }
    return a <= b ? a : b
}

private func gMax(_ a: Float, _ b: Float) -> Float {
    if a.isNaN || b.isNaN { return Float.nan }
    if a == 0 && b == 0 { return a.sign == .minus ? b : a }
    return a >= b ? a : b
}

/// FNV-1a 64 over the little-endian bytes of the Float bit patterns (same as the Kotlin harness).
private let goldenFnvOffset: UInt64 = 0xCBF29CE484222325

private func goldenFnv(_ seed: UInt64, _ x: Float) -> UInt64 {
    var h = seed
    let bits = x.bitPattern
    for k in 0..<4 {
        h ^= UInt64((bits >> UInt32(8 * k)) & 0xFF)
        h = h &* 0x100000001B3
    }
    return h
}

private enum GoldenView { case P, L, U }

private enum GoldenStart {
    /// Synthetic hand: (X(footX), Y(footY) - dp(liftDp)) through the court transform.
    case hand(Float, Float, Float)
    /// (hoopCenterX - dx, hoopY + dy).
    case hoopMinusXPlusY(Float, Float)
    /// (leftRimX - ballRadius * 1.10, hoopY + dy): oneOnOneSafeFinishReleaseStart's nudged layup start.
    case leftRimSafe(Float)
    case fixed(Float, Float)
}

private struct GoldenShotEnd {
    let x: UInt32
    let y: UInt32
    let vx: UInt32
    let vy: UInt32
    let previousX: UInt32
    let previousY: UInt32
    let elapsed: UInt32
    let curve: UInt32
    let maxHeight: UInt32
    let closest: UInt32
    let made: Bool
    let rimHits: Int
    let backboardHits: Int
    let touchingNet: Bool
    let below: Bool
}

private struct GoldenFlightExpect {
    let kind: String
    let end: String
    let frames: Int
    let substeps: Int
    let madeAt: UInt32?
    let eventCount: Int
    /// The first (up to) 24 events: ("rim" | "board" | "below" | "made" | "relaxed", elapsedSeconds bits).
    let events: [(String, UInt32)]
    /// FNV-1a 64 of (x, y, vx, vy) after every substep: the whole trajectory, bit for bit.
    let hash: UInt64
    let loose: (UInt32, UInt32)?
    let finalState: GoldenShotEnd
}

private struct GoldenFlightCase {
    let id: String
    let view: GoldenView
    let start: GoldenStart
    let startX: UInt32
    let startY: UInt32
    let aim: UInt32
    let power: UInt32
    let pull: UInt32
    let diff: UInt32
    let neutral: Bool
    let compact: Bool
    let reject: Bool
    let targetX: UInt32
    let mode: TripleShotPhysics.ShotPathMode
    let flightSeconds: UInt32
    let vx: UInt32
    let vy: UInt32
    let curve: UInt32
    let gravity: UInt32
    let hz60: GoldenFlightExpect
    let hz120: GoldenFlightExpect
    let oneOnOne: GoldenFlightExpect?
    let outcome60: (made: Bool, x: UInt32, y: UInt32, quality: UInt32)
    let preview025: (UInt32, UInt32)
    let previewT: (UInt32, UInt32)
    let trace: [(frame: Int, elapsed: UInt32, x: UInt32, y: UInt32)]
}

private struct GoldenGuide {
    let pull: UInt32
    let aim: UInt32
    let skill: [UInt32]
    let flightSeconds: UInt32
    let total: UInt32
    let points: Int
    let first: (UInt32, UInt32)
    let last: (UInt32, UInt32)
    let reason: String
    let hash: UInt64
}

private struct GoldenScore {
    let quality: Int
    let made: Bool
    let answerQualityPercent: Int
    let answerCorrect: Bool
    let knowledgeMultiplier: Int
    let knowledgePoints: Int
    let basketPoints: Int
    let totalPoints: Int
    let knowledgeStreak: Int
    let shootingStreak: Int
    let bestKnowledgeStreak: Int
    let bestShootingStreak: Int
    let totalScore: Int
    let correctAnswers: Int
    let madeShots: Int
    let shots: Int
}

private struct GoldenFlightResult {
    let kind: String
    let end: String
    let frames: Int
    let substeps: Int
    let madeAt: Float?
    let events: [(String, Float)]
    let hash: UInt64
    let loose: (Float, Float)?
    let trace: [(Int, TripleShotPhysics.ShotState)]
    let state: TripleShotPhysics.ShotState
}

/// Faithful copy of the TripleShotCourtView pieces the physics depends on (view px, Float, same order).
private final class GoldenCourt {
    static let BACKGROUND_WIDTH: Float = 1024
    static let BACKGROUND_HEIGHT: Float = 1536
    static let BACKGROUND_HORIZONTAL_SCALE: Float = 0.92
    static let BACKGROUND_HORIZONTAL_FOCUS: Float = 1.00
    static let SRC_HOOP_CENTER_X: Float = 750
    static let SRC_HOOP_PLANE_Y: Float = 340
    static let SRC_RIM_LEFT_X: Float = 655
    static let SRC_RIM_RIGHT_X: Float = 845
    static let SRC_BACKBOARD_COLLISION_X: Float = 860
    static let SRC_BACKBOARD_TOP_Y: Float = 215
    static let SRC_BACKBOARD_BOTTOM_Y: Float = 397
    static let SRC_NET_BOTTOM_LEFT_X: Float = 704
    static let SRC_NET_BOTTOM_RIGHT_X: Float = 792
    static let SRC_NET_BOTTOM_Y: Float = 505
    static let SRC_AIM_RANGE_X: Float = 130
    static let BALL_PHYSICS_RADIUS_DP: Float = 12.5
    static let MAX_PHYSICS_SUBSTEP_SECONDS: Float = Float(1) / Float(180)
    static let MAX_SHOT_SECONDS: Float = 4.2
    static let MIN_POST_MAKE_SECONDS: Float = 0.24
    static let MAX_POST_MAKE_SECONDS: Float = 0.95
    static let ONE_ON_ONE_IMPACT_REBOUND_MIN_SECONDS: Float = 0.48
    static let ONE_ON_ONE_AIRBALL_REBOUND_MIN_SECONDS: Float = 0.82
    static let ONE_ON_ONE_AIRBALL_RELEASE_BELOW_NET_DP: Float = 48
    static let ONE_ON_ONE_RIM_POST_IMPACT_DAMPING: Float = 0.80
    static let ONE_ON_ONE_BOARD_POST_IMPACT_X_DAMPING: Float = 0.80
    static let ONE_ON_ONE_BOARD_POST_IMPACT_Y_DAMPING: Float = 0.88
    static let ONE_ON_ONE_CLOSE_FINISH_RIM_DAMPING: Float = 0.54
    static let ONE_ON_ONE_CLOSE_FINISH_BOARD_X_DAMPING: Float = 0.58
    static let ONE_ON_ONE_CLOSE_FINISH_BOARD_Y_DAMPING: Float = 0.66
    static let ONE_ON_ONE_NET_MAKE_CONFIRM_T: Float = 0.30
    static let BANK_PREVIEW_AFTER_HIT_SECONDS: Float = 0.18

    struct Transform {
        let scaleX: Float
        let scaleY: Float
        let offsetX: Float
        let offsetY: Float
    }

    let view: GoldenView
    let width: Int
    let height: Int
    let density: Float
    let landscape: Bool
    var oneOnOneEnabled = false

    init(view: GoldenView) {
        self.view = view
        switch view {
        case .P: width = 1080; height = 2400; density = 2.625; landscape = false
        case .L: width = 2400; height = 1080; density = 2.625; landscape = true
        case .U: width = 1024; height = 1536; density = 2.625; landscape = false
        }
    }

    func dp(_ v: Float) -> Float { return v * density }

    func lerp(_ a: Float, _ b: Float, _ t: Float) -> Float { return a + (b - a) * gCoerceIn(t, 0, 1) }

    func backgroundTransform() -> Transform {
        if width <= 0 || height <= 0 { return Transform(scaleX: 1, scaleY: 1, offsetX: 0, offsetY: 0) }
        if landscape {
            return Transform(
                scaleX: Float(width) / GoldenCourt.BACKGROUND_WIDTH,
                scaleY: Float(height) / GoldenCourt.BACKGROUND_HEIGHT,
                offsetX: 0,
                offsetY: 0
            )
        }
        let widthOverScaledArt: Float = Float(width) / (GoldenCourt.BACKGROUND_WIDTH * GoldenCourt.BACKGROUND_HORIZONTAL_SCALE)
        let baseScale = gMax(Float(height) / GoldenCourt.BACKGROUND_HEIGHT, widthOverScaledArt)
        let scaleY = baseScale
        let scaleX = baseScale * GoldenCourt.BACKGROUND_HORIZONTAL_SCALE
        let scaledWidth = GoldenCourt.BACKGROUND_WIDTH * scaleX
        let scaledHeight = GoldenCourt.BACKGROUND_HEIGHT * scaleY
        let overflowX = gCoerceAtLeast(scaledWidth - Float(width), 0)
        let overflowY = gCoerceAtLeast(scaledHeight - Float(height), 0)
        return Transform(
            scaleX: scaleX,
            scaleY: scaleY,
            offsetX: -overflowX * GoldenCourt.BACKGROUND_HORIZONTAL_FOCUS,
            offsetY: -overflowY * 0.5
        )
    }

    func sourceXToView(_ x: Float, _ t: Transform) -> Float { return t.offsetX + x * t.scaleX }
    func sourceYToView(_ y: Float, _ t: Transform) -> Float { return t.offsetY + y * t.scaleY }

    func buildPhysicsGeometry() -> TripleShotPhysics.Geometry {
        let t = backgroundTransform()
        let hoopCenterX = sourceXToView(GoldenCourt.SRC_HOOP_CENTER_X, t)
        let hoopCenterY = sourceYToView(GoldenCourt.SRC_HOOP_PLANE_Y, t)
        let leftRimX = sourceXToView(GoldenCourt.SRC_RIM_LEFT_X, t)
        let rightRimX = sourceXToView(GoldenCourt.SRC_RIM_RIGHT_X, t)
        return TripleShotPhysics.Geometry(
            gravityPxPerSec2: Float(height) * 1.52,
            hoopCenterX: hoopCenterX,
            hoopY: hoopCenterY,
            leftRimX: leftRimX,
            rightRimX: rightRimX,
            rimColliderRadius: gMax(dp(2.5), gMin(t.scaleX, t.scaleY) * 5.5),
            backboardX: sourceXToView(GoldenCourt.SRC_BACKBOARD_COLLISION_X, t),
            backboardTopY: sourceYToView(GoldenCourt.SRC_BACKBOARD_TOP_Y, t),
            backboardBottomY: sourceYToView(GoldenCourt.SRC_BACKBOARD_BOTTOM_Y, t),
            netBottomY: sourceYToView(GoldenCourt.SRC_NET_BOTTOM_Y, t),
            netBottomLeftX: sourceXToView(GoldenCourt.SRC_NET_BOTTOM_LEFT_X, t),
            netBottomRightX: sourceXToView(GoldenCourt.SRC_NET_BOTTOM_RIGHT_X, t),
            ballRadius: dp(GoldenCourt.BALL_PHYSICS_RADIUS_DP)
        )
    }

    /// The unit-test geometry of TripleShotShotPresentationTest for view U, the court geometry otherwise.
    func geometry() -> TripleShotPhysics.Geometry {
        if view == .U { return TripleShotPhysics.Geometry(1200, 750, 340, 655, 845, 5, 860, 215, 397, 505, 704, 792, 20) }
        return buildPhysicsGeometry()
    }

    func aimRangePx() -> Float { return backgroundTransform().scaleX * GoldenCourt.SRC_AIM_RANGE_X }

    func start(_ rule: GoldenStart, _ g: TripleShotPhysics.Geometry) -> (x: Float, y: Float) {
        switch rule {
        case let .hand(footX, footY, liftDp):
            let t = backgroundTransform()
            return (sourceXToView(footX, t), sourceYToView(footY, t) - dp(liftDp))
        case let .hoopMinusXPlusY(dx, dy):
            return (g.hoopCenterX - dx, g.hoopY + dy)
        case let .leftRimSafe(dy):
            return (g.leftRimX - g.ballRadius * 1.10, g.hoopY + dy)
        case let .fixed(x, y):
            return (x, y)
        }
    }

    func launch(_ c: GoldenFlightCase, _ g: TripleShotPhysics.Geometry) -> TripleShotPhysics.ShotState {
        let start = self.start(c.start, g)
        let skill = ShotSkill(aimError: fl(c.aim), powerError: fl(c.power), arcError: 0, rawPeakGyro: 0, rawReleasePitchDeg: 0)
        let aimRange: Float = view == .U ? 0 : aimRangePx()
        let targetX = g.hoopCenterX + gCoerceIn(skill.aimError, -1.30, 1.30) * aimRange
        return TripleShotPhysics.createLaunch(
            skill: skill,
            startX: start.x,
            startY: start.y,
            targetX: targetX,
            targetY: g.hoopY,
            pullBack01: fl(c.pull),
            geometry: g,
            distanceDifficulty: fl(c.diff),
            neutralPowerHitsTarget: c.neutral,
            compactOneOnOneArc: c.compact,
            rejectUpwardBasketEntry: c.reject
        )
    }

    // TripleShotCourtView.kt 7216 (finish = closeFinish when the release rejects upward entry).
    func dampOneOnOneShotImpact(_ state: TripleShotPhysics.ShotState, _ result: TripleShotPhysics.StepResult, _ closeFinish: Bool) {
        if result.rimImpactSpeed > 0 {
            let damping = closeFinish ? GoldenCourt.ONE_ON_ONE_CLOSE_FINISH_RIM_DAMPING : GoldenCourt.ONE_ON_ONE_RIM_POST_IMPACT_DAMPING
            state.vx *= damping
            state.vy *= damping
        } else if result.backboardImpactSpeed > 0 {
            let xDamping = closeFinish ? GoldenCourt.ONE_ON_ONE_CLOSE_FINISH_BOARD_X_DAMPING : GoldenCourt.ONE_ON_ONE_BOARD_POST_IMPACT_X_DAMPING
            let yDamping = closeFinish ? GoldenCourt.ONE_ON_ONE_CLOSE_FINISH_BOARD_Y_DAMPING : GoldenCourt.ONE_ON_ONE_BOARD_POST_IMPACT_Y_DAMPING
            state.vx *= xDamping
            state.vy *= yDamping
        }
    }

    // TripleShotCourtView.kt 7248.
    func oneOnOneShotReadyForLooseBall(_ state: TripleShotPhysics.ShotState, _ geometry: TripleShotPhysics.Geometry) -> Bool {
        if !oneOnOneEnabled || state.made || state.vy <= 0 { return false }
        let touchedBasket = state.rimHits > 0 || state.backboardHits > 0
        if touchedBasket {
            return state.elapsedSeconds >= GoldenCourt.ONE_ON_ONE_IMPACT_REBOUND_MIN_SECONDS &&
                state.y >= geometry.hoopY + geometry.ballRadius * 2.2
        } else {
            return state.elapsedSeconds >= GoldenCourt.ONE_ON_ONE_AIRBALL_REBOUND_MIN_SECONDS &&
                state.y >= geometry.netBottomY + dp(GoldenCourt.ONE_ON_ONE_AIRBALL_RELEASE_BELOW_NET_DP)
        }
    }

    // TripleShotCourtView.kt 7270.
    func maybeMarkOneOnOneRelaxedMake(_ state: TripleShotPhysics.ShotState, _ geometry: TripleShotPhysics.Geometry) -> Bool {
        if !oneOnOneEnabled || state.made || state.vy <= 0 { return false }

        func crossingX(_ planeY: Float) -> Float? {
            if !(state.previousY < planeY && state.y >= planeY) { return nil }
            let dy = state.y - state.previousY
            if abs(dy) < 0.0001 { return state.x }
            let t = gCoerceIn((planeY - state.previousY) / dy, 0, 1)
            return lerp(state.previousX, state.x, t)
        }

        let rimCrossX = crossingX(geometry.hoopY)
        let netConfirmY = geometry.hoopY + (geometry.netBottomY - geometry.hoopY) * GoldenCourt.ONE_ON_ONE_NET_MAKE_CONFIRM_T
        let netCrossX = crossingX(netConfirmY)

        let roseClearlyAbove = state.maxHeightReachedY <= geometry.hoopY - geometry.ballRadius * 1.10
        if !roseClearlyAbove { return false }
        if state.enteredBasketFromBelow && state.rejectUpwardBasketEntry { return false }

        var throughRimOpening = false
        if let x = rimCrossX {
            let relaxedPadding = gCoerceAtLeast(geometry.rimColliderRadius * 0.55, 0)
            throughRimOpening = x > geometry.leftRimX + relaxedPadding && x < geometry.rightRimX - relaxedPadding
        }
        var throughVisibleNetThroat = false
        if let x = netCrossX {
            let t = GoldenCourt.ONE_ON_ONE_NET_MAKE_CONFIRM_T
            let left = lerp(geometry.leftRimX + geometry.ballRadius * 0.20, geometry.netBottomLeftX + geometry.ballRadius * 0.35, t)
            let right = lerp(geometry.rightRimX - geometry.ballRadius * 0.20, geometry.netBottomRightX - geometry.ballRadius * 0.35, t)
            throughVisibleNetThroat = x >= left && x <= right
        }

        if !throughRimOpening && !throughVisibleNetThroat { return false }
        state.made = true
        return true
    }

    // TripleShotCourtView.kt 7336.
    func oneOnOnePlayableReboundVelocity(_ state: TripleShotPhysics.ShotState, _ closeFinish: Bool) -> (Float, Float) {
        let scale: (Float, Float)
        if state.rimHits > 0 && closeFinish {
            scale = (0.55, 0.62)
        } else if state.rimHits > 0 {
            scale = (0.68, 0.72)
        } else if state.backboardHits > 0 && closeFinish {
            scale = (0.62, 0.66)
        } else if state.backboardHits > 0 {
            scale = (0.72, 0.76)
        } else {
            scale = (0.90, 0.90)
        }
        let touchedBasket = state.rimHits > 0 || state.backboardHits > 0
        let maxX = touchedBasket ? dp(210) : dp(300)
        let maxY = touchedBasket ? dp(260) : dp(360)
        return (gCoerceIn(state.vx * scale.0, -maxX, maxX), gCoerceIn(state.vy * scale.1, -maxY, maxY))
    }

    // TripleShotCourtView.kt 7376 (ShotKind `when`).
    func kindOf(_ state: TripleShotPhysics.ShotState, _ geometry: TripleShotPhysics.Geometry) -> String {
        let outcome = TripleShotPhysics.toOutcome(state, geometry)
        if outcome.made && state.backboardHits > 0 { return "BANK_IN" }
        if outcome.made && state.rimHits > 0 { return "RIM_IN" }
        if outcome.made { return "SWISH" }
        if state.enteredBasketFromBelow { return "INVALID_BELOW" }
        if state.rimHits > 0 { return "RIM_OUT" }
        if state.backboardHits > 0 { return "BACKBOARD_OUT" }
        return "AIRBALL"
    }

    /// Human frame loop (TripleShotCourtView.kt 516-603) with a fixed frame period (first frame 1f/60f), no blocks.
    func run(_ state: TripleShotPhysics.ShotState, _ geometry: TripleShotPhysics.Geometry, _ framePeriod: Float,
             _ closeFinish: Bool, _ traceFrames: Set<Int> = []) -> GoldenFlightResult {
        var lastFrame = false
        var shotMadeAtSeconds: Float? = nil
        var frames = 0
        var substeps = 0
        var hash = goldenFnvOffset
        var events: [(String, Float)] = []
        var trace: [(Int, TripleShotPhysics.ShotState)] = []
        while true {
            let rawDt: Float = !lastFrame ? Float(1) / Float(60) : framePeriod
            lastFrame = true
            var remaining = gCoerceIn(rawDt, 0.001, 0.045)
            while remaining > 0 {
                let step = gMin(remaining, GoldenCourt.MAX_PHYSICS_SUBSTEP_SECONDS)
                let wasBelow = state.enteredBasketFromBelow
                let result = TripleShotPhysics.step(state, geometry, step)
                if oneOnOneEnabled {
                    dampOneOnOneShotImpact(state, result, closeFinish)
                }
                let relaxedMadeNow = maybeMarkOneOnOneRelaxedMake(state, geometry)
                if result.rimImpactSpeed > 0 { events.append(("rim", state.elapsedSeconds)) }
                if result.backboardImpactSpeed > 0 { events.append(("board", state.elapsedSeconds)) }
                if !wasBelow && state.enteredBasketFromBelow { events.append(("below", state.elapsedSeconds)) }
                if result.madeNow { events.append(("made", state.elapsedSeconds)) }
                if relaxedMadeNow { events.append(("relaxed", state.elapsedSeconds)) }
                if result.madeNow || relaxedMadeNow {
                    shotMadeAtSeconds = state.elapsedSeconds
                }
                remaining -= step
                hash = goldenFnv(hash, state.x); hash = goldenFnv(hash, state.y)
                hash = goldenFnv(hash, state.vx); hash = goldenFnv(hash, state.vy)
                substeps += 1
            }
            frames += 1
            if traceFrames.contains(frames) { trace.append((frames, state.copy())) }

            let madeAge: Float? = shotMadeAtSeconds.map { state.elapsedSeconds - $0 }
            let madeExitDepth = geometry.netBottomY + geometry.ballRadius * 1.25
            let madeExitedNet = state.made && state.y >= madeExitDepth && (madeAge ?? 0) >= GoldenCourt.MIN_POST_MAKE_SECONDS
            let madeSafetyTimeout = state.made && (madeAge ?? 0) >= GoldenCourt.MAX_POST_MAKE_SECONDS
            let belowView = state.y > Float(height) + geometry.ballRadius * 4
            let leftOfView = state.x < Float(-width) * 0.35
            let rightOfView = state.x > Float(width) * 1.35
            let outside = belowView || leftOfView || rightOfView
            let timedOut = state.elapsedSeconds >= GoldenCourt.MAX_SHOT_SECONDS
            let oneOnOneReboundReady = oneOnOneShotReadyForLooseBall(state, geometry)
            if madeExitedNet || madeSafetyTimeout || outside || timedOut || oneOnOneReboundReady {
                let end: String
                if madeExitedNet { end = "madeExitedNet" }
                else if madeSafetyTimeout { end = "madeSafetyTimeout" }
                else if outside { end = "outside" }
                else if timedOut { end = "timedOut" }
                else { end = "reboundHandoff" }
                let outcome = TripleShotPhysics.toOutcome(state, geometry)
                let loose: (Float, Float)? = oneOnOneEnabled && !outcome.made ? oneOnOnePlayableReboundVelocity(state, closeFinish) : nil
                return GoldenFlightResult(kind: kindOf(state, geometry), end: end, frames: frames, substeps: substeps,
                                          madeAt: shotMadeAtSeconds, events: events, hash: hash, loose: loose,
                                          trace: trace, state: state)
            }
            precondition(frames <= 100_000, "runaway golden flight")
        }
    }
}

// MARK: - Expected values (generated from the JVM harness output; do not edit by hand)

private enum PhysicsGolden {
    /// A.1: (scaleX, scaleY, offsetX, offsetY) bits, Geometry bits in positional order, aimRangePx bits.
    static let geometries: [(view: GoldenView, transform: [UInt32], geometry: [UInt32], aimRange: UInt32)] = [
        (.P, [0x3FB80000, 0x3FC80000, 0xC3C40000, 0x80000000], [0x45640000, 0x442B8800, 0x4404D000, 0x44096400, 0x444DAC00, 0x40FD0000, 0x44531000, 0x43A7F800, 0x441B1400, 0x44454400, 0x441B0000, 0x443AA000, 0x42034000], 0x433AE000),
        (.L, [0x40160000, 0x3F340000, 0x00000000, 0x00000000], [0x44CD3333, 0x44DBBA00, 0x436F1000, 0x44BFE500, 0x44F78F00, 0x40D20000, 0x44FBF400, 0x43172C00, 0x438B9200, 0x43B18A00, 0x44CE4000, 0x44E80800, 0x42034000], 0x43985800),
    ]

    /// A.2: frame dt bits -> substep bits (frame loop 4.8, MAX_PHYSICS_SUBSTEP_SECONDS = 1f/180f).
    static let substeps: [(dt: UInt32, steps: [UInt32])] = [
        (0x3C888889, [0x3BB60B61, 0x3BB60B61, 0x3BB60B61, 0x30800000]),  // 0.016666668
        (0x3C088889, [0x3BB60B61, 0x3B360B62]),  // 0.008333334
        (0x3DCCCCCD, [0x3BB60B61, 0x3BB60B61, 0x3BB60B61, 0x3BB60B61, 0x3BB60B61, 0x3BB60B61, 0x3BB60B61, 0x3BB60B61, 0x3A11A2F0]),  // 0.1
        (0x3C360B61, [0x3BB60B61, 0x3BB60B61]),  // 0.011111111
        (0x3A03126F, [0x3A83126F]),  // 5.0E-4
    ]

    /// A.3 launch + flight cases (inputs, launch bits, 60 Hz / 120 Hz / 1v1-hook loop results).
    static func flightCases() -> [GoldenFlightCase] {
        var cases: [GoldenFlightCase] = []
        // P1 practice_right (690,1085) neutral: mode NORMAL T=1.0628572 vx=81.03574 vy=-2709.0105 curve=0.0
        cases.append(GoldenFlightCase(
            id: "P1", view: .P, start: .hand(690, 1085, 130), startX: 0x4415F800, startY: 0x44A94200,
            aim: 0x00000000, power: 0x00000000, pull: 0x3F333333, diff: 0x3F0A3D71,
            neutral: false, compact: false, reject: false, targetX: 0x442B8800,
            mode: .NORMAL, flightSeconds: 0x3F880BB4, vx: 0x42A2124D, vy: 0xC529502B, curve: 0x00000000,
            gravity: 0x45640000,
            hz60: GoldenFlightExpect(kind: "INVALID_BELOW", end: "outside", frames: 111, substeps: 444, madeAt: nil, eventCount: 1, events: [("below", 0x3EDB05C0)], hash: 0x7A9DF3828666F2DA, loose: nil, finalState: GoldenShotEnd(x: 0x443B7290, y: 0x4521908B, vx: 0x42A2124D, vy: 0x457C7C95, previousX: 0x443B7290, previousY: 0x4521908B, elapsed: 0x3FECCCA3, curve: 0x00000000, maxHeight: 0x43AE1AFE, closest: 0x4000E2EC, made: false, rimHits: 0, backboardHits: 0, touchingNet: false, below: true)),
            hz120: GoldenFlightExpect(kind: "INVALID_BELOW", end: "outside", frames: 220, substeps: 442, madeAt: nil, eventCount: 1, events: [("below", 0x3EDC71DA)], hash: 0xF8ED65D533FEE248, loose: nil, finalState: GoldenShotEnd(x: 0x443B4758, y: 0x451F77E0, vx: 0x42A2124D, vy: 0x457A9622, previousX: 0x443B38F0, previousY: 0x451EC5E8, elapsed: 0x3FEBBBB7, curve: 0x00000000, maxHeight: 0x43AE1A45, closest: 0x3FA7F91A, made: false, rimHits: 0, backboardHits: 0, touchingNet: false, below: true)),
            oneOnOne: nil,
            outcome60: (false, 0x3EEEB162, 0x40000000, 0x3F4CCCCD), preview025: (0x441B0892, 0x4445B3D5), previewT: (0x442B8048, 0x4405D1F8),
            trace: []
        ))
        // P2 practice_right long: mode NORMAL T=1.0628572 vx=86.627205 vy=-2895.9321 curve=0.0
        cases.append(GoldenFlightCase(
            id: "P2", view: .P, start: .hand(690, 1085, 130), startX: 0x4415F800, startY: 0x44A94200,
            aim: 0x00000000, power: 0x3E99999A, pull: 0x3F333333, diff: 0x3F0A3D71,
            neutral: false, compact: false, reject: false, targetX: 0x442B8800,
            mode: .NORMAL, flightSeconds: 0x3F880BB4, vx: 0x42AD4121, vy: 0xC534FEEA, curve: 0x00000000,
            gravity: 0x45640000,
            hz60: GoldenFlightExpect(kind: "INVALID_BELOW", end: "outside", frames: 116, substeps: 464, madeAt: nil, eventCount: 1, events: [("below", 0x3EBE93F4)], hash: 0x98EC5A11FE587C96, loose: nil, finalState: GoldenShotEnd(x: 0x443FD6AC, y: 0x4520CF76, vx: 0x42AD4121, vy: 0x4581E6E9, previousX: 0x443FD6AC, previousY: 0x4520CF76, elapsed: 0x3FF77748, curve: 0x00000000, maxHeight: 0x434C9B8B, closest: 0x41993BCA, made: false, rimHits: 0, backboardHits: 0, touchingNet: false, below: true)),
            hz120: GoldenFlightExpect(kind: "INVALID_BELOW", end: "outside", frames: 230, substeps: 462, madeAt: nil, eventCount: 1, events: [("below", 0x3EBE93F7)], hash: 0x78C9CDCB6E28E512, loose: nil, finalState: GoldenShotEnd(x: 0x443FA8EB, y: 0x451EA72F, vx: 0x42AD4121, vy: 0x4580F3B0, previousX: 0x443F9984, previousY: 0x451DF003, elapsed: 0x3FF66661, curve: 0x00000000, maxHeight: 0x434C9D56, closest: 0x419944E1, made: false, rimHits: 0, backboardHits: 0, touchingNet: false, below: true)),
            oneOnOne: nil,
            outcome60: (false, 0x3F1845B6, 0x40000000, 0x3F4CCCCD), preview025: (0x441B6209, 0x443A0516), previewT: (0x442CFCA1, 0x43A84E10),
            trace: []
        ))
        // P3 practice_right short: mode NORMAL T=1.0628572 vx=75.444275 vy=-2522.0886 curve=0.0
        cases.append(GoldenFlightCase(
            id: "P3", view: .P, start: .hand(690, 1085, 130), startX: 0x4415F800, startY: 0x44A94200,
            aim: 0x00000000, power: 0xBE99999A, pull: 0x3F333333, diff: 0x3F0A3D71,
            neutral: false, compact: false, reject: false, targetX: 0x442B8800,
            mode: .NORMAL, flightSeconds: 0x3F880BB4, vx: 0x4296E378, vy: 0xC51DA16B, curve: 0x00000000,
            gravity: 0x45640000,
            hz60: GoldenFlightExpect(kind: "INVALID_BELOW", end: "outside", frames: 106, substeps: 424, madeAt: nil, eventCount: 1, events: [("below", 0x3F071C7E)], hash: 0x4C902835D8957996, loose: nil, finalState: GoldenShotEnd(x: 0x44374A1A, y: 0x4521F47F, vx: 0x4296E378, vy: 0x45752B59, previousX: 0x44374A1A, previousY: 0x4521F47F, elapsed: 0x3FE221FE, curve: 0x00000000, maxHeight: 0x43F11E2A, closest: 0x41AC9C38, made: false, rimHits: 0, backboardHits: 0, touchingNet: false, below: true)),
            hz120: GoldenFlightExpect(kind: "INVALID_BELOW", end: "outside", frames: 210, substeps: 422, madeAt: nil, eventCount: 1, events: [("below", 0x3F07D289)], hash: 0xA38A7CA7BFA657C8, loose: nil, finalState: GoldenShotEnd(x: 0x44372246, y: 0x451FEB74, vx: 0x4296E378, vy: 0x457344E7, previousX: 0x443714DC, previousY: 0x451F3EB0, elapsed: 0x3FE1110D, curve: 0x00000000, maxHeight: 0x43F11CAA, closest: 0x41AC8D4F, made: false, rimHits: 0, backboardHits: 0, touchingNet: false, below: true)),
            oneOnOne: nil,
            outcome60: (false, 0x3EB055E1, 0x40000000, 0x3F4CCCCD), preview025: (0x441AAF1C, 0x44516295), previewT: (0x442A03EF, 0x44377CF0),
            trace: []
        ))
        // P4 practice_right aim+0.5: mode NORMAL T=1.0628572 vx=168.82446 vy=-2709.0105 curve=0.0
        cases.append(GoldenFlightCase(
            id: "P4", view: .P, start: .hand(690, 1085, 130), startX: 0x4415F800, startY: 0x44A94200,
            aim: 0x3F000000, power: 0x00000000, pull: 0x3F333333, diff: 0x3F0A3D71,
            neutral: false, compact: false, reject: false, targetX: 0x4442E400,
            mode: .NORMAL, flightSeconds: 0x3F880BB4, vx: 0x4328D310, vy: 0xC529502B, curve: 0x00000000,
            gravity: 0x45640000,
            hz60: GoldenFlightExpect(kind: "INVALID_BELOW", end: "outside", frames: 111, substeps: 444, madeAt: nil, eventCount: 1, events: [("below", 0x3EDB05C0)], hash: 0x6EAF4E9262DF6F3A, loose: nil, finalState: GoldenShotEnd(x: 0x44640D1B, y: 0x4521908B, vx: 0x4328D310, vy: 0x457C7C95, previousX: 0x44640D1B, previousY: 0x4521908B, elapsed: 0x3FECCCA3, curve: 0x00000000, maxHeight: 0x43AE1AFE, closest: 0x41635F11, made: false, rimHits: 0, backboardHits: 0, touchingNet: false, below: true)),
            hz120: GoldenFlightExpect(kind: "INVALID_BELOW", end: "outside", frames: 220, substeps: 442, madeAt: nil, eventCount: 1, events: [("below", 0x3EDC71DA)], hash: 0xA1514BE7066F652D, loose: nil, finalState: GoldenShotEnd(x: 0x4463B2A3, y: 0x451F77E0, vx: 0x4328D310, vy: 0x457A9622, previousX: 0x446394A0, previousY: 0x451EC5E8, elapsed: 0x3FEBBBB7, curve: 0x00000000, maxHeight: 0x43AE1A45, closest: 0x41687D85, made: false, rimHits: 0, backboardHits: 0, touchingNet: false, below: true)),
            oneOnOne: nil,
            outcome60: (false, 0x3FD3E78F, 0x40000000, 0x3F4CCCCD), preview025: (0x44208531, 0x4445B3D5), previewT: (0x4442D3EC, 0x4405D1F8),
            trace: []
        ))
        // P5 practice_right aim-0.75: mode NORMAL T=1.0628572 vx=-50.647343 vy=-2709.0105 curve=0.0
        cases.append(GoldenFlightCase(
            id: "P5", view: .P, start: .hand(690, 1085, 130), startX: 0x4415F800, startY: 0x44A94200,
            aim: 0xBF400000, power: 0x00000000, pull: 0x3F333333, diff: 0x3F0A3D71,
            neutral: false, compact: false, reject: false, targetX: 0x44087E00,
            mode: .NORMAL, flightSeconds: 0x3F880BB4, vx: 0xC24A96E1, vy: 0xC529502B, curve: 0x00000000,
            gravity: 0x45640000,
            hz60: GoldenFlightExpect(kind: "RIM_OUT", end: "outside", frames: 94, substeps: 376, madeAt: nil, eventCount: 2, events: [("rim", 0x3ECFA508), ("board", 0x3F238E4A)], hash: 0x85EE67A8D7149476, loose: nil, finalState: GoldenShotEnd(x: 0x4309AB36, y: 0x4521CA69, vx: 0xC4358DCC, vy: 0x45717AD5, previousX: 0x4309AB36, previousY: 0x4521CA69, elapsed: 0x3FC88872, curve: 0x00000000, maxHeight: 0x4406FB35, closest: 0x410F25CE, made: false, rimHits: 1, backboardHits: 1, touchingNet: false, below: false)),
            hz120: GoldenFlightExpect(kind: "RIM_OUT", end: "outside", frames: 186, substeps: 374, madeAt: nil, eventCount: 2, events: [("rim", 0x3ECFA50B), ("board", 0x3F238E43)], hash: 0xEE3757700C9CDC53, loose: nil, finalState: GoldenShotEnd(x: 0x430FB8E9, y: 0x451FC8E3, vx: 0xC4358DB3, vy: 0x456F9418, previousX: 0x4311BD54, previousY: 0x451F1EBF, elapsed: 0x3FC77775, curve: 0x00000000, maxHeight: 0x4406FB0F, closest: 0x410D45D7, made: false, rimHits: 1, backboardHits: 1, touchingNet: false, below: false)),
            oneOnOne: nil,
            outcome60: (false, 0xC0000000, 0x40000000, 0x3F4CCCCD), preview025: (0x4412CDA4, 0x4445B3D5), previewT: (0x440882D3, 0x4405D1F8),
            trace: []
        ))
        // P6 L01 (220,920) pull 0.22: mode NORMAL T=0.72 vx=1054.1014 vy=-2089.956 curve=0.0
        cases.append(GoldenFlightCase(
            id: "P6", view: .P, start: .hand(220, 920, 130), startX: 0xC2978000, startY: 0x44890800,
            aim: 0x00000000, power: 0x00000000, pull: 0x3E6147AE, diff: 0x3F1C28F6,
            neutral: false, compact: false, reject: false, targetX: 0x442B8800,
            mode: .NORMAL, flightSeconds: 0x3F3851EC, vx: 0x4483C33F, vy: 0xC5029F4C, curve: 0x00000000,
            gravity: 0x45640000,
            hz60: GoldenFlightExpect(kind: "RIM_IN", end: "madeExitedNet", frames: 78, substeps: 312, madeAt: 0x3F871C7E, eventCount: 2, events: [("rim", 0x3F127D36), ("made", 0x3F871C7E)], hash: 0x14978E411A8AC678, loose: nil, finalState: GoldenShotEnd(x: 0x443D7F18, y: 0x445A81E3, vx: 0x3E890CB3, vy: 0x44E6A6F0, previousX: 0x443D7F18, previousY: 0x445A81E3, elapsed: 0x3FA66662, curve: 0x00000000, maxHeight: 0x43CBAE23, closest: 0x4294AA6A, made: true, rimHits: 1, backboardHits: 0, touchingNet: false, below: false)),
            hz120: GoldenFlightExpect(kind: "RIM_IN", end: "madeExitedNet", frames: 155, substeps: 312, madeAt: 0x3F871C73, eventCount: 2, events: [("rim", 0x3F127D33), ("made", 0x3F871C73)], hash: 0x85E0F78FBCF9D53C, loose: nil, finalState: GoldenShotEnd(x: 0x443D7F0F, y: 0x445A826F, vx: 0x3DD6A0CA, vy: 0x44E6A74B, previousX: 0x443D7F0A, previousY: 0x44593B4B, elapsed: 0x3FA66666, curve: 0x00000000, maxHeight: 0x43CBAFE4, closest: 0x4294A116, made: true, rimHits: 1, backboardHits: 0, touchingNet: false, below: false)),
            oneOnOne: nil,
            outcome60: (true, 0x3F06B5D6, 0x3FF724DA, 0x3F5C28F6), preview025: (0x433BC67E, 0x442BF0B4), previewT: (0x442ACCFF, 0x440642C4),
            trace: []
        ))
        // P7 L01 pull 1.20: mode NORMAL T=1.42 vx=534.474 vy=-2976.5076 curve=0.0
        cases.append(GoldenFlightCase(
            id: "P7", view: .P, start: .hand(220, 920, 130), startX: 0xC2978000, startY: 0x44890800,
            aim: 0x00000000, power: 0x00000000, pull: 0x3F99999A, diff: 0x3F1C28F6,
            neutral: false, compact: false, reject: false, targetX: 0x442B8800,
            mode: .NORMAL, flightSeconds: 0x3FB5C28F, vx: 0x44059E56, vy: 0xC53A081F, curve: 0x00000000,
            gravity: 0x45640000,
            hz60: GoldenFlightExpect(kind: "SWISH", end: "madeExitedNet", frames: 100, substeps: 400, madeAt: 0x3FB55549, eventCount: 1, events: [("made", 0x3FB55549)], hash: 0xAD2466ABB47A12A1, loose: nil, finalState: GoldenShotEnd(x: 0x443A7C9D, y: 0x44964240, vx: 0x4332CDA6, vy: 0x4541F7DD, previousX: 0x443A7C9D, previousY: 0x44964240, elapsed: 0x3FD55538, curve: 0x00000000, maxHeight: 0xC2EC1E08, closest: 0x4104D72D, made: true, rimHits: 0, backboardHits: 0, touchingNet: false, below: false)),
            hz120: GoldenFlightExpect(kind: "SWISH", end: "madeExitedNet", frames: 198, substeps: 398, madeAt: 0x3FB4FA4E, eventCount: 1, events: [("made", 0x3FB4FA4E)], hash: 0x94AF84D289ED8702, loose: nil, finalState: GoldenShotEnd(x: 0x4439BF3A, y: 0x44930A9F, vx: 0x432F4EA1, vy: 0x4540116B, previousX: 0x4439A010, previousY: 0x4491F9E8, elapsed: 0x3FD44441, curve: 0x00000000, maxHeight: 0xC2EC1E8B, closest: 0x40DA4665, made: true, rimHits: 0, backboardHits: 0, touchingNet: false, below: false)),
            oneOnOne: nil,
            outcome60: (true, 0x3EE048EF, 0x40000000, 0x3F800000), preview025: (0x42677958, 0x43E90FC2), previewT: (0x442ACCFF, 0x4408E174),
            trace: []
        ))
        // P8 H02 (825,945): mode SIDE_ARC T=1.0628572 vx=-500.56464 vy=-2480.94 curve=753.031
        cases.append(GoldenFlightCase(
            id: "P8", view: .P, start: .hand(825, 945, 130), startX: 0x44467C00, startY: 0x448DEA00,
            aim: 0x00000000, power: 0x00000000, pull: 0x3F333333, diff: 0x3F4CCCCD,
            neutral: false, compact: false, reject: false, targetX: 0x442B8800,
            mode: .SIDE_ARC, flightSeconds: 0x3F880BB4, vx: 0xC3FA4846, vy: 0xC51B0F0A, curve: 0x443C41FC,
            gravity: 0x45640000,
            hz60: GoldenFlightExpect(kind: "INVALID_BELOW", end: "outside", frames: 108, substeps: 432, madeAt: nil, eventCount: 1, events: [("below", 0x3EA4FA56)], hash: 0x16F6604E2FD1A8FD, loose: nil, finalState: GoldenShotEnd(x: 0x448B1A99, y: 0x4521361F, vx: 0x4455B922, vy: 0x457F5752, previousX: 0x448B1A99, previousY: 0x4521361F, elapsed: 0x3FE66640, curve: 0x443C41FC, maxHeight: 0x4391D9B9, closest: 0x409FF91D, made: false, rimHits: 0, backboardHits: 0, touchingNet: false, below: true)),
            hz120: GoldenFlightExpect(kind: "INVALID_BELOW", end: "outside", frames: 214, substeps: 430, madeAt: nil, eventCount: 1, events: [("below", 0x3EA4FA59)], hash: 0x06733FB6FD729CC2, loose: nil, finalState: GoldenShotEnd(x: 0x448A377F, y: 0x451F175C, vx: 0x4454277C, vy: 0x457D70E0, previousX: 0x4489EC28, previousY: 0x451E635C, elapsed: 0x3FE55551, curve: 0x443C41FC, maxHeight: 0x4391D869, closest: 0x40A5B2E3, made: false, rimHits: 0, backboardHits: 0, touchingNet: false, below: true)),
            oneOnOne: nil,
            outcome60: (false, 0x40000000, 0x40000000, 0x3F4CCCCD), preview025: (0x442D1507, 0x441D44F6), previewT: (0x442BCFB4, 0x440BBBFC),
            trace: []
        ))
        // P9 H04 (860,1090): mode SIDE_ARC T=1.0628572 vx=-510.29086 vy=-2688.1643 curve=683.56683
        cases.append(GoldenFlightCase(
            id: "P9", view: .P, start: .hand(860, 1090, 130), startX: 0x44531000, startY: 0x44AA3C00,
            aim: 0x00000000, power: 0x00000000, pull: 0x3F333333, diff: 0x3F570A3D,
            neutral: false, compact: false, reject: false, targetX: 0x442B8800,
            mode: .SIDE_ARC, flightSeconds: 0x3F880BB4, vx: 0xC3FF253B, vy: 0xC52802A1, curve: 0x442AE447,
            gravity: 0x45640000,
            hz60: GoldenFlightExpect(kind: "INVALID_BELOW", end: "outside", frames: 110, substeps: 440, madeAt: nil, eventCount: 1, events: [("below", 0x3EE38E4A)], hash: 0xA73868CBB13FDFF2, loose: nil, finalState: GoldenShotEnd(x: 0x44842FC2, y: 0x452043DD, vx: 0x4439BAB9, vy: 0x4579FD53, previousX: 0x44842FC2, previousY: 0x452043DD, elapsed: 0x3FEAAA82, curve: 0x442AE447, maxHeight: 0x43B9B901, closest: 0x400A8600, made: false, rimHits: 0, backboardHits: 0, touchingNet: false, below: true)),
            hz120: GoldenFlightExpect(kind: "INVALID_BELOW", end: "outside", frames: 219, substeps: 440, madeAt: nil, eventCount: 1, events: [("below", 0x3EE22236)], hash: 0xE9F063085F93D861, loose: nil, finalState: GoldenShotEnd(x: 0x44842FB6, y: 0x452043CE, vx: 0x4439BABE, vy: 0x4579FD47, previousX: 0x4483EDC2, previousY: 0x451F9242, elapsed: 0x3FEAAAA6, curve: 0x442AE447, maxHeight: 0x43B9B8E3, closest: 0x3F82E9D9, made: false, rimHits: 0, backboardHits: 0, touchingNet: false, below: true)),
            oneOnOne: nil,
            outcome60: (false, 0x40000000, 0x40000000, 0x3F4CCCCD), preview025: (0x4438827B, 0x4448F55F), previewT: (0x442BFF04, 0x440D4FFC),
            trace: []
        ))
        // P10 H05 (885,1140) pull 0.50: mode HIGH_LOB T=0.92 vx=752.80023 vy=-2630.8616 curve=-2089.0632
        cases.append(GoldenFlightCase(
            id: "P10", view: .P, start: .hand(885, 1140, 130), startX: 0x445C0C00, startY: 0x44B40000,
            aim: 0x00000000, power: 0x00000000, pull: 0x3F000000, diff: 0x3F6147AE,
            neutral: false, compact: false, reject: false, targetX: 0x442B8800,
            mode: .HIGH_LOB, flightSeconds: 0x3F6B851F, vx: 0x443C3337, vy: 0xC5246DC9, curve: 0xC5029103,
            gravity: 0x45640000,
            hz60: GoldenFlightExpect(kind: "BACKBOARD_OUT", end: "outside", frames: 107, substeps: 428, madeAt: nil, eventCount: 1, events: [("board", 0x3F3A4FBA)], hash: 0xF2E07AB25191444E, loose: nil, finalState: GoldenShotEnd(x: 0x44B68D80, y: 0x451F41BC, vx: 0x440A29C2, vy: 0x45721C5F, previousX: 0x44B68D80, previousY: 0x451F41BC, elapsed: 0x3FE4441F, curve: 0x00000000, maxHeight: 0x43F5AB9F, closest: 0x43430C46, made: false, rimHits: 0, backboardHits: 1, touchingNet: false, below: false)),
            hz120: GoldenFlightExpect(kind: "BACKBOARD_OUT", end: "outside", frames: 213, substeps: 428, madeAt: nil, eventCount: 1, events: [("board", 0x3F3999A2)], hash: 0xB7200FA50D2D93F7, loose: nil, finalState: GoldenShotEnd(x: 0x44B6312D, y: 0x451F487F, vx: 0x44091E63, vy: 0x457222CF, previousX: 0x44B6006C, previousY: 0x451E9C89, elapsed: 0x3FE44440, curve: 0x00000000, maxHeight: 0x43F5AB7E, closest: 0x43430F16, made: false, rimHits: 0, backboardHits: 1, touchingNet: false, below: false)),
            oneOnOne: nil,
            outcome60: (false, 0x40000000, 0x40000000, 0x3E925CFC), preview025: (0x447AC6AE, 0x44601237), previewT: (0x442C2B03, 0x440CDC3C),
            trace: []
        ))
        // P11 H05 pull 0.90: mode HIGH_LOB T=1.9349996 vx=357.92065 vy=-3946.5884 curve=-472.243
        cases.append(GoldenFlightCase(
            id: "P11", view: .P, start: .hand(885, 1140, 130), startX: 0x445C0C00, startY: 0x44B40000,
            aim: 0x00000000, power: 0x00000000, pull: 0x3F666666, diff: 0x3F6147AE,
            neutral: false, compact: false, reject: false, targetX: 0x442B8800,
            mode: .HIGH_LOB, flightSeconds: 0x3FF7AE11, vx: 0x43B2F5D8, vy: 0xC576A96A, curve: 0xC3EC1F1B,
            gravity: 0x45640000,
            hz60: GoldenFlightExpect(kind: "SWISH", end: "madeExitedNet", frames: 129, substeps: 516, madeAt: 0x3FF3E911, eventCount: 1, events: [("made", 0x3FF3E911)], hash: 0xF67988FE535DC2BC, loose: nil, finalState: GoldenShotEnd(x: 0x441B26F5, y: 0x44AD4893, vx: 0xC3AC98C8, vy: 0x457389AE, previousX: 0x441B26F5, previousY: 0x44AD4893, elapsed: 0x40099988, curve: 0xC3EC1F1B, maxHeight: 0xC42DB3B4, closest: 0x41AFB6E0, made: true, rimHits: 0, backboardHits: 0, touchingNet: false, below: false)),
            hz120: GoldenFlightExpect(kind: "SWISH", end: "madeExitedNet", frames: 257, substeps: 516, madeAt: 0x3FF3E939, eventCount: 1, events: [("made", 0x3FF3E939)], hash: 0xDF7434086604D041, loose: nil, finalState: GoldenShotEnd(x: 0x441B2D4E, y: 0x44AD4878, vx: 0xC3ACB0E9, vy: 0x457389A2, previousX: 0x441B6A97, previousY: 0x44ABEE8E, elapsed: 0x4009999F, curve: 0xC3EC1F1B, maxHeight: 0xC42DB3D1, closest: 0x41AFB277, made: true, rimHits: 0, backboardHits: 0, touchingNet: false, below: false)),
            oneOnOne: nil,
            outcome60: (true, 0xBEF5A236, 0x40000000, 0x3F800000), preview025: (0x446EBA3F, 0x440DD696), previewT: (0x442C2B04, 0x441E3440),
            trace: []
        ))
        // P12 1v1 (585,1135) clean make: mode NORMAL T=1.3288045 vx=178.49692 vy=-3101.7454 curve=0.0
        cases.append(GoldenFlightCase(
            id: "P12", view: .P, start: .hand(585, 1135, 130), startX: 0x43E07800, startY: 0x44B30600,
            aim: 0x00000000, power: 0x00000000, pull: 0x3F333333, diff: 0x3ECCCCCD,
            neutral: true, compact: true, reject: false, targetX: 0x442B8800,
            mode: .NORMAL, flightSeconds: 0x3FAA1644, vx: 0x43327F36, vy: 0xC541DBED, curve: 0x00000000,
            gravity: 0x45640000,
            hz60: GoldenFlightExpect(kind: "RIM_OUT", end: "outside", frames: 89, substeps: 356, madeAt: nil, eventCount: 1, events: [("rim", 0x3EBBBBC6)], hash: 0xD23283C9D73F33E3, loose: nil, finalState: GoldenShotEnd(x: 0xC3C23D72, y: 0x448FDBCE, vx: 0xC4492B53, vy: 0x45216C7B, previousX: 0xC3C23D72, previousY: 0x448FDBCE, elapsed: 0x3FBDDDCD, curve: 0x00000000, maxHeight: 0x436C93BB, closest: 0x432DBDE6, made: false, rimHits: 1, backboardHits: 0, touchingNet: false, below: false)),
            hz120: GoldenFlightExpect(kind: "RIM_OUT", end: "outside", frames: 142, substeps: 286, madeAt: nil, eventCount: 1, events: [("rim", 0x3EBA4FB2)], hash: 0x6E5912098D8692FD, loose: nil, finalState: GoldenShotEnd(x: 0xC3C03E66, y: 0x443BCADE, vx: 0xC4874FBD, vy: 0x44DBBA78, previousX: 0xC3BEBD83, previousY: 0x443A9344, elapsed: 0x3F988889, curve: 0x00000000, maxHeight: 0x43A3D486, closest: 0x432ED6A4, made: false, rimHits: 1, backboardHits: 0, touchingNet: false, below: false)),
            oneOnOne: GoldenFlightExpect(kind: "RIM_OUT", end: "reboundHandoff", frames: 65, substeps: 260, madeAt: nil, eventCount: 1, events: [("rim", 0x3EBBBBC6)], hash: 0x4507781C4C56A062, loose: (0xC3DADF44, 0x442AA000), finalState: GoldenShotEnd(x: 0x4242E893, y: 0x441BD1F6, vx: 0xC420EF76, vy: 0x44B1B7CC, previousX: 0x4242E893, previousY: 0x441BD1F6, elapsed: 0x3F8AAAB5, curve: 0x00000000, maxHeight: 0x43AD1DC2, closest: 0x432DBDE6, made: false, rimHits: 1, backboardHits: 0, touchingNet: false, below: false)),
            outcome60: (false, 0xC0000000, 0x40000000, 0x3EBA4DC0), preview025: (0x43F6C7E7, 0x4440B013), previewT: (0x442B8800, 0x4404D004),
            trace: []
        ))
        // P13 1v1 miss aim+0.75 power+0.01: mode NORMAL T=0.8128051 vx=465.31653 vy=-2596.9456 curve=0.0
        cases.append(GoldenFlightCase(
            id: "P13", view: .P, start: .hand(585, 1135, 130), startX: 0x43E07800, startY: 0x44B30600,
            aim: 0x3F400000, power: 0x3C23D70A, pull: 0x3F333333, diff: 0x3ECCCCCD,
            neutral: true, compact: true, reject: false, targetX: 0x444E9200,
            mode: .NORMAL, flightSeconds: 0x3F5013FF, vx: 0x43E8A884, vy: 0xC5224F21, curve: 0x00000000,
            gravity: 0x45640000,
            hz60: GoldenFlightExpect(kind: "INVALID_BELOW", end: "outside", frames: 113, substeps: 452, madeAt: nil, eventCount: 2, events: [("below", 0x3F1999A9), ("rim", 0x3F3BBBD1)], hash: 0x9B9D6F679E914510, loose: nil, finalState: GoldenShotEnd(x: 0x44204D38, y: 0x451EC134, vx: 0xC300B929, vy: 0x45718990, previousX: 0x44204D38, previousY: 0x451EC134, elapsed: 0x3FF110E5, curve: 0x00000000, maxHeight: 0x43F68654, closest: 0x41EF982C, made: false, rimHits: 1, backboardHits: 0, touchingNet: false, below: true)),
            hz120: GoldenFlightExpect(kind: "INVALID_BELOW", end: "outside", frames: 225, substeps: 452, madeAt: nil, eventCount: 2, events: [("below", 0x3F1999A4), ("rim", 0x3F3BBBC4)], hash: 0x654B12A7060AB76D, loose: nil, finalState: GoldenShotEnd(x: 0x44204E98, y: 0x451EC108, vx: 0xC300B583, vy: 0x45718969, previousX: 0x4420657A, previousY: 0x451E157F, elapsed: 0x3FF1110C, curve: 0x00000000, maxHeight: 0x43F685B6, closest: 0x41EF4EE8, made: false, rimHits: 1, backboardHits: 0, touchingNet: false, below: true)),
            oneOnOne: GoldenFlightExpect(kind: "INVALID_BELOW", end: "reboundHandoff", frames: 63, substeps: 252, madeAt: nil, eventCount: 2, events: [("below", 0x3F1999A9), ("rim", 0x3F3BBBD1)], hash: 0x3362E292EF067074, loose: (0xC28C0D0A, 0x44205467), finalState: GoldenShotEnd(x: 0x443D288E, y: 0x4417CB76, vx: 0xC2CDF50F, vy: 0x445EAE1D, previousX: 0x443D288E, previousY: 0x4417CB76, elapsed: 0x3F866673, curve: 0x00000000, maxHeight: 0x43F937EF, closest: 0x41EF982C, made: false, rimHits: 1, backboardHits: 0, touchingNet: true, below: true)),
            outcome60: (false, 0xBEA86882, 0x40000000, 0x3F4CCCCD), preview025: (0x440D5110, 0x44603CDF), previewT: (0x444EC98C, 0x44039A04),
            trace: []
        ))
        // P14 1v1 (475,1260) clean make: mode NORMAL T=1.0592512 vx=373.19995 vy=-2967.0032 curve=0.0
        cases.append(GoldenFlightCase(
            id: "P14", view: .P, start: .hand(475, 1260, 130), startX: 0x43916800, startY: 0x44CB7000,
            aim: 0x00000000, power: 0x00000000, pull: 0x3F333333, diff: 0x3F428F5C,
            neutral: true, compact: true, reject: false, targetX: 0x442B8800,
            mode: .NORMAL, flightSeconds: 0x3F87958B, vx: 0x43BA9998, vy: 0xC539700D, curve: 0x00000000,
            gravity: 0x45640000,
            hz60: GoldenFlightExpect(kind: "SWISH", end: "madeExitedNet", frames: 79, substeps: 316, madeAt: 0x3F87D289, eventCount: 1, events: [("made", 0x3F87D289)], hash: 0xA6A17976FBD8C27D, loose: nil, finalState: GoldenShotEnd(x: 0x44359BBC, y: 0x445CC34F, vx: 0x422388FF, vy: 0x44E5865C, previousX: 0x44359BBC, previousY: 0x445CC34F, elapsed: 0x3FA88883, curve: 0x00000000, maxHeight: 0x43D2788C, closest: 0x3FE7DD32, made: true, rimHits: 0, backboardHits: 0, touchingNet: false, below: false)),
            hz120: GoldenFlightExpect(kind: "SWISH", end: "madeExitedNet", frames: 156, substeps: 314, madeAt: 0x3F882D84, eventCount: 1, events: [("made", 0x3F882D84)], hash: 0x823FDBC7A1D53F0E, loose: nil, finalState: GoldenShotEnd(x: 0x4435B358, y: 0x4458F805, vx: 0x42279AD4, vy: 0x44E1B979, previousX: 0x4435ABE5, previousY: 0x4457B7E4, elapsed: 0x3FA77777, curve: 0x00000000, maxHeight: 0x43D27760, closest: 0x3F649193, made: true, rimHits: 0, backboardHits: 0, touchingNet: false, below: false)),
            oneOnOne: GoldenFlightExpect(kind: "SWISH", end: "madeExitedNet", frames: 79, substeps: 316, madeAt: 0x3F87D289, eventCount: 1, events: [("made", 0x3F87D289)], hash: 0xA6A17976FBD8C27D, loose: nil, finalState: GoldenShotEnd(x: 0x44359BBC, y: 0x445CC34F, vx: 0x422388FF, vy: 0x44E5865C, previousX: 0x44359BBC, previousY: 0x445CC34F, elapsed: 0x3FA88883, curve: 0x00000000, maxHeight: 0x43D2788C, closest: 0x3FE7DD32, made: true, rimHits: 0, backboardHits: 0, touchingNet: false, below: false)),
            outcome60: (true, 0x3E971FC0, 0x3FFDA622, 0x3F800000), preview025: (0x43C00E66, 0x4479EFF3), previewT: (0x442B8800, 0x4404D002),
            trace: []
        ))
        // P15 1v1 layup (640,980) hand -150dp: mode NORMAL T=1.3011997 vx=121.52247 vy=-2839.3044 curve=0.0
        cases.append(GoldenFlightCase(
            id: "P15", view: .P, start: .hand(640, 980, 150), startX: 0x44040000, startY: 0x448E3000,
            aim: 0x00000000, power: 0x00000000, pull: 0x3F400000, diff: 0x3DF5C28F,
            neutral: true, compact: true, reject: true, targetX: 0x442B8800,
            mode: .NORMAL, flightSeconds: 0x3FA68DB6, vx: 0x42F30B81, vy: 0xC53174DF, curve: 0x00000000,
            gravity: 0x45640000,
            hz60: GoldenFlightExpect(kind: "RIM_OUT", end: "outside", frames: 61, substeps: 244, madeAt: nil, eventCount: 1, events: [("rim", 0x3E749F4A)], hash: 0x6F3413E3FF384B40, loose: nil, finalState: GoldenShotEnd(x: 0x44973D7C, y: 0x45202CE4, vx: 0x44514A33, vy: 0x4578BACC, previousX: 0x44973D7C, previousY: 0x45202CE4, elapsed: 0x3F822231, curve: 0x00000000, maxHeight: 0x440CD40B, closest: 0x42FE02D0, made: false, rimHits: 1, backboardHits: 0, touchingNet: false, below: false)),
            hz120: GoldenFlightExpect(kind: "RIM_OUT", end: "outside", frames: 121, substeps: 244, madeAt: nil, eventCount: 1, events: [("rim", 0x3E749F50)], hash: 0x04E69496F36FC2F6, loose: nil, finalState: GoldenShotEnd(x: 0x44973F36, y: 0x45202C5E, vx: 0x44514EA9, vy: 0x4578BA21, previousX: 0x4496F4CA, previousY: 0x451F7BB8, elapsed: 0x3F822224, curve: 0x00000000, maxHeight: 0x440CD409, closest: 0x42FE013D, made: false, rimHits: 1, backboardHits: 0, touchingNet: false, below: false)),
            oneOnOne: GoldenFlightExpect(kind: "RIM_OUT", end: "reboundHandoff", frames: 29, substeps: 116, madeAt: nil, eventCount: 1, events: [("rim", 0x3E749F4A)], hash: 0x654CC239CD5F35C2, loose: (0x4378A2E7, 0x442AA000), finalState: GoldenShotEnd(x: 0x44275368, y: 0x444FABF4, vx: 0x43E20875, vy: 0x44BC933B, previousX: 0x44275368, previousY: 0x444FABF4, elapsed: 0x3EF7778C, curve: 0x00000000, maxHeight: 0x440CD40B, closest: 0x430045D6, made: false, rimHits: 1, backboardHits: 0, touchingNet: false, below: false)),
            outcome60: (false, 0x40000000, 0x40000000, 0x3F08F531), preview025: (0x440B985C, 0x44076B21), previewT: (0x442B8800, 0x4404D000),
            trace: []
        ))
        // P16 1v1 start inside cylinder (hoopCenterX-40, hoopY+260): mode NORMAL T=0.7252 vx=236.62195 vy=-1689.0206 curve=0.0
        cases.append(GoldenFlightCase(
            id: "P16", view: .P, start: .hoopMinusXPlusY(40, 260), startX: 0x44218800, startY: 0x4445D000,
            aim: 0x3F333333, power: 0x3CA3D70A, pull: 0x3F400000, diff: 0x3DF5C28F,
            neutral: true, compact: true, reject: true, targetX: 0x444C3C00,
            mode: .NORMAL, flightSeconds: 0x3F39A6B5, vx: 0x436C9F38, vy: 0xC4D320A9, curve: 0x00000000,
            gravity: 0x45640000,
            hz60: GoldenFlightExpect(kind: "INVALID_BELOW", end: "outside", frames: 70, substeps: 280, madeAt: nil, eventCount: 2, events: [("rim", 0x3E4CCCCD), ("below", 0x3E4CCCCD)], hash: 0xA66726931E6B7BD3, loose: nil, finalState: GoldenShotEnd(x: 0x4480067C, y: 0x45213E18, vx: 0x43AB143A, vy: 0x4570C997, previousX: 0x4480067C, previousY: 0x45213E18, elapsed: 0x3F95555A, curve: 0x00000000, maxHeight: 0x440399FD, closest: 0x40C11B27, made: false, rimHits: 1, backboardHits: 0, touchingNet: false, below: true)),
            hz120: GoldenFlightExpect(kind: "INVALID_BELOW", end: "outside", frames: 138, substeps: 278, madeAt: nil, eventCount: 2, events: [("rim", 0x3E49F4A3), ("below", 0x3E49F4A3)], hash: 0xE042B18F9ADD049D, loose: nil, finalState: GoldenShotEnd(x: 0x447FADBA, y: 0x45201D84, vx: 0x43ABA2EB, vy: 0x456FBC6E, previousX: 0x447F70B3, previousY: 0x451F7343, elapsed: 0x3F944445, curve: 0x00000000, maxHeight: 0x44044572, closest: 0x40C8DA92, made: false, rimHits: 1, backboardHits: 0, touchingNet: false, below: true)),
            oneOnOne: GoldenFlightExpect(kind: "INVALID_BELOW", end: "reboundHandoff", frames: 29, substeps: 116, madeAt: nil, eventCount: 2, events: [("rim", 0x3E4CCCCD), ("below", 0x3E4CCCCD)], hash: 0x027C8E2E7E364F93, loose: (0x42CB3DEB, 0x442AA000), finalState: GoldenShotEnd(x: 0x443A733E, y: 0x443D1D7B, vx: 0x4338C3ED, vy: 0x449737FD, previousX: 0x443A733E, previousY: 0x443D1D7B, elapsed: 0x3EF7778C, curve: 0x00000000, maxHeight: 0x440399FD, closest: 0x40C11B27, made: false, rimHits: 1, backboardHits: 0, touchingNet: true, below: true)),
            outcome60: (false, 0x40000000, 0x40000000, 0x3F4CCCCD), preview025: (0x443051F4, 0x43F17F57), previewT: (0x444C6E4A, 0x44036909),
            trace: []
        ))
        // P17 same start, practice flags: mode NORMAL T=1.0985714 vx=158.30676 vy=-2281.1106 curve=0.0
        cases.append(GoldenFlightCase(
            id: "P17", view: .P, start: .hoopMinusXPlusY(40, 260), startX: 0x44218800, startY: 0x4445D000,
            aim: 0x3F333333, power: 0x3CA3D70A, pull: 0x3F400000, diff: 0x3DF5C28F,
            neutral: false, compact: false, reject: false, targetX: 0x444C3C00,
            mode: .NORMAL, flightSeconds: 0x3F8C9DFD, vx: 0x431E4E88, vy: 0xC50E91C5, curve: 0x00000000,
            gravity: 0x45640000,
            hz60: GoldenFlightExpect(kind: "INVALID_BELOW", end: "outside", frames: 125, substeps: 500, madeAt: nil, eventCount: 3, events: [("below", 0x3E02D82E), ("board", 0x3F85B068), ("rim", 0x3F8D82E1)], hash: 0x4151982FDFEF24D3, loose: nil, finalState: GoldenShotEnd(x: 0xC3BD466A, y: 0x44D88078, vx: 0xC4973AC0, vy: 0x453E8BA9, previousX: 0xC3BD466A, previousY: 0x44D88078, elapsed: 0x40055540, curve: 0x00000000, maxHeight: 0x429C22A5, closest: 0x419EC292, made: false, rimHits: 1, backboardHits: 1, touchingNet: false, below: true)),
            hz120: GoldenFlightExpect(kind: "INVALID_BELOW", end: "outside", frames: 250, substeps: 502, madeAt: nil, eventCount: 3, events: [("below", 0x3E05B05B), ("board", 0x3F860B62), ("rim", 0x3F8D82D9)], hash: 0xA74AAED6B92D68CC, loose: nil, finalState: GoldenShotEnd(x: 0xC3BDF2EE, y: 0x44DA1CCA, vx: 0xC49625B8, vy: 0x453FA66C, previousX: 0xC3BC47D8, previousY: 0x44D90CAC, elapsed: 0x4005DDE0, curve: 0x00000000, maxHeight: 0x429C1C96, closest: 0x41A3BDED, made: false, rimHits: 1, backboardHits: 1, touchingNet: false, below: true)),
            oneOnOne: nil,
            outcome60: (false, 0xC0000000, 0x40000000, 0x3F4CCCCD), preview025: (0x442B6CE8, 0x43A77C76), previewT: (0x444D0252, 0x43F34C98),
            trace: []
        ))
        // P18 HORSE jump (505,1190): mode NORMAL T=0.86456096 vx=403.40656 vy=-2692.0527 curve=0.0
        cases.append(GoldenFlightCase(
            id: "P18", view: .P, start: .hand(505, 1190, 130), startX: 0x43A6F800, startY: 0x44BDC400,
            aim: 0x00000000, power: 0x00000000, pull: 0x3F333333, diff: 0x3F47AE14,
            neutral: false, compact: true, reject: false, targetX: 0x442B8800,
            mode: .NORMAL, flightSeconds: 0x3F5D53DE, vx: 0x43C9B40A, vy: 0xC52840D8, curve: 0x00000000,
            gravity: 0x45640000,
            hz60: GoldenFlightExpect(kind: "RIM_OUT", end: "outside", frames: 101, substeps: 404, madeAt: nil, eventCount: 1, events: [("rim", 0x3F16C17B)], hash: 0x7341ACAABE2129F7, loose: nil, finalState: GoldenShotEnd(x: 0x449B706F, y: 0x451E48E2, vx: 0x44197C58, vy: 0x456D193F, previousX: 0x449B706F, previousY: 0x451E48E2, elapsed: 0x3FD77759, curve: 0x00000000, maxHeight: 0x440C0492, closest: 0x424AA0AE, made: false, rimHits: 1, backboardHits: 0, touchingNet: false, below: false)),
            hz120: GoldenFlightExpect(kind: "RIM_OUT", end: "outside", frames: 201, substeps: 404, madeAt: nil, eventCount: 1, events: [("rim", 0x3F16C177)], hash: 0xDA60086DCFEBB918, loose: nil, finalState: GoldenShotEnd(x: 0x449B70AE, y: 0x451E490A, vx: 0x44197C8B, vy: 0x456D195F, previousX: 0x449B3A1B, previousY: 0x451DA0A9, elapsed: 0x3FD77774, curve: 0x00000000, maxHeight: 0x440C04DC, closest: 0x424AA1BF, made: false, rimHits: 1, backboardHits: 0, touchingNet: false, below: false)),
            oneOnOne: nil,
            outcome60: (false, 0x40000000, 0x40000000, 0x3F4CCCCD), preview025: (0x43D96502, 0x446FC728), previewT: (0x442AAD40, 0x440A83C4),
            trace: []
        ))
        // P19 1v1 layup safe start (leftRimX-1.1r, hoopY+300): mode NORMAL T=1.1812 vx=146.17021 vy=-2408.4878 curve=0.0
        cases.append(GoldenFlightCase(
            id: "P19", view: .P, start: .leftRimSafe(300), startX: 0x44005E00, startY: 0x444FD000,
            aim: 0x00000000, power: 0x00000000, pull: 0x3F400000, diff: 0x3DF5C28F,
            neutral: true, compact: true, reject: true, targetX: 0x442B8800,
            mode: .NORMAL, flightSeconds: 0x3F973190, vx: 0x43122B93, vy: 0xC51687CE, curve: 0x00000000,
            gravity: 0x45640000,
            hz60: GoldenFlightExpect(kind: "RIM_OUT", end: "outside", frames: 49, substeps: 196, madeAt: nil, eventCount: 1, events: [("rim", 0x3DFA4FA5)], hash: 0x8180014393DB4A0C, loose: nil, finalState: GoldenShotEnd(x: 0xC3BD00CE, y: 0x44F0367D, vx: 0xC4A36883, vy: 0x45491A2E, previousX: 0xC3BD00CE, previousY: 0x44F0367D, elapsed: 0x3F51112A, curve: 0x00000000, maxHeight: 0x440D081A, closest: 0x43204FF3, made: false, rimHits: 1, backboardHits: 0, touchingNet: false, below: false)),
            hz120: GoldenFlightExpect(kind: "RIM_OUT", end: "outside", frames: 97, substeps: 196, madeAt: nil, eventCount: 1, events: [("rim", 0x3DFA4FA5)], hash: 0xD2AB03FCDB8B1643, loose: nil, finalState: GoldenShotEnd(x: 0xC3BD0257, y: 0x44F035F5, vx: 0xC4A3690C, vy: 0x454919C9, previousX: 0xC3BB3187, previousY: 0x44EF1866, elapsed: 0x3F511118, curve: 0x00000000, maxHeight: 0x440D081A, closest: 0x43205004, made: false, rimHits: 1, backboardHits: 0, touchingNet: false, below: false)),
            oneOnOne: GoldenFlightExpect(kind: "RIM_OUT", end: "reboundHandoff", frames: 29, substeps: 116, madeAt: nil, eventCount: 1, events: [("rim", 0x3DFA4FA5)], hash: 0x3906EAB0F51F2BFF, loose: (0xC3C22107, 0x442AA000), finalState: GoldenShotEnd(x: 0x43897375, y: 0x446A89C4, vx: 0xC4307B1D, vy: 0x44D2DB7E, previousX: 0x43897375, previousY: 0x446A89C4, elapsed: 0x3EF7778C, curve: 0x00000000, maxHeight: 0x440D081A, closest: 0x43204FF3, made: false, rimHits: 1, backboardHits: 0, touchingNet: false, below: false)),
            outcome60: (false, 0xC0000000, 0x40000000, 0x3ED37A88), preview025: (0x440980B9, 0x43AB9064), previewT: (0x442B8800, 0x4404D000),
            trace: []
        ))
        // P20 1v1 right wing (980,1150): mode NORMAL T=1.0598882 vx=-311.94327 vy=-2805.3801 curve=0.0
        cases.append(GoldenFlightCase(
            id: "P20", view: .P, start: .hand(980, 1150, 130), startX: 0x447E3000, startY: 0x44B5F400,
            aim: 0x00000000, power: 0x00000000, pull: 0x3F333333, diff: 0x3F19999A,
            neutral: true, compact: true, reject: false, targetX: 0x442B8800,
            mode: .NORMAL, flightSeconds: 0x3F87AA6B, vx: 0xC39BF8BD, vy: 0xC52F5615, curve: 0x00000000,
            gravity: 0x45640000,
            hz60: GoldenFlightExpect(kind: "BACKBOARD_OUT", end: "outside", frames: 111, substeps: 444, madeAt: nil, eventCount: 1, events: [("board", 0x3EE66678)], hash: 0xC74B08FC3430E660, loose: nil, finalState: GoldenShotEnd(x: 0x4494F048, y: 0x4520D7BA, vx: 0x43609963, vy: 0x45795F7C, previousX: 0x4494F048, previousY: 0x4520D7BA, elapsed: 0x3FECCCA3, curve: 0x00000000, maxHeight: 0x43C3BDFE, closest: 0x43417CF7, made: false, rimHits: 0, backboardHits: 1, touchingNet: false, below: false)),
            hz120: GoldenFlightExpect(kind: "BACKBOARD_OUT", end: "outside", frames: 220, substeps: 442, madeAt: nil, eventCount: 1, events: [("board", 0x3EE6667B)], hash: 0x09CB9FA87F50D686, loose: nil, finalState: GoldenShotEnd(x: 0x4494B463, y: 0x451EC5B8, vx: 0x43609963, vy: 0x4577790A, previousX: 0x4494A06C, previousY: 0x451E15F7, elapsed: 0x3FEBBBB7, curve: 0x00000000, maxHeight: 0x43C3BDE8, closest: 0x43417CF3, made: false, rimHits: 0, backboardHits: 1, touchingNet: false, below: false)),
            oneOnOne: GoldenFlightExpect(kind: "BACKBOARD_OUT", end: "reboundHandoff", frames: 62, substeps: 248, madeAt: nil, eventCount: 1, events: [("board", 0x3EE66678)], hash: 0x02D5B452B3A3B629, loose: (0x43015E7F, 0x442AA000), finalState: GoldenShotEnd(x: 0x4475781B, y: 0x44186E07, vx: 0x4333ADE9, vy: 0x448F1AD6, previousX: 0x4475781B, previousY: 0x44186E07, elapsed: 0x3F844452, curve: 0x00000000, maxHeight: 0x43D70BD5, closest: 0x43417CF7, made: false, rimHits: 0, backboardHits: 1, touchingNet: false, below: false)),
            outcome60: (false, 0x40000000, 0x40000000, 0x3E954986), preview025: (0x446AB0E8, 0x445911EB), previewT: (0x442B8800, 0x4404D000),
            trace: []
        ))
        // P21 1v1 left elbow (430,1050): mode NORMAL T=0.8545001 vx=538.3264 vy=-2457.5254 curve=0.0
        cases.append(GoldenFlightCase(
            id: "P21", view: .P, start: .hand(430, 1050, 130), startX: 0x43622000, startY: 0x44A26C00,
            aim: 0x00000000, power: 0x00000000, pull: 0x3F333333, diff: 0x3EE66666,
            neutral: true, compact: true, reject: false, targetX: 0x442B8800,
            mode: .NORMAL, flightSeconds: 0x3F5AC085, vx: 0x440694E4, vy: 0xC5199868, curve: 0x00000000,
            gravity: 0x45640000,
            hz60: GoldenFlightExpect(kind: "SWISH", end: "madeExitedNet", frames: 68, substeps: 272, madeAt: 0x3F5B05CB, eventCount: 1, events: [("made", 0x3F5B05CB)], hash: 0x516B725F22A06B90, loose: nil, finalState: GoldenShotEnd(x: 0x443A3D80, y: 0x44564078, vx: 0x421B3580, vy: 0x44D19C16, previousX: 0x443A3D80, previousY: 0x44564078, elapsed: 0x3F911118, curve: 0x00000000, maxHeight: 0x43EBCD9A, closest: 0x3F66AE53, made: true, rimHits: 0, backboardHits: 0, touchingNet: true, below: false)),
            hz120: GoldenFlightExpect(kind: "SWISH", end: "madeExitedNet", frames: 134, substeps: 270, madeAt: 0x3F5B05B7, eventCount: 1, events: [("made", 0x3F5B05B7)], hash: 0x3E2FCCD25EC1B787, loose: nil, finalState: GoldenShotEnd(x: 0x443A1A4A, y: 0x4452CA22, vx: 0x422F205E, vy: 0x44CDCF35, previousX: 0x443A1236, previousY: 0x4451A654, elapsed: 0x3F900001, curve: 0x00000000, maxHeight: 0x43EBCD69, closest: 0x3F668E0A, made: true, rimHits: 0, backboardHits: 0, touchingNet: true, below: false)),
            oneOnOne: GoldenFlightExpect(kind: "SWISH", end: "madeExitedNet", frames: 68, substeps: 272, madeAt: 0x3F5B05CB, eventCount: 1, events: [("made", 0x3F5B05CB)], hash: 0x516B725F22A06B90, loose: nil, finalState: GoldenShotEnd(x: 0x443A3D80, y: 0x44564078, vx: 0x421B3580, vy: 0x44D19C16, previousX: 0x443A3D80, previousY: 0x44564078, elapsed: 0x3F911118, curve: 0x00000000, maxHeight: 0x43EBCD9A, closest: 0x3F66AE53, made: true, rimHits: 0, backboardHits: 0, touchingNet: true, below: false)),
            outcome60: (true, 0x3EDC9670, 0x3FEADEF8, 0x3F800000), preview025: (0x43B45A72, 0x4447BF98), previewT: (0x442B8800, 0x4404D000),
            trace: []
        ))
        // P22 1v1 left elbow miss: mode NORMAL T=0.7945 vx=408.49814 vy=-2409.303 curve=0.0
        cases.append(GoldenFlightCase(
            id: "P22", view: .P, start: .hand(430, 1050, 130), startX: 0x43622000, startY: 0x44A26C00,
            aim: 0xBF3851EC, power: 0xBC449BA6, pull: 0x3F333333, diff: 0x3EE66666,
            neutral: true, compact: true, reject: false, targetX: 0x4409E4CD,
            mode: .NORMAL, flightSeconds: 0x3F4B645A, vx: 0x43CC3FC3, vy: 0xC51694D9, curve: 0x00000000,
            gravity: 0x45640000,
            hz60: GoldenFlightExpect(kind: "RIM_OUT", end: "outside", frames: 110, substeps: 440, madeAt: nil, eventCount: 1, events: [("rim", 0x3F360B75)], hash: 0x4C270BDF28044220, loose: nil, finalState: GoldenShotEnd(x: 0x438EFFBF, y: 0x451E9E14, vx: 0xC34D05E3, vy: 0x4570FA94, previousX: 0x438EFFBF, previousY: 0x451E9E14, elapsed: 0x3FEAAA82, curve: 0x00000000, maxHeight: 0x43FA276C, closest: 0x432B9E51, made: false, rimHits: 1, backboardHits: 0, touchingNet: false, below: false)),
            hz120: GoldenFlightExpect(kind: "RIM_OUT", end: "outside", frames: 220, substeps: 442, madeAt: nil, eventCount: 1, events: [("rim", 0x3F36C175)], hash: 0x810F9A8CF32B1B7A, loose: nil, finalState: GoldenShotEnd(x: 0x438BA3E4, y: 0x45200E2E, vx: 0xC3521439, vy: 0x45725720, previousX: 0x438BEE96, previousY: 0x451F6213, elapsed: 0x3FEBBBB7, curve: 0x00000000, maxHeight: 0x43FA1D09, closest: 0x432B8473, made: false, rimHits: 1, backboardHits: 0, touchingNet: false, below: false)),
            oneOnOne: GoldenFlightExpect(kind: "RIM_OUT", end: "reboundHandoff", frames: 60, substeps: 240, madeAt: nil, eventCount: 1, events: [("rim", 0x3F360B75)], hash: 0xEFC6A5E61C3DA2FD, loose: (0xC2DF10A6, 0x441B6513), finalState: GoldenShotEnd(x: 0x43EA58D8, y: 0x44175059, vx: 0xC32404B6, vy: 0x4457D37E, previousX: 0x43EA58D8, previousY: 0x44175059, elapsed: 0x3F800010, curve: 0x00000000, maxHeight: 0x43FB8E83, closest: 0x432B9E51, made: false, rimHits: 1, backboardHits: 0, touchingNet: false, below: false)),
            outcome60: (false, 0xC0000000, 0x40000000, 0x3EBE48C0), preview025: (0x43A41FF1, 0x444AC327), previewT: (0x4409AB50, 0x4406230E),
            trace: []
        ))
        // L1 landscape 1v1 (585,1135): mode NORMAL T=0.96400034 vx=401.1604 vy=-1017.1169 curve=0.0
        cases.append(GoldenFlightCase(
            id: "L1", view: .L, start: .hand(585, 1135, 130), startX: 0x44AB6300, startY: 0x43E46600,
            aim: 0x00000000, power: 0x00000000, pull: 0x3F333333, diff: 0x3ECCCCCD,
            neutral: true, compact: true, reject: false, targetX: 0x44DBBA00,
            mode: .NORMAL, flightSeconds: 0x3F76C8BA, vx: 0x43C89488, vy: 0xC47E477B, curve: 0x00000000,
            gravity: 0x44CD3333,
            hz60: GoldenFlightExpect(kind: "SWISH", end: "madeExitedNet", frames: 73, substeps: 292, madeAt: 0x3F777797, eventCount: 1, events: [("made", 0x3F777797)], hash: 0x69019B0FFD10D261, loose: nil, finalState: GoldenShotEnd(x: 0x44E1233E, y: 0x43D92878, vx: 0x422C3F5E, vy: 0x44750A62, previousX: 0x44E1233E, previousY: 0x43D92878, elapsed: 0x3F9BBBBD, curve: 0x00000000, maxHeight: 0x430DB492, closest: 0x3FECC845, made: true, rimHits: 0, backboardHits: 0, touchingNet: false, below: false)),
            hz120: GoldenFlightExpect(kind: "SWISH", end: "madeExitedNet", frames: 144, substeps: 290, madeAt: 0x3F77777C, eventCount: 1, events: [("made", 0x3F77777C)], hash: 0x15D1721F5CD37EF0, loose: nil, finalState: GoldenShotEnd(x: 0x44E12FBE, y: 0x43D51A41, vx: 0x4236B522, vy: 0x44719EDD, previousX: 0x44E12B8C, previousY: 0x43D3C36D, elapsed: 0x3F9AAAAB, curve: 0x00000000, maxHeight: 0x430DB491, closest: 0x3D9CF47F, made: true, rimHits: 0, backboardHits: 0, touchingNet: false, below: false)),
            oneOnOne: GoldenFlightExpect(kind: "SWISH", end: "madeExitedNet", frames: 73, substeps: 292, madeAt: 0x3F777797, eventCount: 1, events: [("made", 0x3F777797)], hash: 0x69019B0FFD10D261, loose: nil, finalState: GoldenShotEnd(x: 0x44E1233E, y: 0x43D92878, vx: 0x422C3F5E, vy: 0x44750A62, previousX: 0x44E1233E, previousY: 0x43D92878, elapsed: 0x3F9BBBBD, curve: 0x00000000, maxHeight: 0x430DB492, closest: 0x3FECC845, made: true, rimHits: 0, backboardHits: 0, touchingNet: false, below: false)),
            outcome60: (true, 0x3E471606, 0x3F2CB000, 0x3F800000), preview025: (0x44B7EC48, 0x437DD152), previewT: (0x44DBBA00, 0x436F1000),
            trace: []
        ))
        // L2 landscape C03 (470,1100): mode NORMAL T=1.0628572 vx=614.6429 vy=-1049.3223 curve=0.0
        cases.append(GoldenFlightCase(
            id: "L2", view: .L, start: .hand(470, 1100, 130), startX: 0x4489B200, startY: 0x43D81800,
            aim: 0x00000000, power: 0x00000000, pull: 0x3F333333, diff: 0x3F2147AE,
            neutral: false, compact: false, reject: false, targetX: 0x44DBBA00,
            mode: .NORMAL, flightSeconds: 0x3F880BB4, vx: 0x4419A925, vy: 0xC4832A50, curve: 0x00000000,
            gravity: 0x44CD3333,
            hz60: GoldenFlightExpect(kind: "SWISH", end: "madeExitedNet", frames: 78, substeps: 312, madeAt: 0x3F871C7E, eventCount: 1, events: [("made", 0x3F871C7E)], hash: 0x62DD0A832899D9D2, loose: nil, finalState: GoldenShotEnd(x: 0x44E2F39F, y: 0x43E39C28, vx: 0x42B4BF55, vy: 0x44879838, previousX: 0x44E2F39F, previousY: 0x43E39C28, elapsed: 0x3FA66662, curve: 0x00000000, maxHeight: 0x42C1A400, closest: 0x40B64285, made: true, rimHits: 0, backboardHits: 0, touchingNet: false, below: false)),
            hz120: GoldenFlightExpect(kind: "SWISH", end: "madeExitedNet", frames: 155, substeps: 312, madeAt: 0x3F871C73, eventCount: 1, events: [("made", 0x3F871C73)], hash: 0xE8D38035259E67BB, loose: nil, finalState: GoldenShotEnd(x: 0x44E2EEE6, y: 0x43E39C26, vx: 0x42BA6869, vy: 0x4487983A, previousX: 0x44E2E69D, previousY: 0x43E21B45, elapsed: 0x3FA66666, curve: 0x00000000, maxHeight: 0x42C1A3FC, closest: 0x40C440FC, made: true, rimHits: 0, backboardHits: 0, touchingNet: false, below: false)),
            oneOnOne: nil,
            outcome60: (true, 0x3E84E9C2, 0x3F3F2CE6, 0x3F800000), preview025: (0x449CE725, 0x435D282D), previewT: (0x44DB5AE2, 0x43742318),
            trace: []
        ))
        // U1 unit geometry, start (430,700): mode NORMAL T=1.0628572 vx=301.07526 vy=-976.42395 curve=0.0
        cases.append(GoldenFlightCase(
            id: "U1", view: .U, start: .fixed(430, 700), startX: 0x43D70000, startY: 0x442F0000,
            aim: 0x00000000, power: 0x00000000, pull: 0x3F333333, diff: 0x3F000000,
            neutral: false, compact: false, reject: false, targetX: 0x443B8000,
            mode: .NORMAL, flightSeconds: 0x3F880BB4, vx: 0x439689A2, vy: 0xC4741B22, curve: 0x00000000,
            gravity: 0x44960000,
            hz60: GoldenFlightExpect(kind: "SWISH", end: "madeExitedNet", frames: 86, substeps: 344, madeAt: 0x3F888894, eventCount: 1, events: [("made", 0x3F888894)], hash: 0x71D724FBA59F75BF, loose: nil, finalState: GoldenShotEnd(x: 0x444427CE, y: 0x44054822, vx: 0x3F619859, vy: 0x4439E4F6, previousX: 0x444427CE, previousY: 0x44054822, elapsed: 0x3FB7776A, curve: 0x00000000, maxHeight: 0x43976067, closest: 0x3F3C760C, made: true, rimHits: 0, backboardHits: 0, touchingNet: true, below: false)),
            hz120: GoldenFlightExpect(kind: "SWISH", end: "madeExitedNet", frames: 171, substeps: 344, madeAt: 0x3F882D84, eventCount: 1, events: [("made", 0x3F882D84)], hash: 0xD7D85B8B7798A2D8, loose: nil, finalState: GoldenShotEnd(x: 0x4443F2D4, y: 0x44054808, vx: 0x3F79C79B, vy: 0x4439E4DF, previousX: 0x4443F293, previousY: 0x4404C423, elapsed: 0x3FB77776, curve: 0x00000000, maxHeight: 0x43975FCA, closest: 0x3EE0DA07, made: true, rimHits: 0, backboardHits: 0, touchingNet: true, below: false)),
            oneOnOne: nil,
            outcome60: (true, 0x3EBA9816, 0x3FC82A03, 0x3F800000), preview025: (0x43FCA268, 0x43F6B26F), previewT: (0x443B8000, 0x43AA0000),
            trace: [(6, 0x3DCCCCCD, 0x43E60DC2, 0x441816E3), (30, 0x3F00000B, 0x44112279, 0x43B4E4EB), (60, 0x3F800010, 0x4436C50B, 0x43A1C9DA), (84, 0x3FB33328, 0x44441E7B, 0x43FE8100)]
        ))
        // X1 rise<=0, base path crosses the board -> HIGH_LOB, lob search exhausted (2.12): mode HIGH_LOB T=2.12 vx=64.089485 vy=-3351.4827 curve=352.80673
        cases.append(GoldenFlightCase(
            id: "X1", view: .P, start: .hand(150, 450, 130), startX: 0xC3306000, startY: 0x43B4F000,
            aim: 0x3F800000, power: 0xBF000000, pull: 0x3F333333, diff: 0x3F000000,
            neutral: false, compact: false, reject: false, targetX: 0x445A4000,
            mode: .HIGH_LOB, flightSeconds: 0x4007AE14, vx: 0x42802DD1, vy: 0xC55177B9, curve: 0x43B06743,
            gravity: 0x45640000,
            hz60: GoldenFlightExpect(kind: "RIM_OUT", end: "outside", frames: 153, substeps: 612, madeAt: nil, eventCount: 2, events: [("rim", 0x3FF05ADA), ("board", 0x3FFBBB8A)], hash: 0xEE326EE84EB9DE96, loose: nil, finalState: GoldenShotEnd(x: 0xC3C4224F, y: 0x44600010, vx: 0xC500F7E9, vy: 0x44E400B0, previousX: 0xC3C4224F, previousY: 0x44600010, elapsed: 0x40233338, curve: 0x00000000, maxHeight: 0xC49334E4, closest: 0x426A1A39, made: false, rimHits: 1, backboardHits: 1, touchingNet: false, below: false)),
            hz120: GoldenFlightExpect(kind: "BANK_IN", end: "madeExitedNet", frames: 259, substeps: 520, madeAt: 0x3FF60B5B, eventCount: 5, events: [("rim", 0x3FF0B606), ("made", 0x3FF60B5B), ("rim", 0x3FFAAAA5), ("board", 0x3FFBBBB6), ("board", 0x3FFC71C1)], hash: 0xABC0829E7554400D, loose: nil, finalState: GoldenShotEnd(x: 0x443D7F4B, y: 0x446E751A, vx: 0x3DD6A0CA, vy: 0x450BE8D7, previousX: 0x443D7F46, previousY: 0x446CE80A, elapsed: 0x400AAAB1, curve: 0x00000000, maxHeight: 0xC49334E8, closest: 0x4092A2A7, made: true, rimHits: 2, backboardHits: 2, touchingNet: false, below: false)),
            oneOnOne: nil,
            outcome60: (false, 0xC0000000, 0x40000000, 0x3F4924DB), preview025: (0xC31553D2, 0xC3B4FF72), previewT: (0x443C149A, 0x44B5D08C),
            trace: []
        ))
        // X2 clean make, approach fraction out of range; upward rejection side -1 (x left of centre): mode NORMAL T=0.805 vx=107.14285 vy=-1743.1648 curve=0.0
        cases.append(GoldenFlightCase(
            id: "X2", view: .P, start: .hand(690, 700, 130), startX: 0x4415F800, startY: 0x443C2000,
            aim: 0x00000000, power: 0x00000000, pull: 0x3E6147AE, diff: 0x3F000000,
            neutral: true, compact: true, reject: true, targetX: 0x442B8800,
            mode: .NORMAL, flightSeconds: 0x3F4E147B, vx: 0x42D64924, vy: 0xC4D9E546, curve: 0x00000000,
            gravity: 0x45640000,
            hz60: GoldenFlightExpect(kind: "INVALID_BELOW", end: "outside", frames: 66, substeps: 264, madeAt: nil, eventCount: 2, events: [("rim", 0x3E1F49F5), ("below", 0x3E1F49F5)], hash: 0x31781F5BF85405FC, loose: nil, finalState: GoldenShotEnd(x: 0x4414E5E2, y: 0x452049E1, vx: 0xC1B17858, vy: 0x45705113, previousX: 0x4414E5E2, previousY: 0x452049E1, elapsed: 0x3F8CCCD6, curve: 0x00000000, maxHeight: 0x44035E8F, closest: 0x428BA561, made: false, rimHits: 1, backboardHits: 0, touchingNet: false, below: true)),
            hz120: GoldenFlightExpect(kind: "INVALID_BELOW", end: "outside", frames: 130, substeps: 262, madeAt: nil, eventCount: 2, events: [("rim", 0x3E1F49F6), ("below", 0x3E1F49F6)], hash: 0x4328AC375038B169, loose: nil, finalState: GoldenShotEnd(x: 0x4414F17E, y: 0x451E4B39, vx: 0xC1B17890, vy: 0x456E6AA8, previousX: 0x4414F570, previousY: 0x451DA1E8, elapsed: 0x3F8BBBBD, curve: 0x00000000, maxHeight: 0x44035E8E, closest: 0x428BA562, made: false, rimHits: 1, backboardHits: 0, touchingNet: false, below: true)),
            oneOnOne: GoldenFlightExpect(kind: "INVALID_BELOW", end: "reboundHandoff", frames: 29, substeps: 116, madeAt: nil, eventCount: 2, events: [("rim", 0x3E1F49F5), ("below", 0x3E1F49F5)], hash: 0x09314F365D1D9DB6, loose: (0xC0D2D5A1, 0x442AA000), finalState: GoldenShotEnd(x: 0x4419276A, y: 0x444EB623, vx: 0xC13FAAEF, vy: 0x44B072F3, previousX: 0x4419276A, previousY: 0x444EB623, elapsed: 0x3EF7778C, curve: 0x00000000, maxHeight: 0x44035E8F, closest: 0x428BA561, made: false, rimHits: 1, backboardHits: 0, touchingNet: true, below: true)),
            outcome60: (false, 0xBF29B699, 0x40000000, 0x3F3E8E0F), preview025: (0x441CAA49, 0x43D75ABA), previewT: (0x442B8800, 0x4404D000),
            trace: []
        ))
        // X3 clean make, |dx| < 1.5r; upward rejection side from initialVx >= 0: mode NORMAL T=0.805 vx=0.0 vy=-1743.1648 curve=0.0
        cases.append(GoldenFlightCase(
            id: "X3", view: .P, start: .hand(750, 700, 130), startX: 0x442B8800, startY: 0x443C2000,
            aim: 0x00000000, power: 0x00000000, pull: 0x3E6147AE, diff: 0x3F000000,
            neutral: true, compact: true, reject: true, targetX: 0x442B8800,
            mode: .NORMAL, flightSeconds: 0x3F4E147B, vx: 0x00000000, vy: 0xC4D9E546, curve: 0x00000000,
            gravity: 0x45640000,
            hz60: GoldenFlightExpect(kind: "INVALID_BELOW", end: "outside", frames: 66, substeps: 264, madeAt: nil, eventCount: 2, events: [("rim", 0x3E1F49F5), ("below", 0x3E1F49F5)], hash: 0xC02F4F6C15899938, loose: nil, finalState: GoldenShotEnd(x: 0x444A1158, y: 0x452049E1, vx: 0x4301539D, vy: 0x45705113, previousX: 0x444A1158, previousY: 0x452049E1, elapsed: 0x3F8CCCD6, curve: 0x00000000, maxHeight: 0x44035E8F, closest: 0x3F50C000, made: false, rimHits: 1, backboardHits: 0, touchingNet: false, below: true)),
            hz120: GoldenFlightExpect(kind: "INVALID_BELOW", end: "outside", frames: 130, substeps: 262, madeAt: nil, eventCount: 2, events: [("rim", 0x3E1F49F6), ("below", 0x3E1F49F6)], hash: 0xAEFC3C539D77F023, loose: nil, finalState: GoldenShotEnd(x: 0x4449CC5E, y: 0x451E4B39, vx: 0x430153A4, vy: 0x456E6AA8, previousX: 0x4449B560, previousY: 0x451DA1E8, elapsed: 0x3F8BBBBD, curve: 0x00000000, maxHeight: 0x44035E8E, closest: 0x3F50BC00, made: false, rimHits: 1, backboardHits: 0, touchingNet: false, below: true)),
            oneOnOne: GoldenFlightExpect(kind: "INVALID_BELOW", end: "reboundHandoff", frames: 29, substeps: 116, madeAt: nil, eventCount: 2, events: [("rim", 0x3E1F49F5), ("below", 0x3E1F49F5)], hash: 0x417712A2083CC93B, loose: (0x4219A3D9, 0x442AA000), finalState: GoldenShotEnd(x: 0x44314117, y: 0x444EB623, vx: 0x428BAC39, vy: 0x44B072F3, previousX: 0x44314117, previousY: 0x444EB623, elapsed: 0x3EF7778C, curve: 0x00000000, maxHeight: 0x44035E8F, closest: 0x3F50C000, made: false, rimHits: 1, backboardHits: 0, touchingNet: true, below: true)),
            outcome60: (false, 0x3F64F98E, 0x40000000, 0x3F4CCCCD), preview025: (0x442B8800, 0x43D75ABA), previewT: (0x442B8800, 0x4404D000),
            trace: []
        ))
        // X4 clean make search finds nothing -> 1.34 s: mode NORMAL T=1.34 vx=160.91417 vy=-3075.6902 curve=0.0
        cases.append(GoldenFlightCase(
            id: "X4", view: .P, start: .hand(600, 1100, 130), startX: 0x43EB4000, startY: 0x44AC3000,
            aim: 0x00000000, power: 0x00000000, pull: 0x3E6147AE, diff: 0x3F000000,
            neutral: true, compact: true, reject: false, targetX: 0x442B8800,
            mode: .NORMAL, flightSeconds: 0x3FAB851F, vx: 0x4320EA07, vy: 0xC5403B0B, curve: 0x00000000,
            gravity: 0x45640000,
            hz60: GoldenFlightExpect(kind: "RIM_OUT", end: "outside", frames: 56, substeps: 224, madeAt: nil, eventCount: 1, events: [("rim", 0x3EAAAAB2)], hash: 0x677159AB4ADC7A9D, loose: nil, finalState: GoldenShotEnd(x: 0xC3C9C796, y: 0x44852CAF, vx: 0xC4C05C32, vy: 0x44F24C51, previousX: 0xC3C9C796, previousY: 0x44852CAF, elapsed: 0x3F6EEF0D, curve: 0x00000000, maxHeight: 0x44099ACC, closest: 0x432667EF, made: false, rimHits: 1, backboardHits: 0, touchingNet: false, below: false)),
            hz120: GoldenFlightExpect(kind: "RIM_OUT", end: "outside", frames: 110, substeps: 222, madeAt: nil, eventCount: 1, events: [("rim", 0x3EA93E9E)], hash: 0x2B16E15F91A1E743, loose: nil, finalState: GoldenShotEnd(x: 0xC3BDE651, y: 0x4498E0B6, vx: 0xC4BDB635, vy: 0x45094FC5, previousX: 0xC3BBCAB1, previousY: 0x44981DE0, elapsed: 0x3F6CCCD2, curve: 0x00000000, maxHeight: 0x440C0767, closest: 0x432685E5, made: false, rimHits: 1, backboardHits: 0, touchingNet: false, below: false)),
            oneOnOne: GoldenFlightExpect(kind: "RIM_OUT", end: "reboundHandoff", frames: 34, substeps: 136, madeAt: nil, eventCount: 1, events: [("rim", 0x3EAAAAB2)], hash: 0x9407A07672955478, loose: (0xC409D000, 0x43EA4FCE), finalState: GoldenShotEnd(x: 0x4368830C, y: 0x4418E463, vx: 0xC499E35B, vy: 0x4422B76B, previousX: 0x4368830C, previousY: 0x4418E463, elapsed: 0x3F11111F, curve: 0x00000000, maxHeight: 0x440A606A, closest: 0x432667EF, made: false, rimHits: 1, backboardHits: 0, touchingNet: false, below: false)),
            outcome60: (false, 0xC0000000, 0x40000000, 0x3EC80E30), preview025: (0x43FF5D41, 0x4434A4F5), previewT: (0x442B8800, 0x4404D000),
            trace: []
        ))
        // X5 1v1 miss; upward rejection side from initialVx < 0: mode NORMAL T=0.805 vx=-177.20537 vy=-2809.312 curve=0.0
        cases.append(GoldenFlightCase(
            id: "X5", view: .P, start: .hand(800, 1100, 130), startX: 0x443D8000, startY: 0x44AC3000,
            aim: 0xBE99999A, power: 0x3F000000, pull: 0x3E6147AE, diff: 0x3F000000,
            neutral: true, compact: true, reject: true, targetX: 0x441D8400,
            mode: .NORMAL, flightSeconds: 0x3F4E147B, vx: 0xC3313493, vy: 0xC52F94FE, curve: 0x00000000,
            gravity: 0x45640000,
            hz60: GoldenFlightExpect(kind: "INVALID_BELOW", end: "outside", frames: 81, substeps: 324, madeAt: nil, eventCount: 2, events: [("rim", 0x3ED27D36), ("below", 0x3ED27D36)], hash: 0xD6CF7BAD8756204E, loose: nil, finalState: GoldenShotEnd(x: 0x43BFC28C, y: 0x4521A0D0, vx: 0xC3A0A128, vy: 0x4571E521, previousX: 0x43BFC28C, previousY: 0x4521A0D0, elapsed: 0x3FACCCC5, curve: 0x00000000, maxHeight: 0x4404B5AB, closest: 0x3F87C8FB, made: false, rimHits: 1, backboardHits: 0, touchingNet: false, below: true)),
            hz120: GoldenFlightExpect(kind: "INVALID_BELOW", end: "outside", frames: 160, substeps: 322, madeAt: nil, eventCount: 2, events: [("rim", 0x3ED3E950), ("below", 0x3ED3E950)], hash: 0xEA621F5ACAE41AA1, loose: nil, finalState: GoldenShotEnd(x: 0x43C1D10F, y: 0x451EC135, vx: 0xC3A01280, vy: 0x456F2574, previousX: 0x43C242E3, previousY: 0x451E175F, elapsed: 0x3FABBBBB, curve: 0x00000000, maxHeight: 0x4403CDC3, closest: 0x4051B4A8, made: false, rimHits: 1, backboardHits: 0, touchingNet: false, below: true)),
            oneOnOne: GoldenFlightExpect(kind: "INVALID_BELOW", end: "reboundHandoff", frames: 31, substeps: 124, madeAt: nil, eventCount: 2, events: [("rim", 0x3ED27D36), ("below", 0x3ED27D36)], hash: 0x7F12F026A28274B5, loose: (0xC2BED3F0, 0x43C1E81A), finalState: GoldenShotEnd(x: 0x4426B56F, y: 0x441774F8, vx: 0xC32D7ADA, vy: 0x441C6057, previousX: 0x4426B56F, previousY: 0x441774F8, elapsed: 0x3F044450, curve: 0x00000000, maxHeight: 0x4404B5AB, closest: 0x3F87C8FB, made: false, rimHits: 1, backboardHits: 0, touchingNet: false, below: true)),
            outcome60: (false, 0xC0000000, 0x40000000, 0x3F4CCCCD), preview025: (0x44326CB7, 0x44454B02), previewT: (0x4419D661, 0x43950034),
            trace: []
        ))
        return cases
    }

    /// A.4 aim guide: (pull, aim) -> skill bits, T, total, point count, first/last point bits, stop reason, point hash.
    static let guides: [GoldenGuide] = [
        // ShotSkill(aimError=0.0, powerError=0.0, arcError=-0.14285715, rawPeakGyro=3.05, rawReleasePitchDeg=14.0) T=1.0628572 first=(603.11646, 1248.6205) last=(635.531, 515.2241)
        GoldenGuide(pull: 0x3F333333, aim: 0x00000000, skill: [0x00000000, 0x00000000, 0xBE124925, 0x40433333, 0x41600000], flightSeconds: 0x3F880BB4, total: 0x3F8D7CCF, points: 11,
                    first: (0x4416C774, 0x449C13DB), last: (0x441EE1FC, 0x4400CE58), reason: "enteredBasketFromBelow", hash: 0x6A7BE7DC05AF61EC),
        // ShotSkill(aimError=0.2, powerError=-0.28711107, arcError=-1.0, rawPeakGyro=2.6624, rawReleasePitchDeg=8.0) T=0.8485714 first=(605.31, 1263.0645) last=(719.78656, 702.5858)
        GoldenGuide(pull: 0x3ECCCCCD, aim: 0x3E4CCCCD, skill: [0x3E4CCCCD, 0xBE930039, 0xBF800000, 0x402A64C3, 0x41000000], flightSeconds: 0x3F593BFA, total: 0x3F61EC74, points: 23,
                    first: (0x441753D7, 0x449DE210), last: (0x4433F257, 0x442FA57E), reason: "reachedTotal", hash: 0x45524882175C5E4F),
        // ShotSkill(aimError=-0.3, powerError=0.41303706, arcError=1.0, rawPeakGyro=3.6076, rawReleasePitchDeg=22.0) T=1.3485713 first=(600.85406, 1222.7062) last=(607.7075, 466.64197)
        GoldenGuide(pull: 0x3F8CCCCD, aim: 0xBE99999A, skill: [0xBE99999A, 0x3ED37998, 0x3F800000, 0x4066E2EB, 0x41B00000], flightSeconds: 0x3FAC9DFC, total: 0x3FB38595, points: 8,
                    first: (0x441636A9, 0x4498D699), last: (0x4417ED48, 0x43E9522C), reason: "enteredBasketFromBelow", hash: 0x337136712707F186),
    ]

    /// A.5 powerError: (pull bits, powerError bits).
    static let powerErrors: [(UInt32, UInt32)] = [
        (0x00000000, 0xBF4A72D6), (0x3D4CCCCD, 0xBF3A547E), (0x3DCCCCCD, 0xBF2A3627), (0x3E19999A, 0xBF1A17D0),
        (0x3E4CCCCD, 0xBF09F97A), (0x3E800000, 0xBEF3B645), (0x3E99999A, 0xBED37996), (0x3EB33333, 0xBEB33CE8),
        (0x3ECCCCCD, 0xBE930039), (0x3EE66666, 0xBE658717), (0x3F000000, 0xBE250DBA), (0x3F0CCCCD, 0xBDC928B8),
        (0x3F19999A, 0xBD4E5125), (0x3F266666, 0xBCCE512C), (0x3F333333, 0x00000000), (0x3F400000, 0x3CCE512C),
        (0x3F4CCCCD, 0x3D4E512C), (0x3F59999A, 0x3DC928C2), (0x3F666666, 0x3E250DBA), (0x3F733333, 0x3E658717),
        (0x3F800000, 0x3E93003B), (0x3F866666, 0x3EB33CE7), (0x3F8CCCCD, 0x3ED37998), (0x3F933333, 0x3EF3B645),
        (0x3F99999A, 0x3F09F97B), (0x3F147AE1, 0xBD77949A), (0x3F51EB85, 0x3D77949A), (0x3F14BC6A, 0xBD75846F),
        (0x3F51A9FC, 0x3D75846F), (0x3FC00000, 0x3F09F97B), (0xBF000000, 0xBF4A72D6), (0x3DF5C28F, 0xBF23C39E),
        (0x3F19999A, 0xBD4E5125), (0x3F4CCCCD, 0x3D4E512C), (0x3E19999A, 0xBF1A17D0), (0x3F99999A, 0x3F09F97B),
    ]

    /// A.5 skill(aim, pull, flickGyro) -> (aimError, powerError, arcError, rawPeakGyro, rawReleasePitchDeg) bits.
    static let skills: [(input: [UInt32], output: [UInt32])] = [
        ([0x3E99999A, 0x3F333333, 0x00000000], [0x3E99999A, 0x00000000, 0xBE124925, 0x40433333, 0x41600000]),  // 0.3 0.7 0.0 -> ShotSkill(aimError=0.3, powerError=0.0, arcError=-0.14285715, rawPeakGyro=3.05, rawReleasePitchDeg=14.0)
        ([0x00000000, 0x3F333333, 0x3F000000], [0x00000000, 0x3EBDA12F, 0xBE124925, 0x40633333, 0x41600000]),  // 0.0 0.7 0.5 -> ShotSkill(aimError=0.0, powerError=0.37037036, arcError=-0.14285715, rawPeakGyro=3.55, rawReleasePitchDeg=14.0)
        ([0x3FC00000, 0x3DCCCCCD, 0x3F800000], [0x3FA66666, 0xBE06B678, 0xBFD9999A, 0x4037D567, 0x40000000]),  // 1.5 0.1 1.0 -> ShotSkill(aimError=1.3, powerError=-0.13155544, arcError=-1.7, rawPeakGyro=2.8724, rawReleasePitchDeg=2.0)
        ([0xBE4CCCCD, 0x3F99999A, 0x00000000], [0xBE4CCCCD, 0x3F09F97B, 0x3FA49249, 0x4071C433, 0x41C00000]),  // -0.2 1.2 0.0 -> ShotSkill(aimError=-0.2, powerError=0.538963, arcError=1.2857143, rawPeakGyro=3.7776, rawReleasePitchDeg=24.0)
        ([0x3DCCCCCD, 0x00000000, 0x00000000], [0x3DCCCCCD, 0xBF4A72D6, 0xBFD9999A, 0x3FFDBF49, 0x00000000]),  // 0.1 0.0 0.0 -> ShotSkill(aimError=0.1, powerError=-0.79081476, arcError=-1.7, rawPeakGyro=1.9824001, rawReleasePitchDeg=0.0)
        ([0x40000000, 0xBF800000, 0x3F800000], [0x3FA66666, 0xBE83D49A, 0xBFD9999A, 0x402CF41F, 0xC1A00000]),  // 2.0 -1.0 1.0 -> ShotSkill(aimError=1.3, powerError=-0.2574814, arcError=-1.7, rawPeakGyro=2.7024, rawReleasePitchDeg=-20.0)
        ([0xC0000000, 0x3FC00000, 0xBF800000], [0xBFA66666, 0x3F09F97B, 0x3FD9999A, 0x4071C433, 0x41F00000]),  // -2.0 1.5 -1.0 -> ShotSkill(aimError=-1.3, powerError=0.538963, arcError=1.7, rawPeakGyro=3.7776, rawReleasePitchDeg=30.0)
    ]

    /// BasketballFeelTest loop: skill(0.3, i/100f) for i in 0...120 -> (powerError bits, rawPeakGyro bits).
    static let skillLoop: [(UInt32, UInt32)] = [
        (0xBF4A72D6, 0x3FFDBF49), (0xBF473991, 0x3FFFEC57), (0xBF44004D, 0x40010CB2), (0xBF40C708, 0x4002233A),
        (0xBF3D8DC3, 0x400339C1), (0xBF3A547E, 0x40045048), (0xBF371B3A, 0x400566CF), (0xBF33E1F5, 0x40067D57),
        (0xBF30A8B1, 0x400793DE), (0xBF2D6F6D, 0x4008AA64), (0xBF2A3627, 0x4009C0EC), (0xBF26FCE2, 0x400AD774),
        (0xBF23C39E, 0x400BEDFA), (0xBF208A5A, 0x400D0481), (0xBF1D5116, 0x400E1B08), (0xBF1A17D0, 0x400F3190),
        (0xBF16DE8C, 0x40104817), (0xBF13A547, 0x40115E9E), (0xBF106C03, 0x40127525), (0xBF0D32BE, 0x40138BAC),
        (0xBF09F97A, 0x4014A233), (0xBF06C035, 0x4015B8BB), (0xBF0386F0, 0x4016CF42), (0xBF004DAB, 0x4017E5C9),
        (0xBEFA28CE, 0x4018FC50), (0xBEF3B645, 0x401A12D7), (0xBEED43BC, 0x401B295E), (0xBEE6D132, 0x401C3FE6),
        (0xBEE05EA9, 0x401D566D), (0xBED9EC20, 0x401E6CF4), (0xBED37996, 0x401F837B), (0xBECD070D, 0x40209A02),
        (0xBEC69484, 0x4021B08A), (0xBEC021FA, 0x4022C711), (0xBEB9AF71, 0x4023DD98), (0xBEB33CE8, 0x4024F41F),
        (0xBEACCA5E, 0x40260AA6), (0xBEA657D5, 0x4027212D), (0xBE9FE54C, 0x402837B4), (0xBE9972C3, 0x40294E3C),
        (0xBE930039, 0x402A64C3), (0xBE8C8DB0, 0x402B7B4A), (0xBE861B28, 0x402C91D1), (0xBE7F513B, 0x402DA858),
        (0xBE726C29, 0x402EBEE0), (0xBE658717, 0x402FD567), (0xBE58A203, 0x4030EBEE), (0xBE4BBCF1, 0x40320275),
        (0xBE3ED7E0, 0x403318FC), (0xBE31F2CB, 0x40342F83), (0xBE250DBA, 0x4035460A), (0xBE1828A8, 0x40365C92),
        (0xBE0B4396, 0x40377319), (0xBDFCBD09, 0x403889A0), (0xBDE2F2DB, 0x4039A027), (0xBDC928B8, 0x403AB6AE),
        (0xBDAF5E94, 0x403BCD36), (0xBD959471, 0x403CE3BD), (0xBD77949A, 0x403DFA44), (0xBD62F2E3, 0x403E69AD),
        (0xBD4E5125, 0x403ED916), (0xBD39AF6F, 0x403F4880), (0xBD250DB8, 0x403FB7E9), (0xBD106C02, 0x40402752),
        (0xBCF79499, 0x404096BB), (0xBCCE512C, 0x40410625), (0xBCA50DB1, 0x4041758E), (0xBC779489, 0x4041E4F7),
        (0xBC250DB1, 0x40425461), (0xBBA50DB1, 0x4042C3CA), (0x00000000, 0x40433333), (0x3BA50DB1, 0x4043A29C),
        (0x3C250DD0, 0x40441206), (0x3C7794A8, 0x4044816F), (0x3CA50DC0, 0x4044F0D8), (0x3CCE512C, 0x40456041),
        (0x3CF79499, 0x4045CFAB), (0x3D106C02, 0x40463F14), (0x3D250DB8, 0x4046AE7D), (0x3D39AF76, 0x40471DE6),
        (0x3D4E512C, 0x40478D50), (0x3D62F2E3, 0x4047FCB9), (0x3D77949A, 0x40486C22), (0x3D959471, 0x404982A9),
        (0x3DAF5E94, 0x404A9930), (0x3DC928C2, 0x404BAFB8), (0x3DE2F2E5, 0x404CC63F), (0x3DFCBD09, 0x404DDCC6),
        (0x3E0B4396, 0x404EF34D), (0x3E1828A8, 0x405009D4), (0x3E250DBA, 0x4051205C), (0x3E31F2D0, 0x405236E3),
        (0x3E3ED7E2, 0x40534D6A), (0x3E4BBCF4, 0x405463F1), (0x3E58A206, 0x40557A78), (0x3E658717, 0x405690FF),
        (0x3E726C29, 0x4057A786), (0x3E7F5140, 0x4058BE0E), (0x3E861B29, 0x4059D495), (0x3E8C8DB2, 0x405AEB1C),
        (0x3E93003B, 0x405C01A3), (0x3E9972C3, 0x405D182A), (0x3E9FE54C, 0x405E2EB2), (0x3EA657D5, 0x405F4539),
        (0x3EACCA5E, 0x40605BC0), (0x3EB33CE7, 0x40617247), (0x3EB9AF70, 0x406288CE), (0x3EC021FE, 0x40639F56),
        (0x3EC69487, 0x4064B5DD), (0x3ECD0710, 0x4065CC64), (0x3ED37998, 0x4066E2EB), (0x3ED9EC21, 0x4067F972),
        (0x3EE05EAA, 0x40690FF9), (0x3EE6D133, 0x406A2680), (0x3EED43BC, 0x406B3D08), (0x3EF3B645, 0x406C538F),
        (0x3EFA28CE, 0x406D6A16), (0x3F004DAB, 0x406E809D), (0x3F0386F0, 0x406F9724), (0x3F06C037, 0x4070ADAC),
        (0x3F09F97B, 0x4071C433),
    ]

    /// A.6 scoring: one engine, calls in order.
    static let scoring: [GoldenScore] = [
        GoldenScore(quality: 100, made: true, answerQualityPercent: 100, answerCorrect: true, knowledgeMultiplier: 2, knowledgePoints: 6, basketPoints: 3, totalPoints: 9, knowledgeStreak: 1, shootingStreak: 1, bestKnowledgeStreak: 1, bestShootingStreak: 1, totalScore: 9, correctAnswers: 1, madeShots: 1, shots: 1),
        GoldenScore(quality: 100, made: true, answerQualityPercent: 100, answerCorrect: true, knowledgeMultiplier: 3, knowledgePoints: 9, basketPoints: 3, totalPoints: 12, knowledgeStreak: 2, shootingStreak: 2, bestKnowledgeStreak: 2, bestShootingStreak: 2, totalScore: 21, correctAnswers: 2, madeShots: 2, shots: 2),
        GoldenScore(quality: 100, made: false, answerQualityPercent: 100, answerCorrect: true, knowledgeMultiplier: 4, knowledgePoints: 12, basketPoints: 0, totalPoints: 12, knowledgeStreak: 3, shootingStreak: 0, bestKnowledgeStreak: 3, bestShootingStreak: 2, totalScore: 33, correctAnswers: 3, madeShots: 2, shots: 3),
        GoldenScore(quality: 100, made: true, answerQualityPercent: 100, answerCorrect: true, knowledgeMultiplier: 5, knowledgePoints: 15, basketPoints: 3, totalPoints: 18, knowledgeStreak: 4, shootingStreak: 1, bestKnowledgeStreak: 4, bestShootingStreak: 2, totalScore: 51, correctAnswers: 4, madeShots: 3, shots: 4),
        GoldenScore(quality: 100, made: true, answerQualityPercent: 100, answerCorrect: true, knowledgeMultiplier: 5, knowledgePoints: 15, basketPoints: 3, totalPoints: 18, knowledgeStreak: 5, shootingStreak: 2, bestKnowledgeStreak: 5, bestShootingStreak: 2, totalScore: 69, correctAnswers: 5, madeShots: 4, shots: 5),
        GoldenScore(quality: 100, made: true, answerQualityPercent: 100, answerCorrect: true, knowledgeMultiplier: 5, knowledgePoints: 15, basketPoints: 3, totalPoints: 18, knowledgeStreak: 6, shootingStreak: 3, bestKnowledgeStreak: 6, bestShootingStreak: 3, totalScore: 87, correctAnswers: 6, madeShots: 5, shots: 6),
        GoldenScore(quality: 100, made: true, answerQualityPercent: 100, answerCorrect: true, knowledgeMultiplier: 5, knowledgePoints: 15, basketPoints: 3, totalPoints: 18, knowledgeStreak: 7, shootingStreak: 4, bestKnowledgeStreak: 7, bestShootingStreak: 4, totalScore: 105, correctAnswers: 7, madeShots: 6, shots: 7),
        GoldenScore(quality: 100, made: true, answerQualityPercent: 100, answerCorrect: true, knowledgeMultiplier: 5, knowledgePoints: 15, basketPoints: 3, totalPoints: 18, knowledgeStreak: 8, shootingStreak: 5, bestKnowledgeStreak: 8, bestShootingStreak: 5, totalScore: 123, correctAnswers: 8, madeShots: 7, shots: 8),
        GoldenScore(quality: 0, made: true, answerQualityPercent: 0, answerCorrect: false, knowledgeMultiplier: 1, knowledgePoints: 0, basketPoints: 2, totalPoints: 2, knowledgeStreak: 0, shootingStreak: 6, bestKnowledgeStreak: 8, bestShootingStreak: 6, totalScore: 125, correctAnswers: 8, madeShots: 8, shots: 9),
        GoldenScore(quality: 50, made: false, answerQualityPercent: 50, answerCorrect: false, knowledgeMultiplier: 1, knowledgePoints: 1, basketPoints: 0, totalPoints: 1, knowledgeStreak: 0, shootingStreak: 0, bestKnowledgeStreak: 8, bestShootingStreak: 6, totalScore: 126, correctAnswers: 8, madeShots: 8, shots: 10),
        GoldenScore(quality: 1, made: true, answerQualityPercent: 1, answerCorrect: false, knowledgeMultiplier: 1, knowledgePoints: 1, basketPoints: 2, totalPoints: 3, knowledgeStreak: 0, shootingStreak: 1, bestKnowledgeStreak: 8, bestShootingStreak: 6, totalScore: 129, correctAnswers: 8, madeShots: 9, shots: 11),
        GoldenScore(quality: 34, made: true, answerQualityPercent: 34, answerCorrect: false, knowledgeMultiplier: 1, knowledgePoints: 1, basketPoints: 2, totalPoints: 3, knowledgeStreak: 0, shootingStreak: 2, bestKnowledgeStreak: 8, bestShootingStreak: 6, totalScore: 132, correctAnswers: 8, madeShots: 10, shots: 12),
        GoldenScore(quality: 67, made: true, answerQualityPercent: 67, answerCorrect: false, knowledgeMultiplier: 1, knowledgePoints: 2, basketPoints: 2, totalPoints: 4, knowledgeStreak: 0, shootingStreak: 3, bestKnowledgeStreak: 8, bestShootingStreak: 6, totalScore: 136, correctAnswers: 8, madeShots: 11, shots: 13),
        GoldenScore(quality: 99, made: false, answerQualityPercent: 99, answerCorrect: false, knowledgeMultiplier: 1, knowledgePoints: 2, basketPoints: 0, totalPoints: 2, knowledgeStreak: 0, shootingStreak: 0, bestKnowledgeStreak: 8, bestShootingStreak: 6, totalScore: 138, correctAnswers: 8, madeShots: 11, shots: 14),
        GoldenScore(quality: -5, made: false, answerQualityPercent: 0, answerCorrect: false, knowledgeMultiplier: 1, knowledgePoints: 0, basketPoints: 0, totalPoints: 0, knowledgeStreak: 0, shootingStreak: 0, bestKnowledgeStreak: 8, bestShootingStreak: 6, totalScore: 138, correctAnswers: 8, madeShots: 11, shots: 15),
        GoldenScore(quality: 150, made: true, answerQualityPercent: 100, answerCorrect: true, knowledgeMultiplier: 2, knowledgePoints: 6, basketPoints: 3, totalPoints: 9, knowledgeStreak: 1, shootingStreak: 1, bestKnowledgeStreak: 8, bestShootingStreak: 6, totalScore: 147, correctAnswers: 9, madeShots: 12, shots: 16),
        GoldenScore(quality: 33, made: false, answerQualityPercent: 33, answerCorrect: false, knowledgeMultiplier: 1, knowledgePoints: 1, basketPoints: 0, totalPoints: 1, knowledgeStreak: 0, shootingStreak: 0, bestKnowledgeStreak: 8, bestShootingStreak: 6, totalScore: 148, correctAnswers: 9, madeShots: 12, shots: 17),
        GoldenScore(quality: 66, made: true, answerQualityPercent: 66, answerCorrect: false, knowledgeMultiplier: 1, knowledgePoints: 1, basketPoints: 2, totalPoints: 3, knowledgeStreak: 0, shootingStreak: 1, bestKnowledgeStreak: 8, bestShootingStreak: 6, totalScore: 151, correctAnswers: 9, madeShots: 13, shots: 18),
        GoldenScore(quality: 100, made: true, answerQualityPercent: 100, answerCorrect: true, knowledgeMultiplier: 2, knowledgePoints: 6, basketPoints: 3, totalPoints: 9, knowledgeStreak: 1, shootingStreak: 2, bestKnowledgeStreak: 8, bestShootingStreak: 6, totalScore: 160, correctAnswers: 10, madeShots: 14, shots: 19),
    ]

    /// A.7 BasketballMovement.step: (dx, dy, speed, agility, scale, dt) -> (x, y), Float bits.
    static let movementSteps: [(dx: UInt32, dy: UInt32, speed: Int, agility: Int, scale: UInt32, dt: UInt32, x: UInt32, y: UInt32)] = [
        (0x447A0000, 0x00000000, 70, 60, 0x3F800000, 0x3C888889, 0x40A86187, 0x00000000),  // [1000.0, 0.0, 70.0, 60.0, 1.0, 0.016666668] -> Step(x=5.261905, y=0.0)
        (0x447A0000, 0x00000000, 70, 60, 0x3F800000, 0x3D03126F, 0x4121A54E, 0x00000000),  // [1000.0, 0.0, 70.0, 60.0, 1.0, 0.032] -> Step(x=10.102858, y=0.0)
        (0x00000000, 0x447A0000, 70, 60, 0x3F800000, 0x3D03126F, 0x00000000, 0x40851EB8),  // [0.0, 1000.0, 70.0, 60.0, 1.0, 0.032] -> Step(x=0.0, y=4.16)
        (0x3F4CCCCD, 0x40000000, 100, 100, 0x3F800000, 0x3DA3D70A, 0x3F4CCCCD, 0x40000000),  // [0.8, 2.0, 100.0, 100.0, 1.0, 0.08] -> Step(x=0.8, y=2.0)
        (0x447A0000, 0x447A0000, 100, 100, 0x3F800000, 0x43960000, 0x413F7678, 0x413F7678),  // [1000.0, 1000.0, 100.0, 100.0, 1.0, 300.0] -> Step(x=11.966423, y=11.966423)
        (0x40000000, 0x3F800000, 50, 50, 0x3F800000, 0x3D4CCCCD, 0x40000000, 0x3F800000),  // [2.0, 1.0, 50.0, 50.0, 1.0, 0.05] -> Step(x=2.0, y=1.0)
        (0x43960000, 0xC2F00000, 85, 40, 0x3FA00000, 0x3D4CCCCD, 0x416BAD6F, 0xC0BC8AC0),  // [300.0, -120.0, 85.0, 40.0, 1.25, 0.05] -> Step(x=14.729842, y=-5.8919373)
        (0x43960000, 0xC2F00000, 150, -20, 0x40400000, 0x3D4CCCCD, 0x41BC8AC1, 0xC116D567),  // [300.0, -120.0, 150.0, -20.0, 3.0, 0.05] -> Step(x=23.56775, y=-9.4271)
        (0x43960000, 0xC2F00000, 50, 50, 0x3F800000, 0x00000000, 0x00000000, 0x00000000),  // [300.0, -120.0, 50.0, 50.0, 1.0, 0.0] -> Step(x=0.0, y=0.0)
        (0x447A0000, 0x00000000, 90, 50, 0x3F800000, 0x3D23D70A, 0x415BE2BE, 0x00000000),  // [1000.0, 0.0, 90.0, 50.0, 1.0, 0.04] -> Step(x=13.742857, y=0.0)
        (0x447A0000, 0x00000000, 20, 50, 0x3F800000, 0x3D23D70A, 0x410F15F2, 0x00000000),  // [1000.0, 0.0, 20.0, 50.0, 1.0, 0.04] -> Step(x=8.942858, y=0.0)
        (0xC37A0000, 0x42A00000, 0, 0, 0x3F000000, 0x3C83126F, 0xBF7E1D43, 0x3EA2A216),  // [-250.0, 80.0, 0.0, 0.0, 0.5, 0.016] -> Step(x=-0.992634, y=0.31764287)
        (0x40000000, 0x3F800000, 70, 70, 0x3F800000, 0x3C83126F, 0x40000000, 0x3F800000),  // [2.0, 1.0, 70.0, 70.0, 1.0, 0.016] -> Step(x=2.0, y=1.0)
        (0x3F800000, 0x3F800000, 50, 50, 0x3F800000, 0x3D4CCCCD, 0x00000000, 0x00000000),  // [1.0, 1.0, 50.0, 50.0, 1.0, 0.05] -> Step(x=0.0, y=0.0)
    ]
    static let movementRun30: UInt32 = 0x408D70A2
    static let movementRun60: UInt32 = 0x408D70A1
    /// A.7 cutDurationMillis(dx, dy, speed, agility).
    static let cutDurations: [(dx: Int, dy: Int, speed: Int, agility: Int, millis: Int64)] = [
        (30, 20, 70, 70, 1100),
        (300, 230, 70, 70, 2418),
        (300, 230, 95, 95, 2113),
        (300, 230, 30, 30, 3232),
        (5000, 5000, 0, 0, 3800),
        (0, 0, 50, 50, 1100),
        (150, 60, 60, 80, 1121),
        (120, 60, 50, 50, 1136),
        (400, 0, 100, 100, 1468),
        (-300, 230, 120, -5, 2379),
    ]

    /// A.8 DribbleGesture(18): 12 x move(+2), 12 x move(-2), 12 x move(+2) at 8 ms steps, then 12 x move(-2) at 40 ms steps.
    static let dribble1: [[Int]] = [[0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0], [0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0], [0, 0, 0, 0, 0, 0, 0, 0, 1, 0, 0, 0], [0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0]]
    /// A.8 DribbleGesture(47.25) at t = 100, 200, ... then move(50, 1000), move(-50, 1700), move(50, 1800).
    static let dribble2: [Int] = [0, 0, 0, 0, 0, 0, 0, 0, 1, 0, 0]
    static let dribble2Then: [Int] = [0, 0, 0]
    static let dribble3: [Int] = [0, 0, 1, 0, 0, 0]
    static let dribble4: [Int] = [0, 0, 1, 0, 0, 0]
    static let dribble5: [Int] = [0, 0, 1, 0, 1, 0, 0, 0]

    /// A.9 (facing, mirror, moving, frameIndex) after each update of the A.9 script.
    static let visual: [(Int, Bool, Bool, Int)] = [
        (0, false, false, 0), (0, false, true, 0), (0, false, true, 0), (0, false, true, 0),
        (0, false, true, 0), (0, false, true, 0), (0, false, true, 0), (0, false, true, 0),
        (0, false, true, 0), (0, false, true, 0), (0, false, true, 0), (0, false, true, 0),
        (0, false, true, 0), (0, false, true, 1), (0, false, true, 1), (0, false, true, 1),
        (0, false, true, 1), (1, false, true, 1), (1, false, true, 1), (1, false, true, 1),
        (1, false, true, 1), (1, false, true, 1), (1, false, true, 1), (1, false, true, 1),
        (1, false, true, 1), (1, false, true, 1), (1, true, true, 0), (1, true, true, 0),
        (1, true, true, 0), (1, true, true, 0), (1, true, true, 0), (1, true, true, 0),
        (1, true, true, 0), (1, true, true, 0), (1, true, true, 0), (1, true, true, 0),
        (1, true, true, 0), (1, true, true, 0), (1, true, true, 0), (1, true, true, 1),
        (1, true, true, 1), (1, true, false, 1), (2, false, false, 1), (2, false, false, 1),
    ]
    static let visualTurn: [(Int, Bool, Bool, Int)] = [
        (0, false, false, 0), (0, false, false, 0), (0, false, false, 0), (1, false, false, 0),
        (1, false, false, 0), (1, false, false, 0), (2, false, false, 0), (2, false, false, 0),
        (2, true, false, 0), (2, true, false, 0), (2, true, false, 0), (2, false, false, 0),
        (0, false, false, 0), (2, true, false, 0),
    ]

    static let random12345Ints: [Int] = [36, 41, 28]
    static let random12345Booleans: [Bool] = [true, true, true]
    static let random12345Floats: [UInt32] = [0x3F518248, 0x3DC25720, 0x3F26CA5F]
    static let randomMinus7: (UInt32, UInt32, Bool) = (0x3DEB5B40, 0x3F01706B, true)
    static let rolls: [(chance: Int, roll: Int, dir: Bool, u: UInt32)] = [
        (8, 38, true, 0x3DE92160),
        (63, 75, false, 0x3AD1CC00),
        (95, 40, false, 0x3E672698),
    ]
    static let listHashes: [([Bool], Int32)] = [
        ([], 1),
        ([true], 1262),
        ([false], 1268),
        ([true, false], 40359),
        ([true, false, true], 1252360),
        ([false, false, false], 1258132),
    ]
    static let steal: (x: UInt32, y: UInt32, seedBits: Int64, seed: Int, side: Bool, bucket: UInt32, speed: UInt32) = (0x44001800, 0x44880800, 39826873159, 1172167495, false, 0x3E797728, 0x3EC203F4)
}
