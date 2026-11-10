import Foundation

// Multi Ping Pong data model: Android multiplayer/PongModels.kt + BotRoster.kt (MinikCrossPong 828c6fc). One fixture is ONE
// match: participants in seat order with one score each (CROSS_DESIGN §7); a classic pair keeps its a/b/scoreA/scoreB view.

enum ModernPongExperience: String, Codable {
    case full, simple
    var online: Bool { self == .full }
    var tournaments: Bool { self == .full }
    var profiles: Bool { self == .full }
    var closesAfterMatch: Bool { self == .simple }
}
struct MPBot: Codable, Equatable {
    var speed: Int; var reaction: Int; var accuracy: Int; var power: Int; var agility: Int
    var characterId: String; var forehandSkill: Int; var backhandSkill: Int; var serveSkill: Int
    var movement: Double { 0.60 + Double(agility) * 0.065 + Double(speed) * 0.025 }
    var strength: Double { Double(speed) * 0.10 + Double(reaction) * 0.12 + Double(accuracy) * 0.08 + Double(power) * 0.12 + Double(agility) * 0.10 + Double(forehandSkill) * 0.20 + Double(backhandSkill) * 0.18 + Double(serveSkill) * 0.10 }
    /// Android `HouseStrategy` skill and `controlTuning` opponent level input.
    var tacticalSkill: Double { Double(forehandSkill + backhandSkill + accuracy) / 3 }
    /// Android `BotProfile.safe()`.
    func safe() -> MPBot {
        func clamp(_ v: Int) -> Int { min(10, max(1, v)) }
        return MPBot(speed: clamp(speed), reaction: clamp(reaction), accuracy: clamp(accuracy), power: clamp(power), agility: clamp(agility),
                     characterId: String(characterId.prefix(24)), forehandSkill: clamp(forehandSkill), backhandSkill: clamp(backhandSkill), serveSkill: clamp(serveSkill))
    }
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
private enum MPBotKeys: String, CodingKey {
    case speed, reaction, accuracy, power, agility, characterId, forehandSkill, backhandSkill, serveSkill
}
extension MPBot {
    /// Android `PongCodec.bot(w)`: a missing stat reads as 5, a missing skill as the accuracy, and the result is `safe()`, so an
    /// older or partial house record never fails to decode (which would drop every participant of its room).
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: MPBotKeys.self)
        func number(_ key: MPBotKeys, _ fallback: Int) -> Int {
            if let whole = try? c.decodeIfPresent(Int.self, forKey: key) { return whole }
            if let real = try? c.decodeIfPresent(Double.self, forKey: key), real.isFinite { return Int(real.mpClamp(-1000, 1000)) }
            return fallback
        }
        let accuracy = number(.accuracy, 5)
        let character: String = (try? c.decodeIfPresent(String.self, forKey: .characterId)) ?? ""
        let raw = MPBot(speed: number(.speed, 5), reaction: number(.reaction, 5), accuracy: accuracy, power: number(.power, 5),
                        agility: number(.agility, 5), characterId: character, forehandSkill: number(.forehandSkill, accuracy),
                        backhandSkill: number(.backhandSkill, accuracy), serveSkill: number(.serveSkill, accuracy))
        self = raw.safe()
    }
    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: MPBotKeys.self)
        try c.encode(speed, forKey: .speed); try c.encode(reaction, forKey: .reaction); try c.encode(accuracy, forKey: .accuracy)
        try c.encode(power, forKey: .power); try c.encode(agility, forKey: .agility); try c.encode(characterId, forKey: .characterId)
        try c.encode(forehandSkill, forKey: .forehandSkill); try c.encode(backhandSkill, forKey: .backhandSkill)
        try c.encode(serveSkill, forKey: .serveSkill)
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
    /// Android `PongCodec.identity(w)`: missing values read as defaults and the result is `safe()`.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let rawId: String = (try? c.decodeIfPresent(String.self, forKey: .id)) ?? ""
        let rawName: String = (try? c.decodeIfPresent(String.self, forKey: .name)) ?? ""
        let rawAvatar: Int = (try? c.decodeIfPresent(Int.self, forKey: .avatar)) ?? 0
        let rawCharacter: String = (try? c.decodeIfPresent(String.self, forKey: .characterId)) ?? ""
        self = MPIdentity(id: rawId, name: rawName, avatar: rawAvatar, characterId: rawCharacter).safe()
    }
    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id, forKey: .id); try c.encode(name, forKey: .name); try c.encode(avatar, forKey: .avatar)
        if !characterId.isEmpty { try c.encode(characterId, forKey: .characterId) }
    }
    /// Android `Identity.safe()`: a trimmed name of at most 18 characters, avatar 0...5, a roster character or none.
    func safe() -> MPIdentity {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        return MPIdentity(id: id, name: String((trimmed.isEmpty ? "Player" : trimmed).prefix(18)), avatar: min(5, max(0, avatar)),
                          characterId: MPRoster.find(characterId)?.id ?? "")
    }
}
/// Android `houseCopy`: the copy number n >= 2 a repeated house player's name ends with (" <n>"), or nil.
func mpHouseCopy(_ name: String) -> Int? {
    guard let space = name.lastIndex(of: " ") else { return nil }
    let digits = name[name.index(after: space)...]
    guard (1...4).contains(digits.count), digits.allSatisfy({ ("0"..."9").contains($0) }), let n = Int(digits), n >= 2 else { return nil }
    return n
}
struct MPParticipant: Codable, Equatable {
    var identity: MPIdentity; var bot: MPBot?
    var id: String { identity.id }
    /// Android `Participant.displayName`: a house character shows its localized name; a repeated one in a tournament keeps its
    /// number ("Kyra 2" / "ספיר 2").
    func name(hebrew: Bool) -> String {
        guard let character = MPRoster.find(bot?.characterId ?? "") else { return identity.name }
        return character.name(hebrew: hebrew) + (mpHouseCopy(identity.name).map { " \($0)" } ?? "")
    }
}
enum MPSessionKind: String, Codable, CaseIterable {
    case friendly = "FRIENDLY", tournament = "TOURNAMENT"
    var path: String { self == .friendly ? "friendlyRooms" : "tournaments" }
}
enum MPMatchPhase: String, Codable { case waiting = "WAITING", ready = "READY", playing = "PLAYING", finished = "FINISHED", cancelled = "CANCELLED" }
/// Android `GameMode`: how a table of three or four plays (a pair always plays the classic game).
enum MPGameMode: String, Codable, CaseIterable {
    /// Scores never drop below 0 (a loss at 0 is forgiven); the first player to reach the target wins.
    case winnerTakesAll = "WINNER_TAKES_ALL"
    /// "Losers drop out": a player whose score would drop below 0 is out at once. When anybody reaches the target, the lowest
    /// score is out instead (a tie for the lowest plays on until it breaks) and the others restart from 0 with one seat fewer;
    /// the last two play a classic duel from 0:0, first to the target.
    case elimination = "ELIMINATION"
    func title(_ he: Bool) -> String {
        self == .elimination ? MPText.t("Elimination", "הדחה", he) : MPText.t("Winner takes all", "המנצח לוקח הכל", he)
    }
    func explanation(_ he: Bool) -> String {
        if self == .elimination {
            return MPText.t("Drop below 0 and you're out. When someone reaches the target, the lowest score is out and the rest restart from 0; the last two play a regular duel.",
                            "מי שיורדים מתחת ל־0 יוצאים מיד. כשמגיעים ליעד, הניקוד הנמוך ביותר יוצא והשאר מתחילים שוב מ־0; השניים האחרונים משחקים דו־קרב רגיל.", he)
        }
        return MPText.t("Scores never drop below 0; the first player to reach the target wins.", "הניקוד לא יורד מתחת ל־0, ומי שמגיעים ראשונים ליעד מנצחים.", he)
    }
}
/// Android `MatchGoal`: one winner; the two survivors of an elimination table that sends two through; or a tie-break for one
/// place, played to a single point (`MPRules.fixtureTarget`).
enum MPMatchGoal: String, Codable { case win = "WIN", topTwo = "TOP_TWO", tiebreak = "TIEBREAK" }

