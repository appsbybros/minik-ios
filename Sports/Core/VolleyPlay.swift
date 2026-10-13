import Foundation

/// Port of Android core/VolleyPlay.kt: authority-only volleyball actions. Inputs carry intent;
/// contacts and points remain physical events.
final class VolleyPlay {
    /// Unowned: the engine owns this object (`lazy var volley`), and Kotlin's strong back-reference would be a
    /// retain cycle that leaks every match here. Use a VolleyPlay only while its engine is held elsewhere: on a
    /// temporary (`SportsEngine(...).volley.serveMode`) Swift releases the engine before `serveMode` runs, which traps.
    private unowned let e: SportsEngine
    var serveQueued = false
    var serveWindup = 0.0
    var servePrepared = false
    var toss = false
    var tossTime = 0.0
    var readyTime = 0.0
    var misses = 0
    var tossHeight = 1.1
    var tossVelocity = 0.0

    init(_ e: SportsEngine) {
        self.e = e
    }

    private var b: SportsBall { return e.ball }
    private var mode: Control { return e.effectiveControl }

    var serveMode: Control {
        if e.config.tutorial {
            if e.tutorialStage < 3 { return .beginner }
            return e.tutorialStage < 7 ? .standard : .pro
        }
        return e.config.serveControl
    }

    func reset() {
        serveQueued = false
        serveWindup = 0.0
        servePrepared = false
        toss = false
        tossTime = 0.0
        readyTime = 0.0
        misses = 0
        for it in e.players {
            it.volleyKind = "auto"
            it.volleyAttemptAt = -10.0
            it.volleyAttemptShot = -1
            it.volleyTriedShot = -1
            it.volleyExplicit = false
        }
        let s = e.players[e.server]
        s.p = Vec(s.p.x, s.member.team == 0 ? 8.55 : -8.55)
        s.goal = s.p
    }

    func command(_ p: Athlete, _ kind: String, _ x: Double, _ y: Double, _ power: Double) -> Bool {
        if !["hit", "volley_tap", "volley_spike", "volley_swipe", "volley_up", "volley_down", "volley_block", "volley_auto"].contains(kind) { return false }
        if e.countdown > 0 || e.phase == .point { return false }
        if e.phase == .ready {
            if e.players[e.server] !== p || serveQueued { return false }
            if serveMode == .pro && !p.member.bot {
                if !toss {
                    if ["volley_tap", "hit", "volley_auto"].contains(kind) {
                        startToss(p)
                        return true
                    }
                    return false
                }
                if !["volley_swipe", "volley_up", "volley_down"].contains(kind) { return false }
            }
            p.aim = Vec(x, y)
            p.pendingPower = min(max(power, 0.0), 1.0)
            p.volleyKind = kind
            p.volleyExplicit = kind != "volley_auto"
            attempt(p, kind)
            if serveMode == .beginner || p.member.bot || (toss && tossHeight >= 1.45 && tossHeight <= 3.15) {
                e.serve()
            } else if serveMode == .standard {
                missToss(p)
            }
            return true
        }
        if kind == "volley_block" || (kind == "volley_tap" && abs(p.p.y) < 1.15 && abs(y) < 0.65) {
            block(p)
            return true
        }
        if mode == .pro && ["hit", "volley_tap", "volley_auto"].contains(kind) { return false }
        if e.clock - p.volleyAttemptAt < 0.22 { return false }
        p.aim = Vec(x, y)
        p.pendingPower = min(max(power, 0.0), 1.0)
        p.volleyKind = kind
        p.volleyExplicit = kind != "volley_auto"
        attempt(p, kind)
        p.swing = mode == .beginner ? 0.48 : (mode == .standard ? 0.32 : 0.22)
        if kind == "volley_spike" && b.z > 1.7 && p.jump < 0.01 { p.jumpV = 5.5 }
        tryContact(p)
        return true
    }

    private func attempt(_ p: Athlete, _ kind: String) {
        p.volleyAttemptAt = e.clock
        p.volleyAttemptShot = b.shot
        p.pose = kind == "volley_spike" ? "spike" : (kind == "volley_up" ? "set" : "receive")
        p.poseTime = 0.34
        e.event("swing", p.member.id)
    }

    private func startToss(_ p: Athlete) {
        toss = true
        tossTime = 0.0
        tossHeight = 1.2
        tossVelocity = 5.0
        p.pose = "set"
        p.poseTime = 0.6
        e.event("toss", p.member.id)
    }

    private func missToss(_ p: Athlete) {
        toss = false
        misses += 1
        p.swing = 0.0
        if misses >= 2 {
            e.phase = .rally
            e.point(1 - p.member.team, "serve_fault")
        } else {
            readyTime = 0.0
            e.event("serve_retry", p.member.id)
        }
    }

