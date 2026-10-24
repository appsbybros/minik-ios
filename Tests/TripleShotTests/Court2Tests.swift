import XCTest
@testable import MinikTripleShot

// Area w-court2: TripleShotCourtView+Part2.swift (Kotlin TripleShotCourtView.kt 2655-5347, spec 09-court2).
//
// Golden vectors were produced on the JVM (kotlin-stdlib 2.3.21) by a harness that copies the Kotlin formulas of
// this range verbatim (work/w-court2/harness/Court2Golden.kt, Timings.kt). Every Float is compared bit for bit.
// Values that go through dp() exist for densities 1, 2 and 3 (index 0, 1, 2); other densities skip those tests.
// The court is used unattached and unlaid-out (width = height = 0) unless stated: none of the functions under test
// needs a layout, and AndroidKitTestLoop's fake clock makes every System.nanoTime() deadline exact.
final class Court2Tests: XCTestCase {
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

    private func densityIndex(_ court: TripleShotCourtView) throws -> Int {
        switch court.density {
        case 1: return 0
        case 2: return 1
        case 3: return 2
        default: throw XCTSkip("golden vectors exist for densities 1, 2 and 3, not \(court.density)")
        }
    }

    private func f(_ bits: UInt32) -> Float { return Float(bitPattern: bits) }

    private func makeShotState(x: Float, y: Float, vx: Float, vy: Float) -> TripleShotPhysics.ShotState {
        return TripleShotPhysics.ShotState(
            x: x, y: y, vx: vx, vy: vy,
            startX: x, startY: y, targetX: 610, targetY: 520,
            initialVx: vx, initialVy: vy, gravity: 2000, expectedFlightSeconds: 1,
            pathMode: .NORMAL, initialCurveAccelerationX: 0
        )
    }

    // MARK: - Steal deflection (Kotlin 4333-4377): seeded Random(Int) + wrapping Long seed, 4 draws

    private struct DeflectionCase {
        let serial0: Int64
        let ballX: UInt32, ballY: UInt32, stealerX: UInt32, stealerY: UInt32
        let vx: [UInt32]   // density 1, 2, 3
        let vy: [UInt32]
    }

    private static let deflectionCases: [DeflectionCase] = [
        // bucket 0.402 (second speed band)
        DeflectionCase(serial0: 0, ballX: 0x4407_2000, ballY: 0x4497_4800, stealerX: 0x4416_0000, stealerY: 0x44A2_8000,
                       vx: [0x423B_0152, 0x42D2_E5DB, 0x432F_87D6], vy: [0x4241_9DA6, 0x42B6_3702, 0x42F6_CBB7]),
        // bucket 0.783 (third band)
        DeflectionCase(serial0: 1, ballX: 0x439C_6000, ballY: 0x44BA_0400, stealerX: 0x4382_0000, stealerY: 0x44C3_2000,
                       vx: [0xC14A_7727, 0xC273_785B, 0xC31C_CEE9], vy: [0x42A0_D88E, 0x431D_78F5, 0x435E_AF5B]),
        // bucket 0.757 (third band), inexact decimal inputs
        DeflectionCase(serial0: 2, ballX: 0x4448_551F, ballY: 0x44A6_B666, stealerX: 0x4461_999A, stealerY: 0x44AF_5CCD,
                       vx: [0x4298_B1CB, 0x4311_DDF9, 0x4347_EF09], vy: [0x424F_30B0, 0x42BD_B5D0, 0x4300_AEBF]),
        // bucket 0.097 (first band)
        DeflectionCase(serial0: 5, ballX: 0x43E3_8000, ballY: 0x44C8_0000, stealerX: 0x43BE_0000, stealerY: 0x44CB_C000,
                       vx: [0xC261_4E97, 0xC2EB_4E04, 0xC32C_5478], vy: [0x4249_BA1E, 0x42B4_D890, 0x42F1_B60F]),
        // bucket 0.691 (third band, just above 0.68)
        DeflectionCase(serial0: 9, ballX: 0x447A_0800, ballY: 0x449C_5000, stealerX: 0x446B_0000, stealerY: 0x44A1_E000,
                       vx: [0xC2A3_889C, 0xC30F_57FC, 0xC321_154C], vy: [0x4200_5EA1, 0x423F_0C56, 0x424A_3010]),
        // bucket 0.638 (second band)
        DeflectionCase(serial0: 41, ballX: 0x42F6_E979, ballY: 0x44DE_2000, stealerX: 0x435E_0000, stealerY: 0x44E1_0000,
                       vx: [0x4295_24B6, 0x430E_34D7, 0x4343_C222], vy: [0x4257_E14C, 0x42C3_E01F, 0x4305_C506]),
        // stealer on top of the ball (len clamps to 1)
        DeflectionCase(serial0: 1000, ballX: 0x4420_0000, ballY: 0x44AF_0000, stealerX: 0x4420_0000, stealerY: 0x44AF_0000,
                       vx: [0xC137_A96C, 0xC1B7_A96C, 0xC209_BF11], vy: [0x41B2_A317, 0x4232_A317, 0x4285_FA52]),
        // bucket 0.895 and 0.954 (fourth band); ball (720.25, 1350.5), stealer (640, 1420)
        DeflectionCase(serial0: 4, ballX: 0x4434_1000, ballY: 0x44A8_D000, stealerX: 0x4420_0000, stealerY: 0x44B1_8000,
                       vx: [0x4121_CA55, 0xC17B_4EE0, 0xC2AA_8026], vy: [0x4292_153D, 0x4312_3CC5, 0x4356_FFE2]),
        DeflectionCase(serial0: 7, ballX: 0x4434_1000, ballY: 0x44A8_D000, stealerX: 0x4420_0000, stealerY: 0x44B1_8000,
                       vx: [0xC27D_1DBE, 0xC2D7_28A5, 0xC2EF_F069], vy: [0x4224_3BD3, 0x4294_397E, 0x42C7_CEFB])
    ]

