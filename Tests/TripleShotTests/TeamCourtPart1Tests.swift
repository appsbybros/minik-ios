import XCTest
@testable import MinikTripleShot

// Area w-team1: TripleShotTeamCourtView part 1 (Kotlin view/TripleShotTeamCourtView.kt L1-2327, spec 11-team1).
// Everything here runs without a GPU frame: the court is created and laid out but never attached, so the 32 ms AI
// tick and View.postDelayed runnables stay in the view's run queue, while postAction (a main-looper Handler) and the
// ball animator run on AndroidKitTestLoop's fake clock. gpuWorld.project/actorBounds/screenGround return nil before
// the first Metal frame, exactly like Android before the first GL frame, so the Kotlin fallbacks are exercised.
//
// Golden values marked "JVM" were printed by work/w-team1/golden/src/TeamGolden.kt, which holds the Kotlin functions
// copied verbatim from the Android file (role scores, assignTeamRoles, roleHomeSpot, rebuildDefensiveAssignments,
// the shotChance formula and updateDribbleRhythm) compiled with kotlinc 2.3.21 against model/TripleShotCharacters.kt.
// The acceptance invariants come from the Android device tests listed in spec 11 section 8.4.

private typealias Court = TripleShotTeamCourtView
private typealias Team = TripleShotTeamCourtView.Team
private typealias Role = TripleShotTeamCourtView.TeamRole

private final class RecordingTeamListener: TripleShotTeamCourtView.Listener {
    var baskets: [(Team, Int)] = []
    var possessions: [Team] = []
    var statuses: [(String, Team?)] = []
    var shotQualities: [(Int, Bool)] = []
    var deadBalls: [Team] = []
    var guidances: [TripleShotTeamCourtView.HumanGuidance] = []
    var shotClocks: [Int] = []
    var liveTimes: [Int64] = []

    func onTeamBasket(team: Team, points: Int) { baskets.append((team, points)) }
    func onPossessionChanged(team: Team) { possessions.append(team) }
    func onStatus(message: String, team: Team?) { statuses.append((message, team)) }
    func onShotQuality(percent: Int, visible: Bool) { shotQualities.append((percent, visible)) }
    func onDeadBall(defaultNextTeam: Team) { deadBalls.append(defaultNextTeam) }
    func onHumanGuidanceChanged(guidance: TripleShotTeamCourtView.HumanGuidance) { guidances.append(guidance) }
    func onShotClock(seconds: Int) { shotClocks.append(seconds) }
    func onLiveTime(milliseconds: Int64) { liveTimes.append(milliseconds) }
}

/// A listener that relies on the protocol-extension defaults of the three optional callbacks.
private final class MinimalTeamListener: TripleShotTeamCourtView.Listener {
    var statuses: [String] = []
    func onTeamBasket(team: Team, points: Int) {}
    func onPossessionChanged(team: Team) {}
    func onStatus(message: String, team: Team?) { statuses.append(message) }
    func onShotQuality(percent: Int, visible: Bool) {}
    func onDeadBall(defaultNextTeam: Team) {}
}

final class TeamCourtPart1Tests: XCTestCase {
    private let T0: Int64 = 1_000_000_000_000

    override func setUp() {
        super.setUp()
        AndroidKitTestLoop.frameIntervalNanos = 16_666_667
        AndroidKitTestLoop.install(startNanos: T0)
    }

    override func tearDown() {
        AndroidKitTestLoop.uninstall()
        super.tearDown()
    }

    // MARK: - Helpers

    private func makeCourt(teamSize: Int, humans: [String], opponents: [String], seed: Int64 = 7,
                           court courtId: String = "sunset_pulse", width: Int = 2000, height: Int = 1000,
                           layout: Bool = true) -> Court {
        let court = Court()
        court.setCourtStyle(style: TripleShotCourtCatalog.find(id: courtId))
        if layout {
            court.measure(AMeasureSpec.makeMeasureSpec(width, AMeasureSpec.EXACTLY),
                          AMeasureSpec.makeMeasureSpec(height, AMeasureSpec.EXACTLY))
            court.layout(0, 0, width, height)
        }
        court.configure(teamSize: teamSize, humanCharacterId: humans[0], teammateCharacterIds: Array(humans.dropFirst()),
                        opponentCharacterIds: opponents, seed: seed)
        return court
    }

    private func roster1(seed: Int64 = 7) -> Court {
        return makeCourt(teamSize: 2, humans: ["woman_dark", "coach_67"], opponents: ["nova", "flare"], seed: seed)
    }

    private func roster2(seed: Int64 = 7) -> Court {
        return makeCourt(teamSize: 3, humans: ["woman_dark", "coach_67", "zephyr"],
                         opponents: ["nova", "flare", "woman_dark"], seed: seed)
    }

    private func actor(_ court: Court, _ id: String) -> Court.Actor {
        return court.actors.first(where: { $0.id == id })!
    }

    private func floorMetres(_ dx: Float, _ dy: Float) -> Float {
        return khypot(dx * 0.014, dy * 0.034)
    }

    /// A single-pointer Android event at the current fake time (pointer id 0).
    private func touch(_ action: Int, _ downTime: Int64, _ x: Float, _ y: Float) -> AMotionEvent {
        return AMotionEvent.obtain(downTime, AndroidKitTestLoop.nowMillis, action, x, y, 0)
    }

    /// A multi-pointer Android event (ids in index order) at the current fake time.
    private func touches(_ action: Int, actionIndex: Int, _ downTime: Int64, ids: [Int], xs: [Float], ys: [Float])
        -> AMotionEvent {
        return AMotionEvent.obtainTouch(downTime: downTime, eventTimeNanos: AndroidKitTestLoop.nowNanos,
                                        action: action | (actionIndex << AMotionEvent.ACTION_POINTER_INDEX_SHIFT),
                                        pointerIds: ids, xs: xs, ys: ys, rawXs: xs, rawYs: ys)
    }

    private let hebrewOutOfBounds = "\u{05DE}\u{05D7}\u{05D5}\u{05E5} \u{05DC}\u{05DE}\u{05D2}\u{05E8}\u{05E9}"
    private let hebrewShotClock = "24 \u{05E9}\u{05E0}\u{05D9}\u{05D5}\u{05EA} \u{2014} \u{05D4}\u{05DB}\u{05D3}\u{05D5}\u{05E8} " +
        "\u{05DC}\u{05E7}\u{05D1}\u{05D5}\u{05E6}\u{05D4} \u{05D4}\u{05E9}\u{05E0}\u{05D9}\u{05D9}\u{05D4}"

    // MARK: - Types and enums

    func testEnumsKeepKotlinOrdinalsAndNames() {
        XCTAssertEqual(Team.allCases.map { $0.name }, ["HUMAN", "OPPONENT"])
        XCTAssertEqual(Role.allCases.map { $0.name }, ["POINT_GUARD", "WING", "INTERIOR"])
        XCTAssertEqual(Court.DefenseScheme.allCases.map { $0.name }, ["MAN_TO_MAN", "ZONE"])
        XCTAssertEqual(Court.BallFlightKind.allCases.map { $0.name }, ["NONE", "PASS", "SHOT", "ALLEY_OOP"])
        XCTAssertEqual(Team.named("OPPONENT"), .OPPONENT)
        XCTAssertNil(Team.named("opponent"))
    }

