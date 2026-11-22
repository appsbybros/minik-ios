import Foundation

/// iOS payment model (CLAUDE.md, docs/amudu-ios-handoff.md "Deliberate difference: iOS payment model"): Android Spud
/// shows ads and sells "Remove ads"; iOS Spud has no ads and sells one non-consumable, the full game, with a free tier.
/// These are the pure rules of that free tier (no StoreKit, no UserDefaults), so `SpudAccessTests` can pin every limit.
enum SpudAccess {
    /// The App Store product (non-consumable, Family Sharing on). project.yml puts it in the Info.plist under
    /// `productInfoKey`.
    static let productIdentifier = "com.appsbybros.minik.spud.full_game"
    static let productInfoKey = "SpudFullGameProductIdentifier"

    /// At most 3 players in a game without the full game: the player plus house players and/or people.
    static let freePlayers = 3
    /// The most players any game has (Android's room capacity 2...10).
    static let fullPlayers = 10
    static let freeScenes: [ArenaScene] = [.park]
    /// The paint balloon is not in this list: it is metered (`PaintBalloonAllowance`), never locked outright.
    /// Bug report 2026-11-22 (2.3): the Beach ball is part of the full game too; only Soft foam is free.
    static let freeBalls: [BallKind] = [.foam]
    /// Bug report 2026-11-22 (2.3): these characters need the full game, as the player's own character and as house
    /// players. The others (Miniko, Minik, Moshiko, Amber, Comet, June, Coach 67) stay free.
    static let lockedCharacters: [String] = ["flare", "kyra", "gaya", "mia"]
    /// The character a player without the full game plays as when the saved one is locked.
    static let freeAvatar = "miniko"
    /// Steps 0...6 of the daily skill journey (challenges 1-7 of the first cycle).
    static let freeChallenges = 7
    /// Free paint-balloon games before the one-a-day allowance starts.
    static let welcomePaintGames = 3

    static func playersLocked(_ players: Int, owner: Bool) -> Bool {
        return !owner && players > freePlayers
    }

    static func sceneLocked(_ scene: ArenaScene, owner: Bool) -> Bool {
        return !owner && !freeScenes.contains(scene)
    }

    /// Neon and tennis need the full game; the paint balloon only needs a free paint game (or the full game).
    static func ballLocked(_ ball: BallKind, owner: Bool) -> Bool {
        return !owner && ball != .paint && !freeBalls.contains(ball)
    }

    static func characterLocked(_ id: String, owner: Bool) -> Bool {
        return !owner && lockedCharacters.contains(id)
    }

    /// The character this player plays as: a locked saved one (chosen before, or kept after a refund) plays as Miniko;
    /// the saved choice is never rewritten, so buying brings it back.
    static func avatar(_ id: String, owner: Bool) -> String {
        return characterLocked(id, owner: owner) ? freeAvatar : id
    }

    static func challengeLocked(_ step: Int, owner: Bool) -> Bool {
        return !owner && step >= freeChallenges
    }

    /// A lesson's or challenge's conditions follow the arena rule (Andromeda is the space conditions).
    static func conditionsLocked(_ conditions: PracticeConditions, owner: Bool) -> Bool {
        return sceneLocked(conditions.scene, owner: owner)
    }

    /// Online: only the host's choices (players, arena, ball) shape a room, so only a host without the full game is
    /// limited. Joiners are never checked, whatever the host's platform, and a room opened from Android is never
    /// limited (it is never created by this code).
    static func limitsRoom(owner: Bool, hosting: Bool) -> Bool {
        return !owner && hosting
    }

    /// The choices a game starts with.
    struct Choices: Equatable {
        var players: Int
        var scene: ArenaScene
        var ball: BallKind
        var house: [String]

        init(players: Int, scene: ArenaScene, ball: BallKind, house: [String] = []) {
            self.players = players
            self.scene = scene
            self.ball = ball
            self.house = house
        }
    }

    /// What a game this player starts or hosts may use. Old saved settings (the default room capacity 6, a saved
    /// arena or ball) are clamped to the free values here, at the start; the stored settings are never rewritten, so
    /// buying the full game brings them back. A paint balloon stays: it is metered when the game starts.
    static func clamp(_ choices: Choices, owner: Bool) -> Choices {
        if owner { return choices }
        var out = choices
        out.players = min(choices.players, freePlayers)
        if sceneLocked(choices.scene, owner: false) { out.scene = freeScenes[0] }
        if ballLocked(choices.ball, owner: false) { out.ball = freeBalls[0] }
        out.house = Array(choices.house.filter { !characterLocked($0, owner: false) }.prefix(max(out.players - 1, 0)))
        return out
    }

