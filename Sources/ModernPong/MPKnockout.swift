import Foundation

/// Android `Knockout`: durable, seeded redraws. Transaction retries and reconnects never reshuffle a round;
/// pairs are drawn again each round and an odd round's randomly drawn last player advances without playing.
enum MPKnockout {
    static let maxPlayers = 9
    static let maxRounds = 4
    static func id(_ code: String, _ round: Int, _ pair: Int) -> String { "\(code)_K\(round)_\(pair)" }
    static func matches(_ s: MPSession, _ round: Int) -> [MPFixture] {
        guard let count = s.rounds[round]?.players.count else { return [] }
        return (0..<(count / 2)).compactMap { s.matches[id(s.code, round, $0)] }
    }
    static func current(_ s: MPSession) -> Int { s.rounds.keys.max() ?? 0 }
    private static func eligible(_ s: MPSession, _ id: String) -> Bool {
        !id.allSatisfy(\.isWhitespace) && s.participants[id] != nil && s.departed[id] != true
    }
    /// Winners of the round's finished or walkover matches, plus its bye, who are still in the tournament.
    static func advancing(_ s: MPSession, _ round: Int) -> [String] {
        var candidates = matches(s, round).filter(\.terminal).map(\.winner)
        if let bye = s.rounds[round]?.bye { candidates.append(bye) }
        var result: [String] = []
        for id in candidates where eligible(s, id) && !result.contains(id) { result.append(id) }
        return result
    }
    static func winner(_ s: MPSession) -> String? {
        guard s.complete else { return nil }
        let remaining = advancing(s, current(s))
        return remaining.count == 1 ? remaining[0] : nil
    }
    private static func draw(_ s: MPSession, _ players: [String], _ round: Int) throws -> MPSession {
        guard (0..<maxRounds).contains(round), (2...maxPlayers).contains(players.count) else { throw MPError.permission }
        let seed = "\(s.code):\(s.createdAt):\(round)".utf16.reduce(Int64(29)) { ($0 &* 31) &+ Int64($1) }
        var random = MPKotlinRandom(seed: seed)
        let ids = random.shuffled(players.sorted())
        var n = s
        for pair in 0..<(ids.count / 2) {
            let key = id(s.code, round, pair)
            var m = MPFixture(id: key, a: ids[pair * 2], b: ids[pair * 2 + 1], seed: key.utf16.reduce(seed) { ($0 &* 31) &+ Int64($1) })
            m.authorityUid = n.authority(m)
            n.matches[key] = m
        }
        n.rounds[round] = MPKnockoutRound(players: ids)
        n.state = "ACTIVE"
        return n
    }
    static func start(_ s: MPSession) throws -> MPSession {
        guard s.knockout, s.rounds.isEmpty else { throw MPError.permission }
        return try settle(draw(s, Array(s.participants.keys), 0))
    }
    /// Finish house-player fixtures and walkovers, then redraw ONLY after the whole round finishes.
    static func settle(_ initial: MPSession) throws -> MPSession {
        var s = initial
        for _ in 0...maxRounds {
            let round = current(s), games = matches(s, round)
            guard games.count == (s.rounds[round]?.players.count ?? 0) / 2 else { throw MPError.permission }
            for m in games where !m.terminal {
                var updated = m
                if [m.a, m.b].contains(where: { !eligible(s, $0) }) {
                    // A player who left gives the opponent a walkover; no score is invented.
                    updated.phase = .cancelled; updated.ready = [:]
                    updated.winner = [m.a, m.b].first(where: { eligible(s, $0) }) ?? ""
                } else if let score = MPRules.simulate(s, m) {
                    updated.phase = .finished; updated.scoreA = score.a; updated.scoreB = score.b
                    updated.winner = score.a > score.b ? m.a : m.b
                }
                s.matches[m.id] = updated
            }
            if matches(s, round).contains(where: { !$0.terminal }) { s.state = "ACTIVE"; return s }
            let remaining = advancing(s, round)
            if remaining.count <= 1 { s.state = "FINISHED"; return s }
            s = try draw(s, remaining, round + 1)
        }
        throw MPError.permission
    }
    /// Android `KnockoutBracketView` columns: every drawn round, then the expected halving up to the final.
    /// A finished knockout stops at its last drawn round.
    static func bracketColumns(_ s: MPSession) -> [Int] {
        let last = current(s)
        var count = s.rounds[0]?.players.count ?? s.capacity, round = 0, counts: [Int] = []
        while count > 1 && round < maxRounds {
            count = s.rounds[round]?.players.count ?? count
            counts.append(count)
            if s.complete && round == last { break }
            count = (count + 1) / 2; round += 1
        }
        return counts
    }
    static func stage(players: Int, hebrew he: Bool) -> String {
        if players <= 2 { return he ? "הגמר" : "Final" }
        if players <= 4 { return he ? "חצי הגמר" : "Semifinals" }
        if players <= 8 { return he ? "רבע הגמר" : "Quarterfinals" }
        return he ? "סיבוב של \(players) שחקנים" : "Round of \(players)"
    }
    static func stage(_ s: MPSession, hebrew he: Bool) -> String {
        stage(players: s.rounds[current(s)]?.players.count ?? s.capacity, hebrew: he)
    }
    static func advanceText(_ s: MPSession, _ m: MPFixture, hebrew he: Bool) -> String {
        let round = s.rounds.keys.sorted().first(where: { r in matches(s, r).contains(where: { $0.id == m.id }) }) ?? current(s)
        let next = s.rounds[round + 1]?.players.count ?? (((s.rounds[round]?.players.count ?? 0) + 1) / 2)
        if he {
            if next <= 2 { return "העפלת לגמר!" }
            if next <= 4 { return "העפלת לחצי הגמר!" }
            if next <= 8 { return "העפלת לרבע הגמר!" }
            return "העפלת לסיבוב הבא!"
        }
        if next <= 2 { return "You reached the final!" }
        if next <= 4 { return "You reached the semifinals!" }
        if next <= 8 { return "You reached the quarterfinals!" }
        return "You advanced to the next round!"
    }
    static func playerStatus(_ s: MPSession, _ uid: String, hebrew he: Bool) -> String {
        if s.complete {
            let champion = winner(s)
            if champion == uid { return he ? "ניצחת בטורניר!" : "You won the tournament!" }
            if let champion {
                let name = s.participants[champion]?.name(hebrew: he) ?? ""
                return he ? "הטורניר הסתיים. המנצח: \(name)" : "Tournament finished. Winner: \(name)"
            }
            return he ? "הטורניר הסתיים" : "Tournament finished"
        }
        let round = current(s)
        if s.rounds[round]?.bye == uid {
            return he ? "עלית אוטומטית לסיבוב הבא. ממתינים לשאר המשחקים." : "You have a bye to the next round. Waiting for the other matches."
        }
        let mine = matches(s, round).first { $0.contains(uid) }
        if let mine, mine.terminal, mine.winner == uid {
            return advanceText(s, mine, hebrew: he) + " " + (he ? "ממתינים לשאר המשחקים." : "Waiting for the other matches.")
        }
        if mine == nil || mine?.terminal == true {
            return he ? "סיימת את השתתפותך. אפשר לצפות בהמשך הטורניר." : "You have been eliminated. You can follow the remaining rounds."
        }
        return he ? "המשחק שלך בסיבוב הזה" : "Your match this round"
    }
}