/// Android `MatchRecord` with Android `PongCodec.match` wire names: `players` (seat order), `matchSize`, `scores`, `placement`
/// and `goal` (written only when not WIN). Records saved before seat lists hold a classic pair as a/b/scoreA/scoreB.
struct MPFixture: Codable, Equatable, Identifiable {
    var id: String
    var players: [String]
    var seed: Int64
    var phase = MPMatchPhase.waiting
    var ready: [String: Bool] = [:]
    var scores: [Int]
    var winner = ""
    var starts = 0
    var placement: [String] = []
    var goal = MPMatchGoal.win
    var authorityUid: String?
    var a: String { players.count > 0 ? players[0] : "" }
    var b: String { players.count > 1 ? players[1] : "" }
    var scoreA: Int { scores.count > 0 ? scores[0] : 0 }
    var scoreB: Int { scores.count > 1 ? scores[1] : 0 }
    var terminal: Bool { phase == .finished || phase == .cancelled }
    func contains(_ uid: String) -> Bool { players.contains(uid) }
    func scoreOf(_ uid: String) -> Int {
        guard let i = players.firstIndex(of: uid), i < scores.count else { return 0 }
        return scores[i]
    }
    /// Players who said Ready (Android `ready: Set<String>`).
    var readySet: Set<String> { Set(ready.filter { $0.value }.keys) }
    init(id: String, players: [String], seed: Int64, goal: MPMatchGoal = .win) {
        self.id = id; self.players = players; self.seed = seed; self.goal = goal
        scores = Array(repeating: 0, count: players.count)
    }
    /// Classic pair constructor.
    init(id: String, a: String, b: String, seed: Int64) { self.init(id: id, players: [a, b], seed: seed) }
    enum CodingKeys: String, CodingKey { case id, players, matchSize, seed, phase, ready, scores, winner, starts, placement, goal, authorityUid, a, b, scoreA, scoreB }
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = (try? c.decodeIfPresent(String.self, forKey: .id)) ?? ""
        let listedRaw: [String?] = (try? c.decodeIfPresent([String?].self, forKey: .players)) ?? []
        let listed = listedRaw.compactMap { $0 }
        let raw: [Int?]
        if listed.isEmpty {
            let a: String = (try? c.decodeIfPresent(String.self, forKey: .a)) ?? ""
            let b: String = (try? c.decodeIfPresent(String.self, forKey: .b)) ?? ""
            players = [a, b]
            let scoreA: Int? = try? c.decodeIfPresent(Int.self, forKey: .scoreA)
            let scoreB: Int? = try? c.decodeIfPresent(Int.self, forKey: .scoreB)
            raw = [scoreA, scoreB]
        } else {
            players = listed
            raw = (try? c.decodeIfPresent([Int?].self, forKey: .scores)) ?? []
        }
        scores = players.indices.map { $0 < raw.count ? (raw[$0] ?? 0) : 0 }
        if let exact = try? c.decode(Int64.self, forKey: .seed) { seed = exact }
        else if let value = try? c.decode(Double.self, forKey: .seed), let rounded = Int64(exactly: value.rounded()) { seed = rounded }
        else { seed = 0 }
        let phaseName: String = (try? c.decodeIfPresent(String.self, forKey: .phase)) ?? ""
        phase = MPMatchPhase(rawValue: phaseName) ?? .waiting
        let readyFlags: [String: Bool] = (try? c.decodeIfPresent([String: Bool].self, forKey: .ready)) ?? [:]
        ready = readyFlags.filter { $0.value }
        winner = (try? c.decodeIfPresent(String.self, forKey: .winner)) ?? ""
        starts = (try? c.decodeIfPresent(Int.self, forKey: .starts)) ?? 0
        let placed: [String?] = (try? c.decodeIfPresent([String?].self, forKey: .placement)) ?? []
        placement = placed.compactMap { $0 }
        let goalName: String = (try? c.decodeIfPresent(String.self, forKey: .goal)) ?? ""
        goal = MPMatchGoal(rawValue: goalName) ?? .win
        authorityUid = try? c.decodeIfPresent(String.self, forKey: .authorityUid)
    }
    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id, forKey: .id); try c.encode(players, forKey: .players); try c.encode(players.count, forKey: .matchSize)
        try c.encode(seed, forKey: .seed); try c.encode(phase, forKey: .phase); try c.encode(ready.filter { $0.value }, forKey: .ready)
        try c.encode(scores, forKey: .scores); try c.encode(winner, forKey: .winner); try c.encode(starts, forKey: .starts)
        try c.encode(placement, forKey: .placement)
        if goal != .win { try c.encode(goal, forKey: .goal) }
        if let authorityUid { try c.encode(authorityUid, forKey: .authorityUid) }
    }
}
/// Android `TournamentFormat`. Only KNOCKOUT is written to the wire (`format`); round robin omits the key.
enum MPTournamentFormat: String, Codable, CaseIterable {
    case roundRobin = "ROUND_ROBIN", knockout = "KNOCKOUT"
    func title(_ he: Bool) -> String { self == .knockout ? MPText.t("Knockout", "נוקאאוט", he) : MPText.t("Round robin", "כולם נגד כולם", he) }
}
/// Android `KnockoutRound`. A classic round pairs neighbours and the odd one out has the bye. A group round stores its played
/// tables (`groups`) and its `walkovers` (tables no larger than the number going through, whose players all advance without
/// playing); `players` lists the tables' players, then the walkovers', then `byes` (only rounds drawn before walkovers
/// replaced byes rest players). Wire: `{count, players}` plus `tables`/`byes` for a group round and `walkovers` when it has any.
struct MPKnockoutRound: Codable, Equatable {
    var players: [String]
    var groups: [[String]] = []
    var byes: [String] = []
    var walkovers: [[String]] = []
    private var classic: Bool { groups.isEmpty && walkovers.isEmpty }
    var tables: [[String]] {
        guard classic else { return groups }
        return stride(from: 0, to: players.count - 1, by: 2).map { [players[$0], players[$0 + 1]] }
    }
    var bye: String? {
        if classic { return players.count % 2 == 1 ? players.last : nil }
        return byes.first
    }
    /// Everybody who goes through without playing: the bye, the byes and the walkover tables.
    var resting: [String] {
        if classic { return bye.map { [$0] } ?? [] }
        return byes + walkovers.flatMap { $0 }
    }
    /// A single fixture and nobody resting: its winner takes the tournament.
    var isFinal: Bool { tables.count == 1 && resting.isEmpty }
    enum CodingKeys: String, CodingKey { case count, players, tables, byes, walkovers }
    init(players: [String], groups: [[String]] = [], byes: [String] = [], walkovers: [[String]] = []) {
        self.players = players; self.groups = groups; self.byes = byes; self.walkovers = walkovers
    }
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        if let list = try? c.decode([String?].self, forKey: .players) { players = list.compactMap { $0 } }
        else if let keyed = try? c.decode([String: String].self, forKey: .players) {
            var indexed: [(Int, String)] = []
            for (key, value) in keyed { if let index = Int(key) { indexed.append((index, value)) } }
            players = indexed.sorted { $0.0 < $1.0 }.map { $0.1 }
        } else { players = [] }
        let tableLists: [[String?]?] = (try? c.decodeIfPresent([[String?]?].self, forKey: .tables)) ?? []
        groups = tableLists.compactMap { $0?.compactMap { $0 } }.filter { !$0.isEmpty }
        let byeList: [String?] = (try? c.decodeIfPresent([String?].self, forKey: .byes)) ?? []
        byes = byeList.compactMap { $0 }
        let walkoverLists: [[String?]?] = (try? c.decodeIfPresent([[String?]?].self, forKey: .walkovers)) ?? []
        walkovers = walkoverLists.compactMap { $0?.compactMap { $0 } }.filter { !$0.isEmpty }
    }
    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(players.count, forKey: .count); try c.encode(players, forKey: .players)
        if !groups.isEmpty || !walkovers.isEmpty { try c.encode(groups, forKey: .tables); try c.encode(byes, forKey: .byes) }
        if !walkovers.isEmpty { try c.encode(walkovers, forKey: .walkovers) }
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
    /// Players per fixture: 2 (the classic table) or 3/4 (the cross table).
    var tableSize = 2
    /// Friendly seat choice before the start (Android `Session.seats`).
    var seats: [String: Int] = [:]
    /// Friendly and tournament tables of 3 or 4; a pair always plays the classic game.
    var gameMode = MPGameMode.winnerTakesAll
    /// Players going through from each knockout table of 3 or 4: 1 or 2.
    var advance = 2
    var id: String { kind.path + "/" + code }
    var roster: [String] { participants.keys.sorted() }
    var knockout: Bool { kind == .tournament && format == .knockout }
    /// A tournament played at tables of 3 or 4 (`MPGroupTournament`); tableSize 2 is the classic pair format.
    var grouped: Bool { kind == .tournament && tableSize >= 3 }
    /// A knockout is complete when its final is settled (state FINISHED); other rooms when every match is terminal.
    var complete: Bool { knockout ? state == "FINISHED" : !matches.isEmpty && matches.values.allSatisfy(\.terminal) }
    func human(_ uid: String) -> Bool { participants[uid] != nil && participants[uid]?.bot == nil && departed[uid] != true }
    /// Android Session.needsLobbyPresence: a lobby visit must not masquerade as an active court connection, so a player whose
    /// match is PLAYING holds no presence outside the court.
    func needsLobbyPresence(_ uid: String) -> Bool { human(uid) && !matches.values.contains { $0.contains(uid) && $0.phase == .playing } }
    func connected(_ uid: String) -> Bool { departed[uid] != true && (participants[uid]?.bot != nil || connections[uid]?.values.contains(true) == true) }
    var connectedHumans: [String] { roster.filter { human($0) && connected($0) } }
    /// Lexicographically smallest HUMAN uid of the fixture; the host for a house-only fixture.
    func authority(_ match: MPFixture) -> String { match.players.filter { participants[$0]?.bot == nil }.min() ?? host }
    var activity: Int64 { max(createdAt, lastActivityAt) }
    func expired(_ now: Int64) -> Bool { activity > 0 && now - activity >= 14 * 86_400_000 }
    func warning(_ now: Int64) -> Bool { activity > 0 && now - activity >= 7 * 86_400_000 && !expired(now) }
    /// Friendly seats in [0, tableSize). Rooms saved before seats existed seat their players deterministically (host first, then
    /// by id) in the lowest free seats.
    func seating() -> [String: Int] {
        var result: [String: Int] = [:]
        let chosen = seats.sorted { $0.value != $1.value ? $0.value < $1.value : $0.key < $1.key }
        for (uid, seat) in chosen where participants[uid] != nil && seat >= 0 && seat < tableSize && !result.values.contains(seat) { result[uid] = seat }
        let order = participants.keys.sorted { ($0 != host ? 1 : 0, $0) < ($1 != host ? 1 : 0, $1) }
        for uid in order where result[uid] == nil {
            var free = 0
            while result.values.contains(free) { free += 1 }
            result[uid] = free
        }
        return result
    }
    func freeSeats() -> [Int] {
        let taken = Set(seating().values)
        return (0..<max(0, tableSize)).filter { !taken.contains($0) }
    }
    enum CodingKeys: String, CodingKey { case code, kind, host, capacity, legs, winPoints, lossPoints, difficulty, target, participants, matches, connections, departed, state, createdAt, lastActivityAt, format, rounds, tableSize, seats, gameMode, advance }
    /// Android `PongRules.create`: a friendly room seats one table of `tableSize` (2...4) players. A tournament seats every
    /// fixture at `tableSize` players: 2 keeps the classic pairs (2...8 or 2...9 players); 3 or 4 plays group tables (3...8
    /// players in a round robin, 3...32 in a knockout). `gameMode` applies to tables of 3 or 4 (a pair plays the classic game);
    /// `advance` (1 or 2 per table) only to a knockout at tables of 3 or 4.
    init(code: String, kind: MPSessionKind, host: MPIdentity, capacity: Int = 2, legs: Int = 1, winPoints: Int = 3, difficulty: Int = 0, target: Int = 7,
         format: MPTournamentFormat = .roundRobin, tableSize: Int = 2, gameMode: MPGameMode = .winnerTakesAll, advance: Int = 2) {
        let friendly = kind == .friendly
        // Android bb8acda: a two-player tournament is a pair, even when an older setup retained a Y/cross table.
        let table = !friendly && capacity == 2 ? 2 : MPGroupTournament.tableSize(tableSize)
        self.code = code; self.kind = kind; self.host = host.id
        if friendly { self.capacity = table }
        else if table > 2 { self.capacity = MPGroupTournament.capacity(capacity, format) }
        else { self.capacity = min(format == .knockout ? MPKnockout.maxPairPlayers : 8, max(2, capacity)) }
        self.legs = format == .knockout ? 1 : min(2, max(1, legs)); self.winPoints = min(10, max(0, winPoints))
        let level = min(4, max(0, difficulty))
        self.difficulty = level; self.target = (MPLevel(rawValue: level) ?? .easy).target(target)
        self.format = kind == .tournament ? format : .roundRobin
        self.tableSize = table
        participants[host.id] = .init(identity: host.safe())
        seats = friendly ? [host.id: 0] : [:]
        self.gameMode = table > 2 ? gameMode : .winnerTakesAll
        self.advance = !friendly && format == .knockout && table > 2 ? min(2, max(1, advance)) : 2
        createdAt = MPClock.now; lastActivityAt = createdAt
    }
    /// Room level (Android `Difficulty.entries[difficulty]`), including Beginner = 4.
    var level: MPLevel { MPLevel(rawValue: difficulty) ?? .easy }
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        code = try c.decode(String.self, forKey: .code); host = try c.decode(String.self, forKey: .host)
        let kindName: String = (try? c.decodeIfPresent(String.self, forKey: .kind)) ?? ""
        kind = MPSessionKind(rawValue: kindName) ?? .friendly
        capacity = (try? c.decodeIfPresent(Int.self, forKey: .capacity)) ?? 2
        legs = (try? c.decodeIfPresent(Int.self, forKey: .legs)) ?? 1
        winPoints = (try? c.decodeIfPresent(Int.self, forKey: .winPoints)) ?? 3
        lossPoints = (try? c.decodeIfPresent(Int.self, forKey: .lossPoints)) ?? 0
        let level: Int = (try? c.decodeIfPresent(Int.self, forKey: .difficulty)) ?? 0
        difficulty = min(4, max(0, level))
        target = (try? c.decodeIfPresent(Int.self, forKey: .target)) ?? 7
        participants = (try? c.decodeIfPresent([String: MPParticipant].self, forKey: .participants)) ?? [:]
        matches = (try? c.decodeIfPresent([String: MPFixture].self, forKey: .matches)) ?? [:]
        connections = (try? c.decodeIfPresent([String: [String: Bool]].self, forKey: .connections)) ?? [:]
        let leftFlags: [String: Bool] = (try? c.decodeIfPresent([String: Bool].self, forKey: .departed)) ?? [:]
        departed = leftFlags.filter { $0.value }
        state = (try? c.decodeIfPresent(String.self, forKey: .state)) ?? "WAITING"
        createdAt = (try? c.decodeIfPresent(Int64.self, forKey: .createdAt)) ?? 0
        lastActivityAt = (try? c.decodeIfPresent(Int64.self, forKey: .lastActivityAt)) ?? 0
        // Android PongCodec: any other or missing value is a round robin; round keys are integers.
        let rawFormat: String? = try? c.decodeIfPresent(String.self, forKey: .format)
        format = rawFormat == "KNOCKOUT" ? .knockout : .roundRobin
        let rawRounds: [String: MPKnockoutRound] = (try? c.decodeIfPresent([String: MPKnockoutRound].self, forKey: .rounds)) ?? [:]
        var decodedRounds: [Int: MPKnockoutRound] = [:]
        for (key, round) in rawRounds { if let index = Int(key) { decodedRounds[index] = round } }
        rounds = decodedRounds
        // Rooms saved before table sizes and seats were classic two-player rooms; rooms saved before game modes play winner
        // takes all and send two through from every knockout table.
        let table: Int = (try? c.decodeIfPresent(Int.self, forKey: .tableSize)) ?? 2
        tableSize = min(4, max(2, table))
        seats = (try? c.decodeIfPresent([String: Int].self, forKey: .seats)) ?? [:]
        let modeName: String = (try? c.decodeIfPresent(String.self, forKey: .gameMode)) ?? ""
        gameMode = MPGameMode(rawValue: modeName) ?? .winnerTakesAll
        let through: Int = (try? c.decodeIfPresent(Int.self, forKey: .advance)) ?? 2
        advance = min(2, max(1, through))
    }
    /// Android `PongCodec.session`: the same keys, `tableSize` and `seats` always, `gameMode` only when not winner takes all, and
    /// the knockout-only `format`, `rounds` and `advance` (only when not 2) — the Firebase rules reject them elsewhere.
    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(code, forKey: .code); try c.encode(kind, forKey: .kind); try c.encode(host, forKey: .host)
        try c.encode(capacity, forKey: .capacity); try c.encode(tableSize, forKey: .tableSize); try c.encode(legs, forKey: .legs)
        try c.encode(winPoints, forKey: .winPoints); try c.encode(lossPoints, forKey: .lossPoints)
        try c.encode(difficulty, forKey: .difficulty); try c.encode(target, forKey: .target)
        try c.encode(participants, forKey: .participants); try c.encode(seats, forKey: .seats); try c.encode(matches, forKey: .matches)
        try c.encode(connections, forKey: .connections); try c.encode(departed, forKey: .departed)
        try c.encode(state, forKey: .state); try c.encode(createdAt, forKey: .createdAt); try c.encode(lastActivityAt, forKey: .lastActivityAt)
        if gameMode != .winnerTakesAll { try c.encode(gameMode, forKey: .gameMode) }
        if knockout {
            try c.encode(format, forKey: .format)
            if !rounds.isEmpty {
                var keyed: [String: MPKnockoutRound] = [:]
                for (index, round) in rounds { keyed[String(index)] = round }
                try c.encode(keyed, forKey: .rounds)
            }
            if advance != 2 { try c.encode(advance, forKey: .advance) }
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
    case left = "You have left this tournament."
    case seatTaken = "This seat is taken."
    // Android 9adf1f1 SavedLobbyRollback.restore (its `require` messages; PlayActivity.error shows the general explanation).
    case rollbackChanged = "The room has changed or started. Reopen it before discarding changes."
    case rollbackPeerEdit = "The player list changed on another device. Reopen it before discarding changes."
    case rollbackFull = "The room has new players and cannot restore the earlier player list."
    case rollbackSeat = "A saved seat is now occupied. Reopen the room before discarding changes."
    // Android 83b050d LocalPongRepository / RoomBook (`check` and `error` messages).
    case saveFailed = "Could not save the game."
    case noSave = "No saved game."
    var errorDescription: String? { rawValue }
}

