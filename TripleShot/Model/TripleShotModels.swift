import Foundation

// Port of model/TripleShotModels.kt (TripleShotGame 6c38131). Spec 01.
// Firebase wire codecs for the online records live in TripleShotModelsFirebase.swift.

/**
 * Question topics shown in the topic picker.
 *
 * `label` is kept as the Hebrew label for compatibility with older code.
 * New UI should prefer [labelFor] so English-device UI can display English labels.
 * Case order is the Kotlin ordinal order (load-bearing: seeds, argument order, pickers).
 */
enum QuestionCategory: String, KotlinEnum {
    case GENERAL_KNOWLEDGE
    case PROGRAMMING
    case SCIENCE
    case ASTRONOMY
    case PARADOX
    case AI
    case HISTORY
    case ENGLISH
    case KIDS_ARITHMETIC
    case MATH
    case MATRICULATION_MATH

    var label: String {
        switch self {
        case .GENERAL_KNOWLEDGE: return "ידע כללי"
        case .PROGRAMMING: return "ראיון תכנות"
        case .SCIENCE: return "מדע"
        case .ASTRONOMY: return "אסטרונומיה"
        case .PARADOX: return "פרדוקסים במדע ומחשבה"
        case .AI: return "בינה מלאכותית"
        case .HISTORY: return "היסטוריה"
        case .ENGLISH: return "לימוד אנגלית"
        case .KIDS_ARITHMETIC: return "חשבון לילדים"
        case .MATH: return "מתמטיקה"
        case .MATRICULATION_MATH: return "מתמטיקה לבגרות - תרגול"
        }
    }

    private var englishLabel: String {
        switch self {
        case .GENERAL_KNOWLEDGE: return "General knowledge"
        case .PROGRAMMING: return "Programming interview"
        case .SCIENCE: return "Science"
        case .ASTRONOMY: return "Astronomy"
        case .PARADOX: return "Science & thought paradoxes"
        case .AI: return "Artificial intelligence"
        case .HISTORY: return "History"
        case .ENGLISH: return "Learn English"
        case .KIDS_ARITHMETIC: return "Kids arithmetic"
        case .MATH: return "Mathematics"
        case .MATRICULATION_MATH: return "Matriculation math practice"
        }
    }

    func labelFor(languageCode: String) -> String {
        if languageCode == "en" ||
            languageCode == "EN" ||
            languageCode == "En" ||
            languageCode == "eN" {
            return englishLabel
        } else {
            return label
        }
    }

    /// Positional form (Kotlin `labelFor(code)`).
    func labelFor(_ languageCode: String) -> String {
        return labelFor(languageCode: languageCode)
    }
}

/**
 * Orientation chosen specifically for basketball gameplay.
 *
 * The app/home can stay portrait. A bot basketball match can opt into LANDSCAPE for more court
 * width without changing the existing portrait mode.
 */
enum TripleShotGameOrientation: String, KotlinEnum {
    case PORTRAIT
    case LANDSCAPE
}

enum GameType: String, KotlinEnum {
    case PRACTICE
    case SHOOTING_CHALLENGE
    case HORSE
    /** Local real-court duel. */
    case ONE_ON_ONE
    /** Local team basketball: 2v2 or 3v3 with bots. */
    case TEAM_MATCH
}

struct AnswerOption: Hashable {
    var text: String
    /**
     * 0..100. Most current questions use 0/100, while the model already supports
     * graded interview answers later.
     */
    var qualityPercent: Int
}

struct TripleShotQuestion: Hashable {
    var id: String
    var category: QuestionCategory
    var prompt: String
    var answers: [AnswerOption]
    var explanation: String
}

enum GameLimitMode: String, KotlinEnum {
    case RANKED_BOTH
    case BALLS_ONLY
    case TIME_ONLY
}

