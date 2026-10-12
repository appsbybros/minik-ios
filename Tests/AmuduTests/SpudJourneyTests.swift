import XCTest
@testable import MinikAmudu

/// Port of Android `core/SpudJourneyTest.kt` and `core/JourneyLanguageTest.kt`: the daily skill journey is judged by
/// real ball contacts, every challenge can be passed with real throws and catches, and idling never passes.
final class SpudJourneyTests: XCTestCase {
    private func engine(_ id: String, _ cycle: Int = 0) throws -> AmuduEngine {
        let index = try XCTUnwrap(SpudJourney.stages.firstIndex { $0.id == id })
        let s = SpudJourney.stages[index]
        var used: Set<String> = ["miniko"]
        var members = [Member("p0", "miniko", "Player")]
        for i in 0..<s.bots {
            let c = s.bot(cycle, used)
            used.insert(c.id)
            members.append(Member("p\(i + 1)", c.id, c.en, bot: true))
        }
        let config = try GameConfig(participants: members.count, rules: .spud, actionSeconds: 0, challengeStep: cycle * 30 + index)
        return try AmuduEngine(members: members, config: config, seed: 41)
    }

    private func advance(_ e: AmuduEngine, _ t: Double) {
        for _ in 0..<Int(t * 120) { e.tick(1.0 / 120) }
    }

    /// Kotlin `Math.signum`.
    private func signum(_ x: Double) -> Double {
        return x > 0 ? 1.0 : (x < 0 ? -1.0 : 0.0)
    }

    func testThirtyDistinctSkillsKeepPrerequisitesBeforeCombinations() {
        let ids = SpudJourney.stages.map { $0.id }
        func index(_ id: String) -> Int { return ids.firstIndex(of: id) ?? -1 }
        XCTAssertEqual(30, ids.count)
        XCTAssertEqual(30, Set(ids).count)
        for id in ["duck", "jump", "move"] { XCTAssertLessThan(index(id), index("dodge_two")) }
        XCTAssertLessThan(index("catch"), index("pass"))
        XCTAssertLessThan(index("tree"), index("rebound"))
    }

    func testIdleCannotPassAnyDefenceOrCatchAndPauseDoesNotSpendHearts() throws {
        for stage in SpudJourney.stages where stage.defence || stage.skill == .catching {
            let e = try engine(stage.id)
            let p = try XCTUnwrap(e.practice)
            e.paused = true
            advance(e, 20.0)
            XCTAssertEqual(0.0, e.time)
            XCTAssertEqual(0, p.mistakes)
            e.paused = false
            advance(e, 45.0)
            XCTAssertTrue(p.failed, stage.id)
            XCTAssertEqual(0, p.successes, stage.id)
        }
    }

    func testTimedDuckAndJumpWorkAgainstSingleAndPairedWaves() throws {
        for id in ["duck", "jump", "duck_pair", "jump_pair"] {
            for cycle in [0, 8] {
                let e = try engine(id, cycle)
                let h = e.actors[0]
                let p = try XCTUnwrap(e.practice)
                var n = 0
                for _ in 0..<(120 * 150) where e.result == nil {
                    let soon = p.shots.map { (h.position - $0.ball.position).length() / $0.ball.velocity.length() }.min()
                    if let soon, soon < 0.32 {
                        e.command("p0", "c\(n)", id.hasPrefix("jump") ? .jump : .duck)
                        n += 1
                    }
                    e.tick(1.0 / 120)
                }
                XCTAssertTrue(p.won, "\(id) cycle \(cycle) successes=\(p.successes) mistakes=\(p.mistakes)")
            }
        }
    }

    func testDistinctTaskSpecificRosterHasCorrectDifficultyDirection() {
        for s in SpudJourney.stages {
            let excluded: Set<String> = ["miniko"]
            let first = s.bot(0, excluded)
            let last = s.bot(50, excluded)
            XCTAssertNotEqual("miniko", first.id)
            if s.cooperative || !s.defence {
                XCTAssertGreaterThanOrEqual(s.aptitude(first), s.aptitude(last), s.id)
            } else {
                XCTAssertLessThanOrEqual(s.aptitude(first), s.aptitude(last), s.id)
            }
        }
    }

    /// The power whose real flight lands on (or passes through) the target best.
    private func bestPower(_ e: AmuduEngine) -> Double {
        let h = e.actors[0]
        guard let p = e.practice else { return 0 }
        let distance = (p.target - h.position).length() - 0.52
        let g = e.config.scene.gravity
        func miss(_ n: Int) -> Double {
            let profile = e.throwProfile(h, Double(n) / 100.0)
            if p.stage.skill == .ground {
                let t = (profile.vz + (profile.vz * profile.vz + 2 * g * (1.17 - 0.23)).squareRoot()) / g
                return abs(profile.speed * t - distance)
            }
            let t = distance / profile.speed
            return abs(1.17 + profile.vz * t - 0.5 * g * t * t - p.targetHeight)
        }
        let best = (0...100).min { miss($0) < miss($1) } ?? 0
        return Double(best) / 100.0
    }

