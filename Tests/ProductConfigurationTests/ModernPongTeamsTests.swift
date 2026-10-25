import XCTest
@testable import MinikPlus

/// Android MinikPingPong 739f2f8 (2026-10-13) and 29f5dc7 (2026-10-24): ball assistance, the daily journey (34
/// stages), team play (diagonal serves, solid teammates, Standard/Pro team strokes) and the live doubles lobby.
/// Expected values marked "Android" were produced by the compiled Android classes on the JVM (the 29f5dc7 sources with
/// kotlin-stdlib 2.3.21; scratch harness `_work/pingpong-scratch/team/kt/src/TeamGolden.kt`).
final class ModernPongTeamsTests: XCTestCase {
    private func json(_ w: MPWire) throws -> String {
        let data = try JSONSerialization.data(withJSONObject: w, options: [.sortedKeys])
        return String(decoding: data, as: UTF8.self)
    }
    private func ticks(_ g: MPPlay, _ n: Int) { for _ in 0..<n { g.advance(1.0 / 120) } }

    // MARK: Kotlin Random (bot decisions in doubles)
    func testKotlinNextDoubleMatchesAndroid() {
        let expected: [(Int64, Double, Double)] = [
            (0, 0.54963315022148, 0.8488554755054833),
            (1, 0.1397272444266996, 0.8772473577824259),
            (93, 0.06705008706796756, 0.3812209242261574),
            (-7, 0.11492016174825526, 0.716379680973135),
            (123456789012345, 0.47143816932458094, 0.1026340891850096),
            (3023475, 0.3175142375227138, 0.12462531270520916)
        ]
        for (seed, first, second) in expected {
            var random = MPKotlinRandom(seed: seed)
            XCTAssertEqual(random.nextDouble(), first, "seed \(seed)")
            XCTAssertEqual(random.nextDouble(), second, "seed \(seed)")
        }
    }

    // MARK: ReceptionAssist (Android ReceptionAssistTest)
    func testUnsetPreferencesNeverSlowEitherPlayer() {
        var a = MPReceptionAssist(); a.enabled = true
        for seat in 0...3 { for _ in 0..<120 { XCTAssertEqual(a.advance(1.0 / 120, seat: seat, eta: 0.03), 1.0 / 120) } }
        XCTAssertEqual(a.scale, 1)
    }
    func testContinuousEntryAndExitNeverStopTheGame() {
        var a = MPReceptionAssist(); a.enabled = true; a.slow[0] = true
        var previous = 1.0
        for _ in 0..<120 {
            let dt = a.advance(1.0 / 120, seat: 0, eta: 0.03)
            XCTAssertGreaterThan(dt, 0); XCTAssertLessThanOrEqual(a.scale, previous); XCTAssertLessThan(previous - a.scale, 0.024); previous = a.scale
        }
        XCTAssertTrue((0.45...0.47).contains(a.scale))
        for _ in 0..<240 {
            _ = a.advance(1.0 / 120, seat: nil, eta: nil)
            XCTAssertGreaterThanOrEqual(a.scale, previous); XCTAssertLessThan(a.scale - previous, 0.024); previous = a.scale
        }
        XCTAssertEqual(a.scale, 1, accuracy: 0.0001)
    }
    func testOnlyTheReceivingHumansOwnSettingControlsTheSharedClock() {
        var a = MPReceptionAssist(); a.enabled = true; a.slow[0] = false; a.slow[1] = true
        for _ in 0..<120 { _ = a.advance(1.0 / 120, seat: 0, eta: 0) }; XCTAssertEqual(a.scale, 1)
        for _ in 0..<120 { _ = a.advance(1.0 / 120, seat: 1, eta: 0) }; XCTAssertLessThan(a.scale, 0.47)
        XCTAssertEqual(a.receiver, 1); XCTAssertEqual(a.strength, 1)
        // Zoom can still use the strength when this receiver turns slow motion off.
        a.slow[1] = false
        for _ in 0..<240 { _ = a.advance(1.0 / 120, seat: 1, eta: 0) }
        XCTAssertEqual(a.scale, 1, accuracy: 0.0001); XCTAssertEqual(a.strength, 1)
    }
    func testPeerUsesTheAuthorityScaleRegardlessOfLocalSettings() throws {
        var host = MPReceptionAssist(); host.enabled = true; host.slow[1] = true
        for _ in 0..<90 { _ = host.advance(1.0 / 120, seat: 1, eta: 0.1) }
        var peer = try MPReceptionAssist(wire: host.wire); peer.slow[1] = false
        XCTAssertEqual(peer.advance(1.0 / 120, seat: 0, eta: 0, authority: false), host.scale / 120)
        XCTAssertEqual(peer.scale, host.scale)
    }
    func testMirroredMatchPreservesTheCorrectOwner() throws {
        var a = MPReceptionAssist(); a.enabled = true; a.slow[0] = false; a.slow[1] = true
        _ = a.advance(0.02, seat: 1, eta: 0.1)
        let b = try MPReceptionAssist(wire: MPReceptionAssist.reflected(a.wire))
        XCTAssertEqual(b.receiver, 0); XCTAssertEqual(b.slow[1], false); XCTAssertEqual(b.slow[0], true); XCTAssertEqual(b.scale, a.scale)
        XCTAssertEqual(try MPReceptionAssist(wire: MPReceptionAssist.reflected(MPReceptionAssist.reflected(a.wire))), a)
        XCTAssertEqual(a.reflected.reflected, a)
    }
    func testOldSnapshotsPlayAtNormalSpeedAndInvalidStatesAreRejected() throws {
        let a = try MPReceptionAssist(wire: [:]); XCTAssertFalse(a.enabled); XCTAssertEqual(a.scale, 1)
        for value in [Double.nan, .infinity, 0.1, 1.2] { XCTAssertThrowsError(try MPReceptionAssist(wire: ["scale": value])) }
        // A 1v1 checkpoint without "reception" (older Android, or a disabled assistant) still decodes.
        let state = try JSONDecoder().decode(MPState.self, from: JSONEncoder().encode(MPEngine(level: .easy).snapshot()))
        XCTAssertNotNil(state.reception)
        var old = try MPCodec.encode(MPEngine(level: .easy).snapshot()); old["reception"] = nil
        XCTAssertNil(try MPCodec.decode(MPState.self, old).reception)
        // RTDB returns {"0": true, "1": false} as a list.
        var listed = try MPCodec.encode(MPEngine(level: .easy).snapshot())
        listed["reception"] = ["enabled": true, "scale": 0.8, "receiver": 0, "strength": 0.5, "slow": [true, false]] as [String: Any]
        let decoded = try XCTUnwrap(try MPCodec.decode(MPState.self, listed).reception)
        XCTAssertEqual(decoded.slow[0], true); XCTAssertEqual(decoded.slow[1], false); XCTAssertEqual(decoded.scale, 0.8)
    }
    func testAnOutgoingOrWideBallDoesNotInviteReception() {
        XCTAssertNil(MPReceptionAssist.eta(.init(0.1, 0.5), .init(0, 1), .init(0.9, 0.8)))
        XCTAssertLessThan(try XCTUnwrap(MPReceptionAssist.eta(.init(0.5, 0.9), .init(0, 1), .init(0.5, 0.7))), 0)
        var a = MPReceptionAssist(); a.enabled = true; _ = a.advance(0.02, seat: 0, eta: -0.2); XCTAssertEqual(a.strength, 0)
    }
    func testEntireModernSimulationUsesTheSameSlowerDelta() {
        let a = MPEngine(level: .easy, target: 7)
        var f = MPFlight(position: .init(0.5, 0.70), height: 0.22, velocity: .init(0.02, 0.28), lift: 0.2, striker: .minik); f.receiver = true
        var state = a.snapshot(); state.flight = f; state.pointDelay = nil; state.serveDelay = nil
        a.restore(state); a.reception.enabled = true; a.reception.slow[0] = true
        let b = MPEngine(level: .easy, target: 7)
        var plain = a.snapshot(); plain.reception = nil; b.restore(plain)
        for _ in 0..<20 { a.advance(1.0 / 120); b.advance(a.reception.scale / 120) }
        XCTAssertLessThan(a.reception.scale, 1)
        XCTAssertEqual(try XCTUnwrap(b.flight).position.x, try XCTUnwrap(a.flight).position.x, accuracy: 1e-9)
        XCTAssertEqual(try XCTUnwrap(b.flight).position.y, try XCTUnwrap(a.flight).position.y, accuracy: 1e-9)
        XCTAssertEqual(try XCTUnwrap(b.flight).height, try XCTUnwrap(a.flight).height, accuracy: 1e-9)
        XCTAssertEqual(b.childStroke.age, a.childStroke.age, accuracy: 1e-9)
        XCTAssertEqual(a.snapshot().reception?.scale, a.reception.scale)
    }

