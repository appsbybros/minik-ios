import XCTest
@testable import MinikMultiPingPong

// Android MinikCrossPong 47ad0c9 (the v8 issue report, docs/qa/issues-20261103-v8): ServeTutorialRegressionTest, the changed
// CrossExerciseTest, and the iOS parts of the same fixes: the stroke's actual impact time, the game-sounds gate, the tournament
// wording, the grouped tables' seat layout, and the learning screen's Back / close / Help flow.
final class IssueReportV8Tests: XCTestCase {
    override func setUp() { super.setUp(); MPText.configure("en") }
    override func tearDown() { MPText.configure("en"); super.tearDown() }

    // Kotlin: ServeTutorialRegressionTest.everyControlStartsWithAReachableServeDemonstration
    func testEveryControlStartsWithAReachableServeDemonstration() {
        for players in [3, 4] {
            for control in CrossControl.allCases {
                let g = CrossTutorial(players: players, control: control, names: ["You", "Minik", "Mia", "Kyra"])
                XCTAssertEqual(.serve, g.lesson.kind)
                XCTAssertEqual(.explain, g.phase)
                g.demo(); g.engine.paused = false
                for _ in 0..<1600 { g.engine.advance(1.0 / 120); g.update() }
                XCTAssertEqual(true, g.engine.trainingResult?.success, "\(players) \(control) demonstration must land legally: \(String(describing: g.engine.trainingResult))")
                XCTAssertEqual(.explain, g.phase)
            }
        }
    }

    // Kotlin: ServeTutorialRegressionTest.practiceBackDoesNotExitOrSkipServe
    func testPracticeBackDoesNotExitOrSkipServe() {
        let g = CrossTutorial(players: 4, control: .standard, names: ["You"])
        g.practice(); g.back()
        XCTAssertEqual(0, g.index)
        XCTAssertEqual(.explain, g.phase)
    }

    /// Android 47ad0c9: the guide starts with the serve, then the table; there is no introduction card, and the first card has
    /// nothing before it (its Back leaves the guide).
    func testGuideStartsWithServeThenTable() {
        let g = CrossTutorial(players: 3, control: .beginner, names: ["You"])
        XCTAssertEqual([CrossTutorial.Kind.serve, .table, .returning, .returning, .team, .scoring], g.lessons.map(\.kind))
        XCTAssertFalse(g.canGoBack)
        g.practice(); XCTAssertTrue(g.canGoBack)
        g.back(); XCTAssertFalse(g.canGoBack)
        XCTAssertTrue(g.next()); XCTAssertEqual(.table, g.lesson.kind); XCTAssertEqual(.info, g.phase); XCTAssertTrue(g.canGoBack)
        g.back(); XCTAssertEqual(0, g.index); XCTAssertEqual(.explain, g.phase)
        // The explanation no longer ends with "Practice never costs points."
        XCTAssertFalse(g.card(false).message.contains("Practice never costs points."))
    }

    /// Android CrossTutorial 47ad0c9: a Pro serve swiped downward is explained as a sideways or downward swipe.
    func testBackwardServeRetryNamesTheSwipe() {
        let g = CrossTutorial(players: 4, control: .pro, names: ["You"])
        g.practice(); g.engine.paused = false
        let e = g.engine, spot = e.geometry.toView(0, e.serveSpot(0))
        e.touch(e.geometry.fromView(0, spot - MPPoint(0, 0.08)))
        e.touch(e.geometry.fromView(0, spot + MPPoint(0, 0.08)), velocity: MPPoint(0, 0.6), down: false)
        XCTAssertEqual(.backward, e.trainingResult?.serveFault)
        g.update()
        XCTAssertEqual(.result, g.phase)
        let card = g.card(false)
        XCTAssertEqual("Let's try again", card.title)
        XCTAssertTrue(card.message.contains("Your swipe went sideways or down."), card.message)
        XCTAssertEqual("בואו ננסה שוב", g.card(true).title)
    }

    /// Android ModernEvents 47ad0c9 `Stroke.impactAt`: the actual contact time, not the earliest allowed one.
    func testStrokeRecordsItsActualImpactTime() {
        var s = MPStroke(contactAt: 0.10, windowEnd: 0.40, followEnd: 0.50, total: 0.62)
        s.start(1, MPPoint(0.5, 0.8), 0, false)
        XCTAssertEqual(0.10, s.impactAt, accuracy: 1e-12)
        s.advance(0.18)
        s.contact(MPPoint(0.5, 0.8), 0.2)
        XCTAssertEqual(0.18, s.impactAt, accuracy: 1e-12)
        s.start(2, MPPoint(0.5, 0.8), 0, false)
        XCTAssertEqual(0.10, s.impactAt, accuracy: 1e-12, "a new stroke forgets the last impact")
        s.advance(0.04)
        s.contact(MPPoint(0.5, 0.8), 0.2)
        XCTAssertEqual(0.10, s.impactAt, accuracy: 1e-12, "an early contact still happens at the window's start")
    }

