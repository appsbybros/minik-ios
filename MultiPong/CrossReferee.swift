import Foundation

// Android cross/CrossReferee.kt (MinikCrossPong 5c1aa4d). Wire names are the Kotlin enum names.

enum CrossRallyPhase: String, CaseIterable {
    case awaitingServe = "AWAITING_SERVE", serveOwn = "SERVE_OWN", toReceiver = "TO_RECEIVER", receivable = "RECEIVABLE", resolved = "RESOLVED"
    /// Kotlin `ordinal` (checkpoint progress comparison).
    var ordinal: Int { CrossRallyPhase.allCases.firstIndex(of: self) ?? 0 }
    var live: Bool { self == .serveOwn || self == .toReceiver || self == .receivable }
}
enum CrossRallyKind: String, CaseIterable {
    case net = "NET", out = "OUT", ownSide = "OWN_SIDE", badServe = "BAD_SERVE", missed = "MISSED"
}

/// How a table stage scores. multi: the agreed 3/4-player rules (a loss at 0 is forgiven, the first to the target wins).
/// elimination: a loss at 0 eliminates that player and reaching the target is only reported (the match decides who drops
/// out). classic: two players, every error gives the opponent the point, the first to the target wins.
enum CrossScoring { case multi, elimination, classic }

/// One resolved rally. A fault (`faultOwner`) never gives anybody a point; missed gives `striker` +1 and the responsible
/// `receiver` -1. A -1 at 0 is floored: its delta stays 0 and `floored` is true.
struct CrossRallyOutcome: Equatable {
    var rallyId: Int
    var kind: CrossRallyKind
    var striker: Int
    var receiver: Int?
    var faultOwner: Int?
    var deltas: [Int]
    var scoresAfter: [Int]
    var floored: Bool
    var nextServer: Int
    var winner: Int?
    var eliminated: Int? = nil
    var targetReached: Int? = nil
    /// The seat charged with the rally: the fault owner, or the receiver who missed.
    var loser: Int? { faultOwner ?? receiver }
}

/// Snapshot for networking / restore.
struct CrossRefereeState: Equatable {
    var scores: [Int]
    var server: Int
    var rallyId: Int
    var ralliesPlayed: Int
    var winner: Int?
    var phase: CrossRallyPhase
    var striker: Int
    var receiver: Int?
    var hits: Int
    var pointsWon: [Int]
    var faults: [Int]
    var misses: [Int]
    var lastOutcome: CrossRallyOutcome? = nil
}

enum CrossStateError: Error, LocalizedError {
    case invalid(String)
    var errorDescription: String? { if case let .invalid(text) = self { return text }; return nil }
}

/// Rally state machine and scoring of the 3/4-player game. It consumes ball events, strike notifications and the ball's
/// position; every rally resolves exactly once and later input is ignored until `nextRally`.
final class CrossReferee {
    let geometry: CrossGeometry
    let target: Int
    let scoring: CrossScoring
    let players: Int
    let firstServer: Int
    /// Team play (Android `teams`): teammates share every point and nobody loses one; a miss or fault gives the other team the
    /// point. Only for the multi scoring of a 3/4-seat table.
    let teams: CrossTeams?
    private var board: [Int]
    private var won: [Int]
    private var faulted: [Int]
    private var missed: [Int]
    /// Rally r is served by (firstServer + ralliesPlayed) mod n, whatever the previous outcome.
    private(set) var server: Int
    /// Increments at the start of every rally, starting at 1.
    private(set) var rallyId = 1
    private(set) var ralliesPlayed = 0
    private(set) var winner: Int?
    private(set) var phase = CrossRallyPhase.awaitingServe
    /// Last hitter (the server until the serve is struck).
    private(set) var striker: Int
    /// Responsible receiver after a legal receiving bounce.
    private(set) var receiver: Int?
    /// Contacts in this rally; the serve is 0.
    private(set) var hits = 0
    private(set) var lastOutcome: CrossRallyOutcome?

