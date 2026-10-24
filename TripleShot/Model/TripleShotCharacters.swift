import Foundation

// Port of model/TripleShotCharacters.kt (TripleShotGame 6c38131). Spec 01 section 7.3.

/**
 * Basketball ability ratings shared by human-controlled characters and character bots.
 *
 * All values are 0..100 game ratings, not literal real-world measurements. `height` is a
 * gameplay height/reach rating so very different character designs can use the same model.
 */
struct BasketballRatings: Hashable {
    var inside: Int
    var midRange: Int
    var threePoint: Int
    var speed: Int
    var strength: Int
    var height: Int
    var blocking: Int
    var stealing: Int
    var ballHandling: Int
    /** Rim-finishing / dunk ability used by 1v1 drive finishes. */
    var dunking: Int
    /** Team-defense / contain IQ. Separate from the ability to steal or block. */
    var defense: Int
    /** Change-of-direction and reaction quickness. Speed is still straight-line speed. */
    var agility: Int
    /** Ability to create space, sell fakes and keep quality under pressure. */
    var offense: Int
    /** Gameplay mass for contact and box-outs. This is a 0..100 rating, not kilograms. */
    var weight: Int
    /** Vertical explosion for rebounds, blocks, layups and dunks. Separate from standing height. */
    var jumping: Int

    init(
        inside: Int,
        midRange: Int,
        threePoint: Int,
        speed: Int,
        strength: Int,
        height: Int,
        blocking: Int,
        stealing: Int,
        ballHandling: Int,
        dunking: Int = 50,
        defense: Int = 50,
        agility: Int = 50,
        offense: Int = 50,
        weight: Int = 50,
        jumping: Int = 50
    ) {
        self.inside = inside
        self.midRange = midRange
        self.threePoint = threePoint
        self.speed = speed
        self.strength = strength
        self.height = height
        self.blocking = blocking
        self.stealing = stealing
        self.ballHandling = ballHandling
        self.dunking = dunking
        self.defense = defense
        self.agility = agility
        self.offense = offense
        self.weight = weight
        self.jumping = jumping
        for value in [
            inside,
            midRange,
            threePoint,
            speed,
            strength,
            height,
            blocking,
            stealing,
            ballHandling,
            dunking,
            defense,
            agility,
            offense,
            weight,
            jumping
        ] {
            precondition(value >= 0 && value <= 100, "Character ratings must be in 0..100.")
        }
    }

    func shootingFor(zone: ShotZone) -> Int {
        switch zone {
        case .INSIDE: return inside
        case .MID_RANGE: return midRange
        case .THREE_POINT: return threePoint
        }
    }

    /// Positional form (Kotlin `shootingFor(zone)`).
    func shootingFor(_ zone: ShotZone) -> Int {
        return shootingFor(zone: zone)
    }
}

enum ShotZone: String, KotlinEnum {
    case INSIDE
    case MID_RANGE
    case THREE_POINT
}

/** Bot decision tendencies are intentionally separate from raw athletic ratings. */
struct BotTendencies: Hashable {
    var preferredZone: ShotZone?
    var attackAggression: Int
    var stealAggression: Int
    var blockAggression: Int
    var riskTaking: Int

    init(
        preferredZone: ShotZone? = nil,
        attackAggression: Int = 50,
        stealAggression: Int = 50,
        blockAggression: Int = 50,
        riskTaking: Int = 50
    ) {
        self.preferredZone = preferredZone
        self.attackAggression = attackAggression
        self.stealAggression = stealAggression
        self.blockAggression = blockAggression
        self.riskTaking = riskTaking
        for value in [
            attackAggression,
            stealAggression,
            blockAggression,
            riskTaking
        ] {
            precondition(value >= 0 && value <= 100, "Bot tendency ratings must be in 0..100.")
        }
    }
}

/**
 * Trivia behaviour for bots. These values shape knowledge and response style only; they do not
 * affect basketball ratings.
 */
struct BotQuizProfile: Hashable {
    var knowledge: Int
    var responseSpeed: Int
    var guessiness: Int

