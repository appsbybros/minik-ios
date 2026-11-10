import Foundation

// Android cross/CrossMatch.kt (MinikCrossPong 828c6fc; 1fc4bc2: the classic final's two-point lead and resumable eliminations).

/// winnerTakesAll: the first to the target wins (losses at 0 forgiven). elimination: players drop out (below zero, or the fewest
/// points whenever someone reaches the target) and the table shrinks until two remain.
enum CrossMode { case winnerTakesAll, elimination }
/// win: one winner. topTwo: an elimination tournament table that ends when two remain (both qualify). tiebreak: the caller
/// passes target 1; the first player to gain a point takes the place.
enum CrossGoal { case win, topTwo, tiebreak }

/// The next table: who still plays (fixture seats in table order), their start scores and the serving stage seat.
struct CrossStageStart: Equatable {
    var active: [Int]
    var scores: [Int]
    var server: Int
}

/// Checkpoint of a whole fixture: elimination progress plus the current stage engine.
struct CrossMatchState {
    var stage: Int
    var active: [Int]
    var eliminated: [Int]
    var finals: [Int]
    var pending: Bool
    var finished: Bool
    var placement: [Int]
    var transition: Double?
    var next: CrossStageStart?
    var engine: CrossState
    /// The engine's own protocol-2 fields stay at the top level (the live rules check them); progress is under "match".
    func wire() -> MPWire {
        var match: MPWire = ["stage": stage, "active": active, "eliminated": eliminated, "finals": finals, "pending": pending,
                             "finished": finished, "placement": placement]
        if let transition { match["transition"] = transition }
        if let next { match["next"] = ["active": next.active, "scores": next.scores, "server": next.server] as MPWire }
        var w = engine.wire()
        w["match"] = match
        return w
    }
    static func read(_ w: MPWire) throws -> CrossMatchState {
        let engine = try CrossState.read(w)
        let m = MPCodec.map(w["match"])
        let players = engine.referee.scores.count
        if m.isEmpty {
            return CrossMatchState(stage: 0, active: Array(0..<players), eliminated: [], finals: Array(repeating: 0, count: players), pending: false,
                                   finished: engine.referee.winner != nil, placement: [], transition: nil, next: nil, engine: engine)
        }
        let n = MPCodec.map(m["next"])
        return CrossMatchState(stage: CrossWire.int(m, "stage"), active: CrossWire.ints(m["active"]), eliminated: CrossWire.ints(m["eliminated"]),
                               finals: CrossWire.ints(m["finals"]), pending: CrossWire.flag(m, "pending"), finished: CrossWire.flag(m, "finished"),
                               placement: CrossWire.ints(m["placement"]), transition: CrossWire.optional(m, "transition"),
                               next: n.isEmpty ? nil : CrossStageStart(active: CrossWire.ints(n["active"]), scores: CrossWire.ints(n["scores"]), server: CrossWire.int(n, "server")),
                               engine: engine)
    }
}

/// One fixture on the cross table, possibly over several table stages. Seats here are FIXTURE seats (roster indices); the
/// current `engine` numbers its seats 0 until its own player count (`stageSeat`/`fixtureSeat` translate). Only the authority
/// decides eliminations; a peer mirrors them from checkpoints.
final class CrossMatch {
    /// The elimination announcement stays on screen this long before the smaller table starts.
    static let transitionTime = 3.2
    let roster: [CrossSeat]
    let control: CrossControl
    let target: Int
    let seed: Int64
    let networked: Bool
    let firstServer: Int
    let mode: CrossMode
    let goal: CrossGoal
    let players: Int
    /// This phone's player (fixture seat), nil when spectating.
    let localSeat: Int?
    private var auth = true
    private var hold = false
    private(set) var stage = 0
    private(set) var active: [Int]
    private var out: [Int] = []
    /// Fixture seats in the order they dropped out.
    var eliminated: [Int] { out }
    private var finals: [Int]
    /// Someone reached the target while the fewest points were tied: the next rally that breaks the tie decides.
    private(set) var pending = false
    private(set) var finished = false
    /// Final order of fixture seats: the winner (or the two survivors of a topTwo table), then the rest.
    private(set) var placement: [Int] = []
    /// Seconds left before the next (smaller) table starts; the finished stage stays on screen meanwhile.
    private(set) var transition: Double?
    private(set) var next: CrossStageStart?
    private(set) var engine: CrossEngine
    private var events: [CrossEvent] = []
    var authoritative: Bool {
        get { auth }
        set { auth = newValue; engine.authoritative = newValue }
    }
    var paused: Bool {
        get { hold }
        set { hold = newValue; engine.paused = newValue }
    }

