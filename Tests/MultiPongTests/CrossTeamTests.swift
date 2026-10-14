import XCTest
@testable import MinikMultiPingPong

// Android app/src/test/.../cross/CrossTeamTest.kt, CrossSetGestureRegressionTest.kt, CrossNetworkTeamsTest.kt,
// CrossTeamPaceRegressionTest.kt, ReceptionAssistTest.kt and TeamLineupTest.kt (MinikCrossPong 5c1aa4d).

private func team(_ n: Int = 4) -> CrossTeams { CrossTeams(n == 4 ? [0, 1, 0, 1] : [0, 1, 0])! }
private func hasBounce(_ events: [CrossEvent], owner: Int) -> Bool {
    events.contains { if case let .bounce(o, _) = $0 { return o == owner }; return false }
}

final class CrossTeamTests: XCTestCase {
    // Kotlin: friendlyMissGivesOpponentsThePointForThreeAndFourSeats
    func testFriendlyMissGivesOpponentsThePointForThreeAndFourSeats() {
        for n in 3...4 {
            let r = CrossReferee(CrossGeometry(n), target: 7, teams: team(n))
            let g = r.geometry
            XCTAssertTrue(r.serve(0))
            r.ball(.bounce(point: g.fromLocal(0, 0, 0.8), owner: 0))
            r.ball(.bounce(point: g.fromLocal(2, 0, 0.8), owner: 2))
            guard let outcome = r.miss() else { XCTFail("no miss"); continue }
            XCTAssertEqual(1, outcome.scoresAfter[1]); XCTAssertEqual(0, outcome.scoresAfter[0]); XCTAssertEqual(0, outcome.scoresAfter[2])
            if n == 4 { XCTAssertEqual(1, outcome.scoresAfter[3]) }
            XCTAssertNil(r.miss()); XCTAssertEqual(1, r.ralliesPlayed)
        }
    }
    // Kotlin: teamWinsTogetherAndMismatchedRestoresAreRejected
    func testTeamWinsTogetherAndMismatchedRestoresAreRejected() {
        let r = CrossReferee(CrossGeometry(4), target: 1, teams: team())
        let o = r.serveFault(0)
        XCTAssertEqual(1, o?.winner)
        XCTAssertEqual([0, 1, 0, 1], r.scores)
        var divergent = r.exportState()
        divergent.scores = [0, 1, 0, 0]
        XCTAssertThrowsError(try r.restore(divergent), "Divergent partner scores accepted")
    }
    // Kotlin: raisedPassMustContactThenBounceAndSnapshotPreservesItsReceiver
    func testRaisedPassMustContactThenBounceAndSnapshotPreservesItsReceiver() throws {
        let e = CrossEngine(seats: localTable("minik", "gaya", "june"), control: .beginner, target: 7, seed: 15, teams: team())
        e.incoming(from: 1, to: 0)
        XCTAssertTrue(e.liftToTeammate())
        e.touch(e.ballPosition, down: false)
        e.play(0.02)
        XCTAssertEqual(1, e.teamFlight?.sets); XCTAssertEqual(2, e.teamFlight?.setReceiver); XCTAssertEqual(1, e.teamFlight?.passes)
        let state = try CrossState.read(e.exportState().wire())
        let other = CrossEngine(seats: e.seats, control: e.control, target: 7, seed: 15, teams: team())
        try other.restoreState(state)
        XCTAssertEqual(state.ball, other.ballState); XCTAssertEqual(e.teamFlight, other.teamFlight)
        let events = e.play(4, until: { e.referee.hits >= 3 || e.referee.resolved })
        XCTAssertTrue(hasBounce(events, owner: 2))
        XCTAssertFalse(events.contacts(2).isEmpty, "Partner should receive a reachable raised pass")
        XCTAssertEqual(1, e.teamFlight?.smashes)
    }
    // Kotlin: pauseAndMissingPaddleNeverConjureASet
    func testPauseAndMissingPaddleNeverConjureASet() {
        let e = CrossEngine(seats: localTable("minik", "gaya"), control: .beginner, target: 7, seed: 15, teams: team(3))
        e.incoming(from: 1, to: 0)
        e.paused = true
        XCTAssertFalse(e.liftToTeammate())
        let b = e.ballState
        e.play(2)
        XCTAssertEqual(b, e.ballState)
        e.paused = false
        XCTAssertTrue(e.liftToTeammate())
        e.touch(e.geometry.fromLocal(0, -0.63, 1.23), down: false)
        e.play(3)
        XCTAssertEqual(0, e.teamFlight?.sets)
        XCTAssertTrue(e.referee.resolved || e.referee.ralliesPlayed > 0)
    }
    // Kotlin: receivingRaisedBallRequiresASwipeEvenInBeginner
    func testReceivingRaisedBallRequiresASwipeEvenInBeginner() throws {
        let e = CrossEngine(seats: localTable("minik", "gaya", "june"), control: .beginner, target: 7, seed: 15, teams: team())
        e.incoming(from: 2, to: 0)
        var state = e.exportState()
        state.team = CrossTeamFlight(members: team().seats, setReceiver: 0, friendlyHits: 1)
        try e.restoreState(state)
        e.touch(e.ballPosition, down: true)
        e.play(0.06)
        XCTAssertEqual(1, e.referee.hits)
        let at = e.ballPosition
        e.touch(at + MPPoint(0, 0.07), down: true)
        e.touch(at, velocity: MPPoint(0.1, -1.4), down: false)
        XCTAssertEqual(2, e.referee.hits); XCTAssertEqual(1, e.teamFlight?.smashes)
        XCTAssertGreaterThan(e.ballState.velocity.length, 0.8)
    }
    // Kotlin: oldIndividualStateHasNoTeamExtensionAndCannotEnterTeamMatch
    func testOldIndividualStateHasNoTeamExtensionAndCannotEnterTeamMatch() {
        let e = CrossEngine(seats: localTable("minik", "gaya"), control: .beginner, target: 7, seed: 15)
        XCTAssertNil(e.exportState().wire()["localTeam"])
        let t = CrossEngine(seats: e.seats, control: e.control, target: 7, seed: 15, teams: team(3))
        XCTAssertThrowsError(try t.restoreState(e.exportState()), "Teamless restore accepted")
    }

