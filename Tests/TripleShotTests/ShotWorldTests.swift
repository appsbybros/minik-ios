import XCTest
@testable import MinikTripleShot

// Ports of the Android 6c38131 unit tests TripleShotLooseBallTest.kt and TripleShotRadialShotTest.kt
// (app/src/test/.../view) — same assertions.

// MARK: - TripleShotLooseBallTest.kt

final class TripleShotLooseBallTest: XCTestCase {
    func testHandoffKeepsCourtPositionAndDoesNotConvertHeightToDepth() {
        let p = CourtPoint(x: 3.3, y: 2.8, z: 0.4)
        let b = TripleShotLooseBall(start: p, velocity: CourtPoint(x: 0.3, y: -2, z: 1), gravity: 9.8, centerX: 3.3, back: -2.4)
        XCTAssertEqual(p, b.position); b.advance(seconds: Float(1) / Float(60))
        XCTAssertEqual(3.305, b.position.x, accuracy: 0.0002); XCTAssertEqual(0.41667, b.position.z, accuracy: 0.0002)
        XCTAssertTrue(b.position.y < 2.8 && b.position.y > 2.75)
    }

    func testBouncingLosesEnergyAndStaysAboveTheFloor() {
        let b = TripleShotLooseBall(start: CourtPoint(x: 0, y: 3, z: 0), velocity: CourtPoint(x: 0, y: 0, z: 0.2), gravity: 9.8)
        var bounced = false; var peak: Float = 0
        for _ in 0..<600 {
            b.advance(seconds: Float(1) / Float(120)); XCTAssertTrue(b.position.y >= TripleShotLooseBall.RADIUS)
            if b.velocity.y > 0 { bounced = true }; if bounced { peak = max(peak, b.position.y) }
        }
        XCTAssertTrue(bounced); XCTAssertTrue(peak < 1.3); XCTAssertEqual(TripleShotLooseBall.RADIUS, b.position.y, accuracy: 0.001)
    }

    func testCourtBoundaryDoesNotDependOnPhoneWidth() {
        let b = TripleShotLooseBall(start: CourtPoint(x: 11.6, y: 1, z: 1), velocity: CourtPoint(x: 2, y: 0, z: 0), gravity: 9.8,
                                    centerX: 3.3, back: -2.4)
        XCTAssertFalse(b.outOfBounds); for _ in 0..<10 { b.advance(seconds: 0.02) }; XCTAssertTrue(b.outOfBounds)
    }
}

// MARK: - TripleShotRadialShotTest.kt

final class TripleShotRadialShotTest: XCTestCase {
    private let hoop = CourtPoint(x: 3.3, y: 3.35, z: 0)
    private let base = TripleShotPhysics.Geometry(900, 500, 200, 445, 555, 4, 567, 100, 220, 255, 464, 536, 21)

    func testExactHandReleaseAndContinuousReboundFromEitherSide() {
        for x: Float in [-2, 2, 5] {
            for z: Float in [2, 6] {
                let hand = CourtPoint(x: x, y: 2.5, z: z); let scale: Float = 0.01
                let geometry = TripleShotRadialShot.geometry(base: base, release: hand, hoop: hoop, scale: scale)
                let start = TripleShotRadialShot.start(release: hand, hoop: hoop, geometry: geometry, scale: scale)
                let state = TripleShotPhysics.createLaunch(
                    skill: ShotSkill(aimError: 0, powerError: 0, arcError: 0, rawPeakGyro: 0, rawReleasePitchDeg: 0),
                    startX: start.0, startY: start.1, targetX: 500, targetY: 200, pullBack01: 0.6, geometry: geometry,
                    distanceDifficulty: 0.4, neutralPowerHitsTarget: true, compactOneOnOneArc: true, rejectUpwardBasketEntry: true)
                let bridge = TripleShotShotPresentation(); bridge.prepareWorldRelease(point: hand)
                let first = bridge.sample(state: state, geometry: geometry, hoop: hoop, verticalScale: scale)
                XCTAssertEqual(hand.x, first.x, accuracy: 0.0001); XCTAssertEqual(hand.y, first.y, accuracy: 0.0001)
                XCTAssertEqual(hand.z, first.z, accuracy: 0.0001)
                for _ in 0..<360 { _ = TripleShotPhysics.step(state: state, geometry: geometry, dtSeconds: Float(1) / Float(240)) }
                XCTAssertTrue(state.made, "Clean shot from \(hand) must clear the rim and score: \(state)")
                let end = bridge.sample(state: state, geometry: geometry, hoop: hoop, verticalScale: scale)
                let loose = TripleShotLooseBall(start: end,
                                                velocity: bridge.velocity(state: state, geometry: geometry, hoop: hoop, verticalScale: scale),
                                                gravity: 9.8, centerX: hoop.x, back: -2.4)
                XCTAssertEqual(end, loose.position)
            }
        }
    }

    func testSideShotsDoNotHitAnInvisibleBackboard() {
        let side = TripleShotRadialShot.geometry(base: base, release: CourtPoint(x: -2, y: 2, z: 0), hoop: hoop, scale: 0.01)
        XCTAssertTrue(side.backboardX > 1e6)
        let front = TripleShotRadialShot.geometry(base: base, release: CourtPoint(x: 3.3, y: 2, z: 6), hoop: hoop, scale: 0.01)
        XCTAssertEqual(567, front.backboardX, accuracy: 0.001)
    }
}
