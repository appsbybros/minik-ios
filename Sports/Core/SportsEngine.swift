import Foundation

/// Port of Android core/SportsEngine.kt: the platform-independent authoritative fixed-step
/// simulation shared by Minik Squash and Minik Beach Volley. One event and one score per
/// physical contact; the same constants and the same Kotlin `Random` order as Android, so a
/// checkpoint or an online room continues identically on either platform.
enum Sport: String, KotlinEnum {
    case squash = "SQUASH"
    case volley = "VOLLEY"
}

enum Control: String, KotlinEnum {
    case beginner = "BEGINNER"
    case standard = "STANDARD"
    case pro = "PRO"
}

enum AnswerMode: String, KotlinEnum {
    case serves = "SERVES"
    case everyHit = "EVERY_HIT"
}

enum ServeQuestions: String, KotlinEnum {
    case own = "OWN"
    case fullTime = "FULL_TIME"
    case untilServe = "UNTIL_SERVE"
}

/// Android `AnswerWindow` (a mutable data class shared by reference).
final class AnswerWindow {
    let question: Question
    var remaining: Double
    var open: Bool
    var recorded: Bool
    var selected: Int
    let onServe: Bool

    init(_ question: Question, _ remaining: Double, open: Bool = true, recorded: Bool = false, selected: Int = -1, onServe: Bool = true) {
        self.question = question
        self.remaining = remaining
        self.open = open
        self.recorded = recorded
        self.selected = selected
        self.onServe = onServe
    }
}

enum Phase: String, KotlinEnum {
    case ready = "READY"
    case rally = "RALLY"
    case point = "POINT"
    case finished = "FINISHED"
}

struct Vec: Equatable {
    var x: Double
    var y: Double

    init(_ x: Double = 0.0, _ y: Double = 0.0) {
        self.x = x
        self.y = y
    }

    static func + (a: Vec, b: Vec) -> Vec { return Vec(a.x + b.x, a.y + b.y) }
    static func - (a: Vec, b: Vec) -> Vec { return Vec(a.x - b.x, a.y - b.y) }
    static func * (a: Vec, s: Double) -> Vec { return Vec(a.x * s, a.y * s) }
    static func += (a: inout Vec, b: Vec) { a = a + b }
    static func -= (a: inout Vec, b: Vec) { a = a - b }
    static func *= (a: inout Vec, s: Double) { a = a * s }

    func length() -> Double { return hypot(x, y) }
    func unit() -> Vec { return length() < 0.0001 ? Vec() : self * (1 / length()) }
}

/// Android `SportsConfig` (its `init` requirements are `isValid`; the codec clamps network data).
struct SportsConfig: Equatable {
    var sport: Sport = .squash
    var teamSize: Int = 2
    var target: Int = 11
    var arena: String = "beach"
    var control: Control = .beginner
    var seed: Int = 17
    var tutorial: Bool = false
    var answerMode: AnswerMode = .serves
    var serveQuestions: ServeQuestions = .fullTime
    var answerSeconds: Int = 15
    var questionsEnabled: Bool = true
    var serveControl: Control = .beginner
    var ballStyle: String = "classic"
    var teamColors: [String] = ["aqua", "gold"]
    var houseRoster: [String] = []
    var challengeStep: Int = -1

    var isValid: Bool {
        return (2...3).contains(teamSize) && (3...31).contains(target) && ["beach", "park", "squash"].contains(arena)
            && [5, 10, 15, 30].contains(answerSeconds) && VolleyPalette.ballIds.contains(ballStyle)
            && teamColors.count == 2 && Set(teamColors).count == 2 && teamColors.allSatisfy { VolleyPalette.teamIds.contains($0) }
    }

    var halfWidth: Double { return sport == .squash ? 3.2 : 4.0 }
    var halfDepth: Double { return sport == .squash ? 4.875 : 8.0 }
    var gravity: Double { return sport == .squash ? 8.2 : 7.8 }
    var netHeight: Double { return 2.05 }
}

struct Participant: Equatable {
    let id: String
    let character: String
    let team: Int
    let bot: Bool
    let name: String
    let rankPoints: Int

    init(_ id: String, _ character: String, _ team: Int, _ bot: Bool, _ name: String = "", _ rankPoints: Int = 0) {
        self.id = id
        self.character = character
        self.team = team
        self.bot = bot
        self.name = name
        self.rankPoints = rankPoints
    }
}

/// Android `Athlete` (a mutable data class shared by reference).
final class Athlete {
    let member: Participant
    var p = Vec()
    var velocity = Vec()
    var goal = Vec()
    var facing = Vec(0.0, -1.0)
    var pose = "idle"
    var poseTime = 0.0
    var swing = 0.0
    var jump = 0.0
    var jumpV = 0.0
    var think = 0.0
    var plannedMiss = false
    var chosen = 0
    var aim = Vec()
    var steps = 0.0
    var contacts = 0
    var correct = 0
    var mistakes = 0
    var winners = 0
    var pendingTarget = Vec(0.0, 2.7)
    var pendingPower = 0.5
    var floorShot = false
    var inputUntil = -1.0
    var volleyKind = "auto"
    var volleyAttemptAt = -10.0
    var volleyAttemptShot = -1
    var volleyTriedShot = -1
    var volleyExplicit = false

