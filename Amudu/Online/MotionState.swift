import Foundation

/// Android `MotionState` (MotionState.kt): versioned motion anchors. No client predicts ownership, penalties or a
/// successful catch. Statement-by-statement port (same float operations); Kotlin nulls inside nodes are `NSNull`.
enum MotionState {
    static let VERSION = 4

    /// Kotlin `n["key"]` that is neither missing nor null.
    static func present(_ value: Any?) -> Any? {
        return AmuduCodec.isNull(value) ? nil : value
    }

    /// The `Ball(...)` a motion node describes.
    static func readBall(_ n: Node) -> Ball {
        let holder = n.str("holder")
        var b = Ball(AmuduCodec.vector(n["position"]), n.num("height"), AmuduCodec.vector(n["velocity"]), n.num("vz"),
                     Kotlin.isBlank(holder) ? nil : holder, bounces: Kotlin.toInt(n.num("bounces")), flightId: n.str("flightId"),
                     launchAt: n.num("launchAt"))
        b.burst = n.flag("burst")
        b.burstOnGround = n.flag("burstOnGround")
        b.burstOnCatch = n.flag("burstOnCatch")
        return b
    }

    /// Kotlin `crossing(p, v, a, bound)`: the first future time a constant-acceleration coordinate reaches `bound`.
    private static func crossing(_ p: Double, _ v: Double, _ a: Double, _ bound: Double) -> Double {
        if abs(a) < 1e-9 {
            if abs(v) < 1e-9 { return Double.infinity }
            let t = (bound - p) / v
            return t > 1e-7 ? t : Double.infinity
        }
        let disc = v * v - 2 * a * (p - bound)
        if disc < 0 { return Double.infinity }
        let roots = [(-v - disc.squareRoot()) / a, (-v + disc.squareRoot()) / a].filter { $0 > 1e-7 }
        return roots.min() ?? Double.infinity
    }

    static func ball(_ n: Node, _ c: GameConfig, _ wind: V, _ at: Double, _ active: Bool, contain: Bool = false) -> Ball {
        var b = readBall(n)
        var left = Kotlin.clamp(at - n.num("motionAt", at), 0.0, 30.0)
        if !active || b.holder != nil || b.burst { return b }
        // Analytic free flight; only iterate at a real wall/floor boundary, not once per video frame.
        for _ in 0..<32 {
            if left <= 1e-8 || (b.height <= 0.23001 && abs(b.vz) < 0.01 && b.velocity.length() < 0.01) { return b }
            let force = contain ? GroundBounce.edgeWind(b, c, wind) : wind
            let floor = (b.vz + max(0.0, b.vz * b.vz + 2 * c.scene.gravity * (b.height - 0.23)).squareRoot()) / c.scene.gravity
            let wallX = !contain ? Double.infinity
                : min(crossing(b.position.x, b.velocity.x, force.x, 0.25), crossing(b.position.x, b.velocity.x, force.x, c.width - 0.25))
            let wallY = !contain ? Double.infinity
                : min(crossing(b.position.y, b.velocity.y, force.y, 0.25), crossing(b.position.y, b.velocity.y, force.y, c.depth - 0.25))
            let t = min(left, min(max(0.0, floor), min(wallX, wallY)))
            BallFlight.advance(&b, t, c.scene.gravity, force)
            left -= t
            if floor <= t + 1e-7 {
                if c.ball == .paint && b.burstOnGround {
                    b.height = 0.23
                    b.velocity = V(0.0, 0.0)
                    b.vz = 0.0
                    return b
                }
                b.height = 0.23
                let incoming = abs(b.vz)
                b.vz = incoming * c.ball.restitution * c.scene.bounce
                b.velocity = (contain ? GroundBounce.direction(b.velocity, b.flightId, b.bounces) : b.velocity) * 0.8
                b.bounces += 1
                if incoming < 0.7 || b.bounces > 5 {
                    b.vz = 0.0
                    b.velocity = V(0.0, 0.0)
                    return b
                }
            }
            if wallX <= t + 1e-7 { b.velocity = V(0.0, b.velocity.y) }
            if wallY <= t + 1e-7 { b.velocity = V(b.velocity.x, 0.0) }
            if contain {
                b.position = V(Kotlin.clamp(b.position.x, 0.25, c.width - 0.25), Kotlin.clamp(b.position.y, 0.25, c.depth - 0.25))
            }
            if left <= 1e-8 { return b }
        }
        return b
    }

