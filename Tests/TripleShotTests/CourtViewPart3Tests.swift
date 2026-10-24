import XCTest
@testable import MinikTripleShot

// Parity tests for TripleShotCourtView+Part3.swift (Kotlin TripleShotCourtView.kt lines 5353-7945, spec 10-court3).
//
// The expected values in `CourtPart3Golden` were produced on the JVM by the harness
// scratchpad/swish/work/w-court3/harness/CourtPart3Golden.kt, which transcribes the Kotlin bodies of the functions
// under test and compiles them with the snapshot's own TripleShotPhysics.kt. Floats are compared as bit patterns.
//
// Everything here runs without a GPU: the court is created and laid out (`layout(0, 0, w, h)`) but never attached,
// so `onDraw`/`present` never run. Two values come from the device: `density` (UIScreen scale) and the window
// orientation (`resources.configuration.orientation`, which picks the portrait crop or the landscape stretch). The
// golden rows cover densities 2 and 3 and both orientations; each test checks the rows of the environment it runs in.

final class CourtViewPart3Tests: XCTestCase {

    private typealias G = CourtPart3Golden

    // MARK: - helpers

    private func fl(_ bits: UInt32) -> Float { return Float(bitPattern: bits) }

    private func assertBits(_ value: Float, _ bits: UInt32, _ message: String,
                            file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertEqual(value.bitPattern, bits,
                       "\(message): got \(value) (0x\(String(value.bitPattern, radix: 16, uppercase: true))), " +
                       "expected \(Float(bitPattern: bits)) (0x\(String(bits, radix: 16, uppercase: true)))",
                       file: file, line: line)
    }

    private func makeCourt(_ w: Int, _ h: Int) -> TripleShotCourtView {
        let view = TripleShotCourtView()
        view.layout(0, 0, w, h)
        return view
    }

    private func probe() -> TripleShotCourtView { return makeCourt(1080, 2400) }

    private func environmentIsLandscape(_ view: TripleShotCourtView) -> Bool {
        return view.resources.configuration.orientation == AConfiguration.ORIENTATION_LANDSCAPE
    }

    private func environmentDensity(_ view: TripleShotCourtView) -> Int? {
        let d = view.density
        return d == 2 ? 2 : (d == 3 ? 3 : nil)
    }

    /// The Android TripleShotShotPresentationTest geometry (density-independent).
    private let g0 = TripleShotPhysics.Geometry(1200, 750, 340, 655, 845, 5, 860, 215, 397, 505, 704, 792, 20)

    private func finish(_ name: String) -> TripleShotCourtView.OneOnOneDriveFinish {
        return TripleShotCourtView.OneOnOneDriveFinish.named(name)!
    }

    private func shotState(x: Float, y: Float, vx: Float, vy: Float, previousX: Float? = nil, previousY: Float? = nil,
                           elapsed: Float = 0, made: Bool = false, rimHits: Int = 0, backboardHits: Int = 0,
                           maxHeightReachedY: Float? = nil, rejectUpward: Bool = false,
                           enteredFromBelow: Bool = false) -> TripleShotPhysics.ShotState {
        return TripleShotPhysics.ShotState(
            x: x, y: y, vx: vx, vy: vy, startX: 0, startY: 0, targetX: 0, targetY: 0,
            initialVx: 0, initialVy: 0, gravity: 1200, expectedFlightSeconds: 1,
            pathMode: TripleShotPhysics.ShotPathMode.NORMAL, initialCurveAccelerationX: 0,
            previousX: previousX, previousY: previousY, elapsedSeconds: elapsed, made: made,
            rimHits: rimHits, backboardHits: backboardHits, maxHeightReachedY: maxHeightReachedY,
            rejectUpwardBasketEntry: rejectUpward, enteredBasketFromBelow: enteredFromBelow)
    }

    private func catalogStation(_ id: String) -> TripleShotCourtView.Station {
        return TripleShotCourtView.SHOT_SPOT_CATALOG.first { $0.id == id }!
    }

    // MARK: - companion object

    func testSpotCatalogsMatchKotlinCompanionOrderAndValues() {
        let catalog = TripleShotCourtView.SHOT_SPOT_CATALOG
        XCTAssertEqual(catalog.count, G.shotSpotCatalog.count)
        for (i, row) in G.shotSpotCatalog.enumerated() where i < catalog.count {
            XCTAssertEqual(catalog[i].id, row.id)
            assertBits(catalog[i].sourceX, row.x, "\(row.id).sourceX")
            assertBits(catalog[i].sourceY, row.y, "\(row.id).sourceY")
            assertBits(catalog[i].distanceDifficulty, row.dd, "\(row.id).distanceDifficulty")
            XCTAssertEqual(catalog[i].zone, row.zone)
        }
        let practice = TripleShotCourtView.PRACTICE_SPOTS
        XCTAssertEqual(practice.count, G.practiceSpots.count)
        for (i, row) in G.practiceSpots.enumerated() where i < practice.count {
            XCTAssertEqual(practice[i].id, row.id)
            assertBits(practice[i].sourceX, row.x, "\(row.id).sourceX")
            assertBits(practice[i].sourceY, row.y, "\(row.id).sourceY")
            assertBits(practice[i].distanceDifficulty, row.dd, "\(row.id).distanceDifficulty")
            XCTAssertEqual(practice[i].zone, row.zone)
        }
        XCTAssertEqual(TripleShotCourtView.HORSE_SELECTABLE_SPOTS.map { $0.id }, G.horseSelectableIds)
        XCTAssertEqual(TripleShotCourtView.BOT_SPOT_CATALOG, TripleShotCourtView.HORSE_SELECTABLE_SPOTS)
        XCTAssertEqual(TripleShotCourtView.LIVE_REMOTE_IDLE_SPOTS, [APointF(155, 1180), APointF(520, 1260), APointF(805, 1115)])
        XCTAssertEqual(TripleShotCourtView.HEBREW_ANSWER_LABELS, ["\u{05D0}", "\u{05D1}", "\u{05D2}", "\u{05D3}"])
    }

    func testCompanionConstantsKeepKotlinTypesAndValues() {
        assertBits(TripleShotCourtView.MAX_PHYSICS_SUBSTEP_SECONDS, 0x3BB60B61, "MAX_PHYSICS_SUBSTEP_SECONDS = 1f / 180f")
        assertBits(TripleShotCourtView.PREVIEW_STEP_SECONDS, 0x3BB60B61, "PREVIEW_STEP_SECONDS = 1f / 180f")
        XCTAssertEqual(TripleShotCourtView.MIN_SOURCE_SPOT_DISTANCE_SQ, 18225)
        XCTAssertEqual(TripleShotCourtView.RELAXED_SOURCE_SPOT_DISTANCE_SQ, 8100)
        XCTAssertEqual(TripleShotCourtView.PREVIOUS_QUESTION_AVOID_DISTANCE_SQ, 8464)
        XCTAssertEqual(TripleShotCourtView.BOT_ANSWER_AVOID_DISTANCE_SQ, 11025)
        XCTAssertEqual(TripleShotCourtView.HORSE_WAIT_MIN_DISTANCE_SQ, 57600)
        XCTAssertEqual(TripleShotCourtView.BOT_SPOT_SEED_SALT, 0x424F5453504F54)
        XCTAssertEqual(TripleShotCourtView.CHALLENGE_WAIT_SEED_SALT, 0x4348414C57414954)
        XCTAssertEqual(TripleShotCourtView.HORSE_SPOT_SEED_SALT, 0x484F52534553504F)
        XCTAssertEqual(TripleShotCourtView.HORSE_WAIT_SEED_SALT, 0x57414954484F5253)
        XCTAssertEqual(TripleShotCourtView.ONE_ON_ONE_ATTACK_SEED_SALT, 0x314F4E314F4E454C)
        XCTAssertEqual(TripleShotCourtView.DRIBBLE_BOUNCES_DURING_MOVE, 2.0)
        XCTAssertEqual(TripleShotCourtView.PLAYER_MOVE_DURATION_MS, 455)
        XCTAssertEqual(TripleShotCourtView.HUMAN_IDLE_DRIBBLE_DELAY_MS, 2300)
        XCTAssertEqual(TripleShotCourtView.ONE_ON_ONE_IDLE_DRIBBLE_DELAY_MS, 80)
        XCTAssertEqual(TripleShotCourtView.LIVE_REPLAY_SAMPLE_INTERVAL_MS, 55)
        XCTAssertEqual(TripleShotCourtView.LIVE_MAX_REPLAY_SAMPLES, 60)
        XCTAssertEqual(TripleShotCourtView.AIM_ASSIST_MAX_LEVEL, 5)
        assertBits(TripleShotCourtView.HORSE_SIDE_TOP_FRACTION, Float(0.46).bitPattern, "HORSE_SIDE_TOP_FRACTION (the value, not the 58% comment)")
        XCTAssertEqual(TripleShotCourtView.BOT_VISIBLE_AIM_MS, 580)
        XCTAssertEqual(TripleShotCourtView.MIN_VISIBLE_RIM_IMPACT, 45)
        XCTAssertEqual(TripleShotCourtView.MIN_VISIBLE_NET_IMPACT, 32)
    }

    // MARK: - coordinate system and geometry

    func testBackgroundTransformMatchesKotlin() {
        let landscape = environmentIsLandscape(probe())
        var checked = 0
        for row in G.transforms where row.landscape == landscape {
            let t = makeCourt(row.w, row.h).backgroundTransform()
            let values = [t.scaleX, t.scaleY, t.offsetX, t.offsetY]
            for (i, v) in values.enumerated() { assertBits(v, row.bits[i], "\(row.w)x\(row.h) transform[\(i)]") }
            checked += 1
        }
        XCTAssertGreaterThan(checked, 0)
        // Unsized view: the identity transform.
        let unsized = TripleShotCourtView().backgroundTransform()
        XCTAssertEqual(unsized, TripleShotCourtView.BackgroundTransform(scaleX: 1, scaleY: 1, offsetX: 0, offsetY: 0))
    }

    func testPhysicsGeometryAimRangeAndDefaultPointMatchKotlin() {
        let p = probe()
        let landscape = environmentIsLandscape(p)
        guard let density = environmentDensity(p) else { return }
        var checked = 0
        for row in G.geometries where row.landscape == landscape && row.density == density {
            let view = makeCourt(row.w, row.h)
            let g = view.buildPhysicsGeometry()
            let fields = [g.gravityPxPerSec2, g.hoopCenterX, g.hoopY, g.leftRimX, g.rightRimX, g.rimColliderRadius, g.backboardX,
                          g.backboardTopY, g.backboardBottomY, g.netBottomY, g.netBottomLeftX, g.netBottomRightX, g.ballRadius]
            for (i, v) in fields.enumerated() { assertBits(v, row.bits[i], "\(row.w)x\(row.h)@\(density) geometry[\(i)]") }
            assertBits(view.aimRangePx(), row.aimRange, "\(row.w)x\(row.h) aimRangePx")
            let d = view.defaultPlayerScreenPoint()
            assertBits(d.x, row.defaultPoint[0], "\(row.w)x\(row.h)@\(density) defaultPlayerScreenPoint.x")
            assertBits(d.y, row.defaultPoint[1], "\(row.w)x\(row.h)@\(density) defaultPlayerScreenPoint.y")
            // The first layout places the human at the default point (no HORSE station yet).
            assertBits(view.playerX, row.defaultPoint[0], "first layout playerX")
            assertBits(view.playerFootY, row.defaultPoint[1], "first layout playerFootY")
            XCTAssertTrue(view.hasInitialPlayerPosition)
            checked += 1
        }
        XCTAssertGreaterThan(checked, 0)
    }

    func testSourcePointToViewUsesTheTransform() {
        let view = probe()
        let t = view.backgroundTransform()
        let p = view.sourcePointToView(sourceX: 750, sourceY: 340)
        XCTAssertEqual(p.x.bitPattern, (t.offsetX + 750 * t.scaleX).bitPattern)
        XCTAssertEqual(p.y.bitPattern, (t.offsetY + 340 * t.scaleY).bitPattern)
        XCTAssertEqual(view.sourcePointToView(sourceX: 100, sourceY: 200, transform: t), view.sourcePointToView(sourceX: 100, sourceY: 200))
    }

    // MARK: - stations and seeded spot choice

    func testFallbackStationIdsMatchKotlin() {
        let view = probe()
        for row in G.fallbackIds {
            XCTAssertEqual(view.stationForAnswer(index: row.index, count: row.count).id, row.id, "index \(row.index) count \(row.count)")
        }
    }

    func testStationScreenPointsMatchKotlin() {
        let p = probe()
        let landscape = environmentIsLandscape(p)
        guard let density = environmentDensity(p) else { return }
        var checked = 0
        for row in G.fallbackStationPoints where row.landscape == landscape && row.density == density {
            let view = makeCourt(row.w, row.h)
            view.gameplayBottomBoundaryPx = row.boundary.map { Float(bitPattern: $0) }
            var k = 0
            for count in 2...4 {
                for i in 0..<count {
                    let s = view.stationScreenPoint(index: i, count: count)
                    assertBits(s.x, row.bits[k], "\(row.w)x\(row.h) boundary \(String(describing: row.boundary)) station \(i)/\(count).x")
                    assertBits(s.y, row.bits[k + 1], "\(row.w)x\(row.h) boundary \(String(describing: row.boundary)) station \(i)/\(count).y")
                    k += 2
                }
            }
            checked += 1
        }
        XCTAssertGreaterThan(checked, 0)
        for row in G.catalogBotPoints where row.landscape == landscape && row.density == density {
            let view = makeCourt(row.w, row.h)
            for (i, station) in TripleShotCourtView.SHOT_SPOT_CATALOG.enumerated() {
                let s = view.botStationScreenPoint(station: station)
                assertBits(s.x, row.bits[2 * i], "\(row.w)x\(row.h) \(station.id).x")
                assertBits(s.y, row.bits[2 * i + 1], "\(row.w)x\(row.h) \(station.id).y")
            }
        }
    }

    func testChooseBotStationMatchesKotlin() {
        let p = probe()
        let landscape = environmentIsLandscape(p)
        guard let density = environmentDensity(p) else { return }
        var checked = 0
        for row in G.botStationChoices where row.landscape == landscape && row.density == density {
            let view = makeCourt(row.w, row.h)
            if row.scenario == 0 {
                let d = view.defaultPlayerScreenPoint()
                view.playerX = d.x; view.playerFootY = d.y
                view.recentBotSpotIds = []
            } else {
                let s = view.stationScreenPoint(index: 1, count: 3)
                view.playerX = s.x; view.playerFootY = s.y
                view.recentBotSpotIds = G.botStationRecent
            }
            XCTAssertEqual(view.chooseBotStation(seed: row.seed).id, row.id, "\(row.w)x\(row.h) scenario \(row.scenario) seed \(row.seed)")
            checked += 1
        }
        XCTAssertGreaterThan(checked, 0)
    }

    func testChooseHorseWaitingStationMatchesKotlin() {
        let view = probe()
        for row in G.horseWaitingChoices {
            XCTAssertEqual(view.chooseHorseWaitingStation(avoidSpotId: row.avoid, seed: row.seed, preferLeft: row.preferLeft).id, row.id,
                           "avoid \(row.avoid) seed \(row.seed) preferLeft \(row.preferLeft)")
        }
    }

    func testChooseChallengeWaitingStationMatchesKotlin() {
        let view = probe()
        for row in G.challengeWaitingChoices {
            let avoid: TripleShotCourtView.Station
            switch row.avoid {
            case "fallback_3b": avoid = view.stationForAnswer(index: 1, count: 3)
            case "fallback_2a": avoid = view.stationForAnswer(index: 0, count: 2)
            default: avoid = catalogStation(row.avoid)
            }
            XCTAssertEqual(avoid.id, row.avoid)
            XCTAssertEqual(view.chooseChallengeWaitingStation(avoid: avoid, seed: row.seed).id, row.id, "avoid \(row.avoid) seed \(row.seed)")
        }
    }

    func testHorseStationByIdPrefersCustomSpotsThenFullCatalog() {
        let view = probe()
        XCTAssertEqual(view.horseStationById(id: "H04")?.id, "H04", "the full catalog still resolves H03-H05")
        XCTAssertNil(view.horseStationById(id: "FREE_1"))
        let custom = TripleShotCourtView.Station(id: "C01", sourceX: 1, sourceY: 2, distanceDifficulty: 0.5, zone: "horse_free")
        view.horseCustomSpots["C01"] = custom
        XCTAssertEqual(view.horseStationById(id: "C01"), custom)
    }

    func testRememberBotSpotKeepsTheFiveMostRecent() {
        let view = probe()
        for id in ["A", "B", "C", "D", "E", "F"] { view.rememberBotSpot(id: id) }
        XCTAssertEqual(view.recentBotSpotIds, ["B", "C", "D", "E", "F"])
        view.rememberBotSpot(id: "C")
        XCTAssertEqual(view.recentBotSpotIds, ["B", "D", "E", "F", "C"])
    }

    // MARK: - aim guide

    func testArcPreviewFlightFractionMatchesKotlin() {
        let view = probe()
        for row in G.arcFractions {
            let mode: TripleShotPhysics.ShotPathMode = row.highLob ? .HIGH_LOB : .NORMAL
            assertBits(view.arcPreviewFlightFraction(effectiveLevel: fl(row.level), pathMode: mode), row.bits,
                       "level \(fl(row.level)) \(mode)")
        }
    }

    func testEffectiveAimAssistLevelMatchesKotlin() {
        let view = probe()
        for row in G.aimAssistLevels {
            view.aimAssistBaseLevel = row.base
            assertBits(view.effectiveAimAssistLevel(station: catalogStation(row.id)), row.bits, "\(row.id) base \(row.base)")
        }
    }

    func testGuidePointsAreEmptyWhileGuidesAreHidden() {
        let view = probe()
        view.shotGuidesVisible = false
        let human = TripleShotWorldActor(id: "human", position: CourtPoint(x: 0, y: 0, z: 0), state: view.humanRendererState(),
                                         controlled: true, team: 1)
        XCTAssertTrue(view.premiumGuidePoints(human: human, hoop: CourtPoint(x: 3.332, y: 3.35, z: 0)).isEmpty)
        view.shotGuidesVisible = true
        view.horseJumpShot = true
        XCTAssertTrue(view.premiumGuidePoints(human: human, hoop: CourtPoint(x: 3.332, y: 3.35, z: 0)).isEmpty)
        view.horseJumpShot = false
        view.selectedStation = -1
        view.horseHumanStation = nil
        XCTAssertTrue(view.premiumGuidePoints(human: human, hoop: CourtPoint(x: 3.332, y: 3.35, z: 0)).isEmpty)
    }

    // MARK: - live helpers

    func testLiveDistanceDifficultyMatchesKotlin() {
        let view = probe()
        for row in G.liveDifficulty {
            assertBits(view.liveDistanceDifficulty(sourceX: fl(row.x), sourceY: fl(row.y)), row.bits, "(\(fl(row.x)), \(fl(row.y)))")
        }
    }

    // MARK: - motion, facing and mirror

    func testPreReleaseMotionThresholds() {
        let view = probe()
        for row in G.preRelease {
            XCTAssertEqual(view.preReleaseHumanMotionForPull(pull: fl(row.pull)).name, row.motion, "pull \(fl(row.pull))")
        }
    }

    func testCourtFacingHumanHysteresisAndBotHardSwitch() {
        let landscape = environmentIsLandscape(probe())
        var checked = 0
        for row in G.facingSequences where row.landscape == landscape {
            let view = makeCourt(row.w, row.h)
            // Android 6c38131: the court-Y rule is reached only in 1v1 (outside it currentHumanFacing /
            // currentBotFacing return the shot facing, checked below). No ball owner, no loose ball, no spin.
            view.oneOnOneEnabled = true
            // The first layout already resolved the human's court facing once; restart from Kotlin's initial state.
            view.humanCourtFacing = TripleShotPlayerRenderer.Facing.BACK
            view.humanCourtFacingInitialized = false
            view.botCourtFacing = TripleShotPlayerRenderer.Facing.BACK
            for (i, step) in row.steps.enumerated() {
                view.playerFootY = fl(step.footY)
                view.botFootY = fl(step.footY)
                XCTAssertEqual(view.currentHumanFacing(motion: .IDLE).name, step.human, "\(row.w)x\(row.h) human step \(i)")
                XCTAssertEqual(view.currentBotFacing(motion: .IDLE).name, step.bot, "\(row.w)x\(row.h) bot step \(i)")
            }
            checked += 1
        }
        XCTAssertGreaterThan(checked, 0)
    }

    /// Android 6c38131: `if(!oneOnOneEnabled) return currentHumanShotFacing()` (and the bot's), for every motion.
    func testFacingOutsideOneOnOneIsTheShotFacing() {
        let landscape = environmentIsLandscape(probe())
        var checked = 0
        for row in G.shotFacings where row.landscape == landscape {
            let view = makeCourt(row.w, row.h)
            view.playerX = fl(row.x); view.playerFootY = fl(row.y)
            view.botX = fl(row.x); view.botFootY = fl(row.y)
            for motion in [TripleShotPlayerRenderer.Motion.IDLE, .SHOT_SET, .STEAL] {
                XCTAssertEqual(view.currentHumanFacing(motion: motion).name, row.shot, "\(row.w)x\(row.h) human \(motion)")
                XCTAssertEqual(view.currentBotFacing(motion: motion).name, row.shot, "\(row.w)x\(row.h) bot \(motion)")
            }
            checked += 1
        }
        XCTAssertGreaterThan(checked, 0)
    }

    func testShotFacingSelectorsMatchKotlin() {
        let landscape = environmentIsLandscape(probe())
        var checked = 0
        for row in G.shotFacings where row.landscape == landscape {
            let view = makeCourt(row.w, row.h)
            XCTAssertEqual(view.shotFacingFor(actorX: fl(row.x), actorFootY: fl(row.y), fallback: .BACK).name, row.shot,
                           "\(row.w)x\(row.h) shotFacingFor(\(fl(row.x)), \(fl(row.y)))")
            XCTAssertEqual(view.oneOnOneShotFacingFor(actorX: fl(row.x), actorFootY: fl(row.y), fallback: .BACK).name, row.oneOnOne,
                           "\(row.w)x\(row.h) oneOnOneShotFacingFor(\(fl(row.x)), \(fl(row.y)))")
            checked += 1
        }
        XCTAssertGreaterThan(checked, 0)
        let unsized = TripleShotCourtView()
        XCTAssertEqual(unsized.shotFacingFor(actorX: 0, actorFootY: 0, fallback: .SIDE), .SIDE)
        XCTAssertEqual(unsized.oneOnOneShotFacingFor(actorX: 0, actorFootY: 0, fallback: .FRONT), .FRONT)
        XCTAssertEqual(unsized.oneOnOneDefenderFacing(defenderX: 0, defenderFootY: 10, ballHandlerX: 0, ballHandlerFootY: 0), .FRONT)
        XCTAssertEqual(unsized.oneOnOneHoopFacingFor(footY: 5000), .BACK)
    }

    func testOneOnOneActionAndHoopFacingMatchKotlin() {
        let p = probe()
        let landscape = environmentIsLandscape(p)
        guard let density = environmentDensity(p) else { return }
        for row in G.actionFacings where row.density == density {
            XCTAssertEqual(p.oneOnOneActionFacing(actorX: fl(row.ax), actorFootY: fl(row.ay), targetX: fl(row.tx), targetY: fl(row.ty)).name,
                           row.facing, "actor (\(fl(row.ax)), \(fl(row.ay))) target (\(fl(row.tx)), \(fl(row.ty)))")
        }
        var checked = 0
        for row in G.hoopFacings where row.landscape == landscape && row.density == density {
            let view = makeCourt(row.w, row.h)
            XCTAssertEqual(view.oneOnOneHoopFacingFor(footY: fl(row.footY)).name, row.facing, "\(row.w)x\(row.h) footY \(fl(row.footY))")
            checked += 1
        }
        XCTAssertGreaterThan(checked, 0)
        // Defender facing: FRONT when the handler's feet are level with or below the defender's on screen.
        XCTAssertEqual(p.oneOnOneDefenderFacing(defenderX: 0, defenderFootY: 100, ballHandlerX: 500, ballHandlerFootY: 100), .FRONT)
        XCTAssertEqual(p.oneOnOneDefenderFacing(defenderX: 0, defenderFootY: 100, ballHandlerX: 0, ballHandlerFootY: 99.9), .BACK)
    }