    func prepareServe() {
        if serveQueued { return }
        let p = e.players[e.server]
        serveQueued = true
        serveWindup = 0.0
        servePrepared = false
        p.p = Vec(p.p.x, p.member.team == 0 ? 8.55 : -8.55)
        p.goal = p.p
        p.velocity = Vec()
        p.facing = Vec(0.0, p.member.team == 0 ? -1.0 : 1.0)
        if e.clock - p.volleyAttemptAt > 0.1 { attempt(p, "serve") }
        p.pose = "serve_prepare"
        p.poseTime = 0.24
        p.jumpV = 4.8
        e.event("serve_prepare", p.member.id)
    }

    func ready(_ dt: Double) {
        let p = e.players[e.server]
        b.p = p.p
        if serveQueued {
            serveWindup += dt
            b.z = 2.45 + p.jump
            if serveWindup >= 0.22 {
                servePrepared = true
                e.serve()
                serveQueued = false
                servePrepared = false
                toss = false
            }
            return
        }
        if e.countdown > 0 {
            b.z = 1.1
            return
        }
        readyTime += dt
        if p.member.bot || (serveMode == .beginner && e.practice == nil) {
            b.z = 1.1
            if readyTime > 0.7 && (p.member.bot || !e.config.tutorial) { e.serve() }
            return
        }
        if serveMode == .pro && readyTime >= 10 {
            e.phase = .rally
            e.point(1 - p.member.team, "serve_timeout")
            return
        }
        if serveMode == .standard && !toss && readyTime > 0.65 { startToss(p) }
        if toss {
            tossTime += dt
            tossHeight += tossVelocity * dt - 0.5 * e.config.gravity * dt * dt
            tossVelocity -= e.config.gravity * dt
            b.z = tossHeight
            if tossHeight < 0.35 {
                if serveMode == .standard {
                    missToss(p)
                } else {
                    toss = false
                    b.z = 1.1
                }
            }
        } else {
            b.z = 1.1
        }
    }

    func block(_ p: Athlete) {
        if abs(p.p.y) > 1.3 || e.clock - p.volleyAttemptAt < 0.45 { return }
        attempt(p, "volley_block")
        p.volleyKind = "volley_block"
        p.jumpV = 5.5
        p.pose = "block"
        p.poseTime = 0.8
        p.swing = 0.8
    }

    @discardableResult
    func tryContact(_ p: Athlete) -> Bool {
        if e.phase != .rally || !b.active || e.clock - e.poseStamp < 0.18 { return false }
        if p.volleyKind == "volley_block" { return false }
        if !e.canReturn(p) || p.volleyTriedShot == b.shot { return false }
        let automatic = p.member.bot || (mode == .beginner && e.practice == nil)
        if !automatic && p.swing <= 0 { return false }
        let distance = (b.p - p.p).length()
        let reach = !p.member.bot && mode == .beginner ? 1.45 : 1.15
        let dive = distance > reach && distance < reach + 0.75 && b.z < 1.35
        if (distance > reach && !dive) || b.z < 0.15 || b.z > 2.05 + p.jump { return false }
        let spike = p.volleyKind == "volley_spike"
        if spike && b.z < 1.65 && (mode == .pro || (mode == .standard && b.previousTeam == p.member.team && b.touches >= 2)) {
            p.volleyTriedShot = b.shot
            p.swing = 0.0
            e.event("miss", p.member.id, "low_spike")
            return false
        }
        if !p.member.bot && mode != .beginner && !spike && b.z > 2.05 { return false }
        if automatic && p.volleyAttemptShot != b.shot { attempt(p, b.z > 2.0 ? "volley_spike" : "volley_auto") }
        p.volleyTriedShot = b.shot
        let skill = VolleySkills.of(p.member.character)
        let chance = p.member.bot && e.practice == nil ? skill.contactChance : 1.0
        if e.random.nextDouble() > chance * (dive ? 0.66 : 1.0) {
            if dive {
                p.pose = "dive"
                p.poseTime = 0.65
            }
            e.event("miss", p.member.id)
            return false
        }
        if dive {
            p.p = e.bounded(p.p + (b.p - p.p) * 0.45, p.member.team)
            e.event("dive", p.member.id)
        }
        launch(p, serve: false, power: p.pendingPower)
        if dive {
            p.pose = "dive"
            p.poseTime = 0.55
        }
        p.swing = 0.0
        return true
    }

