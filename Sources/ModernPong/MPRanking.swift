import SwiftUI
import UIKit

/// Android `PongRank` (6feaac5 and later): one colour of the colour-rank ladder. `ink` is the text colour on it.
struct MPRank: Equatable {
    let threshold: Int, en: String, he: String, color: UInt32, ink: UInt32
    init(_ threshold: Int, _ en: String, _ he: String, _ color: UInt32, _ ink: UInt32 = 0xff17283f) {
        self.threshold = threshold; self.en = en; self.he = he; self.color = color; self.ink = ink
    }
    func name(he hebrew: Bool) -> String { hebrew ? he : en }
    var uiColor: UIColor { MPColor.ui(color) }
    var swiftColor: Color { MPColor.color(color) }
    var uiInk: UIColor { MPColor.ui(ink) }
}

/// Android `PongRanks`: twelve colours (stored levels 0...11), their point thresholds and the point rewards.
enum MPRanks {
    static let all: [MPRank] = [
        MPRank(0, "White", "לבן", 0xfffafafa), MPRank(200, "Yellow", "צהוב", 0xffffe761),
        MPRank(400, "Cyan", "טורקיז", 0xff62eced), MPRank(650, "Light blue", "תכלת", 0xff8dcaff),
        MPRank(900, "Orange", "כתום", 0xffffa64f), MPRank(1150, "Pink", "ורוד", 0xffff75b5),
        MPRank(1450, "Red", "אדום", 0xffef5350), MPRank(1750, "Blue", "כחול", 0xff2459c5, 0xffffffff),
        MPRank(2050, "Purple", "סגול", 0xff8b54c5, 0xffffffff), MPRank(2400, "Brown", "חום", 0xff795548, 0xffffffff), MPRank(2750, "Silver", "כסף", 0xffd8e0e9),
        MPRank(3100, "Gold", "זהב", 0xffffcf40),
    ]
    static var lastIndex: Int { all.count - 1 }
    static func index(_ points: Int) -> Int { max(all.lastIndex(where: { max(points, 0) >= $0.threshold }) ?? -1, 0) }
    static func at(_ points: Int) -> MPRank { all[index(points)] }
    /// Kotlin `roundToInt` (half away from zero for these positive values).
    private static func round(_ x: Double) -> Int { Int(x.rounded()) }
    /// Points for beating a house player: scaled by its strength within the roster and by the control
    /// (Standard 3...7, Pro 5...10, Starter/Beginner 1...5).
    static func bot(_ b: MPBot, control: Int = 0) -> Int {
        let strengths = MPRoster.all.map(\.profile.strength), lo = strengths.min() ?? 0, hi = strengths.max() ?? 1
        let range: ClosedRange<Int>
        switch MPControlChoice.normalize(control) { case 0: range = 3...7; case 3: range = 5...10; default: range = 1...5 }
        return round(Double(range.lowerBound) + Double(range.upperBound - range.lowerBound) * ((b.strength - lo) / max(hi - lo, 0.01)).mpClamp(0, 1))
    }
    static func human(_ opponentPoints: Int) -> Int { humanLevel(index(opponentPoints)) }
    /// Points for beating a human of colour `level` (Standard 5...15, Pro 8...20, Starter/Beginner 3...10).
    static func humanLevel(_ level: Int, control: Int = 0) -> Int {
        let range: ClosedRange<Int>
        switch MPControlChoice.normalize(control) { case 0: range = 5...15; case 3: range = 8...20; default: range = 3...10 }
        return round(Double(range.lowerBound) + Double(range.upperBound - range.lowerBound) * Double(min(max(level, 0), lastIndex)) / Double(lastIndex))
    }
    /// Daily journey completion reward for journey step `step`.
    static func daily(_ step: Int) -> Int {
        switch step { case 0...4: return 3; case 5...9: return 5; case 10...19: return 7; case 20...29: return 10; case 30...39: return 12; default: return 15 }
    }
    static func podium(_ place: Int) -> Int { switch place { case 1: return 15; case 2: return 10; case 3: return 5; default: return 0 } }
    static func ink(_ color: UInt32) -> UInt32 { [0xff2459c5, 0xff795548, 0xff8b54c5].contains(color) ? 0xffffffff : 0xff17283f }
}

