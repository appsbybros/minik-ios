import Foundation

// Android cross/CrossState.kt (MinikCrossPong 5c1aa4d): the protocol-2 checkpoint/action wire format, field for field. Absent
// (nil) values are omitted, as RTDB drops nulls; RTDB lists may arrive as arrays or index-keyed maps and read back in index
// order.

/// Wire readers with Android `Wire.number/decimal/flag/text` semantics.
enum CrossWire {
    static func number(_ w: MPWire, _ key: String, _ fallback: Int64 = 0) -> Int64 { (w[key] as? NSNumber)?.int64Value ?? fallback }
    static func int(_ w: MPWire, _ key: String, _ fallback: Int = 0) -> Int { Int(number(w, key, Int64(fallback))) }
    static func decimal(_ w: MPWire, _ key: String, _ fallback: Double = 0) -> Double { (w[key] as? NSNumber)?.doubleValue ?? fallback }
    static func optional(_ w: MPWire, _ key: String) -> Double? { (w[key] as? NSNumber)?.doubleValue }
    static func seat(_ w: MPWire, _ key: String) -> Int? { (w[key] as? NSNumber).map { Int($0.int64Value) } }
    static func flag(_ w: MPWire, _ key: String) -> Bool { (w[key] as? Bool) == true }
    static func text(_ w: MPWire, _ key: String, _ fallback: String = "") -> String { (w[key] as? String) ?? fallback }
    /// Android CrossState `entries`: list or index-keyed map, absent slots dropped, index order.
    static func entries(_ raw: Any?) -> [Any] {
        var indexed: [(Int, Any)] = []
        for (key, value) in MPCodec.map(raw) { if let index = Int(key) { indexed.append((index, value)) } }
        return indexed.sorted { $0.0 < $1.0 }.map { $0.1 }
    }
    static func ints(_ raw: Any?) -> [Int] { entries(raw).map { ($0 as? NSNumber).map { Int($0.int64Value) } ?? 0 } }
    static func point(_ p: MPPoint) -> MPWire { ["x": p.x, "y": p.y] }
    static func vector(_ w: MPWire) -> MPPoint { MPPoint(decimal(w, "x"), decimal(w, "y")) }
}

/// One committed contact as published: `ball` is the exact state right after the hit (a serve carries its own-bounce
/// rebound), `point`/`height` the contact. `rallyId`/`hitIndex` identify it; the serve is hit 0.
struct CrossStrike: Equatable {
    var seat: Int
    var point: MPPoint
    var height: Double
    var ball: CrossBallState
    var serve: Bool
    var rallyId = 0
    var hitIndex = 0
    /// Team play: a raised pass to the striker's teammate. Only written when true, so individual strikes keep their shape.
    var raised = false
    func wire() -> MPWire {
        var w: MPWire = ["seat": seat, "point": CrossWire.point(point), "height": height, "ball": ball.wire(), "serve": serve, "rally": rallyId, "hit": hitIndex]
        if raised { w["raised"] = true }
        return w
    }
    static func read(_ w: MPWire) -> CrossStrike {
        CrossStrike(seat: CrossWire.int(w, "seat", -1), point: CrossWire.vector(MPCodec.map(w["point"])), height: CrossWire.decimal(w, "height"),
                    ball: CrossBallState.read(MPCodec.map(w["ball"])), serve: CrossWire.flag(w, "serve"),
                    rallyId: CrossWire.int(w, "rally"), hitIndex: CrossWire.int(w, "hit"), raised: CrossWire.flag(w, "raised"))
    }
}

/// A seat's racket in its own frame: where it is, where it is heading and in how many seconds.
struct CrossMotionState: Equatable {
    var u: Double
    var v: Double
    var toU: Double
    var toV: Double
    var remaining: Double
    var left: Bool
    func wire() -> MPWire { ["u": u, "v": v, "toU": toU, "toV": toV, "remaining": remaining, "left": left] }
    static func read(_ w: MPWire) -> CrossMotionState {
        CrossMotionState(u: CrossWire.decimal(w, "u"), v: CrossWire.decimal(w, "v"), toU: CrossWire.decimal(w, "toU"), toV: CrossWire.decimal(w, "toV"),
                         remaining: CrossWire.decimal(w, "remaining"), left: CrossWire.flag(w, "left"))
    }
}