/// Android 5375378 / 1fc4bc2 `FriendlyRematch`: direct bot rematches. Other humans must not be enrolled without their own
/// readiness.
enum MPFriendlyRematch {
    static func available(_ s: MPSession, uid: String) -> Bool {
        s.kind == .friendly && s.complete && s.participants[uid] != nil && s.participants[uid]?.bot == nil &&
            s.participants.values.allSatisfy { $0.id == uid || $0.bot != nil }
    }
    /// The same room settings and roster (with their seats) under a new code, hosted by `uid`, without matches, presence,
    /// departures or knockout rounds.
    static func create(_ s: MPSession, uid: String, code: String, now: Int64) throws -> MPSession {
        guard available(s, uid: uid) else { throw MPError.permission }
        var next = s
        next.code = code; next.host = uid; next.matches = [:]; next.connections = [:]; next.state = "WAITING"
        next.createdAt = now; next.lastActivityAt = now; next.departed = [:]; next.rounds = [:]
        return next
    }
}

/// Android 9adf1f1 `SavedLobbyRollback`: undo the host's unsaved house-player edits without overwriting online peers.
enum MPSavedLobbyRollback {
    static func available(_ saved: MPSession, _ current: MPSession, uid: String) -> Bool {
        saved.code == current.code && saved.kind == current.kind && saved.host == uid && current.host == uid &&
            saved.state == "WAITING" && current.state == "WAITING" && saved.matches.isEmpty && current.matches.isEmpty
    }
    static func restore(_ saved: MPSession, edited: MPSession, latest: MPSession, uid: String) throws -> MPSession {
        guard available(saved, edited, uid: uid) && available(saved, latest, uid: uid) else { throw MPError.rollbackChanged }
        let savedBots = saved.participants.filter { $0.value.bot != nil }
        let editedBots = edited.participants.filter { $0.value.bot != nil }
        let latestBots = latest.participants.filter { $0.value.bot != nil }
        // A retry may observe peer joins or presence changes; preserve them. A different host session editing the roster must
        // not be silently overwritten.
        guard latestBots == editedBots else { throw MPError.rollbackPeerEdit }
        let people = latest.participants.filter { $0.value.bot == nil }.merging(savedBots) { _, bot in bot }
        guard people.count <= latest.capacity else { throw MPError.rollbackFull }
        var restored = latest
        restored.participants = people
        if latest.kind == .tournament { return restored }
        var seats = latest.seating().filter { latest.participants[$0.key]?.bot == nil }
        let savedSeating = saved.seating()
        // Kotlin walks the saved house players in insertion order; a sorted walk gives the same seats or the same refusal.
        for id in savedBots.keys.sorted() {
            guard let old = savedSeating[id] else { throw MPError.rollbackSeat }
            guard !seats.values.contains(old) else { throw MPError.rollbackSeat }
            seats[id] = old
        }
        restored.seats = seats
        return restored
    }
}

