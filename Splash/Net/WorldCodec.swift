import Foundation

/// Port of Android WorldCodec.kt: the exact Realtime Database / persistence field names.
/// Kotlin nulls are omitted keys (Firebase and JSON treat both as absent).
enum WorldCodec {
    /// Arena size, duration, difficulty and the wall-battle / challenge setup travel with rooms and saved battles;
    /// older ones without them are 12 x 12 standard battles.
    static func config(_ c: SplashConfig) -> Node {
        var n: Node = ["width": c.width, "depth": c.depth, "duration": c.duration, "difficulty": c.difficulty.name,
                       "wallBattle": c.wallBattle, "hitEffect": c.hitEffect.name, "chapter": c.chapter,
                       "challengeStep": c.challengeStep, "target": c.target]
        if let challenge = c.challenge { n["challenge"] = challenge.name }
        return n
    }

    static func config(_ n: Node) -> SplashConfig {
        var c = SplashConfig()
        c.width = min(max(n.num("width", 12.0), 8.0), 28.0)
        c.depth = min(max(n.num("depth", 12.0), 8.0), 28.0)
        c.duration = min(max(n.num("duration", 180.0), 30.0), 3600.0)
        c.difficulty = Difficulty(rawValue: n.str("difficulty")) ?? .standard
        c.wallBattle = n.flag("wallBattle")
        c.hitEffect = HitEffect(rawValue: n.str("hitEffect")) ?? .cosmetic
        c.challenge = ChallengeKind(rawValue: n.str("challenge"))
        c.chapter = max(KotlinNumber.int(n.num("chapter")), 0)
        c.challengeStep = max(KotlinNumber.int(n.num("challengeStep")), 0)
        c.target = max(KotlinNumber.int(n.num("target", 10.0)), 1)
        return c
    }

    private static func v(_ p: V) -> [Double] { return [p.x, p.y] }

    private static func vector(_ n: Node, _ key: String) -> V {
        let a = n.list(key)
        let x = a.count > 0 ? NodeValue.number(a[0]) ?? 0 : 0
        let y = a.count > 1 ? NodeValue.number(a[1]) ?? 0 : 0
        return V(x, y)
    }

    private static func option<T: KotlinEnum>(_ n: Node, _ key: String, _ fallback: T) -> T {
        return T(rawValue: n.str(key)) ?? fallback
    }

    // MARK: Settings and members

    static func settings(_ s: PlayerSettings) -> Node {
        return ["walk": s.walk.name, "throwing": s.throwing.name, "arena": s.arena.name, "court": s.court,
                "balloons": s.balloons.name, "subjects": s.orderedSubjects.map { $0.name }, "difficulty": s.difficulty.name]
    }

    static func settings(_ n: Node) -> PlayerSettings {
        var subjects = Set<Topic>()
        for item in n.list("subjects") {
            if let name = item as? String, let topic = Topic(rawValue: name), topic != .mixed { subjects.insert(topic) }
        }
        if subjects.isEmpty { subjects = [.math] }
        return PlayerSettings(walk: option(n, "walk", WalkMode.easy), throwing: option(n, "throwing", ThrowMode.easy),
                              arena: option(n, "arena", Arena.beach), court: NodeValue.bool(n["court"]) ?? true,
                              balloons: option(n, "balloons", BalloonMode.onePlace), subjects: subjects,
                              difficulty: option(n, "difficulty", Difficulty.easy))
    }

    static func member(_ m: Member) -> Node {
        return ["id": m.id, "character": m.character, "team": m.team, "bot": m.bot, "name": m.name, "ready": m.bot,
                "connected": true, "hebrew": m.hebrew, "settings": settings(m.settings)]
    }

    static func member(_ id: String, _ n: Node) -> Member {
        return Member(id, n.str("character", "minik"), team: KotlinNumber.int(n.num("team")), bot: n.flag("bot"),
                      name: n.str("name", "Player"), hebrew: n.flag("hebrew"), settings: settings(n.node("settings")))
    }

