import Foundation

// Port of game/TripleShotBotOpponent.kt (Android snapshot dd722e5), statement by statement.
// Every decision draws from one KotlinRandom (bit-exact XorWow) in the Kotlin order; all release
// maths stays in Float like the JVM.

/**
 * Local turn-based brain for the visible Shooting Challenge bot.
 *
 * Unlike the previous timer-only bot, this class never invents a basket result. It decides only
 * the bot's knowledge answer and imperfect release inputs. TripleShotCourtView then launches a
 * real ball through TripleShotPhysics, and [recordShot] receives the physical made/missed result.
 */
final class TripleShotBotOpponent {

    struct AnswerPlan: Hashable {
        var selectedAnswerIndex: Int
        var answerQualityPercent: Int
    }

    struct TurnPlan: Hashable {
        var selectedAnswerIndex: Int
        var answerQualityPercent: Int
        var skill: ShotSkill
        var pullBack: Float
    }

    private let displayName: String
    private let characterProfile: TripleShotCharacterProfile
    private let onStateChanged: (LivePlayerState) -> Void

    private let random: KotlinRandom
    private let scoring = TripleShotScoringEngine()

    /*
     * BOB is an adaptive training opponent, not a fixed percentage bot. It watches a short
     * window of the human's real physical makes/misses and changes only its release precision.
     * The physics engine still owns the actual basket result.
     */
    private var recentHumanShots: [Bool] = []
    private var adaptiveShootingAccuracy: Float = TripleShotBotOpponent.ADAPTIVE_PRIOR_ACCURACY

    private var running = false
    private var lastEvent = ""

    init(
        displayName: String,
        seed: Int64,
        characterProfile: TripleShotCharacterProfile = TripleShotCharacterRoster.bob,
        onStateChanged: @escaping (LivePlayerState) -> Void
    ) {
        self.displayName = displayName
        self.characterProfile = characterProfile
        self.onStateChanged = onStateChanged
        self.random = KotlinRandom(seed: seed ^ TripleShotBotOpponent.BOT_SEED_SALT)
    }

    func start() {
        if running { return }
        running = true
        lastEvent = "\u{2026}"
        publish()
    }

    func stop() {
        running = false
    }

    func snapshot() -> LivePlayerState { return buildState() }

    /**
     * Feeds BOB one real human shooting result. A six-shot prior plus a twelve-shot rolling
     * window prevents the bot from copying the previous make/miss immediately.
     * (No Android caller: BOB's level stays at the prior in production.)
     */
    func observeHumanShot(made: Bool) {
        if !characterProfile.adaptiveBot { return }

        if recentHumanShots.count >= TripleShotBotOpponent.HUMAN_SHOT_WINDOW {
            recentHumanShots.removeFirst()
        }
        recentHumanShots.append(made)

        let makes = recentHumanShots.filter { $0 }.count
        let smoothedAccuracy =
            (makes.toFloat() + TripleShotBotOpponent.ADAPTIVE_PRIOR_ACCURACY * TripleShotBotOpponent.ADAPTIVE_PRIOR_SHOTS) /
            (recentHumanShots.count.toFloat() + TripleShotBotOpponent.ADAPTIVE_PRIOR_SHOTS)

        adaptiveShootingAccuracy =
            smoothedAccuracy.coerceIn(TripleShotBotOpponent.ADAPTIVE_MIN_ACCURACY, TripleShotBotOpponent.ADAPTIVE_MAX_ACCURACY)
    }

