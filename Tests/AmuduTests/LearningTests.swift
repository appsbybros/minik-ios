import XCTest
@testable import MinikAmudu

/// Port of Android `core/BotCallAndTurnTest.kt`.
final class BotCallAndTurnTests: XCTestCase {
    private func tick(_ e: AmuduEngine, _ seconds: Double) { NovemberSupport.run(e, seconds, hz: 120) }

    private func game(_ rule: RuleSet = .nicknames) throws -> AmuduEngine {
        let members = [Member("p0", "miniko", "First"), Member("p1", "mia", "Catcher"), Member("p2", "flare", "Third")]
        return try AmuduEngine(members: members, config: GameConfig(participants: 3, rules: rule, actionSeconds: 0), seed: 17)
    }

    private func aimed(_ rule: RuleSet) throws -> AmuduEngine {
        let e = try game(rule)
        e.phase = .aim
        e.thrower = "p0"
        e.called = "p0"
        e.frozen = true
        e.actor("p0")!.position = V(4.0, 8.0)
        e.actor("p0")!.direction = V(1.0, 0.0)
        e.actor("p1")!.position = V(6.0, 8.0)
        e.actor("p2")!.position = V(14.0, 14.0)
        e.ball.holder = "p0"
        return e
    }

    private func catchAttack(_ e: AmuduEngine) {
        XCTAssertTrue(e.command("p0", "throw", .throwBall(power: 0.5)))
        XCTAssertTrue(e.command("p1", "catch", .catchBall))
        // Isolate turn ownership from the separately verified catch probabilities.
        e.actor("p1")!.catchRoll = 0.0
        e.actor("p1")!.catchProbability = 1.0
        tick(e, 0.4)
        XCTAssertEqual("tag_catch", e.infoCode)
    }

    func testCaughtAttackReturnsNextCallToPenalizedThrowerInBothModes() throws {
        for rule in RuleSet.allCases {
            let e = try aimed(rule)
            catchAttack(e)
            XCTAssertEqual(1, e.actor("p0")!.penalties)
            XCTAssertEqual(0, e.actor("p1")!.penalties)
            XCTAssertEqual("p1", e.ball.holder)
            XCTAssertEqual("p0", e.nextThrower)
            // Resume during the result pause must retain the same next turn.
            let resumed = try AmuduCodec.create(AmuduCodec.checkpoint(e))
            for world in [e, resumed] {
                tick(world, 5.1)
                XCTAssertEqual(.circle, world.phase)
                XCTAssertEqual("p0", world.thrower)
                XCTAssertEqual("p0", world.ball.holder)
            }
        }
    }

    func testEliminatedThrowerCannotReceiveNextTurn() throws {
        let e = try aimed(.spud)
        e.actor("p0")!.penalties = 3
        catchAttack(e)
        XCTAssertFalse(e.actor("p0")!.active)
        XCTAssertEqual("p1", e.nextThrower)
        tick(e, 5.1)
        XCTAssertEqual(.circle, e.phase)
        XCTAssertEqual("p1", e.thrower)
    }

    func testLastOpponentEliminationFinishesInsteadOfStartingAnotherCall() throws {
        let e = try aimed(.spud)
        e.actor("p0")!.penalties = 3
        e.actor("p2")!.spectator = .letters
        catchAttack(e)
        tick(e, 5.1)
        XCTAssertEqual(.finished, e.phase)
        XCTAssertEqual(["p1"], e.result?.winners)
    }

    func testNicknameHuddleKeepsPenalizedThrowersNextTurn() throws {
        let e = try aimed(.nicknames)
        e.actor("p0")!.penalties = 2
        catchAttack(e)
        tick(e, 5.1)
        XCTAssertEqual(.huddle, e.phase)
        XCTAssertEqual("p0", e.huddleTarget)
        XCTAssertTrue(e.propose("p1", "frog"))
        XCTAssertTrue(e.applyHuddle("frog"))
        tick(e, 5.1)
        XCTAssertEqual("p0", e.thrower)
        XCTAssertEqual("p0", e.ball.holder)
    }