    init(
        knowledge: Int = 60,
        responseSpeed: Int = 60,
        guessiness: Int = 25
    ) {
        self.knowledge = knowledge
        self.responseSpeed = responseSpeed
        self.guessiness = guessiness
        for value in [knowledge, responseSpeed, guessiness] {
            precondition(value >= 0 && value <= 100, "Bot quiz ratings must be in 0..100.")
        }
    }
}

enum CharacterGender: String, KotlinEnum {
    case FEMALE
    case MALE
    case NEUTRAL
}

enum BotArchetype: String, KotlinEnum {
    case ADAPTIVE_TRAINER
    case BALANCED
    case SHARPSHOOTER
    case SLASHER
    case DEFENDER
    case BIG
}

/**
 * Character identity and gameplay data. Artwork lives in the view-layer visual catalog so
 * model classes stay independent from Android drawable resources.
 */
struct TripleShotCharacterProfile: Hashable {
    var id: String
    var displayName: String
    var gender: CharacterGender = .NEUTRAL
    var ratings: BasketballRatings
    var archetype: BotArchetype
    var tendencies: BotTendencies = BotTendencies()
    var quiz: BotQuizProfile = BotQuizProfile()
    /** BOB keeps adapting to the human instead of using one fixed shooting rating. */
    var adaptiveBot: Bool = false
    /** Intended availability once a complete FRONT/BACK/SIDE sprite pack exists. */
    var selectableByHuman: Bool = false
    var selectableAsBot: Bool = false

    /** Kotlin data-class `copy(...)`: every argument left out keeps its current value. */
    func copy(
        id: String? = nil,
        displayName: String? = nil,
        gender: CharacterGender? = nil,
        ratings: BasketballRatings? = nil,
        archetype: BotArchetype? = nil,
        tendencies: BotTendencies? = nil,
        quiz: BotQuizProfile? = nil,
        adaptiveBot: Bool? = nil,
        selectableByHuman: Bool? = nil,
        selectableAsBot: Bool? = nil
    ) -> TripleShotCharacterProfile {
        return TripleShotCharacterProfile(
            id: id ?? self.id,
            displayName: displayName ?? self.displayName,
            gender: gender ?? self.gender,
            ratings: ratings ?? self.ratings,
            archetype: archetype ?? self.archetype,
            tendencies: tendencies ?? self.tendencies,
            quiz: quiz ?? self.quiz,
            adaptiveBot: adaptiveBot ?? self.adaptiveBot,
            selectableByHuman: selectableByHuman ?? self.selectableByHuman,
            selectableAsBot: selectableAsBot ?? self.selectableAsBot
        )
    }
}

/**
 * Roster metadata.
 *
 * The six extra profiles are already real gameplay characters from the data-model point of view.
 * Their current source sheets are also exposed in the visual catalog as picker portraits. They
 * become selectable on court automatically once a complete body-only FRONT/BACK/SIDE pack is
 * registered for them, so no gameplay branch is needed later.
 */
enum TripleShotCharacterRoster {

    static let ID_BOB = "bob"
    /** Source compatibility for V18 call-sites. New code should use [ID_BOB]. */
    static let ID_MINIK = ID_BOB
    private static let LEGACY_ID_MINIK = "minik"

    static let ID_WOMAN_DARK = "woman_dark"
    static let ID_ROOZA = "rooza"
    static let ID_NOVA = "nova"
    static let ID_UNICORN_32 = "unicorn_32"
    static let ID_COACH_67 = "coach_67"
    static let ID_KYRA = "kyra"
    static let ID_ZEPHYR = "zephyr"
    static let ID_FLARE = "flare"
    static let ID_ACE_23 = "ace_23"
    static let ID_BUDDY_23 = "buddy_23"

