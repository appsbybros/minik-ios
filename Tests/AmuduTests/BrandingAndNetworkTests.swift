import XCTest
@testable import MinikAmudu

/// Port of Android `BrandingBallTest.kt`.
final class BrandingBallTests: XCTestCase {
    func testLanguageNamesAndCallsAreSeparateAndExact() {
        let expected: [(String, String, String)] = [("en", "Spud", "Stop!"), ("he", "עמודו", "עמודו!"), ("es", "Pies Quietos!", "¡Pies quietos!"),
                                                    ("ar", "لعبة أسماء", "ستوب!"), ("hi", "Naam Aur Ball", "STOP!"), ("nl", "Stand in de mand", "Stop!")]
        for (lang, title, call) in expected {
            XCTAssertEqual(title, GameText.title(lang))
            XCTAssertEqual(call, GameText.stopCall(lang))
        }
        XCTAssertEqual("עמודו", GameText.title("iw"))
        XCTAssertEqual("Spud", GameText.title("fr"))
    }

    func testAllStopInstructionsUseLocalCallAndNeverLegacyBrand() {
        let before = AppText.language
        defer { AppText.configure(before) }
        for lang in ["en", "es", "ar", "hi", "nl"] {
            AppText.configure(lang)
            for key in GameText.overriddenKeys() {
                let text = GameText.t(key)
                XCTAssertNil(text.range(of: "amud[uo]|amod[uo]|עמודו", options: [.regularExpression, .caseInsensitive]), "\(lang) / \(key)")
                if key.contains("SPUD") { XCTAssertFalse(text.contains("SPUD"), "\(lang) / \(key)") }
            }
            // A player's chosen name is never rewritten by branding localization.
            XCTAssertTrue(GameText.t("SPUD caught the ball! Their turn to call.").contains("SPUD"))
        }
    }

    private func world(_ kind: BallKind = .foam) throws -> AmuduEngine {
        let members = (0...5).map { Member("p\($0)", AmuduCharacters.all[$0].id, "Player \($0)", bot: true) }
        return try AmuduEngine(members: members, config: GameConfig(ball: kind, participants: 6, turns: 3), seed: 81)
    }

    func testOldAndNewBallSelectionsRoundTripWithoutChangingSavedIdentity() throws {
        for kind in BallKind.allCases {
            let e = try world(kind)
            let restored = try AmuduCodec.create(AmuduCodec.checkpoint(e))
            XCTAssertEqual(e.id, restored.id)
            XCTAssertEqual(kind, restored.config.ball)
            XCTAssertEqual(e.members, restored.members)
        }
        XCTAssertEqual(["FOAM", "BEACH", "NEON"], BallKind.allCases.prefix(3).map { $0.rawValue })
    }

    func testTennisBallHasDistinctPlayableTuning() {
        let b = BallKind.tennis
        XCTAssertTrue(b.speed > BallKind.foam.speed && b.speed < BallKind.neon.speed)
        XCTAssertTrue(b.restitution > BallKind.foam.restitution && b.restitution < 1)
        XCTAssertTrue(b.catchRadius >= 0.5 && b.catchRadius <= 0.8)
        XCTAssertTrue(b.visualScale >= 0.65 && b.visualScale <= 0.85)
    }

    func testTennisWorksAcrossArenasAndThrowModes() throws {
        for scene in ArenaScene.allCases {
            for mode in ThrowMode.allCases {
                let members = (0...5).map { Member("p\($0)", AmuduCharacters.all[$0].id, "Player \($0)", bot: true) }
                let config = try GameConfig(scene: scene, ball: .tennis, participants: 6, turns: 3, throwMode: mode)
                let e = try AmuduEngine(members: members, config: config, seed: 31)
                for _ in 0..<15000 where e.result == nil { e.tick(0.02) }
                XCTAssertNotNil(e.result, "\(scene) / \(mode)")
                XCTAssertTrue(e.ball.position.finite())
                XCTAssertTrue(e.ball.height.isFinite)
            }
        }
    }

    func testStopRemainsOneSharedEventRegardlessOfClientLanguage() throws {
        let e = try world(.tennis)
        e.phase = .shout
        e.called = "p0"
        e.ball.holder = "p0"
        XCTAssertTrue(e.command("p0", "once", .shout))
        XCTAssertFalse(e.command("p0", "once", .shout))
        XCTAssertEqual(1, e.events.filter { $0.kind == "freeze" }.count)
        XCTAssertEqual(.aim, e.phase)
    }
}

/// Port of Android `NetworkStateTest.kt`.
final class NetworkStateTests: XCTestCase {
    private func world() throws -> AmuduEngine {
        let members = (0...5).map { Member("p\($0)", AmuduCharacters.all[$0].id, "Player \($0)", bot: $0 > 1) }
        return try AmuduEngine(members: members, config: GameConfig(participants: 6), seed: 31)
    }

