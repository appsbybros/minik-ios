import XCTest
import UIKit
@testable import MinikTripleShot

// Area w-team2: TripleShotTeamCourtView lines 2328-4096 (spec 12-team2), ported in
// TripleShot/View/TripleShotTeamCourtView+Part2.swift.
//
// Every expected value below was computed on the JVM by the VERBATIM Kotlin code of TripleShotTeamCourtView.kt
// (snapshot dd722e5): a harness copies the Kotlin lines of both halves of the class, replaces only the Android-only
// pieces (GPU world, sprite renderer, animator) by fakes and prints IEEE float32 bit patterns. Floats are compared
// bit for bit. Camera/gap values depend on the view's pixel size and density, so they are tabulated for the device
// densities 1, 2 and 3 with the view laid out at 393x852 dp (portrait) or 852x393 dp (landscape) in px.
//
// No GPU is needed: the court is created detached (its 32 ms AI tick never runs), AndroidKit's fake clock drives
// gameTime(), System.nanoTime() and the postAction/ValueAnimator callbacks, and the GPU geometry services are only
// called where their result is not asserted.

private typealias Court = TripleShotTeamCourtView
private typealias CourtActor = TripleShotTeamCourtView.Actor
private typealias Facing = TripleShotPlayerRenderer.Facing
private typealias Motion = TripleShotPlayerRenderer.Motion

private let MAYA = "woman_dark"

private func F(_ bits: UInt32) -> Float { return Float(bitPattern: bits) }

private func assertBits(_ actual: Float, _ expectedBits: UInt32, _ label: String,
                        file: StaticString = #filePath, line: UInt = #line) {
    XCTAssertEqual(actual.bitPattern, expectedBits,
                   "\(label): got \(actual) (0x\(String(actual.bitPattern, radix: 16))), Kotlin \(F(expectedBits))",
                   file: file, line: line)
}

private func assertPoint(_ x: Float, _ y: Float, _ ex: UInt32, _ ey: UInt32, _ label: String,
                         file: StaticString = #filePath, line: UInt = #line) {
    assertBits(x, ex, label + ".x", file: file, line: line)
    assertBits(y, ey, label + ".y", file: file, line: line)
}

/// `Random(seed)` advanced by `draws` calls, then one more nextInt(): what the court's generator must return next.
private func nextIntAfter(seed: Int64, draws: Int) -> Int32 {
    let reference = KotlinRandom(seed: seed)
    for _ in 0..<draws { _ = reference.nextInt() }
    return reference.nextInt()
}

final class TeamCourtPart2Tests: XCTestCase {
    private let T0: Int64 = 1_000_000_000_000
    private var savedConfiguration: AConfiguration!

    override func setUp() {
        super.setUp()
        AndroidKitTestLoop.install(startNanos: T0)
        savedConfiguration = AConfiguration.current
        setOrientation(portrait: true)
    }

    override func tearDown() {
        AConfiguration.current = savedConfiguration
        AndroidKitTestLoop.uninstall()
        super.tearDown()
    }

    // MARK: - Fixtures

    private var density: Float { return AResources.density }

    private func setOrientation(portrait: Bool) {
        let size = portrait ? CGSize(width: 393, height: 852) : CGSize(width: 852, height: 393)
        AConfiguration.current = AConfiguration.make(windowSize: size, screenSize: CGSize(width: 393, height: 852),
                                                     scale: CGFloat(AResources.density), dark: false)
    }

    /// A configured, detached court laid out at `widthDp` x `heightDp` (in px), every actor reset to the harness
    /// start state: role WING (the Kotlin Actor default), H_i at (400 + 100 i, 700), O_i at (400 + 100 i, 300).
    private func makeCourt(_ humans: [String], _ opponents: [String], widthDp: Int = 393, heightDp: Int = 852) -> Court {
        let court = Court()
        court.configure(teamSize: humans.count, humanCharacterId: humans[0],
                        teammateCharacterIds: Array(humans.dropFirst()), opponentCharacterIds: opponents, seed: 1)
        let d = Int(AResources.density)
        court.layout(0, 0, widthDp * d, heightDp * d)
        var humanIndex = 0
        var opponentIndex = 0
        for actor in court.actors {
            actor.role = .WING
            if actor.team == .HUMAN {
                actor.x = 400 + Float(humanIndex) * 100; actor.y = 700; humanIndex += 1
            } else {
                actor.x = 400 + Float(opponentIndex) * 100; actor.y = 300; opponentIndex += 1
            }
        }
        return court
    }

    private func actor(_ court: Court, _ id: String) -> CourtActor {
        return court.actors.first(where: { $0.id == id })!
    }

    private func place(_ court: Court, _ id: String, _ x: Float, _ y: Float) {
        let a = actor(court, id)
        a.x = x
        a.y = y
    }

    // MARK: - Rating composites (spec 12 §7.3, §7.8)

    func testRatingCompositesMatchKotlin() {
        let court = makeCourt([MAYA, "nova", "coach_67"], ["zephyr", "flare", "kyra"])
        let expected: [(String, UInt32, UInt32, UInt32, UInt32)] = [
            // id, passingSkillProxy, interceptionChance, collisionHalfWidthDp, collisionHalfDepthDp
            ("H0", 0x3f60b780, 0x3f41a9fc, 0x42320000, 0x41f00000),  // Maya 0.8778 / 0.7565 / 44.5 / 30
            ("H1", 0x3f63bcd4, 0x3f59ba5f, 0x42320000, 0x41f00000),  // nova 0.88960004 / 0.85050005
            ("H2", 0x3f221965, 0x3f18d4fd, 0x422c0000, 0x41e80000),  // coach_67 0.6332 / 0.59699994 / 43 / 29
            ("O0", 0x3f5ba5e4, 0x3f5e3540, 0x42340000, 0x41f00000),  // zephyr 0.85800004 / 0.86800003 / 45
            ("O1", 0x3f5e1b08, 0x3f47ceda, 0x42440000, 0x41f00000),  // flare 0.86759996 / 0.78050005 / 49
            ("O2", 0x3f5ba5e4, 0x3f5e3540, 0x42340000, 0x41f00000),  // kyra
        ]
        for (id, pass, intercept, halfW, halfD) in expected {
            let a = actor(court, id)
            assertBits(court.passingSkillProxy(actor: a), pass, "passingSkillProxy \(id)")
            assertBits(court.interceptionChance(actor: a), intercept, "interceptionChance \(id)")
            assertBits(court.collisionHalfWidthDp(actor: a), halfW, "collisionHalfWidthDp \(id)")
            assertBits(court.collisionHalfDepthDp(actor: a), halfD, "collisionHalfDepthDp \(id)")
        }
        assertBits(court.driveAdvantage(attacker: actor(court, "H0"), defender: actor(court, "H0")), 0x3de83e48,
                   "drive Maya vs Maya (0.11340004)")
        assertBits(court.driveAdvantage(attacker: actor(court, "H1"), defender: actor(court, "H2")), 0x3dade00a,
                   "drive nova vs coach_67")
        assertBits(court.driveAdvantage(attacker: actor(court, "H2"), defender: actor(court, "H1")), 0xbe0dd2f6,
                   "drive coach_67 vs nova")
        assertBits(court.driveAdvantage(attacker: actor(court, "O1"), defender: actor(court, "O0")), 0x3d56a148,
                   "drive flare vs zephyr")
        assertBits(court.driveAdvantage(attacker: actor(court, "H0"), defender: nil), 0x3eb33333, "drive without defender")
        XCTAssertTrue(court.isHumanOwned(actor: actor(court, "H0")))
        XCTAssertFalse(court.isHumanOwned(actor: actor(court, "H1")))
    }