    func testMotionClassifiersAndVisualScale() {
        let view = probe()
        let shot: [TripleShotPlayerRenderer.Motion] = [.DUNK, .SHOT_LOW, .SHOT_MID, .SHOT_SET, .RELEASE]
        let botShot: [TripleShotPlayerRenderer.Motion] = [.SHOT_LOW, .SHOT_MID, .SHOT_SET, .RELEASE]
        let action: [TripleShotPlayerRenderer.Motion] = [.STEAL, .BLOCK, .REBOUND, .DUNK]
        for m in TripleShotPlayerRenderer.Motion.allCases {
            XCTAssertEqual(view.isHumanShotMotion(motion: m), shot.contains(m), "isHumanShotMotion \(m)")
            XCTAssertEqual(view.isBotShotMotion(motion: m), botShot.contains(m), "isBotShotMotion \(m)")
            XCTAssertEqual(view.isOneOnOneActionMotion(motion: m), action.contains(m), "isOneOnOneActionMotion \(m)")
            XCTAssertEqual(view.oneOnOneVisualScale(motion: m), 1, "visual scale outside 1v1")
        }
        view.oneOnOneEnabled = true
        XCTAssertEqual(view.oneOnOneVisualScale(motion: .IDLE).bitPattern, Float(1.10).bitPattern)
        XCTAssertEqual(view.oneOnOneVisualScale(motion: .DUNK), 1)
    }

    func testHumanMotionPriorityOutsideOneOnOne() {
        let view = probe()
        XCTAssertEqual(view.currentHumanMotion(), .IDLE)
        view.humanWaitingForTurn = true
        XCTAssertEqual(view.currentHumanMotion(), .WAITING)
        view.humanWalking = true
        // Practice / Challenge: no shared owner, so the human owns the ball and dribbles while walking.
        XCTAssertEqual(view.currentHumanMotion(), .DRIBBLE)
        view.sharedHorseBallOwner = .BOT
        XCTAssertEqual(view.currentHumanMotion(), .WALK)
        view.selectedStation = 0
        view.shotGuidesVisible = true
        view.pullBack = 0.5
        XCTAssertEqual(view.currentHumanMotion(), .SHOT_SET)
        view.shotFrameRunning = true
        view.humanReleaseStartedAtNanos = 0
        XCTAssertEqual(view.currentHumanMotion(), .IDLE, "a release time of 0 counts as an infinite elapsed time")
        view.humanReleaseStartedAtNanos = ASystem.nanoTime()
        XCTAssertEqual(view.currentHumanMotion(), .RELEASE)
        view.humanEndPose = .WINNER
        XCTAssertEqual(view.currentHumanMotion(), .IDLE)
        view.shotFrameRunning = false
    }

    func testBotMotionPriorityOutsideOneOnOne() {
        let view = probe()
        XCTAssertEqual(view.currentBotMotion(), .IDLE)
        view.botPullBack = 0.3
        XCTAssertEqual(view.currentBotMotion(), .SHOT_MID)
        view.botPullBack = 0.015
        XCTAssertEqual(view.currentBotMotion(), .IDLE, "the bot pose threshold is a strict > 0.015")
        view.botShotFrameRunning = true
        XCTAssertEqual(view.currentBotMotion(), .RELEASE)
        view.botEndPose = .LOSER
        XCTAssertEqual(view.currentBotMotion(), .IDLE)
        view.botShotFrameRunning = false
    }

    func testBallOwnershipAndIdleDribbleEligibility() {
        let view = probe()
        XCTAssertTrue(view.humanOwnsVisibleBall(), "outside 1v1 a nil owner counts as the human's ball")
        XCTAssertFalse(view.canHumanIdleDribble(), "Practice / Challenge (owner nil) never idle-dribble")
        view.sharedHorseBallOwner = .HUMAN
        XCTAssertTrue(view.canHumanIdleDribble())
        view.shotGuidesVisible = true
        XCTAssertFalse(view.canHumanIdleDribble())
        view.shotGuidesVisible = false
        view.oneOnOneEnabled = true
        XCTAssertTrue(view.humanOwnsVisibleBall())
        view.sharedHorseBallOwner = nil
        XCTAssertFalse(view.humanOwnsVisibleBall(), "in 1v1 only owner == HUMAN owns the ball")
        view.oneOnOneEnabled = false
        view.sharedHorseBallOwner = .BOT
        XCTAssertFalse(view.humanOwnsVisibleBall())
    }

    func testGiveSharedBallSwitchesVisibilityAndResetsSpin() {
        let view = probe()
        view.botEnabled = true
        view.ballRotationDeg = 33
        view.giveSharedHorseBallToBot()
        XCTAssertEqual(view.sharedHorseBallOwner, .BOT)
        XCTAssertFalse(view.ballVisible)
        XCTAssertTrue(view.botBallVisible)
        XCTAssertEqual(view.botBallRotationDeg, 0)
        view.giveSharedHorseBallToHuman()
        XCTAssertEqual(view.sharedHorseBallOwner, .HUMAN)
        XCTAssertTrue(view.ballVisible)
        XCTAssertFalse(view.botBallVisible)
        XCTAssertEqual(view.ballRotationDeg, 0)
        let held = view.heldBallPosition(motionOverride: .IDLE)
        XCTAssertEqual(view.ballX, held.x)
        XCTAssertEqual(view.ballY, held.y)
        view.cancelHumanIdleDribble()
    }

    func testHeldBallUsesTheRendererSocketOutsideACrossover() {
        let view = probe()
        let expected = view.playerRenderer.heldBallPosition(state: view.humanRendererState(motionOverride: .SHOT_MID))
        XCTAssertEqual(view.heldBallPosition(motionOverride: .SHOT_MID), expected)
        view.botEnabled = true
        let bot = view.playerRenderer.heldBallPosition(state: view.botRendererState())
        XCTAssertEqual(view.heldBotBallPosition(), bot)
    }

    func testRendererStatesCarryTheGameplayFields() {
        let view = probe()
        view.fineAim = 0.4
        view.pullBack = 0.2
        view.hotHand = true
        let human = view.humanRendererState()
        XCTAssertEqual(human.x, view.playerX)
        XCTAssertEqual(human.footY, view.playerFootY)
        XCTAssertEqual(human.fineAim.bitPattern, Float(0.4).bitPattern)
        XCTAssertTrue(human.hotHand)
        XCTAssertEqual(human.style, .HUMAN)
        XCTAssertEqual(human.shotStyle, .PRO)
        XCTAssertEqual(human.characterId, TripleShotCharacterRoster.ID_WOMAN_DARK)
        XCTAssertEqual(human.actionFrameIndex, -1)
        XCTAssertEqual(view.humanRendererState(motionOverride: .SHOT_LOW).motion, .SHOT_LOW)
        view.horseGathering = true
        XCTAssertEqual(view.humanRendererState().motion, .SHOT_SET, "the HORSE jump-shot gather forces SHOT_SET")
        view.horseGathering = false
        let bot = view.botRendererState()
        XCTAssertEqual(bot.style, .BOT)
        XCTAssertEqual(bot.dribblePhase01, 0, "the bot's dribble phase is never set (Android parity)")
        XCTAssertEqual(bot.characterId, TripleShotCharacterRoster.ID_BOB)
        XCTAssertEqual(bot.shotStyle, TripleShotCharacterVisualCatalog.hasVisuals(characterId: TripleShotCharacterRoster.ID_BOB) ? .PRO : .GRANNY)
    }

    // MARK: - movement

    func testSnapMovesCallOnEndSynchronously() {
        let view = probe()
        var humanEnded = 0
        view.setPlayerPosition(x: 123, y: 456, animate: false) { humanEnded += 1 }
        XCTAssertEqual(humanEnded, 1)
        XCTAssertEqual(view.playerX, 123)
        XCTAssertEqual(view.playerFootY, 456)
        XCTAssertFalse(view.humanWalking)
        var botEnded = 0
        view.botDribbleBouncePx = 9
        view.setBotPosition(x: 321, y: 654, animate: false) { botEnded += 1 }
        XCTAssertEqual(botEnded, 1)
        XCTAssertEqual(view.botX, 321)
        XCTAssertEqual(view.botFootY, 654)
        XCTAssertEqual(view.botDribbleBouncePx, 0)
    }

    /// Android 6c38131 (938db79): a bounce never flips the hand ("Crossovers are explicit actions"); a new index only
    /// puts the ball in front and is remembered.
    func testMovingDribbleBounceKeepsTheHandAndPassesInFront() {
        let view = probe()
        view.humanWalkingDribbleHandSign = 1
        view.humanWalkingBallPassInFront = false
        view.humanWalkingBounceIndex = 0
        view.humanMovingFast = false
        view.updateMovingDribbleBounceIndex(newIndex: 1)
        XCTAssertEqual(view.humanWalkingDribbleHandSign, 1)
        XCTAssertTrue(view.humanWalkingBallPassInFront)
        XCTAssertEqual(view.humanWalkingBounceIndex, 1)
        view.humanWalkingBallPassInFront = false
        view.updateMovingDribbleBounceIndex(newIndex: 1)
        XCTAssertFalse(view.humanWalkingBallPassInFront, "same index: no change")
        view.updateMovingDribbleBounceIndex(newIndex: 4)
        XCTAssertEqual(view.humanWalkingDribbleHandSign, 1, "several steps still keep the hand")
        XCTAssertTrue(view.humanWalkingBallPassInFront)
        view.humanMovingFast = true
        view.updateMovingDribbleBounceIndex(newIndex: 5)
        XCTAssertEqual(view.humanWalkingDribbleHandSign, 1)
        XCTAssertEqual(view.humanWalkingBounceIndex, 5)
    }

    func testMovementSpeedHysteresis() {
        let view = probe()
        view.resetHumanMovementSpeed()
        view.humanMovementSampleNanos = 0
        // First sample: dt = 1/60 s.
        let d = view.density
        view.updateHumanMovementSpeed(distancePx: 3 * d, nowNanos: 1_000_000_000)
        let expected: Float = (3 * d / d.coerceAtLeast(0.1)) / (Float(1) / Float(60)).coerceAtLeast(0.001)
        XCTAssertEqual(view.humanMovementSpeedDpPerSec.bitPattern, expected.bitPattern)
        XCTAssertFalse(view.humanMovingFast, "180 dp/s is below the 185 dp/s entry threshold")
        view.updateHumanMovementSpeed(distancePx: 0, nowNanos: 1_016_000_000)
        XCTAssertEqual(view.humanMovementSampleNanos, 1_000_000_000, "a zero distance is ignored")
        view.updateHumanMovementSpeed(distancePx: 10 * d, nowNanos: 1_016_666_667)
        XCTAssertTrue(view.humanMovingFast)
        view.resetHumanMovementSpeed()
        XCTAssertFalse(view.humanMovingFast)
        XCTAssertEqual(view.humanMovementSpeedDpPerSec, 0)
        XCTAssertEqual(view.humanMovementSampleNanos, 0)
    }

    // MARK: - rim / net feedback

    func testRimShakeAndNetKickAmplitudesMatchKotlin() {
        let view = probe()
        guard let density = environmentDensity(view) else { return }
        for row in G.rimShakeAmplitudes where row.density == density {
            view.triggerRimShake(impactSpeed: fl(row.impact))
            assertBits(view.rimShakeAmplitudePx, row.bits, "rim shake amplitude for \(fl(row.impact)) px/s")
        }
        for row in G.netKicks where row.density == density {
            view.triggerNetKick(impactSpeed: fl(row.impact), directionHint: fl(row.hint))
            assertBits(view.netKickAmplitudePx, row.amplitude, "net kick amplitude for \(fl(row.impact)) px/s")
            assertBits(view.netKickDirection, row.direction, "net kick direction for hint \(fl(row.hint))")
        }
    }

    func testRimAndNetOffsetsDecayAndExpire() {
        let view = probe()
        view.rimShakeStartedAtNanos = 0
        view.netKickStartedAtNanos = 0
        XCTAssertEqual(view.currentRimShakeOffset(), 0)
        XCTAssertEqual(view.currentNetKickOffset(), APointF(0, 0))
        view.triggerRimShake(impactSpeed: 520)
        view.triggerNetKick(impactSpeed: 420, directionHint: -1)
        // Within the window the offsets are bounded by the amplitudes.
        XCTAssertLessThanOrEqual(abs(view.currentRimShakeOffset()), view.rimShakeAmplitudePx)
        XCTAssertLessThanOrEqual(abs(view.currentNetKickOffset().x), view.netKickAmplitudePx)
        // 0.1 s after the start: Kotlin's formula, evaluated at the age the view measures (time moves on in between).
        view.rimShakeStartedAtNanos = ASystem.nanoTime() &- 100_000_000
        let rim = view.currentRimShakeOffset()
        let rimAt100ms = ksin(0.1 * 47) * kexp(-0.1 * 7.5) * view.rimShakeAmplitudePx
        XCTAssertEqual(rim, rimAt100ms, accuracy: abs(view.rimShakeAmplitudePx) * 0.05)
        // Expired: 0.48 s (rim) and 0.62 s (net).
        view.rimShakeStartedAtNanos = ASystem.nanoTime() &- 480_000_000
        XCTAssertEqual(view.currentRimShakeOffset(), 0)
        view.netKickStartedAtNanos = ASystem.nanoTime() &- 620_000_000
        XCTAssertEqual(view.currentNetKickOffset(), APointF(0, 0))
    }

    // MARK: - 1v1 post-processing

    func testRelaxedMakeMatchesKotlin() {
        let view = probe()
        view.oneOnOneEnabled = true
        for row in G.relaxedMakes {
            let s = shotState(x: fl(row.x), y: fl(row.y), vx: 0, vy: fl(row.vy), previousX: fl(row.px), previousY: fl(row.py),
                              made: row.made, maxHeightReachedY: fl(row.maxH), rejectUpward: row.reject, enteredFromBelow: row.below)
            XCTAssertEqual(view.maybeMarkOneOnOneRelaxedMake(state: s, geometry: g0), row.result,
                           "relaxed make x \(fl(row.x)) y \(fl(row.y)) prev (\(fl(row.px)), \(fl(row.py))) made \(row.made) below \(row.below) reject \(row.reject)")
            XCTAssertEqual(s.made, row.madeAfter)
        }
        view.oneOnOneEnabled = false
        let s = shotState(x: 750, y: 345, vx: 0, vy: 300, previousX: 748, previousY: 335, maxHeightReachedY: 300)
        XCTAssertFalse(view.maybeMarkOneOnOneRelaxedMake(state: s, geometry: g0), "1v1 only")
        XCTAssertFalse(s.made)
    }

    func testReboundVelocityMatchesKotlin() {
        let view = probe()
        guard let density = environmentDensity(view) else { return }
        for row in G.reboundVelocities where row.density == density {
            let s = shotState(x: 0, y: 0, vx: fl(row.vx), vy: fl(row.vy), rimHits: row.rimHits, backboardHits: row.boardHits)
            let r = view.oneOnOnePlayableReboundVelocity(state: s, finish: finish(row.finish))
            assertBits(r.x, row.outX, "rebound \(row.finish) rim \(row.rimHits) board \(row.boardHits) vx")
            assertBits(r.y, row.outY, "rebound \(row.finish) rim \(row.rimHits) board \(row.boardHits) vy")
        }
    }

    func testImpactDampingMatchesKotlin() {
        let view = probe()
        for row in G.dampings {
            let s = shotState(x: 0, y: 0, vx: fl(row.vx), vy: fl(row.vy))
            view.dampOneOnOneShotImpact(state: s, result: TripleShotPhysics.StepResult(rimImpactSpeed: fl(row.rim), backboardImpactSpeed: fl(row.board)),
                                        finish: finish(row.finish))
            assertBits(s.vx, row.outX, "damping \(row.finish) rim \(fl(row.rim)) board \(fl(row.board)) vx")
            assertBits(s.vy, row.outY, "damping \(row.finish) rim \(fl(row.rim)) board \(fl(row.board)) vy")
        }
    }

    func testLooseBallHandoffMatchesKotlin() {
        let view = probe()
        guard let density = environmentDensity(view) else { return }
        view.oneOnOneEnabled = true
        for row in G.looseReady where row.density == density {
            let s = shotState(x: 700, y: fl(row.y), vx: 0, vy: fl(row.vy), elapsed: fl(row.elapsed), made: row.made,
                              rimHits: row.rimHits, backboardHits: row.boardHits)
            XCTAssertEqual(view.oneOnOneShotReadyForLooseBall(state: s, geometry: g0), row.ready,
                           "loose ready made \(row.made) vy \(fl(row.vy)) rim \(row.rimHits) board \(row.boardHits) t \(fl(row.elapsed)) y \(fl(row.y))")
        }
        view.oneOnOneEnabled = false
        let s = shotState(x: 700, y: 900, vx: 0, vy: 5, elapsed: 2, rimHits: 1)
        XCTAssertFalse(view.oneOnOneShotReadyForLooseBall(state: s, geometry: g0), "1v1 only")
    }

    // MARK: - shot completion and cancellation

    private func runFinishedHumanShot(_ view: TripleShotCourtView, made: Bool, rimHits: Int, backboardHits: Int,
                                      enteredFromBelow: Bool) -> TripleShotCourtView.ShotResult? {
        var received: TripleShotCourtView.ShotResult? = nil
        view.physicsState = shotState(x: 760, y: 700, vx: 10, vy: 200, made: made, rimHits: rimHits, backboardHits: backboardHits,
                                      enteredFromBelow: enteredFromBelow)
        view.physicsGeometry = g0
        view.shotFrameRunning = true
        view.pullBack = 0.8
        view.fineAim = 0.3
        view.humanReleaseStartedAtNanos = 99
        view.shotOnEnd = { received = $0 }
        view.finishPhysicsShot()
        return received
    }

    func testShotKindPriorityAndDeadBallRules() {
        typealias K = TripleShotCourtView.ShotKind
        let cases: [(made: Bool, rim: Int, board: Int, below: Bool, kind: K)] = [
            (true, 1, 1, false, .BANK_IN), (true, 0, 2, false, .BANK_IN), (true, 3, 0, false, .RIM_IN), (true, 0, 0, false, .SWISH),
            (true, 0, 0, true, .SWISH), (false, 2, 1, true, .INVALID_BELOW), (false, 2, 1, false, .RIM_OUT),
            (false, 0, 1, false, .BACKBOARD_OUT), (false, 0, 0, false, .AIRBALL)
        ]
        for c in cases {
            let view = probe()
            let result = runFinishedHumanShot(view, made: c.made, rimHits: c.rim, backboardHits: c.board, enteredFromBelow: c.below)
            XCTAssertEqual(result?.kind, c.kind, "made \(c.made) rim \(c.rim) board \(c.board) below \(c.below)")
            XCTAssertEqual(result?.outcome.made, c.made)
            XCTAssertEqual(result?.rimHits, c.rim)
            XCTAssertEqual(result?.backboardHits, c.board)
            XCTAssertEqual(result?.replaySamples.count, 0, "no Live capture: no samples")
            // Reset before the callback.
            XCTAssertFalse(view.shotFrameRunning)
            XCTAssertNil(view.physicsState)
            XCTAssertNil(view.physicsGeometry)
            XCTAssertNil(view.shotOnEnd)
            XCTAssertEqual(view.pullBack, 0)
            XCTAssertEqual(view.fineAim, 0)
            XCTAssertEqual(view.humanReleaseStartedAtNanos, 0)
            // Practice / Challenge: the ball goes back to the hand.
            XCTAssertTrue(view.ballVisible)
            XCTAssertEqual(view.ballRotationDeg, 0)
        }
        // HORSE (a shared owner or a HORSE station): the dead ball is hidden until the next handoff.
        let horse = probe()
        horse.sharedHorseBallOwner = .HUMAN
        _ = runFinishedHumanShot(horse, made: false, rimHits: 1, backboardHits: 0, enteredFromBelow: false)
        XCTAssertFalse(horse.ballVisible)
        // Not running: nothing happens and no callback.
        let idle = probe()
        var called = false
        idle.shotOnEnd = { _ in called = true }
        idle.physicsState = shotState(x: 0, y: 0, vx: 0, vy: 0)
        idle.physicsGeometry = g0
        idle.finishPhysicsShot()
        XCTAssertFalse(called)
    }

    func testBotShotCompletion() {
        let view = probe()
        view.botEnabled = true
        var received: TripleShotCourtView.ShotResult? = nil
        view.botPhysicsState = shotState(x: 760, y: 700, vx: 10, vy: 200, made: true, rimHits: 1)
        view.botPhysicsGeometry = g0
        view.botShotFrameRunning = true
        view.botPullBack = 0.6
        view.botFineAim = -0.2
        view.botBallRotationDeg = 77
        view.botShotOnEnd = { received = $0 }
        view.finishBotPhysicsShot()
        XCTAssertEqual(received?.kind, .RIM_IN)
        XCTAssertEqual(received?.replaySamples.count, 0)
        XCTAssertFalse(view.botShotFrameRunning)
        XCTAssertNil(view.botPhysicsState)
        XCTAssertEqual(view.botPullBack, 0)
        XCTAssertEqual(view.botFineAim, 0)
        XCTAssertEqual(view.botBallRotationDeg, 0)
        XCTAssertTrue(view.botBallVisible, "Challenge vs MINIK: the ball returns to the bot's hand")
        let held = view.heldBotBallPosition()
        XCTAssertEqual(view.botBallX, held.x)
        XCTAssertEqual(view.botBallY, held.y)
    }

    func testCancellationDropsTheCallback() {
        let view = probe()
        var called = false
        view.physicsState = shotState(x: 0, y: 0, vx: 0, vy: 0)
        view.physicsGeometry = g0
        view.shotFrameRunning = true
        view.shotOnEnd = { _ in called = true }
        view.shotLastFrameNanos = 5
        view.liveReplaySamples = [ShotReplaySample(tMs: 1, x: 2, y: 3, depth: 0)]
        view.liveReplayStartedAtNanos = 7
        view.liveReplayLastSampleMs = 400
        view.cancelShotSimulation(callEnd: false)
        XCTAssertFalse(called)
        XCTAssertFalse(view.shotFrameRunning)
        XCTAssertNil(view.physicsState)
        XCTAssertNil(view.shotOnEnd)
        XCTAssertEqual(view.shotLastFrameNanos, 0)
        XCTAssertTrue(view.liveReplaySamples.isEmpty)
        XCTAssertEqual(view.liveReplayStartedAtNanos, 0)
        XCTAssertEqual(view.liveReplayLastSampleMs, -55)

        var botCalled = false
        view.botPhysicsState = shotState(x: 0, y: 0, vx: 0, vy: 0)
        view.botPhysicsGeometry = g0
        view.botShotFrameRunning = true
        view.botShotOnEnd = { _ in botCalled = true }
        view.botPullBack = 0.4
        view.cancelBotShotSimulation(callEnd: false)
        XCTAssertFalse(botCalled)
        XCTAssertFalse(view.botShotFrameRunning)
        XCTAssertNil(view.botPhysicsState)
        XCTAssertNil(view.botShotOnEnd)
        XCTAssertEqual(view.botPullBack, 0)
    }

    func testHorseShotWithoutStationIsASilentNoOp() {
        let view = probe()
        view.horseHumanStation = nil
        var called = false
        let skill = ShotSkill(aimError: 0, powerError: 0, arcError: 0, rawPeakGyro: 0, rawReleasePitchDeg: 0)
        view.animateHorseShot(skill: skill, pullBackAtRelease: 0.7, hot: false) { _ in called = true }
        XCTAssertFalse(called)
        XCTAssertFalse(view.shotFrameRunning)
        XCTAssertNil(view.physicsState)
    }

    func testHorseShotLaunchesFromTheHorseStation() {
        let view = probe()
        view.horseHumanStation = catalogStation("C03")
        let skill = ShotSkill(aimError: 0.25, powerError: 0, arcError: 0, rawPeakGyro: 3, rawReleasePitchDeg: 14)
        view.animateHorseShot(skill: skill, pullBackAtRelease: 0.7, hot: true) { _ in }
        XCTAssertTrue(view.shotFrameRunning)
        XCTAssertTrue(view.hotHand)
        XCTAssertTrue(view.ballVisible)
        XCTAssertFalse(view.shotGuidesVisible)
        XCTAssertEqual(view.oneOnOneHumanActiveFinish, .JUMPER)
        guard let state = view.physicsState, let geometry = view.physicsGeometry else { return XCTFail("no launch") }
        XCTAssertEqual(geometry, view.buildPhysicsGeometry())
        XCTAssertEqual(state.x, view.ballX)
        XCTAssertEqual(state.y, view.ballY)
        // The same launch Kotlin builds (HORSE, not 1v1, no jump shot).
        view.shotFrameRunning = false
        let start = view.heldBallPosition(motionOverride: view.preReleaseHumanMotionForPull(pull: 0.7))
        let expected = TripleShotPhysics.createLaunch(
            skill: skill, startX: start.x, startY: start.y,
            targetX: geometry.hoopCenterX + skill.aimError.coerceIn(-1.30, 1.30) * view.aimRangePx(), targetY: geometry.hoopY,
            pullBack01: Float(0.7).coerceIn(0.22, 1.20), geometry: geometry, distanceDifficulty: catalogStation("C03").distanceDifficulty)
        XCTAssertEqual(state.vx.bitPattern, expected.vx.bitPattern)
        XCTAssertEqual(state.vy.bitPattern, expected.vy.bitPattern)
        XCTAssertEqual(state.expectedFlightSeconds.bitPattern, expected.expectedFlightSeconds.bitPattern)
        view.cancelShotSimulation(callEnd: false)
    }

