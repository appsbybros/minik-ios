import Foundation

// Android cross/CrossEngine.kt (MinikCrossPong 5c1aa4d).

enum CrossSeatKind { case local, remote, house }

/// Control levels, their stable room/preference ordinals (Android ControlChoice 4 / 0 / 3) and the classic level that supplies
/// the local human's input forgiveness (Android BEGINNER / STARTER / HARD = iOS `.beginner` / `.easy` / `.superHard`).
enum CrossControl: CaseIterable {
    case beginner, standard, pro
    var choice: Int {
        switch self {
        case .beginner: return 4
        case .standard: return 0
        case .pro: return 3
        }
    }
    var level: MPLevel {
        switch self {
        case .beginner: return .beginner
        case .standard: return .easy
        case .pro: return .superHard
        }
    }
    /// Android `CrossControl.fromChoice(ControlChoice.normalize(value))`.
    static func fromChoice(_ value: Int) -> CrossControl {
        switch MPLevel.control(value) {
        case .easy: return .standard
        case .superHard: return .pro
        default: return .beginner
        }
    }
}

struct CrossSeat: Equatable {
    var index: Int
    var kind: CrossSeatKind
    var id: String
    var name: String
    var bot: MPBot? = nil
    var characterId = ""
    var avatar = 0
    /// A house seat's character: its own profile, else its roster character, else Minik.
    var profile: MPBot { bot ?? MPRoster.find(characterId)?.profile ?? MPRoster.all[0].profile }
}

/// What the status line says, from the local seat's point of view.
enum CrossStatus { case yourServe, otherServe, incoming, yourReturn, inPlay, point, youWon, matchOver, practiceDone }

enum CrossDrill { case serve, returning }
/// Tutorial hook. serve: the local seat serves; returning: `server` (default the next seat) serves to the local seat, which
/// returns. No rally ever scores: the local ball's legal receiving bounce in `expected`'s territory (any opponent when nil) is
/// a success, any fault or miss before it a failure. House players never return in a drill. A daily-journey feed (5c1aa4d) also
/// sets the spread (`feedWidth`), the side (`feedSide`) and the pace of the serve sent to the local seat.
struct CrossExercise {
    var drill: CrossDrill
    var expected: Int? = nil
    var server: Int? = nil
    var feedWidth = 0.0
    var feedSide = 0.0
    var paceMultiplier = 1.0
}
struct CrossTrainingResult: Equatable {
    var success: Bool
    var kind: CrossRallyKind? = nil
    var receiver: Int? = nil
}

/// A simultaneous 3/4-player match on the shared cross table: one ball, one referee, local/remote/house seats. Fixed 1/120 s
/// substeps. Only the authority runs house players and resolves rallies; a networked peer predicts the ball and its own
/// strikes and follows checkpoints.
final class CrossEngine {
    static let step = CrossBall.substep
    static let maxFrame = 1.0 / 30
    static let pointDelayTime = 2.6
    static let serveDelayTime = 0.7
    static let serveTicks = Int64((serveDelayTime / step).rounded())
    static let windupTicks = Int64((CrossActor.windup / step).rounded())
    /// A remote receiver's missed waits this long for its strike to arrive.
    static let graceTime = 0.8
    /// Network ball corrections are blended away over this many seconds.
    static let blend = 0.12
    static let gravity = 3.6
    static let restitution = 0.54
    static let netHeight = 0.075
    /// Beginner contact: paddle within this distance of a receivable ball in the strike zone.
    static let autoReach = 0.22
    /// The widest Beginner aim in dp: the far edge of a side player's arm, never beyond it.
    static let safeDrag = CrossAimMap.farGesture * CrossAimMap.dpPerUnit * 0.9
    /// Standard timing is measured around this contact depth.
    static let idealDepth = CrossGeometry.reach - 0.18
    static let minTimingSpeed = 0.2
    static let serveDepth = CrossGeometry.reach - 0.02
    static let serveTravel = 0.03
    static let swingTravel = 0.015
    /// Pro swipes must move inward faster than this (world units/s).
    static let forward = 0.05
    static let retap = 0.18
    static let remoteApproach = 0.10
    static let strikeTolerance = 0.05
    static let snap = 0.3
    /// A touch farther than this from the table centre (world units) is junk, not a position.
    static let touchLimit = 100.0
    /// Android publishes a strike when the engine's last local strike is a new object (`!==`); iOS numbers them instead.
    private static var strikeCounter = 0
    static func localStroke(_ control: CrossControl) -> MPStroke {
        control == .pro ? MPStroke() : MPStroke(contactAt: 0.10, windowEnd: 0.40, followEnd: 0.50, total: 0.62)
    }
    static func actorStroke() -> MPStroke { MPStroke(contactAt: CrossActor.windup, windowEnd: 0.27, followEnd: CrossActor.followEnd, total: CrossActor.total) }