    init(_ member: Participant) {
        self.member = member
    }

    var character: SportsCharacter { return Characters.get(member.character) }
}

/// Android `SportsBall` (shared by reference).
final class SportsBall {
    var p = Vec()
    var z = 1.0
    var velocity = Vec()
    var vz = 0.0
    var active = false
    var hitter = ""
    var shot = 0
    var bounces = 0
    var front = false
    var scoringChecked = false
    var serve = false
    var previousTeam = -1
    var touches = 0
    var receiver = ""
}

struct GameEvent: Equatable {
    let id: Int
    let type: String
    let player: String
    let detail: String

    init(_ id: Int, _ type: String, _ player: String = "", _ detail: String = "") {
        self.id = id
        self.type = type
        self.player = player
        self.detail = detail
    }
}

final class SportsEngine {
    let config: SportsConfig
    let roster: [Participant]
    let matchId: String
    let random: KotlinRandom
    let players: [Athlete]
    let ball = SportsBall()
    var scores = [0, 0]
    var profiles: [String: LearningProfile]
    var phase: Phase = .ready
    var clock = 0.0
    var phaseTime = 0.0
    var server = 0
    var expected = 0
    var returnTeam = 1
    var winner = -1
    var eventId = 0
    var pointSerial = 0
    var shotSerial = 0
    var sequence = 0
    var reason = "serve"
    var selected = 0
    var countdown = 3.0
    var paused = false
    var question: Question
    var shotQuestion: Question
    var shotChoice = 0
    var answers: [String: AnswerWindow] = [:]
    var serveWindowStarted = false
    var serveElapsed = 0.0
    var serveRequested = false
    var timeScale = 1.0
    var receptionSlowEnabled: [String: Bool]
    var receptionScale = 1.0
    var receptionReceiver = ""
    var receptionStrength = 0.0
    var slowResumeAt = 0.0
    var shotHasQuestion = false
    var shotRecorded = false
    var tutorialStage = 0
    var tutorialComplete = false
    var feedbackEn = ""
    var feedbackHe = ""
    var feedbackUntil = 0.0
    /// Android `ArrayDeque<GameEvent>` (the last 100).
    var events: [GameEvent] = []
    private var accumulator = 0.0
    /// Android `LinkedHashSet` of processed command keys (the oldest leave first after 512).
    private var processedOrder: [String] = []
    private var processedSet = Set<String>()
    private let targets: [Double] = [-2.22, -0.74, 0.74, 2.22]
    private(set) lazy var volley = VolleyPlay(self)
    let practice: CourtPractice?
    var poseStamp = -10.0

    var questionsEnabled: Bool {
        return practice == nil && config.sport == .squash && (config.questionsEnabled || config.tutorial)
    }

    func answerFor(_ id: String) -> AnswerWindow? {
        guard let w = answers[id], w.open else { return nil }
        return w
    }

    var effectiveControl: Control {
        if !config.tutorial { return config.control }
        if config.sport == .volley {
            if tutorialStage < 3 { return .beginner }
            return tutorialStage < 7 ? .standard : .pro
        }
        if tutorialStage < 3 { return .beginner }
        return tutorialStage == 3 ? .standard : .pro
    }

    /// Android `require`: unique ids; Squash is one against one, Volley two full teams.
    static func validRoster(_ roster: [Participant], _ config: SportsConfig) -> Bool {
        if Set(roster.map { $0.id }).count != roster.count || !roster.allSatisfy({ $0.team == 0 || $0.team == 1 }) { return false }
        if config.sport == .squash { return roster.count == 2 && Set(roster.map { $0.team }).count == 2 }
        return roster.count == config.teamSize * 2 && roster.filter({ $0.team == 0 }).count == config.teamSize
    }

    init(_ config: SportsConfig, _ roster: [Participant], matchId: String? = nil) {
        precondition(SportsEngine.validRoster(roster, config), "Invalid sports roster")
        self.config = config
        self.roster = roster
        self.matchId = matchId ?? "local-\(config.seed)"
        // Kotlin `Random(seed: Int)`: the seed is a 32-bit Int.
        let r = KotlinRandom(seed: Int64(Int32(truncatingIfNeeded: config.seed)))
        random = r
        players = roster.map { Athlete($0) }
        var profiles: [String: LearningProfile] = [:]
        for member in roster { profiles[member.id] = LearningProfile() }
        self.profiles = profiles
        let first = QuestionBank.generate("q0", .add, 0, r)
        question = first
        shotQuestion = first
        var slow: [String: Bool] = [:]
        for member in roster where !member.bot { slow[member.id] = true }
        receptionSlowEnabled = slow
        practice = config.challengeStep >= 0 ? CourtPractice(config.sport, config.challengeStep) : nil
        resetPositions()
        newQuestion()
        practice?.prepare(self)
    }

