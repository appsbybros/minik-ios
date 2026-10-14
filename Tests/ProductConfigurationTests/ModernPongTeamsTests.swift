import XCTest
@testable import MinikPlus

/// Android MinikPingPong 739f2f8 (2026-10-13): ball assistance, the daily journey, team play and the live doubles
/// lobby. Expected values marked "Android" were produced by the compiled Android classes (kotlin-classes/release)
/// on the JVM with kotlin-stdlib 1.9.23.
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

    // MARK: PongTeamAuthority (Android PongTeamAuthorityTest)
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

    // MARK: Rally ending (Android PongRallyEndingTest)
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
    func testSecondBounceRemainsVisibleAndOutBallsFallBesideTheTable() {
        var tail = MPRallyEnding.from(MPFlight(position: .init(0.5, 0.2), height: 0, velocity: .init(0, -0.3), lift: -0.9, striker: .child), .init(winner: .child, fault: .secondBounce))
        tail.advance(0.1, gravity: 1); XCTAssertGreaterThan(tail.height, 0); XCTAssertLessThan(tail.position.y, 0.2)
        XCTAssertEqual(tail.message(false), "Second bounce · Your team's point")
        var out = MPRallyEnding.from(MPFlight(position: .init(1.01, 0.2), height: 0.05, velocity: .init(0.4, 0), lift: -0.1, striker: .child), .init(winner: .minik, fault: .leftTable))
        for _ in 0..<60 { out.advance(1.0 / 120, gravity: 1) }
        XCTAssertLessThan(out.height, 0); XCTAssertGreaterThan(out.position.x, 1.01)
        var net = MPRallyEnding.from(MPFlight(position: .init(0.5, 0.5), height: 0.05, velocity: .init(0.1, -0.5), lift: -0.2, striker: .child), .init(winner: .minik, fault: .net))
        net.advance(0.1, gravity: 1); XCTAssertGreaterThan(net.position.y, 0.5)
    }

    // MARK: Journey and doubles rules (Android PongJourneyTest, PongHumanSeatsTest, PongLaneTest)
    func testStageIdsAndGoalsMatchAndroid() {
        XCTAssertEqual(Set(MPJourney.stages.map(\.id)).count, 30)
        XCTAssertEqual(MPStage("x", "x", "x", .returning, 15).goal(1), 18); XCTAssertEqual(MPStage("x", "x", "x", .returning, 15).goal(2), 20)
        XCTAssertEqual(MPJourney.stage(-1).id, "final"); XCTAssertEqual(MPJourney.stage(31).id, "return")
    }
    func testPaintMeasuresAreaAndReplacesOwnership() {
        var p = MPPaint(); p.paint(.init(0.5, 0.25), 0); let once = p.coverage(0)
        for _ in 0..<30 { p.paint(.init(0.5, 0.25), 0) }
        XCTAssertEqual(once, p.coverage(0)); p.paint(.init(0.5, 0.25), 1); XCTAssertEqual(p.coverage(0), 0)
    }
    func testIdleCannotWinAndPausedInputDoesNothing() throws {
        let e = MPPlay(step: 1); e.start(); ticks(e, 120 * 35); XCTAssertTrue(e.ended); XCTAssertFalse(e.won); XCTAssertEqual(e.successes, 0)
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
    func testTeammatesCannotCrossEvenWithOpposingRepeatedInputs() {
        for mode in MPTeamMode.allCases {
            let e = MPPlay(mode: mode, humanSeats: [0, 1, 2, 3]); e.start()
            for _ in 0..<600 {
                for i in 0...3 { e.moveSeat(i, .init(i % 2 == 0 ? 1 : 0, 0.5)) }
                e.advance(1.0 / 120)
                for first in [0, 2] {
                    XCTAssertLessThanOrEqual(e.actors[first].at.x, 0.38); XCTAssertGreaterThanOrEqual(e.actors[first + 1].at.x, 0.62)
                    XCTAssertEqual(e.actors[first].at.y, e.actors[first + 1].at.y)
                }
            }
        }
    }
    func testNormalTeamGamesNeverAccumulatePaintMarks() {
        let e = MPPlay(); drive(e, seconds: 45); XCTAssertTrue(e.marks.isEmpty)
    }

    // MARK: Parity with the compiled Android PongPlay
    /// Android test helper `teamBounceAim` (a zero denominator gives Kotlin's NaN aim, which the table ignores).
    private func teamBounceAim(_ e: MPPlay) -> MPPoint {
        let from = e.flight?.position ?? MPPoint(e.human.at.x, 0.96)
        let receiver = e.actors[e.alternate ? e.nextHitter[1] : 2]
        if 0.04 - from.y == 0 { return MPPoint(.nan, 0.25) }
        let ratio = ((0.25 - from.y) / (0.04 - from.y)).mpClamp(0, 1)
        return MPPoint(from.x + (receiver.at.x - from.x) * ratio, 0.25)
    }
    private func drive(_ e: MPPlay, seconds: Int) {
        e.start()
        for _ in 0..<(seconds * 120) where !e.ended {
            if let f = e.flight, f.striker == .minik {
                let offset = e.stage?.skill == .backhand ? 0.12 : e.stage?.skill == .forehand ? -0.12 : 0
                if !e.team || !e.alternate || e.nextHitter[0] == 0 { e.move(.init((f.position.x + offset).mpClamp(0.07, 0.93), 0.84)) } else { e.move(.init(0.9, 0.95)) }
            }
            e.tap(e.team ? teamBounceAim(e) : e.target); e.advance(1.0 / 120)
        }
    }
    /// Android: every stage driven by the Android test's player (`PongJourneyTest.drive`, the paint battles'
    /// deliberate player), roster miniko/minik/mia/june, seed 5. Outcome per stage, from the compiled Android classes.
    func testEveryJourneyStageMatchesAndroid() {
        let expected: [(won: Bool, successes: Int, mistakes: Int, attempts: Int, clock: Double, contacts: Int, cov0: Double, cov1: Double)] = [
            (true, 8, 0, 8, 22.708333333332686, 8, 0.0, 0.0),
            (true, 6, 0, 6, 27.399999999999086, 6, 0.0, 0.0),
            (true, 0, 0, 19, 90.00000000001769, 20, 0.494140625, 0.314453125),
            (true, 6, 0, 6, 27.399999999999086, 6, 0.0, 0.0),
            (true, 8, 0, 8, 36.541666666665236, 8, 0.0, 0.0),
            (true, 8, 0, 8, 22.708333333332686, 8, 0.0, 0.0),
            (true, 6, 0, 6, 29.608333333332293, 6, 0.0, 0.0),
            (true, 0, 0, 7, 90.00000000001769, 24, 0.80078125, 0.447265625),
            (true, 6, 0, 6, 28.54999999999902, 6, 0.0, 0.0),
            (true, 6, 0, 6, 27.449999999999083, 6, 0.0, 0.0),
            (true, 10, 0, 10, 37.29166666666519, 10, 0.0, 0.0),
            (true, 8, 0, 8, 38.399999999998464, 8, 0.0, 0.0),
            (true, 10, 0, 10, 42.191666666664915, 10, 0.0, 0.0),
            (true, 10, 0, 10, 45.88333333333137, 10, 0.0, 0.0),
            (true, 10, 0, 10, 45.88333333333137, 10, 0.0, 0.0),
            (true, 6, 0, 0, 29.241666666665648, 6, 0.0, 0.0),
            (true, 6, 0, 0, 25.274999999999206, 6, 0.0, 0.0),
            (true, 8, 0, 8, 36.541666666665236, 8, 0.0, 0.0),
            (true, 10, 0, 10, 28.54999999999902, 10, 0.0, 0.0),
            (true, 10, 0, 10, 48.40833333333123, 10, 0.0, 0.0),
            (true, 10, 0, 10, 48.79999999999787, 10, 0.0, 0.0),
            (true, 8, 0, 8, 37.44999999999852, 8, 0.0, 0.0),
            (true, 12, 0, 12, 41.89166666666493, 12, 0.0, 0.0),
            (true, 8, 0, 0, 38.15833333333181, 8, 0.0, 0.0),
            (true, 8, 0, 0, 33.44166666666541, 8, 0.0, 0.0),
            (true, 12, 0, 12, 44.549999999998114, 12, 0.0, 0.0),
            (true, 12, 0, 12, 46.533333333331335, 12, 0.0, 0.0),
            (true, 12, 0, 12, 55.08333333333085, 12, 0.0, 0.0),
            (true, 10, 0, 10, 45.88333333333137, 10, 0.0, 0.0),
            (true, 16, 0, 16, 58.916666666663964, 16, 0.0, 0.0)
        ]
        XCTAssertEqual(expected.count, 30)
        for (step, outcome) in expected.enumerated() {
            let e = MPPlay(step: step, roster: ["miniko", "minik", "mia", "june"], seed: 5); e.start()
            let territory = e.stage?.territory == true
            for _ in 0..<(territory ? 11_000 : 120 * 60) where !e.ended {
                let f = e.flight
                if territory {
                    if let f, f.striker == .minik { e.move(.init(f.position.x.mpClamp(0.07, 0.93), 0.84)) }
                    let k = e.human.contacts; e.tap(.init(0.10 + Double(k * 7 % 9) * 0.10, 0.10 + Double(k * 3 % 5) * 0.07))
                } else {
                    if let f, f.striker == .minik {
                        let offset = e.stage?.skill == .backhand ? 0.12 : e.stage?.skill == .forehand ? -0.12 : 0
                        if !e.team || !e.alternate || e.nextHitter[0] == 0 { e.move(.init((f.position.x + offset).mpClamp(0.07, 0.93), 0.84)) } else { e.move(.init(0.9, 0.95)) }
                    }
                    e.tap(e.team ? teamBounceAim(e) : e.target)
                }
                e.advance(1.0 / 120)
            }
            let id = e.stage?.id ?? ""
            XCTAssertEqual(e.won, outcome.won, id); XCTAssertTrue(e.ended, id)
            XCTAssertEqual(e.successes, outcome.successes, id); XCTAssertEqual(e.mistakes, outcome.mistakes, id); XCTAssertEqual(e.attempts, outcome.attempts, id)
            XCTAssertEqual(e.clock, outcome.clock, accuracy: 1e-6, id); XCTAssertEqual(e.human.contacts, outcome.contacts, id)
            XCTAssertEqual(e.paint.coverage(0), outcome.cov0, accuracy: 1e-9, id); XCTAssertEqual(e.paint.coverage(1), outcome.cov1, accuracy: 1e-9, id)
        }
    }
    private struct Trace { let clock: Double; let points: [Int]; let rally: Int; let hitter: Int; let attempts: Int; let flight: (Double, Double, Double)?; let actors: [(Double, Int)] }
    private func check(_ g: MPPlay, _ t: Trace, _ label: String) {
        XCTAssertEqual(g.clock, t.clock, accuracy: 1e-6, label); XCTAssertEqual(g.points, t.points, label); XCTAssertEqual(g.rally, t.rally, label)
        XCTAssertEqual(g.hitter, t.hitter, label); XCTAssertEqual(g.attempts, t.attempts, label)
        if let expected = t.flight {
            XCTAssertEqual(g.flight?.position.x ?? -9, expected.0, accuracy: 1e-6, label); XCTAssertEqual(g.flight?.position.y ?? -9, expected.1, accuracy: 1e-6, label)
            XCTAssertEqual(g.flight?.height ?? -9, expected.2, accuracy: 1e-6, label)
        } else { XCTAssertNil(g.flight, label) }
        for (i, actor) in t.actors.enumerated() { XCTAssertEqual(g.actors[i].at.x, actor.0, accuracy: 1e-6, label); XCTAssertEqual(g.actors[i].contacts, actor.1, label) }
    }
    /// Android: house-player-only doubles (miniko and Minik against Flare and Kyra) from the start.
    func testHousePlayerDoublesMatchAndroid() {
        let cases: [(MPTeamMode, Int64, [Int: Trace])] = [
            (.alternate, 93, [
                4: Trace(clock: 3.9999999999999885, points: [0, 0], rally: 1, hitter: 2, attempts: 0, flight: (0.4469358911824182, 0.37703870710438847, 0.8350351209674809), actors: [(0.3, 1), (0.7027131832406976, 0), (0.12, 1), (0.7, 0)]),
                8: Trace(clock: 8.000000000000187, points: [0, 0], rally: 4, hitter: 0, attempts: 0, flight: (0.2267958283314369, 0.2715138973851755, 0.9282697373203668), actors: [(0.12, 2), (0.88, 1), (0.22749278887768126, 1), (0.88, 1)]),
                10: Trace(clock: 10.000000000000073, points: [0, 1], rally: 0, hitter: 1, attempts: 1, flight: (0.8767504469980728, 0.9592573584991552, 0.2568797458958038), actors: [(0.12, 2), (0.88, 2), (0.20515603369457386, 1), (0.88, 1)])
            ]),
            (.free, 11, [
                4: Trace(clock: 3.9999999999999885, points: [0, 0], rally: 1, hitter: 2, attempts: 0, flight: (0.2368033687673805, 0.40759430764156984, 0.7367752164375019), actors: [(0.21197587923225694, 1), (0.62, 0), (0.25335502845746316, 1), (0.62, 0)]),
                8: Trace(clock: 8.000000000000187, points: [0, 0], rally: 4, hitter: 0, attempts: 0, flight: (0.49471100487530506, 0.46881504675817576, 0.5203594821805042), actors: [(0.19939046905243565, 3), (0.62, 0), (0.38, 1), (0.7548743340525944, 1)]),
                10: Trace(clock: 10.000000000000073, points: [0, 0], rally: 6, hitter: 0, attempts: 0, flight: (0.22751618501016926, 0.91413969165036, 0.5022774732416158), actors: [(0.19939041704681307, 4), (0.62, 0), (0.38, 1), (0.754874334323098, 2)])
            ])
        ]
        for (mode, seed, traces) in cases {
            let g = MPPlay(mode: mode, roster: ["miniko", "minik", "flare", "kyra"], humanSeats: [], seed: seed); g.start()
            for second in 1...10 { ticks(g, 120); if let t = traces[second] { check(g, t, "\(mode) \(seed) t=\(second)") } }
        }
    }
    /// Android: an Android host's snapshot body (JSON text) restores on iOS and continues identically.
    func testAndroidDoublesSnapshotRestoresAndContinues() throws {
        let body = #"{"seed":93,"botTried":[false,false,false,false],"botResponses":[0,0,0,0],"botPreviousX":[null,null,null,null],"reception":{"enabled":false,"scale":1.0,"receiver":2,"strength":0.0,"slow":{}},"version":2,"humanSeats":[0,2],"seatAims":[[0.5,0.25],[0.5,0.25],[0.5,0.75],[0.5,0.75]],"seatArmed":[-1.0,-1.0,-1.0,-1.0],"step":-1,"mode":"ALTERNATE","roster":["miniko","minik","flare","kyra"],"open":false,"clock":2.916666666666659,"successes":0,"mistakes":0,"attempts":0,"won":false,"ended":false,"nextAt":1.0,"server":0,"hitter":0,"nextHitter":[1,2],"points":[0,0],"aim":[0.5,0.25],"armedUntil":-1.0,"backhand":false,"contact":1.249999999999998,"contactAt":[0.3,0.96],"contactHeight":0.25,"pending":true,"waiting":false,"rally":0,"paint":[1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0],"painted":[],"ending":null,"marks":[],"flight":{"position":{"x":0.4777688021245456,"y":0.394502786190473},"height":0.8412148061501001,"velocity":{"x":0.060822873701576435,"y":-0.39534867906024695},"lift":-1.6435870514576687,"striker":"CHILD","receiver":false,"resolved":false,"spin":0.0,"serve":null},"actors":[{"x":0.3,"y":0.88,"gx":0.3,"gy":0.88,"swing":0.0,"back":false,"contacts":1},{"x":0.7,"y":0.88,"gx":0.7,"gy":0.88,"swing":0.0,"back":false,"contacts":0},{"x":0.3,"y":0.12,"gx":0.3,"gy":0.12,"swing":0.0,"back":false,"contacts":0},{"x":0.7,"y":0.12,"gx":0.7,"gy":0.12,"swing":0.0,"back":false,"contacts":0}]}"#
        let g = try MPPlay.restore(try MPJSON.decode(body))
        XCTAssertEqual(g.humanSeats, [0, 2]); XCTAssertEqual(g.mode, .alternate); XCTAssertEqual(g.roster, ["miniko", "minik", "flare", "kyra"])
        XCTAssertEqual(g.nextHitter, [1, 2]); XCTAssertEqual(g.reception.receiver, 2); XCTAssertEqual(g.actors[0].contacts, 1)
        XCTAssertEqual(try json(g.save()), try json(try MPPlay.restore(try MPJSON.decode(try XCTUnwrap(MPJSON.encode(g.save())))).save()))
        g.start()
        ticks(g, 60); check(g, Trace(clock: 3.416666666666657, points: [0, 0], rally: 0, hitter: 0, attempts: 0, flight: (0.5081802389753337, 0.19682844666034907, 0.30973802033812775), actors: [(0.3, 1), (0.7, 0), (0.3, 0), (0.7, 0)]), "android 60")
        ticks(g, 60); check(g, Trace(clock: 3.9166666666666554, points: [1, 0], rally: 0, hitter: 0, attempts: 1, flight: nil, actors: [(0.3, 1), (0.7, 0), (0.3, 0), (0.7, 0)]), "android 120")
        ticks(g, 60); check(g, Trace(clock: 4.416666666666676, points: [1, 0], rally: 0, hitter: 0, attempts: 1, flight: nil, actors: [(0.3, 1), (0.7, 0), (0.3, 0), (0.7, 0)]), "android 180")
    }
}