    func testAirCatchStillStartsFromCatchersPositionWithoutRegrouping() throws {
        for rule in RuleSet.allCases {
            let e = try game(rule)
            e.command("p0", "select", .select(target: "p1"))
            e.command("p0", "toss", .toss(power: 0.0, drift: 0.0))
            e.actor("p1")!.position = e.landing
            var guardSteps = 0
            while (e.ball.vz >= 0 || e.ball.height > 1.95) && guardSteps < 10_000 {
                e.tick(1.0 / 120)
                guardSteps += 1
            }
            e.command("p1", "catch", .catchBall)
            e.actor("p1")!.catchRoll = 0.0
            e.actor("p1")!.catchProbability = 1.0
            tick(e, 0.1)
            XCTAssertEqual("air_catch", e.infoCode)
            let position = e.actor("p1")!.position
            tick(e, 2.3)
            XCTAssertEqual("p1", e.thrower)
            XCTAssertEqual(position, e.actor("p1")!.position)
            XCTAssertTrue(e.actors.allSatisfy { $0.penalties == 0 })
        }
    }

    func testMissedAttackReturnsToThrowerEvenWhenCalledFieldIsStale() throws {
        for rule in RuleSet.allCases {
            let e = try aimed(rule)
            e.called = "p2"
            e.actor("p0")!.direction = V(-1.0, 0.0)
            e.command("p0", "throw", .throwBall(power: 0.2))
            tick(e, 1.5)
            XCTAssertEqual("miss", e.infoCode)
            XCTAssertEqual(1, e.actor("p0")!.penalties)
            tick(e, 5.1)
            XCTAssertEqual("p0", e.thrower)
        }
    }

    func testBotTossOutcomesFollowAccuracyAndChooseAmongDistantPlayers() throws {
        // Check the actual engine's calls and trajectories, across independent seeds.
        let characters = ["miniko", "minik", "comet", "flare", "gaya"]
        for (index, character) in characters.enumerated() {
            for far in [false, true] {
                var low = 0
                var high = 0
                var chosen = Set<String>()
                for sample in 0..<1200 {
                    let members = [Member("bot", character, "Bot", bot: true), Member("near", "amber", "Near"), Member("far1", "mia", "Far one"),
                                   Member("far2", "june", "Far two")]
                    let e = try AmuduEngine(members: members,
                                            config: GameConfig(scene: .andromeda, participants: 4, width: 28.0, depth: 18.0, actionSeconds: 0),
                                            seed: Int64(sample))
                    if far {
                        e.actor("far1")!.position = V(1.0, 1.0)
                        e.actor("far2")!.position = V(27.0, 17.0)
                    }
                    e.actor("bot")!.nextThink = 0.0
                    e.tick(1.0 / 120)
                    XCTAssertEqual(.air, e.phase)
                    chosen.insert(e.called)
                    let q = AmuduCharacters.get(character).qualities
                    let reference = try AmuduEngine(members: [Member("a", "minik", "A"), Member("b", "mia", "B")],
                                                    config: GameConfig(scene: .andromeda, participants: 2), seed: 17)
                    reference.command("a", "select", .select(target: "b"))
                    reference.command("a", "toss", .toss(power: 0.45 + 0.1 * Double(q.power), drift: 0.0))
                    if e.ball.vz > (reference.ball.vz - 4.8 / 120) * 0.88 { high += 1 } else { low += 1 }
                    if far {
                        XCTAssertTrue(["far1", "far2"].contains(e.called))
                        if e.ball.vz < 5 { XCTAssertLessThan(1.2 + e.ball.vz * e.ball.vz / (2 * 4.8), 3.23) }
                    }
                    XCTAssertEqual(0, e.actors.reduce(0) { $0 + $1.penalties })
                }
                let fraction = Double(far ? low : high) / 1200.0
                let expected = far ? 0.30 + Double(index) * 0.15 : 0.76 + Double(index) * 0.01
                XCTAssertEqual(expected, fraction, accuracy: 0.04, "\(character) far=\(far)")
                XCTAssertEqual(far ? Set(["far1", "far2"]) : Set(["near", "far1", "far2"]), chosen)
            }
        }
    }
}

