import XCTest
@testable import MinikMultiPingPong

// Android app/src/test/.../cross/CrossAdversarialTest.kt (MinikCrossPong 828c6fc).
/// A skeptical reviewer's attempts to break the 3/4-player engine: exact geometric degeneracies, rule corner cases,
/// network and restore races, hostile input, and thousands of random rallies replayed against the rules.
final class CrossAdversarialTests: XCTestCase {
    private let starter = MPTuning.values(.easy)
    private let tables = [CrossGeometry(3), CrossGeometry(4)]
    private let zero = MPPoint(0, 0)
    private let step = CrossEngine.step

    override func setUp() {
        super.setUp()
        // JUnit stops a test at its first failed assertion; the long loops below rely on the same behaviour.
        continueAfterFailure = false
    }

    // MARK: - Helpers

    /// `players` seats: `local` is the LOCAL human, `remote` are REMOTE humans, everybody else a house player.
    private func table(_ players: Int, local: Int? = 0, remote: Set<Int> = []) -> [CrossSeat] {
        let names = ["mia", "june", "amber", "kyra"]
        var seats: [CrossSeat] = []
        for i in 0..<players {
            if local == i {
                seats.append(humanSeat(i))
            } else if remote.contains(i) {
                seats.append(humanSeat(i, .remote))
            } else {
                seats.append(houseSeat(i, names[i]))
            }
        }
        return seats
    }

    /// Kotlin `houseTable(*names.toTypedArray())`.
    private func houseLineup(_ names: [String]) -> [CrossSeat] {
        var seats: [CrossSeat] = []
        for (i, name) in names.enumerated() { seats.append(houseSeat(i, name)) }
        return seats
    }

    /// The guest's view of the host's seats: seat 0 (the host) is REMOTE, seat 1 (the guest) LOCAL.
    private func guestSeats(_ hostSeats: [CrossSeat]) -> [CrossSeat] {
        var seats: [CrossSeat] = []
        for seat in hostSeats {
            var copy = seat
            if seat.index == 0 { copy.kind = .remote } else if seat.index == 1 { copy.kind = .local }
            seats.append(copy)
        }
        return seats
    }

    /// Restores a live rally in `phase` with exactly this ball (no timers, no grace, no last strike).
    private func live(_ e: CrossEngine, _ ball: CrossBallState, _ phase: CrossRallyPhase, _ striker: Int, _ receiver: Int? = nil,
                      hits: Int = 1, scores: [Int]? = nil) {
        var base = e.exportState()
        base.referee.phase = phase
        base.referee.striker = striker
        base.referee.receiver = receiver
        base.referee.hits = hits
        if let scores { base.referee.scores = scores }
        base.ball = ball
        base.pointDelay = nil
        base.serveDelay = nil
        base.grace = nil
        base.strike = nil
        do { try e.restoreState(base) } catch { XCTFail("live restore failed: \(error)") }
        e.discardEvents()
    }

    /// A return by REMOTE `seat` from inside its strike zone toward `to`, as that seat's phone would publish it.
    private func remoteReturn(_ e: CrossEngine, _ seat: Int, _ to: Int) -> CrossStrike {
        let g = e.geometry
        let at = g.fromLocal(seat, 0.1, 1.0)
        let launch = CrossShots.targeted(g, e.physics, from: at, height: 0.15, target: g.fromLocal(to, 0, 0.8), pace: 0.9)
        let ball = CrossBallState(position: at, height: 0.15, velocity: launch.velocity, lift: launch.lift)
        return CrossStrike(seat: seat, point: at, height: 0.15, ball: ball, serve: false, rallyId: e.referee.rallyId,
                           hitIndex: e.referee.hits + 1)
    }

    /// A flat, hard ball from `seat` into the net toward its right-hand neighbour (the house player's net fault).
    private func netBall(_ g: CrossGeometry, _ seat: Int) -> CrossBallState {
        let from = g.home(seat)
        let to = g.fromLocal(g.wrap(seat + 1), 0, 0.45)
        let spans = g.netSpans(from, to)
        XCTAssertFalse(spans.isEmpty, "a net lies between \(seat) and its neighbour")
        let f = spans.map { $0.start }.min() ?? 0
        let tau = 0.4
        let drop: Double = 0.5 * starter.gravity * tau * tau
        let lift: Double = (starter.netHeight * 0.4 - 0.1 + drop) / tau
        return CrossBallState(position: from, height: 0.1, velocity: (to - from) * (f / tau), lift: lift)
    }

    private func assertAlike(_ expected: [Double], _ actual: [Double], _ message: String) {
        XCTAssertEqual(expected.count, actual.count, "\(message): \(expected) / \(actual)")
        for i in 0..<min(expected.count, actual.count) {
            XCTAssertEqual(expected[i], actual[i], accuracy: 1e-9, "\(message) [\(i)]: \(expected) / \(actual)")
        }
    }

    /// Kotlin `reference::class`: 0 bounce, 1 net, 2 landed, -1 none.
    private func ballEventKind(_ event: CrossBallEvent?) -> Int {
        guard let found = event else { return -1 }
        switch found {
        case .bounce: return 0
        case .net: return 1
        case .landed: return 2
        }
    }

    private func netEventHeight(_ event: CrossBallEvent?) -> Double? {
        if case let .net(_, height)? = event { return height }
        return nil
    }

    private func bounceEventOwner(_ event: CrossBallEvent?) -> Int? {
        if case let .bounce(_, owner)? = event { return owner }
        return nil
    }

    /// Kotlin `filterIsInstance<CrossEvent.X>()` and `is CrossEvent.X` checks.
    private enum Scan {
        static func served(_ events: [CrossEvent]) -> [Int] {
            var found: [Int] = []
            for event in events { if case let .served(seat) = event { found.append(seat) } }
            return found
        }
        static func victories(_ events: [CrossEvent]) -> [Int] {
            var found: [Int] = []
            for event in events { if case let .victory(seat) = event { found.append(seat) } }
            return found
        }
        static func netStrikers(_ events: [CrossEvent]) -> [Int] {
            var found: [Int] = []
            for event in events { if case let .net(striker, _, _) = event { found.append(striker) } }
            return found
        }
        static func bounces(_ events: [CrossEvent]) -> [(owner: Int, point: MPPoint)] {
            var found: [(owner: Int, point: MPPoint)] = []
            for event in events { if case let .bounce(owner, point) = event { found.append((owner: owner, point: point)) } }
            return found
        }
        static func isBounce(_ event: CrossEvent, owner: Int) -> Bool {
            if case let .bounce(found, _) = event { return found == owner }
            return false
        }
        static func isAnyBounce(_ event: CrossEvent) -> Bool {
            if case .bounce = event { return true }
            return false
        }
        static func isContact(_ event: CrossEvent) -> Bool {
            if case .contact = event { return true }
            return false
        }
        static func isServed(_ event: CrossEvent) -> Bool {
            if case .served = event { return true }
            return false
        }
        static func isSwing(_ event: CrossEvent) -> Bool {
            if case .swing = event { return true }
            return false
        }
        static func isRally(_ event: CrossEvent) -> Bool {
            if case .rally = event { return true }
            return false
        }
        static func isVictory(_ event: CrossEvent) -> Bool {
            if case .victory = event { return true }
            return false
        }
        /// A rally, victory, serve or contact: what a finished match never produces.
        static func isLoud(_ event: CrossEvent) -> Bool {
            isRally(event) || isVictory(event) || isServed(event) || isContact(event)
        }
    }

    /// Kotlin `quiet`: none of the events is a rally, victory, serve or contact.
    private func isQuiet(_ events: [CrossEvent]) -> Bool { !events.contains(where: { Scan.isLoud($0) }) }

    // MARK: - Geometry and ball

