import XCTest
@testable import MinikMultiPingPong

// Android cross/IssueReportTest.kt (MinikCrossPong 7254ab2), plus the iOS parts of the same issue report: the shared orientation
// tip budget and the near-player projection of the classic full-avatar court.
final class IssueReportTests: XCTestCase {
    override func tearDown() { MPText.configure("en"); super.tearDown() }

    private func fault(_ id: Int = 1) -> CrossRallyOutcome {
        CrossRallyOutcome(rallyId: id, kind: .out, striker: 0, receiver: 1, faultOwner: 0, deltas: [0, 0, 0, 0], scoresAfter: [0, 0, 0, 0],
                          floored: true, nextServer: 1, winner: nil)
    }

    // Kotlin: faultAtZeroStillFlashesAndDuplicateSnapshotDoesNotRestart
    func testFaultAtZeroStillFlashesAndDuplicateSnapshotDoesNotRestart() {
        let f = CrossScoreFeedback(), o = fault()
        f.record(o, now: 1.0)
        XCTAssertEqual(.loss, f.change(0, now: 1.0)); XCTAssertNil(f.change(1, now: 1.0))
        var copy = o; copy.deltas = Array(o.deltas); copy.scoresAfter = Array(o.scoresAfter)
        f.record(copy, now: 2.6)
        XCTAssertNil(f.change(0, now: 2.8), "the same outcome delivered again must not restart the flash")
        f.record(fault(2), now: 3.0); XCTAssertEqual(.loss, f.change(0, now: 3.0))
        f.clear(); XCTAssertNil(f.change(0, now: 3.0))
    }

    // Kotlin: awardedPointAndForgivenMissHaveDifferentOutlines
    func testAwardedPointAndForgivenMissHaveDifferentOutlines() {
        let o = CrossRallyOutcome(rallyId: 2, kind: .missed, striker: 1, receiver: 0, faultOwner: nil, deltas: [0, 1, 0, 0], scoresAfter: [0, 1, 0, 0],
                                  floored: true, nextServer: 1, winner: nil)
        let f = CrossScoreFeedback(); f.record(o, now: 0)
        XCTAssertEqual(.loss, f.change(0, now: 0)); XCTAssertEqual(.gain, f.change(1, now: 0)); XCTAssertNil(f.change(2, now: 0))
        XCTAssertNil(f.change(0, now: 0.230)); XCTAssertEqual(.loss, f.change(0, now: 0.450)); XCTAssertNil(f.change(1, now: 1.8))
    }

    // Kotlin: hebrewLocalPossessiveIsNaturalAndOtherNamesStayNamed
    func testHebrewLocalPossessiveIsNaturalAndOtherNamesStayNamed() {
        MPText.configure("he")
        let names = ["אתם", "מיניק", "גאיה", "Flare"]
        let mine = CrossText.outcome(fault(), names: names, local: 0, hebrew: true)
        XCTAssertTrue(mine.hasPrefix("הכדור שלכם"), mine)
        XCTAssertFalse(mine.contains("של אתם"), mine)
        var other = fault(); other.striker = 2; other.faultOwner = 2
        XCTAssertTrue(CrossText.outcome(other, names: names, local: 0, hebrew: true).contains("של גאיה"))
        var own = fault(); own.kind = .ownSide
        XCTAssertTrue(CrossText.outcome(own, names: names, local: 0, hebrew: true).hasPrefix("הכדור שלכם נחת בצד שלכם"))
    }

    // Kotlin: openPaintPracticeContinuesBeyondCompetitiveTimer
    func testOpenPaintPracticeContinuesBeyondCompetitiveTimer() throws {
        let step = try XCTUnwrap(CrossJourney.stages.firstIndex { $0.skill == .paint })
        let p = CrossPractice(step: step, open: true); p.start()
        for _ in 0..<(90 * 120 + 120) { p.advance(1.0 / 120) }
        XCTAssertGreaterThan(p.clock, 90); XCTAssertFalse(p.ended)
        let restored = try CrossPractice.restore(p.save())
        XCTAssertTrue(restored.open); XCTAssertFalse(restored.ended)
    }