    // MARK: TeamLineup (Android TeamLineupTest)
    func testOwnerExampleFromEmptyPlacesThroughFourFriendsAndReplacement() {
        let order = [0, 1, 2, 3]; var members: Set<String> = ["host"]
        var lineup = MPTeamLineup.initial(host: "host", count: 4); XCTAssertFalse(lineup.complete)
        lineup = lineup.choose(1, "b:kyra")
        members.insert("john"); lineup = lineup.reconcile(members: members, arrivals: ["host", "john"], order: order)
        XCTAssertEqual(lineup.slots, ["u:host", "b:kyra", "u:john", "empty"])
        lineup = lineup.choose(1, "u:john"); XCTAssertEqual(lineup.slots, ["u:host", "u:john", "empty", "empty"])
        lineup = lineup.choose(2, "b:flare").choose(3, "b:mia"); XCTAssertTrue(lineup.complete)
        members.insert("bini"); lineup = lineup.reconcile(members: members, arrivals: ["host", "john", "bini"], order: order)
        XCTAssertEqual(lineup.slots[2], "u:bini")
        members.insert("gibi"); lineup = lineup.reconcile(members: members, arrivals: ["host", "john", "bini", "gibi"], order: order)
        XCTAssertEqual(lineup.slots[3], "u:gibi")
        lineup = lineup.choose(3, "b:mia")
        // A benched friend is not immediately reinserted.
        XCTAssertEqual(lineup, lineup.reconcile(members: members, arrivals: Array(members), order: order))
        lineup = lineup.choose(3, "u:gibi"); XCTAssertEqual(lineup.humans.count, 4)
        var without = members; without.remove("john")
        lineup = lineup.reconcile(members: without, arrivals: ["host", "bini", "gibi"], order: order)
        XCTAssertEqual(lineup.slots[1], "empty"); XCTAssertFalse(lineup.complete)
        lineup = lineup.reconcile(members: members, arrivals: Array(members), order: order); XCTAssertEqual(lineup.slots[1], "u:john")
    }
    func testMovingFriendsSwapsWithoutDuplicatingOrDroppingTheHost() {
        let l = MPTeamLineup(slots: ["u:host", "u:a", "u:b", "b:mia"], seen: ["host", "a", "b"])
        XCTAssertEqual(l.choose(0, "u:b").slots, ["u:b", "u:a", "u:host", "b:mia"])
        let benched = l.choose(0, "b:kyra"); XCTAssertNil(benched.humans["host"])
        let restored = benched.choose(2, "u:host")
        XCTAssertEqual(restored.slots, ["b:kyra", "u:a", "u:host", "b:mia"])
        XCTAssertEqual(restored.choose(0, "u:b").slots, ["u:b", "u:a", "u:host", "b:mia"])
        XCTAssertEqual(l.choose(0, "empty").slots[0], "empty")
    }
    func testLineupFillsTheFirstPlacesAndSurvivesTheWire() {
        let four = MPTeamLineup.initial(host: "host", count: 4).reconcile(members: ["host", "a", "b"], arrivals: ["a", "b"], order: [0, 2, 1, 3])
        XCTAssertEqual(four.slots, ["u:host", "u:b", "u:a", "empty"])
        let three = MPTeamLineup.initial(host: "host", count: 3).reconcile(members: ["host", "a"], arrivals: ["a"], order: [0, 2, 1])
        XCTAssertEqual(three, MPTeamLineup.read(three.wire, count: 3))
        XCTAssertTrue(three.choose(1, "b:flare").complete)
        // RTDB returns dense slot keys as a list.
        XCTAssertEqual(MPTeamLineup.read(["slots": ["u:host", "b:kyra", "empty", "b:mia"], "seen": ["host": true]] as [String: Any], count: 4)?.slots, ["u:host", "b:kyra", "empty", "b:mia"])
    }
    func testConcurrentArrivalAlwaysReconcilesAgainstTheLatestChoice() {
        let l = MPTeamLineup.initial(host: "host", count: 4).choose(1, "b:kyra")
        let result = l.choose(2, "b:flare").reconcile(members: ["host", "a"], arrivals: ["a"], order: [0, 1, 2, 3])
        XCTAssertEqual(result.slots, ["u:host", "b:kyra", "b:flare", "u:a"])
        XCTAssertEqual(result, result.reconcile(members: ["host", "a"], arrivals: ["a"], order: [0, 1, 2, 3]))
    }

    // MARK: PongTeamAuthority (Android PongTeamAuthorityTest; 22f756e stroke and control inputs)
    private func authority() throws -> MPTeamAuthority {
        let g = MPPlay(humanSeats: [0, 2]); g.start(); ticks(g, 150)
        return try MPTeamAuthority(game: g, seats: ["host": 0, "guest": 2])
    }
    func testInputsCannotControlAnotherSeatOrSupplyScores() throws {
        let a = try authority(); let before = a.game.human.goal
        XCTAssertFalse(a.receive("outsider", sequence: 1, kind: "move", x: 0.2, y: 0.2)); XCTAssertFalse(a.receive("guest", sequence: 1, kind: "score", x: 0.2, y: 0.2))
        XCTAssertFalse(a.receive("guest", sequence: 1, kind: "move", x: .nan, y: 0.2)); XCTAssertFalse(a.receive("guest", sequence: 1, kind: "move", x: 200, y: 0.2))
        XCTAssertTrue(a.receive("guest", sequence: 1, kind: "move", x: 0.2, y: 0.2)); XCTAssertEqual(a.game.human.goal, before)
        XCTAssertEqual(a.game.actors[2].goal, MPPoint(0.2, 0.12))
    }
    func testStrokeAndControlInputsAreBoundedLikeTheRules() throws {
        let a = try authority()
        XCTAssertFalse(a.receive("guest", sequence: 2, kind: "stroke", x: 0.5, y: 0.5), "A stroke needs its gesture")
        XCTAssertFalse(a.receive("guest", sequence: 2, kind: "control", x: 0.5, y: 0.5, control: 2))
        XCTAssertFalse(a.receive("guest", sequence: 2, kind: "stroke", x: 0.5, y: 0.5, stroke: MPPongStroke(aim: 2, power: 0.5)))
        XCTAssertTrue(a.receive("guest", sequence: 2, kind: "control", x: 0.5, y: 0.5, control: 3)); XCTAssertEqual(a.game.controls[2], 3)
        XCTAssertEqual(a.game.controls[0], 0)
        XCTAssertTrue(a.receive("guest", sequence: 3, kind: "stroke", x: 0.5, y: 0.5, control: 1, stroke: MPPongStroke(aim: 0.2, power: 0.6))); XCTAssertEqual(a.game.controls[2], 1)
        XCTAssertEqual(MPPlayWire.int(a.checkpoint(), "spinControls"), 1)
    }
    func testReplayedAndOutOfOrderInputsAreIgnoredAfterReconnect() throws {
        let a = try authority(); XCTAssertTrue(a.receive("host", sequence: 2, kind: "tap", x: 0.5, y: 0.25))
        let wire = try MPJSON.decode(try XCTUnwrap(MPJSON.encode(a.checkpoint())))
        let restored = try MPTeamAuthority.restore(wire, expectedSeats: a.seats)
        restored.game.start()
        XCTAssertFalse(restored.receive("host", sequence: 2, kind: "tap", x: 0.5, y: 0.25)); XCTAssertFalse(restored.receive("host", sequence: 1, kind: "tap", x: 0.5, y: 0.25))
        XCTAssertTrue(restored.receive("host", sequence: 3, kind: "move", x: 0.8, y: 0.8)); XCTAssertEqual(restored.game.human.contacts, 1)
    }
    func testPausedMatchConsumesNoInputAndTheRosterCannotChangeOnResume() throws {
        let a = try authority(); a.game.paused = true; XCTAssertFalse(a.receive("guest", sequence: 3, kind: "move", x: 0.2, y: 0.2))
        a.game.paused = false; XCTAssertTrue(a.receive("guest", sequence: 3, kind: "move", x: 0.2, y: 0.2))
        XCTAssertThrowsError(try MPTeamAuthority.restore(a.checkpoint(), expectedSeats: ["host": 0, "guest": 1]))
    }

    // MARK: Rally ending (Android PongRallyEndingTest; bcee181 out position)
    func testScoredBallContinuesWithoutScoringAgainAndSurvivesReconnect() throws {
        let g = MPPlay(); g.start(); ticks(g, 150)
        XCTAssertTrue(g.waitingServe); g.tap(.init(0.5, 0.12))
        var count = 0; while g.points[0] + g.points[1] == 0 && count < 3000 { g.advance(1.0 / 120); count += 1 }
        XCTAssertEqual(g.points[0] + g.points[1], 1); XCTAssertNotNil(g.ending); XCTAssertNil(g.flight)
        let other = try MPPlay.restore(g.save()); other.start(); XCTAssertEqual(try json(g.save()), try json(other.save()))
        let at = try XCTUnwrap(g.ending).position
        for _ in 0..<60 { g.advance(1.0 / 120); other.advance(1.0 / 120) }
        XCTAssertNotEqual(at, try XCTUnwrap(g.ending).position); XCTAssertEqual(g.points[0] + g.points[1], 1)
        XCTAssertEqual(try json(g.save()), try json(other.save())); XCTAssertFalse(g.waitingServe)
    }
    func testSecondBounceRemainsVisibleAndOutBallsFallBesideTheTable() throws {
        var tail = MPRallyEnding.from(MPFlight(position: .init(0.5, 0.2), height: 0, velocity: .init(0, -0.3), lift: -0.9, striker: .child), .init(winner: .child, fault: .secondBounce))
        tail.advance(0.1, gravity: 1); XCTAssertGreaterThan(tail.height, 0); XCTAssertLessThan(tail.position.y, 0.2)
        XCTAssertEqual(tail.message(false), "Second bounce · Your team's point")
        var out = MPRallyEnding.from(MPFlight(position: .init(1.01, 0.2), height: 0.05, velocity: .init(0.4, 0), lift: -0.1, striker: .child), .init(winner: .minik, fault: .leftTable))
        for _ in 0..<60 { out.advance(1.0 / 120, gravity: 1) }
        XCTAssertLessThan(out.height, 0); XCTAssertGreaterThan(out.position.x, 1.01)
        // The red cross stays where the ball left; the reconnecting phone keeps it.
        XCTAssertEqual(out.outAt, MPPoint(1.01, 0.2)); XCTAssertEqual(out.message(false), "Out — no bounce on the other side · Other team's point")
        XCTAssertEqual(out.message(true), "הכדור יצא לפני שנחת בצד היריב · נקודה לקבוצה היריבה")
        let read = try MPRallyEnding.read(out.wire); XCTAssertEqual(read.outAt, out.outAt); XCTAssertEqual(read.position, out.position)
        var legacy = out.wire; legacy["outX"] = nil; legacy["outY"] = nil; XCTAssertEqual(try MPRallyEnding.read(legacy).outAt, out.position)
        var net = MPRallyEnding.from(MPFlight(position: .init(0.5, 0.5), height: 0.05, velocity: .init(0.1, -0.5), lift: -0.2, striker: .child), .init(winner: .minik, fault: .net))
        net.advance(0.1, gravity: 1); XCTAssertGreaterThan(net.position.y, 0.5)
    }