    // Kotlin: degenerateFlightsThroughThePostAndAlongNetLinesBehaveTheSameFromEverySeat
    func testDegenerateFlightsThroughThePostAndAlongNetLinesBehaveTheSameFromEverySeat() {
        for g in tables {
            let tip = g.nets[0].end
            let along = tip * (1 / tip.length)
            let normal = MPPoint(-along.y, along.x)
            let beyondTip = tip * 1.2
            let backAlong = along * -2.0
            let nearCentre = along * 0.1
            let midNet = tip * 0.5
            let nudge = normal * 1e-6
            let besideNet = midNet + nudge
            let otherSide = midNet - nudge
            let flights: [CrossBallState] = [
                CrossBallState(position: MPPoint(0, 0.3), height: 0.06, velocity: MPPoint(0, -1), lift: 0.5),   // 0 low along a centre line: the post
                CrossBallState(position: MPPoint(0, 0.3), height: 0.2, velocity: MPPoint(0, -1), lift: 0.3),    // 1 over the post, then the line beyond it
                CrossBallState(position: MPPoint(0, 0.3), height: 0.3, velocity: MPPoint(0, -2), lift: 1.0),    // 2 over the post and the whole line beyond
                CrossBallState(position: beyondTip, height: 0.07, velocity: backAlong, lift: 0),                // 3 from beyond a net's tip straight down its line
                CrossBallState(position: nearCentre, height: 0.2, velocity: along, lift: 0.3),                  // 4 from the centre outward along a net
                CrossBallState(position: MPPoint(CrossGeometry.post, 0.3), height: 0.06, velocity: MPPoint(0, -1), lift: 0.5), // 5 grazing the post
                CrossBallState(position: zero, height: 0.3, velocity: zero, lift: 0),                           // 6 dropped onto the post
                CrossBallState(position: midNet, height: 0.3, velocity: zero, lift: 0),                         // 7 dropped onto a net
                CrossBallState(position: besideNet, height: 0.3, velocity: zero, lift: 0),                      // 8 dropped just beside it
                CrossBallState(position: otherSide, height: 0.3, velocity: zero, lift: 0),                      // 9 ... on its other side
            ]
            for (i, base) in flights.enumerated() {
                guard let reference = CrossBall(g, tuning: starter, initial: base).firstEvent().event else {
                    XCTFail("\(g.players) players, case \(i): no event")
                    continue
                }
                for k in g.seats {
                    // The very same flight seen from seat k: rotate(p, θk) maps seat 0's frame onto seat k's.
                    var turned = base
                    turned.position = CrossGeometry.rotate(base.position, g.angle(k))
                    turned.velocity = CrossGeometry.rotate(base.velocity, g.angle(k))
                    guard let event = CrossBall(g, tuning: starter, initial: turned).firstEvent().event else {
                        XCTFail("\(g.players) players, case \(i), seat \(k): no event")
                        continue
                    }
                    let label = "\(g.players) players, case \(i), seat \(k): \(reference) / \(event)"
                    XCTAssertEqual(ballEventKind(reference), ballEventKind(event), label)
                    assertNear(CrossGeometry.rotate(reference.point, g.angle(k)), event.point, 1e-9, label)
                    if case let .net(_, referenceHeight) = reference {
                        XCTAssertEqual(referenceHeight, netEventHeight(event) ?? -1, accuracy: 1e-9, label)
                    }
                    if case let .bounce(_, referenceOwner) = reference {
                        XCTAssertEqual(g.wrap(referenceOwner + k), bounceEventOwner(event), label)
                    }
                }
            }
            // Seat 0's own outcomes are the physically right ones.
            func firstOf(_ i: Int) -> CrossBallEvent? { CrossBall(g, tuning: starter, initial: flights[i]).firstEvent().event }
            let gravity = starter.gravity
            if case let .net(point, height)? = firstOf(0) {
                assertNear(MPPoint(0, CrossGeometry.post), point, 1e-12)
                let expected: Double = 0.06 + 0.5 * 0.265 - 0.5 * gravity * 0.265 * 0.265
                XCTAssertEqual(expected, height, accuracy: 1e-12)
            } else {
                XCTFail("\(g.players) players: the post: \(String(describing: firstOf(0)))")
            }
            let beyond = firstOf(1)
            if g.players == 3 {
                // The line through the post continues along the net between the two far seats: down onto its top.
                if case let .net(point, height)? = beyond {
                    XCTAssertEqual(starter.netHeight, height, accuracy: 1e-9)
                    let root: Double = sqrt(0.09 + 2 * gravity * (0.2 - starter.netHeight))
                    let y: Double = 0.3 - (0.3 + root) / gravity
                    assertNear(MPPoint(0, y), point, 1e-9)
                } else {
                    XCTFail("3 players: beyond the post: \(String(describing: beyond))")
                }
            } else {
                if case let .bounce(point, owner)? = beyond {
                    XCTAssertEqual(2, owner)
                    let root: Double = sqrt(0.09 + 2 * gravity * 0.2)
                    let y: Double = 0.3 - (0.3 + root) / gravity
                    assertNear(MPPoint(0, y), point, 1e-9)
                } else {
                    XCTFail("4 players: beyond the post: \(String(describing: beyond))")
                }
            }
            if case let .landed(point)? = firstOf(2) {
                let root: Double = sqrt(1 + 2 * gravity * 0.3)
                let y: Double = 0.3 - 2 * (1 + root) / gravity
                assertNear(MPPoint(0, y), point, 1e-9)
            } else {
                XCTFail("\(g.players) players: far: \(String(describing: firstOf(2)))")
            }
            if case let .net(point, _)? = firstOf(3) {
                assertNear(tip, point, 1e-9)
            } else {
                XCTFail("\(g.players) players: at the tip: \(String(describing: firstOf(3)))")
            }
            if case let .net(point, height)? = firstOf(4) {
                XCTAssertEqual(starter.netHeight, height, accuracy: 1e-9)
                XCTAssertTrue(point.dot(along) < tip.length && abs(point.cross(along)) < 1e-12, "\(point)")
            } else {
                XCTFail("\(g.players) players: on top: \(String(describing: firstOf(4)))")
            }
            XCTAssertEqual(1, ballEventKind(firstOf(5)))
            XCTAssertEqual(starter.netHeight, netEventHeight(firstOf(6)) ?? -1, accuracy: 1e-9)
            XCTAssertEqual(starter.netHeight, netEventHeight(firstOf(7)) ?? -1, accuracy: 1e-9)
            let expectedSides: Set<Int?> = [g.nets[0].left, g.nets[0].right]
            let sides: Set<Int?> = [bounceEventOwner(firstOf(8)), bounceEventOwner(firstOf(9))]
            XCTAssertEqual(expectedSides, sides)
        }
    }

    // Kotlin: aBallLandingBesideATerritoryBorderBelongsToItsSideAndOnTheBorderMeetsTheNet
    func testABallLandingBesideATerritoryBorderBelongsToItsSideAndOnTheBorderMeetsTheNet() {
        for g in tables {
            for net in g.nets {
                for s in [0.12, 0.5, 0.97] {
                    let on = net.end * s
                    let normal = MPPoint(-net.end.y, net.end.x) * (1 / net.end.length)
                    for side in [1.0, -1.0] {
                        let p = on + normal * (1e-7 * side)
                        let between = g.dir(net.left) - g.dir(net.right)
                        let owner = (normal * side).dot(between) > 0 ? net.left : net.right
                        let dropped = CrossBallState(position: p, height: 0.3, velocity: zero, lift: 0)
                        let found = CrossBall(g, tuning: starter, initial: dropped).firstEvent().event
                        XCTAssertEqual(CrossBallEvent.bounce(point: p, owner: owner), found, "\(net) \(s) \(side)")
                    }
                    let onBorder = CrossBallState(position: on, height: 0.3, velocity: zero, lift: 0)
                    let hit = CrossBall(g, tuning: starter, initial: onBorder).firstEvent().event
                    let netTop = starter.netHeight
                    let meetsNet = netEventHeight(hit).map { abs($0 - netTop) < 1e-9 } ?? false
                    XCTAssertTrue(meetsNet, "\(net) \(s) \(String(describing: hit))")
                }
            }
        }
        // Beyond the tip of a 4-player net lies the notch between two arms: off the table.
        let four = CrossGeometry(4)
        let notch = CrossBallState(position: four.nets[0].end * 1.0001, height: 0.3, velocity: zero, lift: 0)
        XCTAssertEqual(2, ballEventKind(CrossBall(four, tuning: starter, initial: notch).firstEvent().event))
    }

    // Kotlin: hugeNegativeAndNonFiniteFrameTimesNeverBreakTheClockOrTheBall
    func testHugeNegativeAndNonFiniteFrameTimesNeverBreakTheClockOrTheBall() {
        func makeEngine() -> CrossEngine { CrossEngine(seats: houseTable("kyra", "mia", "june"), control: .beginner, target: 7, seed: 13) }
        let a = makeEngine()
        let b = makeEngine()
        a.advance(1e9)
        for _ in 0..<4 { b.advance(step) }
        XCTAssertEqual(b.exportState(), a.exportState(), "a huge frame is one capped frame")
        a.advance(Double.infinity)
        for _ in 0..<4 { b.advance(step) }
        XCTAssertEqual(b.exportState(), a.exportState())
        let frames: [Double] = [-1.0, -Double.infinity, Double.nan, -0.0, 0.0]
        for dt in frames {
            a.advance(dt)
            XCTAssertEqual(b.exportState(), a.exportState(), "frame \(dt)")
        }
        // A dropped (NaN) frame must not stop the clock: both play on identically.
        for _ in 0..<600 {
            a.advance(1.0 / 60)
            b.advance(1.0 / 60)
        }
        XCTAssertTrue(b.referee.ralliesPlayed > 0 || b.referee.phase != .awaitingServe, "the match moved on")
        XCTAssertEqual(b.exportState(), a.exportState())
        // The ball itself: a NaN step leaves it untouched, a huge one is a single capped step.
        let g = CrossGeometry(4)
        let start = CrossBallState(position: MPPoint(0, 0.9), height: 0.2, velocity: MPPoint(0.1, -0.8), lift: 0.9)
        let ball = CrossBall(g, tuning: starter, initial: start)
        XCTAssertNil(ball.step(Double.nan))
        XCTAssertEqual(start, ball.state)
        XCTAssertNil(ball.step(-Double.infinity))
        XCTAssertEqual(start, ball.state)
        let capped = CrossBall(g, tuning: starter, initial: start)
        capped.step(1e9)
        let once = CrossBall(g, tuning: starter, initial: start)
        once.step(CrossBall.maxStep)
        XCTAssertEqual(once.state, capped.state)
        XCTAssertTrue(capped.state.valid())
    }

    // MARK: - Rules

    // Kotlin: competingResolutionsInOneSubstepResolveTheRallyExactlyOnce
    func testCompetingResolutionsInOneSubstepResolveTheRallyExactlyOnce() throws {
        for g in tables {
            let receiver = 1
            let secondBounce: (CrossReferee) -> CrossRallyOutcome? = { r in
                r.ball(.bounce(point: r.geometry.fromLocal(receiver, 0.1, 1.05), owner: receiver))
            }
            let otherTerritory: (CrossReferee) -> CrossRallyOutcome? = { r in
                r.ball(.bounce(point: r.geometry.fromLocal(2, 0, 0.8), owner: 2))
            }
            let landing: (CrossReferee) -> CrossRallyOutcome? = { r in r.ball(.landed(point: MPPoint(3, 3))) }
            let netting: (CrossReferee) -> CrossRallyOutcome? = { r in r.ball(.net(point: MPPoint(0.1, 0.1), height: 0.02)) }
            let leftZone: (CrossReferee) -> CrossRallyOutcome? = { r in
                r.follow(CrossBallState(position: r.geometry.fromLocal(receiver, 0, 1.4), height: 0.3, velocity: r.geometry.dir(receiver), lift: 0.1))
            }
            let graceExpiry: (CrossReferee) -> CrossRallyOutcome? = { r in r.miss() }
            let triggers: [(String, (CrossReferee) -> CrossRallyOutcome?)] = [
                ("second bounce", secondBounce),
                ("bounce in another territory", otherTerritory),
                ("landing", landing),
                ("net", netting),
                ("left the strike zone", leftZone),
                ("grace expiry", graceExpiry),
            ]
            for (firstName, firstTrigger) in triggers {
                for (secondName, secondTrigger) in triggers {
                    let r = CrossReferee(g, target: 7)
                    var opening = r.exportState()
                    opening.scores = Array(repeating: 2, count: g.players)
                    try r.restore(opening)
                    XCTAssertTrue(r.serve(0))
                    XCTAssertNil(r.ball(.bounce(point: g.fromLocal(0, 0, 0.8), owner: 0)))
                    XCTAssertNil(r.ball(.bounce(point: g.fromLocal(receiver, 0, 0.85), owner: receiver)))
                    let one = firstTrigger(r)
                    let two = secondTrigger(r)
                    XCTAssertNotNil(one, firstName)
                    XCTAssertNil(two, "\(firstName) then \(secondName)")
                    guard let outcome = one else { continue }
                    XCTAssertEqual(CrossRallyKind.missed, outcome.kind)
                    XCTAssertEqual(receiver, outcome.receiver)
                    XCTAssertEqual(1, r.ralliesPlayed)
                    // Kotlin assertSame: the outcome is a value type here.
                    XCTAssertEqual(outcome, r.lastOutcome)
                    let expected = (0..<g.players).map { $0 == 0 ? 3 : ($0 == receiver ? 1 : 2) }
                    XCTAssertEqual(expected, r.scores)
                    XCTAssertFalse(r.strike(receiver))
                    XCTAssertNil(r.serveFault(r.server))
                }
            }
        }
        // In the engine: a remote receiver's grace running out in the very substep in which its ball also lands off the
        // table (or one substep later, or not yet started), and a local receiver without grace. One resolution each time.
        let e = CrossEngine(seats: table(4, local: 0, remote: [1]), control: .beginner, target: 7, seed: 4, networked: true)
        let g = e.geometry
        let landing = CrossBallState(position: g.fromLocal(1, 0, 1.3), height: 0.002, velocity: g.dir(1) * 0.5, lift: -0.5)
        let graces: [Double?] = [step, 2 * step, nil]
        for left in graces {
            live(e, landing, .receivable, 2, 1, scores: [1, 1, 1, 1])
            var withGrace = e.exportState()
            withGrace.grace = left
            try e.restoreState(withGrace)
            let events = e.play(CrossEngine.graceTime + 0.2)
            let label = "grace \(String(describing: left))"
            XCTAssertEqual(1, events.rallies().count, label)
            XCTAssertEqual(CrossRallyKind.missed, events.rallies().first?.kind, label)
            XCTAssertEqual([1, 0, 2, 1], e.referee.scores, label)
        }
        let local = CrossEngine(seats: table(4, local: 1), control: .beginner, target: 7, seed: 4)
        live(local, landing, .receivable, 2, 1, scores: [1, 1, 1, 1])
        local.touch(g.fromLocal(1, -0.6, 0.72))
        local.endTouch()
        let localEvents = local.play(1.0)
        XCTAssertEqual([CrossRallyKind.missed], localEvents.rallies().map { $0.kind })
    }

