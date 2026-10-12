import XCTest
@testable import MinikSplash

private func correctChoice(_ a: SplashActor) -> Int? {
    return a.choices.first { $0.text == a.question?.answer }?.index
}

/// Port of Android core/HouseSkillsTest.kt: star ratings change actual play.
final class HouseSkillsTests: XCTestCase {
    private func engine(_ id: String, _ seed: Int64 = 5) -> SplashEngine {
        var config = SplashConfig()
        config.difficulty = .pro
        return SplashEngine(members: [Member("human", "miniko"), Member("bot", id, bot: true)], seed: seed, config: config)
    }

    func testExactRequestedRatings() {
        let expected: [String: [Int]] = ["gaya": [4, 5, 5, 5], "kyra": [5, 4, 5, 4], "flare": [5, 4, 5, 5], "coach67": [3, 3, 3, 4],
                                         "moshiko": [1, 4, 3, 5], "comet": [5, 4, 5, 4], "minik": [3, 2, 3, 2], "miniko": [3, 3, 3, 3],
                                         "june": [5, 4, 5, 3], "mia": [5, 5, 5, 4], "amber": [4, 5, 3, 3]]
        for c in Characters.all {
            let q = c.qualities
            XCTAssertEqual(expected[c.id], [q.speed, q.precision, q.reflexes, q.power], c.id)
        }
        XCTAssertEqual(Characters.get("coach67").en, "Coach")
    }

    func testStarsChangeActualTravelWithSmoothAcceleration() {
        var distances: [String: Double] = [:]
        for c in Characters.all {
            let e = engine(c.id)
            e.practice = true
            let a = e.actor("bot")!
            a.position = V(6.0, 6.0)
            a.move = V(1.0, 0.0)
            for _ in 0..<10 { e.tick(0.05) }
            let distance = a.position.x - 6
            distances[c.id] = distance
            XCTAssertGreaterThan(distance, 0.3, c.id)
            XCTAssertLessThanOrEqual(distance, e.config.moveSpeed * 0.5 * c.qualities.movementFactor, c.id)
            XCTAssertLessThanOrEqual(e.movementSpeed(a), e.config.moveSpeed, c.id)
        }
        XCTAssertGreaterThan(distances["flare"]!, distances["moshiko"]! * 1.4)
    }

    func testAvatarPowerDeterminesHumanAndHousePlayerReleaseSpeed() {
        for c in Characters.all {
            let e = engine(c.id)
            e.practice = true
            for a in e.actors {
                a.held = correctChoice(a)
                XCTAssertTrue(e.command(a.member.id, "throw-" + a.member.id, .throwBalloon))
            }
            XCTAssertEqual(e.shots.first { $0.owner == "human" }?.velocity.length() ?? -1,
                           e.config.throwSpeed * Characters.get("miniko").qualities.throwFactor, accuracy: 0.00001)
            XCTAssertEqual(e.shots.first { $0.owner == "bot" }?.velocity.length() ?? -1, e.config.throwSpeed * c.qualities.throwFactor, accuracy: 0.00001)
        }
    }

    func testHighPrecisionHasLowerActualAngularError() {
        func error(_ cid: String) -> Double {
            var total = 0.0
            for seed in 1...180 {
                let e = engine(cid, Int64(seed))
                let a = e.actor("bot")!
                let target = e.actor("human")!
                a.position = V(6.0, 7.0)
                target.position = V(6.0, 2.0)
                a.held = correctChoice(a)
                a.nextBotThink = 0.0
                e.tick(0.01)
                XCTAssertEqual(e.shots.count, 1)
                guard let shot = e.shots.first else { continue }
                total += abs(atan2(shot.velocity.x, -shot.velocity.y))
            }
            return total / 180
        }
        XCTAssertLessThan(error("gaya"), error("minik") * 0.2)
        XCTAssertLessThan(error("kyra"), error("minik") * 0.5)
    }