    // MARK: Learning

    static func profile(_ p: LearningProfile) -> Node {
        var out: Node = [:]
        for skill in Skill.allCases {
            let s = p.state(skill)
            out[skill.name] = ["level": s.level, "streak": s.streak, "independent": s.independent,
                               "assisted": s.assisted, "wrong": s.wrong, "reviewed": s.reviewed] as Node
        }
        return out
    }

    static func profile(_ n: Node) -> LearningProfile {
        let p = LearningProfile()
        for skill in Skill.allCases {
            let a = n.node(skill.name)
            p.skills[skill] = SkillState(level: min(max(KotlinNumber.int(a.num("level")), 0), 5),
                                         streak: KotlinNumber.int(a.num("streak")),
                                         independent: KotlinNumber.int(a.num("independent")),
                                         assisted: KotlinNumber.int(a.num("assisted")),
                                         wrong: KotlinNumber.int(a.num("wrong")),
                                         reviewed: KotlinNumber.int(a.num("reviewed")))
        }
        return p
    }

    private static func question(_ q: Question) -> Node {
        return ["id": q.id, "skill": q.skill.name, "level": q.level, "en": q.en, "he": q.he, "answer": q.answer,
                "options": q.options, "explanationEn": q.explanationEn, "explanationHe": q.explanationHe]
    }

    private static func question(_ n: Node) -> Question? {
        guard let skill = Skill(rawValue: n.str("skill")) else { return nil }
        let q = Question(id: n.str("id"), skill: skill, level: KotlinNumber.int(n.num("level")), en: n.str("en"),
                         he: n.str("he"), answer: n.str("answer"), options: n.list("options").map { NodeValue.text($0) },
                         explanationEn: n.str("explanationEn"), explanationHe: n.str("explanationHe"))
        return q.isValid ? q : nil
    }

    // MARK: Private (owner + authority only)

    static func personal(_ a: SplashActor) -> Node {
        var out: Node = ["autoPickupQuestion": a.autoPickupQuestion, "autoPickupIndex": a.autoPickupIndex,
                         "profile": profile(a.profile), "sequence": a.sequence, "questionAt": a.questionAt,
                         "pickupSeconds": a.pickupSeconds, "hinted": a.hinted]
        if let q = a.question { out["question"] = question(q) }
        out["choices"] = a.choices.map { c -> Node in
            return ["index": c.index, "text": c.text, "position": v(c.position), "color": c.color]
        }
        out["answers"] = a.answers.suffix(300).map { r -> Node in
            return ["id": r.questionId, "correct": r.correct, "hinted": r.hinted, "answer": r.answer,
                    "elapsed": r.decisionElapsedSeconds]
        }
        if let f = a.feedback {
            out["feedback"] = ["id": f.questionId, "answer": f.answer, "explanation": f.explanation,
                               "correct": f.correct, "expires": f.expires] as Node
        }
        return out
    }

    static func applyPersonal(_ a: SplashActor, _ n: Node) {
        let q = n.node("question")
        if q.isEmpty { return }
        guard let restored = question(q) else { return }
        a.autoPickupQuestion = n.str("autoPickupQuestion")
        a.autoPickupIndex = KotlinNumber.int(n.num("autoPickupIndex", -1))
        a.question = restored
        a.sequence = KotlinNumber.int(n.num("sequence"))
        a.questionAt = n.num("questionAt")
        a.pickupSeconds = n.num("pickupSeconds")
        a.hinted = n.flag("hinted")
        a.choices = n.list("choices").map { item -> Choice in
            let c = NodeValue.node(item)
            return Choice(index: KotlinNumber.int(c.num("index")), text: c.str("text"), position: vector(c, "position"),
                          color: KotlinNumber.int(c.num("color")))
        }
        let stored = profile(n.node("profile"))
        for (skill, state) in stored.skills { a.profile.skills[skill] = state }
        a.answers = n.list("answers").map { item -> AnswerRecord in
            let r = NodeValue.node(item)
            return AnswerRecord(questionId: r.str("id"), correct: r.flag("correct"), hinted: r.flag("hinted"),
                                answer: r.str("answer"), decisionElapsedSeconds: r.num("elapsed"))
        }
        let f = n.node("feedback")
        a.feedback = f.isEmpty ? nil : Feedback(questionId: f.str("id"), answer: f.str("answer"),
                                                explanation: f.str("explanation"), correct: f.flag("correct"),
                                                expires: f.num("expires"))
    }

