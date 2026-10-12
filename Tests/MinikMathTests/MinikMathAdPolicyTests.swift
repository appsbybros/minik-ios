import XCTest
@testable import MinikMath

// Android C:/Projects/minikMath app/src/test/java/com/appsbybros/minik/monetization/AdPolicyTest.java
// (bbd9b48), test for test. Name map: Java fields keep their names; AdPolicy.decode(p.encode()) ->
// MinikMathAdPolicy.decode(p.encoded()); p.sessions.set(4, x) -> p.sessions[4] = x.

final class MinikMathAdPolicyTests: XCTestCase {
    private func eligible() -> MinikMathAdPolicy {
        var p = MinikMathAdPolicy()
        p.complete("a"); p.complete("b"); p.complete("c")
        return p
    }

    func testFirstTwoAreFreeEvenAfterLongPlay() {
        var p = MinikMathAdPolicy()
        p.activeSinceAd = 9_999_999
        p.complete("a"); XCTAssertFalse(p.due(now: 999_999))
        p.complete("b"); XCTAssertFalse(p.due(now: 999_999))
        p.complete("c"); XCTAssertTrue(p.due(now: 999_999))
    }

    func testNormalCountThreshold() {
        var p = eligible()
        p.shown(now: 100_000)
        p.complete("d"); XCTAssertFalse(p.due(now: 500_000))
        p.complete("e"); XCTAssertTrue(p.due(now: 500_000))
    }

    func testNormalTimeThresholdIsOr() {
        var p = eligible()
        p.shown(now: 100_000)
        p.complete("d")
        p.activeSinceAd = 209_999
        XCTAssertFalse(p.due(now: 500_000))
        p.activeSinceAd += 1
        XCTAssertTrue(p.due(now: 500_000))
    }

    func testMinimumInterval() {
        var p = eligible()
        p.shown(now: 100_000)
        p.complete("d"); p.complete("e")
        XCTAssertFalse(p.due(now: 219_999))
        XCTAssertTrue(p.due(now: 220_000))
    }

    func testClockRollbackPostponesAds() {
        var p = eligible()
        p.shown(now: 500_000)
        p.complete("d"); p.complete("e")
        XCTAssertFalse(p.due(now: 200_000))
    }

    func testFiveLongSessionsUseBothThresholds() {
        var p = eligible()
        for _ in 0..<5 { p.sessions.append(900_000) }
        p.shown(now: 100_000)
        p.complete("d"); p.complete("e")
        p.activeSinceAd = 500_000
        XCTAssertFalse(p.due(now: 900_000))
        p.complete("f")
        p.activeSinceAd = 299_999
        XCTAssertFalse(p.due(now: 900_000))
        p.activeSinceAd += 1
        XCTAssertTrue(p.due(now: 900_000))
    }

    func testFewerThanFiveUseConservativeDefault() {
        var p = eligible()
        for _ in 0..<4 { p.sessions.append(990_000) }
        XCTAssertFalse(p.longSessions)
        XCTAssertTrue(p.due(now: 999_999))
    }

    func testActualAverageDeterminesLongVisits() {
        var p = eligible()
        for _ in 0..<4 { p.sessions.append(900_000) }
        p.sessions.append(899_999)
        XCTAssertFalse(p.longSessions)
        p.sessions[4] = 900_000
        XCTAssertTrue(p.longSessions)
    }

    func testDuplicateResultNeverCountsTwice() {
        var p = eligible()
        XCTAssertFalse(p.complete("c"))
        XCTAssertEqual(p.totalCompleted, 3)
    }

    func testRestoredResultsAndCountersPersist() {
        var p = eligible()
        p.active(1234, now: 500_000)
        var q = MinikMathAdPolicy.decode(p.encoded())
        XCTAssertEqual(q.activeSinceAd, 1234)
        XCTAssertEqual(q.totalCompleted, 3)
        XCTAssertFalse(q.complete("c"))
    }

    func testUnavailableAdDoesNotResetOrStackDebt() {
        var p = eligible()
        p.complete("d"); p.complete("e")
        XCTAssertTrue(p.due(now: 900_000))
        p.shown(now: 900_000)
        XCTAssertEqual(p.completedSinceAd, 0)
        XCTAssertFalse(p.due(now: 2_000_000))
    }

    func testLongBackgroundGapDoesNotBecomePlayTime() {
        var p = MinikMathAdPolicy()
        p.active(1000, now: 100_000)
        p.active(3_600_000, now: 4_000_000)
        XCTAssertEqual(p.activeSinceAd, 6000)
        XCTAssertEqual(p.sessions.first, 1000)
        XCTAssertEqual(p.sessionActive, 5000)
    }

    func testSessionsPersistAcrossProcessRestart() {
        var p = MinikMathAdPolicy()
        p.active(1000, now: 100_000)
        p = MinikMathAdPolicy.decode(p.encoded())
        p.active(1000, now: 2_000_000)
        XCTAssertEqual(p.sessions.count, 1)
    }

    func testNegativeElapsedIgnored() {
        var p = MinikMathAdPolicy()
        p.active(-1, now: 100)
        XCTAssertEqual(p.activeSinceAd, 0)
    }

    func testCorruptStateFailsToFreeAllowance() {
        let p = MinikMathAdPolicy.decode(Data("total=garbage".utf8))
        XCTAssertFalse(p.due(now: 999_999))
    }

    func testInvalidIdsDoNotCount() {
        var p = MinikMathAdPolicy()
        XCTAssertFalse(p.complete(nil))
        XCTAssertFalse(p.complete(""))
        XCTAssertFalse(p.complete("a,b"))
        XCTAssertEqual(p.totalCompleted, 0)
    }

    func testHistoryBounded() {
        var p = MinikMathAdPolicy()
        for i in 0..<800 { p.complete("id\(i)") }
        XCTAssertEqual(p.completed.count, 512)
        XCTAssertEqual(p.totalCompleted, 800)
    }
}