    static let bob = TripleShotCharacterProfile(
        id: ID_BOB,
        displayName: "BOB",
        gender: .MALE,
        ratings: BasketballRatings(
            inside: 60,
            midRange: 60,
            threePoint: 60,
            speed: 68,
            strength: 55,
            height: 55,
            blocking: 52,
            stealing: 58,
            ballHandling: 64,
            dunking: 45,
            defense: 58,
            agility: 66,
            offense: 60,
            weight: 55,
            jumping: 62
        ),
        archetype: .ADAPTIVE_TRAINER,
        tendencies: BotTendencies(
            preferredZone: nil,
            attackAggression: 50,
            stealAggression: 45,
            blockAggression: 48,
            riskTaking: 45
        ),
        quiz: BotQuizProfile(
            knowledge: 68,
            responseSpeed: 58,
            guessiness: 18
        ),
        adaptiveBot: true,
        selectableByHuman: false,
        selectableAsBot: true
    )

    /** Kept only so older source that still references `roster.minik` continues to compile. */
    static var minik: TripleShotCharacterProfile {
        return bob
    }

    static let womanDark = TripleShotCharacterProfile(
        id: ID_WOMAN_DARK,
        displayName: "Maya",
        gender: .FEMALE,
        ratings: BasketballRatings(
            inside: 78,
            midRange: 83,
            threePoint: 86,
            speed: 84,
            strength: 62,
            height: 70,
            blocking: 48,
            stealing: 74,
            ballHandling: 88,
            dunking: 72,
            defense: 66,
            agility: 87,
            offense: 88,
            weight: 60,
            jumping: 78
        ),
        archetype: .SHARPSHOOTER,
        tendencies: BotTendencies(
            preferredZone: .THREE_POINT,
            attackAggression: 62,
            stealAggression: 68,
            blockAggression: 38,
            riskTaking: 58
        ),
        quiz: BotQuizProfile(
            knowledge: 74,
            responseSpeed: 63,
            guessiness: 14
        ),
        selectableByHuman: true,
        selectableAsBot: true
    )

    static let rooza = TripleShotCharacterProfile(
        id: ID_ROOZA,
        displayName: "Rooza",
        gender: .FEMALE,
        ratings: BasketballRatings(
            inside: 76,
            midRange: 82,
            threePoint: 79,
            speed: 95,
            strength: 58,
            height: 60,
            blocking: 43,
            stealing: 88,
            ballHandling: 94,
            dunking: 78,
            defense: 68,
            agility: 97,
            offense: 91,
            weight: 52,
            jumping: 96
        ),
        archetype: .SLASHER,
        tendencies: BotTendencies(
            preferredZone: .MID_RANGE,
            attackAggression: 88,
            stealAggression: 84,
            blockAggression: 35,
            riskTaking: 78
        ),
        quiz: BotQuizProfile(
            knowledge: 52,
            responseSpeed: 94,
            guessiness: 58
        ),
        selectableByHuman: true,
        selectableAsBot: true
    )

    static let nova = TripleShotCharacterProfile(
        id: ID_NOVA,
        // Keep the stable internal id "nova" for saved configs/Firebase compatibility.
        // The actual roster character using that slot is Mia Essence Skies.
        displayName: "Mia Essence Skies",
        gender: .FEMALE,
        ratings: BasketballRatings(
            inside: 86,
            midRange: 88,
            threePoint: 84,
            speed: 91,
            strength: 82,
            height: 88,
            blocking: 79,
            stealing: 82,
            ballHandling: 88,
            dunking: 88,
            defense: 86,
            agility: 91,
            offense: 89,
            weight: 82,
            jumping: 92
        ),
        archetype: .BALANCED,
        tendencies: BotTendencies(
            preferredZone: .MID_RANGE,
            attackAggression: 74,
            stealAggression: 74,
            blockAggression: 72,
            riskTaking: 66
        ),
        quiz: BotQuizProfile(
            knowledge: 91,
            responseSpeed: 88,
            guessiness: 6
        ),
        selectableByHuman: true,
        selectableAsBot: true
    )

    static let unicorn32 = TripleShotCharacterProfile(
        id: ID_UNICORN_32,
        displayName: "Sonic",
        gender: .MALE,
        ratings: BasketballRatings(
            inside: 92,
            midRange: 72,
            threePoint: 58,
            speed: 62,
            strength: 94,
            height: 89,
            blocking: 92,
            stealing: 45,
            ballHandling: 58,
            dunking: 86,
            defense: 91,
            agility: 57,
            offense: 74,
            weight: 96,
            jumping: 78
        ),
        archetype: .BIG,
        tendencies: BotTendencies(
            preferredZone: .INSIDE,
            attackAggression: 84,
            stealAggression: 32,
            blockAggression: 96,
            riskTaking: 48
        ),
        quiz: BotQuizProfile(
            knowledge: 84,
            responseSpeed: 34,
            guessiness: 8
        ),
        selectableByHuman: true,
        selectableAsBot: true
    )