    static func actor(_ n: Node, _ c: GameConfig, _ at: Double, _ active: Bool) -> Node {
        return actor(n, c, at, active, falling: active)
    }

    static func actor(_ n: Node, _ c: GameConfig, _ at: Double, _ active: Bool, falling: Bool) -> Node {
        let dt = active ? Kotlin.clamp(at - n.num("motionAt", at), 0.0, 30.0) : 0.0
        let start = AmuduCodec.vector(n["position"])
        let member = AmuduCodec.readMember(AmuduCodec.node(n["member"]))
        let speed = c.moveSpeed * c.scene.run * (member.bot ? AmuduCharacters.get(member.character).qualities.runFactor : 1.0)
        let velocity = n.flag("actuallyMoving") ? AmuduCodec.vector(n["move"]) * speed : V(0.0, 0.0)
        var movement = velocity * dt
        var arrived = false
        if let target = present(n["motionTarget"]) {
            let remaining = (AmuduCodec.vector(target) - start).length()
            if movement.length() >= remaining {
                movement = movement.unit() * remaining
                arrived = true
            }
        }
        let p = start + movement
        let position = V(Kotlin.clamp(p.x, 0.6, c.width - 0.6), Kotlin.clamp(p.y, 0.6, c.depth - 0.6))
        let moved = (position - start).length()
        let moving = active && !arrived && n.flag("actuallyMoving") && movement.length() <= moved + 0.01
        let elapsed = speed > 0 ? min(dt, moved / speed) : 0.0
        let fallTime = falling ? Kotlin.clamp(at - n.num("motionAt", at), 0.0, 30.0) : 0.0
        let jump = n.num("jumpHeight")
        let vz = n.num("jumpVelocity")
        let h = (jump > 0 || vz > 0) ? max(0.0, jump + vz * fallTime - 0.5 * c.scene.gravity * fallTime * fallTime) : 0.0
        var out = n
        out["position"] = AmuduCodec.v(position)
        out["gait"] = n.num("gait") + elapsed * 9
        out["jumpHeight"] = h
        out["jumpVelocity"] = h > 0 ? vz - c.scene.gravity * fallTime : 0.0
        out["actuallyMoving"] = moving
        return out
    }

    /// Kotlin `materialize(n, at = n.num("time"))`: a motion snapshot evaluated at `at`; others are returned unchanged.
    static func materialize(_ n: Node) -> Node {
        return materialize(n, n.num("time"))
    }

    static func materialize(_ n: Node, _ at: Double) -> Node {
        if Kotlin.toInt(n.num("motionProtocol")) != VERSION { return n }
        guard let c = try? AmuduCodec.readConfig(AmuduCodec.node(n["config"])) else { return n }
        let phase = n.str("phase")
        let paused = n.flag("sharedPause")
        let moving = (!paused && ["CIRCLE", "AIR", "RETRIEVE", "SHOUT", "AIM", "FLIGHT"].contains(phase)) ||
            (!paused && phase == "RESOLVE" && n.str("infoCode") == "air_catch")
        let holder = AmuduCodec.node(n["ball"]).str("holder")
        let heldForCall = phase == "CIRCLE" || phase == "RESOLVE" || phase == "SHOUT"
        var actors: [String: Any] = [:]
        for (id, value) in AmuduCodec.node(n["actors"]) {
            actors[id] = actor(AmuduCodec.node(value), c, at, moving && !(heldForCall && id == holder),
                               falling: !paused && (moving || phase == "RESOLVE"))
        }
        let factor = (c.challengeStep < 0 && ["AIR", "RETRIEVE"].contains(phase)) ? c.callWindFactor : 1.0
        var b = ball(AmuduCodec.node(n["ball"]), c, wind(c, Kotlin.toLong(n.num("seed"))) * factor, at,
                     !paused && ["AIR", "RETRIEVE", "FLIGHT", "RESOLVE"].contains(phase),
                     contain: ["AIR", "RETRIEVE"].contains(phase))
        if let h = b.holder, let a = actors[h] as? Node {
            b.position = AmuduCodec.vector(a["position"])
        }
        var out = n
        out["time"] = at
        out["actors"] = actors
        out["ball"] = ballNode(b)
        return out
    }