    func testStealDeflectionMatchesKotlinGoldenVectors() throws {
        let court = TripleShotCourtView()
        let d = try densityIndex(court)
        for c in Self.deflectionCases {
            for stealerHuman in [true, false] {
                court.oneOnOneEnabled = true
                court.oneOnOneLooseEventSerial = c.serial0
                court.sharedHorseBallOwner = stealerHuman ? .BOT : .HUMAN
                if stealerHuman {
                    court.playerX = f(c.stealerX)
                    court.playerFootY = f(c.stealerY)
                } else {
                    court.botX = f(c.stealerX)
                    court.botFootY = f(c.stealerY)
                }
                var states: [TripleShotCourtView.OneOnOneBallState] = []
                court.oneOnOneAutomaticBallStateListener = { states.append($0) }

                court.startOneOnOneStealDeflection(liveBall: APointF(f(c.ballX), f(c.ballY)), stealerHuman: stealerHuman)

                let label = "serial0=\(c.serial0) stealerHuman=\(stealerHuman)"
                XCTAssertEqual(court.oneOnOneLooseEventSerial, c.serial0 + 1, label)
                XCTAssertEqual(court.oneOnOneLooseBallVx.bitPattern, c.vx[d], label)
                XCTAssertEqual(court.oneOnOneLooseBallVy.bitPattern, c.vy[d], label)
                XCTAssertEqual(states, [.LOOSE], label)
                XCTAssertTrue(court.oneOnOneLooseBallActive, label)
                XCTAssertNil(court.sharedHorseBallOwner, label)
                XCTAssertEqual(court.oneOnOneLooseBallLastOwnerHuman, !stealerHuman, label)
                XCTAssertEqual(court.oneOnOneLooseBallClaimDelaySeconds, Float(0.28), label)
                XCTAssertEqual(court.oneOnOneLooseBallAgeSeconds, 0, label)
                XCTAssertEqual(court.ballX.bitPattern, c.ballX, label)
                XCTAssertEqual(court.ballY.bitPattern, c.ballY, label)
                XCTAssertTrue(court.ballVisible, label)
                XCTAssertFalse(court.botBallVisible, label)

                court.oneOnOneAutomaticBallStateListener = nil
                court.stopOneOnOneLooseBall()
            }
        }
    }

    func testLooseBallKeepsPreviousLastOwnerWhenNobodyOwnsTheBall() {
        let court = TripleShotCourtView()
        court.oneOnOneEnabled = true
        court.sharedHorseBallOwner = .HUMAN
        court.startOneOnOneLooseBall(x: 300, y: 1200, vx: 40, vy: -90)
        XCTAssertNotNil(court.worldLooseBall, "6c38131: the rebound also lives in world metres")
        XCTAssertEqual(court.oneOnOneLooseBallLastOwnerHuman, true)
        XCTAssertEqual(court.oneOnOneLooseBallClaimDelaySeconds, Float(0.18))
        XCTAssertEqual(court.oneOnOneLooseBallVx, 40)
        XCTAssertEqual(court.oneOnOneLooseBallVy, -90)
        // Owner is now null: a second loose start keeps the last known owner (Kotlin `null -> lastOwnerHuman`).
        court.startOneOnOneLooseBall(x: 310, y: 1210, vx: 1, vy: 2, claimDelaySeconds: -1, gravityPxPerSec2: 777)
        XCTAssertEqual(court.oneOnOneLooseBallLastOwnerHuman, true)
        XCTAssertEqual(court.oneOnOneLooseBallClaimDelaySeconds, 0)
        XCTAssertEqual(court.oneOnOneLooseBallGravityPxPerSec2, 777)
        // A non-positive gravity falls back to height * 1.52 (0 for this unlaid-out view).
        court.startOneOnOneLooseBall(x: 310, y: 1210, vx: 1, vy: 2, gravityPxPerSec2: 0)
        XCTAssertEqual(court.oneOnOneLooseBallGravityPxPerSec2, Float(court.height) * 1.52)

        let start = CourtPoint(x: 1, y: 2, z: 3)
        court.startOneOnOneLooseBall(x: 310, y: 1210, vx: 1, vy: 2, worldStart: start, worldVelocity: CourtPoint(x: 0, y: 0, z: 0))
        XCTAssertEqual(court.worldLooseBall?.position, start, "an explicit world start is used as it is")

        court.stopOneOnOneLooseBall()
        XCTAssertNil(court.worldLooseBall)
        XCTAssertFalse(court.oneOnOneLooseBallActive)
        XCTAssertEqual(court.oneOnOneLooseBallVx, 0)
        XCTAssertEqual(court.oneOnOneLooseBallGravityPxPerSec2, 0)
        XCTAssertEqual(court.oneOnOneLooseBallClaimDelaySeconds, Float(0.18))
        XCTAssertEqual(court.oneOnOneLooseBallLastOwnerHuman, true)

        // Disabled 1v1: nothing happens at all.
        court.oneOnOneEnabled = false
        court.startOneOnOneLooseBall(x: 1, y: 1, vx: 1, vy: 1)
        XCTAssertFalse(court.oneOnOneLooseBallActive)
    }

    // MARK: - Hand reflection and block kick (Kotlin 4857-4901)

    private struct ReflectionCase {
        let x: Float, y: Float, vx: Float, vy: Float, handX: Float, handY: Float
        /// The collision radius is the sum of dp() of these values, added in order (Kotlin `dp(a) + dp(b)`).
        let radiusDps: [Float]
        let hit: [Bool]
        let outVx: [UInt32], outVy: [UInt32]
        let kickVx: [UInt32], kickVy: [UInt32]
    }