    // MARK: - Live replay capture

    func testLiveReplayCaptureSamplesInSourceCoordinatesAndCapsAtSixty() {
        let view = probe()
        view.ballX = 600
        view.ballY = 900
        view.liveReplayCaptureEnabled = false
        view.beginLiveReplayCapture()
        XCTAssertTrue(view.liveReplaySamples.isEmpty, "disabled: nothing is captured")
        XCTAssertEqual(view.liveReplayStartedAtNanos, 0)

        view.liveReplayCaptureEnabled = true
        view.beginLiveReplayCapture()
        XCTAssertEqual(view.liveReplaySamples.count, 1, "arming forces one sample")
        let t = view.backgroundTransform()
        let first = view.liveReplaySamples[0]
        XCTAssertEqual(first.x.bitPattern, ((Float(600) - t.offsetX) / t.scaleX).bitPattern)
        XCTAssertEqual(first.y.bitPattern, ((Float(900) - t.offsetY) / t.scaleY).bitPattern)
        XCTAssertEqual(first.depth, 0)
        view.captureLiveReplaySample(force: false)
        XCTAssertEqual(view.liveReplaySamples.count, 1, "unforced samples keep the 55 ms interval")
        for i in 1..<TripleShotCourtView.LIVE_MAX_REPLAY_SAMPLES {
            view.ballX = Float(600 + i)
            view.captureLiveReplaySample(force: true)
        }
        XCTAssertEqual(view.liveReplaySamples.count, 60)
        view.ballX = 1000
        view.liveReplayLastSampleMs = -1000
        view.captureLiveReplaySample(force: false)
        XCTAssertEqual(view.liveReplaySamples.count, 60, "full: an unforced sample is dropped")
        XCTAssertNotEqual(view.liveReplaySamples[59].x.bitPattern, ((Float(1000) - t.offsetX) / t.scaleX).bitPattern)
        view.captureLiveReplaySample(force: true)
        XCTAssertEqual(view.liveReplaySamples.count, 60)
        XCTAssertEqual(view.liveReplaySamples[59].x.bitPattern, ((Float(1000) - t.offsetX) / t.scaleX).bitPattern,
                       "full: a forced sample replaces the last one")
        view.cancelShotSimulation(callEnd: false)
        XCTAssertTrue(view.liveReplaySamples.isEmpty)
    }

    // MARK: - utilities

    func testDpAndClampedLerp() {
        let view = probe()
        XCTAssertEqual(view.dp(28), 28 * view.density)
        XCTAssertEqual(view.dp(v: 28), view.dp(28))
        XCTAssertEqual(view.lerp(10, 20, 0.5), 15)
        XCTAssertEqual(view.lerp(10, 20, -3), 10, "lerp clamps t")
        XCTAssertEqual(view.lerp(10, 20, 7), 20, "lerp clamps t")
        XCTAssertEqual(view.lerp(a: 1, b: 3, t: 0.5), 2)
    }
}

// MARK: - Golden data (JVM)

