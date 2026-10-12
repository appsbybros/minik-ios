import Foundation

/// Port of Android core/SplashEngine.kt: independent simulation, collision, house-player
/// behaviour, paint, scoring and results. Statement order and random-number consumption follow
/// Android exactly so shared rooms, checkpoints and saved battles agree across platforms.
struct Member: Equatable {
    var id: String
    var character: String
    var team: Int
    var bot: Bool
    var name: String
    var hebrew: Bool
    var settings: PlayerSettings

    init(_ id: String, _ character: String, team: Int = 0, bot: Bool = false, name: String? = nil,
         hebrew: Bool = false, settings: PlayerSettings = PlayerSettings()) {
        self.id = id
        self.character = character
        self.team = team
        self.bot = bot
        self.name = name ?? Characters.get(character).en
        self.hebrew = hebrew
        self.settings = settings
    }
}

struct Choice: Equatable {
    var index: Int
    var text: String
    var position: V
    var color: Int
}

struct AnswerRecord: Equatable {
    let questionId: String
    let correct: Bool
    let hinted: Bool
    let answer: String
    let decisionElapsedSeconds: Double
}

struct PaintMark: Equatable {
    let color: Int
    let u: Double
    let v: Double
}

struct Feedback: Equatable {
    let questionId: String
    let answer: String
    let explanation: String
    let correct: Bool
    let expires: Double
}

final class SplashActor {
    let member: Member
    var position: V
    let profile: LearningProfile
    var velocity = V(0, 0)
    var travelDistance = 0.0
    var travelDirection = V(0, 0)
    var runBlend = 0.0
    var throwPower = 1.0
    var aimDistance = 0.0
    var botEvadeReady = 0.0
    var settings: PlayerSettings
    var facing = V(0, 1)
    var walkTarget: V? = nil
    var autoPickupQuestion = ""
    var autoPickupIndex = -1
    var publicHeldColor = 5
    var direction = V(0, -1)
    var move = V(0, 0)
    var held: Int? = nil
    var height = 0.0
    var verticalSpeed = 0.0
    var crouchUntil = 0.0
    var cleanUntil = 0.0
    var shieldUntil = 0.0
    var recoveryUntil = 0.0
    var windupAt = -99.0
    var throwAt = -99.0
    var pickupAt = -99.0
    var hitAt = -99.0
    var gait = 0.0
    var score = 0
    var hits = 0
    var misses = 0
    var sequence = 0
    var questionAt = 0.0
    var pickupSeconds = 0.0
    var hinted = false
    var question: Question? = nil
    var choices: [Choice] = []
    var feedback: Feedback? = nil
    var paint: [PaintMark] = []
    var answers: [AnswerRecord] = []
    var nextBotThink = 0.0
    var botChoice: Int? = nil
    /// Passing challenges: this actor holds the pass ball.
    var passBall = false
    /// Wall battles ("3 hits · 8-second rest"): hits since the last rest.
    var teamHitCount = 0
    /// The height a wall, pass or drill throw aims at (nil for the usual arcs).
    var aimHeight: Double? = nil
    /// Wall battles ("Slow down"): when each slowing hit wears off.
    var slowHits: [Double] = []
    var botThreatId = ""
    var botReactAt = 0.0
    var botDodge = false
    var botEvadeUntil = 0.0
    var botEvade = V(0, 0)

    init(member: Member, position: V, profile: LearningProfile = LearningProfile()) {
        self.member = member
        self.position = position
        self.profile = profile
        self.settings = member.settings
    }
}

struct Shot {
    let id: String
    let owner: String
    let questionId: String
    var answer: String
    var explanation: String
    let color: Int
    var position: V
    var height: Double
    let velocity: V
    var vz: Double
    var age: Double = 0
}

struct Burst {
    let id: String
    let owner: String
    let questionId: String
    let position: V
    let height: Double
    let color: Int
    let at: Double
    let hit: String?
}

struct MatchResult: Equatable {
    let id: String
    let winners: [String]
    let scores: [String: Int]
    let teamScores: [Int]
    let draw: Bool
    let elapsed: Double
}

enum Command: Equatable {
    case move(V)
    case aim(V)
    case walkTo(V, questionId: String = "", index: Int = -1)
    case shootAt(String)
    /// Android `Command.PaintAt(wall, u, v)` (wire type "paintAt").
    case paintAt(wall: Int, u: Double, v: Double)
    /// Android `Command.DrillAim(x, height)` (wire type "drillAim").
    case drillAim(x: Double, height: Double)
    case pickup(questionId: String, index: Int)
    /// Android `Command.Throw` (wire type "throw").
    case throwBalloon
    case jump
    case crouch
    case hint
}

final class SplashEngine {
    let members: [Member]
    let mode: GameMode
    let topic: Topic
    let seed: Int64
    let config: SplashConfig
    let hebrew: Bool
    let profiles: [String: LearningProfile]
    let matchId: String
    let random: KotlinRandom
    /// Android `paintSession`: walls, catches and target points of challenges and wall battles.
    let paintSession: PaintSession
    /// Android `drill`: the defending or aiming drill of a journey challenge.
    let drill: SplashDrillSession?
    private var questionSalt: Int64
    var actors: [SplashActor]
    var shots: [Shot] = []
    var bursts: [Burst] = []
    var teamScores: [Int] = [0, 0]
    private(set) var time: Double = 0
    private(set) var result: MatchResult? = nil
    var paused = false
    var practice = false
    private var serial: Int64 = 0
    private var consumedOrder: [String] = []
    private var consumedSet = Set<String>()
    var onEvent: ((String, String) -> Void)?

