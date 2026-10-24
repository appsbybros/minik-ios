import Foundation

// Port of questionenginelib DifficultyEngine.kt (questionenginelib 578ed22). Spec 04 §4.7.
// Kotlin Long response times are Int64; the fast threshold is Long arithmetic, the comfortable threshold and the
// mean of the timed answers are Double (Iterable<Long>.average()).

struct AnswerPerformance: Equatable, CustomStringConvertible {
    var correct: Bool
    var responseTimeMs: Int64

    init(correct: Bool, responseTimeMs: Int64 = -1) {
        self.correct = correct
        self.responseTimeMs = responseTimeMs
    }

    /// Kotlin data-class `toString`.
    var description: String { return "AnswerPerformance(correct=\(correct), responseTimeMs=\(responseTimeMs))" }
}

struct DifficultyState: Equatable, CustomStringConvertible {
    var level: Int
    var calibrationAnswers: Int
    var recentAnswers: [AnswerPerformance]

    init(level: Int, calibrationAnswers: Int = 0, recentAnswers: [AnswerPerformance] = []) {
        self.level = level
        self.calibrationAnswers = calibrationAnswers
        self.recentAnswers = recentAnswers
    }

    /// Kotlin data-class `toString`.
    var description: String {
        return "DifficultyState(level=\(level), calibrationAnswers=\(calibrationAnswers), "
            + "recentAnswers=[\(recentAnswers.map { $0.description }.joined(separator: ", "))])"
    }
}

struct DifficultyResult: Equatable, CustomStringConvertible {
    var previousLevel: Int
    var newLevel: Int
    var state: DifficultyState
    var levelChanged: Bool

    init(previousLevel: Int, newLevel: Int, state: DifficultyState, levelChanged: Bool) {
        self.previousLevel = previousLevel
        self.newLevel = newLevel
        self.state = state
        self.levelChanged = levelChanged
    }

    /// Kotlin data-class `toString`.
    var description: String {
        return "DifficultyResult(previousLevel=\(previousLevel), newLevel=\(newLevel), state=\(state), levelChanged=\(levelChanged))"
    }
}

/**
 * Starts in the middle of the available range and then calibrates automatically.
 * Response time is optional: pass -1 when a host game does not measure it.
 */
final class DifficultyEngine {
    private let calibrationLength: Int
    private let stableWindowSize: Int

    init(calibrationLength: Int = 8, stableWindowSize: Int = 5) {
        self.calibrationLength = calibrationLength
        self.stableWindowSize = stableWindowSize
    }

    func middleLevel(minLevel: Int, maxLevel: Int) -> Int {
        return ((minLevel + maxLevel) / 2).coerceIn(minLevel, maxLevel)
    }

    func recordAnswer(
        state: DifficultyState,
        correct: Bool,
        responseTimeMs: Int64 = -1,
        minLevel: Int,
        maxLevel: Int
    ) -> DifficultyResult {
        let current = state.level.coerceIn(minLevel, maxLevel)
        let perf = AnswerPerformance(correct: correct, responseTimeMs: responseTimeMs)
        if state.calibrationAnswers < calibrationLength {
            return calibration(state: state, current: current, p: perf, min: minLevel, max: maxLevel)
        }
        return stable(state: state, current: current, p: perf, min: minLevel, max: maxLevel)
    }

    private func calibration(state: DifficultyState, current: Int, p: AnswerPerformance, min: Int, max: Int) -> DifficultyResult {
        // Medium is only the starting hypothesis. Early answers move the engine quickly but not wildly.
        var next = current
        if p.correct {
            next += 1
            if p.responseTimeMs >= 0 && p.responseTimeMs <= fastThresholdMs(level: current) && state.calibrationAnswers % 3 == 2 { next += 1 }
        } else {
            next -= 1
        }
        next = next.coerceIn(min, max)
        let ns = DifficultyState(level: next, calibrationAnswers: state.calibrationAnswers + 1, recentAnswers: [])
        return DifficultyResult(previousLevel: current, newLevel: next, state: ns, levelChanged: next != current)
    }

    private func stable(state: DifficultyState, current: Int, p: AnswerPerformance, min: Int, max: Int) -> DifficultyResult {
        // (state.recentAnswers + p).takeLast(stableWindowSize)
        let recent = Array((state.recentAnswers + [p]).suffix(stableWindowSize))
        if recent.count < stableWindowSize {
            var ns = state
            ns.level = current
            ns.recentAnswers = recent
            return DifficultyResult(previousLevel: current, newLevel: current, state: ns, levelChanged: false)
        }
        let correct = recent.filter { $0.correct }.count
        let timed = recent.filter { $0.responseTimeMs >= 0 }
        let comfortable = timed.isEmpty
            || QuestionsKotlin.average(timed.map { $0.responseTimeMs }) <= comfortableThresholdMs(level: current)
        var next = current
        if correct >= 4 && comfortable {
            next += 1
        } else if correct <= 2 {
            next -= 1
        }
        next = next.coerceIn(min, max)
        let changed = next != current
        let ns = DifficultyState(level: next, calibrationAnswers: state.calibrationAnswers, recentAnswers: changed ? [] : recent)
        return DifficultyResult(previousLevel: current, newLevel: next, state: ns, levelChanged: changed)
    }

    private func fastThresholdMs(level: Int) -> Int64 { return 2800 + Int64(level - 1) * 260 }
    private func comfortableThresholdMs(level: Int) -> Double { return 6500.0 + Double(level - 1) * 450.0 }
}