    func testEveryAimingStageIsReachableByRealThrowsAndWrongAimFails() throws {
        for id in ["tree", "ring", "ground", "ring_side", "ground_far", "ring_high"] {
            let e = try engine(id)
            let p = try XCTUnwrap(e.practice)
            for i in 0..<p.goal {
                let h = e.actors[0]
                XCTAssertTrue(e.command("p0", "aim\(i)", .aim(p.target - h.position)))
                XCTAssertTrue(e.command("p0", "throw\(i)", .throwBall(power: bestPower(e))))
                advance(e, 3.0)
            }
            XCTAssertTrue(p.won, "\(id) successes=\(p.successes) mistakes=\(p.mistakes)")
            let bad = try engine(id)
            for i in 0..<3 {
                bad.command("p0", "aim\(i)", .aim(V(1.0, 0.0)))
                bad.command("p0", "throw\(i)", .throwBall(power: 0.2))
                advance(bad, 5.0)
            }
            XCTAssertTrue(bad.practice?.failed == true, id)
            XCTAssertEqual(0, bad.practice?.successes)
        }
    }

    func testRealCatchWindowWorksAndCooperativePassesStayReachable() throws {
        for id in ["catch", "catch_move", "catch_fast", "pass", "pass_choice", "pass_wide", "rebound", "rebound_fast"] {
            for cycle in [0, 8] {
                let e = try engine(id, cycle)
                let p = try XCTUnwrap(e.practice)
                let h = e.actors[0]
                var n = 0
                for _ in 0..<(120 * 200) where e.result == nil {
                    if e.ball.holder == "p0" && p.shots.isEmpty {
                        e.command("p0", "a\(n)", .aim(p.target - h.position))
                        n += 1
                        e.command("p0", "t\(n)", .throwBall(power: bestPower(e)))
                        n += 1
                    }
                    if let shot = p.shots.first(where: { $0.incoming || $0.rebounded }) {
                        let aim = shot.rebounded ? shot.aim : e.landing
                        if !shot.rebounded && abs(aim.x - h.position.x) > 0.12 {
                            e.command("p0", "m\(n)", .move(V(signum(aim.x - h.position.x), 0.0)))
                        } else {
                            e.command("p0", "m\(n)", .move(V(0.0, 0.0)))
                        }
                        n += 1
                        let near = (shot.ball.position - h.position).length() / shot.ball.velocity.length()
                        if near < 0.25 {
                            e.command("p0", "c\(n)", .catchBall)
                            n += 1
                        }
                    }
                    e.tick(1.0 / 120)
                }
                XCTAssertTrue(p.won, "\(id) cycle \(cycle) successes=\(p.successes) mistakes=\(p.mistakes)")
                XCTAssertEqual(0, h.rankEarned, "Training cannot farm normal match points")
            }
        }
    }

    func testCallNeedsCorrectPartnerAndFreezeNeedsActualMovement() throws {
        let call = try engine("call")
        let p = try XCTUnwrap(call.practice)
        XCTAssertFalse(call.command("p0", "early", .toss(power: 0.4, drift: 0.0)))
        XCTAssertTrue(call.command("p0", "select", .select(target: p.partner(call).member.id)))
        XCTAssertTrue(call.command("p0", "toss", .toss(power: 0.4, drift: 0.0)))
        advance(call, 3.5)
        XCTAssertEqual(1, p.successes)
        let e = try engine("freeze")
        let drill = try XCTUnwrap(e.practice)
        advance(e, 20.0)
        XCTAssertEqual(0, drill.successes)
        var n = 0
        for _ in 0..<(120 * 40) where e.result == nil {
            let x = e.actors[0].position.x
            e.command("p0", "m\(n)", .move(drill.freezeReady ? V(0.0, 0.0) : V(x > 12 ? -1.0 : 1.0, 0.0)))
            n += 1
            e.tick(1.0 / 120)
        }
        XCTAssertTrue(drill.won)
    }

    func testInFlightCheckpointKeepsWaveAndResultAndRejectsDuplicateRewards() throws {
        let e = try engine("duck_pair")
        advance(e, 3.5)
        XCTAssertEqual(2, e.practice?.shots.count)
        let restored = try AmuduCodec.create(AmuduCodec.checkpoint(e))
        advance(e, 3.0)
        advance(restored, 3.0)
        XCTAssertEqual(e.practice?.mistakes, restored.practice?.mistakes)
        XCTAssertEqual(e.practice?.wave, restored.practice?.wave)
        let p = SpudProgress()
        let done = p.finish("one", 0, true, "2026-10-09")
        XCTAssertEqual(70, done.points)
        XCTAssertEqual(done, done.finish("one", 0, true, "2026-10-09"))
        XCTAssertEqual(110, done.finish("two", 1, true, "2026-10-09").points)
        XCTAssertEqual(done, done.finish("wrong", 3, true, "2026-10-10"))
        XCTAssertEqual(done, done.finish("loss", 1, false, "2026-10-10"))
    }

