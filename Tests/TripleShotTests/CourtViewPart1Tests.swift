import XCTest
@testable import MinikTripleShot

// Area w-court1: TripleShotCourtView part 1 (Kotlin view/TripleShotCourtView.kt lines 1-2654, spec 08-court1).
//
// - RefinementTest (androidTest) court expectations in this range, without a GPU: the 1v1 drive-finish choice
//   (`humanDriveFinishesAndSpinHaveRealMotion`, Kotlin lines 96-102).
// - JVM golden vectors (work/w-court1/harness/CourtPart1Golden.kt runs the unmodified Kotlin bodies of
//   prepareAnswerSpots, sourceDistanceSquared, randomHorseSpotIdForBot, rememberBotSpot, horseFreeMinYForX and lerp
//   with the snapshot's catalogs; output in work/w-court1/harness/golden.txt): seeded answer-spot selection for
//   Practice / Shooting Challenge / bot challenge runs, the HORSE bot spot memory, the free-move terrain ceiling.
// - The per-method side effects spec 08 section 3.4 lists (clamps, the picker quirk, unlaid-out no-ops, Live avatars).
// The court view is used unattached (no window, no frames): posted work and animations never run here.

final class CourtViewPart1Tests: XCTestCase {

    private func ids(_ stations: [TripleShotCourtView.Station]) -> String {
        return stations.map { $0.id }.joined(separator: ",")
    }

    private func laidOutCourt(width: Int = 1080, height: Int = 2340) -> TripleShotCourtView {
        let court = TripleShotCourtView()
        court.layout(0, 0, width, height)
        return court
    }

    // MARK: - Nested types

    func testNestedEnumsKeepKotlinOrder() {
        XCTAssertEqual(
            TripleShotCourtView.ShotKind.allCases.map { $0.name },
            ["SWISH", "RIM_IN", "BANK_IN", "RIM_OUT", "BACKBOARD_OUT", "AIRBALL", "INVALID_BELOW"]
        )
        XCTAssertEqual(TripleShotCourtView.SharedBallOwner.allCases.map { $0.name }, ["HUMAN", "BOT"])
        XCTAssertEqual(
            TripleShotCourtView.OneOnOneBallState.allCases.map { $0.name },
            ["HUMAN", "BOT", "LOOSE", "DEAD_HUMAN", "DEAD_BOT"]
        )
        XCTAssertEqual(
            TripleShotCourtView.OneOnOneShotEscape.allCases.map { $0.name },
            ["FADE_AWAY", "SIDE_LEFT", "SIDE_RIGHT"]
        )
        XCTAssertEqual(TripleShotCourtView.OneOnOneDriveFinish.allCases.map { $0.name }, ["JUMPER", "LAYUP", "DUNK"])
        XCTAssertEqual(TripleShotCourtView.OneOnOneDriveFinish.DUNK.ordinal, 2)
    }

    func testDataClassDefaultsAndEquality() {
        let result = TripleShotCourtView.ShotResult(
            outcome: ShotOutcome(made: true, targetOffsetX: 0, targetOffsetY: 0, quality: 1),
            kind: .SWISH,
            rimHits: 0,
            backboardHits: 0
        )
        XCTAssertTrue(result.replaySamples.isEmpty)

        let station = TripleShotCourtView.Station(id: "A", sourceX: 1, sourceY: 2, distanceDifficulty: 0.5)
        XCTAssertEqual(station.zone, "court")
        XCTAssertEqual(station, TripleShotCourtView.Station("A", 1, 2, 0.5, "court"))
        // Kotlin data-class equality compares Float properties with Float.compare (floatToIntBits).
        XCTAssertNotEqual(
            TripleShotCourtView.Station(id: "Z", sourceX: 0, sourceY: 0, distanceDifficulty: 0),
            TripleShotCourtView.Station(id: "Z", sourceX: -0.0, sourceY: 0, distanceDifficulty: 0)
        )
        XCTAssertEqual(
            TripleShotCourtView.Station(id: "N", sourceX: .nan, sourceY: 0, distanceDifficulty: 0),
            TripleShotCourtView.Station(id: "N", sourceX: .nan, sourceY: 0, distanceDifficulty: 0)
        )

        let remote = TripleShotCourtView.LiveRemoteVisual(uid: "u", name: "n", sourceX: 1, sourceY: 2)
        XCTAssertEqual(remote.score, 0)
        XCTAssertTrue(remote.ballVisible)
        XCTAssertEqual(remote.renderScale, 0.82)
        XCTAssertEqual(remote.pose, TripleShotPlayerRenderer.Pose.NORMAL)
        XCTAssertNil(remote.physicsState)
        XCTAssertEqual(remote.lastFrameNanos, 0)
    }