/// Android `RankBadge`: another player's colour as published in `minikPingPong/profiles/<uid>/{rankPoints, rankLevel}`.
struct MPRankBadge: Equatable, Codable {
    var points = 0, level = 0
    init(points: Int = 0, level: Int = 0) { self.points = points; self.level = level }
    var safe: Self { .init(points: max(points, 0), level: min(max(level, 0), MPRanks.lastIndex)) }
    /// Wire for `profiles/<uid>` (Android `FirebasePongRepository.publishRank`); the repository agent writes it.
    var wire: [String: Any] { let s = safe; return ["rankPoints": s.points, "rankLevel": s.level] }
    /// Android `FirebasePongRepository.rank`: absent values read 0.
    init(wire: [String: Any]) {
        self.init(points: (wire["rankPoints"] as? NSNumber)?.intValue ?? 0, level: (wire["rankLevel"] as? NSNumber)?.intValue ?? 0)
        self = safe
    }
}
/// Android `RankRequirement`: house-player wins (or a streak of them) and champion wins needed for the next colour.
struct MPRankRequirement: Equatable { var bots: Int; var streak: Bool; var champions: Int }
/// Android `RankProgress`.
struct MPRankProgress: Equatable {
    var points = 0, level = 0, botWins = 0, streak = 0, championWins = 0
    var next: Int? { level + 1 < MPRanks.all.count ? level + 1 : nil }
    var eligible: Bool { next.map { points >= MPRanks.all[$0].threshold } ?? false }
    var requirement: MPRankRequirement { next.map(MPRankPromotion.requirement) ?? MPRankRequirement(bots: 0, streak: false, champions: 0) }
}