    /// Android requires 2...4 players in roster order and topTwo only for elimination tables of 3 or 4; the app always builds
    /// them so, and stray values are corrected here instead of crashing.
    init(roster input: [CrossSeat], control: CrossControl, target: Int, seed: Int64, networked: Bool = false, firstServer: Int = 0,
         mode: CrossMode = .winnerTakesAll, goal: CrossGoal = .win) {
        let numbered = input.enumerated().map { item -> CrossSeat in
            var seat = item.element
            seat.index = item.offset
            return seat
        }
        roster = numbered
        self.control = control; self.target = target; self.seed = seed; self.networked = networked; self.firstServer = firstServer
        self.mode = mode
        let decided: CrossGoal = goal == .topTwo && !(mode == .elimination && numbered.count >= 3) ? .win : goal
        self.goal = decided
        let n = numbered.count
        players = n
        localSeat = numbered.firstIndex { $0.kind == .local }
        let everyone = Array(0..<n)
        active = everyone
        finals = Array(repeating: 0, count: n)
        engine = CrossMatch.makeEngine(roster: numbered, seats: everyone, control: control, target: target, seed: seed, stage: 0, networked: networked,
                                       server: crossMod(firstServer, max(1, n)), scoring: CrossMatch.scoring(n, mode: mode, goal: decided), scores: nil,
                                       goal: decided, authoritative: true, paused: false)
    }
    var winner: Int? { finished && goal != .topTwo ? placement.first : nil }
    var localOut: Bool { localSeat.map { out.contains($0) } ?? false }
    /// The stage that the final duel of an elimination match is.
    var duel: Bool { mode == .elimination && active.count == 2 && players > 2 }
    func fixtureSeat(_ stageSeat: Int) -> Int { active[stageSeat] }
    func stageSeat(_ fixtureSeat: Int) -> Int? { active.firstIndex(of: fixtureSeat) }
    /// Current score of every fixture seat: the live stage for active players, the score at elimination for the rest.
    func scores() -> [Int] {
        (0..<players).map { f -> Int in
            if !finished, let s = stageSeat(f) { return engine.referee.score(s) }
            return finals[f]
        }
    }
    private static func scoring(_ n: Int, mode: CrossMode, goal: CrossGoal) -> CrossScoring {
        if n == 2 { return .classic }
        if mode == .elimination && goal != .tiebreak { return .elimination }
        return .multi
    }
    private static func makeEngine(roster: [CrossSeat], seats: [Int], control: CrossControl, target: Int, seed: Int64, stage: Int, networked: Bool,
                                   server: Int, scoring: CrossScoring, scores: [Int]?, goal: CrossGoal, authoritative: Bool, paused: Bool) -> CrossEngine {
        let table = seats.enumerated().map { item -> CrossSeat in
            var seat = roster[item.element]
            seat.index = item.offset
            return seat
        }
        // Android 1fc4bc2: a two-player stage (the elimination final on the cross table) keeps the two-point lead of its control
        // level, except in a tie-break.
        let engine = CrossEngine(seats: table, control: control, target: target, seed: seed &+ 7919 &* Int64(stage), networked: networked,
                                 firstServer: server, scoring: scoring, startScores: scores,
                                 classicWinByTwo: seats.count == 2 && control.level.needsTwoPointLead && goal != .tiebreak)
        engine.authoritative = authoritative
        engine.paused = paused
        return engine
    }
    private func build(_ seats: [Int], scores: [Int]?, server: Int) -> CrossEngine {
        CrossMatch.makeEngine(roster: roster, seats: seats, control: control, target: target, seed: seed, stage: stage, networked: networked,
                              server: server, scoring: CrossMatch.scoring(seats.count, mode: mode, goal: goal), scores: scores,
                              goal: goal, authoritative: auth, paused: hold)
    }
    func drainEvents() -> [CrossEvent] {
        let drained = events
        events.removeAll(keepingCapacity: true)
        return drained
    }
    func discardEvents() { events.removeAll(); engine.discardEvents() }