    /// Android `require` on the roster: 2-6 unique members; teams are 2v2 or 3v3.
    static func validRoster(_ members: [Member], _ mode: GameMode) -> Bool {
        guard members.count >= 2 && members.count <= 6 else { return false }
        guard Set(members.map { $0.id }).count == members.count else { return false }
        if mode == .teams {
            guard members.count == 4 || members.count == 6 else { return false }
            let half = members.count / 2
            return members.filter { $0.team == 0 }.count == half && members.filter { $0.team == 1 }.count == half
        }
        return true
    }

    init(members: [Member], mode: GameMode = .solo, topic: Topic = .math, seed: Int64 = 1,
         config: SplashConfig = SplashConfig(), hebrew: Bool = false,
         profiles: [String: LearningProfile] = [:], matchId: String? = nil) {
        precondition(SplashEngine.validRoster(members, mode), "Invalid Splash roster")
        self.members = members
        self.mode = mode
        self.topic = topic
        self.seed = seed
        self.config = config
        self.hebrew = hebrew
        self.profiles = profiles
        self.matchId = matchId ?? "local-\(seed)"
        self.random = KotlinRandom(seed: seed)
        self.paintSession = PaintSession(config, hebrew)
        self.drill = config.challenge?.drill.map { SplashDrillSession($0, config) }
        self.questionSalt = Int64.random(in: Int64.min...Int64.max)
        var created: [SplashActor] = []
        for (i, m) in members.enumerated() {
            let position = V(config.width * (0.18 + Double(i % 3) * 0.32), config.depth * (i < 3 ? 0.73 : 0.27))
            created.append(SplashActor(member: m, position: position, profile: profiles[m.id] ?? LearningProfile()))
        }
        self.actors = created
        let humans = members.filter { !$0.bot }
        let botSettings = PlayerSettings.bots((humans.isEmpty ? members : humans).map { $0.settings })
        for a in actors {
            if a.member.bot {
                a.settings = botSettings
            } else if topic != .math && a.settings.subjects == [.math] {
                a.settings.subjects = topic == .mixed ? [.math, .english, .world] : [topic]
            }
            nextQuestion(a)
        }
        if paintSession.passing && actors.count >= 2 {
            actors[0].position = V(config.width / 2, config.depth * 0.68)
            actors[1].position = V(config.width / 2, config.depth * 0.28)
            actors[1].held = 0
            actors[1].passBall = true
            actors[1].nextBotThink = 3.0
        }
        drill?.prepare(self)
    }

    /// The team index a paint counter uses (Kotlin indexes its two-entry arrays with the team directly).
    private func team(_ a: SplashActor) -> Int { return a.member.team == 1 ? 1 : 0 }

    func questionSecret() -> Int64 { return questionSalt }
    func restoreQuestionSecret(_ value: Int64) { questionSalt = value }

    func loadProfile(_ id: String, _ profile: LearningProfile) {
        guard let a = actor(id) else { return }
        for (skill, state) in profile.skills { a.profile.skills[skill] = state }
        a.sequence = 0
        nextQuestion(a)
    }

    func restoreClock(_ value: Double) { time = value }
    func restoreResult(_ value: MatchResult?) { result = value }
    func serialState() -> Int64 { return serial }
    func consumedState() -> [String] { return consumedOrder }

    func restoreSerial(_ value: Int64, _ ids: [String]) {
        serial = value
        consumedOrder = []
        consumedSet = []
        for id in ids where !consumedSet.contains(id) {
            consumedOrder.append(id)
            consumedSet.insert(id)
        }
    }

    func actor(_ id: String) -> SplashActor? { return actors.first { $0.member.id == id } }
    func privateQuestion(_ id: String) -> Question? { return actor(id)?.question }

    private func nextSerial() -> Int64 {
        serial += 1
        return serial
    }

