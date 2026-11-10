import XCTest
@testable import MinikMultiPingPong

// Multi Ping Pong iOS stage 5 (2026-11-10): guidance and polish, from Android MinikCrossPong c93e760 (CrossPracticeGuide, the
// Daily controls line), 971e958 (receivingSetTip), d0bed3b (court-tap help, tutorial navigation), d376d64 / 80fc74e (the result
// card's readable lettering, the steady point highlight, R.string.tap_opponent_side_to_serve), a6c0b9a (tournament tables) and
// the spacing commits, at dd94c09. Ported Kotlin test: TutorialTapAndRestTest.navigationHasNoPhantomEndpoints (the rest of that
// file is in MultiStageThreeTests); IssueReportTests carries the updated Kotlin IssueReportTest.
final class MultiStageFiveTests: XCTestCase {
    override func setUp() { super.setUp(); MPText.configure("en") }
    override func tearDown() { MPText.configure("en"); super.tearDown() }

    private func defaults() throws -> (UserDefaults, String) {
        let suite = "multi.stage5." + UUID().uuidString
        return (try XCTUnwrap(UserDefaults(suiteName: suite)), suite)
    }
    private func step(_ skill: CrossSkill) throws -> Int { try XCTUnwrap(CrossJourney.stages.firstIndex { $0.skill == skill }) }

    // ---- Kotlin TutorialTapAndRestTest (d0bed3b) ----

    // Kotlin: navigationHasNoPhantomEndpoints
    func testNavigationHasNoPhantomEndpoints() {
        for n in [3, 4] {
            let g = CrossTutorial(players: n, control: .starter, names: ["You"])
            XCTAssertFalse(g.canGoBack); XCTAssertTrue(g.canGoNext)
            g.practice(); XCTAssertTrue(g.canGoBack); g.back(); XCTAssertFalse(g.canGoBack)
            while g.canGoNext { XCTAssertTrue(g.next()) }
            XCTAssertEqual(.scoring, g.lesson.kind)
            XCTAssertTrue(g.canGoBack); XCTAssertFalse(g.next()); XCTAssertFalse(g.canGoNext)
        }
    }

    /// Android d0bed3b CrossActivity.showGuideCard: Back only with a card before, Next only with a card after; reaching the last
    /// card marks the guide as seen, and nothing ends the guide from there but its X (or Learn team play).
    @MainActor
    func testGuideCardsOfferOnlyTheNavigationThatExists() throws {
        let (store, suite) = try defaults()
        defer { store.removePersistentDomain(forName: suite) }
        let preferences = MPPreferences(store)
        let controller = MPController(experience: .full, preferences: preferences, repository: MPLocalRepository(defaults: store), onClose: { _ in })
        controller.openCross(learn: true, seed: 7)
        let first = try XCTUnwrap(controller.tourCard)
        XCTAssertFalse(first.canGoBack); XCTAssertTrue(first.canGoNext)
        XCTAssertFalse(preferences.crossGuideSeen)
        var cards = 1
        while controller.tourCard?.canGoNext == true && cards < 20 { controller.tourNext(); cards += 1 }
        let last = try XCTUnwrap(controller.tourCard)
        XCTAssertFalse(last.canGoNext); XCTAssertTrue(last.canGoBack)
        XCTAssertEqual(.info, last.phase); XCTAssertTrue(last.teamPractice, "the scoring card offers Learn team play")
        XCTAssertTrue(preferences.crossGuideSeen, "the last card marks the guide as seen (guide_seen)")
        controller.tourNext()
        XCTAssertEqual(last, controller.tourCard, "Next does not exist on the last card")
        XCTAssertEqual(.cross, controller.route)
        controller.tourBack()
        XCTAssertEqual(true, controller.tourCard?.canGoNext)
    }

    // ---- d0bed3b: court-tap wording ----