    func testFieldInitialValuesMatchKotlin() {
        let court = TripleShotCourtView()
        XCTAssertEqual(court.premiumCourtId, "enchanted_forest")
        XCTAssertEqual(court.humanCharacterId, "woman_dark")
        XCTAssertEqual(court.botCharacterId, "bob")
        XCTAssertEqual(court.answerCount, 3)
        XCTAssertEqual(court.selectedStation, -1)
        XCTAssertTrue(court.answerMarkersVisible)
        XCTAssertTrue(court.ballVisible)
        XCTAssertFalse(court.botBallVisible)
        XCTAssertEqual(court.botLabel, "BOT")
        XCTAssertEqual(court.currentBallResId, R.drawable.basketball)
        XCTAssertEqual(court.ballResIds.count, 9)
        XCTAssertEqual(court.liveReplayLastSampleMs, -55)
        XCTAssertEqual(court.oneOnOneLooseBallClaimDelaySeconds, 0.18)
        XCTAssertEqual(court.oneOnOneBotRecentAttackIntensity01, 0.82)
        XCTAssertEqual(court.oneOnOneBotDunkFrameIndex, -1)
        XCTAssertEqual(court.oneOnOneBotLastDunkFrameIndex, -1)
        XCTAssertEqual(court.humanShotStyle, TripleShotPlayerRenderer.ShotStyle.PRO)
        XCTAssertEqual(court.courtAtmosphere, TripleShotCourtAtmosphere.NONE)
        XCTAssertEqual(court.oneOnOneBotBlockRating, 50)
        XCTAssertEqual(court.oneOnOneHumanJumpRating, 50)
        XCTAssertEqual(court.density, AResources.displayMetrics.density)
        // Runnables are single instances (removeCallbacks matches by identity).
        XCTAssertTrue(court.physicsFrameRunnable === court.physicsFrameRunnable)
        XCTAssertTrue(court.horseFreeMoveSettleRunnable === court.horseFreeMoveSettleRunnable)
    }

    // MARK: - prepareAnswerSpots golden vectors (JVM)

    private static let practiceSeeds: [Int64] = [
        0, 1, 42, 123456789, -1, Int64.max, Int64.min, 0x5A17C3, 7777777777, -987654321012
    ]

    private static let goldenPractice: [Int: String] = [
        2: "practice_bush,practice_deep;practice_right,practice_deep;practice_right,practice_deep;practice_bush,practice_left;practice_left,practice_deep;practice_left,practice_deep;practice_deep,practice_left;practice_deep,practice_right;practice_right,practice_bush;practice_bush,practice_deep;",
        3: "practice_bush,practice_deep,practice_left;practice_right,practice_deep,practice_bush;practice_right,practice_deep,practice_bush;practice_bush,practice_left,practice_deep;practice_left,practice_deep,practice_right;practice_left,practice_deep,practice_right;practice_deep,practice_left,practice_bush;practice_deep,practice_right,practice_bush;practice_right,practice_bush,practice_deep;practice_bush,practice_deep,practice_left;",
        4: "practice_bush,practice_deep,practice_left,practice_right;practice_right,practice_deep,practice_bush,practice_left;practice_right,practice_deep,practice_bush,practice_left;practice_bush,practice_left,practice_deep,practice_right;practice_left,practice_deep,practice_right,practice_bush;practice_left,practice_deep,practice_right,practice_bush;practice_deep,practice_left,practice_bush,practice_right;practice_deep,practice_right,practice_bush,practice_left;practice_right,practice_bush,practice_deep,practice_left;practice_bush,practice_deep,practice_left,practice_right;"
    ]