    @discardableResult
    func command(_ id: String, _ eventId: String, _ cmd: Command) -> Bool {
        let blank = eventId.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        if result != nil || paused || blank || eventId.utf16.count > 120 || consumedSet.contains(eventId) { return false }
        guard let a = actor(id) else { return false }
        if config.wallBattle && time < a.cleanUntil { return false }
        if config.challenge == .target && paintSession.throwsTaken[team(a)] >= 10 && cmd == .throwBalloon { return false }
        if consumedOrder.count > 8192 {
            let first = consumedOrder.removeFirst()
            consumedSet.remove(first)
        }
        consumedOrder.append(eventId)
        consumedSet.insert(eventId)
        if !a.member.bot, let drill, !drill.allows(cmd) { return false }
        switch cmd {
        case .drillAim(let x, let aimHeight):
            guard let d = drill else { return false }
            if !d.spec.aiming || a.held == nil || !x.isFinite || !aimHeight.isFinite { return false }
            let target = d.target
            let delta = V(min(max(x, 0.5), config.width - 0.5), target.y) - a.position
            a.direction = delta.unit()
            a.facing = a.direction
            a.aimDistance = delta.length()
            a.aimHeight = min(max(aimHeight, 0.1), 5.0)
            a.throwPower = 1.0
        case .move(let vector):
            if !vector.x.isFinite || !vector.y.isFinite { return false }
            a.walkTarget = nil
            a.autoPickupIndex = -1
            a.move = vector.length() > 1 ? vector.unit() : vector
            if a.move.length() > 0.05 { a.facing = a.move.unit() }
        case .aim(let vector):
            a.aimHeight = nil
            if !vector.x.isFinite || !vector.y.isFinite || vector.length() < 0.01 { return false }
            a.direction = vector.unit()
            a.facing = a.direction
            // Standard (EASY) carries the tapped distance; Hard (STANDARD) carries swipe power. A ground drill aims
            // at the tapped island.
            let groundDrill = drill?.spec.ground == true
            a.aimDistance = (a.settings.throwing == .easy || groundDrill) ? min(vector.length(), 55.0) : 0.0
            if groundDrill { a.aimHeight = 0.1 }
            a.throwPower = a.settings.throwing == .standard ? min(max(vector.length(), 0.72), 1.55) : 1.0
            if a.held != nil { a.windupAt = time }
        case .walkTo(let position, let questionId, let index):
            if !position.x.isFinite || !position.y.isFinite { return false }
            if index >= 0 {
                if a.settings.walk != .easy || a.question?.id != questionId || a.held != nil { return false }
                guard let choice = a.choices.first(where: { $0.index == index }) else { return false }
                a.walkTarget = choice.position
                a.autoPickupQuestion = questionId
                a.autoPickupIndex = index
            } else {
                a.walkTarget = clamp(position, a)
                a.autoPickupIndex = -1
            }
        case .paintAt(let wallIndex, let u, let v):
            guard wallIndex >= 0 && wallIndex < paintSession.walls.count else { return false }
            let wall = paintSession.walls[wallIndex]
            if a.held == nil || !u.isFinite || !v.isFinite || u < 0.0 || u > 1.0 || v < 0.0 || v > 1.0 { return false }
            if config.wallBattle && wallIndex == a.member.team { return false }
            let delta = wall.world(u, v) - a.position
            a.direction = delta.unit()
            a.facing = a.direction
            a.aimDistance = delta.length()
            a.aimHeight = v * wall.height
            a.throwPower = 1.0
        case .shootAt(let targetId):
            a.aimHeight = nil
            if (a.settings.throwing != .easy && !paintSession.passing) || a.held == nil { return false }
            guard let target = actor(targetId) else { return false }
            if target === a || (mode == .teams && target.member.team == a.member.team) { return false }
            a.direction = (target.position - a.position).unit()
            a.aimDistance = (target.position - a.position).length()
            a.throwPower = 1.0
            a.facing = a.direction
            if paintSession.passing { a.aimHeight = 1.05 }
            return command(id, eventId + "-throw", .throwBalloon)
        case .pickup(let questionId, let index):
            if a.held != nil || a.question?.id != questionId || time < a.cleanUntil || time < a.recoveryUntil { return false }
            guard let c = a.choices.first(where: { $0.index == index }) else { return false }
            if (c.position - a.position).length() > config.pickupRadius { return false }
            a.held = c.index
            a.autoPickupIndex = -1
            a.pickupAt = time
            a.pickupSeconds = time - a.questionAt
            onEvent?("pickup", id)
        case .throwBalloon:
            if time < a.cleanUntil || time < a.recoveryUntil { return false }
            if paintSession.passing {
                if !a.passBall || a.held == nil { return false }
                let direction = a.direction.unit()
                let shotId = "\(matchId)-pass\(nextSerial())"
                shots.append(Shot(id: shotId, owner: id, questionId: "pass", answer: "", explanation: "", color: 4,
                                  position: a.position + direction * 0.42, height: 1.15, velocity: direction * throwSpeed(a),
                                  vz: launchLift(a)))
                a.held = nil
                a.passBall = false
                a.throwAt = time
                a.aimHeight = nil
                onEvent?("throw", id)
                return true
            }
            guard let held = a.held, let q = a.question else { return false }
            guard let c = a.choices.first(where: { $0.index == held }) else { return false }
            let correct = c.text == q.answer
            if config.challenge?.isTarget == true { paintSession.throwsTaken[team(a)] += 1 }
            a.answers.append(AnswerRecord(questionId: q.id, correct: correct, hinted: a.hinted, answer: q.answer,
                                          decisionElapsedSeconds: a.pickupSeconds))
            a.profile.record(q.skill, correct: correct, hint: a.hinted)
            a.feedback = Feedback(questionId: q.id, answer: q.answer, explanation: q.explanation(a.member.hebrew),
                                  correct: correct, expires: time + (correct ? 2.5 : 6.0))
            a.held = nil
            a.throwAt = time
            a.facing = a.direction
            if correct {
                let direction = a.direction.unit()
                let shotId = "\(matchId)-s\(nextSerial())"
                let launchHeight = a.height + (time < a.crouchUntil ? 0.48 : 1.15)
                shots.append(Shot(id: shotId, owner: id, questionId: q.id, answer: q.answer,
                                  explanation: q.explanation(a.member.hebrew), color: c.color,
                                  position: a.position + direction * 0.42, height: launchHeight,
                                  velocity: direction * throwSpeed(a), vz: launchLift(a)))
                onEvent?("throw", id)
                a.aimHeight = nil
                nextQuestion(a)
            } else {
                burst(id, q.id, a.position, a.height + 0.9, c.color, id)
                applyPaint(a, c.color, false)
                a.score = max(a.score - config.mistakePoints, 0)
                a.recoveryUntil = time + config.mistakeRecovery
                onEvent?("wrong", id)
                nextQuestion(a)
            }
        case .jump:
            let ground = a.settings.arena == .andromeda ? 0.15 : 0.01
            if a.height < ground && time >= a.cleanUntil {
                a.verticalSpeed = config.jumpVelocity
                a.crouchUntil = 0
                onEvent?("jump", id)
            }
        case .crouch:
            if time >= a.cleanUntil {
                a.crouchUntil = time + config.crouchSeconds
                onEvent?("crouch", id)
            }
        case .hint:
            a.hinted = true
            guard let q = a.question else { return false }
            a.feedback = Feedback(questionId: q.id, answer: q.answer, explanation: q.explanation(a.member.hebrew),
                                  correct: false, expires: time + 3)
        }
        return true
    }