    func testCourtTapGuideTextsInEnglishHebrewAndTheCatalogLanguages() {
        let g = CrossTutorial(players: 4, control: .standard, names: ["You"])
        let serve = g.card(false).message
        XCTAssertTrue(serve.contains("'s side of the table on your right to serve there. You can also tap your side and drag toward them."), serve)
        XCTAssertTrue(g.card(true).message.contains("כדי להגיש לשם. אפשר גם להקיש בצד שלכם ולגרור לכיוונם."))
        g.next(); g.next()
        XCTAssertEqual(.returning, g.lesson.kind)
        XCTAssertTrue(g.card(false).message.contains("When the ball reaches your paddle, tap the other player’s court to aim there, or swipe sideways. A faster swipe hits harder."))
        for (language, column) in [("es", 0), ("ar", 1), ("hi", 2), ("nl", 3)] {
            MPText.configure(language)
            let key = "When the ball reaches your paddle, tap the other player’s court to aim there, or swipe sideways. A faster swipe hits harder."
            let row = MPTextCatalog.rows.first { $0.0 == key }
            XCTAssertEqual(4, row?.1.count)
            XCTAssertTrue(g.card(false).message.contains(row?.1[column] ?? "?"), language)
            let tour = CrossTutorial(players: 4, control: .beginner, names: ["You"])
            let template = MPTextCatalog.rows.first { $0.0.hasPrefix("Tap {0}'s side of the table {1} to serve there.") }?.1[column] ?? "?"
            let opening = String(template[..<(template.range(of: "{0}")?.lowerBound ?? template.endIndex)])
            XCTAssertTrue(tour.card(false).message.contains(opening), "\(language): \(tour.card(false).message)")
        }
    }

    /// Android d0bed3b CrossActivity.showHelp for Beginner and Standard (Starter and Pro are unchanged).
    @MainActor
    func testCrossHelpUsesTheCourtTapWording() throws {
        let (store, suite) = try defaults()
        defer { store.removePersistentDomain(forName: suite) }
        let preferences = MPPreferences(store)
        preferences.crossGuideSeen = true
        let controller = MPController(experience: .full, preferences: preferences, repository: MPLocalRepository(defaults: store), onClose: { _ in })
        controller.openCross(learn: false, seed: 7)
        controller.showCrossHelp()
        let message = try XCTUnwrap(controller.crossHelp?.message)
        XCTAssertEqual("Keep the ball on the table and send it to another player's colored arm. Serve: tap another player’s court to aim there, or tap your side and drag left or right. Return: move your paddle into the ball's path; it hits automatically.", message)
        controller.closeCrossHelp()
    }

    // ---- c93e760: CrossPracticeGuide and the Daily controls line ----

    func testPracticeInstructionsDescribeTheAssistedGestures() throws {
        let drag = "Drag your player left or right to meet the ball. The paddle hits automatically."
        let tapAim = "To aim, tap a spot on another court before contact. Each safe return counts."
        let gold = "Tap the gold target first, then drag your player left or right to meet the ball."
        let auto = "The paddle returns toward your selected spot automatically. A hit on the target counts."
        func stage(_ skill: CrossSkill) -> CrossStage { CrossJourney.stages.first { $0.skill == skill }! }
        XCTAssertEqual("Tap the highlighted court to serve. The ball must bounce on your side, then on the highlighted court.", CrossPracticeGuide.instruction(stage(.serve), false))
        XCTAssertEqual(drag + "\n\n" + tapAim, CrossPracticeGuide.instruction(stage(.returning), false))
        XCTAssertEqual(drag + "\n\n" + tapAim, CrossPracticeGuide.instruction(stage(.defend), false))
        XCTAssertEqual(gold + "\n\n" + auto, CrossPracticeGuide.instruction(stage(.aim), false))
        XCTAssertEqual(gold + "\n\nMeet the ball on your left for a backhand. " + auto, CrossPracticeGuide.instruction(stage(.backhand), false))
        XCTAssertEqual(gold + "\n\nMeet the ball on your right for a forehand. " + auto, CrossPracticeGuide.instruction(stage(.forehand), false))
        XCTAssertEqual("Follow the numbered gold targets in order.\n\n" + gold + " " + auto, CrossPracticeGuide.instruction(stage(.shape), false))
        XCTAssertTrue(CrossPracticeGuide.instruction(stage(.pass), false).hasPrefix("Tap your teammate's court, then drag left or right"))
        XCTAssertTrue(CrossPracticeGuide.instruction(stage(.set), false).hasPrefix("Drag your player into the ball's path. Tap twice quickly"))
        XCTAssertTrue(CrossPracticeGuide.instruction(stage(.smash), false).hasSuffix("This smash needs a swipe, not an automatic hit."))
        XCTAssertTrue(CrossPracticeGuide.instruction(stage(.paint), false).hasPrefix("Tap opponents' courts to aim"))
        XCTAssertEqual("הקישו על הצד המודגש כדי להגיש. הכדור צריך לקפוץ בצד שלכם ואז בצד המודגש.", CrossPracticeGuide.instruction(stage(.serve), true))
        for (language, column) in [("es", 0), ("ar", 1), ("hi", 2), ("nl", 3)] {
            MPText.configure(language)
            func row(_ key: String) -> String { MPTextCatalog.rows.first { $0.0 == key }?.1[column] ?? "?" }
            XCTAssertEqual(row(gold) + "\n\n" + row(auto), CrossPracticeGuide.instruction(stage(.aim), false), language)
            XCTAssertEqual(row(drag) + "\n\n" + row(tapAim), CrossPracticeGuide.instruction(stage(.returning), false), language)
        }
    }

