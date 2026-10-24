import XCTest
@testable import MinikSplash

/// The wide court and the Paint walls rules of Android 2026-10-15/17 against golden vectors from the
/// real Android core (AndroidPaintWallsGolden.swift).
final class PaintWallsGoldenTests: XCTestCase {
    private func rows(_ tag: String) -> [[String]] {
        return AndroidGolden.rows(AndroidPaintWallsGolden.data)
            .map { $0.components(separatedBy: "|") }
            .filter { $0.first == tag }
    }

    private func number(_ text: String, file: StaticString = #filePath, line: UInt = #line) -> Double {
        guard let value = Double(text) else {
            XCTFail("not a number: \(text)", file: file, line: line)
            return .nan
        }
        return value
    }

    private func points(_ text: String) -> [V] {
        if text.isEmpty { return [] }
        return text.components(separatedBy: ";").map { pair in
            let p = pair.components(separatedBy: ",")
            return V(number(p[0]), number(p[1]))
        }
    }

    func testAnswerPlacementMatchesAndroidIncludingSideWallStrip() {
        let cases = rows("BAL")
        XCTAssertEqual(cases.count, 2 * 3 * 3 * 2 * 3)
        for f in cases {
            let width = number(f[1])
            let depth = number(f[2])
            let seed = Int64(f[3]) ?? -1
            let origin = V(number(f[4]), number(f[5]))
            let placed = GroundBalloons.place(width, depth, origin, f[6] == "true", 3.6, KotlinRandom(seed: seed), f[7] == "true", f[8] == "true")
            let expected = points(f[9])
            XCTAssertEqual(placed.count, expected.count, f.joined(separator: "|"))
            for (a, b) in zip(placed, expected) {
                XCTAssertEqual(a.x, b.x, accuracy: 1e-12, f.joined(separator: "|"))
                XCTAssertEqual(a.y, b.y, accuracy: 1e-12, f.joined(separator: "|"))
            }
        }
    }

    func testSplatsCellsAndEdgeWallsMatchAndroid() {
        var config = SplashConfig()
        config.wallBattle = true
        let s = PaintSession(config, false)
        s.walls[1].cells[3] = 0
        let hits: [(Int, Double, Double, Int, Bool, Double, Double)] = [
            (1, 0.5, 0.5, 0, false, 7.8, 0.0), (1, 0.2, 0.7, 0, false, 5.1, -2.3), (0, 0.6, 0.3, 1, false, 9.4, 1.7),
            (1, 0.5, 0.5, 0, true, 7.0, -0.5), (0, 0.9, 0.1, 1, true, 3.0, 4.0), (0, 0.4, 0.4, 0, false, 7.8, 0.0),
        ]
        for h in hits { s.hit(h.0, h.1, h.2, h.3, true, erase: h.4, impactSpeed: h.5, impactSlope: h.6) }
        for f in rows("SPLATS") {
            let wall = s.walls[Int(f[1])!]
            let expected = f[2].components(separatedBy: ";").map { $0.components(separatedBy: ",") }
            XCTAssertEqual(wall.splats.count, expected.count, "wall \(wall.id)")
            for (splat, e) in zip(wall.splats, expected) {
                XCTAssertEqual(splat.u, number(e[0]), accuracy: 1e-12)
                XCTAssertEqual(splat.v, number(e[1]), accuracy: 1e-12)
                XCTAssertEqual(splat.team, Int(e[2]))
                XCTAssertEqual(splat.radius, number(e[3]), accuracy: 1e-12)
                XCTAssertEqual(splat.stretch, number(e[4]), accuracy: 1e-12)
                XCTAssertEqual(splat.angle, number(e[5]), accuracy: 1e-9)
            }
        }
        for f in rows("CELLS") {
            XCTAssertEqual(s.walls[Int(f[1])!].cells, f[2].components(separatedBy: ",").map { Int($0)! }, "wall \(f[1])")
        }
        let score = rows("SCORE")[0]
        XCTAssertEqual(s.score(0), Int(score[1]))
        XCTAssertEqual(s.score(1), Int(score[2]))
        for f in rows("WALL") {
            let wall = s.walls[Int(f[1])!]
            XCTAssertEqual(wall.line, number(f[2]), accuracy: 1e-12)
            XCTAssertEqual(wall.span, number(f[3]), accuracy: 1e-12)
            XCTAssertEqual(wall.height, number(f[4]), accuracy: 1e-12)
            XCTAssertEqual(wall.alongY, f[5] == "true")
            XCTAssertEqual(wall.world(0.3, 0.6).x, number(f[6]), accuracy: 1e-12)
            XCTAssertEqual(wall.world(0.3, 0.6).y, number(f[7]), accuracy: 1e-12)
            XCTAssertEqual(wall.uv(7.0, 3.5).x, number(f[8]), accuracy: 1e-12)
            XCTAssertEqual(wall.uv(7.0, 3.5).y, number(f[9]), accuracy: 1e-12)
        }
    }