    private static let reflectionCases: [ReflectionCase] = [
        ReflectionCase(x: 500, y: 900, vx: 120, vy: -1400, handX: 505, handY: 930,
                       radiusDps: [12.5, 4 + 6 * 0.5],
                       hit: [false, true, true],
                       outVx: [0x42F0_0000, 0xC27A_F3A0, 0xC2A2_AEA3], outVy: [0xC4AF_0000, 0xC510_8A53, 0xC511_C5F8],
                       kickVx: [0, 0xC2BB_F055, 0xC300_3036], kickVy: [0, 0xC50C_0C13, 0xC50B_0898]),
        ReflectionCase(x: 500, y: 900, vx: -60, vy: -900, handX: 470, handY: 880,
                       radiusDps: [40],
                       hit: [true, true, true],
                       outVx: [0x4425_ABA7, 0x442E_FEB0, 0x4438_51B8], outVy: [0xC3D7_FDD1, 0xC3D2_71C8, 0xC3CC_E5C0],
                       kickVx: [0x4421_C43F, 0x4427_2FDF, 0x442C_9B7F], kickVy: [0xC3C6_04D2, 0xC3AE_7FC9, 0xC396_FAC2]),
        // Ball exactly on the hand: dist clamps to 0.5 and the normal is (0, 0).
        ReflectionCase(x: 700, y: 600, vx: 0, vy: 0, handX: 700, handY: 600,
                       radiusDps: [20],
                       hit: [true, true, true],
                       outVx: [0x4160_0000, 0x41E0_0000, 0x4228_0000], outVy: [0, 0, 0],
                       kickVx: [0x425F_E5E5, 0x42DF_E5E5, 0x4327_EC6C], kickVy: [0x419A_7C44, 0x421A_7C44, 0x4267_BA66]),
        // Ball moving away from the hand (dot >= -1): the fallback impact -0.42 * |v| is used.
        ReflectionCase(x: 700, y: 600, vx: 300, vy: 200, handX: 690, handY: 610,
                       radiusDps: [20],
                       hit: [true, true, true],
                       outVx: [0x43F7_3583, 0x4404_0DE4, 0x440C_8107], outVy: [0x41C9_E900, 0x4131_8BD0, 0xC042_E980],
                       kickVx: [0x4406_1920, 0x4419_0AA1, 0x442B_FC22], kickVy: [0x4232_32A2, 0x4246_DF38, 0x425B_8BCE])
    ]

    func testHandReflectionAndBlockKickMatchKotlin() throws {
        let court = TripleShotCourtView()
        let d = try densityIndex(court)
        let geometry = TripleShotPhysics.Geometry(
            gravityPxPerSec2: 2000, hoopCenterX: 610, hoopY: 520, leftRimX: 560, rightRimX: 660,
            rimColliderRadius: 5, backboardX: 700, backboardTopY: 400, backboardBottomY: 600, netBottomY: 640,
            netBottomLeftX: 580, netBottomRightX: 640, ballRadius: 25
        )
        for (i, c) in Self.reflectionCases.enumerated() {
            let state = makeShotState(x: c.x, y: c.y, vx: c.vx, vy: c.vy)
            state.previousX = -1
            state.previousY = -1
            var radius: Float = 0
            for (n, v) in c.radiusDps.enumerated() { radius = n == 0 ? court.dp(v: v) : radius + court.dp(v: v) }
            let hit = court.reflectBallFromDefenderHand(
                state: state, handX: c.handX, handY: c.handY, collisionRadius: radius
            )
            XCTAssertEqual(hit, c.hit[d], "case \(i)")
            XCTAssertEqual(state.vx.bitPattern, c.outVx[d], "case \(i)")
            XCTAssertEqual(state.vy.bitPattern, c.outVy[d], "case \(i)")
            if hit {
                // previousX/Y are reset so the same sub-step cannot report a false plane crossing.
                XCTAssertEqual(state.previousX, c.x, "case \(i)")
                XCTAssertEqual(state.previousY, c.y, "case \(i)")
                court.kickBlockedBallAwayFromHoop(state: state, geometry: geometry, strength: 0.72)
                XCTAssertEqual(state.vx.bitPattern, c.kickVx[d], "case \(i)")
                XCTAssertEqual(state.vy.bitPattern, c.kickVy[d], "case \(i)")
            } else {
                XCTAssertEqual(state.previousX, -1, "case \(i)")
            }
        }
    }

    // MARK: - Jump model, rating scale, body radius (Kotlin 4106-4112, 4721-4739)

    func testJumpProfileRatingScaleAndBodyRadiusMatchKotlin() throws {
        let court = TripleShotCourtView()
        let d = try densityIndex(court)
        let started: Int64 = 1_000_000_000
        let until = started + 470_000_000
        let offsets: [(Int64, [UInt32])] = [
            (0, [0, 0, 0]),
            (117_500_000, [0x4198_BC2D, 0x4218_BC2D, 0x4265_1A44]),
            (235_000_000, [0x41D8_0000, 0x4258_0000, 0x42A2_0000]),
            (352_500_000, [0x4198_BC2D, 0x4218_BC2D, 0x4265_1A44]),
            (469_999_999, [0x276E_4304, 0x27EE_4304, 0x2832_B243]),
            (470_000_000, [0, 0, 0])
        ]
        for (k, expected) in offsets {
            XCTAssertEqual(
                court.oneOnOneJumpOffsetPx(now: started + k, started: started, until: until).bitPattern,
                expected[d],
                "now = started + \(k)"
            )
        }
        XCTAssertEqual(court.oneOnOneJumpOffsetPx(now: started, started: 0, until: until), 0)       // never started
        XCTAssertEqual(court.oneOnOneJumpOffsetPx(now: started, started: until, until: until), 0)   // empty window
        XCTAssertEqual(court.oneOnOneJumpOffsetPx(now: until + 1, started: started, until: until), 0)

        let scales: [(Int, UInt32)] = [
            (-10, 0x3F47_AE14), (0, 0x3F47_AE14), (25, 0x3F63_D70A), (49, 0x3F7E_DFA4), (50, 0x3F80_0000),
            (51, 0x3F80_C49C), (75, 0x3F93_3333), (100, 0x3FA6_6666), (140, 0x3FA6_6666)
        ]
        for (rating, expected) in scales {
            XCTAssertEqual(court.oneOnOneJumpRatingScale(rating: rating).bitPattern, expected, "rating \(rating)")
        }

        // The physical jump composes profile * multiplier * rating scale (Kotlin 4721-4727).
        court.oneOnOneHumanJumpStartedAtNanos = started
        court.oneOnOneHumanJumpUntilNanos = until
        court.oneOnOneHumanJumpHeightMultiplier = 2.34
        court.oneOnOneHumanJumpRating = 75
        XCTAssertEqual(
            court.oneOnOneHumanJumpOffsetPx(now: started + 117_500_000).bitPattern,
            (court.oneOnOneJumpOffsetPx(now: started + 117_500_000, started: started, until: until) * Float(2.34) *
                court.oneOnOneJumpRatingScale(rating: 75)).bitPattern
        )
        court.oneOnOneBotJumpStartedAtNanos = started
        court.oneOnOneBotJumpUntilNanos = until
        court.oneOnOneBotJumpHeightMultiplier = 5.20
        court.oneOnOneBotJumpRating = 0
        XCTAssertEqual(
            court.oneOnOneBotJumpOffsetPx(now: started + 235_000_000).bitPattern,
            (court.oneOnOneJumpOffsetPx(now: started + 235_000_000, started: started, until: until) * Float(5.20) *
                court.oneOnOneJumpRatingScale(rating: 0)).bitPattern
        )

        let radii: [(Int, Int, Int, UInt32)] = [
            (50, 50, 50, 0x41D2_0000), (0, 0, 0, 0x41B0_0000), (100, 100, 100, 0x41F4_0000),
            (90, 70, 85, 0x41E9_52F2), (30, 60, 20, 0x41C6_2B02)
        ]
        for (height, strength, weight, expected) in radii {
            court.oneOnOneHumanHeightRating = height
            court.oneOnOneHumanStrengthRating = strength
            court.oneOnOneHumanWeightRating = weight
            court.oneOnOneBotHeightRating = height
            court.oneOnOneBotStrengthRating = strength
            court.oneOnOneBotWeightRating = weight
            XCTAssertEqual(court.oneOnOneBodyRadiusDp(human: true).bitPattern, expected, "human \(height)/\(strength)/\(weight)")
            XCTAssertEqual(court.oneOnOneBodyRadiusDp(human: false).bitPattern, expected, "bot \(height)/\(strength)/\(weight)")
        }
    }

