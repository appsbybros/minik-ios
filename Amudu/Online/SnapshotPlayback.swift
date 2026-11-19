import Foundation

/// Android `SnapshotDelta` (SnapshotPlayback.kt): leaf patches retain atomic public/checkpoint agreement without
/// retransmitting unchanged roster/history. A removed value is `NSNull` (Kotlin `null`), which Firebase deletes.
enum SnapshotDelta {
    static func between(_ previous: Node, _ next: Node) -> [String: Any] {
        var out: [String: Any] = [:]
        func visit(_ path: String, _ a: Any?, _ b: Any?) {
            if NodeEquality.same(a, b) { return }
            if !AmuduCodec.isNull(a), !AmuduCodec.isNull(b), let x = a as? [String: Any], let y = b as? [String: Any] {
                for key in keys(x, y) { visit(path.isEmpty ? key : "\(path)/\(key)", x[key], y[key]) }
            } else {
                out[path] = (AmuduCodec.isNull(b) ? nil : b) ?? NSNull()
            }
        }
        for key in keys(previous, next) { visit(key, previous[key], next[key]) }
        return out
    }

    /// Kotlin `a.keys + b.keys`: the previous keys, then the new ones.
    private static func keys(_ a: [String: Any], _ b: [String: Any]) -> [String] {
        var out = Array(a.keys)
        for key in b.keys where a[key] == nil { out.append(key) }
        return out
    }
}

/// Android `SnapshotPlayback`: locally evaluates known paths continuously. The host alone decides catches, possession
/// and score. Times are `uptimeMs()` milliseconds (Android `SystemClock.uptimeMillis()`).
final class SnapshotPlayback {
    private var state: Node = [:]
    private var received: Int64 = 0
    private var transit = 0.0
    private var renderTime = 0.0
    private var lastRender: Int64 = 0
    private var correctionAt: Int64 = 0
    private var offsets: [String: V] = [:]
    private var facings: [String: V] = [:]
    private var ballOffset = V(0.0, 0.0)
    private var heightOffset = 0.0

    func accept(_ e: AmuduEngine, _ n: Node, _ at: Int64, _ delay: Double) {
        let first = state.isEmpty
        var oldPositions: [String: V] = [:]
        for a in e.actors { oldPositions[a.member.id] = a.position }
        let oldBall = e.ball
        let incoming = AmuduCodec.node(n["ball"])
        let incomingHolder = incoming.str("holder")
        let sameFlight = !first && oldBall.flightId == incoming.str("flightId") &&
            oldBall.holder == (Kotlin.isBlank(incomingHolder) ? nil : incomingHolder)
        let oldPhase = state.str("phase")
        if Kotlin.toInt(n.num("motionProtocol")) == MotionState.VERSION {
            state = n
        } else {
            var legacy = n
            legacy["motionProtocol"] = MotionState.VERSION
            var actors: [String: Any] = [:]
            for (id, value) in AmuduCodec.node(n["actors"]) {
                var x = AmuduCodec.node(value)
                x["motionAt"] = n.num("time")
                actors[id] = x
            }
            legacy["actors"] = actors
            var ball = incoming
            ball["motionAt"] = n.num("time")
            legacy["ball"] = ball
            state = legacy
        }
        received = at
        transit = Kotlin.clamp(delay, 0.0, 0.60)
        correctionAt = at
        if first {
            renderTime = n.num("time") + transit
            lastRender = at
        }
        // A stalled host or delayed first packet must not launch a new ball on the
        // previous phase's extrapolated clock (which can be seconds ahead).
        if !first && oldBall.flightId != incoming.str("flightId") && Kotlin.isBlank(incomingHolder) {
            renderTime = n.num("time") + min(transit, 0.06)
            lastRender = at
        }
        if n.flag("sharedPause") || !AmuduCodec.node(n["result"]).isEmpty {
            renderTime = n.num("time")
        } else if oldPhase != n.str("phase") {
            renderTime = max(renderTime, n.num("phaseAt"))
        }
        AmuduCodec.apply(e, state)
        let projected = MotionState.materialize(state, renderTime)
        offsets.removeAll()
        let projectedActors = AmuduCodec.node(projected["actors"])
        for a in e.actors {
            let id = a.member.id
            let target = AmuduCodec.vector(AmuduCodec.node(projectedActors[id])["position"])
            let delta = (oldPositions[id] ?? target) - target
            // Compare at the SAME simulation time. Comparing with the unadvanced snapshot
            // added velocity * network delay on every packet and produced visible shaking.
            if !first && delta.length() < 2.0 { offsets[id] = delta }
            if first { facings[id] = a.facing }
        }
        let b = AmuduCodec.node(projected["ball"])
        let projectedPosition = AmuduCodec.vector(b["position"])
        ballOffset = (sameFlight && oldBall.holder == nil && (oldBall.position - projectedPosition).length() < 2)
            ? oldBall.position - projectedPosition : V(0.0, 0.0)
        heightOffset = (sameFlight && oldBall.holder == nil && abs(oldBall.height - b.num("height")) < 2)
            ? oldBall.height - b.num("height") : 0.0
    }

    func render(_ e: AmuduEngine, _ now: Int64) {
        if state.isEmpty { return }
        let dt = Kotlin.clamp(Double(now - lastRender) / 1000.0, 0.0, 0.25)
        lastRender = now
        let targetTime = state.num("time") + transit + Double(max(now - received, 0)) / 1000.0
        let paused = state.flag("sharedPause") || !AmuduCodec.node(state["result"]).isEmpty
        if paused {
            renderTime = state.num("time")
        } else {
            renderTime += dt * Kotlin.clamp(1 + (targetTime - renderTime - dt) * 2, 0.85, 1.15)
        }
        let correction = exp(Double(-max(now - correctionAt, 0)) / 150.0)
        let rendered = MotionState.materialize(state, renderTime)
        e.time = renderTime
        for (id, value) in AmuduCodec.node(rendered["actors"]) {
            guard let a = e.actor(id) else { continue }
            let n = AmuduCodec.node(value)
            let p = AmuduCodec.vector(n["position"]) + (offsets[id] ?? V(0.0, 0.0)) * correction
            a.position = V(Kotlin.clamp(p.x, 0.6, e.config.width - 0.6), Kotlin.clamp(p.y, 0.6, e.config.depth - 0.6))
            a.gait = n.num("gait")
            a.jumpHeight = n.num("jumpHeight")
            a.jumpVelocity = n.num("jumpVelocity")
            a.actuallyMoving = n.flag("actuallyMoving")
            let wanted = AmuduCodec.vector(n["facing"])
            let old = facings[id] ?? wanted
            let next = (old * exp(-dt * 12) + wanted * (1 - exp(-dt * 12))).unit()
            a.facing = next.length() < 0.01 ? wanted : next
            facings[id] = a.facing
        }
        e.ball = MotionState.readBall(AmuduCodec.node(rendered["ball"]))
        if let holder = e.ball.holder {
            if let a = e.actor(holder) { e.ball.position = a.position }
            return
        }
        e.ball.position = e.ball.position + ballOffset * correction
        e.ball.height = max(0.23, e.ball.height + heightOffset * correction)
    }
}
