import XCTest
@testable import MinikMultiPingPong

// Android app/src/test/.../cross/CrossControlTest.kt (MinikCrossPong 828c6fc; b0cdeb3 and fcfd6b2 for the fourth level, Starter,
// the saved classic final and the early tap).
/// The local human's four control levels on the cross table.
final class CrossControlTests: XCTestCase {
    private func table(_ players: Int) -> [CrossSeat] {
        players == 3 ? localTable("mia", "june") : localTable("mia", "june", "amber")
    }

    private func engine(_ players: Int, _ control: CrossControl) -> CrossEngine {
        CrossEngine(seats: table(players), control: control, target: 7, seed: 1)
    }

    /// Kotlin `CrossEngine.landing()`: the forecast first event of the live ball (nil where Kotlin's `!!` would throw).
    private func landingOf(_ e: CrossEngine) -> CrossBallEvent? {
        CrossBall(e.geometry, tuning: e.physics, initial: e.ballState).forecast()?.event
    }

    private func bounceOwner(_ event: CrossBallEvent?) -> Int? {
        if case let .bounce(_, owner)? = event { return owner }
        return nil
    }

    private func isLanded(_ event: CrossBallEvent?) -> Bool {
        if case .landed? = event { return true }
        return false
    }

    /// Kotlin `filterIsInstance<CrossEvent.Bounce>()`.
    private func bounceEvents(_ events: [CrossEvent]) -> [(owner: Int, point: MPPoint)] {
        var found: [(owner: Int, point: MPPoint)] = []
        for event in events {
            if case let .bounce(owner, point) = event { found.append((owner: owner, point: point)) }
        }
        return found
    }

    /// Kotlin `filterIsInstance<CrossEvent.Served>().map { it.seat }`.
    private func servedSeats(_ events: [CrossEvent]) -> [Int] {
        var found: [Int] = []
        for event in events {
            if case let .served(seat) = event { found.append(seat) }
        }
        return found
    }

    /// Kotlin `single()`: the only element, failing otherwise.
    private func only<T>(_ items: [T], file: StaticString = #filePath, line: UInt = #line) -> T? {
        XCTAssertEqual(1, items.count, "expected exactly one element", file: file, line: line)
        return items.count == 1 ? items[0] : nil
    }

    /// Kotlin data-class equality of `Tuning` (MPTuning is not Equatable): every number, profile included.
    private func tuningNumbers(_ t: MPTuning) -> [Double] {
        var v: [Double] = [t.tapSpatialTolerance, t.tapTimingWindow, t.tapTimingQualityExponent, t.swipeCollisionForgiveness]
        v += [t.swipeVelocityScale, t.minimumSwipeSpeed, t.maximumSwipeSpeed, t.serveAssistance, t.ballBaseSpeed]
        v += [t.rallySpeedGrowth, t.maximumBallSpeed, t.gravity, t.bounceRestitution, t.netHeight]
        v += [t.netClearanceVelocityTarget, t.maximumArcVelocity, t.incomingVelocityInfluence, t.minikReactionInterval]
        v += [t.minikMaximumReach, t.minikPredictionAmount, t.minikAimError, t.minikErrorProbability]
        v += [t.minikPoorContactProbability, t.minikCornerPreference, t.minikReturnSpeedMultiplier]
        v += [t.minikForehandPreference, t.minikServeFaultProbability]
        return v + profileNumbers(t.profile)
    }

    private func profileNumbers(_ p: MPProfile) -> [Double] {
        var v: [Double] = [p.forehandServe, p.serveSuccess, p.serveMiddle, p.serveSpeed, p.serveVariation]
        v.append(Double(p.serveReceive.count))
        for c in p.serveReceive { v += [c.answer, c.good] }
        let chances: [MPChance] = [p.forehandSame, p.forehandCross, p.backhandSame, p.backhandCross]
        for c in chances { v += [c.answer, c.good] }
        v += [p.answerDrop, p.goodDrop, p.backhandCrossGoodDrop, p.firstForehandSpeed, p.firstBackhandSpeed, p.accelerateChance]
        v += [p.forehandSpeedUp.lowerBound, p.forehandSpeedUp.upperBound, p.backhandSpeedUp.lowerBound, p.backhandSpeedUp.upperBound]
        v += [p.speedDown.lowerBound, p.speedDown.upperBound, p.maxSpeed]
        return v
    }