    // MARK: - Rebound candidates (Kotlin 4587-4639); unlaid-out view, so oneOnOneBoxOutOwner() == null

    /// Android 6c38131 (1ddda77): the candidate is the world loose ball against the feet's world point: no candidate
    /// above 1.45 m (2.1 m + the jump while jumping), beyond 0.85 m horizontally or younger than 0.12 s; the score is
    /// horizontal / 0.85 minus 0.04 while jumping. The cases put the ball exactly on the feet (horizontal 0), so the
    /// scores are exact, or clearly inside / outside the limits.
    func testReboundCandidateUsesTheWorldBallAndFeet() {
        let court = TripleShotCourtView()
        court.layout(0, 0, 1080, 2400)
        court.oneOnOneEnabled = true
        court.oneOnOneLooseBallActive = true
        XCTAssertNil(court.oneOnOneBoxOutOwner())
        let now: Int64 = 1_000_000_000_000
        for human in [true, false] {
            if human { court.playerX = 500; court.playerFootY = 1500 } else { court.botX = 500; court.botFootY = 1500 }
            court.oneOnOneHumanJumpUntilNanos = 0
            court.oneOnOneBotJumpUntilNanos = 0
            let foot = court.worldGround(x: 500, y: 1500)
            func place(_ dx: Float, _ y: Float, age: Float) {
                court.worldLooseBall = TripleShotLooseBall(start: CourtPoint(x: foot.x + dx, y: y, z: foot.z),
                                                           velocity: CourtPoint(x: 0, y: 0, z: 0), gravity: 9.8)
                court.oneOnOneLooseBallAgeSeconds = age
            }
            let label = "human=\(human)"
            court.worldLooseBall = nil
            XCTAssertNil(court.oneOnOneReboundCandidate(human: human, now: now), "no world ball: \(label)")
            place(0, TripleShotLooseBall.RADIUS, age: 0.5)
            let onFeet = court.oneOnOneReboundCandidate(human: human, now: now)
            XCTAssertEqual(onFeet?.score, 0, label)
            XCTAssertEqual(onFeet?.human, human, label)
            place(0, TripleShotLooseBall.RADIUS, age: 0.10)
            XCTAssertNil(court.oneOnOneReboundCandidate(human: human, now: now), "younger than 0.12 s: \(label)")
            place(0.9, TripleShotLooseBall.RADIUS, age: 0.5)
            XCTAssertNil(court.oneOnOneReboundCandidate(human: human, now: now), "0.9 m away: \(label)")
            place(0.425, TripleShotLooseBall.RADIUS, age: 0.5)
            XCTAssertEqual(court.oneOnOneReboundCandidate(human: human, now: now)?.score ?? -1, 0.5, accuracy: 0.0005, label)
            place(0, 1.6, age: 0.5)
            XCTAssertNil(court.oneOnOneReboundCandidate(human: human, now: now), "1.6 m without a jump: \(label)")
            // Jumping: the reach rises to 2.1 m (+ the jump) and the score drops by 0.04.
            if human {
                court.oneOnOneHumanJumpStartedAtNanos = now - 100_000_000
                court.oneOnOneHumanJumpUntilNanos = now + 300_000_000
            } else {
                court.oneOnOneBotJumpStartedAtNanos = now - 100_000_000
                court.oneOnOneBotJumpUntilNanos = now + 300_000_000
            }
            XCTAssertEqual(court.oneOnOneReboundCandidate(human: human, now: now)?.score, -Float(0.04), label)
        }
        court.oneOnOneHumanJumpUntilNanos = 0
        court.oneOnOneBotJumpUntilNanos = 0
    }

    // MARK: - Rebound race, dead ball (Kotlin 4505-4585)