    // MARK: Journey and doubles rules (Android PongJourneyTest, PongHumanSeatsTest, PongLaneTest)
    func testStageIdsAndGoalsMatchAndroid() {
        XCTAssertEqual(MPJourney.count, 34); XCTAssertEqual(Set(MPJourney.stages.map(\.id)).count, 34)
        XCTAssertEqual(MPStage("x", "x", "x", .returning, 15).goal(1), 18); XCTAssertEqual(MPStage("x", "x", "x", .returning, 15).goal(2), 20)
        XCTAssertEqual(MPJourney.stage(-1).id, "standard_pace"); XCTAssertEqual(MPJourney.stage(35).id, "return")
        XCTAssertEqual(Array(MPJourney.stages.suffix(4).map(\.id)), ["topspin", "sidespin", "standard_swipe", "standard_pace"])
        // Android: a 30-stage save keeps its cycle and stage.
        XCTAssertEqual(MPJourney.migrateStep(29, 30), 29); XCTAssertEqual(MPJourney.migrateStep(30, 30), 34); XCTAssertEqual(MPJourney.migrateStep(31, 30), 35)
        XCTAssertEqual(MPJourney.migrateStep(65, 30), 73); XCTAssertEqual(MPJourney.migrateStep(-1, 30), -1); XCTAssertEqual(MPJourney.migrateStep(40, 34), 40)
        XCTAssertEqual(MPJourney.stage(30).controlDescription(false), "Pro controls: curve your swipe to spin the ball.")
        XCTAssertEqual(MPJourney.stage(15).controlDescription(true), "שליטה רגילה: גוררים כדי לזוז, ומחליקים או מקישים כשהכדור מתקרב.")
        XCTAssertEqual(MPJourney.stage(0).controlDescription(false), "Guided serving practice: tap the target to serve.")
        XCTAssertEqual(MPPlay(step: 30).controls, [3, 3]); XCTAssertEqual(MPPlay(step: 32).controls, [0, 0])
    }
    /// EdgeDailyReviewTest.completedJourneysAdvanceControlsAndSaveStableStageIds (Android c9f5fa6).
    func testCompletedJourneysAdvanceControlsAndKeepStableStageIds() {
        var step = 0
        for (cycle, size) in [30, 30, 32, 34].enumerated() {
            XCTAssertEqual(MPJourney.cycleControl(step), [4, 1, 0, 3][cycle])
            for _ in 0..<size { XCTAssertEqual(step / MPJourney.count, cycle); step = MPJourney.nextStep(step) }
        }
        XCTAssertEqual(step / MPJourney.count, 4)
        XCTAssertEqual(MPJourney.control(30), 3); XCTAssertEqual(MPJourney.control(32), 0); XCTAssertEqual(MPJourney.control(MPJourney.count * 3 + 32), 3)
        XCTAssertEqual(MPPlay(step: 0).controls[0], 4); XCTAssertEqual(MPPlay(step: MPJourney.count + 1).controls[0], 1)
    }
    /// EdgeDailyReviewTest.missedPracticeNeverLocksBehindRetry.
    func testMissedPracticeNeverLocksBehindRetry() throws {
        let g = MPPlay(step: 0); g.start()
        for n in 0..<5 {
            for _ in 0..<400 where !g.waitingServe { g.advance(1.0 / 120) }
            XCTAssertTrue(g.waitingServe); g.tap(.init(0.08, 0.42))
            for _ in 0..<800 where g.mistakes == n { g.advance(1.0 / 120) }
            XCTAssertEqual(g.mistakes, n + 1); XCTAssertFalse(g.ended)
        }
        XCTAssertEqual(try json(g.save()), try json(try MPPlay.restore(g.save()).save()))
    }
    func testOldSavedStepsMigrateOnRestore() throws {
        let e = MPPlay(step: 31); var w = e.save(); w["step"] = 31; w["catalogSize"] = nil
        XCTAssertEqual(try MPPlay.restore(w).step, 35)
        w["catalogSize"] = 34; XCTAssertEqual(try MPPlay.restore(w).step, 31)
    }
    func testPaintMeasuresAreaAndReplacesOwnership() {
        var p = MPPaint(); p.paint(.init(0.5, 0.25), 0); let once = p.coverage(0)
        for _ in 0..<30 { p.paint(.init(0.5, 0.25), 0) }
        XCTAssertEqual(once, p.coverage(0)); p.paint(.init(0.5, 0.25), 1); XCTAssertEqual(p.coverage(0), 0)
    }
    func testIdleCannotWinAndPausedInputDoesNothing() throws {
        // Android c9f5fa6: practice continues after misses (no three-miss retry).
        let e = MPPlay(step: 1); e.start(); ticks(e, 120 * 35); XCTAssertFalse(e.ended); XCTAssertFalse(e.won); XCTAssertEqual(e.successes, 0)
        let p = MPPlay(step: 0); p.start(); p.paused = true; let before = try json(p.save())
        p.tap(.init(0.5, 0.25)); p.move(.init(0.9, 0.9)); p.advance(1); XCTAssertEqual(before, try json(p.save()))
    }
    func testSaveRestoresMidFlightWithoutPayingOrResetting() throws {
        let e = MPPlay(step: 4); e.start(); ticks(e, 260)
        let c = try MPPlay.restore(try MPJSON.decode(try XCTUnwrap(MPJSON.encode(e.save()))))
        XCTAssertEqual(try json(e.save()), try json(c.save()))
        c.start(); for _ in 0..<45 { e.advance(1.0 / 120); c.advance(1.0 / 120) }
        XCTAssertEqual(try json(e.save()), try json(c.save()))
    }
    func testOnlyTheAssignedHumanCanServeAndMoveTheirSeat() {
        let e = MPPlay(humanSeats: [0, 2]); e.start(); ticks(e, 150)
        XCTAssertTrue(e.waitingServe); XCTAssertFalse(e.tapSeat(2, .init(0.5, 0.75))); XCTAssertNil(e.flight)
        let bot = e.actors[1].goal; e.moveSeat(1, .init(0.1, 0.8)); XCTAssertEqual(bot, e.actors[1].goal)
        e.moveSeat(2, .init(0.2, 0.9)); XCTAssertEqual(e.actors[2].goal.y, 0.12)
        XCTAssertTrue(e.tapSeat(0, .init(0.5, 0.25))); XCTAssertEqual(e.actors[0].contacts, 1)
    }
    func testFarSideHumanWaitsForTheirOwnServe() {
        let e = MPPlay(humanSeats: [0, 2]); e.server = 1; e.start(); ticks(e, 150)
        XCTAssertTrue(e.waitingServe); XCTAssertFalse(e.tapSeat(0, .init(0.5, 0.25)))
        XCTAssertTrue(e.tapSeat(2, .init(0.5, 0.75))); XCTAssertEqual(e.flight?.striker, .minik); XCTAssertEqual(e.actors[2].contacts, 1)
    }
    func testHumanTeammatesHaveIndependentAimsAndARestorableSave() throws {
        let e = MPPlay(mode: .free, humanSeats: [0, 1, 2, 3]); e.start(); ticks(e, 150)
        e.tapSeat(0, .init(0.5, 0.25)); e.tapSeat(1, .init(0.2, 0.2)); e.tapSeat(2, .init(0.8, 0.8))
        XCTAssertEqual(e.seatAims[1], MPPoint(0.2, 0.2)); XCTAssertEqual(e.seatAims[2], MPPoint(0.8, 0.8)); XCTAssertEqual(e.aim, MPPoint(0.5, 0.25))
        e.moveSeat(3, .init(.nan, 0.2)); XCTAssertTrue(e.actors[3].goal.x.isFinite)
        let restored = try MPPlay.restore(e.save()); XCTAssertEqual(try json(e.save()), try json(restored.save())); XCTAssertEqual(restored.humanSeats, [0, 1, 2, 3])
    }
    func testLegacySinglePlayerSaveStillRestores() throws {
        let e = MPPlay(step: 4); e.start(); ticks(e, 150)
        var old = e.save(); old["version"] = 1; old["humanSeats"] = nil; old["seatAims"] = nil; old["seatArmed"] = nil
        XCTAssertEqual(try json(e.save()), try json(try MPPlay.restore(old).save()))
    }
    func testLocalBotPartnerServesWhenItIsTheirTurn() {
        let e = MPPlay(); e.nextHitter[0] = 1; e.start(); ticks(e, 150)
        XCTAssertFalse(e.waitingServe); XCTAssertNotNil(e.flight); XCTAssertEqual(e.actors[1].contacts, 1)
    }
    /// Android PongLaneTest (79e1148): free teammates keep their half-lanes; alternating teammates stay solid bodies.
    func testTeammatesCannotCrossEvenWithOpposingRepeatedInputs() {
        for mode in MPTeamMode.allCases {
            let e = MPPlay(mode: mode, humanSeats: [0, 1, 2, 3]); e.start()
            for _ in 0..<600 {
                for i in 0...3 { e.moveSeat(i, .init(i % 2 == 0 ? 1 : 0, 0.5)) }
                e.advance(1.0 / 120)
                for first in [0, 2] {
                    if mode == .free { XCTAssertLessThanOrEqual(e.actors[first].at.x, 0.38); XCTAssertGreaterThanOrEqual(e.actors[first + 1].at.x, 0.62) }
                    XCTAssertGreaterThanOrEqual(e.actors[first + 1].at.x - e.actors[first].at.x, (mode == .alternate ? 0.35 : 0.24) - 1e-9, "Solid teammates retain body separation")
                    XCTAssertEqual(e.actors[first].at.y, e.actors[first + 1].at.y)
                }
            }
        }
    }
    func testNormalTeamGamesNeverAccumulatePaintMarks() {
        let e = MPPlay(); drive(e, seconds: 45); XCTAssertTrue(e.marks.isEmpty)
    }