/// Port of Android `core/LearningCurriculumTest.kt`.
final class LearningCurriculumTests: XCTestCase {
    func testLaterLowGravityCycleIsRetained() throws {
        XCTAssertEqual(.space, PracticeCurriculum.conditions(SpudJourney.size * 2))
        let night = try XCTUnwrap(SpudJourney.stages.firstIndex { $0.id == "tree_night" })
        XCTAssertEqual(.windNight, PracticeCurriculum.conditions(SpudJourney.size * 2 + night))
    }

    private func game(_ step: Int = 4, mode: ThrowMode = .easy, ball: BallKind = .foam, conditions: PracticeConditions = .calm,
                      topic: String = "", ground: Bool = false, seed: Int64 = 41) throws -> AmuduEngine {
        let s = SpudPractice(step, seed, topic).stage
        let partners = ["kyra", "gaya", "mia", "flare"]
        var members = [Member("h", "miniko", "Alex")]
        for i in 0..<s.bots { members.append(Member("b\(i + 1)", partners[i], "Partner", bot: true)) }
        let config = try PracticeCurriculum.config(step, mode, ball, conditions, members.count, topic, ground)
        return try AmuduEngine(members: members, config: config, seed: seed)
    }

    private func advance(_ e: AmuduEngine, _ t: Double) { NovemberSupport.run(e, t, hz: 120) }

    func testSelectableBallsModesAndConditionsKeepStagesAndProgress() throws {
        let ids = ["catch", "duck", "jump", "move", "tree", "ring", "ground", "catch_move", "pass", "rebound", "duck_two", "jump_two", "dodge_two",
                   "ring_side", "ground_far", "pass_choice", "duck_three", "jump_three", "opposite", "rebound_fast", "ring_high", "catch_fast",
                   "duck_pair", "jump_pair", "dodge_three", "dodge_four", "dodge_pairs", "pass_wide", "call", "freeze"]
        XCTAssertEqual(ids, SpudJourney.baseStages.map { $0.id })
        for step in 0...89 {
            let choices = PracticeCurriculum.balls(step)
            XCTAssertTrue(choices.contains(PracticeCurriculum.ball(step, "AUTO")))
            XCTAssertEqual(SpudJourney.stage(step).skill != .rebound, choices.contains(.paint), "step \(step)")
            for mode in ThrowMode.allCases {
                for ball in choices {
                    let e = try game(step, mode: mode, ball: ball, conditions: PracticeCurriculum.conditions(step))
                    let r = try AmuduCodec.create(AmuduCodec.checkpoint(e))
                    XCTAssertEqual(e.config, r.config)
                    // SpudStage has no Equatable conformance on iOS; its id identifies the stage (Kotlin compares the data class).
                    XCTAssertEqual(e.practice?.stage.id, r.practice?.stage.id)
                }
            }
        }
        let p = SpudProgress()
        let next = p.finish("one", 0, true, "2026-11-15")
        XCTAssertEqual(1, next.completed)
        XCTAssertEqual(next, next.finish("replay-other-ball", 0, true, "2026-11-16"))
        XCTAssertEqual(.breeze, PracticeCurriculum.conditions(10))
        XCTAssertEqual(.breezeEvening, PracticeCurriculum.conditions(19))
        XCTAssertEqual(.windNight, PracticeCurriculum.conditions(37))
    }