/// Android `RankPromotion`: colour challenges against the three strongest house players and the champions.
enum MPRankPromotion {
    /// The three strongest house players (strength, then id).
    static var strongest: [MPHousePlayer] {
        Array(MPRoster.all.sorted { $0.profile.strength != $1.profile.strength ? $0.profile.strength > $1.profile.strength : $0.id < $1.id }.prefix(3))
    }
    /// Colour numbers in the brief are one-based; stored levels (`target`) are zero-based.
    static func requirement(_ target: Int) -> MPRankRequirement {
        switch target + 1 {
        case 1...2: return .init(bots: 0, streak: false, champions: 0)
        case 3...5: return .init(bots: 3, streak: false, champions: 0)
        case 6...8: return .init(bots: 3, streak: false, champions: 1)
        case 9...10: return .init(bots: 3, streak: true, champions: 2)
        case 11: return .init(bots: 5, streak: true, champions: 3)
        default: return .init(bots: 5, streak: true, champions: 5)
        }
    }
    /// Android control ordinals: 3 Pro, 0 Standard, 1 Starter (4 Beginner never qualifies above level 6).
    static func minimumControl(_ target: Int) -> Int { switch target { case 10...11: return 3; case 7...9: return 0; default: return 1 } }
    static func allowedControl(_ target: Int, _ control: Int) -> Bool {
        switch minimumControl(target) { case 3: return control == 3; case 0: return [0, 3].contains(control); default: return [1, 0, 3].contains(control) }
    }
    /// The house players a challenge for `target` must beat: the strongest only when a streak is required.
    static func bots(_ target: Int) -> [MPHousePlayer] { requirement(target).streak ? Array(strongest.prefix(1)) : strongest }
    static func advance(_ s: MPRankProgress) -> MPRankProgress {
        guard let next = s.next else { return s }
        let r = s.requirement
        if s.eligible && (r.streak ? s.streak : s.botWins) >= r.bots && s.championWins >= r.champions {
            var n = s; n.level = next; n.botWins = 0; n.streak = 0; n.championWins = 0; return n
        }
        return s
    }
    static func result(_ s: MPRankProgress, points: Int, won: Bool, trial: Int?, bot: MPBot?, champion: Bool = false) -> MPRankProgress {
        var n = s
        n.points = Int(min(Int64(s.points) + Int64(max(points, 0)), Int64(Int32.max)))
        if !won && s.streak < s.requirement.bots { n.streak = 0 }
        if s.eligible && won, let target = s.next {
            let validBot = bot.map { p in bots(target).contains { $0.id == p.characterId && p.strength >= $0.profile.strength - 0.001 } } ?? false
            if trial == target && !champion && validBot { n.botWins = min(n.botWins + 1, 5); n.streak = min(n.streak + 1, 5) }
            if trial == target && champion && bot == championProfile(target) { n.championWins = min(n.championWins + 1, 5) }
        }
        return advance(n)
    }
    /// The champion for `target`: skill 7...10 and Gaya, Flare or Kyra in turn.
    static func championProfile(_ target: Int) -> MPBot {
        let over = max(target - 5, 0)
        let skill = min(max(7 + over * 3 / 6, 7), 10)
        let character = ["gaya", "flare", "kyra"][over % 3]
        return MPBot(speed: skill, reaction: skill, accuracy: skill, power: skill, agility: skill, characterId: character,
                     forehandSkill: skill, backhandSkill: skill, serveSkill: skill)
    }
    /// Android `RankPromotion.championTuning`: a champion trial (levels 5...11) reacts faster, aims better, answers more
    /// and hits up to 12 % faster. Any other level (Android passes -1) keeps the tuning.
    static func championTuning(_ base: MPTuning, _ target: Int) -> MPTuning {
        guard (5...11).contains(target) else { return base }
        let strength = Double(target - 5) / 6.0
        func boost(_ c: MPChance) -> MPChance {
            MPChance(min(1 - (1 - c.answer) * (1 - 0.55 * strength), 0.992), min(1 - (1 - c.good) * (1 - 0.4 * strength), 0.985))
        }
        var t = base, p = base.profile
        t.minikReactionInterval = base.minikReactionInterval * (1 - 0.18 * strength)
        t.minikAimError = base.minikAimError * (1 - 0.3 * strength)
        p.serveReceive = p.serveReceive.map(boost)
        p.forehandSame = boost(p.forehandSame); p.forehandCross = boost(p.forehandCross)
        p.backhandSame = boost(p.backhandSame); p.backhandCross = boost(p.backhandCross)
        p.firstForehandSpeed = p.firstForehandSpeed * (1 + 0.12 * strength)
        p.firstBackhandSpeed = p.firstBackhandSpeed * (1 + 0.12 * strength)
        p.maxSpeed = min(p.maxSpeed * (1 + 0.12 * strength), 2.8)
        t.profile = p
        return t
    }
}

