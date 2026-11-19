import Foundation

/// Android `core/AmuduEngine.kt`: authoritative continuous physics; commands never award their own points.
/// Ported statement by statement (same order of random draws and floating-point operations).
final class AmuduEngine {
    let members: [Member]
    let config: GameConfig
    let seed: Int64
    let id: String
    /// Kotlin `practice`: the skill-journey drill or lesson when `config.challengeStep >= 0`, else nil.
    let practice: SpudPractice?
    var actors: [GameActor]
    private var movementStart: [V]
    var phase: Phase = .circle
    var phaseAt = 0.0
    var time = 0.0
    var turn = 1
    var thrower: String
    var selected = ""
    var called = ""
    var nextThrower: String
    var ball: Ball
    var landing: V
    var result: Outcome?
    var paused = false
    var onlineHuddles = false
    var frozen = false
    var regroupPending = false
    var circleFormation = true
    var pickupAnchor: V?
    var huddleTarget = ""
    var huddleSerial = 0
    var huddleDeadline = 0.0
    var sharedPause = false
    /// Kotlin `recallAt`: when a house player who caught a name call makes the next call (0 when not scheduled).
    var recallAt = 0.0
    var circleAngle = -Double.pi / 2
    var paintColor = PaintBalloon.colors[0]
    var paintPoint = 0
    let callBursts: BalloonBurstCycle
    let attackBursts: BalloonBurstCycle
    var paintSplashes: [PaintSplash] = []
    var botCallStreak = 0
    var connectedHumanIds: Set<String>
    var stepRemaining = 0.0
    var retrievalGrace = 0.0
    var retrievalDistance = Double.greatestFiniteMagnitude
    var actionDeadline = 0.0
    var actionActor = ""
    var actionStage = ""
    var timerHumans = 0
    var breakSerial = 0
    var statusSerial = 0
    var lastStatusAt = 0.0
    var returnTarget = ""
    var returnSerial = 0
    var returnDeadline = 0.0
    /// Kotlin `linkedMapOf<String, Boolean>()`: only counts are read, so key order is not needed.
    var returnVotes: [String: Bool] = [:]
    var infoEn = ""
    var infoHe = ""
    var infoUntil = 0.0
    var infoActor = ""
    var infoCode = ""
    var pendingHuddles: [String] = []
    var events: [GameEvent] = []
    var suggestions = OrderedStringMap()
    var votes = OrderedStringMap()
    private var random: KotlinRandom
    var serial = 0
    var consumed = OrderedStringSet()
    var onEvent: ((GameEvent) -> Void)?
    /// Kotlin `baseWind`: the match wind; name calls in a match feel `callWindFactor` of it.
    let baseWind: V

    /// Kotlin `windVector`: reduced during a match's name call (AIR and RETRIEVE), full otherwise and in practice.
    var windVector: V {
        let reduced = practice == nil && (phase == .air || phase == .retrieve)
        return baseWind * (reduced ? config.callWindFactor : 1.0)
    }

    /// Kotlin `activeActors`: the actors still playing, in roster order.
    var activeActors: [GameActor] { return actors.filter { $0.active } }

    /// Kotlin `activeHumans`.
    var activeHumans: Int { return actors.filter { $0.active && !$0.member.bot }.count }

    /// Kotlin defaults: `config = GameConfig(participants = members.size)`, `seed = 1`, `id = "local-" + seed`.
    init(members: [Member], config: GameConfig? = nil, seed: Int64 = 1, id: String? = nil) throws {
        guard let first = members.first else { throw AmuduError.invalidRoster }
        let cfg = try config ?? GameConfig(participants: members.count)
        self.members = members
        self.config = cfg
        self.seed = seed
        self.id = id ?? ("local-" + String(seed))
        practice = cfg.challengeStep >= 0 ? SpudPractice(cfg.challengeStep, seed, cfg.practiceLesson) : nil
        actors = members.map { GameActor(member: $0, position: V.zero) }
        movementStart = [V](repeating: V.zero, count: members.count)
        thrower = first.id
        nextThrower = first.id
        ball = Ball(V(cfg.width / 2, cfg.depth / 2), 1.0, V.zero, 0.0, first.id)
        landing = V(cfg.width / 2, cfg.depth / 2)
        callBursts = BalloonBurstCycle(seed ^ 0x4612)
        attackBursts = BalloonBurstCycle(seed ^ 0x7991)
        connectedHumanIds = Set(members.filter { !$0.bot }.map { $0.id })
        random = KotlinRandom(seed: seed)
        let sign: Double = Kotlin.floorMod(seed, Int64(2)) == 0 ? 1.0 : -1.0
        baseWind = V(sign, 0.18).unit() * cfg.wind.acceleration
        guard members.count == cfg.participants, Set(members.map { $0.id }).count == members.count else { throw AmuduError.invalidRoster }
        guard members.allSatisfy({ Words.validName($0.name) }) else { throw AmuduError.invalidRoster }
        let humans = Set(members.filter { !$0.bot }.map { $0.character })
        let bots = members.filter { $0.bot }.map { $0.character }
        // House players must have unique avatars, distinct from humans.
        guard Set(bots).count == bots.count, !bots.contains(where: { humans.contains($0) }) else { throw AmuduError.invalidRoster }
        circle(thrower)
        practice?.prepare(self)
    }

    func actor(_ id: String) -> GameActor? {
        return actors.first { $0.member.id == id }
    }

    func emit(_ kind: String, _ actorId: String, _ text: String = "") {
        if kind == "catch" && practice == nil { actor(actorId)?.rankEarned += 5 }
        serial += 1
        let e = GameEvent(id: serial, kind: kind, actor: actorId, text: text, at: time)
        events.append(e)
        if events.count > 48 { events.removeFirst() }
        onEvent?(e)
    }

    private func transition(_ p: Phase) {
        phase = p
        phaseAt = time
    }

    private func message(_ en: String, _ he: String, _ who: String = "", _ code: String = "") {
        infoEn = en
        infoHe = he
        infoActor = who
        infoCode = code
        infoUntil = time + 3.0
    }

    func ballWithinReach(_ uid: String) -> Bool {
        guard let a = actor(uid) else { return false }
        if !a.active || ball.holder != nil || time < a.duckUntil { return false }
        let pickup = phase == .retrieve && uid == called && ball.height <= 1.4
        let nameCall = (phase == .air || phase == .retrieve) && uid == called &&
            ball.height >= a.jumpHeight + 1.05 && ball.height <= a.jumpHeight + 2.0
        let attack = phase == .flight && uid != thrower && ball.height >= a.jumpHeight + 0.35 && ball.height <= a.jumpHeight + 2.05
        let catching = nameCall || attack
        return (pickup || catching) && (ball.position - a.position).length() < config.ball.catchRadius + (pickup ? 0.60 : 0.10)
    }

    func isFrozen() -> Bool { return frozen || phase == .aim }

    func canAim(_ uid: String) -> Bool {
        return actor(uid)?.active == true && uid == thrower && ball.holder == uid && (phase == .shout || phase == .aim)
    }

    private func locked(_ a: GameActor) -> Bool {
        let anchored = (pickupAnchor != nil || phase == .aim) && a.member.id == thrower
        let throwingPhase = phase == .shout || phase == .aim || phase == .flight
        return !a.active || ball.holder == a.member.id || (anchored && throwingPhase) || time < a.catchUntil
    }

    private func freeCatchReturn() -> Bool {
        return phase == .resolve && infoCode == "air_catch" && !regroupPending
    }

    private func movingPhase() -> Bool {
        switch phase {
        case .circle, .air, .retrieve, .shout, .aim, .flight:
            return true
        case .resolve, .huddle, .returnVote, .waiting, .finished:
            return freeCatchReturn()
        }
    }

    private func canRun(_ a: GameActor) -> Bool {
        if !a.active || !movingPhase() || time < a.catchUntil { return false }
        // After the call the thrower may spend the step allowance, and nothing more.
        if a.member.id == thrower && phase == .aim && ball.holder == thrower { return stepRemaining > 0.00001 }
        return !locked(a) && !isFrozen()
    }