    func launch(_ p: Athlete, serve: Bool = false, power: Double = 0.5) {
        let skill = VolleySkills.of(p.member.character)
        let team = p.member.team
        let side: Double = team == 0 ? 1 : -1
        if b.previousTeam != team {
            b.previousTeam = team
            b.touches = 0
        }
        b.touches += 1
        if !serve && b.touches > 3 {
            e.point(1 - team, "four_contacts")
            return
        }
        let others = e.players.filter { $0.member.team == team && $0 !== p }
        let rivals = e.players.filter { $0.member.team != team }
        let oldZ = serve ? 2.45 + p.jump : b.z
        b.p = serve ? p.p : b.p
        b.z = oldZ
        let pro = !p.member.bot && (serve ? serveMode : mode) == .pro
        let requestedSpike = p.volleyKind == "volley_spike"
        let lowSet = !serve && requestedSpike && oldZ < 1.65 && b.touches < 3 && mode != .pro
        let smart = serve || b.touches >= 3 || (requestedSpike && !lowSet)
        var target: Vec
        if smart {
            let spaces = [Vec(-2.7, -side * 5.8), Vec(2.7, -side * 5.8), Vec(0.0, -side * 6.6)]
            // Kotlin `maxBy`: the first space farthest from its nearest rival.
            var best = spaces[0]
            var bestGap = -Double.greatestFiniteMagnitude
            for t in spaces {
                let gap = rivals.map { ($0.p - t).length() }.min() ?? Double.greatestFiniteMagnitude
                if gap > bestGap {
                    bestGap = gap
                    best = t
                }
            }
            target = best
        } else {
            let anchor = Vec(-p.p.x * 0.5, side * 2.5)
            var receiver = others[0]
            var nearest = Double.greatestFiniteMagnitude
            for it in others {
                let d = (it.p - anchor).length()
                if d < nearest {
                    nearest = d
                    receiver = it
                }
            }
            target = Vec(min(max(receiver.p.x, -2.9), 2.9), side * 2.1)
        }
        if !pro && !p.member.bot && p.volleyExplicit && !lowSet { target = p.aim }
        let attack = serve || target.y * side < 0 || (b.touches >= 3 && !lowSet)
        let highSet = lowSet || (!attack && p.member.bot && p.contacts % 10 == 7)
        if !attack && b.touches >= 3 {
            e.point(1 - team, "four_contacts")
            return
        }
        if p.member.bot {
            let error = Double(5 - skill.precision) * 0.12
            let dx = e.random.nextDouble(-error - 0.001, error + 0.001)
            let dy = e.random.nextDouble(-error - 0.001, error + 0.001)
            target += Vec(dx, dy)
        }
        if pro {
            var dir = (p.volleyKind == "volley_spike" ? p.aim - b.p : p.aim).unit()
            if dir.length() < 0.1 { dir = Vec(0.0, -side) }
            let speed = 3.8 + power * (10.0 + Double(skill.power) * 0.7)
            b.velocity = dir * speed
            switch p.volleyKind {
            case "volley_up": b.vz = 4.0 + power * 8.5
            case "volley_down": b.vz = -1.0 - power * 5.5
            case "volley_spike": b.vz = -2.0 - power * 4.0
            default: b.vz = 3.0 + power * 3.2
            }
            target = e.predictLanding()
        } else {
            var flight = serve ? 2.35 : (highSet ? 2.1 : (attack ? 1.35 - Double(skill.power - 1) * 0.055 : 1.5))
            // Solve exactly to the tapped landing point; assisted shots clear the net without aim substitution.
            if attack {
                let fraction = abs(b.p.y) / max(abs(b.p.y) + abs(target.y), 0.1)
                let base = b.z * (1 - fraction) + 0.15 * fraction
                let needed = sqrt(max(2 * (e.config.netHeight + 0.28 - base) / max(e.config.gravity * fraction * (1 - fraction), 0.01), 0.0))
                flight = max(flight, needed)
            }
            if p.member.bot && serve && e.random.nextDouble() > skill.serveChance { target = Vec(target.x < 0 ? -4.6 : 4.6, target.y) }
            b.velocity = (target - b.p) * (1 / flight)
            b.vz = (0.15 - b.z + 0.5 * e.config.gravity * flight * flight) / flight
        }
        e.returnTeam = target.y * side < 0 ? 1 - team : team
        let receivers = e.players.filter { $0.member.team == e.returnTeam && $0 !== p }
        var chosen: Athlete? = nil
        var nearest = Double.greatestFiniteMagnitude
        for it in receivers {
            let d = (it.p - target).length()
            if d < nearest {
                nearest = d
                chosen = it
            }
        }
        b.receiver = chosen?.member.id ?? ""
        receivers.first { $0.member.id == b.receiver }?.goal = e.bounded(target, e.returnTeam)
        if p.volleyAttemptShot != b.shot { e.event("swing", p.member.id) }
        b.serve = serve
        e.contact(p)
        if serve {
            p.pose = "serve"
        } else if oldZ - p.jump > 1.65 {
            p.pose = (pro && p.volleyKind == "volley_down") || (requestedSpike && !lowSet) || attack ? "spike" : "set"
        } else {
            p.pose = "receive"
        }
        p.poseTime = 0.60
        let kind: String
        if serve {
            kind = "serve_launch"
        } else if highSet {
            kind = "high_set"
        } else if attack {
            kind = "attack"
        } else if b.touches == 1 {
            kind = "receive"
        } else {
            kind = "set"
        }
        e.event(kind, p.member.id)
        p.volleyExplicit = false
        p.volleyKind = "auto"
        for it in e.players {
            it.plannedMiss = false
            it.think = 0.0
        }
    }