    func testCompetitivePaintPracticeStillEndsAtNinetySeconds() throws {
        let step = try XCTUnwrap(CrossJourney.stages.firstIndex { $0.skill == .paint })
        let p = CrossPractice(step: step); p.start()
        for _ in 0..<(90 * 120 + 120) { p.advance(1.0 / 120) }
        XCTAssertTrue(p.ended)
    }

    // Android PongOrientationHint: one lifetime budget of three, shared by every match screen.
    @MainActor func testLandscapeTipStopsAfterThreeShows() throws {
        let defaults = try XCTUnwrap(UserDefaults(suiteName: "IssueReportTests.tip"))
        defaults.removePersistentDomain(forName: "IssueReportTests.tip")
        var shown = 0
        for _ in 0..<5 where MPXLandscapeTip().claimCounted(active: true, defaults: defaults) { shown += 1 }
        XCTAssertEqual(3, shown)
        XCTAssertEqual(3, defaults.integer(forKey: MPXLandscapeTip.key))
        defaults.removePersistentDomain(forName: "IssueReportTests.tip")
    }

    @MainActor func testSkippedOrLandscapeTipsDoNotUseTheBudget() throws {
        let defaults = try XCTUnwrap(UserDefaults(suiteName: "IssueReportTests.skip"))
        defaults.removePersistentDomain(forName: "IssueReportTests.skip")
        let run = MPXLandscapeTip()
        XCTAssertFalse(run.claimCounted(active: false, defaults: defaults))
        XCTAssertEqual(0, defaults.integer(forKey: MPXLandscapeTip.key))
        run.observe(landscape: true)
        XCTAssertFalse(run.claimCounted(active: true, defaults: defaults), "a run already played in landscape needs no tip")
        XCTAssertEqual(0, defaults.integer(forKey: MPXLandscapeTip.key))
        let next = MPXLandscapeTip()
        XCTAssertTrue(next.claimCounted(active: true, defaults: defaults))
        XCTAssertFalse(next.claimCounted(active: true, defaults: defaults), "once per run")
        XCTAssertEqual(1, defaults.integer(forKey: MPXLandscapeTip.key))
        defaults.removePersistentDomain(forName: "IssueReportTests.skip")
    }

    // Android NearPlayerProjection: touches use the exact inverse of the drawing.
    func testNearPlayerProjectionInvertsAndKeepsTheFarHalf() {
        for i in 0...40 {
            let y = Double(i) / 40 * 1.2
            XCTAssertEqual(y, MPNearPlayerProjection.tableY(MPNearPlayerProjection.imageY(y)), accuracy: 1e-6)
        }
        for y in [0.0, 0.2, 0.5] { XCTAssertEqual(MPProjection.imageY(y), MPNearPlayerProjection.imageY(y), accuracy: 1e-9) }
        XCTAssertEqual(MPProjection.bottom, MPNearPlayerProjection.imageY(1), accuracy: 1e-9)
    }

    // Android PongGait: a pose is held at least 110 ms, and a stroke stops the walk.
    func testGaitHoldsEachPoseAndStopsForAStroke() {
        let gait = MPGait()
        gait.update(1.0 / 60, travel: 0.05, stroke: false)
        XCTAssertTrue(gait.walking); XCTAssertEqual(0, gait.phase)
        gait.update(0.05, travel: 0.05, stroke: false); XCTAssertEqual(0, gait.phase)
        gait.update(0.07, travel: 0.05, stroke: false); XCTAssertEqual(1, gait.phase)
        gait.update(1.0 / 60, travel: 0.05, stroke: true); XCTAssertFalse(gait.walking)
    }

    // Android issue_review.xml: the six languages of the new texts.
    func testIssueTextsFollowTheAppLanguage() {
        MPText.configure("he"); XCTAssertEqual("האתגר הושלם!", MPText.issue("Challenge completed!"))
        MPText.configure("nl"); XCTAssertEqual("Je kunt ook in liggende stand spelen.", MPText.issue("You can also play in landscape."))
        MPText.configure("en"); XCTAssertEqual("Serve to the marked court", MPText.issue("Serve to the marked court"))
    }
}