    func testActorDefaultsMatchTheKotlinConstructor() {
        let a = Court.Actor(id: "H0", team: .HUMAN, characterId: "woman_dark",
                            profile: TripleShotCharacterRoster.womanDark, x: 12, y: 34)
        XCTAssertEqual(a.targetX, 12)
        XCTAssertEqual(a.targetY, 34)
        XCTAssertEqual(a.facing, .BACK)
        XCTAssertEqual(a.motion, .IDLE)
        XCTAssertEqual(a.role, .WING)
        XCTAssertEqual(a.dribbleHandSign, 1)
        XCTAssertFalse(a.hasBall)
        XCTAssertFalse(a.controlled)
        XCTAssertNil(a.screenTargetId)
        XCTAssertNil(a.returnPassId)
        XCTAssertEqual(a.boost01, 0)
        // Identity semantics (Kotlin shares one mutable instance everywhere).
        let b = Court.Actor(id: "H0", team: .HUMAN, characterId: "woman_dark",
                            profile: TripleShotCharacterRoster.womanDark, x: 12, y: 34)
        XCTAssertNotEqual(a, b)
        XCTAssertEqual(a, a)
    }

    func testListenerDefaultsAreNoOpsAndOnStatusDefaultsTheTeamToNull() {
        let listener = MinimalTeamListener()
        listener.onShotClock(seconds: 3)
        listener.onLiveTime(milliseconds: 16)
        listener.onHumanGuidanceChanged(guidance: Court.HumanGuidance(role: .WING, matchupName: nil,
                                                                      defenseScheme: .ZONE))
        listener.onStatus(message: "x")
        XCTAssertEqual(listener.statuses, ["x"])
    }

    // MARK: - Court style, hoops and role homes (spec 11 section 4.8)

    func testCourtStyleAcceptsOnlyFullCourtTeamPhotos() {
        let court = Court()
        court.setCourtStyle(style: TripleShotCourtCatalog.find(id: "neon_falls"))
        XCTAssertEqual(court.currentCourtStyleId, "neon_falls")
        XCTAssertEqual(court.topHoop(), Court.HoopGeometry(rimX: 834, rimY: 246, footX: 834, footY: 338))
        XCTAssertEqual(court.bottomHoop(), Court.HoopGeometry(rimX: 834, rimY: 672, footX: 834, footY: 794))
        court.setCourtStyle(style: TripleShotCourtCatalog.find(id: "neon_tide"))
        XCTAssertEqual(court.currentCourtStyleId, "neon_tide")
        XCTAssertEqual(court.topHoop(), Court.HoopGeometry(rimX: 834, rimY: 210, footX: 834, footY: 304))
        court.setCourtStyle(style: TripleShotCourtCatalog.find(id: "frostline"))
        XCTAssertEqual(court.currentCourtStyleId, "sunset_pulse")
        XCTAssertEqual(court.courtAtmosphere, .COLORED_LIGHTS)
        XCTAssertEqual(court.attackingHoop(team: .HUMAN), court.topHoop())
        XCTAssertEqual(court.attackingHoop(team: .OPPONENT), court.bottomHoop())
        XCTAssertEqual(court.defendingHoop(team: .HUMAN), court.bottomHoop())
        XCTAssertEqual(court.towardCenterSign(hoop: court.topHoop()), 1)
        XCTAssertEqual(court.towardCenterSign(hoop: court.bottomHoop()), -1)
    }

    func testRoleHomeSpotsMatchTheSpecTablesForBothCalibrations() {
        let court = Court()
        func check(_ team: Team, _ attacking: Bool, _ expected: [(Float, Float)], file: StaticString = #filePath,
                   line: UInt = #line) {
            for (index, role) in Role.allCases.enumerated() {
                let p = court.roleHomeSpot(team: team, role: role, attacking: attacking)
                XCTAssertEqual(p.x, expected[index].0, "\(team) \(role) x", file: file, line: line)
                XCTAssertEqual(p.y, expected[index].1, "\(team) \(role) y", file: file, line: line)
            }
        }
        court.setCourtStyle(style: TripleShotCourtCatalog.find(id: "sunset_pulse"))
        check(.HUMAN, true, [(834, 589), (629, 509), (999, 424)])
        check(.OPPONENT, false, [(834, 524), (1039, 469), (669, 402)])
        check(.OPPONENT, true, [(834, 473), (1039, 553), (669, 638)])
        check(.HUMAN, false, [(834, 538), (629, 593), (999, 660)])
        court.setCourtStyle(style: TripleShotCourtCatalog.find(id: "neon_falls"))
        check(.HUMAN, true, [(834, 623), (629, 543), (999, 458)])
        check(.OPPONENT, false, [(834, 558), (1039, 503), (669, 436)])
        check(.OPPONENT, true, [(834, 509), (1039, 589), (669, 674)])
        check(.HUMAN, false, [(834, 574), (629, 629), (999, 696)])
    }

    // MARK: - configure: roles, scores and formation (JVM goldens)

    private struct ActorGolden {
        let id: String
        let role: Role
        let x: Float
        let y: Float
        let pg: UInt32
        let wing: UInt32
        let interior: UInt32
        let rebound: UInt32
        let threat: UInt32
        let pass: UInt32
    }

    private func checkGoldens(_ court: Court, _ goldens: [ActorGolden], file: StaticString = #filePath,
                              line: UInt = #line) {
        XCTAssertEqual(court.actors.map { $0.id }, goldens.map { $0.id }, file: file, line: line)
        for g in goldens {
            let a = actor(court, g.id)
            XCTAssertEqual(a.role, g.role, "\(g.id) role", file: file, line: line)
            XCTAssertEqual(a.x, g.x, "\(g.id) x", file: file, line: line)
            XCTAssertEqual(a.y, g.y, "\(g.id) y", file: file, line: line)
            XCTAssertEqual(court.pointGuardRoleScore(actor: a).bitPattern, g.pg, "\(g.id) pg", file: file, line: line)
            XCTAssertEqual(court.wingRoleScore(actor: a).bitPattern, g.wing, "\(g.id) wing", file: file, line: line)
            XCTAssertEqual(court.interiorRoleScore(actor: a).bitPattern, g.interior, "\(g.id) int", file: file, line: line)
            XCTAssertEqual(court.reboundSkillProxy(actor: a).bitPattern, g.rebound, "\(g.id) reb", file: file, line: line)
            XCTAssertEqual(court.interiorThreatScore(actor: a).bitPattern, g.threat, "\(g.id) threat", file: file, line: line)
            XCTAssertEqual(court.passingSkillProxy(actor: a).bitPattern, g.pass, "\(g.id) pass", file: file, line: line)
        }
    }

    func testConfigureTwoOnTwoRolesScoresAndFormation() {
        let court = roster1()
        checkGoldens(court, [
            ActorGolden(id: "H0", role: .POINT_GUARD, x: 834, y: 589, pg: 0x42aa2389, wing: 0x42a88a3e,
                        interior: 0x428a7ae1, rebound: 0x3f3a1cad, threat: 0x3f3c01a4, pass: 0x3f60b780),
            ActorGolden(id: "H1", role: .INTERIOR, x: 999, y: 424, pg: 0x4269f973, wing: 0x42858a3e,
                        interior: 0x42ac3333, rebound: 0x3f51b08a, threat: 0x3f58793d, pass: 0x3f221965),
            ActorGolden(id: "O0", role: .POINT_GUARD, x: 834, y: 524, pg: 0x42acae7e, wing: 0x42b00a3e,
                        interior: 0x42ac5c29, rebound: 0x3f616f00, threat: 0x3f5eecbf, pass: 0x3f63bcd4),
            ActorGolden(id: "O1", role: .WING, x: 1039, y: 469, pg: 0x42a70795, wing: 0x42a81eb7,
                        interior: 0x42ad3d70, rebound: 0x3f6096bd, threat: 0x3f63f7cf, pass: 0x3f5e1b08),
        ])
        XCTAssertTrue(actor(court, "H0").controlled)
        XCTAssertFalse(actor(court, "H1").controlled)
        XCTAssertEqual(court.activeHumanActorId, "H0")
        XCTAssertNil(court.possession)
        XCTAssertFalse(court.ballVisible)
        XCTAssertEqual(court.teamSize, 2)
        XCTAssertEqual(court.currentBallSkinResId, R.drawable.basketball)
    }