    func testContestShotQualityAndPassLaneMatchKotlin() {
        let court = makeCourt([MAYA, MAYA], [MAYA, MAYA])
        place(court, "H0", 834, 504); place(court, "H1", 400, 700); place(court, "O0", 934, 504); place(court, "O1", 1300, 800)
        let h0 = actor(court, "H0")
        assertBits(court.distance(a: h0, b: actor(court, "O0")), 0x42c80000, "distance 100")
        assertBits(court.distanceToHoop(a: h0), 0x43480000, "distanceToHoop 200")
        assertBits(court.contest01(shooter: h0), 0x3f2416ce, "contest01 (0.640973)")
        assertBits(court.aiShotQuality(actor: h0), 0x3f3b94ab, "aiShotQuality contested (0.73273724)")
        place(court, "O0", 1300, 300)
        assertBits(court.contest01(shooter: h0), 0x00000000, "contest01 open")
        assertBits(court.aiShotQuality(actor: h0), 0x3f67e281, "aiShotQuality open (0.9057999)")
        place(court, "H0", 834, 404)
        assertBits(court.aiShotQuality(actor: h0), 0x3f6ab366, "aiShotQuality inside zone")
        place(court, "H0", 834, 704)
        assertBits(court.aiShotQuality(actor: h0), 0x3f621965, "aiShotQuality three-point zone")

        place(court, "H0", 834, 600); place(court, "H1", 600, 450); place(court, "O0", 700, 540); place(court, "O1", 1300, 800)
        assertBits(court.passLaneSafety(from: h0, to: actor(court, "H1")), 0x3e21cbcd, "passLaneSafety")
        assertBits(court.aiPassScore(from: h0, to: actor(court, "H1")), 0x3edb22b7, "aiPassScore")
        assertBits(court.distancePointToSegment(p: APointF(700, 540), a: APointF(834, 600), b: APointF(600, 450)),
                   0x41ae6b9f, "distancePointToSegment")
        assertBits(court.distancePointToSegment(p: APointF(10, 10), a: APointF(3, 4), b: APointF(3.01, 4)),
                   0x41138341, "degenerate segment = distance to a")
    }

    // MARK: - Legacy virtual camera (spec 12 §4.12, §7.8)

    private struct CameraGolden {
        let scale: UInt32, offsetX: UInt32, offsetY: UInt32, viewX: UInt32, viewY: UInt32, backX: UInt32, backY: UInt32
    }

    private let portraitCamera: [Int: CameraGolden] = [
        1: CameraGolden(scale: 0x3ff9803b, offsetX: 0xc4b2b3e8, offsetY: 0xc42ac702, viewX: 0x43440840, viewY: 0x43e87e04,
                        backX: 0x44442eec, backY: 0x43e2873d),
        2: CameraGolden(scale: 0x4079803b, offsetX: 0xc532b3e8, offsetY: 0xc4aac702, viewX: 0x43c40840, viewY: 0x44687e04,
                        backX: 0x443dc53e, backY: 0x43c8e087),
        3: CameraGolden(scale: 0x40bb202c, offsetX: 0xc58606ee, offsetY: 0xc5001541, viewX: 0x44130630, viewY: 0x44ae5e84,
                        backX: 0x443ba205, backY: 0x43c0539f),
    ]

    private let landscapeCamera: [Int: CameraGolden] = [
        1: CameraGolden(scale: 0x3fbdf9df, offsetX: 0xc44b30d0, offsetY: 0xc4162092, viewX: 0x43d48668, viewY: 0x4388d6c2,
                        backX: 0x4419bf72, backY: 0x4406d6ec),
        2: CameraGolden(scale: 0x403df9df, offsetX: 0xc4cb30d0, offsetY: 0xc4962092, viewX: 0x44548668, viewY: 0x4408d6c2,
                        backX: 0x44115362, backY: 0x43ebfd9a),
        3: CameraGolden(scale: 0x408e7b66, offsetX: 0xc518649a, offsetY: 0xc4e130d8, viewX: 0x449f64ce, viewY: 0x444d4224,
                        backX: 0x440e84b2, backY: 0x43e0c2da),
    ]

    /// HUMAN ball at (834, 589), O0 guarding H0 from (834, 400), no live ball (spec 12 §7.8 camera paragraph).
    private func runCameraScenario(portrait: Bool) {
        setOrientation(portrait: portrait)
        let court = portrait ? makeCourt([MAYA, MAYA], [MAYA, MAYA])
            : makeCourt([MAYA, MAYA], [MAYA, MAYA], widthDp: 852, heightDp: 393)
        let table = portrait ? portraitCamera : landscapeCamera
        guard let golden = table[Int(density)] else {
            XCTFail("no golden for density \(density)")
            return
        }
        let now = court.gameTime()
        court.possession = .HUMAN
        let h0 = actor(court, "H0")
        h0.hasBall = true
        place(court, "H0", 834, 589); place(court, "H1", 500, 650); place(court, "O0", 834, 400); place(court, "O1", 1200, 700)
        court.ballVisible = true
        court.updateCamera(force: true)
        if portrait {
            assertPoint(court.cameraCenterX, court.cameraCenterY, 0x44508f5c, 0x440e4000, "portrait target (834.24, 569)")
            assertBits(court.cameraZoom, 0x4009c82a, "portrait zoom 2.152842")
        } else {
            assertPoint(court.cameraCenterX, court.cameraCenterY, 0x4450a8f6, 0x44064000, "landscape target (834.64, 537)")
            assertBits(court.cameraZoom, 0x403a688e, "landscape zoom 2.9126315")
        }
        let t = court.transform()
        assertBits(t.scaleX, golden.scale, "transform scale")
        assertBits(t.scaleY, golden.scale, "transform scaleY")
        assertPoint(t.offsetX, t.offsetY, golden.offsetX, golden.offsetY, "transform offset")
        let view = court.sourceToView(x: 834, y: 589)
        assertPoint(view.x, view.y, golden.viewX, golden.viewY, "sourceToView")
        let back = court.viewToSource(x: 100, y: 200)
        assertPoint(back.x, back.y, golden.backX, golden.backY, "viewToSource (100, 200) px")

        // Man on-ball cushion: dp(gap) / transform().scaleX, toward the protected hoop.
        h0.possessionReceivedAt = now
        h0.lastMeaningfulMovementAt = now
        let o0 = actor(court, "O0")
        court.updateAiDefender(defender: o0, assigned: h0, handler: h0, helping: false, now: now)
        if portrait {
            assertPoint(o0.targetX, o0.targetY, 0x44508000, 0x440d227f, "on-ball target (834, 589 - 24.460995)")
        } else {
            assertPoint(o0.targetX, o0.targetY, 0x44508000, 0x440b37fb, "on-ball target (834, 589 - 32.125313)")
        }
        assertBits(o0.travelScale, 0x3f9c28f6, "urgency 1.22 (view distance > 150 dp)")
        XCTAssertEqual(o0.motion, Motion.IDLE, "out of steal reach: no reach")

        // One eased update after the handler moves.
        place(court, "H0", 900, 640)
        court.updateCamera()
        if portrait {
            assertPoint(court.cameraCenterX, court.cameraCenterY, 0x445297c2, 0x441008f6, "portrait eased centre")
            assertBits(court.cameraZoom, 0x400a8d30, "portrait eased zoom")
        } else {
            assertPoint(court.cameraCenterX, court.cameraCenterY, 0x44523b16, 0x440808f6, "landscape eased centre")
            assertBits(court.cameraZoom, 0x403b8204, "landscape eased zoom")
        }

        // Far-hoop framing (HUMAN handler above y = 540.5, no live ball).
        place(court, "H0", 834, 420)
        court.updateCamera(force: true)
        if portrait {
            assertPoint(court.cameraCenterX, court.cameraCenterY, 0x44508f5c, 0x43a78000, "portrait far-hoop (834.24, 335)")
            assertBits(court.cameraZoom, 0x3feba8bc, "portrait far-hoop zoom 1.8410869")
        } else {
            assertPoint(court.cameraCenterX, court.cameraCenterY, 0x4450a8f6, 0x439a9ec4, "landscape far-hoop y 309.24036")
            assertBits(court.cameraZoom, 0x402e147b, "landscape far-hoop zoom 2.72")
        }

        // Live ball framing follows the ball focus.
        court.ballInFlight = true
        court.ballCameraFocusX = 900
        court.ballCameraFocusY = 300
        court.updateCamera(force: true)
        if portrait {
            assertPoint(court.cameraCenterX, court.cameraCenterY, 0x445f147b, 0x438c0000, "portrait live ball")
            assertBits(court.cameraZoom, 0x406201fd, "portrait live ball zoom")
        } else {
            assertPoint(court.cameraCenterX, court.cameraCenterY, 0x445be148, 0x43780000, "landscape live ball")
            assertBits(court.cameraZoom, 0x40a3dc30, "landscape live ball zoom")
        }
    }