    /**
     * Produces imperfect release input, never a made/missed outcome. A struggling player causes
     * larger aim/power variation; a strong player gradually faces a much cleaner BOB release.
     */
    func chooseAnswer(question: TripleShotQuestion) -> AnswerPlan {
        if question.answers.isEmpty {
            return AnswerPlan(selectedAnswerIndex: 0, answerQualityPercent: 0)
        }

        let bestQuality = question.answers.map { $0.qualityPercent }.max()!
        let bestIndices =
            question.answers.indices.filter { question.answers[$0].qualityPercent == bestQuality }
        let wrongIndices =
            question.answers.indices.filter { !bestIndices.contains($0) }

        let shouldChooseBest = random.nextFloat() < knowledgeAccuracy(category: question.category)
        let chosenIndex: Int
        if shouldChooseBest || wrongIndices.isEmpty {
            chosenIndex = bestIndices.kRandom(random)
        } else {
            chosenIndex = wrongIndices.kRandom(random)
        }

        return AnswerPlan(
            selectedAnswerIndex: chosenIndex,
            answerQualityPercent: question.answers[chosenIndex].qualityPercent
        )
    }

    /// `answerPlan == nil` is the Kotlin default argument `chooseAnswer(question)`, evaluated first
    /// (before any release draw), exactly like Kotlin evaluates default arguments at the call.
    func prepareTurn(
        question: TripleShotQuestion,
        shotZone: ShotZone = .MID_RANGE,
        answerPlan: AnswerPlan? = nil
    ) -> TurnPlan {
        let answerPlan = answerPlan ?? chooseAnswer(question: question)
        /*
         * BOB keeps the approved adaptive behavior. Character bots use their fixed zone rating,
         * but still create only imperfect release inputs; TripleShotPhysics decides the result.
         */
        let shootingLevel: Float
        if characterProfile.adaptiveBot {
            shootingLevel =
                ((adaptiveShootingAccuracy - TripleShotBotOpponent.ADAPTIVE_MIN_ACCURACY) /
                    (TripleShotBotOpponent.ADAPTIVE_MAX_ACCURACY - TripleShotBotOpponent.ADAPTIVE_MIN_ACCURACY))
                .coerceIn(0, 1)
        } else {
            shootingLevel =
                (characterProfile.ratings.shootingFor(zone: shotZone).toFloat() / 100)
                .coerceIn(0, 1)
        }

        let sloppyChance = lerp(0.36, 0.10, shootingLevel)
        let sloppyRelease = random.nextFloat() < sloppyChance

        let aimAmplitude: Float =
            sloppyRelease ?
            lerp(0.72, 0.32, shootingLevel) :
            lerp(0.34, 0.14, shootingLevel)

        let powerAmplitude: Float =
            sloppyRelease ?
            lerp(0.50, 0.24, shootingLevel) :
            lerp(0.23, 0.10, shootingLevel)

        let arcAmplitude: Float =
            sloppyRelease ?
            lerp(0.30, 0.14, shootingLevel) :
            lerp(0.13, 0.055, shootingLevel)

        let pullSpread = lerp(0.16, 0.07, shootingLevel)

        // Argument order = Kotlin evaluation order: aim, power, arc noise, then the pull-back noise.
        let skill = ShotSkill(
            aimError: centeredNoise(aimAmplitude),
            powerError: centeredNoise(powerAmplitude),
            arcError: centeredNoise(arcAmplitude),
            rawPeakGyro: 0,
            rawReleasePitchDeg: 0
        )
        let pullBack: Float = (0.70 + centeredNoise(pullSpread)).coerceIn(0.48, 0.92)
        return TurnPlan(
            selectedAnswerIndex: answerPlan.selectedAnswerIndex,
            answerQualityPercent: answerPlan.answerQualityPercent,
            skill: skill,
            pullBack: pullBack
        )
    }

    /** Records the real CourtView result and scores it with the same engine as the human. */
    func recordShot(
        turn: TurnPlan,
        made: Bool
    ) {
        if !running { return }

        _ = scoring.score(
            answerQualityPercent: turn.answerQualityPercent,
            made: made
        )

        if turn.answerQualityPercent == 100 && made {
            lastEvent = "\u{2705}  \u{1F3C0}"
        } else if turn.answerQualityPercent == 100 {
            lastEvent = "\u{2705}  \u{2716}\u{1F3C0}"
        } else if made {
            lastEvent = "\u{274C}  \u{1F3C0}"
        } else {
            lastEvent = "\u{274C}  \u{2716}\u{1F3C0}"
        }

        publish()
    }