    func advance(_ dt: Double) {
        if hold || dt.isNaN { return }
        if let left = transition {
            let remaining = left - min(CrossEngine.maxFrame, max(0, dt))
            engine.advance(dt); collect()
            if remaining > 0 { transition = remaining; return }
            transition = nil
            begin()
            return
        }
        engine.advance(dt)
        collect()
    }
    private func collect() {
        let drained = engine.drainEvents()
        events.append(contentsOf: drained)
        if auth && !finished {
            for e in drained { if case let .rally(outcome) = e { decide(outcome) } }
        }
    }
    /// Authority: what a resolved rally means for the whole fixture.
    private func decide(_ o: CrossRallyOutcome) {
        let stageScores = o.scoresAfter
        if let stageWinner = o.winner { finish(stageWinner, stageScores); return }
        if engine.scoring != .elimination { return }
        var loser = o.eliminated
        let reached = o.targetReached != nil || pending
        if loser == nil && reached {
            guard let low = stageScores.min() else { return }
            let lowest = stageScores.indices.filter { stageScores[$0] == low }
            // A tie for the fewest points: play on until one of them gains or loses a point.
            if lowest.count > 1 { pending = true; return }
            loser = lowest[0]
        }
        guard let loserSeat = loser, loserSeat >= 0, loserSeat < active.count, stageScores.count == active.count else { return }
        let gone = active[loserSeat]
        out.append(gone); finals[gone] = stageScores[loserSeat]; pending = false
        events.append(.eliminated(seat: gone, lowest: o.eliminated == nil))
        let remaining = active.filter { $0 != gone }
        for f in remaining { if let i = active.firstIndex(of: f) { finals[f] = stageScores[i] } }
        engine.stopAfterRally = true
        if remaining.count == 2 && goal == .topTwo {
            finished = true
            let scored = finals
            placement = remaining.sorted { scored[$0] != scored[$1] ? scored[$0] > scored[$1] : $0 < $1 } + Array(out.reversed())
            return
        }
        // Reaching the target ends a round: everybody left starts again from 0. The final duel always starts at 0:0.
        let starts = reached || remaining.count == 2 ? Array(repeating: 0, count: remaining.count) : remaining.map { finals[$0] }
        // The serve keeps rotating from the player due next, skipping the one who just left.
        var due = active[crossMod(o.nextServer, active.count)]
        for _ in 0..<players { if !remaining.contains(due) { due = (due + 1) % players } }
        next = CrossStageStart(active: remaining, scores: starts, server: remaining.firstIndex(of: due) ?? 0)
        transition = CrossMatch.transitionTime
    }
    private func finish(_ stageWinner: Int, _ stageScores: [Int]) {
        guard stageScores.count == active.count, stageWinner >= 0, stageWinner < active.count else { return }
        finished = true; engine.stopAfterRally = true
        for (i, f) in active.enumerated() { finals[f] = stageScores[i] }
        let ref = engine.referee
        let faults = ref.faults, won = ref.pointsWon
        let order = active.indices.sorted { a, b in
            if stageScores[a] != stageScores[b] { return stageScores[a] > stageScores[b] }
            if faults[a] != faults[b] { return faults[a] < faults[b] }
            if won[a] != won[b] { return won[a] > won[b] }
            return a < b
        }.map { active[$0] }
        let w = active[stageWinner]
        placement = [w] + order.filter { $0 != w } + Array(out.reversed())
    }
    private func begin() {
        guard let n = next else { return }
        stage += 1; active = n.active; next = nil
        engine = build(n.active, scores: n.scores.contains { $0 > 0 } ? n.scores : nil, server: n.server)
        events.append(.stage(stage: stage, players: active.count))
    }