    func testPortraitCameraTransformAndOnBallGap() {
        runCameraScenario(portrait: true)
    }

    func testLandscapeCameraTransformAndOnBallGap() {
        runCameraScenario(portrait: false)
    }

    func testTransformWithoutSizeIsIdentity() {
        let court = Court()
        let t = court.transform()
        XCTAssertEqual(t, Court.Transform(scaleX: 1, scaleY: 1, offsetX: 0, offsetY: 0))
    }

    // MARK: - Loose ball (spec 12 §4.8, §7.8)

    func testLooseBallPhysicsMatchesTheSpecGoldenSteps() {
        let court = makeCourt([MAYA, MAYA], [MAYA, MAYA])
        place(court, "H0", 309, 255); place(court, "H1", 309, 400); place(court, "O0", 1359, 255); place(court, "O1", 1359, 330)
        court.startLooseBallSource(sourceX: 884, sourceY: 226, vxSource: 120, vySource: 140)
        XCTAssertTrue(court.looseBall)
        XCTAssertTrue(court.ballVisible)
        XCTAssertEqual(court.looseLastNanos, 0)
        // (ballX, ballY, vx, vy, focusY) after each call; call 0 uses dt 0.016, later calls 0.033 s of nanoTime.
        let golden: [Int: (UInt32, UInt32, UInt32, UInt32, UInt32)] = [
            0: (0x445d7ae1, 0x43646ca0, 0x42ec6667, 0x4317851f, 0x436948ed),   // (885.92, 228.42432) v (118.200005, 151.52)
            1: (0x445e7484, 0x436a3564, 0x42e8daa1, 0x432f47ae, 0x43704505),   // (889.82056, 234.20856) v (116.42701, 175.28)
            2: (0x445f6a69, 0x4370c6e1, 0x42e55c78, 0x43470a3d, 0x43772bca),
            10: (0x44669953, 0x43a0c671, 0x42cb3d85, 0x43c28f5d, 0x439d33a4),
            20: (0x446e7051, 0x43f68acb, 0x42aebb5d, 0x441cae16, 0x43e45387),
            30: (0x44752dc9, 0x4439c1b1, 0x429638ed, 0x4458147e, 0x4428dd17),
            35: (0x4477db41, 0x4448dab7, 0x42489361, 0xc3acb74e, 0x4441e982),  // after the floor bounce
            40: (0x4479dd20, 0x443d8bab, 0x4239fa24, 0xc362a1ce, 0x4446d66f),  // (999.4551, 758.1823) v (46.494278, -226.63205)
        ]
        for call in 0...40 {
            if call > 0 { AFakeClock.advance(byNanos: 33_000_000) }
            court.updateLooseBall(now: court.gameTime())
            XCTAssertTrue(court.looseBall, "still loose after call \(call)")
            if let g = golden[call] {
                assertPoint(court.ballSourceX, court.ballSourceY, g.0, g.1, "ball after call \(call)")
                assertPoint(court.looseVxSource, court.looseVySource, g.2, g.3, "velocity after call \(call)")
                assertBits(court.ballCameraFocusX, g.0, "focusX after call \(call)")
                assertBits(court.ballCameraFocusY, g.4, "focusY after call \(call)")
            }
        }
        // dt is clamped to 0.035 s after a long gap and to 0.005 s after a tiny one.
        AFakeClock.advance(byNanos: 500_000_000)
        court.updateLooseBall(now: court.gameTime())
        assertPoint(court.ballSourceX, court.ballSourceY, 0x447a4546, 0x443bc876, "clamped long dt")
        assertPoint(court.looseVxSource, court.looseVySource, 0x42372ffd, 0xc3496e9b, "clamped long dt velocity")
        AFakeClock.advance(byNanos: 1_000_000)
        court.updateLooseBall(now: court.gameTime())
        assertPoint(court.ballSourceX, court.ballSourceY, 0x447a53ee, 0x443b8928, "clamped short dt")
        assertPoint(court.looseVxSource, court.looseVySource, 0x4234708d, 0xc345d501, "clamped short dt velocity")
    }

    func testLooseBallLeavingTheSideIsADeadBall() {
        let court = makeCourt([MAYA, MAYA], [MAYA, MAYA])
        place(court, "H0", 1359, 805); place(court, "H1", 1359, 700); place(court, "O0", 1300, 805); place(court, "O1", 1300, 700)
        court.startLooseBallSource(sourceX: 60, sourceY: 500, vxSource: -3000, vySource: 0)
        var steps = 0
        while court.looseBall && steps < 20 {
            court.looseLastNanos = 0
            court.updateLooseBall(now: court.gameTime())
            steps += 1
        }
        XCTAssertEqual(steps, 3)
        XCTAssertFalse(court.looseBall)
        XCTAssertFalse(court.ballVisible)
        assertBits(court.ballSourceX, 0xc2a3b39e, "x past -45")
    }

    func testNearestActorWithin72ClaimsTheLooseBallAsARebound() {
        let court = makeCourt([MAYA, MAYA], [MAYA, MAYA])
        place(court, "H0", 309, 255); place(court, "H1", 309, 400); place(court, "O0", 900, 520); place(court, "O1", 1359, 330)
        court.startLooseBallSource(sourceX: 900, sourceY: 450, vxSource: 0, vySource: 0)
        court.updateLooseBall(now: court.gameTime())
        XCTAssertFalse(court.looseBall)
        XCTAssertEqual(court.currentBallHandler()?.id, "O0")
        XCTAssertEqual(court.possession, .OPPONENT)
        XCTAssertEqual(actor(court, "O0").lastReboundClaimAt, court.gameTime())
        XCTAssertEqual(court.possessionStartedAt, court.gameTime(), "a rebound always restarts the possession clock")
        XCTAssertEqual(actor(court, "O0").motion, Motion.DRIBBLE)
        XCTAssertEqual(actor(court, "O0").facing, Facing.FRONT, "opponents face their attacking (bottom) hoop")
    }

    // MARK: - Defense (spec 12 §4.6)