    static func wind(_ c: GameConfig, _ seed: Int64) -> V {
        return V(Kotlin.floorMod(seed, 2) == 0 ? 1.0 : -1.0, 0.18).unit() * c.wind.acceleration
    }

    static func ballNode(_ b: Ball) -> Node {
        return ["position": AmuduCodec.v(b.position), "height": b.height, "velocity": AmuduCodec.v(b.velocity), "vz": b.vz,
                "holder": b.holder ?? "", "bounces": b.bounces, "flightId": b.flightId, "launchAt": b.launchAt, "burst": b.burst,
                "burstOnGround": b.burstOnGround, "burstOnCatch": b.burstOnCatch]
    }
}

/// Android `MotionPublication`: reuses a path until its direction, physics or outcome changes. All private recovery
/// data remains atomic.
final class MotionPublication {
    private var previous: Node = [:]

    func reset() { previous = [:] }

    func encode(_ e: AmuduEngine, _ raw: Node, _ enabled: Bool) -> Node {
        if !enabled {
            reset()
            return raw
        }
        let restart = previous.str("id") != e.id || previous.str("phase") != e.phase.rawValue ||
            Kotlin.toInt(previous.num("turn")) != e.turn || previous.flag("sharedPause") != e.sharedPause
        let oldActors = AmuduCodec.node(previous["actors"])
        var actors: [String: Any] = [:]
        for (id, value) in AmuduCodec.node(raw["actors"]) {
            let n = AmuduCodec.node(value)
            guard let a = e.actor(id) else {
                actors[id] = n
                continue
            }
            let old = AmuduCodec.node(oldActors[id])
            let returning = e.phase == .circle || (e.phase == .resolve && e.infoCode == "air_catch") ||
                (e.phase == .air && a.anticipationFlight == e.ball.flightId)
            let target: V?
            if !a.member.bot {
                target = nil
            } else if e.phase == .air && e.called == id {
                target = e.landing
            } else if returning, let spot = a.circleSpot {
                target = spot - (spot - a.position).unit() * 0.10
            } else {
                target = nil
            }
            let predicted = MotionState.actor(old, e.config, e.time, true)
            let oldTarget = MotionState.present(old["motionTarget"])
            let sameTarget: Bool
            if let target {
                sameTarget = oldTarget != nil && (AmuduCodec.vector(oldTarget) - target).length() < 0.02
            } else {
                sameTarget = oldTarget == nil
            }
            let reusable = !restart && sameTarget && !old.isEmpty && n.flag("actuallyMoving") == old.flag("actuallyMoving") &&
                (AmuduCodec.vector(predicted["position"]) - a.position).length() < 0.025 &&
                (AmuduCodec.vector(old["move"]) - a.move).length() < 0.035 &&
                abs(predicted.num("jumpHeight") - a.jumpHeight) < 0.015 && abs(predicted.num("jumpVelocity") - a.jumpVelocity) < 0.03
            var out = n
            if reusable {
                for key in ["position", "move", "gait", "jumpHeight", "jumpVelocity", "motionAt", "motionTarget"] {
                    out[key] = old[key] ?? NSNull()
                }
            } else {
                out["motionAt"] = e.time
                out["motionTarget"] = target.map { AmuduCodec.v($0) as Any } ?? NSNull()
            }
            actors[id] = out
        }
        let oldBall = AmuduCodec.node(previous["ball"])
        let actual = e.ball
        let predicted = MotionState.ball(oldBall, e.config, e.windVector, e.time, true, contain: e.phase == .air || e.phase == .retrieve)
        let same = !restart && !oldBall.isEmpty && actual.flightId == predicted.flightId && actual.holder == predicted.holder &&
            actual.bounces == predicted.bounces && actual.burst == predicted.burst && actual.burstOnGround == predicted.burstOnGround &&
            actual.burstOnCatch == predicted.burstOnCatch &&
            (actual.holder != nil || ((actual.position - predicted.position).length() < 0.015 && abs(actual.height - predicted.height) < 0.015 &&
                                      (actual.velocity - predicted.velocity).length() < 0.02 && abs(actual.vz - predicted.vz) < 0.02))
        var ball: Node
        if same {
            ball = oldBall
        } else {
            ball = AmuduCodec.node(raw["ball"])
            ball["motionAt"] = e.time
        }
        var out = raw
        out["motionProtocol"] = MotionState.VERSION
        out["actors"] = actors
        out["ball"] = ball
        previous = out
        return out
    }
}
