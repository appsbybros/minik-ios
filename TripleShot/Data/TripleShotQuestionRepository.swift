import Foundation

// Port of data/TripleShotQuestionRepository.kt (TripleShotGame dd722e5). Spec 04 §4.1-4.10.
//
// - Main thread only (Kotlin `@Synchronized` on `shuffled`; every caller is UI code).
// - Two KotlinRandom(seed) instances per session, as on Android: one for the category order, one shared by
//   every generator of the session.
// - `shuffled` returns an AdaptiveQuestionList: Kotlin's anonymous lazy AbstractList of 4096 entries. An entry is
//   generated the first time its index is read, at the difficulty level of that moment.
// - Android re-parses every bank on every `shuffled` call. Parsing is deterministic and draws nothing from the
//   random generators, so the parsed (immutable) banks are cached per asset path and language; the generators,
//   the random generators and the restored difficulty states are rebuilt for every session exactly as on Android
//   (spec 04 §8.15), so the generated sequence is unchanged.
// - Preferences "triple_shot_question_difficulty_v2" (AndroidKit ASharedPreferences): "<MODE>_level",
//   "<MODE>_cal" and "adaptive_intro_shown".
// - The language follows `ConfigurationCompat.getLocales(context.resources.configuration)[0]`; AndroidKit gives
//   every context the app window's configuration (first iOS preferred language, DESIGN 2.7).

/**
 * Thin compatibility adapter: TripleShot keeps its existing TripleShotQuestion API while all
 * content/difficulty now comes from questionenginelib + XML assets.
 */
enum TripleShotQuestionRepository {
    private static let PREFS = "triple_shot_question_difficulty_v2"
    private static let ADAPTIVE_LIST_SIZE = 4096
    private static let INTRO_SHOWN_KEY = "adaptive_intro_shown"
    nonisolated(unsafe) private static var appContext: AContext? = nil
    nonisolated(unsafe) private static var questionLanguage = "en"

    private struct Session {
        let engine: QuestionEngine
    }

    private struct Origin {
        let question: Question
        let session: Session
    }

    nonisolated(unsafe) private static var originByQuestionId: [String: Origin] = [:]
    nonisolated(unsafe) private static var lastSession: Session? = nil

    /// iOS only (spec 04 §8.15): parsed banks by "<preferredLanguage>|<asset path>", parsed words.xml by path.
    nonisolated(unsafe) private static var parsedBanks: [String: [Question]] = [:]
    nonisolated(unsafe) private static var parsedWords: [String: [WordEntry]] = [:]

    static func initialize(context: AContext) {
        let app = context.applicationContext
        appContext = app
        questionLanguage = ["he", "iw"].contains((AConfigurationCompat.getLocales(context.resources.configuration)[0] ?? ALocale.getDefault()).language) ? "he" : "en"
        let prefs = app.getSharedPreferences(PREFS, MODE_PRIVATE)
        if !prefs.getBoolean(INTRO_SHOWN_KEY, false) {
            let he = ["he", "iw"].contains((AConfigurationCompat.getLocales(app.resources.configuration)[0] ?? ALocale.getDefault()).language)
            let message: String
            if he {
                message = "מתחילים ברמה בינונית. הרמה תותאם אוטומטית לפי התשובות שלך."
            } else {
                message = "You start at a medium level. Difficulty will adjust automatically from your answers."
            }
            AToast.makeText(message, AToast.LENGTH_LONG).show()
            prefs.edit().putBoolean(INTRO_SHOWN_KEY, true).apply()
        }
    }

    /**
     * Backward-compatible List API with adaptive internals.
     * Existing game code can keep using questions[index]. A question is generated only the first
     * time that index is requested, so after recordAnswer() the *next* index immediately uses the
     * newly adjusted level instead of waiting for the next match.
     */
    static func shuffled(seed: Int64, categories: KLinkedSet<QuestionCategory>) -> AdaptiveQuestionList {
        guard let context = appContext else {
            preconditionFailure("TripleShotQuestionRepository.initialize(context) must be called first")
        }
        let session = Session(engine: buildEngine(context: context, seed: seed))
        lastSession = session
        let active = (categories.isEmpty ? QuestionCategory.allCases : categories.elements)
            .filter { modeFor(category: $0) != nil }
            .kShuffled(KotlinRandom(seed: seed))
        precondition(!active.isEmpty, "No supported question categories selected")

        return AdaptiveQuestionList(size: ADAPTIVE_LIST_SIZE) { index in
            let category = active[index % active.count]
            let mode = modeFor(category: category)!
            let q = session.engine.nextQuestion(mode: mode)
            originByQuestionId[q.id] = Origin(question: q, session: session)
            return q.toTripleShot(category: category)
        }
    }

    /** Call once when the human commits an answer. The next generated question reflects the change. */
    static func recordAnswer(questionId: String, selectedAnswerIndex: Int, responseTimeMs: Int64 = -1) {
        guard let origin = originByQuestionId[questionId] else { return }
        let result = origin.session.engine.recordAnswer(question: origin.question, answerIndex: selectedAnswerIndex,
                                                        responseTimeMs: responseTimeMs)
        persist(mode: origin.question.mode, s: result.state)
    }