    func testReboundRaceTieGoesToTheHumanAndBotWinsWhenOnlyItReaches() {
        let court = TripleShotCourtView()
        // 6c38131: candidates come from the world loose ball, so the court needs its background transform.
        court.layout(0, 0, 1080, 2400)
        court.oneOnOneEnabled = true
        court.botEnabled = true
        var states: [TripleShotCourtView.OneOnOneBallState] = []
        court.oneOnOneAutomaticBallStateListener = { states.append($0) }

        func makeLoose(age: Float) {
            court.sharedHorseBallOwner = nil
            court.oneOnOneLooseBallActive = true
            court.oneOnOneLooseBallAgeSeconds = age
            court.oneOnOneLooseBallClaimDelaySeconds = 0.18
            court.ballX = 520
            court.ballY = 1470
            // The world ball lies on the floor at the (500, 1500) feet.
            let foot = court.worldGround(x: 500, y: 1500)
            court.worldLooseBall = TripleShotLooseBall(start: CourtPoint(x: foot.x, y: TripleShotLooseBall.RADIUS, z: foot.z),
                                                       velocity: CourtPoint(x: 0, y: 0, z: 0), gravity: 9.8)
        }

        // Before the claim delay nobody may pick the ball up.
        court.playerX = 500
        court.playerFootY = 1500
        court.botX = 500
        court.botFootY = 1500
        makeLoose(age: 0.10)
        court.resolveOneOnOneLooseBallPossession(now: ASystem.nanoTime())
        XCTAssertTrue(court.oneOnOneLooseBallActive)
        XCTAssertEqual(states, [])

        // Identical feet, identical ratings: equal scores, the human wins the tie (`human.score <= bot.score`).
        makeLoose(age: 0.5)
        court.resolveOneOnOneLooseBallPossession(now: ASystem.nanoTime())
        XCTAssertFalse(court.oneOnOneLooseBallActive)
        XCTAssertEqual(court.sharedHorseBallOwner, .HUMAN)
        XCTAssertEqual(states, [.HUMAN])
        XCTAssertEqual(
            court.oneOnOneHumanStealProtectedUntilNanos,
            ASystem.nanoTime() + TripleShotCourtView.ONE_ON_ONE_STEAL_AFTER_PICKUP_PROTECTION_MS * 1_000_000
        )
        XCTAssertEqual(court.oneOnOneHumanLastMoveNanos, ASystem.nanoTime())

        // Only the bot reaches.
        states.removeAll()
        court.playerX = 100
        court.playerFootY = 1500
        court.botX = 500
        court.botFootY = 1500
        makeLoose(age: 0.5)
        court.resolveOneOnOneLooseBallPossession(now: ASystem.nanoTime())
        XCTAssertFalse(court.oneOnOneLooseBallActive)
        XCTAssertEqual(court.sharedHorseBallOwner, .BOT)
        XCTAssertEqual(states, [.BOT])
        XCTAssertEqual(
            court.oneOnOneBotStealProtectedUntilNanos,
            ASystem.nanoTime() + TripleShotCourtView.ONE_ON_ONE_STEAL_AFTER_PICKUP_PROTECTION_MS * 1_000_000
        )

        // Nobody reaches: the ball stays live, no teleport.
        states.removeAll()
        court.playerX = 100
        court.botX = 1000
        makeLoose(age: 0.5)
        court.resolveOneOnOneLooseBallPossession(now: ASystem.nanoTime())
        XCTAssertTrue(court.oneOnOneLooseBallActive)
        XCTAssertEqual(states, [])
    }

    func testDeadBallGoesToTheTeamThatDidNotTouchItLast() {
        let court = TripleShotCourtView()
        court.oneOnOneEnabled = true
        var states: [TripleShotCourtView.OneOnOneBallState] = []
        court.oneOnOneAutomaticBallStateListener = { states.append($0) }
        for (lastOwnerHuman, expected) in [(true, TripleShotCourtView.OneOnOneBallState.DEAD_BOT),
                                           (false, .DEAD_HUMAN)] as [(Bool?, TripleShotCourtView.OneOnOneBallState)] {
            states.removeAll()
            court.oneOnOneLooseBallActive = true
            court.oneOnOneLooseBallLastOwnerHuman = lastOwnerHuman
            court.ballVisible = true
            court.botBallVisible = true
            court.resolveOneOnOneDeadBall()
            XCTAssertEqual(states, [expected])
            XCTAssertFalse(court.oneOnOneLooseBallActive)
            XCTAssertNil(court.sharedHorseBallOwner)
            XCTAssertFalse(court.ballVisible)
            XCTAssertFalse(court.botBallVisible)
            XCTAssertEqual(court.oneOnOneLooseBallLastOwnerHuman, lastOwnerHuman)
        }
        // An unknown last owner also restarts with the human (Kotlin `null -> DEAD_HUMAN`).
        states.removeAll()
        court.oneOnOneLooseBallActive = true
        court.oneOnOneLooseBallLastOwnerHuman = nil
        court.resolveOneOnOneDeadBall()
        XCTAssertEqual(states, [.DEAD_HUMAN])
        // Not loose: no event.
        states.removeAll()
        court.resolveOneOnOneDeadBall()
        XCTAssertEqual(states, [])
    }

    // MARK: - Move timings (Kotlin 3457-3563, 3680-3759): exact ms from the JVM

    private struct TimingSet {
        let humanBallHandling: Int, humanOffense: Int, botAgility: Int, botDefense: Int
        let crossoverWindowMs: Int64, crossoverStunMs: Int64, hesitationMs: Int64
        let spinWindowMs: Int64, spinStunMs: Int64, escapeDelayMs: Int64
    }

    private static let timingSets: [TimingSet] = [
        TimingSet(humanBallHandling: 50, humanOffense: 50, botAgility: 50, botDefense: 50,
                  crossoverWindowMs: 415, crossoverStunMs: 425, hesitationMs: 315,
                  spinWindowMs: 520, spinStunMs: 610, escapeDelayMs: 260),
        TimingSet(humanBallHandling: 92, humanOffense: 80, botAgility: 40, botDefense: 35,
                  crossoverWindowMs: 535, crossoverStunMs: 659, hesitationMs: 420,
                  spinWindowMs: 578, spinStunMs: 717, escapeDelayMs: 348),
        TimingSet(humanBallHandling: 20, humanOffense: 30, botAgility: 95, botDefense: 90,
                  crossoverWindowMs: 306, crossoverStunMs: 198, hesitationMs: 240,
                  spinWindowMs: 442, spinStunMs: 467, escapeDelayMs: 140),
        TimingSet(humanBallHandling: 100, humanOffense: 100, botAgility: 0, botDefense: 0,
                  crossoverWindowMs: 560, crossoverStunMs: 720, hesitationMs: 440,
                  spinWindowMs: 598, spinStunMs: 753, escapeDelayMs: 383)
    ]