    // Kotlin: aFaultAtZeroByAnySeatLeavesTheScoreboardAloneButEndsTheRally
    func testAFaultAtZeroByAnySeatLeavesTheScoreboardAloneButEndsTheRally() throws {
        for g in tables {
            for seat in g.seats {
                for kind in [CrossRallyKind.net, .out, .ownSide, .badServe] {
                    let r = CrossReferee(g, target: 7, firstServer: kind == .badServe ? seat : g.wrap(seat + 1))
                    let scores = (0..<g.players).map { $0 == seat ? 0 : 3 }
                    var opening = r.exportState()
                    opening.scores = scores
                    try r.restore(opening)
                    let server = r.server
                    XCTAssertTrue(r.serve(server))
                    let label = "\(g.players) players, seat \(seat), \(kind)"
                    let found: CrossRallyOutcome?
                    if kind == .badServe {
                        found = r.ball(.bounce(point: g.fromLocal(seat, 0, 0.3), owner: seat))
                    } else {
                        XCTAssertNil(r.ball(.bounce(point: g.fromLocal(server, 0, 0.8), owner: server)))
                        XCTAssertNil(r.ball(.bounce(point: g.fromLocal(seat, 0, 0.85), owner: seat)))
                        XCTAssertTrue(r.strike(seat))
                        let event: CrossBallEvent
                        switch kind {
                        case .net: event = .net(point: MPPoint(0.05, 0.05), height: 0.03)
                        case .out: event = .landed(point: MPPoint(4, 0))
                        default: event = .bounce(point: g.fromLocal(seat, 0.1, 0.6), owner: seat)
                        }
                        found = r.ball(event)
                    }
                    guard let outcome = found else {
                        XCTFail("\(label): no outcome")
                        continue
                    }
                    XCTAssertEqual(kind, outcome.kind, label)
                    XCTAssertEqual(seat, outcome.faultOwner, label)
                    XCTAssertNil(outcome.receiver, label)
                    XCTAssertTrue(outcome.floored, label)
                    XCTAssertTrue(outcome.deltas.allSatisfy { $0 == 0 }, label)
                    XCTAssertEqual(scores, outcome.scoresAfter, label)
                    XCTAssertEqual(scores, r.scores, label)
                    XCTAssertEqual(1, outcome.rallyId)
                    XCTAssertEqual(g.wrap(server + 1), outcome.nextServer)
                    XCTAssertNil(outcome.winner)
                    XCTAssertEqual(1, r.faults[seat])
                    XCTAssertTrue(r.nextRally())
                    XCTAssertEqual(2, r.rallyId)
                    XCTAssertEqual(g.wrap(server + 1), r.server)
                }
            }
        }
        // Through the engine: a net and a long ball by every seat at 0 resolve with nothing to subtract, and play goes on.
        for g in tables {
            for seat in g.seats {
                for long in [false, true] {
                    let e = CrossEngine(seats: table(g.players, local: nil), control: .beginner, target: 7, seed: 3)
                    let scores = (0..<g.players).map { $0 == seat ? 0 : 3 }
                    let from = g.home(seat)
                    let ball: CrossBallState
                    if long {
                        let target = g.fromLocal(g.wrap(seat + 1), 0, CrossGeometry.reach + 0.25)
                        let launch = CrossShots.targeted(g, e.physics, from: from, height: 0.1, target: target, pace: 0.9)
                        ball = CrossBallState(position: from, height: 0.1, velocity: launch.velocity, lift: launch.lift)
                    } else {
                        ball = netBall(g, seat)
                    }
                    live(e, ball, .toReceiver, seat, scores: scores)
                    let events = e.play(6.0) { e.referee.resolved }
                    let label = "\(g.players) players, seat \(seat), long \(long)"
                    let rallies = events.rallies()
                    XCTAssertEqual(1, rallies.count, label)
                    guard let outcome = rallies.first else { continue }
                    XCTAssertEqual(long ? CrossRallyKind.out : CrossRallyKind.net, outcome.kind, label)
                    XCTAssertEqual(seat, outcome.faultOwner, label)
                    XCTAssertTrue(outcome.floored, label)
                    XCTAssertTrue(outcome.deltas.allSatisfy { $0 == 0 }, label)
                    XCTAssertEqual(scores, e.referee.scores, label)
                    if !long { XCTAssertEqual([seat], Scan.netStrikers(events), label) }
                    let next = e.play(CrossEngine.pointDelayTime + 0.1) { e.referee.rallyId != outcome.rallyId }
                    XCTAssertEqual(outcome.rallyId + 1, e.referee.rallyId, label)
                    XCTAssertEqual(outcome.nextServer, e.referee.server, label)
                    XCTAssertTrue(next.rallies().isEmpty, label)
                }
            }
        }
    }

    // Kotlin: aServeThatBouncesTwiceOnTheServersOwnSideIsABadServe
    func testAServeThatBouncesTwiceOnTheServersOwnSideIsABadServe() throws {
        for players in 3...4 {
            // A genuine but feeble Pro swipe: the serve makes its own bounce and dies on the same arm.
            let e = CrossEngine(seats: table(players), control: .pro, target: 7, seed: 2)
            let g = e.geometry
            let spot = g.toView(0, e.serveSpot(0))
            e.touch(g.fromView(0, spot + MPPoint(0, 0.06)))
            e.touch(g.fromView(0, spot - MPPoint(0, 0.06)), velocity: MPPoint(0, -0.05), down: false)
            e.endTouch()
            let events = e.play(4.0) { e.referee.resolved }
            XCTAssertEqual([0], Scan.served(events))
            let bounces = Scan.bounces(events)
            XCTAssertEqual([0, 0], bounces.map { $0.owner }, "\(players) \(bounces)")
            if let firstBounce = bounces.first {
                XCTAssertTrue(g.inServeZone(0, firstBounce.point))
            } else {
                XCTFail("\(players): no bounce")
            }
            let rallies = events.rallies()
            XCTAssertEqual(1, rallies.count)
            guard let outcome = rallies.first else { continue }
            XCTAssertEqual(CrossRallyKind.badServe, outcome.kind)
            XCTAssertEqual(0, outcome.faultOwner)
            XCTAssertNil(outcome.receiver)
            XCTAssertTrue(outcome.floored)
            XCTAssertEqual(Array(repeating: 0, count: players), outcome.deltas)
        }
        // For every server with points: it costs the server only.
        for g in tables {
            for s in g.seats {
                let r = CrossReferee(g, target: 7, firstServer: s)
                var opening = r.exportState()
                opening.scores = Array(repeating: 3, count: g.players)
                try r.restore(opening)
                XCTAssertTrue(r.serve(s))
                XCTAssertNil(r.ball(.bounce(point: g.fromLocal(s, 0.1, 0.8), owner: s)))
                guard let o = r.ball(.bounce(point: g.fromLocal(s, 0.1, 0.6), owner: s)) else {
                    XCTFail("\(g.players) players, server \(s): no outcome")
                    continue
                }
                XCTAssertEqual(CrossRallyKind.badServe, o.kind)
                XCTAssertEqual(s, o.faultOwner)
                XCTAssertEqual((0..<g.players).map { $0 == s ? -1 : 0 }, o.deltas)
            }
        }
    }

    // Kotlin: aLegalBounceNearTheHubRunningOnIntoAnotherTerritoryIsOnlyTheReceiversMiss
    func testALegalBounceNearTheHubRunningOnIntoAnotherTerritoryIsOnlyTheReceiversMiss() {
        let kinds: [CrossSeatKind] = [.local, .remote, .house]
        for g in tables {
            for r in g.seats {
                for q in g.seats where q != r {
                    for kind in kinds {
                        guard let sender = g.seats.first(where: { $0 != r && $0 != q }) else { continue }
                        let localSeat: Int? = kind == .local ? r : nil
                        let remoteSeats: Set<Int> = kind == .remote ? [r] : []
                        let seats = table(g.players, local: localSeat, remote: remoteSeats)
                        let e = CrossEngine(seats: seats, control: .beginner, target: 7, seed: 5, networked: kind == .remote)
                        // Right after a legal bounce close to the centre of r's territory, heading over the net into q's arm.
                        let bounce = g.fromLocal(r, 0, 0.3)
                        XCTAssertEqual(r, g.owner(bounce))
                        let launch = CrossShots.targeted(g, e.physics, from: bounce, height: 0, target: g.fromLocal(q, 0, 0.9), pace: 0.9)
                        let ball = CrossBallState(position: bounce, height: 0, velocity: launch.velocity, lift: launch.lift)
                        live(e, ball, .receivable, sender, r, scores: Array(repeating: 2, count: g.players))
                        let events = e.play(8.0) { e.referee.resolved }
                        let label = "\(g.players) players, \(kind) receiver \(r), into \(q), from \(sender)"
                        let rallies = events.rallies()
                        XCTAssertEqual(1, rallies.count, label)
                        guard let outcome = rallies.first else { continue }
                        XCTAssertEqual(CrossRallyKind.missed, outcome.kind, label)
                        XCTAssertEqual(r, outcome.receiver, label)
                        XCTAssertEqual(sender, outcome.striker, label)
                        let expected = (0..<g.players).map { $0 == sender ? 3 : ($0 == r ? 1 : 2) }
                        XCTAssertEqual(expected, e.referee.scores, label)
                        XCTAssertFalse(events.contains(where: { Scan.isContact($0) }), "\(label): nobody may touch it")
                    }
                }
            }
        }
    }