    let seats: [CrossSeat]
    let control: CrossControl
    let networked: Bool
    let firstServer: Int
    let exercise: CrossExercise?
    let scoring: CrossScoring
    private let startScores: [Int]?
    /// Team play (5c1aa4d): seat membership, a tap on another court picks the return target (`tapTargets`), and a team lesson
    /// whose house players keep feeding `teamLesson`'s teammate.
    let teams: CrossTeams?
    let tapTargets: Bool
    let teamLesson: Int?
    let players: Int
    let geometry: CrossGeometry
    let aims: CrossAimMap
    /// The one local seat; nil when spectating (all-house simulations).
    let localSeat: Int?
    /// The local human's input forgiveness for the selected control level.
    let tuning: MPTuning
    /// The same control values with the table physics every phone shares, whatever its control level.
    let physics: MPTuning
    var automaticContact: Bool { control == .beginner }
    /// Set by the link before the first network frame.
    var authoritative = true
    /// Android `ReceptionAssist`: the shared simulation clock that may slow down before a human's return.
    let reception = CrossReception()
    var paused = false
    private let opening: Int
    private(set) var referee: CrossReferee
    /// Set by the match when this stage is over (an elimination changes the table): no further rally starts.
    var stopAfterRally = false
    private let ball: CrossBall
    private let houses: [Int: CrossHouse]
    private var strokes: [MPStroke]
    private let motions: [CrossMotion]
    private let variation = CrossVariation()
    private var events: [CrossEvent] = []
    /// Android `onEvent`: hears every event as it is added (sounds of screens whose practice drains the engine itself).
    var onEvent: ((CrossEvent) -> Void)?
    private(set) var teamFlight: CrossTeamFlight?
    private var teamLift = false
    private var teamPass = false
    private var teamHoldUntil: Int64 = 0
    /// The court of another player the local player tapped (journeys and team tables): the next return goes there.
    private(set) var selectedAim: MPPoint?
    private var practicePaddlePlaced = false
    /// One raised pass is armed for the local return (a double tap).
    var setArmed: Bool { teamLift }
    /// The live ball is a teammate's raised pass to the local seat: only a swipe returns it.
    var receivingSet: Bool { localSeat != nil && teamFlight?.setReceiver == localSeat }
    func teammate(_ seat: Int) -> Int? { teams?.partner(seat) }
    private var serial = 0
    private var ticks: Int64 = 0
    private var carry = 0.0
    private(set) var pointDelay: Double?
    private var serveAt: Int64?
    private var serveSwing = false
    private var grace: Double?
    /// A peer whose ball reached a decision: the result is the authority's to tell.
    private var settled = false
    private var predicted: Int?
    private var lastStrike: CrossStrike?
    private var ownStrike: CrossStrike?
    /// Changes whenever this phone's player commits a new strike (Android: a new strike object).
    private(set) var localStrikeID = 0
    private var pendingServe: CrossServe?
    private var pendingTap: MPPoint?
    private var serveArmed = false
    private var serveTap: MPPoint?
    private var aimDp = 0.0
    private var gestureSpeed = 0.0
    private var gestureLast: MPPoint?
    /// Beginner: where the latest gesture started inside the strike zone. A small aiming swipe moves the paddle a little; the
    /// automatic hit still counts from where the finger came down, so aiming never costs the return.
    private var gestureAnchor: MPPoint?
    private var gestureTravel = 0.0
    private var gestureCommitted = false
    private var lastVelocity = MPPoint.zero
    private var reconciliation = MPPoint.zero
    private var reconciliationAge = 0.0
    /// Finger paddle (world) while it is in the local strike zone.
    private(set) var paddle: MPPoint?
    /// Last valid strike-zone paddle position; kept after finger-up (Beginner contact uses it).
    private(set) var restingPaddle: MPPoint
    private(set) var paddleTilt = 0.0
    private(set) var bouncePoint: MPPoint?
    private(set) var bounceAge = 1.0
    private(set) var netAge = 1.0
    private(set) var trainingResult: CrossTrainingResult?
    private(set) var trainingTime = 0.0

    /// Android requires 2...4 seats in index order and at most one local seat; the app always builds them so. Seat indices are
    /// renumbered by position here, so a stray index can never break the arrays.
    init(seats input: [CrossSeat], control: CrossControl, target: Int, seed: Int64, networked: Bool = false, firstServer: Int = 0,
         exercise: CrossExercise? = nil, scoring: CrossScoring = .multi, startScores: [Int]? = nil, teams: CrossTeams? = nil,
         tapTargets: Bool = false, teamLesson: Int? = nil) {
        let numbered = input.enumerated().map { item -> CrossSeat in
            var seat = item.element
            seat.index = item.offset
            return seat
        }
        seats = numbered
        self.control = control; self.networked = networked; self.firstServer = firstServer; self.exercise = exercise
        self.scoring = scoring; self.startScores = startScores
        let n = numbered.count
        players = n
        // Android requires team membership to match the table; a mismatch plays individually.
        var membership: CrossTeams?
        if let teams, teams.seats.count == n { membership = teams }
        self.teams = membership; self.tapTargets = tapTargets; self.teamLesson = teamLesson
        teamFlight = membership.map { CrossTeamFlight(members: $0.seats) }
        let g = CrossGeometry(n)
        geometry = g
        aims = CrossAimMap(g)
        let local = numbered.first(where: { $0.kind == .local })?.index
        localSeat = local
        let own = MPTuning.values(control.level)
        tuning = own
        var shared = own
        shared.gravity = CrossEngine.gravity; shared.bounceRestitution = CrossEngine.restitution; shared.netHeight = CrossEngine.netHeight
        physics = shared
        var start: Int?
        if let exercise { start = exercise.drill == .serve ? local : (exercise.server ?? local.map { $0 + 1 }) }
        let opener = start ?? firstServer
        opening = opener
        referee = CrossReferee(g, target: target, firstServer: opener, scoring: scoring, startScores: startScores, teams: membership)
        ball = CrossBall(g, tuning: shared, initial: CrossBallState(position: .zero, height: 0, velocity: .zero, lift: 0, stopped: true))
        // Each house player draws its own well-mixed seed: nearly equal seeds give correlated XorWow streams.
        var master = MPKotlinRandom(seed: seed)
        var built: [Int: CrossHouse] = [:]
        for seat in numbered where seat.kind == .house {
            built[seat.index] = CrossHouse(g, physics: shared, seat: seat.index, profile: seat.profile, control: control.level, seed: master.nextLong())
        }
        houses = built
        strokes = (0..<n).map { $0 == local ? CrossEngine.localStroke(control) : CrossEngine.actorStroke() }
        motions = (0..<n).map { CrossMotion(home: CrossLocal(0, CrossGeometry.homeDepth), speedLimit: built[$0]?.speedLimit ?? .infinity) }
        restingPaddle = g.home(local ?? 0)
        startRally()
    }

