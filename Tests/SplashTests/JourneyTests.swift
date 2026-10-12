import XCTest
@testable import MinikSplash

/// Port of Android core/SplashJourneyTest.kt: the 30-step drill journey (dodging, aiming, rewards).
final class SplashJourneyTests: XCTestCase {
    private func engine(_ kind: ChallengeKind, _ cycle: Int = 0) -> SplashEngine {
        let spec = kind.drill!
        var members = [Member("p0", "miniko")]
        for i in stride(from: 1, through: spec.bots, by: 1) {
            members.append(Member("p\(i)", kind.partner(cycle).id, team: 1, bot: true))
        }
        var config = SplashConfig()
        config.challenge = kind
        config.chapter = cycle
        return SplashEngine(members: members, seed: 41, config: config)
    }

    private func advance(_ e: SplashEngine, _ seconds: Double) {
        for _ in 0..<Int(seconds * 120) { e.tick(1.0 / 120) }
    }

    private func answer(_ a: SplashActor, correct: Bool = true) -> Int? {
        return a.choices.first { ($0.text == a.question?.answer) == correct }?.index
    }

    func testThirtyUniqueStagesTeachSimpleActionsBeforeCombinations() {
        let path = SplashDrills.journey
        XCTAssertEqual(path.count, 30)
        XCTAssertEqual(Set(path).count, 30)
        XCTAssertLessThan(path.firstIndex(of: .duck)!, path.firstIndex(of: .dodgeTwo)!)
        XCTAssertLessThan(path.firstIndex(of: .jump)!, path.firstIndex(of: .dodgePairs)!)
        XCTAssertLessThan(path.firstIndex(of: .sidestep)!, path.firstIndex(of: .dodgeOpposite)!)
    }

    func testIdlePlayerCannotEarnEvasionPoints() {
        for k in SplashDrills.journey where k.drill?.defending == true {
            let e = engine(k)
            advance(e, 35.0)
            XCTAssertTrue(e.drill?.failed == true, "\(k.name) must punish missed evasions")
            XCTAssertEqual(e.drill?.successes, 0, k.name)
            XCTAssertFalse(e.result?.winners.contains("p0") ?? true, k.name)
        }
    }

    func testDedicatedDrillsEnforceTheirControlAndFreezeOnPause() {
        let e = engine(.duck)
        XCTAssertFalse(e.command("p0", "jump", .jump))
        XCTAssertFalse(e.command("p0", "move", .move(V(1.0, 0.0))))
        XCTAssertTrue(e.command("p0", "duck", .crouch))
        e.paused = true
        advance(e, 15.0)
        XCTAssertEqual(e.time, 0.0)
        XCTAssertTrue(e.shots.isEmpty)
    }

    func testTimedDuckAndJumpAvoidProductionHitboxesEvenInPairedWaves() {
        for k in [ChallengeKind.duck, .jump, .duckPair, .jumpPair] {
            for cycle in [0, 10] {
                let e = engine(k, cycle)
                var seq = 0
                let human = e.actors[0]
                for _ in 0..<(120 * 180) {
                    let soon = e.shots.filter { $0.owner != "p0" }.map { (human.position - $0.position).length() / $0.velocity.length() }.min()
                    if let soon = soon, soon >= 0.29 && soon <= 0.40 {
                        e.command("p0", "control-\(seq)", k.drill?.defence == .duck ? .crouch : .jump)
                        seq += 1
                    }
                    e.tick(1.0 / 120)
                }
                XCTAssertTrue(e.drill?.won == true, "\(k)/\(cycle): \(e.drill?.successes ?? -1) hits \(e.drill?.mistakes ?? -1)")
                XCTAssertEqual(e.result?.winners, ["p0"])
            }
        }
    }

    func testAimingScoresFlightThroughRingNotTapOrWrongAnswer() {
        let e = engine(.ring)
        let d = e.drill!
        let a = e.actors[0]
        a.held = answer(a)
        e.command("p0", "aim", .drillAim(x: d.target.x, height: d.height))
        XCTAssertEqual(d.successes, 0)
        e.command("p0", "throw", .throwBalloon)
        advance(e, 5.0)
        XCTAssertEqual(d.successes, 1)
        XCTAssertEqual(d.mistakes, 0)
        a.held = answer(a, correct: false)
        e.command("p0", "wrong-aim", .drillAim(x: d.target.x, height: d.height))
        e.command("p0", "wrong-throw", .throwBalloon)
        advance(e, 5.0)
        XCTAssertEqual(d.successes, 1)
    }