    // ---- CrossSetGestureRegressionTest ----
    // Kotlin: oneArmedSetUsesRealContactInEveryControlMode
    func testOneArmedSetUsesRealContactInEveryControlMode() {
        for control in CrossControl.allCases {
            let e = CrossEngine(seats: localTable("minik", "gaya", "june"), control: control, target: 7, seed: 15, teams: team(), tapTargets: true)
            e.incoming(from: 1, to: 0)
            XCTAssertTrue(e.liftToTeammate(), "\(control) must accept a double-tap set")
            XCTAssertTrue(e.setArmed)
            e.touch(e.ballPosition, velocity: MPPoint(0.1, -1.4), down: false)
            e.play(0.02)
            XCTAssertEqual(1, e.teamFlight?.sets, "\(control) must produce a set, not a driven stroke")
            XCTAssertFalse(e.setArmed, "One return only")
            XCTAssertEqual(2, e.teamFlight?.setReceiver)
        }
    }
    // Kotlin: observerDoesNotConsumeGameplayEvents
    func testObserverDoesNotConsumeGameplayEvents() {
        let e = CrossEngine(seats: localTable("minik", "gaya", "june"), control: .beginner, target: 7, seed: 15)
        var heard: [CrossEvent] = []
        e.onEvent = { heard.append($0) }
        e.incoming(from: 1, to: 0)
        e.touch(e.ballPosition, down: false)
        e.advance(0.02)
        let drained = e.drainEvents()
        XCTAssertTrue(drained.contains { if case .contact = $0 { return true }; return false })
        XCTAssertEqual(drained, heard)
        XCTAssertTrue(e.drainEvents().isEmpty)
    }
    // Kotlin: networkSnapshotPreservesPendingLocalSetButFreshRestoreDoesNot
    func testNetworkSnapshotPreservesPendingLocalSetButFreshRestoreDoesNot() throws {
        let e = CrossEngine(seats: localTable("minik", "gaya", "june"), control: .pro, target: 7, seed: 15, teams: team())
        e.incoming(from: 1, to: 0)
        XCTAssertTrue(e.liftToTeammate())
        let state = e.exportState()
        try e.restoreState(state, preserveInput: true)
        XCTAssertTrue(e.setArmed)
        try e.restoreState(state)
        XCTAssertFalse(e.setArmed)
    }