    func testPracticeSpotsMatchJvm() {
        for count in 2...4 {
            var line = ""
            for seed in Self.practiceSeeds {
                let court = TripleShotCourtView()
                court.prepareAnswerSpots(count: count, seed: seed, randomize: false)
                line += ids(court.activeStations) + ";"
                XCTAssertTrue(court.recentSpotIds.isEmpty, "Practice never feeds the recent-spot memory")
            }
            XCTAssertEqual(line, Self.goldenPractice[count], "count \(count)")
        }
    }

    private static let goldenChallenge: [Int: (runs: String, recent: String)] = [
        2: (
            "C03,L05;H05,H01;L04,L01;H02,H04;L06,L02;H03,R07;L03,X01;H05,H01;L01,L04;H04,H02;L02,L06;R07,H03;L03,X01;H01,H05;L04,L01;H04,H02;L02,L06;R07,H03;L03,X01;H01,H05;L01,L04;H04,H02;L06,L02;R07,H03;",
            "H01,H05,L01,L04,H04,H02,L06,L02,R07,H03"
        ),
        3: (
            "R03,L05,C03;R01,H01,H05;L01,L04,C04;H04,H02,C05;L02,L06,C07;R01,H03,H01;L04,L05,L01;H05,R06,H02;L06,C01,L02;R04,R05,H04;X01,C02,L03;H01,R06,H05;L05,L04,L01;H03,R01,R07;C04,L06,L02;X05,H04,H01;C03,X01,L03;H05,R06,H02;L05,L04,L01;R04,R05,H04;C01,L02,L06;R06,H05,H01;C02,X01,L03;R07,C07,H03;",
            "L06,R06,H05,H01,C02,X01,L03,R07,C07,H03"
        ),
        4: (
            "C03,R03,H05,L05;R01,L01,H01,L04;R04,C02,C04,H04;H02,L02,R02,L06;R06,C01,C07,H05;H01,L01,L04,R01;H04,C02,R04,C04;R02,L06,L02,H02;H05,C01,R06,C07;H01,R01,L04,L01;C02,R04,H04,C04;L06,H02,L02,R02;H05,R06,C01,C07;L04,R01,H01,L01;C02,H04,C04,R04;H02,L06,L02,R02;C07,H05,C01,R06;L01,R01,H01,L04;C04,H04,R04,C02;R02,L06,H02,L02;H05,C07,C01,R06;R01,L01,H01,L04;R04,C02,C04,H04;H02,R02,L06,L02;",
            "H01,L04,R04,C02,C04,H04,H02,R02,L06,L02"
        )
    ]

    func testShootingChallengeRunMatchesJvm() {
        for count in [2, 3, 4] {
            let court = TripleShotCourtView()
            var line = ""
            for i in 0..<24 {
                let n = Int64(i)
                let seed: Int64 = 20261017 ^ (n * 97) ^ (n << 33)
                court.prepareAnswerSpots(count: count, seed: seed, randomize: true)
                line += ids(court.activeStations) + ";"
                XCTAssertEqual(court.selectedStation, -1)
            }
            XCTAssertEqual(line, Self.goldenChallenge[count]?.runs, "count \(count)")
            XCTAssertEqual(court.recentSpotIds.joined(separator: ","), Self.goldenChallenge[count]?.recent)
        }
    }

    func testBotChallengeAvoidsTheWaitingBotLikeJvm() {
        let court = TripleShotCourtView()
        court.botEnabled = true
        let catalog = TripleShotCourtView.SHOT_SPOT_CATALOG
        var line = ""
        for i in 0..<24 {
            court.botCurrentStation = catalog[(i * 7) % catalog.count]
            let seed: Int64 = -5555 + Int64(i) * 1_000_003
            court.prepareAnswerSpots(count: 3, seed: seed, randomize: true)
            line += ids(court.activeStations) + ";"
        }
        XCTAssertEqual(
            line,
            "C05,H02,R04;L05,L01,L04;H01,R06,H05;C01,L02,L06;R02,H02,H04;C02,L01,C04;H03,H01,R07;L02,X02,L04;R06,H02,H05;L01,L05,C03;H04,X05,H01;L06,C01,L02;R02,R04,H03;C04,X02,L04;H05,R06,H02;C01,L03,L01;X05,R07,H01;C04,L02,L06;R01,H03,R04;C03,X01,L03;R03,R05,H05;L05,L04,L01;H04,R01,H02;L02,L06,C04;"
        )
        XCTAssertEqual(court.recentSpotIds.joined(separator: ","), "H05,L05,L04,L01,H04,R01,H02,L02,L06,C04")
    }