    var ballState: CrossBallState { ball.state }
    var ballPosition: MPPoint { ball.position }
    var ballHeight: Double { ball.height }
    /// Drawing position: a network correction is blended away over `blend` seconds.
    var renderBallPosition: MPPoint { ball.position + reconciliation * (reconciliationAge / CrossEngine.blend) }
    /// Seat expected to receive the live ball (owner of its next receiving bounce), for the target indicator.
    var predictedReceiver: Int? {
        switch referee.phase {
        case .receivable: return referee.receiver
        case .serveOwn, .toReceiver: return predicted
        default: return nil
        }
    }
    func kind(_ seat: Int) -> CrossSeatKind { seats[geometry.wrap(seat)].kind }
    func stroke(_ seat: Int) -> MPStroke { strokes[geometry.wrap(seat)] }
    func motion(_ seat: Int) -> CrossMotion { motions[geometry.wrap(seat)] }
    /// World racket point of `seat`; the local seat's follows its paddle.
    func racket(_ seat: Int) -> MPPoint {
        let s = geometry.wrap(seat)
        return geometry.fromLocal(s, motions[s].racket)
    }
    /// A house seat's current intercept plan (authority only).
    func plan(_ seat: Int) -> CrossIntercept? { houses[geometry.wrap(seat)]?.plan }
    /// Where `seat`'s serve is struck: centred, just inside its arm end.
    func serveSpot(_ seat: Int) -> MPPoint { geometry.fromLocal(seat, 0, CrossEngine.serveDepth) }
    /// The local seat's last committed strike, for the link to publish once per (rallyId, hitIndex).
    func localStrike() -> CrossStrike? { ownStrike }
    /// The last committed strike of any seat (the one a checkpoint carries).
    var lastCommittedStrike: CrossStrike? { lastStrike }
    var animating: Bool { strokes.contains { $0.active } || motions.contains { $0.moving } }
    var status: CrossStatus {
        let local = localSeat
        if exercise != nil && trainingResult != nil { return .practiceDone }
        if let winner = referee.winner {
            let together = local.map { teams?.same(winner, $0) == true } ?? false
            return winner == local || together ? .youWon : .matchOver
        }
        switch referee.phase {
        case .resolved: return .point
        case .awaitingServe: return local != nil && referee.server == local ? .yourServe : .otherServe
        case .receivable: return local != nil && referee.receiver == local ? .yourReturn : .inPlay
        case .serveOwn, .toReceiver: return local != nil && predicted == local ? .incoming : .inPlay
        }
    }
    private func emit(_ event: CrossEvent) { events.append(event); onEvent?(event) }
    func drainEvents() -> [CrossEvent] {
        let drained = events
        events.removeAll(keepingCapacity: true)
        return drained
    }
    func discardEvents() { events.removeAll() }
    func restart() {
        referee = CrossReferee(geometry, target: referee.target, firstServer: opening, scoring: scoring, startScores: startScores, teams: teams)
        stopAfterRally = false
        paused = false; teamFlight = teams.map { CrossTeamFlight(members: $0.seats) }; events.removeAll(); release()
        for i in strokes.indices { strokes[i].cancel() }
        motions.forEach { $0.reset() }
        houses.values.forEach { $0.reset() }
        ownStrike = nil; lastStrike = nil; bouncePoint = nil; bounceAge = 1; netAge = 1
        restingPaddle = geometry.home(localSeat ?? 0)
        startRally()
    }
    private func startRally() {
        practicePaddlePlaced = false
        if var flight = teamFlight { flight.setReceiver = nil; flight.friendlyHits = 0; teamFlight = flight }
        teamLift = false; teamPass = false; teamHoldUntil = 0
        pointDelay = nil; grace = nil; serveAt = nil; serveSwing = false; pendingServe = nil; pendingTap = nil
        serveArmed = false; settled = false; predicted = nil; trainingResult = nil; trainingTime = 0; gestureAnchor = nil
        variation.reset()
        houses.values.forEach { $0.newRally() }
        let server = referee.server
        ball.restore(CrossBallState(position: serveSpot(server), height: CrossShots.contactHeight, velocity: .zero, lift: 0, stopped: true))
        if authoritative && referee.winner == nil { scheduleServe(server) }
    }
    /// A house server serves `serveDelayTime` from now and walks to its serve spot meanwhile; returns that substep (nil for a
    /// human server).
    @discardableResult private func scheduleServe(_ server: Int) -> Int64? {
        guard let house = houses[server] else { return nil }
        let spot = geometry.toLocal(server, serveSpot(server))
        let seconds = max(CrossEngine.serveDelayTime - CrossActor.windup, CrossMotion.distance(motions[server].racket, spot) / house.speedLimit)
        motions[server].approach(spot, seconds: seconds, left: house.serveHand())
        let at = ticks + CrossEngine.serveTicks
        serveAt = at
        return at
    }
    /// Clamps dt to 1/30 s and runs fixed 1/120 s substeps (a remainder carries to the next frame). The reception clock may
    /// slow the whole match while a ball approaches a human receiver who asked for it.
    func advance(_ dt: Double) {
        // A NaN frame is dropped: it would stop the clock for good.
        if paused || dt.isNaN { return }
        var receiving: Int?
        if let r = predictedReceiver, kind(r) != .house, !ball.stopped { receiving = r }
        let aimPoint = receiving.map { geometry.fromLocal($0, geometry.toLocal($0, ball.position).u, 0.88) }
        let eta = aimPoint.flatMap { CrossReception.eta(ball.position, ball.velocity, $0) }
        carry += reception.advance(dt, seat: receiving, eta: eta, authority: authoritative)
        while carry >= CrossEngine.step - 1e-9 { carry -= CrossEngine.step; tick() }
    }
    private func tick() {
        let step = CrossEngine.step
        ticks += 1
        reconciliationAge = max(0, reconciliationAge - step)
        paddleTilt *= exp(-step * 10)
        for i in strokes.indices { strokes[i].advance(step) }
        motions.forEach { $0.advance(step) }
        bounceAge += step; netAge += step
        if trainingResult != nil || referee.winner != nil { coast(); idle(); return }
        if exercise != nil { trainingTime += step }
        if let left = pointDelay {
            pointDelay = left - step; coast(); idle()
            if left - step <= 1e-9 && !stopAfterRally && referee.nextRally() { startRally() }
            return
        }
        switch referee.phase {
        case .awaitingServe: serving(); return
        case .resolved: coast(); return
        default: break
        }
        // A remote receiver's grace runs from the substep after its miss was seen, so it lasts the whole grace.
        if let left = grace {
            grace = left - step
            if left - step <= 1e-9 {
                grace = nil
                if let outcome = referee.miss() { resolved(outcome); return }
            }
        }
        stepBall()
        if pointDelay != nil || trainingResult != nil { return }
        localContact()
        houseContacts()
    }
    /// A decided ball finishes its flight silently: no events, it simply falls away.
    private func coast() { if !ball.stopped { ball.step(CrossEngine.step) } }
    /// Rackets with no plan or stroke drift home (between rallies, and while another seat serves).
    private func idle(except: Int? = nil) {
        for i in 0..<players where i != localSeat && i != except && !strokes[i].active && houses[i]?.plan == nil { motions[i].settle() }
    }
    private func serving() {
        idle(except: referee.server)
        if let plan = pendingServe {
            if strokes[plan.server].age >= strokes[plan.server].contactAt { launchServe(plan) }
            return
        }
        let server = referee.server
        if !authoritative || houses[server] == nil { serveAt = nil; return }
        // An authority always has its house server's serve due, also once it stops being a follower or after a checkpoint
        // without that timer; otherwise the match would wait for this serve forever.
        guard let at = serveAt ?? scheduleServe(server) else { return }
        if !serveSwing && ticks >= at - CrossEngine.windupTicks {
            serveSwing = true
            begin(server, serveSpot(server), CrossShots.contactHeight, left: motions[server].left)
        }
        if ticks >= at { serveAt = nil; houseServe(server) }
    }
    private func houseServe(_ server: Int) {
        guard let house = houses[server] else { return }
        let drill = exercise?.drill
        if let feed = exercise, feed.drill == .returning, feed.feedWidth > 0 || feed.feedSide != 0 || feed.paceMultiplier != 1, let local = localSeat {
            let u = (feed.feedSide + house.random.nextDouble(-1, 1) * feed.feedWidth).mpClamp(-0.35, 0.35)
            launchServe(CrossShots.serve(geometry, physics, server: server, start: serveSpot(server), first: geometry.fromLocal(server, 0, 0.78),
                                         second: geometry.fromLocal(local, u, 0.83), pace: CrossShots.basePace(physics) * feed.paceMultiplier))
            return
        }
        if let lesson = teamLesson, let teams, !teams.same(server, lesson), let mate = teammate(lesson) {
            launchServe(CrossShots.serve(geometry, physics, server: server, start: serveSpot(server), first: geometry.fromLocal(server, 0, 0.78),
                                         second: geometry.fromLocal(mate, 0, 0.83), pace: CrossShots.basePace(physics)))
            return
        }
        var target: Int?
        if exercise != nil { target = localSeat }
        else if let others = teams?.opponents(server), !others.isEmpty { target = others[(referee.rallyId + server) % others.count] }
        launchServe(house.serve(serveSpot(server), target: target, allowFault: exercise == nil, middle: drill == .returning))
    }
    private func launchServe(_ plan: CrossServe) {
        pendingServe = nil
        let seat = plan.server
        if !referee.serve(seat, plan.start) { return }
        ball.launch(plan.start, plan.height, plan.launch, rebound: plan.rebound)
        if !strokes[seat].active { begin(seat, plan.start, plan.height, left: false) }
        contact(seat, plan.start, plan.height)
        emit(.served(seat: seat))
        committed(seat, plan.start, plan.height, serve: true)
    }
    private func stepBall() {
        if let event = ball.step(CrossEngine.step) { ballEvent(event) }
        else if referee.phase == .receivable && referee.unreachable(ball.state) { judge(.missed, nil) }
    }
    private func ballEvent(_ e: CrossBallEvent) {
        switch e {
        case let .bounce(point, owner):
            bouncePoint = point; bounceAge = 0
            emit(.bounce(owner: owner, point: point))
        case let .net(point, height):
            netAge = 0
            emit(.net(striker: referee.striker, point: point, height: height))
        case .landed: break
        }
        if settled { return }
        if let kind = referee.verdict(e) { judge(kind, e); return }
        referee.ball(e)
        guard let drill = exercise else { return }
        // A drill ends at the local ball's legal receiving bounce.
        if referee.phase == .receivable, let local = localSeat, referee.striker == local {
            finish(drill.expected == nil || referee.receiver == drill.expected, nil, receiver: referee.receiver)
        }
    }
    /// A resolution the ball calls for. Drills only report it; a peer leaves it to the authority; a networked authority gives a
    /// remote receiver `graceTime` seconds for its strike to arrive before calling missed.
    private func judge(_ kind: CrossRallyKind, _ event: CrossBallEvent?) {
        if settled { return }
        if exercise != nil { finish(false, kind); return }
        if networked && !authoritative { settled = true; pendingTap = nil; return }
        if kind == .missed && networked, let receiver = referee.receiver, seats[receiver].kind == .remote {
            if grace == nil { grace = CrossEngine.graceTime }
            return
        }
        let outcome: CrossRallyOutcome?
        if let event { outcome = referee.ball(event) } else { outcome = referee.miss() }
        if let outcome { resolved(outcome) }
    }
    private func resolved(_ outcome: CrossRallyOutcome) {
        emit(.rally(outcome))
        if let winner = outcome.winner { emit(.victory(seat: winner)) }
        pointDelay = CrossEngine.pointDelayTime; grace = nil; serveAt = nil; pendingServe = nil; pendingTap = nil
        houses.values.forEach { $0.plan = nil }
    }
    private func finish(_ success: Bool, _ kind: CrossRallyKind?, receiver: Int? = nil) {
        trainingResult = CrossTrainingResult(success: success, kind: kind, receiver: receiver)
        pendingTap = nil; pendingServe = nil; serveAt = nil; grace = nil
        houses.values.forEach { $0.plan = nil }
    }
    private func houseContacts() {
        if !authoritative { return }
        // Seat order, as Android's insertion-ordered map.
        for seat in houses.keys.sorted() {
            guard let house = houses[seat], let plan = house.plan else { continue }
            if !house.swung && ticks >= plan.tick - CrossEngine.windupTicks {
                house.swung = true
                begin(seat, plan.point, plan.height, left: plan.left)
            }
            if ticks < plan.tick { continue }
            house.plan = nil
            houseStrike(seat, house, plan)
            if pointDelay != nil || trainingResult != nil { return }
        }
    }
    private func houseStrike(_ seat: Int, _ house: CrossHouse, _ plan: CrossIntercept) {
        let s = ball.state
        if !referee.mayStrike(seat) || s.stopped || !geometry.inStrikeZone(seat, s.position) { return }
        guard let c = house.roll(s, racket: racket(seat), reachable: plan.reachable, ready: strokes[seat].active,
                                 served: referee.server == seat, serveBall: referee.hits == 0) else { return }
        let h = max(s.height, CrossShots.contactHeight)
        let lateral = geometry.toLocal(seat, s.position).u
        let lanes = variation
        let normal = house.shot(c, from: s.position, height: h, sender: referee.striker) { lanes.due(seat, $0, lateral) }
        // Team play: a good contact goes to the chosen opponent; every third rally hit (or a lesson's teammate) is raised to the
        // partner, who smashes it.
        let mate = teammate(seat)
        let isSet = teamFlight?.setReceiver == seat
        let rhythm = (referee.rallyId + referee.hits) % 3 == 0 || (mate != nil && mate == teamLesson)
        let shouldSet = c.quality >= CrossHouse.good && teams != nil && !isSet && mate != nil && teamFlight?.friendlyHits == 0 && rhythm
        var receiver: Int?
        if shouldSet { receiver = mate }
        else if let others = teams?.opponents(seat), !others.isEmpty { receiver = others[(referee.rallyId + referee.hits) % others.count] }
        let point = receiver.map { geometry.fromLocal($0, (house.random.nextDouble() - 0.5) * (shouldSet ? 0.16 : 0.45), 0.88) }
        var shot = normal
        if let point, c.quality >= CrossHouse.good {
            shot.launch = teamShot(s.position, h, point, lob: shouldSet, power: isSet ? 1.65 : 1,
                                   contactPace: max(normal.launch.velocity.length, CrossShots.basePace(physics)))
        }
        if shouldSet { teamLift = true }
        if !referee.strike(seat, s.position) { return }
        ball.launch(s.position, h, shot.launch)
        contact(seat, s.position, h)
        committed(seat, s.position, h, serve: false)
    }
    /// Records a committed contact (exactly once per contact), forecasts its receiver and, on the authority, lets the receiving
    /// house player plan its intercept.
    private func committed(_ seat: Int, _ point: MPPoint, _ height: Double, serve: Bool) {
        let strike = CrossStrike(seat: seat, point: point, height: height, ball: ball.state, serve: serve, rallyId: referee.rallyId, hitIndex: serve ? 0 : referee.hits,
                                 raised: teams != nil && !serve && teamLift)
        lastStrike = strike
        if seat == localSeat {
            ownStrike = strike
            CrossEngine.strikeCounter += 1
            localStrikeID = CrossEngine.strikeCounter
        }
        settled = false
        forecast(seat)
        updateTeamFlight(strike)
        if !serve { variation.hit(seat, predicted ?? -1, geometry.toLocal(seat, point).u) }
    }
    /// The same team transition runs for an accepted remote contact and a local contact. A raise counts only when the physical
    /// flight reaches this striker's teammate.
    private func updateTeamFlight(_ strike: CrossStrike) {
        guard let membership = teams else { return }
        if strike.serve { return }
        guard let old = teamFlight else { return }
        let friend = predicted.map { membership.same(strike.seat, $0) } ?? false
        let raised = friend && strike.raised
        var next = old
        next.setReceiver = raised ? predicted : nil
        next.passes = old.passes + (friend ? 1 : 0)
        next.sets = old.sets + (raised ? 1 : 0)
        next.smashes = old.smashes + (old.setReceiver == strike.seat && !friend ? 1 : 0)
        next.friendlyHits = friend ? 1 : 0
        teamFlight = next
        teamLift = false; teamPass = false
    }
    private func forecast(_ striker: Int) {
        let found = CrossForecast.receiving(geometry, ball, striker: striker)
        predicted = found?.owner
        guard let r = found, authoritative, exercise == nil, let house = houses[r.owner] else { return }
        house.makePlan(CrossForecast.intercept(geometry, seat: r.owner, r, earliest: house.reactionTicks), now: ticks, motion: motions[r.owner])
    }
    /// After a restore: the forecast again and, on the authority, a house receiver's plan from the current ball.
    private func replan() {
        switch referee.phase {
        case .serveOwn, .toReceiver: forecast(referee.striker)
        case .receivable:
            predicted = nil
            guard let r = referee.receiver, let house = houses[r] else { return }
            if !authoritative || exercise != nil { return }
            // The live ball's next substep is the earliest one a plan can meet.
            let receiving = CrossReceiving(owner: r, point: ball.position, ticks: 0, probe: ball.copy())
            house.makePlan(CrossForecast.intercept(geometry, seat: r, receiving, earliest: 1), now: ticks, motion: motions[r])
        default: predicted = nil
        }
    }
    private func begin(_ seat: Int, _ point: MPPoint, _ height: Double, left: Bool) {
        if seat == localSeat { rest(seat, point) }
        serial += 1
        strokes[seat].start(serial, point, height, left)
        emit(.swing(seat: seat, id: strokes[seat].id))
    }
    /// One contact event per stroke: the stroke's `contacted` guards a second one.
    private func contact(_ seat: Int, _ point: MPPoint, _ height: Double) {
        if seat == localSeat { rest(seat, point) }
        if strokes[seat].contacted { return }
        strokes[seat].contact(point, height)
        emit(.contact(seat: seat, id: strokes[seat].id, point: point, height: height))
    }
    private func rest(_ local: Int, _ point: MPPoint) {
        if !geometry.inStrikeZone(local, point) { return }
        restingPaddle = point
        motions[local].place(geometry.toLocal(local, point))
    }
    private func playable() -> Bool { !paused && referee.winner == nil && pointDelay == nil && trainingResult == nil && referee.phase != .resolved }
    /// Local input in the viewer (local seat) frame. `point` is WORLD (nil off the court); `drag` the finger offset from
    /// touch-down in points (Android dp; +x right, +y down); `velocity` world units/s in the viewer frame (+y toward the viewer).
    func touch(_ point: MPPoint?, drag: MPPoint = .zero, velocity: MPPoint = .zero, down: Bool = true) {
        guard let local = localSeat else { return }
        if !playable() { return }
        // Junk input (NaN/infinite values from a zero-size view or a zero frame interval upstream) never reaches the physics:
        // such a point is off the court, such a speed is none and such a drag keeps the current aim.
        let sane: MPPoint? = point.flatMap { $0.length < CrossEngine.touchLimit ? $0 : nil }
        let usable = velocity.length.isFinite
        if sane != point || !usable { touch(sane, drag: drag, velocity: usable ? velocity : .zero, down: down); return }
        // A tap on another player's court picks where the next return goes (journeys and team tables).
        if down, tapTargets, let point, let owner = geometry.owner(point), owner != local { selectedAim = point }
        if down {
            // A team touch holds the automatic return briefly, so a second tap can still arm a raised pass.
            if teams != nil && !receivingSet && !referee.mayServe(local) { teamHoldUntil = ticks + 34 }
            aimDp = 0; gestureSpeed = 0; gestureLast = point; gestureTravel = 0; gestureCommitted = false
            gestureAnchor = point.flatMap { geometry.inStrikeZone(local, $0) ? $0 : nil }
        } else if drag.x.isFinite { aimDp = drag.x }
        gestureSpeed = max(gestureSpeed, velocity.length)
        lastVelocity = velocity
        if referee.mayServe(local) && pendingServe == nil { serveInput(local, point, velocity, down: down); return }
        if pendingServe != nil { return }
        if let point, geometry.inStrikeZone(local, point) { practicePaddlePlaced = true; movePaddle(local, point) }
        if receivingSet {
            if !down, let point { swipe(local, point, velocity) }
            return
        }
        if teams != nil, let point, let owner = geometry.owner(point), owner == teammate(local), teamFlight?.friendlyHits == 0 { teamPass = true }
        switch control {
        case .beginner: break // position alone arms the automatic contact
        case .standard:
            if down {
                if let point, geometry.inStrikeZone(local, point) { tap(local, point) }
            } else if let point, pendingTap != nil, !strokes[local].contacted, geometry.inStrikeZone(local, point) { pendingTap = point }
        case .pro:
            if !teamLift && !down, let point { swipe(local, point, velocity) }
        }
    }
    func endTouch(cancelled: Bool = false) {
        if let local = localSeat, !cancelled, playable(), referee.mayServe(local), pendingServe == nil {
            if control != .pro {
                if serveArmed { tapServe(local) }
            } else if !gestureCommitted && gestureTravel >= CrossEngine.serveTravel, let last = gestureLast {
                // A stationary DOWN/UP is not a swing; a release next to the ball completes one.
                if last.distance(serveSpot(local)) <= physics.swipeCollisionForgiveness { commitSwipe(local, last, lastVelocity) }
            }
        }
        // CANCEL drops a pending timed contact; a released tap keeps its stroke window.
        if cancelled { pendingTap = nil }
        serveArmed = false; serveTap = nil
        gestureLast = nil; gestureTravel = 0; lastVelocity = .zero
        paddle = nil
    }
    func release() { endTouch(cancelled: true) }
    private func movePaddle(_ local: Int, _ point: MPPoint) {
        let before = geometry.toView(local, restingPaddle).x
        paddle = point; rest(local, point)
        paddleTilt = ((geometry.toView(local, point).x - before) * 160).mpClamp(-14, 14)
    }
    private func serveInput(_ local: Int, _ point: MPPoint?, _ velocity: MPPoint, down: Bool) {
        if control != .pro {
            if down { serveArmed = true; serveTap = point }
            return
        }
        guard !down, let point else { return }
        let previous = gestureLast ?? point
        gestureTravel += previous.distance(point); gestureLast = point
        if !gestureCommitted && gestureTravel >= CrossEngine.serveTravel &&
            CrossEngine.segmentDistance(previous, point, serveSpot(local)) <= physics.swipeCollisionForgiveness {
            commitSwipe(local, point, velocity)
        }
    }
    /// Beginner/Standard serve on release: the tap picks the first bounce on the own arm; its side and the drag pick the target
    /// through the aim map; Standard adds pace from the gesture speed.
    private func tapServe(_ local: Int) {
        serveArmed = false
        let tap = serveTap
        var lateral: Double?
        if let tap, geometry.inArm(local, tap) { lateral = geometry.toLocal(local, tap).u }
        let power = automaticContact ? 0 : gesturePower()
        let aim = aims.aim(local, dragDp: aimDp, power: power, serveLateral: lateral, variation: sway())
        let pace = automaticContact ? CrossShots.basePace(physics) : CrossShots.pace(physics, power: power)
        queueServe(CrossShots.tapServe(geometry, physics, server: local, start: serveSpot(local), tap: tap, second: selectedAim ?? aim.point, pace: pace))
    }
    /// Pro serve: a swipe through the ball (the classic swipe serve); a weak or backward swipe is a bad serve.
    private func commitSwipe(_ local: Int, _ point: MPPoint, _ swipe: MPPoint) {
        gestureCommitted = true
        if let plan = CrossShots.swipeServe(geometry, physics, server: local, start: serveSpot(local), swipe: swipe) { queueServe(plan); return }
        begin(local, point, CrossShots.contactHeight, left: swipe.x < 0)
        if exercise != nil { finish(false, .badServe); return }
        if networked && !authoritative {
            // The authority judges it: the failed serve is published as a ball dropped from the hand.
            let start = serveSpot(local)
            if !referee.serve(local, start) { return }
            ball.launch(start, CrossShots.contactHeight, CrossLaunch(velocity: .zero, lift: 0))
            contact(local, start, CrossShots.contactHeight)
            emit(.served(seat: local))
            committed(local, start, CrossShots.contactHeight, serve: true)
            return
        }
        if let outcome = referee.serveFault(local) { resolved(outcome) }
    }
    private func queueServe(_ plan: CrossServe) {
        pendingServe = plan
        let toward = geometry.toView(plan.server, plan.second ?? plan.first).x
        begin(plan.server, plan.start, plan.height, left: toward < geometry.toView(plan.server, plan.start).x)
    }
    /// Standard: a tap in the strike zone starts a stroke; it can make contact only when this seat is (or is about to be) the
    /// receiver. An early or empty swing is audible, never contact.
    private func tap(_ local: Int, _ point: MPPoint) {
        let s = strokes[local]
        if s.active && !s.contacted && s.age < CrossEngine.retap { return }
        let travelling = referee.phase == .serveOwn || referee.phase == .toReceiver
        pendingTap = !settled && (referee.mayStrike(local) || (travelling && predicted == local)) ? point : nil
        begin(local, point, ball.height, left: geometry.toLocal(local, point).u < 0)
    }
    /// Pro: the gesture IS the swing. Segments are swept so a fast stroke cannot tunnel through the ball; the motion must run
    /// from outward to inward (toward the centre) and pass within swipeCollisionForgiveness of the ball.
    private func swipe(_ local: Int, _ point: MPPoint, _ velocity: MPPoint) {
        let previous = gestureLast ?? point
        gestureTravel += previous.distance(point); gestureLast = point
        if settled || !referee.mayStrike(local) || gestureTravel < CrossEngine.swingTravel { return }
        if !strokes[local].active { begin(local, point, ball.height, left: velocity.x < 0) }
        let at = ball.position
        let miss = CrossEngine.segmentDistance(previous, point, at)
        if strokes[local].contacted || ball.stopped || !geometry.inStrikeZone(local, at) || velocity.y >= -CrossEngine.forward ||
            miss > physics.swipeCollisionForgiveness { return }
        // Only implausible sensor spikes are capped; weak strokes stay weak.
        let speed = velocity.length
        let cap = physics.maximumSwipeSpeed * 3
        let swing = speed > cap ? velocity * (cap / speed) : velocity
        let quality = (2 - miss / physics.swipeCollisionForgiveness) / 2
        let shot: CrossLaunch
        if receivingSet && control != .pro, let teams {
            // Learning controls keep the swipe's chosen opponent, with a safely cleared faster trajectory. The gesture still has
            // to cross the real bounced ball; it never acts as an automatic hit.
            let direction = geometry.fromView(local, swing)
            let others = teams.opponents(local)
            var receiver = others[0]
            var best = -Double.greatestFiniteMagnitude
            for candidate in others {
                let d = geometry.fromLocal(candidate, 0, 0.87) - at
                let value = d.dot(direction) / d.length
                if value > best { best = value; receiver = candidate }
            }
            let spot = geometry.fromLocal(receiver, (swing.x * 0.08).mpClamp(-0.18, 0.18), 0.86)
            shot = teamShot(at, max(ball.height, CrossShots.contactHeight), spot, lob: false, power: 1.45 + 0.35 * gesturePower())
        } else {
            shot = CrossShots.driven(geometry, physics, striker: local, swipe: receivingSet ? swing * 1.35 : swing,
                                     height: max(ball.height, CrossShots.contactHeight), incoming: ball.velocity, quality: quality)
        }
        strike(local, shot)
    }
    private func localContact() {
        guard let local = localSeat else { return }
        let s = strokes[local]
        // A journey waits until the player has placed the paddle; a raised pass needs a swipe; a team touch may still become a
        // double tap.
        if tapTargets && !practicePaddlePlaced { return }
        if receivingSet || (teams != nil && ticks < teamHoldUntil && !teamLift) { return }
        if teams != nil, let tap = pendingTap, s.age > s.windowEnd, !s.contacted, s.age < 0.65 {
            begin(local, tap, ball.height, left: geometry.toLocal(local, tap).u < 0)
        } else if pendingTap != nil && s.age > s.windowEnd && !s.contacted { pendingTap = nil }
        if settled || !referee.mayStrike(local) || ball.stopped || !geometry.inStrikeZone(local, ball.position) { return }
        let at = ball.position
        if teamLift && (paddle ?? restingPaddle).distance(at) <= CrossEngine.autoReach {
            begin(local, at, ball.height, left: geometry.toLocal(local, at).u < 0)
            strike(local, assisted(local, power: 0))
            return
        }
        switch control {
        case .beginner:
            // Position alone arms Beginner: a held or released paddle meets the legal ball exactly once.
            let anchor = gestureAnchor.map { $0.distance(at) } ?? Double.greatestFiniteMagnitude
            if min((paddle ?? restingPaddle).distance(at), anchor) <= CrossEngine.autoReach {
                begin(local, at, ball.height, left: geometry.toLocal(local, at).u < 0)
                strike(local, assisted(local, power: 0))
            }
        case .standard:
            guard let tap = pendingTap, strokes[local].contactWindow else { return }
            let depth = geometry.toLocal(local, at).v
            let timing = (depth - CrossEngine.idealDepth) / max(abs(geometry.toLocal(local, ball.velocity).v), CrossEngine.minTimingSpeed)
            if tap.distance(at) <= physics.tapSpatialTolerance && abs(timing) <= physics.tapTimingWindow { strike(local, assisted(local, power: gesturePower())) }
        case .pro: break // the swipe itself makes contact
        }
    }
    /// The local return: exactly one contact event and one committed strike per contact.
    private func strike(_ local: Int, _ shot: CrossLaunch) {
        let s = ball.state
        if strokes[local].contacted || !referee.strike(local, s.position) { return }
        let h = max(s.height, CrossShots.contactHeight)
        ball.launch(s.position, h, shot)
        contact(local, s.position, h)
        pendingTap = nil; aimDp = 0; gestureSpeed = 0; gestureAnchor = nil; practicePaddlePlaced = false
        committed(local, s.position, h, serve: false)
    }
    /// Beginner/Standard: the aim map picks the opponent and spot from the drag; pace is base (+35 % x power for Standard).
    private func assisted(_ local: Int, power: Double) -> CrossLaunch {
        let s = ball.state
        // Team play: one friendly pass (raised after a double tap) goes to the partner.
        if let mate = teammate(local), teamLift || teamPass, teamFlight?.friendlyHits == 0 {
            return teamShot(s.position, max(s.height, CrossShots.contactHeight), geometry.fromLocal(mate, 0, 0.88), lob: teamLift)
        }
        let aim = aims.aim(local, dragDp: aimDrag(), power: power, sender: referee.striker, variation: sway())
        let pace = automaticContact ? CrossShots.basePace(physics) : CrossShots.pace(physics, power: power)
        // A tapped court is the target, except the own team's court once the friendly pass is used; a team return never goes
        // to the partner by the drag alone.
        var selected = selectedAim
        if let point = selected, let teams, teamFlight?.friendlyHits == 1, let owner = geometry.owner(point), teams.same(owner, local) { selected = nil }
        var safe = aim.point
        if let selected { safe = selected }
        else if let teams, teams.same(local, aim.opponent), let first = teams.opponents(local).first { safe = geometry.fromLocal(first, 0, 0.88) }
        return CrossShots.targeted(geometry, physics, from: s.position, height: max(s.height, CrossShots.contactHeight), target: safe, pace: pace)
    }
    /// Beginner aims with the latest sideways swipe (made any time before the hit, kept after the finger lifts), limited so an
    /// automatic return always stays on the table; Standard keeps the full drag (a wide drag may go out).
    private func aimDrag() -> Double { automaticContact ? aimDp.mpClamp(-CrossEngine.safeDrag, CrossEngine.safeDrag) : aimDp }
    /// Who the local return would go to right now (Beginner/Standard, ball on its way to the local seat): shown on court.
    var aimTarget: Int? {
        guard let local = localSeat else { return nil }
        if control == .pro || paused || predictedReceiver != local { return nil }
        return aims.aim(local, dragDp: aimDrag(), power: 0, sender: referee.striker).opponent
    }
    /// A deliberate double tap arms one raised pass; the paddle must still meet the live receiving ball.
    @discardableResult func liftToTeammate() -> Bool {
        guard let local = localSeat else { return false }
        if !playable() || teammate(local) == nil || teamFlight?.friendlyHits != 0 || receivingSet || referee.mayServe(local) { return false }
        if predictedReceiver != local { return false }
        teamLift = true; teamPass = true; teamHoldUntil = 0; pendingTap = nil
        return true
    }
    /// A team shot to `to`: a normal targeted shot, or (`lob`) a high pass that takes 0.16 s longer than the pace (at most 2.55 s).
    private func teamShot(_ from: MPPoint, _ height: Double, _ to: MPPoint, lob: Bool, power: Double = 1, contactPace: Double? = nil) -> CrossLaunch {
        let pace = (contactPace ?? CrossShots.basePace(physics)) * power
        if !lob { return CrossShots.targeted(geometry, physics, from: from, height: height, target: to, pace: pace) }
        let time = min(2.55, CrossShots.flightTime(geometry, physics, from: from, height: height, target: to, pace: pace) + 0.16)
        return CrossLaunch(velocity: (to - from) * (1 / time), lift: (0.5 * physics.gravity * time * time - height) / time)
    }
    /// Alternating side for assisted placements: consecutive human returns never repeat one spot.
    private func sway() -> Double { (referee.rallyId + referee.hits) % 2 == 0 ? 1 : -1 }
    private func gesturePower() -> Double { (gestureSpeed / physics.maximumSwipeSpeed).mpClamp(0, 1) }
    func exportState() -> CrossState {
        let delay: Double? = serveAt.map { max(0, Double($0 - ticks) * CrossEngine.step) }
        return CrossState(referee: referee.exportState(), ball: ball.state, pointDelay: pointDelay, serveDelay: delay, grace: grace, strike: lastStrike,
                          motions: motions.map { CrossMotionState(u: $0.racket.u, v: $0.racket.v, toU: $0.destination.u, toV: $0.destination.v, remaining: $0.remaining, left: $0.left) },
                          team: teamFlight, practiceAim: selectedAim, paddlePlaced: practicePaddlePlaced, reception: CrossWireBox(reception.wire()))
    }
    /// Adopts a checkpoint. With `preserveInput` (live following) a checkpoint that only acknowledges this seat's own predicted
    /// strike never rewinds the ball, a new strike by another seat is animated once, a new outcome is announced and the held
    /// finger survives within the same rally. Throws (changing nothing) for an invalid state.
    func restoreState(_ state: CrossState, preserveInput: Bool = false) throws {
        guard state.team?.members == teams?.seats else { throw CrossStateError.invalid("Team membership mismatch") }
        if let aim = state.practiceAim, !(aim.length.isFinite && geometry.onTable(aim)) { throw CrossStateError.invalid("Invalid practice aim") }
        guard state.ball.valid() else { throw CrossStateError.invalid("Invalid ball state") }
        // Checked before anything changes: a NaN timer would freeze the match, an unknown striker would fail halfway through.
        let timers = [state.pointDelay, state.serveDelay, state.grace].compactMap { $0 }
        let motionsFinite = state.motions.allSatisfy { m in [m.u, m.v, m.toU, m.toV, m.remaining].allSatisfy { $0.isFinite } }
        let strikeSeat = state.strike.map { $0.seat >= 0 && $0.seat < players } ?? true
        guard timers.allSatisfy({ $0.isFinite }), motionsFinite, strikeSeat else { throw CrossStateError.invalid("Invalid timers, motions or strike") }
        guard state.motions.isEmpty || state.motions.count == players else { throw CrossStateError.invalid("Seat count mismatch") }
        try reception.restore(state.reception.value)
        let before = renderBallPosition
        let old = referee.exportState()
        let next = state.referee
        let local = localSeat
        let same = preserveInput && next.rallyId == old.rallyId && next.winner == nil
        if same, let local, next.striker == local, old.striker == local, next.hits == old.hits, next.phase.live, old.phase.live {
            teamFlight = state.team
            adopt(state, snap: false)
            return
        }
        try referee.restore(next)
        teamFlight = state.team
        if !same || next.hits != old.hits || !next.phase.live || state.team?.friendlyHits != 0 { teamLift = false; teamPass = false; teamHoldUntil = 0 }
        if !same { selectedAim = state.practiceAim; practicePaddlePlaced = state.paddlePlaced }
        if !preserveInput, let local, state.motions.count == players {
            let m = state.motions[local]
            rest(local, geometry.fromLocal(local, m.u, m.v))
        }
        if !same {
            release()
            if let local { strokes[local].cancel() }
            pendingServe = nil; pendingTap = nil; variation.reset()
        }
        let known = lastStrike
        ball.restore(state.ball)
        pointDelay = state.pointDelay
        grace = authoritative ? state.grace : nil
        if authoritative && next.phase == .awaitingServe && houses[next.server] != nil, let delay = state.serveDelay {
            serveAt = ticks + max(0, Int64((delay / CrossEngine.step).rounded()))
        } else { serveAt = nil }
        serveSwing = false; settled = false
        houses.values.forEach { $0.plan = nil }
        lastStrike = state.strike
        if preserveInput, let strike = state.strike, strike.seat != local, strike.rallyId == next.rallyId, next.phase.live {
            let fresh = known.map { $0.rallyId != strike.rallyId || $0.hitIndex != strike.hitIndex || $0.seat != strike.seat } ?? true
            if fresh {
                let left = geometry.toLocal(strike.seat, strike.point).u < 0
                begin(strike.seat, strike.point, strike.height, left: left)
                contact(strike.seat, strike.point, strike.height)
                if strike.serve { emit(.served(seat: strike.seat)) }
            }
        }
        // Rackets first, so a reopened authority plans its house receiver from where that player really is.
        adopt(state, snap: !preserveInput)
        replan()
        if preserveInput, let outcome = next.lastOutcome, outcome.rallyId != old.lastOutcome?.rallyId {
            emit(.rally(outcome))
            if let winner = outcome.winner { emit(.victory(seat: winner)) }
        }
        reconciliation = before - ball.position
        reconciliationAge = reconciliation.length < 0.4 ? CrossEngine.blend : 0
    }
    /// Peers ease other seats' rackets along the authority's motion plans; a fresh restore (`snap`) places them exactly.
    private func adopt(_ state: CrossState, snap: Bool) {
        guard state.motions.count == players else { return }
        for i in 0..<players {
            if i == localSeat || houses[i]?.plan != nil { continue }
            let m = state.motions[i]
            let at = CrossLocal(m.u, m.v)
            if snap || CrossMotion.distance(motions[i].racket, at) > CrossEngine.snap { motions[i].place(at, left: m.left) }
            motions[i].approach(CrossLocal(m.toU, m.toV), seconds: max(m.remaining, CrossMotion.minTime), left: m.left)
        }
    }
    /// Authority side of a remote seat's published strike: the rally id, the hit index (serve 0, else hits + 1), the seat (the
    /// server awaiting the serve, or the current receiver) and a contact inside that seat's strike zone. Applied once;
    /// duplicates and stale strikes are refused. A strike that arrives before this engine's ball made the legal receiving
    /// bounce first plays the flight forward to that bounce (the strike proves it).
    @discardableResult func applyRemoteStrike(_ seat: Int, _ strike: CrossStrike, rallyId: Int, hitIndex: Int) -> Bool {
        if !networked || seat < 0 || seat >= players || seats[seat].kind != .remote || strike.seat != seat { return false }
        if rallyId != referee.rallyId || strike.rallyId != rallyId || strike.hitIndex != hitIndex || referee.winner != nil { return false }
        if !strike.ball.valid() || strike.ball.stopped || !strike.height.isFinite || !geometry.inStrikeZone(seat, strike.point) ||
            strike.ball.position.distance(strike.point) > CrossEngine.strikeTolerance { return false }
        if strike.serve {
            if hitIndex != 0 || pendingServe != nil || !referee.serve(seat, strike.point) { return false }
        } else if hitIndex != referee.hits + 1 || (!referee.mayStrike(seat) && !catchUp(seat)) || !referee.strike(seat, strike.point) { return false }
        let before = renderBallPosition
        grace = nil; serveAt = nil; settled = false
        ball.restore(strike.ball)
        let left = geometry.toLocal(seat, strike.point).u < 0
        begin(seat, strike.point, strike.height, left: left)
        contact(seat, strike.point, strike.height)
        motions[seat].approach(geometry.toLocal(seat, strike.point), seconds: CrossEngine.remoteApproach, left: left)
        if strike.serve { emit(.served(seat: seat)) }
        lastStrike = strike
        forecast(seat)
        updateTeamFlight(strike)
        if !strike.serve { variation.hit(seat, predicted ?? -1, geometry.toLocal(seat, strike.point).u) }
        reconciliation = before - ball.position
        reconciliationAge = reconciliation.length < 0.4 ? CrossEngine.blend : 0
        return true
    }
    private func catchUp(_ seat: Int) -> Bool {
        if (referee.phase != .serveOwn && referee.phase != .toReceiver) || predicted != seat { return false }
        let probe = ball.copy()
        for _ in 0..<CrossForecast.ticks {
            guard let e = probe.step(CrossEngine.step) else { continue }
            if referee.verdict(e) != nil { return false }
            referee.ball(e)
            if referee.phase == .receivable { return referee.receiver == seat }
        }
        return false
    }
    static func segmentDistance(_ a: MPPoint, _ b: MPPoint, _ p: MPPoint) -> Double {
        let d = b - a
        let square = d.dot(d)
        let t = square == 0 ? 0 : ((p - a).dot(d) / square).mpClamp(0, 1)
        return (a + d * t).distance(p)
    }
}