    /// Android c93e760 CrossPracticeGuide.tip: an aiming lesson waits for its gold target; then the learner drags to the ball.
    func testAimedLessonTipAsksForTheTargetBeforeEachFeed() throws {
        let p = CrossPractice(step: try step(.aim))
        p.start()
        p.advance(CrossEngine.step)
        XCTAssertNil(p.engine.selectedAim)
        XCTAssertEqual("Tap the gold target to start the next ball.", CrossPracticeGuide.tip(p, false))
        XCTAssertEqual("הקישו על המטרה הזהובה כדי להתחיל את הכדור הבא.", CrossPracticeGuide.tip(p, true))
        p.engine.touch(p.target); p.engine.endTouch()
        XCTAssertNotNil(p.engine.selectedAim)
        XCTAssertEqual("Target chosen. Drag left or right to meet the ball.", CrossPracticeGuide.tip(p, false))
        let pass = CrossPractice(step: try step(.pass))
        XCTAssertEqual("Tap your teammate's court, then meet the ball.", CrossPracticeGuide.tip(pass, false))
        XCTAssertEqual("Wait for your teammate's high pass.", CrossPracticeGuide.tip(CrossPractice(step: try step(.smash)), false))
        XCTAssertEqual("Drag left or right. The paddle hits automatically.", CrossPracticeGuide.tip(CrossPractice(step: try step(.returning)), false))
    }

    /// Android c93e760 / d376d64 / dd94c09 CrossJourneyActivity: the brief, HUD and Help name the controls ("Controls: Beginner"); a
    /// practice's HUD keeps four portrait lines, a team match's three; the fraction is isolated with no-break spaces (651245f).
    @MainActor
    func testJourneyNamesTheControlsAndKeepsItsHudLines() throws {
        let (store, suite) = try defaults()
        defer { store.removePersistentDomain(forName: suite) }
        let preferences = MPPreferences(store)
        let model = CrossJourneyModel(page: .brief, players: 4, preferences: preferences, hebrew: false, audio: MPAudio(), onClose: {}, onOnlineTeams: { _ in })
        XCTAssertEqual("Controls: Beginner", model.controls())
        XCTAssertEqual("רמת השליטה: מתחילים", CrossJourneyModel(page: .brief, players: 4, preferences: preferences, hebrew: true, audio: MPAudio(), onClose: {}, onOnlineTeams: { _ in }).controls())
        let aim = try step(.aim)
        model.startJourney(aim)
        XCTAssertEqual(4, model.hudLines)
        let goal = try XCTUnwrap(model.practice?.goal)
        XCTAssertEqual("Controls: Beginner · \u{2066}\u{2066}0\u{00a0}/\u{00a0}\(goal)\u{2069} · ♥ 3\u{2069}", model.hudScore)
        XCTAssertEqual("Tap the gold target to start the next ball.", model.hudTip)
        XCTAssertEqual(model.hudTitle + "\n" + (model.hudScore ?? "") + "\n" + model.hudTip, model.hud)
        model.showHelp()
        XCTAssertEqual("Controls: Beginner\n\n" + CrossPracticeGuide.instruction(CrossJourney.stages[aim], false), model.help)
        model.closeHelp()
        model.startTeamMatch(seed: 3)
        XCTAssertEqual(3, model.hudLines)
        XCTAssertNil(model.hudScore)
        XCTAssertEqual("Team match", model.hudTitle)
        XCTAssertEqual("Tap an opponent’s side to serve", model.hudTip, "the learner serves first in a team match")
        model.back()
    }