    // Kotlin: selectedControlLevelSurvivesEngineCreation
    func testSelectedControlLevelSurvivesEngineCreation() {
        // Kotlin Difficulty BEGINNER / STARTER / HARD = iOS .beginner / .easy / .superHard.
        let cases: [(Int, CrossControl, MPLevel)] = [(4, .beginner, .beginner), (0, .standard, .easy), (3, .pro, .superHard)]
        for (choice, control, difficulty) in cases {
            XCTAssertEqual(control, CrossControl.fromChoice(choice))
            XCTAssertEqual(control, CrossControl.fromChoice(control.choice))
            XCTAssertEqual(difficulty, MPLevel.control(control.choice))
            let e = CrossEngine(seats: table(4), control: control, target: 7, seed: 1)
            XCTAssertEqual(control, e.control)
            XCTAssertEqual(tuningNumbers(MPTuning.values(difficulty)), tuningNumbers(e.tuning))
            XCTAssertEqual(control == .beginner, e.automaticContact)
            // Every phone shares the table physics whatever its control level.
            XCTAssertEqual(3.6, e.physics.gravity)
            XCTAssertEqual(0.54, e.physics.bounceRestitution)
            XCTAssertEqual(0.075, e.physics.netHeight)
            XCTAssertEqual(e.tuning.swipeCollisionForgiveness, e.physics.swipeCollisionForgiveness)
        }
        // Older intermediate ordinals use Standard input; anything else is Beginner. Android b0cdeb3: 1 is Starter again.
        XCTAssertEqual(CrossControl.starter, CrossControl.fromChoice(1))
        XCTAssertEqual(CrossControl.standard, CrossControl.fromChoice(2))
        XCTAssertEqual(CrossControl.beginner, CrossControl.fromChoice(9))
    }

    // iOS (Android b0cdeb3 CrossControl.STARTER(1, Difficulty.EASY)): Starter's wire value, input values and stroke.
    func testStarterIsWireValueOneWithEasyValuesAndALongerWindow() {
        XCTAssertEqual(CrossControl.allCases, [.beginner, .standard, .pro, .starter]) // Kotlin `entries` order
        XCTAssertEqual(1, CrossControl.starter.choice)
        XCTAssertEqual(MPLevel.medium, CrossControl.starter.level)                     // Kotlin Difficulty.EASY
        XCTAssertEqual(CrossControl.starter, CrossControl.fromChoice(CrossControl.starter.choice))
        let e = engine(4, .starter)
        var expected = MPTuning.values(.medium)
        expected.tapSpatialTolerance = 0.28
        expected.tapTimingWindow = 0.80
        XCTAssertEqual(tuningNumbers(expected), tuningNumbers(e.tuning))
        XCTAssertFalse(e.automaticContact)
        XCTAssertEqual(3.6, e.physics.gravity)
        let stroke = CrossEngine.localStroke(.starter)
        XCTAssertEqual([0.10, 0.85, 1.10, 1.50], [stroke.contactAt, stroke.windowEnd, stroke.followEnd, stroke.total])
        for control in [CrossControl.beginner, .standard] {
            let s = CrossEngine.localStroke(control)
            XCTAssertEqual([0.10, 0.40, 0.50, 0.65], [s.contactAt, s.windowEnd, s.followEnd, s.total], "\(control)")
        }
    }

