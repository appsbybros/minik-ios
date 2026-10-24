import Foundation

// Port of game/TripleShotScoringEngine.kt (Android snapshot dd722e5), statement by statement.

final class TripleShotScoringEngine {
    private(set) var totalScore: Int = 0
    private(set) var knowledgeStreak: Int = 0
    private(set) var shootingStreak: Int = 0
    private(set) var bestKnowledgeStreak: Int = 0
    private(set) var bestShootingStreak: Int = 0
    private(set) var correctAnswers: Int = 0
    private(set) var madeShots: Int = 0
    private(set) var shots: Int = 0

    init() {}

    @discardableResult
    func score(answerQualityPercent: Int, made: Bool) -> ScoreDelta {
        let normalizedQuality = answerQualityPercent.coerceIn(0, 100)
        let fullyCorrect = normalizedQuality == 100

        if fullyCorrect {
            knowledgeStreak += 1
            correctAnswers += 1
        } else {
            knowledgeStreak = 0
        }

        if made {
            shootingStreak += 1
            madeShots += 1
        } else {
            shootingStreak = 0
        }
        shots += 1

        bestKnowledgeStreak = max(bestKnowledgeStreak, knowledgeStreak)
        bestShootingStreak = max(bestShootingStreak, shootingStreak)

        // Knowledge is intentionally worth much more than shooting.
        // Streak 1 => x2, 2 => x3, 3 => x4, 4+ => x5 (hard cap).
        let multiplier = fullyCorrect ? (knowledgeStreak + 1).coerceAtMost(5) : 1
        let fullKnowledgePoints = fullyCorrect ? 3 * multiplier : 0
        let partialKnowledgePoints: Int
        if !fullyCorrect && normalizedQuality > 0 {
            // Kotlin `((3f * normalizedQuality) / 100f).toInt().coerceAtLeast(1)`: Float * Int is a Float operation.
            let scaled: Float = (Float(3) * normalizedQuality.toFloat()) / Float(100)
            partialKnowledgePoints = scaled.toInt().coerceAtLeast(1)
        } else {
            partialKnowledgePoints = 0
        }
        let knowledgePoints = fullKnowledgePoints + partialKnowledgePoints

        // A basket is always worth something, but never more than the knowledge reward.
        let basketPoints: Int
        if !made {
            basketPoints = 0
        } else if fullyCorrect {
            basketPoints = 3
        } else {
            basketPoints = 2
        }

        let total = knowledgePoints + basketPoints
        totalScore += total

        return ScoreDelta(
            answerQualityPercent: normalizedQuality,
            answerCorrect: fullyCorrect,
            knowledgeMultiplier: multiplier,
            knowledgePoints: knowledgePoints,
            basketPoints: basketPoints,
            totalPoints: total,
            knowledgeStreak: knowledgeStreak,
            shootingStreak: shootingStreak,
            bestKnowledgeStreak: bestKnowledgeStreak,
            bestShootingStreak: bestShootingStreak
        )
    }

    /// Kotlin positional call form `scoring.score(quality, made)`.
    @discardableResult
    func score(_ answerQualityPercent: Int, _ made: Bool) -> ScoreDelta {
        return score(answerQualityPercent: answerQualityPercent, made: made)
    }
}