    func testOptionalLessonsRestoreWithoutBecomingJourneyStages() throws {
        for topic in PracticeCurriculum.topics where topic != "rules" {
            let e = try game(PracticeCurriculum.step(topic), topic: topic)
            let r = try AmuduCodec.create(AmuduCodec.checkpoint(e))
            XCTAssertEqual(topic, r.config.practiceLesson)
            XCTAssertEqual(3, r.practice?.goal)
        }
        XCTAssertNil(AmuduCodec.config(try GameConfig())["practiceLesson"])
    }

    func testAllModesCanActuallyHitPracticeTargetsWithEveryCompatibleBall() throws {
        let keys = ["tree", "ring", "ground", "ring_side", "ground_far", "ring_high", "tree_evening", "tree_night"]
        let steps = keys.map { key in SpudJourney.stages.firstIndex { $0.id == key } ?? -1 }
        for step in steps {
            for ball in PracticeCurriculum.balls(step) {
                for conditions in PracticeConditions.allCases {
                    for mode in [ThrowMode.easy, ThrowMode.target] {
                        let e = try game(step, mode: mode, ball: ball, conditions: conditions)
                        let p = try XCTUnwrap(e.practice)
                        XCTAssertTrue(e.command("h", "throw", .pointThrow(point: p.target, height: p.targetHeight)))
                        advance(e, 4.0)
                        XCTAssertEqual(1, p.successes, "step=\(step) \(ball) \(conditions) \(mode)")
                    }
                }
            }
        }
    }

    func testBallSpeedAndGravityActuallyChangePractice() throws {
        let beach = try game(0, ball: .beach)
        let tennis = try game(0, ball: .tennis)
        advance(beach, 3.25)
        advance(tennis, 3.25)
        let tennisShot = try XCTUnwrap(tennis.practice?.shots.first)
        let beachShot = try XCTUnwrap(beach.practice?.shots.first)
        XCTAssertGreaterThan(tennisShot.ball.velocity.length(), beachShot.ball.velocity.length())
        let park = try game(2)
        let space = try game(2, conditions: .space)
        park.command("h", "jump", .jump)
        space.command("h", "jump", .jump)
        advance(park, 0.45)
        advance(space, 0.45)
        XCTAssertGreaterThan(space.actors[0].jumpHeight, park.actors[0].jumpHeight + 0.3)
    }

    func testPaintLessonUsesRealContactAndPersistsPaint() throws {
        let e = try game(ball: .paint, topic: "paint")
        let p = try XCTUnwrap(e.practice)
        XCTAssertTrue(e.command("h", "throw", .pointThrow(point: p.target, height: 1.1)))
        advance(e, 1.0)
        XCTAssertEqual(1, p.successes)
        XCTAssertEqual(1, p.partner(e).paintHits.count)
        // Roster order kept like Kotlin's in-memory LinkedHashMap (the saved local game passes it the same way).
        let r = try AmuduCodec.create(AmuduCodec.checkpoint(e), order: e.actors.map { $0.member.id })
        XCTAssertEqual(e.actors[1].paintHits, r.actors[1].paintHits)
    }

    func testGroundLessonEnforcesSharedRuleOnActualBounces() throws {
        func launch(_ allowed: Bool) throws -> AmuduEngine {
            let e = try game(topic: "ground", ground: allowed)
            let p = try XCTUnwrap(e.practice)
            let h = e.actors[0]
            // Low trajectory with a first bounce just before the target and a chest-level rebound.
            let b = Ball(V(8.0, 7.3), 0.3, V(0.0, -5.0), -8.0, nil, bounces: 0, flightId: "ground", launchAt: e.time)
            // Kotlin shares one Ball object between the shot and the engine; iOS refreshes the engine ball from the first shot.
            p.shots.append(PracticeBall(b, h.member.id, false, p.target))
            e.ball = b
            return e
        }
        let blocked = try launch(false)
        advance(blocked, 0.7)
        XCTAssertEqual(1, blocked.practice?.mistakes)
        XCTAssertEqual(0, blocked.practice?.successes)
        let allowed = try launch(true)
        advance(allowed, 0.7)
        XCTAssertEqual(1, allowed.practice?.successes)
    }