    private func nextQuestion(_ a: SplashActor) {
        a.sequence += 1
        let mixed = seed ^ questionSalt ^ Int64(a.member.id.javaHashCode) ^ (Int64(a.sequence) &* 0x9E37_79B9)
        let r = KotlinRandom(seed: mixed)
        var selectedTopics = a.settings.orderedSubjects
        if selectedTopics.isEmpty { selectedTopics = [.math] }
        let selectedTopic = selectedTopics[(a.sequence - 1) % selectedTopics.count]
        let s = QuestionBank.chooseSkill(a.profile, selectedTopic, r, a.sequence)
        let previousLevel = a.profile.state(s).level
        // Review sometimes steps one level back; no timer pressure changes mastery.
        let level = a.sequence % 7 == 0 ? max(previousLevel - 1, 0) : previousLevel
        let question = QuestionBank.generate("\(a.member.id)-q\(a.sequence)", s, level, r, hebrew: a.member.hebrew)
        a.question = question
        let colors = Array(Array(0...5).kotlinShuffled(r).prefix(4))
        let spots = GroundBalloons.place(config.width, config.depth, a.position, practice || a.settings.balloons == .onePlace,
                                         practice ? 1.8 : config.answerRing, r)
        var made: [Choice] = []
        for (i, text) in question.options.enumerated() where i < spots.count && i < colors.count {
            made.append(Choice(index: i, text: text, position: spots[i], color: colors[i]))
        }
        a.choices = made
        a.questionAt = time
        a.hinted = false
        a.botChoice = nil
        let skill = Characters.get(a.member.character).skill
        a.nextBotThink = time + (config.botThinkMin + (1 - skill) * (config.botThinkMax - config.botThinkMin) + r.nextDouble() * 0.6) *
            config.difficulty.think
    }

    func tick(_ rawDt: Double) {
        if paused || result != nil { return }
        // Bounded fixed-step integration avoids tunnelling and time jumps after background.
        var left = min(max(rawDt, 0.0), 0.10)
        while left > 0 {
            let dt = min(left, 1.0 / 120)
            step(dt)
            left -= dt
        }
    }

