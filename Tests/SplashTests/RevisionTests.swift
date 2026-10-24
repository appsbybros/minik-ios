import XCTest
@testable import MinikSplash

/// Port of Android RevisionTest.kt.
final class RevisionTests: XCTestCase {
    private var id = 0

    private func engine(_ s: PlayerSettings = PlayerSettings(), _ other: PlayerSettings = PlayerSettings()) -> SplashEngine {
        return SplashEngine(members: [Member("a", "miniko", settings: s), Member("b", "minik", team: 1, settings: other)], seed: 654)
    }

    @discardableResult
    private func send(_ e: SplashEngine, _ c: Command) -> Bool {
        id += 1
        return e.command("a", "t\(id)", c)
    }

    private func ticks(_ e: SplashEngine, _ seconds: Double) {
        for _ in 0..<Int(seconds / 0.02) { e.tick(0.02) }
    }

    private func hold(_ e: SplashEngine, correct: Bool = true) {
        guard let a = e.actor("a"), let q = a.question,
              let ch = a.choices.first(where: { ($0.text == q.answer) == correct }) else {
            XCTFail("No choice")
            return
        }
        a.position = ch.position
        XCTAssertTrue(send(e, .pickup(questionId: q.id, index: ch.index)))
    }

    func testDefaultsAreEasyMathCourtAndOnePlace() {
        let s = PlayerSettings()
        XCTAssertEqual(s.walk, .easy)
        XCTAssertEqual(s.throwing, .easy)
        XCTAssertEqual(s.subjects, [.math])
        XCTAssertTrue(s.court)
        XCTAssertEqual(s.balloons, .onePlace)
    }

    func testEasyWalkPicksOnlyTheExplicitSelectedBalloon() {
        let e = engine()
        let a = e.actor("a")!
        let ch = a.choices[0]
        XCTAssertTrue(send(e, .walkTo(ch.position, questionId: a.question!.id, index: ch.index)))
        ticks(e, 3.0)
        XCTAssertEqual(a.held, ch.index)
    }

    func testStandardWalkDoesNotPickUpAndRejectsAutoPickup() {
        var s = PlayerSettings()
        s.walk = .standard
        let e = engine(s)
        let a = e.actor("a")!
        let ch = a.choices[0]
        XCTAssertFalse(send(e, .walkTo(ch.position, questionId: a.question!.id, index: ch.index)))
        XCTAssertNil(a.walkTarget)
        XCTAssertTrue(send(e, .walkTo(ch.position)))
        ticks(e, 3.0)
        XCTAssertNil(a.held)
        XCTAssertTrue(send(e, .pickup(questionId: a.question!.id, index: ch.index)))
    }

    func testDraggingCancelsAutomaticWalk() {
        let e = engine()
        send(e, .walkTo(V(9, 6)))
        send(e, .move(V(-1, 0)))
        XCTAssertNil(e.actor("a")!.walkTarget)
    }

    func testEasyThrowAimsAtOpponentButNeverHomes() {
        let e = engine()
        hold(e)
        e.actor("a")!.position = V(6, 8)
        e.actor("b")!.position = V(6, 3)
        XCTAssertTrue(send(e, .shootAt("b")))
        XCTAssertEqual(e.shots.count, 1)
        let velocity = e.shots[0].velocity
        XCTAssertLessThan(velocity.y, 0)
        e.actor("b")!.position = V(11, 3)
        ticks(e, 0.1)
        XCTAssertEqual(e.shots.first?.velocity, velocity)
    }

    func testStandardRejectsAutomaticThrow() {
        var s = PlayerSettings()
        s.throwing = .standard
        let e = engine(s)
        hold(e)
        XCTAssertFalse(send(e, .shootAt("b")))
        XCTAssertNotNil(e.actor("a")!.held)
        XCTAssertTrue(e.shots.isEmpty)
    }

    func testWrongEasyThrowStillPaintsAndGivesCorrectFeedback() {
        let e = engine()
        hold(e, correct: false)
        let old = e.actor("a")!.question!
        XCTAssertTrue(send(e, .shootAt("b")))
        let a = e.actor("a")!
        XCTAssertEqual(a.paint.count, 1)
        XCTAssertEqual(old.answer, a.feedback?.answer)
        XCTAssertFalse(a.answers.last!.correct)
        XCTAssertTrue(e.shots.isEmpty)
        XCTAssertNotEqual(old.id, a.question!.id)
    }

