import XCTest
@testable import MinikAmudu

/// Port of Android `core/AmuduEngineTest.kt`.
final class AmuduEngineTests: XCTestCase {
    private func game(_ n: Int = 4, rule: FreezeRule = .freeze) throws -> AmuduEngine {
        let members = (0..<n).map { Member("p\($0)", AmuduCharacters.all[$0 % 11].id, "Player \($0)") }
        return try AmuduEngine(members: members, config: GameConfig(freezeRule: rule, participants: n))
    }

    private func tick(_ e: AmuduEngine, _ seconds: Double) {
        let steps = Int(seconds * 120)
        for _ in 0..<steps { e.tick(1.0 / 120) }
    }

    func testCircleSupportsTenAndUniqueRoster() throws {
        let e = try game(10)
        XCTAssertEqual(10, e.actors.count)
        XCTAssertEqual(10, Set(e.actors.map { $0.position }).count)
        XCTAssertEqual(0.0, (e.actors[0].position - V(8, 8)).length(), accuracy: 0.001)
        for a in e.actors.dropFirst() {
            XCTAssertEqual(4.5, (a.position - V(8, 8)).length(), accuracy: 0.001)
        }
    }

    func testNoMovingBeforeReleaseAndThrowRequiresTarget() throws {
        let e = try game()
        XCTAssertFalse(e.command("p0", "1", .toss(power: 0.5, drift: 0)))
        XCTAssertFalse(e.command("p1", "2", .move(V(1, 0))))
        XCTAssertTrue(e.command("p0", "3", .select(target: "p1")))
        XCTAssertTrue(e.command("p0", "4", .toss(power: 0.5, drift: 0)))
        XCTAssertTrue(e.command("p1", "5", .move(V(1, 0))))
    }

    func testSwipePowerChangesHeightAndAirTimeWithinBounds() throws {
        for s in ArenaScene.allCases {
            let low = try game()
            let high = try AmuduEngine(members: low.members, config: low.config.with(scene: s))
            low.command("p0", "s", .select(target: "p1"))
            high.command("p0", "s", .select(target: "p1"))
            low.command("p0", "t", .toss(power: 0, drift: 0))
            high.command("p0", "t", .toss(power: 1, drift: 0))
            XCTAssertGreaterThan(high.ball.vz, low.ball.vz)
            tick(high, 4.2)
            XCTAssertEqual(.retrieve, high.phase, "\(s)")
        }
    }

    func testCatchNeedsCorrectPersonDistanceTimingAndDescent() throws {
        let e = try game()
        e.command("p0", "s", .select(target: "p1"))
        e.command("p0", "t", .toss(power: 0.5, drift: 0))
        XCTAssertFalse(e.command("p2", "c", .catchBall))
        e.actor("p1")!.position = e.landing
        var guardSteps = 0
        while (e.ball.vz >= 0 || e.ball.height > 1.65) && guardSteps < 10_000 {
            e.tick(1.0 / 120)
            guardSteps += 1
        }
        XCTAssertTrue(e.command("p1", "catch", .catchBall))
        tick(e, 0.05)
        XCTAssertEqual(.resolve, e.phase)
        XCTAssertEqual("p1", e.nextThrower)
    }

    func testMissedCatchRequiresPickupThenShout() throws {
        let e = try game()
        e.command("p0", "s", .select(target: "p1"))
        e.command("p0", "t", .toss(power: 0, drift: 0))
        tick(e, 1.2)
        XCTAssertEqual(.retrieve, e.phase)
        XCTAssertFalse(e.command("p1", "bad", .shout))
        e.actor("p1")!.position = e.ball.position
        XCTAssertTrue(e.command("p1", "pick", .catchBall))
        XCTAssertTrue(e.command("p1", "stop", .shout))
        XCTAssertEqual(.aim, e.phase)
        XCTAssertFalse(e.command("p2", "run", .move(V(1, 0))))
    }

    private func aimed(_ rule: FreezeRule = .freeze) throws -> AmuduEngine {
        let e = try game(rule: rule)
        e.phase = .aim
        e.thrower = "p0"
        e.called = "p0"
        e.actor("p0")!.position = V(4, 8)
        e.actor("p1")!.position = V(6, 8)
        e.actor("p2")!.position = V(14, 14)
        e.actor("p3")!.position = V(14, 2)
        e.ball.holder = "p0"
        e.actor("p0")!.direction = V(1, 0)
        return e
    }

    func testTagAwardsOnePenaltyOnly() throws {
        let e = try aimed()
        e.command("p0", "t", .throwBall(power: 0.5))
        tick(e, 0.3)
        XCTAssertEqual(1, e.actor("p1")!.penalties)
        tick(e, 0.5)
        XCTAssertEqual(1, e.actor("p1")!.penalties)
    }

    func testCaughtReturnPenalizesThrower() throws {
        let e = try aimed()
        e.command("p0", "t", .throwBall(power: 0.5))
        e.command("p1", "c", .catchBall)
        tick(e, 0.3)
        XCTAssertEqual(1, e.actor("p0")!.penalties)
        XCTAssertEqual(0, e.actor("p1")!.penalties)
    }