    private func step(_ dt: Double) {
        if result != nil { return }
        time += dt
        drill?.step(self)
        for a in actors {
            a.slowHits.removeAll { $0 <= time }
            if config.wallBattle && a.cleanUntil > 0 && time >= a.cleanUntil {
                a.paint.removeAll()
                a.teamHitCount = 0
                a.cleanUntil = 0
                a.slowHits.removeAll()
                a.shieldUntil = time + config.returnShield
            }
            if a.member.bot && !practice && drill == nil { bot(a) }
            if let target = a.walkTarget {
                let delta = target - a.position
                let pickup = a.autoPickupIndex >= 0 && a.autoPickupQuestion == a.question?.id
                let distance = pickup ? config.pickupRadius * 0.75 : 0.10
                if delta.length() <= distance {
                    a.move = V(0, 0)
                    a.walkTarget = nil
                    if pickup {
                        let index = a.autoPickupIndex
                        a.autoPickupIndex = -1
                        command(a.member.id, "walk-pickup-\(nextSerial())", .pickup(questionId: a.autoPickupQuestion, index: index))
                    }
                } else {
                    a.move = delta.unit() * min(1.0, delta.length() / (config.moveSpeed * 0.10))
                }
            }
            if time >= a.cleanUntil && time >= a.recoveryUntil {
                let before = a.position
                a.position = clamp(a.position + PlayFeel.advance(a, movementSpeed(a), dt), a)
                if a.move.length() > 0.05 && time - a.windupAt > 0.35 && time - a.throwAt > 0.3 { a.facing = a.move.unit() }
                if a.settings.arena == .andromeda && a.move.length() > 0.1 && a.height < 0.005 && a.verticalSpeed <= 0 && time >= a.crouchUntil {
                    a.verticalSpeed = 0.95
                }
                // Distance travelled drives the four-frame locomotion loop.
                a.gait += (a.position - before).length() * 2.7
            }
            if a.height > 0 || a.verticalSpeed > 0 {
                a.height += a.verticalSpeed * dt
                a.verticalSpeed -= a.settings.arena == .andromeda ? a.settings.jumpGravity * dt : config.jumpGravity * dt
                if a.height <= 0 {
                    a.height = 0
                    a.verticalSpeed = 0
                }
            }
            if !config.wallBattle && a.paint.count >= config.paintLayers && time >= a.cleanUntil && a.cleanUntil > 0 {
                a.paint.removeAll()
                a.cleanUntil = 0
                a.shieldUntil = time + config.returnShield
            }
        }
        // Soft physical separation; all participants remain independently active.
        for i in 0..<actors.count {
            for j in (i + 1)..<max(i + 1, actors.count) {
                let a = actors[i]
                let b = actors[j]
                let d = a.position - b.position
                let n = d.length()
                if n > 0 && n < config.personalSpace {
                    let push = d.unit() * ((config.personalSpace - n) * 0.5)
                    a.position = clamp(a.position + push, a)
                    b.position = clamp(b.position - push, b)
                }
            }
        }
        var index = 0
        while index < shots.count {
            var s = shots[index]
            let old = s.position
            let oldH = s.height
            s.position = s.position + s.velocity * dt
            s.height += s.vz * dt
            let factor = actor(s.owner)?.settings.projectileGravityFactor ?? 1.0
            s.vz -= config.gravity * factor * dt
            s.age += dt
            drill?.flight(self, s, old, oldH)
            var wallHit = false
            for wall in paintSession.walls {
                let dy = s.position.y - old.y
                if abs(dy) < 0.000001 { continue }
                let t = (wall.y - old.y) / dy
                if t < 0.0 || t > 1.0 { continue }
                let impact = old + (s.position - old) * t
                let z = oldH + (s.height - oldH) * t
                let uv = wall.uv(impact.x, z)
                if uv.x >= 0.0 && uv.x <= 1.0 && uv.y >= 0.0 && uv.y <= 1.0 {
                    if let owner = actor(s.owner) { paintSession.hit(wall.id, uv.x, uv.y, owner.member.team, !owner.member.bot) }
                    s.position = impact
                    s.height = z
                    explode(s, nil)
                    shots.remove(at: index)
                    wallHit = true
                    onEvent?("paint", s.owner)
                    break
                }
            }
            if wallHit { continue }
            var target: SplashActor? = nil
            var nearest = Double.greatestFiniteMagnitude
            for a in actors {
                if (paintSession.active && !config.wallBattle) || (drill != nil && a.member.bot) { continue }
                if a.member.id == s.owner || time < a.shieldUntil || time < a.cleanUntil { continue }
                guard let owner = actor(s.owner) else { continue }
                if mode == .teams && !config.friendlyFire && a.member.team == owner.member.team { continue }
                let line = s.position - old
                let length2 = line.x * line.x + line.y * line.y
                let toActor = a.position - old
                let t = length2 < 0.00001 ? 0.0 : min(max((toActor.x * line.x + toActor.y * line.y) / length2, 0.0), 1.0)
                let h = oldH + (s.height - oldH) * t
                let top = a.height + (time < a.crouchUntil ? config.crouchHeight : config.standingHeight)
                let close = (a.position - (old + line * t)).length() <= config.actorRadius + 0.14
                if close && h + 0.12 >= a.height && h - 0.12 <= top && t < nearest {
                    target = a
                    nearest = t
                }
            }
            if let catcher = target, paintSession.passing {
                if s.vz < 0 && s.height >= 0.3 && s.height <= 1.85 {
                    catcher.held = 0
                    catcher.passBall = true
                    catcher.pickupAt = time
                    catcher.nextBotThink = time + (config.challenge == .passQuick ? 1.2 : 2.0)
                    if !catcher.member.bot { paintSession.catches += 1 }
                    shots.remove(at: index)
                    onEvent?("pickup", catcher.member.id)
                    continue
                }
            } else if let hitTarget = target {
                if let owner = actor(s.owner) {
                    if !config.wallBattle || config.hitEffect != .cosmetic { owner.hits += 1 }
                    if !config.wallBattle { owner.score += 1 }
                    if mode == .teams && !config.wallBattle && owner.member.team >= 0 && owner.member.team < teamScores.count {
                        teamScores[owner.member.team] += 1
                    }
                }
                drill?.hit(self, s, hitTarget)
                applyPaint(hitTarget, s.color)
                explode(s, hitTarget.member.id)
                shots.remove(at: index)
                onEvent?("hit", hitTarget.member.id)
                continue
            } else if s.height <= 0.1 || outsideShot(s) || s.age > 6 {
                drill?.ended(self, s)
                if paintSession.passing { paintSession.failed = true }
                if let owner = actor(s.owner) { owner.misses += 1 }
                explode(s, nil)
                shots.remove(at: index)
                continue
            }
            shots[index] = s
            index += 1
        }
        bursts.removeAll { time - $0.at > 7 }
        if paintSession.active {
            for team in 0...1 { teamScores[team] = paintSession.score(team) }
            let fixedDone = config.challenge == .target && paintSession.throwsTaken.allSatisfy { $0 >= 10 } && shots.isEmpty
            let timedDone = (config.wallBattle || config.challenge == .timedTarget || config.challenge == .race) && time >= config.duration
            if !practice && (paintSession.failed || paintSession.complete() || paintSession.fullWinner() != nil || fixedDone || timedDone) {
                finish()
            }
        }
        if paintSession.passing && !practice && (paintSession.failed || paintSession.catches >= paintSession.catchGoal) { finish() }
        if let drill, !practice && (drill.won || drill.failed) { finish() }
        if drill == nil && !paintSession.active && !paintSession.passing && !practice {
            let timeUp = time >= config.duration
            let soloDone = mode == .solo && actors.contains { $0.score >= config.target }
            let teamDone = mode == .teams && teamScores.contains { $0 >= config.teamTarget }
            if timeUp || soloDone || teamDone { finish() }
        }
    }

