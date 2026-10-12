import Foundation

enum SportsCodecError: Error {
    case missing(String)
    case invalid(String)
}

/// `org.json` accessor semantics for nodes parsed from Android JSON text: `opt*` falls back
/// (`optDouble` to NaN, `optInt` to 0, `optString` to ""), `get*` throws when a value is absent.
extension Dictionary where Key == String, Value == Any {
    func optInt(_ key: String, _ fallback: Int = 0) -> Int {
        if let n = NodeValue.number(self[key]) { return KotlinNumber.int(n) }
        if let s = self[key] as? String, let d = Double(s.trimmingCharacters(in: .whitespaces)) { return KotlinNumber.int(d) }
        return fallback
    }

    func optDouble(_ key: String, _ fallback: Double = Double.nan) -> Double {
        if let n = NodeValue.number(self[key]) { return n }
        if let s = self[key] as? String, let d = Double(s.trimmingCharacters(in: .whitespaces)) { return d }
        return fallback
    }

    func optBool(_ key: String, _ fallback: Bool = false) -> Bool {
        if let b = NodeValue.bool(self[key]) { return b }
        if let s = self[key] as? String {
            if s.lowercased() == "true" { return true }
            if s.lowercased() == "false" { return false }
        }
        return fallback
    }

    func optString(_ key: String, _ fallback: String = "") -> String {
        guard let value = self[key], !(value is NSNull) else { return fallback }
        return NodeValue.text(value)
    }

    func optNode(_ key: String) -> Node? { return self[key] as? [String: Any] }

    func optArray(_ key: String) -> [Any]? { return self[key] as? [Any] }

    func getString(_ key: String) throws -> String {
        guard let value = self[key], !(value is NSNull) else { throw SportsCodecError.missing(key) }
        return NodeValue.text(value)
    }

    func getInt(_ key: String) throws -> Int {
        guard has(key) else { throw SportsCodecError.missing(key) }
        if let n = NodeValue.number(self[key]) { return KotlinNumber.int(n) }
        if let s = self[key] as? String, let d = Double(s) { return KotlinNumber.int(d) }
        throw SportsCodecError.invalid(key)
    }

    func getDouble(_ key: String) throws -> Double {
        guard has(key) else { throw SportsCodecError.missing(key) }
        if let n = NodeValue.number(self[key]) { return n }
        if let s = self[key] as? String, let d = Double(s) { return d }
        throw SportsCodecError.invalid(key)
    }

    func getBool(_ key: String) throws -> Bool {
        guard has(key) else { throw SportsCodecError.missing(key) }
        if let b = NodeValue.bool(self[key]) { return b }
        if let s = self[key] as? String, s.lowercased() == "true" || s.lowercased() == "false" { return s.lowercased() == "true" }
        throw SportsCodecError.invalid(key)
    }

    func getNode(_ key: String) throws -> Node {
        guard let n = self[key] as? [String: Any] else { throw SportsCodecError.missing(key) }
        return n
    }

    func getArray(_ key: String) throws -> [Any] {
        guard let a = self[key] as? [Any] else { throw SportsCodecError.missing(key) }
        return a
    }
}

/// Port of Android SportsCodec.kt: the exact JSON field names of saved matches and of the room
/// snapshot, so iOS and Android players share rooms and either side can restore the other's match.
enum SportsCodec {
    static func profile(_ p: LearningProfile) -> Node {
        var j: Node = [:]
        for skill in Skill.allCases {
            let s = p.state(skill)
            j[skill.name] = ["level": s.level, "streak": s.streak, "independent": s.independent, "assisted": s.assisted, "wrong": s.wrong] as Node
        }
        return j
    }

    static func profile(_ p: LearningProfile, _ j: Node) {
        for skill in Skill.allCases {
            guard let n = j.optNode(skill.name) else { continue }
            var s = p.state(skill)
            s.level = min(max(n.optInt("level"), 0), 5)
            s.streak = n.optInt("streak")
            s.independent = n.optInt("independent")
            s.assisted = n.optInt("assisted")
            s.wrong = n.optInt("wrong")
            p.skills[skill] = s
        }
    }