    /// Kotlin `moveActor(a, delta, contact)`: with `contact`, swept body contact (`ActorMovement.advance`) against the
    /// other active players; the thrower's movement after the call spends `stepRemaining`.
    private func moveActor(_ a: GameActor, _ delta: V, contact: Bool = false) {
        let end: V
        if contact {
            let blockers = actors.filter { $0 !== a && $0.active }.map { $0.position }
            end = ActorMovement.advance(a.position, delta, blockers, config)
        } else {
            end = bounded(a.position + delta)
        }
        let desired = end - a.position
        if a.member.id == thrower && phase == .aim {
            let length = desired.length()
            let amount = min(length, stepRemaining)
            if length > 0.000001 { a.position = a.position + desired * (amount / length) }
            stepRemaining = max(stepRemaining - amount, 0.0)
        } else {
            a.position = a.position + desired
        }
    }

    @discardableResult
    func command(_ uid: String, _ eventId: String, _ cmd: GameCommand) -> Bool {
        if result != nil || paused || Kotlin.isBlank(eventId) || eventId.utf16.count > 120 { return false }
        if !consumed.insert(eventId) { return false }
        if consumed.count > 8192 { consumed.removeFirst() }
        guard let a = actor(uid) else { return false }
        if case .pause(let value) = cmd {
            if !a.active || a.member.bot || activeHumans > 1 || phase == .huddle || phase == .returnVote { return false }
            sharedPause = value
            for other in actors { other.move = V.zero }
            return true
        }
        if sharedPause { return false }
        if let practice { return practice.command(self, a, cmd) }
        if cmd == .requestReturn { return requestReturn(a) }
        if case .returnVote(let voteSerial, let yes) = cmd { return castReturnVote(a, voteSerial, yes) }
        if !a.active { return false }
        if (phase == .huddle || phase == .returnVote || phase == .waiting) && cmd != .end { return false }
        switch cmd {
        case .move(let v):
            if !v.finite() { return false }
            if !a.member.bot && v.length() > 0.08 {
                a.catchUntil = 0.0
                a.catchRecoveryUntil = 0.0
            }
            if !canRun(a) {
                a.move = V.zero
                return false
            }
            a.move = v.length() > 1 ? v.unit() : v
        case .aim(let v):
            if !canAim(uid) || !v.finite() || v.length() < 0.01 { return false }
            a.direction = v.unit()
            a.facing = a.direction
        case .select(let target, let typedName):
            if phase != .circle || uid != thrower || target == uid { return false }
            guard let t = actor(target), t.active else { return false }
            if config.rules == .nicknames && config.nicknameAnswer != .automatic && !t.suffixes.isEmpty {
                let typed = Words.normalize(typedName)
                let names = [t.fullName(), t.fullName(hebrew: false), t.fullName(hebrew: true)]
                if !names.contains(where: { typed == Words.normalize($0) }) {
                    penalty(a, "Incorrect nickname.", "כינוי שגוי.")
                    resolve(uid, "Incorrect nickname: one penalty.", "כינוי שגוי: נקודת חובה אחת.", who: uid, code: "wrong_nickname")
                    return false
                }
            }
            selected = t.member.id
            a.facing = (t.position - a.position).unit()
            emit("selected", uid)
        case .toss(let rawPower, let rawDrift):
            if phase != .circle || uid != thrower || Kotlin.isBlank(selected) || !rawPower.isFinite || !rawDrift.isFinite { return false }
            toss(a, uid, Kotlin.clamp(rawPower, 0.0, 1.0), rawDrift)
        case .jump:
            if phase == .retrieve && ball.height < 0.35 && abs(ball.vz) < 0.7 { return false }
            let jumpPhase = phase == .air || phase == .retrieve || phase == .shout || phase == .aim || phase == .flight
            if !jumpPhase || a.jumpHeight > 0 || time < a.duckUntil { return false }
            a.jumpVelocity = CatchPhysics.jumpVelocity(a)
            a.catchUntil = 0.0
        case .catchBall:
            if time < a.duckUntil || time < a.catchUntil || time < a.catchRecoveryUntil { return false }
            if phase == .retrieve && uid == called && ball.height <= 1.4 && (ball.position - a.position).length() < config.ball.catchRadius + 0.60 {
                ball.holder = uid
                ball.velocity = V.zero
                ball.vz = 0.0
                ball.height = 1.2
                a.catchAt = time
                a.move = V.zero
                a.actuallyMoving = false
                thrower = uid
                pickupAnchor = a.position
                transition(.shout)
                a.nextThink = time + 0.7
                emit("pickup", uid)
                return true
            }
            let nameCall = (phase == .air || phase == .retrieve) && uid == called
            let defender = (phase == .retrieve && uid != called || (phase == .shout || phase == .aim || phase == .flight) && uid != thrower) &&
                ball.holder != uid
            if nameCall || defender {
                let wasRunning = a.actuallyMoving || a.move.length() > 0.08
                a.catchProbability = CatchPhysics.probability(a, ball, actor(thrower), phase == .flight)
                a.catchReadyAt = time
                a.catchReach = wasRunning && !a.member.bot ? 0.82 : 1.0
                if phase == .flight {
                    if let approach = AttackPhysics.approach(ball, a, config, windVector) {
                        a.catchHeight = approach.height - a.jumpHeight
                    } else {
                        a.catchHeight = ball.height - a.jumpHeight
                    }
                } else {
                    a.catchHeight = 1.3
                }
                a.catchRoll = random.nextDouble()
                a.catchUntil = time + CatchPhysics.window(a, config)
                a.catchRecoveryUntil = a.member.bot ? a.catchUntil + 0.12 : time
                a.move = V.zero
                a.actuallyMoving = false
                a.facing = (ball.position - a.position).unit()
                emit("catch_attempt", uid)
                return true
            }
            return false
        case .duck:
            if phase == .retrieve && ball.height < 0.35 && abs(ball.vz) < 0.7 { return false }
            let duckPhase = phase == .air || phase == .retrieve || phase == .shout || phase == .aim || phase == .flight
            if !duckPhase { return false }
            a.duckUntil = time + config.duckSeconds
            a.catchUntil = 0.0
            emit("duck", uid)
        case .shout:
            if phase != .shout || uid != called || ball.holder != uid { return false }
            thrower = uid
            frozen = true
            stepRemaining = Double(config.stepsAfterCall) * min(config.width, config.depth) * config.stepLengthFraction
            for other in actors {
                other.move = V.zero
                other.actuallyMoving = false
                other.nextThink = time + reaction(other)
                other.facing = (a.position - other.position).unit()
            }
            transition(.aim)
            emit("freeze", uid)
            message("SPUD! Catch or duck — keep your feet still.", "עמודו! תפסו או התכופפו — בלי להזיז רגליים.")
        case .pointThrow(let point, let height):
            if !canAim(uid) || a.member.bot || config.throwMode == .standard || (config.requireCall && phase != .aim) ||
                !TargetThrow.valid(point, height, config) { return false }
            a.idleStrikes = 0
            stepRemaining = 0.0
            if phase == .aim { frozen = true }
            serial += 1
            ball = TargetThrow.launch(a, point, height, config, windVector, id + "-hit-" + String(turn) + "-" + String(serial), time)
            armAttackBurst(ball.velocity.length() / throwProfile(a, 1.0).speed)
            a.direction = ball.velocity.unit()
            a.facing = a.direction
            a.throwAt = time
            a.move = V.zero
            for other in actors {
                other.catchDecided = false
                other.nextThink = time + reaction(other)
            }
            refreshPreparedCatches()
            transition(.flight)
            emit("throw", uid)
        case .throwBall(let rawPower, let botVz):
            if !canAim(uid) || !rawPower.isFinite || (config.requireCall && phase != .aim) { return false }
            a.idleStrikes = 0
            stepRemaining = 0.0
            if let vz = botVz, !a.member.bot || !vz.isFinite { return false }
            let p = Kotlin.clamp(rawPower, 0.0, 1.0)
            let base = throwProfile(a, p)
            let lift = (config.scene.gravity / 9.8).squareRoot()
            let launchVz: Double
            if let vz = botVz {
                launchVz = Kotlin.clamp(vz, -0.35 * lift, 4.95 * (config.scene.gravity / 9.8).squareRoot())
            } else {
                launchVz = base.vz
            }
            if phase == .aim { frozen = true }
            serial += 1
            let flight = id + "-hit-" + String(turn) + "-" + String(serial)
            ball = Ball(a.position + a.direction * 0.52, 1.17, a.direction * base.speed, launchVz, nil, bounces: 0, flightId: flight,
                        launchAt: time)
            armAttackBurst(p)
            a.throwAt = time
            a.facing = a.direction
            a.move = V.zero
            for other in actors {
                other.catchDecided = false
                other.nextThink = time + reaction(other)
            }
            refreshPreparedCatches()
            transition(.flight)
            emit("throw", uid)
        case .end:
            if uid != members[0].id { return false }
            finish()
        case .pause, .requestReturn, .returnVote:
            return false
        case .say(let index):
            if index < 0 || index >= Words.phrasesEn.count { return false }
            if let last = events.last(where: { $0.actor == uid && $0.kind == "say" }), time - last.at < 4 { return false }
            emit("say", uid, String(index))
        }
        return true
    }