    func player(_ id: String) -> Athlete? { return players.first { $0.member.id == id } }
    func targetX(_ index: Int) -> Double { return targets[min(max(index, 0), 3)] }
    func targetZ(_ index: Int) -> Double { return 2.6 }

    func event(_ type: String, _ p: String = "", _ detail: String = "") {
        eventId += 1
        events.append(GameEvent(eventId, type, p, detail))
        while events.count > 100 { events.removeFirst() }
    }

    @discardableResult
    func command(_ id: String, _ nonce: String, _ kind: String, _ x: Double = 0.0, _ y: Double = 0.0, _ power: Double = 0.5,
                 questionId: String? = nil) -> Bool {
        let key = id + ":" + nonce
        let blank = nonce.kotlinIsBlank
        if !x.isFinite || !y.isFinite || !power.isFinite || blank || nonce.utf16.count > 100 || processedSet.contains(key)
            || phase == .finished || paused { return false }
        guard let p = player(id) else { return false }
        processedSet.insert(key)
        processedOrder.append(key)
        while processedOrder.count > 512 { processedSet.remove(processedOrder.removeFirst()) }
        if config.sport == .volley && !["move", "aim", "jump"].contains(kind) { return volley.command(p, kind, x, y, power) }
        switch kind {
        case "answer":
            guard let w = answerFor(id) else { return false }
            if w.remaining <= 0 || (questionId != nil && questionId != w.question.id) { return false }
            let i = KotlinNumber.int(x)
            if !(0...3).contains(i) || w.recorded { return false }
            w.selected = i
            p.chosen = i
            if phase == .ready && players[server] !== p { recordAnswer(p, w.question, i, w) }
        case "wall", "floor", "stroke":
            if config.sport != .squash { return false }
            if (kind == "stroke" && effectiveControl != .pro) || (kind != "stroke" && effectiveControl == .pro) { return false }
            if phase == .ready && players[server] !== p { return false }
            if phase == .rally && players[expected] !== p { return false }
            p.pendingTarget = Vec(min(max(x, -12.0), 12.0), min(max(y, -3.0), 12.0))
            p.pendingPower = min(max(power, 0.0), 1.0)
            p.floorShot = kind == "floor"
            p.inputUntil = clock + (effectiveControl == .beginner ? 0.48 : (effectiveControl == .standard ? 0.3 : 0.18))
            p.swing = p.inputUntil - clock
            if phase == .ready && countdown <= 0 {
                beginServeQuestions()
                serveRequested = true
                prepareServicePosition(p)
                maybeServe()
            } else {
                tryContact(p, p.pendingPower)
            }
        case "move":
            p.goal = bounded(Vec(x, y), p.member.team)
            if config.tutorial && tutorialStage == 0 { tutorialStage = 1 }
        case "aim":
            p.aim = Vec(min(max(x, -4.0), 4.0), min(max(y, -8.0), 8.0))
            if config.sport == .squash { p.chosen = min(max(KotlinNumber.int(x), 0), 3) }
        case "hit":
            if config.sport == .squash { return false }
            if ball.z > 1.8 && ball.z < 3.3 && (ball.p - p.p).length() < 1.5 && p.jump <= 0.01 { p.jumpV = 4.6 }
            p.swing = effectiveControl == .pro ? 0.28 : 0.75
            p.aim = Vec(x, y)
            if phase == .ready && players[server] === p && countdown <= 0 { serve() } else { tryContact(p, min(max(power, 0.0), 1.0)) }
        case "jump":
            if p.jump <= 0.01 {
                p.jumpV = 4.6
                p.pose = "jump"
                p.poseTime = 0.65
            }
        default:
            return false
        }
        return true
    }

    func update(_ dt: Double) {
        if paused || phase == .finished { return }
        accumulator += min(max(dt, 0.0), 0.12)
        while accumulator >= 1.0 / 120 {
            step(1.0 / 120)
            accumulator -= 1.0 / 120
        }
    }