    func testReflexesChangeActualDodgeRateAndDontRerollEveryFrame() {
        func rate(_ cid: String) -> Int {
            var count = 0
            for seed in 1...220 {
                let e = engine(cid, Int64(seed))
                let a = e.actor("bot")!
                a.position = V(6.0, 6.0)
                a.nextBotThink = 100.0
                e.actor("human")?.position = V(2.0, 2.0)
                e.shots.append(Shot(id: "incoming", owner: "human", questionId: "old", answer: "4", explanation: "", color: 0,
                                    position: V(6.0, 4.4), height: 1.6, velocity: V(0.0, 4.0), vz: 0.0))
                for _ in 0..<34 { e.tick(0.01) }
                if a.crouchUntil > 0 || a.verticalSpeed > 0 || a.botEvadeUntil > 0 { count += 1 }
            }
            return count
        }
        let elite = rate("gaya")
        let normal = rate("minik")
        XCTAssertGreaterThan(elite, normal + 30, "Elite \(elite), normal \(normal)")
        XCTAssertTrue((110...160).contains(elite), "Elite \(elite)")
        XCTAssertTrue((45...95).contains(normal), "Normal \(normal)")
    }

    func testLobbyEnforcesAbsoluteLimitAndSupportsLargerChosenGroups() {
        XCTAssertEqual(LobbyPlan.problem(2, 5, 6, false), "limit")
        XCTAssertEqual(LobbyPlan.problem(2, 3, 4, false), "selected")
        XCTAssertNil(LobbyPlan.problem(2, 4, 6, true))
        XCTAssertEqual(LobbyPlan.problem(2, 3, 4, true), "teams")
        XCTAssertEqual(LobbyPlan.problem(1, 0, 6, false), "minimum")
    }
}

/// Port of Android core/KnowledgeTest.kt.
final class KnowledgeTests: XCTestCase {
    func testRequestedKnowledgeRatings() {
        let expected = ["minik": 5, "kyra": 5, "flare": 4, "gaya": 4, "mia": 5, "amber": 3, "comet": 4, "june": 3, "moshiko": 3, "coach67": 3, "miniko": 3]
        for c in Characters.all { XCTAssertEqual(expected[c.id], c.qualities.knowledge, c.id) }
    }

    func testActualFirstChoiceMatchesRatingOverManySeedsAndNeverRerolls() {
        for id in ["minik", "gaya", "miniko"] {
            var correct = 0
            for seed in 0..<3500 {
                let e = SplashEngine(members: [Member("human", "miniko"), Member("bot", id, bot: true)], seed: Int64(seed))
                let a = e.actor("bot")!
                a.position = V(0.6, 0.6)
                a.nextBotThink = 0.0
                e.tick(0.001)
                guard let choice = a.botChoice else {
                    XCTFail("\(id) \(seed): no choice")
                    continue
                }
                if a.choices.first(where: { $0.index == choice })?.text == a.question?.answer { correct += 1 }
                for _ in 0..<5 {
                    e.tick(0.001)
                    XCTAssertEqual(a.botChoice, choice)
                }
            }
            XCTAssertEqual(Double(correct) / 3500.0, Double(Characters.get(id).qualities.knowledge) / 7.0, accuracy: 0.03, id)
        }
    }

    func testLowRatingsRemainValidAndHumansDoNotUseBotKnowledge() {
        for rating in 1...5 { XCTAssertEqual(HouseSkills(3, 3, 3, 3, rating).correctAnswerProbability, Double(rating) / 7.0) }
        let e = SplashEngine(members: [Member("a", "minik"), Member("b", "miniko")], seed: 4)
        for _ in 0..<80 { e.tick(0.05) }
        XCTAssertTrue(e.actors.allSatisfy { $0.botChoice == nil && $0.held == nil })
    }
}