    func testMixedModesAndCountClampMatchJvm() {
        let court = TripleShotCourtView()
        let counts = [3, 4, 2, 3, 4, 4, 1, 5, 3, 2]
        var line = ""
        for i in 0..<counts.count {
            let randomize = i % 4 != 3
            court.prepareAnswerSpots(count: counts[i], seed: 99 * Int64(i) - 31, randomize: randomize)
            line += "\(court.answerCount):" + ids(court.activeStations) + ";"
        }
        XCTAssertEqual(
            line,
            "3:H02,X03,L06;4:R04,C01,L01,H05;2:H01,L04;3:practice_right,practice_bush,practice_deep;4:R01,C02,L03,H03;4:X05,X01,R07,C07;2:C05,L06;4:practice_bush,practice_right,practice_deep,practice_left;3:H05,H01,X03;2:L01,L03;"
        )
        XCTAssertEqual(court.recentSpotIds.joined(separator: ","), "X01,R07,C07,C05,L06,H05,H01,X03,L01,L03")
    }

    func testRandomHorseSpotIdForBotMatchesJvm() {
        let court = TripleShotCourtView()
        var line = ""
        for i in 0..<20 {
            line += court.randomHorseSpotIdForBot(seed: 31337 * Int64(i) - 4242) + ","
        }
        XCTAssertEqual(line, "L05,X02,R05,C01,X05,R06,X03,C04,H02,L03,R03,C05,C03,X05,X01,R02,C07,X02,L01,C03,")
        XCTAssertEqual(court.recentBotSpotIds, ["R02", "C07", "X02", "L01", "C03"])
    }

    // MARK: - HORSE free-move bounds

    func testHorseFreeMinYForXMatchesJvmBits() {
        let portrait = laidOutCourt(width: 1080, height: 2340)
        let xs: [Float] = [-5, 0, 50, 108, 120, 140, 151.2, 200, 540, 820.8, 830, 850, 864, 900, 1080, 1200]
        let expected: [UInt32] = [
            0x44868CCD, 0x44868CCD, 0x44868CCD, 0x44868CCD, 0x4489CCCD, 0x448F3777, 0x44924000, 0x44924000,
            0x44924000, 0x44924000, 0x448FC222, 0x448A5778, 0x44868CCD, 0x44868CCD, 0x44868CCD, 0x44868CCD
        ]
        XCTAssertEqual(xs.map { portrait.horseFreeMinYForX(x: $0).bitPattern }, expected)

        let landscape = laidOutCourt(width: 2340, height: 1080)
        let xs2: [Float] = [0, 234, 250, 300, 327.6, 1000, 1778.4, 1800, 1850, 1872, 2340]
        let expected2: [UInt32] = [
            0x43F86667, 0x43F86667, 0x43FC17A2, 0x4403D0BD, 0x44070000, 0x44070000, 0x44070000, 0x440481F8,
            0x43FD7A19, 0x43F86667, 0x43F86667
        ]
        XCTAssertEqual(xs2.map { landscape.horseFreeMinYForX(x: $0).bitPattern }, expected2)

        XCTAssertEqual(TripleShotCourtView().horseFreeMinYForX(x: 10), 0, "unlaid-out view returns 0")
    }

    func testHorseFreeClampsUseTheTerrainCeiling() {
        let court = laidOutCourt(width: 1080, height: 2340)
        let dp24 = 24 * court.density
        XCTAssertEqual(court.horseFreeMinX(), dp24)
        XCTAssertEqual(court.horseFreeMaxX(), kmax(dp24 + 1, 1080 - dp24))
        let minY = court.horseFreeMinYForX(x: 540)
        XCTAssertEqual(court.clampHorseFreeY(x: 540, y: 0), minY)
        XCTAssertEqual(court.clampHorseFreeY(x: 540, y: 99_999), kmax(minY + 1, 2340 - dp24))
        XCTAssertEqual(court.horseFreeMaxY(), kmax(Float(2340) * 0.50 + 1, 2340 - dp24))
    }

