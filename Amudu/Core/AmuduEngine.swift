import Foundation

/// Android `core/AmuduEngine.kt`: authoritative continuous physics; commands never award their own points.
/// Ported statement by statement (same order of random draws and floating-point operations).
final class AmuduEngine {
    let members: [Member]
    let config: GameConfig
    let seed: Int64
    let id: String
    /// Kotlin `practice`: the skill-journey drill when `config.challengeStep >= 0`, else nil.
    let practice: SpudPractice?
    var actors: [GameActor]
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
    var stepRemaining = 0.0
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
    let windVector: V

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
        practice = cfg.challengeStep >= 0 ? SpudPractice(cfg.challengeStep) : nil
        actors = members.map { GameActor(member: $0, position: V.zero) }
        thrower = first.id
        nextThrower = first.id
        ball = Ball(V(cfg.width / 2, cfg.depth / 2), 1.0, V.zero, 0.0, first.id)
        landing = V(cfg.width / 2, cfg.depth / 2)
        random = KotlinRandom(seed: seed)
        let sign: Double = Kotlin.floorMod(seed, Int64(2)) == 0 ? 1.0 : -1.0
        windVector = V(sign, 0.18).unit() * cfg.wind.acceleration
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
        let catchingPhase = (phase == .air && uid == called) || (phase == .flight && uid != thrower)
        let catching = catchingPhase && ball.height >= 0.35 && ball.height <= 2.1
        let reach = config.ball.catchRadius + (pickup ? 0.25 : 0.10)
        return (pickup || catching) && (ball.position - a.position).length() < reach
    }

    func isFrozen() -> Bool { return frozen || phase == .aim }

    func canAim(_ uid: String) -> Bool {
        return actor(uid)?.active == true && uid == thrower && ball.holder == uid && (phase == .shout || phase == .aim)
    }

    private func locked(_ a: GameActor) -> Bool {
        let anchored = (pickupAnchor != nil || phase == .aim) && a.member.id == thrower
        let throwingPhase = phase == .shout || phase == .aim || phase == .flight
        return !a.active || (anchored && throwingPhase) || time < a.catchUntil
    }

    private func movingPhase() -> Bool {
        switch phase {
        case .air, .retrieve, .shout, .aim, .flight:
            return true
        case .circle, .resolve, .huddle, .returnVote, .waiting, .finished:
            return false
        }
    }

    private func canRun(_ a: GameActor) -> Bool {
        if !a.active || !movingPhase() || time < a.catchUntil { return false }
        // After the call the thrower may spend the step allowance, and nothing more.
        if a.member.id == thrower && phase == .aim && ball.holder == thrower { return stepRemaining > 0.00001 }
        return !locked(a) && (!isFrozen() || config.freezeRule == .honor)
    }

    /// Kotlin `moveActor`: bounded movement; the thrower's movement after the call spends `stepRemaining`.
    private func moveActor(_ a: GameActor, _ delta: V) {
        let desired = bounded(a.position + delta) - a.position
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
            if !canRun(a) {
                a.move = V.zero
                return false
            }
            a.move = v.length() > 1 ? v.unit() : v
            if isFrozen() && uid != thrower && a.move.length() > 0.12 && a.movementPenaltyTurn != turn {
                a.movementPenaltyTurn = turn
                penalty(a, "Moved after the call.", "זזתם אחרי הקריאה.")
                resolve(uid, "Moved after the call.", "זזתם אחרי הקריאה.", who: uid, code: "moved")
            }
        case .aim(let v):
            if !canAim(uid) || !v.finite() || v.length() < 0.01 { return false }
            a.direction = v.unit()
            a.facing = a.direction
        case .select(let target, let typedName):
            if phase != .circle || uid != thrower || target == uid { return false }
            guard let t = actor(target), t.active else { return false }
            if config.rules == .nicknames && !t.suffixes.isEmpty {
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
            let power = Kotlin.clamp(rawPower, 0.0, 1.0)
            let duration = 1.05 + power * 2.95
            a.idleStrikes = 0
            called = selected
            let goal = V(config.width / 2, config.depth / 2)
            let driftX = Kotlin.clamp(rawDrift, -1.0, 1.0) * (1 + power * 2)
            let driftY = (random.nextDouble() - 0.5) * 0.7
            let nominal = bounded(goal + V(driftX, driftY))
            let g = config.scene.gravity
            let start = a.position
            // Wind acts during flight. Its projected landing marker is not a homing target.
            landing = bounded(nominal + windVector * (0.5 * duration * duration))
            serial += 1
            let flight = id + "-t" + String(turn) + "-" + String(serial)
            let vz = g * duration / 2 - 1.2 / duration
            ball = Ball(start, 1.2, (nominal - start) * (1 / duration), vz, nil, bounces: 0, flightId: flight, launchAt: time)
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
        case .jump:
            return false
        case .catchBall:
            if time < a.duckUntil || time < a.catchUntil || time < a.catchRecoveryUntil { return false }
            if phase == .retrieve && uid == called && ball.height <= 1.4 && (ball.position - a.position).length() < config.ball.catchRadius + 0.25 {
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
            if (phase == .air && uid == called) || (phase == .flight && uid != thrower) {
                let wasRunning = a.actuallyMoving || a.move.length() > 0.08
                a.catchProbability = a.member.bot ? AmuduCharacters.get(a.member.character).qualities.catchProbability(wasRunning: wasRunning) : 1.0
                let runningHuman = wasRunning && !a.member.bot
                a.catchReadyAt = time + (runningHuman ? 0.10 : 0.0)
                a.catchReach = runningHuman ? 0.82 : 1.0
                a.catchRoll = random.nextDouble()
                a.catchUntil = time + config.catchWindow
                a.catchRecoveryUntil = a.catchUntil + 0.12
                a.move = V.zero
                a.actuallyMoving = false
                a.facing = (ball.position - a.position).unit()
                emit("catch_attempt", uid)
                return true
            }
            return false
        case .duck:
            if !movingPhase() { return false }
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
        case .throwBall(let rawPower):
            if !canAim(uid) || !rawPower.isFinite || (config.requireCall && phase != .aim) { return false }
            a.idleStrikes = 0
            stepRemaining = 0.0
            let p = Kotlin.clamp(rawPower, 0.0, 1.0)
            let profile = throwProfile(a, p)
            if phase == .aim { frozen = true }
            serial += 1
            let flight = id + "-hit-" + String(turn) + "-" + String(serial)
            ball = Ball(a.position + a.direction * 0.52, 1.17, a.direction * profile.speed, profile.vz, nil, bounces: 0, flightId: flight, launchAt: time)
            a.throwAt = time
            a.facing = a.direction
            a.move = V.zero
            for other in actors {
                other.catchDecided = false
                other.nextThink = time + reaction(other)
            }
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

    func throwProfile(_ a: GameActor, _ power: Double) -> (speed: Double, vz: Double) {
        let p = Kotlin.clamp(power, 0.0, 1.0)
        let strength = a.member.bot ? AmuduCharacters.get(a.member.character).qualities.powerFactor : 1.0
        if config.throwMode == .easy {
            return (config.ball.speed * (0.8 + p * 0.55) * strength, config.scene.gravity * 0.09)
        }
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
        var index = 0
        let playing = activeActors
        let count = playing.count - 1
        for a in playing {
            if regroup {
                if a.member.id == current {
                    a.position = center
                } else {
                    let angle = -Double.pi / 2 + 2 * Double.pi * Double(index) / Double(count)
                    index += 1
                    a.position = center + V(cos(angle), sin(angle)) * 4.5
                }
            }
            a.move = V.zero
            a.actuallyMoving = false
            a.duckUntil = 0.0
            a.catchUntil = 0.0
            a.catchRecoveryUntil = 0.0
            a.nextThink = time + 1.0
            a.catchDecided = false
            a.facing = (eligible.position - a.position).unit()
        }
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
            a.move = V.zero
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
        nextThrower = next
        for a in actors {
            a.move = V.zero
            a.actuallyMoving = false
        }
        transition(.resolve)
        message(en, he, who ?? next, code)
    }

    func tick(_ rawDt: Double) {
        if paused || sharedPause || result != nil { return }
        var left = Kotlin.clamp(rawDt, 0.0, 0.1)
        while left > 0 {
            let dt = min(left, 1.0 / 120)
            step(dt)
            left -= dt
        }
    }

    private func airborne(_ dt: Double) {
        BallFlight.advance(&ball, dt, config.scene.gravity, windVector)
    }

    private func ground() {
        ball.height = 0.23
        let incoming = abs(ball.vz)
        ball.vz = incoming * config.ball.restitution * config.scene.bounce
        ball.velocity = ball.velocity * 0.80
        ball.bounces += 1
        if incoming > 0.9 { emit("bounce", "") }
        if incoming < 0.7 || ball.bounces > 5 {
            ball.vz = 0.0
            ball.velocity = V.zero
        }
    }

    private func wall() {
        if ball.position.x < 0.25 || ball.position.x > config.width - 0.25 {
            ball.position = V(Kotlin.clamp(ball.position.x, 0.25, config.width - 0.25), ball.position.y)
            ball.velocity = V(-ball.velocity.x * 0.55, ball.velocity.y)
        }
        if ball.position.y < 0.25 || ball.position.y > config.depth - 0.25 {
            ball.position = V(ball.position.x, Kotlin.clamp(ball.position.y, 0.25, config.depth - 0.25))
            ball.velocity = V(ball.velocity.x, -ball.velocity.y * 0.55)
        }
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
                if time >= huddleDeadline { finishHuddleLocal() }
            }
            return
        }
        if phase == .resolve {
            // A tag rebounds away. It never visually becomes a catch.
            if ball.holder == nil && (ball.velocity.length() > 0.04 || ball.height > 0.24) {
                airborne(dt)
                if ball.height <= 0.23 { ground() }
                wall()
            }
            let wait = regroupPending ? max(5.0, config.resolveSeconds) : config.resolveSeconds
            if time - phaseAt >= wait { afterResolution() }
            return
        }
        moveActors(dt)
        if movingPhase() { separateActors() }
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
        if phase == .air {
            if airContact() { return }
        } else if phase == .flight {
            if flightContact(before: before, beforeZ: beforeZ) { return }
        }
        if ball.height <= 0.23 {
            let was = phase
            ground()
            if was == .air {
                transition(.retrieve)
                message("Pick it up. Throw now, or call SPUD to stop runners.", "אספו את הכדור. זרקו מיד, או קראו עמודו כדי לעצור את הרצים.", called, "pickup")
            }
            if was == .flight && config.throwMode == .standard {
                miss("The ball touched the ground first.", "הכדור נגע קודם בקרקע.")
                return
            }
        }
        wall()
        if phase == .flight && (time - phaseAt > 4.5 || ball.bounces >= 2) { miss("The throw missed.", "הזריקה החטיאה.") }
    }

    /// The `activeActors.forEach` movement loop of Kotlin `step` (the list is taken once, as Kotlin does).
    private func moveActors(_ dt: Double) {
        for a in activeActors {
            if a.member.bot { bot(a) }
            if !canRun(a) {
                a.move = V.zero
                a.actuallyMoving = false
            }
            if a.move.length() > 0.01 {
                let old = a.position
                let factor = a.member.bot ? AmuduCharacters.get(a.member.character).qualities.runFactor : 1.0
                moveActor(a, a.move * (config.moveSpeed * config.scene.run * factor * dt))
                let actual = a.position - old
                a.actuallyMoving = actual.length() > 0.0001
                if a.actuallyMoving {
                    a.gait += dt * 9
                    a.facing = actual.unit()
                } else {
                    a.move = V.zero
                    a.facing = (ball.position - a.position).unit()
                }
            } else {
                a.actuallyMoving = false
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

    /// The AIR branch of `step`; returns true when Kotlin returns from `step`.
    private func airContact() -> Bool {
        guard let target = actor(called) else { return true }
        let distance = (ball.position - target.position).length()
        let catchable = ball.vz < 0 && ball.height >= 0.48 && ball.height <= 2.0 && distance < config.ball.catchRadius * target.catchReach
        if catchable && time >= target.catchReadyAt && time < target.catchUntil && time >= target.duckUntil {
            if target.catchRoll < target.catchProbability {
                target.catchAt = time
                ball.holder = called
                emit("catch", called)
                resolve(called, "Great catch! Call someone from here.", "תפיסה נהדרת! קראו למישהו מהמקום שלכם.", who: called, code: "air_catch")
                return true
            }
            target.catchUntil = 0.0
        }
        if ball.vz < 0 && ball.height >= 0.3 && ball.height <= 1.6 && distance < 0.45 && time >= target.duckUntil {
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
        let squared = delta.x * delta.x + delta.y * delta.y
        var collisions: [(actor: GameActor, t: Double, dist: Double)] = []
        for a in activeActors where a.member.id != thrower {
            var t = 0.0
            if delta.length() >= 0.0001 {
                let projection = (a.position.x - before.x) * delta.x + (a.position.y - before.y) * delta.y
                t = Kotlin.clamp(projection / squared, 0.0, 1.0)
            }
            let closest = before + delta * t
            collisions.append((actor: a, t: t, dist: (closest - a.position).length()))
        }
        let ordered = Kotlin.stableSorted(collisions) { $0.t < $1.t }
        for entry in ordered {
            let a = entry.actor
            let z = beforeZ + (ball.height - beforeZ) * entry.t
            let height = time < a.duckUntil ? config.duckHeight : config.standingHeight
            if entry.t > groundT && config.throwMode == .standard { continue }
            if entry.dist < 0.50 && z >= 0.22 && z <= height {
                let armed = time >= a.catchReadyAt && time < a.catchUntil && time >= a.duckUntil
                if armed && z > 0.48 && a.catchRoll < a.catchProbability {
                    a.catchAt = time
                    emit("catch", a.member.id)
                    if let th = actor(thrower) { penalty(th, "The ball was caught!", "הכדור נתפס!") }
                    ball.holder = a.member.id
                    ball.velocity = V.zero
                    ball.vz = 0.0
                    resolve(a.member.id, "Caught it! The thrower gets a penalty.", "תפסתם! הזורק מקבל נקודת חובה.", who: a.member.id, code: "tag_catch")
                } else {
                    a.catchUntil = 0.0
                    actor(thrower)?.rankEarned += 5
                    penalty(a, "Tagged!", "הכדור פגע!")
                    rebound(a)
                    resolve(a.member.id, "A tag, not a catch. Back to the circle.", "פגיעה ולא תפיסה. חוזרים למעגל.", who: a.member.id, code: "tagged")
                }
                return true
            }
        }
        return false
    }

    private func rebound(_ a: GameActor) {
        let offset = ball.position - a.position
        let normal = offset.length() < 0.05 ? ball.velocity.unit() * -1.0 : offset.unit()
        let dot = ball.velocity.x * normal.x + ball.velocity.y * normal.y
        ball.velocity = (ball.velocity - normal * (2 * dot)) * 0.55
        ball.vz = abs(ball.vz) * 0.3 + 1.2
        ball.holder = nil
        ball.position = a.position + normal * 0.58
        a.hitAt = time
        emit("hit", a.member.id)
    }

    private func miss(_ en: String, _ he: String) {
        if let th = actor(thrower) { penalty(th, en, he) }
        let next = Kotlin.isBlank(called) ? thrower : called
        resolve(next, en + " The thrower gets a penalty.", he + " הזורק מקבל נקודת חובה.", who: thrower, code: "miss")
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

    @discardableResult
    func propose(_ uid: String, _ text: String) -> Bool {
        if phase != .huddle || uid == huddleTarget || actor(uid)?.active != true || !Words.validSuggestion(text) { return false }
        suggestions[uid] = Words.nfkcTrim(text)
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
        // Kotlin `activeActors.singleOrNull { !it.member.bot }`.
        let humans = activeActors.filter { !$0.member.bot }
        var chosen: String?
        if humans.count == 1 {
            let human = humans[0].member.id
            if human != huddleTarget && suggestions[human] != nil { chosen = human }
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
        // SPUD: the last active player wins; nickname rules: the fewest penalties among everyone.
        let eligible = config.rules == .spud ? activeActors : actors
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
        }
        timerHumans = humans
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

    private func nextBotId() -> String {
        serial += 1
        return "bot-" + String(serial)
    }

    private func flee(_ a: GameActor) {
        let delta = (a.position - ball.position).unit()
        let next = bounded(a.position + delta * 0.2)
        if (next - (a.position + delta * 0.2)).length() > 0.001 {
            a.move = V.zero
            a.facing = (ball.position - a.position).unit()
        } else {
            a.move = delta
        }
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
        var best = 0.5
        var score = Double.greatestFiniteMagnitude
        for i in 10...100 {
            let p = Double(i) / 100.0
            let profile = throwProfile(a, p)
            let t = distance / profile.speed
            let z = 1.17 + profile.vz * t - 0.5 * config.scene.gravity * t * t
            let cost = abs(z - 1.1)
            if cost < score {
                score = cost
                best = p
            }
        }
        let powerError = Double(5 - q.accuracy) * 0.045
        let p = Kotlin.clamp(best + random.nextDouble(-1.0, 1.0) * powerError, 0.06, 1.0)
        let travel = distance / throwProfile(a, p).speed
        let lead = target.actuallyMoving ? target.move * (config.moveSpeed * travel * (Double(q.accuracy) / 5.0)) : V.zero
        let error = Double(5 - q.accuracy) * 0.24
        let errorX = random.nextDouble(-1.0, 1.0) * error
        let errorY = random.nextDouble(-1.0, 1.0) * error
        let aim = delta + lead - windVector * (0.5 * travel * travel) + V(errorX, errorY)
        command(a.member.id, nextBotId(), .aim(aim.unit()))
        command(a.member.id, nextBotId(), .throwBall(power: p))
    }

    private func bot(_ a: GameActor) {
        let uid = a.member.id
        let q = AmuduCharacters.get(a.member.character).qualities
        if time < a.catchUntil {
            a.move = V.zero
            return
        }
        switch phase {
        case .circle:
            if uid == thrower && time > a.nextThink {
                let others = activeActors.filter { $0.member.id != uid }
                if others.isEmpty { return }
                let target = others[random.nextIndex(others.count)]
                command(uid, nextBotId(), .select(target: target.member.id, typedName: target.fullName()))
                let tossId = nextBotId()
                let power = random.nextDouble(0.18, 0.45 + 0.1 * Double(q.power))
                let drift = random.nextDouble(-1.0, 1.0) * (1.0 - Double(q.accuracy) * 0.12)
                command(uid, tossId, .toss(power: power, drift: drift))
            }
        case .air, .retrieve:
            if uid == called {
                let goal = phase == .air ? landing : ball.position
                let delta = goal - a.position
                a.move = delta.length() > 0.15 ? delta.unit() : V.zero
                let near = (ball.position - a.position).length()
                if phase == .air && ball.vz < 0 && ball.height < 2.5 && !a.catchDecided && time > a.nextThink && near < config.ball.catchRadius + 0.35 {
                    a.catchDecided = true
                    command(uid, nextBotId(), .catchBall)
                }
                if phase == .retrieve && (ball.position - a.position).length() < config.ball.catchRadius + 0.2 {
                    command(uid, nextBotId(), .catchBall)
                }
            } else {
                flee(a)
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
                flee(a)
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
                if !isFrozen() && !a.catchDecided { flee(a) }
                let delta = ball.position - a.position
                let approaching = ball.velocity.x * delta.x + ball.velocity.y * delta.y < 0
                if !a.catchDecided && delta.length() < (1.6 + Double(q.catching) * 0.12) && time > a.nextThink && approaching {
                    a.catchDecided = true
                    if q.catching >= 3 && ball.height > 1.25 && random.nextDouble() < 0.12 {
                        a.move = V.zero
                        command(uid, nextBotId(), .duck)
                    } else {
                        command(uid, nextBotId(), .catchBall)
                    }
                }
            }
        case .resolve, .huddle, .returnVote, .waiting, .finished:
            break
        }
    }

    private func botsHuddle() {
        let helpers = activeActors.filter { $0.member.bot && $0.member.id != huddleTarget }
        for a in helpers {
            if time > a.nextThink && suggestions[a.member.id] == nil {
                let index = Int(random.nextInt(until: 6))
                propose(a.member.id, Words.suggestion(index, hebrew: a.member.hebrew))
                a.nextThink = time + 1.0
            }
            if time > a.nextThink && !suggestions.isEmpty && votes[a.member.id] == nil {
                let keys = suggestions.keys
                vote(a.member.id, keys[random.nextIndex(keys.count)])
            }
        }
    }
}