/// Port of Android core/PresentationFeelTest.kt: Standard aiming, Hard swipes, running and braking.
final class PresentationFeelTests: XCTestCase {
    private func engine() -> SplashEngine {
        var config = SplashConfig()
        config.duration = 600.0
        let e = SplashEngine(members: [Member("u", "mia"), Member("v", "minik")], config: config)
        e.practice = true
        e.actor("u")?.position = V(2.0, 4.0)
        e.actor("v")?.position = V(2.0, 18.0)
        return e
    }

    func testStandardTargetUsesPointAndAvatarPower() {
        let e = engine()
        let a = e.actor("u")!
        a.held = correctChoice(a)
        e.command("u", "aim", .aim(V(9.0, 0.0)))
        e.command("u", "throw", .throwBalloon)
        XCTAssertEqual(e.shots.count, 1)
        guard let shot = e.shots.first else { return }
        XCTAssertEqual(shot.velocity.length(), e.config.throwSpeed * Characters.get("mia").qualities.throwFactor, accuracy: 1e-6)
        let t = (9 - 0.42) / shot.velocity.length()
        let h = shot.height + shot.vz * t - 0.5 * e.config.gravity * t * t
        XCTAssertEqual(h, 0.65, accuracy: 1e-6)
        XCTAssertGreaterThan(shot.velocity.x, 0)
        XCTAssertEqual(shot.velocity.y, 0.0, accuracy: 1e-6)
    }

    func testStandardFarTargetsStayReachableForLowPowerAvatars() {
        for distance in [9.0, 35.0, 55.0] {
            for speed in [5.0, 7.8] {
                let t = (distance - 0.42) / speed
                let lift = PlayFeel.lift(distance, speed, 1.15, 2.6)
                XCTAssertEqual(1.15 + lift * t - 1.3 * t * t, 0.65, accuracy: 1e-6)
            }
        }
    }

    func testFasterHardSwipeActuallyThrowsFaster() {
        func speed(_ power: Double) -> Double {
            let e = engine()
            let a = e.actor("u")!
            a.settings.throwing = .standard
            a.held = correctChoice(a)
            e.command("u", "aim", .aim(V(power, 0.0)))
            e.command("u", "throw", .throwBalloon)
            XCTAssertEqual(e.shots.count, 1)
            return e.shots.first?.velocity.length() ?? 0
        }
        XCTAssertGreaterThan(speed(PlayFeel.powerFromSwipe(1500.0)), speed(PlayFeel.powerFromSwipe(100.0)) * 1.7)
    }

    func testSustainedTravelRunsAndReleaseBrakes() {
        let e = engine()
        let a = e.actor("u")!
        e.command("u", "move", .move(V(1.0, 0.0)))
        for _ in 0..<140 { e.tick(0.02) }
        XCTAssertGreaterThan(a.travelDistance, PlayFeel.runAfterDistance)
        XCTAssertGreaterThan(a.velocity.length(), e.config.moveSpeed * 1.2)
        let before = a.position
        e.command("u", "stop", .move(V(0.0, 0.0)))
        e.tick(0.03)
        XCTAssertGreaterThan(a.velocity.length(), 0)
        for _ in 0..<30 { e.tick(0.02) }
        XCTAssertEqual(a.velocity.length(), 0.0, accuracy: 1e-6)
        XCTAssertLessThan((a.position - before).length(), 1.3)
    }

    func testRotatedCameraAndPointerCoordinatesRoundTrip() {
        for yaw in [0.0, 0.7, 1.57, 3.14, 4.7, 6.2] {
            for size in [(1080, 2200), (2200, 1080)] {
                let c = ArenaCamera(12.0, 12.0, distance: 38.0, yaw: yaw)
                let point = c.project(13.0, 16.0, 0.0, size.0, size.1)
                let back = c.ground(point.x, point.y, size.0, size.1)
                XCTAssertEqual(back.x, 13.0, accuracy: 0.0001)
                XCTAssertEqual(back.y, 16.0, accuracy: 0.0001)
            }
        }
    }