    func testPracticeCannotEndByTimeOrScore() {
        let e = engine()
        e.practice = true
        e.restoreClock(10000)
        e.actor("a")!.score = 100
        for _ in 0..<100 { e.tick(0.1) }
        e.finish()
        XCTAssertNil(e.result)
    }

    func testLowGravityHasHigherLongerJump() {
        let normal = engine()
        var low = PlayerSettings()
        low.arena = .andromeda
        let space = engine(low)
        id += 1
        normal.command("a", "t\(id)", .jump)
        id += 1
        space.command("a", "t\(id)", .jump)
        ticks(normal, 0.75)
        ticks(space, 0.75)
        XCTAssertGreaterThan(space.actor("a")!.height, normal.actor("a")!.height + 0.8)
        ticks(space, 0.4)
        XCTAssertGreaterThan(space.actor("a")!.height, 0)
    }

    func testCourtOffLetsShotsTravelBeyondWall() {
        var open = PlayerSettings()
        open.court = false
        let e = engine(open)
        hold(e)
        e.actor("a")!.position = V(11.7, 6)
        send(e, .aim(V(1, 0)))
        send(e, .throwBalloon)
        ticks(e, 0.15)
        XCTAssertTrue(e.shots.contains { $0.position.x > 12 })
    }

    func testSelectedSubjectsStayPersonal() {
        var s = PlayerSettings()
        s.subjects = [.english, .world]
        let e = engine(s, PlayerSettings())
        let a = e.actor("a")!
        for _ in 0..<30 {
            XCTAssertTrue([Skill.english, Skill.world].contains(a.question!.skill))
            hold(e)
            send(e, .throwBalloon)
        }
        XCTAssertFalse([Skill.english, Skill.world].contains(e.actor("b")!.question!.skill))
    }

    func testAllOverSpreadsFourOptionsAcrossArena() {
        var s = PlayerSettings()
        s.balloons = .allOver
        let e = engine(s)
        let q = e.actor("a")!.choices
        XCTAssertEqual(q.count, 4)
        let xs = q.map { $0.position.x }
        let ys = q.map { $0.position.y }
        XCTAssertGreaterThan(xs.max()! - xs.min()!, 4)
        XCTAssertGreaterThan(ys.max()! - ys.min()!, 3)
    }

    func testBotsUseHarderLayoutIfAnyHumanRequestsIt() {
        var other = PlayerSettings()
        other.balloons = .allOver
        other.arena = .andromeda
        let s = PlayerSettings.bots([PlayerSettings(), other])
        XCTAssertEqual(s.walk, .standard)
        XCTAssertEqual(s.throwing, .standard)
        XCTAssertEqual(s.balloons, .allOver)
        XCTAssertEqual(s.arena, .andromeda)
    }

    func testSettingsAndNavigationSurviveCheckpoint() {
        let s = PlayerSettings(walk: .standard, throwing: .easy, arena: .andromeda, court: false, balloons: .allOver, subjects: [.math, .world])
        let e = engine(s)
        send(e, .walkTo(V(9, 7)))
        let restored = engine()
        WorldCodec.restore(restored, WorldCodec.checkpoint(e))
        // Every battle has a court now: "court" always travels and restores as true.
        var withCourt = s
        withCourt.court = true
        XCTAssertEqual(restored.actor("a")!.settings, withCourt)
        XCTAssertEqual(restored.actor("a")!.walkTarget, V(9, 7))
        XCTAssertEqual(WorldCodec.member("a", WorldCodec.member(e.members[0])).settings, withCourt)
    }

    func testNewCommandsRoundTrip() {
        let c = Command.walkTo(V(2, 3), questionId: "a-q1", index: 2)
        XCTAssertEqual(WorldCodec.command(WorldCodec.command(c)), c)
        XCTAssertEqual(WorldCodec.command(WorldCodec.command(.shootAt("b"))), .shootAt("b"))
        for command in [Command.move(V(0.5, -0.25)), .aim(V(1, 0)), .pickup(questionId: "x", index: 3), .throwBalloon, .jump, .crouch, .hint] {
            XCTAssertEqual(WorldCodec.command(WorldCodec.command(command)), command)
        }
    }

    func testFacingFollowsMovementAndAiming() {
        let e = engine()
        send(e, .move(V(0, -1)))
        XCTAssertEqual(Facing.of(e.actor("a")!.facing), .back)
        send(e, .aim(V(-1, 0)))
        XCTAssertEqual(Facing.of(e.actor("a")!.facing), .left)
        XCTAssertEqual(Facing.of(V(1, 0)), .right)
        XCTAssertEqual(Facing.of(V(0, 1)), .front)
    }
}