/// Android `PongRanking`: atomic progress plus durable receipts, so reopening a result cannot pay or qualify twice.
/// UserDefaults keys are Android's `pong_ranking` keys under `modern.pong.ranking.`: `points`, `level`, `botWins`,
/// `streak`, `championWins`, `paid/<receipt>`, `played/<receipt>`, `opponent/<uid>`, `activeTrial`, `trial/<kind/code/createdAt>`,
/// `champion/<kind/code/createdAt>`, `promotion`. Sharing the badge online (`profiles/<uid>/rankPoints|rankLevel`) is the
/// caller's job after a `true` result: `MPRankBadge.wire`.
final class MPRanking {
    static let prefix = "modern.pong.ranking."
    private static let lock = NSLock()
    let defaults: UserDefaults
    init(_ defaults: UserDefaults = .standard) { self.defaults = defaults }
    private func key(_ name: String) -> String { MPRanking.prefix + name }
    private func int(_ name: String, _ fallback: Int = 0) -> Int { (defaults.object(forKey: key(name)) as? NSNumber)?.intValue ?? fallback }
    private func contains(_ name: String) -> Bool { defaults.object(forKey: key(name)) != nil }
    var state: MPRankProgress {
        MPRankProgress(points: max(int("points"), 0), level: min(max(int("level"), 0), 11), botWins: int("botWins"), streak: int("streak"), championWins: int("championWins"))
    }
    var points: Int { state.points }
    var rank: MPRank { MPRanks.all[state.level] }
    var badge: MPRankBadge { MPRankBadge(points: points, level: state.level) }
    @discardableResult private func commit(_ receipt: String, _ next: MPRankProgress) -> Bool {
        let before = state
        defaults.set(true, forKey: key("paid/" + receipt)); defaults.set(next.points, forKey: key("points")); defaults.set(next.level, forKey: key("level"))
        defaults.set(next.botWins, forKey: key("botWins")); defaults.set(next.streak, forKey: key("streak")); defaults.set(next.championWins, forKey: key("championWins"))
        if next.level > before.level { defaults.set(next.level, forKey: key("promotion")) }
        return true
    }
    /// Pays `amount` once per `receipt` (e.g. a daily-journey completion).
    @discardableResult func award(_ receipt: String, _ amount: Int) -> Bool {
        MPRanking.lock.lock(); defer { MPRanking.lock.unlock() }
        if amount <= 0 || contains("paid/" + receipt) { return false }
        var s = state; s.points = Int(min(Int64(points) + Int64(amount), Int64(Int32.max)))
        return commit(receipt, MPRankPromotion.advance(s))
    }
    func rememberOpponent(_ uid: String, _ badge: MPRankBadge) { defaults.set(badge.level, forKey: key("opponent/" + uid)) }
    private func trialKey(_ s: MPSession) -> String { s.kind.rawValue + "/" + s.code + "/" + String(s.createdAt) }
    var activeTrialCode: String? { defaults.string(forKey: key("activeTrial")) }
    func clearActiveTrial() { defaults.removeObject(forKey: key("activeTrial")) }
    func abandonTrial() {
        MPRanking.lock.lock(); defer { MPRanking.lock.unlock() }
        var s = state; if s.streak < s.requirement.bots { s.streak = 0 }
        commit("abandon/" + (activeTrialCode ?? "null"), s); clearActiveTrial()
    }
    /// A finished local match against a house player (Android `ModernActivity`: receipt `modern/<completionId>`).
    @discardableResult func localResult(_ receipt: String, won: Bool, bot: MPBot, control: Int = 0) -> Bool {
        MPRanking.lock.lock(); defer { MPRanking.lock.unlock() }
        if contains("paid/" + receipt) { return false }
        return commit(receipt, MPRankPromotion.result(state, points: won ? MPRanks.bot(bot, control: control) : 0, won: won, trial: nil, bot: bot))
    }
    /// Android `registerTrial` requires an eligible player challenging the next colour; iOS returns false instead of throwing.
    @discardableResult func registerTrial(_ s: MPSession, target: Int, champion: Bool) -> Bool {
        guard state.eligible && state.next == target else { return false }
        defaults.set(s.code, forKey: key("activeTrial")); defaults.set(target, forKey: key("trial/" + trialKey(s)))
        defaults.set(champion, forKey: key("champion/" + trialKey(s))); return true
    }
    func trial(_ s: MPSession) -> Int? { let v = int("trial/" + trialKey(s), -1); return (2...11).contains(v) ? v : nil }
    func champion(_ s: MPSession) -> Bool { trial(s) != nil && defaults.bool(forKey: key("champion/" + trialKey(s))) }
    /// Android `PongRanking.session`: pays each finished match of `uid` once (and a tournament podium once). Returns
    /// true when anything changed, so the caller republishes the badge.
    @discardableResult func session(_ s: MPSession, uid: String, online: Bool, opponentBadge: MPRankBadge? = nil) -> Bool {
        MPRanking.lock.lock(); defer { MPRanking.lock.unlock() }
        if !s.human(uid) { return false }
        let base = (online ? "online" : "local") + "/" + trialKey(s) + "/" + uid
        var changed = false
        // Android iterates its decoded map; iOS uses the match ids' order so a replay pays in a stable order.
        for m in s.matches.values.filter({ $0.contains(uid) }).sorted(by: { $0.id < $1.id }) {
            let receipt = base + "/" + m.id
            if m.phase == .playing { defaults.set(true, forKey: key("played/" + receipt)); defaults.set(true, forKey: key("played/" + base)) }
            if m.phase == .finished && defaults.bool(forKey: key("played/" + receipt)) && !contains("paid/" + receipt) {
                if activeTrialCode == s.code { clearActiveTrial() }
                let other = s.participants[m.a == uid ? m.b : m.a], won = m.winner == uid
                // A human win must wait for a real profile (or the saved profile read during play).
                if won && online && s.kind == .friendly && other?.bot == nil && opponentBadge == nil && !contains("opponent/" + (other?.id ?? "null")) { continue }
                let amount: Int
                if !won { amount = 0 }
                else if s.kind == .tournament { amount = 1 }
                else if let bot = other?.bot { amount = MPRanks.bot(bot, control: s.difficulty) }
                else { amount = MPRanks.humanLevel(opponentBadge?.level ?? int("opponent/" + (other?.id ?? "null")), control: s.difficulty) }
                let qualifying = trial(s).flatMap { !online && s.target >= 11 && MPRankPromotion.allowedControl($0, s.difficulty) ? $0 : nil }
                changed = commit(receipt, MPRankPromotion.result(state, points: amount, won: won, trial: qualifying, bot: other?.bot, champion: champion(s))) || changed
            }
        }
        if s.complete && s.kind == .tournament && defaults.bool(forKey: key("played/" + base)) && s.matches.values.contains(where: { $0.phase == .finished }) {
            let place = (MPRanking.podium(s).firstIndex(of: uid) ?? -1) + 1
            let receipt = base + "/podium", amount = MPRanks.podium(place)
            if amount > 0 && !contains("paid/" + receipt) {
                var next = state; next.points = Int(min(Int64(next.points) + Int64(amount), Int64(Int32.max)))
                changed = commit(receipt, MPRankPromotion.advance(next)) || changed
            }
        }
        return changed
    }
    /// Android `CompletionText.podium`: the first three of the standings; a knockout puts its winner and the final's
    /// loser first.
    static func podium(_ s: MPSession) -> [String] {
        let standings = MPRules.standings(s).map(\.id)
        guard s.knockout, let winner = MPKnockout.winner(s) else { return Array(standings.prefix(3)) }
        let final = MPKnockout.matches(s, s.rounds.keys.max() ?? 0).first { $0.winner == winner }
        let runner = final.map { $0.a == winner ? $0.b : $0.a }
        var out: [String] = []
        for id in [winner] + (runner.map { [$0] } ?? []) + standings where !out.contains(id) { out.append(id) }
        return Array(out.prefix(3))
    }
    /// The colour just reached, until the celebration acknowledges it.
    func promotion() -> Int? { let v = int("promotion"); return v > 0 ? v : nil }
    func acknowledgePromotion() { defaults.removeObject(forKey: key("promotion")) }
}

/// Android `PongRankPresentation` colours: rank surfaces bypass the generic pastel palette (metallic Silver).
enum MPRankPresentation {
    /// The raised face of a rank surface: Silver has its own metallic gradient.
    static func face(_ rank: MPRank) -> MPCourtFace {
        if rank == MPRanks.all[10] { return MPCourtFace(base: rank.color, top: 0xffe2e8f0, middle: 0xffb8c4d2, bottom: 0xff94a5ba) }
        return MPCourtFace(base: rank.color, top: MPColor.mix(rank.color, 0xffffffff, 0.14), middle: rank.color, bottom: MPColor.mix(rank.color, 0xff000000, 0.08))
    }
    /// The 1-point outline of a rank surface (White gets a blue-grey edge).
    static func stroke(_ rank: MPRank) -> UInt32 { rank == MPRanks.all[0] ? 0xff7993ab : MPColor.mix(rank.color, 0xff000000, 0.2) }
    /// Android `summary` text colour and divider.
    static let summaryText: UInt32 = 0xff173e56
    static let summaryDivider: UInt32 = 0x66718da8
}