    static func config(_ c: SportsConfig) -> Node {
        return ["sport": c.sport.name, "teamSize": c.teamSize, "target": c.target, "arena": c.arena, "control": c.control.name,
                "seed": c.seed, "tutorial": c.tutorial, "answerMode": c.answerMode.name, "serveQuestions": c.serveQuestions.name,
                "answerSeconds": c.answerSeconds, "questionsEnabled": c.questionsEnabled, "serveControl": c.serveControl.name,
                "ballStyle": c.ballStyle, "teamColors": c.teamColors, "houseRoster": c.houseRoster, "challengeStep": c.challengeStep]
    }

    private static func strings(_ value: [Any]?) -> [String]? {
        return value?.map { NodeValue.text($0) }
    }

    /// Android `SportsConfig(...)` from JSON; its `require` failures (an invalid shared config) throw here.
    static func config(_ j: Node) throws -> SportsConfig {
        guard let sport = Sport(rawValue: try j.getString("sport")) else { throw SportsCodecError.invalid("sport") }
        guard let control = Control(rawValue: j.optString("control", "BEGINNER")),
              let answerMode = AnswerMode(rawValue: j.optString("answerMode", "SERVES")),
              let serveQuestions = ServeQuestions(rawValue: j.optString("serveQuestions", "FULL_TIME")),
              let serveControl = Control(rawValue: j.optString("serveControl", j.optString("control", "BEGINNER"))) else {
            throw SportsCodecError.invalid("config")
        }
        var c = SportsConfig()
        c.sport = sport
        c.teamSize = j.optInt("teamSize", 2)
        c.target = j.optInt("target", 11)
        c.arena = j.optString("arena", "beach")
        c.control = control
        c.seed = j.optInt("seed", 17)
        c.tutorial = j.optBool("tutorial")
        c.answerMode = answerMode
        c.serveQuestions = serveQuestions
        c.answerSeconds = j.optInt("answerSeconds", 15)
        c.questionsEnabled = j.optBool("questionsEnabled", true)
        c.serveControl = serveControl
        c.ballStyle = j.optString("ballStyle", "classic")
        c.teamColors = strings(j.optArray("teamColors")) ?? ["aqua", "gold"]
        c.houseRoster = strings(j.optArray("houseRoster")) ?? []
        c.challengeStep = j.optInt("challengeStep", -1)
        guard c.isValid else { throw SportsCodecError.invalid("config") }
        return c
    }

    static func participant(_ p: Participant) -> Node {
        return ["id": p.id, "character": p.character, "team": p.team, "bot": p.bot, "name": p.name, "rankPoints": p.rankPoints]
    }

    static func participant(_ j: Node) throws -> Participant {
        return Participant(try j.getString("id"), try j.getString("character"), try j.getInt("team"), try j.getBool("bot"),
                           j.optString("name"), j.optInt("rankPoints"))
    }

    static func question(_ q: Question) -> Node {
        return ["id": q.id, "skill": q.skill.name, "level": q.level, "en": q.en, "he": q.he, "answer": q.answer,
                "options": q.options, "why": q.explanationEn, "whyHe": q.explanationHe]
    }

    static func question(_ j: Node) throws -> Question {
        guard let skill = Skill(rawValue: try j.getString("skill")) else { throw SportsCodecError.invalid("skill") }
        let options = try j.getArray("options")
        guard options.count >= 4 else { throw SportsCodecError.invalid("options") }
        let q = Question(id: try j.getString("id"), skill: skill, level: try j.getInt("level"), en: try j.getString("en"),
                         he: try j.getString("he"), answer: try j.getString("answer"), options: (0...3).map { NodeValue.text(options[$0]) },
                         explanationEn: try j.getString("why"), explanationHe: try j.getString("whyHe"))
        // Android's Question init requires four distinct options with exactly one answer.
        guard q.isValid else { throw SportsCodecError.invalid("question") }
        return q
    }