/// Android 83b050d `SaveComparison`: compare game state, excluding transport counters and lobby-presence housekeeping. Numbers
/// compare as doubles (Kotlin `Number.toDouble()`); a JSON boolean stays a boolean.
enum MPSaveComparison {
    static let housekeeping: Set<String> = ["connections", "lastActivityAt", "revision", "serverAt", "clientAt"]
    static func meaningful(_ value: Any?) -> Any {
        guard let value else { return NSNull() }
        switch value {
        case let map as [String: Any]:
            var out: [String: Any] = [:]
            for (key, item) in map where !housekeeping.contains(key) { out[key] = meaningful(item) }
            return out
        case let list as [Any]: return list.map { meaningful($0) }
        case let number as NSNumber:
            if CFGetTypeID(number) == CFBooleanGetTypeID() { return number.boolValue }
            return number.doubleValue
        default: return value
        }
    }
    /// Structural equality of two `meaningful` values.
    static func equal(_ a: Any, _ b: Any) -> Bool {
        switch (a, b) {
        case let (x as [String: Any], y as [String: Any]):
            return x.count == y.count && x.allSatisfy { key, value in y[key].map { equal(value, $0) } ?? false }
        case let (x as [Any], y as [Any]):
            return x.count == y.count && zip(x, y).allSatisfy { equal($0, $1) }
        case let (x as Bool, y as Bool): return x == y
        case let (x as Double, y as Double): return x == y
        case let (x as String, y as String): return x == y
        case (is NSNull, is NSNull): return true
        default: return false
        }
    }
    /// A value as stored and read back as JSON (Android keeps its saves as `JsonWire` text).
    static func json(_ value: Any) -> Any? {
        guard JSONSerialization.isValidJSONObject(value), let data = try? JSONSerialization.data(withJSONObject: value) else { return nil }
        return try? JSONSerialization.jsonObject(with: data)
    }
    static func same(_ a: MPSession, _ b: MPSession) -> Bool {
        guard let left = try? MPCodec.session(a), let right = try? MPCodec.session(b) else { return false }
        return equal(meaningful(json(left)), meaningful(json(right)))
    }
}
struct MPStanding: Identifiable, Equatable {
    var id: String; var played = 0, wins = 0, losses = 0, points = 0, pointsFor = 0, pointsAgainst = 0
}
/// Final scores in seat order and every participant ranked, winner first (Android `TableResult`).
struct MPTableResult: Equatable {
    var scores: [Int]
    var placement: [String]
}