    private func step(_ realDt: Double) {
        let focus = SportsReception.incoming(self)
        receptionReceiver = focus?.id ?? ""
        receptionStrength = focus?.strength ?? 0.0
        var readingWindow = false
        if let f = focus, let w = answerFor(f.id) { readingWindow = !w.onServe && w.remaining > 0 }
        var desiredReception = 1.0
        if let f = focus, !readingWindow, receptionSlowEnabled[f.id] != false { desiredReception = 1.0 - 0.55 * f.strength }
        receptionScale = SportsReception.smooth(receptionScale, desiredReception, realDt)
        let dt = realDt * receptionScale
        clock += dt
        phaseTime += dt
        practice?.tick(self)
        if phase == .finished { return }
        if config.sport == .squash {
            var humanWindow: AnswerWindow? = nil
            if phase == .rally && !players[expected].member.bot { humanWindow = answerFor(players[expected].member.id) }
            let slow = humanWindow != nil && !humanWindow!.onServe && humanWindow!.remaining > 0 && clock >= slowResumeAt
            let desired = slow ? 0.035 : 1.0
            timeScale += (desired - timeScale) * (1 - exp(-dt * (slow ? 6.0 : 3.5)))
            if phase == .rally && clock >= slowResumeAt {
                for w in answers.values where w.open { w.remaining = max(w.remaining - dt, 0.0) }
            }
        }
        let worldDt = dt * (config.sport == .squash ? timeScale : 1.0)
        if phase == .point {
            animate(dt)
            if phaseTime > 1.6 {
                phase = .ready
                phaseTime = 0.0
                countdown = 3.0
                resetPositions()
            }
            return
        }
        countdown = max(countdown - dt, 0.0)
        for p in players {
            if p.member.bot && (practice == nil || practice!.botMayPlay(self, p)) {
                think(p, dt)
            } else if config.sport == .squash && effectiveControl == .beginner && phase == .rally && players[expected] === p {
                p.goal = bounded(predictIntercept(1.95), p.member.team)
            }
            let delta = p.goal - p.p
            let speed = config.sport == .volley ? 3.3 + Double(VolleySkills.of(p.member.character).speed) * 0.34
                : 3.8 * (0.77 + Double(p.character.qualities.speed) * 0.055)
            let desired = delta.unit() * min(speed, delta.length() * 5.5)
            p.velocity = p.velocity + (desired - p.velocity) * (1 - exp(-dt * 12))
            let old = p.p
            p.p = bounded(p.p + p.velocity * dt, p.member.team)
            p.steps += (p.p - old).length()
            p.swing = max(p.swing - dt, 0.0)
            p.poseTime = max(p.poseTime - dt, 0.0)
            if p.jump > 0 || p.jumpV > 0 {
                p.jump += p.jumpV * dt
                p.jumpV -= 9.8 * dt
                if p.jump < 0 {
                    p.jump = 0.0
                    p.jumpV = 0.0
                }
            }
        }
        separate()
        if phase == .ready && config.sport == .volley {
            volley.ready(dt)
            return
        }
        if phase == .ready {
            let s = players[server]
            ball.p = s.p
            ball.z = 1.1
            if countdown <= 0 {
                if config.sport == .squash {
                    if config.tutorial && tutorialStage == 0 { return }
                    beginServeQuestions()
                    serveElapsed += dt
                    for w in answers.values where w.open { w.remaining = max(Double(config.answerSeconds) - serveElapsed, 0.0) }
                    let wait = questionsEnabled ? 1.6 + Double(5 - s.character.qualities.knowledge) * 0.55 : 0.6
                    if s.member.bot && !serveRequested && serveElapsed > wait {
                        let q = answers[s.member.id]?.question
                        if let q = q, random.nextDouble() < 0.45 + Double(s.character.qualities.knowledge) * 0.095 {
                            s.chosen = q.options.firstIndex(of: q.answer) ?? -1
                        } else {
                            s.chosen = random.nextInt(4)
                        }
                        s.pendingTarget = q == nil ? Vec(s.p.x < 0 ? 1.0 : -1.0, 2.7) : Vec(targetX(s.chosen), targetZ(s.chosen))
                        serveRequested = true
                        prepareServicePosition(s)
                    }
                    maybeServe()
                } else if s.member.bot || (!config.tutorial && effectiveControl == .beginner) {
                    serve()
                }
            }
            return
        }
        if !ball.active { return }
        let old = ball.p
        ball.p += ball.velocity * worldDt
        ball.z += ball.vz * worldDt - 0.5 * config.gravity * worldDt * worldDt
        ball.vz -= config.gravity * worldDt
        if config.sport == .squash { squashPhysics(old) } else { volley.physics(old) }
        if phase != .rally { return }
        let candidates = players.filter { canReturn($0) }
        if config.sport == .volley && effectiveControl == .beginner {
            for it in candidates where !it.member.bot {
                if ball.z >= 1.9 && ball.z <= 3.1 && (ball.p - it.p).length() < 1.4 && it.jump <= 0.01 { it.jumpV = 4.2 }
            }
        }
        for p in candidates {
            if p.member.bot && (p.plannedMiss || (practice != nil && !practice!.botMayPlay(self, p))) { continue }
            if p.member.bot || (practice == nil && config.sport == .volley && effectiveControl == .beginner) || p.swing > 0 {
                tryContact(p, p.pendingPower)
            }
            if phase != .rally || !ball.active { break }
        }
    }

