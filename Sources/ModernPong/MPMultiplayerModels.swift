import Foundation

enum ModernPongExperience: String, Codable {
    case full, simple
    var online: Bool { self == .full }
    var tournaments: Bool { self == .full }
    var profiles: Bool { self == .full }
    /// Simple hosts hear about every completed match (onClose(result)) and close on Back (onClose(nil)).
    /// Since the 2026-10 owner report a finished match first shows its result instead of closing at once.
    var closesAfterMatch: Bool { self == .simple }
}
struct MPBot: Codable, Equatable {
    var speed: Int; var reaction: Int; var accuracy: Int; var power: Int; var agility: Int
    var characterId: String; var forehandSkill: Int; var backhandSkill: Int; var serveSkill: Int
    var movement: Double { 0.60 + Double(agility) * 0.065 + Double(speed) * 0.025 }
    var strength: Double { Double(speed) * 0.10 + Double(reaction) * 0.12 + Double(accuracy) * 0.08 + Double(power) * 0.12 + Double(agility) * 0.10 + Double(forehandSkill) * 0.20 + Double(backhandSkill) * 0.18 + Double(serveSkill) * 0.10 }
    /// Android `HouseStrategy` skill and `controlTuning` opponent level input.
    var tacticalSkill: Double { Double(forehandSkill + backhandSkill + accuracy) / 3 }
    /// Android `BotProfile.controlTuning`: the character's own skill picks its AI level (9+ HARD, 8+ MEDIUM, 7+ EASY, else STARTER).
    var opponentLevel: MPLevel {
        let skill = tacticalSkill
        return skill >= 9 ? .superHard : skill >= 8 ? .hard : skill >= 7 ? .medium : .easy
    }
    /// `houseControls`: the room/control level selects input forgiveness only; the character owns AI skill and pace.
    func tuning(_ level: MPLevel, houseControls: Bool) -> MPTuning {
        var t = MPTuning.values(houseControls ? opponentLevel : level)
        if characterId != "minik" {
            func success(_ base: Double, _ skill: Int) -> Double { (1 - (1 - base) * Double(11 - skill) / 5).mpClamp(0.05, 0.995) }
            func chance(_ c: MPChance, _ skill: Int) -> MPChance { .init(success(c.answer, skill), success(c.good, skill)) }
            var p = t.profile
            let pace = 1 + Double(power - 6) * 0.025, endurance = (11 - Double(forehandSkill + backhandSkill) / 2) / 5
            p.forehandServe = (0.5 + Double(forehandSkill - backhandSkill) * 0.04).mpClamp(0.2, 0.8)
            p.serveSuccess = success(p.serveSuccess, serveSkill); p.serveMiddle = (p.serveMiddle - Double(serveSkill - 6) * 0.035).mpClamp(0.04, 0.95)
            p.serveSpeed *= pace
            p.serveReceive = p.serveReceive.enumerated().map { chance($0.element, $0.offset == 0 ? backhandSkill : $0.offset == 2 ? forehandSkill : (forehandSkill + backhandSkill) / 2) }
            p.forehandSame = chance(p.forehandSame, forehandSkill); p.forehandCross = chance(p.forehandCross, forehandSkill)
            p.backhandSame = chance(p.backhandSame, backhandSkill); p.backhandCross = chance(p.backhandCross, backhandSkill)
            p.answerDrop *= endurance; p.goodDrop *= endurance; p.backhandCrossGoodDrop *= Double(11 - backhandSkill) / 5
            p.firstForehandSpeed *= pace; p.firstBackhandSpeed *= pace; p.maxSpeed *= pace; t.profile = p
            t.minikReactionInterval *= 1 - Double(reaction - 6) * 0.09
            t.minikMaximumReach = min(0.56, t.minikMaximumReach * (1 + Double(agility - 6) * 0.025))
            t.minikPredictionAmount = (t.minikPredictionAmount + Double(reaction - 6) * 0.012).mpClamp(0.2, 0.995)
            t.minikAimError *= 1 - Double(accuracy - 6) * 0.12
            t.minikErrorProbability = 1 - p.forehandSame.answer; t.minikPoorContactProbability = 1 - p.forehandSame.good
            t.minikForehandPreference = p.forehandServe; t.minikServeFaultProbability = 1 - p.serveSuccess
        }
        if houseControls {
            let input = MPTuning.values(level)
            t.ballBaseSpeed = 0.40; t.gravity = 3.6; t.bounceRestitution = 0.54; t.netHeight = 0.075
            t.tapSpatialTolerance = input.tapSpatialTolerance; t.tapTimingWindow = input.tapTimingWindow; t.tapTimingQualityExponent = input.tapTimingQualityExponent
            t.swipeCollisionForgiveness = input.swipeCollisionForgiveness; t.swipeVelocityScale = input.swipeVelocityScale
            t.minimumSwipeSpeed = input.minimumSwipeSpeed; t.maximumSwipeSpeed = input.maximumSwipeSpeed
            t.serveAssistance = input.serveAssistance; t.incomingVelocityInfluence = input.incomingVelocityInfluence
        }
        return t
    }
}
struct MPHousePlayer: Identifiable {
    var id: String; var english: String; var hebrew: String; var profile: MPBot
    func name(hebrew: Bool) -> String { hebrew ? self.hebrew : english }
}
struct MPIdentity: Codable, Equatable {
    var id: String; var name: String; var avatar = 0; var characterId = ""
    enum CodingKeys: String, CodingKey { case id, name, avatar, characterId }
    init(id: String, name: String, avatar: Int = 0, characterId: String = "") { self.id = id; self.name = name; self.avatar = avatar; self.characterId = characterId }
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id); name = try c.decode(String.self, forKey: .name)
        avatar = try c.decodeIfPresent(Int.self, forKey: .avatar) ?? 0
        characterId = try c.decodeIfPresent(String.self, forKey: .characterId) ?? ""
    }
    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id, forKey: .id); try c.encode(name, forKey: .name); try c.encode(avatar, forKey: .avatar)
        if !characterId.isEmpty { try c.encode(characterId, forKey: .characterId) }
    }
}
struct MPParticipant: Codable, Equatable {
    var identity: MPIdentity; var bot: MPBot?
    var id: String { identity.id }
    func name(hebrew: Bool) -> String { bot.flatMap { MPRoster.find($0.characterId) }?.name(hebrew: hebrew) ?? identity.name }
}
enum MPSessionKind: String, Codable, CaseIterable {
    case friendly = "FRIENDLY", tournament = "TOURNAMENT"
    var path: String { self == .friendly ? "friendlyRooms" : "tournaments" }
}
enum MPMatchPhase: String, Codable { case waiting = "WAITING", ready = "READY", playing = "PLAYING", finished = "FINISHED", cancelled = "CANCELLED" }
struct MPFixture: Codable, Equatable, Identifiable {
    var id: String; var a: String; var b: String; var seed: Int64
    var phase = MPMatchPhase.waiting, ready: [String: Bool] = [:]
    var scoreA = 0, scoreB = 0, winner = "", starts = 0
    var authorityUid: String?
    var terminal: Bool { phase == .finished || phase == .cancelled }
    func contains(_ uid: String) -> Bool { a == uid || b == uid }
    enum CodingKeys: String, CodingKey { case id, a, b, seed, phase, ready, scoreA, scoreB, winner, starts, authorityUid }
    init(id: String, a: String, b: String, seed: Int64) { self.id = id; self.a = a; self.b = b; self.seed = seed }
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id); a = try c.decode(String.self, forKey: .a); b = try c.decode(String.self, forKey: .b)
        seed = try c.decode(Int64.self, forKey: .seed); phase = try c.decode(MPMatchPhase.self, forKey: .phase)
        ready = try c.decodeIfPresent([String: Bool].self, forKey: .ready) ?? [:]
        scoreA = try c.decodeIfPresent(Int.self, forKey: .scoreA) ?? 0; scoreB = try c.decodeIfPresent(Int.self, forKey: .scoreB) ?? 0
        winner = try c.decodeIfPresent(String.self, forKey: .winner) ?? ""; starts = try c.decodeIfPresent(Int.self, forKey: .starts) ?? 0
        authorityUid = try c.decodeIfPresent(String.self, forKey: .authorityUid)
    }
}
/// Android `TournamentFormat`. Only KNOCKOUT is written to the wire (`format`); round robin omits the key.
enum MPTournamentFormat: String, Codable, CaseIterable {
    case roundRobin = "ROUND_ROBIN", knockout = "KNOCKOUT"
    func title(_ he: Bool) -> String { self == .knockout ? (he ? "נוקאאוט" : "Knockout") : (he ? "כולם נגד כולם" : "Round robin") }
}
/// Android `KnockoutRound`; wire `rounds/<n>` = `{count, players}`. An odd draw's last player has the bye.
struct MPKnockoutRound: Codable, Equatable {
    var players: [String]
    var bye: String? { players.count % 2 == 1 ? players.last : nil }
    enum CodingKeys: String, CodingKey { case count, players }
    init(players: [String]) { self.players = players }
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        if let list = try? c.decode([String].self, forKey: .players) { players = list }
        else if let keyed = try? c.decode([String: String].self, forKey: .players) {
            players = keyed.sorted { (Int($0.key) ?? Int.max) < (Int($1.key) ?? Int.max) }.map(\.value)
        } else { players = [] }
    }
    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(players.count, forKey: .count); try c.encode(players, forKey: .players)
    }
}
struct MPSession: Codable, Equatable, Identifiable {
    var code: String; var kind: MPSessionKind; var host: String
    var capacity = 2, legs = 1, winPoints = 3, lossPoints = 0, difficulty = 0, target = 7
    var participants: [String: MPParticipant] = [:], matches: [String: MPFixture] = [:]
    var connections: [String: [String: Bool]] = [:], departed: [String: Bool] = [:]
    var state = "WAITING", createdAt: Int64 = 0, lastActivityAt: Int64 = 0
    var format = MPTournamentFormat.roundRobin
    var rounds: [Int: MPKnockoutRound] = [:]
    /// Android `Session.arena` (a4174b6): "" for older rooms (the original court), otherwise beach / indoors / park /
    /// castle. Written only when non-empty and immutable once the room exists (live rules).
    var arena = ""
    var id: String { kind.path + "/" + code }
    var roster: [String] { participants.keys.sorted() }
    var knockout: Bool { kind == .tournament && format == .knockout }
    /// A knockout is complete when its final is settled (state FINISHED); other rooms when every match is terminal.
    var complete: Bool { knockout ? state == "FINISHED" : !matches.isEmpty && matches.values.allSatisfy(\.terminal) }
    func human(_ uid: String) -> Bool { participants[uid] != nil && participants[uid]?.bot == nil && departed[uid] != true }
    /// Android Session.needsLobbyPresence (7f5dd0a): a lobby visit must not masquerade as an active court
    /// connection, so a player whose match is PLAYING holds no presence outside the court.
    func needsLobbyPresence(_ uid: String) -> Bool { human(uid) && !matches.values.contains { $0.contains(uid) && $0.phase == .playing } }
    func connected(_ uid: String) -> Bool { departed[uid] != true && (participants[uid]?.bot != nil || connections[uid]?.values.contains(true) == true) }
    var connectedHumans: [String] { roster.filter { human($0) && connected($0) } }
    func authority(_ match: MPFixture) -> String { [match.a, match.b].filter { participants[$0]?.bot == nil }.sorted().first ?? host }
    var activity: Int64 { max(createdAt, lastActivityAt) }
    func expired(_ now: Int64) -> Bool { activity > 0 && now - activity >= 14 * 86_400_000 }
    func warning(_ now: Int64) -> Bool { activity > 0 && now - activity >= 7 * 86_400_000 && !expired(now) }
    enum CodingKeys: String, CodingKey { case code, kind, host, capacity, legs, winPoints, lossPoints, difficulty, target, participants, matches, connections, departed, state, createdAt, lastActivityAt, format, rounds, arena }
    /// Android `PongRules.create`: a knockout has up to nine players and a single leg; only tournaments keep a format.
    /// The arena defaults to Park for tournaments and Beach for friendly games; Android requires one of the four
    /// choices, iOS falls back to that default for anything else.
    init(code: String, kind: MPSessionKind, host: MPIdentity, capacity: Int = 2, legs: Int = 1, winPoints: Int = 3, difficulty: Int = 0, target: Int = 7, format: MPTournamentFormat = .roundRobin, arena: String? = nil) {
        self.code = code; self.kind = kind; self.host = host.id
        self.capacity = kind == .friendly ? 2 : min(format == .knockout ? MPKnockout.maxPlayers : 8, max(2, capacity))
        self.legs = format == .knockout ? 1 : min(2, max(1, legs)); self.winPoints = min(10, max(0, winPoints))
        self.difficulty = min(4, max(0, difficulty)); self.target = self.level.target(target)
        self.format = kind == .tournament ? format : .roundRobin
        let fallback = kind == .tournament ? MPArena.park : MPArena.beach
        self.arena = MPArena.choices.first { $0.wire == arena }?.wire ?? fallback.wire
        participants[host.id] = .init(identity: host); createdAt = MPClock.now; lastActivityAt = createdAt
    }
    /// Room level (Android `Difficulty.entries[difficulty]`), including Beginner = 4.
    var level: MPLevel { MPLevel(rawValue: difficulty) ?? .easy }
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        code = try c.decode(String.self, forKey: .code); kind = try c.decode(MPSessionKind.self, forKey: .kind); host = try c.decode(String.self, forKey: .host)
        capacity = try c.decode(Int.self, forKey: .capacity); legs = try c.decode(Int.self, forKey: .legs)
        winPoints = try c.decode(Int.self, forKey: .winPoints); lossPoints = try c.decode(Int.self, forKey: .lossPoints)
        difficulty = try min(4, max(0, c.decode(Int.self, forKey: .difficulty))); target = try c.decode(Int.self, forKey: .target)
        participants = try c.decode([String: MPParticipant].self, forKey: .participants)
        matches = try c.decodeIfPresent([String: MPFixture].self, forKey: .matches) ?? [:]
        connections = try c.decodeIfPresent([String: [String: Bool]].self, forKey: .connections) ?? [:]
        departed = try c.decodeIfPresent([String: Bool].self, forKey: .departed) ?? [:]
        state = try c.decode(String.self, forKey: .state); createdAt = try c.decodeIfPresent(Int64.self, forKey: .createdAt) ?? 0
        lastActivityAt = try c.decodeIfPresent(Int64.self, forKey: .lastActivityAt) ?? createdAt
        // Android PongCodec: any other or missing value is a round robin; round keys are integers.
        let rawFormat = try? c.decodeIfPresent(String.self, forKey: .format)
        format = rawFormat == "KNOCKOUT" ? .knockout : .roundRobin
        let rawRounds = try? c.decodeIfPresent([String: MPKnockoutRound].self, forKey: .rounds)
        var decodedRounds: [Int: MPKnockoutRound] = [:]
        for (key, round) in rawRounds ?? [:] { if let index = Int(key) { decodedRounds[index] = round } }
        rounds = decodedRounds
        // Android PongCodec: `w.text("arena")`, so a missing or non-text value is an older room.
        arena = (try? c.decodeIfPresent(String.self, forKey: .arena)) ?? ""
    }
    /// Same keys as the synthesized encoding, plus Android's knockout-only `format` and `rounds`
    /// (the Firebase rules reject both on a round robin or friendly room).
    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(code, forKey: .code); try c.encode(kind, forKey: .kind); try c.encode(host, forKey: .host)
        try c.encode(capacity, forKey: .capacity); try c.encode(legs, forKey: .legs)
        try c.encode(winPoints, forKey: .winPoints); try c.encode(lossPoints, forKey: .lossPoints)
        try c.encode(difficulty, forKey: .difficulty); try c.encode(target, forKey: .target)
        try c.encode(participants, forKey: .participants); try c.encode(matches, forKey: .matches)
        try c.encode(connections, forKey: .connections); try c.encode(departed, forKey: .departed)
        try c.encode(state, forKey: .state); try c.encode(createdAt, forKey: .createdAt); try c.encode(lastActivityAt, forKey: .lastActivityAt)
        // Android PongCodec writes `arena` only when it is not blank.
        if !arena.trimmingCharacters(in: .whitespaces).isEmpty { try c.encode(arena, forKey: .arena) }
        if knockout {
            try c.encode(format, forKey: .format)
            if !rounds.isEmpty {
                var keyed: [String: MPKnockoutRound] = [:]
                for (index, round) in rounds { keyed[String(index)] = round }
                try c.encode(keyed, forKey: .rounds)
            }
        }
    }
}
enum MPClock { static var now: Int64 { Int64(Date().timeIntervalSince1970 * 1000) } }
enum MPError: String, Error, LocalizedError {
    case code = "Use the six-character room code."
    case full = "This game has already started or is full."
    case missing = "No game or tournament exists with this code."
    case configuration = "Online play is not configured for this build."
    case limit = "You can have up to three open games and three open tournaments."
    case roster = "Fill the roster before starting."
    case duplicate = "This house player is already in the tournament."
    case permission = "This action is not available."
    case invalidResult = "Invalid final score."
    case assistance = "Ball assistance could not be shared. The match uses normal speed until it connects."
    var errorDescription: String? { rawValue }
}
struct MPStanding: Identifiable {
    var id: String; var played = 0, wins = 0, losses = 0, points = 0, pointsFor = 0, pointsAgainst = 0
}
enum MPRules {
    static let alphabet = Array("ABCDEFGHJKLMNPQRSTUVWXYZ23456789")
    static func code() -> String { String((0..<6).map { _ in alphabet.randomElement()! }) }
    static func normalize(_ code: String) throws -> String {
        let value = code.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        guard value.count == 6, value.allSatisfy({ alphabet.contains($0) }) else { throw MPError.code }; return value
    }
    /// Android `PongRules.acceptsNewPlayer`: a scheduled room never takes a new seat.
    static func acceptsNewPlayer(_ s: MPSession) -> Bool { s.state == "WAITING" && s.matches.isEmpty && s.participants.count < s.capacity }
    /// Android `PongRules.canFinishFriendly`: either human participant may Finish (delete) a friendly game, even while playing.
    static func canFinishFriendly(_ s: MPSession, actor: String) -> Bool { s.kind == .friendly && s.human(actor) }
    static func join(_ s: MPSession, _ identity: MPIdentity) throws -> MPSession {
        guard s.departed[identity.id] != true else { throw MPError.permission }
        if s.participants[identity.id] != nil {
            var next = s; if s.state == "WAITING" { next.participants[identity.id]?.identity = identity }; return next
        }
        guard acceptsNewPlayer(s) else { throw MPError.full }
        var n = s; n.participants[identity.id] = .init(identity: identity); return n
    }
    static func add(_ s: MPSession, actor: String, player: MPHousePlayer, hebrew: Bool) throws -> MPSession {
        guard actor == s.host, s.state == "WAITING", s.participants.count < s.capacity else { throw MPError.full }
        guard !s.participants.values.contains(where: { $0.bot?.characterId == player.id }) else { throw MPError.duplicate }
        var n = s; let id = "bot_" + player.id
        n.participants[id] = .init(identity: .init(id: id, name: player.name(hebrew: hebrew), characterId: player.id), bot: player.profile); return n
    }
    /// Android `PongRules.addFriendlyHousePlayer`: the human join and the house-player choice compete for the same
    /// single seat, so a full or started friendly game is returned unchanged.
    static func addFriendlyHousePlayer(_ s: MPSession, actor: String, player: MPParticipant) throws -> MPSession {
        guard s.kind == .friendly, actor == s.host else { throw MPError.permission }
        if s.state != "WAITING" || s.participants.count >= s.capacity { return s }
        guard let bot = player.bot, player.id.hasPrefix("bot_"), s.participants[player.id] == nil else { throw MPError.permission }
        guard bot.characterId.isEmpty || !s.participants.values.contains(where: { $0.bot?.characterId == bot.characterId }) else { throw MPError.duplicate }
        var n = s; n.participants[player.id] = player; return n
    }
    /// Android `PongRules.friendlyHouseReady`: pressing Start on a house player is the host's Ready.
    static func friendlyHouseReady(_ s: MPSession, actor: String) -> MPSession {
        guard s.kind == .friendly, s.state == "ACTIVE", actor == s.host, s.participants.values.filter({ $0.bot != nil }).count == 1,
            s.matches.count == 1, let m = s.matches.values.first, m.phase == .waiting, m.starts == 0 else { return s }
        return (try? ready(s, match: m.id, uid: actor, value: true)) ?? s
    }
    /// A house player as a room participant: Android's random `bot_<uuid>` id and the character's English name.
    static func housePlayer(_ bot: MPBot) -> MPParticipant {
        let character = MPRoster.find(bot.characterId) ?? MPRoster.all[0]
        return MPParticipant(identity: .init(id: "bot_" + UUID().uuidString.replacingOccurrences(of: "-", with: "").lowercased(), name: character.english, characterId: character.id), bot: bot)
    }
    /// Android PlayActivity "Remove <house player>": the host edits a tournament roster before it starts.
    static func removeHouse(_ s: MPSession, actor: String, id: String) throws -> MPSession {
        guard actor == s.host, s.state == "WAITING", s.matches.isEmpty, s.participants[id]?.bot != nil else { throw MPError.permission }
        var n = s; n.participants[id] = nil; return n
    }
    static func start(_ s: MPSession, actor: String) throws -> MPSession {
        guard s.state == "WAITING" else { return s }
        guard actor == s.host, s.participants.count == s.capacity else { throw MPError.roster }
        if s.knockout { return try MPKnockout.start(s) }
        var n = s; n.state = "ACTIVE"
        for leg in 0..<s.legs { for i in 0..<s.roster.count { for j in (i + 1)..<s.roster.count {
            let id = "\(s.code)_\(leg)_\(i)_\(j)"
            let seed = id.utf16.reduce(Int64(17)) { ($0 &* 31) &+ Int64($1) }
            let a = s.roster[leg == 0 ? i : j], b = s.roster[leg == 0 ? j : i]
            var m = MPFixture(id: id, a: a, b: b, seed: seed); m.authorityUid = s.authority(m)
            if let score = simulate(s, m) { m.phase = .finished; m.scoreA = score.a; m.scoreB = score.b; m.winner = score.a > score.b ? a : b }
            n.matches[id] = m
        } } }
        if n.complete { n.state = "FINISHED" }; return n
    }
    /// House player against house player (Android `PongRules.simulate`): scored point by point with the room's
    /// target/deuce rule, completed inside the same durable transition. Nil when either side is human.
    static func simulate(_ s: MPSession, _ m: MPFixture) -> (a: Int, b: Int)? {
        guard let aBot = s.participants[m.a]?.bot, let bBot = s.participants[m.b]?.bot else { return nil }
        var random = MPRandom(seed: UInt64(bitPattern: m.seed)), x = 0, y = 0
        let chance = (0.5 + (aBot.strength - bBot.strength) * 0.055).mpClamp(0.12, 0.88)
        while !validFinal(s, x, y) { if random.unit() < chance { x += 1 } else { y += 1 } }
        return (x, y)
    }
    static func ready(_ s: MPSession, match id: String, uid: String, value: Bool) throws -> MPSession {
        guard var m = s.matches[id], m.contains(uid), s.human(uid) else { throw MPError.permission }
        guard !m.terminal, m.phase != .playing else { return s }
        m.ready[uid] = value ? true : nil; m.phase = m.ready.isEmpty ? .waiting : .ready
        var n = s; n.matches[id] = m; return n
    }
    static func startReady(_ s: MPSession, match id: String) -> MPSession {
        guard var m = s.matches[id], !m.terminal, m.phase != .playing else { return s }
        let humans = [m.a, m.b].filter { s.participants[$0]?.bot == nil }
        guard !humans.isEmpty, humans.allSatisfy({ m.ready[$0] == true && s.connected($0) }),
            !s.matches.values.contains(where: { other in other.id != id && other.phase == .playing && humans.contains(where: other.contains) }) else { return s }
        m.phase = .playing; m.ready = [:]; m.starts += 1; var n = s; n.matches[id] = m; return n
    }
    static func validFinal(_ s: MPSession, _ a: Int, _ b: Int) -> Bool {
        guard a >= 0, b >= 0, a != b, max(a, b) >= s.target else { return false }
        if !s.level.needsTwoPointLead { return max(a, b) == s.target && min(a, b) < s.target }
        return min(a, b) < s.target - 1 ? max(a, b) == s.target : abs(a - b) == 2
    }
    static func finish(_ s: MPSession, match id: String, actor: String, a: Int, b: Int) throws -> MPSession {
        guard var m = s.matches[id] else { throw MPError.missing }
        if m.phase == .finished { return s }
        guard s.authority(m) == actor, m.phase == .playing else { throw MPError.permission }
        guard validFinal(s, a, b) else { throw MPError.invalidResult }
        m.phase = .finished; m.scoreA = a; m.scoreB = b; m.winner = a > b ? m.a : m.b
        var n = s; n.matches[id] = m
        // A knockout redraws only after its whole round has finished.
        if n.knockout { return try MPKnockout.settle(n) }
        if n.complete { n.state = "FINISHED" }; return n
    }
    static func canDelete(_ s: MPSession, actor: String) -> Bool { s.kind == .tournament && s.human(actor) && !s.connectedHumans.contains(where: { $0 != actor }) }
    static func leave(_ s: MPSession, actor: String) throws -> MPSession {
        guard s.kind == .tournament, s.human(actor), let successor = s.connectedHumans.filter({ $0 != actor }).sorted().first else { throw MPError.permission }
        var n = s; if n.host == actor { n.host = successor }; n.connections[actor] = nil
        if s.state == "WAITING" { n.participants[actor] = nil }
        else {
            n.departed[actor] = true
            // A knockout gives the opponent a walkover (no invented score) when the round is settled.
            if n.knockout { n = try MPKnockout.settle(n) }
            else {
                for (id, var m) in s.matches where m.contains(actor) && !m.terminal { m.phase = .cancelled; m.ready = [:]; n.matches[id] = m }
                if n.complete { n.state = "FINISHED" }
            }
        }
        for (id, var m) in n.matches { m.authorityUid = n.authority(m); n.matches[id] = m }; return n
    }
    static func standings(_ s: MPSession) -> [MPStanding] {
        var rows = Dictionary(uniqueKeysWithValues: s.roster.map { ($0, MPStanding(id: $0)) })
        for m in s.matches.values where m.phase == .finished { for id in [m.a, m.b] {
            guard var row = rows[id] else { continue }; let win = id == m.winner
            row.played += 1; row.wins += win ? 1 : 0; row.losses += win ? 0 : 1; row.points += win ? s.winPoints : s.lossPoints
            row.pointsFor += id == m.a ? m.scoreA : m.scoreB; row.pointsAgainst += id == m.a ? m.scoreB : m.scoreA; rows[id] = row
        } }
        return rows.values.sorted {
            if $0.points != $1.points { return $0.points > $1.points }; if $0.wins != $1.wins { return $0.wins > $1.wins }
            if $0.pointsFor - $0.pointsAgainst != $1.pointsFor - $1.pointsAgainst { return $0.pointsFor - $0.pointsAgainst > $1.pointsFor - $1.pointsAgainst }
            if $0.pointsFor != $1.pointsFor { return $0.pointsFor > $1.pointsFor }; return $0.id < $1.id
        }
    }
}