    /// The `Command.Toss` branch of Kotlin `command` (power already clamped).
    private func toss(_ a: GameActor, _ uid: String, _ power: Double, _ rawDrift: Double) {
        let launchVz = CallLob.velocity(config.scene, actor(selected)?.member.bot == false, power)
        let spread = CallLob.spreadFactor(config.scene, launchVz)
        let callWind = baseWind * config.callWindFactor
        let g = config.scene.gravity
        let duration = (launchVz + (launchVz * launchVz + 2 * g * (config.wind == .fast ? 1.2 : 1.2 - 0.23)).squareRoot()) / g
        a.idleStrikes = 0
        called = selected
        if infoCode == "air_catch" { infoUntil = time }
        assignCircleSpots(called)
        botCallStreak = a.member.bot && actor(called)?.member.bot == true ? botCallStreak + 1 : 0
        let goal = V(config.width / 2, config.depth / 2)
        let drift = Kotlin.clamp(rawDrift, -1.0, 1.0)
        // One fixed landing choice per call; no mid-flight homing or repeated random rolls.
        let nominal: V
        if config.wind == .fast {
            // Preserve the established strong-wind launch and wind-driven flight.
            let sideways = drift * (a.member.bot ? (1 + power * 2) * spread : (CircleFormation.RADIUS - 0.35) * spread)
            nominal = bounded(goal + V(sideways, (random.nextDouble() - 0.5) * 0.7 * spread))
        } else {
            let range = ((CircleFormation.RADIUS - 0.35) * spread) * (config.wind == .none ? 0.30 : 1.0)
            let angle = random.nextDouble(0.0, 2 * Double.pi)
            let radius = random.nextDouble().squareRoot() * range
            let randomOffset = V(cos(angle), sin(angle)) * radius
            let offset = a.member.bot ? randomOffset + V(drift * range * 0.29, 0.0)
                : CallLob.aimedOffset(randomOffset, rawDrift, (CircleFormation.RADIUS - 0.35) * spread)
            let aimed = !a.member.bot && abs(rawDrift) >= 0.08
            let limit = aimed ? (CircleFormation.RADIUS - 0.35) * spread : range
            let destination = bounded(goal + (offset.length() > limit ? offset.unit() * limit : offset))
            // Aim against light wind so its landing spread stays inside the marked circle.
            if aimed {
                let windy = destination - goal + callWind * (0.5 * duration * duration)
                nominal = goal + (windy.length() > limit ? windy.unit() * limit : windy) - callWind * (0.5 * duration * duration)
            } else {
                nominal = destination - callWind * (0.5 * duration * duration)
            }
        }
        let start = a.position
        landing = bounded(nominal + callWind * (0.5 * duration * duration))
        serial += 1
        let flight = id + "-t" + String(turn) + "-" + String(serial)
        ball = Ball(start, 1.2, (nominal - start) * (1 / duration), launchVz, nil, bounces: 0, flightId: flight, launchAt: time)
        ball.burstOnGround = config.ball == .paint && callBursts.released(CallLob.high(config.scene, launchVz))
        a.throwAt = time
        a.facing = (nominal - start).unit()
        for other in actors {
            other.catchDecided = false
            other.catchUntil = 0.0
            other.nextThink = time + reaction(other)
        }
        frozen = false
        circleFormation = false
        pickupAnchor = nil
        transition(.air)
        emit("call", uid, actor(called)?.fullName() ?? "")
        emit("throw", uid)
    }

    /// Catch may begin before release. Keep its original deadline and random roll, but use the actual released
    /// projectile, not the previous held/rolling ball.
    private func refreshPreparedCatches() {
        for a in actors where a.active && a.member.id != thrower && time < a.catchUntil {
            a.catchProbability = CatchPhysics.probability(a, ball, actor(thrower), true)
            if let approach = AttackPhysics.approach(ball, a, config, windVector) {
                a.catchHeight = approach.height - a.jumpHeight
            } else {
                a.catchHeight = ball.height - a.jumpHeight
            }
        }
    }

    func throwProfile(_ a: GameActor, _ power: Double) -> (speed: Double, vz: Double) {
        let p = Kotlin.clamp(power, 0.0, 1.0)
        let strength = a.member.bot ? AmuduCharacters.get(a.member.character).qualities.powerFactor : 1.0
        let speed = config.ball.speed * (0.55 + p * 1.1) * strength
        let vz = (-0.35 + 5.3 * p * p) * (config.scene.gravity / 9.8).squareRoot()
        return (speed, vz)
    }

    private func reaction(_ a: GameActor) -> Double {
        if a.member.bot {
            let catching = AmuduCharacters.get(a.member.character).qualities.catching
            return 0.10 + Double(5 - catching) * 0.065 + random.nextDouble() * 0.08
        }
        return 0.1
    }

    private func bounded(_ v: V) -> V {
        return V(Kotlin.clamp(v.x, 0.6, config.width - 0.6), Kotlin.clamp(v.y, 0.6, config.depth - 0.6))
    }

    func circle(_ uid: String, regroup: Bool = true) {
        var candidate = actor(uid)
        if let chosen = candidate, !chosen.active { candidate = nil }
        let eligibleActor = candidate ?? activeActors.first
        guard let eligible = eligibleActor, activeActors.count >= 2 else {
            transition(.waiting)
            ball.holder = nil
            return
        }
        let current = eligible.member.id
        let immediateRecall = !regroup && recallAt > 0 && eligible.member.bot
        for a in actors where !a.active { EliminationExit.start(a, config, time) }
        recallAt = 0.0
        if regroup {
            paintPoint += 1
            paintColor = PaintBalloon.next(seed, paintPoint, paintColor)
        }
        thrower = current
        selected = ""
        called = ""
        transition(.circle)
        frozen = false
        pickupAnchor = nil
        stepRemaining = 0.0
        actionStage = ""
        actionDeadline = 0.0
        circleFormation = regroup
        regroupPending = false
        let center = V(config.width / 2, config.depth / 2)
        if regroup {
            let others = activeActors.filter { $0.member.id != current }
            if time == 0.0 {
                circleAngle = random.nextDouble(0.0, 2 * Double.pi)
                let spots = random.shuffled(CircleFormation.spots(center, others.count, circleAngle))
                for (i, a) in others.enumerated() { a.circleSpot = spots[i] }
            } else {
                assignCircleSpots(current)
            }
            eligible.position = center
            eligible.circleSpot = nil
            for a in others { a.position = a.circleSpot ?? a.position }
        }
        for a in activeActors {
            if regroup || a.member.id == current {
                a.move = V.zero
                a.actuallyMoving = false
            }
            a.duckUntil = 0.0
            a.catchUntil = 0.0
            a.catchRecoveryUntil = 0.0
            a.nextThink = immediateRecall && a.member.id == current ? time : time + random.nextDouble(1.15, 1.75)
            a.catchDecided = false
            a.facing = (eligible.position - a.position).unit()
        }
        assignCircleSpots(current)
        ball = Ball(eligible.position, 1.2, V.zero, 0.0, current)
    }