    // Kotlin: aBallLeavingTheReceiversReachIsMissedInTheAirWithoutWaitingForItToLand
    func testABallLeavingTheReceiversReachIsMissedInTheAirWithoutWaitingForItToLand() {
        for g in tables {
            for r in g.seats {
                for sideways in [false, true] {
                    for remote in [false, true] {
                        let sender = g.wrap(r + 1)
                        let localSeat: Int? = remote ? nil : r
                        let remoteSeats: Set<Int> = remote ? [r] : []
                        let e = CrossEngine(seats: table(g.players, local: localSeat, remote: remoteSeats), control: .beginner, target: 7,
                                            seed: 6, networked: remote)
                        let way = sideways ? g.right(r) : g.dir(r)
                        let ball = CrossBallState(position: g.fromLocal(r, 0.1, 1.0), height: 0, velocity: way * 1.5, lift: 2.0)
                        live(e, ball, .receivable, sender, r, scores: Array(repeating: 1, count: g.players))
                        // A local receiver waits with its paddle on the far side, so it never touches the ball.
                        if !remote {
                            e.touch(g.fromLocal(r, -0.6, 0.72))
                            e.endTouch()
                        }
                        let label = "\(g.players) players, seat \(r), sideways \(sideways), remote \(remote)"
                        let events = e.play(1.0) { e.referee.resolved || e.referee.unreachable(e.ballState) }
                        // A local receiver's miss is called on the spot; a remote one is still receivable, inside its grace.
                        XCTAssertTrue(remote ? e.referee.unreachable(e.ballState) : e.referee.resolved, label)
                        let local = g.toLocal(r, e.ballPosition)
                        XCTAssertTrue(e.ballHeight > 0.1, "\(label): still in the air")
                        XCTAssertFalse(events.contains(where: { Scan.isAnyBounce($0) }), "\(label): no second bounce")
                        if sideways {
                            let limit: Double = CrossGeometry.strikeHalf + 1.5 * step + 1e-9
                            XCTAssertTrue(abs(local.u) > CrossGeometry.strikeHalf && abs(local.u) < limit, "\(label) \(local)")
                        } else {
                            let limit: Double = CrossGeometry.strikeFar + 1.5 * step + 1e-9
                            XCTAssertTrue(local.v > CrossGeometry.strikeFar && local.v < limit, "\(label) \(local)")
                        }
                        let outcomes: [CrossRallyOutcome]
                        if remote {
                            XCTAssertTrue(events.rallies().isEmpty, label)
                            outcomes = e.play(CrossEngine.graceTime + 0.1).rallies()
                        } else {
                            outcomes = events.rallies()
                        }
                        XCTAssertEqual(1, outcomes.count, label)
                        guard let outcome = outcomes.first else { continue }
                        XCTAssertEqual(CrossRallyKind.missed, outcome.kind, label)
                        XCTAssertEqual(r, outcome.receiver, label)
                        XCTAssertEqual(sender, outcome.striker, label)
                        let expected = (0..<g.players).map { $0 == sender ? 2 : ($0 == r ? 0 : 1) }
                        XCTAssertEqual(expected, e.referee.scores, label)
                        XCTAssertTrue(e.play(1.0).rallies().isEmpty, label)
                    }
                }
            }
        }
    }

    // Kotlin: noControlLevelCanStrikeTheBallBeforeItsReceivingBounce
    func testNoControlLevelCanStrikeTheBallBeforeItsReceivingBounce() {
        for players in 3...4 {
            for control in CrossControl.allCases {
                for peer in [false, true] {
                    let e = CrossEngine(seats: table(players), control: control, target: 7, seed: 4, networked: peer)
                    e.authoritative = !peer
                    let g = e.geometry
                    // A deep bounce: on its way in the ball crosses the receiver's strike zone first.
                    e.approaching(from: 2, to: 0, u: 0.05, v: 1.02)
                    e.play(3.0) { g.inStrikeZone(0, e.ballPosition) }
                    XCTAssertEqual(CrossRallyPhase.toReceiver, e.referee.phase)
                    let label = "\(players) players \(control) peer \(peer)"
                    var events: [CrossEvent] = []
                    var firstTouch = true
                    var bounced = false
                    var spins = 0
                    // Every substep until the receiving bounce the human goes straight for the ball. (A legal contact may come in
                    // the very substep of the bounce, so the loop ends there.)
                    while !bounced && e.referee.phase == .toReceiver && spins < 7200 {
                        spins += 1
                        let at = g.toView(0, e.ballPosition)
                        switch control {
                        case .beginner:
                            e.touch(e.ballPosition, down: firstTouch)
                        case .standard, .starter:
                            e.touch(e.ballPosition)
                            e.endTouch()
                        case .pro:
                            e.touch(g.fromView(0, at + MPPoint(0, 0.05)))
                            e.touch(g.fromView(0, at - MPPoint(0, 0.05)), velocity: MPPoint(0, -1), down: false)
                            e.endTouch()
                        }
                        firstTouch = false
                        XCTAssertEqual(1, e.referee.hits, "\(label): no contact before the bounce")
                        e.advance(step)
                        let drained = e.drainEvents()
                        events += drained
                        bounced = drained.contains(where: { Scan.isBounce($0, owner: 0) })
                    }
                    XCTAssertTrue(bounced, label)
                    events = e.play(1.0, into: events)
                    let bounce = events.firstIndex(where: { Scan.isBounce($0, owner: 0) })
                    let contact = events.firstIndex(where: { Scan.isContact($0) })
                    XCTAssertNotNil(bounce, label)
                    if let contact {
                        XCTAssertTrue(contact > (bounce ?? -1), "\(label): the contact must follow the receiving bounce")
                    }
                }
            }
        }
    }

    // Kotlin: nobodyButTheResponsibleReceiverCanTouchTheBall
    func testNobodyButTheResponsibleReceiverCanTouchTheBall() {
        for players in 3...4 {
            let g = CrossGeometry(players)
            // REMOTE strikes from the wrong seat are refused and change nothing, while the ball is still on its way to its
            // receiver (no catch-up for a seat it is not predicted to reach) or already receivable.
            for receivable in [false, true] {
                let e = CrossEngine(seats: table(players, local: 0, remote: [1, 2]), control: .beginner, target: 7, seed: 8, networked: true)
                if receivable { e.incoming(from: 0, to: 1) } else { e.approaching(from: 0, to: 1) }
                XCTAssertEqual(1, e.predictedReceiver)
                let before = e.exportState()
                let wrong = remoteReturn(e, 2, 0)
                XCTAssertFalse(e.applyRemoteStrike(2, wrong, rallyId: wrong.rallyId, hitIndex: wrong.hitIndex))
                // The receiver itself, but from another seat's strike zone or with a skipped hit index.
                var elsewhere = remoteReturn(e, 1, 0)
                elsewhere.point = g.fromLocal(2, 0.1, 1.0)
                elsewhere.ball.position = g.fromLocal(2, 0.1, 1.0)
                XCTAssertFalse(e.applyRemoteStrike(1, elsewhere, rallyId: elsewhere.rallyId, hitIndex: elsewhere.hitIndex))
                var skipped = remoteReturn(e, 1, 0)
                skipped.hitIndex += 1
                XCTAssertFalse(e.applyRemoteStrike(1, skipped, rallyId: skipped.rallyId, hitIndex: skipped.hitIndex))
                XCTAssertEqual(before, e.exportState(), "\(players) receivable \(receivable)")
                XCTAssertTrue(e.drainEvents().isEmpty)
                let right = remoteReturn(e, 1, 0)
                XCTAssertTrue(e.applyRemoteStrike(1, right, rallyId: right.rallyId, hitIndex: right.hitIndex))
                XCTAssertEqual(1, e.referee.striker)
            }
            // A local human whose paddle sits right on somebody else's ball never touches it.
            for control in CrossControl.allCases {
                let e = CrossEngine(seats: table(players, local: 0, remote: [1]), control: control, target: 7, seed: 8, networked: true)
                let ball = CrossBallState(position: g.fromLocal(0, 0, 0.85), height: 0.1, velocity: g.dir(0) * 0.4, lift: 0.9)
                live(e, ball, .receivable, 2, 1)
                var events: [CrossEvent] = []
                for tick in 0..<90 {
                    let at = g.toView(0, e.ballPosition)
                    switch control {
                    case .beginner:
                        e.touch(e.ballPosition, down: tick == 0)
                    case .standard, .starter:
                        e.touch(e.ballPosition)
                        e.endTouch()
                    case .pro:
                        e.touch(g.fromView(0, at + MPPoint(0, 0.05)))
                        e.touch(g.fromView(0, at - MPPoint(0, 0.05)), velocity: MPPoint(0, -1), down: false)
                        e.endTouch()
                    }
                    e.advance(step)
                    events += e.drainEvents()
                }
                XCTAssertTrue(events.contacts(0).isEmpty, "\(players) \(control)")
                XCTAssertEqual(1, e.referee.hits)
            }
        }
    }

    // MARK: - Network, restore, pause

    // Kotlin: theRemoteGraceRunsItsFullSpanAndAStrikeInItsLastSubstepStillCounts
    func testTheRemoteGraceRunsItsFullSpanAndAStrikeInItsLastSubstepStillCounts() {
        func waiting() -> CrossEngine {
            let e = CrossEngine(seats: table(4, local: 0, remote: [1]), control: .beginner, target: 7, seed: 4, networked: true)
            e.incoming(from: 2, to: 1, scores: [0, 1, 1, 0])
            var ticks = 0
            while e.exportState().grace == nil {
                if ticks >= 600 {
                    XCTFail("the grace never started")
                    break
                }
                ticks += 1
                e.advance(step)
                XCTAssertTrue(e.drainEvents().rallies().isEmpty)
            }
            return e
        }
        let span = Int((CrossEngine.graceTime / step).rounded())
        XCTAssertEqual(CrossEngine.graceTime, waiting().exportState().grace ?? -1, accuracy: 1e-12, "the grace starts at its full length")
        // One substep before it runs out a late strike still wins over the timeout; wrong or repeated strikes never do.
        let late = waiting()
        for _ in 0..<(span - 1) { late.advance(step) }
        XCTAssertTrue(late.drainEvents().rallies().isEmpty)
        XCTAssertEqual(CrossRallyPhase.receivable, late.referee.phase)
        var stray = remoteReturn(late, 1, 3)
        stray.hitIndex += 1
        XCTAssertFalse(late.applyRemoteStrike(1, stray, rallyId: stray.rallyId, hitIndex: stray.hitIndex))
        XCTAssertNotNil(late.exportState().grace)
        let strike = remoteReturn(late, 1, 3)
        XCTAssertTrue(late.applyRemoteStrike(1, strike, rallyId: strike.rallyId, hitIndex: strike.hitIndex))
        XCTAssertNil(late.exportState().grace)
        XCTAssertFalse(late.applyRemoteStrike(1, strike, rallyId: strike.rallyId, hitIndex: strike.hitIndex))
        XCTAssertEqual(1, late.referee.striker)
        XCTAssertEqual(3, late.predictedReceiver)
        XCTAssertTrue(late.play(1.0).rallies().isEmpty)
        // Without it, MISSED comes on exactly the substep the grace runs out, once; a strike after that is stale.
        let missed = waiting()
        for _ in 0..<(span - 1) { missed.advance(step) }
        XCTAssertTrue(missed.drainEvents().rallies().isEmpty)
        missed.advance(step)
        let rallies = missed.drainEvents().rallies()
        XCTAssertEqual(1, rallies.count)
        if let outcome = rallies.first {
            XCTAssertEqual(CrossRallyKind.missed, outcome.kind)
            XCTAssertEqual(1, outcome.receiver)
            XCTAssertEqual(2, outcome.striker)
        }
        XCTAssertEqual([0, 0, 2, 0], missed.referee.scores)
        let stale = remoteReturn(missed, 1, 3)
        XCTAssertFalse(missed.applyRemoteStrike(1, stale, rallyId: stale.rallyId, hitIndex: stale.hitIndex))
        XCTAssertTrue(missed.play(2.0).rallies().isEmpty)
    }