    // MARK: - RefinementTest: humanDriveFinishesAndSpinHaveRealMotion (court part, Kotlin lines 96-102)

    func testRefinementDriveFinishChoices() {
        let c = laidOutCourt(width: 1080, height: 2340)
        c.setOneOnOneEnabled(enabled: true)
        c.oneOnOneGiveBallToHuman()
        c.moveHumanToHorseSourceSpot(sourceX: 650, sourceY: 1090, spotId: "qa-drive", animate: false)
        c.botX = c.playerX + 450
        c.botFootY = c.playerFootY + 100
        XCTAssertEqual(
            TripleShotCourtView.OneOnOneDriveFinish.DUNK,
            c.chooseOneOnOneHumanDriveFinish(movementIntensity01: 1, movementDx: 100, movementDy: -142, dunkAbility: 95)
        )
        XCTAssertEqual(
            TripleShotCourtView.OneOnOneDriveFinish.JUMPER,
            c.chooseOneOnOneHumanDriveFinish(movementIntensity01: 0, movementDx: 0, movementDy: 0, dunkAbility: 95)
        )
        XCTAssertEqual(
            TripleShotCourtView.OneOnOneDriveFinish.LAYUP,
            c.chooseOneOnOneHumanDriveFinish(movementIntensity01: 0.65, movementDx: 100, movementDy: -142, dunkAbility: 30)
        )
        // Without possession the finish is always a jumper.
        c.sharedHorseBallOwner = nil
        XCTAssertEqual(
            TripleShotCourtView.OneOnOneDriveFinish.JUMPER,
            c.chooseOneOnOneHumanDriveFinish(movementIntensity01: 1, movementDx: 100, movementDy: -142, dunkAbility: 95)
        )
    }

    func testOneOnOneEnableClampsRatingsAndDisableClearsListeners() {
        let court = TripleShotCourtView()
        court.setOneOnOneAutomaticBallStateListener(listener: { _ in })
        court.setOneOnOneBlockEventListener(listener: { _ in })
        court.setOneOnOneEnabled(enabled: false, botBlockRating: 150, humanBlockRating: -3, botJumpRating: 101)
        XCTAssertEqual(court.oneOnOneBotBlockRating, 100)
        XCTAssertEqual(court.oneOnOneHumanBlockRating, 0)
        XCTAssertEqual(court.oneOnOneBotJumpRating, 100)
        XCTAssertNil(court.oneOnOneAutomaticBallStateListener)
        XCTAssertNil(court.oneOnOneBlockEventListener)
        XCTAssertNil(court.sharedHorseBallOwner)
        XCTAssertFalse(court.horseFreeMoveEnabled)
        XCTAssertFalse(court.isOneOnOneHumanPossession())
        XCTAssertFalse(court.isOneOnOneLooseBall())

        // Not laid out: enabling keeps the flag and defers the rest (no possession yet).
        court.setOneOnOneEnabled(enabled: true)
        XCTAssertTrue(court.oneOnOneEnabled)
        XCTAssertNil(court.sharedHorseBallOwner)
        XCTAssertEqual(court.oneOnOneBotDunkFrameIndex, -1)
        XCTAssertEqual(court.oneOnOneLooseEventSerial, 0)
    }

    func testOneOnOneMovingShotJumpNeedsPossession() {
        let court = laidOutCourt()
        XCTAssertFalse(court.oneOnOneHumanMovingShotJump(directionX: 1, directionY: 0, intensity01: 1))
        court.setOneOnOneEnabled(enabled: true)
        court.oneOnOneGiveBallToHuman()
        XCTAssertEqual(court.sharedHorseBallOwner, TripleShotCourtView.SharedBallOwner.HUMAN)
        let before = ASystem.nanoTime()
        XCTAssertTrue(court.oneOnOneHumanMovingShotJump(directionX: 1, directionY: 0, intensity01: 2))
        // Intensity is clamped to 1: multiplier 0.78 + 0.34, jump window 430 ms, defender lock >= now + 160 ms.
        XCTAssertEqual(court.oneOnOneHumanJumpHeightMultiplier, Float(0.78) + Float(0.34) * 1)
        XCTAssertEqual(court.oneOnOneHumanJumpUntilNanos - court.oneOnOneHumanJumpStartedAtNanos, 430_000_000)
        XCTAssertGreaterThanOrEqual(court.oneOnOneBotReactionLockedUntilNanos, before + 160_000_000)
        XCTAssertFalse(court.moveOneOnOneHumanByTouch(dx: 0, dy: 0), "legacy Boolean result is always false")
    }