    func testAllRingPositionsAndGroundTargetsAreReachable() {
        for k in [ChallengeKind.ring, .ringSides, .ringHigh, .ground, .groundFar] {
            let e = engine(k)
            let d = e.drill!
            let a = e.actors[0]
            let goal = d.goal
            for i in 0..<goal {
                a.held = answer(a)
                let cmd: Command = d.spec.ground ? .aim(d.target - a.position) : .drillAim(x: d.target.x, height: d.height)
                XCTAssertTrue(e.command("p0", "aim-\(i)", cmd))
                XCTAssertTrue(e.command("p0", "throw-\(i)", .throwBalloon))
                advance(e, 5.0)
            }
            XCTAssertTrue(d.won, "\(k): \(d.successes) successes, \(d.mistakes) misses")
        }
    }

    func testMissesCannotAwardSuccessAndSameProjectileCountsOnce() {
        let e = engine(.ring)
        let d = e.drill!
        let a = e.actors[0]
        a.held = answer(a)
        e.command("p0", "aim", .drillAim(x: 1.0, height: 4.5))
        e.command("p0", "throw", .throwBalloon)
        advance(e, 6.0)
        XCTAssertEqual(d.successes, 0)
        XCTAssertEqual(d.mistakes, 1)
    }

    func testCheckpointRestoresLiveWaveWithoutDuplicateCredit() {
        let e = engine(.duckPair)
        advance(e, 4.0)
        let checkpoint = WorldCodec.checkpoint(e)
        let restored = engine(.duckPair)
        WorldCodec.restore(restored, checkpoint)
        let live = e.drill!.incoming
        let copy = restored.drill!.incoming
        XCTAssertEqual(Set(live.keys), Set(copy.keys))
        for (id, flight) in live {
            XCTAssertEqual(copy[id]?.aim, flight.aim, id)
            XCTAssertEqual(copy[id]?.passed, flight.passed, id)
        }
        XCTAssertEqual(e.drill!.wave, restored.drill!.wave)
        XCTAssertEqual(e.drill!.releaseAt, restored.drill!.releaseAt)
        advance(e, 25.0)
        advance(restored, 25.0)
        XCTAssertEqual(e.drill!.mistakes, restored.drill!.mistakes)
        XCTAssertEqual(e.drill!.successes, restored.drill!.successes)
    }

    func testDailyRewardIsOncePerDayAndLegacyReceiptCannotSkipDifferentLesson() {
        let old = ChallengeProgress(completed: 5, points: 230, lastBonusDay: "2026-10-08")
        XCTAssertEqual(SplashDrills.migrateCompleted(old.completed), old.completed)
        XCTAssertEqual(old.finish("legacy", 5, true, "2026-10-09", .letter), old)
        let next = old.finish("new", 5, true, "2026-10-09")
        XCTAssertEqual(next.points - old.points, 70)
        XCTAssertEqual(next.finish("new", 5, true, "2026-10-09"), next)
        XCTAssertEqual(next.finish("next", 6, true, "2026-10-09").points - next.points, 40)
    }
}

/// Port of Android core/PaintFeedbackTest.kt: paint walls, targets, wall battles, hit effects and journey progress.
final class PaintFeedbackTests: XCTestCase {
    private func engine(_ kind: ChallengeKind? = .cover, wall: Bool = false, effect: HitEffect = .cosmetic) -> SplashEngine {
        let members = wall ? (0...3).map { Member("p\($0)", Characters.all[$0].id, team: $0 / 2) }
            : [Member("p0", "miniko", team: 0), Member("p1", "minik", team: 1)]
        var config = SplashConfig()
        config.challenge = kind
        config.wallBattle = wall
        config.hitEffect = effect
        return SplashEngine(members: members, mode: wall ? .teams : .solo, seed: 12, config: config)
    }

    private func correct(_ a: SplashActor) -> Int? {
        return a.choices.first { $0.text == a.question?.answer }?.index
    }

    private func throwWall(_ e: SplashEngine, _ u: Double, _ v: Double) {
        guard let a = e.actor("p0") else { return XCTFail("no player") }
        a.position = V(10.0, 10.0)
        a.held = correct(a)
        XCTAssertTrue(e.command("p0", "aim-\(a.sequence)", .paintAt(wall: 0, u: u, v: v)))
        XCTAssertTrue(e.command("p0", "throw-\(a.sequence)", .throwBalloon))
        for _ in 0..<40 { e.tick(0.1) }
    }