    func testPracticeCallIdentifiesThePartnerForSpeechAndCatch() throws {
        let e = try game(PracticeCurriculum.step("calls"), topic: "calls")
        let target = try XCTUnwrap(e.practice).partner(e).member.id
        XCTAssertTrue(e.command("h", "choose", .select(target: target)))
        XCTAssertEqual(target, e.called)
        XCTAssertTrue(e.command("h", "toss", .toss(power: 0.5, drift: 0.0)))
    }

    func testNewLearningCopyIsTranslatedAndSafeForEveryLanguage() {
        let old = AppText.language
        defer { AppText.configure(old) }
        for lang in ["he", "es", "ar", "hi", "nl"] {
            AppText.configure(lang)
            for (key, row) in LearningCopy.rows {
                XCTAssertTrue(row.count == 6, key)
                XCTAssertFalse(Kotlin.isBlank(LearningCopy.get(key)), key)
                XCTAssertNotEqual(row[0], LearningCopy.get(key), "\(lang) \(key)")
            }
        }
    }
}

/// Port of Android `core/OwnerFeedbackPhysicsTest.kt`.
final class OwnerFeedbackPhysicsTests: XCTestCase {
    private func actor(_ bot: Bool = false, _ id: String = "miniko") -> GameActor {
        return GameActor(member: Member("p0", id, "Player", bot: bot), position: V(8.0, 12.0))
    }

    func testCatchingUsesFacingSpeedMovementAndSkill() {
        let h = actor()
        h.facing = V(0.0, -1.0)
        var b = Ball(V(8.0, 11.5), 1.2, V(0.0, 4.0), 0.0)
        let from = GameActor(member: Member("p1", "gaya", "Gaya", bot: true), position: V(8.0, 4.0))
        let easy = CatchPhysics.probability(h, b, from)
        XCTAssertEqual(0.95, easy, accuracy: 0.001)
        h.facing = V(0.0, 1.0)
        h.move = V(1.0, 0.0)
        b.velocity = V(0.0, 16.0)
        from.position = V(8.0, 11.9)
        let hard = CatchPhysics.probability(h, b, from)
        XCTAssertTrue(hard >= 0.225 && hard <= 0.25, "\(hard)")
        let weak = actor(true, "miniko")
        let strong = actor(true, "gaya")
        weak.facing = V(0.0, -1.0)
        strong.facing = weak.facing
        b.velocity = V(0.0, 4.0)
        from.position = V(8.0, 4.0)
        XCTAssertEqual(0.78 * 0.90, CatchPhysics.probability(weak, b, from), accuracy: 0.001)
        XCTAssertEqual(0.97 * 0.90, CatchPhysics.probability(strong, b, from), accuracy: 0.001)
    }

    private func stageGame(_ id: String) throws -> AmuduEngine {
        let step = SpudJourney.stages.firstIndex { $0.id == id } ?? -1
        return try AmuduEngine(members: [Member("p0", "miniko", "Player"), Member("p1", "gaya", "Gaya", bot: true)],
                               config: GameConfig(participants: 2, actionSeconds: 0, challengeStep: step), seed: 1)
    }

    func testMoveCatchTargetsAReachableSideLocation() throws {
        let e = try stageGame("catch_move")
        for _ in 0..<410 { e.tick(0.01) }
        XCTAssertGreaterThan(abs(e.landing.x - e.actors[0].position.x), 2)
        XCTAssertLessThan((e.landing - e.actors[0].position).length(), 3)
    }

