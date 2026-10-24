import XCTest
@testable import MinikTripleShot

// Ports of the Android 6c38131 unit tests BasketballMovesTest.kt and TrumpetCadenceTest.kt — same assertions.

// MARK: - BasketballMovesTest.kt

final class BasketballMovesTest: XCTestCase {
    func testCircleRecognizesBothDirectionsButNotZigzags() {
        for sign in [-1, 1] {
            let g = CircularDribbleGesture(14); var events: [Int] = []; var previousX: Float = 32; var previousY: Float = 0
            for i in 1...40 {
                let a = Double(sign * i * 2) * Double.pi / 40
                let x = Float(32) * cos(a).toFloat(); let y = Float(32) * sin(a).toFloat()
                events.append(g.move(dx: x - previousX, dy: y - previousY, now: 1000 + Int64(i) * 20))
                previousX = x; previousY = y
            }
            XCTAssertEqual([sign], events.filter { $0 != 0 })
        }
        let g = CircularDribbleGesture(14)
        for it in 0..<60 { XCTAssertEqual(0, g.move(dx: it / 10 % 2 == 0 ? 5 : -5, dy: 0, now: 1000 + Int64(it) * 10)) }
    }

    func testSpinChanceUsesRatingQuickRetriesAndResetsAfterPause() {
        let s = BasketballMoves.SpinSeries()
        XCTAssertEqual(0.1, s.attempt(now: 1000, defense: 100) { 0.99 }.chance, accuracy: 0.0001)
        XCTAssertEqual(0.15, s.attempt(now: 1600, defense: 100) { 0.99 }.chance, accuracy: 0.0001)
        for it in 0..<12 { _ = s.attempt(now: 2200 + Int64(it) * 600, defense: 100) { 0.99 } }
        XCTAssertEqual(0.45, s.attempt(now: 9600, defense: 100) { 0.99 }.chance, accuracy: 0.0001)
        XCTAssertEqual(0.2, s.attempt(now: 15000, defense: 0) { 0.99 }.chance, accuracy: 0.0001)
    }

    func testIndependentTrialsHaveExpectedSuccessFallAndRecoveryDistribution() {
        let r = KotlinRandom(seed: 4004); var success = 0; var falls = 0
        for _ in 0..<30000 {
            let result = BasketballMoves.SpinSeries().attempt(now: 1000, defense: 100) { r.nextFloat() }
            if result.success {
                success += 1; if result.fall { falls += 1 }
                XCTAssertTrue(result.recoveryMs >= 1000 && result.recoveryMs <= 2000)
            }
        }
        XCTAssertTrue(success >= 2800 && success <= 3200)
        let fallShare = falls.toFloat() / success.toFloat()
        XCTAssertTrue(fallShare >= Float(0.17) && fallShare <= Float(23) / Float(100))
        XCTAssertEqual(0.95, BasketballMoves.screenChance(defense: 0), accuracy: 0.00001)
        XCTAssertEqual(0.85, BasketballMoves.screenChance(defense: 100), accuracy: 0.00001)
        XCTAssertEqual(0.10, BasketballMoves.switchChance(defense: 0), accuracy: 0.00001)
        XCTAssertEqual(0.20, BasketballMoves.switchChance(defense: 100), accuracy: 0.00001)
    }
}

// MARK: - TrumpetCadenceTest.kt

final class TrumpetCadenceTest: XCTestCase {
    func testMixedEventsShareCountAndWaitForMinimumGap() {
        let c = TrumpetCadence(random: KotlinRandom(seed: 10)); let initial = c.target
        for it in kuntil(0, initial - 1) {
            XCTAssertFalse(c.event(event: TrumpetCadence.Event.allCases[it % 3], liveMillis: Int64(it) * 100))
        }
        XCTAssertTrue(c.event(event: .DUNK, liveMillis: 2000)); c.acknowledge(liveMillis: 2000)
        for _ in kuntil(0, c.target) { XCTAssertFalse(c.event(event: .OFFENSE, liveMillis: 5000)) }
        XCTAssertTrue(c.event(event: .DISTANCE_BASKET, liveMillis: 20000)); c.acknowledge(liveMillis: 20000)
        XCTAssertEqual(2, c.played); XCTAssertEqual(0, c.count)
    }

    func testRotationPreservesProgressReplayGetsNewBudgetAndCapIsFive() {
        let c = TrumpetCadence(random: KotlinRandom(seed: 25)); for _ in 0..<3 { _ = c.event(event: .DUNK, liveMillis: 0) }
        let restored = TrumpetCadence(random: KotlinRandom(seed: 6)); restored.restore(s: c.snapshot())
        XCTAssertEqual(c.snapshot(), restored.snapshot())
        for n in 0..<5 {
            while !restored.event(event: .OFFENSE, liveMillis: Int64(n) * 20000) {}
            restored.acknowledge(liveMillis: Int64(n) * 20000)
        }
        for _ in 0..<80 { XCTAssertFalse(restored.event(event: .DUNK, liveMillis: 200000)) }
        restored.reset(); XCTAssertEqual(0, restored.total); XCTAssertEqual(0, restored.played)
        XCTAssertTrue(restored.target >= 7 && restored.target <= 12)
    }

    func testRandomizedThresholdsStayWithinRequestedRange() {
        let values = Set((1...100).map { TrumpetCadence(random: KotlinRandom(seed: $0)).target })
        XCTAssertEqual(Set(7...12), values)
    }
}
