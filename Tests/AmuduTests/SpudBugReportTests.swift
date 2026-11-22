import XCTest
@testable import MinikAmudu

/// The Spud iOS bug report of 22 November 2026 (14 sections): every fix that a test can pin.
final class SpudBugReportTests: XCTestCase {
    private func repoRoot(file: StaticString = #filePath) -> URL {
        return URL(fileURLWithPath: "\(file)").deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
    }

    private let languages = ["en", "he", "es", "ar", "hi", "nl"]

    // MARK: 3.5 The arena (park, grass, sky) was missing in every game

    func testTheWorldArtIsInTheSpudAppItself() throws {
        // ArenaWorldView draws nothing (plain navy) unless all five load; they were only in the Splash target.
        let catalog = repoRoot().appendingPathComponent("Amudu/Assets.xcassets")
        for name in ["park_sky", "beach_sky", "andromeda_sky", "grass", "sand", "minik_close"] {
            let set = catalog.appendingPathComponent(name + ".imageset")
            let contents = try Data(contentsOf: set.appendingPathComponent("Contents.json"))
            let json = try XCTUnwrap(JSONSerialization.jsonObject(with: contents) as? [String: Any])
            let images = try XCTUnwrap(json["images"] as? [[String: Any]])
            let files = images.compactMap { $0["filename"] as? String }
            XCTAssertFalse(files.isEmpty, name)
            for file in files {
                XCTAssertTrue(FileManager.default.fileExists(atPath: set.appendingPathComponent(file).path), name + "/" + file)
            }
        }
        // Inside the app (hosted tests) the images load by name.
        if Bundle.main.bundleIdentifier == "com.appsbybros.minik.spud" {
            for name in ["park_sky", "beach_sky", "andromeda_sky", "grass", "sand", "minik_close"] {
                XCTAssertNotNil(UIImage(named: name), name)
            }
        }
    }

    // MARK: 2.2 The store message names the real problem

    func testOnlyAnOfflineDeviceIsToldToCheckTheConnection() {
        XCTAssertNil(SpudStore.problemAfterLoad(answered: true, hasProduct: true, offline: false))
        XCTAssertEqual(SpudStore.problemAfterLoad(answered: true, hasProduct: false, offline: false), .productUnavailable)
        XCTAssertEqual(SpudStore.problemAfterLoad(answered: true, hasProduct: false, offline: true), .productUnavailable,
                       "an answer without the product is never a connection problem")
        XCTAssertEqual(SpudStore.problemAfterLoad(answered: false, hasProduct: false, offline: false), .notAnswering)
        XCTAssertEqual(SpudStore.problemAfterLoad(answered: false, hasProduct: false, offline: true), .offline)
        XCTAssertEqual(SpudStore.problemAfterPurchaseError(productNotFound: true, canMakePayments: true, offline: false), .productUnavailable)
        XCTAssertEqual(SpudStore.problemAfterPurchaseError(productNotFound: false, canMakePayments: false, offline: false), .purchasesNotAllowed)
        XCTAssertEqual(SpudStore.problemAfterPurchaseError(productNotFound: false, canMakePayments: true, offline: true), .offline)
        XCTAssertEqual(SpudStore.problemAfterPurchaseError(productNotFound: false, canMakePayments: true, offline: false), .notAnswering)
    }

    func testStoreTextsSayWhatHappenedAndTheButtonDoesNotPromiseAPrice() {
        for language in languages {
            let offline = StoreText.problem(.offline, language: language)
            for other in [SpudStoreProblem.notAnswering, .productUnavailable, .purchasesNotAllowed] {
                XCTAssertNotEqual(StoreText.problem(other, language: language), offline, language)
            }
        }
        XCTAssertEqual(StoreText.get(.reload, language: "en"), "Try again")
        XCTAssertFalse(StoreText.get(.reload, language: "en").lowercased().contains("price"))
        XCTAssertFalse(StoreText.problem(.productUnavailable, language: "en").lowercased().contains("connection"))
        XCTAssertTrue(StoreText.problem(.offline, language: "en").lowercased().contains("internet"))
    }

    // MARK: 10.2 Numbers come from the rules, not typed into texts

    func testStoreNumbersComeFromTheRules() {
        for language in languages {
            for key in StoreText.Key.allCases where key != .buy {
                XCTAssertFalse(StoreText.get(key, language: language).contains("{0}"), key.rawValue + " " + language)
            }
            XCTAssertTrue(StoreText.get(.featurePlayers, language: language).contains(String(SpudAccess.fullPlayers)), language)
            XCTAssertTrue(StoreText.get(.challengeLocked, language: language).contains(String(SpudAccess.freeChallenges)), language)
            XCTAssertTrue(StoreText.get(.roomFull, language: language).contains(String(SpudAccess.freePlayers)), language)
        }
        // The unlock screen lists the new locks.
        XCTAssertTrue(StoreText.get(.featureBalls, language: "en").contains("Beach ball"))
        for name in ["Flare", "Kyra", "Gaya", "Mia"] {
            XCTAssertTrue(StoreText.get(.featureCharacters, language: "en").contains(name), name)
        }
    }