    /// A scripted Beginner human who acts while the ball is still on its way to it (a real player does; acting only once
    /// the ball is receivable is too late, since the retained paddle may already have returned it): a tap serve; for every
    /// ball predicted to reach it, the paddle on the ball with a drag aim or, now and then, deliberately elsewhere.
    private final class Human {
        private static let aims: [Double] = [-70, -20, 0, 20, 70]
        private let e: CrossEngine
        private var random: MPKotlinRandom
        private let missRate: Double
        /// Kotlin `decided: Pair<Int, Int>?` as [rallyId, hits]; empty = none yet.
        private var decided: [Int] = []
        private var skip = false
        private var aim = 0.0

        init(_ e: CrossEngine, seed: Int32, missRate: Double) {
            self.e = e
            self.random = MPKotlinRandom(intSeed: seed)
            self.missRate = missRate
        }

        func step() {
            let g = e.geometry
            guard let local = e.localSeat else { return }
            let r = e.referee
            if e.status == .yourServe {
                if decided != [r.rallyId, -1] {
                    decided = [r.rallyId, -1]
                    let u = random.nextDouble(-0.25, 0.25)
                    let v = random.nextDouble(0.65, 0.9)
                    let tap = g.fromLocal(local, u, v)
                    e.touch(tap)
                    let drag = random.element(Human.aims)
                    e.touch(tap, drag: MPPoint(drag, 0), down: false)
                    e.endTouch()
                }
                return
            }
            let mine: Bool
            if r.phase == .receivable { mine = r.receiver == local } else { mine = e.predictedReceiver == local }
            if !mine { return }
            if decided != [r.rallyId, r.hits] {
                decided = [r.rallyId, r.hits]
                skip = random.nextDouble() < missRate
                aim = random.element(Human.aims)
                e.touch(g.fromLocal(local, 0, CrossGeometry.homeDepth))
            }
            let ball = g.toLocal(local, e.ballPosition)
            let at = skip ? g.fromLocal(local, ball.u > 0 ? -0.6 : 0.6, CrossGeometry.homeDepth) : e.ballPosition
            if g.inStrikeZone(local, at) { e.touch(at, drag: MPPoint(aim, 0), down: false) }
        }
    }

    // Kotlin: anAuthorityAndAFollowerPlayAWholeMatchInLockstep
    func testAnAuthorityAndAFollowerPlayAWholeMatchInLockstep() throws {
        for players in 3...4 {
            // The host is the authority with the local seat 0; the guest follows with the local seat 1. A minimal link
            // publishes every committed guest hit once and hands the guest a checkpoint every substep.
            let hostSeats = table(players, local: 0, remote: [1])
            let seed = Int64(21 + players)
            let host = CrossEngine(seats: hostSeats, control: .beginner, target: 5, seed: seed, networked: true, firstServer: 1)
            let guest = CrossEngine(seats: guestSeats(hostSeats), control: .beginner, target: 5, seed: seed, networked: true, firstServer: 1)
            guest.authoritative = false
            let hostScript = Human(host, seed: 1, missRate: 0.2)
            let guestScript = Human(guest, seed: 2, missRate: 0.2)
            var hostEvents: [CrossEvent] = []
            var guestEvents: [CrossEvent] = []
            var published: CrossStrike? = nil
            var hits = 0
            var steps = 0
            while host.referee.winner == nil && steps < 7200 * 60 {
                steps += 1
                hostScript.step()
                guestScript.step()
                host.advance(step)
                guest.advance(step)
                if let s = guest.localStrike(), s != published {
                    published = s
                    hits += 1
                    XCTAssertTrue(host.applyRemoteStrike(1, s, rallyId: s.rallyId, hitIndex: s.hitIndex),
                                  "\(players) players: the authority accepts the guest's hit \(s)")
                }
                try guest.restoreState(host.exportState(), preserveInput: true)
                hostEvents += host.drainEvents()
                guestEvents += guest.drainEvents()
                let hostReferee = host.referee.exportState()
                let guestReferee = guest.referee.exportState()
                if hostReferee != guestReferee {
                    XCTAssertEqual(hostReferee, guestReferee, "\(players) players, substep \(steps)")
                    break
                }
                if host.ballState != guest.ballState {
                    XCTAssertEqual(host.ballState, guest.ballState, "\(players) players, substep \(steps)")
                    break
                }
            }
            guard let winner = host.referee.winner else {
                XCTFail("\(players) players: the match ends")
                continue
            }
            XCTAssertTrue(hits >= 5, "\(players) players: the guest played (\(hits) hits)")
            // Both sides announce the same rallies, each exactly once, and one victory.
            XCTAssertEqual(hostEvents.rallies(), guestEvents.rallies())
            XCTAssertEqual(host.referee.ralliesPlayed, hostEvents.rallies().count)
            XCTAssertEqual([winner], Scan.victories(hostEvents))
            XCTAssertEqual([winner], Scan.victories(guestEvents))
            // Every contact of every seat is seen once on each side.
            for seat in 0..<players {
                XCTAssertEqual(hostEvents.contacts(seat).count, guestEvents.contacts(seat).count, "\(players) players, seat \(seat)")
            }
        }
    }

    // Kotlin: aFollowerBehindASlowLinkStillPlaysTheSameMatch
    func testAFollowerBehindASlowLinkStillPlaysTheSameMatch() throws {
        let holdLimit = Int(0.85 / step)
        for players in 3...4 {
            for latency in [3, 12] {
                // Each way the link takes `latency` substeps. As the spec's link does, the guest holds back checkpoints that do
                // not yet acknowledge its own latest hit, for at most 850 ms.
                let hostSeats = table(players, local: 0, remote: [1])
                let seed = Int64(40 + players + latency)
                let host = CrossEngine(seats: hostSeats, control: .beginner, target: 5, seed: seed, networked: true, firstServer: 1)
                let guest = CrossEngine(seats: guestSeats(hostSeats), control: .beginner, target: 5, seed: seed, networked: true, firstServer: 1)
                guest.authoritative = false
                let hostScript = Human(host, seed: 3, missRate: 0.2)
                let guestScript = Human(guest, seed: 4, missRate: 0.2)
                var toHost: [(at: Int, strike: CrossStrike)] = []
                var toGuest: [(at: Int, state: CrossState)] = []
                var hostEvents: [CrossEvent] = []
                var guestEvents: [CrossEvent] = []
                var held: (hit: CrossStrike, at: Int)? = nil
                var published: CrossStrike? = nil
                var hits = 0
                var steps = 0
                let label = "\(players) players, latency \(latency)"
                while host.referee.winner == nil || guest.referee.winner == nil {
                    if steps >= 7200 * 60 {
                        XCTFail("\(label): the match ends")
                        break
                    }
                    steps += 1
                    hostScript.step()
                    guestScript.step()
                    host.advance(step)
                    guest.advance(step)
                    if let s = guest.localStrike(), s != published {
                        published = s
                        held = (hit: s, at: steps)
                        hits += 1
                        toHost.append((at: steps + latency, strike: s))
                    }
                    while let head = toHost.first, head.at <= steps {
                        toHost.removeFirst()
                        let s = head.strike
                        XCTAssertTrue(host.applyRemoteStrike(1, s, rallyId: s.rallyId, hitIndex: s.hitIndex),
                                      "\(label): the authority accepts the guest's hit \(s)")
                    }
                    toGuest.append((at: steps + latency, state: host.exportState()))
                    while let head = toGuest.first, head.at <= steps {
                        toGuest.removeFirst()
                        let state = head.state
                        if let pending = held {
                            let sameStrike = state.strike == pending.hit
                            let otherRally = state.referee.rallyId != pending.hit.rallyId
                            let laterHit = state.referee.hits > pending.hit.hitIndex
                            let settled = state.referee.phase == .resolved
                            let acknowledged = sameStrike || otherRally || laterHit || settled
                            if acknowledged || steps - pending.at > holdLimit { held = nil }
                        }
                        if held == nil { try guest.restoreState(state, preserveInput: true) }
                    }
                    hostEvents += host.drainEvents()
                    guestEvents += guest.drainEvents()
                }
                XCTAssertTrue(hits >= 5, "\(label): the guest played (\(hits) hits)")
                XCTAssertEqual(host.referee.exportState(), guest.referee.exportState(), label)
                XCTAssertEqual(hostEvents.rallies(), guestEvents.rallies(), label)
                XCTAssertEqual(host.referee.ralliesPlayed, guestEvents.rallies().count, label)
                let expectedVictory: [Int?] = [host.referee.winner]
                let guestVictories: [Int?] = Scan.victories(guestEvents).map { Optional($0) }
                let hostVictories: [Int?] = Scan.victories(hostEvents).map { Optional($0) }
                XCTAssertEqual(expectedVictory, guestVictories, label)
                XCTAssertEqual(expectedVictory, hostVictories, label)
            }
        }
    }