/// A wire map compared by value, for Equatable states that carry one.
struct CrossWireBox: Equatable {
    var value: MPWire
    init(_ value: MPWire = [:]) { self.value = value }
    static func == (a: CrossWireBox, b: CrossWireBox) -> Bool { NSDictionary(dictionary: a.value).isEqual(to: b.value) }
}

/// Authoritative match state for checkpoints (protocol 2): referee, ball, phase timers (point delay, house serve delay), the
/// pending remote-receiver grace, the last strike (peers animate it once) and every seat's racket motion. 5c1aa4d adds the team
/// rally ("localTeam", team tables only), the practice aim and placed paddle (journeys only) and the shared reception pace
/// (always written, empty when unused; absent in old checkpoints).
struct CrossState: Equatable {
    static let protocolVersion = 2
    var referee: CrossRefereeState
    var ball: CrossBallState
    var pointDelay: Double? = nil
    var serveDelay: Double? = nil
    var grace: Double? = nil
    var strike: CrossStrike? = nil
    var motions: [CrossMotionState] = []
    var team: CrossTeamFlight? = nil
    var practiceAim: MPPoint? = nil
    var paddlePlaced = false
    var reception = CrossWireBox()
    func wire() -> MPWire {
        var w: MPWire = ["reception": reception.value, "protocol": CrossState.protocolVersion, "referee": referee.wire(), "ball": ball.wire(),
                         "motions": motions.map { $0.wire() }]
        if let pointDelay { w["pointDelay"] = pointDelay }
        if let serveDelay { w["serveDelay"] = serveDelay }
        if let grace { w["grace"] = grace }
        if let strike { w["strike"] = strike.wire() }
        if let team { w["localTeam"] = team.wire() }
        if let practiceAim { w["practiceAim"] = CrossWire.point(practiceAim); w["paddlePlaced"] = paddlePlaced }
        return w
    }
    static func read(_ w: MPWire) throws -> CrossState {
        guard CrossWire.number(w, "protocol") == Int64(protocolVersion) else { throw CrossStateError.invalid("Unsupported cross match protocol") }
        let strikeWire = MPCodec.map(w["strike"])
        let referee = try CrossRefereeState.read(MPCodec.map(w["referee"]))
        let teamWire = MPCodec.map(w["localTeam"]), aimWire = MPCodec.map(w["practiceAim"])
        var team: CrossTeamFlight?
        if !teamWire.isEmpty { team = try CrossTeamFlight.read(teamWire) }
        let reception = try CrossReception.canonical(MPCodec.map(w["reception"]))
        return CrossState(referee: referee, ball: CrossBallState.read(MPCodec.map(w["ball"])),
                          pointDelay: CrossWire.optional(w, "pointDelay"), serveDelay: CrossWire.optional(w, "serveDelay"), grace: CrossWire.optional(w, "grace"),
                          strike: strikeWire.isEmpty ? nil : CrossStrike.read(strikeWire),
                          motions: CrossWire.entries(w["motions"]).map { CrossMotionState.read(MPCodec.map($0)) },
                          team: team, practiceAim: aimWire.isEmpty ? nil : CrossWire.vector(aimWire), paddlePlaced: CrossWire.flag(w, "paddlePlaced"),
                          reception: CrossWireBox(reception))
    }
}