private enum CourtPart3Golden {
    // GENERATED by work/w-court3/harness/CourtPart3Golden.kt from the Kotlin sources (dd722e5). Do not edit.
    static let shotSpotCatalog: [(id: String, x: UInt32, y: UInt32, dd: UInt32, zone: String)] = [
        ("L01", 0x435C0000, 0x44660000, 0x3F1C28F6, "left_bush"),
        ("L02", 0x43750000, 0x447B4000, 0x3F000000, "left_bush"),
        ("L03", 0x43870000, 0x4488E000, 0x3ED70A3D, "left_edge"),
        ("L04", 0x43988000, 0x4492E000, 0x3EF5C28F, "court_left"),
        ("L05", 0x43AA0000, 0x44802000, 0x3F000000, "left_edge"),
        ("L06", 0x43B68000, 0x448CA000, 0x3F0CCCCD, "court_left"),
        ("C01", 0x43D20000, 0x44688000, 0x3F28F5C3, "upper_court"),
        ("C02", 0x43E38000, 0x447C8000, 0x3F19999A, "upper_court"),
        ("C03", 0x43EB0000, 0x44898000, 0x3F2147AE, "court_center"),
        ("C04", 0x43FA0000, 0x44956000, 0x3F51EB85, "court_deep"),
        ("C05", 0x440AC000, 0x44728000, 0x3F266666, "upper_court"),
        ("C06", 0x440D4000, 0x4485C000, 0x3F23D70A, "court_center"),
        ("C07", 0x44138000, 0x4491A000, 0x3F451EB8, "court_deep"),
        ("R01", 0x441EC000, 0x44660000, 0x3F30A3D7, "right_upper"),
        ("R02", 0x44214000, 0x447DC000, 0x3F170A3D, "court_right"),
        ("R03", 0x44278000, 0x448A2000, 0x3F1C28F6, "court_right"),
        ("R04", 0x442F0000, 0x44938000, 0x3F333333, "right_edge"),
        ("R05", 0x4437C000, 0x44728000, 0x3F28F5C3, "right_bush"),
        ("R06", 0x443CC000, 0x44852000, 0x3F23D70A, "right_edge"),
        ("R07", 0x44444000, 0x448E8000, 0x3F333333, "right_edge"),
        ("H01", 0x44458000, 0x445C0000, 0x3F428F5C, "right_bush_hard"),
        ("H02", 0x444E4000, 0x446C4000, 0x3F4CCCCD, "near_pole_hard"),
        ("H03", 0x44534000, 0x447DC000, 0x3F51EB85, "behind_board_hard"),
        ("H04", 0x44570000, 0x44884000, 0x3F570A3D, "behind_board_hard"),
        ("H05", 0x445D4000, 0x448E8000, 0x3F6147AE, "behind_board_extreme"),
        ("X01", 0x43A50000, 0x446D8000, 0x3F147AE1, "left_bush"),
        ("X02", 0x43CA8000, 0x44848000, 0x3F147AE1, "court_diag"),
        ("X03", 0x4405C000, 0x4480C000, 0x3F1C28F6, "court_diag"),
        ("X04", 0x441B0000, 0x448CA000, 0x3F333333, "court_diag"),
        ("X05", 0x44340000, 0x447C8000, 0x3F23D70A, "right_diag"),
    ]
    static let practiceSpots: [(id: String, x: UInt32, y: UInt32, dd: UInt32, zone: String)] = [
        ("practice_left", 0x43960000, 0x448CA000, 0x3EAE147B, "court_left"),
        ("practice_deep", 0x43FC8000, 0x4494C000, 0x3F47AE14, "court_deep"),
        ("practice_right", 0x442C8000, 0x4487A000, 0x3F0A3D71, "court_right"),
        ("practice_bush", 0x43898000, 0x446EC000, 0x3F000000, "left_bush"),
    ]
    static let horseSelectableIds: [String] = ["L01", "L02", "L03", "L04", "L05", "L06", "C01", "C02", "C03", "C04", "C05", "C06", "C07", "R01", "R02", "R03", "R04", "R05", "R06", "R07", "H01", "H02", "X01", "X02", "X03", "X04", "X05"]
    static let transforms: [(w: Int, h: Int, landscape: Bool, bits: [UInt32])] = [
        (1080, 2400, false, [0x3FB80000, 0x3FC80000, 0xC3C40000, 0x80000000]),
        (1170, 2532, false, [0x3FC21EB9, 0x3FD30000, 0xC3BF7AE4, 0x80000000]),
        (828, 1792, false, [0x3F8962FC, 0x3F955555, 0xC3878BF0, 0x80000000]),
        (1536, 2048, false, [0x3FC00000, 0x3FD0B216, 0x80000000, 0xC3642C80]),
        (2532, 1170, true, [0x401E4000, 0x3F430000, 0x00000000, 0x00000000]),
        (2048, 1536, true, [0x40000000, 0x3F800000, 0x00000000, 0x00000000]),
    ]
    static let geometries: [(w: Int, h: Int, landscape: Bool, density: Int, bits: [UInt32], aimRange: UInt32, defaultPoint: [UInt32])] = [
        (1080, 2400, false, 2, [0x45640000, 0x442B8800, 0x4404D000, 0x44096400, 0x444DAC00, 0x40FD0000, 0x44531000, 0x43A7F800, 0x441B1400, 0x44454400, 0x441B0000, 0x443AA000, 0x41C80000], 0x433AE000, [0x43AC0000, 0x44E57E00]),
        (1080, 2400, false, 3, [0x45640000, 0x442B8800, 0x4404D000, 0x44096400, 0x444DAC00, 0x40FD0000, 0x44531000, 0x43A7F800, 0x441B1400, 0x44454400, 0x441B0000, 0x443AA000, 0x42160000], 0x433AE000, [0x43AC0000, 0x44E57E00]),
        (1170, 2532, false, 2, [0x45708A3D, 0x443C9D8E, 0x440C1E00, 0x441898DC, 0x4460A242, 0x4105751F, 0x44665228, 0x43B13500, 0x44239B80, 0x44501D80, 0x442B2CCC, 0x444C8A14, 0x41C80000], 0x43452734, [0x43C4C28E, 0x44F21D40]),
        (1170, 2532, false, 3, [0x45708A3D, 0x443C9D8E, 0x440C1E00, 0x441898DC, 0x4460A242, 0x4105751F, 0x44665228, 0x43B13500, 0x44239B80, 0x44501D80, 0x442B2CCC, 0x444C8A14, 0x42160000], 0x43452734, [0x43C4C28E, 0x44F21D40]),
        (828, 1792, false, 2, [0x452A3D70, 0x44057A07, 0x43C65555, 0x43D7F852, 0x441EF7E5, 0x40BCE81A, 0x4422FE4B, 0x437AD555, 0x43E79555, 0x44134AAA, 0x43F24444, 0x4410BF26, 0x41C80000], 0x430B8888, [0x438B3A08, 0x44AB5AAA]),
        (828, 1792, false, 3, [0x452A3D70, 0x44057A07, 0x43C65555, 0x43D7F852, 0x441EF7E5, 0x40F00000, 0x4422FE4B, 0x437AD555, 0x43E79555, 0x44134AAA, 0x43F24444, 0x4410BF26, 0x42160000], 0x430B8888, [0x438B3A08, 0x44AB5AAA]),
        (1536, 2048, false, 2, [0x45428F5C, 0x448CA000, 0x43A31646, 0x4475A000, 0x449E7000, 0x41040000, 0x44A14000, 0x42F4BD40, 0x43D18DEC, 0x4414CC87, 0x44840000, 0x44948000, 0x41C80000], 0x43430000, [0x44400000, 0x44D2F2C9]),
        (1536, 2048, false, 3, [0x45428F5C, 0x448CA000, 0x43A31646, 0x4475A000, 0x449E7000, 0x41040000, 0x44A14000, 0x42F4BD40, 0x43D18DEC, 0x4414CC87, 0x44840000, 0x44948000, 0x42160000], 0x43430000, [0x44400000, 0x44D2F2C9]),
        (2532, 1170, true, 2, [0x44DE4CCD, 0x44E7CFC0, 0x43817E00, 0x44CA72E0, 0x45029650, 0x40A00000, 0x4504E7C0, 0x4323C500, 0x43973380, 0x43C05580, 0x44D99800, 0x44F4CB00, 0x41C80000], 0x43A0B900, [0x449E4000, 0x445FC140]),
        (2532, 1170, true, 3, [0x44DE4CCD, 0x44E7CFC0, 0x43817E00, 0x44CA72E0, 0x45029650, 0x40F00000, 0x4504E7C0, 0x4323C500, 0x43973380, 0x43C05580, 0x44D99800, 0x44F4CB00, 0x42160000], 0x43A0B900, [0x449E4000, 0x445FC140]),
        (2048, 1536, true, 2, [0x4511EB85, 0x44BB8000, 0x43AA0000, 0x44A3C000, 0x44D34000, 0x40B00000, 0x44D70000, 0x43570000, 0x43C68000, 0x43FC8000, 0x44B00000, 0x44C60000, 0x41C80000], 0x43820000, [0x44800000, 0x4492E000]),
        (2048, 1536, true, 3, [0x4511EB85, 0x44BB8000, 0x43AA0000, 0x44A3C000, 0x44D34000, 0x40F00000, 0x44D70000, 0x43570000, 0x43C68000, 0x43FC8000, 0x44B00000, 0x44C60000, 0x42160000], 0x43820000, [0x44800000, 0x4492E000]),
    ]
    static let fallbackStationPoints: [(w: Int, h: Int, landscape: Bool, density: Int, boundary: UInt32?, bits: [UInt32])] = [
        (1080, 2400, false, 2, nil, [0x42734000, 0x44DDAE00, 0x44079800, 0x44D3EA00, 0x42600000, 0x44D8CC00, 0x43A6F800, 0x44E86C00, 0x441D2800, 0x44CC1A00, 0x42600000, 0x44CC1A00, 0x431A4000, 0x44E67800, 0x43CE8000, 0x44D8CC00, 0x442F2000, 0x44C44A00]),
        (1080, 2400, false, 2, 0x45010000, [0x42734000, 0x44DDAE00, 0x44079800, 0x44D3EA00, 0x42600000, 0x44D8CC00, 0x43A6F800, 0x44E86C00, 0x441D2800, 0x44CC1A00, 0x42600000, 0x44CC1A00, 0x431A4000, 0x44E67800, 0x43CE8000, 0x44D8CC00, 0x442F2000, 0x44C44A00]),
        (1080, 2400, false, 2, 0x44700000, [0x42734000, 0x44904000, 0x44079800, 0x44904000, 0x42600000, 0x44904000, 0x43A6F800, 0x44904000, 0x441D2800, 0x44904000, 0x42600000, 0x44904000, 0x431A4000, 0x44904000, 0x43CE8000, 0x44904000, 0x442F2000, 0x44904000]),
        (1080, 2400, false, 3, nil, [0x42A80000, 0x44DDAE00, 0x44079800, 0x44D3EA00, 0x42A80000, 0x44D8CC00, 0x43A6F800, 0x44E86C00, 0x441D2800, 0x44CC1A00, 0x42A80000, 0x44CC1A00, 0x431A4000, 0x44E67800, 0x43CE8000, 0x44D8CC00, 0x442F2000, 0x44C44A00]),
        (1080, 2400, false, 3, 0x45010000, [0x42A80000, 0x44DDAE00, 0x44079800, 0x44D3EA00, 0x42A80000, 0x44D8CC00, 0x43A6F800, 0x44E86C00, 0x441D2800, 0x44CC1A00, 0x42A80000, 0x44CC1A00, 0x431A4000, 0x44E67800, 0x43CE8000, 0x44D8CC00, 0x442F2000, 0x44C44A00]),
        (1080, 2400, false, 3, 0x44700000, [0x42A80000, 0x44906000, 0x44079800, 0x44906000, 0x42A80000, 0x44906000, 0x43A6F800, 0x44906000, 0x441D2800, 0x44906000, 0x42A80000, 0x44906000, 0x431A4000, 0x44906000, 0x43CE8000, 0x44906000, 0x442F2000, 0x44906000]),
        (1170, 2532, false, 2, nil, [0x42BD83A8, 0x44E9DF40, 0x4416B38F, 0x44DF91C0, 0x42600000, 0x44E4B880, 0x43BF73B6, 0x44F53480, 0x442D7328, 0x44D753C0, 0x42600000, 0x44D753C0, 0x4341556C, 0x44F32500, 0x43E92850, 0x44E4B880, 0x44406828, 0x44CF15C0]),
        (1170, 2532, false, 2, 0x45081852, [0x42BD83A8, 0x44E9DF40, 0x4416B38F, 0x44DF91C0, 0x42600000, 0x44E4B880, 0x43BF73B6, 0x44F53480, 0x442D7328, 0x44D753C0, 0x42600000, 0x44D753C0, 0x4341556C, 0x44F32500, 0x43E92850, 0x44E4B880, 0x44406828, 0x44CF15C0]),
        (1170, 2532, false, 2, 0x447D3333, [0x42BD83A8, 0x44982B85, 0x4416B38F, 0x44982B85, 0x42600000, 0x44982B85, 0x43BF73B6, 0x44982B85, 0x442D7328, 0x44982B85, 0x42600000, 0x44982B85, 0x4341556C, 0x44982B85, 0x43E92850, 0x44982B85, 0x44406828, 0x44982B85]),
        (1170, 2532, false, 3, nil, [0x42BD83A8, 0x44E9DF40, 0x4416B38F, 0x44DF91C0, 0x42A80000, 0x44E4B880, 0x43BF73B6, 0x44F53480, 0x442D7328, 0x44D753C0, 0x42A80000, 0x44D753C0, 0x4341556C, 0x44F32500, 0x43E92850, 0x44E4B880, 0x44406828, 0x44CF15C0]),
        (1170, 2532, false, 3, 0x45081852, [0x42BD83A8, 0x44E9DF40, 0x4416B38F, 0x44DF91C0, 0x42A80000, 0x44E4B880, 0x43BF73B6, 0x44F53480, 0x442D7328, 0x44D753C0, 0x42A80000, 0x44D753C0, 0x4341556C, 0x44F32500, 0x43E92850, 0x44E4B880, 0x44406828, 0x44CF15C0]),
        (1170, 2532, false, 3, 0x447D3333, [0x42BD83A8, 0x44984B85, 0x4416B38F, 0x44984B85, 0x42A80000, 0x44984B85, 0x43BF73B6, 0x44984B85, 0x442D7328, 0x44984B85, 0x42A80000, 0x44984B85, 0x4341556C, 0x44984B85, 0x43E92850, 0x44984B85, 0x44406828, 0x44984B85]),
        (828, 1792, false, 2, nil, [0x42860370, 0x44A58555, 0x43D54964, 0x449E3AAA, 0x42600000, 0x44A1E000, 0x43877854, 0x44AD8AAA, 0x43F57C96, 0x44986555, 0x42600000, 0x44986555, 0x4308C5FC, 0x44AC1555, 0x43A4FC98, 0x44A1E000, 0x440828F6, 0x44929000]),
        (828, 1792, false, 2, 0x44C0A3D7, [0x42860370, 0x44A58555, 0x43D54964, 0x449E3AAA, 0x42600000, 0x44A1E000, 0x43877854, 0x44AD8AAA, 0x43F57C96, 0x44986555, 0x42600000, 0x44986555, 0x4308C5FC, 0x44AC1555, 0x43A4FC98, 0x44A1E000, 0x440828F6, 0x44929000]),
        (828, 1792, false, 2, 0x44333333, [0x42860370, 0x44578A3D, 0x43D54964, 0x44578A3D, 0x42600000, 0x44578A3D, 0x43877854, 0x44578A3D, 0x43F57C96, 0x44578A3D, 0x42600000, 0x44578A3D, 0x4308C5FC, 0x44578A3D, 0x43A4FC98, 0x44578A3D, 0x440828F6, 0x44578A3D]),
        (828, 1792, false, 3, nil, [0x42A80000, 0x44A58555, 0x43D54964, 0x449E3AAA, 0x42A80000, 0x44A1E000, 0x43877854, 0x44AD8AAA, 0x43F57C96, 0x44986555, 0x42A80000, 0x44986555, 0x4308C5FC, 0x44AC1555, 0x43A4FC98, 0x44A1E000, 0x440828F6, 0x44929000]),
        (828, 1792, false, 3, 0x44C0A3D7, [0x42A80000, 0x44A58555, 0x43D54964, 0x449E3AAA, 0x42A80000, 0x44A1E000, 0x43877854, 0x44AD8AAA, 0x43F57C96, 0x44986555, 0x42A80000, 0x44986555, 0x4308C5FC, 0x44AC1555, 0x43A4FC98, 0x44A1E000, 0x440828F6, 0x44929000]),
        (828, 1792, false, 3, 0x44333333, [0x42A80000, 0x4457CA3D, 0x43D54964, 0x4457CA3D, 0x42A80000, 0x4457CA3D, 0x43877854, 0x4457CA3D, 0x43F57C96, 0x4457CA3D, 0x42A80000, 0x4457CA3D, 0x4308C5FC, 0x4457CA3D, 0x43A4FC98, 0x4457CA3D, 0x440828F6, 0x4457CA3D]),
        (1536, 2048, false, 2, nil, [0x43EC4000, 0x44CACBD4, 0x4473C000, 0x44C09B22, 0x43B40000, 0x44C5B37B, 0x443D6000, 0x44D60165, 0x44852000, 0x44B8742D, 0x4399C000, 0x44B8742D, 0x440E8000, 0x44D3F7A7, 0x44520000, 0x44C5B37B, 0x448E8000, 0x44B04D38]),
        (1536, 2048, false, 2, 0x44DC28F6, [0x43EC4000, 0x44CACBD4, 0x4473C000, 0x44C09B22, 0x43B40000, 0x44C5B37B, 0x443D6000, 0x44D528F6, 0x44852000, 0x44B8742D, 0x4399C000, 0x44B8742D, 0x440E8000, 0x44D3F7A7, 0x44520000, 0x44C5B37B, 0x448E8000, 0x44B04D38]),
        (1536, 2048, false, 2, 0x444CCCCD, [0x43EC4000, 0x4476428F, 0x4473C000, 0x4476428F, 0x43B40000, 0x4476428F, 0x443D6000, 0x4476428F, 0x44852000, 0x4476428F, 0x4399C000, 0x4476428F, 0x440E8000, 0x4476428F, 0x44520000, 0x4476428F, 0x448E8000, 0x4476428F]),
        (1536, 2048, false, 3, nil, [0x43EC4000, 0x44CACBD4, 0x4473C000, 0x44C09B22, 0x43B40000, 0x44C5B37B, 0x443D6000, 0x44D60165, 0x44852000, 0x44B8742D, 0x4399C000, 0x44B8742D, 0x440E8000, 0x44D3F7A7, 0x44520000, 0x44C5B37B, 0x448E8000, 0x44B04D38]),
        (1536, 2048, false, 3, 0x44DC28F6, [0x43EC4000, 0x44CACBD4, 0x4473C000, 0x44C09B22, 0x43B40000, 0x44C5B37B, 0x443D6000, 0x44D1A8F6, 0x44852000, 0x44B8742D, 0x4399C000, 0x44B8742D, 0x440E8000, 0x44D1A8F6, 0x44520000, 0x44C5B37B, 0x448E8000, 0x44B04D38]),
        (1536, 2048, false, 3, 0x444CCCCD, [0x43EC4000, 0x4476828F, 0x4473C000, 0x4476828F, 0x43B40000, 0x4476828F, 0x443D6000, 0x4476828F, 0x44852000, 0x4476828F, 0x4399C000, 0x4476828F, 0x440E8000, 0x4476828F, 0x44520000, 0x4476828F, 0x448E8000, 0x4476828F]),
        (2532, 1170, true, 2, nil, [0x4442B8C0, 0x44582340, 0x44C8E740, 0x444E9DC0, 0x44145C00, 0x44536080, 0x449C1620, 0x44629C80, 0x44DB72C0, 0x4446FFC0, 0x43FD7280, 0x4446FFC0, 0x446AE700, 0x4460B500, 0x44AD1600, 0x44536080, 0x44EAE700, 0x443F61C0]),
        (2532, 1170, true, 2, 0x447B8CCD, [0x4442B8C0, 0x44582340, 0x44C8E740, 0x444E9DC0, 0x44145C00, 0x44536080, 0x449C1620, 0x44629C80, 0x44DB72C0, 0x4446FFC0, 0x43FD7280, 0x4446FFC0, 0x446AE700, 0x4460B500, 0x44AD1600, 0x44536080, 0x44EAE700, 0x443F61C0]),
        (2532, 1170, true, 2, 0x43EA0000, [0x4442B8C0, 0x440CE666, 0x44C8E740, 0x440CE666, 0x44145C00, 0x440CE666, 0x449C1620, 0x440CE666, 0x44DB72C0, 0x440CE666, 0x43FD7280, 0x440CE666, 0x446AE700, 0x440CE666, 0x44AD1600, 0x440CE666, 0x44EAE700, 0x440CE666]),
        (2532, 1170, true, 3, nil, [0x4442B8C0, 0x44582340, 0x44C8E740, 0x444E9DC0, 0x44145C00, 0x44536080, 0x449C1620, 0x44629C80, 0x44DB72C0, 0x4446FFC0, 0x43FD7280, 0x4446FFC0, 0x446AE700, 0x4460B500, 0x44AD1600, 0x44536080, 0x44EAE700, 0x443F61C0]),
        (2532, 1170, true, 3, 0x447B8CCD, [0x4442B8C0, 0x44582340, 0x44C8E740, 0x444E9DC0, 0x44145C00, 0x44536080, 0x449C1620, 0x44629C80, 0x44DB72C0, 0x4446FFC0, 0x43FD7280, 0x4446FFC0, 0x446AE700, 0x4460B500, 0x44AD1600, 0x44536080, 0x44EAE700, 0x443F61C0]),
        (2532, 1170, true, 3, 0x43EA0000, [0x4442B8C0, 0x440D2666, 0x44C8E740, 0x440D2666, 0x44145C00, 0x440D2666, 0x449C1620, 0x440D2666, 0x44DB72C0, 0x440D2666, 0x43FD7280, 0x440D2666, 0x446AE700, 0x440D2666, 0x44AD1600, 0x440D2666, 0x44EAE700, 0x440D2666]),
        (2048, 1536, true, 2, nil, [0x441D8000, 0x448DE000, 0x44A28000, 0x4487A000, 0x43F00000, 0x448AC000, 0x447C8000, 0x4494C000, 0x44B18000, 0x4482A000, 0x43CD0000, 0x4482A000, 0x443E0000, 0x44938000, 0x448C0000, 0x448AC000, 0x44BE0000, 0x447B4000]),
        (2048, 1536, true, 2, 0x44A51EB8, [0x441D8000, 0x448DE000, 0x44A28000, 0x4487A000, 0x43F00000, 0x448AC000, 0x447C8000, 0x4494C000, 0x44B18000, 0x4482A000, 0x43CD0000, 0x4482A000, 0x443E0000, 0x44938000, 0x448C0000, 0x448AC000, 0x44BE0000, 0x447B4000]),
        (2048, 1536, true, 2, 0x4419999A, [0x441D8000, 0x4438D1EB, 0x44A28000, 0x4438D1EB, 0x43F00000, 0x4438D1EB, 0x447C8000, 0x4438D1EB, 0x44B18000, 0x4438D1EB, 0x43CD0000, 0x4438D1EB, 0x443E0000, 0x4438D1EB, 0x448C0000, 0x4438D1EB, 0x44BE0000, 0x4438D1EB]),
        (2048, 1536, true, 3, nil, [0x441D8000, 0x448DE000, 0x44A28000, 0x4487A000, 0x43F00000, 0x448AC000, 0x447C8000, 0x4494C000, 0x44B18000, 0x4482A000, 0x43CD0000, 0x4482A000, 0x443E0000, 0x44938000, 0x448C0000, 0x448AC000, 0x44BE0000, 0x447B4000]),
        (2048, 1536, true, 3, 0x44A51EB8, [0x441D8000, 0x448DE000, 0x44A28000, 0x4487A000, 0x43F00000, 0x448AC000, 0x447C8000, 0x4494C000, 0x44B18000, 0x4482A000, 0x43CD0000, 0x4482A000, 0x443E0000, 0x44938000, 0x448C0000, 0x448AC000, 0x44BE0000, 0x447B4000]),
        (2048, 1536, true, 3, 0x4419999A, [0x441D8000, 0x443911EB, 0x44A28000, 0x443911EB, 0x43F00000, 0x443911EB, 0x447C8000, 0x443911EB, 0x44B18000, 0x443911EB, 0x43CD0000, 0x443911EB, 0x443E0000, 0x443911EB, 0x448C0000, 0x443911EB, 0x44BE0000, 0x443911EB]),
    ]
    static let catalogBotPoints: [(w: Int, h: Int, landscape: Bool, density: Int, bits: [UInt32])] = [
        (1080, 2400, false, 2, [0x42600000, 0x44B3B000, 0x42600000, 0x44C44A00, 0x42600000, 0x44D5DE00, 0x42600000, 0x44E57E00, 0x42C18000, 0x44C83200, 0x4304B000, 0x44DBBA00, 0x4353C000, 0x44B5A400, 0x43830800, 0x44C54400, 0x438DD000, 0x44D6D800, 0x43A36000, 0x44E96600, 0x43CAE800, 0x44BD7400, 0x43D21800, 0x44D0FC00, 0x43E41000, 0x44E38A00, 0x44023400, 0x44B3B000, 0x4405CC00, 0x44C63E00, 0x440EC800, 0x44D7D200, 0x44199000, 0x44E67800, 0x44262400, 0x44BD7400, 0x442D5400, 0x44D00200, 0x44381C00, 0x44DEA800, 0x4439E800, 0x44ABE000, 0x44467C00, 0x44B89200, 0x444DAC00, 0x44C63E00, 0x44531000, 0x44D4E400, 0x445C0C00, 0x44DEA800, 0x42A4C000, 0x44B98C00, 0x433E3000, 0x44CF0800, 0x43BC8800, 0x44C92C00, 0x43F9A000, 0x44DBBA00, 0x4420C000, 0x44C54400]),
        (1080, 2400, false, 3, [0x42A80000, 0x44B3B000, 0x42A80000, 0x44C44A00, 0x42A80000, 0x44D5DE00, 0x42A80000, 0x44E57E00, 0x42C18000, 0x44C83200, 0x4304B000, 0x44DBBA00, 0x4353C000, 0x44B5A400, 0x43830800, 0x44C54400, 0x438DD000, 0x44D6D800, 0x43A36000, 0x44E96600, 0x43CAE800, 0x44BD7400, 0x43D21800, 0x44D0FC00, 0x43E41000, 0x44E38A00, 0x44023400, 0x44B3B000, 0x4405CC00, 0x44C63E00, 0x440EC800, 0x44D7D200, 0x44199000, 0x44E67800, 0x44262400, 0x44BD7400, 0x442D5400, 0x44D00200, 0x44381C00, 0x44DEA800, 0x4439E800, 0x44ABE000, 0x44467C00, 0x44B89200, 0x444DAC00, 0x44C63E00, 0x44531000, 0x44D4E400, 0x445C0C00, 0x44DEA800, 0x42A80000, 0x44B98C00, 0x433E3000, 0x44CF0800, 0x43BC8800, 0x44C92C00, 0x43F9A000, 0x44DBBA00, 0x4420C000, 0x44C54400]),
        (1170, 2532, false, 2, [0x42600000, 0x44BD9200, 0x42600000, 0x44CF15C0, 0x42600000, 0x44E1A140, 0x429F2ED8, 0x44F21D40, 0x4304ABD4, 0x44D334C0, 0x432A95D4, 0x44E7CFC0, 0x437DFF08, 0x44BFA180, 0x439989B6, 0x44D01D80, 0x43A4E984, 0x44E2A900, 0x43BBA91E, 0x44F63C40, 0x43E55DB8, 0x44C7DF80, 0x43ECF2EA, 0x44DC7A80, 0x43FFE7EA, 0x44F00DC0, 0x441103A8, 0x44BD9200, 0x4414CE42, 0x44D12540, 0x441E48C2, 0x44E3B0C0, 0x4429A88E, 0x44F32500, 0x4436EDA8, 0x44C7DF80, 0x443E82DC, 0x44DB72C0, 0x4449E2A8, 0x44EAE700, 0x444BC7F6, 0x44B55400, 0x44590D10, 0x44C2B8C0, 0x4460A242, 0x44D12540, 0x44665228, 0x44E09980, 0x446FCCA8, 0x44EAE700, 0x42EB02D8, 0x44C3C080, 0x43673F6C, 0x44DA6B00, 0x43D63350, 0x44D43C80, 0x440B53C2, 0x44E7CFC0, 0x44313DC2, 0x44D01D80]),
        (1170, 2532, false, 3, [0x42A80000, 0x44BD9200, 0x42A80000, 0x44CF15C0, 0x42A80000, 0x44E1A140, 0x42A80000, 0x44F21D40, 0x4304ABD4, 0x44D334C0, 0x432A95D4, 0x44E7CFC0, 0x437DFF08, 0x44BFA180, 0x439989B6, 0x44D01D80, 0x43A4E984, 0x44E2A900, 0x43BBA91E, 0x44F63C40, 0x43E55DB8, 0x44C7DF80, 0x43ECF2EA, 0x44DC7A80, 0x43FFE7EA, 0x44F00DC0, 0x441103A8, 0x44BD9200, 0x4414CE42, 0x44D12540, 0x441E48C2, 0x44E3B0C0, 0x4429A88E, 0x44F32500, 0x4436EDA8, 0x44C7DF80, 0x443E82DC, 0x44DB72C0, 0x4449E2A8, 0x44EAE700, 0x444BC7F6, 0x44B55400, 0x44590D10, 0x44C2B8C0, 0x4460A242, 0x44D12540, 0x44665228, 0x44E09980, 0x446FCCA8, 0x44EAE700, 0x42EB02D8, 0x44C3C080, 0x43673F6C, 0x44DA6B00, 0x43D63350, 0x44D43C80, 0x440B53C2, 0x44E7CFC0, 0x44313DC2, 0x44D01D80]),
        (828, 1792, false, 2, [0x42600000, 0x44862AAA, 0x42600000, 0x44929000, 0x42600000, 0x449FB000, 0x426117F0, 0x44AB5AAA, 0x42BBAE1C, 0x44957AAA, 0x42F158C4, 0x44A41000, 0x4333B4EA, 0x4487A000, 0x435945FC, 0x44934AAA, 0x43695F96, 0x44A06AAA, 0x4384C964, 0x44AE4555, 0x43A24DA8, 0x448D7555, 0x43A7AB86, 0x449C0AAA, 0x43B51630, 0x44A9E555, 0x43CD3C98, 0x44862AAA, 0x43D29A74, 0x44940555, 0x43E00520, 0x44A12555, 0x43F01EBA, 0x44AC1555, 0x440173A1, 0x448D7555, 0x4406D17F, 0x449B5000, 0x440EDE4B, 0x44A64000, 0x441035C3, 0x44805555, 0x44199A07, 0x4489D000, 0x441EF7E5, 0x44940555, 0x4422FE4B, 0x449EF555, 0x4429B3A1, 0x44A64000, 0x42A636A4, 0x448A8AAA, 0x43239B52, 0x449A9555, 0x439791EC, 0x44963555, 0x43C52FCA, 0x44A41000, 0x43FADA74, 0x44934AAA]),
        (828, 1792, false, 3, [0x42A80000, 0x44862AAA, 0x42A80000, 0x44929000, 0x42A80000, 0x449FB000, 0x42A80000, 0x44AB5AAA, 0x42BBAE1C, 0x44957AAA, 0x42F158C4, 0x44A41000, 0x4333B4EA, 0x4487A000, 0x435945FC, 0x44934AAA, 0x43695F96, 0x44A06AAA, 0x4384C964, 0x44AE4555, 0x43A24DA8, 0x448D7555, 0x43A7AB86, 0x449C0AAA, 0x43B51630, 0x44A9E555, 0x43CD3C98, 0x44862AAA, 0x43D29A74, 0x44940555, 0x43E00520, 0x44A12555, 0x43F01EBA, 0x44AC1555, 0x440173A1, 0x448D7555, 0x4406D17F, 0x449B5000, 0x440EDE4B, 0x44A64000, 0x441035C3, 0x44805555, 0x44199A07, 0x4489D000, 0x441EF7E5, 0x44940555, 0x4422FE4B, 0x449EF555, 0x4429B3A1, 0x44A64000, 0x42A80000, 0x448A8AAA, 0x43239B52, 0x449A9555, 0x439791EC, 0x44963555, 0x43C52FCA, 0x44A41000, 0x43FADA74, 0x44934AAA]),
        (1536, 2048, false, 2, [0x43A50000, 0x449EFA70, 0x43B7C000, 0x44B04D38, 0x43CA8000, 0x44C2A4DF, 0x43E4C000, 0x44D2F2C9, 0x43FF0000, 0x44B460B3, 0x4408E000, 0x44C8C217, 0x441D8000, 0x44A1042D, 0x442AA000, 0x44B15217, 0x44304000, 0x44C3A9BE, 0x443B8000, 0x44D70643, 0x44502000, 0x44A92B22, 0x4453E000, 0x44BD8C86, 0x445D4000, 0x44D0E90C, 0x446E2000, 0x449EFA70, 0x4471E000, 0x44B256F5, 0x447B4000, 0x44C4AE9C, 0x44834000, 0x44D3F7A7, 0x4489D000, 0x44A92B22, 0x448D9000, 0x44BC87A7, 0x44933000, 0x44CBD0B2, 0x44942000, 0x4496D37B, 0x449AB000, 0x44A412C9, 0x449E7000, 0x44B256F5, 0x44A14000, 0x44C1A000, 0x44A5F000, 0x44CBD0B2, 0x43F78000, 0x44A517A7, 0x4417E000, 0x44BB82C9, 0x4448A000, 0x44B56591, 0x44688000, 0x44C8C217, 0x44870000, 0x44B15217]),
        (1536, 2048, false, 3, [0x43A50000, 0x449EFA70, 0x43B7C000, 0x44B04D38, 0x43CA8000, 0x44C2A4DF, 0x43E4C000, 0x44D2F2C9, 0x43FF0000, 0x44B460B3, 0x4408E000, 0x44C8C217, 0x441D8000, 0x44A1042D, 0x442AA000, 0x44B15217, 0x44304000, 0x44C3A9BE, 0x443B8000, 0x44D70643, 0x44502000, 0x44A92B22, 0x4453E000, 0x44BD8C86, 0x445D4000, 0x44D0E90C, 0x446E2000, 0x449EFA70, 0x4471E000, 0x44B256F5, 0x447B4000, 0x44C4AE9C, 0x44834000, 0x44D3F7A7, 0x4489D000, 0x44A92B22, 0x448D9000, 0x44BC87A7, 0x44933000, 0x44CBD0B2, 0x44942000, 0x4496D37B, 0x449AB000, 0x44A412C9, 0x449E7000, 0x44B256F5, 0x44A14000, 0x44C1A000, 0x44A5F000, 0x44CBD0B2, 0x43F78000, 0x44A517A7, 0x4417E000, 0x44BB82C9, 0x4448A000, 0x44B56591, 0x44688000, 0x44C8C217, 0x44870000, 0x44B15217]),
        (2532, 1170, true, 2, [0x4407FF00, 0x442F3200, 0x44177340, 0x443F61C0, 0x4426E780, 0x44508540, 0x443C8A40, 0x445FC140, 0x44522D00, 0x444330C0, 0x4461A140, 0x44563BC0, 0x4481D080, 0x44311980, 0x448CA1E0, 0x44405580, 0x449144C0, 0x44517900, 0x449A8A80, 0x44639040, 0x44AB8A60, 0x4438B780, 0x44AEA1A0, 0x444BC280, 0x44B65BC0, 0x445DD9C0, 0x44C44460, 0x442F3200, 0x44C75BA0, 0x44414940, 0x44CF15C0, 0x44526CC0, 0x44D85B80, 0x4460B500, 0x44E32CE0, 0x4438B780, 0x44E95B60, 0x444ACEC0, 0x44F2A120, 0x44591700, 0x44F42CC0, 0x44279400, 0x44FEFE20, 0x4433F4C0, 0x45029650, 0x44414940, 0x4504E7C0, 0x444F9180, 0x4508C4D0, 0x44591700, 0x444BFE80, 0x4434E880, 0x447A5B40, 0x4449DB00, 0x44A55BE0, 0x44442480, 0x44BFA180, 0x44563BC0, 0x44DE8A00, 0x44405580]),
        (2532, 1170, true, 3, [0x4407FF00, 0x442F3200, 0x44177340, 0x443F61C0, 0x4426E780, 0x44508540, 0x443C8A40, 0x445FC140, 0x44522D00, 0x444330C0, 0x4461A140, 0x44563BC0, 0x4481D080, 0x44311980, 0x448CA1E0, 0x44405580, 0x449144C0, 0x44517900, 0x449A8A80, 0x44639040, 0x44AB8A60, 0x4438B780, 0x44AEA1A0, 0x444BC280, 0x44B65BC0, 0x445DD9C0, 0x44C44460, 0x442F3200, 0x44C75BA0, 0x44414940, 0x44CF15C0, 0x44526CC0, 0x44D85B80, 0x4460B500, 0x44E32CE0, 0x4438B780, 0x44E95B60, 0x444ACEC0, 0x44F2A120, 0x44591700, 0x44F42CC0, 0x44279400, 0x44FEFE20, 0x4433F4C0, 0x45029650, 0x44414940, 0x4504E7C0, 0x444F9180, 0x4508C4D0, 0x44591700, 0x444BFE80, 0x4434E880, 0x447A5B40, 0x4449DB00, 0x44A55BE0, 0x44442480, 0x44BFA180, 0x44563BC0, 0x44DE8A00, 0x44405580]),
        (2048, 1536, true, 2, [0x43DC0000, 0x44660000, 0x43F50000, 0x447B4000, 0x44070000, 0x4488E000, 0x44188000, 0x4492E000, 0x442A0000, 0x44802000, 0x44368000, 0x448CA000, 0x44520000, 0x44688000, 0x44638000, 0x447C8000, 0x446B0000, 0x44898000, 0x447A0000, 0x44956000, 0x448AC000, 0x44728000, 0x448D4000, 0x4485C000, 0x44938000, 0x4491A000, 0x449EC000, 0x44660000, 0x44A14000, 0x447DC000, 0x44A78000, 0x448A2000, 0x44AF0000, 0x44938000, 0x44B7C000, 0x44728000, 0x44BCC000, 0x44852000, 0x44C44000, 0x448E8000, 0x44C58000, 0x445C0000, 0x44CE4000, 0x446C4000, 0x44D34000, 0x447DC000, 0x44D70000, 0x44884000, 0x44DD4000, 0x448E8000, 0x44250000, 0x446D8000, 0x444A8000, 0x44848000, 0x4485C000, 0x4480C000, 0x449B0000, 0x448CA000, 0x44B40000, 0x447C8000]),
        (2048, 1536, true, 3, [0x43DC0000, 0x44660000, 0x43F50000, 0x447B4000, 0x44070000, 0x4488E000, 0x44188000, 0x4492E000, 0x442A0000, 0x44802000, 0x44368000, 0x448CA000, 0x44520000, 0x44688000, 0x44638000, 0x447C8000, 0x446B0000, 0x44898000, 0x447A0000, 0x44956000, 0x448AC000, 0x44728000, 0x448D4000, 0x4485C000, 0x44938000, 0x4491A000, 0x449EC000, 0x44660000, 0x44A14000, 0x447DC000, 0x44A78000, 0x448A2000, 0x44AF0000, 0x44938000, 0x44B7C000, 0x44728000, 0x44BCC000, 0x44852000, 0x44C44000, 0x448E8000, 0x44C58000, 0x445C0000, 0x44CE4000, 0x446C4000, 0x44D34000, 0x447DC000, 0x44D70000, 0x44884000, 0x44DD4000, 0x448E8000, 0x44250000, 0x446D8000, 0x444A8000, 0x44848000, 0x4485C000, 0x4480C000, 0x449B0000, 0x448CA000, 0x44B40000, 0x447C8000]),
    ]
    static let botStationRecent: [String] = ["L03", "C03", "R05", "X02", "H02"]
    static let botStationChoices: [(w: Int, h: Int, landscape: Bool, density: Int, scenario: Int, seed: Int64, id: String)] = [
        (1080, 2400, false, 2, 0, 0, "R06"),
        (1080, 2400, false, 2, 0, 1, "C05"),
        (1080, 2400, false, 2, 0, 42, "C05"),
        (1080, 2400, false, 2, 0, 2024, "L01"),
        (1080, 2400, false, 2, 0, -1, "X01"),
        (1080, 2400, false, 2, 0, -5, "L02"),
        (1080, 2400, false, 2, 0, 123456789, "R04"),
        (1080, 2400, false, 2, 0, 99999999999, "X02"),
        (1080, 2400, false, 2, 1, 0, "R06"),
        (1080, 2400, false, 2, 1, 1, "C05"),
        (1080, 2400, false, 2, 1, 42, "C05"),
        (1080, 2400, false, 2, 1, 2024, "L01"),
        (1080, 2400, false, 2, 1, -1, "X01"),
        (1080, 2400, false, 2, 1, -5, "L02"),
        (1080, 2400, false, 2, 1, 123456789, "R04"),
        (1080, 2400, false, 2, 1, 99999999999, "C02"),
        (1080, 2400, false, 3, 0, 0, "R06"),
        (1080, 2400, false, 3, 0, 1, "C05"),
        (1080, 2400, false, 3, 0, 42, "C05"),
        (1080, 2400, false, 3, 0, 2024, "L01"),
        (1080, 2400, false, 3, 0, -1, "X01"),
        (1080, 2400, false, 3, 0, -5, "L02"),
        (1080, 2400, false, 3, 0, 123456789, "R04"),
        (1080, 2400, false, 3, 0, 99999999999, "C02"),
        (1080, 2400, false, 3, 1, 0, "R06"),
        (1080, 2400, false, 3, 1, 1, "C05"),
        (1080, 2400, false, 3, 1, 42, "C05"),
        (1080, 2400, false, 3, 1, 2024, "L01"),
        (1080, 2400, false, 3, 1, -1, "X01"),
        (1080, 2400, false, 3, 1, -5, "L02"),
        (1080, 2400, false, 3, 1, 123456789, "R04"),
        (1080, 2400, false, 3, 1, 99999999999, "C02"),
        (1170, 2532, false, 2, 0, 0, "R06"),
        (1170, 2532, false, 2, 0, 1, "C05"),
        (1170, 2532, false, 2, 0, 42, "C05"),
        (1170, 2532, false, 2, 0, 2024, "L01"),
        (1170, 2532, false, 2, 0, -1, "X01"),
        (1170, 2532, false, 2, 0, -5, "L02"),
        (1170, 2532, false, 2, 0, 123456789, "R04"),
        (1170, 2532, false, 2, 0, 99999999999, "X02"),
        (1170, 2532, false, 2, 1, 0, "R06"),
        (1170, 2532, false, 2, 1, 1, "C05"),
        (1170, 2532, false, 2, 1, 42, "C05"),
        (1170, 2532, false, 2, 1, 2024, "L01"),
        (1170, 2532, false, 2, 1, -1, "X01"),
        (1170, 2532, false, 2, 1, -5, "L02"),
        (1170, 2532, false, 2, 1, 123456789, "R04"),
        (1170, 2532, false, 2, 1, 99999999999, "C02"),
        (1170, 2532, false, 3, 0, 0, "R06"),
        (1170, 2532, false, 3, 0, 1, "C05"),
        (1170, 2532, false, 3, 0, 42, "C05"),
        (1170, 2532, false, 3, 0, 2024, "L01"),
        (1170, 2532, false, 3, 0, -1, "X01"),
        (1170, 2532, false, 3, 0, -5, "L02"),
        (1170, 2532, false, 3, 0, 123456789, "R04"),
        (1170, 2532, false, 3, 0, 99999999999, "X02"),
        (1170, 2532, false, 3, 1, 0, "R06"),
        (1170, 2532, false, 3, 1, 1, "C05"),
        (1170, 2532, false, 3, 1, 42, "C05"),
        (1170, 2532, false, 3, 1, 2024, "L01"),
        (1170, 2532, false, 3, 1, -1, "X01"),
        (1170, 2532, false, 3, 1, -5, "L02"),
        (1170, 2532, false, 3, 1, 123456789, "R04"),
        (1170, 2532, false, 3, 1, 99999999999, "C02"),
        (828, 1792, false, 2, 0, 0, "R06"),
        (828, 1792, false, 2, 0, 1, "C05"),
        (828, 1792, false, 2, 0, 42, "C05"),
        (828, 1792, false, 2, 0, 2024, "L01"),
        (828, 1792, false, 2, 0, -1, "X01"),
        (828, 1792, false, 2, 0, -5, "L02"),
        (828, 1792, false, 2, 0, 123456789, "R04"),
        (828, 1792, false, 2, 0, 99999999999, "X02"),
        (828, 1792, false, 2, 1, 0, "R06"),
        (828, 1792, false, 2, 1, 1, "C05"),
        (828, 1792, false, 2, 1, 42, "C05"),
        (828, 1792, false, 2, 1, 2024, "L01"),
        (828, 1792, false, 2, 1, -1, "X01"),
        (828, 1792, false, 2, 1, -5, "L02"),
        (828, 1792, false, 2, 1, 123456789, "R04"),
        (828, 1792, false, 2, 1, 99999999999, "C02"),
        (828, 1792, false, 3, 0, 0, "R06"),
        (828, 1792, false, 3, 0, 1, "L01"),
        (828, 1792, false, 3, 0, 42, "R06"),
        (828, 1792, false, 3, 0, 2024, "L01"),
        (828, 1792, false, 3, 0, -1, "X01"),
        (828, 1792, false, 3, 0, -5, "L02"),
        (828, 1792, false, 3, 0, 123456789, "R01"),
        (828, 1792, false, 3, 0, 99999999999, "X05"),
        (828, 1792, false, 3, 1, 0, "R06"),
        (828, 1792, false, 3, 1, 1, "L01"),
        (828, 1792, false, 3, 1, 42, "R06"),
        (828, 1792, false, 3, 1, 2024, "L01"),
        (828, 1792, false, 3, 1, -1, "X01"),
        (828, 1792, false, 3, 1, -5, "L02"),
        (828, 1792, false, 3, 1, 123456789, "R01"),
        (828, 1792, false, 3, 1, 99999999999, "X05"),
        (1536, 2048, false, 2, 0, 0, "R06"),
        (1536, 2048, false, 2, 0, 1, "C05"),
        (1536, 2048, false, 2, 0, 42, "C05"),
        (1536, 2048, false, 2, 0, 2024, "L01"),
        (1536, 2048, false, 2, 0, -1, "X01"),
        (1536, 2048, false, 2, 0, -5, "L02"),
        (1536, 2048, false, 2, 0, 123456789, "R04"),
        (1536, 2048, false, 2, 0, 99999999999, "X02"),
        (1536, 2048, false, 2, 1, 0, "R06"),
        (1536, 2048, false, 2, 1, 1, "C05"),
        (1536, 2048, false, 2, 1, 42, "C05"),
        (1536, 2048, false, 2, 1, 2024, "L01"),
        (1536, 2048, false, 2, 1, -1, "X01"),
        (1536, 2048, false, 2, 1, -5, "L02"),
        (1536, 2048, false, 2, 1, 123456789, "R04"),
        (1536, 2048, false, 2, 1, 99999999999, "C02"),
        (1536, 2048, false, 3, 0, 0, "R06"),
        (1536, 2048, false, 3, 0, 1, "C05"),
        (1536, 2048, false, 3, 0, 42, "C05"),
        (1536, 2048, false, 3, 0, 2024, "L01"),
        (1536, 2048, false, 3, 0, -1, "X01"),
        (1536, 2048, false, 3, 0, -5, "L02"),
        (1536, 2048, false, 3, 0, 123456789, "R04"),
        (1536, 2048, false, 3, 0, 99999999999, "X02"),
        (1536, 2048, false, 3, 1, 0, "R06"),
        (1536, 2048, false, 3, 1, 1, "C05"),
        (1536, 2048, false, 3, 1, 42, "C05"),
        (1536, 2048, false, 3, 1, 2024, "L01"),
        (1536, 2048, false, 3, 1, -1, "X01"),
        (1536, 2048, false, 3, 1, -5, "L02"),
        (1536, 2048, false, 3, 1, 123456789, "R04"),
        (1536, 2048, false, 3, 1, 99999999999, "C02"),
        (2532, 1170, true, 2, 0, 0, "R06"),
        (2532, 1170, true, 2, 0, 1, "C05"),
        (2532, 1170, true, 2, 0, 42, "C05"),
        (2532, 1170, true, 2, 0, 2024, "L01"),
        (2532, 1170, true, 2, 0, -1, "X01"),
        (2532, 1170, true, 2, 0, -5, "L02"),
        (2532, 1170, true, 2, 0, 123456789, "R04"),
        (2532, 1170, true, 2, 0, 99999999999, "X02"),
        (2532, 1170, true, 2, 1, 0, "R06"),
        (2532, 1170, true, 2, 1, 1, "C05"),
        (2532, 1170, true, 2, 1, 42, "C05"),
        (2532, 1170, true, 2, 1, 2024, "L01"),
        (2532, 1170, true, 2, 1, -1, "X01"),
        (2532, 1170, true, 2, 1, -5, "L02"),
        (2532, 1170, true, 2, 1, 123456789, "R04"),
        (2532, 1170, true, 2, 1, 99999999999, "C02"),
        (2532, 1170, true, 3, 0, 0, "R06"),
        (2532, 1170, true, 3, 0, 1, "L01"),
        (2532, 1170, true, 3, 0, 42, "R06"),
        (2532, 1170, true, 3, 0, 2024, "L01"),
        (2532, 1170, true, 3, 0, -1, "X01"),
        (2532, 1170, true, 3, 0, -5, "L02"),
        (2532, 1170, true, 3, 0, 123456789, "R04"),
        (2532, 1170, true, 3, 0, 99999999999, "X02"),
        (2532, 1170, true, 3, 1, 0, "R06"),
        (2532, 1170, true, 3, 1, 1, "L01"),
        (2532, 1170, true, 3, 1, 42, "R06"),
        (2532, 1170, true, 3, 1, 2024, "L01"),
        (2532, 1170, true, 3, 1, -1, "X01"),
        (2532, 1170, true, 3, 1, -5, "L02"),
        (2532, 1170, true, 3, 1, 123456789, "R04"),
        (2532, 1170, true, 3, 1, 99999999999, "L04"),
        (2048, 1536, true, 2, 0, 0, "R06"),
        (2048, 1536, true, 2, 0, 1, "C05"),
        (2048, 1536, true, 2, 0, 42, "C05"),
        (2048, 1536, true, 2, 0, 2024, "L01"),
        (2048, 1536, true, 2, 0, -1, "X01"),
        (2048, 1536, true, 2, 0, -5, "L02"),
        (2048, 1536, true, 2, 0, 123456789, "R04"),
        (2048, 1536, true, 2, 0, 99999999999, "X02"),
        (2048, 1536, true, 2, 1, 0, "R06"),
        (2048, 1536, true, 2, 1, 1, "C05"),
        (2048, 1536, true, 2, 1, 42, "C05"),
        (2048, 1536, true, 2, 1, 2024, "L01"),
        (2048, 1536, true, 2, 1, -1, "X01"),
        (2048, 1536, true, 2, 1, -5, "L02"),
        (2048, 1536, true, 2, 1, 123456789, "R04"),
        (2048, 1536, true, 2, 1, 99999999999, "C02"),
        (2048, 1536, true, 3, 0, 0, "R06"),
        (2048, 1536, true, 3, 0, 1, "L01"),
        (2048, 1536, true, 3, 0, 42, "R06"),
        (2048, 1536, true, 3, 0, 2024, "L01"),
        (2048, 1536, true, 3, 0, -1, "X01"),
        (2048, 1536, true, 3, 0, -5, "L02"),
        (2048, 1536, true, 3, 0, 123456789, "R04"),
        (2048, 1536, true, 3, 0, 99999999999, "L04"),
        (2048, 1536, true, 3, 1, 0, "R06"),
        (2048, 1536, true, 3, 1, 1, "L01"),
        (2048, 1536, true, 3, 1, 42, "R06"),
        (2048, 1536, true, 3, 1, 2024, "L01"),
        (2048, 1536, true, 3, 1, -1, "X01"),
        (2048, 1536, true, 3, 1, -5, "L02"),
        (2048, 1536, true, 3, 1, 123456789, "R04"),
        (2048, 1536, true, 3, 1, 99999999999, "L04"),
    ]
    static let horseWaitingChoices: [(avoid: String, seed: Int64, preferLeft: Bool, id: String)] = [
        ("L01", 0, true, "C04"),
        ("L01", 0, false, "R02"),
        ("L01", 1, true, "C02"),
        ("L01", 1, false, "H02"),
        ("L01", 42, true, "L06"),
        ("L01", 42, false, "C05"),
        ("L01", 2024, true, "L04"),
        ("L01", 2024, false, "C05"),
        ("L01", -1, true, "C03"),
        ("L01", -1, false, "R04"),
        ("L01", -5, true, "C03"),
        ("L01", -5, false, "X05"),
        ("L01", 123456789, true, "C04"),
        ("L01", 123456789, false, "R02"),
        ("L01", 99999999999, true, "C02"),
        ("L01", 99999999999, false, "R03"),
        ("L01", 9223372036854775807, true, "C04"),
        ("L01", 9223372036854775807, false, "R02"),
        ("L01", Int64.min, true, "C04"),
        ("L01", Int64.min, false, "R07"),
        ("L01", 81985529216486895, true, "C02"),
        ("L01", 81985529216486895, false, "R06"),
        ("L01", -987654321012, true, "C03"),
        ("L01", -987654321012, false, "X05"),
        ("C04", 0, true, "X01"),
        ("C04", 0, false, "X05"),
        ("C04", 1, true, "L03"),
        ("C04", 1, false, "H02"),
        ("C04", 42, true, "L02"),
        ("C04", 42, false, "H02"),
        ("C04", 2024, true, "L01"),
        ("C04", 2024, false, "H02"),
        ("C04", -1, true, "C01"),
        ("C04", -1, false, "H01"),
        ("C04", -5, true, "C01"),
        ("C04", -5, false, "H01"),
        ("C04", 123456789, true, "X01"),
        ("C04", 123456789, false, "R01"),
        ("C04", 99999999999, true, "L03"),
        ("C04", 99999999999, false, "R01"),
        ("C04", 9223372036854775807, true, "X01"),
        ("C04", 9223372036854775807, false, "H02"),
        ("C04", Int64.min, true, "X01"),
        ("C04", Int64.min, false, "R01"),
        ("C04", 81985529216486895, true, "L03"),
        ("C04", 81985529216486895, false, "R05"),
        ("C04", -987654321012, true, "C01"),
        ("C04", -987654321012, false, "R01"),
        ("R07", 0, true, "L01"),
        ("R07", 0, false, "X03"),
        ("R07", 1, true, "C02"),
        ("R07", 1, false, "H01"),
        ("R07", 42, true, "X01"),
        ("R07", 42, false, "X03"),
        ("R07", 2024, true, "C04"),
        ("R07", 2024, false, "C05"),
        ("R07", -1, true, "L05"),
        ("R07", -1, false, "X03"),
        ("R07", -5, true, "L03"),
        ("R07", -5, false, "X03"),
        ("R07", 123456789, true, "C01"),
        ("R07", 123456789, false, "H01"),
        ("R07", 99999999999, true, "X02"),
        ("R07", 99999999999, false, "H01"),
        ("R07", 9223372036854775807, true, "L05"),
        ("R07", 9223372036854775807, false, "H01"),
        ("R07", Int64.min, true, "X02"),
        ("R07", Int64.min, false, "C05"),
        ("R07", 81985529216486895, true, "C01"),
        ("R07", 81985529216486895, false, "X03"),
        ("R07", -987654321012, true, "C04"),
        ("R07", -987654321012, false, "X03"),
        ("H01", 0, true, "L01"),
        ("H01", 0, false, "R07"),
        ("H01", 1, true, "C02"),
        ("H01", 1, false, "R04"),
        ("H01", 42, true, "X01"),
        ("H01", 42, false, "C05"),
        ("H01", 2024, true, "C04"),
        ("H01", 2024, false, "C06"),
        ("H01", -1, true, "L05"),
        ("H01", -1, false, "C07"),
        ("H01", -5, true, "L03"),
        ("H01", -5, false, "R07"),
        ("H01", 123456789, true, "C01"),
        ("H01", 123456789, false, "R07"),
        ("H01", 99999999999, true, "X02"),
        ("H01", 99999999999, false, "R07"),
        ("H01", 9223372036854775807, true, "L05"),
        ("H01", 9223372036854775807, false, "R07"),
        ("H01", Int64.min, true, "X02"),
        ("H01", Int64.min, false, "R07"),
        ("H01", 81985529216486895, true, "C01"),
        ("H01", 81985529216486895, false, "R04"),
        ("H01", -987654321012, true, "C04"),
        ("H01", -987654321012, false, "X03"),
        ("H04", 0, true, "L01"),
        ("H04", 0, false, "C05"),
        ("H04", 1, true, "C02"),
        ("H04", 1, false, "C06"),
        ("H04", 42, true, "X01"),
        ("H04", 42, false, "C07"),
        ("H04", 2024, true, "C04"),
        ("H04", 2024, false, "X04"),
        ("H04", -1, true, "L05"),
        ("H04", -1, false, "C06"),
        ("H04", -5, true, "L03"),
        ("H04", -5, false, "X04"),
        ("H04", 123456789, true, "C01"),
        ("H04", 123456789, false, "R01"),
        ("H04", 99999999999, true, "X02"),
        ("H04", 99999999999, false, "X03"),
        ("H04", 9223372036854775807, true, "L05"),
        ("H04", 9223372036854775807, false, "C06"),
        ("H04", Int64.min, true, "X02"),
        ("H04", Int64.min, false, "C05"),
        ("H04", 81985529216486895, true, "C01"),
        ("H04", 81985529216486895, false, "R01"),
        ("H04", -987654321012, true, "C04"),
        ("H04", -987654321012, false, "X04"),
        ("X05", 0, true, "L01"),
        ("X05", 0, false, "L01"),
        ("X05", 1, true, "C02"),
        ("X05", 1, false, "C02"),
        ("X05", 42, true, "X01"),
        ("X05", 42, false, "X01"),
        ("X05", 2024, true, "C04"),
        ("X05", 2024, false, "C04"),
        ("X05", -1, true, "L05"),
        ("X05", -1, false, "L05"),
        ("X05", -5, true, "L03"),
        ("X05", -5, false, "L03"),
        ("X05", 123456789, true, "C01"),
        ("X05", 123456789, false, "C01"),
        ("X05", 99999999999, true, "X02"),
        ("X05", 99999999999, false, "X02"),
        ("X05", 9223372036854775807, true, "L05"),
        ("X05", 9223372036854775807, false, "L05"),
        ("X05", Int64.min, true, "X02"),
        ("X05", Int64.min, false, "X02"),
        ("X05", 81985529216486895, true, "C01"),
        ("X05", 81985529216486895, false, "C01"),
        ("X05", -987654321012, true, "C04"),
        ("X05", -987654321012, false, "C04"),
        ("FREE_9", 0, true, "L01"),
        ("FREE_9", 0, false, "R02"),
        ("FREE_9", 1, true, "C02"),
        ("FREE_9", 1, false, "H02"),
        ("FREE_9", 42, true, "X01"),
        ("FREE_9", 42, false, "C05"),
        ("FREE_9", 2024, true, "C04"),
        ("FREE_9", 2024, false, "C05"),
        ("FREE_9", -1, true, "L05"),
        ("FREE_9", -1, false, "R04"),
        ("FREE_9", -5, true, "L03"),
        ("FREE_9", -5, false, "X05"),
        ("FREE_9", 123456789, true, "C01"),
        ("FREE_9", 123456789, false, "R02"),
        ("FREE_9", 99999999999, true, "X02"),
        ("FREE_9", 99999999999, false, "R03"),
        ("FREE_9", 9223372036854775807, true, "L05"),
        ("FREE_9", 9223372036854775807, false, "R02"),
        ("FREE_9", Int64.min, true, "X02"),
        ("FREE_9", Int64.min, false, "R07"),
        ("FREE_9", 81985529216486895, true, "C01"),
        ("FREE_9", 81985529216486895, false, "R06"),
        ("FREE_9", -987654321012, true, "C04"),
        ("FREE_9", -987654321012, false, "X05"),
    ]
    static let challengeWaitingChoices: [(avoid: String, seed: Int64, id: String)] = [
        ("L03", 0, "X05"),
        ("L03", 1, "R04"),
        ("L03", 42, "R04"),
        ("L03", 2024, "R06"),
        ("L03", -1, "R05"),
        ("L03", -5, "C07"),
        ("L03", 123456789, "R06"),
        ("L03", 99999999999, "X03"),
        ("L03", 9223372036854775807, "R01"),
        ("L03", Int64.min, "X03"),
        ("L03", 81985529216486895, "R04"),
        ("L03", -987654321012, "H01"),
        ("C01", 0, "X05"),
        ("C01", 1, "H02"),
        ("C01", 42, "H01"),
        ("C01", 2024, "H01"),
        ("C01", -1, "R04"),
        ("C01", -5, "C07"),
        ("C01", 123456789, "H01"),
        ("C01", 99999999999, "H01"),
        ("C01", 9223372036854775807, "R05"),
        ("C01", Int64.min, "R03"),
        ("C01", 81985529216486895, "X04"),
        ("C01", -987654321012, "R03"),
        ("C04", 0, "H01"),
        ("C04", 1, "R01"),
        ("C04", 42, "H01"),
        ("C04", 2024, "H02"),
        ("C04", -1, "R01"),
        ("C04", -5, "H01"),
        ("C04", 123456789, "H01"),
        ("C04", 99999999999, "R07"),
        ("C04", 9223372036854775807, "H01"),
        ("C04", Int64.min, "R07"),
        ("C04", 81985529216486895, "H01"),
        ("C04", -987654321012, "R01"),
        ("R04", 0, "X02"),
        ("R04", 1, "C03"),
        ("R04", 42, "C02"),
        ("R04", 2024, "C02"),
        ("R04", -1, "L04"),
        ("R04", -5, "L01"),
        ("R04", 123456789, "C02"),
        ("R04", 99999999999, "C02"),
        ("R04", 9223372036854775807, "L05"),
        ("R04", Int64.min, "L03"),
        ("R04", 81985529216486895, "X01"),
        ("R04", -987654321012, "L03"),
        ("X03", 0, "L02"),
        ("X03", 1, "L02"),
        ("X03", 42, "L02"),
        ("X03", 2024, "L04"),
        ("X03", -1, "L03"),
        ("X03", -5, "L02"),
        ("X03", 123456789, "L01"),
        ("X03", 99999999999, "L01"),
        ("X03", 9223372036854775807, "L02"),
        ("X03", Int64.min, "L01"),
        ("X03", 81985529216486895, "L01"),
        ("X03", -987654321012, "L04"),
        ("H02", 0, "C02"),
        ("H02", 1, "C02"),
        ("H02", 42, "X02"),
        ("H02", 2024, "C04"),
        ("H02", -1, "C03"),
        ("H02", -5, "C01"),
        ("H02", 123456789, "L01"),
        ("H02", 99999999999, "C04"),
        ("H02", 9223372036854775807, "C01"),
        ("H02", Int64.min, "L05"),
        ("H02", 81985529216486895, "L04"),
        ("H02", -987654321012, "L02"),
        ("H05", 0, "C02"),
        ("H05", 1, "C02"),
        ("H05", 42, "X02"),
        ("H05", 2024, "C04"),
        ("H05", -1, "C03"),
        ("H05", -5, "C01"),
        ("H05", 123456789, "L01"),
        ("H05", 99999999999, "C04"),
        ("H05", 9223372036854775807, "C01"),
        ("H05", Int64.min, "L05"),
        ("H05", 81985529216486895, "L04"),
        ("H05", -987654321012, "L02"),
        ("fallback_3b", 0, "H01"),
        ("fallback_3b", 1, "R01"),
        ("fallback_3b", 42, "H01"),
        ("fallback_3b", 2024, "H02"),
        ("fallback_3b", -1, "R01"),
        ("fallback_3b", -5, "H01"),
        ("fallback_3b", 123456789, "H01"),
        ("fallback_3b", 99999999999, "R07"),
        ("fallback_3b", 9223372036854775807, "H01"),
        ("fallback_3b", Int64.min, "R07"),
        ("fallback_3b", 81985529216486895, "H01"),
        ("fallback_3b", -987654321012, "R01"),
        ("fallback_2a", 0, "X05"),
        ("fallback_2a", 1, "R04"),
        ("fallback_2a", 42, "R04"),
        ("fallback_2a", 2024, "R06"),
        ("fallback_2a", -1, "R05"),
        ("fallback_2a", -5, "C07"),
        ("fallback_2a", 123456789, "R06"),
        ("fallback_2a", 99999999999, "X03"),
        ("fallback_2a", 9223372036854775807, "R01"),
        ("fallback_2a", Int64.min, "X03"),
        ("fallback_2a", 81985529216486895, "R04"),
        ("fallback_2a", -987654321012, "H01"),
    ]
    static let fallbackIds: [(index: Int, count: Int, id: String)] = [
        (-2, -1, "fallback_2a"),
        (-1, -1, "fallback_2a"),
        (0, -1, "fallback_2a"),
        (1, -1, "fallback_2b"),
        (2, -1, "fallback_2b"),
        (3, -1, "fallback_2b"),
        (4, -1, "fallback_2b"),
        (5, -1, "fallback_2b"),
        (-2, 0, "fallback_2a"),
        (-1, 0, "fallback_2a"),
        (0, 0, "fallback_2a"),
        (1, 0, "fallback_2b"),
        (2, 0, "fallback_2b"),
        (3, 0, "fallback_2b"),
        (4, 0, "fallback_2b"),
        (5, 0, "fallback_2b"),
        (-2, 1, "fallback_2a"),
        (-1, 1, "fallback_2a"),
        (0, 1, "fallback_2a"),
        (1, 1, "fallback_2b"),
        (2, 1, "fallback_2b"),
        (3, 1, "fallback_2b"),
        (4, 1, "fallback_2b"),
        (5, 1, "fallback_2b"),
        (-2, 2, "fallback_2a"),
        (-1, 2, "fallback_2a"),
        (0, 2, "fallback_2a"),
        (1, 2, "fallback_2b"),
        (2, 2, "fallback_2b"),
        (3, 2, "fallback_2b"),
        (4, 2, "fallback_2b"),
        (5, 2, "fallback_2b"),
        (-2, 3, "fallback_3a"),
        (-1, 3, "fallback_3a"),
        (0, 3, "fallback_3a"),
        (1, 3, "fallback_3b"),
        (2, 3, "fallback_3c"),
        (3, 3, "fallback_3c"),
        (4, 3, "fallback_3c"),
        (5, 3, "fallback_3c"),
        (-2, 4, "fallback_4a"),
        (-1, 4, "fallback_4a"),
        (0, 4, "fallback_4a"),
        (1, 4, "fallback_4b"),
        (2, 4, "fallback_4c"),
        (3, 4, "fallback_4d"),
        (4, 4, "fallback_4d"),
        (5, 4, "fallback_4d"),
        (-2, 5, "fallback_4a"),
        (-1, 5, "fallback_4a"),
        (0, 5, "fallback_4a"),
        (1, 5, "fallback_4b"),
        (2, 5, "fallback_4c"),
        (3, 5, "fallback_4d"),
        (4, 5, "fallback_4d"),
        (5, 5, "fallback_4d"),
        (-2, 6, "fallback_4a"),
        (-1, 6, "fallback_4a"),
        (0, 6, "fallback_4a"),
        (1, 6, "fallback_4b"),
        (2, 6, "fallback_4c"),
        (3, 6, "fallback_4d"),
        (4, 6, "fallback_4d"),
        (5, 6, "fallback_4d"),
    ]
    static let arcFractions: [(level: UInt32, highLob: Bool, bits: UInt32)] = [
        (0x00000000, false, 0x3F851EB8),
        (0x00000000, true, 0x3F851EB8),
        (0x3E800000, false, 0x3F800000),
        (0x3E800000, true, 0x3F80A3D7),
        (0x3F000000, false, 0x3F75C28F),
        (0x3F000000, true, 0x3F7851EB),
        (0x3F400000, false, 0x3F6B851E),
        (0x3F400000, true, 0x3F6F5C28),
        (0x3F800000, false, 0x3F6147AE),
        (0x3F800000, true, 0x3F666666),
        (0x3FC00000, false, 0x3F451EB8),
        (0x3FC00000, true, 0x3F4F5C29),
        (0x40133333, false, 0x3F19999A),
        (0x40133333, true, 0x3F2D9169),
        (0x407FEF9E, false, 0x3E99AE92),
        (0x407FEF9E, true, 0x3ED71F36),
        (0x40800000, false, 0x3E99999A),
        (0x40800000, true, 0x3ED70A3D),
        (0x40900000, false, 0x3E75C290),
        (0x40900000, true, 0x3EBD70A4),
        (0x409FAE14, false, 0x3E398C80),
        (0x409FAE14, true, 0x3EA45A1D),
        (0x40A00000, false, 0x3E3851EC),
        (0x40A00000, true, 0x3EA3D70A),
        (0xBF000000, false, 0x3F851EB8),
        (0xBF000000, true, 0x3F851EB8),
        (0x40E00000, false, 0x3E3851EC),
        (0x40E00000, true, 0x3EA3D70A),
    ]
    static let aimAssistLevels: [(id: String, base: Int, bits: UInt32)] = [
        ("L01", 0, 0x3EBC9630),
        ("L02", 0, 0x3E59999A),
        ("L03", 0, 0x3DCB17E3),
        ("L04", 0, 0x3E3C962F),
        ("L05", 0, 0x3E59999A),
        ("L06", 0, 0x3E911112),
        ("C01", 0, 0x3EE0DA76),
        ("C02", 0, 0x3EB55556),
        ("C03", 0, 0x3ECB17E4),
        ("C04", 0, 0x3F2A740E),
        ("C05", 0, 0x3ED99998),
        ("C06", 0, 0x3ED258BE),
        ("C07", 0, 0x3F1851EB),
        ("R01", 0, 0x3EF69D04),
        ("R02", 0, 0x3EAE147A),
        ("R03", 0, 0x3EBC9630),
        ("R04", 0, 0x3EFDDDDE),
        ("R05", 0, 0x3EE0DA76),
        ("R06", 0, 0x3ED258BE),
        ("R07", 0, 0x3EFDDDDE),
        ("H01", 0, 0x3F14B17E),
        ("H02", 0, 0x3F233334),
        ("H03", 0, 0x3F2A740E),
        ("H04", 0, 0x3F31B4E8),
        ("H05", 0, 0x3FF34E81),
        ("X01", 0, 0x3EA6D3A0),
        ("X02", 0, 0x3EA6D3A0),
        ("X03", 0, 0x3EBC9630),
        ("X04", 0, 0x3EFDDDDE),
        ("X05", 0, 0x3ED258BE),
        ("L01", 2, 0x401792C6),
        ("L02", 2, 0x400D999A),
        ("L03", 2, 0x400658BF),
        ("L04", 2, 0x400BC963),
        ("L05", 2, 0x400D999A),
        ("L06", 2, 0x40122222),
        ("C01", 2, 0x401C1B4F),
        ("C02", 2, 0x4016AAAB),
        ("C03", 2, 0x401962FC),
        ("C04", 2, 0x402A9D04),
        ("C05", 2, 0x401B3333),
        ("C06", 2, 0x401A4B18),
        ("C07", 2, 0x4026147B),
        ("R01", 2, 0x401ED3A0),
        ("R02", 2, 0x4015C28F),
        ("R03", 2, 0x401792C6),
        ("R04", 2, 0x401FBBBC),
        ("R05", 2, 0x401C1B4F),
        ("R06", 2, 0x401A4B18),
        ("R07", 2, 0x401FBBBC),
        ("H01", 2, 0x40252C60),
        ("H02", 2, 0x4028CCCD),
        ("H03", 2, 0x402A9D04),
        ("H04", 2, 0x402C6D3A),
        ("H05", 2, 0x4079A740),
        ("X01", 2, 0x4014DA74),
        ("X02", 2, 0x4014DA74),
        ("X03", 2, 0x401792C6),
        ("X04", 2, 0x401FBBBC),
        ("X05", 2, 0x401A4B18),
        ("L01", 5, 0x40A00000),
        ("L02", 5, 0x40A00000),
        ("L03", 5, 0x40A00000),
        ("L04", 5, 0x40A00000),
        ("L05", 5, 0x40A00000),
        ("L06", 5, 0x40A00000),
        ("C01", 5, 0x40A00000),
        ("C02", 5, 0x40A00000),
        ("C03", 5, 0x40A00000),
        ("C04", 5, 0x40A00000),
        ("C05", 5, 0x40A00000),
        ("C06", 5, 0x40A00000),
        ("C07", 5, 0x40A00000),
        ("R01", 5, 0x40A00000),
        ("R02", 5, 0x40A00000),
        ("R03", 5, 0x40A00000),
        ("R04", 5, 0x40A00000),
        ("R05", 5, 0x40A00000),
        ("R06", 5, 0x40A00000),
        ("R07", 5, 0x40A00000),
        ("H01", 5, 0x40A00000),
        ("H02", 5, 0x40A00000),
        ("H03", 5, 0x40A00000),
        ("H04", 5, 0x40A00000),
        ("H05", 5, 0x40A00000),
        ("X01", 5, 0x40A00000),
        ("X02", 5, 0x40A00000),
        ("X03", 5, 0x40A00000),
        ("X04", 5, 0x40A00000),
        ("X05", 5, 0x40A00000),
    ]
    static let liveDifficulty: [(x: UInt32, y: UInt32, bits: UInt32)] = [
        (0x443B8000, 0x43AA0000, 0x00000000),
        (0x431B0000, 0x44938000, 0x3F5DB0C8),
        (0x44020000, 0x449D8000, 0x3F46A1B1),
        (0x44494000, 0x448B6000, 0x3F15E344),
        (0x44000000, 0x4492E000, 0x3F2FDC0D),
        (0x00000000, 0x00000000, 0x3F231EAF),
        (0x44800000, 0x44C00000, 0x3F800000),
        (0x44610000, 0x43FA0000, 0x00000000),
        (0x43964000, 0x44779000, 0x3F19BD52),
    ]
    static let preRelease: [(pull: UInt32, motion: String)] = [
        (0xBF800000, "SHOT_LOW"),
        (0x00000000, "SHOT_LOW"),
        (0x3D236E2F, "SHOT_LOW"),
        (0x3D23D70A, "SHOT_MID"),
        (0x3E4CCCCD, "SHOT_MID"),
        (0x3EEB7803, "SHOT_MID"),
        (0x3EEB851F, "SHOT_SET"),
        (0x3F800000, "SHOT_SET"),
        (0x3F99999A, "SHOT_SET"),
        (0x40A00000, "SHOT_SET"),
    ]
    static let facingSequences: [(w: Int, h: Int, landscape: Bool, steps: [(footY: UInt32, human: String, bot: String)])] = [
        (1080, 2400, false, [(0x44D6D800, "BACK", "BACK"), (0x44C54400, "BACK", "BACK"), (0x44C31E00, "BACK", "FRONT"), (0x44BEA000, "BACK", "FRONT"), (0x44BE6E00, "FRONT", "FRONT"), (0x44BB8000, "FRONT", "FRONT"), (0x44C35000, "FRONT", "FRONT"), (0x44C38200, "FRONT", "BACK"), (0x44C80000, "FRONT", "BACK"), (0x44C83200, "BACK", "BACK"), (0x44D6D800, "BACK", "BACK"), (0x44BE8700, "BACK", "FRONT"), (0x44BE3C00, "FRONT", "FRONT"), (0x44C86400, "BACK", "BACK"), (0x441C4000, "FRONT", "FRONT"), (0x45435000, "BACK", "BACK")]),
        (1170, 2532, false, [(0x44E2A900, "BACK", "BACK"), (0x44D01D80, "BACK", "BACK"), (0x44CDD940, "BACK", "FRONT"), (0x44C91C00, "BACK", "FRONT"), (0x44C8E740, "FRONT", "FRONT"), (0x44C5D000, "FRONT", "FRONT"), (0x44CE0E00, "FRONT", "FRONT"), (0x44CE42C0, "FRONT", "BACK"), (0x44D30000, "FRONT", "BACK"), (0x44D334C0, "BACK", "BACK"), (0x44E2A900, "BACK", "BACK"), (0x44C901A0, "BACK", "FRONT"), (0x44C8B280, "FRONT", "FRONT"), (0x44D36980, "BACK", "BACK"), (0x4424D800, "FRONT", "FRONT"), (0x454E0E00, "BACK", "BACK")]),
        (828, 1792, false, [(0x44A06AAA, "BACK", "BACK"), (0x44934AAA, "BACK", "BACK"), (0x4491B000, "BACK", "FRONT"), (0x448E5555, "BACK", "FRONT"), (0x448E3000, "BACK", "FRONT"), (0x448C0000, "FRONT", "FRONT"), (0x4491D555, "FRONT", "FRONT"), (0x4491FAAA, "FRONT", "BACK"), (0x44955555, "FRONT", "BACK"), (0x44957AAA, "BACK", "BACK"), (0x44A06AAA, "BACK", "BACK"), (0x448E42AA, "BACK", "FRONT"), (0x448E0AAA, "FRONT", "FRONT"), (0x4495A000, "BACK", "BACK"), (0x43E95555, "FRONT", "FRONT"), (0x4511D555, "BACK", "BACK")]),
        (1536, 2048, false, [(0x44C3A9BE, "BACK", "BACK"), (0x44B15217, "BACK", "BACK"), (0x44AF142D, "BACK", "FRONT"), (0x44AA642D, "BACK", "FRONT"), (0x44AA3000, "FRONT", "FRONT"), (0x44A72165, "FRONT", "FRONT"), (0x44AF4859, "FRONT", "FRONT"), (0x44AF7C86, "FRONT", "BACK"), (0x44B42C86, "FRONT", "BACK"), (0x44B460B3, "BACK", "BACK"), (0x44C3A9BE, "BACK", "BACK"), (0x44AA4A17, "BACK", "FRONT"), (0x44A9FBD4, "FRONT", "FRONT"), (0x44B494DF, "BACK", "BACK"), (0x43D40002, "FRONT", "FRONT"), (0x453D8B21, "BACK", "BACK")]),
        (2532, 1170, true, [(0x44517900, "BACK", "BACK"), (0x44405580, "BACK", "BACK"), (0x443E3D40, "BACK", "FRONT"), (0x4439DC00, "BACK", "FRONT"), (0x4439AB40, "FRONT", "FRONT"), (0x4436D000, "FRONT", "FRONT"), (0x443E6E00, "FRONT", "FRONT"), (0x443E9EC0, "FRONT", "BACK"), (0x44430000, "FRONT", "BACK"), (0x444330C0, "BACK", "BACK"), (0x44517900, "BACK", "BACK"), (0x4439C3A0, "BACK", "FRONT"), (0x44397A80, "FRONT", "FRONT"), (0x44436180, "BACK", "BACK"), (0x43985800, "FRONT", "FRONT"), (0x44BE6E00, "BACK", "BACK")]),
        (2048, 1536, true, [(0x44898000, "BACK", "BACK"), (0x447C8000, "BACK", "BACK"), (0x4479C000, "BACK", "FRONT"), (0x44740000, "BACK", "FRONT"), (0x4473C000, "FRONT", "FRONT"), (0x44700000, "FRONT", "FRONT"), (0x447A0000, "FRONT", "FRONT"), (0x447A4000, "FRONT", "BACK"), (0x44800000, "FRONT", "BACK"), (0x44802000, "BACK", "BACK"), (0x44898000, "BACK", "BACK"), (0x4473E000, "BACK", "FRONT"), (0x44738000, "FRONT", "FRONT"), (0x44804000, "BACK", "BACK"), (0x43C80000, "FRONT", "FRONT"), (0x44FA0000, "BACK", "BACK")]),
    ]
    // 6c38131: shotFacingFor uses the world hoop direction (hoopScreenDirection); oneOnOneShotFacingFor is the
    // same function. Regenerated with the w-court3 harness updated to those bodies.
    static let shotFacings: [(w: Int, h: Int, landscape: Bool, x: UInt32, y: UInt32, shot: String, oneOnOne: String)] = [
        (1080, 2400, false, 0xC2978000, 0x44B3B000, "SIDE", "SIDE"),
        (1080, 2400, false, 0xC21F4000, 0x44C44A00, "SIDE", "SIDE"),
        (1080, 2400, false, 0xC0780000, 0x44D5DE00, "SIDE", "SIDE"),
        (1080, 2400, false, 0x4239C000, 0x44E57E00, "SIDE", "SIDE"),
        (1080, 2400, false, 0x42C18000, 0x44C83200, "SIDE", "SIDE"),
        (1080, 2400, false, 0x4304B000, 0x44DBBA00, "SIDE", "SIDE"),
        (1080, 2400, false, 0x4353C000, 0x44B5A400, "SIDE", "SIDE"),
        (1080, 2400, false, 0x43830800, 0x44C54400, "SIDE", "SIDE"),
        (1080, 2400, false, 0x438DD000, 0x44D6D800, "SIDE", "SIDE"),
        (1080, 2400, false, 0x43A36000, 0x44E96600, "SIDE", "SIDE"),
        (1080, 2400, false, 0x43CAE800, 0x44BD7400, "SIDE", "SIDE"),
        (1080, 2400, false, 0x43D21800, 0x44D0FC00, "SIDE", "SIDE"),
        (1080, 2400, false, 0x43E41000, 0x44E38A00, "SIDE", "SIDE"),
        (1080, 2400, false, 0x44023400, 0x44B3B000, "FRONT", "FRONT"),
        (1080, 2400, false, 0x4405CC00, 0x44C63E00, "SIDE", "SIDE"),
        (1080, 2400, false, 0x440EC800, 0x44D7D200, "SIDE", "SIDE"),
        (1080, 2400, false, 0x44199000, 0x44E67800, "SIDE", "SIDE"),
        (1080, 2400, false, 0x44262400, 0x44BD7400, "SIDE", "SIDE"),
        (1080, 2400, false, 0x442D5400, 0x44D00200, "BACK", "BACK"),
        (1080, 2400, false, 0x44381C00, 0x44DEA800, "BACK", "BACK"),
        (1080, 2400, false, 0x4439E800, 0x44ABE000, "SIDE", "SIDE"),
        (1080, 2400, false, 0x44467C00, 0x44B89200, "SIDE", "SIDE"),
        (1080, 2400, false, 0x444DAC00, 0x44C63E00, "BACK", "BACK"),
        (1080, 2400, false, 0x44531000, 0x44D4E400, "BACK", "BACK"),
        (1080, 2400, false, 0x445C0C00, 0x44DEA800, "BACK", "BACK"),
        (1080, 2400, false, 0x42A4C000, 0x44B98C00, "SIDE", "SIDE"),
        (1080, 2400, false, 0x433E3000, 0x44CF0800, "SIDE", "SIDE"),
        (1080, 2400, false, 0x43BC8800, 0x44C92C00, "SIDE", "SIDE"),
        (1080, 2400, false, 0x43F9A000, 0x44DBBA00, "SIDE", "SIDE"),
        (1080, 2400, false, 0x4420C000, 0x44C54400, "SIDE", "SIDE"),
        (1080, 2400, false, 0x442B8800, 0x446A6000, "FRONT", "FRONT"),
        (1080, 2400, false, 0x442B8800, 0x44B92800, "BACK", "BACK"),
        (1080, 2400, false, 0x4482B000, 0x44FDE800, "BACK", "BACK"),
        (1080, 2400, false, 0xC3BCD000, 0x449C4000, "SIDE", "SIDE"),
        (1080, 2400, false, 0x4404B800, 0x44B5D600, "SIDE", "SIDE"),
        (1080, 2400, false, 0x44525800, 0x4508B800, "BACK", "BACK"),
        (1170, 2532, false, 0xC24543E8, 0x44BD9200, "SIDE", "SIDE"),
        (1170, 2532, false, 0xC1366FA0, 0x44CF15C0, "SIDE", "SIDE"),
        (1170, 2532, false, 0x41D41830, 0x44E1A140, "SIDE", "SIDE"),
        (1170, 2532, false, 0x429F2ED8, 0x44F21D40, "SIDE", "SIDE"),
        (1170, 2532, false, 0x4304ABD4, 0x44D334C0, "SIDE", "SIDE"),
        (1170, 2532, false, 0x432A95D4, 0x44E7CFC0, "SIDE", "SIDE"),
        (1170, 2532, false, 0x437DFF08, 0x44BFA180, "SIDE", "SIDE"),
        (1170, 2532, false, 0x439989B6, 0x44D01D80, "SIDE", "SIDE"),
        (1170, 2532, false, 0x43A4E984, 0x44E2A900, "SIDE", "SIDE"),
        (1170, 2532, false, 0x43BBA91E, 0x44F63C40, "SIDE", "SIDE"),
        (1170, 2532, false, 0x43E55DB8, 0x44C7DF80, "SIDE", "SIDE"),
        (1170, 2532, false, 0x43ECF2EA, 0x44DC7A80, "SIDE", "SIDE"),
        (1170, 2532, false, 0x43FFE7EA, 0x44F00DC0, "SIDE", "SIDE"),
        (1170, 2532, false, 0x441103A8, 0x44BD9200, "FRONT", "FRONT"),
        (1170, 2532, false, 0x4414CE42, 0x44D12540, "SIDE", "SIDE"),
        (1170, 2532, false, 0x441E48C2, 0x44E3B0C0, "SIDE", "SIDE"),
        (1170, 2532, false, 0x4429A88E, 0x44F32500, "SIDE", "SIDE"),
        (1170, 2532, false, 0x4436EDA8, 0x44C7DF80, "SIDE", "SIDE"),
        (1170, 2532, false, 0x443E82DC, 0x44DB72C0, "BACK", "BACK"),
        (1170, 2532, false, 0x4449E2A8, 0x44EAE700, "BACK", "BACK"),
        (1170, 2532, false, 0x444BC7F6, 0x44B55400, "SIDE", "SIDE"),
        (1170, 2532, false, 0x44590D10, 0x44C2B8C0, "SIDE", "SIDE"),
        (1170, 2532, false, 0x4460A242, 0x44D12540, "BACK", "BACK"),
        (1170, 2532, false, 0x44665228, 0x44E09980, "BACK", "BACK"),
        (1170, 2532, false, 0x446FCCA8, 0x44EAE700, "BACK", "BACK"),
        (1170, 2532, false, 0x42EB02D8, 0x44C3C080, "SIDE", "SIDE"),
        (1170, 2532, false, 0x43673F6C, 0x44DA6B00, "SIDE", "SIDE"),
        (1170, 2532, false, 0x43D63350, 0x44D43C80, "SIDE", "SIDE"),
        (1170, 2532, false, 0x440B53C2, 0x44E7CFC0, "SIDE", "SIDE"),
        (1170, 2532, false, 0x44313DC2, 0x44D01D80, "SIDE", "SIDE"),
        (1170, 2532, false, 0x443C9D8E, 0x44774400, "FRONT", "FRONT"),
        (1170, 2532, false, 0x443C9D8E, 0x44C35700, "SIDE", "SIDE"),
        (1170, 2532, false, 0x448DB348, 0x4505EF80, "BACK", "BACK"),
        (1170, 2532, false, 0xC3B7E5B1, 0x44A4D800, "SIDE", "SIDE"),
        (1170, 2532, false, 0x4413AB14, 0x44BFD640, "SIDE", "SIDE"),
        (1170, 2532, false, 0x4465900A, 0x45103D00, "BACK", "BACK"),
        (828, 1792, false, 0xC20BD6FC, 0x44862AAA, "SIDE", "SIDE"),
        (828, 1792, false, 0xC10206A0, 0x44929000, "SIDE", "SIDE"),
        (828, 1792, false, 0x4195A760, 0x449FB000, "SIDE", "SIDE"),
        (828, 1792, false, 0x426117F0, 0x44AB5AAA, "SIDE", "SIDE"),
        (828, 1792, false, 0x42BBAE1C, 0x44957AAA, "SIDE", "SIDE"),
        (828, 1792, false, 0x42F158C4, 0x44A41000, "SIDE", "SIDE"),
        (828, 1792, false, 0x4333B4EA, 0x4487A000, "SIDE", "SIDE"),
        (828, 1792, false, 0x435945FC, 0x44934AAA, "SIDE", "SIDE"),
        (828, 1792, false, 0x43695F96, 0x44A06AAA, "SIDE", "SIDE"),
        (828, 1792, false, 0x4384C964, 0x44AE4555, "SIDE", "SIDE"),
        (828, 1792, false, 0x43A24DA8, 0x448D7555, "SIDE", "SIDE"),
        (828, 1792, false, 0x43A7AB86, 0x449C0AAA, "SIDE", "SIDE"),
        (828, 1792, false, 0x43B51630, 0x44A9E555, "SIDE", "SIDE"),
        (828, 1792, false, 0x43CD3C98, 0x44862AAA, "FRONT", "FRONT"),
        (828, 1792, false, 0x43D29A74, 0x44940555, "SIDE", "SIDE"),
        (828, 1792, false, 0x43E00520, 0x44A12555, "SIDE", "SIDE"),
        (828, 1792, false, 0x43F01EBA, 0x44AC1555, "SIDE", "SIDE"),
        (828, 1792, false, 0x440173A1, 0x448D7555, "SIDE", "SIDE"),
        (828, 1792, false, 0x4406D17F, 0x449B5000, "BACK", "BACK"),
        (828, 1792, false, 0x440EDE4B, 0x44A64000, "BACK", "BACK"),
        (828, 1792, false, 0x441035C3, 0x44805555, "SIDE", "SIDE"),
        (828, 1792, false, 0x44199A07, 0x4489D000, "SIDE", "SIDE"),
        (828, 1792, false, 0x441EF7E5, 0x44940555, "BACK", "BACK"),
        (828, 1792, false, 0x4422FE4B, 0x449EF555, "BACK", "BACK"),
        (828, 1792, false, 0x4429B3A1, 0x44A64000, "BACK", "BACK"),
        (828, 1792, false, 0x42A636A4, 0x448A8AAA, "SIDE", "SIDE"),
        (828, 1792, false, 0x43239B52, 0x449A9555, "SIDE", "SIDE"),
        (828, 1792, false, 0x439791EC, 0x44963555, "SIDE", "SIDE"),
        (828, 1792, false, 0x43C52FCA, 0x44A41000, "SIDE", "SIDE"),
        (828, 1792, false, 0x43FADA74, 0x44934AAA, "SIDE", "SIDE"),
        (828, 1792, false, 0x44057A07, 0x442F0000, "FRONT", "FRONT"),
        (828, 1792, false, 0x44057A07, 0x448A4000, "BACK", "BACK"),
        (828, 1792, false, 0x44488F5C, 0x44BD9555, "BACK", "BACK"),
        (828, 1792, false, 0xC3822E12, 0x44695555, "SIDE", "SIDE"),
        (828, 1792, false, 0x43D0FE4C, 0x4487C555, "SIDE", "SIDE"),
        (828, 1792, false, 0x442274E8, 0x44CC2AAA, "BACK", "BACK"),
        (1536, 2048, false, 0x43A50000, 0x449EFA70, "SIDE", "SIDE"),
        (1536, 2048, false, 0x43B7C000, 0x44B04D38, "SIDE", "SIDE"),
        (1536, 2048, false, 0x43CA8000, 0x44C2A4DF, "SIDE", "SIDE"),
        (1536, 2048, false, 0x43E4C000, 0x44D2F2C9, "SIDE", "SIDE"),
        (1536, 2048, false, 0x43FF0000, 0x44B460B3, "SIDE", "SIDE"),
        (1536, 2048, false, 0x4408E000, 0x44C8C217, "SIDE", "SIDE"),
        (1536, 2048, false, 0x441D8000, 0x44A1042D, "SIDE", "SIDE"),
        (1536, 2048, false, 0x442AA000, 0x44B15217, "SIDE", "SIDE"),
        (1536, 2048, false, 0x44304000, 0x44C3A9BE, "SIDE", "SIDE"),
        (1536, 2048, false, 0x443B8000, 0x44D70643, "SIDE", "SIDE"),
        (1536, 2048, false, 0x44502000, 0x44A92B22, "SIDE", "SIDE"),
        (1536, 2048, false, 0x4453E000, 0x44BD8C86, "SIDE", "SIDE"),
        (1536, 2048, false, 0x445D4000, 0x44D0E90C, "SIDE", "SIDE"),
        (1536, 2048, false, 0x446E2000, 0x449EFA70, "FRONT", "FRONT"),
        (1536, 2048, false, 0x4471E000, 0x44B256F5, "SIDE", "SIDE"),
        (1536, 2048, false, 0x447B4000, 0x44C4AE9C, "SIDE", "SIDE"),
        (1536, 2048, false, 0x44834000, 0x44D3F7A7, "SIDE", "SIDE"),
        (1536, 2048, false, 0x4489D000, 0x44A92B22, "SIDE", "SIDE"),
        (1536, 2048, false, 0x448D9000, 0x44BC87A7, "BACK", "BACK"),
        (1536, 2048, false, 0x44933000, 0x44CBD0B2, "BACK", "BACK"),
        (1536, 2048, false, 0x44942000, 0x4496D37B, "SIDE", "SIDE"),
        (1536, 2048, false, 0x449AB000, 0x44A412C9, "SIDE", "SIDE"),
        (1536, 2048, false, 0x449E7000, 0x44B256F5, "BACK", "BACK"),
        (1536, 2048, false, 0x44A14000, 0x44C1A000, "BACK", "BACK"),
        (1536, 2048, false, 0x44A5F000, 0x44CBD0B2, "BACK", "BACK"),
        (1536, 2048, false, 0x43F78000, 0x44A517A7, "SIDE", "SIDE"),
        (1536, 2048, false, 0x4417E000, 0x44BB82C9, "SIDE", "SIDE"),
        (1536, 2048, false, 0x4448A000, 0x44B56591, "SIDE", "SIDE"),
        (1536, 2048, false, 0x44688000, 0x44C8C217, "SIDE", "SIDE"),
        (1536, 2048, false, 0x44870000, 0x44B15217, "SIDE", "SIDE"),
        (1536, 2048, false, 0x448CA000, 0x443B8592, "FRONT", "FRONT"),
        (1536, 2048, false, 0x448CA000, 0x44A4AF4E, "BACK", "BACK"),
        (1536, 2048, false, 0x44BB8000, 0x44EC6C86, "BACK", "BACK"),
        (1536, 2048, false, 0x41700000, 0x44868591, "SIDE", "SIDE"),
        (1536, 2048, false, 0x4470C000, 0x44A1385A, "SIDE", "SIDE"),
        (1536, 2048, false, 0x44A0E000, 0x450066F5, "BACK", "BACK"),
        (2532, 1170, true, 0x4407FF00, 0x442F3200, "SIDE", "SIDE"),
        (2532, 1170, true, 0x44177340, 0x443F61C0, "SIDE", "SIDE"),
        (2532, 1170, true, 0x4426E780, 0x44508540, "SIDE", "SIDE"),
        (2532, 1170, true, 0x443C8A40, 0x445FC140, "SIDE", "SIDE"),
        (2532, 1170, true, 0x44522D00, 0x444330C0, "SIDE", "SIDE"),
        (2532, 1170, true, 0x4461A140, 0x44563BC0, "SIDE", "SIDE"),
        (2532, 1170, true, 0x4481D080, 0x44311980, "SIDE", "SIDE"),
        (2532, 1170, true, 0x448CA1E0, 0x44405580, "SIDE", "SIDE"),
        (2532, 1170, true, 0x449144C0, 0x44517900, "SIDE", "SIDE"),
        (2532, 1170, true, 0x449A8A80, 0x44639040, "SIDE", "SIDE"),
        (2532, 1170, true, 0x44AB8A60, 0x4438B780, "SIDE", "SIDE"),
        (2532, 1170, true, 0x44AEA1A0, 0x444BC280, "SIDE", "SIDE"),
        (2532, 1170, true, 0x44B65BC0, 0x445DD9C0, "SIDE", "SIDE"),
        (2532, 1170, true, 0x44C44460, 0x442F3200, "FRONT", "FRONT"),
        (2532, 1170, true, 0x44C75BA0, 0x44414940, "SIDE", "SIDE"),
        (2532, 1170, true, 0x44CF15C0, 0x44526CC0, "SIDE", "SIDE"),
        (2532, 1170, true, 0x44D85B80, 0x4460B500, "SIDE", "SIDE"),
        (2532, 1170, true, 0x44E32CE0, 0x4438B780, "SIDE", "SIDE"),
        (2532, 1170, true, 0x44E95B60, 0x444ACEC0, "BACK", "BACK"),
        (2532, 1170, true, 0x44F2A120, 0x44591700, "BACK", "BACK"),
        (2532, 1170, true, 0x44F42CC0, 0x44279400, "SIDE", "SIDE"),
        (2532, 1170, true, 0x44FEFE20, 0x4433F4C0, "SIDE", "SIDE"),
        (2532, 1170, true, 0x45029650, 0x44414940, "BACK", "BACK"),
        (2532, 1170, true, 0x4504E7C0, 0x444F9180, "BACK", "BACK"),
        (2532, 1170, true, 0x4508C4D0, 0x44591700, "BACK", "BACK"),
        (2532, 1170, true, 0x444BFE80, 0x4434E880, "SIDE", "SIDE"),
        (2532, 1170, true, 0x447A5B40, 0x4449DB00, "SIDE", "SIDE"),
        (2532, 1170, true, 0x44A55BE0, 0x44442480, "SIDE", "SIDE"),
        (2532, 1170, true, 0x44BFA180, 0x44563BC0, "SIDE", "SIDE"),
        (2532, 1170, true, 0x44DE8A00, 0x44405580, "SIDE", "SIDE"),
        (2532, 1170, true, 0x44E7CFC0, 0x43E48400, "FRONT", "FRONT"),
        (2532, 1170, true, 0x44E7CFC0, 0x44348700, "BACK", "BACK"),
        (2532, 1170, true, 0x451A8A80, 0x44778F00, "BACK", "BACK"),
        (2532, 1170, true, 0x41C5D000, 0x44185800, "SIDE", "SIDE"),
        (2532, 1170, true, 0x44C66E40, 0x44314A40, "SIDE", "SIDE"),
        (2532, 1170, true, 0x450498A0, 0x44854D00, "BACK", "BACK"),
        (2048, 1536, true, 0x43DC0000, 0x44660000, "SIDE", "SIDE"),
        (2048, 1536, true, 0x43F50000, 0x447B4000, "SIDE", "SIDE"),
        (2048, 1536, true, 0x44070000, 0x4488E000, "SIDE", "SIDE"),
        (2048, 1536, true, 0x44188000, 0x4492E000, "SIDE", "SIDE"),
        (2048, 1536, true, 0x442A0000, 0x44802000, "SIDE", "SIDE"),
        (2048, 1536, true, 0x44368000, 0x448CA000, "SIDE", "SIDE"),
        (2048, 1536, true, 0x44520000, 0x44688000, "SIDE", "SIDE"),
        (2048, 1536, true, 0x44638000, 0x447C8000, "SIDE", "SIDE"),
        (2048, 1536, true, 0x446B0000, 0x44898000, "SIDE", "SIDE"),
        (2048, 1536, true, 0x447A0000, 0x44956000, "SIDE", "SIDE"),
        (2048, 1536, true, 0x448AC000, 0x44728000, "SIDE", "SIDE"),
        (2048, 1536, true, 0x448D4000, 0x4485C000, "SIDE", "SIDE"),
        (2048, 1536, true, 0x44938000, 0x4491A000, "SIDE", "SIDE"),
        (2048, 1536, true, 0x449EC000, 0x44660000, "FRONT", "FRONT"),
        (2048, 1536, true, 0x44A14000, 0x447DC000, "SIDE", "SIDE"),
        (2048, 1536, true, 0x44A78000, 0x448A2000, "SIDE", "SIDE"),
        (2048, 1536, true, 0x44AF0000, 0x44938000, "SIDE", "SIDE"),
        (2048, 1536, true, 0x44B7C000, 0x44728000, "SIDE", "SIDE"),
        (2048, 1536, true, 0x44BCC000, 0x44852000, "BACK", "BACK"),
        (2048, 1536, true, 0x44C44000, 0x448E8000, "BACK", "BACK"),
        (2048, 1536, true, 0x44C58000, 0x445C0000, "SIDE", "SIDE"),
        (2048, 1536, true, 0x44CE4000, 0x446C4000, "SIDE", "SIDE"),
        (2048, 1536, true, 0x44D34000, 0x447DC000, "BACK", "BACK"),
        (2048, 1536, true, 0x44D70000, 0x44884000, "BACK", "BACK"),
        (2048, 1536, true, 0x44DD4000, 0x448E8000, "BACK", "BACK"),
        (2048, 1536, true, 0x44250000, 0x446D8000, "SIDE", "SIDE"),
        (2048, 1536, true, 0x444A8000, 0x44848000, "SIDE", "SIDE"),
        (2048, 1536, true, 0x4485C000, 0x4480C000, "SIDE", "SIDE"),
        (2048, 1536, true, 0x449B0000, 0x448CA000, "SIDE", "SIDE"),
        (2048, 1536, true, 0x44B40000, 0x447C8000, "SIDE", "SIDE"),
        (2048, 1536, true, 0x44BB8000, 0x44160000, "FRONT", "FRONT"),
        (2048, 1536, true, 0x44BB8000, 0x446D0000, "BACK", "BACK"),
        (2048, 1536, true, 0x44FA0000, 0x44A28000, "BACK", "BACK"),
        (2048, 1536, true, 0x41A00000, 0x44480000, "SIDE", "SIDE"),
        (2048, 1536, true, 0x44A08000, 0x4468C000, "SIDE", "SIDE"),
        (2048, 1536, true, 0x44D68000, 0x44AF0000, "BACK", "BACK"),
    ]
    static let actionFacings: [(density: Int, ax: UInt32, ay: UInt32, tx: UInt32, ty: UInt32, facing: String)] = [
        (2, 0x43FA0000, 0x44BB8000, 0x43FA0000, 0x44AF0000, "BACK"),
        (2, 0x43FA0000, 0x44BB8000, 0x43FA0000, 0x44C80000, "FRONT"),
        (2, 0x43FA0000, 0x44BB8000, 0x44160000, 0x44BB8000, "SIDE"),
        (2, 0x43FA0000, 0x44BB8000, 0x43C80000, 0x44BA4000, "SIDE"),
        (2, 0x43FA0000, 0x44BB8000, 0x44020000, 0x44BCC000, "FRONT"),
        (2, 0x43FA0000, 0x44BB8000, 0x44020000, 0x44BA4000, "BACK"),
        (2, 0x43FA0000, 0x44BB8000, 0x43FA0000, 0x44B34000, "BACK"),
        (2, 0x43FA0000, 0x44BB8000, 0x43FA0000, 0x44C3C000, "FRONT"),
        (2, 0x43FA0000, 0x44BB8000, 0x44168000, 0x44BB8000, "SIDE"),
        (2, 0x43FA0000, 0x44BB8000, 0x43C70000, 0x44BB8000, "SIDE"),
        (2, 0x43FA0000, 0x44BB8000, 0x43FA0000, 0x44BB8000, "FRONT"),
        (2, 0x43FA0000, 0x44BB8000, 0x440DC000, 0x44B5E000, "BACK"),
        (3, 0x43FA0000, 0x44BB8000, 0x43FA0000, 0x44AF0000, "BACK"),
        (3, 0x43FA0000, 0x44BB8000, 0x43FA0000, 0x44C80000, "FRONT"),
        (3, 0x43FA0000, 0x44BB8000, 0x44160000, 0x44BB8000, "FRONT"),
        (3, 0x43FA0000, 0x44BB8000, 0x43C80000, 0x44BA4000, "BACK"),
        (3, 0x43FA0000, 0x44BB8000, 0x44020000, 0x44BCC000, "FRONT"),
        (3, 0x43FA0000, 0x44BB8000, 0x44020000, 0x44BA4000, "BACK"),
        (3, 0x43FA0000, 0x44BB8000, 0x43FA0000, 0x44B34000, "BACK"),
        (3, 0x43FA0000, 0x44BB8000, 0x43FA0000, 0x44C3C000, "FRONT"),
        (3, 0x43FA0000, 0x44BB8000, 0x44168000, 0x44BB8000, "SIDE"),
        (3, 0x43FA0000, 0x44BB8000, 0x43C70000, 0x44BB8000, "SIDE"),
        (3, 0x43FA0000, 0x44BB8000, 0x43FA0000, 0x44BB8000, "FRONT"),
        (3, 0x43FA0000, 0x44BB8000, 0x440DC000, 0x44B5E000, "BACK"),
    ]
    static let hoopFacings: [(w: Int, h: Int, landscape: Bool, density: Int, footY: UInt32, facing: String)] = [
        (1080, 2400, false, 2, 0x44ACA800, "FRONT"),
        (1080, 2400, false, 2, 0x44B92800, "FRONT"),
        (1080, 2400, false, 2, 0x44BDA800, "FRONT"),
        (1080, 2400, false, 2, 0x44BDB800, "BACK"),
        (1080, 2400, false, 2, 0x44DEA800, "BACK"),
        (1080, 2400, false, 3, 0x44ACA800, "FRONT"),
        (1080, 2400, false, 3, 0x44B92800, "FRONT"),
        (1080, 2400, false, 3, 0x44BFE800, "FRONT"),
        (1080, 2400, false, 3, 0x44BFF800, "BACK"),
        (1080, 2400, false, 3, 0x44DEA800, "BACK"),
        (1170, 2532, false, 2, 0x44B6D700, "FRONT"),
        (1170, 2532, false, 2, 0x44C35700, "FRONT"),
        (1170, 2532, false, 2, 0x44C7D700, "FRONT"),
        (1170, 2532, false, 2, 0x44C7E700, "BACK"),
        (1170, 2532, false, 2, 0x44E8D700, "BACK"),
        (1170, 2532, false, 3, 0x44B6D700, "FRONT"),
        (1170, 2532, false, 3, 0x44C35700, "FRONT"),
        (1170, 2532, false, 3, 0x44CA1700, "FRONT"),
        (1170, 2532, false, 3, 0x44CA2700, "BACK"),
        (1170, 2532, false, 3, 0x44E8D700, "BACK"),
        (828, 1792, false, 2, 0x447B8000, "FRONT"),
        (828, 1792, false, 2, 0x448A4000, "FRONT"),
        (828, 1792, false, 2, 0x448EC000, "FRONT"),
        (828, 1792, false, 2, 0x448ED000, "BACK"),
        (828, 1792, false, 2, 0x44AFC000, "BACK"),
        (828, 1792, false, 3, 0x447B8000, "FRONT"),
        (828, 1792, false, 3, 0x448A4000, "FRONT"),
        (828, 1792, false, 3, 0x44910000, "FRONT"),
        (828, 1792, false, 3, 0x44911000, "BACK"),
        (828, 1792, false, 3, 0x44AFC000, "BACK"),
        (1536, 2048, false, 2, 0x44982F4E, "FRONT"),
        (1536, 2048, false, 2, 0x44A4AF4E, "FRONT"),
        (1536, 2048, false, 2, 0x44A92F4E, "FRONT"),
        (1536, 2048, false, 2, 0x44A93F4E, "BACK"),
        (1536, 2048, false, 2, 0x44CA2F4E, "BACK"),
        (1536, 2048, false, 3, 0x44982F4E, "FRONT"),
        (1536, 2048, false, 3, 0x44A4AF4E, "FRONT"),
        (1536, 2048, false, 3, 0x44AB6F4E, "FRONT"),
        (1536, 2048, false, 3, 0x44AB7F4E, "BACK"),
        (1536, 2048, false, 3, 0x44CA2F4E, "BACK"),
        (2532, 1170, true, 2, 0x441B8700, "FRONT"),
        (2532, 1170, true, 2, 0x44348700, "FRONT"),
        (2532, 1170, true, 2, 0x443D8700, "FRONT"),
        (2532, 1170, true, 2, 0x443DA700, "BACK"),
        (2532, 1170, true, 2, 0x447F8700, "BACK"),
        (2532, 1170, true, 3, 0x441B8700, "FRONT"),
        (2532, 1170, true, 3, 0x44348700, "FRONT"),
        (2532, 1170, true, 3, 0x44420700, "FRONT"),
        (2532, 1170, true, 3, 0x44422700, "BACK"),
        (2532, 1170, true, 3, 0x447F8700, "BACK"),
        (2048, 1536, true, 2, 0x44540000, "FRONT"),
        (2048, 1536, true, 2, 0x446D0000, "FRONT"),
        (2048, 1536, true, 2, 0x44760000, "FRONT"),
        (2048, 1536, true, 2, 0x44762000, "BACK"),
        (2048, 1536, true, 2, 0x449C0000, "BACK"),
        (2048, 1536, true, 3, 0x44540000, "FRONT"),
        (2048, 1536, true, 3, 0x446D0000, "FRONT"),
        (2048, 1536, true, 3, 0x447A8000, "FRONT"),
        (2048, 1536, true, 3, 0x447AA000, "BACK"),
        (2048, 1536, true, 3, 0x449C0000, "BACK"),
    ]
    static let rimShakeAmplitudes: [(density: Int, impact: UInt32, bits: UInt32)] = [
        (2, 0x00000000, 0x400CCCCD),
        (2, 0x42340000, 0x400CCCCD),
        (2, 0x42C80000, 0x400CCCCD),
        (2, 0x43960000, 0x40813B14),
        (2, 0x44020000, 0x40E00000),
        (2, 0x442F0000, 0x4116C4EC),
        (2, 0x447A0000, 0x41300000),
        (2, 0x459C4000, 0x41300000),
        (3, 0x00000000, 0x40533334),
        (3, 0x42340000, 0x40533334),
        (3, 0x42C80000, 0x40533334),
        (3, 0x43960000, 0x40C1D89D),
        (3, 0x44020000, 0x41280000),
        (3, 0x442F0000, 0x41622763),
        (3, 0x447A0000, 0x41840000),
        (3, 0x459C4000, 0x41840000),
    ]
    static let netKicks: [(density: Int, impact: UInt32, hint: UInt32, amplitude: UInt32, direction: UInt32)] = [
        (2, 0x418CCCCD, 0xC0400000, 0x408CCCCD, 0xBF800000),
        (2, 0x418CCCCD, 0xBF000000, 0x408CCCCD, 0x3F800000),
        (2, 0x418CCCCD, 0x00000000, 0x408CCCCD, 0x3F800000),
        (2, 0x418CCCCD, 0x3F000000, 0x408CCCCD, 0x3F800000),
        (2, 0x418CCCCD, 0x3F028F5C, 0x408CCCCD, 0x3F800000),
        (2, 0x418CCCCD, 0x42200000, 0x408CCCCD, 0x3F800000),
        (2, 0x42000000, 0xC0400000, 0x408CCCCD, 0xBF800000),
        (2, 0x42000000, 0xBF000000, 0x408CCCCD, 0x3F800000),
        (2, 0x42000000, 0x00000000, 0x408CCCCD, 0x3F800000),
        (2, 0x42000000, 0x3F000000, 0x408CCCCD, 0x3F800000),
        (2, 0x42000000, 0x3F028F5C, 0x408CCCCD, 0x3F800000),
        (2, 0x42000000, 0x42200000, 0x408CCCCD, 0x3F800000),
        (2, 0x42C80000, 0xC0400000, 0x408CCCCD, 0xBF800000),
        (2, 0x42C80000, 0xBF000000, 0x408CCCCD, 0x3F800000),
        (2, 0x42C80000, 0x00000000, 0x408CCCCD, 0x3F800000),
        (2, 0x42C80000, 0x3F000000, 0x408CCCCD, 0x3F800000),
        (2, 0x42C80000, 0x3F028F5C, 0x408CCCCD, 0x3F800000),
        (2, 0x42C80000, 0x42200000, 0x408CCCCD, 0x3F800000),
        (2, 0x43D20000, 0xC0400000, 0x41800000, 0xBF800000),
        (2, 0x43D20000, 0xBF000000, 0x41800000, 0x3F800000),
        (2, 0x43D20000, 0x00000000, 0x41800000, 0x3F800000),
        (2, 0x43D20000, 0x3F000000, 0x41800000, 0x3F800000),
        (2, 0x43D20000, 0x3F028F5C, 0x41800000, 0x3F800000),
        (2, 0x43D20000, 0x42200000, 0x41800000, 0x3F800000),
        (2, 0x442F0000, 0xC0400000, 0x41C00000, 0xBF800000),
        (2, 0x442F0000, 0xBF000000, 0x41C00000, 0x3F800000),
        (2, 0x442F0000, 0x00000000, 0x41C00000, 0x3F800000),
        (2, 0x442F0000, 0x3F000000, 0x41C00000, 0x3F800000),
        (2, 0x442F0000, 0x3F028F5C, 0x41C00000, 0x3F800000),
        (2, 0x442F0000, 0x42200000, 0x41C00000, 0x3F800000),
        (2, 0x44FA0000, 0xC0400000, 0x41C00000, 0xBF800000),
        (2, 0x44FA0000, 0xBF000000, 0x41C00000, 0x3F800000),
        (2, 0x44FA0000, 0x00000000, 0x41C00000, 0x3F800000),
        (2, 0x44FA0000, 0x3F000000, 0x41C00000, 0x3F800000),
        (2, 0x44FA0000, 0x3F028F5C, 0x41C00000, 0x3F800000),
        (2, 0x44FA0000, 0x42200000, 0x41C00000, 0x3F800000),
        (3, 0x418CCCCD, 0xC0400000, 0x40D33334, 0xBF800000),
        (3, 0x418CCCCD, 0xBF000000, 0x40D33334, 0x3F800000),
        (3, 0x418CCCCD, 0x00000000, 0x40D33334, 0x3F800000),
        (3, 0x418CCCCD, 0x3F000000, 0x40D33334, 0x3F800000),
        (3, 0x418CCCCD, 0x3F028F5C, 0x40D33334, 0x3F800000),
        (3, 0x418CCCCD, 0x42200000, 0x40D33334, 0x3F800000),
        (3, 0x42000000, 0xC0400000, 0x40D33334, 0xBF800000),
        (3, 0x42000000, 0xBF000000, 0x40D33334, 0x3F800000),
        (3, 0x42000000, 0x00000000, 0x40D33334, 0x3F800000),
        (3, 0x42000000, 0x3F000000, 0x40D33334, 0x3F800000),
        (3, 0x42000000, 0x3F028F5C, 0x40D33334, 0x3F800000),
        (3, 0x42000000, 0x42200000, 0x40D33334, 0x3F800000),
        (3, 0x42C80000, 0xC0400000, 0x40D33334, 0xBF800000),
        (3, 0x42C80000, 0xBF000000, 0x40D33334, 0x3F800000),
        (3, 0x42C80000, 0x00000000, 0x40D33334, 0x3F800000),
        (3, 0x42C80000, 0x3F000000, 0x40D33334, 0x3F800000),
        (3, 0x42C80000, 0x3F028F5C, 0x40D33334, 0x3F800000),
        (3, 0x42C80000, 0x42200000, 0x40D33334, 0x3F800000),
        (3, 0x43D20000, 0xC0400000, 0x41C00000, 0xBF800000),
        (3, 0x43D20000, 0xBF000000, 0x41C00000, 0x3F800000),
        (3, 0x43D20000, 0x00000000, 0x41C00000, 0x3F800000),
        (3, 0x43D20000, 0x3F000000, 0x41C00000, 0x3F800000),
        (3, 0x43D20000, 0x3F028F5C, 0x41C00000, 0x3F800000),
        (3, 0x43D20000, 0x42200000, 0x41C00000, 0x3F800000),
        (3, 0x442F0000, 0xC0400000, 0x42100000, 0xBF800000),
        (3, 0x442F0000, 0xBF000000, 0x42100000, 0x3F800000),
        (3, 0x442F0000, 0x00000000, 0x42100000, 0x3F800000),
        (3, 0x442F0000, 0x3F000000, 0x42100000, 0x3F800000),
        (3, 0x442F0000, 0x3F028F5C, 0x42100000, 0x3F800000),
        (3, 0x442F0000, 0x42200000, 0x42100000, 0x3F800000),
        (3, 0x44FA0000, 0xC0400000, 0x42100000, 0xBF800000),
        (3, 0x44FA0000, 0xBF000000, 0x42100000, 0x3F800000),
        (3, 0x44FA0000, 0x00000000, 0x42100000, 0x3F800000),
        (3, 0x44FA0000, 0x3F000000, 0x42100000, 0x3F800000),
        (3, 0x44FA0000, 0x3F028F5C, 0x42100000, 0x3F800000),
        (3, 0x44FA0000, 0x42200000, 0x42100000, 0x3F800000),
    ]
    static let relaxedMakes: [(x: UInt32, y: UInt32, vy: UInt32, px: UInt32, py: UInt32, maxH: UInt32, made: Bool, below: Bool, reject: Bool, result: Bool, madeAfter: Bool)] = [
        (0x443B8000, 0x43AC8000, 0x43960000, 0x443B0000, 0x43A78000, 0x43960000, false, false, false, true, true),
        (0x443B8000, 0x43AC8000, 0x43960000, 0x443B0000, 0x43A78000, 0x43960000, true, false, false, false, true),
        (0x443B8000, 0x43AC8000, 0x43960000, 0x443B0000, 0x43A78000, 0x43960000, false, true, true, false, false),
        (0x443B8000, 0x43AC8000, 0x43960000, 0x443B0000, 0x43A78000, 0x43960000, false, true, false, true, true),
        (0x442F0000, 0x43AC8000, 0x43960000, 0x442C8000, 0x43A78000, 0x43960000, false, false, false, true, true),
        (0x442F0000, 0x43AC8000, 0x43960000, 0x442C8000, 0x43A78000, 0x43960000, true, false, false, false, true),
        (0x442F0000, 0x43AC8000, 0x43960000, 0x442C8000, 0x43A78000, 0x43960000, false, true, true, false, false),
        (0x442F0000, 0x43AC8000, 0x43960000, 0x442C8000, 0x43A78000, 0x43960000, false, true, false, true, true),
        (0x4426C000, 0x43AB0000, 0x43960000, 0x44268000, 0x43A90000, 0x43960000, false, false, false, true, true),
        (0x4426C000, 0x43AB0000, 0x43960000, 0x44268000, 0x43A90000, 0x43960000, true, false, false, false, true),
        (0x4426C000, 0x43AB0000, 0x43960000, 0x44268000, 0x43A90000, 0x43960000, false, true, true, false, false),
        (0x4426C000, 0x43AB0000, 0x43960000, 0x44268000, 0x43A90000, 0x43960000, false, true, false, true, true),
        (0x44268000, 0x43AB0000, 0x43960000, 0x44264000, 0x43A90000, 0x43960000, false, false, false, true, true),
        (0x44268000, 0x43AB0000, 0x43960000, 0x44264000, 0x43A90000, 0x43960000, true, false, false, false, true),
        (0x44268000, 0x43AB0000, 0x43960000, 0x44264000, 0x43A90000, 0x43960000, false, true, true, false, false),
        (0x44268000, 0x43AB0000, 0x43960000, 0x44264000, 0x43A90000, 0x43960000, false, true, false, true, true),
        (0x44520000, 0x43AA8000, 0x43960000, 0x44520000, 0x43A98000, 0x43960000, false, false, false, true, true),
        (0x44520000, 0x43AA8000, 0x43960000, 0x44520000, 0x43A98000, 0x43960000, true, false, false, false, true),
        (0x44520000, 0x43AA8000, 0x43960000, 0x44520000, 0x43A98000, 0x43960000, false, true, true, false, false),
        (0x44520000, 0x43AA8000, 0x43960000, 0x44520000, 0x43A98000, 0x43960000, false, true, false, true, true),
        (0x443B8000, 0x43AC8000, 0x43960000, 0x443B0000, 0x43A78000, 0x439F0000, false, false, false, true, true),
        (0x443B8000, 0x43AC8000, 0x43960000, 0x443B0000, 0x43A78000, 0x439F0000, true, false, false, false, true),
        (0x443B8000, 0x43AC8000, 0x43960000, 0x443B0000, 0x43A78000, 0x439F0000, false, true, true, false, false),
        (0x443B8000, 0x43AC8000, 0x43960000, 0x443B0000, 0x43A78000, 0x439F0000, false, true, false, true, true),
        (0x443B8000, 0x43AC8000, 0x43960000, 0x443B0000, 0x43A78000, 0x439E8000, false, false, false, true, true),
        (0x443B8000, 0x43AC8000, 0x43960000, 0x443B0000, 0x43A78000, 0x439E8000, true, false, false, false, true),
        (0x443B8000, 0x43AC8000, 0x43960000, 0x443B0000, 0x43A78000, 0x439E8000, false, true, true, false, false),
        (0x443B8000, 0x43AC8000, 0x43960000, 0x443B0000, 0x43A78000, 0x439E8000, false, true, false, true, true),
        (0x443B8000, 0x43AC8000, 0xC1200000, 0x443B0000, 0x43A78000, 0x43960000, false, false, false, false, false),
        (0x443B8000, 0x43AC8000, 0xC1200000, 0x443B0000, 0x43A78000, 0x43960000, true, false, false, false, true),
        (0x443B8000, 0x43AC8000, 0xC1200000, 0x443B0000, 0x43A78000, 0x43960000, false, true, true, false, false),
        (0x443B8000, 0x43AC8000, 0xC1200000, 0x443B0000, 0x43A78000, 0x43960000, false, true, false, false, false),
        (0x443B8000, 0x43AA0000, 0x43960000, 0x443B0000, 0x43AA0000, 0x43960000, false, false, false, false, false),
        (0x443B8000, 0x43AA0000, 0x43960000, 0x443B0000, 0x43AA0000, 0x43960000, true, false, false, false, true),
        (0x443B8000, 0x43AA0000, 0x43960000, 0x443B0000, 0x43AA0000, 0x43960000, false, true, true, false, false),
        (0x443B8000, 0x43AA0000, 0x43960000, 0x443B0000, 0x43AA0000, 0x43960000, false, true, false, false, false),
        (0x443B8000, 0x43A98000, 0x43960000, 0x443B0000, 0x43A50000, 0x43960000, false, false, false, false, false),
        (0x443B8000, 0x43A98000, 0x43960000, 0x443B0000, 0x43A50000, 0x43960000, true, false, false, false, true),
        (0x443B8000, 0x43A98000, 0x43960000, 0x443B0000, 0x43A50000, 0x43960000, false, true, true, false, false),
        (0x443B8000, 0x43A98000, 0x43960000, 0x443B0000, 0x43A50000, 0x43960000, false, true, false, false, false),
        (0x442F0000, 0x43C30000, 0x43960000, 0x442F0000, 0x43BE0000, 0x43960000, false, false, false, true, true),
        (0x442F0000, 0x43C30000, 0x43960000, 0x442F0000, 0x43BE0000, 0x43960000, true, false, false, false, true),
        (0x442F0000, 0x43C30000, 0x43960000, 0x442F0000, 0x43BE0000, 0x43960000, false, true, true, false, false),
        (0x442F0000, 0x43C30000, 0x43960000, 0x442F0000, 0x43BE0000, 0x43960000, false, true, false, true, true),
        (0x4428C000, 0x43C30000, 0x43960000, 0x4428C000, 0x43BE0000, 0x43960000, false, false, false, true, true),
        (0x4428C000, 0x43C30000, 0x43960000, 0x4428C000, 0x43BE0000, 0x43960000, true, false, false, false, true),
        (0x4428C000, 0x43C30000, 0x43960000, 0x4428C000, 0x43BE0000, 0x43960000, false, true, true, false, false),
        (0x4428C000, 0x43C30000, 0x43960000, 0x4428C000, 0x43BE0000, 0x43960000, false, true, false, true, true),
        (0x44288000, 0x43C30000, 0x43960000, 0x44288000, 0x43BE0000, 0x43960000, false, false, false, false, false),
        (0x44288000, 0x43C30000, 0x43960000, 0x44288000, 0x43BE0000, 0x43960000, true, false, false, false, true),
        (0x44288000, 0x43C30000, 0x43960000, 0x44288000, 0x43BE0000, 0x43960000, false, true, true, false, false),
        (0x44288000, 0x43C30000, 0x43960000, 0x44288000, 0x43BE0000, 0x43960000, false, true, false, false, false),
        (0x444D0000, 0x43C20000, 0x43960000, 0x444D0000, 0x43C10000, 0x43960000, false, false, false, false, false),
        (0x444D0000, 0x43C20000, 0x43960000, 0x444D0000, 0x43C10000, 0x43960000, true, false, false, false, true),
        (0x444D0000, 0x43C20000, 0x43960000, 0x444D0000, 0x43C10000, 0x43960000, false, true, true, false, false),
        (0x444D0000, 0x43C20000, 0x43960000, 0x444D0000, 0x43C10000, 0x43960000, false, true, false, false, false),
        (0x444D4000, 0x43C20000, 0x43960000, 0x444D4000, 0x43C10000, 0x43960000, false, false, false, false, false),
        (0x444D4000, 0x43C20000, 0x43960000, 0x444D4000, 0x43C10000, 0x43960000, true, false, false, false, true),
        (0x444D4000, 0x43C20000, 0x43960000, 0x444D4000, 0x43C10000, 0x43960000, false, true, true, false, false),
        (0x444D4000, 0x43C20000, 0x43960000, 0x444D4000, 0x43C10000, 0x43960000, false, true, false, false, false),
        (0x443E0000, 0x43AA0002, 0x43960000, 0x442F0000, 0x43A9FFFE, 0x43960000, false, false, false, true, true),
        (0x443E0000, 0x43AA0002, 0x43960000, 0x442F0000, 0x43A9FFFE, 0x43960000, true, false, false, false, true),
        (0x443E0000, 0x43AA0002, 0x43960000, 0x442F0000, 0x43A9FFFE, 0x43960000, false, true, true, false, false),
        (0x443E0000, 0x43AA0002, 0x43960000, 0x442F0000, 0x43A9FFFE, 0x43960000, false, true, false, true, true),
        (0x44160000, 0x44160000, 0x43960000, 0x44480000, 0x43480000, 0x42C80000, false, false, false, true, true),
        (0x44160000, 0x44160000, 0x43960000, 0x44480000, 0x43480000, 0x42C80000, true, false, false, false, true),
        (0x44160000, 0x44160000, 0x43960000, 0x44480000, 0x43480000, 0x42C80000, false, true, true, false, false),
        (0x44160000, 0x44160000, 0x43960000, 0x44480000, 0x43480000, 0x42C80000, false, true, false, true, true),
    ]
    static let reboundVelocities: [(density: Int, vx: UInt32, vy: UInt32, rimHits: Int, boardHits: Int, finish: String, outX: UInt32, outY: UInt32)] = [
        (2, 0x42C80000, 0x43480000, 0, 0, "JUMPER", 0x42B40000, 0x43340000),
        (2, 0x42C80000, 0x43480000, 0, 0, "LAYUP", 0x42B40000, 0x43340000),
        (2, 0x42C80000, 0x43480000, 0, 0, "DUNK", 0x42B40000, 0x43340000),
        (2, 0x42C80000, 0x43480000, 1, 0, "JUMPER", 0x42880000, 0x43100000),
        (2, 0x42C80000, 0x43480000, 1, 0, "LAYUP", 0x425C0000, 0x42F80000),
        (2, 0x42C80000, 0x43480000, 1, 0, "DUNK", 0x425C0000, 0x42F80000),
        (2, 0x42C80000, 0x43480000, 0, 2, "JUMPER", 0x42900000, 0x43180000),
        (2, 0x42C80000, 0x43480000, 0, 2, "LAYUP", 0x42780000, 0x43040000),
        (2, 0x42C80000, 0x43480000, 0, 2, "DUNK", 0x42780000, 0x43040000),
        (2, 0x42C80000, 0x43480000, 3, 1, "JUMPER", 0x42880000, 0x43100000),
        (2, 0x42C80000, 0x43480000, 3, 1, "LAYUP", 0x425C0000, 0x42F80000),
        (2, 0x42C80000, 0x43480000, 3, 1, "DUNK", 0x425C0000, 0x42F80000),
        (2, 0xC4610000, 0x44BB8000, 0, 0, "JUMPER", 0xC4160000, 0x44340000),
        (2, 0xC4610000, 0x44BB8000, 0, 0, "LAYUP", 0xC4160000, 0x44340000),
        (2, 0xC4610000, 0x44BB8000, 0, 0, "DUNK", 0xC4160000, 0x44340000),
        (2, 0xC4610000, 0x44BB8000, 1, 0, "JUMPER", 0xC3D20000, 0x44020000),
        (2, 0xC4610000, 0x44BB8000, 1, 0, "LAYUP", 0xC3D20000, 0x44020000),
        (2, 0xC4610000, 0x44BB8000, 1, 0, "DUNK", 0xC3D20000, 0x44020000),
        (2, 0xC4610000, 0x44BB8000, 0, 2, "JUMPER", 0xC3D20000, 0x44020000),
        (2, 0xC4610000, 0x44BB8000, 0, 2, "LAYUP", 0xC3D20000, 0x44020000),
        (2, 0xC4610000, 0x44BB8000, 0, 2, "DUNK", 0xC3D20000, 0x44020000),
        (2, 0xC4610000, 0x44BB8000, 3, 1, "JUMPER", 0xC3D20000, 0x44020000),
        (2, 0xC4610000, 0x44BB8000, 3, 1, "LAYUP", 0xC3D20000, 0x44020000),
        (2, 0xC4610000, 0x44BB8000, 3, 1, "DUNK", 0xC3D20000, 0x44020000),
        (2, 0x44960000, 0xC4AF0000, 0, 0, "JUMPER", 0x44160000, 0xC4340000),
        (2, 0x44960000, 0xC4AF0000, 0, 0, "LAYUP", 0x44160000, 0xC4340000),
        (2, 0x44960000, 0xC4AF0000, 0, 0, "DUNK", 0x44160000, 0xC4340000),
        (2, 0x44960000, 0xC4AF0000, 1, 0, "JUMPER", 0x43D20000, 0xC4020000),
        (2, 0x44960000, 0xC4AF0000, 1, 0, "LAYUP", 0x43D20000, 0xC4020000),
        (2, 0x44960000, 0xC4AF0000, 1, 0, "DUNK", 0x43D20000, 0xC4020000),
        (2, 0x44960000, 0xC4AF0000, 0, 2, "JUMPER", 0x43D20000, 0xC4020000),
        (2, 0x44960000, 0xC4AF0000, 0, 2, "LAYUP", 0x43D20000, 0xC4020000),
        (2, 0x44960000, 0xC4AF0000, 0, 2, "DUNK", 0x43D20000, 0xC4020000),
        (2, 0x44960000, 0xC4AF0000, 3, 1, "JUMPER", 0x43D20000, 0xC4020000),
        (2, 0x44960000, 0xC4AF0000, 3, 1, "LAYUP", 0x43D20000, 0xC4020000),
        (2, 0x44960000, 0xC4AF0000, 3, 1, "DUNK", 0x43D20000, 0xC4020000),
        (2, 0x43A6A666, 0xC29B6666, 0, 0, "JUMPER", 0x4395FC28, 0xC28BDC28),
        (2, 0x43A6A666, 0xC29B6666, 0, 0, "LAYUP", 0x4395FC28, 0xC28BDC28),
        (2, 0x43A6A666, 0xC29B6666, 0, 0, "DUNK", 0x4395FC28, 0xC28BDC28),
        (2, 0x43A6A666, 0xC29B6666, 1, 0, "JUMPER", 0x4362A4DD, 0xC25FC6A8),
        (2, 0x43A6A666, 0xC29B6666, 1, 0, "LAYUP", 0x433750A4, 0xC240B22D),
        (2, 0x43A6A666, 0xC29B6666, 1, 0, "DUNK", 0x433750A4, 0xC240B22D),
        (2, 0x43A6A666, 0xC29B6666, 0, 2, "JUMPER", 0x436FF9DB, 0xC26C353F),
        (2, 0x43A6A666, 0xC29B6666, 0, 2, "LAYUP", 0x434EA560, 0xC24D20C5),
        (2, 0x43A6A666, 0xC29B6666, 0, 2, "DUNK", 0x434EA560, 0xC24D20C5),
        (2, 0x43A6A666, 0xC29B6666, 3, 1, "JUMPER", 0x4362A4DD, 0xC25FC6A8),
        (2, 0x43A6A666, 0xC29B6666, 3, 1, "LAYUP", 0x433750A4, 0xC240B22D),
        (2, 0x43A6A666, 0xC29B6666, 3, 1, "DUNK", 0x433750A4, 0xC240B22D),
        (3, 0x42C80000, 0x43480000, 0, 0, "JUMPER", 0x42B40000, 0x43340000),
        (3, 0x42C80000, 0x43480000, 0, 0, "LAYUP", 0x42B40000, 0x43340000),
        (3, 0x42C80000, 0x43480000, 0, 0, "DUNK", 0x42B40000, 0x43340000),
        (3, 0x42C80000, 0x43480000, 1, 0, "JUMPER", 0x42880000, 0x43100000),
        (3, 0x42C80000, 0x43480000, 1, 0, "LAYUP", 0x425C0000, 0x42F80000),
        (3, 0x42C80000, 0x43480000, 1, 0, "DUNK", 0x425C0000, 0x42F80000),
        (3, 0x42C80000, 0x43480000, 0, 2, "JUMPER", 0x42900000, 0x43180000),
        (3, 0x42C80000, 0x43480000, 0, 2, "LAYUP", 0x42780000, 0x43040000),
        (3, 0x42C80000, 0x43480000, 0, 2, "DUNK", 0x42780000, 0x43040000),
        (3, 0x42C80000, 0x43480000, 3, 1, "JUMPER", 0x42880000, 0x43100000),
        (3, 0x42C80000, 0x43480000, 3, 1, "LAYUP", 0x425C0000, 0x42F80000),
        (3, 0x42C80000, 0x43480000, 3, 1, "DUNK", 0x425C0000, 0x42F80000),
        (3, 0xC4610000, 0x44BB8000, 0, 0, "JUMPER", 0xC44A8000, 0x44870000),
        (3, 0xC4610000, 0x44BB8000, 0, 0, "LAYUP", 0xC44A8000, 0x44870000),
        (3, 0xC4610000, 0x44BB8000, 0, 0, "DUNK", 0xC44A8000, 0x44870000),
        (3, 0xC4610000, 0x44BB8000, 1, 0, "JUMPER", 0xC4190000, 0x44430000),
        (3, 0xC4610000, 0x44BB8000, 1, 0, "LAYUP", 0xC3F78000, 0x44430000),
        (3, 0xC4610000, 0x44BB8000, 1, 0, "DUNK", 0xC3F78000, 0x44430000),
        (3, 0xC4610000, 0x44BB8000, 0, 2, "JUMPER", 0xC41D8000, 0x44430000),
        (3, 0xC4610000, 0x44BB8000, 0, 2, "LAYUP", 0xC40B8000, 0x44430000),
        (3, 0xC4610000, 0x44BB8000, 0, 2, "DUNK", 0xC40B8000, 0x44430000),
        (3, 0xC4610000, 0x44BB8000, 3, 1, "JUMPER", 0xC4190000, 0x44430000),
        (3, 0xC4610000, 0x44BB8000, 3, 1, "LAYUP", 0xC3F78000, 0x44430000),
        (3, 0xC4610000, 0x44BB8000, 3, 1, "DUNK", 0xC3F78000, 0x44430000),
        (3, 0x44960000, 0xC4AF0000, 0, 0, "JUMPER", 0x44610000, 0xC4870000),
        (3, 0x44960000, 0xC4AF0000, 0, 0, "LAYUP", 0x44610000, 0xC4870000),
        (3, 0x44960000, 0xC4AF0000, 0, 0, "DUNK", 0x44610000, 0xC4870000),
        (3, 0x44960000, 0xC4AF0000, 1, 0, "JUMPER", 0x441D8000, 0xC4430000),
        (3, 0x44960000, 0xC4AF0000, 1, 0, "LAYUP", 0x441D8000, 0xC4430000),
        (3, 0x44960000, 0xC4AF0000, 1, 0, "DUNK", 0x441D8000, 0xC4430000),
        (3, 0x44960000, 0xC4AF0000, 0, 2, "JUMPER", 0x441D8000, 0xC4430000),
        (3, 0x44960000, 0xC4AF0000, 0, 2, "LAYUP", 0x441D8000, 0xC4430000),
        (3, 0x44960000, 0xC4AF0000, 0, 2, "DUNK", 0x441D8000, 0xC4430000),
        (3, 0x44960000, 0xC4AF0000, 3, 1, "JUMPER", 0x441D8000, 0xC4430000),
        (3, 0x44960000, 0xC4AF0000, 3, 1, "LAYUP", 0x441D8000, 0xC4430000),
        (3, 0x44960000, 0xC4AF0000, 3, 1, "DUNK", 0x441D8000, 0xC4430000),
        (3, 0x43A6A666, 0xC29B6666, 0, 0, "JUMPER", 0x4395FC28, 0xC28BDC28),
        (3, 0x43A6A666, 0xC29B6666, 0, 0, "LAYUP", 0x4395FC28, 0xC28BDC28),
        (3, 0x43A6A666, 0xC29B6666, 0, 0, "DUNK", 0x4395FC28, 0xC28BDC28),
        (3, 0x43A6A666, 0xC29B6666, 1, 0, "JUMPER", 0x4362A4DD, 0xC25FC6A8),
        (3, 0x43A6A666, 0xC29B6666, 1, 0, "LAYUP", 0x433750A4, 0xC240B22D),
        (3, 0x43A6A666, 0xC29B6666, 1, 0, "DUNK", 0x433750A4, 0xC240B22D),
        (3, 0x43A6A666, 0xC29B6666, 0, 2, "JUMPER", 0x436FF9DB, 0xC26C353F),
        (3, 0x43A6A666, 0xC29B6666, 0, 2, "LAYUP", 0x434EA560, 0xC24D20C5),
        (3, 0x43A6A666, 0xC29B6666, 0, 2, "DUNK", 0x434EA560, 0xC24D20C5),
        (3, 0x43A6A666, 0xC29B6666, 3, 1, "JUMPER", 0x4362A4DD, 0xC25FC6A8),
        (3, 0x43A6A666, 0xC29B6666, 3, 1, "LAYUP", 0x433750A4, 0xC240B22D),
        (3, 0x43A6A666, 0xC29B6666, 3, 1, "DUNK", 0x433750A4, 0xC240B22D),
    ]
    static let dampings: [(vx: UInt32, vy: UInt32, rim: UInt32, board: UInt32, finish: String, outX: UInt32, outY: UInt32)] = [
        (0x43A0C000, 0xC4239000, 0x00000000, 0x00000000, "JUMPER", 0x43A0C000, 0xC4239000),
        (0x43A0C000, 0xC4239000, 0x00000000, 0x00000000, "LAYUP", 0x43A0C000, 0xC4239000),
        (0x43A0C000, 0xC4239000, 0x00000000, 0x00000000, "DUNK", 0x43A0C000, 0xC4239000),
        (0x43A0C000, 0xC4239000, 0x42480000, 0x00000000, "JUMPER", 0x4380999A, 0xC402D99A),
        (0x43A0C000, 0xC4239000, 0x42480000, 0x00000000, "LAYUP", 0x432D9C29, 0xC3B0A5C3),
        (0x43A0C000, 0xC4239000, 0x42480000, 0x00000000, "DUNK", 0x432D9C29, 0xC3B0A5C3),
        (0x43A0C000, 0xC4239000, 0x00000000, 0x42200000, "JUMPER", 0x4380999A, 0xC40FEF5C),
        (0x43A0C000, 0xC4239000, 0x00000000, 0x42200000, "LAYUP", 0x433A7852, 0xC3D7E70B),
        (0x43A0C000, 0xC4239000, 0x00000000, 0x42200000, "DUNK", 0x433A7852, 0xC3D7E70B),
        (0x43A0C000, 0xC4239000, 0x42480000, 0x42200000, "JUMPER", 0x4380999A, 0xC402D99A),
        (0x43A0C000, 0xC4239000, 0x42480000, 0x42200000, "LAYUP", 0x432D9C29, 0xC3B0A5C3),
        (0x43A0C000, 0xC4239000, 0x42480000, 0x42200000, "DUNK", 0x432D9C29, 0xC3B0A5C3),
        (0xC47A0000, 0x44480000, 0x00000000, 0x00000000, "JUMPER", 0xC47A0000, 0x44480000),
        (0xC47A0000, 0x44480000, 0x00000000, 0x00000000, "LAYUP", 0xC47A0000, 0x44480000),
        (0xC47A0000, 0x44480000, 0x00000000, 0x00000000, "DUNK", 0xC47A0000, 0x44480000),
        (0xC47A0000, 0x44480000, 0x42480000, 0x00000000, "JUMPER", 0xC4480000, 0x44200000),
        (0xC47A0000, 0x44480000, 0x42480000, 0x00000000, "LAYUP", 0xC4070000, 0x43D80001),
        (0xC47A0000, 0x44480000, 0x42480000, 0x00000000, "DUNK", 0xC4070000, 0x43D80001),
        (0xC47A0000, 0x44480000, 0x00000000, 0x42200000, "JUMPER", 0xC4480000, 0x44300000),
        (0xC47A0000, 0x44480000, 0x00000000, 0x42200000, "LAYUP", 0xC4110000, 0x44040000),
        (0xC47A0000, 0x44480000, 0x00000000, 0x42200000, "DUNK", 0xC4110000, 0x44040000),
        (0xC47A0000, 0x44480000, 0x42480000, 0x42200000, "JUMPER", 0xC4480000, 0x44200000),
        (0xC47A0000, 0x44480000, 0x42480000, 0x42200000, "LAYUP", 0xC4070000, 0x43D80001),
        (0xC47A0000, 0x44480000, 0x42480000, 0x42200000, "DUNK", 0xC4070000, 0x43D80001),
    ]
    static let looseReady: [(density: Int, made: Bool, vy: UInt32, rimHits: Int, boardHits: Int, elapsed: UInt32, y: UInt32, ready: Bool)] = [
        (2, true, 0x40A00000, 1, 0, 0x3F800000, 0x44610000, false),
        (2, false, 0xC0A00000, 1, 0, 0x3F800000, 0x44610000, false),
        (2, false, 0x00000000, 0, 0, 0x3F800000, 0x44610000, false),
        (2, false, 0x40A00000, 1, 0, 0x3EF0A3D7, 0x43BF8000, false),
        (2, false, 0x40A00000, 1, 0, 0x3EF0A3D7, 0x43C00000, false),
        (2, false, 0x40A00000, 1, 0, 0x3EF5C28F, 0x43BF8000, false),
        (2, false, 0x40A00000, 1, 0, 0x3EF5C28F, 0x43C00000, true),
        (2, false, 0x40A00000, 0, 1, 0x3EF0A3D7, 0x43BF8000, false),
        (2, false, 0x40A00000, 0, 1, 0x3EF0A3D7, 0x43C00000, false),
        (2, false, 0x40A00000, 0, 1, 0x3EF5C28F, 0x43BF8000, false),
        (2, false, 0x40A00000, 0, 1, 0x3EF5C28F, 0x43C00000, true),
        (2, false, 0x40A00000, 0, 0, 0x3F4F5C29, 0x44160000, false),
        (2, false, 0x40A00000, 0, 0, 0x3F4F5C29, 0x44164000, false),
        (2, false, 0x40A00000, 0, 0, 0x3F51EB85, 0x44160000, false),
        (2, false, 0x40A00000, 0, 0, 0x3F51EB85, 0x44164000, true),
        (3, true, 0x40A00000, 1, 0, 0x3F800000, 0x44610000, false),
        (3, false, 0xC0A00000, 1, 0, 0x3F800000, 0x44610000, false),
        (3, false, 0x00000000, 0, 0, 0x3F800000, 0x44610000, false),
        (3, false, 0x40A00000, 1, 0, 0x3EF0A3D7, 0x43BF8000, false),
        (3, false, 0x40A00000, 1, 0, 0x3EF0A3D7, 0x43C00000, false),
        (3, false, 0x40A00000, 1, 0, 0x3EF5C28F, 0x43BF8000, false),
        (3, false, 0x40A00000, 1, 0, 0x3EF5C28F, 0x43C00000, true),
        (3, false, 0x40A00000, 0, 1, 0x3EF0A3D7, 0x43BF8000, false),
        (3, false, 0x40A00000, 0, 1, 0x3EF0A3D7, 0x43C00000, false),
        (3, false, 0x40A00000, 0, 1, 0x3EF5C28F, 0x43BF8000, false),
        (3, false, 0x40A00000, 0, 1, 0x3EF5C28F, 0x43C00000, true),
        (3, false, 0x40A00000, 0, 0, 0x3F4F5C29, 0x44220000, false),
        (3, false, 0x40A00000, 0, 0, 0x3F4F5C29, 0x44224000, false),
        (3, false, 0x40A00000, 0, 0, 0x3F51EB85, 0x44220000, false),
        (3, false, 0x40A00000, 0, 0, 0x3F51EB85, 0x44224000, true),
    ]
}