    func testRankThresholdsStayOrderedAndReachGold() {
        XCTAssertEqual(SplashRanks.at(0).en, "White")
        XCTAssertEqual(SplashRanks.at(100).en, "Yellow")
        XCTAssertEqual(SplashRanks.at(18000).en, "Gold")
        XCTAssertTrue(zip(SplashRanks.all, SplashRanks.all.dropFirst()).allSatisfy { $0.0.threshold < $0.1.threshold })
    }

    func testMovementAndPowerSurviveCheckpoint() {
        let e = engine()
        let a = e.actor("u")!
        a.velocity = V(2.0, 1.0)
        a.runBlend = 0.7
        a.throwPower = 1.3
        a.aimDistance = 8.0
        let saved = WorldCodec.checkpoint(e)
        let other = engine()
        WorldCodec.restore(other, saved)
        XCTAssertEqual(other.actor("u")?.velocity, a.velocity)
        XCTAssertEqual(other.actor("u")?.throwPower ?? 0, 1.3, accuracy: 0.0001)
    }

    func testWideNearbyBalloonsStayValidNearEveryCorner() {
        for seed in 0...99 {
            for x in [0.8, 10.0, 19.2] {
                for y in [0.8, 10.0, 19.2] {
                    let points = GroundBalloons.place(20.0, 20.0, V(x, y), true, 3.6, KotlinRandom(seed: Int64(seed)))
                    XCTAssertEqual(points.count, 4)
                    for i in points.indices {
                        for j in 0..<i { XCTAssertGreaterThanOrEqual((points[i] - points[j]).length(), 3.2 - 1e-9) }
                    }
                }
            }
        }
    }
}

/// Ports of Android core/RoomInputPolicyTest.kt and core/RosterArrivalTest.kt.
final class RoomPolicyTests: XCTestCase {
    func testFinishedMetadataStopsCommandsBeforeDelayedSnapshot() { XCTAssertFalse(RoomInputPolicy.accepts("finished", false, false)) }
    func testStoredReceiptStopsCommandsBeforeMetadata() { XCTAssertFalse(RoomInputPolicy.accepts("playing", false, true)) }
    func testLocalResultStopsCommandsBeforeBothRemoteSignals() { XCTAssertFalse(RoomInputPolicy.accepts("playing", true, false)) }

    func testNextRoundMaySendAgainAfterReset() {
        XCTAssertTrue(RoomInputPolicy.accepts("playing", false, false))
        XCTAssertFalse(RoomInputPolicy.accepts("lobby", false, false))
    }

    func testPhaseBeforeRosterDoesNotConstructAnIncompleteWorld() {
        XCTAssertFalse(LobbyPlan.readyRoster([0, 1], true, 6))
        XCTAssertFalse(LobbyPlan.readyRoster([0, 0, 1, 1], true, 6))
        XCTAssertTrue(LobbyPlan.readyRoster([0, 0, 0, 1, 1, 1], true, 6))
    }

    func testSoloAlsoWaitsForAnnouncedRoster() {
        XCTAssertFalse(LobbyPlan.readyRoster([0, 0], false, 6))
        XCTAssertTrue(LobbyPlan.readyRoster([0, 0, 0, 0, 0, 0], false, 6))
    }
}

/// Ports of Android world/ArenaCameraTest.kt and world/StableLabelsTest.kt.
final class ArenaViewGeometryTests: XCTestCase {
    func testTouchProjectionMatchesWorldAtEveryCamera() {
        for size in [(1080, 2160), (1080, 2400), (720, 1280)] {
            for d in [20.0, 26.0, 40.0] {
                for x in [1.0, 10.0, 25.0] {
                    for y in [1.0, 12.0, 26.0] {
                        let c = ArenaCamera(14.0, 14.0, distance: d)
                        let p = c.project(x, y, 0.0, size.0, size.1)
                        let q = c.ground(p.x, p.y, size.0, size.1)
                        XCTAssertEqual(q.x, x, accuracy: 0.0001)
                        XCTAssertEqual(q.y, y, accuracy: 0.0001)
                    }
                }
            }
        }
    }