    func testConfigureThreeOnThreeRolesScoresAndFormation() {
        let court = makeCourt(teamSize: 3, humans: ["bob", "rooza", "unicorn_32"],
                              opponents: ["kyra", "ace_23", "buddy_23"])
        checkGoldens(court, [
            ActorGolden(id: "H0", role: .WING, x: 629, y: 509, pg: 0x42798034, wing: 0x4275ae14,
                        interior: 0x42608f5b, rebound: 0x3f164c2f, threat: 0x3f0fd220, pass: 0x3f21e4f8),
            ActorGolden(id: "H1", role: .POINT_GUARD, x: 834, y: 589, pg: 0x42b735a7, wing: 0x42aa0000,
                        interior: 0x428951ec, rebound: 0x3f428241, threat: 0x3f3ced91, pass: 0x3f70068d),
            ActorGolden(id: "H2", role: .INTERIOR, x: 999, y: 424, pg: 0x42692234, wing: 0x4285cccd,
                        interior: 0x42b1c28f, rebound: 0x3f591d14, threat: 0x3f5f1aa0, pass: 0x3f20346e),
            ActorGolden(id: "O0", role: .INTERIOR, x: 669, y: 402, pg: 0x42a79687, wing: 0x42a53d70,
                        interior: 0x42a43d71, rebound: 0x3f58db8d, threat: 0x3f551eb8, pass: 0x3f5ba5e4),
            ActorGolden(id: "O1", role: .WING, x: 1039, y: 469, pg: 0x42b384ea, wing: 0x42b03334,
                        interior: 0x42943d70, rebound: 0x3f491d14, threat: 0x3f4a71df, pass: 0x3f6cd9e8),
            ActorGolden(id: "O2", role: .POINT_GUARD, x: 834, y: 524, pg: 0x42b86a7f, wing: 0x42a24cce,
                        interior: 0x426dae14, rebound: 0x3f3096bb, threat: 0x3f25fd8c, pass: 0x3f6f9db2),
        ])
    }

    func testRoleTiesKeepTheFirstMaximumAndTheWingInteriorMarginOfFour() {
        // zephyr and kyra share the same ratings: the first one (H0) becomes the PG, the other one is a WING because
        // its interior score (0x42a43d71) is not above wing (0x42a53d70) + 4.
        let court = makeCourt(teamSize: 2, humans: ["zephyr", "kyra"], opponents: ["ace_23", "bob"])
        XCTAssertEqual(court.actors.map { $0.role }, [.POINT_GUARD, .WING, .POINT_GUARD, .WING])
        XCTAssertEqual(court.actors.map { $0.x }, [834, 629, 834, 1039])
        XCTAssertEqual(court.actors.map { $0.y }, [589, 509, 524, 469])
    }

    func testConfigurePadsAndTruncatesTheRostersWithWomanDark() {
        let short = makeCourt(teamSize: 3, humans: ["nova"], opponents: ["flare"])
        XCTAssertEqual(short.actors.map { $0.id }, ["H0", "H1", "H2", "O0", "O1", "O2"])
        XCTAssertEqual(short.actors.map { $0.characterId },
                       ["nova", "woman_dark", "woman_dark", "flare", "woman_dark", "woman_dark"])
        let long = makeCourt(teamSize: 7, humans: ["nova", "flare", "kyra", "bob"], opponents: ["ace_23", "zephyr", "bob"])
        XCTAssertEqual(long.teamSize, 3)
        XCTAssertEqual(long.actors.map { $0.characterId }, ["nova", "flare", "kyra", "ace_23", "zephyr", "bob"])
        let unknown = makeCourt(teamSize: 1, humans: ["nobody"], opponents: [])
        XCTAssertEqual(unknown.teamSize, 2)
        XCTAssertEqual(unknown.actors.count, 4)
        XCTAssertEqual(unknown.actors[0].characterId, "nobody")
        XCTAssertEqual(unknown.actors[0].profile, TripleShotCharacterRoster.womanDark)
    }

    // MARK: - Defensive planning (spec 11 section 4.9)

    func testDefensiveAssignmentsAreGreedyAndInsertionOrdered() {
        let court = makeCourt(teamSize: 3, humans: ["bob", "rooza", "unicorn_32"],
                              opponents: ["kyra", "ace_23", "buddy_23"])
        court.rebuildDefensiveAssignments(offenseTeam: .OPPONENT)
        XCTAssertEqual(court.defensiveAssignments.keys, ["H0", "H2", "H1"])           // JVM: H0>O1,H2>O0,H1>O2
        XCTAssertEqual(court.defensiveAssignments.values, ["O1", "O0", "O2"])
        court.rebuildDefensiveAssignments(offenseTeam: .HUMAN)
        XCTAssertEqual(court.defensiveAssignments.keys, ["O0", "O1", "O2"])           // JVM: O0>H2,O1>H0,O2>H1
        XCTAssertEqual(court.defensiveAssignments.values, ["H2", "H0", "H1"])
        let pairs = court.assignmentActors()
        XCTAssertEqual(pairs.keys, ["O0", "O1", "O2"])
        XCTAssertEqual(pairs.values.map { $0.id }, ["H2", "H0", "H1"])

        let three = roster2()
        three.rebuildDefensiveAssignments(offenseTeam: .OPPONENT)
        XCTAssertEqual(three.defensiveAssignments.keys, ["H0", "H2", "H1"])           // JVM: H0>O0,H2>O2,H1>O1
        XCTAssertEqual(three.defensiveAssignments.values, ["O0", "O2", "O1"])
    }

    func testTwoOnTwoAlwaysPlaysManWithoutConsumingARandomDraw() {
        let court = roster1(seed: 12345)
        XCTAssertEqual(court.chooseDefenseScheme(defenseTeam: .OPPONENT, offenseTeam: .HUMAN), .MAN_TO_MAN)
        XCTAssertEqual(court.random.nextInt(), KotlinRandom(seed: Int64(12345)).nextInt())
    }

    func testThreeOnThreeZoneRollUsesTheThreatCounts() {
        // Roster 2: the human offense has one paint threat -> zoneChance 0.24 (JVM ZONE line); bob/rooza/unicorn_32
        // have two paint threats and at most one shooter -> 0.42.
        var sawZone = false
        var sawMan = false
        for seed in Int64(1)...Int64(40) {
            let court = roster2(seed: seed)
            let expectedRoll = KotlinRandom(seed: seed).nextFloat()
            let scheme = court.chooseDefenseScheme(defenseTeam: .OPPONENT, offenseTeam: .HUMAN)
            XCTAssertEqual(scheme, expectedRoll < 0.24 ? .ZONE : .MAN_TO_MAN, "seed \(seed)")
            if scheme == .ZONE { sawZone = true } else { sawMan = true }
            let other = makeCourt(teamSize: 3, humans: ["bob", "rooza", "unicorn_32"],
                                  opponents: ["kyra", "ace_23", "buddy_23"], seed: seed)
            XCTAssertEqual(other.chooseDefenseScheme(defenseTeam: .OPPONENT, offenseTeam: .HUMAN),
                           expectedRoll < 0.42 ? .ZONE : .MAN_TO_MAN, "seed \(seed)")
        }
        XCTAssertTrue(sawZone)
        XCTAssertTrue(sawMan)
    }