    // MARK: Public snapshot

    static func actorState(_ a: SplashActor) -> Node {
        var heldColor = 5
        if let held = a.held, let choice = a.choices.first(where: { $0.index == held }) { heldColor = choice.color }
        var out: Node = ["passBall": a.passBall, "teamHitCount": a.teamHitCount, "slowHits": a.slowHits,
                         "velocity": v(a.velocity), "travelDistance": a.travelDistance, "travelDirection": v(a.travelDirection),
                         "runBlend": a.runBlend, "throwPower": a.throwPower, "aimDistance": a.aimDistance,
                         "botEvadeReady": a.botEvadeReady]
        if let height = a.aimHeight { out["aimHeight"] = height }
        out["settings"] = settings(a.settings)
        out["facing"] = v(a.facing)
        out["position"] = v(a.position)
        out["direction"] = v(a.direction)
        out["move"] = v(a.move)
        out["held"] = a.held ?? -1
        out["heldColor"] = heldColor
        out["height"] = a.height
        out["verticalSpeed"] = a.verticalSpeed
        out["crouchUntil"] = a.crouchUntil
        out["cleanUntil"] = a.cleanUntil
        out["shieldUntil"] = a.shieldUntil
        out["recoveryUntil"] = a.recoveryUntil
        out["throwAt"] = a.throwAt
        out["windupAt"] = a.windupAt
        out["pickupAt"] = a.pickupAt
        out["hitAt"] = a.hitAt
        out["gait"] = a.gait
        out["score"] = a.score
        out["hits"] = a.hits
        out["misses"] = a.misses
        out["paint"] = a.paint.map { p -> [Any] in return [p.color, p.u, p.v] }
        out["nextBotThink"] = a.nextBotThink
        out["botChoice"] = a.botChoice ?? -1
        out["botThreatId"] = a.botThreatId
        out["botReactAt"] = a.botReactAt
        out["botDodge"] = a.botDodge
        out["botEvadeUntil"] = a.botEvadeUntil
        out["botEvade"] = v(a.botEvade)
        if let target = a.walkTarget { out["walkTarget"] = v(target) }
        return out
    }

