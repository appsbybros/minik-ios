import XCTest
@testable import MinikPlus

/// Owner, 15 November 2026 (the App Review reply for Minik Plus): the grown-up check comes before
/// the Parent Area opens, and one check covers the whole visit.
final class ParentAreaVisitTests: XCTestCase {
    func testNoVisitIsOpenBeforeTheGrownUpCheck() {
        let visit = ParentAreaVisit()
        XCTAssertFalse(visit.isOpen)
        // Back from a Parent Area page without a passed check leads to the main screen.
        XCTAssertFalse(visit.backFromPageOpensParentArea)
    }

    func testTheGrownUpCheckOpensOneVisitOnly() {
        var visit = ParentAreaVisit()
        visit.grownUpCheckPassed()
        XCTAssertTrue(visit.isOpen)
        // Progress, Records and Learning progress return into the same visit without a new check.
        XCTAssertTrue(visit.backFromPageOpensParentArea)
        XCTAssertTrue(visit.backFromPageOpensParentArea)

        visit.leave()
        XCTAssertFalse(visit.isOpen)
        XCTAssertFalse(visit.backFromPageOpensParentArea)

        // The next visit needs the check again.
        visit.grownUpCheckPassed()
        XCTAssertTrue(visit.isOpen)
    }

    func testLeavingTwiceKeepsTheVisitClosed() {
        var visit = ParentAreaVisit()
        visit.leave()
        visit.leave()
        XCTAssertEqual(visit, ParentAreaVisit())
    }
}