    func testHumanGuidanceAlwaysReadsTheH0Assignment() {
        let seed: Int64 = 3
        let court = roster2(seed: seed)
        let listener = RecordingTeamListener()
        court.setListener(listener: listener)
        court.practiceQuiet = true
        court.startPossession(team: .OPPONENT)
        let expectedScheme: Court.DefenseScheme = KotlinRandom(seed: seed).nextFloat() < 0.24 ? .ZONE : .MAN_TO_MAN
        XCTAssertEqual(court.defendingTeam, .HUMAN)
        XCTAssertEqual(court.activeDefenseScheme, expectedScheme)
        XCTAssertEqual(court.defensiveAssignments["H0"], "O0")
        let nova = actor(court, "O0").profile.displayName
        XCTAssertEqual(court.humanGuidance(),
                       Court.HumanGuidance(role: .POINT_GUARD, matchupName: nova, defenseScheme: expectedScheme))
        XCTAssertEqual(listener.guidances.last, court.humanGuidance())

        court.setControlled(id: "H1")
        // The role follows the controlled player; the matchup is still H0's (Android quirk, spec 11 section 8.1 #18).
        XCTAssertEqual(court.humanGuidance(),
                       Court.HumanGuidance(role: .INTERIOR, matchupName: nova, defenseScheme: expectedScheme))
        XCTAssertEqual(listener.guidances.last?.role, .INTERIOR)   // forced notification on a defensive switch
        XCTAssertTrue(actor(court, "H1").controlled)
        XCTAssertFalse(actor(court, "H0").controlled)
    }

    func testHumanGuidancePreviewsTheSameRoleBeforeAnyPlan() {
        let court = roster2()
        let guidance = court.humanGuidance()
        XCTAssertEqual(guidance.role, .POINT_GUARD)
        XCTAssertEqual(guidance.matchupName, actor(court, "O0").profile.displayName)   // first opponent PG
        XCTAssertEqual(guidance.defenseScheme, .MAN_TO_MAN)
    }

    // MARK: - Possessions (spec 11 section 4.1)

    func testHumanPossessionAlwaysStartsWithH0() {
        let court = roster2()
        let listener = RecordingTeamListener()
        court.setListener(listener: listener)
        court.setControlled(id: "H2")
        court.startPossession(team: .HUMAN)
        XCTAssertTrue(actor(court, "H0").hasBall)
        XCTAssertEqual(court.actors.filter { $0.hasBall }.count, 1)
        XCTAssertEqual(court.activeHumanActorId, "H0")
        XCTAssertEqual(court.actors.filter { $0.controlled }.map { $0.id }, ["H0"])
        XCTAssertEqual(actor(court, "H0").facing, .BACK)
        XCTAssertEqual(court.possession, .HUMAN)
        XCTAssertEqual(court.defendingTeam, .OPPONENT)
        XCTAssertEqual(court.trackedHandlerId, "H0")
        XCTAssertEqual(court.possessionStartedAt, court.gameTime())
        XCTAssertTrue(court.ballVisible)
        XCTAssertEqual(listener.possessions, [.HUMAN])
        // Every defender can reach at once (lastStealAttempt pre-armed TEAM_STEAL_RETRY_MS ago).
        for defender in court.actors.filter({ $0.team == .OPPONENT }) {
            XCTAssertEqual(defender.lastStealAttempt, court.gameTime() - 980)
            XCTAssertEqual(defender.screenedUntil, 0)
        }

        court.startPossession(team: .OPPONENT)
        XCTAssertTrue(actor(court, "O0").hasBall)   // nova is the opponent POINT_GUARD
        XCTAssertFalse(actor(court, "H0").hasBall)
        XCTAssertEqual(actor(court, "O0").facing, .FRONT)
        XCTAssertEqual(listener.possessions, [.HUMAN, .OPPONENT])
    }

    func testDeadBallRestartFormationAfterAMadeBasket() {
        let court = roster2()
        court.startPossession(team: .HUMAN, restartFromOwnBaseline: true)
        XCTAssertEqual([actor(court, "H0").x, actor(court, "H0").y], [834, 686])
        XCTAssertEqual([actor(court, "H1").x, actor(court, "H1").y], [679, 608])
        XCTAssertEqual([actor(court, "H2").x, actor(court, "H2").y], [1033, 550])
        XCTAssertEqual(actor(court, "H1").facing, .FRONT)
        XCTAssertEqual(actor(court, "H2").facing, .FRONT)
        XCTAssertEqual(actor(court, "H1").motion, .IDLE)
        // The defense resets to its defending shell at the top basket.
        XCTAssertEqual([actor(court, "O0").x, actor(court, "O0").y], [834, 524])
        XCTAssertEqual([actor(court, "O1").x, actor(court, "O1").y], [669, 402])
        XCTAssertEqual([actor(court, "O2").x, actor(court, "O2").y], [1039, 469])

        court.startPossession(team: .OPPONENT, restartFromOwnBaseline: true)
        XCTAssertEqual([actor(court, "O0").x, actor(court, "O0").y], [834, 376])
        XCTAssertEqual([actor(court, "O1").x, actor(court, "O1").y], [679, 454])
        XCTAssertEqual([actor(court, "O2").x, actor(court, "O2").y], [1033, 512])
        XCTAssertEqual(actor(court, "O1").facing, .BACK)
        XCTAssertEqual(actor(court, "O0").motion, .DRIBBLE)
    }

    func testSizeChangeRestoresTheInitialFormationOnlyWithoutPossession() {
        let court = roster1()
        actor(court, "H0").x = 400
        actor(court, "O1").y = 700
        court.layout(0, 0, 1000, 2000)                       // e.g. a rotation during a question
        XCTAssertEqual([actor(court, "H0").x, actor(court, "H0").y], [834, 589])
        XCTAssertEqual([actor(court, "O1").x, actor(court, "O1").y], [1039, 469])
        court.startPossession(team: .HUMAN)
        actor(court, "H1").x = 2000
        actor(court, "O0").x = 500
        court.layout(0, 0, 2000, 1000)                       // live possession: actors are only clamped
        XCTAssertEqual(actor(court, "H1").x, 1359)
        XCTAssertEqual(actor(court, "O0").x, 500)
    }

    func testClearForQuestionStopsPlayAndInitialisesAnUnsetCamera() {
        let court = makeCourt(teamSize: 2, humans: ["woman_dark"], opponents: ["nova"], layout: false)
        let listener = RecordingTeamListener()
        court.setListener(listener: listener)
        court.startPossession(team: .HUMAN)
        XCTAssertFalse(court.cameraInitialized)   // no size yet: updateCamera is a no-op
        court.clearForQuestion()
        XCTAssertNil(court.possession)
        XCTAssertEqual(court.possessionStartedAt, 0)
        XCTAssertFalse(court.ballVisible)
        XCTAssertTrue(court.actors.allSatisfy { !$0.hasBall && $0.motion == .IDLE })
        XCTAssertTrue(court.cameraInitialized)
        XCTAssertEqual(court.cameraZoom, 2.15)
        XCTAssertEqual(court.cameraCenterX, 836)
        XCTAssertEqual(court.cameraCenterY, 470.5)
        XCTAssertEqual(listener.shotQualities.last?.0, 0)
        XCTAssertEqual(listener.shotQualities.last?.1, false)
    }

    func testSetActorBoostClampsAndSnapshotsFollowActorOrder() {
        let court = roster1()
        court.setActorBoost(actorId: "H0", boost01: 0.9)
        court.setActorBoost(actorId: "O1", boost01: -1)
        court.setActorBoost(actorId: "missing", boost01: 0.2)
        let snapshots = court.actorSnapshots()
        XCTAssertEqual(snapshots.map { $0.id }, ["H0", "H1", "O0", "O1"])
        XCTAssertEqual(snapshots[0], Court.ActorSnapshot(id: "H0", team: .HUMAN, characterId: "woman_dark", sourceX: 834,
                                                         sourceY: 589, hasBall: false, controlled: true, boost01: 0.35))
        XCTAssertEqual(snapshots[3].boost01, 0)
        XCTAssertEqual(court.humanActorIds(), ["H0", "H1"])
        XCTAssertEqual(court.opponentActorIds(), ["O0", "O1"])
    }