    // Kotlin: anAuthorityAlwaysServesForItsHouseServer
    func testAnAuthorityAlwaysServesForItsHouseServer() throws {
        // The link may keep the engine a follower until it knows the fixture's authority: once it is the authority, its
        // house server still serves.
        let e = CrossEngine(seats: table(4, local: 0, remote: [1]), control: .beginner, target: 7, seed: 4, networked: true, firstServer: 2)
        e.authoritative = false
        XCTAssertFalse(e.play(2.0).contains(where: { Scan.isServed($0) }))
        XCTAssertEqual(CrossRallyPhase.awaitingServe, e.referee.phase)
        e.authoritative = true
        let served = e.play(CrossEngine.serveDelayTime + 0.1) { e.referee.phase != .awaitingServe }
        XCTAssertEqual([2], Scan.served(served))
        // Nor does a checkpoint without the house serve timer (as a follower would write it) freeze the next rally.
        let waiting = CrossEngine(seats: table(4, local: 0, remote: [1]), control: .beginner, target: 7, seed: 4, networked: true, firstServer: 3)
        let state = waiting.exportState()
        XCTAssertNotNil(state.serveDelay)
        let reopened = CrossEngine(seats: table(4, local: 0, remote: [1]), control: .beginner, target: 7, seed: 4, networked: true)
        var untimed = state
        untimed.serveDelay = nil
        try reopened.restoreState(untimed)
        let serve = reopened.play(CrossEngine.serveDelayTime + 0.1) { reopened.referee.phase != .awaitingServe }
        XCTAssertEqual([3], Scan.served(serve))
    }

    // Kotlin: restartDropsAPendingGrace
    func testRestartDropsAPendingGrace() {
        let e = CrossEngine(seats: table(4, local: 0, remote: [1]), control: .beginner, target: 7, seed: 4, networked: true, firstServer: 2)
        e.incoming(from: 2, to: 1)
        e.play(5.0) { e.exportState().grace != nil }
        XCTAssertNotNil(e.exportState().grace)
        e.restart()
        XCTAssertNil(e.exportState().grace)
        XCTAssertNil(e.pointDelay)
        XCTAssertEqual(1, e.referee.rallyId)
        XCTAssertEqual(CrossRallyPhase.awaitingServe, e.referee.phase)
        XCTAssertFalse(e.play(0.65).contains(where: { Scan.isRally($0) || Scan.isServed($0) }))
    }

    // Kotlin: restoringDuringThePointDelayKeepsTheScheduleAndNeverRepeatsTheRally
    func testRestoringDuringThePointDelayKeepsTheScheduleAndNeverRepeatsTheRally() throws {
        let lineup = houseTable("kyra", "mia", "june", "gaya")
        let a = CrossEngine(seats: lineup, control: .beginner, target: 7, seed: 9)
        let opening = a.play(60.0) { a.referee.resolved }
        let firstRallies = opening.rallies()
        XCTAssertEqual(1, firstRallies.count)
        guard let outcome = firstRallies.first else { return }
        a.play(1.0)
        let state = a.exportState()
        XCTAssertEqual(CrossEngine.pointDelayTime - 1.0, state.pointDelay ?? -1, accuracy: 1e-9)
        let b = CrossEngine(seats: lineup, control: .beginner, target: 7, seed: 9)
        try b.restoreState(state)
        XCTAssertTrue(b.drainEvents().isEmpty)
        // A peer following the same checkpoint announces the rally once, however often the checkpoint arrives.
        let peer = CrossEngine(seats: table(4, local: 0, remote: [1]), control: .beginner, target: 7, seed: 9, networked: true)
        peer.authoritative = false
        for _ in 0..<3 { try peer.restoreState(state, preserveInput: true) }
        XCTAssertEqual([outcome], peer.drainEvents().rallies())
        var ticks = 0
        while a.referee.phase == .resolved {
            a.advance(step)
            b.advance(step)
            peer.advance(step)
            ticks += 1
            XCTAssertEqual(a.referee.phase, b.referee.phase)
            XCTAssertEqual(a.referee.phase, peer.referee.phase)
            for e in [a, b, peer] { XCTAssertTrue(e.drainEvents().rallies().isEmpty) }
        }
        XCTAssertEqual(Int(((CrossEngine.pointDelayTime - 1.0) / step).rounded()), ticks)
        for e in [a, b, peer] {
            XCTAssertEqual(outcome.rallyId + 1, e.referee.rallyId)
            XCTAssertEqual(outcome.nextServer, e.referee.server)
        }
        // The restored authority's house server serves after the usual house serve delay, like the original.
        for e in [a, b] {
            var wait = 0
            var served: [CrossEvent] = []
            while !served.contains(where: { Scan.isServed($0) }) {
                if wait >= 240 {
                    XCTFail("no serve within 240 substeps")
                    break
                }
                wait += 1
                e.advance(step)
                served += e.drainEvents()
            }
            XCTAssertEqual(Int(CrossEngine.serveTicks), wait)
            XCTAssertEqual([outcome.nextServer], Scan.served(served))
        }
    }

    // Kotlin: aFinishedMatchStaysFinishedThroughRestoresInputAndTime
    func testAFinishedMatchStaysFinishedThroughRestoresInputAndTime() throws {
        let lineup = houseTable("kyra", "moshiko", "amber", "june")
        let house = CrossEngine(seats: lineup, control: .beginner, target: 3, seed: 12)
        let played = house.play(1800.0) { house.referee.winner != nil }
        guard let winner = house.referee.winner else {
            XCTFail("the house match ends")
            return
        }
        XCTAssertEqual([winner], Scan.victories(played))
        let finalState = house.exportState()
        XCTAssertTrue(isQuiet(house.play(20.0)))
        // A fresh engine adopting the final checkpoint has nothing to announce and nothing left to play.
        let fresh = CrossEngine(seats: lineup, control: .beginner, target: 3, seed: 12)
        try fresh.restoreState(finalState)
        XCTAssertTrue(fresh.drainEvents().isEmpty)
        XCTAssertTrue(isQuiet(fresh.play(20.0)))
        XCTAssertEqual(finalState.referee, fresh.referee.exportState())
        XCTAssertEqual(CrossStatus.matchOver, fresh.status)
        XCTAssertFalse(fresh.referee.nextRally())
        // A peer following it announces the last rally and the victory exactly once; input and time change nothing.
        let peer = CrossEngine(seats: table(4, local: 0, remote: [1]), control: .beginner, target: 3, seed: 12, networked: true)
        peer.authoritative = false
        for _ in 0..<3 { try peer.restoreState(finalState, preserveInput: true) }
        let announced = peer.drainEvents()
        let expectedLast: [CrossRallyOutcome?] = [finalState.referee.lastOutcome]
        let announcedRallies: [CrossRallyOutcome?] = announced.rallies().map { Optional($0) }
        XCTAssertEqual(expectedLast, announcedRallies)
        XCTAssertEqual([winner], Scan.victories(announced))
        XCTAssertEqual(winner == 0 ? CrossStatus.youWon : CrossStatus.matchOver, peer.status)
        let g = peer.geometry
        peer.touch(g.fromLocal(0, 0, 0.8))
        peer.touch(g.fromLocal(0, 0, 0.8), drag: MPPoint(60, 0), down: false)
        peer.endTouch()
        XCTAssertTrue(isQuiet(peer.play(10.0)))
        XCTAssertEqual(finalState.referee, peer.referee.exportState())
        // An authority holding it refuses any further remote strike.
        let authority = CrossEngine(seats: table(4, local: 0, remote: [1]), control: .beginner, target: 3, seed: 12, networked: true)
        try authority.restoreState(finalState)
        let late = remoteReturn(authority, 1, 2)
        XCTAssertFalse(authority.applyRemoteStrike(1, late, rallyId: late.rallyId, hitIndex: late.hitIndex))
        XCTAssertTrue(isQuiet(authority.play(10.0)))
        XCTAssertEqual(finalState.referee, authority.referee.exportState())
    }

    // Kotlin: aRejectedCheckpointLeavesTheEngineExactlyAsItWas
    func testARejectedCheckpointLeavesTheEngineExactlyAsItWas() {
        let e = CrossEngine(seats: table(4, local: 0, remote: [1]), control: .beginner, target: 7, seed: 4, networked: true)
        e.incoming(from: 2, to: 1, scores: [1, 2, 3, 0])
        e.play(0.3)
        let good = e.exportState()
        var bad: [CrossState] = []
        var overTarget = good
        overTarget.referee.scores = [1, 2, 8, 0]
        bad.append(overTarget)
        var shortScores = good
        shortScores.referee.scores = [1, 2, 3]
        bad.append(shortScores)
        var noReceiver = good
        noReceiver.referee.receiver = nil
        bad.append(noReceiver)
        var earlyWinner = good
        earlyWinner.referee.winner = 2
        bad.append(earlyWinner)
        var badServer = good
        badServer.referee.server = 4
        bad.append(badServer)
        var nanHeight = good
        nanHeight.ball.height = Double.nan
        bad.append(nanHeight)
        var hugeVelocity = good
        hugeVelocity.ball.velocity = MPPoint(1e9, 0)
        bad.append(hugeVelocity)
        var fewMotions = good
        fewMotions.motions = Array(good.motions.prefix(3))
        bad.append(fewMotions)
        var nanMotion = good
        if nanMotion.motions.count > 2 { nanMotion.motions[2].u = Double.nan }
        bad.append(nanMotion)
        var nanDelay = good
        nanDelay.pointDelay = Double.nan
        bad.append(nanDelay)
        var endlessGrace = good
        endlessGrace.grace = Double.infinity
        bad.append(endlessGrace)
        // A last strike by a seat that does not exist (a missing seat reads back as -1).
        var noSeat = good
        noSeat.strike = CrossStrike(seat: -1, point: good.ball.position, height: 0.1, ball: good.ball, serve: false,
                                    rallyId: good.referee.rallyId, hitIndex: good.referee.hits)
        bad.append(noSeat)
        var fifthSeat = good
        fifthSeat.strike = CrossStrike(seat: 4, point: good.ball.position, height: 0.1, ball: good.ball, serve: false,
                                       rallyId: good.referee.rallyId, hitIndex: good.referee.hits)
        bad.append(fifthSeat)
        for (i, state) in bad.enumerated() {
            for preserve in [false, true] {
                XCTAssertThrowsError(try e.restoreState(state, preserveInput: preserve), "\(i) \(preserve)")
                XCTAssertEqual(good, e.exportState(), "\(i) \(preserve)")
                XCTAssertTrue(e.drainEvents().isEmpty)
            }
        }
        // It simply plays on: the ball passes the remote receiver, which then gets its grace.
        e.play(4.0) { e.referee.resolved }
        XCTAssertEqual(CrossRallyKind.missed, e.referee.lastOutcome?.kind)
        // A house server's serve timer that is not a number is refused before anything changes, too.
        let serving = CrossEngine(seats: table(4, local: 0, remote: [1]), control: .beginner, target: 7, seed: 4, networked: true, firstServer: 2)
        let due = serving.exportState()
        XCTAssertNotNil(due.serveDelay)
        let other = CrossEngine(seats: table(4, local: 0, remote: [1]), control: .beginner, target: 7, seed: 4, networked: true)
        other.incoming(from: 2, to: 3)
        let before = other.exportState()
        var nanServe = due
        nanServe.serveDelay = Double.nan
        XCTAssertThrowsError(try other.restoreState(nanServe))
        XCTAssertEqual(before, other.exportState())
    }