    func physics(_ old: Vec) {
        for p in e.players {
            if p.volleyKind != "volley_block" || p.swing <= 0 || p.member.team == e.teamOf(b.hitter) || b.serve || e.clock - e.poseStamp < 0.18 { continue }
            if abs(p.p.y) < 1.3 && abs(b.p.y) < 1.2 && abs(p.p.x - b.p.x) < 0.9 && b.z >= 1.9 && b.z <= 2.05 + p.jump && p.volleyTriedShot != b.shot {
                p.volleyTriedShot = b.shot
                if (!p.member.bot && e.practice != nil) || e.random.nextDouble() <= VolleySkills.of(p.member.character).blockChance {
                    let side: Double = p.member.team == 0 ? 1 : -1
                    b.velocity = Vec(b.velocity.x * 0.25, -side * max(3.0, abs(b.velocity.y) * 0.55))
                    b.vz = -0.8
                    b.previousTeam = p.member.team
                    b.touches = 1
                    e.returnTeam = 1 - p.member.team
                    b.receiver = ""
                    e.contact(p)
                    p.pose = "block"
                    p.poseTime = 0.5
                    e.event("block", p.member.id)
                    e.practice?.block(e, p.member.id)
                    return
                }
            }
        }
        if old.y * b.p.y <= 0 && abs(b.velocity.y) > 0.1 && b.z < e.config.netHeight {
            e.point(1 - e.teamOf(b.hitter), "net")
            return
        }
        if old.y > 0 && b.p.y <= 0 && b.z >= e.config.netHeight {
            e.practice?.crossed(e)
            if !b.active { return }
        }
        if abs(b.p.x) > 6 || abs(b.p.y) > 10 {
            e.point(1 - e.teamOf(b.hitter), "out")
            return
        }
        if b.z <= 0.14 {
            let inside = abs(b.p.x) <= 4 && abs(b.p.y) <= 8
            let land = b.p.y >= 0 ? 0 : 1
            e.point(inside ? 1 - land : 1 - e.teamOf(b.hitter), inside ? "ground" : "out")
        }
    }

    func think(_ p: Athlete) {
        let skill = VolleySkills.of(p.member.character)
        p.think = 0.08 + Double(5 - skill.hitting) * 0.025
        let team = e.players.filter { $0.member.team == p.member.team }
        let side: Double = p.member.team == 0 ? 1 : -1
        if p.member.team == e.returnTeam {
            let landing = e.predictLanding()
            var receiver = team.first { $0.member.id == b.receiver }
            if receiver == nil {
                var nearest = Double.greatestFiniteMagnitude
                for it in team where it.member.id != b.hitter {
                    let d = (it.p - landing).length()
                    if d < nearest {
                        nearest = d
                        receiver = it
                    }
                }
            }
            if p === receiver {
                p.goal = e.bounded(landing, p.member.team)
                if b.z >= 2.0 && b.z <= 3.25 && (p.p - b.p).length() < 1.3 && p.jump <= 0 {
                    p.jumpV = 4.0 + Double(skill.blocking) * 0.2
                    if b.previousTeam == p.member.team && b.touches >= 2 { p.volleyKind = "volley_spike" }
                }
            } else if !b.serve && b.previousTeam != p.member.team && abs(b.p.y) < 2.5 && b.z > 2.2 && skill.blocking >= 3 {
                p.goal = Vec(min(max(b.p.x, -3.5), 3.5), side * 0.62)
                if abs(p.p.y) < 1.2 && (b.p - p.p).length() < 1.8 && e.random.nextDouble() < skill.blockChance { block(p) }
            } else {
                let support = team.filter { $0 !== receiver }
                let slot = Double(support.firstIndex { $0 === p } ?? -1)
                let x: Double
                if support.count == 1 {
                    x = receiver != nil && receiver!.p.x >= 0 ? -2.3 : 2.3
                } else {
                    x = (slot - Double(support.count - 1) / 2.0) * 4.4
                }
                p.goal = Vec(x, side * 2.4)
            }
        } else {
            let slot = Double(team.firstIndex { $0 === p } ?? -1)
            p.goal = Vec((slot - Double(team.count - 1) / 2.0) * 2.7, side * 4.2)
        }
    }
}