    /// A practice ball: a locked saved choice falls back to the first free ball the challenge allows.
    static func practiceBall(_ ball: BallKind, allowed: [BallKind], owner: Bool) -> BallKind {
        if !ballLocked(ball, owner: owner) { return ball }
        return allowed.first { !ballLocked($0, owner: owner) } ?? freeBalls[0]
    }

    /// Practice conditions: locked ones (Andromeda) fall back to the calm park.
    static func practiceConditions(_ conditions: PracticeConditions, owner: Bool) -> PracticeConditions {
        return conditionsLocked(conditions, owner: owner) ? .calm : conditions
    }
}

/// iOS payment model (CLAUDE.md): the paint balloon without the full game. The first `SpudAccess.welcomePaintGames`
/// games are free; after those, one free game per local calendar day. Unused days are lost (nothing accumulates), and
/// the day on which the last welcome game is used counts as that day's free game, so the next one comes tomorrow.
/// Counted per game (a match, a hosted room or league round, a challenge or lesson run), never per throw.
/// A pure value: every answer is a function of the stored state, the date and the calendar.
struct PaintBalloonAllowance: Equatable {
    /// Welcome games used, 0...3.
    var welcomeUsed: Int
    /// The local day ("yyyy-MM-dd") whose free game was used, or nil.
    var lastFreeDay: String?

    init(welcomeUsed: Int = 0, lastFreeDay: String? = nil) {
        self.welcomeUsed = max(0, min(welcomeUsed, SpudAccess.welcomePaintGames))
        self.lastFreeDay = lastFreeDay
    }

    /// The local calendar day of `date` in `calendar` (its time zone).
    static func day(_ date: Date, calendar: Calendar) -> String {
        let c = calendar.dateComponents([.year, .month, .day], from: date)
        return pad(c.year ?? 0, 4) + "-" + pad(c.month ?? 0, 2) + "-" + pad(c.day ?? 0, 2)
    }

    private static func pad(_ value: Int, _ width: Int) -> String {
        let digits = String(value)
        return String(repeating: "0", count: max(width - digits.count, 0)) + digits
    }

    /// Whether the free games left are welcome games (3, 2 or 1 left) rather than today's game.
    var inWelcome: Bool {
        return welcomeUsed < SpudAccess.welcomePaintGames
    }

    /// Free paint-balloon games that can start now: the welcome games left, else 1 or 0 for today.
    func gamesLeft(now: Date, calendar: Calendar) -> Int {
        if inWelcome { return SpudAccess.welcomePaintGames - welcomeUsed }
        return lastFreeDay == PaintBalloonAllowance.day(now, calendar: calendar) ? 0 : 1
    }

    /// The state after one paint-balloon game starts, or nil when no free game is left.
    func consuming(now: Date, calendar: Calendar) -> PaintBalloonAllowance? {
        guard gamesLeft(now: now, calendar: calendar) > 0 else { return nil }
        let today = PaintBalloonAllowance.day(now, calendar: calendar)
        var next = self
        if inWelcome {
            next.welcomeUsed += 1
            if !next.inWelcome { next.lastFreeDay = today }
        } else {
            next.lastFreeDay = today
        }
        return next
    }
}

/// The paint-balloon allowance in UserDefaults (removed with the other `amudu.` keys by `SpudScreenshot.prepare`).
struct PaintBalloonAllowanceRepository: @unchecked Sendable {
    static let welcomeKey = "amudu.store.paintWelcomeUsed"
    static let dayKey = "amudu.store.paintFreeDay"

    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    func load() -> PaintBalloonAllowance {
        return PaintBalloonAllowance(welcomeUsed: defaults.integer(forKey: PaintBalloonAllowanceRepository.welcomeKey),
                                     lastFreeDay: defaults.string(forKey: PaintBalloonAllowanceRepository.dayKey))
    }

    func save(_ value: PaintBalloonAllowance) {
        defaults.set(value.welcomeUsed, forKey: PaintBalloonAllowanceRepository.welcomeKey)
        if let day = value.lastFreeDay {
            defaults.set(day, forKey: PaintBalloonAllowanceRepository.dayKey)
        } else {
            defaults.removeObject(forKey: PaintBalloonAllowanceRepository.dayKey)
        }
    }
}