    /// A complete serve gesture in seat 0's view: a tap and drag (Beginner/Standard) or a swipe through the ball (Pro).
    private func serveGesture(_ e: CrossEngine) {
        let g = e.geometry
        if e.control == .pro {
            let spot = g.toView(0, e.serveSpot(0))
            e.touch(g.fromView(0, spot + MPPoint(0, 0.07)))
            e.touch(g.fromView(0, spot - MPPoint(0, 0.07)), drag: MPPoint(0, -40), velocity: MPPoint(0.1, -1), down: false)
        } else {
            e.touch(g.fromLocal(0, 0.1, 0.8))
            e.touch(g.fromLocal(0, 0.1, 0.8), drag: MPPoint(60, 0), velocity: MPPoint(0, -0.5), down: false)
        }
        e.endTouch()
    }

    /// A complete return gesture right at the ball for the engine's control level.
    private func returnGesture(_ e: CrossEngine) {
        let g = e.geometry
        let at = g.toView(0, e.ballPosition)
        switch e.control {
        case .beginner:
            e.touch(e.ballPosition)
            e.touch(e.ballPosition, drag: MPPoint(-60, 0), down: false)
        case .standard, .starter:
            e.touch(e.ballPosition)
            e.touch(e.ballPosition, drag: MPPoint(-60, 0), velocity: MPPoint(0, -0.8), down: false)
        case .pro:
            e.touch(g.fromView(0, at + MPPoint(0, 0.06)))
            e.touch(g.fromView(0, at - MPPoint(0, 0.06)), velocity: MPPoint(0, -1.1), down: false)
        }
        e.endTouch()
    }

    // Kotlin: aPausedEngineIgnoresEveryGestureAndStandsStill
    func testAPausedEngineIgnoresEveryGestureAndStandsStill() {
        for players in 3...4 {
            for control in CrossControl.allCases {
                let label = "\(players) players \(control)"
                // The local serve while paused: no swing, no serve, nothing queued for later.
                let e = CrossEngine(seats: table(players), control: control, target: 7, seed: 1)
                e.paused = true
                let before = e.exportState()
                serveGesture(e)
                for _ in 0..<60 { e.advance(1.0 / 60) }
                XCTAssertEqual(before, e.exportState(), label)
                XCTAssertTrue(e.drainEvents().isEmpty, label)
                e.paused = false
                let resumed = e.play(2.0)
                XCTAssertFalse(resumed.contains(where: { Scan.isServed($0) || Scan.isSwing($0) || Scan.isContact($0) }), label)
                XCTAssertEqual(CrossStatus.yourServe, e.status, label)
                // A return while paused: the paddle, a tap or a swipe right through the ball does nothing.
                e.incoming(from: 1, to: 0)
                e.touch(e.geometry.fromLocal(0, -0.6, 0.72))
                e.endTouch()
                e.waitForBall(0, depth: 0.9)
                e.paused = true
                let frozen = e.exportState()
                let paddle = e.restingPaddle
                returnGesture(e)
                for _ in 0..<60 { e.advance(1.0 / 60) }
                XCTAssertEqual(frozen, e.exportState(), label)
                XCTAssertEqual(paddle, e.restingPaddle, label)
                XCTAssertTrue(e.drainEvents().isEmpty, label)
                XCTAssertEqual(1, e.referee.hits, label)
            }
        }
    }

    // MARK: - Input

    // Kotlin: nonFiniteTouchInputNeverReachesTheBall
    func testNonFiniteTouchInputNeverReachesTheBall() {
        let nan = Double.nan
        let inf = Double.infinity
        let junks = [MPPoint(nan, nan), MPPoint(inf, -inf), MPPoint(nan, 0), MPPoint(0, -inf)]
        for junk in junks {
            for players in 3...4 {
                for control in CrossControl.allCases {
                    let label = "\(players) players \(control) \(junk)"
                    // Serving: a zero-size view or a zero frame interval upstream feeds junk positions, drags and speeds.
                    let s = CrossEngine(seats: table(players), control: control, target: 7, seed: 1)
                    let g = s.geometry
                    let spot = g.toView(0, s.serveSpot(0))
                    s.touch(g.fromView(0, spot + MPPoint(0, 0.07)), drag: junk, velocity: junk)
                    s.touch(junk, drag: junk, velocity: junk, down: false)
                    s.touch(g.fromView(0, spot - MPPoint(0, 0.07)), drag: junk, velocity: junk, down: false)
                    s.endTouch()
                    s.play(3.0) {
                        XCTAssertTrue(s.ballState.valid(), "\(label) serve \(s.ballState)")
                        return false
                    }
                    // Returning with the same junk: whatever happens (a junk-free contact may still be made), the ball stays a real
                    // ball and play goes on to a resolution.
                    let e = CrossEngine(seats: table(players), control: control, target: 7, seed: 1)
                    e.incoming(from: 1, to: 0)
                    e.waitForBall(0, depth: 0.9)
                    let at = g.toView(0, e.ballPosition)
                    e.touch(g.fromView(0, at + MPPoint(0, 0.06)), drag: junk, velocity: junk)
                    e.touch(junk, drag: junk, velocity: junk, down: false)
                    e.touch(g.fromView(0, at - MPPoint(0, 0.06)), drag: junk, velocity: junk, down: false)
                    e.endTouch()
                    e.play(60.0) {
                        XCTAssertTrue(e.ballState.valid(), "\(label) return \(e.ballState)")
                        return e.referee.ralliesPlayed > 0
                    }
                    XCTAssertTrue(e.referee.ralliesPlayed > 0, "\(label): play must go on")
                }
            }
        }
    }

    // Kotlin: theSameScreenGestureMeansTheSameShotFromEverySeat
    func testTheSameScreenGestureMeansTheSameShotFromEverySeat() {
        for players in 3...4 {
            for control in CrossControl.allCases {
                var serves: [[Double]] = []
                var returns: [[Double]] = []
                for k in 0..<players { serves.append(servedFrom(players, control, k)) }
                for k in 0..<players { returns.append(returnedFrom(players, control, k)) }
                for k in 1..<players {
                    assertAlike(serves[0], serves[k], "\(players) players \(control) serve from seat \(k)")
                    assertAlike(returns[0], returns[k], "\(players) players \(control) return from seat \(k)")
                }
            }
        }
    }

    /// Seat `k` serves with one fixed screen gesture; what happened, in that seat's own view.
    private func servedFrom(_ players: Int, _ control: CrossControl, _ k: Int) -> [Double] {
        let e = CrossEngine(seats: table(players, local: k), control: control, target: 7, seed: 3, firstServer: k)
        let g = e.geometry
        XCTAssertEqual(CrossStatus.yourServe, e.status)
        if control == .pro {
            let spot = g.toView(k, e.serveSpot(k))
            e.touch(g.fromView(k, spot + MPPoint(0.01, 0.07)))
            e.touch(g.fromView(k, spot + MPPoint(-0.01, -0.07)), drag: MPPoint(-20, -50), velocity: MPPoint(0.25, -1), down: false)
        } else {
            e.touch(g.fromView(k, MPPoint(0.12, 0.8)))
            e.touch(g.fromView(k, MPPoint(0.1, 0.78)), drag: MPPoint(-60, -10), velocity: MPPoint(0.1, -0.7), down: false)
        }
        e.endTouch()
        let events = e.play(4.0) { e.referee.phase == .receivable || e.referee.resolved }
        var seen: [Double] = []
        for b in Scan.bounces(events) {
            let view = g.toView(k, b.point)
            seen += [view.x, view.y, Double(crossMod(b.owner - k, players))]
        }
        for seat in Scan.served(events) { seen.append(Double(crossMod(seat - k, players))) }
        seen.append(Double(e.referee.phase.ordinal))
        let receiver: Double = e.referee.receiver.map { Double(crossMod($0 - k, players)) } ?? -1.0
        seen.append(receiver)
        return seen
    }

    /// Seat `k` returns a ball that arrives the same way from its right-hand neighbour, with one fixed screen gesture.
    private func returnedFrom(_ players: Int, _ control: CrossControl, _ k: Int) -> [Double] {
        let e = CrossEngine(seats: table(players, local: k), control: control, target: 7, seed: 3)
        let g = e.geometry
        e.incoming(from: g.wrap(k + 1), to: k, u: 0.05)
        let at: MPPoint
        switch control {
        case .beginner:
            at = g.toView(k, e.ballAfter(25))
        case .standard, .starter:
            e.waitForBall(k, depth: 0.84)
            at = g.toView(k, e.ballPosition)
        case .pro:
            e.waitForBall(k, depth: 0.9)
            at = g.toView(k, e.ballPosition)
        }
        switch control {
        case .beginner:
            e.touch(g.fromView(k, at))
            e.touch(g.fromView(k, at), drag: MPPoint(-60, 0), down: false)
        case .standard, .starter:
            e.touch(g.fromView(k, at))
            e.touch(g.fromView(k, at + MPPoint(0.01, 0)), drag: MPPoint(45, 0), velocity: MPPoint(0.1, -0.9), down: false)
        case .pro:
            e.touch(g.fromView(k, at + MPPoint(0, 0.06)))
            e.touch(g.fromView(k, at - MPPoint(0, 0.06)), drag: zero, velocity: MPPoint(0.3, -1.1), down: false)
        }
        e.endTouch()
        let tilt = e.paddleTilt
        e.play(1.5) { e.referee.striker == k }
        XCTAssertEqual(k, e.referee.striker, "\(players) \(control) seat \(k) returned")
        let b = e.ballState
        let p = g.toView(k, b.position)
        let v = g.toView(k, b.velocity)
        let rest = g.toView(k, e.restingPaddle)
        let receiver: Double = e.predictedReceiver.map { Double(crossMod($0 - k, players)) } ?? -1.0
        let hits = Double(e.referee.hits)
        return [at.x, at.y, tilt, p.x, p.y, b.height, v.x, v.y, b.lift, rest.x, rest.y, hits, receiver]
    }

    // MARK: - Long random simulation

    /// Replays one spectated match's events, substep by substep, against the rules of the cross game.
    private final class Audit {
        private let e: CrossEngine
        private let n: Int
        private let target: Int
        private var scores: [Int]
        private var rally: Int
        private var striker = -1
        private var serving = false
        private var bounces = 0
        private var legal: Int? = nil
        private var lastOwner = -1
        private var netted = false
        private var over = false
        private var victories = 0
        private var rackets: [MPPoint]
        private(set) var outcomes: [CrossRallyOutcome] = []

        init(_ engine: CrossEngine) {
            e = engine
            n = engine.players
            target = engine.referee.target
            scores = engine.referee.scores
            rally = engine.referee.rallyId
            var start: [MPPoint] = []
            for seat in 0..<engine.players { start.append(engine.racket(seat)) }
            rackets = start
        }