    func testHelpDefenderScoreUsesTheKotlinParseOfTheIfElse() {
        // Kotlin: `assignmentThreat * if (stat) 54f else 44f - distance * 0.035f` multiplies the threat by
        // (44 - distance * 0.035): H2 scores 23.856194 and wins; the spec's reading would pick H1 (16.17 > 9.62).
        let court = makeCourt([MAYA, MAYA, MAYA], [MAYA, MAYA, MAYA])
        court.possession = .OPPONENT
        actor(court, "O0").hasBall = true
        place(court, "O0", 834, 600); place(court, "O1", 434, 700); place(court, "O2", 1234, 700)
        place(court, "H0", 834, 500); place(court, "H1", 834, 640); place(court, "H2", 834, 300)
        court.defensiveAssignments["H0"] = "O0"
        court.defensiveAssignments["H1"] = "O1"
        court.defensiveAssignments["H2"] = "O2"
        assertBits(court.aiShotQuality(actor: actor(court, "O1")), 0x3f621965, "threat O1")
        assertBits(court.aiShotQuality(actor: actor(court, "O2")), 0x3f621965, "threat O2")
        let helper = court.chooseHelpDefender(assignments: court.assignmentActors(), handler: actor(court, "O0"),
                                              now: court.gameTime())
        XCTAssertEqual(helper, "H2")
    }

    func testStationaryHumanHandlerDrawsTheFirstBestDoubleTeam() {
        let court = makeCourt([MAYA, MAYA, MAYA], [MAYA, MAYA, MAYA])
        let now = court.gameTime()
        court.possession = .HUMAN
        let h0 = actor(court, "H0")
        h0.hasBall = true
        h0.possessionReceivedAt = now - 5000
        h0.lastMeaningfulMovementAt = now - 5000
        place(court, "H0", 834, 600); place(court, "H1", 434, 700); place(court, "H2", 1234, 700)
        place(court, "O0", 834, 560); place(court, "O1", 834, 650); place(court, "O2", 834, 900)
        court.defensiveAssignments["O0"] = "H0"
        court.defensiveAssignments["O1"] = "H1"
        court.defensiveAssignments["O2"] = "H2"
        XCTAssertEqual(court.handlerIdleMs(handler: h0, now: now), 5000)
        // Equal scores (no distance term for a stationary double team): the first maximum in map order wins.
        XCTAssertEqual(court.chooseHelpDefender(assignments: court.assignmentActors(), handler: h0, now: now), "O1")
        XCTAssertNil(court.chooseHelpDefender(assignments: court.assignmentActors(), handler: nil, now: now))
    }

    func testZoneAnchorsOnBallAndShellTargets() {
        let court = makeCourt([MAYA, MAYA, MAYA], [MAYA, MAYA, MAYA])
        actor(court, "H0").role = .POINT_GUARD; actor(court, "H1").role = .WING; actor(court, "H2").role = .INTERIOR
        actor(court, "O0").role = .POINT_GUARD; actor(court, "O1").role = .WING; actor(court, "O2").role = .INTERIOR
        let anchors: [(String, UInt32, UInt32)] = [
            ("H0", 0x441d4000, 0x44068000),  // (629, 538)
            ("H1", 0x4479c000, 0x44150000),  // (999, 596)
            ("H2", 0x44508000, 0x44258000),  // (834, 662)
            ("O0", 0x4481e000, 0x44030000),  // (1039, 524)
            ("O1", 0x44274000, 0x43e90000),  // (669, 466)
            ("O2", 0x44508000, 0x43c80000),  // (834, 400)
        ]
        for (id, ex, ey) in anchors {
            let anchor = court.zoneBaseAnchor(defender: actor(court, id))
            assertPoint(anchor.x, anchor.y, ex, ey, "zoneBaseAnchor \(id)")
        }
        place(court, "H0", 700, 560); place(court, "H1", 1000, 600); place(court, "H2", 834, 660)
        place(court, "O0", 900, 450); place(court, "O1", 1100, 520); place(court, "O2", 700, 420)
        actor(court, "O0").hasBall = true
        XCTAssertEqual(court.zoneOnBallDefenderId(handler: actor(court, "O0")), "H1")
        XCTAssertEqual(court.zoneSecondPressureDefenderId(handler: actor(court, "O0"), onBallId: "H0"), "H1")
        let t1 = court.zoneDefenseTarget(defender: actor(court, "H1"), assigned: actor(court, "O1"), handler: actor(court, "O0"))
        assertPoint(t1.x, t1.y, 0x44746000, 0x440b1eb8, "zone target H1")
        let t2 = court.zoneDefenseTarget(defender: actor(court, "H2"), assigned: actor(court, "O2"), handler: actor(court, "O0"))
        assertPoint(t2.x, t2.y, 0x445670a4, 0x441de666, "zone target H2")
        let t3 = court.zoneDefenseTarget(defender: actor(court, "H2"), assigned: actor(court, "O2"), handler: nil)
        assertPoint(t3.x, t3.y, 0x44508000, 0x44258000, "zone target H2 without a live handler = anchor")
    }

    // MARK: - Spacing, collisions, movement (spec 12 §4.7, §4.11)

    func testTeammateSpacingClampAndCollisions() {
        let court = makeCourt([MAYA, MAYA, MAYA], [MAYA, MAYA, MAYA])
        place(court, "H1", 700, 500); place(court, "H0", 760, 520); place(court, "H2", 650, 560)
        let offense = court.applyTeammateSpacing(actor: actor(court, "H1"), target: APointF(720, 480))
        assertPoint(offense.x, offense.y, 0x443193cd, 0x43dfedb6, "offense spacing")
        let defense = court.applyTeammateSpacing(actor: actor(court, "H1"), target: APointF(720, 480), defenseSpacing: true)
        assertPoint(defense.x, defense.y, 0x4431d2c2, 0x43e3033d, "defense spacing")
        let clamped = court.clampPointToPlayable(point: APointF(100, 900))
        assertPoint(clamped.x, clamped.y, 0x439a8000, 0x44494000, "clamp to (309, 805)")

        place(court, "H0", 800, 500); place(court, "O0", 820, 510); place(court, "H1", 790, 490); place(court, "H2", 300, 255)
        place(court, "O1", 1359, 805); place(court, "O2", 1300, 805)
        court.resolveActorCollisions(moved: actor(court, "H0"))
        assertPoint(actor(court, "H0").x, actor(court, "H0").y, 0x444492fe, 0x4404f639, "pushed out of two bodies")
        XCTAssertEqual(actor(court, "O0").x, 820, "only the moved actor is pushed")

        // Zero distance: String order of the ids decides the side ("O0" > "H0").
        place(court, "O0", 600, 600); place(court, "H0", 600, 600); place(court, "H1", 300, 255)
        court.resolveActorCollisions(moved: actor(court, "O0"))
        assertPoint(actor(court, "O0").x, actor(court, "O0").y, 0x44064925, 0x44160000, "tie O0 goes left")
        place(court, "O0", 600, 600); place(court, "H0", 600, 600)
        court.resolveActorCollisions(moved: actor(court, "H0"))
        assertPoint(actor(court, "H0").x, actor(court, "H0").y, 0x4425b6db, 0x44160000, "tie H0 goes right")
        assertBits(court.floorDistance(a: actor(court, "H0"), b: actor(court, "O0")), 0x3f6147a8, "floor gap 0.88 m")
    }