enum MPRules {
    static let alphabet = Array("ABCDEFGHJKLMNPQRSTUVWXYZ23456789")
    static func code() -> String { String((0..<6).map { _ in alphabet.randomElement()! }) }
    static func normalize(_ code: String) throws -> String {
        let value = code.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        guard value.count == 6, value.allSatisfy({ alphabet.contains($0) }) else { throw MPError.code }; return value
    }
    /// A tie-break is played to one point; every other fixture to the room's target.
    static func fixtureTarget(_ s: MPSession, _ m: MPFixture) -> Int { m.goal == .tiebreak ? 1 : s.target }
    /// An ELIMINATION table of 3 or 4: played until two are left, ranked by elimination order. Pairs and tie-breaks rank by score.
    static func eliminates(_ s: MPSession, _ m: MPFixture) -> Bool { m.players.count > 2 && (m.goal == .topTwo || m.goal == .win && s.gameMode == .elimination) }

    // ---- Final duels: an ELIMINATION table that must produce one winner hands its two survivors to a classic pair ----
    /// The final duel of table `tableId`.
    static func duelId(_ tableId: String) -> String { tableId + "_D" }
    static func isDuel(_ m: MPFixture) -> Bool { m.id.hasSuffix("_D") }
    static func duelOf(_ s: MPSession, _ m: MPFixture) -> MPFixture? { s.matches[duelId(m.id)] }
    /// The table a duel decides; nil for any other fixture.
    static func tableOf(_ s: MPSession, _ m: MPFixture) -> MPFixture? { isDuel(m) ? s.matches[String(m.id.dropLast(2))] : nil }
    /// A finished ELIMINATION table of 3 or 4 that must produce one winner (goal WIN: the friendly table, a knockout table sending
    /// one through, the final table, every round-robin table); a TOP_TWO table sends both survivors on instead.
    static func needsDuel(_ s: MPSession, _ m: MPFixture) -> Bool { m.phase == .finished && m.goal == .win && m.players.count > 2 && s.gameMode == .elimination }
    /// Adds `m`'s final duel once, in the transition that stores the table: the table's placement[0] against placement[1], the
    /// room target and the classic pair rules (the two-point lead where the difficulty needs it). A house-only duel is played live
    /// when the friendly-room host is watching; tournament-only fixtures are simulated (Android 1fc4bc2).
    static func withDuel(_ s: MPSession, _ m: MPFixture) -> MPSession {
        let id = duelId(m.id)
        if !needsDuel(s, m) || s.matches[id] != nil || m.placement.count < 2 { return s }
        var duel = MPFixture(id: id, players: Array(m.placement.prefix(2)), seed: crossFold(id, m.seed))
        // Like every other new fixture: the stored authority equals what the codec writes, so a round trip compares equal.
        duel.authorityUid = s.authority(duel)
        var n = s
        n.matches[id] = houseOnly(s, duel) && s.kind != .friendly ? simulated(s, duel) : duel
        return n
    }
    /// Android 1fc4bc2 `spectatedDuel`: the friendly host watches the live final duel of two house players.
    static func spectatedDuel(_ s: MPSession, _ m: MPFixture, uid: String) -> Bool {
        s.kind == .friendly && s.host == uid && isDuel(m) && houseOnly(s, m) && s.human(uid)
    }
    /// Android 1fc4bc2 `startSpectatedDuel`: the watching host starts the house players' final duel once.
    static func startSpectatedDuel(_ s: MPSession, id: String, actor: String) -> MPSession {
        guard var m = s.matches[id] else { return s }
        if !spectatedDuel(s, m, uid: actor) || m.terminal || m.phase == .playing { return s }
        m.phase = .playing; m.starts = 1
        var n = s; n.matches[id] = m; return n
    }
    private static func stays(_ s: MPSession, _ uid: String) -> Bool { s.participants[uid] != nil && s.departed[uid] != true }
    /// Kotlin `players.sortedByDescending(m::scoreOf)`: higher score first, seat order on ties (a stable sort).
    private static func byScore(_ m: MPFixture) -> [String] {
        let order = m.players.indices.sorted { a, b in
            let left = m.scoreOf(m.players[a]), right = m.scoreOf(m.players[b])
            if left != right { return left > right }
            return a < b
        }
        return order.map { m.players[$0] }
    }
    /// A finished table's final order: its placement, or for a table with a final duel the duel's winner and loser (the player
    /// still in the tournament first when the duel was cancelled) ahead of the others; nil while the duel is open.
    static func ranking(_ s: MPSession, _ m: MPFixture) -> [String]? {
        if m.phase != .finished { return nil }
        let stored = m.placement.isEmpty ? byScore(m) : m.placement
        if !needsDuel(s, m) { return stored }
        guard let duel = duelOf(s, m) else { return nil }
        let top: [String]
        switch duel.phase {
        case .finished: top = [duel.winner] + duel.players.filter { $0 != duel.winner }
        case .cancelled:
            // Kotlin sortedBy { !stays }: the player still in the tournament first, otherwise seat order.
            let staying = duel.players.filter { stays(s, $0) }
            top = staying + duel.players.filter { !staying.contains($0) }
        default: return nil
        }
        return top + stored.filter { !duel.players.contains($0) }
    }
    /// The winner a finished fixture finally produces: its own winner, or for a table with a final duel the duel's winner (the
    /// remaining player of a cancelled duel); nil while that duel is open.
    static func finalWinner(_ s: MPSession, _ m: MPFixture) -> String? {
        if needsDuel(s, m) { return ranking(s, m)?.first }
        return m.phase == .finished ? m.winner : nil
    }
    /// Android `PongRules.acceptsNewPlayer`: a scheduled room never takes a new seat.
    static func acceptsNewPlayer(_ s: MPSession) -> Bool { s.state == "WAITING" && s.matches.isEmpty && s.participants.count < s.capacity }
    /// Android `PongRules.canFinishFriendly`: either human participant may Finish (delete) a friendly game, even while playing.
    static func canFinishFriendly(_ s: MPSession, actor: String) -> Bool { s.kind == .friendly && s.human(actor) }
    static func join(_ s: MPSession, _ identity: MPIdentity) throws -> MPSession {
        guard s.departed[identity.id] != true else { throw MPError.left }
        if s.participants[identity.id] != nil {
            var next = s; if s.state == "WAITING" { next.participants[identity.id]?.identity = identity.safe() }; return next
        }
        guard acceptsNewPlayer(s) else { throw MPError.full }
        var n = s; n.participants[identity.id] = .init(identity: identity.safe())
        if s.kind == .friendly {
            guard let free = s.freeSeats().first else { throw MPError.full }
            n.seats = s.seating(); n.seats[identity.id] = free
        }
        return n
    }
    /// Android `BotRoster` + `participant(c)`: a house player with a unique "bot_<32 hex>" id and the character's English name.
    static func housePlayer(_ player: MPHousePlayer) -> MPParticipant {
        let id = "bot_" + UUID().uuidString.replacingOccurrences(of: "-", with: "").lowercased()
        return MPParticipant(identity: MPIdentity(id: id, name: player.english, characterId: player.id), bot: player.profile)
    }
    /// The copy number the next house player of `characterId` gets: 1 while the character is not there (and for a house player
    /// without a character), otherwise the smallest n >= 2 that none of its copies is numbered with.
    static func copyNumber(_ s: MPSession, _ characterId: String) -> Int {
        let copies = s.participants.values.filter { !characterId.trimmingCharacters(in: .whitespaces).isEmpty && $0.bot?.characterId == characterId }
        if copies.isEmpty { return 1 }
        let used = Set(copies.compactMap { mpHouseCopy($0.identity.name) })
        var n = 2
        while used.contains(n) { n += 1 }
        return n
    }
    /// House players take the lowest free friendly seat unless the host places them in a free `seat`. A friendly room seats each
    /// house character once; a tournament may repeat one, named "<English name> <n>".
    static func addBot(_ s: MPSession, actor: String, bot: MPParticipant, seat: Int? = nil) throws -> MPSession {
        guard actor == s.host, s.state == "WAITING", s.participants.count < s.capacity, let profile = bot.bot else { throw MPError.full }
        guard bot.id.hasPrefix("bot_"), s.participants[bot.id] == nil else { throw MPError.permission }
        let character = profile.characterId
        let copy = copyNumber(s, character)
        guard copy == 1 || s.kind == .tournament else { throw MPError.duplicate }
        var identity = bot.identity
        if copy != 1 {
            let suffix = " \(copy)"
            let base = (MPRoster.find(character)?.english ?? bot.identity.name.trimmingCharacters(in: .whitespaces))
            identity.name = String(base.prefix(max(0, 18 - suffix.count))).trimmingCharacters(in: .whitespaces) + suffix
        }
        var added = s
        added.participants[bot.id] = MPParticipant(identity: identity.safe(), bot: profile.safe())
        if s.kind != .friendly {
            guard seat == nil else { throw MPError.permission }
            return added
        }
        let free = s.freeSeats()
        guard let chosen = seat ?? free.first else { throw MPError.full }
        guard free.contains(chosen) else { throw MPError.seatTaken }
        added.seats = s.seating(); added.seats[bot.id] = chosen
        return added
    }
    /// The host fills a waiting tournament with house players until it is full: characters not yet in it first, then repeats;
    /// each time the character with the fewest house copies, in roster order on ties.
    static func fillWithBots(_ s: MPSession, actor: String) throws -> MPSession {
        guard s.kind == .tournament, s.state == "WAITING", actor == s.host else { throw MPError.permission }
        var next = s
        while next.participants.count < next.capacity {
            let counts = MPRoster.all.map { c in next.participants.values.filter { $0.bot?.characterId == c.id }.count }
            guard let fewest = counts.min(), let index = counts.firstIndex(of: fewest) else { break }
            next = try addBot(next, actor: actor, bot: housePlayer(MPRoster.all[index]))
        }
        return next
    }
    /// The human join and house-player choice compete for the same seats; a human who got there first keeps it.
    static func addFriendlyHousePlayer(_ s: MPSession, actor: String, bot: MPParticipant, seat: Int? = nil) throws -> MPSession {
        guard s.kind == .friendly, actor == s.host else { throw MPError.permission }
        if let seat, !(0..<s.tableSize).contains(seat) { throw MPError.permission }
        if s.state != "WAITING" || s.participants.count >= s.capacity { return s }
        if let seat, !s.freeSeats().contains(seat) { return s }
        return try addBot(s, actor: actor, bot: bot, seat: seat)
    }
    /// Before the start a human may move to a free seat; nobody moves another player.
    static func chooseSeat(_ s: MPSession, actor: String, seat: Int) throws -> MPSession {
        guard s.kind == .friendly, s.state == "WAITING", s.matches.isEmpty, s.human(actor), (0..<s.tableSize).contains(seat) else { throw MPError.permission }
        let seating = s.seating()
        if seating[actor] == seat { return s }
        guard !seating.contains(where: { $0.key != actor && $0.value == seat }) else { throw MPError.seatTaken }
        var n = s; n.seats = seating; n.seats[actor] = seat
        return n
    }
    /// The host removes a house player before the start (Android PlayActivity "Remove", which also frees its friendly seat).
    static func removeHouse(_ s: MPSession, actor: String, id: String) throws -> MPSession {
        guard actor == s.host, s.state == "WAITING", s.matches.isEmpty, s.participants[id]?.bot != nil else { throw MPError.permission }
        var n = s; n.participants[id] = nil; n.seats[id] = nil; return n
    }
    /// Android "Remove all house players" on a waiting tournament.
    static func removeAllHouse(_ s: MPSession, actor: String) throws -> MPSession {
        guard actor == s.host, s.state == "WAITING", s.matches.isEmpty else { throw MPError.permission }
        var n = s; n.participants = s.participants.filter { $0.value.bot == nil }; return n
    }
    /// Pressing Start with house players only is the host's Ready action (any table size, and the final duel); when another
    /// human sits at the table, every human still chooses Ready.
    static func friendlyHouseReady(_ s: MPSession, actor: String) -> MPSession {
        if s.kind != .friendly || s.state != "ACTIVE" || actor != s.host { return s }
        if !s.participants.values.contains(where: { $0.bot != nil }) || s.participants.values.contains(where: { $0.bot == nil && $0.id != s.host }) { return s }
        // The host's waiting, never-started fixture: the table, then its final duel.
        guard let m = s.matches.values.sorted(by: { $0.id < $1.id }).first(where: { $0.phase == .waiting && $0.starts == 0 && $0.contains(actor) }) else { return s }
        return (try? ready(s, match: m.id, uid: actor, value: true)) ?? s
    }
    static func schedule(_ s: MPSession) -> [String: MPFixture] {
        if s.kind == .friendly {
            // The friendly room is ONE fixture at one table: every player, in seat order.
            let seated = s.seating().sorted { $0.value < $1.value }.map(\.key)
            let id = "\(s.code)_0_0_1"
            return [id: MPFixture(id: id, players: seated, seed: crossFold(id, 17))]
        }
        if s.grouped { return MPGroupTournament.schedule(s) }
        let ids = s.roster
        var result: [String: MPFixture] = [:]
        for leg in 0..<s.legs {
            for i in 0..<ids.count {
                for j in (i + 1)..<max(i + 1, ids.count) {
                    let id = "\(s.code)_\(leg)_\(i)_\(j)"
                    result[id] = MPFixture(id: id, a: leg == 0 ? ids[i] : ids[j], b: leg == 0 ? ids[j] : ids[i], seed: crossFold(id, 17))
                }
            }
        }
        return result
    }
    static func start(_ s: MPSession, actor: String) throws -> MPSession {
        guard s.state == "WAITING" else { return s }
        guard actor == s.host, s.participants.count == s.capacity else { throw MPError.roster }
        if s.knockout { return try MPKnockout.start(s) }
        var next = s
        next.matches = schedule(s); next.state = "ACTIVE"
        for (id, var m) in next.matches { m.authorityUid = next.authority(m); next.matches[id] = m }
        // Complete every house-only fixture (and its final duel) in this single durable transition. No timer, host presence, or
        // background phone is needed afterward.
        for id in next.matches.keys.sorted() {
            guard let m = next.matches[id], houseOnly(next, m) else { continue }
            let done = simulated(next, m)
            next.matches[id] = done
            next = withDuel(next, done)
        }
        if next.knockout { return try MPKnockout.settle(next) }
        next.state = next.complete ? "FINISHED" : "ACTIVE"
        return next
    }
    static func houseOnly(_ s: MPSession, _ m: MPFixture) -> Bool { m.players.allSatisfy { s.participants[$0]?.bot != nil } }
    static func ready(_ s: MPSession, match id: String, uid: String, value: Bool) throws -> MPSession {
        guard var m = s.matches[id], m.contains(uid), s.human(uid) else { throw MPError.permission }
        if m.phase == .playing || m.terminal { return s }
        m.ready[uid] = value ? true : nil; m.phase = m.ready.isEmpty ? .waiting : .ready
        var n = s; n.matches[id] = m; return n
    }
    /// Every human of the fixture Ready and connected: PLAYING once, in this one transition.
    static func startReady(_ s: MPSession, match id: String) -> MPSession {
        guard var m = s.matches[id], !m.terminal, m.phase != .playing else { return s }
        let humans = m.players.filter { s.participants[$0]?.bot == nil }
        guard !humans.isEmpty, humans.allSatisfy({ m.ready[$0] == true && s.connected($0) }) else { return s }
        // One person cannot be in two live fixtures, even if two Ready operations race.
        guard !s.matches.values.contains(where: { other in other.id != id && other.phase == .playing && humans.contains(where: other.contains) }) else { return s }
        m.phase = .playing; m.ready = [:]; m.starts += 1; var n = s; n.matches[id] = m; return n
    }
    static func canDelete(_ s: MPSession, actor: String) -> Bool { s.kind == .tournament && s.human(actor) && !s.connectedHumans.contains(where: { $0 != actor }) }
    static func leave(_ s: MPSession, actor: String) throws -> MPSession {
        guard s.kind == .tournament, s.human(actor), let successor = s.connectedHumans.filter({ $0 != actor }).sorted().first else { throw MPError.permission }
        var n = s; if n.host == actor { n.host = successor }; n.connections[actor] = nil
        if s.state == "WAITING" { n.participants[actor] = nil; return n }
        n.departed[actor] = true
        // Preserve roster indices and completed scores. Unplayed fixtures are cancelled, never fabricated as wins/losses; a knockout
        // gives the remaining players a walkover when the round is settled.
        if n.knockout { n = try MPKnockout.settle(n) }
        else {
            for (id, var m) in s.matches where m.contains(actor) && !m.terminal { m.phase = .cancelled; m.ready = [:]; n.matches[id] = m }
            n.state = n.complete ? "FINISHED" : "ACTIVE"
        }
        for (id, var m) in n.matches { m.authorityUid = n.authority(m); n.matches[id] = m }
        return n
    }
    /// Authority-only result, written once: a FINISHED result is immutable. `scores` follow the seat order. Winner takes all,
    /// pairs and tie-breaks: `placement` ranks every player by non-increasing score, winner first. An ELIMINATION table of 3 or 4
    /// plays until two are left: each player's score when they went out and the last stage's scores for the two survivors;
    /// `placement` is the survivors by score, then the others from the last out to the first. When that table must produce one
    /// winner, this same transition adds its final duel.
    static func finish(_ s: MPSession, match id: String, actor: String, scores: [Int], placement: [String]) throws -> MPSession {
        guard let m = s.matches[id] else { throw MPError.missing }
        if m.phase == .finished { return s }
        guard s.authority(m) == actor, m.phase == .playing else { throw MPError.permission }
        guard validFinal(s, m, scores), validPlacement(s, m, scores, placement), let first = placement.first else { throw MPError.invalidResult }
        var updated = m
        updated.phase = .finished; updated.scores = scores; updated.winner = first; updated.placement = placement
        var next = s
        next.matches[id] = updated
        next = withDuel(next, updated)
        if next.knockout { return try MPKnockout.settle(next) }
        next.state = next.complete ? "FINISHED" : "ACTIVE"
        return next
    }
    /// Classic pair result (MPMatchLink); the placement follows the score.
    static func finish(_ s: MPSession, match id: String, actor: String, a: Int, b: Int) throws -> MPSession {
        guard let m = s.matches[id] else { throw MPError.missing }
        return try finish(s, match: id, actor: actor, scores: [a, b], placement: a > b ? m.players : m.players.reversed())
    }
    static func validFinal(_ s: MPSession, _ a: Int, _ b: Int) -> Bool { validFinal(s, target: s.target, a, b) }
    /// The classic pair rule at `target`, with its two-point lead on the levels that need one.
    static func validFinal(_ s: MPSession, target: Int, _ a: Int, _ b: Int) -> Bool {
        guard a >= 0, b >= 0, a != b, max(a, b) >= target else { return false }
        if !s.level.needsTwoPointLead { return max(a, b) == target && min(a, b) < target }
        return min(a, b) < target - 1 ? max(a, b) == target : abs(a - b) == 2
    }
    /// Winner takes all: a pair keeps the classic rule (including deuce). A 3/4-player table ends the moment one player reaches
    /// `target` exactly; everybody else stays in [0, target).
    static func validFinal(_ s: MPSession, target: Int, scores: [Int]) -> Bool {
        switch scores.count {
        case 2: return validFinal(s, target: target, scores[0], scores[1])
        case 3, 4: return scores.filter { $0 == target }.count == 1 && scores.allSatisfy { $0 == target || ($0 >= 0 && $0 < target) }
        default: return false
        }
    }
    /// The fixture's own rule: an ELIMINATION table of 3 or 4 only needs every score in [0, target]; a tie-break pair is decided by
    /// its first point (1:0, never a two-point lead); any other fixture as above.
    static func validFinal(_ s: MPSession, _ m: MPFixture, _ scores: [Int]) -> Bool {
        let target = fixtureTarget(s, m)
        if scores.count != m.players.count { return false }
        if eliminates(s, m) { return scores.allSatisfy { $0 >= 0 && $0 <= target } }
        if m.goal == .tiebreak && scores.count == 2 { return scores.sorted() == [0, 1] }
        return validFinal(s, target: target, scores: scores)
    }
    /// Same size and same set is a permutation only of distinct players; a stored fixture with one uid in two seats has no valid ranking.
    private static func permutation(_ m: MPFixture, _ placement: [String]) -> Bool {
        placement.count == m.players.count && Set(m.players).count == m.players.count && Set(placement) == Set(m.players)
    }
    static func validPlacement(_ m: MPFixture, _ scores: [Int], _ placement: [String]) -> Bool {
        guard scores.count == m.players.count, permutation(m, placement) else { return false }
        var score: [String: Int] = [:]
        for (i, id) in m.players.enumerated() { score[id] = scores[i] }
        return zip(placement, placement.dropFirst()).allSatisfy { (score[$0.0] ?? 0) >= (score[$0.1] ?? 0) }
    }
    /// Winner takes all, pairs and tie-breaks rank by score. An ELIMINATION table ranks by elimination order (the two survivors,
    /// then the last out to the first): any permutation, no target required.
    static func validPlacement(_ s: MPSession, _ m: MPFixture, _ scores: [Int], _ placement: [String]) -> Bool {
        if !eliminates(s, m) { return validPlacement(m, scores, placement) }
        return scores.count == m.players.count && permutation(m, placement)
    }
    static func standings(_ s: MPSession) -> [MPStanding] {
        if s.grouped { return MPGroupTournament.standings(s) }
        var rows = Dictionary(uniqueKeysWithValues: s.participants.keys.map { ($0, MPStanding(id: $0)) })
        // A final duel belongs to its table: the table counts once, for the duel's winner, when the duel is over.
        for m in s.matches.values where m.phase == .finished && !isDuel(m) {
            guard let first = finalWinner(s, m) else { continue }
            for id in m.players {
                guard var row = rows[id] else { continue }
                let win = id == first
                row.played += 1; row.wins += win ? 1 : 0; row.losses += win ? 0 : 1
                if m.players.count == 2 {
                    row.points += win ? s.winPoints : s.lossPoints
                    row.pointsFor += id == m.a ? m.scoreA : m.scoreB; row.pointsAgainst += id == m.a ? m.scoreB : m.scoreA
                } else {
                    // A friendly 3/4-player table: a generic row only; tournament tables score placement points.
                    row.pointsFor += m.scoreOf(id)
                }
                rows[id] = row
            }
        }
        return rows.values.sorted {
            if $0.points != $1.points { return $0.points > $1.points }; if $0.wins != $1.wins { return $0.wins > $1.wins }
            if $0.pointsFor - $0.pointsAgainst != $1.pointsFor - $1.pointsAgainst { return $0.pointsFor - $0.pointsAgainst > $1.pointsFor - $1.pointsAgainst }
            if $0.pointsFor != $1.pointsFor { return $0.pointsFor > $1.pointsFor }; return $0.id < $1.id
        }
    }
    /// House-only fixture, deterministic from its seed (Kotlin's random sequence), at its `fixtureTarget`. A pair (a classic match,
    /// a final duel or a tie-break) keeps the classic point-by-point model (target and deuce; a tie-break pair ends on its first
    /// point); a 3/4-player table plays cross-scoring rallies under the room's mode (an ELIMINATION table until two are left).
    static func simulate(_ s: MPSession, _ m: MPFixture) -> MPTableResult? {
        let bots = m.players.compactMap { s.participants[$0]?.bot }
        guard bots.count == m.players.count, !bots.isEmpty else { return nil }
        let target = fixtureTarget(s, m)
        if bots.count != 2 {
            guard bots.count == 3 || bots.count == 4 else { return nil }
            return eliminates(s, m) ? MPTableSimulation.elimination(m.players, bots, target: target, seed: m.seed)
                : MPTableSimulation.play(m.players, bots, target: target, seed: m.seed)
        }
        var rng = MPKotlinRandom(seed: m.seed)
        let p = (0.5 + (bots[0].strength - bots[1].strength) * 0.055).mpClamp(0.12, 0.88)
        var x = 0, y = 0
        // Score one point at a time, honoring the same target/deuce rule as the classic game.
        while !validFinal(s, m, [x, y]) && x + y < 10_000 { if rng.nextDouble() < p { x += 1 } else { y += 1 } }
        return MPTableResult(scores: [x, y], placement: x > y ? m.players : m.players.reversed())
    }
    static func simulated(_ s: MPSession, _ m: MPFixture) -> MPFixture {
        guard let r = simulate(s, m), let first = r.placement.first else { return m }
        var done = m
        done.phase = .finished; done.ready = [:]; done.scores = r.scores; done.winner = first; done.placement = r.placement
        return done
    }
}

/// Android `SequenceGate`: actions are applied once per sender, in increasing sequence order.
struct MPSequenceGate {
    private(set) var last: [String: Int64] = [:]
    mutating func accept(_ sender: String, _ sequence: Int64) -> Bool {
        if sequence <= 0 || sequence <= (last[sender] ?? 0) { return false }
        last[sender] = sequence
        return true
    }
    mutating func restore(_ values: [String: Int64]) { for (k, v) in values { last[k] = max(last[k] ?? 0, v) } }
    func snapshot() -> [String: Int64] { last }
}