    func testEveryBriefAndTitleIsTranslated() {
        let before = AppText.language
        defer { AppText.configure(before) }
        for lang in ["es", "ar", "hi", "nl"] {
            AppText.configure(lang)
            for stage in SpudJourney.stages {
                XCTAssertNotEqual(stage.en, AppText.t(stage.en), lang)
                XCTAssertNotEqual(stage.brief(false), AppText.t(stage.brief(false)), lang)
                XCTAssertNotEqual(stage.role(false), AppText.t(stage.role(false)), lang)
            }
        }
    }
}

/// Port of Android `world/SpudReceptionZoomTest.kt`: presentation only, never a change to the simulation.
final class SpudReceptionZoomTests: XCTestCase {
    private func engine() throws -> AmuduEngine {
        let members = [Member("me", "minik", "You"), Member("other", "gaya", "Friend"), Member("bot", "flare", "Flare", bot: true)]
        let e = try AmuduEngine(members: members, config: GameConfig(participants: 3), seed: 73)
        e.actors[0].position = V(8.0, 8.0)
        e.actors[1].position = V(2.0, 2.0)
        e.actors[2].position = V(14.0, 14.0)
        e.phase = .flight
        e.thrower = "bot"
        e.ball = Ball(V(8.0, 4.0), 1.2, V(0.0, 6.0), 3.0)
        return e
    }

    func testOnlyPlausibleIncomingHumanTrajectories() throws {
        let e = try engine()
        let z = SpudReceptionZoom()
        XCTAssertEqual("me", z.incoming(e, "me", true, false)?.receiver)
        e.ball.velocity = V(0.0, -6.0)
        XCTAssertNil(z.incoming(e, "me", true, true))
        e.ball.position = V(2.0, 12.0)
        e.ball.velocity = V(8.0, 0.0)
        XCTAssertNil(z.incoming(e, "me", true, true))
        e.ball.position = V(14.0, 10.0)
        e.ball.velocity = V(0.0, 6.0)
        XCTAssertNil(z.incoming(e, "me", true, true), "Bots never trigger")
    }

    func testOwnAndOtherHumanPreferencesAreIndependent() throws {
        let e = try engine()
        let z = SpudReceptionZoom()
        XCTAssertNil(z.incoming(e, "me", false, true))
        XCTAssertNotNil(z.incoming(e, "me", true, false))
        e.actors[1].position = V(8.0, 8.0)
        e.actors[0].position = V(1.0, 1.0)
        XCTAssertEqual("other", z.incoming(e, "me", false, true)?.receiver)
        XCTAssertNil(z.incoming(e, "me", true, false))
        XCTAssertNil(z.incoming(e, "me", false, false))
    }

    func testHighTossWaitsUntilCatchableAndIgnoresHeldBall() throws {
        let e = try engine()
        let z = SpudReceptionZoom()
        e.phase = .air
        e.called = "me"
        e.ball = Ball(V(8.0, 8.0), 20.0, V(0.0, 0.0), 5.0)
        XCTAssertNil(z.incoming(e, "me", true, false))
        e.ball.height = 4.0
        e.ball.vz = -2.0
        XCTAssertNotNil(z.incoming(e, "me", true, false))
        e.ball.holder = "me"
        XCTAssertNil(z.incoming(e, "me", true, false))
    }

    func testSmoothApproachReturnPauseAndNoSimulationMutation() throws {
        let e = try engine()
        let z = SpudReceptionZoom()
        let before = e.ball
        let time = e.time
        for _ in 0..<40 { _ = z.step(z.incoming(e, "me", true, false), 0.016) }
        XCTAssertTrue(z.amount >= 0.1 && z.amount <= 1.0)
        let previous = z.amount
        e.paused = true
        _ = z.step(z.incoming(e, "me", true, false), 0.016)
        XCTAssertTrue(z.amount > 0 && z.amount < previous)
        for _ in 0..<150 { _ = z.step(nil, 0.016) }
        XCTAssertEqual(0.0, z.amount, accuracy: 0.001)
        XCTAssertEqual(time, e.time)
        XCTAssertEqual(before, e.ball)
    }

    func testPresentingZoomDoesNotChangeIdenticalEngines() throws {
        let a = try engine()
        let b = try engine()
        let zoom = SpudReceptionZoom()
        for _ in 0..<300 {
            a.tick(0.016)
            b.tick(0.016)
            _ = zoom.step(zoom.incoming(a, "me", true, true), 0.016)
            XCTAssertEqual(a.time, b.time)
            XCTAssertEqual(a.ball, b.ball)
            XCTAssertEqual(a.phase, b.phase)
            XCTAssertEqual(a.actors.map { $0.position }, b.actors.map { $0.position })
        }
    }
}