    // MARK: Team movement (Android PongTeamMovement, TeamCoverage/TeamPolish regression tests)
    func testTeamMovementPrimitivesMatchAndroid() {
        let step = MPTeamMovement.step(.init(0.3, 0.88), .init(0.8, 1.04), 0.85 / 120)
        XCTAssertEqual(step.x, 0.0053663948907702345, accuracy: 1e-15); XCTAssertEqual(step.y, 0.0017172463650464754, accuracy: 1e-15)
        XCTAssertEqual(MPTeamMovement.aroundCorner(.init(1.1, 0.6), .init(0.5, 0.88), 0), MPPoint(1.1, 0.88))
        XCTAssertEqual(MPTeamMovement.aroundCorner(.init(1.1, 0.88), .init(0.5, 0.88), 0), MPPoint(0.5, 0.88))
        XCTAssertEqual(MPTeamMovement.waitingY(0), 1.04, accuracy: 1e-12); XCTAssertEqual(MPTeamMovement.waitingY(1), -0.04, accuracy: 1e-12)
        let (sa, sb) = MPTeamMovement.separate(.init(1.10, 0.80), .init(0.83, 0.88), .init(-0.004, 0.002), .init(0.005, -0.001), wideA: true, wideB: true)
        XCTAssertEqual(sa.x, 0.0010694391396868087, accuracy: 1e-15); XCTAssertEqual(sa.y, 4.979439586113178e-4, accuracy: 1e-15)
        XCTAssertEqual(sb.x, 6.319413098149291e-4, accuracy: 1e-15); XCTAssertEqual(sb.y, 2.942396119066862e-4, accuracy: 1e-15)
    }
    func testSweptCollisionBlocksCrossingButAllowsRetreatAndPreservesSpeed() {
        let expected: [Int: (Double, Double, Double, Double)] = [39: (0.3650902704406461, 0.9561017111221081, 0.6489202623965474, 0.88),
                                                                 79: (0.590019889476936, 1.0109523597347505, 0.6079891300784364, 0.88),
                                                                 119: (0.8, 1.04, 0.32465579674510314, 0.88), 239: (0.8, 1.04, 0.2, 0.88)]
        var a = MPPoint(0.3, 0.88), b = MPPoint(0.65, 0.88)
        for i in 0..<240 {
            let da = MPTeamMovement.step(a, .init(0.8, 1.04), 0.85 / 120), db = MPTeamMovement.step(b, .init(0.2, 0.88), 0.85 / 120)
            let (sa, sb) = MPTeamMovement.separate(a, b, da, db)
            a = .init(a.x + sa.x, a.y + sa.y); b = .init(b.x + sb.x, b.y + sb.y)
            XCTAssertGreaterThanOrEqual(MPTeamMovement.distance(a, b), 0.35 - 1e-8)
            if let e = expected[i] {
                XCTAssertEqual(a.x, e.0, accuracy: 1e-9, "\(i)"); XCTAssertEqual(a.y, e.1, accuracy: 1e-9, "\(i)")
                XCTAssertEqual(b.x, e.2, accuracy: 1e-9, "\(i)"); XCTAssertEqual(b.y, e.3, accuracy: 1e-9, "\(i)")
            }
        }
        XCTAssertEqual(b.x, 0.2, accuracy: 0.001); XCTAssertEqual(a.x, 0.8, accuracy: 0.001)
    }
    func testCollisionKeepsSolidBodiesInsideTheFloorCorridor() {
        var random = SystemRandomNumberGenerator()
        for team in 0...1 {
            for n in 0..<20_000 {
                let low = team == 0 ? 0.88 : MPTeamMovement.waitingY(1), high = team == 0 ? MPTeamMovement.waitingY(0) : 0.12
                let a = MPPoint(Double.random(in: 0.06..<0.94, using: &random), n % 3 == 0 ? low : Double.random(in: low..<high, using: &random))
                let angle = Double.random(in: 0..<1, using: &random) * 2 * .pi
                let b = MPPoint(a.x + cos(angle) * 0.350000001, a.y + sin(angle) * 0.130000001)
                guard (0.06...0.94).contains(b.x), (low...high).contains(b.y) else { continue }
                func next(_ at: MPPoint) -> MPPoint { MPTeamMovement.step(at, .init(Double.random(in: 0.06..<0.94, using: &random), Double.random(in: low..<high, using: &random)), 0.007) }
                let da = next(a), db = next(b), (sa, sb) = MPTeamMovement.separate(a, b, da, db)
                let aa = MPPoint(a.x + sa.x, a.y + sa.y), bb = MPPoint(b.x + sb.x, b.y + sb.y)
                XCTAssertGreaterThanOrEqual(MPTeamMovement.distance(aa, bb), 0.35 - 1e-9, "Bodies remain solid")
                for v in [aa, bb] { XCTAssertTrue((0.06 - 1e-9...0.94 + 1e-9).contains(v.x) && (low - 1e-9...high + 1e-9).contains(v.y), "Never onto table or outside floor: \(v)") }
                XCTAssertLessThanOrEqual(MPTeamMovement.distance(a, aa), 0.007 + 1e-9); XCTAssertLessThanOrEqual(MPTeamMovement.distance(b, bb), 0.007 + 1e-9)
            }
        }
    }
    func testSidelineBotsRetreatAroundTheCornerWithoutCuttingThroughTable() {
        for team in 0...1 {
            for x in [-0.14, 1.14] {
                var at = MPPoint(x, team == 0 ? 0.56 : 0.44)
                let base = team == 0 ? 0.88 : 0.12, goal = MPPoint(0.5, base)
                for _ in 0..<240 {
                    let route = MPTeamMovement.aroundCorner(at, goal, team), d = MPTeamMovement.step(at, route, 0.85 / 120)
                    at = .init(at.x + d.x, at.y + d.y)
                    if (0.02...0.98).contains(at.x) { XCTAssertTrue(team == 0 ? at.y >= base - 0.001 : at.y <= base + 0.001) }
                }
                XCTAssertEqual(at.y, base, accuracy: 0.001); XCTAssertEqual(at.x, 0.5, accuracy: 0.01)
            }
        }
    }
    func testCollisionAtSidelineNeverPushesTheBotIntoTheTable() {
        for team in 0...1 {
            var a = MPPoint(1.10, team == 1 ? 0.20 : 0.80), b = MPPoint(0.83, team == 1 ? 0.12 : 0.88)
            for _ in 0..<240 {
                let ga = MPTeamMovement.aroundCorner(a, .init(0.78, MPTeamMovement.waitingY(team)), team)
                let gb = MPTeamMovement.aroundCorner(b, .init(1.14, team == 1 ? 0.40 : 0.60), team)
                let (sa, sb) = MPTeamMovement.separate(a, b, MPTeamMovement.step(a, ga, 0.006), MPTeamMovement.step(b, gb, 0.006), wideA: true, wideB: true)
                XCTAssertLessThanOrEqual(hypot(sa.x, sa.y * MPTeamMovement.depthScale), 0.006001); XCTAssertLessThanOrEqual(hypot(sb.x, sb.y * MPTeamMovement.depthScale), 0.006001)
                a = .init(a.x + sa.x, a.y + sa.y); b = .init(b.x + sb.x, b.y + sb.y)
                for p in [a, b] where (0.02...0.98).contains(p.x) { XCTAssertTrue(team == 1 ? p.y <= 0.121 : p.y >= 0.879) }
            }
        }
    }
    /// Android TeamCoverageRegressionTest `incoming`: a ball toward `side` whose next hitter is the right-hand teammate.
    private func incoming(_ side: Int, _ x: Double, bot: Bool, seed: Int64 = 1) throws -> MPPlay {
        let g = MPPlay(roster: ["miniko", "minik", "flare", "kyra"], humanSeats: bot ? [] : [0, 1, 2, 3], seed: seed)
        let first = side * 2; g.nextHitter[side] = first + 1
        let y = side == 0 ? 0.88 : 0.12
        g.actors[first].at = .init(x, y); g.actors[first].goal = g.actors[first].at
        g.actors[first + 1].at = .init(0.79, y); g.actors[first + 1].goal = g.actors[first + 1].at
        let striker: MPSide = side == 0 ? .minik : .child
        let from = MPPoint(x, side == 0 ? 0.04 : 0.96), target = MPPoint(x, side == 0 ? 0.75 : 0.25), time = from.distance(target) / 1.10
        let f = MPFlight(position: from, height: 0.25, velocity: .init(0, (target.y - from.y) / time), lift: (0.5 * g.tuning.gravity * time * time - 0.25) / time, striker: striker)
        var w = g.save(); w["flight"] = try MPCodec.encode(f); w["rally"] = 2
        let restored = try MPPlay.restore(w); restored.start(); return restored
    }
    func testRepeatedShotsAtPreviousHitterAreReachableWithoutRemoteContacts() throws {
        for side in 0...1 {
            for x in [0.21, 0.30] {
                var returns = 0
                for seed in Int64(1)...30 {
                    let g = try incoming(side, x, bot: true, seed: seed), i = side * 2 + 1
                    for _ in 0..<220 where g.flight != nil && g.actors[i].contacts == 0 {
                        let before = g.actors[i].at; g.advance(1.0 / 120)
                        XCTAssertLessThanOrEqual(MPTeamMovement.distance(before, g.actors[i].at), 0.91 / 120 + 1e-8, "Bounded physical speed")
                        XCTAssertGreaterThanOrEqual(MPTeamMovement.distance(g.actors[i - 1].at, g.actors[i].at), 0.35 - 1e-8, "Separate in floor space")
                    }
                    XCTAssertEqual(g.actors[i - 1].contacts, 0, "Waiting partner must not steal the hit")
                    if g.actors[i].contacts > 0 {
                        returns += 1; XCTAssertLessThan(abs(g.contactAt.x - g.actors[i].at.x), MPContactGeometry.strikeReach)
                        XCTAssertEqual(g.actors[i].at.y, side == 0 ? 0.88 : 0.12, accuracy: 0.001)
                    }
                }
                XCTAssertGreaterThanOrEqual(returns, 12, "Teammate must have a real chance for side=\(side) x=\(x)")
            }
        }
    }
    func testManualMovementAndOneTapCanCrossInFrontOfManuallyYieldingPartner() throws {
        for side in 0...1 {
            let g = try incoming(side, 0.21, bot: false), i = side * 2 + 1
            g.moveSeat(i - 1, .init(0.22, MPTeamMovement.waitingY(side))); g.moveSeat(i, .init(0.21, side == 0 ? 0.88 : 0.12))
            XCTAssertTrue(g.tapSeat(i, .init(0.5, side == 0 ? 0.25 : 0.75)))
            for _ in 0..<220 where g.actors[i].contacts == 0 { g.advance(1.0 / 120) }
            XCTAssertEqual(g.actors[i].contacts, 1); XCTAssertEqual(g.actors[i - 1].contacts, 0)
        }
    }
    /// Android PongCoverageTest: alternating players can cover across; contacts never push or jitter.
    func testAlternatingPlayersCanCoverAcrossAndContactsDoNotPushOrJitter() {
        let e = MPPlay(humanSeats: [0, 1, 2, 3]); e.start(); e.nextAt = 1000
        // Right teammate yields, letting the left receiver cover the right lane.
        e.moveSeat(1, .init(0.94, 0.88)); e.moveSeat(0, .init(0.90, 0.88))
        var old = e.actors.map(\.at.x)
        for _ in 0..<300 {
            e.advance(1.0 / 120)
            for (i, a) in e.actors.enumerated() { XCTAssertLessThanOrEqual(abs(a.at.x - old[i]), 0.85 / 120 + 1e-9) }
            XCTAssertGreaterThanOrEqual(e.actors[1].at.x - e.actors[0].at.x, 0.35 - 1e-9)
            old = e.actors.map(\.at.x)
        }
        XCTAssertEqual(e.actors[0].at.x, 0.59, accuracy: 1e-8); XCTAssertEqual(e.actors[1].at.x, 0.94, accuracy: 1e-8)
        let settled = e.actors.map(\.at); for _ in 0..<240 { e.advance(1.0 / 120); XCTAssertEqual(settled, e.actors.map(\.at)) }
        // Swap the duty, not the bodies: left player yields and right covers left.
        e.moveSeat(0, .init(0.06, 0.88)); e.moveSeat(1, .init(0.08, 0.88))
        for _ in 0..<300 { e.advance(1.0 / 120); XCTAssertGreaterThanOrEqual(e.actors[1].at.x - e.actors[0].at.x, 0.35 - 1e-9) }
        XCTAssertEqual(e.actors[1].at.x, 0.41, accuracy: 1e-8)
    }
    func testCrossCourtChasesAndPlacementSurviveAuthorityCheckpoint() throws {
        let e = MPPlay(roster: ["miniko", "minik", "flare", "kyra"], humanSeats: [], seed: 4482); e.start()
        var crossed = false, returns = 0, targeted: Set<Int> = []
        for it in 0..<(360 * 60) {
            if e.ended { e.ended = false; e.points = [0, 0] }
            let before = e.lastContact; e.advance(1.0 / 60)
            if e.actors.enumerated().contains(where: { i, a in i % 2 == 0 ? a.at.x > 0.45 : a.at.x < 0.55 }) { crossed = true }
            for first in [0, 2] { XCTAssertGreaterThanOrEqual(MPTeamMovement.distance(e.actors[first].at, e.actors[first + 1].at), 0.35 - 1e-8) }
            if e.lastContact != before && e.lastEvent == "contact", var f = e.flight {
                returns += 1; let receiving = 1 - e.actors[e.hitter].team
                for _ in 0..<500 where !f.resolved && MPContactGeometry.distanceToEnd(receiving, f.position.y) > MPContactGeometry.endInset { _ = f.advance(1.0 / 120, e.tuning) }
                targeted.insert(f.position.x < 0.5 ? 0 : 1)
            }
            if it % 277 == 0 {
                let copy = try MPPlay.restore(e.save()); copy.start()
                for _ in 0..<25 { e.advance(1.0 / 60); copy.advance(1.0 / 60) }
                XCTAssertEqual(try json(e.save()), try json(copy.save()))
            }
        }
        XCTAssertTrue(crossed, "Eligible receivers must actually cross the old half-lane limit")
        XCTAssertGreaterThan(returns, 35, "Exercise real rallies"); XCTAssertEqual(targeted, [0, 1])
    }
    /// Android TeamPolishRegressionTest / PlacementAndHintTest: the serve read and return placement survive a save.
    func testServeReadAndPlacementSurviveSave() throws {
        let g = MPPlay(seed: 18); g.start(); ticks(g, 140); g.tap(.init(0.95, 0.4)); ticks(g, 300)
        let saved = g.save(), restored = try MPPlay.restore(saved).save()
        XCTAssertEqual(try json(["v": saved["serveRead"] as Any]), try json(["v": restored["serveRead"] as Any]))
        XCTAssertEqual(try json(["v": saved["serveReadCount"] as Any]), try json(["v": restored["serveReadCount"] as Any]))
        XCTAssertEqual(g.human.at, MPPoint(0.3, 0.88))
        let p = MPPlay(seed: 42); p.start(); ticks(p, 150); p.tap(.init(0.8, 0.2))
        XCTAssertEqual(try json(["v": p.save()["receivingStartX"] as Any]), try json(["v": try MPPlay.restore(p.save()).save()["receivingStartX"] as Any]))
    }
    /// Android TeamReviewRegressionTest.
    private func withFlight(_ g: MPPlay, _ f: MPFlight) throws -> MPPlay {
        var w = g.save(); w["flight"] = try MPCodec.encode(f); return try MPPlay.restore(w)
    }
    func testOnePreparedTapReturnsAtTheActualBaselineWithoutRepeatedTaps() throws {
        var incoming = MPFlight(position: .init(0.3, 0.70), height: 0.12, velocity: .init(0, 0.8), lift: 1.1, striker: .minik); incoming.receiver = true
        let g = try withFlight(MPPlay(mode: .free, roster: ["miniko", "minik", "flare", "kyra"]), incoming)
        g.start(); g.tap(.init(0.32, 0.25))
        for _ in 0..<120 where g.actors[0].contacts == 0 { g.advance(1.0 / 120) }
        XCTAssertEqual(g.actors[0].contacts, 1)
        XCTAssertGreaterThanOrEqual(g.contactAt.y, MPContactGeometry.baseline(0), "No early mid-table hit")
        XCTAssertEqual(g.flight?.striker, .child)
    }
    func testATapOnTheWrongTeammatesTurnCannotQueueAnAutomaticLaterHit() throws {
        var incoming = MPFlight(position: .init(0.3, 0.70), height: 0.12, velocity: .init(0, 0.8), lift: 1.1, striker: .minik); incoming.receiver = true
        let g = try withFlight(MPPlay(), incoming); g.start(); g.nextHitter[0] = 1
        XCTAssertFalse(g.tapSeat(0, .init(0.4, 0.25))); XCTAssertLessThan(g.seatArmedUntil[0], 0)
    }
    /// Android aca67f4/f0f27c4: a straight team serve into the wrong half is a fault with a 2 s readable notice.
    func testWrongHalfTeamServeIsAFaultWithNotice() {
        let g = MPPlay(roster: ["miniko", "minik", "flare", "kyra"], humanSeats: [0], seed: 7); g.start(); ticks(g, 150)
        XCTAssertTrue(g.waitingServe); XCTAssertTrue(g.tapSeat(0, .init(0.2, 0.25)))
        var n = 0; while g.points[0] + g.points[1] == 0 && n < 2000 { g.advance(1.0 / 120); n += 1 }
        XCTAssertEqual(n, 135); XCTAssertEqual(g.points, [0, 1]); XCTAssertEqual(g.notice, "diagonal-serve-0"); XCTAssertTrue(g.showServeFaultBadge)
        XCTAssertEqual(g.ending?.remaining ?? 0, 2.0, accuracy: 1e-12); XCTAssertEqual(g.ending?.fault, .illegalServe)
        XCTAssertEqual(g.nextAt, 4.374999999999995, accuracy: 1e-9); XCTAssertEqual(g.clock, 2.3749999999999942, accuracy: 1e-9)
        XCTAssertEqual(MPHelpTips.diagonal(he: false, ownPoint: false), "Serve fault: serve diagonally. Other team's point")
    }