    static func encode(_ e: SportsEngine) -> Node {
        let b = e.ball
        var j: Node = [:]
        if let d = e.practice {
            j["practice"] = ["successes": d.successes, "mistakes": d.mistakes, "attempts": d.attempts, "nextAt": d.nextAt,
                             "deadline": d.deadline, "pending": d.pending, "kind": d.pendingKind, "received": d.received,
                             "initialSteps": d.initialSteps, "painted": d.painted, "lastGood": d.lastGood] as Node
        }
        let v = e.volley
        j["volley"] = ["serveQueued": v.serveQueued, "serveWindup": v.serveWindup, "servePrepared": v.servePrepared, "toss": v.toss,
                       "tossTime": v.tossTime, "readyTime": v.readyTime, "misses": v.misses, "height": v.tossHeight,
                       "velocity": v.tossVelocity] as Node
        var windows: Node = [:]
        for (id, w) in e.answers {
            windows[id] = ["question": question(w.question), "remaining": w.remaining, "open": w.open, "recorded": w.recorded,
                           "selected": w.selected, "onServe": w.onServe] as Node
        }
        j["answerWindows"] = windows
        j["serveWindowStarted"] = e.serveWindowStarted
        j["serveElapsed"] = e.serveElapsed
        j["serveRequested"] = e.serveRequested
        j["timeScale"] = e.timeScale
        j["receptionScale"] = e.receptionScale
        j["receptionReceiver"] = e.receptionReceiver
        j["receptionStrength"] = e.receptionStrength
        j["receptionSlowEnabled"] = e.receptionSlowEnabled as Node
        j["slowResumeAt"] = e.slowResumeAt
        j["shotHasQuestion"] = e.shotHasQuestion
        j["shotRecorded"] = e.shotRecorded
        var profiles: Node = [:]
        for (id, p) in e.profiles { profiles[id] = profile(p) }
        j["profiles"] = profiles
        j["poseStamp"] = e.poseStamp
        j["tutorialStage"] = e.tutorialStage
        j["feedbackEn"] = e.feedbackEn
        j["feedbackHe"] = e.feedbackHe
        j["feedbackUntil"] = e.feedbackUntil
        j["version"] = 2
        j["matchId"] = e.matchId
        j["config"] = config(e.config)
        j["roster"] = e.roster.map { participant($0) }
        j["clock"] = e.clock
        j["phase"] = e.phase.name
        j["phaseTime"] = e.phaseTime
        j["countdown"] = e.countdown
        j["server"] = e.server
        j["expected"] = e.expected
        j["returnTeam"] = e.returnTeam
        j["winner"] = e.winner
        j["scores"] = e.scores
        j["reason"] = e.reason
        j["sequence"] = e.sequence
        j["eventId"] = e.eventId
        j["pointSerial"] = e.pointSerial
        j["shotSerial"] = e.shotSerial
        j["question"] = question(e.question)
        j["shotQuestion"] = question(e.shotQuestion)
        j["shotChoice"] = e.shotChoice
        j["ball"] = ["x": b.p.x, "y": b.p.y, "z": b.z, "vx": b.velocity.x, "vy": b.velocity.y, "vz": b.vz, "active": b.active,
                     "hitter": b.hitter, "shot": b.shot, "bounces": b.bounces, "front": b.front, "scoringChecked": b.scoringChecked,
                     "serve": b.serve, "previousTeam": b.previousTeam, "touches": b.touches, "receiver": b.receiver] as Node
        j["players"] = e.players.map { p -> Node in
            return ["id": p.member.id, "x": p.p.x, "y": p.p.y, "gx": p.goal.x, "gy": p.goal.y, "vx": p.velocity.x, "vy": p.velocity.y,
                    "fx": p.facing.x, "fy": p.facing.y, "pose": p.pose, "poseTime": p.poseTime, "jump": p.jump, "jumpV": p.jumpV,
                    "swing": p.swing, "think": p.think, "plannedMiss": p.plannedMiss, "aimX": p.aim.x, "aimY": p.aim.y, "steps": p.steps,
                    "chosen": p.chosen, "contacts": p.contacts, "correct": p.correct, "mistakes": p.mistakes, "winners": p.winners,
                    "pendingX": p.pendingTarget.x, "pendingZ": p.pendingTarget.y, "pendingPower": p.pendingPower, "floorShot": p.floorShot,
                    "inputUntil": p.inputUntil, "volleyKind": p.volleyKind, "volleyAttemptAt": p.volleyAttemptAt,
                    "volleyAttemptShot": p.volleyAttemptShot, "volleyTriedShot": p.volleyTriedShot, "volleyExplicit": p.volleyExplicit]
        }
        j["events"] = e.events.suffix(12).map { ["id": $0.id, "type": $0.type, "player": $0.player, "detail": $0.detail] as Node }
        return j
    }