    // Kotlin (b0cdeb3): savedClassicFinalKeepsScoresAndCorrectPlayerSeats
    func testSavedClassicFinalKeepsScoresAndCorrectPlayerSeats() throws {
        for child in 0...1 {
            for winner in [nil, MPSide.child] as [MPSide?] {
                let m = CrossMatch(roster: localTable("kyra"), control: .standard, target: 7, seed: 22, mode: .elimination)
                let old = MPScore(child: winner == nil ? 2 : 7, minik: 4, rallies: 6, server: .minik, winner: winner, streak: 0)
                try m.restoreState(CrossLink.legacyDuel(m, old, childSeat: child))
                XCTAssertEqual(old.child, m.scores()[child])
                XCTAssertEqual(4, m.scores()[1 - child])
                XCTAssertEqual(1 - child, m.engine.referee.server)
                XCTAssertEqual(winner != nil, m.finished)
            }
        }
    }

    // Kotlin (b0cdeb3): starterAndStandardOneGestureAtPlayerDepthReturnTheLiveBall
    func testStarterAndStandardOneGestureAtPlayerDepthReturnTheLiveBall() {
        for control in [CrossControl.starter, .standard] {
            for n in 2...4 {
                for u in [-0.3, 0.0, 0.3] {
                    let roster = [humanSeat(0)] + (1..<n).map { houseSeat($0, "kyra") }
                    let e = CrossEngine(seats: roster, control: control, target: 7, seed: 11)
                    e.incoming(from: 1, to: 0, u: u)
                    e.waitForBall(0, depth: 0.82)
                    let at = e.geometry.toLocal(0, e.ballPosition)
                    // A finger at the player's depth, not exactly at the ball's ground shadow.
                    let touch = e.geometry.fromLocal(0, at.u, 1.12)
                    e.touch(touch)
                    e.endTouch()
                    XCTAssertEqual(1, e.play(1.2) { e.referee.striker == 0 }.contacts(0).count, "\(control)/\(n)/\(u)")
                }
            }
        }
    }

    // Kotlin (b0cdeb3): starterHasLongerPreparationButStillNeedsAPlayerGesture
    func testStarterHasLongerPreparationButStillNeedsAPlayerGesture() {
        let easy = engine(4, .starter)
        let standard = engine(4, .standard)
        XCTAssertTrue(easy.tuning.tapTimingWindow > standard.tuning.tapTimingWindow)
        XCTAssertTrue(CrossEngine.localStroke(.starter).total > CrossEngine.localStroke(.standard).total)
        easy.incoming(from: 2, to: 0)
        XCTAssertTrue(easy.play(3.0) { easy.referee.resolved }.contacts(0).isEmpty)
    }

    // Kotlin: beginnerContactIsAutomaticAtTheRetainedPaddleAndHappensOnce
    func testBeginnerContactIsAutomaticAtTheRetainedPaddleAndHappensOnce() {
        for players in 3...4 {
            for u in [-0.3, 0.0, 0.3] {
                let e = engine(players, .beginner)
                e.incoming(from: 1, to: 0, u: u)
                // Put the paddle on the ball's path, then let go: the retained paddle meets the legal ball by itself.
                let path = e.ballAfter(25)
                e.touch(path)
                e.endTouch()
                XCTAssertNil(e.paddle)
                XCTAssertEqual(path, e.restingPaddle)
                let events = e.play(1.5) { e.referee.striker == 0 }
                XCTAssertEqual(1, events.contacts(0).count)
                XCTAssertEqual(1, events.swings(0).count)
                XCTAssertEqual(2, e.referee.hits)
                XCTAssertEqual(CrossRallyPhase.toReceiver, e.referee.phase)
                guard let strike = e.localStrike() else {
                    XCTFail("\(players) \(u): no local strike")
                    continue
                }
                XCTAssertEqual(0, strike.seat)
                XCTAssertEqual(2, strike.hitIndex)
                XCTAssertEqual(e.referee.rallyId, strike.rallyId)
                XCTAssertFalse(strike.serve)
                let strikeID = e.localStrikeID
                // The paddle stays there while the ball leaves: no second sound, stroke or network hit.
                let later = e.play(1.0)
                XCTAssertTrue(later.contacts(0).isEmpty && later.swings(0).isEmpty)
                // Kotlin assertSame: iOS strikes are values, numbered by localStrikeID instead of object identity.
                XCTAssertEqual(strike, e.localStrike())
                XCTAssertEqual(strikeID, e.localStrikeID)
                let landing = landingOf(e)
                let owner = bounceOwner(landing)
                XCTAssertTrue(owner != nil && owner != 0, "\(players) \(u) \(String(describing: landing))")
            }
        }
    }