    // ---- CrossNetworkTeamsTest ----
    private func networked(_ local: Int) -> CrossEngine {
        CrossEngine(seats: (0...3).map { humanSeat($0, $0 == local ? .local : .remote) }, control: .beginner, target: 7, seed: 15, networked: true, teams: team())
    }
    // Kotlin: remoteRaisedPassUpdatesReceiverAndCannotBeCountedTwice
    func testRemoteRaisedPassUpdatesReceiverAndCannotBeCountedTwice() throws {
        let sender = networked(0)
        sender.incoming(from: 1, to: 0)
        let authority = networked(1)
        try authority.restoreState(sender.exportState())
        XCTAssertTrue(sender.liftToTeammate())
        sender.touch(sender.ballPosition, down: false)
        sender.play(0.02)
        guard let own = sender.localStrike() else { return XCTFail("no strike") }
        let strike = CrossStrike.read(own.wire())
        XCTAssertTrue(strike.raised)
        XCTAssertTrue(authority.applyRemoteStrike(0, strike, rallyId: strike.rallyId, hitIndex: strike.hitIndex))
        XCTAssertEqual(sender.teamFlight, authority.teamFlight)
        XCTAssertEqual(2, authority.teamFlight?.setReceiver)
        XCTAssertFalse(authority.applyRemoteStrike(0, strike, rallyId: strike.rallyId, hitIndex: strike.hitIndex))
        XCTAssertEqual(1, authority.teamFlight?.sets)
        let receiver = networked(2)
        try receiver.restoreState(try CrossState.read(authority.exportState().wire()))
        XCTAssertTrue(receiver.receivingSet)
    }
    // Kotlin: acknowledgedOwnStrikeStillAdoptsAuthoritativeTeamState
    func testAcknowledgedOwnStrikeStillAdoptsAuthoritativeTeamState() throws {
        let peer = networked(0)
        peer.incoming(from: 1, to: 0)
        XCTAssertTrue(peer.liftToTeammate())
        peer.touch(peer.ballPosition, down: false)
        peer.play(0.02)
        var corrected = peer.exportState()
        XCTAssertEqual(1, peer.teamFlight?.sets)
        corrected.team?.sets = 3
        try peer.restoreState(corrected, preserveInput: true)
        XCTAssertEqual(3, peer.teamFlight?.sets)
    }
    // Kotlin: oldIndividualContactsKeepTheirOriginalWireShape
    func testOldIndividualContactsKeepTheirOriginalWireShape() {
        let e = CrossEngine(seats: localTable("minik", "gaya", "june"), control: .beginner, target: 7, seed: 15)
        e.incoming(from: 1, to: 0)
        e.touch(e.ballPosition, down: false)
        e.play(0.02)
        guard let strike = e.localStrike() else { return XCTFail("no strike") }
        XCTAssertNil(strike.wire()["raised"])
        XCTAssertEqual(strike, CrossStrike.read(strike.wire()))
    }