    // MARK: Parity with the compiled Android PongPlay (29f5dc7)
    /// Android test helper `teamBounceAim` (a zero denominator gives Kotlin's NaN aim, which the table ignores).
    private func teamBounceAim(_ e: MPPlay) -> MPPoint {
        let from = e.flight?.position ?? MPPoint(e.human.at.x, 0.96)
        let receiver = e.actors[e.alternate ? e.nextHitter[1] : 2]
        if 0.04 - from.y == 0 { return MPPoint(.nan, 0.25) }
        let ratio = ((0.25 - from.y) / (0.04 - from.y)).mpClamp(0, 1)
        return MPPoint(from.x + (receiver.at.x - from.x) * ratio, 0.25)
    }
    /// Android `PongJourneyTest.drive` (29f5dc7: Standard swipes and Pro strokes for the new stages).
    private func drive(_ e: MPPlay, seconds: Int) {
        e.start()
        for _ in 0..<(seconds * 120) where !e.ended {
            if let f = e.flight, f.striker == .minik {
                let offset = e.stage?.skill == .backhand ? 0.12 : e.stage?.skill == .forehand ? -0.12 : 0
                if !e.team || !e.alternate || e.nextHitter[0] == 0 { e.move(.init((f.position.x + offset).mpClamp(0.07, 0.93), 0.84)) } else { e.move(.init(0.9, 0.95)) }
            }
            if e.stage?.standard == true {
                let at = e.flight?.position ?? MPPoint(0.5, 0.96), aim = ((e.target.x - at.x) / 0.8).mpClamp(-0.95, 0.95)
                let speed = ((0.39 - e.target.y) / 0.29).mpClamp(0.02, 1) * 2.5
                e.standardSwipe(.init(aim * speed, -sqrt(1 - aim * aim) * speed))
            } else if e.stage?.spin == true {
                e.strokeSeat(0, MPPongStroke(aim: 0, power: 0.55, top: e.stage?.skill == .topspin ? 0.8 : 0, side: e.stage?.skill == .sidespin ? 0.8 : 0))
            } else { e.tap(e.team ? teamBounceAim(e) : e.target) }
            e.advance(1.0 / 120)
        }
    }
    /// Android: every stage driven by the Android test's player (`PongJourneyTest.drive`, the paint battles'
    /// deliberate player), roster miniko/minik/mia/june, seed 5. Outcome per stage, from the compiled Android classes
    /// (6c8c757: the first cycle plays with Beginner controls, and only the paint rally changes).
    func testEveryJourneyStageMatchesAndroid() {
        let expected: [(won: Bool, successes: Int, mistakes: Int, attempts: Int, clock: Double, contacts: Int, cov0: Double, cov1: Double)] = [
            (true, 8, 0, 8, 22.708333333332686, 8, 0.0, 0.0),
            (true, 6, 0, 6, 27.399999999999086, 6, 0.0, 0.0),
            (true, 0, 0, 19, 90.00000000001769, 20, 0.494140625, 0.314453125),
            (true, 6, 0, 6, 27.399999999999086, 6, 0.0, 0.0),
            (true, 8, 0, 8, 36.541666666665236, 8, 0.0, 0.0),
            (true, 8, 0, 8, 22.708333333332686, 8, 0.0, 0.0),
            (true, 6, 0, 6, 29.608333333332293, 6, 0.0, 0.0),
            (true, 0, 0, 5, 90.00000000001769, 25, 0.798828125, 0.4453125),
            (true, 6, 0, 6, 28.54999999999902, 6, 0.0, 0.0),
            (true, 6, 0, 6, 27.449999999999083, 6, 0.0, 0.0),
            (true, 10, 0, 10, 37.29166666666519, 10, 0.0, 0.0),
            (true, 8, 0, 8, 38.399999999998464, 8, 0.0, 0.0),
            (true, 10, 0, 10, 42.191666666664915, 10, 0.0, 0.0),
            (true, 10, 0, 10, 45.88333333333137, 10, 0.0, 0.0),
            (true, 10, 0, 10, 45.88333333333137, 10, 0.0, 0.0),
            (true, 6, 0, 0, 23.24166666666599, 6, 0.0, 0.0),
            (true, 6, 0, 0, 20.18333333333283, 6, 0.0, 0.0),
            (true, 8, 0, 8, 36.541666666665236, 8, 0.0, 0.0),
            (true, 10, 0, 10, 28.54999999999902, 10, 0.0, 0.0),
            (true, 10, 0, 10, 48.40833333333123, 10, 0.0, 0.0),
            (true, 10, 0, 10, 48.79999999999787, 10, 0.0, 0.0),
            (true, 8, 0, 8, 37.44999999999852, 8, 0.0, 0.0),
            (true, 12, 0, 12, 41.89166666666493, 12, 0.0, 0.0),
            (true, 8, 0, 0, 39.84166666666505, 8, 0.0, 0.0),
            (true, 8, 0, 0, 35.84999999999861, 8, 0.0, 0.0),
            (true, 12, 0, 12, 44.549999999998114, 12, 0.0, 0.0),
            (true, 12, 0, 12, 46.533333333331335, 12, 0.0, 0.0),
            (true, 12, 0, 12, 55.08333333333085, 12, 0.0, 0.0),
            (true, 10, 0, 10, 45.88333333333137, 10, 0.0, 0.0),
            (true, 16, 0, 16, 58.916666666663964, 16, 0.0, 0.0),
            (true, 6, 0, 6, 23.849999999999287, 6, 0.0, 0.0),
            (true, 6, 0, 6, 23.89166666666595, 6, 0.0, 0.0),
            (true, 6, 0, 6, 26.124999999999158, 6, 0.0, 0.0),
            (true, 6, 0, 6, 25.391666666665866, 6, 0.0, 0.0)
        ]
        XCTAssertEqual(expected.count, 34)
        for (step, outcome) in expected.enumerated() {
            let e = MPPlay(step: step, roster: ["miniko", "minik", "mia", "june"], seed: 5)
            if e.stage?.territory == true {
                e.start()
                for _ in 0..<11_000 {
                    if let f = e.flight, f.striker == .minik { e.move(.init(f.position.x.mpClamp(0.07, 0.93), 0.84)) }
                    let k = e.human.contacts; e.tap(.init(0.10 + Double(k * 7 % 9) * 0.10, 0.10 + Double(k * 3 % 5) * 0.07)); e.advance(1.0 / 120)
                }
            } else { drive(e, seconds: 150) }
            let id = e.stage?.id ?? ""
            XCTAssertEqual(e.won, outcome.won, id); XCTAssertTrue(e.ended, id)
            XCTAssertEqual(e.successes, outcome.successes, id); XCTAssertEqual(e.mistakes, outcome.mistakes, id); XCTAssertEqual(e.attempts, outcome.attempts, id)
            XCTAssertEqual(e.clock, outcome.clock, accuracy: 1e-6, id); XCTAssertEqual(e.human.contacts, outcome.contacts, id)
            XCTAssertEqual(e.paint.coverage(0), outcome.cov0, accuracy: 1e-9, id); XCTAssertEqual(e.paint.coverage(1), outcome.cov1, accuracy: 1e-9, id)
        }
    }
    private struct Trace { let clock: Double; let points: [Int]; let rally: Int; let hitter: Int; let attempts: Int; let flight: (Double, Double, Double)?; let actors: [(Double, Double, Int)]; let next: [Int] }
    private func check(_ g: MPPlay, _ t: Trace, _ label: String) {
        XCTAssertEqual(g.clock, t.clock, accuracy: 1e-6, label); XCTAssertEqual(g.points, t.points, label); XCTAssertEqual(g.rally, t.rally, label)
        XCTAssertEqual(g.hitter, t.hitter, label); XCTAssertEqual(g.attempts, t.attempts, label); XCTAssertEqual(g.nextHitter, t.next, label)
        if let expected = t.flight {
            XCTAssertEqual(g.flight?.position.x ?? -9, expected.0, accuracy: 1e-6, label); XCTAssertEqual(g.flight?.position.y ?? -9, expected.1, accuracy: 1e-6, label)
            XCTAssertEqual(g.flight?.height ?? -9, expected.2, accuracy: 1e-6, label)
        } else { XCTAssertNil(g.flight, label) }
        for (i, actor) in t.actors.enumerated() {
            XCTAssertEqual(g.actors[i].at.x, actor.0, accuracy: 1e-6, label); XCTAssertEqual(g.actors[i].at.y, actor.1, accuracy: 1e-6, label)
            XCTAssertEqual(g.actors[i].contacts, actor.2, label)
        }
    }
    /// Android 29f5dc7 (6c8c757 from the eighth second: hand-skill serve edges): house-player-only doubles (miniko and
    /// Minik against Flare and Kyra) from the start.
    func testHousePlayerDoublesMatchAndroid() {
        let cases: [(MPTeamMode, Int64, [Int: Trace])] = [
            (.alternate, 93, [
                1: Trace(clock: 0.9999999999999989, points: [0, 0], rally: 0, hitter: 0, attempts: 0, flight: nil, actors: [(0.3, 0.88, 0), (0.86, 0.88, 0), (0.3, 0.12, 0), (0.86, 0.12, 0)], next: [0, 2]),
                2: Trace(clock: 1.9999999999999953, points: [0, 0], rally: 0, hitter: 0, attempts: 0, flight: (0.5534597272849704, 0.4256258475687334, 0.2239217359972032), actors: [(0.22, 1.04, 1), (0.86, 0.88, 0), (0.22, -0.04000000000000001, 0), (0.7459164921355025, 0.12, 0)], next: [1, 3]),
                3: Trace(clock: 2.999999999999992, points: [0, 0], rally: 1, hitter: 3, attempts: 0, flight: (0.7742820183888031, 0.6302095837280355, 0.14008313180471166), actors: [(0.22, 1.04, 1), (0.7904285487176048, 0.88, 0), (0.22, -0.04000000000000001, 0), (0.78, -0.04000000000000001, 1)], next: [1, 2]),
                4: Trace(clock: 3.9999999999999885, points: [0, 0], rally: 2, hitter: 1, attempts: 0, flight: (0.39231509801585074, 0.3206298789523185, 0.11172252304273733), actors: [(0.22, 1.04, 1), (0.78, 1.04, 1), (0.21963938445846343, 0.12, 0), (0.78, -0.04000000000000001, 1)], next: [0, 2]),
                5: Trace(clock: 5.000000000000038, points: [0, 0], rally: 3, hitter: 2, attempts: 0, flight: (0.6200001666889519, 0.6971446004862003, 0.08737803569431377), actors: [(0.5960640637730953, 0.9290609028136078, 1), (0.78, 1.04, 1), (0.22, -0.04000000000000001, 1), (0.78, -0.04000000000000001, 1)], next: [0, 3]),
                6: Trace(clock: 6.000000000000088, points: [0, 0], rally: 4, hitter: 0, attempts: 0, flight: (0.495607583720848, 0.22891748500445167, 0.5553474241379113), actors: [(0.34835864539852646, 1.0018247591715006, 2), (0.78, 1.04, 1), (0.22, -0.04000000000000001, 1), (0.5588915853457078, 0.12, 1)], next: [1, 3]),
                7: Trace(clock: 7.000000000000138, points: [0, 1], rally: 4, hitter: 0, attempts: 1, flight: nil, actors: [(0.22, 0.88, 2), (0.78, 0.88, 1), (0.22, 0.12, 1), (0.7578457198880766, 0.12, 1)], next: [1, 3]),
                8: Trace(clock: 8.000000000000187, points: [0, 1], rally: 4, hitter: 0, attempts: 1, flight: nil, actors: [(0.22, 0.88, 2), (0.78, 0.88, 1), (0.22, 0.12, 1), (0.7578457198880766, 0.12, 1)], next: [1, 3]),
                9: Trace(clock: 9.00000000000013, points: [0, 1], rally: 0, hitter: 1, attempts: 1, flight: (0.4941952733709317, 0.47046366339510454, 0.2829527088247114), actors: [(0.22, 0.88, 2), (0.78, 1.04, 2), (0.22, 0.12, 1), (0.78, -0.04000000000000001, 1)], next: [0, 2]),
                10: Trace(clock: 10.000000000000073, points: [0, 1], rally: 1, hitter: 2, attempts: 1, flight: (0.22476980613058928, 0.5509681629298268, 0.21379496220904512), actors: [(0.22, 0.88, 2), (0.78, 1.04, 2), (0.22, -0.028720000000000113, 2), (0.78, -0.04000000000000001, 1)], next: [0, 3])
            ]),
            (.free, 11, [
                1: Trace(clock: 0.9999999999999989, points: [0, 0], rally: 0, hitter: 0, attempts: 0, flight: nil, actors: [(0.3, 0.88, 0), (0.86, 0.88, 0), (0.3, 0.12, 0), (0.86, 0.12, 0)], next: [0, 2]),
                2: Trace(clock: 1.9999999999999953, points: [0, 0], rally: 0, hitter: 0, attempts: 0, flight: (0.2632664538788989, 0.36681175093857227, 0.1336522306979107), actors: [(0.14, 0.88, 1), (0.86, 0.88, 0), (0.25360143123759943, 0.12, 0), (0.86, 0.12, 0)], next: [0, 2]),
                3: Trace(clock: 2.999999999999992, points: [0, 0], rally: 1, hitter: 2, attempts: 0, flight: (0.2214960950538334, 0.7487310810741599, 0.0016393366555679904), actors: [(0.21161753007421313, 0.88, 1), (0.86, 0.88, 0), (0.14, 0.12, 1), (0.86, 0.12, 0)], next: [0, 2]),
                4: Trace(clock: 3.9999999999999885, points: [0, 0], rally: 2, hitter: 0, attempts: 0, flight: (0.6542611453019755, 0.20793924515369855, 0.05689240406337308), actors: [(0.14, 0.88, 2), (0.86, 0.88, 0), (0.14, 0.12, 1), (0.7557003071250052, 0.12, 0)], next: [0, 2]),
                5: Trace(clock: 5.000000000000038, points: [0, 0], rally: 3, hitter: 3, attempts: 0, flight: (0.2935816426555508, 0.8039984552303199, 0.07550041121973394), actors: [(0.19927171113117267, 0.88, 2), (0.86, 0.88, 0), (0.14, 0.12, 1), (0.86, 0.12, 1)], next: [0, 2]),
                6: Trace(clock: 6.000000000000088, points: [0, 0], rally: 4, hitter: 0, attempts: 0, flight: (0.6708927261150457, 0.17517882651210442, 0.10190204175507792), actors: [(0.14, 0.88, 3), (0.86, 0.88, 0), (0.14, 0.12, 1), (0.7557845088121422, 0.12, 1)], next: [0, 2]),
                7: Trace(clock: 7.000000000000138, points: [0, 0], rally: 5, hitter: 3, attempts: 0, flight: (0.27473097814138314, 0.835448369534085, 0.11559343952275347), actors: [(0.1992716007812636, 0.88, 3), (0.86, 0.88, 0), (0.14, 0.12, 1), (0.86, 0.12, 2)], next: [0, 2]),
                8: Trace(clock: 8.000000000000187, points: [0, 0], rally: 6, hitter: 0, attempts: 0, flight: (0.6897575542879573, 0.14373740952032038, 0.13845750607964868), actors: [(0.14, 0.88, 4), (0.86, 0.88, 0), (0.14, 0.12, 1), (0.7557845095677045, 0.12, 2)], next: [0, 2]),
                9: Trace(clock: 9.00000000000013, points: [0, 0], rally: 7, hitter: 3, attempts: 0, flight: (0.25586613387729823, 0.8668897768711651, 0.15083254144778027), actors: [(0.19927160078027115, 0.88, 4), (0.86, 0.88, 0), (0.14, 0.12, 1), (0.86, 0.12, 3)], next: [0, 2]),
                10: Trace(clock: 10.000000000000073, points: [0, 0], rally: 8, hitter: 0, attempts: 0, flight: (0.7086223986535216, 0.11229600224412542, 0.17070788944154572), actors: [(0.14, 0.88, 5), (0.86, 0.88, 0), (0.14, 0.12, 1), (0.7557845095677111, 0.12, 3)], next: [0, 2])
            ])
        ]
        for (mode, seed, traces) in cases {
            let g = MPPlay(mode: mode, roster: ["miniko", "minik", "flare", "kyra"], humanSeats: [], seed: seed); g.start()
            for second in 1...10 { ticks(g, 120); if let t = traces[second] { check(g, t, "\(mode) \(seed) t=\(second)") } }
        }
    }
    /// Android 6c8c757: Standard/Starter swipes (strokes 0 and 1), Pro strokes (3) and Beginner assisted returns (4) in
    /// a team match against house players, seed 21.
    func testTeamControlLevelsMatchAndroid() {
        let traces: [Int: (Trace, strokes: Int, standard: Bool)] = [
            0: (Trace(clock: 19.999999999999506, points: [1, 3], rally: 2, hitter: 3, attempts: 4, flight: nil, actors: [(0.3745680994516361, 0.88, 2), (0.78, 0.9742942857142849, 3), (0.2910463114187586, 0.032353717637785585, 3), (0.78, 0.0407857142857143, 3)], next: [0, 2]), strokes: 198, standard: false),
            1: (Trace(clock: 19.999999999999506, points: [1, 3], rally: 2, hitter: 3, attempts: 4, flight: nil, actors: [(0.30645284431309905, 0.88, 2), (0.78, 0.9878885714285708, 3), (0.2763470745734982, 0.017383982954105807, 3), (0.78, 0.02407142857142858, 3)], next: [0, 2]), strokes: 210, standard: false),
            3: (Trace(clock: 19.999999999999506, points: [1, 1], rally: 2, hitter: 3, attempts: 2, flight: (0.6916054533814834, 0.2071461715922675, 0.3154803143817743), actors: [(0.45131120810778486, 0.88, 4), (0.78, 1.04, 4), (0.22, -0.04000000000000001, 4), (0.78, 0.0615000000000001, 4)], next: [0, 2]), strokes: 72, standard: false),
            4: (Trace(clock: 19.999999999999506, points: [1, 1], rally: 1, hitter: 1, attempts: 2, flight: (0.7807141170426217, 0.1736286845363584, 0.08159754462010747), actors: [(0.30264305831018273, 0.88, 4), (0.78, 1.04, 4), (0.22, -0.04000000000000001, 4), (0.78, 0.12, 3)], next: [0, 3]), strokes: 0, standard: false)
        ]
        for control in [0, 1, 3, 4] {
            let g = MPPlay(roster: ["miniko", "minik", "flare", "kyra"], humanSeats: [0], seed: 21, control: control); g.start()
            var strokes = 0
            for _ in 0..<(120 * 20) {
                if let f = g.flight, f.striker == .minik, g.nextHitter[0] == 0 { g.move(.init(f.position.x.mpClamp(0.06, 0.94), 0.88)) }
                if g.waitingServe { g.tap(.init(0.72, 0.25)) }
                else if control == 0 || control == 1 { if g.canPrepareStandard(0) && g.strokeSeat(0, MPPongStroke(aim: 0.2, power: 0.6)) { strokes += 1 } }
                else if control == 3 { if g.mayReceive(0) && g.strokeSeat(0, MPPongStroke(aim: -0.3, power: 0.7, top: 0.6, side: 0)) { strokes += 1 } }
                g.advance(1.0 / 120)
            }
            let expected = traces[control]!
            check(g, expected.0, "control \(control)"); XCTAssertEqual(strokes, expected.strokes, "control \(control)")
            XCTAssertEqual(g.lastHumanStandard, expected.standard, "control \(control)"); XCTAssertEqual(g.controls, Array(repeating: control, count: 4))
        }
    }
    /// Android 739f2f8: an older Android host's snapshot body (no `catalogSize`, `botPlanAt`, strokes…) restores on
    /// iOS: its humans stop where they stand, then it continues as the 29f5dc7 Android classes do.
    func testAndroidDoublesSnapshotRestoresAndContinues() throws {
        let body = #"{"seed":93,"botTried":[false,false,false,false],"botResponses":[0,0,0,0],"botPreviousX":[null,null,null,null],"reception":{"enabled":false,"scale":1.0,"receiver":2,"strength":0.0,"slow":{}},"version":2,"humanSeats":[0,2],"seatAims":[[0.5,0.25],[0.5,0.25],[0.5,0.75],[0.5,0.75]],"seatArmed":[-1.0,-1.0,-1.0,-1.0],"step":-1,"mode":"ALTERNATE","roster":["miniko","minik","flare","kyra"],"open":false,"clock":2.916666666666659,"successes":0,"mistakes":0,"attempts":0,"won":false,"ended":false,"nextAt":1.0,"server":0,"hitter":0,"nextHitter":[1,2],"points":[0,0],"aim":[0.5,0.25],"armedUntil":-1.0,"backhand":false,"contact":1.249999999999998,"contactAt":[0.3,0.96],"contactHeight":0.25,"pending":true,"waiting":false,"rally":0,"paint":[1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0],"painted":[],"ending":null,"marks":[],"flight":{"position":{"x":0.4777688021245456,"y":0.394502786190473},"height":0.8412148061501001,"velocity":{"x":0.060822873701576435,"y":-0.39534867906024695},"lift":-1.6435870514576687,"striker":"CHILD","receiver":false,"resolved":false,"spin":0.0,"serve":null},"actors":[{"x":0.3,"y":0.88,"gx":0.3,"gy":0.88,"swing":0.0,"back":false,"contacts":1},{"x":0.7,"y":0.88,"gx":0.7,"gy":0.88,"swing":0.0,"back":false,"contacts":0},{"x":0.3,"y":0.12,"gx":0.3,"gy":0.12,"swing":0.0,"back":false,"contacts":0},{"x":0.7,"y":0.12,"gx":0.7,"gy":0.12,"swing":0.0,"back":false,"contacts":0}]}"#
        let g = try MPPlay.restore(try MPJSON.decode(body))
        XCTAssertEqual(g.humanSeats, [0, 2]); XCTAssertEqual(g.mode, .alternate); XCTAssertEqual(g.roster, ["miniko", "minik", "flare", "kyra"])
        XCTAssertEqual(g.nextHitter, [1, 2]); XCTAssertEqual(g.reception.receiver, 2); XCTAssertEqual(g.actors[0].contacts, 1)
        XCTAssertEqual(g.actors.map(\.goal), [MPPoint(0.3, 0.88), MPPoint(0.7, 0.88), MPPoint(0.3, 0.12), MPPoint(0.7, 0.12)]); XCTAssertEqual(g.seatArmedUntil, [-1, -1, -1, -1])
        XCTAssertEqual(try json(g.save()), try json(try MPPlay.restore(try MPJSON.decode(try XCTUnwrap(MPJSON.encode(g.save())))).save()))
        g.start()
        ticks(g, 60); check(g, Trace(clock: 3.416666666666657, points: [0, 0], rally: 0, hitter: 0, attempts: 0, flight: (0.5081802389753337, 0.19682844666034907, 0.30973802033812775), actors: [(0.3, 0.88, 1), (0.7, 0.88, 0), (0.3, 0.12, 0), (0.78, -0.04000000000000001, 0)], next: [1, 2]), "android 739f2f8 60")
        // Android 6c8c757: the far serve is no longer called out in the air beyond the end line; it falls to the plane.
        ticks(g, 60); check(g, Trace(clock: 3.9166666666666554, points: [0, 0], rally: 0, hitter: 0, attempts: 0, flight: (0.5385916758261194, -8.458928697744469E-4, 0.8901985367536637), actors: [(0.3, 0.88, 1), (0.7, 0.88, 0), (0.3, 0.12, 0), (0.78, -0.04000000000000001, 0)], next: [1, 2]), "android 739f2f8 120")
        ticks(g, 60); check(g, Trace(clock: 4.416666666666676, points: [0, 0], rally: 0, hitter: 0, attempts: 0, flight: (0.5690031126769052, -0.19852023239989797, 0.5706590531692002), actors: [(0.3, 0.88, 1), (0.7, 0.88, 0), (0.3, 0.12, 0), (0.78, -0.04000000000000001, 0)], next: [1, 2]), "android 739f2f8 180")
    }
    /// Android 29f5dc7: a current Android host's snapshot body (serve read, plans, strokes, controls, arena) restores
    /// on iOS, round-trips, and continues identically.
    func testCurrentAndroidDoublesSnapshotRestoresAndContinues() throws {
        let body = #"{"serveRead":[null,null],"serveReadCount":[0,0],"bounceAt":[0.3,0.94],"bounceTime":1.6416666666666633,"wrongServeHalf":false,"botPlanAt":[0.0,1.9183333333333294,0.0,1.9183333333333294],"catalogSize":34,"lastStroke":null,"controls":[0,0,0,0],"standardStrokes":[null,null,null,null],"strokes":[null,null,null,null],"arena":"","seed":93,"receivingStartX":[0.3,0.86,0.3,0.86],"botTried":[false,false,false,false],"botResponses":[0,0,0,0],"botPreviousX":[null,null,null,null],"reception":{"enabled":false,"scale":1.0,"receiver":-1,"strength":0.0,"slow":{}},"version":2,"humanSeats":[0,2],"seatAims":[[0.72,0.25],[0.5,0.25],[0.5,0.75],[0.5,0.75]],"seatArmed":[-1.0,-1.0,-1.0,-1.0],"step":-1,"mode":"ALTERNATE","roster":["miniko","minik","flare","kyra"],"open":false,"notice":"","clock":1.8333333333333293,"successes":0,"mistakes":0,"attempts":0,"won":false,"ended":false,"nextAt":1.0,"server":0,"hitter":0,"nextHitter":[1,3],"points":[0,0],"aim":[0.72,0.25],"armedUntil":-1.0,"standard":false,"backhand":false,"contact":1.249999999999998,"contactAt":[0.3,0.96],"contactHeight":0.25,"pending":true,"waiting":false,"rally":0,"paint":[1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0],"painted":[],"ending":null,"marks":[],"flight":{"position":{"x":0.39645738013453435,"y":0.7815343040646944},"height":0.2302365079070762,"velocity":{"x":0.49394959955095796,"y":-0.8114886278337167},"lift":0.8275205241329631,"striker":"CHILD","receiver":false,"resolved":false,"spin":0.0,"top":0.0,"angle":0.0,"serve":null},"actors":[{"x":0.3,"y":0.88,"gx":0.3,"gy":0.88,"swing":0.0,"back":false,"contacts":1},{"x":0.86,"y":0.88,"gx":0.86,"gy":0.88,"swing":0.0,"back":false,"contacts":0},{"x":0.3,"y":0.12,"gx":0.3,"gy":0.12,"swing":0.0,"back":false,"contacts":0},{"x":0.86,"y":0.12,"gx":0.86,"gy":0.12,"swing":0.0,"back":false,"contacts":0}]}"#
        let g = try MPPlay.restore(try MPJSON.decode(body))
        XCTAssertEqual(g.humanSeats, [0, 2]); XCTAssertEqual(g.nextHitter, [1, 3]); XCTAssertEqual(g.controls, [0, 0, 0, 0]); XCTAssertEqual(g.arena, "")
        XCTAssertEqual(g.bounceAt, MPPoint(0.3, 0.94))
        XCTAssertEqual(try json(g.save()), try json(try MPPlay.restore(try MPJSON.decode(try XCTUnwrap(MPJSON.encode(g.save())))).save()))
        g.start()
        ticks(g, 60); check(g, Trace(clock: 2.3333333333333277, points: [0, 0], rally: 0, hitter: 0, attempts: 0, flight: (0.6434321799100133, 0.37578999014783737, 0.19399676997355692), actors: [(0.3, 0.88, 1), (0.86, 0.88, 0), (0.3, 0.12, 0), (0.86, 0.12, 0)], next: [1, 3]), "android 29f5dc7 60")
        ticks(g, 60); check(g, Trace(clock: 2.833333333333326, points: [0, 0], rally: 1, hitter: 3, attempts: 0, flight: (0.8433685505421455, 0.12914787261946595, 0.27760227591840564), actors: [(0.3, 0.88, 1), (0.799, 0.88, 0), (0.3, 0.12, 0), (0.8463055854617921, 0.09261117092358359, 1)], next: [1, 2]), "android 29f5dc7 120")
        ticks(g, 60); check(g, Trace(clock: 3.333333333333324, points: [0, 0], rally: 1, hitter: 3, attempts: 0, flight: (0.8081127754575439, 0.678016737033529, 0.09120272484379643), actors: [(0.3, 0.88, 1), (0.789897291663833, 0.88, 0), (0.3, 0.12, 0), (0.78, -0.04000000000000001, 1)], next: [1, 2]), "android 29f5dc7 180")
    }
}