    func testMovingAwayAndReturningStillGetsHit() throws {
        let e = try stageGame("move")
        e.command("p0", "left", .move(V(1.0, 0.0)))
        for _ in 0..<20 { e.tick(0.01) }
        e.command("p0", "right", .move(V(-1.0, 0.0)))
        for _ in 0..<20 { e.tick(0.01) }
        e.command("p0", "stop", .move(V(0.0, 0.0)))
        for _ in 0..<600 { e.tick(0.01) }
        XCTAssertGreaterThan(e.practice?.mistakes ?? 0, 0)
        XCTAssertEqual(0, e.practice?.successes)
    }

    func testFailedPassIsStillInFlightBeyondReceiver() throws {
        let e = try stageGame("pass")
        let d = try XCTUnwrap(e.practice)
        let b = Ball(V(d.target.x + 2, d.target.y + 0.05), 2.7, V(0.0, -7.0), 1.0, nil, bounces: 0, flightId: "miss", launchAt: e.time)
        d.shots.append(PracticeBall(b, "p0", false, d.target))
        e.ball = b
        e.tick(0.02)
        // Kotlin checks object identity (`it.ball === b`) and reads the shared ball; iOS identifies the shot by its flight id
        // and reads the shot's own (authoritative) ball.
        let shot = try XCTUnwrap(d.shots.first { $0.ball.flightId == "miss" })
        XCTAssertNil(shot.ball.holder)
        XCTAssertLessThan(shot.ball.position.y, d.target.y)
        XCTAssertEqual(0, d.mistakes)
    }

    func testDuckCannotMakeDescendingBallPassThroughBody() throws {
        let e = try AmuduEngine(members: [Member("p0", "miniko", "Player"), Member("p1", "gaya", "Gaya")], config: GameConfig(participants: 2),
                                seed: 1)
        let target = e.actors[1]
        e.phase = .air
        e.called = "p1"
        target.duckUntil = 2.0
        e.ball = Ball(target.position, 1.0, V(0.0, 0.0), -1.0, nil)
        e.tick(0.01)
        XCTAssertEqual(.retrieve, e.phase)
        XCTAssertEqual("air_hit", e.infoCode)
    }

    func testEasyTreeArcUsesActualBallLaunchPosition() throws {
        for power in [0.15, 0.4, 0.7, 1.0] {
            let e = try AmuduEngine(members: [Member("p0", "miniko", "Player"), Member("p1", "mia", "Mia", bot: true)],
                                    config: GameConfig(participants: 2, throwMode: .easy, challengeStep: 4), seed: 1)
            e.command("p0", "throw", .throwBall(power: power))
            for _ in 0..<400 { e.tick(0.01) }
            XCTAssertEqual(1, e.practice?.successes, "Power \(power) missed the aimed trunk")
        }
    }

    func testBotJumpUsesIndependentJumpRatingAndPreservesHumanControl() {
        // Same Speed, different Jump: changing the jump rating must actually change the leap.
        let low = actor(true, "coach67")
        let high = actor(true, "minik")
        XCTAssertEqual(AmuduCharacters.get("coach67").qualities.speed, AmuduCharacters.get("minik").qualities.speed)
        XCTAssertGreaterThan(CatchPhysics.jumpVelocity(high), CatchPhysics.jumpVelocity(low))
        let weak = actor(true, "moshiko")
        let strong = actor(true, "flare")
        let weakVelocity = CatchPhysics.jumpVelocity(weak)
        let strongVelocity = CatchPhysics.jumpVelocity(strong)
        let weakPeak = weakVelocity * weakVelocity / (2 * 9.8)
        let strongPeak = strongVelocity * strongVelocity / (2 * 9.8)
        XCTAssertGreaterThan(strongPeak, weakPeak * 1.5)
        XCTAssertEqual(CatchPhysics.jumpVelocity(actor(false, "moshiko")), CatchPhysics.jumpVelocity(actor(false, "flare")))
    }