/// Android `CompletionText`: the headline of a completed room and who celebrates it.
enum MPCompletionText {
    static func place(_ s: MPSession, _ uid: String) -> Int { (MPRules.standings(s).firstIndex { $0.id == uid } ?? -1) + 1 }
    static func won(_ s: MPSession, _ uid: String) -> Bool {
        guard s.complete else { return false }
        if s.knockout { return MPKnockout.winner(s) == uid }
        if s.kind == .tournament { return place(s, uid) == 1 && (MPRules.standings(s).first?.wins ?? 0) > 0 }
        return s.matches.count == 1 && s.matches.values.first?.winner == uid
    }
    static func headline(_ s: MPSession, _ uid: String, hebrew he: Bool) -> String {
        if s.knockout { return MPKnockout.playerStatus(s, uid, hebrew: he) }
        if s.kind == .friendly {
            if won(s, uid) { return he ? "ניצחתם במשחק!" : "You won the match!" }
            return he ? "המשחק הסתיים" : "Match finished"
        }
        if won(s, uid) { return he ? "ניצחתם בטורניר!" : "You won the tournament!" }
        let rank = place(s, uid)
        if rank <= 0 { return he ? "הטורניר הסתיים" : "Tournament finished" }
        let ordinal: String
        if (11...13).contains(rank % 100) { ordinal = "\(rank)th" }
        else if rank % 10 == 1 { ordinal = "\(rank)st" }
        else if rank % 10 == 2 { ordinal = "\(rank)nd" }
        else if rank % 10 == 3 { ordinal = "\(rank)rd" }
        else { ordinal = "\(rank)th" }
        return he ? "הטורניר הסתיים. סיימתם במקום ה־\(rank)." : "Tournament finished. You placed \(ordinal)."
    }
}