    // Kotlin: beginnerCannotReturnWithThePaddleOnTheWrongSide
    func testBeginnerCannotReturnWithThePaddleOnTheWrongSide() {
        let e = engine(4, .beginner)
        e.incoming(from: 2, to: 0, u: 0.3)
        e.touch(e.geometry.fromLocal(0, -0.55, CrossGeometry.homeDepth))
        e.endTouch()
        let events = e.play(4) { e.referee.resolved }
        guard let outcome = only(events.rallies()) else { return }
        XCTAssertEqual(CrossRallyKind.missed, outcome.kind)
        XCTAssertEqual(0, outcome.receiver)
        XCTAssertEqual(2, outcome.striker)
    }

    // Kotlin: beginnerSideGesturesReachTheLeftAndRightOpponents
    func testBeginnerSideGesturesReachTheLeftAndRightOpponents() {
        for players in 3...4 {
            let g = CrossGeometry(players)
            let order = CrossAimMap(g).opponents(0)
            let left = order[0]
            let right = order[order.count - 1]
            let sender = players == 4 ? 2 : 1
            let neutral = players == 4 ? 2 : sender
            let cases: [(Double, Int)] = [(-60.0, left), (60.0, right), (-100.0, left), (100.0, right), (0.0, neutral)]
            for (drag, expected) in cases {
                let e = engine(players, .beginner)
                e.incoming(from: sender, to: 0, u: 0.1)
                let path = e.ballAfter(25)
                e.touch(path)
                e.touch(path, drag: MPPoint(drag, 0), down: false)
                e.endTouch()
                e.play(1.5) { e.referee.striker == 0 }
                XCTAssertEqual(expected, e.predictedReceiver, "\(players) players, drag \(drag)")
                let events = e.play(4) { e.referee.phase != .toReceiver }
                let bounces = bounceEvents(events)
                guard let bounce = bounces.first else {
                    XCTFail("\(players) players, drag \(drag): no bounce")
                    continue
                }
                XCTAssertEqual(expected, bounce.owner)
                XCTAssertEqual(CrossRallyPhase.receivable, e.referee.phase)
            }
        }
    }

    // Kotlin: aWideBeginnerSwipeChoosesTheSidePlayerAndStaysOnTheTable
    func testAWideBeginnerSwipeChoosesTheSidePlayerAndStaysOnTheTable() {
        for players in 3...4 {
            let e = engine(players, .beginner)
            let scores: [Int] = (0..<players).map { $0 == 0 ? 2 : 1 }
            e.incoming(from: 1, to: 0, scores: scores)
            let path = e.ballAfter(25)
            e.touch(path)
            e.touch(path, drag: MPPoint(140, 0), down: false)
            e.endTouch()
            let right = CrossAimMap(e.geometry).opponents(0).last
            e.play(3) { e.referee.striker == 0 && e.referee.phase == .receivable }
            XCTAssertEqual(right, e.referee.receiver, "players=\(players)")
            XCTAssertEqual(scores, e.referee.scores)
        }
    }

    /// A Standard tap at the ball as it reaches the ideal depth, then a drag at `speed` world units/s.
    private func standardReturn(_ players: Int, _ drag: Double, _ speed: Double,
                                file: StaticString = #filePath, line: UInt = #line) -> CrossEngine {
        let e = engine(players, .standard)
        e.incoming(from: players == 4 ? 2 : 1, to: 0, u: 0.05)
        e.waitForBall(0, depth: 0.84)
        let at = e.ballPosition
        e.touch(at)
        e.touch(at, drag: MPPoint(drag, 0), velocity: MPPoint(0, -speed), down: false)
        e.endTouch()
        let events = e.play(1.0) { e.referee.striker == 0 }
        XCTAssertEqual(1, events.contacts(0).count, "\(players) \(drag) \(speed)", file: file, line: line)
        return e
    }