    func testActualFlightPaintsRequestedWallAndRepeatedSpotDoesNotComplete() {
        let e = engine()
        throwWall(e, 0.5, 0.5)
        let first = e.paintSession.coverage(0)
        XCTAssertTrue(first > 0.0 && first < 0.5)
        throwWall(e, 0.5, 0.5)
        XCTAssertEqual(e.paintSession.coverage(0), first, accuracy: 0.000001)
        XCTAssertNil(e.result)
    }

    func testAllTargetsAreReachableThroughBallistics() {
        for u in [0.05, 0.5, 0.95] {
            for v in [0.05, 0.5, 0.95] {
                let e = engine()
                throwWall(e, u, v)
                XCTAssertGreaterThan(e.paintSession.coverage(0), 0.0, "\(u),\(v)")
            }
        }
    }

    func testWrongAnswerDoesNotPaint() {
        let e = engine()
        let a = e.actors[0]
        a.held = a.choices.first { $0.text != a.question?.answer }?.index
        e.command("p0", "aim", .paintAt(wall: 0, u: 0.5, v: 0.5))
        e.command("p0", "throw", .throwBalloon)
        XCTAssertTrue(e.shots.isEmpty)
        XCTAssertEqual(e.paintSession.coverage(0), 0.0)
    }

    func testWholeWallAndPatternUseCoverageNotHitCount() {
        for k in [ChallengeKind.cover, .pattern, .letter, .shape] {
            let e = engine(k)
            let s = e.paintSession
            let w = s.walls[0]
            for i in w.cells.indices where s.targetMask[i] { w.cells[i] = 0 }
            e.tick(0.01)
            XCTAssertEqual(e.result?.winners, ["p0"], k.name)
        }
    }

    func testFourOffShapeShotsFailAndCanRestartClean() {
        let e = engine(.shape)
        for _ in 0..<4 { e.paintSession.hit(0, 0.01, 0.01, 0) }
        e.tick(0.01)
        XCTAssertTrue(e.paintSession.failed)
        XCTAssertFalse(e.result?.winners.contains("p0") ?? true)
        XCTAssertFalse(engine(.shape).paintSession.failed)
    }

    func testTargetRewardsAccuracyAndWaitsForLastProjectile() {
        let e = engine(.target)
        let p = e.paintSession
        p.hit(0, 0.5, 0.5, 0)
        p.hit(0, 0.77, 0.5, 1)
        XCTAssertGreaterThan(p.points[0], p.points[1])
        p.throwsTaken = [10, 10]
        e.shots.append(Shot(id: "last", owner: "p1", questionId: "q", answer: "a", explanation: "", color: 1, position: V(10.0, 10.0),
                            height: 1.0, velocity: V(1.0, 0.0), vz: 1.0))
        e.tick(0.01)
        XCTAssertNil(e.result)
        for _ in 0..<60 { e.tick(0.1) }
        XCTAssertNotNil(e.result)
    }

    func testFixedTargetDoesNotTimeOutOrAllowAnEleventhThrow() {
        let e = engine(.target)
        e.restoreClock(4000.0)
        e.tick(0.01)
        XCTAssertNil(e.result)
        e.paintSession.throwsTaken[0] = 10
        let a = e.actors[0]
        a.held = correct(a)
        XCTAssertFalse(e.command("p0", "eleven", .throwBalloon))
    }

    func testTeamScoresOnlyOpposingWallAndFullCoverageWins() {
        let e = engine(nil, wall: true)
        let s = e.paintSession
        s.hit(0, 0.5, 0.5, 0)
        XCTAssertEqual(s.walls[0].fraction(0), 0.0)
        s.walls[1].cells = Array(repeating: 0, count: s.walls[1].cells.count)
        e.tick(0.01)
        XCTAssertEqual(e.result?.winners, ["p0", "p1"])
    }

    private func hit(_ e: SplashEngine, _ id: String) {
        e.actor("p0")?.position = V(10.0, 10.0)
        e.actor("p2")?.position = V(16.0, 16.0)
        e.actor("p1")?.position = V(3.0, 15.0)
        e.actor("p3")?.position = V(17.0, 4.0)
        e.shots.append(Shot(id: id, owner: "p2", questionId: "q", answer: "a", explanation: "", color: 2, position: V(10.0, 9.5),
                            height: 1.0, velocity: V(0.0, 5.0), vz: 0.0))
        e.tick(0.1)
    }