    func testDuckActuallyChangesCollision() throws {
        let e = try aimed()
        e.command("p1", "d", .duck)
        e.command("p0", "t", .throwBall(power: 0.5))
        tick(e, 0.3)
        XCTAssertEqual(0, e.actor("p1")!.penalties)
        XCTAssertEqual(.flight, e.phase)
    }

    func testHonorMovementOnlyOnePenaltyPerFreeze() throws {
        let e = try aimed(.honor)
        for i in 0..<5 { e.command("p2", "m\(i)", .move(V(1, 0))) }
        XCTAssertEqual(1, e.actor("p2")!.penalties)
        tick(e, 0.1)
        // Android (2026-10): the honor penalty ends the throw at once, so nobody keeps running.
        XCTAssertEqual(.resolve, e.phase)
        XCTAssertEqual(14.0, e.actor("p2")!.position.x, accuracy: 0.0001)
    }

    func testDuplicateThrowAndInvalidNumbersRejected() throws {
        let e = try aimed()
        XCTAssertFalse(e.command("p0", "bad", .throwBall(power: Double.nan)))
        XCTAssertTrue(e.command("p0", "t", .throwBall(power: 0.5)))
        XCTAssertFalse(e.command("p0", "t", .throwBall(power: 0.5)))
        XCTAssertEqual(1, e.events.filter { $0.kind == "throw" }.count)
    }

    func testThirdPenaltyHuddleExcludesTargetAndRemembersName() throws {
        let e = try aimed()
        e.actor("p1")!.penalties = 2
        e.command("p0", "t", .throwBall(power: 0.5))
        // A penalty keeps the players & scores view for five seconds before the huddle.
        tick(e, 5.7)
        XCTAssertEqual(.huddle, e.phase)
        XCTAssertFalse(e.propose("p1", "frog"))
        XCTAssertTrue(e.propose("p0", "frog"))
        XCTAssertFalse(e.vote("p1", "p0"))
        XCTAssertTrue(e.vote("p2", "p0"))
        XCTAssertTrue(e.applyHuddle("frog"))
        tick(e, 2.3)
        XCTAssertEqual(["frog"], e.actor("p1")!.suffixes)
        e.circle("p0")
        XCTAssertFalse(e.command("p0", "s1", .select(target: "p1")))
        XCTAssertEqual(1, e.actor("p0")!.penalties)
        tick(e, 5.4)
        XCTAssertTrue(e.command("p0", "s2", .select(target: "p1", typedName: "frog")))
    }

    func testFiniteMatchHasStableOutcomeAndNoElimination() throws {
        let e = try game(10)
        e.finish()
        XCTAssertEqual(10, e.result!.winners.count)
        XCTAssertFalse(e.command("p0", "m", .move(V(1, 0))))
        XCTAssertEqual(10, e.actors.count)
    }

    func testReviewedSuggestionsAreAcceptedBothLanguages() {
        for i in 0..<6 {
            XCTAssertTrue(Words.validSuggestion(Words.suggestion(i, hebrew: false)))
            XCTAssertTrue(Words.validSuggestion(Words.suggestion(i, hebrew: true)))
        }
        XCTAssertFalse(Words.validSuggestion("an unreviewed insult"))
        XCTAssertFalse(Words.validName("https://example.com"))
    }

    func testSixAndTenHousePlayersCompleteEveryScene() throws {
        for scene in ArenaScene.allCases {
            for n in [6, 10] {
                let members = (0..<n).map { Member("p\($0)", AmuduCharacters.all[$0 % 11].id, "Player \($0)", bot: true) }
                let e = try AmuduEngine(members: members, config: GameConfig(scene: scene, participants: n, turns: 6, huddleSeconds: 2.0), seed: 42)
                for _ in 0..<(120 * 250) where e.result == nil { e.tick(1.0 / 120) }
                XCTAssertNotNil(e.result, "\(scene) n=\(n) stuck in \(e.phase)")
            }
        }
    }

    func testHouseNamesFollowPhoneLanguageButHumansKeepTypedName() throws {
        let members = [Member("p0", "miniko", "Robin"), Member("p1", "kyra", "Kyra", bot: true)]
        let e = try AmuduEngine(members: members, config: GameConfig(participants: 2))
        let target = e.actor("p1")!
        target.suffixes.append("banana")
        XCTAssertEqual("ספיר", members[1].displayName(hebrew: true))
        XCTAssertEqual("Robin", members[0].displayName(hebrew: true))
        XCTAssertTrue(e.command("p0", "he", .select(target: "p1", typedName: "banana")))
        XCTAssertTrue(e.command("p0", "en", .select(target: "p1", typedName: "banana")))
        XCTAssertFalse(e.command("p0", "wrong", .select(target: "p1", typedName: "Kyra")))
    }

    func testRetrieverCannotMoveEvenInHonorRule() throws {
        let e = try aimed(.honor)
        for i in 0..<4 { XCTAssertFalse(e.command("p0", "run\(i)", .move(V(0, 1)))) }
        XCTAssertEqual(0, e.actor("p0")!.penalties)
        tick(e, 0.1)
        XCTAssertEqual(8.0, e.actor("p0")!.position.y, accuracy: 0.001)
    }
}