    /// Android ModernAudio / LobbyAudio 47ad0c9: "Game sounds" decides every cue of the shared player.
    @MainActor
    func testGameSoundsSettingGatesEveryCue() throws {
        let suite = "IssueReportV8Tests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let preferences = MPPreferences(defaults)
        let controller = MPController(experience: .full, preferences: preferences, repository: MPLocalRepository(defaults: defaults), onClose: { _ in })
        XCTAssertTrue(controller.audio.soundsEnabled())
        preferences.journeySound = false
        XCTAssertFalse(controller.audio.soundsEnabled())
        var asked = 0
        let audio = MPAudio()
        audio.soundsEnabled = { asked += 1; return false }
        audio.play("minik_kick"); audio.play("connected")
        XCTAssertEqual(2, asked)
    }

    /// Android PlayActivity 47ad0c9: the advancement selector's wording and the renamed tournament actions, in every language.
    func testTournamentWordingIsInTheCatalog() {
        let keys = Set(MPTextCatalog.rows.map { $0.0 })
        for key in ["Players advancing from each table", "Top one", "Top two", "Cancel tournament", "Cancel tournament?", "Back to tournament",
                    "Let's try again", "Keep the ball on the table and send it to another player's colored arm. "] {
            XCTAssertTrue(keys.contains(key), key)
        }
        XCTAssertEqual("שחקנים שעולים מכל שולחן", MPText.t("Players advancing from each table", "שחקנים שעולים מכל שולחן", true))
        MPText.configure("es")
        XCTAssertEqual("Jugadores que pasan de cada mesa", MPText.t("Players advancing from each table", "שחקנים שעולים מכל שולחן", false))
        XCTAssertEqual("Los dos primeros", MPText.t("Top two", "שני הראשונים", false))
        XCTAssertEqual("Volver al torneo", MPText.t("Back to tournament", "חזרה לטורניר", false))
    }

    /// Android TournamentTableCard 47ad0c9: the fixture's first seat is at the bottom and every seat has its own place around
    /// the table in the middle; the scores use the court's seat colours.
    @MainActor
    func testTournamentTableSeatsSurroundTheTable() {
        for count in 2...4 {
            let places = (0..<count).map { MPXTournamentTable.place($0, count: count) }
            XCTAssertEqual(1, places[0].column); XCTAssertEqual(2, places[0].row)
            XCTAssertEqual(count, Set(places.map { $0.column * 3 + $0.row }).count, "\(count) seats need \(count) places")
            XCTAssertFalse(places.contains { $0.column == 1 && $0.row == 1 }, "the middle holds the table")
        }
        for seat in 0..<4 {
            let c = CrossScene.seatColors[seat]
            XCTAssertEqual(0xff00_0000 | UInt32(c.0) << 16 | UInt32(c.1) << 8 | UInt32(c.2), MPXSeatColor.argb(seat))
        }
    }

    /// Android CrossActivity 47ad0c9: "Learn how to play" opens the serve card; a practice's Back returns to its card; the first
    /// card's Back closes the learning screen. Help pauses a running match and its X resumes it.
    @MainActor
    func testLearningBackCloseAndHelp() throws {
        let suite = "IssueReportV8Tests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let preferences = MPPreferences(defaults)
        let controller = MPController(experience: .full, preferences: preferences, repository: MPLocalRepository(defaults: defaults), onClose: { _ in })
        controller.openCross(learn: true, seed: 7)
        XCTAssertEqual(.cross, controller.route)
        let first = try XCTUnwrap(controller.tourCard)
        XCTAssertEqual(.explain, first.phase)
        XCTAssertEqual("Serve", first.title)
        XCTAssertFalse(first.canGoBack)
        controller.tourTry()
        XCTAssertNil(controller.tourCard)
        controller.back()
        XCTAssertEqual(.explain, controller.tourCard?.phase, "Back from a practice returns to its lesson")
        controller.tourBack()
        XCTAssertEqual(.menu, controller.route, "Back on the first card leaves the learning screen")

        preferences.crossGuideSeen = true
        controller.openCross(learn: false, seed: 7)
        XCTAssertNil(controller.tourCard)
        XCTAssertFalse(controller.crossPaused)
        controller.showCrossHelp()
        let help = try XCTUnwrap(controller.crossHelp)
        XCTAssertEqual("Help", help.title)
        XCTAssertTrue(help.message.hasPrefix("Keep the ball on the table"), help.message)
        XCTAssertTrue(controller.crossPaused)
        controller.closeCrossHelp()
        XCTAssertNil(controller.crossHelp)
        XCTAssertFalse(controller.crossPaused)
    }
}