    func testCosmeticHitsNeverSlowStopOrAddObjectiveScore() {
        let e = engine(nil, wall: true)
        let a = e.actor("p0")!
        let speed = e.movementSpeed(a)
        for i in 0..<6 { hit(e, "s\(i)") }
        XCTAssertEqual(e.movementSpeed(a), speed)
        XCTAssertEqual(a.cleanUntil, 0.0)
        XCTAssertEqual(e.teamScores.reduce(0, +), 0)
    }

    func testSlowStacksExpireIndependentlyAndCapDoesNotRefreshOldHits() {
        let e = engine(nil, wall: true, effect: .slow)
        let a = e.actor("p0")!
        hit(e, "first")
        XCTAssertEqual(a.slowHits.count, 1)
        let expiry = a.slowHits[0]
        e.restoreClock(15.0)
        hit(e, "second")
        XCTAssertEqual(a.slowHits.count, 2)
        for i in 0..<6 { hit(e, "more\(i)") }
        XCTAssertEqual(a.slowHits.count, 5)
        XCTAssertEqual(a.slowHits.first, expiry)
        e.restoreClock(expiry + 0.01)
        e.tick(0.01)
        XCTAssertEqual(a.slowHits.count, 4)
        e.restoreClock(46.0)
        e.tick(0.01)
        XCTAssertTrue(a.slowHits.isEmpty)
    }

    func testRestBlocksInputThenReturnsClean() {
        let e = engine(nil, wall: true, effect: .rest)
        let a = e.actor("p0")!
        for i in 0..<3 { hit(e, "rest\(i)") }
        XCTAssertGreaterThan(a.cleanUntil, e.time)
        XCTAssertFalse(e.command("p0", "move", .move(V(1.0, 0.0))))
        e.restoreClock(a.cleanUntil + 0.01)
        e.tick(0.01)
        XCTAssertTrue(a.paint.isEmpty)
        XCTAssertTrue(e.command("p0", "move2", .move(V(1.0, 0.0))))
    }

    func testSaveRestoresPaintIndependentTimersAndChallengeIdentity() {
        let e = engine(nil, wall: true, effect: .slow)
        hit(e, "slow")
        e.paintSession.hit(1, 0.5, 0.5, 0)
        let restored = SplashEngine(members: e.members, mode: e.mode, config: WorldCodec.config(WorldCodec.config(e.config)))
        WorldCodec.restore(restored, WorldCodec.checkpoint(e))
        XCTAssertEqual(e.paintSession.walls[1].cells, restored.paintSession.walls[1].cells)
        XCTAssertEqual(e.actor("p0")!.slowHits, restored.actor("p0")!.slowHits)
    }

    func testCompleteCycleAdvancesOpponentAndNeverPaysTwice() {
        var p = ChallengeProgress()
        let first = ChallengeKind.duel.partner(0)
        for i in ChallengeKind.allCases.indices {
            let next = p.finish("match\(i)", i, true, "2026-10-08")
            XCTAssertEqual(next.finish("match\(i)", i, true, "2026-10-08"), next)
            p = next
        }
        XCTAssertEqual(p.chapter, 1)
        XCTAssertNotEqual(ChallengeKind.duel.partner(p.chapter), first)
        XCTAssertEqual(p.points, ChallengeKind.allCases.count * 40 + 30)
        XCTAssertEqual(p.finish("loss", ChallengeKind.allCases.count, false, "2026-10-09"), p)
        let next = p.finish("new", ChallengeKind.allCases.count, true, "2026-10-09")
        XCTAssertEqual(next.points - p.points, 80)
    }

    func testMissedDaysDoNotResetAndBackwardsClockDoesNotPayDailyAgain() {
        var p = ChallengeProgress().finish("one", 0, true, "2026-10-08")
        p = p.finish("two", 1, true, "2026-10-07")
        XCTAssertEqual(p.points, 110)
        p = p.finish("three", 2, true, "2026-11-02")
        XCTAssertEqual(p.completed, 3)
        XCTAssertEqual(p.points, 180)
    }

    func testDifficultyChangesActualMovementAndThinking() {
        func e(_ d: Difficulty) -> SplashEngine {
            var config = SplashConfig()
            config.difficulty = d
            return SplashEngine(members: [Member("u", "miniko"), Member("b", "kyra", bot: true)], config: config)
        }
        let easy = e(.easy)
        let pro = e(.pro)
        XCTAssertLessThan(easy.movementSpeed(easy.actors[1]), pro.movementSpeed(pro.actors[1]) * 0.7)
        XCTAssertGreaterThan(easy.actors[1].nextBotThink, pro.actors[1].nextBotThink)
    }