    func testFirstCatchDoesNotTeachTheMovingCatchMarker() throws {
        let movingStage = try XCTUnwrap(SpudJourney.stages.first { $0.id == "catch_move" })
        for mode in ThrowMode.allCases {
            let first = PracticeGuidance.brief(SpudJourney.stages[0], mode, false)
            let moving = PracticeGuidance.brief(movingStage, mode, false)
            XCTAssertFalse(first.contains("marker"))
            XCTAssertTrue(moving.contains("marker"))
        }
    }
}

/// Port of Android `core/SpaceTossTest.kt`.
final class SpaceTossTests: XCTestCase {
    private func toss(_ power: Double, _ scene: ArenaScene = .andromeda) throws -> AmuduEngine {
        let e = try AmuduEngine(members: [Member("a", "minik", "A"), Member("b", "mia", "B")],
                                config: GameConfig(scene: scene, participants: 2, width: 24.0, depth: 24.0, actionSeconds: 0), seed: 17)
        e.command("a", "select", .select(target: "b"))
        e.command("a", "toss", .toss(power: power, drift: 0.0))
        return e
    }

    func testMinimumSpaceTossIsLowBriefAndStillPhysicallyCatchable() throws {
        let e = try toss(0.0)
        var peak = 0.0
        var catchable = false
        while e.phase == .air {
            e.tick(1.0 / 120)
            peak = max(peak, e.ball.height)
            if e.ball.vz < 0 && e.ball.height >= 0.70 && e.ball.height <= 1.55 { catchable = true }
            if e.time >= 2.7 {
                XCTFail("toss still airborne at \(e.time)")
                break
            }
        }
        XCTAssertEqual(2.8 * 1.15 * 1.20 * 1.10 * 1.15, peak, accuracy: 0.03)
        XCTAssertTrue(catchable)
        XCTAssertEqual(.retrieve, e.phase)
    }

    func testGentleSwipesStayLowButFullPowerRetainsSpaceHeight() throws {
        let peaks = try [0.0, 0.1, 0.2, 0.3, 0.5, 0.75, 1.0].map { p -> Double in
            let e = try toss(p)
            return e.ball.height + e.ball.vz * e.ball.vz / (2 * e.config.scene.gravity)
        }
        XCTAssertTrue(zip(peaks, peaks.dropFirst()).allSatisfy { $0.1 > $0.0 })
        XCTAssertLessThan(peaks[2], 5.7)
        let maxVz = 9.8 * 4 / 2 - 1.2 / 4
        XCTAssertEqual((1.2 + maxVz * maxVz / (2 * 4.8)) * 0.90, peaks[peaks.count - 1], accuracy: 1e-8)
    }

    func testFarRunnerHasLessTimeToReachLowCallThanHighCall() throws {
        func canReach(_ power: Double) throws -> Bool {
            let e = try toss(power)
            let b = e.actor("b")!
            b.position = V(0.6, 0.6)
            // The caller runs away, so the receiver is not blocked by a stationary body.
            e.command("a", "leave-center", .move(V(1.0, 0.0)))
            while e.phase == .air {
                e.command("b", "move-\(e.serial)-\(e.time)", .move((e.landing - b.position).unit()))
                e.tick(1.0 / 120)
                if e.ball.vz < 0 && e.ball.height >= 1.65 && e.ball.height <= 2.0 &&
                    (b.position - e.ball.position).length() < e.config.ball.catchRadius {
                    return true
                }
            }
            return false
        }
        XCTAssertFalse(try canReach(0.0))
        XCTAssertTrue(try canReach(1.0))
    }

    func testSpaceTossIsContinuousBallisticsNotAnAnimationOrHomingThrow() throws {
        let e = try toss(0.2)
        let start = e.ball.height
        let velocity = e.ball.vz
        for _ in 0..<40 { e.tick(0.01) }
        XCTAssertEqual(start + velocity * 0.4 - 0.5 * e.config.scene.gravity * 0.4 * 0.4, e.ball.height, accuracy: 0.001)
        XCTAssertEqual(velocity - e.config.scene.gravity * 0.4, e.ball.vz, accuracy: 0.001)
    }
}