    private func animate(_ dt: Double) {
        for it in players {
            it.poseTime = max(it.poseTime - dt, 0.0)
            it.velocity *= exp(-dt * 8)
            if config.sport == .volley && (it.jump > 0 || it.jumpV > 0) {
                it.jump = max(it.jump + it.jumpV * dt, 0.0)
                it.jumpV = it.jump > 0 ? it.jumpV - 9.8 * dt : 0.0
            }
        }
    }

    func bounded(_ p: Vec, _ team: Int) -> Vec {
        let yy: Double
        if config.sport == .squash {
            yy = min(max(p.y, -4.0), 4.2)
        } else if team == 0 {
            yy = min(max(p.y, 0.48), 9.1)
        } else {
            yy = min(max(p.y, -9.1), -0.48)
        }
        return Vec(min(max(p.x, -config.halfWidth + 0.28), config.halfWidth - 0.28), yy)
    }

    /// Inelastic contact: resolve penetration AND closing velocity. Keeping velocity aimed
    /// into another body makes network extrapolation repeatedly push through and snap back.
    private func separate() {
        let diameter = 1.05
        for _ in 0..<12 {
            for i in players.indices {
                for j in 0..<i {
                    let a = players[i]
                    let b = players[j]
                    let d = a.p - b.p
                    let distance = d.length()
                    if distance <= diameter + 0.0001 {
                        // Stable fallback also separates two bodies restored at exactly the same point.
                        let n = distance > 0.000001 ? d * (1.0 / distance) : Vec(1.0, 0.0)
                        let depth = max(diameter - distance, 0.0)
                        if depth > 0 {
                            a.p = bounded(a.p + n * (depth * 0.5), a.member.team)
                            b.p = bounded(b.p - n * (depth * 0.5), b.member.team)
                        }
                        let relative = a.velocity - b.velocity
                        let closing = relative.x * n.x + relative.y * n.y
                        if closing < 0 {
                            a.velocity -= n * (closing * 0.5)
                            b.velocity += n * (closing * 0.5)
                        }
                    }
                }
            }
            // A wall cannot absorb half a correction indefinitely or retain outward momentum.
            for p in players { p.velocity = (bounded(p.p + p.velocity * 0.001, p.member.team) - p.p) * 1000.0 }
        }
        for p in players where p.poseTime <= 0 {
            if p.velocity.length() > 0.15 { p.facing = p.velocity.unit() }
            p.pose = p.velocity.length() > 0.2 ? "walk" : "idle"
        }
    }

    func resetPositions() {
        answers.removeAll()
        serveWindowStarted = false
        serveElapsed = 0.0
        serveRequested = false
        timeScale = 1.0
        shotHasQuestion = false
        shotRecorded = false
        for (i, p) in players.enumerated() {
            if config.sport == .squash {
                p.p = Vec(i == server ? -1.65 : 1.65, 2.8)
            } else {
                let team = players.filter { $0.member.team == p.member.team }
                let slot = Double(team.firstIndex { $0 === p } ?? 0)
                p.p = Vec((slot - Double(team.count - 1) / 2.0) * 2.6, p.member.team == 0 ? 5.2 : -5.2)
            }
            p.goal = p.p
            p.velocity = Vec()
            p.pose = "idle"
            p.swing = 0.0
            p.jump = 0.0
            p.jumpV = 0.0
            p.plannedMiss = false
            p.inputUntil = -1.0
            p.floorShot = false
            p.pendingTarget = Vec(i == server ? 1.0 : -1.0, 2.7)
        }
        ball.active = false
        ball.p = players[server].p
        ball.z = 1.0
        ball.touches = 0
        ball.previousTeam = -1
        expected = 1 - server
        returnTeam = 1 - players[server].member.team
        if config.sport == .volley { volley.reset() }
    }

    func newQuestion() {
        let a = expected >= 0 && expected < players.count ? players[expected] : players[0]
        question = makeQuestion(a)
    }

    private func makeQuestion(_ a: Athlete) -> Question {
        let profile = profiles[a.member.id] ?? LearningProfile()
        let skill = QuestionBank.chooseSkill(profile, .math, random, sequence)
        sequence += 1
        return QuestionBank.generate("\(matchId)-q\(sequence)", skill, profile.state(skill).level, random)
    }

    func beginServeQuestions() {
        if serveWindowStarted { return }
        serveWindowStarted = true
        serveElapsed = 0.0
        if !questionsEnabled { return }
        for p in players where players[server] === p || config.serveQuestions != .own {
            let q = makeQuestion(p)
            answers[p.member.id] = AnswerWindow(q, Double(config.answerSeconds))
            if players[server] === p { question = q }
        }
    }