        func tick(_ events: [CrossEvent]) {
            var resolutions = 0
            for event in events where Scan.isRally(event) { resolutions += 1 }
            if resolutions > 1 { XCTFail("one resolution per substep: \(events)") }
            if over && events.contains(where: { Scan.isLoud($0) }) { XCTFail("a finished match stays finished: \(events)") }
            for (i, event) in events.enumerated() {
                switch event {
                case let .contact(seat, _, _, _):
                    let servedNext = i + 1 < events.count && events[i + 1] == CrossEvent.served(seat: seat)
                    onContact(seat, served: servedNext)
                case let .bounce(owner, _):
                    bounces += 1
                    lastOwner = owner
                    if bounces == (serving ? 2 : 1) { legal = owner }
                case let .net(netStriker, _, _):
                    netted = true
                    XCTAssertEqual(striker, netStriker)
                case let .rally(outcome):
                    onRally(outcome)
                case let .victory(seat):
                    victories += 1
                    over = true
                    XCTAssertEqual(outcomes.last?.winner, seat)
                    XCTAssertEqual(e.referee.winner, seat)
                case .served, .swing, .eliminated, .stage:
                    break
                }
            }
            let now = e.referee.scores
            if now != scores { XCTAssertEqual(scores, now, "only resolutions change the score") }
            let limit = target
            if !now.allSatisfy({ $0 >= 0 && $0 <= limit }) { XCTFail("scores stay within 0..target: \(now)") }
            if e.referee.rallyId != rally {
                XCTAssertEqual(rally + 1, e.referee.rallyId, "rally ids advance one by one")
                rally = e.referee.rallyId
                XCTAssertEqual(crossMod(e.referee.firstServer + e.referee.ralliesPlayed, n), e.referee.server, "the serve rotates every rally")
                striker = -1
                serving = false
                bounces = 0
                legal = nil
                netted = false
            }
            if !e.ballState.valid() { XCTFail("the ball stays a real ball: \(e.ballState)") }
            for seat in 0..<n {
                let at = e.racket(seat)
                let reach: Double = 1.5 * e.motion(seat).speedLimit * CrossEngine.step + 1e-9
                if !(at.distance(rackets[seat]) <= reach) { XCTFail("seat \(seat) moved faster than its feet allow") }
                rackets[seat] = at
            }
        }

        private func onContact(_ seat: Int, served: Bool) {
            if served {
                XCTAssertEqual(e.referee.server, seat, "only the server serves")
                XCTAssertEqual(-1, striker, "one serve per rally")
                striker = seat
                serving = true
                bounces = 0
                legal = nil
                netted = false
                return
            }
            // A return: right after its legal bounce in the hitter's own territory; never a volley, never somebody else's ball.
            XCTAssertEqual(serving ? 2 : 1, bounces, "contact only right after the legal bounce")
            XCTAssertEqual(legal, seat, "only the responsible receiver strikes")
            XCTAssertNotEqual(striker, seat)
            striker = seat
            serving = false
            bounces = 0
            legal = nil
            netted = false
        }

        private func onRally(_ o: CrossRallyOutcome) {
            XCTAssertEqual(rally, o.rallyId, "each rally resolves once, in order: \(o)")
            XCTAssertEqual(outcomes.count + 1, o.rallyId)
            XCTAssertEqual(striker, o.striker, "\(o)")
            switch o.kind {
            case .missed:
                XCTAssertNotNil(legal, "\(o)")
                XCTAssertEqual(legal, o.receiver, "\(o)")
                XCTAssertNil(o.faultOwner)
            case .badServe:
                XCTAssertTrue(serving, "\(o)")
            case .net:
                XCTAssertFalse(serving, "\(o)")
                XCTAssertTrue(netted, "\(o)")
                XCTAssertEqual(0, bounces, "\(o)")
            case .out:
                XCTAssertFalse(serving, "\(o)")
                XCTAssertFalse(netted, "\(o)")
                XCTAssertEqual(0, bounces, "\(o)")
            case .ownSide:
                XCTAssertFalse(serving, "\(o)")
                XCTAssertEqual(1, bounces, "\(o)")
                XCTAssertEqual(striker, lastOwner, "\(o)")
            }
            if o.kind != .missed {
                XCTAssertEqual(striker, o.faultOwner, "\(o)")
                XCTAssertNil(o.receiver, "\(o)")
            }
            guard let loser = o.loser else {
                XCTFail("no loser: \(o)")
                return
            }
            var expected = Array(repeating: 0, count: n)
            if o.kind == .missed { expected[o.striker] = 1 }
            if scores[loser] > 0 { expected[loser] = -1 }
            XCTAssertEqual(expected, o.deltas, "\(o)")
            XCTAssertEqual(scores[loser] == 0, o.floored, "\(o)")
            let after = zip(scores, o.deltas).map { $0 + $1 }
            XCTAssertEqual(after, o.scoresAfter, "\(o)")
            let won = o.kind == .missed && after[o.striker] >= target
            let expectedWinner: Int? = won ? o.striker : nil
            XCTAssertEqual(expectedWinner, o.winner, "\(o)")
            XCTAssertEqual(crossMod(e.referee.firstServer + o.rallyId, n), o.nextServer, "\(o)")
            scores = after
            outcomes.append(o)
        }

        func finish() {
            guard let winner = e.referee.winner else {
                XCTFail("the audited match has no winner")
                return
            }
            XCTAssertEqual(1, victories, "exactly one victory")
            XCTAssertEqual(Array(1...e.referee.rallyId), outcomes.map { $0.rallyId })
            XCTAssertEqual(target, e.referee.score(winner))
            let limit = target
            XCTAssertTrue(e.referee.scores.enumerated().allSatisfy { $0.offset == winner || ($0.element >= 0 && $0.element < limit) })
        }
    }

    // Kotlin: theSameSeedPlaysTheSameMatch
    func testTheSameSeedPlaysTheSameMatch() {
        for players in 3...4 {
            let lineup = houseLineup(Array(["kyra", "moshiko", "comet", "june"].prefix(players)))
            func run() -> [CrossEvent] {
                let e = CrossEngine(seats: lineup, control: .standard, target: 5, seed: Int64(99 + players), firstServer: 1)
                return e.play(3600.0) { e.referee.winner != nil }
            }
            let firstRun = run()
            let secondRun = run()
            XCTAssertFalse(firstRun.rallies().isEmpty)
            XCTAssertEqual(firstRun, secondRun)
        }
    }

    // Kotlin: anAuthorityReopenedOverAndOverStillFinishesTheMatchByTheRules
    func testAnAuthorityReopenedOverAndOverStillFinishesTheMatchByTheRules() throws {
        for players in 3...4 {
            let lineup = houseLineup(Array(["kyra", "mia", "june", "gaya"].prefix(players)))
            var e = CrossEngine(seats: lineup, control: .beginner, target: 4, seed: Int64(77 + players))
            var random = MPKotlinRandom(intSeed: Int32(players))
            var outcomes: [CrossRallyOutcome] = []
            var victories = 0
            var steps = 0
            var swaps = 0
            var next = 1 + random.nextIndex(600)
            while e.referee.winner == nil {
                if steps >= 7200 * 60 {
                    XCTFail("\(players) players: the match ends")
                    break
                }
                steps += 1
                e.advance(step)
                for event in e.drainEvents() {
                    if case let .rally(outcome) = event { outcomes.append(outcome) }
                    if case .victory = event { victories += 1 }
                }
                if !e.referee.scores.allSatisfy({ $0 >= 0 }) {
                    XCTFail("\(players) players: negative score \(e.referee.scores)")
                    break
                }
                if !e.ballState.valid() {
                    XCTFail("\(players) players: invalid ball \(e.ballState)")
                    break
                }
                next -= 1
                if next == 0 {
                    // A new process with its own random streams adopts the last checkpoint, sometimes on every substep.
                    next = random.nextIndex(4) == 0 ? 1 : 1 + random.nextIndex(600)
                    let state = e.exportState()
                    e = CrossEngine(seats: lineup, control: .beginner, target: 4, seed: Int64(1000 + swaps))
                    swaps += 1
                    try e.restoreState(state)
                    XCTAssertEqual(state.referee, e.referee.exportState())
                    XCTAssertEqual(state.ball, e.ballState)
                    XCTAssertTrue(e.drainEvents().isEmpty)
                }
            }
            XCTAssertTrue(swaps > 50, "\(players) players: \(swaps) reopenings")
            XCTAssertEqual(Array(1...e.referee.rallyId), outcomes.map { $0.rallyId }, "\(players) players")
            XCTAssertEqual(1, victories)
            var totals = Array(repeating: 0, count: players)
            for o in outcomes {
                for (i, d) in o.deltas.enumerated() where i < players { totals[i] += d }
            }
            XCTAssertEqual(e.referee.scores, totals)
            if let winner = e.referee.winner {
                XCTAssertEqual(4, e.referee.score(winner))
            } else {
                XCTFail("\(players) players: no winner")
            }
        }
    }

    // Kotlin: twoThousandRandomAllHouseRalliesPerTableSizeObeyEveryRule
    func testTwoThousandRandomAllHouseRalliesPerTableSizeObeyEveryRule() {
        let roster = MPRoster.all.map { $0.id }
        let controls = CrossControl.allCases
        for players in 3...4 {
            var random = MPKotlinRandom(intSeed: Int32(7000 + players))
            var kinds = Set<CrossRallyKind>()
            var rallies = 0
            var matches = 0
            var finished = 0
            while rallies < 2000 {
                var lineup: [String] = []
                for _ in 0..<players { lineup.append(roster[random.nextIndex(roster.count)]) }
                // Faults only cost the faulter, so evenly matched weak tables drift toward 0 and long targets can take
                // hundreds of rallies; small targets keep the sample to many complete matches.
                let target = 3 + random.nextIndex(4)
                let control = controls[random.nextIndex(controls.count)]
                let seed = random.nextLong()
                let firstServer = random.nextIndex(players)
                let e = CrossEngine(seats: houseLineup(lineup), control: control, target: target, seed: seed, firstServer: firstServer)
                let audit = Audit(e)
                var ticks = 0
                // Every substep is audited; a rare match still running after an hour of play is left there.
                while e.referee.winner == nil && ticks < 7200 * 60 {
                    ticks += 1
                    e.advance(step)
                    audit.tick(e.drainEvents())
                }
                if e.referee.winner != nil {
                    for _ in 0..<600 {
                        e.advance(step)
                        audit.tick(e.drainEvents())
                    }
                    audit.finish()
                    finished += 1
                }
                for o in audit.outcomes { kinds.insert(o.kind) }
                rallies += e.referee.ralliesPlayed
                matches += 1
            }
            XCTAssertTrue(finished >= matches * 9 / 10 && finished >= 30, "\(players) players: \(finished) of \(matches) matches finished")
            XCTAssertEqual(Set(CrossRallyKind.allCases), kinds, "\(players) players: every way a rally can end occurred")
        }
    }
}