    /// Android requires target >= 1, classic scoring only for two players and start scores in [0, target): invalid values
    /// (only possible from a corrupt checkpoint) are corrected here instead of crashing the court.
    init(_ geometry: CrossGeometry, target: Int, firstServer: Int = 0, scoring: CrossScoring = .multi, startScores: [Int]? = nil,
         teams: CrossTeams? = nil) {
        self.geometry = geometry
        self.target = max(1, target)
        let mode: CrossScoring = scoring == .classic && geometry.players != 2 ? .multi : scoring
        self.scoring = mode
        players = geometry.players
        // Android requires a team table to match the seats and use multi scoring; anything else plays individually.
        var team: CrossTeams?
        if let teams, teams.seats.count == geometry.players, mode == .multi { team = teams }
        self.teams = team
        let opening = geometry.wrap(firstServer)
        self.firstServer = opening
        let zeros = Array(repeating: 0, count: geometry.players)
        var start = zeros
        if let startScores, startScores.count == geometry.players, startScores.allSatisfy({ $0 >= 0 && $0 < max(1, target) }),
           CrossReferee.teamScoresAgree(team, startScores) { start = startScores }
        board = start
        won = zeros
        faulted = zeros
        missed = zeros
        server = opening
        striker = opening
    }
    var scores: [Int] { board }
    var pointsWon: [Int] { won }
    var faults: [Int] { faulted }
    var misses: [Int] { missed }
    func score(_ seat: Int) -> Int { board[geometry.wrap(seat)] }
    /// The live ball is still the serve.
    var serving: Bool { hits == 0 && (phase == .serveOwn || phase == .toReceiver) }
    var resolved: Bool { phase == .resolved }
    func mayServe(_ seat: Int) -> Bool { phase == .awaitingServe && winner == nil && seat == server }
    func mayStrike(_ seat: Int) -> Bool { phase == .receivable && seat == receiver }
    /// The server strikes the serve; with a `point`, it must be inside the server's strike zone.
    @discardableResult func serve(_ seat: Int, _ point: MPPoint? = nil) -> Bool {
        if !mayServe(seat) { return false }
        if let point, !geometry.inStrikeZone(seat, point) { return false }
        phase = .serveOwn; striker = seat; receiver = nil; hits = 0
        return true
    }
    /// A serve gesture that never produced a ball (weak/backward Pro swipe) is the server's bad serve.
    func serveFault(_ seat: Int) -> CrossRallyOutcome? {
        guard mayServe(seat) else { return nil }
        striker = seat
        return resolve(.badServe, seat)
    }
    /// Only the responsible receiver may hit, once the ball made its legal bounce.
    @discardableResult func strike(_ seat: Int, _ point: MPPoint? = nil) -> Bool {
        if !mayStrike(seat) { return false }
        if let point, !geometry.inStrikeZone(seat, point) { return false }
        striker = seat; receiver = nil; hits += 1; phase = .toReceiver
        return true
    }
    /// What `event` means now, without applying it: the resolution it causes, or nil (legal or ignored).
    func verdict(_ event: CrossBallEvent) -> CrossRallyKind? {
        switch phase {
        case .serveOwn:
            if case let .bounce(point, _) = event, geometry.inServeZone(striker, point) { return nil }
            return .badServe
        case .toReceiver:
            if case let .bounce(_, owner) = event, owner != striker { return nil }
            if hits == 0 { return .badServe }
            switch event {
            case .bounce: return .ownSide
            case .net: return .net
            case .landed: return .out
            }
        // After the legal bounce any further bounce, landing or net contact is the receiver's miss.
        case .receivable: return .missed
        case .awaitingServe, .resolved: return nil
        }
    }
    @discardableResult func ball(_ event: CrossBallEvent) -> CrossRallyOutcome? {
        guard let kind = verdict(event) else {
            if phase == .serveOwn { phase = .toReceiver }
            else if phase == .toReceiver, case let .bounce(_, owner) = event { receiver = owner; phase = .receivable }
            return nil
        }
        return kind == .missed ? miss() : resolve(kind, striker)
    }
    /// The responsible receiver can no longer legally meet the ball: it is dead, or (travelling in a straight line) it has
    /// left the receiver's strike zone, or never reaches it, and cannot come back.
    func unreachable(_ ball: CrossBallState) -> Bool {
        guard let r = receiver, phase == .receivable else { return false }
        if ball.stopped { return true }
        let p = geometry.toLocal(r, ball.position)
        let v = geometry.toLocal(r, ball.velocity)
        return abs(p.u) > CrossGeometry.strikeHalf || p.v > CrossGeometry.strikeFar || (p.v < CrossGeometry.strikeNear && v.v <= 0)
    }
    /// Called with the live ball between events: a ball leaving the receiver's reach is missed.
    func follow(_ ball: CrossBallState) -> CrossRallyOutcome? { unreachable(ball) ? miss() : nil }
    /// The responsible receiver did not return the ball (also the engine's grace expiry for a remote receiver).
    @discardableResult func miss() -> CrossRallyOutcome? {
        guard phase == .receivable, let r = receiver else { return nil }
        return resolve(.missed, r, gainer: striker)
    }
    /// Starts the next rally after a resolution; false once there is a winner.
    @discardableResult func nextRally() -> Bool {
        if phase != .resolved || winner != nil { return false }
        rallyId += 1; server = crossMod(firstServer + ralliesPlayed, players); striker = server; receiver = nil; hits = 0
        phase = .awaitingServe
        return true
    }
    func exportState() -> CrossRefereeState {
        CrossRefereeState(scores: board, server: server, rallyId: rallyId, ralliesPlayed: ralliesPlayed, winner: winner, phase: phase,
                          striker: striker, receiver: receiver, hits: hits, pointsWon: won, faults: faulted, misses: missed, lastOutcome: lastOutcome)
    }
    /// Android `restore` (`require` → throws): nothing changes unless the whole state is consistent.
    func restore(_ s: CrossRefereeState) throws {
        guard [s.scores, s.pointsWon, s.faults, s.misses].allSatisfy({ $0.count == players }) else { throw CrossStateError.invalid("Seat count mismatch") }
        let seatRange = 0..<players
        guard seatRange.contains(s.server), seatRange.contains(s.striker), s.receiver.map({ seatRange.contains($0) }) ?? true,
              s.winner.map({ seatRange.contains($0) }) ?? true else { throw CrossStateError.invalid("Seat out of range") }
        guard s.rallyId >= 1, s.ralliesPlayed >= 0, s.hits >= 0, s.scores.allSatisfy({ $0 >= 0 && $0 <= target }) else { throw CrossStateError.invalid("Invalid referee state") }
        // A receiver exists exactly while the ball is receivable (and may remain on a resolved missed); a winner ends play.
        let receiverOk = (s.phase != .receivable || s.receiver != nil) && (s.receiver == nil || s.phase == .receivable || s.phase == .resolved)
        let winnerOk = s.winner.map { s.phase == .resolved && s.scores[$0] >= target } ?? true
        guard receiverOk, winnerOk else { throw CrossStateError.invalid("Inconsistent referee state") }
        guard CrossReferee.teamScoresAgree(teams, s.scores) else { throw CrossStateError.invalid("Team scores differ") }
        board = s.scores; won = s.pointsWon; faulted = s.faults; missed = s.misses
        server = s.server; rallyId = s.rallyId; ralliesPlayed = s.ralliesPlayed; winner = s.winner; phase = s.phase
        striker = s.striker; receiver = s.receiver; hits = s.hits; lastOutcome = s.lastOutcome
    }
    /// Teammates always have equal scores (Android `require`, "Team scores differ").
    private static func teamScoresAgree(_ teams: CrossTeams?, _ scores: [Int]) -> Bool {
        guard let teams, scores.count == teams.seats.count else { return true }
        for a in scores.indices { for b in scores.indices where teams.same(a, b) && scores[a] != scores[b] { return false } }
        return true
    }
    private func resolve(_ kind: CrossRallyKind, _ loser: Int, gainer: Int? = nil) -> CrossRallyOutcome {
        var deltas = Array(repeating: 0, count: players)
        // classic: every error gives the opponent the point and nobody ever loses one.
        // Teams: the other team gains (the striker's team after a miss), every teammate together; nobody loses a point.
        let gain: Int?
        if let teams {
            if let gainer, !teams.same(gainer, loser) { gain = gainer } else { gain = teams.opponents(loser).first }
        } else if scoring == .classic { gain = gainer ?? crossMod(loser + 1, players) }
        else { gain = gainer }
        if let gain {
            if let teams { for seat in geometry.seats where teams.same(seat, gain) { deltas[seat] = 1 } } else { deltas[gain] = 1 }
        }
        var floored = false
        var out: Int?
        if teams == nil && scoring != .classic {
            if board[loser] > 0 { deltas[loser] = -1 }
            else if scoring == .elimination { out = loser } // dropping below zero is out
            else { floored = true }                          // a loss at 0 is forgiven
        }
        for i in 0..<players { board[i] += deltas[i] }
        if let gain { won[gain] += 1 }
        if gainer != nil { missed[loser] += 1 } else { faulted[loser] += 1 }
        ralliesPlayed += 1
        var reached: Int?
        // The first to reach the target wins at once (no win-by-two); in elimination it only triggers a drop-out.
        if let gain, board[gain] >= target {
            if scoring == .elimination { reached = gain } else if winner == nil { winner = gain }
        }
        phase = .resolved
        let outcome = CrossRallyOutcome(rallyId: rallyId, kind: kind, striker: striker, receiver: gainer != nil ? loser : nil,
                                        faultOwner: gainer == nil ? loser : nil, deltas: deltas, scoresAfter: board, floored: floored,
                                        nextServer: crossMod(firstServer + ralliesPlayed, players), winner: winner, eliminated: out, targetReached: reached)
        lastOutcome = outcome
        return outcome
    }
}
