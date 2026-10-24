import Foundation

// Port of questionenginelib Question.kt (questionenginelib 578ed22). Spec 04 §3.2, §4.3.
//
// Kotlin data class whose `init { require(...) }` validates the question. The initialiser throws
// QuestionsIllegalArgumentException (Kotlin's IllegalArgumentException) because AndroidQuestionBankParser.parse
// propagates it to callers that catch it (DESIGN 2.1); the generators that build questions use `try!`, a crash
// like the uncaught exception on Android. The properties are `let`: they are validated Kotlin `val`s.
//
// Strings are compared with Swift `==` / `Set`, which equal Java `equals` / `HashSet` for these values: every
// bundled bank and words.xml file is NFC (checked when porting), and two different NFC strings are never
// canonically equivalent. A clash would also make the bank parity tests fail.

struct Question {
    let id: String
    let mode: QuestionMode
    let level: Int
    let prompt: String
    let answers: [String]
    let correctAnswerIndex: Int
    let explanation: String?
    let language: String
    let imageRef: String?
    /// Kotlin `Set<String>` (LinkedHashSet from `toSet()` / `setOf`).
    let tags: KLinkedSet<String>
    let allowMultipleCorrectAnswers: Bool
    /// Kotlin `Set<Int>` (the parser's `linkedSetOf`).
    let correctAnswerIndices: KLinkedSet<Int>

    /// `correctAnswerIndices` nil is Kotlin's default `setOf(correctAnswerIndex)` (a Swift default value cannot
    /// read another parameter).
    init(
        id: String,
        mode: QuestionMode,
        level: Int,
        prompt: String,
        answers: [String],
        correctAnswerIndex: Int,
        explanation: String? = nil,
        language: String = "he",
        imageRef: String? = nil,
        tags: KLinkedSet<String> = KLinkedSet(),
        allowMultipleCorrectAnswers: Bool = false,
        correctAnswerIndices: KLinkedSet<Int>? = nil
    ) throws {
        self.id = id
        self.mode = mode
        self.level = level
        self.prompt = prompt
        self.answers = answers
        self.correctAnswerIndex = correctAnswerIndex
        self.explanation = explanation
        self.language = language
        self.imageRef = imageRef
        self.tags = tags
        self.allowMultipleCorrectAnswers = allowMultipleCorrectAnswers
        self.correctAnswerIndices = correctAnswerIndices ?? KLinkedSet([correctAnswerIndex])

        try QuestionsKotlin.require(!id.kotlinIsBlank, "Question id must not be blank")
        try QuestionsKotlin.require(level >= 1, "Question level must be >= 1")
        try QuestionsKotlin.require(!prompt.kotlinIsBlank, "Question prompt must not be blank")
        try QuestionsKotlin.require(answers.count >= 2, "Question must contain at least 2 answers")
        try QuestionsKotlin.require(!answers.contains(where: { $0.kotlinIsBlank }), "Question answers must not be blank")
        try QuestionsKotlin.require(answers.indices.contains(correctAnswerIndex), "correctAnswerIndex is outside answers")
        try QuestionsKotlin.require(answers.map { $0.ktrim() }.kDistinct().count == answers.count, "Answers must be unique")
        try QuestionsKotlin.require(!self.correctAnswerIndices.isEmpty, "Question must contain a correct answer")
        try QuestionsKotlin.require(self.correctAnswerIndices.elements.allSatisfy { answers.indices.contains($0) },
                                    "A correct answer index is outside answers")
        if allowMultipleCorrectAnswers {
            try QuestionsKotlin.require(self.correctAnswerIndices.contains(correctAnswerIndex),
                                        "correctAnswerIndex must remain one of the accepted answers")
        } else {
            // correctAnswerIndices == setOf(correctAnswerIndex)
            try QuestionsKotlin.require(self.correctAnswerIndices == KLinkedSet([correctAnswerIndex]),
                                        "Single-answer questions must contain exactly one correct answer")
        }
    }

    func isCorrect(answerIndex: Int) -> Bool {
        return correctAnswerIndices.contains(answerIndex)
    }

    var correctAnswer: String { return answers[correctAnswerIndex] }
}

/// Kotlin data-class `equals`: every property; the sets compare as sets (KLinkedSet `==` ignores order).
extension Question: Equatable {}

extension Question: CustomStringConvertible {
    /// Kotlin data-class `toString` (lists and sets print `[a, b]` in iteration order).
    var description: String {
        return "Question(id=\(id), mode=\(mode.name), level=\(level), prompt=\(prompt), "
            + "answers=[\(answers.joined(separator: ", "))], correctAnswerIndex=\(correctAnswerIndex), "
            + "explanation=\(explanation ?? "null"), language=\(language), imageRef=\(imageRef ?? "null"), "
            + "tags=[\(tags.elements.joined(separator: ", "))], allowMultipleCorrectAnswers=\(allowMultipleCorrectAnswers), "
            + "correctAnswerIndices=[\(correctAnswerIndices.elements.map { String($0) }.joined(separator: ", "))])"
    }
}