    private func clamp(_ p: V, _ a: SplashActor) -> V {
        if paintSession.active {
            return V(min(max(p.x, 0.8), config.width - 0.8), min(max(p.y, 3.0), config.depth - 3.0))
        }
        if a.settings.court {
            return V(min(max(p.x, 0.55), config.width - 0.55), min(max(p.y, 0.8), config.depth - 0.65))
        }
        return V(min(max(p.x, -0.75), config.width + 0.75), min(max(p.y, -0.65), config.depth + 0.9))
    }

    private func outsideShot(_ s: Shot) -> Bool {
        let margin = actor(s.owner)?.settings.court != false ? 0.0 : 6.0
        return s.position.x < -margin || s.position.y < -margin || s.position.x > config.width + margin || s.position.y > config.depth + margin
    }

    func resetPracticeQuestion(_ id: String) {
        guard practice, let a = actor(id) else { return }
        a.held = nil
        a.walkTarget = nil
        a.move = V(0, 0)
        nextQuestion(a)
    }

    private func applyPaint(_ a: SplashActor, _ color: Int, _ opponentHit: Bool = true) {
        if config.wallBattle {
            let u = 0.25 + random.nextDouble() * 0.5
            let v = 0.28 + random.nextDouble() * 0.38
            a.paint.append(PaintMark(color: color, u: u, v: v))
            a.hitAt = time
            if opponentHit {
                switch config.hitEffect {
                case .cosmetic:
                    break
                case .rest:
                    a.teamHitCount += 1
                    if a.teamHitCount >= 3 {
                        a.cleanUntil = time + 8.0
                        a.move = V(0, 0)
                        a.velocity = V(0, 0)
                        a.walkTarget = nil
                        a.held = nil
                    }
                case .slow:
                    if a.slowHits.filter({ $0 > time }).count < 5 { a.slowHits.append(time + 30.0) }
                }
            }
            while a.paint.count > 5 { a.paint.removeFirst() }
            return
        }
        let u = 0.25 + random.nextDouble() * 0.5
        let v = 0.28 + random.nextDouble() * 0.38
        a.paint.append(PaintMark(color: color, u: u, v: v))
        a.hitAt = time
        if a.paint.count >= config.paintLayers {
            a.cleanUntil = time + config.cleanSeconds
            a.move = V(0, 0)
        }
    }

    private func burst(_ owner: String, _ questionId: String, _ p: V, _ h: Double, _ color: Int, _ hit: String?) {
        bursts.append(Burst(id: "\(matchId)-b\(nextSerial())", owner: owner, questionId: questionId, position: p,
                            height: h, color: color, at: time, hit: hit))
    }

    private func explode(_ s: Shot, _ hit: String?) {
        burst(s.owner, s.questionId, s.position, max(s.height, 0.0), s.color, hit)
        // Feedback references its original question; never rewrites a newer question.
        guard let owner = actor(s.owner) else { return }
        var keepWrong = false
        if let f = owner.feedback { keepWrong = !f.correct && time < f.expires }
        if !keepWrong {
            owner.feedback = Feedback(questionId: s.questionId, answer: s.answer, explanation: s.explanation,
                                      correct: true, expires: time + 1.8)
        }
    }

    /// Avatar speed stars change house players' movement; humans move at the full speed.
    func movementSpeed(_ a: SplashActor) -> Double {
        let bot = a.member.bot ? Characters.get(a.member.character).qualities.movementFactor * (practice ? 1.0 : config.difficulty.speed) : 1.0
        return config.moveSpeed * bot * (1.0 - 0.11 * Double(a.slowHits.filter { $0 > time }.count))
    }

    /// Avatar power scales the release speed of every throw (human or house player).
    func throwSpeed(_ a: SplashActor) -> Double {
        if paintSession.passing && a.aimDistance > 1 { return (a.aimDistance - 0.42) / 2.4 }
        return config.throwSpeed * Characters.get(a.member.character).qualities.throwFactor * a.throwPower
    }

    /// Standard throwing lands at the tapped distance; Hard and house throws keep the fixed lift.
    func launchLift(_ a: SplashActor) -> Double {
        if let height = a.aimHeight {
            let t = max(max(a.aimDistance - 0.42, 0.25) / throwSpeed(a), 0.06)
            return (height - (a.height + (time < a.crouchUntil ? 0.48 : 1.15)) + 0.5 * config.gravity * a.settings.projectileGravityFactor * t * t) / t
        }
        if a.settings.throwing == .easy && a.aimDistance > 0.05 {
            return PlayFeel.lift(a.aimDistance, throwSpeed(a), a.height + (time < a.crouchUntil ? 0.48 : 1.15),
                                 config.gravity * a.settings.projectileGravityFactor)
        }
        return config.launchLift
    }