    private static func applyActor(_ a: SplashActor, _ n: Node, _ blend: Double) {
        a.passBall = n.flag("passBall")
        a.teamHitCount = KotlinNumber.int(n.num("teamHitCount"))
        a.aimHeight = NodeValue.number(n["aimHeight"])
        a.slowHits = n.list("slowHits").compactMap { NodeValue.number($0) }
        a.velocity = vector(n, "velocity")
        a.travelDistance = n.num("travelDistance")
        a.travelDirection = vector(n, "travelDirection")
        a.runBlend = n.num("runBlend")
        a.throwPower = n.num("throwPower", 1.0)
        a.aimDistance = n.num("aimDistance")
        a.botEvadeReady = n.num("botEvadeReady")
        let pos = vector(n, "position")
        a.position = a.position + (pos - a.position) * blend
        if n.has("settings") { a.settings = settings(n.node("settings")) }
        a.facing = n.has("facing") ? vector(n, "facing") : vector(n, "direction")
        a.walkTarget = n.list("walkTarget").count == 2 ? vector(n, "walkTarget") : nil
        a.direction = vector(n, "direction")
        a.move = vector(n, "move")
        let held = KotlinNumber.int(n.num("held", -1))
        a.held = held >= 0 ? held : nil
        a.publicHeldColor = KotlinNumber.int(n.num("heldColor", 5))
        a.height = n.num("height")
        a.verticalSpeed = n.num("verticalSpeed")
        a.crouchUntil = n.num("crouchUntil")
        a.cleanUntil = n.num("cleanUntil")
        a.shieldUntil = n.num("shieldUntil")
        a.recoveryUntil = n.num("recoveryUntil")
        a.throwAt = n.num("throwAt", -99)
        a.windupAt = n.num("windupAt", -99)
        a.pickupAt = n.num("pickupAt", -99)
        a.hitAt = n.num("hitAt", -99)
        a.gait = n.num("gait")
        a.score = KotlinNumber.int(n.num("score"))
        a.hits = KotlinNumber.int(n.num("hits"))
        a.misses = KotlinNumber.int(n.num("misses"))
        a.nextBotThink = n.num("nextBotThink")
        let botChoice = KotlinNumber.int(n.num("botChoice", -1))
        a.botChoice = botChoice >= 0 ? botChoice : nil
        a.botThreatId = n.str("botThreatId")
        a.botReactAt = n.num("botReactAt")
        a.botDodge = n.flag("botDodge")
        a.botEvadeUntil = n.num("botEvadeUntil")
        a.botEvade = vector(n, "botEvade")
        var paint: [PaintMark] = []
        for item in n.list("paint") {
            guard let mark = item as? [Any], mark.count >= 3,
                  let color = NodeValue.number(mark[0]), let u = NodeValue.number(mark[1]), let pv = NodeValue.number(mark[2]) else { continue }
            paint.append(PaintMark(color: KotlinNumber.int(color), u: u, v: pv))
        }
        a.paint = paint
    }

    // MARK: Results

    static func result(_ r: MatchResult) -> Node {
        return ["id": r.id, "winners": r.winners, "scores": r.scores, "teamScores": r.teamScores, "draw": r.draw,
                "elapsed": r.elapsed]
    }

    static func result(_ n: Node) -> MatchResult? {
        if n.isEmpty { return nil }
        var scores: [String: Int] = [:]
        for (key, value) in n.node("scores") { scores[key] = KotlinNumber.int(NodeValue.number(value) ?? 0) }
        return MatchResult(id: n.str("id"), winners: n.list("winners").map { NodeValue.text($0) }, scores: scores,
                           teamScores: n.list("teamScores").map { KotlinNumber.int(NodeValue.number($0) ?? 0) },
                           draw: n.flag("draw"), elapsed: n.num("elapsed"))
    }

    /// The committed room result replaces a stale authority checkpoint exactly (scores, clock).
    static func applyResult(_ e: SplashEngine, _ r: MatchResult) {
        e.restoreResult(r)
        e.restoreClock(r.elapsed)
        for a in e.actors {
            if let score = r.scores[a.member.id] { a.score = score }
        }
        for (i, score) in r.teamScores.prefix(2).enumerated() where i < e.teamScores.count {
            e.teamScores[i] = score
        }
    }

    // MARK: Drills and paint

    static func drill(_ d: SplashDrillSession) -> Node {
        var incoming: Node = [:]
        for (id, f) in d.incoming { incoming[id] = ["aim": v(f.aim), "passed": f.passed] as Node }
        return ["successes": d.successes, "mistakes": d.mistakes, "wave": d.wave, "nextCue": d.nextCue, "releaseAt": d.releaseAt,
                "lastSuccess": d.lastSuccess, "cueHigh": d.cueHigh, "cueBots": d.cueBots, "resolved": d.resolvedOrder,
                "incoming": incoming]
    }