    private func prepareServicePosition(_ p: Athlete) {
        if !p.floorShot {
            p.goal = Vec(p.pendingTarget.x >= 0 ? -1.65 : 1.65, 2.8)
            players.first { $0 !== p }?.goal = Vec(-p.goal.x, 0.5)
        }
    }

    private func maybeServe() {
        if phase != .ready || countdown > 0 { return }
        let full = questionsEnabled && config.serveQuestions == .fullTime && players.contains { !$0.member.bot }
        if full && serveElapsed < Double(config.answerSeconds) { return }
        if serveRequested && (players[server].goal - players[server].p).length() > 0.12 { return }
        if !serveRequested && questionsEnabled && serveElapsed >= Double(config.answerSeconds) && !players[server].member.bot {
            answers[players[server].member.id]?.open = false
        }
        if serveRequested || (questionsEnabled && serveElapsed >= Double(config.answerSeconds)) { serve() }
    }

    func serve() {
        if phase != .ready || countdown > 0 { return }
        let p = players[server]
        if config.sport == .volley && !volley.servePrepared {
            volley.prepareServe()
            return
        }
        if config.sport == .squash {
            beginServeQuestions()
            if questionsEnabled && config.serveQuestions == .fullTime && players.contains(where: { !$0.member.bot })
                && serveElapsed < Double(config.answerSeconds) { return }
        }
        phase = .rally
        phaseTime = 0.0
        ball.p = p.p
        ball.z = 1.1
        ball.active = true
        ball.serve = true
        if config.sport == .squash {
            launchAimedSquash(p, p.pendingTarget, serve: true, power: p.pendingPower, floor: p.floorShot)
            for w in answers.values where w.onServe { w.open = false }
        } else {
            ball.previousTeam = -1
            ball.touches = 0
            volley.launch(p, serve: true, power: p.pendingPower)
        }
        event("serve", p.member.id)
        if config.tutorial && tutorialStage == 1 { tutorialStage = 2 }
    }

    /// Predict a reachable contact, including front/back/side rebounds; never aim beyond the court.
    func predictIntercept(_ contactHeight: Double = 1.5) -> Vec {
        var p = ball.p
        var z = ball.z
        var v = ball.velocity
        var vz = ball.vz
        var front = ball.front
        var bounce = ball.bounces
        var candidate = p
        for _ in 0..<420 {
            let dt = 0.008
            p += v * dt
            z += vz * dt - 0.5 * config.gravity * dt * dt
            vz -= config.gravity * dt
            if abs(p.x) > config.halfWidth {
                p = Vec(KotlinMath.sign(p.x) * (2 * config.halfWidth - abs(p.x)), p.y)
                v = Vec(-v.x * 0.93, v.y)
            }
            if p.y < -config.halfDepth {
                p = Vec(p.x, -2 * config.halfDepth - p.y)
                v = Vec(v.x * 0.95, abs(v.y) * 0.86)
                front = true
            }
            if p.y > config.halfDepth {
                p = Vec(p.x, 2 * config.halfDepth - p.y)
                v = Vec(v.x, -abs(v.y) * 0.75)
            }
            if z < 0.08 {
                bounce += 1
                if bounce >= 2 { return bounded(candidate, 0) }
                z = 0.08
                vz = abs(vz) * 0.78
            }
            if front && z >= 0.55 && z <= contactHeight {
                candidate = p
                if vz < 0 { return bounded(p, 0) }
            }
        }
        return bounded(candidate, 0)
    }

    func canReturn(_ p: Athlete) -> Bool {
        if config.sport == .squash { return (players.firstIndex { $0 === p } ?? -1) == expected && ball.front }
        return p.member.team == returnTeam && (ball.hitter != p.member.id || ball.previousTeam != p.member.team)
            && (!p.member.bot || ball.receiver.kotlinIsBlank || ball.receiver == p.member.id)
    }

    @discardableResult
    private func tryContact(_ p: Athlete, _ power: Double = 0.5) -> Bool {
        if phase != .rally || !ball.active || !canReturn(p) || clock - poseStamp < 0.16 { return false }
        if config.sport == .squash && !p.member.bot && clock > p.inputUntil { return false }
        let reach: Double
        if effectiveControl == .pro && !p.member.bot {
            reach = 0.9
        } else if effectiveControl == .beginner && !p.member.bot {
            reach = 1.45
        } else {
            reach = 1.3
        }
        if config.sport == .volley { return volley.tryContact(p) }
        if (ball.p - p.p).length() > reach || ball.z < 0.12 || ball.z > 2.05 + p.jump { return false }
        if config.sport == .squash {
            if p.member.bot {
                launchSquash(p, p.chosen, serve: false, power: power)
            } else {
                launchAimedSquash(p, p.pendingTarget, serve: false, power: power, floor: p.floorShot)
            }
        } else {
            volley.launch(p, serve: false, power: power)
        }
        p.swing = 0.0
        return true
    }