    func testPlannedMovementIntegratesTargetsWithTheTickDt() {
        let court = makeCourt([MAYA, MAYA], [MAYA, MAYA])
        let now = court.gameTime()
        place(court, "H0", 400, 700); place(court, "H1", 600, 500); place(court, "O0", 1000, 400); place(court, "O1", 1200, 300)
        let h1 = actor(court, "H1")
        let o1 = actor(court, "O1")
        court.moveAiToward(actor: h1, tx: 700, ty: 400, speedScale: 0.9)
        court.moveAiToward(actor: o1, tx: 1100, ty: 320, speedScale: 1.5)
        assertBits(o1.travelScale, 0x3faccccd, "travelScale clamped to 1.35")
        court.movementAt = 0
        court.advancePlannedMovement(now: now)   // first call: dt = TEAM_FRAME_MS / 1000
        XCTAssertEqual(court.movementAt, now)
        assertPoint(h1.x, h1.y, 0x4416fa98, 0x43f80ad1, "H1 after dt 0.032")
        assertPoint(h1.vx, h1.vy, 0x407a9800, 0xc07a9780, "H1 step")
        XCTAssertEqual(h1.motion, Motion.WALK)
        XCTAssertEqual(h1.facing, Facing.SIDE)
        XCTAssertFalse(h1.mirror)
        XCTAssertEqual(h1.lastMeaningfulMovementAt, now)
        assertPoint(o1.x, o1.y, 0x449443fd, 0x43976335, "O1 after dt 0.032")
        XCTAssertEqual(o1.facing, Facing.SIDE)
        XCTAssertTrue(o1.mirror, "mirror follows a left step larger than 1.4")
        XCTAssertEqual(actor(court, "H0").x, 400, "the controlled human is never moved by the AI")
        court.advancePlannedMovement(now: now + 40)   // dt = 0.04
        assertPoint(h1.x, h1.y, 0x441833d5, 0x43f59856, "H1 after dt 0.04")
        assertPoint(h1.vx, h1.vy, 0x409c9e80, 0xc09c9ec0, "H1 second step")
        assertPoint(o1.x, o1.y, 0x449218f9, 0x43991f38, "O1 after dt 0.04")
    }

    // MARK: - Rebounds (spec 12 §4.8)

    func testShotReboundAnticipationCrashersAndOutlets() {
        let court = makeCourt([MAYA, MAYA, MAYA], [MAYA, MAYA, MAYA])
        actor(court, "H0").role = .POINT_GUARD; actor(court, "H1").role = .WING; actor(court, "H2").role = .INTERIOR
        actor(court, "O0").role = .POINT_GUARD; actor(court, "O1").role = .WING; actor(court, "O2").role = .INTERIOR
        court.possession = .HUMAN
        court.ballSourceY = 500
        place(court, "H0", 834, 600); place(court, "H1", 600, 450); place(court, "H2", 950, 380)
        place(court, "O0", 834, 520); place(court, "O1", 700, 400); place(court, "O2", 900, 340)
        court.updateShotReboundAnticipation(now: court.gameTime())
        let expected: [(String, UInt32, UInt32, UInt32)] = [
            ("H1", 0x441d4000, 0x44094000, 0x3f1eb852),  // outlet (629, 549) at 0.62
            ("H2", 0x44440000, 0x43b30000, 0x3f85590c),  // crash rank 0 (784, 358)
            ("O0", 0x4481e000, 0x44094000, 0x3f1eb852),  // outlet (1039, 549)
            ("O1", 0x44640000, 0x43bf0000, 0x3f85590c),  // crash rank 1 (912, 382)
            ("O2", 0x44440000, 0x43b30000, 0x3f85590c),  // crash rank 0 (784, 358)
        ]
        for (id, tx, ty, travel) in expected {
            let a = actor(court, id)
            assertPoint(a.targetX, a.targetY, tx, ty, "rebound target \(id)")
            assertBits(a.travelScale, travel, "rebound speed \(id)")
            XCTAssertEqual(a.facing, Facing.BACK, "\(id) faces the rim")
            XCTAssertEqual(a.motion, Motion.IDLE, "\(id) does not jump while the ball is far from the rim")
        }
    }

    func testLooseBallChaseChasersAndOutlets() {
        let court = makeCourt([MAYA, MAYA, MAYA], [MAYA, MAYA, MAYA])
        actor(court, "H0").role = .POINT_GUARD; actor(court, "H1").role = .WING; actor(court, "H2").role = .INTERIOR
        actor(court, "O0").role = .POINT_GUARD; actor(court, "O1").role = .WING; actor(court, "O2").role = .INTERIOR
        court.possession = .OPPONENT
        court.ballVisible = true
        court.ballSourceX = 900
        court.ballSourceY = 650
        place(court, "H0", 834, 300); place(court, "H1", 600, 640); place(court, "H2", 1000, 700)
        place(court, "O0", 834, 500); place(court, "O1", 700, 690); place(court, "O2", 980, 620)
        court.updateAiLooseBallChase(now: court.gameTime())
        let expected: [(String, UInt32, UInt32, UInt32)] = [
            ("H1", 0x44610000, 0x44228000, 0x3f974492),  // chase the ball (900, 650)
            ("H2", 0x44610000, 0x44228000, 0x3f974492),
            ("O0", 0x4483c000, 0x43f90000, 0x3f147ae1),  // outlet (1054, 498) at 0.58
            ("O1", 0x44198000, 0x43f90000, 0x3f147ae1),  // outlet (614, 498)
            ("O2", 0x44610000, 0x44228000, 0x3f974492),
        ]
        for (id, tx, ty, travel) in expected {
            let a = actor(court, id)
            assertPoint(a.targetX, a.targetY, tx, ty, "loose target \(id)")
            assertBits(a.travelScale, travel, "loose speed \(id)")
        }
    }

    // MARK: - Off-ball offense (spec 12 §4.7)

    func testOffBallSpacingAndCutTargets() {
        let court = makeCourt([MAYA, MAYA, MAYA], [MAYA, MAYA, MAYA])
        actor(court, "H1").role = .POINT_GUARD
        actor(court, "H2").role = .INTERIOR
        place(court, "H0", 900, 300); place(court, "H1", 500, 700); place(court, "H2", 1300, 800)
        let right = court.offBallSpacingTarget(actor: actor(court, "H1"), handler: actor(court, "H0"))
        assertPoint(right.x, right.y, 0x4416c000, 0x44134000, "PG spot with the handler right of centre (603, 589)")
        place(court, "H0", 700, 300)
        let left = court.offBallSpacingTarget(actor: actor(court, "H1"), handler: actor(court, "H0"))
        assertPoint(left.x, left.y, 0x443e2000, 0x44134000, "PG spot otherwise (760.5, 589)")
        let interior = court.offBallSpacingTarget(actor: actor(court, "H2"), handler: actor(court, "H0"))
        assertPoint(interior.x, interior.y, 0x4476da8f, 0x43c37333, "INTERIOR seal (always toward -y)")

        actor(court, "H1").role = .WING
        place(court, "H0", 1300, 805); place(court, "H1", 600, 600); place(court, "H2", 1100, 300)
        let now = court.gameTime()
        actor(court, "H1").cutUntil = now + 1000
        actor(court, "H2").cutUntil = now + 1000
        court.updateOffBallOffense(actor: actor(court, "H1"), handler: actor(court, "H0"), now: now)
        court.updateOffBallOffense(actor: actor(court, "H2"), handler: actor(court, "H0"), now: now)
        assertPoint(actor(court, "H1").targetX, actor(court, "H1").targetY, 0x443e8000, 0x43bf0000, "WING cut (762, 382)")
        assertBits(actor(court, "H1").travelScale, 0x3f828f5c, "cut speed 1.02")
        assertPoint(actor(court, "H2").targetX, actor(court, "H2").targetY, 0x44628000, 0x43b30000, "INTERIOR cut (906, 358)")

        let opponents = makeCourt([MAYA, MAYA], [MAYA, MAYA])
        place(opponents, "O1", 600, 450); place(opponents, "O0", 1300, 300)
        actor(opponents, "O1").cutUntil = opponents.gameTime() + 1000
        opponents.updateOffBallOffense(actor: actor(opponents, "O1"), handler: actor(opponents, "O0"), now: opponents.gameTime())
        assertPoint(actor(opponents, "O1").targetX, actor(opponents, "O1").targetY, 0x443e8000, 0x442a0000, "OPPONENT cut (762, 680)")

        let cutter = makeCourt([MAYA, MAYA], [MAYA, MAYA])
        place(cutter, "H1", 600, 600)
        let start = cutter.gameTime()
        actor(cutter, "H1").screenTargetId = "H0"
        actor(cutter, "H1").screenHoldUntil = start + 99
        cutter.beginCut(actor: actor(cutter, "H1"), now: start)
        XCTAssertEqual(actor(cutter, "H1").cutUntil - start, 2000)
        XCTAssertNil(actor(cutter, "H1").screenTargetId)
        XCTAssertEqual(actor(cutter, "H1").screenHoldUntil, 0)
    }