/**
 * Launch configuration of every game screen.
 *
 * `selectedCategories` is a Kotlin `Set`: an insertion-ordered set (KLinkedSet) whose iteration order is the
 * producer's order (EnumSet = ordinal order by default). The second initialiser accepts any ordered sequence
 * (array, KLinkedSet, ...) and keeps the first occurrence of each topic, like Kotlin `toSet()`.
 * Equality is the data-class equality (the set compares as a set, order ignored, like java.util.AbstractSet).
 */
struct TripleShotGameConfig: Hashable {
    var playerName: String
    var gameType: GameType
    var limitMode: GameLimitMode
    var selectedCategories: KLinkedSet<QuestionCategory>
    var roomId: String?
    /** Firebase server timestamp used to keep Live countdowns aligned across devices. */
    var roomStartedAtMs: Int64
    /** True for a local match against either adaptive BOB or a fixed character bot. */
    var botMatch: Bool
    /** Stable roster id for the locally controlled on-court character. */
    var playerCharacterId: String
    /** Stable roster id for the local bot. BOB remains the default adaptive trainer. */
    var botCharacterId: String
    /** 1 for 1v1, 2 for 2v2, 3 for 3v3. */
    var teamSize: Int
    /** Extra members of the human team, excluding [playerCharacterId]. */
    var teammateCharacterIds: [String]
    /** Opposing team. For 1v1 this may contain only [botCharacterId]. */
    var opponentCharacterIds: [String]
    /** Basketball display mode chosen in Play vs Bot. Non-basketball modes keep portrait. */
    var gameOrientation: TripleShotGameOrientation
    /** Stable visual court id. Missing artwork safely falls back to the original forest court. */
    var courtId: String
    var seed: Int64
    var ballLimit: Int
    var timeLimitSeconds: Int
    var leagueSeasonId: String
    var leagueFixtureKey: String
    var teamName: String
    var opponentTeamName: String
    var teamColor: Int
    var opponentTeamColor: Int

    init(
        playerName: String,
        gameType: GameType = .SHOOTING_CHALLENGE,
        limitMode: GameLimitMode = .TIME_ONLY,
        selectedCategories: KLinkedSet<QuestionCategory> = KLinkedSet(QuestionCategory.allCases),
        roomId: String? = nil,
        roomStartedAtMs: Int64 = 0,
        botMatch: Bool = false,
        playerCharacterId: String = TripleShotCharacterRoster.ID_WOMAN_DARK,
        botCharacterId: String = TripleShotCharacterRoster.ID_BOB,
        teamSize: Int = 1,
        teammateCharacterIds: [String] = [],
        opponentCharacterIds: [String] = [],
        gameOrientation: TripleShotGameOrientation = .PORTRAIT,
        courtId: String = "enchanted_forest",
        seed: Int64 = ASystem.currentTimeMillis(),
        ballLimit: Int = 20,
        timeLimitSeconds: Int = 60,
        leagueSeasonId: String = "",
        leagueFixtureKey: String = "",
        teamName: String = "",
        opponentTeamName: String = "",
        teamColor: Int = Int(Int32(bitPattern: 0xff76d8ff)),
        opponentTeamColor: Int = Int(Int32(bitPattern: 0xffffb779))
    ) {
        self.playerName = playerName
        self.gameType = gameType
        self.limitMode = limitMode
        self.selectedCategories = selectedCategories
        self.roomId = roomId
        self.roomStartedAtMs = roomStartedAtMs
        self.botMatch = botMatch
        self.playerCharacterId = playerCharacterId
        self.botCharacterId = botCharacterId
        self.teamSize = teamSize
        self.teammateCharacterIds = teammateCharacterIds
        self.opponentCharacterIds = opponentCharacterIds
        self.gameOrientation = gameOrientation
        self.courtId = courtId
        self.seed = seed
        self.ballLimit = ballLimit
        self.timeLimitSeconds = timeLimitSeconds
        self.leagueSeasonId = leagueSeasonId
        self.leagueFixtureKey = leagueFixtureKey
        self.teamName = teamName
        self.opponentTeamName = opponentTeamName
        self.teamColor = teamColor
        self.opponentTeamColor = opponentTeamColor
    }