    private func penalty(_ a: GameActor, _ en: String, _ he: String) {
        if !a.active { return }
        a.penalties += 1
        a.hitAt = time
        regroupPending = true
        emit("penalty", a.member.id)
        message(a.member.displayName(hebrew: false) + ": " + en, a.member.displayName(hebrew: true) + ": " + he)
        if config.rules == .spud && a.penalties >= 4 {
            a.spectator = .letters
            a.eliminatedAt = time
            a.exitAt = -1.0
            a.exitFrom = nil
            a.exitTo = nil
            a.move = V.zero
            a.actuallyMoving = false
            emit("spectator", a.member.id)
        } else if config.rules == .nicknames && a.penalties % 3 == 0 {
            pendingHuddles.append(a.member.id)
        }
    }

    private func resolve(_ next: String, _ en: String, _ he: String, who: String? = nil, code: String = "") {
        if regroupPending {
            breakSerial += 1
            statusSerial += 1
            lastStatusAt = time
        }
        if code == "air_catch" && actor(next)?.member.bot == true {
            recallAt = time + random.nextDouble(0.70, 1.20)
        } else {
            recallAt = 0.0
        }
        nextThrower = next
        if code != "air_catch" {
            for a in actors {
                a.move = V.zero
                a.actuallyMoving = false
            }
        }
        transition(.resolve)
        message(en, he, who ?? next, code)
    }

    func tick(_ rawDt: Double) {
        if paused || sharedPause || result != nil { return }
        var left = Kotlin.clamp(rawDt, 0.0, 0.1)
        while left > 1e-9 {
            let dt = min(left, 1.0 / 120)
            step(dt)
            left -= dt
        }
    }

    private func airborne(_ dt: Double) {
        if ball.burst { return }
        let wind = (phase == .air || phase == .retrieve) ? GroundBounce.edgeWind(ball, config, windVector) : windVector
        BallFlight.advance(&ball, dt, config.scene.gravity, wind)
    }

    private func ground() {
        if ball.burst { return }
        ball.height = 0.23
        let incoming = abs(ball.vz)
        ball.vz = incoming * config.ball.restitution * config.scene.bounce
        let nameCall = phase == .air || phase == .retrieve
        ball.velocity = (nameCall ? GroundBounce.direction(ball.velocity, ball.flightId, ball.bounces) : ball.velocity) * 0.80
        ball.bounces += 1
        if incoming > 0.9 { emit("bounce", "") }
        if incoming < 0.7 || ball.bounces > 5 {
            ball.vz = 0.0
            ball.velocity = V.zero
        }
    }

    /// The court edge is not an invisible wall. Let the ball slide to rest there; never reflect a leftward call to the
    /// right without a real contact.
    private func wall() {
        GroundBounce.contain(&ball, config)
    }

    private func step(_ dt: Double) {
        time += dt
        if let practice {
            practice.tick(self, dt)
            return
        }
        if phase == .returnVote {
            if time >= returnDeadline { finishReturnVote() }
            return
        }
        if phase == .waiting {
            beginReturnVoteIfReady()
            return
        }
        if tickActionTimer() { return }
        if phase == .huddle {
            if !onlineHuddles {
                botsHuddle()
                let voted = activeActors.filter { $0.member.id != huddleTarget }.allSatisfy { votes[$0.member.id] != nil }
                if time >= huddleDeadline || (time - phaseAt >= 2.0 && voted) { finishHuddleLocal() }
            }
            return
        }
        // A point pauses walking, not gravity: finish an airborne dodge naturally.
        for a in actors where a.jumpHeight > 0 || a.jumpVelocity != 0.0 {
            a.jumpHeight = max(a.jumpHeight + a.jumpVelocity * dt - 0.5 * config.scene.gravity * dt * dt, 0.0)
            a.jumpVelocity -= config.scene.gravity * dt
            if a.jumpHeight == 0.0 { a.jumpVelocity = 0.0 }
        }
        if phase == .resolve && !freeCatchReturn() {
            // A tag rebounds away. It never visually becomes a catch.
            if ball.holder == nil && (ball.velocity.length() > 0.04 || ball.height > 0.24) {
                airborne(dt)
                if ball.height <= 0.23 { ground() }
            }
            let wait = regroupPending ? max(5.0, config.resolveSeconds) : config.resolveSeconds
            if time - phaseAt >= wait { afterResolution() }
            return
        }
        for (i, a) in actors.enumerated() { movementStart[i] = a.position }
        moveActors(dt)
        if movingPhase() { separateActors() }
        walkPoses(dt)
        if freeCatchReturn() && time >= (recallAt > 0 ? recallAt : phaseAt + config.resolveSeconds) {
            afterResolution()
            return
        }
        if let holder = ball.holder {
            if let h = actor(holder) { ball.position = h.position }
            ball.height = 1.2
            return
        }
        switch phase {
        case .air, .retrieve, .flight:
            break
        case .circle, .shout, .aim, .resolve, .huddle, .returnVote, .waiting, .finished:
            return
        }
        if phase == .retrieve && ball.height <= 0.23001 && ball.vz == 0.0 && ball.velocity.length() < 0.001 { return }
        let before = ball.position
        let beforeZ = ball.height
        airborne(dt)
        if phase == .air || phase == .retrieve {
            if nameCallContact() { return }
        } else if phase == .flight {
            if flightContact(before: before, beforeZ: beforeZ) { return }
        }
        if ball.height <= 0.23 {
            let was = phase
            if config.ball == .paint && (was == .flight || was == .air && ball.burstOnGround) {
                ball.height = 0.23
                burstBalloon()
                if was == .flight {
                    miss("The balloon burst on the ground.", "הבלון התפוצץ על הקרקע.")
                } else {
                    if let target = actor(called) { penalty(target, "The high balloon burst.", "הבלון הגבוה התפוצץ.") }
                    resolve(called, "The high balloon burst before pickup. One penalty.", "הבלון הגבוה התפוצץ לפני האיסוף. נקודת חובה אחת.",
                            who: called, code: "paint_burst")
                }
                return
            }
            ground()
            if was == .air {
                transition(.retrieve)
                message("Pick it up. Throw now, or call SPUD to stop runners.", "אספו את הכדור. זרקו מיד, או קראו עמודו כדי לעצור את הרצים.", called, "pickup")
            }
            if was == .flight && !config.allowGroundHit {
                miss("The ball touched the ground first.", "הכדור נגע קודם בקרקע.")
                return
            }
        }
        if phase == .air || phase == .retrieve { wall() }
        if phase == .flight && (time - phaseAt > 4.5 || ball.bounces >= 2) { miss("The throw missed.", "הזריקה החטיאה.") }
    }

    /// The `activeActors.forEach` movement loop of Kotlin `step` (the list is taken once, as Kotlin does).
    private func moveActors(_ dt: Double) {
        for a in activeActors {
            if a.member.bot { bot(a, dt) }
            if !canRun(a) {
                a.move = V.zero
                a.actuallyMoving = false
            }
            if a.move.length() > 0.01 {
                let factor = a.member.bot ? AmuduCharacters.get(a.member.character).qualities.runFactor : 1.0
                moveActor(a, a.move * (config.moveSpeed * config.scene.run * factor * dt), contact: true)
            }
        }
    }

    private func separateActors() {
        let n = actors.count
        for i in 0..<n {
            for j in (i + 1)..<n {
                let a = actors[i]
                let b = actors[j]
                if !a.active || !b.active { continue }
                let delta = b.position - a.position
                let distance = delta.length()
                if distance < 1.1 {
                    let fallbackAngle = Double(i) + Double(j)
                    let direction = distance > 0.001 ? delta.unit() : V(cos(fallbackAngle), sin(fallbackAngle))
                    let canA = canRun(a)
                    let canB = canRun(b)
                    let share: Double = (canA && canB) ? 2 : 1
                    let push = direction * ((1.1 - distance) / share)
                    if canA { moveActor(a, push * -1.0) }
                    if canB { moveActor(b, push) }
                }
            }
        }
    }