    /// Android 6c38131 (938db79): the screen defender is the nearest opponent; after the 180 ms plant the screener
    /// holds 650 ms and a `screenChance(defense)` draw decides the screen: a success freezes the defender for
    /// 1100 + nextInt(501) ms (and may switch assignments), a failure frees nobody. The handler then takes the roll
    /// draw; a roll cuts 650 ms later on the game clock. Expected draws were computed on the JVM with the 6c38131
    /// BasketballMoves and roster (woman_dark defense 66 -> chance 0.884; coach_67 roll probability 0.58174):
    /// seed 2 = success, freeze 117, no roll; seed 6 = success, freeze 260, roll; seed 10 = failed screen, roll.
    func testScreenPlantsForTheFullDelayThenDrawsTheScreenAndTheRoll() {
        // seed, screen succeeded, freeze draw, roll cut started, cutUntil - t0 after the delayed cut
        let cases: [(Int64, Bool, Int64, Bool, Int64)] = [(2, true, 117, false, 0), (6, true, 260, true, 2141),
                                                          (10, false, 0, true, 2141)]
        for (seed, success, freeze, rolled, cut) in cases {
            let court = makeCourt([MAYA, "coach_67", MAYA], [MAYA, MAYA, MAYA])
            court.random = KotlinRandom(seed: seed)
            court.possession = .HUMAN
            let h0 = actor(court, "H0")
            h0.hasBall = true
            place(court, "H0", 834, 560); place(court, "H1", 834, 500); place(court, "H2", 1300, 300)
            place(court, "O0", 834, 500); place(court, "O1", 400, 300); place(court, "O2", 1300, 805)
            court.defensiveAssignments["O0"] = "H0"
            let h1 = actor(court, "H1")
            h1.screenTargetId = "H0"
            let t0 = court.gameTime()
            court.updateOffBallOffense(actor: h1, handler: h0, now: t0)
            XCTAssertEqual(h1.screenPlantedAt, t0, "contact plants the screen")
            XCTAssertEqual(h1.travelScale, 0)
            XCTAssertEqual(h1.motion, Motion.IDLE)
            court.updateOffBallOffense(actor: h1, handler: h0, now: t0 + 179)
            XCTAssertEqual(h1.screenTargetId, "H0", "not fired before 180 ms")
            court.updateOffBallOffense(actor: h1, handler: h0, now: t0 + 180)
            XCTAssertNil(h1.screenTargetId)
            XCTAssertEqual(h1.screenPlantedAt, 0)
            if success {
                XCTAssertEqual(actor(court, "O0").screenedUntil - t0, 180 + 1100 + freeze, "seed \(seed): defender frozen")
            } else {
                XCTAssertEqual(actor(court, "O0").screenedUntil, 0, "seed \(seed): a failed screen frees nobody")
            }
            XCTAssertEqual(h1.screenCooldownUntil - t0, 2380)
            XCTAssertEqual(h1.screenHoldUntil - t0, 830, "screener holds 650 ms")
            XCTAssertEqual(h1.cutUntil, 0, "seed \(seed): a roll waits 650 ms")
            XCTAssertEqual(court.random.nextInt(), nextIntAfter(seed: seed, draws: success ? 3 : 2),
                           "seed \(seed): screen, freeze (on success) and roll draws")
            AndroidKitTestLoop.advance(millis: 650)
            if rolled {
                XCTAssertEqual(h1.cutUntil - t0, cut, "seed \(seed): the screener rolls")
                XCTAssertEqual(h1.screenHoldUntil, 0, "beginCut clears the hold")
            } else {
                XCTAssertEqual(h1.cutUntil, 0, "seed \(seed): no roll")
                XCTAssertEqual(h1.screenHoldUntil - t0, 830)
            }
        }
    }

    // MARK: - Jumps (spec 12 §4.14)

    func testJumpHeightsDurationsAndDefensiveReset() {
        let golden: [Int: (UInt32, UInt32, UInt32, UInt32, UInt32)] = [
            // contested, uncontested, updateJump at t = .5, at 100 ms, boosted at 200 ms
            1: (0x4283cbc6, 0x425cea4a, 0x427f851f, 0x41ed7dfd, 0x427716e1),   // 65.898 / 55.2288 / 63.88 dp
            2: (0x4303cbc6, 0x42dcea4a, 0x42ff851f, 0x426d7dfd, 0x42f716e1),
            3: (0x4345b1a9, 0x4325afb8, 0x433fa3d7, 0x42b21e7e, 0x43395129),
        ]
        guard let g = golden[Int(density)] else {
            XCTFail("no golden for density \(density)")
            return
        }
        let court = makeCourt([MAYA, "kyra"], ["zephyr", MAYA])
        let now = court.gameTime()
        let h0 = actor(court, "H0")
        court.beginActorJump(actor: h0, contested: true)
        XCTAssertEqual(h0.jumpStarted, now)
        XCTAssertEqual(h0.jumpUntil - h0.jumpStarted, 650)
        assertBits(h0.jumpPx, g.0, "contested initial jump")
        let o1 = actor(court, "O1")
        court.beginActorJump(actor: o1, contested: false)
        XCTAssertEqual(o1.jumpUntil - o1.jumpStarted, 520)
        assertBits(o1.jumpPx, g.1, "uncontested initial jump")
        court.beginActorJump(actor: actor(court, "H1"), contested: false)
        XCTAssertEqual(actor(court, "H1").jumpUntil - actor(court, "H1").jumpStarted, 820, "kyra")
        court.beginActorJump(actor: actor(court, "O0"), contested: true)
        XCTAssertEqual(actor(court, "O0").jumpUntil - actor(court, "O0").jumpStarted, 820, "zephyr")
        court.updateJump(actor: h0, now: h0.jumpStarted + 325)
        assertBits(h0.jumpPx, g.2, "sine peak")
        court.updateJump(actor: h0, now: h0.jumpStarted + 100)
        assertBits(h0.jumpPx, g.3, "sine at 100 ms")
        h0.boost01 = 0.35
        court.updateJump(actor: h0, now: h0.jumpStarted + 200)
        assertBits(h0.jumpPx, g.4, "boosted sine at 200 ms")
        court.updateJump(actor: h0, now: h0.jumpUntil)
        XCTAssertEqual(h0.jumpPx, 0)

        // Defensive jump: pose, lock = jumpUntil, reset posted at jumpUntil - started + 20 on the game clock.
        court.beginDefensiveJump(actor: o1, motion: .BLOCK)
        XCTAssertEqual(o1.motion, Motion.BLOCK)
        XCTAssertEqual(o1.actionLockUntil, o1.jumpUntil)
        XCTAssertEqual(o1.jumpUntil - o1.jumpStarted, 650)
        AndroidKitTestLoop.advance(millis: 669)
        XCTAssertEqual(o1.motion, Motion.BLOCK)
        AndroidKitTestLoop.advance(millis: 1)
        XCTAssertEqual(o1.motion, Motion.IDLE)
        XCTAssertEqual(o1.actionLockUntil, 0)
    }