    /** Same as the main initialiser, for producers that hold the topics in an array or another sequence. */
    init<S: Sequence>(
        playerName: String,
        gameType: GameType = .SHOOTING_CHALLENGE,
        limitMode: GameLimitMode = .TIME_ONLY,
        selectedCategories: S,
        roomId: String? = nil,
        roomStartedAtMs: Int64 = 0,
        botMatch: Bool = false,
        playerCharacterId: String = TripleShotCharacterRoster.ID_WOMAN_DARK,
        botCharacterId: String = TripleShotCharacterRoster.ID_BOB,
        teamSize: Int = 1,
        teammateCharacterIds: [String] = [],
        opponentCharacterIds: [String] = [],
        gameOrientation: TripleShotGameOrientation = .PORTRAIT,
        courtId: String = "enchanted_forest",
        seed: Int64 = ASystem.currentTimeMillis(),
        ballLimit: Int = 20,
        timeLimitSeconds: Int = 60,
        leagueSeasonId: String = "",
        leagueFixtureKey: String = "",
        teamName: String = "",
        opponentTeamName: String = "",
        teamColor: Int = Int(Int32(bitPattern: 0xff76d8ff)),
        opponentTeamColor: Int = Int(Int32(bitPattern: 0xffffb779))
    ) where S.Element == QuestionCategory {
        self.init(
            playerName: playerName,
            gameType: gameType,
            limitMode: limitMode,
            selectedCategories: KLinkedSet(selectedCategories),
            roomId: roomId,
            roomStartedAtMs: roomStartedAtMs,
            botMatch: botMatch,
            playerCharacterId: playerCharacterId,
            botCharacterId: botCharacterId,
            teamSize: teamSize,
            teammateCharacterIds: teammateCharacterIds,
            opponentCharacterIds: opponentCharacterIds,
            gameOrientation: gameOrientation,
            courtId: courtId,
            seed: seed,
            ballLimit: ballLimit,
            timeLimitSeconds: timeLimitSeconds,
            leagueSeasonId: leagueSeasonId,
            leagueFixtureKey: leagueFixtureKey,
            teamName: teamName,
            opponentTeamName: opponentTeamName,
            teamColor: teamColor,
            opponentTeamColor: opponentTeamColor
        )
    }

    var isMultiplayer: Bool {
        return roomId != nil && roomId!.length > 0
    }

    var isPractice: Bool {
        return gameType == .PRACTICE && !isMultiplayer && !botMatch
    }

    var isBotMatch: Bool {
        return botMatch && !isMultiplayer
    }

    var isOneOnOne: Bool {
        return gameType == .ONE_ON_ONE && isBotMatch
    }

    var isTeamMatch: Bool {
        return gameType == .TEAM_MATCH && isBotMatch && teamSize >= 2 && teamSize <= 3
    }

    /**
     * The global high-score table is now based on the short, repeatable
     * Shooting Challenge rather than an unlimited cumulative score.
     * The current menu starts it alongside a house opponent; that must not exclude
     * the human's own 60-second result after the legacy solo entry was removed.
     */
    var isRanked: Bool {
        return gameType == .SHOOTING_CHALLENGE &&
            !isMultiplayer &&
            limitMode == .TIME_ONLY &&
            timeLimitSeconds == 60
    }

    /** Default of [copy]'s `roomId`: keep the current room id. Passing `roomId: nil` clears it, as in Kotlin. */
    static let COPY_KEEP_ROOM_ID = "\u{0}TripleShotGameConfig.copy.keepRoomId\u{0}"