    func testAvatarJumpWalkAndFloatTimingMatchAndroid() {
        let six = Array(Characters.all.prefix(6)).enumerated().map { pair in
            Member("h\(pair.offset)", pair.element.id, settings: PlayerSettings(arena: .andromeda))
        }
        let e = SplashEngine(members: six)
        let abilities = rows("ABILITY")
        XCTAssertEqual(abilities.count, Characters.all.count)
        for f in abilities {
            let beach = SplashEngine(members: [Member("child", f[1]), Member("other", "miniko", bot: true)]).actor("child")!
            let moon = SplashEngine(members: [Member("child", f[1], settings: PlayerSettings(arena: .andromeda)),
                                              Member("other", "miniko", bot: true)]).actor("child")!
            XCTAssertEqual(e.characterJumpSpeed(beach), number(f[2]), accuracy: 1e-12, f[1])
            XCTAssertEqual(e.characterJumpSpeed(moon), number(f[3]), accuracy: 1e-12, f[1])
            XCTAssertEqual(e.movementSpeed(beach), number(f[4]), accuracy: 1e-12, f[1])
        }
        for f in rows("FLOAT") {
            XCTAssertEqual(SplashActor(member: Member(f[1], "miniko"), position: V(0, 0)).nextFloatAt, number(f[2]), f[1])
        }
        for f in rows("POS") {
            let n = Int(f[1])!
            let members = (0..<n).map { Member("p\($0)", Characters.all[$0].id, team: $0 < n / 2 ? 0 : 1, bot: $0 != 0) }
            var config = SplashConfig()
            config.wallBattle = true
            let wall = SplashEngine(members: members, mode: .teams, seed: 5, config: config)
            let expected = points(f[2])
            XCTAssertEqual(wall.actors.count, expected.count)
            for (a, p) in zip(wall.actors, expected) {
                XCTAssertEqual(a.position.x, p.x, accuracy: 1e-12)
                XCTAssertEqual(a.position.y, p.y, accuracy: 1e-12)
            }
        }
    }

    private func check(_ tag: String, _ e: SplashEngine, _ f: [String]) {
        let at = tag + " t=" + f[1]
        XCTAssertEqual(e.time, number(f[1]), accuracy: 1e-9, at)
        XCTAssertEqual(e.teamScores.map { String($0) }.joined(separator: ","), f[2], at)
        XCTAssertEqual(e.paintSession.score(0), Int(f[3]), at)
        XCTAssertEqual(e.paintSession.score(1), Int(f[4]), at)
        XCTAssertEqual(e.paintSession.walls.map { String($0.splats.count) }.joined(separator: ","), f[5], at)
        XCTAssertEqual(e.shots.count, Int(f[6]), at)
        XCTAssertEqual(e.bursts.count, Int(f[7]), at)
        XCTAssertEqual(e.result.map { $0.winners.joined(separator: ",") } ?? "-", f[8], at)
        let actors = f[9].components(separatedBy: ";").map { $0.components(separatedBy: ",") }
        XCTAssertEqual(e.actors.count, actors.count, at)
        for (a, x) in zip(e.actors, actors) {
            let who = at + " " + x[0]
            XCTAssertEqual(a.member.id, x[0], who)
            XCTAssertEqual(a.position.x, number(x[1]), accuracy: 1e-7, who)
            XCTAssertEqual(a.position.y, number(x[2]), accuracy: 1e-7, who)
            XCTAssertEqual(a.height, number(x[3]), accuracy: 1e-7, who)
            XCTAssertEqual(a.sequence, Int(x[4]), who)
            XCTAssertEqual(a.score, Int(x[5]), who)
            XCTAssertEqual(a.hits, Int(x[6]), who)
            XCTAssertEqual(a.floatCount, Int(x[7]), who)
            XCTAssertEqual(a.held.map { String($0) } ?? "null", x[8], who)
        }
    }