    /// Decide the walk pose after collision separation, from distance actually travelled. Tiny approach corrections or a
    /// blocked stride are not running.
    private func walkPoses(_ dt: Double) {
        for (i, a) in actors.enumerated() where a.active {
            let actual = a.position - movementStart[i]
            let direction = a.move.unit()
            let forward = actual.x * direction.x + actual.y * direction.y
            // A rate threshold is independent of the variable final physics substep.
            // Below this is collision/rounding correction, not a visible stride.
            a.actuallyMoving = a.move.length() > 0.01 && forward > dt * (a.actuallyMoving ? 0.01 : 0.025)
            if a.actuallyMoving {
                let factor = a.member.bot ? AmuduCharacters.get(a.member.character).qualities.runFactor : 1.0
                let speed = config.moveSpeed * config.scene.run * factor
                a.gait += min(forward, speed * dt) / speed * 9
                a.facing = direction
            } else if ball.holder != a.member.id && (ball.position - a.position).length() > 0.05 {
                a.facing = (ball.position - a.position).unit()
            }
        }
    }

    /// The AIR/RETRIEVE branch of `step`; returns true when Kotlin returns from `step`.
    private func nameCallContact() -> Bool {
        guard let target = actor(called) else { return true }
        let inHands = ball.height >= target.jumpHeight + 1.05 && ball.height <= target.jumpHeight + 2.0
        if (ball.vz < 0 || phase == .retrieve) && inHands && (ball.position - target.position).length() < config.ball.catchRadius * target.catchReach &&
            time >= target.catchReadyAt && time < target.catchUntil && time >= target.duckUntil {
            if target.catchRoll < target.catchProbability {
                target.catchUntil = 0.0
                target.catchAt = time
                target.move = V.zero
                target.actuallyMoving = false
                ball.holder = called
                if phase == .retrieve {
                    // Once the name-call ball has bounced, collecting it (even in the air) leads
                    // to a tag attempt, not another free name call.
                    ball.velocity = V.zero
                    ball.vz = 0.0
                    ball.height = 1.2
                    thrower = called
                    pickupAnchor = target.position
                    target.move = V.zero
                    target.actuallyMoving = false
                    transition(.shout)
                    target.nextThink = time + 0.7
                    emit("pickup", called)
                } else {
                    emit("catch", called)
                    resolve(called, "Great catch! Call someone from here.", "תפיסה נהדרת! קראו למישהו מהמקום שלכם.", who: called, code: "air_catch")
                }
                return true
            }
            target.catchUntil = 0.0
        }
        let bodyTop = time < target.duckUntil ? max(config.duckHeight, 1.4) : 1.6
        if ball.vz < 0 && ball.height >= target.jumpHeight + 0.3 && ball.height <= target.jumpHeight + bodyTop &&
            (ball.position - target.position).length() < 0.45 {
            if config.ball == .paint && ball.burstOnGround {
                burstBalloon(target)
                penalty(target, "Paint hit!", "פגיעת צבע!")
                resolve(called, "The balloon burst on the called player. One penalty.", "הבלון התפוצץ על השחקן ששמו נקרא. נקודת חובה אחת.",
                        who: called, code: "paint_hit")
                return true
            }
            rebound(target)
            transition(.retrieve)
            message("It bounced off you. Pick it up to throw.", "הכדור פגע בכם. אספו אותו כדי לזרוק.", called, "air_hit")
            return true
        }
        return false
    }

    /// The FLIGHT branch of `step`: resolve ground contact before any actor beyond the crossing point.
    private func flightContact(before: V, beforeZ: Double) -> Bool {
        let groundT: Double
        if ball.height <= 0.23 && beforeZ > 0.23 {
            groundT = Kotlin.clamp((beforeZ - 0.23) / (beforeZ - ball.height), 0.0, 1.0)
        } else {
            groundT = 1.0
        }
        let delta = ball.position - before
        let radius = BallContact.radius(config.ball)
        var collisions: [(actor: GameActor, t: Double)] = []
        for a in activeActors where a.member.id != thrower {
            let height = time < a.duckUntil ? max(config.duckHeight, 1.4) : config.standingHeight
            let reaching = time >= a.catchReadyAt && time < a.catchUntil && time >= a.duckUntil
            let body = BallContact.first(before, ball.position, beforeZ, ball.height, a.position, 0.28 + radius, a.jumpHeight - radius / 2,
                                         a.jumpHeight + height + radius / 2)
            // An outstretched hand is a real contact, not merely an animation beside a tiny torso collider.
            var hand: Double?
            if reaching {
                let low = a.catchHeight < 1.05
                hand = BallContact.first(before, ball.position, beforeZ, ball.height, a.position + a.facing * 0.58, 0.20 + radius,
                                         a.jumpHeight + (low ? 0.35 : 1.05), a.jumpHeight + (low ? 1.05 : 2.0))
            }
            let found = [body, hand].compactMap { $0 }
            if let t = found.min() { collisions.append((actor: a, t: t)) }
        }
        let ordered = Kotlin.stableSorted(collisions) { $0.t < $1.t }
        for entry in ordered {
            let a = entry.actor
            let t = entry.t
            if t > groundT && (!config.allowGroundHit || config.ball == .paint) { continue }
            let z = beforeZ + (ball.height - beforeZ) * t
            ball.position = before + delta * t
            ball.height = z
            let caught = time >= a.catchReadyAt && time < a.catchUntil && time >= a.duckUntil && z - a.jumpHeight >= 0.35 &&
                z - a.jumpHeight <= 2.05 &&
                a.catchRoll < a.catchProbability * min(AttackPhysics.catchFactor(a.catchHeight), AttackPhysics.catchFactor(z - a.jumpHeight))
            if caught {
                a.catchUntil = 0.0
                a.catchAt = time
                if config.ball == .paint && ball.burstOnCatch {
                    burstBalloon(a, caught: true)
                    penalty(a, "The balloon burst in your hands!", "הבלון התפוצץ בידיים שלכם!")
                    resolve(a.member.id, "Caught it, but it burst! The catcher gets a penalty.", "תפסתם, אבל הבלון התפוצץ! התופסים מקבלים נקודת חובה.",
                            who: a.member.id, code: "catch_burst")
                    return true
                }
                emit("catch", a.member.id)
                if let th = actor(thrower) { penalty(th, "The ball was caught!", "הכדור נתפס!") }
                ball.holder = a.member.id
                ball.velocity = V.zero
                ball.vz = 0.0
                // The penalized player makes the next name call in both rule sets.
                // A fourth SPUD letter eliminates them, so the catcher starts instead.
                var next = a.member.id
                if let th = actor(thrower), th.active { next = th.member.id }
                resolve(next, "Caught it! The thrower gets a penalty.", "תפסתם! הזורק מקבל נקודת חובה.", who: a.member.id, code: "tag_catch")
            } else {
                a.catchUntil = 0.0
                actor(thrower)?.rankEarned += 5
                penalty(a, "Tagged!", "הכדור פגע!")
                if config.ball == .paint { burstBalloon(a) } else { rebound(a) }
                resolve(a.member.id, "A tag, not a catch. Back to the circle.", "פגיעה ולא תפיסה. חוזרים למעגל.", who: a.member.id, code: "tagged")
            }
            return true
        }
        return false
    }

    /// Kotlin `armAttackBurst(power)`: every direct impact bursts; only an otherwise successful catch uses the
    /// rare-burst cadence.
    func armAttackBurst(_ power: Double) {
        if config.ball == .paint {
            ball.burstOnGround = true
            ball.burstOnCatch = attackBursts.released(power >= 0.80)
        }
    }

    /// Kotlin `burstBalloon(target = null, call = phase in (AIR, RETRIEVE), caught = false)`.
    func burstBalloon(_ target: GameActor? = nil, call: Bool? = nil, caught: Bool = false) {
        let isCall = call ?? (phase == .air || phase == .retrieve)
        if ball.burst { return }
        let area = PaintBalloon.splashArea((pow(ball.velocity.length(), 2.0) + ball.vz * ball.vz).squareRoot())
        if isCall {
            callBursts.burst()
        } else if caught {
            attackBursts.burst()
        }
        ball.burst = true
        ball.velocity = V.zero
        ball.vz = 0.0
        ball.holder = nil
        if let t = target {
            t.paintHits.append(paintColor)
            t.hitAt = time
        }
        paintSplashes.append(PaintSplash(ball.position, paintColor, Int64(Kotlin.hashCode(ball.flightId)), time, area))
        if paintSplashes.count > 36 { paintSplashes.removeFirst() }
        emit("paint", target?.member.id ?? "")
    }