    // Kotlin: standardDirectionComesFromTheDragAndPaceFromTheGestureSpeed
    func testStandardDirectionComesFromTheDragAndPaceFromTheGestureSpeed() {
        for players in 3...4 {
            let order = CrossAimMap(CrossGeometry(players)).opponents(0)
            let left = order[0]
            let right = order[order.count - 1]
            XCTAssertEqual(left, standardReturn(players, -60.0, 0.2).predictedReceiver)
            XCTAssertEqual(right, standardReturn(players, 60.0, 0.2).predictedReceiver)
            let slow = standardReturn(players, 0.0, 0.0).ballState.velocity.length
            let fast = standardReturn(players, 0.0, 2.0).ballState.velocity.length
            XCTAssertTrue(fast > slow * 1.2, "faster gesture, faster ball: \(slow) -> \(fast)")
            let starter = MPTuning.values(.easy)
            XCTAssertEqual(CrossShots.pace(starter, power: 1.0) / CrossShots.basePace(starter), 1.35, accuracy: 1e-12)
        }
    }

    // Kotlin: standardNeedsATimedTapNotJustAPosition
    func testStandardNeedsATimedTapNotJustAPosition() {
        let e = engine(4, .standard)
        e.incoming(from: 2, to: 0)
        let path = e.ballAfter(25)
        // Resting the paddle on the path is Beginner's automatic contact; Standard needs the tap's stroke window.
        e.touch(path, down: false)
        e.endTouch()
        let resting = e.play(3.0) { e.referee.resolved }
        XCTAssertTrue(resting.contacts(0).isEmpty)
        // A tap far too early (the ball has only just left the opposite player) remains movement without a swing (Android fcfd6b2).
        let early = engine(4, .standard)
        early.approaching(from: 2, to: 0)
        XCTAssertEqual(0, early.predictedReceiver)
        XCTAssertEqual(CrossStatus.incoming, early.status)
        early.touch(early.geometry.fromLocal(0, 0, 1.0))
        early.endTouch()
        let events = early.play(5.0) { early.referee.resolved }
        XCTAssertTrue(events.swings(0).isEmpty)
        XCTAssertTrue(events.contacts(0).isEmpty)
        XCTAssertEqual(CrossRallyKind.missed, only(events.rallies())?.kind)
    }

    /// A Pro swipe through the ball's current position from just behind it, inward, at `velocity`.
    private func swipeThrough(_ e: CrossEngine, _ velocity: MPPoint, offset: Double = 0) {
        let view = e.geometry.toView(0, e.ballPosition)
        e.touch(e.geometry.fromView(0, view + MPPoint(offset, 0.06)))
        e.touch(e.geometry.fromView(0, view + MPPoint(offset, -0.06)), velocity: velocity, down: false)
        e.endTouch()
    }