    // ---- 971e958: receivingSetTip ----

    /// The smash practice's teammate always sets to the learner (teamLesson 0): wait for the bounce, then swipe up through it.
    func testReceivingSetTipWaitsForTheBounceThenAsksForTheSwipe() throws {
        let p = CrossPractice(step: try step(.smash))
        p.start()
        var waited = false, swiped = false
        for _ in 0..<(30 * 120) {
            let e = p.engine
            if e.referee.mayServe(0) { e.touch(p.target); e.endTouch() }
            if e.receivingSet {
                if e.referee.phase == .receivable {
                    XCTAssertEqual("Swipe up through the bounced ball to smash", CrossText.receivingSetTip(e, false))
                    XCTAssertEqual("החליקו למעלה דרך הכדור אחרי הקפיצה כדי להנחית", CrossText.receivingSetTip(e, true))
                    swiped = true; break
                }
                XCTAssertEqual("Your teammate is setting for you. Wait for the bounce.", CrossText.receivingSetTip(e, false))
                XCTAssertEqual("חבר הקבוצה מרים לכם. חכו לקפיצה בצד שלכם.", CrossText.receivingSetTip(e, true))
                waited = true
            } else if e.predictedReceiver == 0, e.geometry.inStrikeZone(0, e.ballPosition) {
                e.touch(e.ballPosition, down: false)
            }
            p.advance(CrossEngine.step)
        }
        XCTAssertTrue(waited, "the teammate's high pass came to the learner")
        XCTAssertTrue(swiped, "the high pass bounced on the learner's court")
        MPText.configure("es")
        XCTAssertEqual("Tu compañero te envía una pelota alta. Espera al bote.", CrossText.receivingSetTip(CrossPractice(step: try step(.smash)).engine, false))
    }

    // ---- d376d64: the serve tips of R.string ----

    func testServeTipsInEveryLanguage() {
        let marked = ["en": "Tap the highlighted side to serve", "he": "הקישו על השולחן המודגש כדי להגיש", "es": "Toca la zona resaltada para sacar",
                      "ar": "اضغط على الجزء المضيء للإرسال", "hi": "सर्व करने के लिए चमकते हिस्से पर टैप करें", "nl": "Tik op het gemarkeerde vak om te serveren"]
        let opponent = ["en": "Tap an opponent’s side to serve", "he": "הקישו על צד של יריב כדי להגיש", "es": "Toca el lado de un rival para sacar",
                        "ar": "اضغط على جانب أحد المنافسين للإرسال", "hi": "सर्व करने के लिए किसी विरोधी की तरफ़ टैप करें", "nl": "Tik op de kant van een tegenstander om te serveren"]
        for language in ["en", "he", "es", "ar", "hi", "nl"] {
            MPText.configure(language)
            XCTAssertEqual(marked[language], MPText.issue("Tap the highlighted side to serve"), language)
            XCTAssertEqual(opponent[language], MPText.issue("Tap an opponent’s side to serve"), language)
        }
        XCTAssertNil(MPText.issueTexts["Tap the highlighted court to serve"], "the old English text is gone (d376d64)")
    }