    func testCheckpointRestoresOutstandingBallAndDedupe() throws {
        let e = try world()
        e.command("p0", "choose", .select(target: "p1"))
        e.command("p0", "toss", .toss(power: 0.8, drift: 0.3))
        for _ in 0..<30 { e.tick(1.0 / 120) }
        let restored = try AmuduCodec.create(AmuduCodec.checkpoint(e))
        XCTAssertEqual(e.phase, restored.phase)
        XCTAssertEqual(e.ball.flightId, restored.ball.flightId)
        XCTAssertEqual(e.ball.position, restored.ball.position)
        XCTAssertEqual(e.landing, restored.landing)
        XCTAssertFalse(restored.command("p0", "toss", .toss(power: 0.8, drift: 0.3)))
    }

    func testPublicSnapshotExcludesPrivateSuggestionsAndVotes() throws {
        let e = try world()
        e.phase = .huddle
        e.huddleTarget = "p0"
        e.propose("p1", "frog")
        e.vote("p2", "p1")
        let n = AmuduCodec.shared(e)
        XCTAssertNil(n["suggestions"])
        XCTAssertNil(n["votes"])
        XCTAssertFalse(AmuduCodec.describe(n).contains("frog"))
        XCTAssertEqual("frog", AmuduCodec.node(AmuduCodec.checkpoint(e)["suggestions"])["p1"] as? String)
    }

    func testCommandRoundTripAndResultStable() throws {
        let commands: [GameCommand] = [.move(V(0.6, 0.8)), .aim(V(-1, 0)), .select(target: "p1", typedName: "Player 1 frog"), .toss(power: 0.9, drift: -0.2),
                                       .catchBall, .duck, .shout, .throwBall(power: 0.8), .say(index: 2), .end]
        for c in commands { XCTAssertEqual(c, AmuduCodec.readCommand(AmuduCodec.command(c))) }
        let e = try world()
        e.actor("p0")!.penalties = 2
        e.finish()
        let n = try AmuduCodec.create(AmuduCodec.checkpoint(e))
        XCTAssertEqual(e.result, n.result)
        XCTAssertEqual(.finished, n.phase)
    }

    func testDistantTargetAimIsNormalizedForNetworkRules() {
        let wire = AmuduCodec.command(.aim(V(9, -12)))
        guard case .aim(let direction)? = AmuduCodec.readCommand(wire) else {
            XCTFail("not an aim command")
            return
        }
        XCTAssertEqual(0.6, direction.x, accuracy: 0.0001)
        XCTAssertEqual(-0.8, direction.y, accuracy: 0.0001)
    }
}

/// Port of Android `localization/LanguageTest.kt`.
final class LanguageTests: XCTestCase {
    private var saved = "en"

    override func setUp() {
        super.setUp()
        saved = AppText.language
    }

    override func tearDown() {
        AppText.configure(saved)
        super.tearDown()
    }

    func testDeviceTagsMapToSupportedLanguages() {
        XCTAssertEqual("es", AppText.normalize("es-MX"))
        XCTAssertEqual("hi", AppText.normalize("hi-IN"))
        XCTAssertEqual("nl", AppText.normalize("nl-NL"))
        XCTAssertEqual("ar", AppText.normalize("ar-SA"))
        XCTAssertEqual("he", AppText.normalize("iw"))
        XCTAssertEqual("en", AppText.normalize("fr"))
    }

    func testAllFourLanguagesHaveCompleteCatalogColumns() {
        // Android's effective AppText.rows size at 372c448 (audit-amudu.py checks the rows themselves).
        XCTAssertEqual(1142, AppText.keys().count)
        for lang in ["es", "ar", "hi", "nl"] {
            for key in AppText.keys() {
                let value = AppText.translated(key, lang) ?? ""
                XCTAssertFalse(Kotlin.isBlank(value), "\(lang) \(key)")
            }
        }
    }

    func testRtlAndExistingHebrewArePreserved() {
        AppText.configure("ar")
        XCTAssertTrue(AppText.rtl)
        XCTAssertEqual("رجوع", AppText.t("Back", "חזרה", hebrew: false))
        XCTAssertEqual("חזרה", AppText.t("Back", "חזרה", hebrew: true))
        AppText.configure("nl")
        XCTAssertFalse(AppText.rtl)
    }

    func testPlaceholdersPreservePrivateNamesAndNumbers() {
        AppText.configure("es")
        XCTAssertEqual("Quedan 7 segundos", AppText.t("7 seconds left"))
        let actual = AppText.t("Mia caught the ball! Their turn to call.")
        XCTAssertTrue(actual.contains("Mia"))
        XCTAssertFalse(actual.contains("caught"))
        XCTAssertEqual("A name not in the catalog", AppText.t("A name not in the catalog"))
    }
}