    // MARK: - Setters and per-method side effects (spec 08 section 3.4)

    func testSettersClampLikeKotlin() {
        let court = TripleShotCourtView()
        court.setFineAim(normalized: 2)
        XCTAssertEqual(court.fineAim, 1.30)
        court.setFineAim(normalized: -9)
        XCTAssertEqual(court.fineAim, -1.30)
        court.setPullBack(normalized: 5)
        XCTAssertEqual(court.pullBack, 1.20)
        court.setPullBack(normalized: -1)
        XCTAssertEqual(court.pullBack, 0)
        court.setAimAssistLevel(level: 9)
        XCTAssertEqual(court.aimAssistBaseLevel, 5)
        court.setAimAssistLevel(level: -2)
        XCTAssertEqual(court.aimAssistBaseLevel, 0)
        court.setHotHand(active: true)
        XCTAssertTrue(court.hotHand)
        court.setHorseJumpShot(enabled: true)
        XCTAssertTrue(court.horseJumpShot)
        court.setHumanShotStyle(style: .GRANNY)
        XCTAssertEqual(court.humanShotStyle, .GRANNY)

        court.prepareAnswerSpots(count: 3, seed: 7, randomize: true)
        XCTAssertEqual(court.activeStations.count, 3)
        court.setAnswerCount(count: 9)
        XCTAssertEqual(court.answerCount, 4)
        XCTAssertTrue(court.activeStations.isEmpty, "a station list of another size is dropped")

        court.setLocalCharacters(humanCharacterId: "kyra", botCharacterId: "zephyr")
        XCTAssertEqual(court.humanCharacterId, "kyra")
        XCTAssertEqual(court.botCharacterId, "zephyr")
        XCTAssertFalse(court.humanCourtFacingInitialized)
    }

    func testHorsePickerFalseReShowsAnswerMarkers() {
        let court = TripleShotCourtView()
        court.setHorseFreeMoveEnabled(enabled: false)
        XCTAssertFalse(court.answerMarkersVisible)
        XCTAssertNil(court.findStationAt(x: 10, y: 10), "hidden markers never hit")
        court.setHorseSpotPickerVisible(visible: false)
        XCTAssertTrue(court.answerMarkersVisible, "Android quirk: hiding the picker re-shows A/B/C/D")
        XCTAssertNil(court.horseSelectedSpotId)
        court.setHorseSpotPickerVisible(visible: true)
        XCTAssertFalse(court.answerMarkersVisible)
        XCTAssertNil(court.findHorseSpotAt(x: 1, y: 1), "unlaid-out view")
    }

    func testUnlaidOutCallsAreNoOpsOrDeferred() {
        let court = TripleShotCourtView()
        let source = court.currentPlayerSourcePosition()
        XCTAssertEqual(source.x, 0)
        XCTAssertEqual(source.y, 0)

        court.horseFreeMoveEnabled = true
        XCTAssertNil(court.lockCurrentHorseFreeSpot())

        var resetEnded = false
        court.resetOneOnOneCheckPositions(humanOffense: true, animate: false, onEnd: { resetEnded = true })
        XCTAssertFalse(resetEnded, "returns without onEnd outside 1v1 / before layout")

        var botEnds = 0
        court.moveBotToOpenWaitingSpot(seed: 1, animate: true, onEnd: { botEnds += 1 })
        court.moveBotToHorseSpot(spotId: "L01", animate: true, onEnd: { botEnds += 1 })
        court.moveBotToHorseWaitingSpot(avoidSpotId: "L01", seed: 1, animate: true, onEnd: { botEnds += 1 })
        XCTAssertEqual(botEnds, 3, "without a bot every bot walk ends at once")

        court.moveHumanToHorseSourceSpot(sourceX: 650, sourceY: 1090, spotId: "later", animate: false)
        XCTAssertNil(court.horseHumanStation, "deferred with post until laid out")
        XCTAssertFalse(court.humanWaitingForTurn)
    }