    func contact(_ p: Athlete) {
        p.pose = "hit"
        p.poseTime = 0.52
        p.contacts += 1
        p.facing = ball.velocity.unit()
        ball.hitter = p.member.id
        shotSerial += 1
        ball.shot = shotSerial
        ball.bounces = 0
        ball.scoringChecked = false
        poseStamp = clock
        event("hit", p.member.id)
        practice?.contact(self, p)
    }

    func launchSquash(_ p: Athlete, _ choice: Int, serve: Bool = false, power: Double = 0.5) {
        launchAimedSquash(p, Vec(targetX(choice), targetZ(choice)), serve: serve, power: power, floor: false)
    }

    func launchAimedSquash(_ p: Athlete, _ target: Vec, serve: Bool = false, power: Double = 0.5, floor: Bool = false) {
        let w = answers[p.member.id]
        shotHasQuestion = questionsEnabled && w != nil && w!.open && !w!.recorded && (w!.remaining > 0 || w!.selected >= 0)
        shotRecorded = false
        shotQuestion = w?.question ?? question
        shotChoice = w?.selected ?? -1
        w?.open = false
        ball.p = p.p
        ball.z = 1.1 + p.jump * 0.4
        // Accuracy assistance solves a ballistic trajectory to the exact tapped wall coordinate.
        // Character skill controls movement, never silently substitutes a different wall target.
        let t = (serve ? 0.70 : 0.72) - (effectiveControl == .pro && !p.member.bot ? power * 0.38 : 0.0)
        let destination = floor ? Vec(min(max(target.x, -3.2), 3.2), min(max(target.y, -4.5), 4.5)) : Vec(target.x, -config.halfDepth)
        ball.velocity = (destination - ball.p) * (1 / t)
        ball.vz = ((floor ? 0.0 : target.y) - ball.z + 0.5 * config.gravity * t * t) / t
        ball.front = false
        ball.serve = serve
        contact(p)
        p.inputUntil = -1.0
        expected = 1 - (players.firstIndex { $0 === p } ?? 0)
        let receiver = players[expected]
        receiver.plannedMiss = receiver.member.bot && random.nextDouble() < 0.04 + Double(5 - receiver.character.qualities.reflexes) * 0.035
        if questionsEnabled && (config.answerMode == .everyHit || config.tutorial) {
            slowResumeAt = clock + 0.7
            let next = players[expected]
            let q = makeQuestion(next)
            answers[next.member.id] = AnswerWindow(q, Double(config.answerSeconds), onServe: false)
            question = q
        }
    }

    private func recordAnswer(_ p: Athlete, _ q: Question, _ index: Int, _ w: AnswerWindow? = nil) {
        if !(0...3).contains(index) || w?.recorded == true { return }
        if let w = w {
            w.recorded = true
            w.selected = index
        }
        let right = q.options[index] == q.answer
        profiles[p.member.id]?.record(q.skill, correct: right, hint: false)
        feedbackEn = (right ? "Correct! +1 learning point. " : "Correct answer: ") + q.explanation(false)
        feedbackHe = (right ? "נכון! נקודת למידה אחת. " : "התשובה הנכונה: ") + q.explanation(true)
        feedbackUntil = clock + 4
        if right {
            p.correct += 1
            event("correct", p.member.id, q.answer)
        } else {
            p.mistakes += 1
            event("wrong", p.member.id, q.explanation(false))
        }
    }

    private func squashPhysics(_ old: Vec) {
        if abs(ball.p.x) >= config.halfWidth {
            ball.p = Vec(KotlinMath.sign(ball.p.x) * (2 * config.halfWidth - abs(ball.p.x)), ball.p.y)
            ball.velocity = Vec(-ball.velocity.x * 0.93, ball.velocity.y)
            event("wall")
        }
        if ball.p.y <= -config.halfDepth && old.y > -config.halfDepth {
            if ball.z <= 0.48 || ball.z >= 4.57 {
                point(1 - teamOf(ball.hitter), ball.z <= 0.48 ? "tin" : "out")
                return
            }
            if ball.serve && ball.z <= 1.78 {
                point(1 - teamOf(ball.hitter), "serve_fault")
                return
            }
            if let practice = practice {
                practice.front(self, ball.p.x, ball.z)
                if !ball.active { return }
            }
            ball.p = Vec(ball.p.x, -config.halfDepth + (-config.halfDepth - ball.p.y))
            ball.velocity = Vec(ball.velocity.x * 0.95, -ball.velocity.y * 0.86)
            ball.front = true
            event("wall")
            if !ball.scoringChecked {
                ball.scoringChecked = true
                if shotHasQuestion && !shotRecorded {
                    var index = 0
                    var best = Double.greatestFiniteMagnitude
                    for i in 0...3 {
                        let d = hypot(ball.p.x - targetX(i), ball.z - targetZ(i))
                        if d < best {
                            best = d
                            index = i
                        }
                    }
                    if hypot(ball.p.x - targetX(index), ball.z - targetZ(index)) < 0.58, let a = player(ball.hitter) {
                        shotRecorded = true
                        let window = answers[a.member.id].flatMap { $0.question.id == shotQuestion.id ? $0 : nil }
                        recordAnswer(a, shotQuestion, index, window)
                    }
                }
            }
        }
        if ball.p.y >= config.halfDepth {
            ball.p = Vec(ball.p.x, 2 * config.halfDepth - ball.p.y)
            ball.velocity = Vec(ball.velocity.x, -abs(ball.velocity.y) * 0.75)
            event("wall")
        }
        if ball.z <= 0.08 {
            if !ball.front {
                point(1 - teamOf(ball.hitter), "floor_before_wall")
                return
            }
            ball.bounces += 1
            if ball.bounces >= 2 {
                point(teamOf(ball.hitter), "two_bounces")
                return
            }
            // Assisted serving still observes opposite-quarter landing. A volley may return it earlier.
            if ball.serve && ball.bounces == 1, let hitter = player(ball.hitter) {
                if ball.p.y < 0 || ball.p.x * hitter.p.x >= 0 {
                    point(1 - hitter.member.team, "serve_fault")
                    return
                }
            }
            ball.z = 0.08
            ball.vz = abs(ball.vz) * 0.78
            event("bounce")
        }
    }

