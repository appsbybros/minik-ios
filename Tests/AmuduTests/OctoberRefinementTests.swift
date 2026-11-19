import XCTest
@testable import MinikAmudu

/// Port of Android `core/OctoberRefinementTest.kt`.
final class OctoberRefinementTests: XCTestCase {
    private func world() throws -> AmuduEngine {
        let members = [Member("me", "miniko", "Alex"), Member("b", "gaya", "Gaya", bot: true), Member("c", "flare", "Flare", bot: true)]
        return try AmuduEngine(members: members, config: GameConfig(participants: 3, huddleSeconds: 2.0), seed: 11)
    }

    func testUnicodeSingleWordNamesAreAcceptedWithoutAWhitelist() {
        for word in ["Mooncake", "צפרדע", "Rápido", "نجمة", "खुशी", "Sterretje"] {
            XCTAssertTrue(Words.validSuggestion(word), word)
            XCTAssertTrue(Words.validName(word), word)
        }
        for word in ["two words", "https://x", "<tag>", "", "123", "a\nb"] {
            XCTAssertFalse(Words.validSuggestion(word), word)
        }
    }

    func testSoloHumanCanChangeTheirAutomaticallyCastVote() throws {
        let e = try world()
        e.phase = .huddle
        e.huddleTarget = "b"
        e.huddleDeadline = 2.0
        XCTAssertTrue(e.propose("me", "Mooncake"))
        XCTAssertTrue(e.propose("c", "frog"))
        e.vote("me", "c")
        e.vote("c", "c")
        for _ in 0..<60 { e.tick(1.0 / 120) }
        XCTAssertEqual(.huddle, e.phase)
        for _ in 0..<220 { e.tick(1.0 / 120) }
        XCTAssertEqual("frog", e.actor("b")!.fullName())
    }

    func testWrongNicknamePenalizedExactlyOnce() throws {
        let e = try world()
        e.actor("b")!.suffixes.append("Mooncake")
        XCTAssertFalse(e.command("me", "bad", .select(target: "b", typedName: "frog")))
        XCTAssertEqual(1, e.actor("me")!.penalties)
        XCTAssertFalse(e.command("me", "bad", .select(target: "b", typedName: "frog")))
        XCTAssertEqual(1, e.actor("me")!.penalties)
        XCTAssertEqual("me", e.infoActor)
        XCTAssertEqual("wrong_nickname", e.infoCode)
    }

    func testCalmTossStaysNearCenterEvenIfCalledPlayerIsFarAway() throws {
        let e = try world()
        e.actor("b")!.position = V(15, 15)
        e.command("me", "s", .select(target: "b"))
        e.command("me", "t", .toss(power: 1, drift: 0))
        XCTAssertLessThanOrEqual((e.landing - V(e.config.width / 2, e.config.depth / 2)).length(), 1.246)
    }

    func testProximityRequiresCorrectPhaseReachAndHeight() throws {
        let e = try world()
        e.phase = .retrieve
        e.called = "me"
        e.ball = Ball(e.actor("me")!.position, 0.23, V.zero, 0)
        XCTAssertTrue(e.ballWithinReach("me"))
        XCTAssertFalse(e.ballWithinReach("c"))
        e.ball.height = 5
        XCTAssertFalse(e.ballWithinReach("me"))
        e.ball.height = 0.23
        e.ball.position = V(0, 0)
        XCTAssertFalse(e.ballWithinReach("me"))
    }

    func testActorFeedbackSurvivesReplicaCheckpoint() throws {
        let e = try world()
        e.infoActor = "b"
        e.infoCode = "air_catch"
        let r = try AmuduCodec.create(AmuduCodec.checkpoint(e))
        XCTAssertEqual("b", r.infoActor)
        XCTAssertEqual("air_catch", r.infoCode)
    }
}