    /** Kotlin data-class `copy(...)`: every argument left out keeps its current value. */
    func copy(
        playerName: String? = nil,
        gameType: GameType? = nil,
        limitMode: GameLimitMode? = nil,
        selectedCategories: KLinkedSet<QuestionCategory>? = nil,
        roomId: String? = TripleShotGameConfig.COPY_KEEP_ROOM_ID,
        roomStartedAtMs: Int64? = nil,
        botMatch: Bool? = nil,
        playerCharacterId: String? = nil,
        botCharacterId: String? = nil,
        teamSize: Int? = nil,
        teammateCharacterIds: [String]? = nil,
        opponentCharacterIds: [String]? = nil,
        gameOrientation: TripleShotGameOrientation? = nil,
        courtId: String? = nil,
        seed: Int64? = nil,
        ballLimit: Int? = nil,
        timeLimitSeconds: Int? = nil,
        leagueSeasonId: String? = nil,
        leagueFixtureKey: String? = nil,
        teamName: String? = nil,
        opponentTeamName: String? = nil,
        teamColor: Int? = nil,
        opponentTeamColor: Int? = nil
    ) -> TripleShotGameConfig {
        var c = self
        if let v = playerName { c.playerName = v }
        if let v = gameType { c.gameType = v }
        if let v = limitMode { c.limitMode = v }
        if let v = selectedCategories { c.selectedCategories = v }
        if roomId != TripleShotGameConfig.COPY_KEEP_ROOM_ID { c.roomId = roomId }
        if let v = roomStartedAtMs { c.roomStartedAtMs = v }
        if let v = botMatch { c.botMatch = v }
        if let v = playerCharacterId { c.playerCharacterId = v }
        if let v = botCharacterId { c.botCharacterId = v }
        if let v = teamSize { c.teamSize = v }
        if let v = teammateCharacterIds { c.teammateCharacterIds = v }
        if let v = opponentCharacterIds { c.opponentCharacterIds = v }
        if let v = gameOrientation { c.gameOrientation = v }
        if let v = courtId { c.courtId = v }
        if let v = seed { c.seed = v }
        if let v = ballLimit { c.ballLimit = v }
        if let v = timeLimitSeconds { c.timeLimitSeconds = v }
        if let v = leagueSeasonId { c.leagueSeasonId = v }
        if let v = leagueFixtureKey { c.leagueFixtureKey = v }
        if let v = teamName { c.teamName = v }
        if let v = opponentTeamName { c.opponentTeamName = v }
        if let v = teamColor { c.teamColor = v }
        if let v = opponentTeamColor { c.opponentTeamColor = v }
        return c
    }
}

struct ShotSkill: Hashable {
    /** Horizontal fine-aim error, normalized around 0. */
    var aimError: Float
    /** Release power error, normalized around 0. */
    var powerError: Float
    /** Release pitch/arc error, normalized around 0. */
    var arcError: Float
    var rawPeakGyro: Float
    var rawReleasePitchDeg: Float

    /** Kotlin data-class `copy(...)`: every argument left out keeps its current value. */
    func copy(
        aimError: Float? = nil,
        powerError: Float? = nil,
        arcError: Float? = nil,
        rawPeakGyro: Float? = nil,
        rawReleasePitchDeg: Float? = nil
    ) -> ShotSkill {
        return ShotSkill(
            aimError: aimError ?? self.aimError,
            powerError: powerError ?? self.powerError,
            arcError: arcError ?? self.arcError,
            rawPeakGyro: rawPeakGyro ?? self.rawPeakGyro,
            rawReleasePitchDeg: rawReleasePitchDeg ?? self.rawReleasePitchDeg
        )
    }
}

struct ShotOutcome: Hashable {
    var made: Bool
    var targetOffsetX: Float
    var targetOffsetY: Float
    var quality: Float
}

struct ScoreDelta: Hashable {
    var answerQualityPercent: Int
    var answerCorrect: Bool
    var knowledgeMultiplier: Int
    var knowledgePoints: Int
    var basketPoints: Int
    var totalPoints: Int
    var knowledgeStreak: Int
    var shootingStreak: Int
    var bestKnowledgeStreak: Int
    var bestShootingStreak: Int
}