/// Android `ControlChoice.title`: the room's control level (wire 4/0/3; older 1 and 2 are Standard).
enum MPControlChoice {
    /// Android `ControlChoice.normalize` (96ae066): 0 and 2 Standard, 1 Starter, 3 Pro, anything else Beginner (4).
    /// Used by the colour ranks; `MPLevel.control` keeps the room/engine mapping.
    static func normalize(_ value: Int) -> Int {
        switch value { case 0, 2: return 0; case 1: return 1; case 3: return 3; default: return 4 }
    }
    static func title(_ value: Int, hebrew he: Bool) -> String {
        switch MPLevel.control(value) {
        case .medium: return he ? "נינוחה" : "Starter"
        case .easy: return he ? "רגילה" : "Standard"
        case .superHard: return he ? "מקצועני" : "Pro"
        default: return he ? "מתחילים" : "Beginner"
        }
    }
    /// Android `ControlChoice.explanation` (c9f5fa6): only the selected control is explained on setup pages.
    static func explanation(_ value: Int, hebrew he: Bool) -> String {
        switch normalize(value) {
        case 4: return he ? "זזים אל הכדור לחבטה אוטומטית. החלקה קטנה הצדה מכוונת את החבטה." : "Move into reach for an automatic hit. A small sideways swipe aims it."
        case 1: return he ? "זזים אל הכדור ומכינים החלקה מכוונת מוקדם, עם חלון תזמון רחב. אפשר גם להקיש להחזרה פשוטה." : "Move into reach and prepare an aimed swipe early, with a generous timing window. You can also tap for a simple return."
        case 0: return he ? "זזים אל הכדור ומחליקים כשהוא מגיע. הכיוון מכוון; המהירות קובעת עוצמה ועומק. אפשר גם להקיש להחזרה פשוטה." : "Move into reach, then swipe as the ball arrives. Direction aims; swipe speed sets pace and depth. A tap gives a simple return."
        default: return he ? "זזים אל הכדור ומחליקים כדי לחבוט. הכיוון והמהירות קובעים את החבטה; החלקה בקשת מוסיפה סיבוב." : "Move into reach and swipe to return. Direction and speed shape the shot; a curved swipe adds spin."
        }
    }
}

/// Android `MatchText.result`: canonical player/score order even when a nickname has the opposite direction.
enum MPMatchText {
    private static func name(_ value: String) -> String { "\u{2068}" + value + "\u{2069}" }
    static func ordered(_ value: String) -> String { "\u{2066}" + value + "\u{2069}" }
    static func result(_ a: String, _ scoreA: Int, _ scoreB: Int, _ b: String) -> String {
        ordered(name(a) + "  \(scoreA) : \(scoreB)  " + name(b))
    }
}

/// Kotlin `kotlin.random.Random(seed: Long)` (XorWow) and `shuffled(random)`, so an iOS knockout draw equals
/// Android's for the same room code, creation time and round.
struct MPKotlinRandom {
    private var x: Int32, y: Int32, z: Int32, w: Int32, v: Int32, addend: Int32
    init(seed: Int64) {
        let seed1 = Int32(truncatingIfNeeded: seed), seed2 = Int32(truncatingIfNeeded: seed >> 32)
        x = seed1; y = seed2; z = 0; w = 0; v = ~seed1
        addend = (seed1 << 10) ^ Int32(bitPattern: UInt32(bitPattern: seed2) >> 4)
        for _ in 0..<64 { _ = nextInt() }
    }
    mutating func nextInt() -> Int32 {
        var t = x
        t = t ^ Int32(bitPattern: UInt32(bitPattern: t) >> 2)
        x = y; y = z; z = w
        let v0 = v
        w = v0
        t = (t ^ (t << 1)) ^ v0 ^ (v0 << 4)
        v = t
        addend = addend &+ 362437
        return t &+ addend
    }
    /// Kotlin `Random.nextInt(until)` for `until > 0`.
    mutating func nextInt(until n: Int32) -> Int32 {
        if n & (0 &- n) == n {
            let bitCount = 31 - n.leadingZeroBitCount
            if bitCount == 0 { _ = nextInt(); return 0 }
            return Int32(bitPattern: UInt32(bitPattern: nextInt()) >> UInt32(32 - bitCount))
        }
        var bits: Int32 = 0, value: Int32 = 0
        repeat {
            bits = Int32(bitPattern: UInt32(bitPattern: nextInt()) >> 1)
            value = bits % n
        } while bits &- value &+ (n &- 1) < 0
        return value
    }
    /// Kotlin `Random.nextDouble()`: the upper 26 and 27 bits of two `nextInt()` values (`doubleFromParts`).
    mutating func nextDouble() -> Double {
        let hi = Int64(UInt32(bitPattern: nextInt()) >> 6), lo = Int64(UInt32(bitPattern: nextInt()) >> 5)
        return Double((hi << 27) + lo) / 9007199254740992.0
    }
    /// Kotlin `MutableList.shuffle(random)`: swaps from the last index down to 1.
    mutating func shuffled<T>(_ input: [T]) -> [T] {
        var list = input
        guard list.count > 1 else { return list }
        for i in stride(from: list.count - 1, through: 1, by: -1) {
            let j = Int(nextInt(until: Int32(i + 1)))
            list.swapAt(i, j)
        }
        return list
    }
}