    /// Whole Paint walls matches of house players on the 40 x 24 court: answers in the middle strip,
    /// white paint, splats, the edge walls, the "3 hits · rest" rule and Andromeda's floating steps.
    func testPaintWallsMatchesFollowAndroidTickForTick() {
        for (arena, seed) in [(Arena.andromeda, Int64(12)), (Arena.beach, Int64(3))] {
            let tag = "WALLSIM-" + arena.name
            let expected = rows(tag)
            XCTAssertEqual(expected.count, 6, tag)
            let settings = PlayerSettings(arena: arena, balloons: .allOver)
            let members = [Member("you", "mia", team: 0, bot: true, settings: settings), Member("minik", "minik", team: 0, bot: true, settings: settings),
                           Member("miniko", "miniko", team: 1, bot: true, settings: settings), Member("flare", "flare", team: 1, bot: true, settings: settings)]
            var config = SplashConfig()
            config.wallBattle = true
            config.duration = 305.0
            config.hitEffect = .rest
            let e = SplashEngine(members: members, mode: .teams, seed: seed, config: config)
            e.restoreQuestionSecret(seed)
            for a in e.actors { e.loadProfile(a.member.id, LearningProfile()) }
            var next = 0
            for i in 1...900 {
                e.tick(0.1)
                if i % 150 == 0 && next < expected.count {
                    check(tag, e, expected[next])
                    next += 1
                }
            }
        }
    }

    /// A solo battle of six house players on the default 40 x 24 Andromeda court.
    func testWideSoloMatchFollowsAndroidTickForTick() {
        let expected = rows("SOLOSIM")
        XCTAssertEqual(expected.count, 6)
        let members = (0..<6).map { Member("p\($0)", Characters.all[$0].id, team: 0, bot: true, settings: PlayerSettings(arena: .andromeda)) }
        let e = SplashEngine(members: members, mode: .solo, seed: 77, config: SplashConfig())
        e.restoreQuestionSecret(77)
        for a in e.actors { e.loadProfile(a.member.id, LearningProfile()) }
        var next = 0
        for i in 1...900 {
            e.tick(0.1)
            if i % 150 == 0 && next < expected.count {
                check("SOLOSIM", e, expected[next])
                next += 1
            }
        }
    }

    func testOnlineRoomsKeepTheTwentyByTwentyCourtAndCodecAcceptsTheWideOne() {
        let room = OnlineSession.roomConfig(wallBattle: true, hitEffect: .slow)
        XCTAssertEqual(room.width, 20.0)
        XCTAssertEqual(room.depth, 20.0)
        XCTAssertTrue(room.wallBattle)
        XCTAssertEqual(room.hitEffect, .slow)
        let wide = SplashConfig()
        XCTAssertEqual(wide.width, 40.0)
        XCTAssertEqual(wide.depth, 24.0)
        let decoded = WorldCodec.config(WorldCodec.config(wide))
        XCTAssertEqual(decoded.width, 40.0)
        XCTAssertEqual(decoded.depth, 24.0)
        var huge = SplashConfig()
        huge.width = 90.0
        XCTAssertEqual(WorldCodec.config(WorldCodec.config(huge)).width, 64.0)
    }

    func testSharedSnapshotCarriesSplatsAndWhitePaintToReplicas() {
        var config = SplashConfig()
        config.wallBattle = true
        let members = (0...3).map { Member("p\($0)", Characters.all[$0].id, team: $0 / 2) }
        let e = SplashEngine(members: members, mode: .teams, seed: 9, config: config)
        e.paintSession.hit(1, 0.4, 0.6, 0, true, impactSpeed: 6.5, impactSlope: -1.2)
        e.shots.append(Shot(id: "w", owner: "p0", questionId: "q", answer: "a", explanation: "", color: 2, position: V(10, 10), height: 1,
                            velocity: V(1, 0), vz: 0, whitePaint: true))
        let replica = SplashEngine(members: members, mode: .teams, seed: 9, config: config)
        WorldCodec.applyShared(replica, WorldCodec.shared(e))
        XCTAssertEqual(replica.paintSession.walls[1].splats, e.paintSession.walls[1].splats)
        XCTAssertEqual(replica.paintSession.walls[1].cells, e.paintSession.walls[1].cells)
        XCTAssertEqual(replica.shots.first?.whitePaint, true)
        // Settings always travel with a court.
        var s = PlayerSettings()
        s.court = false
        XCTAssertEqual(WorldCodec.settings(s)["court"] as? Bool, true)
        XCTAssertTrue(WorldCodec.settings(WorldCodec.settings(s)).court)
    }
}

