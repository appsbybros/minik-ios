import XCTest
import UIKit
@testable import MinikAmudu

/// Logic checks from Android's instrumentation tests (DeviceInteractionTest, IdentityDeviceTest, RefinementDeviceTest)
/// that do not need synthetic touches: art poses, facing, arena texts, localized names and assets.
final class DeviceEquivalentTests: XCTestCase {
    private static let art = ArtStore()

    private func tenPlayers() throws -> AmuduEngine {
        let members = (0..<10).map { Member("p\($0)", AmuduCharacters.all[$0 % 11].id, "Player \($0)") }
        return try AmuduEngine(members: members, config: GameConfig(participants: 10), seed: 41)
    }

    @MainActor func testHeldCatchShowsTheReachPoseAndExpires() throws {
        let e = try tenPlayers()
        e.phase = .air
        e.called = "p0"
        e.ball = Ball(V(1, 1), 25, V.zero, 0)
        XCTAssertTrue(e.command("p0", "hold", .catchBall))
        XCTAssertEqual(6, DeviceEquivalentTests.art.frame(e.actor("p0")!, e))
        XCTAssertFalse(e.command("p0", "move", .move(V(1, 0))))
        for _ in 0..<100 { e.tick(1.0 / 120) }
        XCTAssertLessThan(e.actor("p0")!.catchUntil, e.time)
        XCTAssertEqual(1, e.events.filter { $0.kind == "catch_attempt" }.count)
    }

    @MainActor func testUpwardMotionUsesBackFramesAndStopsAtCourtEdge() throws {
        let e = try tenPlayers()
        e.phase = .shout
        e.called = "p1"
        e.thrower = "p1"
        e.ball.holder = "p1"
        e.actor("p0")!.position = V(8, 7)
        XCTAssertTrue(e.command("p0", "up", .move(V(0, -1))))
        for _ in 0..<20 { e.tick(1.0 / 120) }
        XCTAssertEqual("back", DeviceEquivalentTests.art.visual(e.actor("p0")!, e).facing)
        XCTAssertTrue(e.actor("p0")!.actuallyMoving)
        e.actor("p0")!.position = V(8, 0.6)
        e.command("p0", "edge", .move(V(0, -1)))
        for _ in 0..<12 { e.tick(1.0 / 120) }
        XCTAssertFalse(e.actor("p0")!.actuallyMoving)
    }

    @MainActor func testSideArtIsMirroredForLeftMovement() throws {
        let e = try tenPlayers()
        let a = e.actor("p0")!
        a.facing = V(-1, 0)
        let visual = DeviceEquivalentTests.art.visual(a, e)
        XCTAssertEqual("left", visual.facing)
        XCTAssertTrue(visual.mirrored)
        a.facing = V(1, 0.2)
        XCTAssertFalse(DeviceEquivalentTests.art.visual(a, e).mirrored)
    }

    @MainActor func testNicknameTargetGetsOnlyANeutralPause() throws {
        let before = AppText.language
        defer { AppText.configure(before) }
        AppText.configure("en")
        let e = try tenPlayers()
        let view = ArenaView(engine: e, ownId: "p0", art: DeviceEquivalentTests.art, hebrew: false)
        e.phase = .huddle
        e.huddleTarget = "p0"
        e.huddleDeadline = e.time + 30
        let instruction = view.instruction()
        XCTAssertTrue(instruction.contains("Take a break"))
        XCTAssertFalse(instruction.contains("name") || instruction.contains("word"))
        e.huddleTarget = "p1"
        XCTAssertTrue(view.instruction().contains("funny word"))
    }

    @MainActor func testHebrewFeedbackNamesTheOtherPlayer() throws {
        let before = AppText.language
        defer { AppText.configure(before) }
        AppText.configure("he")
        let members = (0..<6).map { Member("p\($0)", ["miniko", "flare", "gaya", "mia", "kyra", "minik"][$0], "Player \($0)") }
        let e = try AmuduEngine(members: members, config: GameConfig(participants: 6), seed: 17)
        let view = ArenaView(engine: e, ownId: "p0", art: DeviceEquivalentTests.art, hebrew: true)
        e.phase = .resolve
        e.infoActor = "p3"
        e.infoCode = "air_catch"
        e.infoUntil = e.time + 5
        let text = view.feedbackText()
        XCTAssertTrue(text.contains("Player 3"))
        XCTAssertFalse(text.contains("תפסתם"))
        e.infoActor = "p0"
        XCTAssertTrue(view.feedbackText().contains("תפסתם"))
    }

    @MainActor func testArenaCommandsRouteToTheLocalEngine() throws {
        let e = try tenPlayers()
        let view = ArenaView(engine: e, ownId: "p0", art: DeviceEquivalentTests.art, hebrew: false)
        view.command(.select(target: "p4"))
        XCTAssertEqual("p4", e.selected)
        view.command(.toss(power: 1, drift: 0))
        XCTAssertEqual(.air, e.phase)
        XCTAssertEqual("p4", e.called)
        XCTAssertGreaterThan(e.ball.vz, 5)
        XCTAssertNil(e.ball.holder)
    }

    func testEveryCharacterBallAndArenaHasArt() {
        let art = DeviceEquivalentTests.art
        for kind in BallKind.allCases { XCTAssertGreaterThan(art.ball(kind).size.width, 0, kind.rawValue) }
        for scene in ArenaScene.allCases { XCTAssertGreaterThan(art.scene(scene).size.width, 0, scene.rawValue) }
        for c in AmuduCharacters.all {
            XCTAssertEqual(256, art.portrait(c.id).size.width, c.id)
            XCTAssertEqual(16, art.frames[c.id]?.count, c.id)
            XCTAssertEqual(16, art.directionalFrames[c.id]?.count, c.id)
        }
    }

    /// Android `res/values*/app_name.xml` (the launcher names, "Minik" + the game's local name).
    func testLocalizedDisplayNamesMatchAndroidAppNames() throws {
        let names = ["en": "Minik Spud", "he": "מיניק עמודו", "es": "Minik Pies Quietos!", "ar": "مينيك لعبة أسماء", "hi": "Minik Naam Aur Ball",
                     "nl": "Minik Stand in de mand"]
        for lang in ["en", "he", "es", "ar", "hi", "nl"] {
            let path = try XCTUnwrap(Bundle.main.path(forResource: lang, ofType: "lproj"), lang)
            let bundle = try XCTUnwrap(Bundle(path: path), lang)
            XCTAssertEqual(names[lang], bundle.localizedString(forKey: "CFBundleDisplayName", value: nil, table: "InfoPlist"), lang)
        }
    }

    @MainActor func testAudioFilesAreBundled() {
        for file in GameAudio.files.values {
            let parts = file.split(separator: ".").map(String.init)
            XCTAssertNotNil(Bundle.main.url(forResource: parts[0], withExtension: parts[1]), file)
        }
    }
}