    static func restoreDrill(_ d: SplashDrillSession, _ n: Node) {
        if n.isEmpty { return }
        d.successes = KotlinNumber.int(n.num("successes"))
        d.mistakes = KotlinNumber.int(n.num("mistakes"))
        d.wave = KotlinNumber.int(n.num("wave"))
        d.nextCue = n.num("nextCue")
        d.releaseAt = n.num("releaseAt", -1.0)
        d.lastSuccess = n.num("lastSuccess", -10.0)
        d.cueHigh = n.flag("cueHigh")
        d.cueBots = n.list("cueBots").map { NodeValue.text($0) }
        d.restoreResolved(n.list("resolved").map { NodeValue.text($0) })
        d.incoming = [:]
        for (id, value) in n.node("incoming") {
            let f = NodeValue.node(value)
            d.incoming[id] = DrillFlight(vector(f, "aim"), passed: f.flag("passed"))
        }
    }

    // MARK: Shared world

    static func shared(_ e: SplashEngine) -> Node {
        var actors: Node = [:]
        for a in e.actors { actors[a.member.id] = actorState(a) }
        var out: Node = ["time": e.time, "actors": actors, "teamScores": e.teamScores]
        if let d = e.drill { out["drill"] = drill(d) }
        let paint = e.paintSession
        out["paintCatches"] = paint.catches
        out["paintWalls"] = paint.walls.map { $0.cells }
        out["paintPoints"] = paint.points
        out["paintThrows"] = paint.throwsTaken
        out["paintSpills"] = paint.spills
        out["paintFailed"] = paint.failed
        out["shots"] = e.shots.map { s -> Node in
            return ["id": s.id, "owner": s.owner, "questionId": s.questionId, "position": v(s.position), "height": s.height,
                    "velocity": v(s.velocity), "vz": s.vz, "color": s.color, "age": s.age]
        }
        out["bursts"] = e.bursts.map { b -> Node in
            var burst: Node = ["id": b.id, "owner": b.owner, "questionId": b.questionId, "position": v(b.position),
                               "height": b.height, "color": b.color, "at": b.at]
            if let hit = b.hit { burst["hit"] = hit }
            return burst
        }
        if let r = e.result { out["result"] = result(r) }
        return out
    }

    static func applyShared(_ e: SplashEngine, _ n: Node, blend: Double = 1.0) {
        if let d = e.drill { restoreDrill(d, n.node("drill")) }
        let paint = e.paintSession
        paint.catches = KotlinNumber.int(n.num("paintCatches"))
        for (i, raw) in n.list("paintWalls").enumerated() where i < paint.walls.count {
            let wall = paint.walls[i]
            for (j, value) in NodeValue.list(raw).prefix(wall.cells.count).enumerated() {
                wall.cells[j] = NodeValue.number(value).map { KotlinNumber.int($0) } ?? -1
            }
        }
        for (i, value) in n.list("paintPoints").prefix(2).enumerated() { paint.points[i] = KotlinNumber.int(NodeValue.number(value) ?? 0) }
        for (i, value) in n.list("paintThrows").prefix(2).enumerated() { paint.throwsTaken[i] = KotlinNumber.int(NodeValue.number(value) ?? 0) }
        paint.spills = KotlinNumber.int(n.num("paintSpills"))
        paint.failed = n.flag("paintFailed")
        e.restoreClock(n.num("time"))
        let states = n.node("actors")
        for a in e.actors {
            if let state = states[a.member.id] { applyActor(a, NodeValue.node(state), blend) }
        }
        for (i, score) in n.list("teamScores").prefix(2).enumerated() where i < e.teamScores.count {
            e.teamScores[i] = KotlinNumber.int(NodeValue.number(score) ?? 0)
        }
        e.shots = n.list("shots").map { item -> Shot in
            let s = NodeValue.node(item)
            return Shot(id: s.str("id"), owner: s.str("owner"), questionId: s.str("questionId"), answer: "", explanation: "",
                        color: KotlinNumber.int(s.num("color")), position: vector(s, "position"), height: s.num("height"),
                        velocity: vector(s, "velocity"), vz: s.num("vz"), age: s.num("age"))
        }
        e.bursts = n.list("bursts").map { item -> Burst in
            let b = NodeValue.node(item)
            return Burst(id: b.str("id"), owner: b.str("owner"), questionId: b.str("questionId"), position: vector(b, "position"),
                         height: b.num("height"), color: KotlinNumber.int(b.num("color")), at: b.num("at"),
                         hit: b["hit"] as? String)
        }
        e.restoreResult(result(n.node("result")))
    }