    func predictLanding() -> Vec {
        let t = (ball.vz + sqrt(max(ball.vz * ball.vz + 2 * config.gravity * (ball.z - 0.9), 0.0))) / config.gravity
        var x = ball.p.x + ball.velocity.x * t
        var y = ball.p.y + ball.velocity.y * t
        if config.sport == .squash {
            for _ in 0..<3 {
                if abs(x) > config.halfWidth { x = KotlinMath.sign(x) * (2 * config.halfWidth - abs(x)) }
                if y > config.halfDepth { y = 2 * config.halfDepth - y }
            }
        }
        return Vec(x, y)
    }

    private func think(_ p: Athlete, _ dt: Double) {
        p.think -= dt
        if p.think > 0 { return }
        p.think = 0.12 + Double(5 - p.character.qualities.reflexes) * 0.025
        if phase != .rally { return }
        if config.sport == .squash {
            if (players.firstIndex { $0 === p } ?? -1) == expected && ball.front {
                let landing = predictIntercept()
                p.goal = bounded(landing, p.member.team)
                let w = answerFor(p.member.id)
                if let w = w, w.selected < 0 {
                    if random.nextDouble() < 0.45 + Double(p.character.qualities.knowledge) * 0.095 {
                        p.chosen = w.question.options.firstIndex(of: w.question.answer) ?? -1
                    } else {
                        p.chosen = random.nextInt(4)
                    }
                    w.selected = p.chosen
                } else if w == nil {
                    if p.contacts % 3 == 0 {
                        p.chosen = random.nextInt(4)
                    } else {
                        p.chosen = p.p.x < 0 ? 3 : 0
                    }
                }
            } else {
                p.goal = Vec(ball.p.x > 0 ? -0.7 : 0.7, 0.2)
            }
        } else {
            volley.think(p)
        }
    }

    func teamOf(_ id: String) -> Int { return player(id)?.member.team ?? 0 }

    func point(_ team: Int, _ why: String) {
        if phase != .rally { return }
        if let practice = practice {
            practice.point(self, why)
            return
        }
        scores[team] += 1
        pointSerial += 1
        reason = why
        ball.active = false
        phase = .point
        phaseTime = 0.0
        server = players.firstIndex { $0.member.team == team } ?? -1
        if let hitter = player(ball.hitter), hitter.member.team == team { hitter.winners += 1 }
        event("point", players[server].member.id, why)
        checkWinner()
    }

    private func checkWinner() {
        if config.tutorial { return }
        for t in 0...1 where scores[t] >= config.target && scores[t] - scores[1 - t] >= 2 {
            winner = t
            phase = .finished
            ball.active = false
            event("finished", "", String(t))
        }
    }

    func earned(_ id: String) -> Int {
        guard let p = player(id) else { return 0 }
        if config.tutorial || practice != nil { return 0 }
        return p.contacts + 4 * p.correct + 3 * p.winners + (winner == p.member.team ? 15 : 0)
    }

    func finishTutorial() {
        tutorialComplete = true
        event("tutorial_finished")
    }
}

/// Kotlin math helpers with Kotlin's exact semantics.
enum KotlinMath {
    /// `kotlin.math.sign`: -1, 0 or 1 (NaN stays NaN).
    static func sign(_ x: Double) -> Double {
        if x.isNaN { return x }
        if x > 0 { return 1.0 }
        if x < 0 { return -1.0 }
        return x
    }
}