    private func threatens(_ s: Shot, _ a: SplashActor) -> Bool {
        if s.owner == a.member.id { return false }
        if !(mode == .solo || actor(s.owner)?.member.team != a.member.team) { return false }
        if (s.position - a.position).length() >= 1.8 { return false }
        let d = s.velocity.unit()
        let n = (a.position - s.position).unit()
        return d.x * n.x + d.y * n.y > 0.72
    }

    private func bot(_ a: SplashActor) {
        if time < a.cleanUntil || time < a.recoveryUntil { return }
        if paintSession.passing {
            a.move = V(0, 0)
            if a.passBall && time >= a.nextBotThink, let human = actors.first(where: { !$0.member.bot }) {
                let precision = Characters.get(a.member.character).qualities.precision
                let extra: Double = config.challenge == .passWide ? 0.75 : (config.challenge == .passQuick ? 1.0 : 0.0)
                let spread = min(0.25 + extra + Double(5 - precision) * 0.38 + Double(config.chapter) * 0.07, 2.2)
                let target = V(min(max(human.position.x + (random.nextDouble() * 2 - 1) * spread, 2.0), config.width - 2),
                               min(max(human.position.y, 3.0), config.depth - 3))
                let delta = target - a.position
                a.direction = delta.unit()
                a.facing = a.direction
                a.aimDistance = delta.length()
                a.aimHeight = 1.05
                command(a.member.id, "pass-\(nextSerial())", .throwBalloon)
            }
            return
        }
        if paintSession.cooperative {
            a.move = V(0, 0)
            a.position = V(config.width * 0.10, config.depth * 0.36)
            let precision = Characters.get(a.member.character).qualities.precision
            // A partner demonstrates and helps with part of the wall; the child completes it.
            if time >= a.nextBotThink && paintSession.coverage(0) < 0.35 {
                let wall = paintSession.walls[0]
                let open = wall.cells.indices.filter { paintSession.targetMask[$0] && wall.cells[$0] != 0 }
                if !open.isEmpty {
                    let pt = wall.at(open[random.nextInt(open.count)])
                    let drift = Double(5 - precision) * 0.018
                    a.held = a.choices.first(where: { $0.text == a.question?.answer })?.index
                    let u = min(max(pt.x + (random.nextDouble() * 2 - 1) * drift, 0.01), 0.99)
                    let v = min(max(pt.y + (random.nextDouble() * 2 - 1) * drift, 0.01), 0.99)
                    command(a.member.id, "guide-aim-\(nextSerial())", .paintAt(wall: 0, u: u, v: v))
                    command(a.member.id, "guide-throw-\(nextSerial())", .throwBalloon)
                }
                a.nextBotThink = time + 6.0 + Double(5 - precision) * 0.7
            }
            return
        }
        if config.challenge == .target && paintSession.throwsTaken[team(a)] >= 10 {
            a.move = V(0, 0)
            return
        }
        let qualities = Characters.get(a.member.character).qualities
        let threat = shots.first { threatens($0, a) }
        // One defence decision per incoming shot (reflex stars), not one per frame.
        if let threat = threat, a.botThreatId != threat.id {
            a.botThreatId = threat.id
            a.botReactAt = time + qualities.reactionSeconds * config.difficulty.think
            a.botDodge = time >= a.botEvadeReady && random.nextDouble() < qualities.dodgeChance
        }
        if let threat = threat, a.botDodge, time >= a.botReactAt {
            a.botDodge = false
            a.botEvadeReady = time + 1.3 + Double(5 - qualities.reflexes) * 0.18
            let impact = (threat.position - a.position).length() / threat.velocity.length()
            let projectedHeight = threat.height + threat.vz * impact - 0.5 * config.gravity * impact * impact
            // A stance or a sidestep, not both.
            if random.nextDouble() < 0.55 {
                if projectedHeight > config.crouchHeight + 0.15 {
                    command(a.member.id, "bot-\(nextSerial())", .crouch)
                } else if a.height < 0.01 {
                    command(a.member.id, "bot-\(nextSerial())", .jump)
                }
            } else {
                let perpendicular = V(-threat.velocity.y, threat.velocity.x).unit()
                a.botEvade = perpendicular * (a.position.x > config.width / 2 ? -1.0 : 1.0)
                a.botEvadeUntil = time + 0.30
            }
        }
        if a.held == nil {
            if time < a.nextBotThink {
                a.move = V(0, 0)
            } else {
                guard let q = a.question, !a.choices.isEmpty else { return }
                if a.botChoice == nil {
                    // Knowledge stars: the chance that the first choice is correct (rating / 7).
                    if random.nextDouble() < qualities.correctAnswerProbability {
                        a.botChoice = a.choices.first(where: { $0.text == q.answer })?.index
                    } else {
                        let wrong = a.choices.filter { $0.text != q.answer }
                        if wrong.isEmpty { return }
                        a.botChoice = wrong[random.nextInt(wrong.count)].index
                    }
                }
                guard let choice = a.choices.first(where: { $0.index == a.botChoice }) else { return }
                let d = choice.position - a.position
                if d.length() <= config.pickupRadius * 0.8 {
                    a.move = V(0, 0)
                    command(a.member.id, "bot-\(nextSerial())", .pickup(questionId: q.id, index: choice.index))
                    a.nextBotThink = time + (0.55 + random.nextDouble() * 0.4) * config.difficulty.think
                } else {
                    a.move = d.unit()
                }
            }
        } else if paintSession.active {
            a.move = V(0, 0)
            if time >= a.nextBotThink {
                let wall = paintSession.walls[config.wallBattle ? 1 - team(a) : 0]
                let isTarget = config.challenge?.isTarget == true
                let spot: V
                if isTarget {
                    let spread = 0.58 - Double(qualities.precision) * 0.085
                    let x = 0.5 + (random.nextDouble() - 0.5) * spread
                    let y = 0.5 + (random.nextDouble() - 0.5) * spread
                    spot = V(x, y)
                } else {
                    let open = wall.cells.indices.filter { wall.cells[$0] != a.member.team }
                    spot = open.isEmpty ? V(0.5, 0.5) : wall.at(open[random.nextInt(open.count)])
                }
                // A nearby rival is an occasional tactical choice; painting remains the primary objective.
                let rival = actors.first { $0.member.team != a.member.team && ($0.position - a.position).length() < 5 }
                if config.wallBattle && config.hitEffect != .cosmetic, let rival, random.nextDouble() < 0.18 {
                    a.direction = (rival.position - a.position).unit()
                    a.aimHeight = nil
                } else {
                    let du = isTarget ? 0.0 : (random.nextDouble() - 0.5) * Double(5 - qualities.precision) * 0.04
                    let u = min(max(spot.x + du, 0.01), 0.99)
                    let dv = isTarget ? 0.0 : (random.nextDouble() - 0.5) * Double(5 - qualities.precision) * 0.04
                    let v = min(max(spot.y + dv, 0.01), 0.99)
                    command(a.member.id, "wall-aim-\(nextSerial())", .paintAt(wall: wall.id, u: u, v: v))
                }
                command(a.member.id, "wall-throw-\(nextSerial())", .throwBalloon)
            }
        } else {
            let opponents = actors.filter { other in other !== a && (mode == .solo || other.member.team != a.member.team) }
            // Kotlin `minBy`: the first smallest value wins.
            guard var opponent = opponents.first else { return }
            var best = (opponent.position - a.position).length() + (time < opponent.cleanUntil ? 20.0 : 0.0)
            for candidate in opponents.dropFirst() {
                let value = (candidate.position - a.position).length() + (time < candidate.cleanUntil ? 20.0 : 0.0)
                if best > value {
                    best = value
                    opponent = candidate
                }
            }
            let distance = (opponent.position - a.position).length()
            let predicted = opponent.position + opponent.move * (movementSpeed(opponent) * distance / throwSpeed(a) * qualities.prediction)
            let natural = (predicted - a.position).unit()
            a.direction = natural
            // Sample once on release, not every render/physics frame.
            if time >= a.nextBotThink {
                let radians = (random.nextDouble() * 2 - 1) * qualities.aimErrorDegrees * Double.pi / 180
                a.direction = V(natural.x * cos(radians) - natural.y * sin(radians), natural.x * sin(radians) + natural.y * cos(radians))
                command(a.member.id, "bot-\(nextSerial())", .throwBalloon)
            }
            a.move = distance > throwSpeed(a) * 0.82 ? (opponent.position - a.position).unit() * 0.6 : V(0, 0)
        }
        if time < a.botEvadeUntil { a.move = a.botEvade }
        // Steering leaves room without pushing the human or changing physics for their input.
        var avoidance = V(0, 0)
        let space = config.difficulty.space
        for other in actors where other !== a {
            let away = a.position - other.position
            let distance = away.length()
            if distance > 0.001 && distance < space { avoidance = avoidance + away.unit() * ((space - distance) / space) }
        }
        let steer = a.move + avoidance * 1.4
        a.move = steer.length() > 1 ? steer.unit() : steer
    }

