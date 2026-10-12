import XCTest
@testable import MinikSquash

/// The saved-match and room snapshot JSON (Android SportsCodec field names): a snapshot taken mid
/// match restores into an engine with the same state.
final class SportsCodecTests: XCTestCase {
    private func engine(_ sport: Sport, step: Int = -1, human: Bool = false) -> SportsEngine {
        var c = SportsConfig()
        c.sport = sport
        c.seed = 4321
        c.challengeStep = step
        c.control = .standard
        c.serveControl = .standard
        let roster: [Participant] = sport == .squash
            ? [Participant("you", "miniko", 0, !human, "You"), Participant("house-0", "minik", 1, true)]
            : [Participant("you", "miniko", 0, !human, "You"), Participant("teammate-0", "june", 0, true),
               Participant("opponent-0", "minik", 1, true), Participant("opponent-1", "mia", 1, true)]
        return SportsEngine(c, roster, matchId: "codec-\(sport.name)-\(step)")
    }

    private func run(_ e: SportsEngine, _ steps: Int) {
        for _ in 0..<steps { e.update(1.0 / 60) }
    }

    private func roundTrip(_ e: SportsEngine, allowPractice: Bool = true) throws -> SportsEngine {
        let node = try XCTUnwrap(NodeJSON.node(SportsCodec.text(SportsCodec.encode(e))))
        return try SportsCodec.decode(node, allowPractice: allowPractice)
    }

    private func same(_ a: SportsEngine, _ b: SportsEngine) -> Bool {
        guard let x = NodeJSON.node(SportsCodec.text(SportsCodec.encode(a))),
              let y = NodeJSON.node(SportsCodec.text(SportsCodec.encode(b))) else { return false }
        return NSDictionary(dictionary: x).isEqual(to: y)
    }

    func testSnapshotRestoresTheSameMatch() throws {
        for sport in Sport.allCases {
            let original = engine(sport)
            run(original, 900)
            let copy = try roundTrip(original)
            XCTAssertTrue(same(copy, original), sport.name)
            XCTAssertEqual(copy.ball.p, original.ball.p)
            XCTAssertEqual(copy.scores, original.scores)
            XCTAssertEqual(copy.phase, original.phase)
            XCTAssertEqual(copy.players.map { $0.p }, original.players.map { $0.p })
            XCTAssertEqual(copy.events, Array(original.events.suffix(12)))
        }
    }

    func testDrillSnapshotKeepsItsProgress() throws {
        let original = engine(.volley, step: 3, human: true)
        run(original, 600)
        let copy = try roundTrip(original)
        let a = try XCTUnwrap(original.practice)
        let b = try XCTUnwrap(copy.practice)
        XCTAssertEqual(b.successes, a.successes)
        XCTAssertEqual(b.mistakes, a.mistakes)
        XCTAssertEqual(b.attempts, a.attempts)
        XCTAssertEqual(b.painted, a.painted)
        XCTAssertEqual(b.nextAt, a.nextAt)
        // An online room never restores a drill (Android `decode(j, allowPractice = false)`).
        XCTAssertNil(try roundTrip(original, allowPractice: false).practice)
    }

    func testAndroidFieldNamesAndDefaults() throws {
        let j = SportsCodec.encode(engine(.squash))
        for key in ["volley", "answerWindows", "serveWindowStarted", "serveElapsed", "serveRequested", "timeScale", "receptionScale",
                    "receptionReceiver", "receptionStrength", "receptionSlowEnabled", "slowResumeAt", "shotHasQuestion", "shotRecorded", "profiles",
                    "poseStamp", "tutorialStage", "feedbackEn", "feedbackHe", "feedbackUntil", "version", "matchId", "config", "roster", "clock",
                    "phase", "phaseTime", "countdown", "server", "expected", "returnTeam", "winner", "scores", "reason", "sequence", "eventId",
                    "pointSerial", "shotSerial", "question", "shotQuestion", "shotChoice", "ball", "players", "events"] {
            XCTAssertNotNil(j[key], key)
        }
        XCTAssertNil(j["practice"], "a match without a drill has no practice node")
        XCTAssertEqual(j["version"] as? Int, 2)
        // Android `config(j)` defaults: a minimal shared config is a valid squash match.
        let minimal = try SportsCodec.config(["sport": "SQUASH"])
        XCTAssertEqual(minimal.target, 11)
        XCTAssertEqual(minimal.serveControl, .beginner)
        XCTAssertEqual(minimal.teamColors, ["aqua", "gold"])
        XCTAssertEqual(minimal.challengeStep, -1)
        XCTAssertThrowsError(try SportsCodec.config(["sport": "TENNIS"]))
        XCTAssertThrowsError(try SportsCodec.config(["sport": "VOLLEY", "teamSize": 4]))
    }

    func testRoomCodes() {
        XCTAssertTrue(SportsOnline.isRoomCode("ABC234"))
        XCTAssertFalse(SportsOnline.isRoomCode("ABC23"))
        XCTAssertFalse(SportsOnline.isRoomCode("abc234"))
        XCTAssertFalse(SportsOnline.isRoomCode("ABC1O0"))
    }
}
