import Foundation

// Port of questionenginelib LocalizedEnglishQuestionGenerator.kt (questionenginelib 578ed22). Spec 04 §4.6.
// "How do you say ... in English?" questions from words.xml (Hebrew devices). Random draws, in order:
// `available.random(random)` (one nextInt), then the LAZY `available.asSequence().shuffled(random)` (one
// nextInt(buffer.size) per pulled element, stopping right after the third distinct distractor: `take(3)` checks
// its count before pulling), then `(distractors + answer).shuffled(random)` (nextInt(4), nextInt(3), nextInt(2)).

final class LocalizedEnglishQuestionGenerator: QuestionGenerator {
    private let words: [WordEntry]
    private let random: KotlinRandom
    let mode = QuestionMode.ENGLISH
    let minLevel = 1
    let maxLevel = 5
    private let sourceLanguageCode: String
    private let targetLanguageCode: String

    init(words: [WordEntry], sourceLanguageCode: String = "he", targetLanguageCode: String = "en",
         random: KotlinRandom = KotlinRandom.Default) {
        self.words = words
        self.random = random
        self.sourceLanguageCode = QuestionLocaleContract.normalize(languageCode: sourceLanguageCode)
        self.targetLanguageCode = QuestionLocaleContract.normalize(languageCode: targetLanguageCode)

        precondition(self.sourceLanguageCode != self.targetLanguageCode,
                     "English learning needs a non-English source language")
        let usable = words.filter {
            $0.value(languageCode: self.sourceLanguageCode) != nil && $0.value(languageCode: self.targetLanguageCode) != nil
        }
        precondition(usable.count >= 4
                        && usable.compactMap { $0.value(languageCode: self.targetLanguageCode) }.kDistinct().count >= 4,
                     "English learning needs four usable source-to-target entries with distinct answers")
    }

    func generate(level: Int) -> Question {
        let safe = level.coerceIn(1, 5)
        var available = words.filter {
            $0.level == safe && $0.value(languageCode: sourceLanguageCode) != nil && $0.value(languageCode: targetLanguageCode) != nil
        }
        if available.isEmpty {  // .ifEmpty { ... }
            available = words.filter {
                $0.value(languageCode: sourceLanguageCode) != nil && $0.value(languageCode: targetLanguageCode) != nil
            }
        }
        precondition(available.count >= 4, "words.xml needs at least four translatable entries")
        let correct = available.kRandom(random)
        let answer = correct.value(languageCode: targetLanguageCode)!
        // available.asSequence().shuffled(random).mapNotNull { it.value(targetLanguageCode) }
        //     .filter { it != answer }.distinct().take(3).toList()
        var distractors: [String] = []
        var observed = Set<String>()
        var shuffled = QuestionsLazyShuffledSequence(available, random)
        while distractors.count < 3, let entry = shuffled.next() {
            guard let value = entry.value(languageCode: targetLanguageCode) else { continue }
            if value != answer && observed.insert(value).inserted { distractors.append(value) }
        }
        precondition(distractors.count == 3, "words.xml needs four distinct target-language values")
        let options = (distractors + [answer]).kShuffled(random)
        return try! Question(
            id: "words_\(correct.id)",
            mode: mode,
            level: safe,
            prompt: promptFor(language: sourceLanguageCode, source: correct.value(languageCode: sourceLanguageCode)!),
            answers: options,
            correctAnswerIndex: options.firstIndex(of: answer) ?? -1,
            language: sourceLanguageCode,
            tags: KLinkedSet([correct.group, "words_xml"])
        )
    }

    private func promptFor(language: String, source: String) -> String {
        switch language {
        case "he": return "איך אומרים באנגלית: \(source)?"
        case "ar": return "كيف نقول بالإنجليزية: \(source)؟"
        case "es": return "¿Cómo se dice en inglés: \(source)?"
        case "hi": return "इसे अंग्रेज़ी में कैसे कहते हैं: \(source)?"
        default: return "Choose the English meaning of: \(source)"
        }
    }
}

/// Kotlin `Sequence<T>.shuffled(random)` (kotlin-stdlib 2.3.21 Sequences.kt): `buffer = toMutableList()`; each
/// pulled element costs exactly one `random.nextInt(buffer.size)`, then `last = buffer.removeLast()` and
/// `if (j < buffer.size) buffer.set(j, last) /* yields the old buffer[j] */ else last`. Nothing is drawn for
/// elements that are never pulled.
private struct QuestionsLazyShuffledSequence<Element>: IteratorProtocol {
    private var buffer: [Element]
    private let random: KotlinRandom

    init(_ elements: [Element], _ random: KotlinRandom) {
        self.buffer = elements
        self.random = random
    }

    mutating func next() -> Element? {
        if buffer.isEmpty { return nil }
        let j = random.nextInt(buffer.count)
        let last = buffer.removeLast()
        if j < buffer.count {
            let value = buffer[j]
            buffer[j] = last
            return value
        }
        return last
    }
}