    // ---- CrossTeamPaceRegressionTest ----
    // Kotlin: strongBotsKeepTheirPaceAndSetsRemainReachable
    func testStrongBotsKeepTheirPaceAndSetsRemainReachable() {
        let seats = ["miniko", "flare", "minik", "kyra"].enumerated().map { item in
            CrossSeat(index: item.offset, kind: .house, id: item.element, name: item.element, bot: MPRoster.find(item.element)?.profile, characterId: item.element)
        }
        let e = CrossEngine(seats: seats, control: .beginner, target: 100, seed: 47, teams: team())
        var previous: CrossStrike?
        var speeds: [Double] = []
        var sets = 0, smashes = 0
        for _ in 0..<(120 * 80) {
            e.advance(1.0 / 120)
            if let s = e.lastCommittedStrike, s != previous {
                previous = s
                if !s.serve && !s.raised && [1, 3].contains(s.seat) { speeds.append(s.ball.velocity.length) }
                if s.raised { sets += 1 }
                smashes = max(smashes, e.teamFlight?.smashes ?? 0)
            }
        }
        XCTAssertGreaterThanOrEqual(speeds.count, 8, "Need repeated strong-bot returns")
        XCTAssertGreaterThanOrEqual(speeds.filter { $0 > 1.0 }.count, speeds.count / 2, "Bot speed must not be replaced with constant beginner pace")
        XCTAssertGreaterThanOrEqual(sets, 3, "Team sets must remain in real rallies")
        XCTAssertGreaterThanOrEqual(smashes, 1, "Partners must still reach and smash a set")
    }
}