    func testNoTextPromisesTheCatchWindowsLength() {
        XCTAssertEqual(CatchPhysics.HUMAN_WINDOW, 0.5, "if this changes, no text needs to change: none states it")
        var texts = LearningCopy.ordered.flatMap { $0.1 }
        texts += SpudIOSText.copy.values.flatMap { $0 }
        texts += [SpudJourney.stage(0).brief(false), SpudJourney.stage(0).brief(true)]
        for text in texts {
            for phrase in ["half a second", "חצי שנייה", "medio segundo", "نصف ثانية", "आधा सेकंड", "halve seconde"] {
                XCTAssertFalse(text.contains(phrase), text)
            }
        }
    }

    // MARK: 14 Rules in plain words

    func testRulesTextsExplainWithoutFormulas() {
        let previous = AppText.language
        defer { AppText.configure(previous) }
        for language in languages {
            AppText.configure(language)
            let burst = LearningCopy.get("burst_rule")
            XCTAssertNil(burst.rangeOfCharacter(from: CharacterSet(charactersIn: "0123456789%")), language + ": " + burst)
            XCTAssertNil(RuleText["timerHint"].rangeOfCharacter(from: .decimalDigits), language)
            XCTAssertNil(RuleText["idleHelp"].rangeOfCharacter(from: .decimalDigits), language)
        }
        AppText.configure("en")
        XCTAssertEqual(RuleText["steps"], "Steps after Stop!")
        XCTAssertNotEqual(LearningCopy.get("conditions"), "Practice conditions")
    }

    func testEveryNewTextIsInTheSixLanguages() {
        XCTAssertEqual(SpudIOSText.languages, languages)
        for (en, values) in SpudIOSText.copy {
            XCTAssertEqual(values.count, 6, en)
            XCTAssertEqual(values[0], en)
            XCTAssertFalse(values.contains { $0.isEmpty }, en)
            for i in 1..<6 { XCTAssertNotEqual(values[i], en, en + " " + languages[i]) }
        }
        let previous = AppText.language
        defer { AppText.configure(previous) }
        for (i, language) in languages.enumerated() where language != "he" {
            AppText.configure(language)
            XCTAssertEqual(GameText.t(SpudIOSText.stepsExplained), SpudIOSText.copy[SpudIOSText.stepsExplained]?[i], language)
        }
    }

    // MARK: 3.1, 6.1 Ball sizes (drawing only)

    func testBeachBallAndBalloonAreDrawnLargerWithoutChangingThePhysics() {
        XCTAssertEqual(BallKind.beach.drawScale, 1.4)
        XCTAssertEqual(BallKind.paint.drawScale, 1.5)
        for kind in [BallKind.foam, .neon, .tennis] { XCTAssertEqual(kind.drawScale, 1.0) }
        XCTAssertEqual(BallKind.beach.visualScale, 1.0, "the contact size stays as before")
    }

    // MARK: 4.3 Name tags beside their own player

    func testATagSitsBesideItsPlayerAndNeverOverAnother() {
        let labels = StableLabels()
        let bounds = LabelBox(x: 0, y: 0, w: 400, h: 600)
        let body = LabelBox(x: 100, y: 200, w: 40, h: 80)
        // Free: under the feet, centred.
        let free = labels.placeNear("a", body: body, 60, 22, bounds, [], [])
        XCTAssertEqual(free.y, body.bottom + 3)
        XCTAssertEqual(free.cx, body.cx)
        // Another player right under the feet: the tag moves to another side of its own player, not onto the other.
        let other = LabelBox(x: 80, y: 280, w: 80, h: 80)
        let moved = StableLabels().placeNear("a", body: body, 60, 22, bounds, [other], [])
        XCTAssertFalse(moved.overlaps(other))
        XCTAssertFalse(moved.overlaps(body))
        let gap = max(body.x - moved.right, moved.x - body.right, body.y - moved.bottom, moved.y - body.bottom)
        XCTAssertLessThanOrEqual(gap, 20, "the tag stays next to its player")
        // A player off the screen: the tag stays on screen at the edge.
        let away = LabelBox(x: 500, y: 700, w: 40, h: 80)
        let pinned = StableLabels().placeNear("a", body: away, 60, 22, bounds, [], [])
        XCTAssertLessThanOrEqual(pinned.right, bounds.right)
        XCTAssertLessThanOrEqual(pinned.bottom, bounds.bottom)
    }
}