    // MARK: Authority checkpoint

    static func checkpoint(_ e: SplashEngine) -> Node {
        var privateNodes: Node = [:]
        for a in e.actors { privateNodes[a.member.id] = personal(a) }
        var answers: Node = [:]
        for s in e.shots { answers[s.id] = ["answer": s.answer, "explanation": s.explanation] as Node }
        return ["secret": NSNumber(value: e.questionSecret()), "shared": shared(e), "private": privateNodes,
                "serial": NSNumber(value: e.serialState()), "consumed": e.consumedState(), "shotAnswers": answers]
    }

    static func restore(_ e: SplashEngine, _ n: Node) {
        e.restoreQuestionSecret(NodeValue.int64(n["secret"]) ?? 0)
        applyShared(e, n.node("shared"))
        e.restoreSerial(KotlinNumber.long(n.num("serial")), n.list("consumed").map { NodeValue.text($0) })
        let privateNodes = n.node("private")
        for a in e.actors { applyPersonal(a, privateNodes.node(a.member.id)) }
        let answers = n.node("shotAnswers")
        for i in e.shots.indices {
            let a = answers.node(e.shots[i].id)
            e.shots[i].answer = a.str("answer")
            e.shots[i].explanation = a.str("explanation")
        }
    }

    // MARK: Commands

    static func command(_ c: Command) -> Node {
        switch c {
        case .drillAim(let x, let height): return ["type": "drillAim", "x": x, "height": height]
        case .paintAt(let wall, let u, let v): return ["type": "paintAt", "wall": wall, "u": u, "v": v]
        case .move(let vector): return ["type": "move", "x": vector.x, "y": vector.y]
        case .aim(let vector): return ["type": "aim", "x": vector.x, "y": vector.y]
        case .walkTo(let position, let questionId, let index):
            return ["type": "walkTo", "x": position.x, "y": position.y, "qid": questionId, "index": index]
        case .shootAt(let target): return ["type": "shootAt", "target": target]
        case .pickup(let questionId, let index): return ["type": "pickup", "qid": questionId, "index": index]
        case .throwBalloon: return ["type": "throw"]
        case .jump: return ["type": "jump"]
        case .crouch: return ["type": "crouch"]
        case .hint: return ["type": "hint"]
        }
    }

    static func command(_ n: Node) -> Command? {
        switch n.str("type") {
        case "drillAim": return .drillAim(x: n.num("x"), height: n.num("height"))
        case "paintAt": return .paintAt(wall: KotlinNumber.int(n.num("wall")), u: n.num("u"), v: n.num("v"))
        case "move": return .move(V(n.num("x"), n.num("y")))
        case "aim": return .aim(V(n.num("x"), n.num("y")))
        case "walkTo": return .walkTo(V(n.num("x"), n.num("y")), questionId: n.str("qid"), index: KotlinNumber.int(n.num("index", -1)))
        case "shootAt": return .shootAt(n.str("target"))
        case "pickup": return .pickup(questionId: n.str("qid"), index: KotlinNumber.int(n.num("index", -1)))
        case "throw": return .throwBalloon
        case "jump": return .jump
        case "crouch": return .crouch
        case "hint": return .hint
        default: return nil
        }
    }
}