    func testLockCurrentHorseFreeSpotStoresSourceStation() {
        let court = laidOutCourt()
        court.setHorseFreeMoveEnabled(enabled: true)
        court.playerX = 300
        court.playerFootY = 1900
        let id = court.lockCurrentHorseFreeSpot()
        XCTAssertEqual(id, "FREE_1")
        let station = court.horseCustomSpots["FREE_1"]
        XCTAssertNotNil(station)
        XCTAssertEqual(station?.zone, "horse_free")
        XCTAssertEqual(court.horseHumanStation, station)
        XCTAssertEqual(court.horseSelectedSpotId, "FREE_1")
        XCTAssertFalse(court.horseFreeMoveEnabled)
        if let s = station {
            let dx = s.sourceX - 750
            let dy = s.sourceY - 340
            XCTAssertEqual(s.distanceDifficulty, ((ksqrt(dx * dx + dy * dy) - 330) / 720).coerceIn(0.18, 0.95))
            XCTAssertTrue(s.sourceX >= 0 && s.sourceX <= 1024 && s.sourceY >= 0 && s.sourceY <= 1536)
        }
        XCTAssertNil(court.lockCurrentHorseFreeSpot(), "free move is off after a lock")
        court.setHorseFreeMoveEnabled(enabled: true)
        XCTAssertEqual(court.lockCurrentHorseFreeSpot(), "FREE_2")
        court.clearHorseModeVisuals()
        XCTAssertEqual(court.horseCustomSpotCounter, 0)
        XCTAssertTrue(court.horseCustomSpots.isEmpty)
        XCTAssertTrue(court.answerMarkersVisible)
        court.setHorseFreeMoveEnabled(enabled: true)
        XCTAssertEqual(court.lockCurrentHorseFreeSpot(), "FREE_1")
    }

    func testHorseAnswerModeLocksOneSkinAndInfersTheOwner() {
        let court = TripleShotCourtView()
        court.botEnabled = true
        court.ballVisible = false
        court.botBallVisible = true
        court.setHorseAnswerMode()
        XCTAssertEqual(court.sharedHorseBallOwner, TripleShotCourtView.SharedBallOwner.BOT)
        XCTAssertFalse(court.ballVisible)
        XCTAssertTrue(court.botBallVisible)
        XCTAssertTrue(court.horseBallSkinLocked)
        XCTAssertTrue(court.ballResIds.contains(court.currentBallResId))
        let skin = court.currentBallResId
        court.randomizeBallSkin()
        XCTAssertEqual(court.currentBallResId, skin, "a locked HORSE skin never changes")

        let live = TripleShotCourtView()
        live.setHorseAnswerMode()
        XCTAssertNil(live.sharedHorseBallOwner)
        XCTAssertFalse(live.ballVisible)
        XCTAssertFalse(live.botBallVisible)
    }

    func testMatchCelebrationPosesAndClear() {
        let court = TripleShotCourtView()
        court.botEnabled = true
        court.sharedHorseBallOwner = .HUMAN
        court.startHorseMatchCelebration(humanWon: false)
        XCTAssertEqual(court.humanEndPose, TripleShotPlayerRenderer.Pose.LOSER)
        XCTAssertEqual(court.botEndPose, TripleShotPlayerRenderer.Pose.WINNER)
        XCTAssertFalse(court.ballVisible)
        XCTAssertFalse(court.botBallVisible)
        XCTAssertFalse(court.answerMarkersVisible)
        XCTAssertNotNil(court.matchCelebrationAnimator)
        XCTAssertEqual(court.matchCelebrationAnimator?.duration, 2800)
        court.clearMatchCelebration()
        XCTAssertNil(court.matchCelebrationAnimator)
        XCTAssertEqual(court.humanEndPose, TripleShotPlayerRenderer.Pose.NORMAL)
        XCTAssertEqual(court.botEndPose, TripleShotPlayerRenderer.Pose.NORMAL)
        XCTAssertTrue(court.ballVisible)
        XCTAssertFalse(court.botBallVisible, "owner HUMAN keeps the bot ball hidden")
    }