    private func rebound(_ a: GameActor) {
        let offset = ball.position - a.position
        let normal = offset.length() < 0.05 ? ball.velocity.unit() * -1.0 : offset.unit()
        let dot = ball.velocity.x * normal.x + ball.velocity.y * normal.y
        ball.velocity = (ball.velocity - normal * (2 * dot)) * 0.55
        ball.vz = abs(ball.vz) * 0.3 + 1.2
        ball.holder = nil
        ball.position = a.position + normal * (0.28 + BallContact.radius(config.ball) + 0.02)
        a.hitAt = time
        emit("hit", a.member.id)
    }

    private func miss(_ en: String, _ he: String) {
        if let th = actor(thrower) { penalty(th, en, he) }
        resolve(thrower, en + " The thrower gets a penalty.", he + " הזורק מקבל נקודת חובה.", who: thrower, code: "miss")
    }

    private func afterResolution() {
        if config.rules == .spud && activeActors.count <= 1 {
            finish()
            return
        }
        if beginReturnVoteIfReady() { return }
        pendingHuddles.removeAll { actor($0)?.active != true }
        if !pendingHuddles.isEmpty {
            beginHuddle(pendingHuddles.removeFirst())
            return
        }
        if config.turns > 0 && turn >= config.turns {
            finish()
            return
        }
        if time - lastStatusAt >= 180 {
            statusSerial += 1
            lastStatusAt = time
        }
        turn += 1
        circle(nextThrower, regroup: regroupPending)
    }

    private func beginHuddle(_ target: String) {
        huddleTarget = target
        huddleSerial += 1
        huddleDeadline = time + config.huddleSeconds
        suggestions.removeAll()
        votes.removeAll()
        transition(.huddle)
        for a in actors { a.nextThink = time + random.nextDouble(0.8, 2.0) }
        // No global spoken announcement: the target gets an ordinary between-round pause.
    }

    /// Kotlin `propose`: one person may offer distinct words (later ones keyed `uid~proposalKey`); a duplicate word never
    /// splits votes. The proposer's own vote goes to their latest word.
    @discardableResult
    func propose(_ uid: String, _ text: String) -> Bool {
        if phase != .huddle || uid == huddleTarget || actor(uid)?.active != true || !Words.validSuggestion(text) { return false }
        let word = Words.nfkcTrim(text)
        if suggestions.values.contains(where: { Words.normalize($0) == Words.normalize(word) }) { return false }
        let key = suggestions[uid] == nil ? uid : uid + "~" + Words.proposalKey(word)
        suggestions[key] = word
        votes[uid] = key
        return true
    }

    @discardableResult
    func vote(_ uid: String, _ proposal: String) -> Bool {
        if phase != .huddle || uid == huddleTarget || actor(uid)?.active != true || suggestions[proposal] == nil { return false }
        votes[uid] = proposal
        return true
    }

    /// `keys.sortedWith(compareByDescending { votes.count(it) }.thenBy { it }).first()`.
    static func rankedWinner(keys: [String], votes: [String]) -> String? {
        var counts: [String: Int] = [:]
        for v in votes { counts[v, default: 0] += 1 }
        var best: String?
        for key in keys {
            guard let current = best else {
                best = key
                continue
            }
            let a = counts[key] ?? 0
            let b = counts[current] ?? 0
            if a > b || (a == b && Kotlin.less(key, current)) { best = key }
        }
        return best
    }

    private func finishHuddleLocal() {
        if suggestions.isEmpty {
            suggestions["fallback"] = Words.suggestion(huddleSerial, hebrew: actor(huddleTarget)?.member.hebrew ?? false)
        }
        // Kotlin `activeActors.singleOrNull { !it.member.bot }?.member?.id?.takeIf { it != huddleTarget }?.let { votes[it] }`.
        let humans = activeActors.filter { !$0.member.bot }
        var chosen: String?
        if humans.count == 1 {
            let human = humans[0].member.id
            if human != huddleTarget { chosen = votes[human] }
        }
        if chosen == nil { chosen = AmuduEngine.rankedWinner(keys: suggestions.keys, votes: votes.values) }
        if let key = chosen, let winner = suggestions[key] { applyHuddle(winner) }
    }

    @discardableResult
    func applyHuddle(_ winner: String) -> Bool {
        if phase != .huddle || !Words.validSuggestion(winner) { return false }
        guard let a = actor(huddleTarget) else { return false }
        a.suffixes.append(Kotlin.trim(winner))
        statusSerial += 1
        emit("renamed", a.member.id, a.fullName())
        huddleTarget = ""
        transition(.resolve)
        message("Next round…", "התור הבא…")
        return true
    }

    func finish() {
        if result != nil { return }
        // SPUD: the last active player wins; nickname rules: the fewest penalties among everyone still in the room.
        let eligible = config.rules == .spud ? activeActors : actors.filter { !$0.departed }
        let low = eligible.map { $0.penalties }.min()
        var penalties: [String: Int] = [:]
        for a in actors { penalties[a.member.id] = a.penalties }
        let winners = eligible.filter { $0.penalties == low }.map { $0.member.id }
        result = Outcome(id: id, penalties: penalties, winners: winners, elapsed: time)
        transition(.finished)
        emit("finish", "")
    }

    /// Kotlin `countdownSeconds()`: whole seconds left on the action timer, or -1 when no timer runs.
    func countdownSeconds() -> Int {
        if actionDeadline > 0 && !actionStage.isEmpty { return max(Kotlin.toInt(ceil(actionDeadline - time)), 0) }
        return -1
    }

    /// Kotlin `tickActionTimer()`: with two or more active humans, an unfinished toss, pickup or throw costs a penalty;
    /// three in a row make the actor a watcher. Returns true when the turn was resolved.
    private func tickActionTimer() -> Bool {
        let stage: String
        switch phase {
        case .circle:
            stage = "toss"
        case .retrieve:
            stage = ball.height <= 1.4 ? "retrieve" : ""
        case .shout, .aim:
            stage = "throw"
        case .air, .flight, .resolve, .huddle, .returnVote, .waiting, .finished:
            stage = ""
        }
        let uid = phase == .retrieve ? called : thrower
        let humans = activeHumans
        if config.actionSeconds == 0 || humans < 2 || stage.isEmpty {
            actionStage = ""
            actionActor = ""
            actionDeadline = 0.0
            timerHumans = humans
            return false
        }
        if stage != actionStage || uid != actionActor || timerHumans < 2 {
            actionStage = stage
            actionActor = uid
            actionDeadline = time + Double(config.actionSeconds)
            retrievalGrace = 0.0
            retrievalDistance = Double.greatestFiniteMagnitude
        }
        timerHumans = humans
        if stage == "retrieve", let a = actor(uid) {
            let distance = (ball.position - a.position).length()
            // At most three extra seconds, earned only by measurable progress toward the ball.
            if distance < retrievalDistance - 0.25 && a.move.length() > 0.08 && retrievalGrace < 3.0 && actionDeadline - time < 3 {
                let extra = min(0.5, 3.0 - retrievalGrace)
                actionDeadline += extra
                retrievalGrace += extra
            }
            if distance < retrievalDistance - 0.25 { retrievalDistance = distance }
        }
        if time < actionDeadline { return false }
        guard let a = actor(uid), a.active else { return false }
        actionStage = ""
        actionDeadline = 0.0
        a.idleStrikes += 1
        penalty(a, "Time ran out.", "הזמן נגמר.")
        if a.active && a.idleStrikes >= config.idleLimit {
            a.spectator = .inactive
            a.returnAttempts = 0
            a.returnQueued = false
            a.move = V.zero
            a.actuallyMoving = false
            pendingHuddles.removeAll { $0 == uid }
            emit("spectator", uid)
        }
        let index = actors.firstIndex { $0 === a } ?? 0
        var next = uid
        for offset in 1...actors.count {
            let candidate = actors[(index + offset) % actors.count]
            if candidate.active {
                next = candidate.member.id
                break
            }
        }
        ball.holder = nil
        ball.velocity = V.zero
        ball.vz = 0.0
        resolve(next, "Time ran out. Next player.", "הזמן נגמר. עוברים לשחקן הבא.", who: uid, code: "timeout")
        return true
    }