struct LivePlayerState: Hashable {
    var uid: String = ""
    var name: String = ""
    var score: Int = 0
    var knowledgeStreak: Int = 0
    var shootingStreak: Int = 0
    var bestKnowledgeStreak: Int = 0
    var bestShootingStreak: Int = 0
    var correctAnswers: Int = 0
    var madeShots: Int = 0
    var shots: Int = 0
    var lastEvent: String = ""
    /** True once this player has reached the shared Live deadline. */
    var finished: Bool = false
    var updatedAt: Int64 = 0
}

struct RoomMeta: Hashable {
    var hostUid: String = ""
    var status: String = "WAITING"
    var seed: Int64 = 0
    var createdAt: Int64 = 0
    var startedAt: Int64 = 0
    var gameType: String = GameType.SHOOTING_CHALLENGE.name
    var categories: [String] = []
    var timeLimitSeconds: Int = 60
    var maxPlayers: Int = 4
}

/**
 * Authoritative turn state for Live HORSE / חיובים.
 *
 * It intentionally stores only small turn facts. The physical shot itself is still
 * published as [LiveShotEvent], so every spectator can replay the real flight.
 */
struct LiveHorseState: Hashable {
    var phase: String = LiveHorseState.PHASE_SETTING
    var setterUid: String = ""
    var currentPlayerUid: String = ""
    var challengeEstablished: Bool = false
    var challengeCategory: String = ""
    var challengeSpotId: String = ""
    var challengeSpotX: Float = 0
    var challengeSpotY: Float = 0
    var playerOrder: [String] = []
    var attemptedUids: [String] = []
    var penalties: [String: Int] = [:]
    var spectatorSlots: [String: Int] = [:]
    var winnerUid: String = ""
    var turnNumber: Int = 0
    var updatedAt: Int64 = 0

    var isFinished: Bool {
        return phase == LiveHorseState.PHASE_FINISHED || !winnerUid.kotlinIsBlank
    }

    static let PHASE_SETTING = "SETTING"
    static let PHASE_ATTEMPT = "ATTEMPT"
    static let PHASE_FINISHED = "FINISHED"

    /** Kotlin data-class `copy(...)`: every argument left out keeps its current value. */
    func copy(
        phase: String? = nil,
        setterUid: String? = nil,
        currentPlayerUid: String? = nil,
        challengeEstablished: Bool? = nil,
        challengeCategory: String? = nil,
        challengeSpotId: String? = nil,
        challengeSpotX: Float? = nil,
        challengeSpotY: Float? = nil,
        playerOrder: [String]? = nil,
        attemptedUids: [String]? = nil,
        penalties: [String: Int]? = nil,
        spectatorSlots: [String: Int]? = nil,
        winnerUid: String? = nil,
        turnNumber: Int? = nil,
        updatedAt: Int64? = nil
    ) -> LiveHorseState {
        return LiveHorseState(
            phase: phase ?? self.phase,
            setterUid: setterUid ?? self.setterUid,
            currentPlayerUid: currentPlayerUid ?? self.currentPlayerUid,
            challengeEstablished: challengeEstablished ?? self.challengeEstablished,
            challengeCategory: challengeCategory ?? self.challengeCategory,
            challengeSpotId: challengeSpotId ?? self.challengeSpotId,
            challengeSpotX: challengeSpotX ?? self.challengeSpotX,
            challengeSpotY: challengeSpotY ?? self.challengeSpotY,
            playerOrder: playerOrder ?? self.playerOrder,
            attemptedUids: attemptedUids ?? self.attemptedUids,
            penalties: penalties ?? self.penalties,
            spectatorSlots: spectatorSlots ?? self.spectatorSlots,
            winnerUid: winnerUid ?? self.winnerUid,
            turnNumber: turnNumber ?? self.turnNumber,
            updatedAt: updatedAt ?? self.updatedAt
        )
    }
}

struct LeaderboardEntry: Hashable {
    var uid: String = ""
    var name: String = ""
    var bestScore: Int = 0

    /**
     * All-time independent streak records. These stay useful for the existing
     * "shooting streak" leaderboard even when the best-score run happened elsewhere.
     */
    var bestShootingStreak: Int = 0
    var bestKnowledgeStreak: Int = 0
    var bestCorrectAnswers: Int = 0