    func testPracticeEventsAreDroppedWithoutPossession() {
        let court = roster1()
        var events: [(BasketballSkill, Double)] = []
        court.practiceAction = { skill, amount in events.append((skill, amount)) }
        court.practiceEvent(skill: .PASS)
        XCTAssertTrue(events.isEmpty)
        court.startPossession(team: .HUMAN)
        court.practiceEvent(skill: .PASS)
        court.practiceEvent(skill: .MOVE, amount: 0.25)
        XCTAssertEqual(events.map { $0.0 }, [.PASS, .MOVE])
        XCTAssertEqual(events.map { $0.1 }, [1.0, 0.25])
    }

    // MARK: - Clocks (spec 11 sections 4.1, 4.2, 4.11)

    func testPauseFreezesGameTimeAndResumeContinuesFromTheFrozenValue() {
        let court = roster1()
        let before = court.gameTime()
        court.setMatchPaused(paused: true)
        let frozen = court.gameTime()
        AndroidKitTestLoop.advance(millis: 1200)
        XCTAssertEqual(court.gameTime(), frozen)
        court.setMatchPaused(paused: true)                 // pausing twice keeps the first pause time
        XCTAssertEqual(court.gameTime(), frozen)
        court.setMatchPaused(paused: false)
        XCTAssertLessThan(court.gameTime() - frozen, 100)
        XCTAssertEqual(court.gameTime(), before)           // the fake clock did not move outside the pause
        XCTAssertEqual(court.pausedDuration, 1200)
        XCTAssertEqual(court.lastLiveTick, 0)
        XCTAssertEqual(court.looseLastNanos, 0)
        AndroidKitTestLoop.advance(millis: 40)
        XCTAssertEqual(court.gameTime(), before + 40)
    }

    func testPostActionRunsOnTheGameClockAndWaitsOutPauses() {
        let court = roster1()
        var ran = 0
        court.postAction(action: { ran += 1 }, delay: 100)
        AndroidKitTestLoop.advance(millis: 50)
        court.setMatchPaused(paused: true)
        AndroidKitTestLoop.advance(millis: 1000)            // paused: re-checked every 100 ms, never run
        XCTAssertEqual(ran, 0)
        court.setMatchPaused(paused: false)                 // 50 ms of game time remain
        AndroidKitTestLoop.advance(millis: 49)
        XCTAssertEqual(ran, 0)
        AndroidKitTestLoop.advance(millis: 1)
        XCTAssertEqual(ran, 1)
        AndroidKitTestLoop.advance(millis: 500)
        XCTAssertEqual(ran, 1)
    }

    func testShotClockCountsDownReportsLiveTimeAndExpiresIntoATurnover() {
        let court = roster1()
        let listener = RecordingTeamListener()
        court.setListener(listener: listener)
        court.practiceQuiet = true                          // freezes the AI defenders: nobody steals
        court.startPossession(team: .HUMAN)
        court.updateActors(now: court.gameTime())
        AndroidKitTestLoop.advance(millis: 1000)
        court.updateActors(now: court.gameTime())
        AndroidKitTestLoop.advance(millis: 22_001)
        court.updateActors(now: court.gameTime())
        XCTAssertEqual(listener.shotClocks, [24, 23, 1])
        XCTAssertEqual(listener.liveTimes, [0, 80, 80])
        XCTAssertEqual(court.possession, .HUMAN)
        AndroidKitTestLoop.advance(millis: 999)
        court.updateActors(now: court.gameTime())
        XCTAssertEqual(listener.shotClocks, [24, 23, 1, 0])
        XCTAssertNil(court.possession)
        XCTAssertEqual(listener.deadBalls, [.OPPONENT])
        let last = listener.statuses.last
        XCTAssertTrue(last?.0 == "24 seconds \u{2014} other team's ball" || last?.0 == hebrewShotClock)
        XCTAssertEqual(last?.1, .HUMAN)
        // lastClockSeconds is never reset: the next possession reports 24 again only because the value changed.
        court.startPossession(team: .OPPONENT)
        court.updateActors(now: court.gameTime())
        XCTAssertEqual(listener.shotClocks.last, 24)
        XCTAssertEqual(listener.liveTimes.last, 0)          // clearForQuestion reset the live tick
    }

    func testPracticeModeHasNoShotClockAndNoLiveTime() {
        let court = roster1()
        let listener = RecordingTeamListener()
        court.setListener(listener: listener)
        court.practiceQuiet = true
        court.practiceAction = { _, _ in }
        court.startPossession(team: .HUMAN)
        court.updateActors(now: court.gameTime())
        AndroidKitTestLoop.advance(millis: 30_000)
        court.updateActors(now: court.gameTime())
        XCTAssertTrue(listener.shotClocks.isEmpty)
        XCTAssertTrue(listener.liveTimes.isEmpty)
        XCTAssertEqual(court.possession, .HUMAN)
    }

    func testDribbleRhythmUsesJavaHashCodeOffsets() {
        let court = Court()
        // (id, now, dribblePhase bits, dribbleBounce bits) printed on the JVM.
        let goldens: [(String, Int64, UInt32, UInt32)] = [
            ("H0", 0, 0x3da60dd6, 0x413974b3), ("H0", 310, 0x3f000000, 0x42380000), ("H0", 680, 0, 0),
            ("H0", 1_000_123, 0x3f19410a, 0x422f3bf5), ("H0", 987_654_321, 0x3da8d256, 0x413c7a5c),
            ("H1", 0, 0x3da8d256, 0x413c7a5c), ("H1", 310, 0x3f005890, 0x4237ff93), ("H1", 680, 0x3ab11fd4, 0x3e47f97b),
            ("H1", 1_000_123, 0x3f19999a, 0x422efe90), ("H1", 987_654_321, 0x3dab96d5, 0x413f7f27),
            ("O0", 0, 0x3ebfa770, 0x4229d80f), ("O0", 310, 0x3f4b11fd, 0x41de9351), ("O0", 680, 0x3e9623fa, 0x421287af),
            ("O0", 1_000_123, 0x3f645307, 0x417530d6), ("O0", 987_654_321, 0x3ec05890, 0x422a2496),
            ("O2", 0, 0x3ec109b0, 0x422a7055), ("O2", 310, 0x3f4bc31d, 0x41dc143e), ("O2", 680, 0x3e97863a, 0x4213783b),
            ("O2", 1_000_123, 0x3f650427, 0x416f4a2d), ("O2", 987_654_321, 0x3ec1bad0, 0x422abb49),
        ]
        for (id, now, phase, bounce) in goldens {
            let a = Court.Actor(id: id, team: .HUMAN, characterId: "woman_dark",
                                profile: TripleShotCharacterRoster.womanDark, x: 0, y: 0, hasBall: true)
            court.updateDribbleRhythm(actor: a, now: now)
            XCTAssertEqual(a.dribblePhase.bitPattern, phase, "\(id) \(now) phase")
            XCTAssertEqual(a.dribbleBounce.bitPattern, bounce, "\(id) \(now) bounce")
            XCTAssertEqual(a.dribbleHandSign, 1)
        }
        // Android 6c38131 (938db79): the hand is kept until a deliberate crossover; mirroring no longer sets it.
        let mirrored = Court.Actor(id: "H0", team: .HUMAN, characterId: "woman_dark",
                                   profile: TripleShotCharacterRoster.womanDark, x: 0, y: 0, hasBall: true, mirror: true)
        court.updateDribbleRhythm(actor: mirrored, now: 310)
        XCTAssertEqual(mirrored.dribbleHandSign, 1)
        let leftHand = Court.Actor(id: "H0", team: .HUMAN, characterId: "woman_dark",
                                   profile: TripleShotCharacterRoster.womanDark, x: 0, y: 0, hasBall: true)
        leftHand.dribbleHandSign = -1
        court.updateDribbleRhythm(actor: leftHand, now: 310)
        XCTAssertEqual(leftHand.dribbleHandSign, -1)
        let empty = Court.Actor(id: "H0", team: .HUMAN, characterId: "woman_dark",
                                profile: TripleShotCharacterRoster.womanDark, x: 0, y: 0, dribblePhase: 0.25,
                                dribbleBounce: 12)
        court.updateDribbleRhythm(actor: empty, now: 310)
        XCTAssertEqual(empty.dribbleBounce, 0)
        XCTAssertEqual(empty.dribblePhase, 0.25)
    }