    func finish() {
        if result != nil || practice { return }
        var winners: [String] = []
        let human = actors.first { !$0.member.bot }
        if let drill {
            if drill.won, let human { winners = [human.member.id] }
        } else if paintSession.passing {
            if !paintSession.failed && paintSession.catches >= paintSession.catchGoal, let human { winners = [human.member.id] }
        } else if paintSession.active {
            let winner: Int?
            if paintSession.cooperative {
                winner = (paintSession.complete() && !paintSession.failed) ? 0 : 1
            } else {
                winner = paintSession.fullWinner() ?? paintSession.winner()
            }
            winners = actors.filter { $0.member.team == winner }.map { $0.member.id }
        } else if mode == .teams {
            if teamScores[0] != teamScores[1] {
                let team = teamScores[0] > teamScores[1] ? 0 : 1
                winners = actors.filter { $0.member.team == team }.map { $0.member.id }
            }
        } else {
            let best = actors.map { $0.score }.max() ?? 0
            let leaders = actors.filter { $0.score == best }
            winners = leaders.count > 1 ? [] : leaders.map { $0.member.id }
        }
        var scores: [String: Int] = [:]
        for a in actors { scores[a.member.id] = a.score }
        result = MatchResult(id: matchId, winners: winners, scores: scores, teamScores: teamScores,
                             draw: winners.isEmpty, elapsed: time)
        onEvent?("finish", matchId)
    }
}