    func testOpponentsImproveByRelevantSkillWhilePartnersGetLessPrecise() {
        for kind in ChallengeKind.allCases {
            let ranks = Characters.all.indices.map { kind.aptitude(kind.partner($0)) }
            let ordered = zip(ranks, ranks.dropFirst()).allSatisfy { kind.cooperative ? $0.0 >= $0.1 : $0.0 <= $0.1 }
            XCTAssertTrue(ordered, kind.name)
        }
        XCTAssertEqual(ChallengeKind.passing.aptitude(ChallengeKind.passing.partner(0)), Characters.all.map { ChallengeKind.passing.aptitude($0) }.max())
    }

    func testGuideHelpsWithoutFinishingForTheHumanOrSpendingTheirMistakes() {
        var config = SplashConfig()
        config.width = 26.0
        config.depth = 14.0
        config.challenge = .cover
        let e = SplashEngine(members: [Member("p0", "miniko", team: 0), Member("p1", ChallengeKind.cover.partner(0).id, team: 0, bot: true)], config: config)
        e.actors[0].position = V(16.0, 8.0)
        for _ in 0..<600 { e.tick(0.1) }
        XCTAssertGreaterThan(e.paintSession.coverage(0), 0.0)
        XCTAssertLessThan(e.paintSession.coverage(0), 0.7)
        XCTAssertNil(e.result)
        var shapeConfig = SplashConfig()
        shapeConfig.challenge = .shape
        let shape = PaintSession(shapeConfig, false)
        for _ in 0..<10 { shape.hit(0, 0.01, 0.01, 0, false) }
        XCTAssertEqual(shape.spills, 0)
        XCTAssertFalse(shape.failed)
    }

    /// Android checks the feedback rows; iOS loads the whole catalog, so every row is checked.
    func testTranslationsKeepEveryRuntimePlaceholder() throws {
        let tokens = try NSRegularExpression(pattern: "\\{[0-9]+\\}")
        func found(_ s: String) -> Set<String> {
            let ns = s as NSString
            return Set(tokens.matches(in: s, range: NSRange(location: 0, length: ns.length)).map { ns.substring(with: $0.range) })
        }
        for key in AppText.keys() {
            for lang in ["es", "ar", "hi", "nl"] {
                guard let value = AppText.translated(key, lang) else {
                    XCTFail("\(lang): \(key)")
                    continue
                }
                XCTAssertFalse(value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, "\(lang): \(key)")
                XCTAssertEqual(found(value), found(key), "\(lang): \(key)")
            }
        }
    }

    func testCooperativePassIsCatchableAndReturnUsesSamePhysics() {
        var config = SplashConfig()
        config.challenge = .passing
        let e = SplashEngine(members: [Member("p0", "miniko", team: 0), Member("p1", ChallengeKind.passing.partner(0).id, team: 1, bot: true)], config: config)
        for _ in 0..<70 { e.tick(0.1) }
        XCTAssertEqual(e.paintSession.catches, 1)
        XCTAssertTrue(e.actors[0].passBall)
        XCTAssertTrue(e.command("p0", "return", .shootAt("p1")))
        for _ in 0..<35 { e.tick(0.1) }
        XCTAssertTrue(e.actors[1].passBall)
        XCTAssertFalse(e.paintSession.failed)
    }

    func testUnattendedWidePassFailsRatherThanBeingAnAutomaticSuccess() {
        var config = SplashConfig()
        config.challenge = .passing
        config.chapter = 10
        let e = SplashEngine(members: [Member("p0", "miniko", team: 0), Member("p1", "minik", team: 1, bot: true)], config: config)
        e.actors[0].position = V(1.0, 17.0)
        for _ in 0..<100 { e.tick(0.1) }
        XCTAssertTrue(e.paintSession.failed)
        XCTAssertNotNil(e.result)
    }
}

/// Port of Android core/JourneyLanguageTest.kt.
final class JourneyLanguageTests: XCTestCase {
    func testEveryBriefAndTitleIsTranslated() {
        defer { AppText.configure("en") }
        for lang in ["es", "ar", "hi", "nl"] {
            AppText.configure(lang)
            for kind in SplashDrills.journey {
                XCTAssertNotEqual(AppText.t(kind.en), kind.en, "\(lang): \(kind.name)")
                XCTAssertNotEqual(AppText.t(kind.goal(false)), kind.goal(false), "\(lang): \(kind.name)")
                XCTAssertNotEqual(AppText.t(kind.introduction(false)), kind.introduction(false), "\(lang): \(kind.name)")
            }
        }
    }
}