    func testHandlerTrackingRestartsTheHandlerClock() {
        let court = roster1()
        court.startPossession(team: .HUMAN)
        let start = court.gameTime()
        AndroidKitTestLoop.advance(millis: 500)
        court.updateHandlerTracking(now: court.gameTime())
        XCTAssertEqual(court.trackedHandlerSince, start)      // same handler: unchanged
        actor(court, "H0").hasBall = false
        actor(court, "H1").hasBall = true
        court.updateHandlerTracking(now: court.gameTime())
        XCTAssertEqual(court.trackedHandlerId, "H1")
        XCTAssertEqual(court.trackedHandlerSince, start + 500)
        XCTAssertEqual(actor(court, "H1").possessionReceivedAt, start + 500)
        actor(court, "H1").hasBall = false
        court.updateHandlerTracking(now: court.gameTime())
        XCTAssertNil(court.trackedHandlerId)
        XCTAssertEqual(court.trackedHandlerSince, 0)
    }

    // MARK: - Shooting (spec 11 section 4.7)

    func testShotChanceMatchesTheJvmFormulaInEveryZone() {
        let court = roster1()
        court.startPossession(team: .HUMAN)
        let h0 = actor(court, "H0")   // woman_dark: inside 78, midRange 83, threePoint 86
        actor(court, "O0").x = 1350; actor(court, "O0").y = 260
        actor(court, "O1").x = 320; actor(court, "O1").y = 260
        // (y of H0 below the top hoop foot, held ms, boost, expected chance) from the JVM WDSHOT lines.
        let goldens: [(Float, Int64, Float, Int)] = [
            (404, 0, 0, 34), (404, 200, 0.2, 36), (404, 450, 0.35, 37), (404, 700, 0, 54), (404, 1000, 0.2, 78),
            (404, 1500, 0.35, 80), (554, 0, 0, 36), (554, 700, 0.2, 58), (554, 1000, 0.35, 83), (554, 1500, 0, 80),
            (704, 450, 0.2, 38), (704, 700, 0.35, 60), (704, 1000, 0, 82), (704, 1500, 0.2, 84),
        ]
        for (y, held, boost, expected) in goldens {
            h0.x = 834; h0.y = y
            court.setActorBoost(actorId: "H0", boost01: boost)
            XCTAssertEqual(court.contest01(shooter: h0), 0)
            XCTAssertEqual(court.shotChance(actor: h0, heldMs: held), expected, "y \(y) held \(held) boost \(boost)")
        }
    }

    func testTwoFingerHoldGathersBeforeTheBallIsReleased() {
        let court = roster1()
        let listener = RecordingTeamListener()
        court.setListener(listener: listener)
        court.practiceQuiet = true
        court.startPossession(team: .HUMAN)
        let h0 = actor(court, "H0")
        let down = AndroidKitTestLoop.nowMillis
        XCTAssertTrue(court.onTouchEvent(touch(AMotionEvent.ACTION_DOWN, down, 100, 120)))
        XCTAssertTrue(court.onTouchEvent(touches(AMotionEvent.ACTION_POINTER_DOWN, actionIndex: 1, down,
                                                 ids: [0, 1], xs: [100, 400], ys: [120, 300])))
        XCTAssertTrue(court.shotHoldActive)                  // the second finger starts the gather at once
        XCTAssertEqual(court.shotPointerId, 1)
        XCTAssertEqual(h0.motion, .SHOT_LOW)
        XCTAssertEqual(listener.shotQualities.last?.1, true)
        AndroidKitTestLoop.advance(millis: 1200)
        XCTAssertTrue(court.onTouchEvent(touches(AMotionEvent.ACTION_POINTER_UP, actionIndex: 1, down,
                                                 ids: [0, 1], xs: [100, 400], ys: [120, 300])))
        XCTAssertFalse(court.shotHoldActive)
        XCTAssertEqual(court.pendingShotActor, "H0")          // the shot is queued ...
        XCTAssertFalse(court.ballInFlight)                    // ... but not released yet
        XCTAssertTrue(h0.hasBall)
        AndroidKitTestLoop.advance(millis: 280)
        XCTAssertEqual(h0.motion, .SHOT_SET)
        XCTAssertGreaterThan(h0.jumpPx, 0)
        XCTAssertTrue(h0.hasBall)
        AndroidKitTestLoop.advance(millis: 220)               // 500 ms after the release: the ball flies (>= 520 ms)
        XCTAssertNil(court.pendingShotActor)
        XCTAssertTrue(court.ballInFlight)
        XCTAssertEqual(court.ballFlightKind, .SHOT)
        XCTAssertFalse(h0.hasBall)
        XCTAssertEqual(court.possession, .HUMAN)
    }

    func testShootRequiresTheBallAndOneGatherAtATime() {
        let court = roster1()
        court.startPossession(team: .HUMAN)
        let h0 = actor(court, "H0")
        let h1 = actor(court, "H1")
        court.shoot(actor: h1, chance: 50)                   // no ball: ignored
        XCTAssertNil(court.pendingShotActor)
        court.shoot(actor: h0, chance: 50)
        XCTAssertEqual(court.pendingShotActor, "H0")
        XCTAssertEqual(h0.motion, .SHOT_LOW)
        XCTAssertEqual(h0.actionLockUntil, court.gameTime() + 1100)
        h1.hasBall = true
        court.shoot(actor: h1, chance: 50)                   // another gather is pending: ignored
        XCTAssertEqual(court.pendingShotActor, "H0")
        h1.hasBall = false
        // Possession lost during the gather: the queued shot is dropped at 470 ms.
        court.possession = .OPPONENT
        AndroidKitTestLoop.advance(millis: 470)
        XCTAssertNil(court.pendingShotActor)
        XCTAssertFalse(court.ballInFlight)
        XCTAssertTrue(h0.hasBall)
    }

    func testHumanBlockAttemptOnAnOpponentShotJumpsIntoBlock() {
        let court = roster1()
        court.practiceQuiet = true
        court.startPossession(team: .OPPONENT)
        let shooter = actor(court, "O0")
        let defender = actor(court, "H0")
        defender.x = shooter.x + 20
        defender.y = shooter.y - 20
        court.shoot(actor: shooter, chance: 60)
        AndroidKitTestLoop.advance(millis: 480)
        XCTAssertTrue(court.ballInFlight)
        court.attemptHumanDefensiveAction()
        XCTAssertEqual(defender.motion, .BLOCK)
        XCTAssertGreaterThan(defender.jumpUntil, court.gameTime())
        XCTAssertEqual(defender.lastStealAttempt, court.gameTime())
        XCTAssertEqual(defender.actionLockUntil, defender.jumpUntil)
    }