    static func currentLevel(category: QuestionCategory) -> Int? {
        guard let mode = modeFor(category: category) else { return nil }
        return lastSession?.engine.getDifficultyState(mode: mode)?.level ?? load(mode: mode)?.level
    }

    // Unlabelled forms of the calls above (Kotlin positional arguments).
    static func initialize(_ context: AContext) { initialize(context: context) }
    static func shuffled(_ seed: Int64, _ categories: KLinkedSet<QuestionCategory>) -> AdaptiveQuestionList {
        return shuffled(seed: seed, categories: categories)
    }
    static func recordAnswer(_ questionId: String, _ selectedAnswerIndex: Int, _ responseTimeMs: Int64 = -1) {
        recordAnswer(questionId: questionId, selectedAnswerIndex: selectedAnswerIndex, responseTimeMs: responseTimeMs)
    }
    static func currentLevel(_ category: QuestionCategory) -> Int? { return currentLevel(category: category) }

    /// `context.assets.open(...)` is AResources.openAsset on iOS (the app's Res/assets folder); the context only
    /// keeps the Kotlin shape.
    private static func buildEngine(context: AContext, seed: Int64) -> QuestionEngine {
        let language = questionLanguage
        let bankFolder = language == "en" ? "question_banks/en" : "question_banks"
        let specs: [(QuestionMode, String)] = [
            (QuestionMode.ARITHMETIC, "arithmetic.xml"),
            (QuestionMode.GENERAL_KNOWLEDGE, "general_knowledge.xml"),
            (QuestionMode.SCIENCE, "science.xml"),
            (QuestionMode.ASTRONOMY, "astronomy.xml"),
            (QuestionMode.ARTIFICIAL_INTELLIGENCE, "artificial_intelligence.xml"),
            (QuestionMode.HISTORY, "history.xml"),
            (QuestionMode.MATHEMATICS, "mathematics.xml"),
            (QuestionMode.PROGRAMMING, "programming.xml"),
            (QuestionMode.BAGRUT_MATHEMATICS, "bagrut_mathematics.xml"),
            (QuestionMode.PARADOXES, "paradoxes.xml")
        ]
        let random = KotlinRandom(seed: seed)
        var generators: [QuestionGenerator] = specs.map { spec -> QuestionGenerator in
            let (mode, file) = spec
            let questions = parsedBank(path: "\(bankFolder)/\(file)", preferredLanguage: language)
            precondition(questions.allSatisfy { $0.mode == mode }, "Bank \(file) contains another mode")
            return XmlQuestionGenerator(mode: mode, questions: questions, random: random)
        }
        let words = parsedWordList(path: "question_banks/words.xml")
        if language == "he" {
            generators.append(LocalizedEnglishQuestionGenerator(words: words, sourceLanguageCode: "he", targetLanguageCode: "en",
                                                                random: random))
        } else {
            generators.append(XmlQuestionGenerator(mode: QuestionMode.ENGLISH,
                                                   questions: parsedBank(path: "question_banks/en/english.xml", preferredLanguage: "en"),
                                                   random: random))
        }
        let e = QuestionEngine(generators: generators, random: random)
        // No saved evidence -> library's true middle level. Saved evidence -> continue from there.
        for mode in e.registeredModes() {
            if let saved = load(mode: mode) { e.restoreDifficultyState(mode: mode, state: saved) }
        }
        return e
    }

    /// `assets.open(path).use { AndroidQuestionBankParser.parse(it, preferredLanguage = ...) }`, parsed once.
    /// A missing or invalid bank crashes, as the uncaught exception does on Android.
    private static func parsedBank(path: String, preferredLanguage: String) -> [Question] {
        let key = "\(preferredLanguage)|\(path)"
        if let cached = parsedBanks[key] { return cached }
        let questions = try! AndroidQuestionBankParser.parse(input: try! AResources.openAsset(path),
                                                             preferredLanguage: preferredLanguage)
        parsedBanks[key] = questions
        return questions
    }

    /// `assets.open(path).use(WordsXmlParser::parse)`, parsed once.
    private static func parsedWordList(path: String) -> [WordEntry] {
        if let cached = parsedWords[path] { return cached }
        let words = WordsXmlParser.parse(input: try! AResources.openAsset(path))
        parsedWords[path] = words
        return words
    }

    private static func modeFor(category: QuestionCategory) -> QuestionMode? {
        switch category.name {
        case "KIDS_ARITHMETIC", "ARITHMETIC": return QuestionMode.ARITHMETIC
        case "ENGLISH": return QuestionMode.ENGLISH
        case "GENERAL_KNOWLEDGE": return QuestionMode.GENERAL_KNOWLEDGE
        case "SCIENCE": return QuestionMode.SCIENCE
        case "ASTRONOMY": return QuestionMode.ASTRONOMY
        case "AI", "ARTIFICIAL_INTELLIGENCE": return QuestionMode.ARTIFICIAL_INTELLIGENCE
        case "HISTORY": return QuestionMode.HISTORY
        case "MATH", "MATHEMATICS": return QuestionMode.MATHEMATICS
        case "PROGRAMMING": return QuestionMode.PROGRAMMING
        case "BAGRUT_MATH", "BAGRUT_MATHEMATICS", "MATRICULATION_MATH": return QuestionMode.BAGRUT_MATHEMATICS
        case "PARADOXES", "PARADOX": return QuestionMode.PARADOXES
        default: return nil
        }
    }