    /**
     * Snapshot of the run that produced [bestScore]. Unlike the all-time streak
     * maxima above, these values always belong to the same 60-second run.
     */
    var bestRunCorrectAnswers: Int = 0
    var bestRunShots: Int = 0
    var bestRunMadeShots: Int = 0
    var bestRunKnowledgeAccuracyPercent: Int = 0
    var bestRunShootingPercent: Int = 0
    var bestRunCategories: [String] = []

    var updatedAt: Int64 = 0
}

/**
 * Per-player learning counters. Percentages are deliberately derived from the counters
 * so a 9/10 sample never becomes indistinguishable from a 900/1000 sample.
 * (No callers on Android: the repository writes this shape by explicit paths.)
 */
struct KnowledgeTopicStats: Hashable {
    var correct: Int = 0
    var total: Int = 0
    var updatedAt: Int64 = 0
}

/**
 * Minimal profile stored next to learning stats. Anonymous Firebase Auth still supplies
 * the stable installation identity; this is only the user-facing profile data.
 * (No callers on Android: the repository writes this shape by explicit paths.)
 */
struct PlayerLearningProfile: Hashable {
    var uid: String = ""
    var displayName: String = ""
    var createdAt: Int64 = 0
    var updatedAt: Int64 = 0
}

/**
 * One sampled ball position of a Live shot, in source-art coordinates.
 * Firebase Android writes `tMs` under the key "tms" and cannot read it back (spec 01 section 4.3).
 */
struct ShotReplaySample: Hashable {
    var tMs: Int64 = 0
    var x: Float = 0
    var y: Float = 0
    var depth: Float = 0
}

struct LiveShotEvent: Hashable {
    var id: String = ""
    var playerUid: String = ""
    var playerName: String = ""
    /** Source-artwork coordinates, not screen pixels, so every device can map the same spot. */
    var shotSpotX: Float = 0
    var shotSpotY: Float = 0
    var aimError: Float = 0
    var powerError: Float = 0
    var arcError: Float = 0
    var rawPeakGyro: Float = 0
    var rawReleasePitchDeg: Float = 0
    var pullBack: Float = 0
    var hotHand: Bool = false
    var releasedAt: Int64 = 0
    /** Authoritative result is still supplied by the shooter's player-state update. */
    var made: Bool = false
    var samples: [ShotReplaySample] = []

    /** Kotlin data-class `copy(...)`: every argument left out keeps its current value. */
    func copy(
        id: String? = nil,
        playerUid: String? = nil,
        playerName: String? = nil,
        shotSpotX: Float? = nil,
        shotSpotY: Float? = nil,
        aimError: Float? = nil,
        powerError: Float? = nil,
        arcError: Float? = nil,
        rawPeakGyro: Float? = nil,
        rawReleasePitchDeg: Float? = nil,
        pullBack: Float? = nil,
        hotHand: Bool? = nil,
        releasedAt: Int64? = nil,
        made: Bool? = nil,
        samples: [ShotReplaySample]? = nil
    ) -> LiveShotEvent {
        return LiveShotEvent(
            id: id ?? self.id,
            playerUid: playerUid ?? self.playerUid,
            playerName: playerName ?? self.playerName,
            shotSpotX: shotSpotX ?? self.shotSpotX,
            shotSpotY: shotSpotY ?? self.shotSpotY,
            aimError: aimError ?? self.aimError,
            powerError: powerError ?? self.powerError,
            arcError: arcError ?? self.arcError,
            rawPeakGyro: rawPeakGyro ?? self.rawPeakGyro,
            rawReleasePitchDeg: rawReleasePitchDeg ?? self.rawReleasePitchDeg,
            pullBack: pullBack ?? self.pullBack,
            hotHand: hotHand ?? self.hotHand,
            releasedAt: releasedAt ?? self.releasedAt,
            made: made ?? self.made,
            samples: samples ?? self.samples
        )
    }
}