    func testSmoothCameraConvergesWithoutOvershoot() {
        var c = ArenaCamera(0.0, 0.0)
        var target = c
        target.x = 12.0
        target.y = 20.0
        target.distance = 22.0
        for _ in 0..<600 {
            c = c.toward(target, 1.0 / 60)
            XCTAssertTrue(c.x <= 12 && c.y <= 20)
        }
        XCTAssertEqual(c.x, 12.0, accuracy: 0.001)
    }

    func testExpandedArenaKeepsAnswerFacesBelowPortraitInsetAtEveryYaw() {
        let points = [GroundPoint(1.2, 1.2), GroundPoint(34.8, 2.0), GroundPoint(2.0, 34.8), GroundPoint(34.0, 34.0), GroundPoint(18.0, 30.0)]
        for yaw in [0.0, 0.7, 1.57, 3.14, 4.7] {
            for size in [(1080, 1951), (1080, 2209), (2209, 1080)] {
                let portrait = size.1 > size.0
                let c = ArenaCamera(18.0, 18.0, centerY: portrait ? 0.68 : 0.61, yaw: yaw).frameGround(points, size.0, size.1, 0.0)
                for point in points {
                    let p = c.project(point.x, point.y, 0.0, size.0, size.1)
                    let px = Double(p.x)
                    let py = Double(p.y)
                    XCTAssertTrue(px >= Double(size.0) * 0.10 && px <= Double(size.0) * 0.90)
                    XCTAssertTrue(py >= Double(size.1) * (portrait ? 0.48 : 0.38) && py <= Double(size.1) * 0.80)
                }
            }
        }
    }

    func testUnchangedSceneDoesNotOscillateBetweenSlots() {
        let l = StableLabels()
        let bounds = LabelBox(0, 0, 400, 650)
        let bodies = [LabelBox(130, 250, 90, 150), LabelBox(185, 350, 85, 140)]
        var first: [LabelBox]? = nil
        for _ in 0..<500 {
            var used: [LabelBox] = []
            for i in 0...5 {
                used.append(l.place("p\(i)", 170 + Float(i) * 7, 385 + Float(i) * 10, 70, 22, bounds, bodies, used, 24))
            }
            if let first = first {
                XCTAssertEqual(first, used)
            } else {
                first = used
            }
        }
    }

    func testTinyMotionKeepsPreviousSlotAndEdgeTargetsRemainTouchable() {
        let l = StableLabels()
        let b = LabelBox(8, 100, 380, 500)
        let a = l.place("a", 200, 300, 80, 24, b, [LabelBox(160, 295, 100, 50)], [], 24)
        let next = l.place("a", 200.1, 300.1, 80, 24, b, [], [], 24)
        XCTAssertEqual(next.x, a.x + 0.1, accuracy: 0.02)
        XCTAssertEqual(next.y, a.y + 0.1, accuracy: 0.02)
        let edge = l.place("far", -2000, 2500, 80, 24, b, [], [], 24)
        XCTAssertTrue(edge.x >= b.x && edge.right <= b.right && edge.y >= b.y && edge.bottom <= b.bottom)
    }
}

/// Port of Android localization/PresentationLanguageTest.kt.
final class PresentationLanguageTests: XCTestCase {
    func testRecentControlsAndCameraHintsResolveForEverySupportedTranslation() {
        let old = AppText.language
        defer { AppText.configure(old) }
        let keys = ["Your question", "Your colour ranks", "Game orientation", "Hard · aim the arc; swipe for power", "Standard · tap anywhere to throw",
                    "Action view · switch", "Choose a player", "Learn to play with Minik", "Learn to play with Mia"]
        for lang in ["es", "ar", "hi", "nl"] {
            AppText.configure(lang)
            for key in keys {
                let translated = AppText.t(key)
                XCTAssertFalse(translated.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, "Empty \(lang): \(key)")
                XCTAssertNotEqual(translated, key, "English fallback in \(lang): \(key)")
            }
        }
    }
}