final class CrossReceptionTests: XCTestCase {
    // Kotlin: unsetPreferencesNeverSlowEitherPlayer
    func testUnsetPreferencesNeverSlowEitherPlayer() {
        let a = CrossReception(); a.enabled = true
        for seat in 0...3 { for _ in 0..<120 { XCTAssertEqual(1.0 / 120, a.advance(1.0 / 120, seat: seat, eta: 0.03), accuracy: 0) } }
        XCTAssertEqual(1.0, a.scale)
    }
    // Kotlin: continuousEntryAndExitNeverStopTheGame
    func testContinuousEntryAndExitNeverStopTheGame() {
        let a = CrossReception(); a.enabled = true; a.slow[0] = true
        var previous = 1.0
        for _ in 0..<120 {
            let dt = a.advance(1.0 / 120, seat: 0, eta: 0.03)
            XCTAssertGreaterThan(dt, 0); XCTAssertLessThanOrEqual(a.scale, previous); XCTAssertLessThan(previous - a.scale, 0.024)
            previous = a.scale
        }
        XCTAssertTrue((0.45...0.47).contains(a.scale))
        for _ in 0..<240 {
            _ = a.advance(1.0 / 120, seat: nil, eta: nil)
            XCTAssertGreaterThanOrEqual(a.scale, previous); XCTAssertLessThan(a.scale - previous, 0.024)
            previous = a.scale
        }
        XCTAssertEqual(1.0, a.scale, accuracy: 0.0001)
    }
    // Kotlin: onlyReceivingHumansOwnSettingControlsSharedClock
    func testOnlyReceivingHumansOwnSettingControlsSharedClock() {
        let a = CrossReception(); a.enabled = true; a.slow[0] = false; a.slow[1] = true
        for _ in 0..<120 { _ = a.advance(1.0 / 120, seat: 0, eta: 0) }
        XCTAssertEqual(1.0, a.scale)
        for _ in 0..<120 { _ = a.advance(1.0 / 120, seat: 1, eta: 0) }
        XCTAssertLessThan(a.scale, 0.47)
        XCTAssertEqual(1, a.receiver); XCTAssertEqual(1.0, a.strength)
        // Zoom can still use strength when this receiver turns slow motion off.
        a.slow[1] = false
        for _ in 0..<240 { _ = a.advance(1.0 / 120, seat: 1, eta: 0) }
        XCTAssertEqual(1.0, a.scale, accuracy: 0.0001); XCTAssertEqual(1.0, a.strength)
    }
    // Kotlin: peerUsesAuthorityScaleRegardlessOfLocalSettings
    func testPeerUsesAuthorityScaleRegardlessOfLocalSettings() throws {
        let host = CrossReception(); host.enabled = true; host.slow[1] = true
        for _ in 0..<90 { _ = host.advance(1.0 / 120, seat: 1, eta: 0.1) }
        let peer = CrossReception()
        try peer.restore(host.wire())
        peer.slow[1] = false
        XCTAssertEqual(host.scale / 120, peer.advance(1.0 / 120, seat: 0, eta: 0, authority: false), accuracy: 0)
        XCTAssertEqual(host.scale, peer.scale)
    }
    // Kotlin: mirroredMatchPreservesTheCorrectOwner
    func testMirroredMatchPreservesTheCorrectOwner() throws {
        let a = CrossReception(); a.enabled = true; a.slow[0] = false; a.slow[1] = true
        _ = a.advance(0.02, seat: 1, eta: 0.1)
        let b = CrossReception()
        try b.restore(CrossReception.reflected(a.wire()))
        XCTAssertEqual(0, b.receiver); XCTAssertEqual(false, b.slow[1]); XCTAssertEqual(true, b.slow[0]); XCTAssertEqual(a.scale, b.scale)
        XCTAssertTrue(NSDictionary(dictionary: a.wire()).isEqual(to: CrossReception.reflected(CrossReception.reflected(a.wire()))))
    }
    // Kotlin: oldSnapshotsStayAtNormalSpeedAndInvalidStatesAreRejected
    func testOldSnapshotsStayAtNormalSpeedAndInvalidStatesAreRejected() throws {
        let a = CrossReception()
        try a.restore([:])
        XCTAssertFalse(a.enabled); XCTAssertEqual(1.0, a.scale)
        for value in [Double.nan, Double.infinity, 0.1, 1.2] { XCTAssertThrowsError(try a.restore(["scale": value])) }
    }
    // Kotlin: anOutgoingOrWideBallDoesNotInviteReception
    func testAnOutgoingOrWideBallDoesNotInviteReception() {
        XCTAssertNil(CrossReception.eta(MPPoint(0.1, 0.5), MPPoint(0, 1), MPPoint(0.9, 0.8)))
        XCTAssertLessThan(CrossReception.eta(MPPoint(0.5, 0.9), MPPoint(0, 1), MPPoint(0.5, 0.7)) ?? 1, 0)
        let a = CrossReception(); a.enabled = true
        _ = a.advance(0.02, seat: 0, eta: -0.2)
        XCTAssertEqual(0.0, a.strength)
    }
    // Kotlin: entireModernSimulationUsesTheSameSlowerDelta (the classic two-player engine, MPEngine)
    func testEntireClassicSimulationUsesTheSameSlowerDelta() throws {
        let a = MPEngine(level: .easy, target: 7)
        let flight = try MPCodec.decode(MPFlight.self, ["position": ["x": 0.5, "y": 0.70], "height": 0.22, "velocity": ["x": 0.02, "y": 0.28], "lift": 0.2,
                                                         "striker": "MINIK", "receiver": true, "resolved": false, "spin": 0.0] as [String: Any])
        var state = a.snapshot()
        state.flight = flight; state.pointDelay = nil; state.serveDelay = nil
        a.restore(state)
        a.reception.enabled = true; a.reception.slow[0] = true
        let b = MPEngine(level: .easy, target: 7)
        var copy = a.snapshot()
        copy.reception = nil
        b.restore(copy)
        for _ in 0..<20 { a.advance(1.0 / 120); b.advance(a.reception.scale / 120) }
        XCTAssertLessThan(a.reception.scale, 1)
        let fa = try XCTUnwrap(a.flight), fb = try XCTUnwrap(b.flight)
        XCTAssertEqual(fb.position.x, fa.position.x, accuracy: 1e-9)
        XCTAssertEqual(fb.position.y, fa.position.y, accuracy: 1e-9)
        XCTAssertEqual(fb.height, fa.height, accuracy: 1e-9)
        XCTAssertEqual(b.childStroke.age, a.childStroke.age, accuracy: 1e-9)
        let saved = try MPCodec.decode(MPState.self, try MPCodec.encode(a.snapshot()))
        XCTAssertEqual(a.reception.scale, saved.reception?.scale ?? 0, accuracy: 0)
    }
}

