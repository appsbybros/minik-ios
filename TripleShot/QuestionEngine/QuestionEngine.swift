import Foundation

// Port of questionenginelib QuestionEngine.kt (questionenginelib 578ed22). Spec 04 §3.2, §4.6.
// Triple Shot uses the constructor (generators, random), registeredModes, restoreDifficultyState,
// nextQuestion(mode:), recordAnswer and getDifficultyState; the mix paths are ported as well and stay unused.
// generatorsByMode (associateBy) and states (mutableMapOf) are LinkedHashMaps: KLinkedMap keeps that order.

final class QuestionEngine {
    private let random: KotlinRandom
    private let difficultyEngine: DifficultyEngine
    private var generatorsByMode = KLinkedMap<QuestionMode, QuestionGenerator>()
    private var states = KLinkedMap<QuestionMode, DifficultyState>()

    /** Weighted subject choice for [nextQuestion] without a mode; null means all registered modes equally. */
    private(set) var mix: QuestionMix?

    init(
        generators: [QuestionGenerator],
        random: KotlinRandom = KotlinRandom.Default,
        difficultyEngine: DifficultyEngine = DifficultyEngine(),
        initialMix: QuestionMix? = nil
    ) {
        self.random = random
        self.difficultyEngine = difficultyEngine
        // generators.associateBy { it.mode }: the last generator of a mode wins, the mode keeps its first position.
        for g in generators { generatorsByMode[g.mode] = g }
        mix = initialMix

        precondition(generatorsByMode.count == generators.count, "Only one generator per mode is allowed")
        for g in generators {
            states[g.mode] = DifficultyState(level: difficultyEngine.middleLevel(minLevel: g.minLevel, maxLevel: g.maxLevel))
        }
        if let initialMix = initialMix { validateMix(questionMix: initialMix) }
    }

    func registeredModes() -> KLinkedSet<QuestionMode> { return KLinkedSet(generatorsByMode.keys) }

    func setQuestionMix(newMix: QuestionMix) {
        validateMix(questionMix: newMix)
        mix = newMix
    }

    /** Chooses the subject from [mix] and generates at that subject's current adaptive level. */
    func nextQuestion() -> Question { return nextQuestion(mode: chooseMode()) }

    /** Mix-selected subject at an explicit level (tests/previews); adaptive state is unchanged. */
    func nextQuestion(levels: [QuestionMode: Int]) -> Question {
        let mode = chooseMode()
        let g = generatorsByMode[mode]!  // getValue
        return nextQuestion(mode: mode, explicitLevel: levels[mode] ?? difficultyEngine.middleLevel(minLevel: g.minLevel, maxLevel: g.maxLevel))
    }

    private func chooseMode() -> QuestionMode {
        // mix?.weights?.filterValues { it > 0 } ?: generatorsByMode.keys.associateWith { 1 }
        var weights = KLinkedMap<QuestionMode, Int>()
        if let mix = mix {
            for (mode, weight) in mix.weights where weight > 0 { weights[mode] = weight }
        } else {
            for mode in generatorsByMode.keys { weights[mode] = 1 }
        }
        precondition(!weights.isEmpty, "No question modes are registered")
        var ticket = random.nextInt(QuestionsKotlin.sumOfInts(weights.values))
        for (mode, weight) in weights {
            if ticket < weight { return mode }
            ticket -= weight
        }
        preconditionFailure("Could not select a question mode")
    }

    private func validateMix(questionMix: QuestionMix) {
        for mode in questionMix.enabledModes {
            precondition(generatorsByMode.containsKey(mode), "QuestionMix contains \(mode.name) but no generator is registered for it")
        }
    }

    /** Every subject starts at its medium level, then adjusts independently. */
    func nextQuestion(mode: QuestionMode) -> Question {
        guard let g = generatorsByMode[mode] else { preconditionFailure("No generator registered for \(mode.name)") }
        let level = (states[mode]?.level ?? difficultyEngine.middleLevel(minLevel: g.minLevel, maxLevel: g.maxLevel))
            .coerceIn(g.minLevel, g.maxLevel)
        return g.generate(level: level)
    }

    func nextQuestion(mode: QuestionMode, explicitLevel: Int) -> Question {
        guard let g = generatorsByMode[mode] else { preconditionFailure("No generator registered for \(mode.name)") }
        return g.generate(level: explicitLevel.coerceIn(g.minLevel, g.maxLevel))
    }

    @discardableResult
    func recordAnswer(question: Question, answerIndex: Int, responseTimeMs: Int64 = -1) -> DifficultyResult {
        guard let g = generatorsByMode[question.mode] else {
            preconditionFailure("No generator registered for \(question.mode.name)")
        }
        let current = states[question.mode]
            ?? DifficultyState(level: difficultyEngine.middleLevel(minLevel: g.minLevel, maxLevel: g.maxLevel))
        let result = difficultyEngine.recordAnswer(state: current, correct: question.isCorrect(answerIndex: answerIndex),
                                                   responseTimeMs: responseTimeMs, minLevel: g.minLevel, maxLevel: g.maxLevel)
        states[question.mode] = result.state
        return result
    }

    func getDifficultyState(mode: QuestionMode) -> DifficultyState? { return states[mode] }

    /// `states.toMap()`: a copy in insertion order.
    func getAllDifficultyStates() -> KLinkedMap<QuestionMode, DifficultyState> { return states }

    func restoreDifficultyState(mode: QuestionMode, state: DifficultyState) {
        guard let g = generatorsByMode[mode] else { preconditionFailure("No generator registered for \(mode.name)") }
        var restored = state
        restored.level = state.level.coerceIn(g.minLevel, g.maxLevel)
        states[mode] = restored
    }
}