    private func publish() {
        onStateChanged(buildState())
    }

    private func buildState() -> LivePlayerState {
        return LivePlayerState(
            uid: TripleShotBotOpponent.BOT_UID,
            name: displayName,
            score: scoring.totalScore,
            knowledgeStreak: scoring.knowledgeStreak,
            shootingStreak: scoring.shootingStreak,
            bestKnowledgeStreak: scoring.bestKnowledgeStreak,
            bestShootingStreak: scoring.bestShootingStreak,
            correctAnswers: scoring.correctAnswers,
            madeShots: scoring.madeShots,
            shots: scoring.shots,
            lastEvent: lastEvent,
            updatedAt: ASystem.currentTimeMillis()
        )
    }

    /// `(nextFloat() + nextFloat() - 1f) * amplitude`; the two draws happen left to right.
    private func centeredNoise(_ amplitude: Float) -> Float {
        let first = random.nextFloat()
        let second = random.nextFloat()
        return (first + second - 1) * amplitude
    }

    private func lerp(_ a: Float, _ b: Float, _ t: Float) -> Float {
        return a + (b - a) * t.coerceIn(0, 1)
    }

    private func knowledgeAccuracy(category: QuestionCategory) -> Float {
        switch category {
        case .KIDS_ARITHMETIC: return 0.82
        case .ENGLISH: return 0.76
        case .GENERAL_KNOWLEDGE: return 0.66
        case .SCIENCE: return 0.68
        case .ASTRONOMY: return 0.65
        case .AI: return 0.67
        case .HISTORY: return 0.64
        case .MATH: return 0.64
        case .PROGRAMMING: return 0.62
        case .MATRICULATION_MATH: return 0.58
        case .PARADOX: return 0.56
        }
    }

    private static let BOT_UID = "LOCAL_BOT"
    private static let BOT_SEED_SALT: Int64 = 0x4D494E494B535749

    private static let HUMAN_SHOT_WINDOW = 12
    private static let ADAPTIVE_PRIOR_SHOTS: Float = 6
    private static let ADAPTIVE_PRIOR_ACCURACY: Float = 0.55
    private static let ADAPTIVE_MIN_ACCURACY: Float = 0.30
    private static let ADAPTIVE_MAX_ACCURACY: Float = 0.88
}

// MARK: - Positional (Kotlin call-site) forms

extension TripleShotBotOpponent {
    convenience init(
        _ displayName: String,
        _ seed: Int64,
        _ characterProfile: TripleShotCharacterProfile = TripleShotCharacterRoster.bob,
        _ onStateChanged: @escaping (LivePlayerState) -> Void
    ) {
        self.init(displayName: displayName, seed: seed, characterProfile: characterProfile, onStateChanged: onStateChanged)
    }

    func observeHumanShot(_ made: Bool) { observeHumanShot(made: made) }

    func chooseAnswer(_ question: TripleShotQuestion) -> AnswerPlan { return chooseAnswer(question: question) }

    func prepareTurn(_ question: TripleShotQuestion, _ shotZone: ShotZone = .MID_RANGE, _ answerPlan: AnswerPlan? = nil) -> TurnPlan {
        return prepareTurn(question: question, shotZone: shotZone, answerPlan: answerPlan)
    }

    func recordShot(_ turn: TurnPlan, _ made: Bool) { recordShot(turn: turn, made: made) }
}

extension TripleShotBotOpponent.AnswerPlan {
    init(_ selectedAnswerIndex: Int, _ answerQualityPercent: Int) {
        self.init(selectedAnswerIndex: selectedAnswerIndex, answerQualityPercent: answerQualityPercent)
    }
}

extension TripleShotBotOpponent.TurnPlan {
    init(_ selectedAnswerIndex: Int, _ answerQualityPercent: Int, _ skill: ShotSkill, _ pullBack: Float) {
        self.init(selectedAnswerIndex: selectedAnswerIndex, answerQualityPercent: answerQualityPercent, skill: skill, pullBack: pullBack)
    }
}
