import XCTest
@testable import MinikSquash

/// Android SportsText/AppText lookups: the sports tables first (journey, volleyball, squash), then
/// the extra rows, then the shared catalog; Hebrew always comes from the call site.
final class SportsTextTests: XCTestCase {
    override func tearDown() {
        AppText.configure("en")
        super.tearDown()
    }

    func testHebrewComesFromTheCallSite() {
        AppText.configure("he")
        XCTAssertEqual(SportsText.t("Settings", "הגדרות", true), "הגדרות")
        XCTAssertTrue(AppText.rtl)
    }

    func testEnglishIsUnchanged() {
        AppText.configure("en")
        XCTAssertEqual(SportsText.t("Public tournaments", "טורנירים פתוחים", false), "Public tournaments")
        XCTAssertFalse(AppText.rtl)
    }

    func testSportsTablesTakePrecedence() {
        AppText.configure("es")
        XCTAssertEqual(SportsText.t("Public tournaments", "טורנירים פתוחים", false), "Torneos públicos")
        XCTAssertEqual(SportsText.t("Your first target", "המטרה הראשונה", false), "Tu primer objetivo")
        XCTAssertEqual(SportsText.t("Learning", "למידה", false), "Aprendizaje")
        XCTAssertEqual(SportsText.t("White", "לבן", false), "Blanco")
        // A volleyball tip matches by its prefix.
        XCTAssertEqual(SportsText.volley("Automatic toss: tap your target when the ball is above your shoulder. One retry."),
                       "La pelota se lanza sola: toca tu objetivo cuando esté sobre el hombro. Un reintento.")
        AppText.configure("ar")
        XCTAssertTrue(AppText.rtl)
        XCTAssertNotEqual(SportsText.t("Public tournaments", "טורנירים פתוחים", false), "Public tournaments")
    }

    func testEveryStageTitleIsTranslated() {
        for language in ["es", "ar", "hi", "nl"] {
            AppText.configure(language)
            for sport in Sport.allCases {
                for stage in SportsJourney.stages(sport) {
                    XCTAssertNotEqual(SportsText.t(stage.en, stage.he, false), stage.en, "\(language) \(stage.id)")
                    let brief = stage.brief(sport, false)
                    XCTAssertNotEqual(SportsText.t(brief, stage.brief(sport, true), false), brief, "\(language) \(stage.id) brief")
                }
            }
        }
    }

    func testFeedbackPrefixes() {
        AppText.configure("en")
        XCTAssertEqual(SportsText.feedback("Correct! 2 + 3 = 5", "נכון! 2 + 3 = 5", false), "Correct! \u{200E}2 + 3 = 5\u{200E}")
        XCTAssertEqual(SportsText.feedback("Correct answer: 7", "התשובה הנכונה: 7", true), "התשובה הנכונה: \u{200E}7\u{200E}")
        AppText.configure("nl")
        XCTAssertEqual(SportsText.feedback("Correct answer: 7", "התשובה הנכונה: 7", false), "Juiste antwoord: \u{200E}7\u{200E}")
    }

    func testParentGateExpressionIsIsolated() {
        XCTAssertEqual(ParentGate.isolate("For a grown-up: 8 × 7 = ?"), "For a grown-up: \u{2066}8 × 7 = ?\u{2069}")
        XCTAssertEqual(ParentGate.isolate("لشخص بالغ: 8 × 7 = ؟"), "لشخص بالغ: \u{2066}8 × 7 = ؟\u{2069}")
    }
}