    private func requestReturn(_ a: GameActor) -> Bool {
        if config.rules != .nicknames || a.spectator != .inactive || a.returnQueued || a.member.bot ||
            a.returnAttempts >= config.returnAttemptLimit || returnTarget == a.member.id { return false }
        a.returnQueued = true
        a.returnAfterBreak = breakSerial + (phase == .waiting ? 0 : 1)
        emit("return_requested", a.member.id)
        return true
    }

    @discardableResult
    private func beginReturnVoteIfReady() -> Bool {
        if config.rules != .nicknames { return false }
        guard let a = actors.first(where: { $0.returnQueued && $0.spectator == .inactive && $0.returnAfterBreak <= breakSerial }) else { return false }
        a.returnQueued = false
        a.returnAttempts += 1
        returnTarget = a.member.id
        returnSerial += 1
        returnVotes.removeAll()
        returnDeadline = time + config.returnVoteSeconds
        for other in actors {
            other.move = V.zero
            other.actuallyMoving = false
        }
        transition(.returnVote)
        emit("return_vote", a.member.id)
        return true
    }

    private func castReturnVote(_ a: GameActor, _ voteSerial: Int, _ yes: Bool) -> Bool {
        if phase != .returnVote || voteSerial != returnSerial || !a.active || a.member.bot || a.member.id == returnTarget ||
            returnVotes[a.member.id] != nil { return false }
        returnVotes[a.member.id] = yes
        return true
    }

    private func finishReturnVote() {
        guard let a = actor(returnTarget) else { return }
        let eligible = returnVotes.filter { entry in
            guard let voter = actor(entry.key) else { return false }
            return voter.active && !voter.member.bot
        }
        let yes = eligible.values.filter { $0 }.count
        let no = eligible.values.filter { !$0 }.count
        if yes > no {
            a.spectator = SpectatorReason.none
            a.idleStrikes = 0
            a.returnAttempts = 0
            a.returnQueued = false
            regroupPending = true
            statusSerial += 1
            emit("returned", a.member.id)
        } else {
            emit("return_denied", a.member.id)
        }
        returnTarget = ""
        returnVotes.removeAll()
        returnDeadline = 0.0
        actionStage = ""
        actionDeadline = 0.0
        transition(.resolve)
    }

    private func flee(_ a: GameActor, _ dt: Double) {
        FleeMovement.update(a, ball, windVector, config, time, dt, seed, phase, actors)
    }

    /// Assign one stable, evenly spaced destination per return, nearest overall. This never moves a human: only a
    /// point reset places players on the circle.
    private func assignCircleSpots(_ receiver: String) {
        guard let target = actor(receiver) else { return }
        target.circleSpot = nil
        let others = activeActors.filter { $0.member.id != receiver }
        let spots = CircleFormation.spots(V(config.width / 2, config.depth / 2), others.count, circleAngle)
        let assigned = CircleFormation.nearest(others.map { $0.position }, spots)
        for (i, a) in others.enumerated() { a.circleSpot = assigned[i] }
    }

    private func returnToBall(_ a: GameActor, _ pace: Double) {
        if ball.holder == a.member.id {
            a.move = V.zero
            return
        }
        if a.circleSpot == nil { assignCircleSpots(phase == .air ? called : (ball.holder ?? thrower)) }
        guard let spot = a.circleSpot else { return }
        let delta = spot - a.position
        // Stop on the marked 4.5-unit perimeter, with a real arrival tolerance.
        a.move = delta.length() > 0.10 ? delta.unit() * min(pace, delta.length() * 1.5) : V.zero
    }

    private func shouldAnticipateCatch(_ a: GameActor) -> Bool {
        guard let receiver = actor(called), receiver.active else { return false }
        if ball.bounces != 0 { return false }
        // This is a gamble on this flight, not a direction choice every physics tick.
        // Crossing the six-unit entry threshold must not switch return -> flee -> return.
        if !Kotlin.isBlank(ball.flightId) && a.anticipationFlight == ball.flightId { return true }
        if (a.position - landing).length() < 6.0 { return false }
        let g = config.scene.gravity
        let disc = ball.vz * ball.vz + 2 * g * (ball.height - 1.45)
        if disc <= 0 { return false }
        let remaining = (ball.vz + disc.squareRoot()) / g
        if remaining <= 0.12 { return false }
        let point = ball.position + ball.velocity * remaining + windVector * (0.5 * remaining * remaining)
        let factor = receiver.member.bot ? AmuduCharacters.get(receiver.member.character).qualities.runFactor : 1.0
        let run = config.moveSpeed * config.scene.run * factor
        if (point - receiver.position).length() > run * remaining * 0.85 + config.ball.catchRadius { return false }
        // Estimate from visible trajectory/skill, never from the secret success roll.
        let likely = copyForCatchPrediction(receiver, point, ball.velocity, ball.vz - g * remaining)
        let chance = CatchPhysics.probability(likely.0, likely.1, actor(thrower))
        var wagerRandom = KotlinRandom(seed: seed ^ Int64(Kotlin.hashCode(ball.flightId)) ^ Int64(Kotlin.hashCode(a.member.id)))
        let wager = wagerRandom.nextDouble()
        let returning = chance > 0.70 && wager < 0.65 + 0.25 * (Double(AmuduCharacters.get(a.member.character).qualities.accuracy) / 5.0)
        if returning { a.anticipationFlight = ball.flightId }
        return returning
    }

    private func copyForCatchPrediction(_ actor: GameActor, _ point: V, _ velocity: V, _ vz: Double) -> (GameActor, Ball) {
        let copy = GameActor(member: actor.member, position: point)
        copy.facing = velocity.unit() * -1.0
        return (copy, Ball(point, 1.45, velocity, vz))
    }

    /// Explicit room departure is different from a temporary connection loss.
    func depart(_ uid: String) {
        guard let a = actor(uid) else { return }
        if a.departed { return }
        a.departed = true
        a.spectator = .inactive
        a.move = V.zero
        a.actuallyMoving = false
        a.returnQueued = false
        connectedHumanIds.remove(uid)
        pendingHuddles.removeAll { $0 == uid }
        returnVotes[uid] = nil
        votes[uid] = nil
        emit("left", uid)
        if result != nil { return }
        if activeActors.count < 2 {
            finish()
            return
        }
        let heldTurn = called == uid && (phase == .air || phase == .retrieve) ||
            thrower == uid && (phase == .circle || phase == .shout || phase == .aim)
        if huddleTarget == uid || returnTarget == uid || ball.holder == uid || heldTurn {
            huddleTarget = ""
            returnTarget = ""
            if let first = activeActors.first { circle(first.member.id, regroup: false) }
        }
    }

    private func nextBotId() -> String {
        serial += 1
        return "bot-" + String(serial)
    }