    // MARK: - Random draw order (spec 12 §4.5, §4.6, §8.4)

    func testPumpFakeDrawsExactlyOnceAndResetsAfter430Ms() {
        let cases: [(Int64, Bool)] = [(3, false), (11, true), (99, false)]
        for (seed, bites) in cases {
            let court = makeCourt([MAYA, MAYA], [MAYA, MAYA])
            court.random = KotlinRandom(seed: seed)
            let now = court.gameTime()
            let o0 = actor(court, "O0")
            o0.hasBall = true
            let h1 = actor(court, "H1")
            court.startAiPumpFake(handler: o0, defender: h1, now: now)
            XCTAssertEqual(o0.motion, Motion.SHOT_LOW)
            XCTAssertEqual(o0.actionLockUntil, now + 520)
            XCTAssertEqual(h1.motion, bites ? Motion.BLOCK : Motion.IDLE, "seed \(seed)")
            XCTAssertEqual(h1.screenedUntil, bites ? now + 420 : 0, "seed \(seed)")
            XCTAssertEqual(court.random.nextInt(), nextIntAfter(seed: seed, draws: 1), "seed \(seed): one draw")
            AndroidKitTestLoop.advance(millis: 429)
            XCTAssertEqual(o0.motion, Motion.SHOT_LOW)
            AndroidKitTestLoop.advance(millis: 1)
            XCTAssertEqual(o0.motion, Motion.DRIBBLE, "seed \(seed): the fake ends after 430 ms")
        }
        let noBall = makeCourt([MAYA, MAYA], [MAYA, MAYA])
        noBall.random = KotlinRandom(seed: 3)
        noBall.startAiPumpFake(handler: actor(noBall, "O0"), defender: actor(noBall, "H1"), now: noBall.gameTime())
        XCTAssertEqual(noBall.random.nextInt(), nextIntAfter(seed: 3, draws: 0), "no ball: no draw")
        XCTAssertEqual(actor(noBall, "O0").motion, Motion.IDLE)
    }

    func testPumpFakeResetKeepsItsGuard() {
        let court = makeCourt([MAYA, MAYA], [MAYA, MAYA])
        court.random = KotlinRandom(seed: 3)
        let o0 = actor(court, "O0")
        o0.hasBall = true
        court.startAiPumpFake(handler: o0, defender: actor(court, "H1"), now: court.gameTime())
        o0.hasBall = false
        AndroidKitTestLoop.advance(millis: 500)
        XCTAssertEqual(o0.motion, Motion.SHOT_LOW, "the 430 ms reset only runs while the handler still has the ball")
    }

    func testAiStealRetryGateReachAndSingleDraw() {
        // (aggression, ms since the last attempt, commits): retry = max(560, (980 - a * 360).toLong()).
        let cases: [(Float, Int64, Bool)] = [
            (0, 979, false), (0, 980, true), (0.45, 817, false), (0.45, 818, true),
            (0.55, 781, false), (0.55, 782, true), (1, 619, false), (1, 620, true),
        ]
        for (aggression, back, commits) in cases {
            let court = makeCourt([MAYA, MAYA], [MAYA, MAYA])
            court.random = KotlinRandom(seed: 7)
            let now = court.gameTime()
            let h0 = actor(court, "H0")
            h0.hasBall = true
            h0.possessionReceivedAt = now - 5000
            h0.lastMeaningfulMovementAt = now - 5000
            place(court, "H0", 800, 500); place(court, "O0", 860, 520)
            let o0 = actor(court, "O0")
            o0.lastStealAttempt = now - back
            assertBits(court.floorDistance(a: o0, b: h0), 0x3f8a55b5, "gap 1.0807406 m")
            court.maybeAttemptAiSteal(defender: o0, handler: h0, now: now, aggression01: aggression)
            let label = "aggression \(aggression) after \(back) ms"
            XCTAssertEqual(court.random.nextInt(), nextIntAfter(seed: 7, draws: commits ? 1 : 0), label)
            XCTAssertEqual(o0.motion, commits ? Motion.STEAL : Motion.IDLE, label)
            XCTAssertEqual(o0.lastStealAttempt, commits ? now : now - back, label)
            if commits {
                XCTAssertEqual(o0.actionLockUntil, now + 390, label)
                XCTAssertEqual(o0.facing, Facing.SIDE, label)
                XCTAssertEqual(h0.actionLockUntil, 0, "seed 7 fails the roll: no transfer lock")
                AndroidKitTestLoop.advance(millis: 390)
                XCTAssertEqual(o0.motion, Motion.IDLE, "failed steal pose resets after 390 ms")
                XCTAssertTrue(h0.hasBall)
            }
        }
        // A moving human handler (idle < 900 ms) is only reached within 0.9 m.
        let court = makeCourt([MAYA, MAYA], [MAYA, MAYA])
        court.random = KotlinRandom(seed: 7)
        let now = court.gameTime()
        let h0 = actor(court, "H0")
        h0.hasBall = true
        h0.possessionReceivedAt = now - 100
        h0.lastMeaningfulMovementAt = now - 100
        place(court, "H0", 800, 500); place(court, "O0", 860, 520)
        court.maybeAttemptAiSteal(defender: actor(court, "O0"), handler: h0, now: now)
        XCTAssertEqual(court.random.nextInt(), nextIntAfter(seed: 7, draws: 0))
        XCTAssertEqual(actor(court, "O0").motion, Motion.IDLE)
    }

    func testOffBallPlanningDrawOrder() {
        // (seed, screen target after the call): one draw each (the cut branch never reaches its roll here).
        let cases: [(Int64, String?)] = [(5, nil), (8, nil), (13, nil), (21, "H0")]
        for (seed, screen) in cases {
            let court = makeCourt([MAYA, "coach_67", MAYA], [MAYA, MAYA, MAYA])
            court.random = KotlinRandom(seed: seed)
            let now = court.gameTime()
            court.possession = .HUMAN
            court.possessionStartedAt = now - 5000
            court.trackedHandlerSince = now - 2000
            actor(court, "H1").role = .INTERIOR
            let h0 = actor(court, "H0")
            h0.hasBall = true
            place(court, "H0", 834, 560); place(court, "H1", 700, 520); place(court, "H2", 1100, 600)
            place(court, "O0", 834, 500); place(court, "O1", 700, 430); place(court, "O2", 1100, 450)
            court.defensiveAssignments["O0"] = "H0"
            court.defensiveAssignments["O1"] = "H1"
            court.defensiveAssignments["O2"] = "H2"
            let h1 = actor(court, "H1")
            court.maybePlanOffBallAction(actor: h1, handler: h0, now: now)
            XCTAssertEqual(h1.lastAiDecision, now)
            XCTAssertEqual(h1.screenTargetId, screen, "seed \(seed)")
            XCTAssertEqual(h1.actionLockUntil, screen == nil ? 0 : now + 950, "seed \(seed)")
            XCTAssertEqual(h1.cutUntil, 0, "seed \(seed)")
            XCTAssertEqual(court.random.nextInt(), nextIntAfter(seed: seed, draws: 1), "seed \(seed): one draw")
            // The 680 ms gate (lastAiDecision, shared with the handler gate): a call 679 ms later draws nothing.
            // Two values are consumed so far (the call's draw and the check above).
            court.maybePlanOffBallAction(actor: h1, handler: h0, now: now + 679)
            XCTAssertEqual(h1.lastAiDecision, now)
            XCTAssertEqual(court.random.nextInt(), nextIntAfter(seed: seed, draws: 2), "seed \(seed): gated, no draw")
        }
    }