extension CrossBallState {
    func wire() -> MPWire {
        var w: MPWire = ["x": position.x, "y": position.y, "height": height, "vx": velocity.x, "vy": velocity.y, "lift": lift, "stopped": stopped]
        if let rebound { w["rebound"] = ["vx": rebound.velocity.x, "vy": rebound.velocity.y, "lift": rebound.lift] }
        return w
    }
    static func read(_ w: MPWire) -> CrossBallState {
        let r = MPCodec.map(w["rebound"])
        return CrossBallState(position: MPPoint(CrossWire.decimal(w, "x"), CrossWire.decimal(w, "y")), height: CrossWire.decimal(w, "height"),
                              velocity: MPPoint(CrossWire.decimal(w, "vx"), CrossWire.decimal(w, "vy")), lift: CrossWire.decimal(w, "lift"),
                              rebound: r.isEmpty ? nil : CrossLaunch(velocity: MPPoint(CrossWire.decimal(r, "vx"), CrossWire.decimal(r, "vy")), lift: CrossWire.decimal(r, "lift")),
                              stopped: CrossWire.flag(w, "stopped"))
    }
}

extension CrossRallyOutcome {
    func wire() -> MPWire {
        var w: MPWire = ["rallyId": rallyId, "kind": kind.rawValue, "striker": striker, "deltas": deltas, "scoresAfter": scoresAfter,
                         "floored": floored, "nextServer": nextServer]
        if let receiver { w["receiver"] = receiver }
        if let faultOwner { w["faultOwner"] = faultOwner }
        if let winner { w["winner"] = winner }
        if let eliminated { w["eliminated"] = eliminated }
        if let targetReached { w["targetReached"] = targetReached }
        return w
    }
    static func read(_ w: MPWire) throws -> CrossRallyOutcome {
        guard let kind = CrossRallyKind(rawValue: CrossWire.text(w, "kind")) else { throw CrossStateError.invalid("Unknown rally kind") }
        return CrossRallyOutcome(rallyId: CrossWire.int(w, "rallyId"), kind: kind, striker: CrossWire.int(w, "striker"), receiver: CrossWire.seat(w, "receiver"),
                                 faultOwner: CrossWire.seat(w, "faultOwner"), deltas: CrossWire.ints(w["deltas"]), scoresAfter: CrossWire.ints(w["scoresAfter"]),
                                 floored: CrossWire.flag(w, "floored"), nextServer: CrossWire.int(w, "nextServer"), winner: CrossWire.seat(w, "winner"),
                                 eliminated: CrossWire.seat(w, "eliminated"), targetReached: CrossWire.seat(w, "targetReached"))
    }
}

extension CrossRefereeState {
    func wire() -> MPWire {
        var w: MPWire = ["scores": scores, "server": server, "rallyId": rallyId, "ralliesPlayed": ralliesPlayed, "phase": phase.rawValue,
                         "striker": striker, "hits": hits, "pointsWon": pointsWon, "faults": faults, "misses": misses]
        if let winner { w["winner"] = winner }
        if let receiver { w["receiver"] = receiver }
        if let lastOutcome { w["lastOutcome"] = lastOutcome.wire() }
        return w
    }
    static func read(_ w: MPWire) throws -> CrossRefereeState {
        guard let phase = CrossRallyPhase(rawValue: CrossWire.text(w, "phase")) else { throw CrossStateError.invalid("Unknown rally phase") }
        let last = MPCodec.map(w["lastOutcome"])
        var outcome: CrossRallyOutcome?
        if !last.isEmpty { outcome = try CrossRallyOutcome.read(last) }
        return CrossRefereeState(scores: CrossWire.ints(w["scores"]), server: CrossWire.int(w, "server"), rallyId: CrossWire.int(w, "rallyId", 1),
                                 ralliesPlayed: CrossWire.int(w, "ralliesPlayed"), winner: CrossWire.seat(w, "winner"), phase: phase,
                                 striker: CrossWire.int(w, "striker"), receiver: CrossWire.seat(w, "receiver"), hits: CrossWire.int(w, "hits"),
                                 pointsWon: CrossWire.ints(w["pointsWon"]), faults: CrossWire.ints(w["faults"]), misses: CrossWire.ints(w["misses"]),
                                 lastOutcome: outcome)
    }
}