    /// Android `decode(j, allowPractice)`: an online room never restores a drill.
    static func decode(_ j: Node, allowPractice: Bool = true) throws -> SportsEngine {
        let r = try j.getArray("roster")
        var c = try config(try j.getNode("config"))
        if !allowPractice { c.challengeStep = -1 }
        let roster = try r.map { item -> Participant in
            guard let n = item as? [String: Any] else { throw SportsCodecError.invalid("roster") }
            return try participant(n)
        }
        guard SportsEngine.validRoster(roster, c) else { throw SportsCodecError.invalid("roster") }
        let e = SportsEngine(c, roster, matchId: try j.getString("matchId"))
        try apply(e, j)
        return e
    }

    static func apply(_ e: SportsEngine, _ j: Node) throws {
        // Checked before anything is written: an out-of-range server (or squash receiver) would index
        // outside the roster. Volleyball's `expected` is often out of range on Android too.
        let server = try j.getInt("server")
        let expected = try j.getInt("expected")
        guard e.players.indices.contains(server), e.config.sport != .squash || e.players.indices.contains(expected) else {
            throw SportsCodecError.invalid("server")
        }
        if let v = j.optNode("practice"), let d = e.practice {
            d.successes = v.optInt("successes")
            d.mistakes = v.optInt("mistakes")
            d.attempts = v.optInt("attempts")
            d.nextAt = v.optDouble("nextAt")
            d.deadline = v.optDouble("deadline")
            d.pending = v.optBool("pending")
            d.pendingKind = v.optString("kind")
            d.received = v.optBool("received")
            d.initialSteps = v.optDouble("initialSteps")
            d.lastGood = v.optDouble("lastGood", -10.0)
            d.painted.removeAll()
            if let a = v.optArray("painted") {
                for item in a {
                    let i = KotlinNumber.int(NodeValue.number(item) ?? 0)
                    if !d.painted.contains(i) { d.painted.append(i) }
                }
            }
        }
        if let v = j.optNode("volley") {
            let s = e.volley
            s.serveQueued = v.optBool("serveQueued")
            s.serveWindup = v.optDouble("serveWindup", 0.0)
            s.servePrepared = v.optBool("servePrepared")
            s.toss = v.optBool("toss")
            s.tossTime = v.optDouble("tossTime", 0.0)
            s.readyTime = v.optDouble("readyTime", 0.0)
            s.misses = v.optInt("misses")
            s.tossHeight = v.optDouble("height", 1.1)
            s.tossVelocity = v.optDouble("velocity", 0.0)
        }
        e.receptionScale = min(max(j.optDouble("receptionScale", 1.0), 0.45), 1.0)
        e.receptionReceiver = j.optString("receptionReceiver")
        e.receptionStrength = min(max(j.optDouble("receptionStrength", 0.0), 0.0), 1.0)
        if let n = j.optNode("receptionSlowEnabled") {
            for id in Array(e.receptionSlowEnabled.keys) { e.receptionSlowEnabled[id] = n.optBool(id, true) }
        }
        e.answers.removeAll()
        if let a = j.optNode("answerWindows") {
            for id in a.keys.sorted(by: JavaOrder.firebaseKeyPrecedes) {
                let w = try a.getNode(id)
                e.answers[id] = AnswerWindow(try question(try w.getNode("question")), try w.getDouble("remaining"), open: try w.getBool("open"),
                                             recorded: try w.getBool("recorded"), selected: try w.getInt("selected"), onServe: try w.getBool("onServe"))
            }
        }
        e.serveWindowStarted = j.optBool("serveWindowStarted")
        e.serveElapsed = j.optDouble("serveElapsed", 0.0)
        e.serveRequested = j.optBool("serveRequested")
        e.timeScale = j.optDouble("timeScale", 1.0)
        e.slowResumeAt = j.optDouble("slowResumeAt", 0.0)
        e.shotHasQuestion = j.optBool("shotHasQuestion")
        e.shotRecorded = j.optBool("shotRecorded")
        if let n = j.optNode("profiles") {
            for (id, p) in e.profiles {
                if let it = n.optNode(id) { profile(p, it) }
            }
        }
        e.clock = try j.getDouble("clock")
        e.poseStamp = j.optDouble("poseStamp", -10.0)
        e.tutorialStage = j.optInt("tutorialStage")
        e.feedbackEn = j.optString("feedbackEn")
        e.feedbackHe = j.optString("feedbackHe")
        e.feedbackUntil = j.optDouble("feedbackUntil", 0.0)
        guard let phase = Phase(rawValue: try j.getString("phase")) else { throw SportsCodecError.invalid("phase") }
        e.phase = phase
        e.phaseTime = try j.getDouble("phaseTime")
        e.countdown = try j.getDouble("countdown")
        e.server = server
        e.expected = expected
        e.returnTeam = try j.getInt("returnTeam")
        e.winner = try j.getInt("winner")
        let scores = try j.getArray("scores")
        guard scores.count >= 2 else { throw SportsCodecError.invalid("scores") }
        e.scores[0] = KotlinNumber.int(NodeValue.number(scores[0]) ?? 0)
        e.scores[1] = KotlinNumber.int(NodeValue.number(scores[1]) ?? 0)
        e.reason = try j.getString("reason")
        e.sequence = try j.getInt("sequence")
        e.eventId = try j.getInt("eventId")
        e.pointSerial = try j.getInt("pointSerial")
        e.shotSerial = try j.getInt("shotSerial")
        e.question = try question(try j.getNode("question"))
        e.shotQuestion = try question(try j.getNode("shotQuestion"))
        e.shotChoice = try j.getInt("shotChoice")
        let b = try j.getNode("ball")
        let ball = e.ball
        ball.p = Vec(try b.getDouble("x"), try b.getDouble("y"))
        ball.z = try b.getDouble("z")
        ball.velocity = Vec(try b.getDouble("vx"), try b.getDouble("vy"))
        ball.vz = try b.getDouble("vz")
        ball.active = try b.getBool("active")
        ball.hitter = try b.getString("hitter")
        ball.shot = try b.getInt("shot")
        ball.bounces = try b.getInt("bounces")
        ball.front = try b.getBool("front")
        ball.scoringChecked = try b.getBool("scoringChecked")
        ball.serve = try b.getBool("serve")
        ball.previousTeam = try b.getInt("previousTeam")
        ball.touches = try b.getInt("touches")
        ball.receiver = b.optString("receiver")
        for item in try j.getArray("players") {
            guard let s = item as? [String: Any], let p = e.player(try s.getString("id")) else { continue }
            p.p = Vec(try s.getDouble("x"), try s.getDouble("y"))
            p.goal = Vec(try s.getDouble("gx"), try s.getDouble("gy"))
            p.velocity = Vec(try s.getDouble("vx"), try s.getDouble("vy"))
            p.facing = Vec(try s.getDouble("fx"), try s.getDouble("fy"))
            p.pose = try s.getString("pose")
            p.poseTime = try s.getDouble("poseTime")
            p.jump = try s.getDouble("jump")
            p.jumpV = try s.getDouble("jumpV")
            p.swing = s.optDouble("swing", 0.0)
            p.think = s.optDouble("think", 0.0)
            p.plannedMiss = s.optBool("plannedMiss")
            p.aim = Vec(s.optDouble("aimX", 0.0), s.optDouble("aimY", 0.0))
            p.steps = try s.getDouble("steps")
            p.chosen = try s.getInt("chosen")
            p.contacts = try s.getInt("contacts")
            p.correct = try s.getInt("correct")
            p.mistakes = try s.getInt("mistakes")
            p.winners = try s.getInt("winners")
            p.pendingTarget = Vec(s.optDouble("pendingX", 0.0), s.optDouble("pendingZ", 2.7))
            p.pendingPower = s.optDouble("pendingPower", 0.5)
            p.floorShot = s.optBool("floorShot")
            p.inputUntil = s.optDouble("inputUntil", -1.0)
            p.volleyKind = s.optString("volleyKind", "auto")
            p.volleyAttemptAt = s.optDouble("volleyAttemptAt", -10.0)
            p.volleyAttemptShot = s.optInt("volleyAttemptShot", -1)
            p.volleyTriedShot = s.optInt("volleyTriedShot", -1)
            p.volleyExplicit = s.optBool("volleyExplicit")
        }
        e.events.removeAll()
        for item in j.optArray("events") ?? [] {
            guard let v = item as? [String: Any] else { continue }
            e.events.append(GameEvent(try v.getInt("id"), try v.getString("type"), try v.getString("player"), try v.getString("detail")))
        }
    }

    /// JSON text (`JSONObject.toString()`); nil instead of an exception for unencodable content.
    static func text(_ node: Node) -> String? { return NodeJSON.string(node) }
}