    func testCrossoverHesitationSpinAndEscapeTimingsMatchKotlin() {
        for set in Self.timingSets {
            let court = TripleShotCourtView()
            court.oneOnOneEnabled = true
            court.botEnabled = true
            court.sharedHorseBallOwner = .HUMAN
            court.shotGuidesVisible = false
            court.oneOnOneHumanBallHandlingRating = set.humanBallHandling
            court.oneOnOneHumanAgilityRating = set.humanBallHandling
            court.oneOnOneHumanOffenseRating = set.humanOffense
            court.oneOnOneBotAgilityRating = set.botAgility
            court.oneOnOneBotDefenseRating = set.botDefense
            let label = "ratings \(set.humanBallHandling)/\(set.humanOffense)/\(set.botAgility)/\(set.botDefense)"
            let now = ASystem.nanoTime()

            court.oneOnOneHumanCrossover(directionSign: -1)
            XCTAssertEqual(court.oneOnOneHumanCrossoverUntilNanos, now + set.crossoverWindowMs * 1_000_000, label)
            XCTAssertEqual(court.oneOnOneBotReactionLockedUntilNanos, now + set.crossoverStunMs * 1_000_000, label)
            XCTAssertEqual(court.humanCrossAt, now, label)
            XCTAssertEqual(court.humanCrossFrom, 1, label)
            XCTAssertEqual(court.humanDribbleHandSign, -1, label)
            XCTAssertEqual(court.humanWalkingDribbleHandSign, -1, label)
            XCTAssertFalse(court.humanCrossBehind, "the first crossover is in front: \(label)")
            XCTAssertTrue(court.humanWalkingBallPassInFront, label)

            // Hesitation merges with max(); crossover overwrites (a shorter stun can shorten a longer one).
            court.oneOnOneBotReactionLockedUntilNanos = 0
            court.oneOnOneHumanHesitation()
            XCTAssertEqual(court.oneOnOneBotReactionLockedUntilNanos, now + set.hesitationMs * 1_000_000, label)
            court.oneOnOneBotReactionLockedUntilNanos = now + 10_000_000_000
            court.oneOnOneHumanHesitation()
            XCTAssertEqual(court.oneOnOneBotReactionLockedUntilNanos, now + 10_000_000_000, label)
            court.oneOnOneHumanCrossover(directionSign: 1)
            XCTAssertEqual(court.oneOnOneBotReactionLockedUntilNanos, now + set.crossoverStunMs * 1_000_000, label)
            XCTAssertEqual(court.humanCrossFrom, -1, label)
            XCTAssertEqual(court.humanDribbleHandSign, 1, label)
            XCTAssertTrue(court.humanCrossBehind, "a repeat within 2.2 s goes behind the back: \(label)")
            XCTAssertFalse(court.humanWalkingBallPassInFront, label)
            let lockBeforeSpin = court.oneOnOneBotReactionLockedUntilNanos

            // Contact spin (bodies touching).
            court.oneOnOneHumanCrossoverUntilNanos = 0
            court.playerX = 500
            court.playerFootY = 1500
            court.botX = 500 + court.dp(v: court.oneOnOneBodyRadiusDp(human: true) + court.oneOnOneBodyRadiusDp(human: false))
            court.botFootY = 1500
            XCTAssertTrue(court.isOneOnOneHumanInBodyContact(), label)
            XCTAssertTrue(court.oneOnOneHumanSpin(directionSign: -1), label)
            // 6c38131: the spin is a BasketballMoves.SpinSeries draw (Random.Default). A success opens the spin window
            // and locks the defender for 1000-2000 ms; a failure opens no window and leaves the lock as it was.
            // (spinStunMs is the dd722e5 stun, no longer used.)
            if court.oneOnOneHumanCrossoverUntilNanos == now {
                XCTAssertEqual(court.oneOnOneBotReactionLockedUntilNanos, lockBeforeSpin, label)
            } else {
                XCTAssertEqual(court.oneOnOneHumanCrossoverUntilNanos, now + set.spinWindowMs * 1_000_000, label)
                XCTAssertGreaterThanOrEqual(court.oneOnOneBotReactionLockedUntilNanos, now + 1000 * 1_000_000, label)
                XCTAssertLessThanOrEqual(court.oneOnOneBotReactionLockedUntilNanos, now + 2000 * 1_000_000, label)
            }
            XCTAssertEqual(court.humanSpinAt, now, label)
            XCTAssertEqual(court.humanCrossAt, now, label)
            XCTAssertEqual(court.humanDribbleHandSign, -1, label)
            court.playerMoveAnimator?.cancel()

            // Shot escape while aiming (side step: 1.34 jump over 430 ms).
            court.shotGuidesVisible = true
            court.oneOnOneBotContestActive = true
            court.botPullBack = 0.62
            XCTAssertTrue(court.oneOnOneHumanShotEscape(move: .SIDE_LEFT), label)
            XCTAssertEqual(court.oneOnOneBotReactionLockedUntilNanos, now + set.escapeDelayMs * 1_000_000, label)
            XCTAssertEqual(court.oneOnOneHumanJumpStartedAtNanos, now, label)
            XCTAssertEqual(court.oneOnOneHumanJumpUntilNanos, now + 430 * 1_000_000, label)
            XCTAssertEqual(court.oneOnOneHumanJumpHeightMultiplier, Float(1.34), label)
            XCTAssertFalse(court.oneOnOneBotContestActive, label)
            XCTAssertEqual(court.botPullBack, 0, label)
            XCTAssertEqual(court.horseHumanStation?.id, "ONE_ON_ONE_ESCAPE", label)
            XCTAssertEqual(court.horseHumanStation?.zone, "one_on_one", label)
        }
    }

    /// RefinementTest.humanDriveFinishesAndSpinHaveRealMotion (spin half): the spin starts at the current feet
    /// (the synchronous fraction-0 update does not move the body) and has moved the body after 230 ms.
    func testSpinStartsInPlaceAndMovesTheBodyWithin230Ms() {
        let court = TripleShotCourtView()
        court.oneOnOneEnabled = true
        court.botEnabled = true
        court.sharedHorseBallOwner = .HUMAN
        court.shotGuidesVisible = false
        court.playerX = 500
        court.playerFootY = 1500
        let distance = (court.oneOnOneBodyRadiusDp(human: true) + court.oneOnOneBodyRadiusDp(human: false)) * court.density
        court.botX = 500 + distance
        court.botFootY = 1500
        let startX = court.playerX
        let startY = court.playerFootY

        XCTAssertTrue(court.oneOnOneHumanSpin(directionSign: -1))
        XCTAssertEqual(court.playerX, startX, accuracy: 0.1)
        XCTAssertEqual(court.playerFootY, startY, accuracy: 0.1)
        XCTAssertTrue(court.playerMoveAnimator?.isRunning == true)

        AndroidKitTestLoop.advance(millis: 230)
        XCTAssertGreaterThan(abs(court.playerX - startX) + abs(court.playerFootY - startY), 1)

        AndroidKitTestLoop.advance(millis: 400)
        XCTAssertFalse(court.playerMoveAnimator?.isRunning == true)
    }