    // Kotlin: proSwipesArePreciseInDirectionAndPower
    func testProSwipesArePreciseInDirectionAndPower() {
        for players in 3...4 {
            let g = CrossGeometry(players)
            for target in g.seats where target != 0 {
                let e = engine(players, .pro)
                e.incoming(from: target, to: 0)
                e.waitForBall(0, depth: 0.9)
                // A well-aimed swipe: its direction points at the target arm and its power carries the ball onto it.
                let delta = g.toView(0, g.fromLocal(target, 0, 0.8)) - g.toView(0, e.ballPosition)
                let psi = atan2(delta.x, -delta.y)
                let height = max(e.ballHeight, CrossShots.contactHeight)
                func swipeFor(_ forward: Double) -> MPPoint { MPPoint(forward * tan(psi / 1.25), -forward) }
                // As Kotlin's local `landing`, it reads the engine's ball when called.
                func landingFor(_ forward: Double) -> CrossBallEvent? {
                    let launch = CrossShots.driven(g, e.physics, striker: 0, swipe: swipeFor(forward), height: height, incoming: e.ballState.velocity)
                    let state = CrossBallState(position: e.ballPosition, height: height, velocity: launch.velocity, lift: launch.lift)
                    return CrossBall(g, tuning: e.physics, initial: state).forecast()?.event
                }
                let maxSpeed = e.physics.maximumSwipeSpeed
                var found: Double? = nil
                for k in 4...40 {
                    let candidate: Double = Double(k) * 0.05 * maxSpeed
                    if bounceOwner(landingFor(candidate)) == target {
                        found = candidate
                        break
                    }
                }
                XCTAssertNotNil(found, "\(players) -> \(target)")
                // The same direction with far too much power flies long: a precise game, not an assisted one.
                XCTAssertTrue(isLanded(landingFor(3 * maxSpeed)))
                guard let forward = found else { continue }
                swipeThrough(e, swipeFor(forward))
                XCTAssertEqual(0, e.referee.striker)
                XCTAssertEqual(2, e.referee.hits)
                let landed = landingOf(e)
                XCTAssertEqual(target, bounceOwner(landed), "\(players) -> \(target) \(String(describing: landed))")
                XCTAssertEqual(landingFor(forward), landed)
            }
            // An oversized sideways swipe is a genuine wide shot: out.
            let wide = engine(players, .pro)
            wide.incoming(from: 1, to: 0)
            wide.waitForBall(0, depth: 0.9)
            swipeThrough(wide, MPPoint(3.6, -1.3))
            XCTAssertTrue(isLanded(landingOf(wide)))
            let events = wide.play(5.0) { wide.referee.resolved }
            XCTAssertEqual(CrossRallyKind.out, only(events.rallies())?.kind)
        }
    }

    // Kotlin: aProSwipeMustPassTheBallAndMoveInward
    func testAProSwipeMustPassTheBallAndMoveInward() {
        let missed = engine(4, .pro)
        missed.incoming(from: 2, to: 0)
        missed.waitForBall(0, depth: 0.9)
        swipeThrough(missed, MPPoint(0, -1.0), offset: 0.12) // beyond the .072 forgiveness
        XCTAssertEqual(1, missed.referee.hits)
        let backward = engine(4, .pro)
        backward.incoming(from: 2, to: 0)
        backward.waitForBall(0, depth: 0.9)
        swipeThrough(backward, MPPoint(0, 0.8))
        XCTAssertEqual(1, backward.referee.hits)
    }

    // Kotlin: oneSwipeThroughTheBallIsOneContact
    func testOneSwipeThroughTheBallIsOneContact() {
        let e = engine(4, .pro)
        e.incoming(from: 2, to: 0)
        e.waitForBall(0, depth: 0.9)
        let view = e.geometry.toView(0, e.ballPosition)
        var events: [CrossEvent] = []
        e.touch(e.geometry.fromView(0, view + MPPoint(0, 0.1)))
        // The finger keeps moving through and past the ball over several frames.
        for k in 1...8 {
            let offset: Double = 0.1 - 0.04 * Double(k)
            e.touch(e.geometry.fromView(0, view + MPPoint(0, offset)), velocity: MPPoint(0, -1.1), down: false)
            e.advance(CrossEngine.step)
            events += e.drainEvents()
        }
        e.endTouch()
        events = e.play(1.0, into: events)
        XCTAssertEqual(1, events.contacts(0).count)
        XCTAssertEqual(1, events.swings(0).count)
        XCTAssertEqual(2, e.referee.hits)
    }