    static let coach67 = TripleShotCharacterProfile(
        id: ID_COACH_67,
        displayName: "Coach 67",
        gender: .MALE,
        ratings: BasketballRatings(
            inside: 90,
            midRange: 75,
            threePoint: 64,
            speed: 55,
            strength: 97,
            height: 85,
            blocking: 86,
            stealing: 52,
            ballHandling: 64,
            dunking: 80,
            defense: 93,
            agility: 50,
            offense: 72,
            weight: 98,
            jumping: 72
        ),
        archetype: .BIG,
        tendencies: BotTendencies(
            preferredZone: .INSIDE,
            attackAggression: 79,
            stealAggression: 38,
            blockAggression: 88,
            riskTaking: 42
        ),
        quiz: BotQuizProfile(
            knowledge: 78,
            responseSpeed: 47,
            guessiness: 10
        ),
        selectableByHuman: true,
        selectableAsBot: true
    )


    /**
     * ZEPHYR is the MALE winged character that was accidentally shipped under KYRA's id/name in
     * the first production pack. Keep his current gameplay ratings, but give him his own identity
     * so the real female KYRA can be rebuilt cleanly without mixing faces/body art again.
     */
    static let zephyr = TripleShotCharacterProfile(
        id: ID_ZEPHYR,
        displayName: "Comet",
        gender: .MALE,
        ratings: BasketballRatings(
            inside: 84,
            midRange: 81,
            threePoint: 78,
            speed: 89,
            strength: 76,
            height: 75,
            blocking: 76,
            stealing: 86,
            ballHandling: 85,
            dunking: 91,
            defense: 85,
            agility: 90,
            offense: 84,
            weight: 72,
            jumping: 96
        ),
        archetype: .SLASHER,
        tendencies: BotTendencies(
            preferredZone: .INSIDE,
            attackAggression: 82,
            stealAggression: 82,
            blockAggression: 69,
            riskTaking: 68
        ),
        quiz: BotQuizProfile(
            knowledge: 70,
            responseSpeed: 86,
            guessiness: 18
        ),
        selectableByHuman: true,
        selectableAsBot: true
    )

    /**
     * Real KYRA is the female rainbow-wing athlete from the newly supplied reference sheets.
     * She stays visible in roster metadata but is deliberately NOT selectable until the corrected
     * folded-wing runtime sheets are generated and cut. This prevents another male/female asset mix.
     * (Stale Kotlin comment, kept verbatim: both selectable flags are true and her art resolves; spec 01 8.5.)
     */
    static let kyra = TripleShotCharacterProfile(
        id: ID_KYRA,
        displayName: "Gaya",
        gender: .FEMALE,
        ratings: BasketballRatings(
            inside: 84,
            midRange: 81,
            threePoint: 78,
            speed: 89,
            strength: 76,
            height: 75,
            blocking: 76,
            stealing: 86,
            ballHandling: 85,
            dunking: 91,
            defense: 85,
            agility: 90,
            offense: 84,
            weight: 72,
            jumping: 96
        ),
        archetype: .SLASHER,
        tendencies: BotTendencies(
            preferredZone: .INSIDE,
            attackAggression: 82,
            stealAggression: 82,
            blockAggression: 69,
            riskTaking: 68
        ),
        quiz: BotQuizProfile(knowledge: 70, responseSpeed: 86, guessiness: 18),
        selectableByHuman: true,
        selectableAsBot: true
    )