    // MARK: - Facing (spec 12 §4.13)

    func testFacingRules() {
        let court = makeCourt([MAYA, MAYA], [MAYA, MAYA])
        XCTAssertEqual(court.facingForVelocity(dx: 3, dy: 1), Facing.SIDE)
        XCTAssertEqual(court.facingForVelocity(dx: 1, dy: -3), Facing.BACK)
        XCTAssertEqual(court.facingForVelocity(dx: 1, dy: 3), Facing.FRONT)
        XCTAssertEqual(court.facingForVelocity(dx: 0.8, dy: 1), Facing.FRONT, "|dx| must exceed |dy| * 0.8")
        XCTAssertEqual(court.facingForVelocity(dx: -0.81, dy: -1), Facing.SIDE)
        let h1 = actor(court, "H1")
        place(court, "H1", 500, 500)
        XCTAssertEqual(court.facingTowardPoint(actor: h1, targetX: 600, targetY: 400), Facing.SIDE)
        XCTAssertEqual(court.facingTowardPoint(actor: h1, targetX: 591, targetY: 400), Facing.BACK)
        XCTAssertEqual(court.facingTowardPoint(actor: h1, targetX: 591, targetY: 600), Facing.FRONT)
        h1.facing = .SIDE
        XCTAssertEqual(court.stableIdleFacingTowardPoint(actor: h1, targetX: 900, targetY: 510), Facing.BACK)
        h1.facing = .FRONT
        XCTAssertEqual(court.stableIdleFacingTowardPoint(actor: h1, targetX: 900, targetY: 482), Facing.FRONT, "18 px dead band")
        XCTAssertEqual(court.stableIdleFacingTowardPoint(actor: h1, targetX: 900, targetY: 481), Facing.BACK)
        let o1 = actor(court, "O1")
        o1.facing = .SIDE
        place(court, "O1", 500, 500)
        XCTAssertEqual(court.stableIdleFacingTowardPoint(actor: o1, targetX: 100, targetY: 518), Facing.FRONT)
        XCTAssertEqual(court.facingTowardAttackingHoop(actor: h1), Facing.BACK)
        XCTAssertEqual(court.facingTowardAttackingHoop(actor: o1), Facing.FRONT)
        // A ball holder always faces the attacking hoop; a defender reads the opposing handler.
        let o0 = actor(court, "O0")
        o0.hasBall = true
        XCTAssertEqual(court.basketballFacing(actor: o0, moveDx: 5, moveDy: 0), Facing.FRONT)
        place(court, "O0", 500, 300)
        h1.facing = .FRONT
        XCTAssertEqual(court.basketballFacing(actor: h1, moveDx: 5, moveDy: 0), Facing.BACK, "defender faces the handler")
    }

    // MARK: - Ball flight animator (spec 12 §4.9)

    func testBallArcAnimatorSyncStartEndAndCancel() {
        let court = makeCourt([MAYA, MAYA], [MAYA, MAYA])
        court.ballVisible = true
        court.ballInFlight = true
        court.ballFlightKind = .PASS
        var ended = 0
        var frames: [Float] = []
        court.animateBallArcSource(start: APointF(600, 500), end: APointF(800, 400), durationMs: 300, apexSource: 38,
                                   cameraArcFollow01: 0.04, onFrame: { t, _ in frames.append(t) }) { ended += 1 }
        XCTAssertEqual(frames, [0], "start() delivers the t = 0 update synchronously")
        XCTAssertEqual(court.ballSourceX, 600)
        XCTAssertEqual(court.ballSourceY, 500)
        XCTAssertNotNil(court.ballAnimator)
        AndroidKitTestLoop.advance(millis: 400)
        XCTAssertEqual(ended, 1)
        XCTAssertNil(court.ballAnimator)
        XCTAssertEqual(frames.last, 1)
        XCTAssertEqual(court.ballSourceX, 800)
        XCTAssertEqual(court.ballSourceY, 400)

        // cancel(): no onEnd, the animator is dropped.
        court.animateBallArcSource(start: APointF(600, 500), end: APointF(800, 400), durationMs: 300,
                                   apexSource: 38) { ended += 1 }
        AndroidKitTestLoop.advance(millis: 100)
        court.cancelBallAnimator()
        XCTAssertNil(court.ballAnimator)
        AndroidKitTestLoop.advance(millis: 400)
        XCTAssertEqual(ended, 1, "a cancelled flight never runs onEnd")

        // A new flight replaces the running one without its onEnd, and onEnd may start the next flight.
        var chained = 0
        court.animateBallArcSource(start: APointF(600, 500), end: APointF(700, 450), durationMs: 110, apexSource: 0) {
            court.animateBallArcSource(start: APointF(700, 450), end: APointF(800, 400), durationMs: 245,
                                       apexSource: 38) { chained += 1 }
            XCTAssertNotNil(court.ballAnimator, "the nested flight is running")
        }
        AndroidKitTestLoop.advance(millis: 600)
        XCTAssertEqual(chained, 1)
        XCTAssertNil(court.ballAnimator)
        XCTAssertEqual(court.ballSourceX, 800)
        XCTAssertEqual(court.ballSourceY, 400)
    }

    // MARK: - Companion object (spec 12 §7.1)

    func testCompanionConstantsKeepTheKotlinValues() {
        XCTAssertEqual(Court.FULL_COURT_CENTER_X, 836)
        XCTAssertEqual(Court.FULL_COURT_CENTER_Y, 470.5)
        XCTAssertEqual(Court.SUNSET_GEOMETRY.top.rimY, 210)
        XCTAssertEqual(Court.SUNSET_GEOMETRY.top.footY, 304)
        XCTAssertEqual(Court.SUNSET_GEOMETRY.bottom.rimY, 620)
        XCTAssertEqual(Court.SUNSET_GEOMETRY.bottom.footY, 758)
        XCTAssertEqual(Court.NEON_FALLS_GEOMETRY.top.footY, 338)
        XCTAssertEqual(Court.NEON_FALLS_GEOMETRY.bottom.rimY, 672)
        XCTAssertEqual(Court.SOURCE_PLAY_MIN_X, 309)
        XCTAssertEqual(Court.SOURCE_PLAY_MAX_Y, 805)
        XCTAssertEqual(Court.TEAM_FRAME_MS, 32)
        XCTAssertEqual(Court.TEAM_DRIBBLE_PERIOD_MS, 740)
        XCTAssertEqual(Court.STEAL_TRANSFER_DELAY_MS, 150)
        XCTAssertEqual(Court.TEAM_FULL_COURT_STYLE_IDS, ["sunset_pulse", "sunset_cove", "neon_tide", "neon_falls"])
        XCTAssertEqual(Court.FULL_COURT_STYLE_ID, "sunset_pulse")
    }
}