    func testLiveOpponentsKeepTheFirstThreeAtTheIdleSpots() {
        let court = TripleShotCourtView()
        var players: [LivePlayerState] = []
        for (uid, name, score) in [("a", "Ann", 3), ("b", " ", 1), ("c", "Cy", 0), ("d", "Dee", 9)] {
            var p = LivePlayerState()
            p.uid = uid
            p.name = name
            p.score = score
            players.append(p)
        }
        court.setLiveOpponents(players: players)
        XCTAssertEqual(court.liveRemotePlayers.keys, ["a", "b", "c"])
        XCTAssertEqual(court.liveRemotePlayers["b"]?.name, "Player")
        XCTAssertEqual(court.liveRemotePlayers["a"]?.score, 3)
        let spots = TripleShotCourtView.LIVE_REMOTE_IDLE_SPOTS
        for (index, uid) in ["a", "b", "c"].enumerated() {
            XCTAssertEqual(court.liveRemotePlayers[uid]?.sourceX, spots[index].x)
            XCTAssertEqual(court.liveRemotePlayers[uid]?.sourceY, spots[index].y)
        }

        // Existing remotes only get name/score updates; a blank name keeps the old one.
        court.liveRemotePlayers["a"]?.sourceX = 400
        var renamed = players[0]
        renamed.name = ""
        renamed.score = 7
        court.setLiveOpponents(players: [players[2], renamed])
        XCTAssertEqual(court.liveRemotePlayers.keys, ["a", "c"])
        XCTAssertEqual(court.liveRemotePlayers["a"]?.name, "Ann")
        XCTAssertEqual(court.liveRemotePlayers["a"]?.score, 7)
        XCTAssertEqual(court.liveRemotePlayers["a"]?.sourceX, 400, "not moved")

        court.clearLiveOpponents()
        XCTAssertTrue(court.liveRemotePlayers.isEmpty)
    }

    func testLiveReplayCaptureDisableResetsTheSampleClock() {
        let court = TripleShotCourtView()
        court.setLiveReplayCaptureEnabled(enabled: true)
        court.liveReplaySamples = [ShotReplaySample(tMs: 1, x: 2, y: 3, depth: 0)]
        court.liveReplayStartedAtNanos = 99
        court.liveReplayLastSampleMs = 500
        court.setLiveReplayCaptureEnabled(enabled: true)
        XCTAssertEqual(court.liveReplaySamples.count, 1, "enabling alone does not start or clear a capture")
        court.setLiveReplayCaptureEnabled(enabled: false)
        XCTAssertTrue(court.liveReplaySamples.isEmpty)
        XCTAssertEqual(court.liveReplayStartedAtNanos, 0)
        XCTAssertEqual(court.liveReplayLastSampleMs, -55)
    }

    func testCourtStyleAndThemeAccessors() {
        let court = TripleShotCourtView()
        let style = TripleShotCourtStyle(
            id: "beach",
            titleRes: R.string.minik_swish_court_enchanted_forest,
            subtitleRes: R.string.minik_swish_court_enchanted_forest,
            landscapeDrawableName: "x",
            portraitDrawableName: nil,
            atmosphere: .LIGHT_SNOW
        )
        court.setCourtStyle(style: style)
        XCTAssertEqual(court.premiumCourtId, "beach")
        XCTAssertEqual(court.courtAtmosphere, .LIGHT_SNOW)
        XCTAssertEqual(court.currentCourtThemeId(), "enchanted_forest")
        XCTAssertEqual(court.spectatorSpots().count, 3)
        XCTAssertEqual(court.spectatorSpots()[1].sourceX, 520)
    }

    func testGameplayBoundaryIgnoresNonPositiveValues() {
        let court = TripleShotCourtView()
        court.setGameplayBottomBoundary(boundaryY: 0)
        XCTAssertNil(court.gameplayBottomBoundaryPx)
        court.setGameplayBottomBoundary(boundaryY: .nan)
        XCTAssertNil(court.gameplayBottomBoundaryPx)
        court.setGameplayBottomBoundary(boundaryY: 1234)
        XCTAssertEqual(court.gameplayBottomBoundaryPx, 1234)
    }
}