    func testSpinNeedsBodyContactAndNoAim() {
        let court = TripleShotCourtView()
        court.oneOnOneEnabled = true
        court.botEnabled = true
        court.sharedHorseBallOwner = .HUMAN
        court.playerX = 500
        court.playerFootY = 1500
        court.botX = 900
        court.botFootY = 1500
        XCTAssertFalse(court.oneOnOneHumanSpin(directionSign: 1))
        XCTAssertNil(court.playerMoveAnimator)
        court.botX = 510
        court.shotGuidesVisible = true
        XCTAssertFalse(court.oneOnOneHumanSpin(directionSign: 1))
        XCTAssertNil(court.playerMoveAnimator)
    }

    // MARK: - Pump fake, contest permission, held motion (Kotlin 2829-2866, 3436-3452)

    func testPumpFakeCycleStunsABitingDefender() {
        let court = TripleShotCourtView()
        court.oneOnOneEnabled = true
        court.sharedHorseBallOwner = .HUMAN
        court.shotGuidesVisible = true
        court.pullBack = 0.7
        court.oneOnOneBotContestActive = true
        court.botPullBack = 0.62
        let now = ASystem.nanoTime()
        court.oneOnOnePumpFakeCycle()
        XCTAssertEqual(court.pullBack, Float(0.02))
        XCTAssertFalse(court.oneOnOneBotContestActive)
        XCTAssertEqual(court.botPullBack, 0)
        XCTAssertEqual(court.oneOnOneBotReactionLockedUntilNanos, now + 620 * 1_000_000)
        XCTAssertEqual(court.oneOnOneBotContestRecoveryUntilNanos, court.oneOnOneBotReactionLockedUntilNanos)

        // Not biting: only the pose drops, no stun.
        court.oneOnOneBotReactionLockedUntilNanos = 0
        court.oneOnOneBotContestRecoveryUntilNanos = 0
        court.pullBack = 0.7
        court.oneOnOnePumpFakeCycle()
        XCTAssertEqual(court.pullBack, Float(0.02))
        XCTAssertEqual(court.oneOnOneBotReactionLockedUntilNanos, 0)

        // Guides hidden: nothing.
        court.shotGuidesVisible = false
        court.pullBack = 0.7
        court.oneOnOnePumpFakeCycle()
        XCTAssertEqual(court.pullBack, Float(0.7))
    }

    func testContestPermissionAndHeldMotionOverride() {
        let court = TripleShotCourtView()
        court.oneOnOneBotContestActive = true
        court.botPullBack = 0.62
        court.shotFrameRunning = true
        court.setOneOnOneBotContestAllowed(allowed: false)
        // A human shot in flight keeps the contest (Kotlin `!allowed && !shotFrameRunning`).
        XCTAssertFalse(court.oneOnOneBotContestAllowed)
        XCTAssertTrue(court.oneOnOneBotContestActive)
        XCTAssertEqual(court.botPullBack, Float(0.62))
        court.shotFrameRunning = false
        court.setOneOnOneBotContestAllowed(allowed: false)
        XCTAssertFalse(court.oneOnOneBotContestActive)
        XCTAssertEqual(court.botPullBack, 0)
        court.setOneOnOneBotContestAllowed(allowed: true)
        XCTAssertTrue(court.oneOnOneBotContestAllowed)

        court.setOneOnOneHumanHeldMotion(high: true)
        XCTAssertEqual(court.oneOnOneHumanHeldMotionOverride, .SHOT_MID)
        court.setOneOnOneHumanHeldMotion(high: false)
        XCTAssertEqual(court.oneOnOneHumanHeldMotionOverride, .SHOT_LOW)
        court.setOneOnOneHumanHeldMotion(high: nil)
        XCTAssertNil(court.oneOnOneHumanHeldMotionOverride)
    }

    // MARK: - Steal attempt gating (Kotlin 3944-3991)

    func testHumanStealAttemptStartsAVisibleReachOnlyWhenAllowed() {
        let court = TripleShotCourtView()
        court.oneOnOneEnabled = true
        court.sharedHorseBallOwner = .BOT
        let now = ASystem.nanoTime()

        // 6c38131: a protected ball no longer refuses the tap; the delayed contact checks the protection.
        court.oneOnOneBotStealProtectedUntilNanos = now + 1
        XCTAssertTrue(court.oneOnOneHumanStealAttempt())
        court.oneOnOneBotStealProtectedUntilNanos = 0
        court.oneOnOneHumanStealResolvePosted = false
        court.oneOnOneHumanStealCooldownUntilNanos = 0

        XCTAssertTrue(court.oneOnOneHumanStealAttempt())
        XCTAssertEqual(court.oneOnOneHumanStealCooldownUntilNanos, now + 820 * 1_000_000)
        XCTAssertEqual(court.oneOnOneHumanStealStartedAtNanos, now)
        XCTAssertEqual(court.oneOnOneHumanStealUntilNanos, now + 310 * 1_000_000)
        XCTAssertTrue(court.oneOnOneHumanStealResolvePosted)
        // The contact is still pending, and the cooldown runs: a second tap is refused.
        XCTAssertFalse(court.oneOnOneHumanStealAttempt())

        court.oneOnOneHumanStealResolvePosted = false
        XCTAssertFalse(court.oneOnOneHumanStealAttempt())   // cooldown

        // Wrong owner / loose ball / bot shot in flight.
        court.oneOnOneHumanStealCooldownUntilNanos = 0
        court.sharedHorseBallOwner = .HUMAN
        XCTAssertFalse(court.oneOnOneHumanStealAttempt())
        court.sharedHorseBallOwner = .BOT
        court.botShotFrameRunning = true
        XCTAssertFalse(court.oneOnOneHumanStealAttempt())
        court.botShotFrameRunning = false
        court.oneOnOneLooseBallActive = true
        XCTAssertFalse(court.oneOnOneHumanStealAttempt())
    }

    // MARK: - Zones, ball side, dunk lottery (Kotlin 3070-3113, 4316-4326, 4914-5029)