    func exportState() -> CrossMatchState {
        CrossMatchState(stage: stage, active: active, eliminated: out, finals: finals, pending: pending, finished: finished, placement: placement,
                        transition: transition, next: next, engine: engine.exportState())
    }
    /// Adopts a checkpoint; a different stage rebuilds the table first. New eliminations are announced once. Throws, changing
    /// nothing, for an invalid state.
    func restoreState(_ s: CrossMatchState, preserveInput: Bool = false) throws {
        let seatRange = 0..<players
        // Android 1fc4bc2: a player who just went out is still at the table during the announcement (the next stage leaves them
        // out), and the last one out of a finished top-two table is still in its last stage; both checkpoints must reopen.
        let goal = self.goal
        func eliminatedOk(_ seat: Int) -> Bool {
            guard seatRange.contains(seat) else { return false }
            if !s.active.contains(seat) { return true }
            if s.transition != nil, let n = s.next, !n.active.contains(seat) { return true }
            return s.finished && goal == .topTwo && s.placement.dropFirst(2).contains(seat) && !s.placement.prefix(2).contains(where: { s.eliminated.contains($0) })
        }
        guard s.active.count >= 2, s.active.count <= players, s.active.allSatisfy({ seatRange.contains($0) }), s.active == s.active.sorted(),
              Set(s.active).count == s.active.count, s.finals.count == players,
              Set(s.eliminated).count == s.eliminated.count, s.eliminated.allSatisfy(eliminatedOk),
              s.placement.allSatisfy({ seatRange.contains($0) }), s.transition.map({ $0.isFinite }) ?? true else {
            throw CrossStateError.invalid("Invalid match state")
        }
        if let n = s.next {
            guard s.transition != nil, n.active == s.active.filter({ !s.eliminated.contains($0) }), n.active.count >= 2,
                  n.active.allSatisfy({ seatRange.contains($0) }), n.scores.count == n.active.count, n.active.indices.contains(n.server) else {
                throw CrossStateError.invalid("Invalid match state")
            }
        }
        guard s.engine.referee.scores.count == s.active.count else { throw CrossStateError.invalid("Stage seat count mismatch") }
        let sameStage = s.stage == stage && s.active == active
        let known = Set(out)
        if sameStage {
            try engine.restoreState(s.engine, preserveInput: preserveInput)
        } else {
            let previousStage = stage
            stage = s.stage
            let fresh = build(s.active, scores: nil, server: 0)
            do { try fresh.restoreState(s.engine, preserveInput: false) } catch { stage = previousStage; throw error }
            active = s.active; engine = fresh
            events.append(.stage(stage: stage, players: active.count))
        }
        out = s.eliminated; finals = s.finals
        pending = s.pending; finished = s.finished; placement = s.placement; transition = s.transition; next = s.next
        engine.stopAfterRally = finished || transition != nil
        for seat in s.eliminated where !known.contains(seat) { events.append(.eliminated(seat: seat, lowest: true)) }
    }
    /// Authority: another human's strike, for the stage it was made in (`fixtureSeat` is the sender's roster seat).
    @discardableResult func applyRemoteStrike(stage: Int, fixtureSeat: Int, _ strike: CrossStrike, rallyId: Int, hitIndex: Int) -> Bool {
        if stage != self.stage || transition != nil || finished { return false }
        guard let seat = stageSeat(fixtureSeat), strike.seat == seat else { return false }
        return engine.applyRemoteStrike(seat, strike, rallyId: rallyId, hitIndex: hitIndex)
    }
    func localStrike() -> CrossStrike? { engine.localStrike() }
    var localStrikeID: Int { engine.localStrikeID }
    func placementIds(_ ids: [String]) -> [String] { placement.compactMap { $0 >= 0 && $0 < ids.count ? ids[$0] : nil } }
}
