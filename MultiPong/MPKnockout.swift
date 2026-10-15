import Foundation

/// Android multiplayer/Knockout.kt (MinikCrossPong 828c6fc): durable, seeded redraws; transaction retries and reconnects never
/// reshuffle a round. A classic pair knockout keeps its original rules (pairs drawn again each round; an odd round's randomly
/// drawn last player advances without playing). At tables of 3 or 4 every round is redrawn into `MPGroupTournament.split`
/// tables; each table sends `MPSession.advance` players through — winner takes all: the winner (and the runner-up; a tie for that
/// place plays a one-point TIEBREAK among exactly the tied players). ELIMINATION tables play until two are left: both go through
/// (TOP_TWO), or, for one, they play a classic final duel (`MPRules.withDuel`) whose winner goes through. The final table (2...4
/// players) always has one winner, the champion (its final duel's winner in ELIMINATION).
enum MPKnockout {
    /// Most players in a knockout at tables of 3 or 4.
    static let maxPlayers = 32
    /// A classic pair knockout keeps its original size and rounds.
    static let maxPairPlayers = 9
    static let maxRounds = 4
    /// Every group round loses a player (a played table or a departure), so 32 players need at most about ten rounds.
    static let maxGroupRounds = 16
    static func id(_ code: String, _ round: Int, _ pair: Int) -> String { "\(code)_K\(round)_\(pair)" }
    /// The tie-break for the last place through from table `table` of `round`.
    static func tiebreakId(_ code: String, _ round: Int, _ table: Int) -> String { id(code, round, table) + "_T" }
    /// The round's played tables in draw order (index i is table i).
    static func matches(_ s: MPSession, _ round: Int) -> [MPFixture] {
        guard let r = s.rounds[round] else { return [] }
        return r.tables.indices.compactMap { s.matches[id(s.code, round, $0)] }
    }
    /// The round's tie-breaks in table order.
    static func tiebreaks(_ s: MPSession, _ round: Int) -> [MPFixture] {
        guard let r = s.rounds[round] else { return [] }
        return r.tables.indices.compactMap { s.matches[tiebreakId(s.code, round, $0)] }
    }
    /// The round's final duels in table order.
    static func duels(_ s: MPSession, _ round: Int) -> [MPFixture] {
        guard let r = s.rounds[round] else { return [] }
        return r.tables.indices.compactMap { s.matches[MPRules.duelId(id(s.code, round, $0))] }
    }
    /// Every fixture of the round: its tables, then their tie-breaks, then their final duels.
    static func fixtures(_ s: MPSession, _ round: Int) -> [MPFixture] { matches(s, round) + tiebreaks(s, round) + duels(s, round) }
    static func current(_ s: MPSession) -> Int { s.rounds.keys.max() ?? 0 }
    /// Players each table of 3 or 4 sends through: 1 or 2.
    static func perTable(_ s: MPSession) -> Int { min(2, max(1, s.advance)) }
    private static func eligible(_ s: MPSession, _ id: String) -> Bool {
        !id.allSatisfy(\.isWhitespace) && s.participants[id] != nil && s.departed[id] != true
    }
    static func roundOf(_ s: MPSession, _ m: MPFixture) -> Int? { s.rounds.keys.sorted().first { r in fixtures(s, r).contains { $0.id == m.id } } }
    /// The players tied for the runner-up place of a finished winner-takes-all table that sends two through (empty when that
    /// place is clear): they play a tie-break for it.
    static func tied(_ s: MPSession, _ r: MPKnockoutRound, _ m: MPFixture) -> [String] {
        if r.groups.isEmpty || r.isFinal || m.phase != .finished || m.goal != .win || m.players.count < 3 || s.gameMode != .winnerTakesAll || perTable(s) < 2 { return [] }
        let rest = m.players.filter { $0 != m.winner }
        guard let best = rest.map({ m.scoreOf($0) }).max() else { return [] }
        let tiedPlayers = rest.filter { m.scoreOf($0) == best }
        return tiedPlayers.count > 1 ? tiedPlayers : []
    }
    /// Who goes through from a terminal table of `round`: a classic pair's winner; every remaining player of a cancelled table (a
    /// walkover); an elimination table's two survivors (TOP_TWO) or its final duel's winner (the remaining player of a cancelled
    /// duel); the final's winner; a winner-takes-all table's winner and, when two go through, its runner-up or the winner of their
    /// tie-break (everybody left in a cancelled tie-break). Departed players are filtered by `advancing`.
    static func through(_ s: MPSession, _ round: Int, _ m: MPFixture) -> [String] {
        guard let r = s.rounds[round] else { return [] }
        if r.groups.isEmpty { return [m.winner] }
        if m.phase == .cancelled { return m.players }
        if MPRules.needsDuel(s, m) { return MPRules.duelOf(s, m).map { decided($0) } ?? [] }
        let first = m.placement.isEmpty ? [m.winner] : m.placement
        if r.isFinal { return Array(first.prefix(1)) }
        if m.goal == .topTwo { return Array(first.prefix(2)) }
        if s.gameMode == .winnerTakesAll && perTable(s) == 2 && m.players.count > 2 { return Array(first.prefix(1)) + runnerUp(s, round, r, m) }
        return Array(first.prefix(1))
    }
    /// A terminal duel or tie-break: its winner, or everybody left in it when it was cancelled; nobody while it is open.
    private static func decided(_ m: MPFixture) -> [String] {
        switch m.phase {
        case .finished: return [m.winner]
        case .cancelled: return m.players
        default: return []
        }
    }
    private static func runnerUp(_ s: MPSession, _ round: Int, _ r: MPKnockoutRound, _ m: MPFixture) -> [String] {
        if tied(s, r, m).isEmpty {
            let rest = m.players.filter { $0 != m.winner }
            guard let best = rest.map({ m.scoreOf($0) }).max(), let runner = rest.first(where: { m.scoreOf($0) == best }) else { return [] }
            return [runner]
        }
        guard let table = r.tables.indices.first(where: { id(s.code, round, $0) == m.id }) else { return [] }
        return s.matches[tiebreakId(s.code, round, table)].map { decided($0) } ?? []
    }
    static func advancing(_ s: MPSession, _ round: Int) -> [String] {
        guard let r = s.rounds[round] else { return [] }
        let candidates = matches(s, round).filter(\.terminal).flatMap { through(s, round, $0) } + r.resting
        var result: [String] = []
        for id in candidates where eligible(s, id) && !result.contains(id) { result.append(id) }
        return result
    }
    /// Players `r` sends to the next round when nobody leaves.
    static func expected(_ s: MPSession, _ r: MPKnockoutRound) -> Int {
        if r.isFinal { return 1 }
        if r.groups.isEmpty { return (r.players.count + 1) / 2 }
        return r.tables.reduce(0) { $0 + min($1.count, perTable(s)) } + r.resting.count
    }
    static func winner(_ s: MPSession) -> String? {
        guard s.complete else { return nil }
        let remaining = advancing(s, current(s))
        return remaining.count == 1 ? remaining[0] : nil
    }
    private static func seed(_ s: MPSession, _ round: Int) -> Int64 { crossFold("\(s.code):\(s.createdAt):\(round)", 29) }
    private static func record(_ s: MPSession, _ key: String, _ players: [String], _ seed: Int64, goal: MPMatchGoal = .win) -> MPFixture {
        var m = MPFixture(id: key, players: players, seed: crossFold(key, seed), goal: goal)
        m.authorityUid = s.authority(m)
        return m
    }
    private static func draw(_ s: MPSession, _ players: [String], _ round: Int) throws -> MPSession {
        let rounds = s.grouped ? maxGroupRounds : maxRounds
        let most = s.grouped ? maxPlayers : maxPairPlayers
        guard round >= 0, round < rounds, players.count >= 2, players.count <= most else { throw MPError.permission }
        let drawSeed = seed(s, round)
        var random = MPKotlinRandom(seed: drawSeed)
        let ids = random.shuffled(players.sorted())
        var n = s
        if !s.grouped {
            for pair in 0..<(ids.count / 2) {
                let key = id(s.code, round, pair)
                n.matches[key] = record(n, key, [ids[pair * 2], ids[pair * 2 + 1]], drawSeed)
            }
            n.rounds[round] = MPKnockoutRound(players: ids)
            n.state = "ACTIVE"
            return n
        }
        // Tables of 3 and 4; a table no larger than the number going through is a walkover. The final has one winner.
        let finalRound = ids.count <= 4
        let going = perTable(s)
        var groups: [[String]] = []
        var start = 0
        for size in MPGroupTournament.split(ids.count, s.tableSize) {
            let end = min(ids.count, start + size)
            if start < end { groups.append(Array(ids[start..<end])) }
            start = end
        }
        let walkovers = groups.filter { !finalRound && $0.count <= going }
        let tables = groups.filter { finalRound || $0.count > going }
        let goal: MPMatchGoal = !finalRound && s.gameMode == .elimination && going == 2 ? .topTwo : .win
        for (table, seats) in tables.enumerated() {
            let key = id(s.code, round, table)
            n.matches[key] = record(n, key, seats, drawSeed, goal: goal)
        }
        n.rounds[round] = MPKnockoutRound(players: tables.flatMap { $0 } + walkovers.flatMap { $0 }, groups: tables, byes: [], walkovers: walkovers)
        n.state = "ACTIVE"
        return n
    }
    static func start(_ s: MPSession) throws -> MPSession {
        guard s.knockout, s.rounds.isEmpty else { throw MPError.permission }
        return try settle(draw(s, Array(s.participants.keys), 0))
    }
    /// A fixture with a departed player is cancelled (never scored); a house-only one is simulated at once.
    private static func resolve(_ s: MPSession, _ m: MPFixture) -> MPSession {
        if m.terminal { return s }
        var updated = m
        if m.players.contains(where: { !eligible(s, $0) }) {
            updated.phase = .cancelled; updated.ready = [:]
            updated.winner = m.players.first(where: { eligible(s, $0) }) ?? ""
        } else if MPRules.houseOnly(s, m) { updated = MPRules.simulated(s, m) }
        var n = s
        n.matches[m.id] = updated
        return n
    }
    /// Finish house-player fixtures, add the tie-breaks and final duels finished tables need (in the same transition), then redraw
    /// ONLY after the whole round, tie-breaks and duels included, finishes.
    static func settle(_ initial: MPSession) throws -> MPSession {
        var s = initial
        for _ in 0...maxGroupRounds {
            let round = current(s)
            let drawn = s.rounds[round]
            let games = matches(s, round)
            guard games.count == (drawn?.tables.count ?? 0) else { throw MPError.permission }
            for m in games { s = resolve(s, m) }
            if let drawn {
                for (table, m) in matches(s, round).enumerated() {
                    s = MPRules.withDuel(s, m)
                    let tie = tied(s, drawn, m)
                    let key = tiebreakId(s.code, round, table)
                    if !tie.isEmpty && s.matches[key] == nil { s.matches[key] = record(s, key, tie, seed(s, round), goal: .tiebreak) }
                }
            }
            for m in tiebreaks(s, round) + duels(s, round) { s = resolve(s, m) }
            if fixtures(s, round).contains(where: { !$0.terminal }) { s.state = "ACTIVE"; return s }
            let remaining = advancing(s, round)
            if remaining.count <= 1 { s.state = "FINISHED"; return s }
            s = try draw(s, remaining, round + 1)
        }
        throw MPError.permission
    }
    /// The classic bracket's columns (iOS `MPKnockoutBracketView`): every drawn round, then the expected halving up to the final. A
    /// finished knockout stops at its last drawn round.
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
    // Texts: Android Knockout.kt of the working tree on 828c6fc (2026-10-04) passes each EN/HE pair through AppText (`MPText`);
    // `advanceText` is the one it leaves in English and Hebrew.
    static func stage(players: Int, hebrew he: Bool) -> String {
        if players <= 2 { return MPText.t("Final", "הגמר", he) }
        if players <= 4 { return MPText.t("Semifinals", "חצי הגמר", he) }
        if players <= 8 { return MPText.t("Quarterfinals", "רבע הגמר", he) }
        return MPText.t("Round of \(players)", "סיבוב של \(players) שחקנים", he)
    }
    static func stage(_ s: MPSession, hebrew he: Bool) -> String {
        let players = s.rounds[current(s)]?.players.count ?? s.capacity
        return s.grouped ? MPGroupTournament.stage(players, s.tableSize, hebrew: he, advance: perTable(s)) : stage(players: players, hebrew: he)
    }
    /// Who goes through from every table of the current round, as one sentence for the round screen.
    static func rule(_ s: MPSession, hebrew he: Bool) -> String {
        if !s.grouped { return MPText.t("The winner of every match advances.", "המנצחים בכל משחק עולים לסיבוב הבא.", he) }
        let elimination = s.gameMode == .elimination
        let round = s.rounds[current(s)]
        if (round.map { $0.isFinal && $0.players.count > 2 } ?? false) || (s.state == "WAITING" && s.capacity <= 4) {
            if elimination { return MPText.t("The last two left at the final table play the final duel for the tournament.", "שני האחרונים שנשארים בשולחן הגמר משחקים קרב גמר על הטורניר.", he) }
            return MPText.t("The winner of the final table takes the tournament.", "הניצחון בשולחן הגמר מכריע את הטורניר.", he)
        }
        if round?.isFinal == true { return MPText.t("The winner of the final takes the tournament.", "הניצחון בגמר מכריע את הטורניר.", he) }
        if perTable(s) == 1 && elimination {
            return MPText.t("At every table the last two left play a final duel; its winner advances.", "בכל שולחן שני האחרונים שנשארים משחקים קרב גמר, והניצחון בו מעלה לסיבוב הבא.", he)
        }
        if perTable(s) == 1 { return MPText.t("The winner of every table advances.", "מכל שולחן עולה רק המקום הראשון.", he) }
        if elimination { return MPText.t("The last two players left at every table advance.", "מכל שולחן עולים שני האחרונים שנשארים במשחק.", he) }
        return MPText.t("The top two of every table advance; a tie for second place is settled by a one-point tie-break.",
                        "מכל שולחן עולים שני המקומות הראשונים; שוויון על המקום השני מוכרע בשובר שוויון של נקודה אחת.", he)
    }
    /// The short form of `rule` for the player's own table.
    private static func tableRule(_ s: MPSession, finalTable: Bool, hebrew he: Bool) -> String {
        if finalTable { return MPText.t("the winner takes the tournament", "הניצחון מכריע את הטורניר", he) }
        if perTable(s) == 1 && s.gameMode == .elimination { return MPText.t("the final duel's winner advances", "הניצחון בקרב הגמר מעלה לסיבוב הבא", he) }
        if perTable(s) == 1 { return MPText.t("the winner advances", "רק המקום הראשון עולה", he) }
        if s.gameMode == .elimination { return MPText.t("the last two left advance", "שני האחרונים שנשארים עולים", he) }
        return MPText.t("the top two advance", "שני הראשונים עולים", he)
    }
    static func tiebreakTitle(hebrew he: Bool) -> String { MPText.t("Tie-break for the last place", "שובר שוויון על המקום האחרון", he) }
    static func walkoverTitle(hebrew he: Bool) -> String { MPText.t("Advance without playing", "עולים בלי לשחק", he) }
    static func advanceText(_ s: MPSession, _ m: MPFixture, hebrew he: Bool) -> String {
        let round = roundOf(s, m) ?? current(s)
        if s.grouped, let drawn = s.rounds[round] {
            let next = s.rounds[round + 1]?.players.count ?? expected(s, drawn)
            let semifinal = next > 4 && MPGroupTournament.advancing(next, s.tableSize, advance: perTable(s)) <= 4
            if he { return next <= 4 ? "העפלת לגמר!" : (semifinal ? "העפלת לשולחנות חצי הגמר!" : "העפלת לסיבוב הבא!") }
            return next <= 4 ? "You reached the final!" : (semifinal ? "You reached the semifinal tables!" : "You advanced to the next round!")
        }
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
    /// `uid` goes through from `m`'s round (so far): from a terminal table, a tie-break or without playing.
    static func goesThrough(_ s: MPSession, _ m: MPFixture, _ uid: String) -> Bool { roundOf(s, m).map { advancing(s, $0).contains(uid) } ?? false }
    /// A tie-break `uid` still has to play in `m`'s round.
    static func pendingTiebreak(_ s: MPSession, _ m: MPFixture, _ uid: String) -> MPFixture? {
        guard let r = roundOf(s, m) else { return nil }
        return tiebreaks(s, r).first { $0.contains(uid) && !$0.terminal }
    }
    static func tiebreakStatus(hebrew he: Bool) -> String {
        MPText.t("\(tiebreakTitle(hebrew: false)): the first point decides who advances.", "\(tiebreakTitle(hebrew: true)): הנקודה הראשונה מכריעה מי עולה.", he)
    }
    static func eliminatedText(hebrew he: Bool) -> String { MPText.t("You have been eliminated. You can follow the remaining rounds.", "סיימת את השתתפותך. אפשר לצפות בהמשך הטורניר.", he) }
    static func playerStatus(_ s: MPSession, _ uid: String, hebrew he: Bool) -> String {
        if s.complete {
            let champion = winner(s)
            if champion == uid { return MPText.t("You won the tournament!", "ניצחת בטורניר!", he) }
            if let champion {
                let winnerEnglish = s.participants[champion]?.name(hebrew: false) ?? ""
                let winnerHebrew = s.participants[champion]?.name(hebrew: true) ?? ""
                return MPText.t("Tournament finished. Winner: \(winnerEnglish)", "הטורניר הסתיים. המנצח: \(winnerHebrew)", he)
            }
            return MPText.t("Tournament finished", "הטורניר הסתיים", he)
        }
        let round = current(s)
        let drawn = s.rounds[round]
        let group = s.grouped
        let waiting = group ? MPText.t("Waiting for the other tables.", "ממתינים לשאר השולחנות.", he) : MPText.t("Waiting for the other matches.", "ממתינים לשאר המשחקים.", he)
        if let drawn, drawn.walkovers.contains(where: { $0.contains(uid) }) {
            return MPText.t("Your table advances without playing. ", "השולחן שלכם עולה לסיבוב הבא בלי לשחק. ", he) + waiting
        }
        if let drawn, drawn.resting.contains(uid) { return MPText.t("You have a bye to the next round. ", "עלית אוטומטית לסיבוב הבא. ", he) + waiting }
        if tiebreaks(s, round).contains(where: { $0.contains(uid) && !$0.terminal }) { return tiebreakStatus(hebrew: he) }
        if duels(s, round).contains(where: { $0.contains(uid) && !$0.terminal }) { return MPCompletionText.duelStatus(s, hebrew: he) }
        let own = matches(s, round).first { $0.contains(uid) }
        if let own, own.terminal, through(s, round, own).contains(uid) { return advanceText(s, own, hebrew: he) + " " + waiting }
        // Out at the final table: the final duel still decides the champion and the places.
        if let own, own.terminal, drawn?.isFinal == true, let duel = MPRules.duelOf(s, own), !duel.terminal { return MPCompletionText.duelWaiting(hebrew: he) }
        if own == nil || own?.terminal == true { return eliminatedText(hebrew: he) }
        if !group { return MPText.t("Your match this round", "המשחק שלך בסיבוב הזה", he) }
        return MPText.t("Your table this round: ", "השולחן שלכם בסיבוב הזה: ", he) + tableRule(s, finalTable: drawn?.isFinal == true, hebrew: he) + "."
    }
    /// A finished group knockout's placing: 1 for the champion, then the final table's order (its final duel's winner and loser
    /// first in ELIMINATION); 0 when the player went out earlier (or it is still running).
    static func place(_ s: MPSession, _ uid: String) -> Int {
        if !s.complete { return 0 }
        if winner(s) == uid { return 1 }
        let last = current(s)
        let tables = matches(s, last)
        guard tables.count == 1, let table = tables.first, table.phase == .finished, s.rounds[last]?.isFinal == true,
              let ranking = MPRules.ranking(s, table), let index = ranking.firstIndex(of: uid) else { return 0 }
        return index + 1
    }
}

/// Android `CompletionText`: the headline of a completed room, who celebrates it, and the result title after one fixture.
enum MPCompletionText {
    /// Standings rank; a group knockout ranks its champion and then the final table (`MPKnockout.place`).
    static func place(_ s: MPSession, _ uid: String) -> Int {
        if s.knockout && s.grouped { return MPKnockout.place(s, uid) }
        return (MPRules.standings(s).firstIndex { $0.id == uid } ?? -1) + 1
    }
    /// A friendly room is won by its table's final winner: the table's winner, or its final duel's winner.
    static func won(_ s: MPSession, _ uid: String) -> Bool {
        guard s.complete else { return false }
        if s.knockout { return MPKnockout.winner(s) == uid }
        if s.kind == .tournament { return place(s, uid) == 1 && (MPRules.standings(s).first?.wins ?? 0) > 0 }
        return friendlyWinner(s) == uid
    }
    /// The friendly table's final winner (its single non-duel fixture).
    private static func friendlyWinner(_ s: MPSession) -> String? {
        let tables = s.matches.values.filter { !MPRules.isDuel($0) }
        guard tables.count == 1, let table = tables.first else { return nil }
        return MPRules.finalWinner(s, table)
    }
    static func headline(_ s: MPSession, _ uid: String, hebrew he: Bool) -> String {
        if s.knockout {
            // A finalist of a group knockout learns their place at the final table.
            let rank = s.grouped && s.complete && !won(s, uid) ? place(s, uid) : 0
            return rank > 1 ? placed(rank, hebrew: he) : MPKnockout.playerStatus(s, uid, hebrew: he)
        }
        if s.kind == .friendly {
            if won(s, uid) { return MPText.t("You won the match!", "ניצחתם במשחק!", he) }
            // Android 1dbfe33 MatchResultWords: a house character's sentence agrees with the character; a person's is neutral.
            if let winner = friendlyWinner(s), let player = s.participants[winner] {
                return MPResultWords.winner(player.name(hebrew: he), houseCharacter: player.bot?.characterId, language: he ? "he" : MPText.language)
            }
            return MPText.t("Match finished", "המשחק הסתיים", he)
        }
        if won(s, uid) { return MPText.t("You won the tournament!", "ניצחתם בטורניר!", he) }
        let rank = place(s, uid)
        if rank <= 0 { return MPText.t("Tournament finished", "הטורניר הסתיים", he) }
        return placed(rank, hebrew: he)
    }
    /// The result title after one fixture (a table, a tie-break or a final duel): the room's outcome once complete; while a table's
    /// final duel is open, that `uid` plays it or waits for it; in a knockout whether `uid` goes through (a runner-up, both survivors
    /// and a tie-break or duel winner too), plays a tie-break for the last place, or is out; otherwise a won or finished match or
    /// final duel.
    static func matchHeadline(_ s: MPSession, _ fixture: MPFixture, _ uid: String, hebrew he: Bool) -> String {
        if s.complete { return headline(s, uid, hebrew: he) }
        let m = s.matches[fixture.id] ?? fixture                                   // the stored record, never a stale copy
        // An open final duel: its players are in it; everybody else waits for it, except those already out of a knockout before
        // its final (an open duel's round is always the current one).
        if let duel = MPRules.duelOf(s, MPRules.tableOf(s, m) ?? m), !duel.terminal {
            if duel.contains(uid) { return duelStatus(s, hebrew: he) }
            if !s.knockout || s.rounds[MPKnockout.current(s)]?.isFinal == true { return duelWaiting(hebrew: he) }
        }
        if s.knockout && m.contains(uid) {
            if MPKnockout.goesThrough(s, m, uid) { return MPKnockout.advanceText(s, m, hebrew: he) }
            if MPKnockout.pendingTiebreak(s, m, uid) != nil { return MPKnockout.tiebreakStatus(hebrew: he) }
            if m.terminal { return MPKnockout.eliminatedText(hebrew: he) }
        }
        if MPRules.isDuel(m) && m.phase == .finished && m.contains(uid) {
            if m.winner == uid { return MPText.t("You won the final duel!", "ניצחתם בקרב הגמר!", he) }
            return MPText.t("You lost the final duel.", "הפסדתם בקרב הגמר.", he)
        }
        if m.winner == uid { return MPText.t("You won this match!", "ניצחתם במשחק!", he) }
        return MPText.t("Match finished", "המשחק הסתיים", he)
    }
    /// For a player in an open final duel: what the duel decides.
    static func duelStatus(_ s: MPSession, hebrew he: Bool) -> String {
        let stake: String
        if s.kind == .friendly { stake = MPText.t("the winner takes the game", "הניצחון מכריע את המשחק", he) }
        else if !s.knockout { stake = MPText.t("the winner takes first place at the table", "הניצחון מעניק את המקום הראשון בשולחן", he) }
        else if s.rounds[MPKnockout.current(s)]?.isFinal == true { stake = MPText.t("the winner takes the tournament", "הניצחון מכריע את הטורניר", he) }
        else { stake = MPText.t("the winner advances", "הניצחון מעלה לסיבוב הבא", he) }
        return MPText.t("You are in the final duel: ", "אתם בקרב הגמר: ", he) + stake + "."
    }
    /// For everybody else whose table's final duel is still open.
    static func duelWaiting(hebrew he: Bool) -> String { MPText.t("Waiting for the final duel.", "ממתינים לקרב הגמר.", he) }
    static func ordinal(_ rank: Int) -> String {
        if (11...13).contains(rank % 100) { return "\(rank)th" }
        if rank % 10 == 1 { return "\(rank)st" }
        if rank % 10 == 2 { return "\(rank)nd" }
        if rank % 10 == 3 { return "\(rank)rd" }
        return "\(rank)th"
    }
    private static func placed(_ rank: Int, hebrew he: Bool) -> String {
        MPText.t("Tournament finished. You placed \(ordinal(rank)).", "הטורניר הסתיים. סיימתם במקום ה־\(rank).", he)
    }
}

/// Android `ControlChoice.title`: the room's control level (wire 4/0/3; older 1 and 2 are Standard).
enum MPControlChoice {
    static func title(_ value: Int, hebrew he: Bool) -> String {
        switch MPLevel.control(value) {
        case .easy: return MPText.t("Standard", "רגילה", he)
        case .superHard: return MPText.t("Pro", "מקצועני", he)
        default: return MPText.t("Beginner", "מתחילים", he)
        }
    }
}

/// Android `MatchText`: canonical player/score order even when a nickname has the opposite direction.
enum MPMatchText {
    private static func name(_ value: String) -> String { "\u{2068}" + value + "\u{2069}" }
    static func ordered(_ value: String) -> String { "\u{2066}" + value + "\u{2069}" }
    static func score(_ a: Int, _ b: Int) -> String { ordered("\(a) : \(b)") }
    static func pair(_ a: String, _ b: String) -> String { ordered(name(a) + " ↔ " + name(b)) }
    static func result(_ a: String, _ scoreA: Int, _ scoreB: Int, _ b: String) -> String {
        ordered(name(a) + "  \(scoreA) : \(scoreB)  " + name(b))
    }
    /// 3/4-player table in seat order: "A · B · C".
    static func group(_ names: [String]) -> String { ordered(names.map { name($0) }.joined(separator: " · ")) }
    /// 3/4-player scores in seat order: "A 5 · B 3 · C 0".
    static func table(_ names: [String], _ scores: [Int]) -> String {
        ordered(zip(names, scores).map { name($0.0) + " \($0.1)" }.joined(separator: " · "))
    }
    /// Seat-ordered live scoreboard without names: "5 : 3 : 0".
    static func scoreboard(_ values: [Int]) -> String { ordered(values.map { String($0) }.joined(separator: " : ")) }
    /// Any fixture in seat order, then its state: "A ↔ B · state" or "A · B · C · state".
    static func summary(_ names: [String], _ state: String) -> String { ordered((names.count == 2 ? pair(names[0], names[1]) : group(names)) + " · " + state) }
    /// The label of a final duel's row.
    static func duelTitle(hebrew he: Bool) -> String { MPText.t("Final duel", "קרב גמר", he) }
    /// A row label for fixtures that are not an ordinary table: a final duel or a tie-break; nil otherwise.
    static func label(_ m: MPFixture, hebrew he: Bool) -> String? {
        if MPRules.isDuel(m) { return duelTitle(hebrew: he) }
        return m.goal == .tiebreak ? MPKnockout.tiebreakTitle(hebrew: he) : nil
    }
}

/// Kotlin `kotlin.random.Random(seed: Long)` (XorWow) and `shuffled(random)`, so an iOS knockout draw equals Android's for the same
/// room code, creation time and round. The rest of Kotlin's Random API is in CrossGeometry.swift.
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