    func testZonesAndDifficultyBands() {
        let court = TripleShotCourtView()
        XCTAssertEqual(court.zoneForDifficulty(difficulty: 0.0), .INSIDE)
        XCTAssertEqual(court.zoneForDifficulty(difficulty: 0.3399), .INSIDE)
        XCTAssertEqual(court.zoneForDifficulty(difficulty: 0.34), .MID_RANGE)
        XCTAssertEqual(court.zoneForDifficulty(difficulty: 0.6799), .MID_RANGE)
        XCTAssertEqual(court.zoneForDifficulty(difficulty: 0.68), .THREE_POINT)

        // Not laid out: the bot zone comes from its station difficulty (0.50 without a station) ...
        XCTAssertEqual(court.currentBotShotZone(), .MID_RANGE)
        court.botCurrentStation = TripleShotCourtView.Station(id: "t", sourceX: 0, sourceY: 0, distanceDifficulty: 0.2)
        XCTAssertEqual(court.currentBotShotZone(), .INSIDE)
        court.botCurrentStation = TripleShotCourtView.Station(id: "t", sourceX: 0, sourceY: 0, distanceDifficulty: 0.9)
        XCTAssertEqual(court.currentBotShotZone(), .THREE_POINT)
        // ... and the human source position is (0, 0), about 1209 source px from the hoop depth point.
        XCTAssertEqual(court.currentHumanShotZone(), .THREE_POINT)

        // Not laid out: no contest pressure at all.
        court.oneOnOneEnabled = true
        court.botEnabled = true
        XCTAssertEqual(court.oneOnOneHumanShotContest01(), 0)
        XCTAssertEqual(court.oneOnOneBotShotContest01(), 0)
    }

    func testBallOnDefenderSide() {
        let court = TripleShotCourtView()
        let two = court.dp(v: 2)
        let four = court.dp(v: 4)
        // Defender straight in front of the handler (|dD| < 2 dp) or ball centred (|dB| < 4 dp): exposed.
        XCTAssertTrue(court.oneOnOneBallOnDefenderSide(defenderX: 500 + two * 0.5, handlerX: 500, ballX: 400))
        XCTAssertTrue(court.oneOnOneBallOnDefenderSide(defenderX: 300, handlerX: 500, ballX: 500 + four * 0.5))
        XCTAssertTrue(court.oneOnOneBallOnDefenderSide(defenderX: 300, handlerX: 500, ballX: 450))
        XCTAssertTrue(court.oneOnOneBallOnDefenderSide(defenderX: 700, handlerX: 500, ballX: 550))
        XCTAssertFalse(court.oneOnOneBallOnDefenderSide(defenderX: 300, handlerX: 500, ballX: 560))
        XCTAssertFalse(court.oneOnOneBallOnDefenderSide(defenderX: 700, handlerX: 500, ballX: 440))
    }

    func testDunkLotteryPicksAnAuthoredFrame() {
        let court = TripleShotCourtView()
        court.botCharacterId = TripleShotCharacterRoster.ID_WOMAN_DARK
        let count = TripleShotCharacterVisualCatalog.find(characterId: court.botCharacterId)?.dunks.count ?? 0
        XCTAssertGreaterThan(count, 0)
        for serial in 0..<40 {
            court.oneOnOneLooseEventSerial = Int64(serial)
            court.oneOnOneBotRecentAttackIntensity01 = Float(serial % 10) / 9
            court.oneOnOneBotLastDunkFrameIndex = serial % count
            AndroidKitTestLoop.advance(millis: 7)   // the lottery is seeded from nanoTime()
            let index = court.chooseOneOnOneBotDunkFrame()
            XCTAssertTrue(index >= 0 && index < count, "index \(index)")
        }
        court.botCharacterId = "no_such_character"
        XCTAssertEqual(court.chooseOneOnOneBotDunkFrame(), -1)
        XCTAssertNil(court.currentOneOnOneBotDunkSprite())
    }

    // MARK: - Silent no-callback guards and bot teardown (spec 09 §8.2)

    func testGuardedLaunchersNeverCallBackInInvalidStates() {
        let court = TripleShotCourtView()
        var calls = 0
        let skill = ShotSkill(aimError: 0, powerError: 0, arcError: 0, rawPeakGyro: 0, rawReleasePitchDeg: 0)

        court.botEnabled = false
        court.animateBotShot(skill: skill, pullBackAtRelease: 0.7, hot: false) { _ in calls += 1 }
        XCTAssertNil(court.botShotOnEnd)
        XCTAssertNil(court.botAimAnimator)

        court.oneOnOneEnabled = false
        court.animateOneOnOneHumanShot(skill: skill, pullBackAtRelease: 0.7) { _ in calls += 1 }
        court.animateOneOnOneBotDunk { _ in calls += 1 }
        XCTAssertFalse(court.oneOnOneBotDunkActive)

        var moved = 0
        court.moveBotToAnswerStation(index: 1, answerCount: 3) { moved += 1 }
        XCTAssertEqual(moved, 1)   // no bot: onEnd runs at once

        AndroidKitTestLoop.advance(millis: 1_000)
        XCTAssertEqual(calls, 0)
    }

    func testBotOpponentDisableTearsDownTheBot() {
        let court = TripleShotCourtView()
        court.botEnabled = true
        court.sharedHorseBallOwner = .BOT
        court.botBallVisible = true
        court.botHotHand = true
        court.recentBotSpotIds = ["a", "b"]
        court.botCurrentStation = TripleShotCourtView.Station(id: "s", sourceX: 1, sourceY: 2, distanceDifficulty: 0.5)
        let label = court.botLabel

        court.setBotOpponentEnabled(enabled: false)
        XCTAssertFalse(court.botEnabled)
        XCTAssertNil(court.sharedHorseBallOwner)
        XCTAssertFalse(court.botBallVisible)
        XCTAssertFalse(court.botHotHand)
        XCTAssertEqual(court.recentBotSpotIds, [])
        XCTAssertNil(court.botCurrentStation)
        XCTAssertNil(court.botMoveAnimator)
        XCTAssertEqual(court.botLabel, label)

        court.setBotHotHand(active: true)
        XCTAssertTrue(court.botHotHand)

        // Enabling before layout stores the label and defers the placement (Kotlin `post { ... }`).
        court.setBotOpponentEnabled(enabled: true, seed: 7, label: "MAYA")
        XCTAssertTrue(court.botEnabled)
        XCTAssertEqual(court.botLabel, "MAYA")
        XCTAssertNil(court.botCurrentStation)
    }
}