final class CrossLineupTests: XCTestCase {
    // Kotlin: ownerExampleFromEmptyPlacesThroughFourFriendsAndReplacement
    func testOwnerExampleFromEmptyPlacesThroughFourFriendsAndReplacement() {
        let order = [0, 1, 2, 3]
        var members: Set<String> = ["host"]
        var lineup = CrossLineup.initial("host", count: 4)
        XCTAssertFalse(lineup.complete)
        lineup = lineup.choose(1, "b:kyra")
        members.insert("john"); lineup = lineup.reconcile(members, arrivals: ["host", "john"], order: order)
        XCTAssertEqual(["u:host", "b:kyra", "u:john", "empty"], lineup.slots)
        lineup = lineup.choose(1, "u:john")
        XCTAssertEqual(["u:host", "u:john", "empty", "empty"], lineup.slots)
        lineup = lineup.choose(2, "b:flare").choose(3, "b:mia")
        XCTAssertTrue(lineup.complete)
        members.insert("bini"); lineup = lineup.reconcile(members, arrivals: ["host", "john", "bini"], order: order)
        XCTAssertEqual("u:bini", lineup.slots[2])
        members.insert("gibi"); lineup = lineup.reconcile(members, arrivals: ["host", "john", "bini", "gibi"], order: order)
        XCTAssertEqual("u:gibi", lineup.slots[3])
        lineup = lineup.choose(3, "b:mia")
        // Benched friend is not immediately reinserted.
        XCTAssertEqual(lineup, lineup.reconcile(members, arrivals: ["host", "john", "bini", "gibi"], order: order))
        lineup = lineup.choose(3, "u:gibi")
        XCTAssertEqual(4, lineup.humans.count)
        var without = members; without.remove("john")
        lineup = lineup.reconcile(without, arrivals: ["host", "bini", "gibi"], order: order)
        XCTAssertEqual("empty", lineup.slots[1]); XCTAssertFalse(lineup.complete)
        lineup = lineup.reconcile(members, arrivals: ["host", "john", "bini", "gibi"], order: order)
        XCTAssertEqual("u:john", lineup.slots[1])
    }
    // Kotlin: movingFriendsSwapsWithoutDuplicatingOrDroppingHost
    func testMovingFriendsSwapsWithoutDuplicatingOrDroppingHost() {
        let l = CrossLineup(slots: ["u:host", "u:a", "u:b", "b:mia"], seen: ["host", "a", "b"])
        let swapped = l.choose(0, "u:b")
        XCTAssertEqual(["u:b", "u:a", "u:host", "b:mia"], swapped.slots)
        let benched = l.choose(0, "b:kyra")
        XCTAssertNil(benched.humans["host"])
        let restored = benched.choose(2, "u:host")
        XCTAssertEqual(["b:kyra", "u:a", "u:host", "b:mia"], restored.slots)
        XCTAssertEqual(["u:b", "u:a", "u:host", "b:mia"], restored.choose(0, "u:b").slots)
        XCTAssertEqual("empty", l.choose(0, "empty").slots[0])
    }
    // Kotlin: multiplayerFillsOwnTeammateBeforeOpponentsAndSupportsThreePlaces
    func testMultiplayerFillsOwnTeammateBeforeOpponentsAndSupportsThreePlaces() {
        let four = CrossLineup.initial("host", count: 4).reconcile(["host", "a", "b"], arrivals: ["a", "b"], order: [0, 2, 1, 3])
        XCTAssertEqual(["u:host", "u:b", "u:a", "empty"], four.slots)
        let three = CrossLineup.initial("host", count: 3).reconcile(["host", "a"], arrivals: ["a"], order: [0, 2, 1])
        XCTAssertEqual(three, CrossLineup.read(three.wire(), count: 3))
        XCTAssertTrue(three.choose(1, "b:flare").complete)
    }
    // Kotlin: concurrentArrivalAlwaysReconcilesAgainstLatestChoice
    func testConcurrentArrivalAlwaysReconcilesAgainstLatestChoice() {
        let l = CrossLineup.initial("host", count: 4).choose(1, "b:kyra")
        let afterChoice = l.choose(2, "b:flare")
        let result = afterChoice.reconcile(["host", "a"], arrivals: ["a"], order: [0, 1, 2, 3])
        XCTAssertEqual(["u:host", "b:kyra", "b:flare", "u:a"], result.slots)
        XCTAssertEqual(result, result.reconcile(["host", "a"], arrivals: ["a"], order: [0, 1, 2, 3]))
    }
}
