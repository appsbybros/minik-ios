import Foundation

// Port of questionenginelib QuestionMix.kt (questionenginelib 578ed22). Spec 04 §3.2.
// Part of the QuestionEngine API (its optional `initialMix`); Triple Shot never sets a mix, so it stays nil.
// `weights` is iterated (weighted choice), hence the insertion-ordered KLinkedMap.

/** Weighted choice of subjects for local (on-device) question generation. Ported from the
 * original client library; MATH is now [QuestionMode.ARITHMETIC]. */
struct QuestionMix {
    let weights: KLinkedMap<QuestionMode, Int>

    init(weights: KLinkedMap<QuestionMode, Int>) {
        self.weights = weights
        precondition(!weights.isEmpty, "QuestionMix must contain at least one mode")
        for (mode, weight) in weights {
            precondition(weight >= 0, "Weight for \(mode.name) cannot be negative")
        }
        precondition(QuestionsKotlin.sumOfInts(weights.values) > 0, "QuestionMix must contain at least one positive weight")
    }

    var totalWeight: Int { return QuestionsKotlin.sumOfInts(weights.values) }

    /// `weights.filterValues { it > 0 }.keys` (insertion order).
    var enabledModes: KLinkedSet<QuestionMode> {
        return KLinkedSet(weights.entries.filter { $0.value > 0 }.map { $0.key })
    }

    func weightOf(mode: QuestionMode) -> Int { return weights[mode] ?? 0 }

    static func single(mode: QuestionMode) -> QuestionMix {
        return QuestionMix(weights: KLinkedMap([(mode, 100)]))
    }

    static func arithmeticOnly() -> QuestionMix { return single(mode: QuestionMode.ARITHMETIC) }

    @available(*, deprecated, renamed: "arithmeticOnly()", message: "MATH is now ARITHMETIC")
    static func mathOnly() -> QuestionMix { return arithmeticOnly() }
}