    // ---- Owner decision (stage 5): no English fallback on the stage-5 screens ----

    /// Texts Android leaves in English outside English and Hebrew get iOS-only translations (MPTextIOS), read after Android's rows.
    func testStageFiveTextsAreTranslatedWhereAndroidFallsBackToEnglish() {
        for (key, values) in MPTextIOS.rows {
            XCTAssertNil(MPTextCatalog.rows.first { $0.0 == key }, "an Android row must win: \(key)")
            XCTAssertEqual(4, values.count, key)
            for value in values { XCTAssertFalse(value.isEmpty); XCTAssertNotEqual(key, value) }
        }
        MPText.configure("es")
        XCTAssertEqual("Mesa 2", MPText.t("Table 2", "שולחן 2", false))
        XCTAssertEqual("Desempate por el 2.º puesto", MPText.t("Tie-break for 2nd place", "שובר שוויון על המקום השני", false))
        XCTAssertEqual("La pelota tocó la red", MPText.t("Ball hit the net", "הכדור פגע ברשת", false), "not the catalog's {0} hit the net template")
        XCTAssertEqual("Juego por equipos: prepara un remate", CrossText.setTitle(false))
        let starter = CrossTutorial(players: 4, control: .starter, names: ["You"])
        starter.next(); starter.next()
        XCTAssertTrue(starter.card(false).message.hasSuffix("Inicial te da más tiempo para devolverla."), starter.card(false).message)
        MPText.configure("nl")
        XCTAssertEqual("Tafel 3", MPText.t("Table 3", "שולחן 3", false))
        XCTAssertEqual("Punt voor jouw team", MPText.t("Your team's point", "נקודה לקבוצה שלכם", false))
        MPText.configure("ar")
        XCTAssertEqual("أُلغيت", MPText.t("Cancelled", "בוטל", false))
        MPText.configure("hi")
        XCTAssertEqual("(✓ – आगे जाएँगे)", MPText.t("(✓ – through)", "(✓ – עלו)", false))
        // Android's own rows are unchanged: a catalog text still shows Android's translation.
        XCTAssertEqual(MPTextCatalog.rows.first { $0.0 == "Final duel" }?.1[2], MPText.t("Final duel", "קרב גמר", false))
        MPText.configure("he")
        XCTAssertEqual("שולחן 2", MPText.t("Table 2", "שולחן 2", true))
    }

    // ---- d376d64: the result card ----

    /// Android MatchResultDialog.readable: the hue darkened 15 % at a time (Float, truncated) until it reads on #808080.
    func testResultLetteringIsDarkenedUntilReadable() {
        XCTAssertEqual(0xff270d19, MPXResultCard.readable(0xffff5ba6))
        XCTAssertEqual(0xff091621, MPXResultCard.readable(MPXResultCard.ink))
        XCTAssertEqual([0xff270a1a, 0xff06172d, 0xff02190b, 0xff211b00], MPXSeatColor.values.map { MPXResultCard.readable($0) })
        for color in [0xffff5ba6, MPXResultCard.ink, 0xffb73578, 0xff2570cd, 0xff22c55e] as [UInt32] {
            XCTAssertGreaterThanOrEqual(MPXResultCard.contrast(MPXResultCard.readable(color), 0xff808080), 4.5)
        }
        // Twelve steps at most: the yellow seat stops just below 4.5, as on Android.
        XCTAssertLessThan(MPXResultCard.contrast(MPXResultCard.readable(0xfffacc15), 0xff808080), 4.5)
        XCTAssertEqual(0xffd8178c, MPXResultCard.blendBlack(0xffff1ca5, 0.15))
        // Each channel × 0.85 (Float, as on Android), truncated: 0x14 → 0x11.
        XCTAssertEqual(0xff111111, MPXResultCard.blendBlack(0xff141414, 0.15))
        XCTAssertEqual([0xff5b450d, 0xff183e62, 0xff104c3b, 0xff632d50], MPXResultCard.accents)
    }
}
