import Foundation

// Port of questionenginelib XmlQuestionGenerator.kt (questionenginelib 578ed22). Spec 04 §4.6.
// The pool keeps the XML document order; the pick is Kotlin `candidates.random(random)` (one
// `nextInt(candidates.size)`); `recentIds` is the java.util.ArrayDeque anti-repeat window.

final class XmlQuestionGenerator: QuestionGenerator {
    let mode: QuestionMode
    private let random: KotlinRandom
    private let recentMemory: Int
    private let pool: [Question]
    let minLevel: Int
    let maxLevel: Int
    /// java.util.ArrayDeque<String> (at most recentMemory + 1 entries).
    private var recentIds: [String] = []

    init(mode: QuestionMode, questions: [Question], random: KotlinRandom = KotlinRandom.Default, recentMemory: Int = 12) {
        self.mode = mode
        self.random = random
        self.recentMemory = recentMemory
        let pool = questions.filter { $0.mode == mode }
        self.pool = pool
        minLevel = pool.map { $0.level }.min() ?? 1
        maxLevel = pool.map { $0.level }.max() ?? 1
        precondition(!pool.isEmpty, "No questions supplied for \(mode.name)")
    }

    func generate(level: Int) -> Question {
        let safe = level.coerceIn(minLevel, maxLevel)
        var candidates = pool.filter { $0.level == safe && !recentIds.contains($0.id) }
        if candidates.isEmpty { candidates = pool.filter { $0.level == safe } }
        if candidates.isEmpty {
            let nearest = pool.map { abs($0.level - safe) }.min()!
            candidates = pool.filter { abs($0.level - safe) == nearest && !recentIds.contains($0.id) }
            if candidates.isEmpty { candidates = pool.filter { abs($0.level - safe) == nearest } }
        }
        let q = candidates.kRandom(random)
        // ArrayDeque.remove(Object) removes the first occurrence.
        if let index = recentIds.firstIndex(of: q.id) { recentIds.remove(at: index) }
        recentIds.append(q.id)
        while recentIds.count > recentMemory { recentIds.removeFirst() }
        return q
    }
}