    /**
     * FLARE is the neon graffiti power-wing generated from the production five-sheet set.
     * These ratings are intentionally provisional until playtesting gives us real balance data.
     */
    static let flare = TripleShotCharacterProfile(
        id: ID_FLARE,
        displayName: "FLARE",
        gender: .MALE,
        ratings: BasketballRatings(
            inside: 88,
            midRange: 82,
            threePoint: 80,
            speed: 87,
            strength: 91,
            height: 82,
            blocking: 74,
            stealing: 75,
            ballHandling: 86,
            dunking: 94,
            defense: 79,
            agility: 84,
            offense: 90,
            weight: 88,
            jumping: 93
        ),
        archetype: .SLASHER,
        tendencies: BotTendencies(
            preferredZone: .INSIDE,
            attackAggression: 88,
            stealAggression: 66,
            blockAggression: 64,
            riskTaking: 72
        ),
        quiz: BotQuizProfile(
            knowledge: 64,
            responseSpeed: 82,
            guessiness: 25
        ),
        selectableByHuman: true,
        selectableAsBot: true
    )

    static let ace23 = TripleShotCharacterProfile(
        id: ID_ACE_23,
        displayName: "Ace 23",
        gender: .MALE,
        ratings: BasketballRatings(
            inside: 82,
            midRange: 86,
            threePoint: 88,
            speed: 90,
            strength: 66,
            height: 72,
            blocking: 50,
            stealing: 82,
            ballHandling: 92,
            dunking: 82,
            defense: 65,
            agility: 93,
            offense: 93,
            weight: 64,
            jumping: 90
        ),
        archetype: .SHARPSHOOTER,
        tendencies: BotTendencies(
            preferredZone: .THREE_POINT,
            attackAggression: 72,
            stealAggression: 78,
            blockAggression: 42,
            riskTaking: 70
        ),
        quiz: BotQuizProfile(
            knowledge: 36,
            responseSpeed: 97,
            guessiness: 86
        ),
        selectableByHuman: true,
        selectableAsBot: true
    )

    static let buddy23 = TripleShotCharacterProfile(
        id: ID_BUDDY_23,
        displayName: "Buddy 23",
        gender: .MALE,
        ratings: BasketballRatings(
            inside: 76,
            midRange: 79,
            threePoint: 74,
            speed: 96,
            strength: 48,
            height: 38,
            blocking: 35,
            stealing: 92,
            ballHandling: 94,
            dunking: 60,
            defense: 62,
            agility: 99,
            offense: 89,
            weight: 38,
            jumping: 98
        ),
        archetype: .SLASHER,
        tendencies: BotTendencies(
            preferredZone: .INSIDE,
            attackAggression: 91,
            stealAggression: 93,
            blockAggression: 25,
            riskTaking: 82
        ),
        quiz: BotQuizProfile(
            knowledge: 24,
            responseSpeed: 72,
            guessiness: 96
        ),
        selectableByHuman: true,
        selectableAsBot: true
    )

    // Keep legacy IDs for saved squads; the original Kyra gets a separate stable identity.

    static let originalKyra = kyra.copy(id: "kyra_original", displayName: "Kyra")

    static let all: [TripleShotCharacterProfile] =
        [
            bob,
            womanDark,
            rooza,
            nova,
            unicorn32,
            coach67,
            zephyr,
            kyra,
            originalKyra,
            flare,
            ace23,
            buddy23
        ]

    private static func normalizeId(id: String?) -> String? {
        if id == LEGACY_ID_MINIK {
            return ID_BOB
        } else {
            return id
        }
    }

    static func find(id: String?) -> TripleShotCharacterProfile? {
        guard let normalized = normalizeId(id: id) else { return nil }
        return all.first { $0.id == normalized }
    }

    static func requireProfile(id: String?) -> TripleShotCharacterProfile {
        return find(id: id) ?? womanDark
    }

    /// Positional forms (Kotlin `find(id)` / `requireProfile(id)`).
    static func find(_ id: String?) -> TripleShotCharacterProfile? {
        return find(id: id)
    }

    static func requireProfile(_ id: String?) -> TripleShotCharacterProfile {
        return requireProfile(id: id)
    }

    static func humanSelectable() -> [TripleShotCharacterProfile] {
        return all.filter { $0.selectableByHuman }
    }

    static func botSelectable() -> [TripleShotCharacterProfile] {
        return all.filter { $0.selectableAsBot }
    }
}