    // Kotlin: beginnerAndStandardServesUseTheTapForTheFirstBounceAndTheDragForTheTarget
    func testBeginnerAndStandardServesUseTheTapForTheFirstBounceAndTheDragForTheTarget() {
        let controls: [CrossControl] = [.beginner, .standard]
        for control in controls {
            for players in 3...4 {
                let g = CrossGeometry(players)
                let order = CrossAimMap(g).opponents(0)
                let left = order[0]
                let right = order[order.count - 1]
                let cases: [(Double, Int)] = [(-60.0, left), (60.0, right)]
                for (drag, expected) in cases {
                    let e = CrossEngine(seats: table(players), control: control, target: 7, seed: 1)
                    XCTAssertEqual(CrossStatus.yourServe, e.status)
                    let tap = g.fromLocal(0, 0.15, 0.75)
                    e.touch(tap)
                    e.touch(tap, drag: MPPoint(drag, 0), down: false)
                    XCTAssertEqual(CrossRallyPhase.awaitingServe, e.referee.phase) // the serve goes on release
                    e.endTouch()
                    let events = e.play(3.0) { e.referee.phase == .receivable || e.referee.resolved }
                    XCTAssertEqual([0], servedSeats(events))
                    let bounces = bounceEvents(events)
                    guard bounces.count >= 2 else {
                        XCTFail("\(control) \(players) \(drag): \(bounces.count) bounces")
                        continue
                    }
                    XCTAssertEqual(0, bounces[0].owner)
                    XCTAssertTrue(g.inServeZone(0, bounces[0].point))
                    XCTAssertEqual(0.15, g.toLocal(0, bounces[0].point).u, accuracy: 1e-9)
                    XCTAssertEqual(expected, bounces[1].owner, "\(control) \(players) \(drag)")
                    XCTAssertEqual(0, e.localStrike()?.hitIndex)
                    XCTAssertEqual(true, e.localStrike()?.serve)
                }
            }
        }
    }

    // Kotlin: proServesAreSwipedThroughTheBallAndAWeakSwipeIsABadServe
    func testProServesAreSwipedThroughTheBallAndAWeakSwipeIsABadServe() throws {
        let e = CrossEngine(seats: table(4), control: .pro, target: 7, seed: 1)
        let spot = e.geometry.toView(0, e.serveSpot(0))
        e.touch(e.geometry.fromView(0, spot + MPPoint(0, 0.08)))
        e.touch(e.geometry.fromView(0, spot - MPPoint(0, 0.08)), velocity: MPPoint(0.1, -1.0), down: false)
        e.endTouch()
        let events = e.play(3.0) { e.referee.phase == .receivable || e.referee.resolved }
        XCTAssertEqual(1, servedSeats(events).count)
        XCTAssertEqual(CrossRallyPhase.receivable, e.referee.phase)
        // A weak, backward swipe through the ball serves nothing: BAD_SERVE, the server's fault.
        let badServer = CrossEngine(seats: table(4), control: .pro, target: 7, seed: 1)
        badServer.incoming(from: 1, to: 2, scores: [1, 0, 0, 0]) // any scored state, then back to a serve
        var fresh = badServer.exportState()
        fresh.referee.phase = .awaitingServe
        fresh.referee.server = 0
        fresh.referee.striker = 0
        fresh.referee.receiver = nil
        fresh.referee.hits = 0
        fresh.ball = CrossBallState(position: badServer.serveSpot(0), height: CrossShots.contactHeight, velocity: MPPoint(0, 0), lift: 0, stopped: true)
        try badServer.restoreState(fresh)
        badServer.touch(badServer.geometry.fromView(0, spot - MPPoint(0, 0.08)))
        badServer.touch(badServer.geometry.fromView(0, spot + MPPoint(0, 0.08)), velocity: MPPoint(0, 0.5), down: false)
        badServer.endTouch()
        let outcome = only(badServer.drainEvents().rallies())
        XCTAssertEqual(CrossRallyKind.badServe, outcome?.kind)
        XCTAssertEqual(0, outcome?.faultOwner)
        XCTAssertEqual([0, 0, 0, 0], badServer.referee.scores)
    }
}