    /// The steal roll is the first random draw after configure in 2v2 (no zone roll): seed 4 draws 0.033 (below the
    /// 0.08 minimum chance, so it always succeeds) and seed 7 draws 0.958 (above the 0.58 maximum, so it always fails).
    private func stealScenario(seed: Int64) -> (Court, RecordingTeamListener, Court.Actor, Court.Actor) {
        let court = roster1(seed: seed)
        let listener = RecordingTeamListener()
        court.setListener(listener: listener)
        court.practiceQuiet = true
        court.startPossession(team: .OPPONENT)
        let handler = actor(court, "O0")
        let defender = actor(court, "H0")
        defender.x = handler.x
        defender.y = handler.y - 100                         // 3.4 m away: out of reach, no cooldown
        let cooldownBefore = defender.lastStealAttempt
        court.attemptHumanDefensiveAction()
        XCTAssertEqual(listener.statuses.last?.0, getString(R.string.minik_swish_team_steal_get_closer))
        XCTAssertEqual(listener.statuses.last?.1, .HUMAN)
        XCTAssertEqual(defender.lastStealAttempt, cooldownBefore)
        defender.y = handler.y - 20
        court.attemptHumanDefensiveAction()
        XCTAssertEqual(defender.motion, .STEAL)
        XCTAssertEqual(defender.lastStealAttempt, court.gameTime())
        XCTAssertEqual(defender.actionLockUntil, court.gameTime() + 360)
        XCTAssertEqual(listener.statuses.last?.0, getString(R.string.minik_swish_team_steal_attempt))
        return (court, listener, handler, defender)
    }

    func testSuccessfulHumanStealTransfersTheBallAfterTheReach() {
        let (court, listener, handler, defender) = stealScenario(seed: 4)
        XCTAssertGreaterThanOrEqual(handler.actionLockUntil, court.gameTime() + 190)
        AndroidKitTestLoop.advance(millis: 149)
        XCTAssertTrue(handler.hasBall)                        // the reach frame shows first
        AndroidKitTestLoop.advance(millis: 1)
        XCTAssertFalse(handler.hasBall)
        XCTAssertTrue(defender.hasBall)
        XCTAssertEqual(court.possession, .HUMAN)
        XCTAssertEqual(listener.statuses.last?.0, getString(R.string.minik_swish_team_steal_success))
        XCTAssertEqual(listener.statuses.last?.1, .HUMAN)
        AndroidKitTestLoop.advance(millis: 230)
        XCTAssertEqual(defender.motion, .DRIBBLE)             // giveBall's pose: the 380 ms reset does not apply
    }

    func testFailedHumanStealResetsThePoseAfter380Ms() {
        let (court, _, handler, defender) = stealScenario(seed: 7)
        AndroidKitTestLoop.advance(millis: 379)
        XCTAssertEqual(defender.motion, .STEAL)
        AndroidKitTestLoop.advance(millis: 1)
        XCTAssertEqual(defender.motion, .IDLE)
        XCTAssertEqual(defender.actionLockUntil, 0)
        XCTAssertTrue(handler.hasBall)
        XCTAssertEqual(court.possession, .OPPONENT)
        court.attemptHumanDefensiveAction()                   // 650 ms cooldown since the attempt
        XCTAssertEqual(defender.motion, .IDLE)
    }

    // MARK: - Touch (spec 11 section 4.5) and movement (section 4.6)

    func testFiftyMovesWithOneTimestampDoNotMoveButRealTimeMovesDo() {
        let court = roster1()
        court.practiceQuiet = true
        court.startPossession(team: .HUMAN)
        let h0 = actor(court, "H0")
        let startX = h0.x, startY = h0.y
        let down = AndroidKitTestLoop.nowMillis
        _ = court.onTouchEvent(touch(AMotionEvent.ACTION_DOWN, down, 600, 500))
        for i in 1...50 {
            _ = court.onTouchEvent(touch(AMotionEvent.ACTION_MOVE, down, 600 + Float(i) * 8, 500))
        }
        XCTAssertTrue(court.dragMoved)
        XCTAssertLessThan(floorMetres(h0.x - startX, h0.y - startY), 0.35)
        _ = court.onTouchEvent(touch(AMotionEvent.ACTION_UP, down, 1000, 500))

        let x0 = h0.x, y0 = h0.y
        let down2 = AndroidKitTestLoop.nowMillis
        _ = court.onTouchEvent(touch(AMotionEvent.ACTION_DOWN, down2, 600, 500))
        for i in 1...10 {
            AndroidKitTestLoop.advance(millis: 35)
            _ = court.onTouchEvent(touch(AMotionEvent.ACTION_MOVE, down2, 600 + Float(i) * 40, 500))   // 20% of 2000 px
        }
        let moved = floorMetres(h0.x - x0, h0.y - y0)
        XCTAssertGreaterThan(moved, 0.15)
        XCTAssertLessThan(moved, 3)
        XCTAssertEqual(h0.motion, .DRIBBLE)
        XCTAssertEqual(court.possession, .HUMAN)
        _ = court.onTouchEvent(touch(AMotionEvent.ACTION_UP, down2, 1000, 500))
        XCTAssertEqual(h0.vx, 0)
        XCTAssertEqual(h0.vy, 0)
        XCTAssertEqual(court.dragPointerId, -1)
    }

    func testDribblingAcrossTheSidelineIsATurnover() {
        let court = roster1()
        let listener = RecordingTeamListener()
        court.setListener(listener: listener)
        court.practiceQuiet = true
        court.startPossession(team: .HUMAN)
        let h0 = actor(court, "H0")
        h0.x = 1358
        let down = AndroidKitTestLoop.nowMillis
        _ = court.onTouchEvent(touch(AMotionEvent.ACTION_DOWN, down, 600, 500))
        for i in 1...30 where court.possession != nil {
            AndroidKitTestLoop.advance(millis: 35)
            _ = court.onTouchEvent(touch(AMotionEvent.ACTION_MOVE, down, 600 + Float(i) * 40, 500))
        }
        XCTAssertLessThanOrEqual(AndroidKitTestLoop.nowMillis - down, 1200)
        XCTAssertNil(court.possession)
        XCTAssertEqual(h0.x, 1359)                           // clamped to the play rectangle
        XCTAssertFalse(h0.hasBall)
        XCTAssertEqual(listener.deadBalls, [.OPPONENT])
        let status = listener.statuses.last
        XCTAssertTrue(status?.0 == "Out of bounds" || status?.0 == hebrewOutOfBounds)
        XCTAssertEqual(status?.1, .HUMAN)                    // the offending team's tone
    }

    func testTouchIsIgnoredWhilePausedAndDuringADeadBall() {
        let court = roster1()
        court.setMatchPaused(paused: true)
        XCTAssertTrue(court.onTouchEvent(touch(AMotionEvent.ACTION_DOWN, AndroidKitTestLoop.nowMillis, 10, 10)))
        XCTAssertTrue(court.touchPicks.isEmpty)               // paused: not even the gesture detector runs
        court.setMatchPaused(paused: false)
        let down = AndroidKitTestLoop.nowMillis
        XCTAssertTrue(court.onTouchEvent(touch(AMotionEvent.ACTION_DOWN, down, 10, 10)))
        XCTAssertEqual(court.touchPicks.count, 1)             // the detector ran (onDown)
        XCTAssertEqual(court.dragPointerId, -1)               // possession == nil: no raw handling
    }

    func testTouchPicksKeepTheFourMostRecentGestures() {
        let court = roster1()
        var downs: [Int64] = []
        for _ in 0..<5 {
            let down = AndroidKitTestLoop.nowMillis
            downs.append(down)
            _ = court.onTouchEvent(touch(AMotionEvent.ACTION_DOWN, down, 50, 50))
            AndroidKitTestLoop.advance(millis: 50)
            _ = court.onTouchEvent(touch(AMotionEvent.ACTION_UP, down, 50, 50))
            AndroidKitTestLoop.advance(millis: 400)
        }
        XCTAssertEqual(court.touchPicks.keys, Array(downs.dropFirst()))
        let pick = court.touchPicks[downs[4]]!
        XCTAssertNil(pick.actorId)
        XCTAssertNil(pick.team)
        XCTAssertEqual(pick.possessionAt, 0)
        // A pick is valid only for the possession it was taken in.
        let event = touch(AMotionEvent.ACTION_UP, downs[4], 50, 50)
        XCTAssertNotNil(court.touchPick(e: event))
        court.startPossession(team: .HUMAN)
        XCTAssertNil(court.touchPick(e: event))
    }