/// Port of Android core/PaintWallActiveMatchTest.kt.
final class PaintWallActiveMatchTests: XCTestCase {
    private func match(_ seed: Int64 = 12, _ arena: Arena = .andromeda) -> SplashEngine {
        let settings = PlayerSettings(arena: arena, balloons: .allOver)
        let members = [Member("you", "mia", team: 0, settings: settings), Member("minik", "minik", team: 0, bot: true, settings: settings),
                       Member("miniko", "miniko", team: 1, bot: true, settings: settings), Member("flare", "flare", team: 1, bot: true, settings: settings)]
        var config = SplashConfig()
        config.wallBattle = true
        config.duration = 305.0
        let e = SplashEngine(members: members, mode: .teams, seed: seed, config: config)
        e.restoreQuestionSecret(seed)
        for a in e.actors { e.loadProfile(a.member.id, LearningProfile()) }
        return e
    }

    func testBotsCanCollectAnswersBeyondTheOldEndWallBoundary() {
        for y in [1.0, 23.0] {
            let e = match()
            let a = e.actor("flare")!
            a.position = V(20.0, y < 12 ? 4.0 : 20.0)
            for (i, other) in e.actors.filter({ $0 !== a }).enumerated() {
                other.position = V(5.0 + Double(i) * 3, 12.0)
                other.nextBotThink = 999.0
            }
            let answer = a.choices.first { $0.text == a.question?.answer }!
            a.choices = a.choices.map { $0.index == answer.index ? Choice(index: $0.index, text: $0.text, position: V(20.0, y), color: $0.color) : $0 }
            a.botChoice = answer.index
            a.nextBotThink = 0.0
            let initial = a.sequence
            for _ in 0..<150 { e.tick(0.1) }
            XCTAssertGreaterThan(a.sequence, initial, "Flare cannot collect y=\(y); at=\(a.position)")
        }
    }

    func testEveryBotKeepsPlayingThroughTheLastMinuteOfFiveMinuteMatches() {
        for arena in [Arena.beach, .andromeda] {
            for seed in Int64(1)...Int64(6) {
                let e = match(seed, arena)
                let bots = e.actors.filter { $0.member.bot }
                var progress: [String: Int] = [:]
                var lastProgress: [String: Double] = [:]
                for a in bots {
                    progress[a.member.id] = 1
                    lastProgress[a.member.id] = 0.0
                }
                for _ in 0..<3000 {
                    e.tick(0.1)
                    for a in bots {
                        if a.sequence != progress[a.member.id] {
                            progress[a.member.id] = a.sequence
                            lastProgress[a.member.id] = e.time
                        }
                        if e.result == nil && e.time - lastProgress[a.member.id]! >= 60.0 {
                            XCTFail("\(arena.name) seed=\(seed) \(a.member.id) stalled at t=\(e.time), pos=\(a.position)")
                            return
                        }
                    }
                }
                XCTAssertTrue(e.time > 240 || e.result != nil, "Unexpected early finish \(e.time)")
                for a in bots { XCTAssertGreaterThan(a.sequence, 4, "\(a.member.id) only completed \(a.sequence - 1) questions") }
            }
        }
    }
}

/// Port of Android core/PaintWallBalloonPlacementTest.kt.
final class PaintWallBalloonPlacementTests: XCTestCase {
    func testFourDistinctReachableAnswersClearBothSideWalls() {
        for seed in 0...59 {
            for x in [0.8, 20.0, 39.2] {
                for y in [0.8, 12.0, 23.2] {
                    for nearby in [false, true] {
                        let points = GroundBalloons.place(40.0, 24.0, V(x, y), nearby, 3.6, KotlinRandom(seed: Int64(seed)), true, true)
                        XCTAssertEqual(points.count, 4)
                        for p in points {
                            XCTAssertTrue(p.x >= 10.5 && p.x <= 29.5, "Answer behind side wall: \(p)")
                            XCTAssertTrue(p.y >= 0.7 && p.y <= 23.3)
                        }
                        let gap = nearby ? 3.2 : 24.0 * 0.22
                        for i in points.indices {
                            for j in 0..<i { XCTAssertGreaterThanOrEqual((points[i] - points[j]).length(), gap - 1e-9) }
                        }
                    }
                }
            }
        }
    }
}