    private static func persist(mode: QuestionMode, s: DifficultyState) {
        guard let p = appContext?.getSharedPreferences(PREFS, MODE_PRIVATE) else { return }
        p.edit()
            .putInt("\(mode.name)_level", s.level)
            .putInt("\(mode.name)_cal", s.calibrationAnswers)
            .apply()
    }

    private static func load(mode: QuestionMode) -> DifficultyState? {
        guard let p = appContext?.getSharedPreferences(PREFS, MODE_PRIVATE) else { return nil }
        let key = "\(mode.name)_level"
        if !p.contains(key) { return nil }
        return DifficultyState(
            level: p.getInt(key, 1),
            calibrationAnswers: p.getInt("\(mode.name)_cal", 0)
        )
    }
}

private extension Question {
    func toTripleShot(category: QuestionCategory) -> TripleShotQuestion {
        return TripleShotQuestion(
            id: id,
            category: category,
            prompt: prompt,
            answers: answers.enumerated().map { AnswerOption(text: $0.element, qualityPercent: $0.offset == correctAnswerIndex ? 100 : 0) },
            explanation: explanation ?? ""
        )
    }
}

/// The Kotlin `List<TripleShotQuestion>` of `TripleShotQuestionRepository.shuffled`: an anonymous lazy
/// `AbstractList` with `size` 4096 and a private `HashMap<Int, TripleShotQuestion>` cache. `get(index)` requires
/// `0 <= index < size`, then generates the entry on its first read (`cache.getOrPut(index) { ... }`).
/// `AdaptiveQuestionList()` / `.emptyList()` stand for Kotlin's `emptyList()` on screens without questions.
///
/// Deliberately NOT a Swift Sequence or Collection: `Array(list)`, `map`, `for in`, `reversed()` or `contains`
/// would generate all 4096 entries and consume random draws. Only the List members the callers use exist, under
/// their Kotlin names (`size`, `get`, `getOrNull`, `firstOrNull`, `first()`, `isNotEmpty()`, `indices`) and their
/// Swift Array names (`count`, `subscript`, `isEmpty`, `first(where:)`).
final class AdaptiveQuestionList {
    /// Kotlin `size`.
    let size: Int
    private let generator: ((Int) -> TripleShotQuestion)?
    private var cache: [Int: TripleShotQuestion] = [:]

    /// Kotlin `emptyList()`.
    init() {
        size = 0
        generator = nil
    }

    fileprivate init(size: Int, generator: @escaping (Int) -> TripleShotQuestion) {
        self.size = size
        self.generator = generator
    }

    /// Kotlin `emptyList<TripleShotQuestion>()`.
    static func emptyList() -> AdaptiveQuestionList { return AdaptiveQuestionList() }

    /// Swift name of `size`.
    var count: Int { return size }
    /// Kotlin `isEmpty()`.
    var isEmpty: Bool { return size == 0 }
    /// Kotlin `isNotEmpty()`.
    func isNotEmpty() -> Bool { return size != 0 }
    /// Kotlin `indices` (0 until size).
    var indices: Range<Int> { return 0..<size }

    /// Kotlin `get(index)`; an index outside 0 until size crashes as on Android ("Failed requirement.").
    func get(_ index: Int) -> TripleShotQuestion {
        precondition(index >= 0 && index < size, "Failed requirement.")
        if let cached = cache[index] { return cached }
        let q = generator!(index)
        cache[index] = q
        return q
    }

    /// Kotlin `list[index]`.
    subscript(index: Int) -> TripleShotQuestion { return get(index) }

    /// Kotlin `getOrNull(index)`.
    func getOrNull(_ index: Int) -> TripleShotQuestion? {
        return index >= 0 && index < size ? get(index) : nil
    }

    /// Kotlin `firstOrNull { predicate }`: reads index 0, 1, ... in order and stops at the first match.
    func firstOrNull(_ predicate: (TripleShotQuestion) -> Bool) -> TripleShotQuestion? {
        var index = 0
        while index < size {
            let element = get(index)
            if predicate(element) { return element }
            index += 1
        }
        return nil
    }

    /// Swift name of `firstOrNull { predicate }`.
    func first(where predicate: (TripleShotQuestion) -> Bool) -> TripleShotQuestion? { return firstOrNull(predicate) }

    /// Kotlin `firstOrNull()`.
    func firstOrNull() -> TripleShotQuestion? { return size == 0 ? nil : get(0) }

    /// Kotlin `first()`: NoSuchElementException("List is empty.") on an empty list.
    func first() -> TripleShotQuestion {
        precondition(size != 0, "List is empty.")
        return get(0)
    }
}