    // MARK: - Ball actions

    func testCommandScreenAllowsOneScreenerOnTheHandler() {
        let court = roster2()
        let listener = RecordingTeamListener()
        court.setListener(listener: listener)
        court.startPossession(team: .HUMAN)
        let h0 = actor(court, "H0"), h1 = actor(court, "H1"), h2 = actor(court, "H2")
        h1.screenTargetId = "H0"
        let statusCount = listener.statuses.count
        court.commandScreen(screener: h2, ballHandler: h0)
        XCTAssertNil(h2.screenTargetId)
        XCTAssertEqual(listener.statuses.count, statusCount)
        h1.screenTargetId = nil
        court.commandScreen(screener: h2, ballHandler: h0)
        XCTAssertEqual(h2.screenTargetId, "H0")
        XCTAssertEqual(listener.statuses.last?.0, getString(R.string.minik_swish_team_screen_set))
        XCTAssertEqual(listener.statuses.last?.1, .HUMAN)
        court.commandScreen(screener: h0, ballHandler: h0)   // the handler cannot screen for itself
        XCTAssertNil(h0.screenTargetId)
    }

    func testPassFreezesTheReceiverAndLocksThePasser() {
        let court = roster1()
        court.practiceQuiet = true                            // no pass interceptions
        court.startPossession(team: .HUMAN)
        let h0 = actor(court, "H0"), h1 = actor(court, "H1")
        court.passBall(from: h0, to: h1)
        XCTAssertFalse(h0.hasBall)
        XCTAssertEqual(h0.motion, .SHOT_MID)
        XCTAssertEqual(h0.actionLockUntil, court.gameTime() + 600)
        XCTAssertEqual(court.passReceiverId, "H1")
        XCTAssertTrue(court.ballInFlight)
        XCTAssertEqual(court.ballFlightKind, .PASS)
        AndroidKitTestLoop.advance(millis: 110 + 430 + 100)   // gather leg + the longest flight + frame slack
        XCTAssertFalse(court.ballInFlight)
        XCTAssertTrue(h1.hasBall)
        XCTAssertNil(court.passReceiverId)
        XCTAssertEqual(court.activeHumanActorId, "H1")         // control follows the ball
        XCTAssertTrue(h1.controlled)
        XCTAssertEqual(court.possession, .HUMAN)
    }

    func testAlleyOopWithoutDefendersScoresTwo() {
        let court = roster1()
        let listener = RecordingTeamListener()
        court.setListener(listener: listener)
        court.practiceQuiet = true
        court.startPossession(team: .HUMAN)
        for opponent in court.actors.filter({ $0.team == .OPPONENT }) {   // nobody near the lob or the rim
            opponent.x = 1350
            opponent.y = 800
        }
        court.startAlleyOop(from: actor(court, "H0"), receiver: actor(court, "H1"))
        XCTAssertEqual(listener.statuses.last?.0, getString(R.string.minik_swish_team_alley_oop))
        XCTAssertEqual(court.ballFlightKind, .ALLEY_OOP)
        XCTAssertEqual(actor(court, "H1").cutUntil, court.gameTime() + 950)
        AndroidKitTestLoop.advance(millis: 700)
        XCTAssertEqual(listener.baskets.count, 1)
        XCTAssertEqual(listener.baskets.first?.0, .HUMAN)
        XCTAssertEqual(listener.baskets.first?.1, 2)
        XCTAssertEqual(listener.deadBalls, [.OPPONENT])
        XCTAssertEqual(actor(court, "H1").motion, .DUNK)
        XCTAssertFalse(court.ballVisible)
    }

    // MARK: - Opponent ball-handler AI (spec 11 section 4.10)

    func testOpponentHandlerKeepsTheShapeEarlyWithoutRandomDraws() {
        let seed: Int64 = 99
        let court = roster1(seed: seed)
        court.startPossession(team: .OPPONENT)
        let handler = actor(court, "O0")
        let now = court.gameTime()
        court.updateOpponentOffense(now: now)
        XCTAssertEqual(handler.lastAiDecision, now)
        XCTAssertEqual(handler.travelScale, 0.66)
        // Rule 13: the PG home at the bottom basket (834, 473), probe sideways by 18 + agility * 0.12, up 8.
        let offset: Float = 18 + handler.profile.ratings.agility.toFloat() * 0.12
        XCTAssertEqual(handler.targetY, 465)
        XCTAssertTrue(handler.targetX == 834 - offset || handler.targetX == 834 + offset, "\(handler.targetX)")
        XCTAssertEqual(court.random.nextInt(), KotlinRandom(seed: seed).nextInt())   // no roll consumed
        // At most one decision every 360 ms.
        handler.travelScale = 0
        court.updateOpponentOffense(now: now + 359)
        XCTAssertEqual(handler.travelScale, 0)
        XCTAssertEqual(handler.lastAiDecision, now)
    }

    func testPracticeQuietDisablesTheOpponentHandler() {
        let court = roster1()
        court.practiceQuiet = true
        court.startPossession(team: .OPPONENT)
        let handler = actor(court, "O0")
        court.updateOpponentOffense(now: court.gameTime())
        XCTAssertEqual(handler.lastAiDecision, 0)
        XCTAssertEqual(handler.travelScale, 0)
    }

    // MARK: - Runtime state (spec 11 section 4.13)

    func testRuntimeStateRoundTripTurnsAnInFlightBallIntoALooseBall() {
        let court = roster2()
        let listener = RecordingTeamListener()
        court.setListener(listener: listener)
        court.startPossession(team: .OPPONENT)
        let o1 = actor(court, "O1")
        o1.x = 700; o1.y = 500; o1.boost01 = 0.2; o1.screenTargetId = "O0"; o1.motion = .WALK
        court.setControlled(id: "H2")
        court.ballInFlight = true
        court.looseVxSource = 0
        court.looseVySource = 0
        let saved = court.saveRuntimeState()
        XCTAssertEqual(saved.getInt("actorCount", -1), 6)
        XCTAssertEqual(saved.getString("possession"), "OPPONENT")
        XCTAssertEqual(saved.getStringArrayList("assignmentKeys"), court.defensiveAssignments.keys)

        o1.x = 1000; o1.y = 300; o1.boost01 = 0; o1.screenTargetId = nil; o1.motion = .IDLE
        court.possession = .HUMAN
        court.defensiveAssignments.clear()
        XCTAssertTrue(court.restoreRuntimeState(state: saved))
        XCTAssertEqual(o1.x, 700)
        XCTAssertEqual(o1.y, 500)
        XCTAssertEqual(o1.boost01, 0.2)
        XCTAssertEqual(o1.screenTargetId, "O0")
        XCTAssertEqual(o1.motion, .WALK)
        XCTAssertEqual(court.possession, .OPPONENT)
        XCTAssertEqual(court.activeHumanActorId, "H2")
        XCTAssertEqual(court.actors.filter { $0.controlled }.map { $0.id }, ["H2"])
        XCTAssertEqual(court.defensiveAssignments.keys, saved.getStringArrayList("assignmentKeys"))
        XCTAssertFalse(court.ballInFlight)
        XCTAssertTrue(court.looseBall)
        XCTAssertEqual(court.looseVySource, 45)
        XCTAssertEqual(listener.possessions.last, .OPPONENT)

        let small = roster1()
        XCTAssertFalse(small.restoreRuntimeState(state: saved))   // actorCount differs
        XCTAssertFalse(Court().restoreRuntimeState(state: saved))  // no actors yet
    }
}