    private func botThrow(_ a: GameActor) {
        let q = AmuduCharacters.get(a.member.character).qualities
        let others = activeActors.filter { $0.member.id != a.member.id }
        guard var target = others.first else { return }
        // Kotlin `minBy`: the selector (and its random draw) runs only when there are at least two candidates.
        if others.count > 1 {
            var minValue = (target.position - a.position).length() + random.nextDouble() * 1.5
            for other in others.dropFirst() {
                let value = (other.position - a.position).length() + random.nextDouble() * 1.5
                if minValue > value {
                    target = other
                    minValue = value
                }
            }
        }
        let delta = target.position - a.position
        let distance = max(delta.length() - 0.52, 0.2)
        let targetHeight = AttackPhysics.height(random.nextDouble())
        // Prefer a purposeful attack. Solve its elevation independently so power
        // is not silently reduced just to reach torso height.
        let preferred = 0.60 + 0.06 * Double(q.power)
        let g = config.scene.gravity
        let lift = (g / 9.8).squareRoot()
        var best = preferred
        var score = Double.greatestFiniteMagnitude
        for i in 10...100 {
            let p = Double(i) / 100.0
            let t = distance / throwProfile(a, p).speed
            let vz = (targetHeight - 1.17 + 0.5 * g * t * t) / t
            let outside = abs(vz - Kotlin.clamp(vz, -0.35 * lift, 4.95 * lift))
            let cost = outside * 8 + abs(p - preferred)
            if cost < score {
                score = cost
                best = p
            }
        }
        let powerError = Double(5 - q.accuracy) * 0.045
        let p = Kotlin.clamp(best + random.nextDouble(-1.0, 1.0) * powerError, 0.06, 1.0)
        let travel = distance / throwProfile(a, p).speed
        let lead = target.actuallyMoving ? target.move * (config.moveSpeed * travel * (Double(q.accuracy) / 5.0)) : V.zero
        let ballError: Double
        switch config.ball {
        case .tennis: ballError = 0.65
        case .beach: ballError = 1.3
        case .paint: ballError = 0.9
        case .foam, .neon: ballError = 1.0
        }
        let error = Double(5 - q.accuracy) * 0.24 * ballError
        let errorX = random.nextDouble(-1.0, 1.0) * error
        let errorY = random.nextDouble(-1.0, 1.0) * error
        let aim = delta + lead - windVector * (0.5 * travel * travel) + V(errorX, errorY)
        // All three heights use the same legal launch limits, also in Easy mode.
        let vz = (targetHeight - 1.17 + 0.5 * g * travel * travel) / travel + random.nextDouble(-1.0, 1.0) * Double(5 - q.accuracy) * 0.05
        command(a.member.id, nextBotId(), .aim(aim.unit()))
        command(a.member.id, nextBotId(), .throwBall(power: p, botVz: vz))
    }

    private func bot(_ a: GameActor, _ dt: Double) {
        let uid = a.member.id
        let q = AmuduCharacters.get(a.member.character).qualities
        if time < a.catchUntil {
            a.move = V.zero
            return
        }
        if freeCatchReturn() {
            returnToBall(a, 1.0)
            return
        }
        switch phase {
        case .circle:
            if uid != thrower {
                returnToBall(a, 1.0)
            } else if time > a.nextThink {
                botCall(a, uid, q)
            }
        case .air, .retrieve:
            if uid == called {
                let goal = phase == .air ? landing : ball.position
                let delta = goal - a.position
                a.move = delta.length() > 0.15 ? delta.unit() : V.zero
                if ball.vz < 0 && ball.height < 2.5 && !a.catchDecided && time > a.nextThink &&
                    (ball.position - a.position).length() < config.ball.catchRadius + 0.35 {
                    a.catchDecided = true
                    command(uid, nextBotId(), .catchBall)
                }
                if phase == .retrieve && (ball.position - a.position).length() < config.ball.catchRadius + 0.2 {
                    command(uid, nextBotId(), .catchBall)
                }
            } else if phase == .air && shouldAnticipateCatch(a) {
                returnToBall(a, 0.42 + 0.16 * (Double(q.speed) / 5.0))
            } else {
                flee(a, dt)
            }
        case .shout:
            if uid == thrower {
                a.move = V.zero
                if time > a.nextThink {
                    // A required call or a step allowance means the house player always calls first.
                    if config.requireCall || config.stepsAfterCall > 0 || random.nextDouble() < 0.58 {
                        command(uid, nextBotId(), .shout)
                        a.nextThink = time + 0.7
                    } else {
                        botThrow(a)
                    }
                }
            } else {
                flee(a, dt)
            }
        case .aim:
            a.move = V.zero
            a.facing = (ball.position - a.position).unit()
            if uid == thrower {
                // Kotlin `activeActors.filter { it != a }.minByOrNull { distance }`.
                var target: GameActor?
                var nearest = 0.0
                for other in activeActors where other !== a {
                    let d = (other.position - a.position).length()
                    if target == nil || d < nearest {
                        target = other
                        nearest = d
                    }
                }
                if stepRemaining > 0.01, let t = target, (t.position - a.position).length() > 2.5 {
                    a.move = (t.position - a.position).unit()
                    a.nextThink = max(a.nextThink, time + 0.15)
                } else if time > a.nextThink {
                    botThrow(a)
                }
            }
        case .flight:
            if uid != thrower {
                if !isFrozen() && !a.catchDecided { flee(a, dt) }
                if !a.catchDecided && time > a.nextThink {
                    if let incoming = AttackPhysics.approach(ball, a, config, windVector), incoming.at <= 0.35 {
                        a.catchDecided = true
                        let action: GameCommand
                        if incoming.height < 0.95 && AttackPhysics.canJump(ball, a, config, incoming) &&
                            random.nextDouble() < 0.55 + 0.08 * Double(q.jumping - 1) {
                            action = .jump
                        } else if incoming.height > 1.50 && AttackPhysics.canDuck(ball, a, config, incoming) &&
                            random.nextDouble() < 0.55 + 0.08 * Double(q.catching - 1) {
                            action = .duck
                        } else {
                            action = .catchBall
                        }
                        a.move = V.zero
                        command(uid, nextBotId(), action)
                    }
                }
            }
        case .resolve, .huddle, .returnVote, .waiting, .finished:
            break
        }
    }

    /// The CIRCLE name call of a house thrower (Kotlin `bot`, `Phase.CIRCLE`, thrower branch).
    private func botCall(_ a: GameActor, _ uid: String, _ q: Skills) {
        let opponents = activeActors.filter { $0.member.id != uid }
        if opponents.isEmpty { return }
        // Name calls land around the circle center. Outside the initial 4.5-unit
        // circle plus 1.5 units is a meaningful run back, regardless of thrower position.
        let center = V(config.width / 2, config.depth / 2)
        let distant = opponents.filter { ($0.position - center).length() > 6.0 }
        let accuracy = Double(min(max(q.accuracy, 1), 5) - 1) / 4.0
        let maxPower = Kotlin.clamp(0.45 + 0.1 * Double(q.power), 0.0, 1.0)
        let humans = opponents.filter { !$0.member.bot && connectedHumanIds.contains($0.member.id) }
        let pool = botCallStreak >= 3 && !humans.isEmpty ? humans : (distant.isEmpty ? opponents : distant)
        let target = pool[random.nextIndex(pool.count)]
        let power: Double
        if distant.contains(where: { $0 === target }) {
            // One roll per call: low/fast arrival 30–90%; otherwise the bot's full toss.
            power = random.nextDouble() < 0.30 + 0.60 * accuracy ? 0.0 : maxPower
        } else {
            // Nearby opponents get a high call 76–80%; the alternative stays below
            // even Earth's existing height cap, so the two choices really differ.
            if random.nextDouble() < 0.76 + 0.04 * accuracy {
                power = maxPower * random.nextDouble(0.94, 1.0)
            } else {
                power = random.nextDouble(0.08, 0.30)
            }
        }
        if command(uid, nextBotId(), .select(target: target.member.id, typedName: target.fullName())) {
            let tossId = nextBotId()
            let drift = random.nextDouble(-1.0, 1.0) * (1.0 - Double(q.accuracy) * 0.12)
            command(uid, tossId, .toss(power: power, drift: drift))
        }
    }

    private func botsHuddle() {
        let helpers = activeActors.filter { $0.member.bot && $0.member.id != huddleTarget }
        for a in helpers {
            if time > a.nextThink && suggestions[a.member.id] == nil {
                let index = Int(random.nextInt(until: 10000))
                propose(a.member.id, Words.uniqueSuggestion(index, hebrew: a.member.hebrew, used: suggestions.values))
                a.nextThink = time + 1.0
            }
            if time > a.nextThink && !suggestions.isEmpty && votes[a.member.id] == nil {
                let keys = suggestions.keys
                vote(a.member.id, keys[random.nextIndex(keys.count)])
            }
        }
    }
}
