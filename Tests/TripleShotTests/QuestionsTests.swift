import CryptoKit
import XCTest
@testable import MinikTripleShot

/// Question layer parity (spec 04): the Android unit tests AndroidQuestionBankParserTest and QuestionLocalizationTest,
/// the question part of the instrumented RefinementTest, and golden vectors from the unmodified Kotlin sources
/// (SNAP/work/t-questions/harness/Golden.kt: spec 04 Appendix A sections A-H, plus parser cases, generator and
/// engine draws, bank hashes and repository semantics). As in the harness, "fresh" means empty preferences followed
/// by `initialize` with a context in that language, and the categories are passed in ordinal order.
final class QuestionsTests: XCTestCase {
    private static let PREFS = "triple_shot_question_difficulty_v2"

    private var savedConfiguration: AConfiguration!
    private var savedPrefs: [String: Any] = [:]

    override func setUp() {
        super.setUp()
        savedConfiguration = AConfiguration.current
        savedPrefs = Self.storedPrefs()
    }

    override func tearDown() {
        AConfiguration.current = savedConfiguration
        let defaults = UserDefaults.standard
        for key in Self.storedPrefs().keys { defaults.removeObject(forKey: key) }
        for (key, value) in savedPrefs { defaults.set(value, forKey: key) }
        super.tearDown()
    }

    // MARK: - AndroidQuestionBankParserTest

    func testAllPackagedBanksRetainEveryQuestionAndAnswer() throws {
        let banks = Self.bankFiles("question_banks")
        XCTAssertEqual(10, banks.count)
        for name in banks {
            let expected = try ValidatedXmlQuestionBankParser.parse(input: AResources.openAsset("question_banks/\(name)"),
                                                                    preferredLanguage: "he")
            let actual = try AndroidQuestionBankParser.parse(input: AResources.openAsset("question_banks/\(name)"),
                                                             preferredLanguage: "he")
            XCTAssertTrue(!actual.isEmpty, name)
            XCTAssertEqual(expected, actual, name)
        }
    }

    func testRejectsDoctypeBeforeCreatingAnAndroidDomParser() {
        let xml = "<!DOCTYPE x [<!ENTITY e SYSTEM 'file:///invalid'>]><x/>"
        XCTAssertThrowsError(try AndroidQuestionBankParser.parse(input: Data(xml.utf8))) { error in
            XCTAssertEqual(Self.message(error), "DOCTYPE is not allowed in question banks")
        }
    }

    // MARK: - QuestionLocalizationTest

    func testEnglishBanksRetainIdsLevelsAndCorrectPositions() throws {
        for name in Self.bankFiles("question_banks") {
            let he = try Self.parseBank("question_banks/\(name)", "he")
            let en = try Self.parseBank("question_banks/en/\(name)", "en")
            XCTAssertEqual(he.count, en.count, name)
            for (a, b) in zip(he, en) {
                XCTAssertEqual(a.id, b.id)
                XCTAssertEqual(a.level, b.level)
                XCTAssertEqual(a.correctAnswerIndex, b.correctAnswerIndex)
                XCTAssertEqual(4, b.answers.kDistinct().count)
                // b.prompt + b.answers.joinToString() + b.explanation
                XCTAssertFalse(Self.containsHebrew(b.prompt + b.answers.joined(separator: ", ") + (b.explanation ?? "null")),
                               b.prompt)
            }
        }
    }

    func testEnglishVocabularyBankIsValid() throws {
        let q = try Self.parseBank("question_banks/en/english.xml", "en")
        XCTAssertEqual(20, q.count)
        XCTAssertEqual(5, q.map { $0.level }.kDistinct().count)
    }

    // MARK: - Data guard: Swift String equality is Java equals for the bundled text

    /// Swift compares Strings by canonical equivalence, Java by UTF-16 units. The two agree on NFC text (two
    /// different NFC strings are never canonically equivalent), and every `==`, Set, `distinct` and dictionary key of
    /// this layer (question and word ids, answers, distractors, locale keys) works on text read from these 22 files,
    /// so they must stay NFC for the port to keep Android's comparisons.
    func testBundledQuestionTextIsNfc() throws {
        var paths = Self.bankFiles("question_banks").map { "question_banks/\($0)" }
        paths += Self.bankFiles("question_banks/en").map { "question_banks/en/\($0)" }
        paths.append("question_banks/words.xml")
        XCTAssertEqual(22, paths.count)
        for path in paths {
            let text = String(decoding: try AResources.openAsset(path), as: UTF8.self)
            let nfc = text.precomposedStringWithCanonicalMapping
            XCTAssertTrue(text.unicodeScalars.elementsEqual(nfc.unicodeScalars), path)
        }
    }

    // MARK: - RefinementTest.questionRepositoryWorksInBothLanguagesAndEveryCategory (+ golden R)

    func testQuestionRepositoryWorksInBothLanguagesAndEveryCategory() {
        var lines: [String] = []
        for lang in ["he", "en"] {
            for category in QuestionCategory.allCases {
                fresh(lang)
                let q = TripleShotQuestionRepository.shuffled(seed: 123, categories: [category])
                for i in 0..<10 {
                    XCTAssertEqual(4, q[i].answers.count)
                    XCTAssertTrue(!q[i].prompt.kotlinIsBlank)
                    if lang == "en" { XCTAssertFalse(Self.containsHebrew(q[i].prompt), q[i].prompt) }
                }
                let firstTen = (0..<10).map { "\(q[$0].id)#\(correctIndex(q[$0]))" }.joined(separator: " ")
                lines.append(["R", "lang=\(lang)", category.name, firstTen, "\(q.size)"].joined(separator: "|"))
            }
        }
        assertGolden(["R"], lines)
    }

    // MARK: - Golden A: kotlin.random.Random(seed)

    func testGoldenA_KotlinRandom() {
        var lines: [String] = []
        for seed: Int64 in [0, 1, 42, 123, -1, 1760000000000] {
            let r1 = KotlinRandom(seed: seed)
            let ints = (0..<3).map { _ in String(r1.nextInt()) }
            let r2 = KotlinRandom(seed: seed)
            let bounded = [4, 3, 2, 439, 184].map { String(r2.nextInt($0)) }
            let r3 = KotlinRandom(seed: seed)
            _ = r3.nextInt()
            _ = r3.nextInt()
            _ = r3.nextInt()
            let continued = [4, 3, 2, 439, 184].map { String(r3.nextInt($0)) }
            lines.append(["A", "seed=\(seed)", "nextInt()x3=" + ints.joined(separator: ","),
                          "fresh nextInt(4,3,2,439,184)=" + bounded.joined(separator: ","),
                          "continued=" + continued.joined(separator: ",")].joined(separator: "|"))
        }
        assertGolden(["A"], lines)
    }

    // MARK: - Golden B: category order of an all-categories game

    func testGoldenB_CategoryOrder() {
        var lines: [String] = []
        for seed: Int64 in [0, 1, 42, 123, -1, 1760000000000] {
            fresh("he")
            let list = TripleShotQuestionRepository.shuffled(seed: seed, categories: KLinkedSet())
            lines.append(["B", "seed=\(seed)", (0..<11).map { list[$0].category.name }.joined(separator: ",")].joined(separator: "|"))
        }
        assertGolden(["B"], lines)
    }

    // MARK: - Golden C: seed 123, all categories, Hebrew and English devices

    func testGoldenC_AllCategoriesBothLanguages() {
        var lines: [String] = []
        for lang in ["he", "en"] {
            fresh(lang)
            let list = TripleShotQuestionRepository.shuffled(seed: 123, categories: KLinkedSet())
            for i in 0..<22 {
                let q = list[i]
                lines.append(["C", lang, "\(i)", q.category.name, q.id, "L" + level(q.id), "c=\(correctIndex(q))"].joined(separator: "|"))
            }
        }
        assertGolden(["C"], lines)
    }

    // MARK: - Golden D: Hebrew device, ENGLISH from words.xml

    func testGoldenD_HebrewWordsQuestions() {
        fresh("he")
        let list = TripleShotQuestionRepository.shuffled(seed: 123, categories: [QuestionCategory.ENGLISH])
        var lines: [String] = []
        for i in 0..<20 {
            let q = list[i]
            lines.append(["D", "\(i)", q.id, "L" + level(q.id), q.prompt, q.answers.map { $0.text }.joined(separator: "|"),
                          "c=\(correctIndex(q))", "expl='\(q.explanation)'"].joined(separator: "|"))
        }
        assertGolden(["D"], lines)
    }

    // MARK: - Golden E: Hebrew KIDS_ARITHMETIC, untimed, 10 right then 6 wrong, then a new session

    func testGoldenE_UntimedCalibrationAndStablePhase() {
        fresh("he")
        let list = TripleShotQuestionRepository.shuffled(seed: 42, categories: [QuestionCategory.KIDS_ARITHMETIC])
        var lines: [String] = []
        for i in 0..<16 {
            let q = list[i]
            let right = i < 10
            let c = correctIndex(q)
            let answer = right ? c : (c + 1) % q.answers.count
            TripleShotQuestionRepository.recordAnswer(questionId: q.id, selectedAnswerIndex: answer)
            lines.append(["E", "\(i)", q.id, "askedL" + level(q.id), right ? "right" : "wrong", "prefs:" + prefsDump()].joined(separator: "|"))
        }
        let again = TripleShotQuestionRepository.shuffled(seed: 42, categories: [QuestionCategory.KIDS_ARITHMETIC])
        let first = again[0]
        let currentLevel = TripleShotQuestionRepository.currentLevel(category: QuestionCategory.KIDS_ARITHMETIC)
        lines.append(["E", "new-session", "first=\(first.id)", "askedL" + level(first.id),
                      "currentLevel=" + (currentLevel.map { String($0) } ?? "null")].joined(separator: "|"))
        assertGolden(["E"], lines)
    }

    // MARK: - Golden F: English MATH, timed answers

    func testGoldenF_TimedAnswers() {
        fresh("en")
        let list = TripleShotQuestionRepository.shuffled(seed: 7, categories: [QuestionCategory.MATH])
        let plan: [(Bool, Int64)] = Array(repeating: (true, 1000), count: 8) + Array(repeating: (true, 9000), count: 5)
            + Array(repeating: (true, 1000), count: 5) + Array(repeating: (false, 1000), count: 5)
        var lines: [String] = []
        for (i, step) in plan.enumerated() {
            let (right, ms) = step
            let q = list[i]
            let c = correctIndex(q)
            let answer = right ? c : (c + 1) % q.answers.count
            TripleShotQuestionRepository.recordAnswer(questionId: q.id, selectedAnswerIndex: answer, responseTimeMs: ms)
            lines.append(["F", "\(i)", q.id, "askedL" + level(q.id), "\(right ? "right" : "wrong")@\(ms)", "prefs:" + prefsDump()]
                .joined(separator: "|"))
        }
        assertGolden(["F"], lines)
    }

    // MARK: - Golden H: HORSE (TripleShotGameFragment.nextHorseQuestion verbatim)

    func testGoldenH_HorseQuestions() {
        var lines: [String] = []
        fresh("he")
        let h1 = Horse(configSeed: 1760000000000)
        for call in 1...9 {
            let q = h1.nextHorseQuestion(category: QuestionCategory.AI)
            lines.append(["H", "AI-no-answers", "\(call)", "\(h1.lastSeed)", q.id, "L" + level(q.id), "prefs:" + prefsDump()]
                .joined(separator: "|"))
        }
        fresh("he")
        let h2 = Horse(configSeed: 1760000000000)
        for call in 1...9 {
            let q = h2.nextHorseQuestion(category: QuestionCategory.MATH)
            TripleShotQuestionRepository.recordAnswer(questionId: q.id, selectedAnswerIndex: correctIndex(q))
            lines.append(["H", "MATH-answered-right", "\(call)", "\(h2.lastSeed)", q.id, "L" + level(q.id), "prefs:" + prefsDump()]
                .joined(separator: "|"))
        }
        assertGolden(["H"], lines)
    }

    /// TripleShotGameFragment.nextHorseQuestion (:2138-2161) with HORSE_RECENT_QUESTION_MEMORY = 8.
    private final class Horse {
        let configSeed: Int64
        var horseQuestionCounter = 0
        var horseRecentQuestionIds: [String] = []
        var lastSeed: Int64 = 0

        init(configSeed: Int64) {
            self.configSeed = configSeed
        }

        func nextHorseQuestion(category: QuestionCategory) -> TripleShotQuestion {
            horseQuestionCounter += 1
            let seed = configSeed ^ (Int64(horseQuestionCounter) &* 0x9E37_79B9) ^ Int64(category.ordinal)
            lastSeed = seed
            let pool = TripleShotQuestionRepository.shuffled(seed: seed, categories: [category])
            let chosen = pool.firstOrNull { !horseRecentQuestionIds.contains($0.id) } ?? pool.first()
            if let index = horseRecentQuestionIds.firstIndex(of: chosen.id) { horseRecentQuestionIds.remove(at: index) }
            horseRecentQuestionIds.append(chosen.id)
            while horseRecentQuestionIds.count > 8 {
                horseRecentQuestionIds.remove(at: 0)
            }
            return chosen
        }
    }

    // MARK: - Golden G: DifficultyEngine

    func testGoldenG_DifficultyEngine() {
        let e = DifficultyEngine()
        var s = DifficultyState(level: 9)
        let steps: [(Bool, Int64)] = [
            (true, 2000), (true, 2000), (true, 2000), (false, -1), (true, 9000), (true, 3000), (true, -1), (false, -1),
            (true, -1), (true, -1), (true, -1), (true, -1), (false, -1), (true, -1), (true, 20000), (true, 20000),
            (true, 20000), (true, 20000), (false, -1), (false, -1), (false, -1), (true, -1), (true, -1)
        ]
        var lines: [String] = []
        for (i, step) in steps.enumerated() {
            let r = e.recordAnswer(state: s, correct: step.0, responseTimeMs: step.1, minLevel: 1, maxLevel: 18)
            s = r.state
            lines.append(["G", "\(i)", "\(step.0)", "\(step.1)", "L\(r.newLevel)", "cal=\(s.calibrationAnswers)",
                          "recent=" + s.recentAnswers.map { $0.correct ? "1" : "0" }.joined(),
                          "prev=\(r.previousLevel)", "changed=\(r.levelChanged)"].joined(separator: "|"))
        }
        assertGolden(["G"], lines)

        var extra: [String] = []
        let middles = [e.middleLevel(minLevel: 1, maxLevel: 18), e.middleLevel(minLevel: 1, maxLevel: 4),
                       e.middleLevel(minLevel: 1, maxLevel: 3), e.middleLevel(minLevel: 1, maxLevel: 5),
                       e.middleLevel(minLevel: 2, maxLevel: 2), e.middleLevel(minLevel: 4, maxLevel: 7)]
        extra.append((["G2", "middle"] + middles.map { String($0) }).joined(separator: "|"))
        let r1 = e.recordAnswer(state: DifficultyState(level: 40, calibrationAnswers: 0), correct: true, responseTimeMs: 100,
                                minLevel: 1, maxLevel: 5)
        extra.append(["G2", "clampHigh", "\(r1.previousLevel)", "\(r1.newLevel)", "\(r1.state)", "\(r1.levelChanged)"].joined(separator: "|"))
        let window = [AnswerPerformance(correct: false), AnswerPerformance(correct: false), AnswerPerformance(correct: false),
                      AnswerPerformance(correct: true)]
        let r2 = e.recordAnswer(state: DifficultyState(level: -3, calibrationAnswers: 8, recentAnswers: window), correct: false,
                                responseTimeMs: -1, minLevel: 1, maxLevel: 5)
        extra.append(["G2", "clampLowStable", "\(r2.previousLevel)", "\(r2.newLevel)", "\(r2.state)", "\(r2.levelChanged)"].joined(separator: "|"))
        // Fast bonus boundary at level 5: 2800 + 4 * 260 = 3840.
        for ms: Int64 in [3840, 3841, 0, -1] {
            let r = e.recordAnswer(state: DifficultyState(level: 5, calibrationAnswers: 2), correct: true, responseTimeMs: ms,
                                   minLevel: 1, maxLevel: 18)
            extra.append(["G2", "fast@L5", "\(ms)", "\(r.newLevel)"].joined(separator: "|"))
        }
        // Comfortable boundary at level 3: 6500 + 2 * 450 = 7400.0 (mean of the timed answers only).
        let timings: [[Int64]] = [[7400, 7400, 7400, 7400, 7400], [7401, 7400, 7400, 7400, 7400], [-1, -1, -1, -1, 99999],
                                  [-1, 14800, 0, -1, -1]]
        for times in timings {
            var st = DifficultyState(level: 3, calibrationAnswers: 8)
            var last: DifficultyResult?
            for t in times {
                let r = e.recordAnswer(state: st, correct: true, responseTimeMs: t, minLevel: 1, maxLevel: 5)
                last = r
                st = r.state
            }
            extra.append(["G2", "comfort@L3", times.map { String($0) }.joined(separator: ","), "\(last!.newLevel)"].joined(separator: "|"))
        }
        let custom = DifficultyEngine(calibrationLength: 2, stableWindowSize: 3)
        var cs = DifficultyState(level: 2)
        let customSteps: [(Bool, Int64)] = [(true, 100), (true, 100), (true, -1), (false, -1), (true, -1), (false, -1), (false, -1),
                                            (false, -1)]
        for (c, ms) in customSteps {
            let r = custom.recordAnswer(state: cs, correct: c, responseTimeMs: ms, minLevel: 1, maxLevel: 4)
            cs = r.state
            extra.append(["G2", "custom", "\(c)", "\(ms)", "\(r.newLevel)", "\(cs.calibrationAnswers)", "\(cs.recentAnswers.count)"]
                .joined(separator: "|"))
        }
        assertGolden(["G2"], extra)
    }

    // MARK: - Golden: QuestionLocaleContract, WordEntry, words.xml

    func testGoldenLocaleContractAndWordEntry() {
        let inputs: [String?] = [nil, "", " ", "he", "HE", "iw", "IW-il", "he_IL", "en-US", "fr", "ar", "es-419", "hi_IN", " he ",
                                 "x-he", "-he", "_en", "pt_BR", "zh-Hant-TW", "\u{00A0}he", "he\u{2003}"]
        let norm = inputs.map { input -> String in
            let units = input.map { s in s.utf16.map { String(format: "%04x", Int($0)) }.joined(separator: ".") } ?? "null"
            return "\(units)=\(QuestionLocaleContract.normalize(languageCode: input))"
        }.joined(separator: ";")
        var lines = ["NORM|" + norm]
        let w1 = WordEntry(values: ["he": "תפוח", "en": "Apple"], group: "fruits_a", level: 1)
        let w2 = WordEntry(values: ["en": "Near", "ar": "قريب", "es": "cerca"], group: "directions_a", level: 1)
        let w3 = WordEntry(values: KLinkedMap(), group: "x", level: 3)
        lines.append(["WORDID", w1.id, w2.id, w3.id].joined(separator: "|"))
        let w4 = WordEntry(values: ["he": "  ", "en": "Dog", "EN": "DOG", "x": "y"], group: "g", level: 2, id: "id1")
        let values = ["he", "en", "EN", "en-US", "fr", "x", "iw", ""].map { w4.value(languageCode: $0) ?? "null" }
        lines.append((["WORDVALUE"] + values).joined(separator: "|"))
        assertGolden(["NORM", "WORDID", "WORDVALUE"], lines)
    }

    func testGoldenWordsXml() throws {
        let words = WordsXmlParser.parse(input: try AResources.openAsset("question_banks/words.xml"))
        var lines: [String] = []
        lines.append(["WORDS", "entries=\(words.count)", "first=\(words[0])", "last=\(words[words.count - 1])"].joined(separator: "|"))
        lines.append("WORDS_LEVELS|" + (1...5).map { l in "L\(l)=\(words.filter { $0.level == l }.count)" }.joined(separator: ","))
        lines.append("WORDS_GROUPS|\(words.map { $0.group }.kDistinct().count)")
        var keyCounts: [String: Int] = [:]
        for w in words {
            for key in w.values.keys { keyCounts[key, default: 0] += 1 }
        }
        let keys = keyCounts.keys.sorted { $0.javaPrecedes($1) }.map { "\($0)=\(keyCounts[$0]!)" }.joined(separator: ", ")
        lines.append("WORDS_KEYS|{\(keys)}")
        lines.append(["WORDS_SAMPLE", "\(words[100])", "\(words[500])", "\(words[834])"].joined(separator: "|"))
        assertGolden(["WORDS", "WORDS_LEVELS", "WORDS_GROUPS", "WORDS_KEYS", "WORDS_SAMPLE"], lines)
    }

    func testGoldenWordsXmlAttributeHandling() {
        // Case-insensitive names, iw -> he, blank and non-content locales dropped, level from the suffix after the
        // last '_' (none -> "a", unknown -> 3); commented-out words are not words.
        let xml = #"<?xml version="1.0" encoding="utf-8"?><resources><!-- <string-array name="hidden_a"><word en="Ghost" he="רוח"/></string-array> --><string-array name="x_b"><word EN=" Dog " iw="כלב" fr="Chien" hi=" " he2="x"/><!-- <word en="Cat"/> --><word Ar="قط" eS="gato"/></string-array><string-array name="noUnderscore"><group><word es="perro"/></group></string-array><string-array name="y_Z"><word hI="कुत्ता"/></string-array><string-array name="a_b_e"><word en="Five"/></string-array></resources>"#
        let entries = WordsXmlParser.parse(input: Data(xml.utf8)).map { "\($0)" }.joined(separator: " ## ")
        assertGolden(["WSYN"], ["WSYN|" + entries])
    }

    // MARK: - Golden: generators and engine

    func testGoldenWordsGeneratorDraws() throws {
        let words = WordsXmlParser.parse(input: try AResources.openAsset("question_banks/words.xml"))
        var lines: [String] = []
        for seed: Int64 in [1, 7, 123, -99] {
            for level in [1, 3, 5, 0, 9] {
                let random = KotlinRandom(seed: seed)
                let g = LocalizedEnglishQuestionGenerator(words: words, sourceLanguageCode: "he", targetLanguageCode: "en", random: random)
                let qs = (0..<25).map { _ in g.generate(level: level) }
                let joined = qs.map { q -> String in
                    let parts = [q.id, "\(q.level)", q.prompt, q.answers.joined(separator: "/"), "\(q.correctAnswerIndex)",
                                 q.tags.elements.joined(separator: ","), q.language]
                    return parts.joined(separator: "|")
                }.joined(separator: "\n")
                let first = "first=\(qs[0].id)/\(qs[0].answers.joined(separator: "/"))/\(qs[0].correctAnswerIndex)"
                lines.append(["WGEN", "seed=\(seed)", "level=\(level)", first, "last=\(qs[qs.count - 1].id)", "sha=" + Self.sha256(joined),
                              "nextInt=\(random.nextInt())"].joined(separator: "|"))
            }
        }
        assertGolden(["WGEN"], lines)

        // Other source languages (unreachable in the app; library behaviour). "hi" (no Hindi words) and "fr"
        // (normalized to "en") are IllegalArgumentExceptions on Android and preconditions here, so they are not run.
        var sources: [String] = []
        for code in ["ar", "es", "iw"] {
            let random = KotlinRandom(seed: 5)
            let g = LocalizedEnglishQuestionGenerator(words: words, sourceLanguageCode: code, targetLanguageCode: "en", random: random)
            let q = g.generate(level: 2)
            sources.append(["WGEN_SRC", code, q.id, q.prompt, q.language, q.answers.joined(separator: "/"), "\(q.correctAnswerIndex)",
                            "nextInt=\(random.nextInt())"].joined(separator: "|"))
        }
        let expected = QuestionsGolden.lines.filter {
            $0.hasPrefix("WGEN_SRC|ar|") || $0.hasPrefix("WGEN_SRC|es|") || $0.hasPrefix("WGEN_SRC|iw|")
        }
        XCTAssertEqual(sources, expected)
    }

    func testGoldenXmlGeneratorAndEngine() throws {
        var lines: [String] = []
        let ai = try Self.parseBank("question_banks/artificial_intelligence.xml", "he")
        let cases: [(Int64, Int)] = [(3, 1), (3, 2), (11, 2), (11, 3), (5, 7), (5, -2)]
        for (seed, level) in cases {
            let random = KotlinRandom(seed: seed)
            let g = XmlQuestionGenerator(mode: QuestionMode.ARTIFICIAL_INTELLIGENCE, questions: ai, random: random)
            let ids = (0..<16).map { _ in Self.removePrefix(g.generate(level: level).id, "artificial_intelligence_") }
            lines.append(["XGEN", "seed=\(seed)", "level=\(level)", "min=\(g.minLevel)", "max=\(g.maxLevel)", ids.joined(separator: ","),
                          "nextInt=\(random.nextInt())"].joined(separator: "|"))
        }
        // Nearest-level fallback over a synthetic pool (levels 1, 1, 4, 4, 6; a SCIENCE question to filter out).
        func sq(_ id: String, _ level: Int, _ mode: QuestionMode = QuestionMode.HISTORY) -> Question {
            return try! Question(id: id, mode: mode, level: level, prompt: "p\(id)", answers: ["a", "b"], correctAnswerIndex: 0)
        }
        let syn = [sq("a", 1), sq("b", 1), sq("c", 4), sq("d", 4), sq("e", 6), sq("z", 2, QuestionMode.SCIENCE)]
        let sr = KotlinRandom(seed: 77)
        let sg = XmlQuestionGenerator(mode: QuestionMode.HISTORY, questions: syn, random: sr, recentMemory: 2)
        let picks = [2, 2, 2, 2, 3, 3, 3, 5, 5, 5, 5, 2, 6, 6, 1].map { "\($0):\(sg.generate(level: $0).id)" }.joined(separator: ",")
        lines.append(["XGEN_NEAR", "min=\(sg.minLevel)", "max=\(sg.maxLevel)", picks, "nextInt=\(sr.nextInt())"].joined(separator: "|"))

        // QuestionEngine with and without a mix (library behaviour; Triple Shot never sets a mix).
        let mixRandom = KotlinRandom(seed: 9)
        let gk = try Self.parseBank("question_banks/general_knowledge.xml", "he")
        let hist = try Self.parseBank("question_banks/history.xml", "he")
        let eng = QuestionEngine(generators: [XmlQuestionGenerator(mode: QuestionMode.GENERAL_KNOWLEDGE, questions: gk, random: mixRandom),
                                              XmlQuestionGenerator(mode: QuestionMode.HISTORY, questions: hist, random: mixRandom)],
                                 random: mixRandom)
        let modes = eng.registeredModes().elements.map { $0.name }.joined(separator: ",")
        let states = "{" + eng.getAllDifficultyStates().entries.map { "\($0.key.name)=\($0.value)" }.joined(separator: ", ") + "}"
        let firstEight = (0..<8).map { _ in eng.nextQuestion().id }.joined(separator: ",")
        lines.append(["QENGINE", "modes=" + modes, "states=" + states, firstEight].joined(separator: "|"))
        eng.setQuestionMix(newMix: QuestionMix(weights: [QuestionMode.HISTORY: 3, QuestionMode.GENERAL_KNOWLEDGE: 0]))
        let mixed = (0..<5).map { _ in eng.nextQuestion().id }.joined(separator: ",")
        let explicit = (0..<3).map { _ in eng.nextQuestion(levels: [QuestionMode.HISTORY: 9]).id }.joined(separator: ",")
        let low = eng.nextQuestion(mode: QuestionMode.GENERAL_KNOWLEDGE, explicitLevel: -5).id
        lines.append(["QENGINE", "mix", mixed, explicit, low, "nextInt=\(mixRandom.nextInt())"].joined(separator: "|"))
        let hq = eng.nextQuestion(mode: QuestionMode.HISTORY)
        let res = eng.recordAnswer(question: hq, answerIndex: hq.correctAnswerIndex, responseTimeMs: 1200)
        eng.restoreDifficultyState(mode: QuestionMode.GENERAL_KNOWLEDGE,
                                   state: DifficultyState(level: 99, calibrationAnswers: 3,
                                                          recentAnswers: [AnswerPerformance(correct: true, responseTimeMs: 5)]))
        let gkState = eng.getDifficultyState(mode: QuestionMode.GENERAL_KNOWLEDGE).map { "\($0)" } ?? "null"
        let scienceState = eng.getDifficultyState(mode: QuestionMode.SCIENCE).map { "\($0)" } ?? "null"
        lines.append(["QENGINE", "record", hq.id, "\(res)", gkState, scienceState].joined(separator: "|"))
        let arithmeticOnly = QuestionMix.arithmeticOnly().enabledModes.elements.map { $0.name }.joined(separator: ", ")
        let scienceOnly = QuestionMix(weights: [QuestionMode.HISTORY: 0, QuestionMode.SCIENCE: 2]).enabledModes.elements
            .map { $0.name }.joined(separator: ", ")
        lines.append(["QMIX", "\(QuestionMix.single(mode: QuestionMode.PARADOXES).totalWeight)", "[\(arithmeticOnly)]", "[\(scienceOnly)]",
                      "\(QuestionMix(weights: [QuestionMode.SCIENCE: 2]).weightOf(mode: QuestionMode.HISTORY))"].joined(separator: "|"))
        assertGolden(["XGEN", "XGEN_NEAR", "QENGINE", "QMIX"], lines)
    }

    // MARK: - Golden: every bank parses to the Android result (SHA-256 of the canonical form)

    func testGoldenBankHashes() throws {
        var lines: [String] = []
        for name in Self.bankFiles("question_banks") {
            let he = try Self.parseBank("question_banks/\(name)", "he")
            let en = try Self.parseBank("question_banks/en/\(name)", "en")
            let heFileEnglishPreference = try Self.parseBank("question_banks/\(name)", "en")
            lines.append(["BANK", name, "he=\(he.count)", "en=\(en.count)", "sha256(he)=" + Self.sha256(Self.canon(he)),
                          "sha256(en)=" + Self.sha256(Self.canon(en)),
                          "sha256(he-file,en-pref)=" + Self.sha256(Self.canon(heFileEnglishPreference))].joined(separator: "|"))
        }
        let english = try Self.parseBank("question_banks/en/english.xml", "en")
        lines.append(["BANK", "en/english.xml", "en=\(english.count)", "sha256(en)=" + Self.sha256(Self.canon(english))].joined(separator: "|"))
        let first = try Self.parseBank("question_banks/science.xml", "he")[0]
        lines.append("BANK_FIRST|\(first)")
        assertGolden(["BANK", "BANK_FIRST"], lines)
    }

    // MARK: - Golden: AndroidQuestionBankParser cases

    func testGoldenParserCases() {
        var lines: [String] = []
        let ok = #"<question-bank mode="HISTORY" language="he"><question id="q1" level="2"><prompt lang="he">שלום</prompt><prompt lang="en">Hello</prompt><answer correct="true">a</answer><answer>b</answer><explanation lang="en">because</explanation></question></question-bank>"#
        lines.append(parseCase("ok-en", ok, "en"))
        lines.append(parseCase("ok-he", ok, "he"))
        lines.append(parseCase("ok-ar", ok, "ar"))
        lines.append(parseCase("ok-iw", ok, "iw"))
        lines.append(parseCase("doctype", "<!DOCTYPE x [<!ENTITY e SYSTEM 'file:///invalid'>]><x/>"))
        lines.append(parseCase("doctype-lower", #"<?xml version="1.0"?><!doctype q-b><question-bank/>"#))
        lines.append(parseCase("doctype-mixed-in-text", #"<question-bank mode="HISTORY"><question id="q" level="1"><prompt>x &lt;!DocType y</prompt><answer correct="true">a</answer><answer>b</answer></question></question-bank>"#))
        lines.append(parseCase("empty-bank", #"<question-bank mode="HISTORY"/>"#))
        lines.append(parseCase("no-mode", #"<question-bank><question id="q1" level="1"><prompt>p</prompt><answer correct="true">a</answer><answer>b</answer></question></question-bank>"#))
        lines.append(parseCase("blank-mode-root", #"<question-bank mode="  "><question id=" q1 " level="1"><prompt>p</prompt><answer correct="true">a</answer><answer>b</answer></question></question-bank>"#))
        lines.append(parseCase("question-mode", #"<question-bank><question id="q1" mode=" history " level="1"><prompt>p</prompt><answer correct="true">a</answer><answer>b</answer></question></question-bank>"#))
        lines.append(parseCase("invalid-mode", #"<question-bank mode="MATH"><question id="q1" level="1"><prompt>p</prompt><answer correct="true">a</answer><answer>b</answer></question></question-bank>"#))
        lines.append(parseCase("blank-id", #"<question-bank mode="HISTORY"><question id="q0" level="1"><prompt>p</prompt><answer correct="true">a</answer><answer>b</answer></question><question id="  " level="1"><prompt>p</prompt><answer correct="true">a</answer><answer>b</answer></question></question-bank>"#))
        lines.append(parseCase("dup-id", #"<question-bank mode="HISTORY"><question id="q1" level="1"><prompt>p</prompt><answer correct="true">a</answer><answer>b</answer></question><question id=" q1" level="1"><prompt>p</prompt><answer correct="true">a</answer><answer>b</answer></question></question-bank>"#))
        for lv in ["x", "0", "-1", " 3", "+3", "٣", "３", "2147483648", "", "1.0", "07"] {
            lines.append(parseCase("level[\(lv)]", #"<question-bank mode="HISTORY"><question id="q1" level=""# + lv + #""><prompt>p</prompt><answer correct="true">a</answer><answer>b</answer></question></question-bank>"#))
        }
        lines.append(parseCase("no-prompt", #"<question-bank mode="HISTORY"><question id="q1" level="1"><prompt> </prompt><answer correct="true">a</answer><answer>b</answer></question></question-bank>"#))
        lines.append(parseCase("blank-answer", #"<question-bank mode="HISTORY"><question id="q1" level="1"><prompt>p</prompt><answer correct="true">a</answer><answer> </answer></question></question-bank>"#))
        lines.append(parseCase("no-correct", #"<question-bank mode="HISTORY"><question id="q1" level="1"><prompt>p</prompt><answer correct="yes">a</answer><answer quality="99">b</answer></question></question-bank>"#))
        lines.append(parseCase("multi-correct", #"<question-bank mode="HISTORY"><question id="q1" level="1"><prompt>p</prompt><answer correct="TRUE">a</answer><answer quality="100">b</answer></question></question-bank>"#))
        lines.append(parseCase("multi-allowed", #"<question-bank mode="HISTORY"><question id="q1" level="1"><prompt>p</prompt><answer>z</answer><answer correct="True">a</answer><answer quality="100">b</answer></question></question-bank>"#, "en", true))
        lines.append(parseCase("quality100", #"<question-bank mode="HISTORY"><question id="q1" level="1"><prompt>p</prompt><answer>z</answer><answer quality="100">a</answer><answer quality=" 100">b</answer></question></question-bank>"#))
        lines.append(parseCase("dup-answers", #"<question-bank mode="HISTORY"><question id="q1" level="1"><prompt>p</prompt><answer correct="true">a</answer><answer> a </answer></question></question-bank>"#))
        lines.append(parseCase("one-answer", #"<question-bank mode="HISTORY"><question id="q1" level="1"><prompt>p</prompt><answer correct="true">a</answer></question></question-bank>"#))
        lines.append(parseCase("attrs", #"<question-bank mode="HISTORY" language=""><question id="q1" level="1" language="iw-IL" image="img.png" tags=" b, a,,b , "><prompt>p</prompt><answer correct="true">a</answer><answer>b</answer></question><question id="q2" level="1" image="  "><prompt>p</prompt><answer correct="true">a</answer><answer>b</answer></question></question-bank>"#, "es"))
        lines.append(parseCase("lang-default-pref", #"<question-bank mode="HISTORY"><question id="q1" level="1"><prompt>p</prompt><answer correct="true">a</answer><answer>b</answer></question></question-bank>"#, "he-IL"))
        lines.append(parseCase("localized-fallbacks", #"<question-bank mode="HISTORY"><question id="q1" level="1"><prompt lang="ar"> عربي </prompt><prompt> plain </prompt><prompt lang="fr">french-as-en</prompt><prompt lang="en">english</prompt><answer correct="true">a</answer><answer>b</answer><explanation lang="ar"> </explanation><explanation>x</explanation></question></question-bank>"#, "he"))
        lines.append(parseCase("localized-blank-first", #"<question-bank mode="HISTORY"><question id="q1" level="1"><prompt lang="ar">  </prompt><prompt lang="es">second</prompt><answer correct="true">a</answer><answer>b</answer><explanation lang="he"> </explanation></question></question-bank>"#, "he"))
        lines.append(parseCase("textcontent", #"<question-bank mode="HISTORY"><question id="q1" level="1"><prompt lang="en"> Hello <b>big</b> <!-- c --> world &amp; &lt;x&gt; &#x5D0; </prompt><answer correct="true"><![CDATA[a < b]]></answer><answer>b<i>c</i>d</answer></question></question-bank>"#))
        lines.append(parseCase("nested-descendants", #"<question-bank mode="HISTORY"><group><question id="q1" level="1"><prompt>p</prompt><wrap><answer correct="true">a</answer></wrap><answer>b</answer></question></group><question id="q2" level="1"><prompt>p2</prompt><answer>x</answer><answer correct="true">y</answer></question></question-bank>"#))
        lines.append(parseCase("whitespace-trim", "<question-bank mode=\"HISTORY\"><question id=\"q1\" level=\"1\"><prompt>\n\t p  </prompt><answer correct=\"true\"> a </answer><answer>b</answer></question></question-bank>"))
        assertGolden(["PARSE"], lines)
    }

    /// Golden.kt `parseCase`: "OK" and every question's fields, or "ERR <exception>: <message>".
    private func parseCase(_ name: String, _ xml: String, _ pref: String = "en", _ multi: Bool = false) -> String {
        let result: String
        do {
            let qs = try AndroidQuestionBankParser.parse(input: Data(xml.utf8), preferredLanguage: pref, allowMultipleCorrectAnswers: multi)
            result = "OK " + qs.map { q -> String in
                let answers = q.answers.map { "[\($0)]" }.joined(separator: "/")
                let indices = "[" + q.correctAnswerIndices.elements.map { String($0) }.joined(separator: ", ") + "]"
                let explanation = q.explanation.map { "[\($0)]" } ?? "null"
                let tags = "[" + q.tags.elements.joined(separator: ", ") + "]"
                let parts = [q.id, q.mode.name, "\(q.level)", "[\(q.prompt)]", answers, "\(q.correctAnswerIndex)", indices, explanation,
                             q.language, q.imageRef ?? "null", tags, "\(q.allowMultipleCorrectAnswers)"]
                return parts.joined(separator: "~")
            }.joined(separator: " ## ")
        } catch let error as QuestionsIllegalArgumentException {
            result = "ERR IllegalArgumentException: " + error.message
        } catch {
            result = "ERR \(error)"
        }
        return "PARSE|\(name)|\(result)"
    }

    // MARK: - Golden S: repository semantics

    func testGoldenS_RepositorySemantics() {
        var lines: [String] = []
        fresh("he")
        // A question is generated the first time its index is read.
        let a = TripleShotQuestionRepository.shuffled(seed: 42, categories: [QuestionCategory.KIDS_ARITHMETIC, QuestionCategory.HISTORY])
        let reads = [7, 0, 1, 7, 2, 3].map { "\($0):\(a[$0].category.name):\(a[$0].id)" }.joined(separator: ",")
        lines.append(["S", "out-of-order", reads, "getOrNull(-1)=" + (a.getOrNull(-1).map { "\($0)" } ?? "null"),
                      "getOrNull(4096)=" + (a.getOrNull(4096).map { "\($0)" } ?? "null"), "size=\(a.size)"].joined(separator: "|"))
        // The categories' iteration order feeds the shuffle.
        let b = TripleShotQuestionRepository.shuffled(seed: 42, categories: [QuestionCategory.HISTORY, QuestionCategory.KIDS_ARITHMETIC])
        lines.append(["S", "set-order", (0..<4).map { "\(b[$0].category.name):\(b[$0].id)" }.joined(separator: ",")].joined(separator: "|"))
        // The latest session that generated an id receives its answers.
        fresh("he")
        let s1 = TripleShotQuestionRepository.shuffled(seed: 42, categories: [QuestionCategory.KIDS_ARITHMETIC])
        let q1 = s1[0]
        let s2 = TripleShotQuestionRepository.shuffled(seed: 42, categories: [QuestionCategory.KIDS_ARITHMETIC])
        let q2 = s2[0]
        TripleShotQuestionRepository.recordAnswer(questionId: q1.id, selectedAnswerIndex: correctIndex(q1))
        let s1Next = s1[1]
        let s2Next = s2[1]
        lines.append(["S", "latest-session", q1.id, q2.id, "s1[1]=\(s1Next.id)/L" + level(s1Next.id), "s2[1]=\(s2Next.id)/L" + level(s2Next.id),
                      "prefs:" + prefsDump()].joined(separator: "|"))
        // Unknown ids are ignored; answer indices outside the answers count as wrong.
        TripleShotQuestionRepository.recordAnswer(questionId: "no_such_question", selectedAnswerIndex: 0, responseTimeMs: 500)
        lines.append(["S", "unknown-id", "prefs:" + prefsDump()].joined(separator: "|"))
        TripleShotQuestionRepository.recordAnswer(questionId: q1.id, selectedAnswerIndex: 7, responseTimeMs: 500)
        TripleShotQuestionRepository.recordAnswer(questionId: q1.id, selectedAnswerIndex: -1)
        lines.append(["S", "out-of-range-answers", "prefs:" + prefsDump()].joined(separator: "|"))
        let levels = QuestionCategory.allCases.map { category -> String in
            "\(category.name)=" + (TripleShotQuestionRepository.currentLevel(category: category).map { String($0) } ?? "null")
        }.joined(separator: ",")
        lines.append(["S", "currentLevel", levels].joined(separator: "|"))
        // Saved levels are clamped into the bank's range; a calibration count without a level is not restored.
        fresh("en")
        getSharedPreferences(Self.PREFS, MODE_PRIVATE).edit()
            .putInt("HISTORY_level", 40).putInt("HISTORY_cal", 8).putInt("SCIENCE_cal", 5).commit()
        let h = TripleShotQuestionRepository.shuffled(seed: 5, categories: [QuestionCategory.HISTORY, QuestionCategory.SCIENCE])
        let firstSix = (0..<6).map { "\(h[$0].id)/L" + level(h[$0].id) }.joined(separator: ",")
        let history = TripleShotQuestionRepository.currentLevel(category: QuestionCategory.HISTORY).map { String($0) } ?? "null"
        let science = TripleShotQuestionRepository.currentLevel(category: QuestionCategory.SCIENCE).map { String($0) } ?? "null"
        lines.append(["S", "restore-clamp", firstSix, "history=" + history, "science=" + science].joined(separator: "|"))
        TripleShotQuestionRepository.recordAnswer(questionId: h[0].id, selectedAnswerIndex: correctIndex(h[0]), responseTimeMs: 100)
        TripleShotQuestionRepository.recordAnswer(questionId: h[1].id, selectedAnswerIndex: correctIndex(h[1]), responseTimeMs: 100)
        lines.append(["S", "restore-record", "prefs:" + prefsDump()].joined(separator: "|"))
        assertGolden(["S"], lines)
    }

    // MARK: - Intro, language, release gating, list and question basics

    func testInitializeShowsTheIntroOnceAndPicksTheQuestionLanguage() {
        let prefs = getSharedPreferences(Self.PREFS, MODE_PRIVATE)
        prefs.edit().clear().commit()
        setLanguage("he")
        TripleShotQuestionRepository.initialize(context: AApplication.shared)  // shows the LENGTH_LONG intro toast
        XCTAssertEqual(prefsDump(), "adaptive_intro_shown=true")
        XCTAssertEqual(TripleShotQuestionRepository.shuffled(seed: 123, categories: [QuestionCategory.ENGLISH])[0].id, "words_verbs_c-16")
        // Only he/iw gives the Hebrew banks; every other language gets the English banks (spec 04 §4.9).
        for (language, firstEnglishId) in [("en", "english_en_008"), ("fr", "english_en_008"), ("iw", "words_verbs_c-16")] {
            setLanguage(language)
            TripleShotQuestionRepository.initialize(context: AApplication.shared)
            XCTAssertEqual(TripleShotQuestionRepository.shuffled(seed: 123, categories: [QuestionCategory.ENGLISH])[0].id, firstEnglishId,
                           language)
        }
        XCTAssertEqual(prefsDump(), "adaptive_intro_shown=true")
    }

    func testCloudPracticeIsDisabledInReleaseBuilds() {
        XCTAssertFalse(TripleShotDelivery.hasBundle)
        XCTAssertFalse(TripleShotDelivery.hasRemote)
        XCTAssertFalse(TripleShotDelivery.enabled)
    }

    func testAdaptiveListMembers() {
        let empty = AdaptiveQuestionList.emptyList()
        XCTAssertEqual(empty.size, 0)
        XCTAssertEqual(empty.count, 0)
        XCTAssertTrue(empty.isEmpty)
        XCTAssertFalse(empty.isNotEmpty())
        XCTAssertTrue(empty.indices.isEmpty)
        XCTAssertNil(empty.getOrNull(0))
        XCTAssertNil(empty.firstOrNull())
        XCTAssertNil(empty.firstOrNull { _ in true })

        fresh("he")
        let list = TripleShotQuestionRepository.shuffled(seed: 123, categories: [QuestionCategory.HISTORY])
        XCTAssertEqual(list.size, 4096)
        XCTAssertEqual(list.count, 4096)
        XCTAssertFalse(list.isEmpty)
        XCTAssertTrue(list.isNotEmpty())
        XCTAssertEqual(list.indices, 0..<4096)
        XCTAssertNil(list.getOrNull(-1))
        XCTAssertNil(list.getOrNull(4096))
        XCTAssertEqual(list.first(), list[0])
        XCTAssertEqual(list.firstOrNull(), list.get(0))
        XCTAssertEqual(list.first(where: { $0.id == list[1].id }), list[1])
        XCTAssertEqual(list[0].category, QuestionCategory.HISTORY)
        XCTAssertEqual(list[0].answers.map { $0.qualityPercent }.filter { $0 == 100 }.count, 1)
        XCTAssertEqual(list[0].answers.map { $0.qualityPercent }.filter { $0 == 0 }.count, 3)
    }

    func testQuestionDefaultsAndValidationMessages() throws {
        let q = try Question(id: "q", mode: QuestionMode.HISTORY, level: 1, prompt: "p", answers: ["a", "b", "c"], correctAnswerIndex: 2)
        XCTAssertEqual(q.correctAnswerIndices, [2])
        XCTAssertTrue(q.isCorrect(answerIndex: 2))
        XCTAssertFalse(q.isCorrect(answerIndex: 0))
        XCTAssertFalse(q.isCorrect(answerIndex: -1))
        XCTAssertEqual(q.correctAnswer, "c")
        XCTAssertNil(q.explanation)
        XCTAssertEqual(q.language, "he")
        XCTAssertNil(q.imageRef)
        XCTAssertTrue(q.tags.isEmpty)
        XCTAssertFalse(q.allowMultipleCorrectAnswers)

        func failure(_ make: () throws -> Question) -> String? {
            do {
                _ = try make()
                return nil
            } catch {
                return Self.message(error)
            }
        }
        let h = QuestionMode.HISTORY
        XCTAssertEqual(failure { try Question(id: " ", mode: h, level: 1, prompt: "p", answers: ["a", "b"], correctAnswerIndex: 0) },
                       "Question id must not be blank")
        XCTAssertEqual(failure { try Question(id: "q", mode: h, level: 0, prompt: "p", answers: ["a", "b"], correctAnswerIndex: 0) },
                       "Question level must be >= 1")
        XCTAssertEqual(failure { try Question(id: "q", mode: h, level: 1, prompt: "\t", answers: ["a", "b"], correctAnswerIndex: 0) },
                       "Question prompt must not be blank")
        XCTAssertEqual(failure { try Question(id: "q", mode: h, level: 1, prompt: "p", answers: ["a"], correctAnswerIndex: 0) },
                       "Question must contain at least 2 answers")
        XCTAssertEqual(failure { try Question(id: "q", mode: h, level: 1, prompt: "p", answers: ["a", " "], correctAnswerIndex: 0) },
                       "Question answers must not be blank")
        XCTAssertEqual(failure { try Question(id: "q", mode: h, level: 1, prompt: "p", answers: ["a", "b"], correctAnswerIndex: 2) },
                       "correctAnswerIndex is outside answers")
        XCTAssertEqual(failure { try Question(id: "q", mode: h, level: 1, prompt: "p", answers: ["a", " a"], correctAnswerIndex: 0) },
                       "Answers must be unique")
        XCTAssertEqual(failure {
            try Question(id: "q", mode: h, level: 1, prompt: "p", answers: ["a", "b"], correctAnswerIndex: 0, correctAnswerIndices: KLinkedSet())
        }, "Question must contain a correct answer")
        XCTAssertEqual(failure {
            try Question(id: "q", mode: h, level: 1, prompt: "p", answers: ["a", "b"], correctAnswerIndex: 0, correctAnswerIndices: [0, 5])
        }, "A correct answer index is outside answers")
        XCTAssertEqual(failure {
            try Question(id: "q", mode: h, level: 1, prompt: "p", answers: ["a", "b"], correctAnswerIndex: 0,
                         allowMultipleCorrectAnswers: true, correctAnswerIndices: [1])
        }, "correctAnswerIndex must remain one of the accepted answers")
        XCTAssertEqual(failure {
            try Question(id: "q", mode: h, level: 1, prompt: "p", answers: ["a", "b"], correctAnswerIndex: 0, correctAnswerIndices: [0, 1])
        }, "Single-answer questions must contain exactly one correct answer")
    }

    // MARK: - Helpers (the JVM harness)

    /// `Configuration(ctx.resources.configuration).setLocale(Locale(language))`: RefinementTest and the harness give
    /// `initialize` a context in that language; AndroidKit contexts share the app window's configuration.
    private func setLanguage(_ language: String) {
        let base = AConfiguration.current
        AConfiguration.current = AConfiguration(
            orientation: base.orientation, screenWidthDp: base.screenWidthDp, screenHeightDp: base.screenHeightDp,
            smallestScreenWidthDp: base.smallestScreenWidthDp, densityDpi: base.densityDpi, fontScale: base.fontScale,
            uiMode: base.uiMode, locales: ALocaleList([ALocale(language)]))
    }

    /// Golden.kt `fresh(lang)`: empty preferences, then `initialize`. There the intro toast then set
    /// adaptive_intro_shown; setting it first leaves the same preferences without queueing a toast per scenario
    /// (the intro itself: testInitializeShowsTheIntroOnceAndPicksTheQuestionLanguage).
    private func fresh(_ language: String) {
        setLanguage(language)
        let prefs = getSharedPreferences(Self.PREFS, MODE_PRIVATE)
        prefs.edit().clear().commit()
        prefs.edit().putBoolean("adaptive_intro_shown", true).commit()
        TripleShotQuestionRepository.initialize(context: AApplication.shared)
    }

    /// MemPrefs.dump(): "key=value" in TreeMap (String.compareTo) order, joined by ",".
    private func prefsDump() -> String {
        let prefs = getSharedPreferences(Self.PREFS, MODE_PRIVATE)
        return prefs.getAll().keys.sorted { $0.javaPrecedes($1) }.map { key -> String in
            key == "adaptive_intro_shown" ? "\(key)=\(prefs.getBoolean(key, false))" : "\(key)=\(prefs.getInt(key, 0))"
        }.joined(separator: ",")
    }

    /// The UserDefaults entries of the difficulty preferences file (ASharedPreferences "<file>.<key>").
    private static func storedPrefs() -> [String: Any] {
        let prefix = PREFS + "."
        return UserDefaults.standard.dictionaryRepresentation().filter { $0.key.hasPrefix(prefix) }
    }

    /// Golden.kt `correctIndex`: the index of the 100-quality answer.
    private func correctIndex(_ q: TripleShotQuestion) -> Int {
        return q.answers.firstIndex { $0.qualityPercent == 100 } ?? -1
    }

    /// Golden.kt `levelById`: every bank question's level by id (he and en folders) and "words_<id>" levels.
    private static let levelById: [String: Int] = {
        var map: [String: Int] = [:]
        for (folder, language) in [("question_banks", "he"), ("question_banks/en", "en")] {
            for name in QuestionsTests.bankFiles(folder) {
                for q in try! QuestionsTests.parseBank("\(folder)/\(name)", language) { map[q.id] = q.level }
            }
        }
        for w in WordsXmlParser.parse(input: try! AResources.openAsset("question_banks/words.xml")) {
            map["words_" + w.id] = w.level
        }
        return map
    }()

    /// `"${levelById[id]}"`.
    private func level(_ id: String) -> String {
        return Self.levelById[id].map { String($0) } ?? "null"
    }

    /// `File(folder).listFiles().filter { it.extension == "xml" && it.name != "words.xml" }`, sorted by name.
    private static func bankFiles(_ folder: String) -> [String] {
        let names = (try? FileManager.default.contentsOfDirectory(atPath: AResources.assetURL(folder).path)) ?? []
        return names.filter { $0.hasSuffix(".xml") && $0 != "words.xml" }.sorted { $0.javaPrecedes($1) }
    }

    private static func parseBank(_ path: String, _ language: String) throws -> [Question] {
        return try AndroidQuestionBankParser.parse(input: AResources.openAsset(path), preferredLanguage: language)
    }

    /// Golden.kt `canon`: the fields of every question, \u{1}-separated (answers \u{2}-separated, tags sorted).
    private static func canon(_ questions: [Question]) -> String {
        return questions.map { q -> String in
            let parts = [q.id, q.mode.name, "\(q.level)", q.prompt, q.answers.joined(separator: "\u{2}"), "\(q.correctAnswerIndex)",
                         q.explanation ?? "", q.language, q.tags.elements.sorted { $0.javaPrecedes($1) }.joined(separator: ",")]
            return parts.joined(separator: "\u{1}")
        }.joined(separator: "\n")
    }

    private static func sha256(_ s: String) -> String {
        return SHA256.hash(data: Data(s.utf8)).map { String(format: "%02x", $0) }.joined()
    }

    /// Regex("[֐-׿]").containsMatchIn(s).
    private static func containsHebrew(_ s: String) -> Bool {
        return s.utf16.contains { $0 >= 0x0590 && $0 <= 0x05FF }
    }

    private static func removePrefix(_ s: String, _ prefix: String) -> String {
        return s.hasPrefix(prefix) ? String(s.dropFirst(prefix.count)) : s
    }

    private static func message(_ error: Error) -> String? {
        return (error as? QuestionsIllegalArgumentException)?.message
    }

    /// Compares the iOS lines with the Android golden lines of these sections (in file order).
    private func assertGolden(_ sections: [String], _ actual: [String], file: StaticString = #filePath, line: UInt = #line) {
        let expected = QuestionsGolden.lines.filter { golden in sections.contains { golden.hasPrefix($0 + "|") } }
        XCTAssertFalse(expected.isEmpty, "no golden lines for \(sections)", file: file, line: line)
        XCTAssertEqual(actual.count, expected.count, "\(sections): line count", file: file, line: line)
        for (index, pair) in zip(actual, expected).enumerated() where pair.0 != pair.1 {
            XCTFail("\(sections) line \(index)\n  iOS:     \(pair.0)\n  Android: \(pair.1)", file: file, line: line)
        }
    }
}

/// questionenginelib ValidatedXmlQuestionBankParser.kt (578ed22), the reference parser of
/// AndroidQuestionBankParserTest, statement by statement over AXmlDocument. Its Apache `disallow-doctype-decl`
/// feature (a SAXParseException for any document type declaration) is a "<!DOCTYPE" check (XML spells the keyword
/// in capitals); no bundled bank has one.
private enum ValidatedXmlQuestionBankParser {
    struct DoctypeDisallowed: Error {}

    static func parse(
        input: Data,
        preferredLanguage: String = "en",
        allowMultipleCorrectAnswers: Bool = false
    ) throws -> [Question] {
        if String(decoding: input, as: UTF8.self).contains("<!DOCTYPE") { throw DoctypeDisallowed() }
        let doc = try AXmlDocument.parse(input)
        let root = doc.documentElement
        let defaultMode = QuestionsKotlin.notBlank(root.getAttribute("mode"))
        let defaultLanguage = QuestionsKotlin.notBlank(root.getAttribute("language")) ?? preferredLanguage
        var out: [Question] = []
        var ids = Set<String>()
        let nodes = root.getElementsByTagName("question")
        for i in kuntil(0, nodes.count) {
            let element = nodes[i]
            guard let modeName = QuestionsKotlin.notBlank(element.getAttribute("mode")) ?? defaultMode else {
                throw QuestionsIllegalArgumentException("question \(element.getAttribute("id")) has no mode")
            }
            guard let mode = QuestionMode.named(modeName.ktrim().uppercased()) else {
                throw QuestionsIllegalArgumentException("question \(element.getAttribute("id")) has invalid mode: \(modeName)")
            }
            let id = element.getAttribute("id").ktrim()
            try QuestionsKotlin.require(!id.kotlinIsBlank, "question at index \(i) has a blank id")
            try QuestionsKotlin.require(ids.insert(id).inserted, "Duplicate question id: \(id)")
            let levelText = element.getAttribute("level")
            guard let level = QuestionsKotlin.toIntOrNull(levelText) else {
                throw QuestionsIllegalArgumentException("question \(id) has invalid level: \(levelText)")
            }
            try QuestionsKotlin.require(level >= 1, "question \(id) has invalid level: \(level)")
            let language = QuestionLocaleContract.normalize(
                languageCode: QuestionsKotlin.notBlank(element.getAttribute("language")) ?? defaultLanguage)
            let image = QuestionsKotlin.notBlank(element.getAttribute("image"))
            let tags = KLinkedSet(QuestionsKotlin.split(element.getAttribute("tags"), ",").map { $0.ktrim() }.filter { !$0.isEmpty })
            let prompt = localizedChildText(parent: element, tag: "prompt", language: preferredLanguage)
            try QuestionsKotlin.require(!prompt.kotlinIsBlank, "question \(id) has no prompt")
            let answerNodes = element.getElementsByTagName("answer")
            var answers: [String] = []
            var correct = KLinkedSet<Int>()
            for j in kuntil(0, answerNodes.count) {
                let answerElement = answerNodes[j]
                let answer = answerElement.textContent.ktrim()
                try QuestionsKotlin.require(!answer.kotlinIsBlank, "question \(id) has a blank answer")
                answers.append(answer)
                if QuestionsKotlin.equalsIgnoreCase(answerElement.getAttribute("correct"), "true")
                    || answerElement.getAttribute("quality") == "100" {
                    correct.add(j)
                }
            }
            try QuestionsKotlin.require(!correct.isEmpty, "question \(id) has no correct answer")
            if !allowMultipleCorrectAnswers {
                try QuestionsKotlin.require(correct.count == 1, "question \(id) has multiple correct answers")
            }
            let explanation = QuestionsKotlin.notBlank(localizedChildText(parent: element, tag: "explanation", language: preferredLanguage))
            out.append(try Question(
                id: id,
                mode: mode,
                level: level,
                prompt: prompt,
                answers: answers,
                correctAnswerIndex: correct.elements[0],
                explanation: explanation,
                language: language,
                imageRef: image,
                tags: tags,
                allowMultipleCorrectAnswers: allowMultipleCorrectAnswers,
                correctAnswerIndices: correct
            ))
        }
        return out
    }

    private static func localizedChildText(parent: AXmlElement, tag: String, language: String) -> String {
        let nodes = parent.getElementsByTagName(tag)
        var fallback = ""
        var english = ""
        let wanted = QuestionLocaleContract.normalize(languageCode: language)
        for i in kuntil(0, nodes.count) {
            let element = nodes[i]
            let text = element.textContent.ktrim()
            if fallback.kotlinIsBlank { fallback = text }
            let rawLanguage = element.getAttribute("lang")
            let normalized = rawLanguage.kotlinIsBlank ? "" : QuestionLocaleContract.normalize(languageCode: rawLanguage)
            if normalized == "en" && english.kotlinIsBlank { english = text }
            if normalized == wanted { return text }
        }
        return english.kotlinIsBlank ? fallback : english
    }
}

/// The Android golden lines, verbatim.
private enum QuestionsGolden {
    /// SNAP/work/t-questions/harness/Golden.kt run over the unmodified Kotlin sources (kotlin-compiler-embeddable
    /// 2.3.21, JDK 25 jbr) and the Android assets: 303 lines (the TOASTS count line is left out).
    static let lines: [String] = [
        "A|seed=0|nextInt()x3=-1934310868,1409199696,-649160781|fresh nextInt(4,3,2,439,184)=2,0,1,347,58|continued=2,0,0,36,167",
        "A|seed=1|nextInt()x3=600123930,-1531902544,-527218591|fresh nextInt(4,3,2,439,184)=0,0,1,149,13|continued=2,0,0,137,41",
        "A|seed=42|nextInt()x3=972016666,1740578880,-408207414|fresh nextInt(4,3,2,439,184)=0,0,1,139,93|continued=3,1,0,287,76",
        "A|seed=123|nextInt()x3=296510812,1786788691,-507296660|fresh nextInt(4,3,2,439,184)=0,0,1,281,119|continued=1,0,0,208,84",
        "A|seed=-1|nextInt()x3=-280203964,-1115932487,-2122700674|fresh nextInt(4,3,2,439,184)=3,2,1,42,84|continued=1,1,0,329,179",
        "A|seed=1760000000000|nextInt()x3=-337619862,2111320207,791028487|fresh nextInt(4,3,2,439,184)=3,0,0,406,47|continued=2,1,0,396,158",
        "B|seed=0|HISTORY,PARADOX,MATH,GENERAL_KNOWLEDGE,PROGRAMMING,ENGLISH,SCIENCE,AI,ASTRONOMY,KIDS_ARITHMETIC,MATRICULATION_MATH",
        "B|seed=1|MATH,GENERAL_KNOWLEDGE,ASTRONOMY,SCIENCE,PROGRAMMING,ENGLISH,KIDS_ARITHMETIC,MATRICULATION_MATH,PARADOX,HISTORY,AI",
        "B|seed=42|SCIENCE,MATRICULATION_MATH,PARADOX,ASTRONOMY,PROGRAMMING,MATH,HISTORY,ENGLISH,AI,GENERAL_KNOWLEDGE,KIDS_ARITHMETIC",
        "B|seed=123|PROGRAMMING,MATH,ENGLISH,KIDS_ARITHMETIC,GENERAL_KNOWLEDGE,MATRICULATION_MATH,HISTORY,ASTRONOMY,PARADOX,AI,SCIENCE",
        "B|seed=-1|AI,PROGRAMMING,ENGLISH,ASTRONOMY,MATH,HISTORY,KIDS_ARITHMETIC,SCIENCE,GENERAL_KNOWLEDGE,MATRICULATION_MATH,PARADOX",
        "B|seed=1760000000000|HISTORY,MATRICULATION_MATH,PARADOX,PROGRAMMING,KIDS_ARITHMETIC,SCIENCE,ENGLISH,AI,GENERAL_KNOWLEDGE,ASTRONOMY,MATH",
        "C|he|0|PROGRAMMING|programming_004|L2|c=3",
        "C|he|1|MATH|math_058|L3|c=1",
        "C|he|2|ENGLISH|words_people_c-10|L3|c=3",
        "C|he|3|KIDS_ARITHMETIC|arith_09_002|L9|c=3",
        "C|he|4|GENERAL_KNOWLEDGE|general_knowledge_006|L2|c=1",
        "C|he|5|MATRICULATION_MATH|bagrut_051|L3|c=0",
        "C|he|6|HISTORY|history_001|L2|c=2",
        "C|he|7|ASTRONOMY|astronomy_008|L2|c=0",
        "C|he|8|PARADOX|paradoxes_002|L2|c=2",
        "C|he|9|AI|artificial_intelligence_007|L2|c=0",
        "C|he|10|SCIENCE|science_003|L2|c=2",
        "C|he|11|PROGRAMMING|programming_008|L2|c=3",
        "C|he|12|MATH|math_049|L3|c=2",
        "C|he|13|ENGLISH|words_animals_c-6|L3|c=2",
        "C|he|14|KIDS_ARITHMETIC|arith_09_024|L9|c=2",
        "C|he|15|GENERAL_KNOWLEDGE|general_knowledge_008|L2|c=3",
        "C|he|16|MATRICULATION_MATH|bagrut_050|L3|c=2",
        "C|he|17|HISTORY|history_010|L2|c=1",
        "C|he|18|ASTRONOMY|astronomy_012|L2|c=2",
        "C|he|19|PARADOX|paradoxes_001|L2|c=3",
        "C|he|20|AI|artificial_intelligence_011|L2|c=2",
        "C|he|21|SCIENCE|science_002|L2|c=0",
        "C|en|0|PROGRAMMING|programming_004|L2|c=3",
        "C|en|1|MATH|math_058|L3|c=1",
        "C|en|2|ENGLISH|english_en_011|L3|c=1",
        "C|en|3|KIDS_ARITHMETIC|arith_09_029|L9|c=1",
        "C|en|4|GENERAL_KNOWLEDGE|general_knowledge_014|L2|c=2",
        "C|en|5|MATRICULATION_MATH|bagrut_050|L3|c=2",
        "C|en|6|HISTORY|history_010|L2|c=1",
        "C|en|7|ASTRONOMY|astronomy_012|L2|c=2",
        "C|en|8|PARADOX|paradoxes_001|L2|c=3",
        "C|en|9|AI|artificial_intelligence_003|L2|c=1",
        "C|en|10|SCIENCE|science_003|L2|c=2",
        "C|en|11|PROGRAMMING|programming_008|L2|c=3",
        "C|en|12|MATH|math_052|L3|c=3",
        "C|en|13|ENGLISH|english_en_009|L3|c=3",
        "C|en|14|KIDS_ARITHMETIC|arith_09_028|L9|c=3",
        "C|en|15|GENERAL_KNOWLEDGE|general_knowledge_011|L2|c=3",
        "C|en|16|MATRICULATION_MATH|bagrut_051|L3|c=0",
        "C|en|17|HISTORY|history_001|L2|c=2",
        "C|en|18|ASTRONOMY|astronomy_008|L2|c=0",
        "C|en|19|PARADOX|paradoxes_002|L2|c=2",
        "C|en|20|AI|artificial_intelligence_007|L2|c=0",
        "C|en|21|SCIENCE|science_013|L2|c=3",
        "D|0|words_verbs_c-16|L3|איך אומרים באנגלית: לענות?|Answer|Pharmacist|Brother-in-law|Toward|c=0|expl=''",
        "D|1|words_people_c-4|L3|איך אומרים באנגלית: בן דוד?|Blanket|Decide|Kangaroo|Cousin|c=3|expl=''",
        "D|2|words_food_c-13|L3|איך אומרים באנגלית: מרק עוף?|Leek|In front of|Chicken soup|United Kingdom|c=2|expl=''",
        "D|3|words_verbs_c-15|L3|איך אומרים באנגלית: לבחור?|Lilac|Choose|Through|Mandarin|c=1|expl=''",
        "D|4|words_sentences_c-5|L3|איך אומרים באנגלית: הצבע על?|Siblings|Pyramid|Cereal|Point to|c=3|expl=''",
        "D|5|words_time_c-19|L3|איך אומרים באנגלית: אלף?|Fridge|Millennium|Baby girl|Four hundred|c=1|expl=''",
        "D|6|words_tech_c-4|L3|איך אומרים באנגלית: מיקרוגל?|Along|Hindi|Microwave|Classroom|c=2|expl=''",
        "D|7|words_verbs_c-19|L3|איך אומרים באנגלית: לסיים?|Show|Norway|Pupil|Finish|c=3|expl=''",
        "D|8|words_numbers_c-8|L3|איך אומרים באנגלית: חצי?|Uncle|Half|Thirty|Mac and cheese|c=1|expl=''",
        "D|9|words_food_c-14|L3|איך אומרים באנגלית: בייגלה?|Pretzel|Trumpet|Pentagon|Future|c=0|expl=''",
        "D|10|words_food_c-7|L3|איך אומרים באנגלית: חביתה?|Hamburger|Scrambled eggs|Emotion|Downhill|c=1|expl=''",
        "D|11|words_fruits_c-2|L3|איך אומרים באנגלית: תאנה?|Shelf|Towel|Across|Fig|c=3|expl=''",
        "D|12|words_fruits_c-4|L3|איך אומרים באנגלית: אננס?|Korean|Eggplant|Pineapple|Point to|c=2|expl=''",
        "D|13|words_home_c-5|L3|איך אומרים באנגלית: אמבטיה?|Blanket|Stew|On the bed|Bathtub|c=3|expl=''",
        "D|14|words_tech_c-4|L3|איך אומרים באנגלית: מיקרוגל?|Quarter|In front of|Microwave|Goodbye|c=2|expl=''",
        "D|15|words_home_c-3|L3|איך אומרים באנגלית: כיריים?|Stove|Write|Folder|Ivory|c=0|expl=''",
        "D|16|words_countries_c-7|L3|איך אומרים באנגלית: הונגריה?|Drone|Trumpet|Mandarin|Hungary|c=3|expl=''",
        "D|17|words_verbs_c-10|L3|איך אומרים באנגלית: לתפוס?|Catch|Choose|Cork|Ketchup|c=0|expl=''",
        "D|18|words_vegetables_c-4|L3|איך אומרים באנגלית: כרישה?|Leek|Drone|Arabic|Kangaroo|c=0|expl=''",
        "D|19|words_verbs_c-2|L3|איך אומרים באנגלית: לכתוב?|Ketchup|Violet|Write|Clementine|c=2|expl=''",
        "E|0|arith_09_009|askedL9|right|prefs:ARITHMETIC_cal=1,ARITHMETIC_level=10,adaptive_intro_shown=true",
        "E|1|arith_10_023|askedL10|right|prefs:ARITHMETIC_cal=2,ARITHMETIC_level=11,adaptive_intro_shown=true",
        "E|2|arith_11_023|askedL11|right|prefs:ARITHMETIC_cal=3,ARITHMETIC_level=12,adaptive_intro_shown=true",
        "E|3|arith_12_003|askedL12|right|prefs:ARITHMETIC_cal=4,ARITHMETIC_level=13,adaptive_intro_shown=true",
        "E|4|arith_13_002|askedL13|right|prefs:ARITHMETIC_cal=5,ARITHMETIC_level=14,adaptive_intro_shown=true",
        "E|5|arith_14_009|askedL14|right|prefs:ARITHMETIC_cal=6,ARITHMETIC_level=15,adaptive_intro_shown=true",
        "E|6|arith_15_010|askedL15|right|prefs:ARITHMETIC_cal=7,ARITHMETIC_level=16,adaptive_intro_shown=true",
        "E|7|arith_16_017|askedL16|right|prefs:ARITHMETIC_cal=8,ARITHMETIC_level=17,adaptive_intro_shown=true",
        "E|8|arith_17_007|askedL17|right|prefs:ARITHMETIC_cal=8,ARITHMETIC_level=17,adaptive_intro_shown=true",
        "E|9|arith_17_029|askedL17|right|prefs:ARITHMETIC_cal=8,ARITHMETIC_level=17,adaptive_intro_shown=true",
        "E|10|arith_17_005|askedL17|wrong|prefs:ARITHMETIC_cal=8,ARITHMETIC_level=17,adaptive_intro_shown=true",
        "E|11|arith_17_011|askedL17|wrong|prefs:ARITHMETIC_cal=8,ARITHMETIC_level=17,adaptive_intro_shown=true",
        "E|12|arith_17_023|askedL17|wrong|prefs:ARITHMETIC_cal=8,ARITHMETIC_level=16,adaptive_intro_shown=true",
        "E|13|arith_16_029|askedL16|wrong|prefs:ARITHMETIC_cal=8,ARITHMETIC_level=16,adaptive_intro_shown=true",
        "E|14|arith_16_020|askedL16|wrong|prefs:ARITHMETIC_cal=8,ARITHMETIC_level=16,adaptive_intro_shown=true",
        "E|15|arith_16_011|askedL16|wrong|prefs:ARITHMETIC_cal=8,ARITHMETIC_level=16,adaptive_intro_shown=true",
        "E|new-session|first=arith_16_009|askedL16|currentLevel=16",
        "F|0|math_051|askedL3|right@1000|prefs:MATHEMATICS_cal=1,MATHEMATICS_level=4,adaptive_intro_shown=true",
        "F|1|math_078|askedL4|right@1000|prefs:MATHEMATICS_cal=2,MATHEMATICS_level=5,adaptive_intro_shown=true",
        "F|2|math_100|askedL5|right@1000|prefs:MATHEMATICS_cal=3,MATHEMATICS_level=5,adaptive_intro_shown=true",
        "F|3|math_118|askedL5|right@1000|prefs:MATHEMATICS_cal=4,MATHEMATICS_level=5,adaptive_intro_shown=true",
        "F|4|math_101|askedL5|right@1000|prefs:MATHEMATICS_cal=5,MATHEMATICS_level=5,adaptive_intro_shown=true",
        "F|5|math_119|askedL5|right@1000|prefs:MATHEMATICS_cal=6,MATHEMATICS_level=5,adaptive_intro_shown=true",
        "F|6|math_111|askedL5|right@1000|prefs:MATHEMATICS_cal=7,MATHEMATICS_level=5,adaptive_intro_shown=true",
        "F|7|math_115|askedL5|right@1000|prefs:MATHEMATICS_cal=8,MATHEMATICS_level=5,adaptive_intro_shown=true",
        "F|8|math_109|askedL5|right@9000|prefs:MATHEMATICS_cal=8,MATHEMATICS_level=5,adaptive_intro_shown=true",
        "F|9|math_117|askedL5|right@9000|prefs:MATHEMATICS_cal=8,MATHEMATICS_level=5,adaptive_intro_shown=true",
        "F|10|math_106|askedL5|right@9000|prefs:MATHEMATICS_cal=8,MATHEMATICS_level=5,adaptive_intro_shown=true",
        "F|11|math_107|askedL5|right@9000|prefs:MATHEMATICS_cal=8,MATHEMATICS_level=5,adaptive_intro_shown=true",
        "F|12|math_110|askedL5|right@9000|prefs:MATHEMATICS_cal=8,MATHEMATICS_level=5,adaptive_intro_shown=true",
        "F|13|math_098|askedL5|right@1000|prefs:MATHEMATICS_cal=8,MATHEMATICS_level=5,adaptive_intro_shown=true",
        "F|14|math_114|askedL5|right@1000|prefs:MATHEMATICS_cal=8,MATHEMATICS_level=5,adaptive_intro_shown=true",
        "F|15|math_100|askedL5|right@1000|prefs:MATHEMATICS_cal=8,MATHEMATICS_level=5,adaptive_intro_shown=true",
        "F|16|math_103|askedL5|right@1000|prefs:MATHEMATICS_cal=8,MATHEMATICS_level=5,adaptive_intro_shown=true",
        "F|17|math_099|askedL5|right@1000|prefs:MATHEMATICS_cal=8,MATHEMATICS_level=5,adaptive_intro_shown=true",
        "F|18|math_116|askedL5|wrong@1000|prefs:MATHEMATICS_cal=8,MATHEMATICS_level=5,adaptive_intro_shown=true",
        "F|19|math_104|askedL5|wrong@1000|prefs:MATHEMATICS_cal=8,MATHEMATICS_level=5,adaptive_intro_shown=true",
        "F|20|math_111|askedL5|wrong@1000|prefs:MATHEMATICS_cal=8,MATHEMATICS_level=4,adaptive_intro_shown=true",
        "F|21|math_079|askedL4|wrong@1000|prefs:MATHEMATICS_cal=8,MATHEMATICS_level=4,adaptive_intro_shown=true",
        "F|22|math_083|askedL4|wrong@1000|prefs:MATHEMATICS_cal=8,MATHEMATICS_level=4,adaptive_intro_shown=true",
        "H|AI-no-answers|1|1758086281660|artificial_intelligence_008|L2|prefs:adaptive_intro_shown=true",
        "H|AI-no-answers|2|1756444636023|artificial_intelligence_007|L2|prefs:adaptive_intro_shown=true",
        "H|AI-no-answers|3|1752657734958|artificial_intelligence_001|L2|prefs:adaptive_intro_shown=true",
        "H|AI-no-answers|4|1768200152801|artificial_intelligence_011|L2|prefs:adaptive_intro_shown=true",
        "H|AI-no-answers|5|1764681687192|artificial_intelligence_003|L2|prefs:adaptive_intro_shown=true",
        "H|AI-no-answers|6|1763040041555|artificial_intelligence_003|L2|prefs:adaptive_intro_shown=true",
        "H|AI-no-answers|7|1776433009674|artificial_intelligence_007|L2|prefs:adaptive_intro_shown=true",
        "H|AI-no-answers|8|1774787694029|artificial_intelligence_011|L2|prefs:adaptive_intro_shown=true",
        "H|AI-no-answers|9|1770732357508|artificial_intelligence_007|L2|prefs:adaptive_intro_shown=true",
        "H|MATH-answered-right|1|1758086281648|math_058|L3|prefs:MATHEMATICS_cal=1,MATHEMATICS_level=4,adaptive_intro_shown=true",
        "H|MATH-answered-right|2|1756444636027|math_093|L4|prefs:MATHEMATICS_cal=2,MATHEMATICS_level=5,adaptive_intro_shown=true",
        "H|MATH-answered-right|3|1752657734946|math_098|L5|prefs:MATHEMATICS_cal=3,MATHEMATICS_level=5,adaptive_intro_shown=true",
        "H|MATH-answered-right|4|1768200152813|math_119|L5|prefs:MATHEMATICS_cal=4,MATHEMATICS_level=5,adaptive_intro_shown=true",
        "H|MATH-answered-right|5|1764681687188|math_108|L5|prefs:MATHEMATICS_cal=5,MATHEMATICS_level=5,adaptive_intro_shown=true",
        "H|MATH-answered-right|6|1763040041567|math_107|L5|prefs:MATHEMATICS_cal=6,MATHEMATICS_level=5,adaptive_intro_shown=true",
        "H|MATH-answered-right|7|1776433009670|math_101|L5|prefs:MATHEMATICS_cal=7,MATHEMATICS_level=5,adaptive_intro_shown=true",
        "H|MATH-answered-right|8|1774787694017|math_114|L5|prefs:MATHEMATICS_cal=8,MATHEMATICS_level=5,adaptive_intro_shown=true",
        "H|MATH-answered-right|9|1770732357512|math_106|L5|prefs:MATHEMATICS_cal=8,MATHEMATICS_level=5,adaptive_intro_shown=true",
        "G|0|true|2000|L10|cal=1|recent=|prev=9|changed=true",
        "G|1|true|2000|L11|cal=2|recent=|prev=10|changed=true",
        "G|2|true|2000|L13|cal=3|recent=|prev=11|changed=true",
        "G|3|false|-1|L12|cal=4|recent=|prev=13|changed=true",
        "G|4|true|9000|L13|cal=5|recent=|prev=12|changed=true",
        "G|5|true|3000|L15|cal=6|recent=|prev=13|changed=true",
        "G|6|true|-1|L16|cal=7|recent=|prev=15|changed=true",
        "G|7|false|-1|L15|cal=8|recent=|prev=16|changed=true",
        "G|8|true|-1|L15|cal=8|recent=1|prev=15|changed=false",
        "G|9|true|-1|L15|cal=8|recent=11|prev=15|changed=false",
        "G|10|true|-1|L15|cal=8|recent=111|prev=15|changed=false",
        "G|11|true|-1|L15|cal=8|recent=1111|prev=15|changed=false",
        "G|12|false|-1|L16|cal=8|recent=|prev=15|changed=true",
        "G|13|true|-1|L16|cal=8|recent=1|prev=16|changed=false",
        "G|14|true|20000|L16|cal=8|recent=11|prev=16|changed=false",
        "G|15|true|20000|L16|cal=8|recent=111|prev=16|changed=false",
        "G|16|true|20000|L16|cal=8|recent=1111|prev=16|changed=false",
        "G|17|true|20000|L16|cal=8|recent=11111|prev=16|changed=false",
        "G|18|false|-1|L16|cal=8|recent=11110|prev=16|changed=false",
        "G|19|false|-1|L16|cal=8|recent=11100|prev=16|changed=false",
        "G|20|false|-1|L15|cal=8|recent=|prev=16|changed=true",
        "G|21|true|-1|L15|cal=8|recent=1|prev=15|changed=false",
        "G|22|true|-1|L15|cal=8|recent=11|prev=15|changed=false",
        "G2|middle|9|2|2|3|2|5",
        "G2|clampHigh|5|5|DifficultyState(level=5, calibrationAnswers=1, recentAnswers=[])|false",
        "G2|clampLowStable|1|1|DifficultyState(level=1, calibrationAnswers=8, recentAnswers=[AnswerPerformance(correct=false, responseTimeMs=-1), AnswerPerformance(correct=false, responseTimeMs=-1), AnswerPerformance(correct=false, responseTimeMs=-1), AnswerPerformance(correct=true, responseTimeMs=-1), AnswerPerformance(correct=false, responseTimeMs=-1)])|false",
        "G2|fast@L5|3840|7",
        "G2|fast@L5|3841|6",
        "G2|fast@L5|0|7",
        "G2|fast@L5|-1|6",
        "G2|comfort@L3|7400,7400,7400,7400,7400|4",
        "G2|comfort@L3|7401,7400,7400,7400,7400|3",
        "G2|comfort@L3|-1,-1,-1,-1,99999|3",
        "G2|comfort@L3|-1,14800,0,-1,-1|4",
        "G2|custom|true|100|3|1|0",
        "G2|custom|true|100|4|2|0",
        "G2|custom|true|-1|4|2|1",
        "G2|custom|false|-1|4|2|2",
        "G2|custom|true|-1|3|2|0",
        "G2|custom|false|-1|3|2|1",
        "G2|custom|false|-1|3|2|2",
        "G2|custom|false|-1|2|2|0",
        "NORM|null=en;=en;0020=en;0068.0065=he;0048.0045=he;0069.0077=he;0049.0057.002d.0069.006c=he;0068.0065.005f.0049.004c=he;0065.006e.002d.0055.0053=en;0066.0072=en;0061.0072=ar;0065.0073.002d.0034.0031.0039=es;0068.0069.005f.0049.004e=hi;0020.0068.0065.0020=he;0078.002d.0068.0065=en;002d.0068.0065=en;005f.0065.006e=en;0070.0074.005f.0042.0052=en;007a.0068.002d.0048.0061.006e.0074.002d.0054.0057=en;00a0.0068.0065=he;0068.0065.2003=he",
        "WORDID|fruits_a-1--419020314|directions_a-1-1166783243|x-3-0",
        "WORDVALUE|null|Dog|Dog|Dog|Dog|Dog|null|Dog",
        "WORDS|entries=835|first=WordEntry(values={ar=تفاحة, en=Apple, es=manzana, he=תפוח}, group=fruits_a, level=1, id=fruits_a-0)|last=WordEntry(values={ar=ما اسمك؟, en=What is your name?, es=¿cómo te llamas?, he=מה השם שלך?}, group=sentences_d, level=4, id=sentences_d-4)",
        "WORDS_LEVELS|L1=184,L2=189,L3=250,L4=136,L5=76",
        "WORDS_GROUPS|90",
        "WORDS_KEYS|{ar=835, en=835, es=835, he=835}",
        "WORDS_SAMPLE|WordEntry(values={ar=منقلة, en=Protractor, es=transportador, he=מד זווית}, group=school_c, level=3, id=school_c-4)|WordEntry(values={ar=كرة, en=Sphere, es=esfera, he=כדור}, group=shapes_c, level=3, id=shapes_c-4)|WordEntry(values={ar=ما اسمك؟, en=What is your name?, es=¿cómo te llamas?, he=מה השם שלך?}, group=sentences_d, level=4, id=sentences_d-4)",
        "WGEN|seed=1|level=1|first=words_colors_a-1/Board/Left/Circle/Blue/3|last=words_numbers_a-8|sha=5c44039bcb501f8d11e31605b2c258b934a8e1e8affb9ce3c3ca11eff7861614|nextInt=-1096383825",
        "WGEN|seed=1|level=3|first=words_expressions_c-5/Maroon/Stove/Hamburger/Island/3|last=words_directions_c-11|sha=5aa0a054f16ca61e120196ffb174eeb1120a9bd8870f9419f9fb5b92d2c3cf02|nextInt=-1096383825",
        "WGEN|seed=1|level=5|first=words_shapes_e-0/Librarian/Extension Cord/Metronome/Icosahedron/3|last=words_people_e-3|sha=7717b1c0dea077b95e0a2ea38b292a44de4cfe37265d880211b8d1104cf2e1c7|nextInt=2135837857",
        "WGEN|seed=1|level=0|first=words_colors_a-1/Board/Left/Circle/Blue/3|last=words_numbers_a-8|sha=5c44039bcb501f8d11e31605b2c258b934a8e1e8affb9ce3c3ca11eff7861614|nextInt=-1096383825",
        "WGEN|seed=1|level=9|first=words_shapes_e-0/Librarian/Extension Cord/Metronome/Icosahedron/3|last=words_people_e-3|sha=7717b1c0dea077b95e0a2ea38b292a44de4cfe37265d880211b8d1104cf2e1c7|nextInt=2135837857",
        "WGEN|seed=7|level=1|first=words_animals_a-4/Crown/Truck/Cow/Yes/2|last=words_animals_a-10|sha=00f2f4b36734372cacefd885a0df48044eeb070b9ccbb8da579d81ab0e61e053|nextInt=-2131873332",
        "WGEN|seed=7|level=3|first=words_jobs_c-14/South/Remember/Programmer/Watermelon/2|last=words_food_c-8|sha=5e00687bc9f19bd2ee131888668a20f3567d53ed28f826185a2bac62b259bd9e|nextInt=800507044",
        "WGEN|seed=7|level=5|first=words_numbers_e-5/Spectroscope/Planisphere/Decillion/Counterclockwise/2|last=words_fruits_e-9|sha=14d86f6a7c76867024223c0cb33eb7c736977bfdfdce7f7c68ae88d10efd9e9d|nextInt=643014067",
        "WGEN|seed=7|level=0|first=words_animals_a-4/Crown/Truck/Cow/Yes/2|last=words_animals_a-10|sha=00f2f4b36734372cacefd885a0df48044eeb070b9ccbb8da579d81ab0e61e053|nextInt=-2131873332",
        "WGEN|seed=7|level=9|first=words_numbers_e-5/Spectroscope/Planisphere/Decillion/Counterclockwise/2|last=words_fruits_e-9|sha=14d86f6a7c76867024223c0cb33eb7c736977bfdfdce7f7c68ae88d10efd9e9d|nextInt=643014067",
        "WGEN|seed=123|level=1|first=words_expressions_a-8/Big/Please/Prince/Kiwi/0|last=words_home_a-0|sha=139de412cf4638d0b33b0faba272513554e6bd666930666e32d6c48761c8bacf|nextInt=-1325936862",
        "WGEN|seed=123|level=3|first=words_verbs_c-16/Answer/Pharmacist/Brother-in-law/Toward/0|last=words_time_c-18|sha=f0b206d8be86884b60bac1c7e1ed87f3072b131b4bd0660bca6887763aa6d96d|nextInt=1864888634",
        "WGEN|seed=123|level=5|first=words_fruits_e-2/Loquat/Physicist/Periscope/Icosahedron/0|last=words_other_e-5|sha=caf9eba27823c75c6c124bb31c07bf3fc7d125fb0c6b0a738457820e7555eeee|nextInt=-1325936862",
        "WGEN|seed=123|level=0|first=words_expressions_a-8/Big/Please/Prince/Kiwi/0|last=words_home_a-0|sha=139de412cf4638d0b33b0faba272513554e6bd666930666e32d6c48761c8bacf|nextInt=-1325936862",
        "WGEN|seed=123|level=9|first=words_fruits_e-2/Loquat/Physicist/Periscope/Icosahedron/0|last=words_other_e-5|sha=caf9eba27823c75c6c124bb31c07bf3fc7d125fb0c6b0a738457820e7555eeee|nextInt=-1325936862",
        "WGEN|seed=-99|level=1|first=words_verbs_a-7/Play/Cup/Pepper/Cookie/0|last=words_time_a-3|sha=4b763de7e0521540d73835d94cf9fa0fd1c976da1e542bbf173796f44b5b5a3e|nextInt=1710336246",
        "WGEN|seed=-99|level=3|first=words_verbs_c-12/Wash/Arabic/Point to/Dolphin/0|last=words_directions_c-2|sha=d6d911cad81c184972dc1a728db3f41222e32f76c6c4d414df7b808c0a8c2c3d|nextInt=506621297",
        "WGEN|seed=-99|level=5|first=words_vegetables_e-0/Watercress/Tahini/Salak/Loquat/0|last=words_home_e-0|sha=3dbebfc520ad333216d5b9ef366a123ecd6f13b07cede2b0c3206e1eaa99956b|nextInt=1068045040",
        "WGEN|seed=-99|level=0|first=words_verbs_a-7/Play/Cup/Pepper/Cookie/0|last=words_time_a-3|sha=4b763de7e0521540d73835d94cf9fa0fd1c976da1e542bbf173796f44b5b5a3e|nextInt=1710336246",
        "WGEN|seed=-99|level=9|first=words_vegetables_e-0/Watercress/Tahini/Salak/Loquat/0|last=words_home_e-0|sha=3dbebfc520ad333216d5b9ef366a123ecd6f13b07cede2b0c3206e1eaa99956b|nextInt=1068045040",
        "WGEN_SRC|ar|words_colors_b-4|كيف نقول بالإنجليزية: أزرق داكن؟|ar|Better/Cucumber/Globe/Dark Blue|3|nextInt=-1300293752",
        "WGEN_SRC|es|words_colors_b-4|¿Cómo se dice en inglés: azul oscuro?|es|Better/Cucumber/Globe/Dark Blue|3|nextInt=-1300293752",
        "WGEN_SRC|hi|ERR IllegalArgumentException: English learning needs four usable source-to-target entries with distinct answers",
        "WGEN_SRC|fr|ERR IllegalArgumentException: English learning needs a non-English source language",
        "WGEN_SRC|iw|words_colors_b-4|איך אומרים באנגלית: כחול כהה?|he|Better/Cucumber/Globe/Dark Blue|3|nextInt=-1300293752",
        "XGEN|seed=3|level=1|min=1|max=4|004,004,004,004,004,004,004,004,004,004,004,004,004,004,004,004|nextInt=-1783099817",
        "XGEN|seed=3|level=2|min=1|max=4|001,008,007,011,003,011,008,003,007,003,008,007,001,001,003,007|nextInt=-1783099817",
        "XGEN|seed=11|level=2|min=1|max=4|003,008,001,007,011,001,003,003,007,001,001,008,011,008,003,008|nextInt=944004739",
        "XGEN|seed=11|level=3|min=1|max=4|005,009,002,006,010,002,005,005,006,002,002,009,010,009,005,009|nextInt=944004739",
        "XGEN|seed=5|level=7|min=1|max=4|012,012,012,012,012,012,012,012,012,012,012,012,012,012,012,012|nextInt=-369745968",
        "XGEN|seed=5|level=-2|min=1|max=4|004,004,004,004,004,004,004,004,004,004,004,004,004,004,004,004|nextInt=-369745968",
        "XGEN_NEAR|min=1|max=6|2:b,2:a,2:a,2:a,3:d,3:c,3:c,5:e,5:d,5:c,5:e,2:b,6:e,6:e,1:a|nextInt=1967722084",
        "QENGINE|modes=GENERAL_KNOWLEDGE,HISTORY|states={GENERAL_KNOWLEDGE=DifficultyState(level=2, calibrationAnswers=0, recentAnswers=[]), HISTORY=DifficultyState(level=2, calibrationAnswers=0, recentAnswers=[])}|general_knowledge_001,general_knowledge_008,history_010,history_001,general_knowledge_014,general_knowledge_010,general_knowledge_006,general_knowledge_007",
        "QENGINE|mix|history_005,history_002,history_002,history_002,history_005|history_006,history_009,history_008|general_knowledge_003|nextInt=-1112063386",
        "QENGINE|record|history_002|DifficultyResult(previousLevel=2, newLevel=3, state=DifficultyState(level=3, calibrationAnswers=1, recentAnswers=[]), levelChanged=true)|DifficultyState(level=3, calibrationAnswers=3, recentAnswers=[AnswerPerformance(correct=true, responseTimeMs=5)])|null",
        "QMIX|100|[ARITHMETIC]|[SCIENCE]|0",
        "BANK|arithmetic.xml|he=439|en=439|sha256(he)=fee9734936c0daa9e6a89693536f18eb4a57ce95ac500b69e8ccfce295db7a4d|sha256(en)=45459f7fa41267b713b7a3ec4a332344d60fd1547d642c2b0ca91a0373b1a4b8|sha256(he-file,en-pref)=fee9734936c0daa9e6a89693536f18eb4a57ce95ac500b69e8ccfce295db7a4d",
        "BANK|artificial_intelligence.xml|he=12|en=12|sha256(he)=5b8aaa82c7cc12c993f0a925711f7c16947f260b31f693e66ffc30686b724faa|sha256(en)=6afc4e352ec5fd6a73e996e91e6179b25b66d565d14c911a3171d77e2e6c5ed3|sha256(he-file,en-pref)=5b8aaa82c7cc12c993f0a925711f7c16947f260b31f693e66ffc30686b724faa",
        "BANK|astronomy.xml|he=12|en=12|sha256(he)=291ea33f689409902abfb2a484fa5f2331c2bd4f546d4159e9d8d59cb0e41c6b|sha256(en)=bb43024575943bb9bcc8b2029560554f72faffdc96a7b36a740c98a729f92c6a|sha256(he-file,en-pref)=291ea33f689409902abfb2a484fa5f2331c2bd4f546d4159e9d8d59cb0e41c6b",
        "BANK|bagrut_mathematics.xml|he=64|en=64|sha256(he)=6b3aaa84ce4d49c1d18da22b02d877b40653e4c7dfec15aa9aa99ed131b9f3b5|sha256(en)=09c7d942b9a608c32cd8c3404608615fd0c9a056205bd5050871f83f9dc558e7|sha256(he-file,en-pref)=6b3aaa84ce4d49c1d18da22b02d877b40653e4c7dfec15aa9aa99ed131b9f3b5",
        "BANK|general_knowledge.xml|he=20|en=20|sha256(he)=305a9ea1d6913dbb286b3d1edd1a9d0202600414729d37973146aa6b1d9b0d24|sha256(en)=ad96c9b31c691dad703eed3b12fcee27c1203b7fd3e2f088b490774a11687623|sha256(he-file,en-pref)=305a9ea1d6913dbb286b3d1edd1a9d0202600414729d37973146aa6b1d9b0d24",
        "BANK|history.xml|he=10|en=10|sha256(he)=0e406a30d1354cf69fb16f4d0931e55f1047019b5dd2a228f2ab339a8ff701b0|sha256(en)=b66bd00cb9b1694e1544ab0268c66af7fa7419bb7e3ec52655451e85e9486792|sha256(he-file,en-pref)=0e406a30d1354cf69fb16f4d0931e55f1047019b5dd2a228f2ab339a8ff701b0",
        "BANK|mathematics.xml|he=117|en=117|sha256(he)=d138219704d48181081622a6b70c44ceab0c597ecbe934bb5093ad58a31cbf79|sha256(en)=802cfc70d83d3c7131201ae7fa11edc32e11bceeb8cbd4a5b58485fb42050449|sha256(he-file,en-pref)=d138219704d48181081622a6b70c44ceab0c597ecbe934bb5093ad58a31cbf79",
        "BANK|paradoxes.xml|he=10|en=10|sha256(he)=ae3322130ad537844863f09e573edf046c4e6b6bca459bd705c003b951eda471|sha256(en)=b75feb004d12d93b9077f0cc5e9d52b12844ae58fe7428d293c167ea98db7b41|sha256(he-file,en-pref)=ae3322130ad537844863f09e573edf046c4e6b6bca459bd705c003b951eda471",
        "BANK|programming.xml|he=12|en=12|sha256(he)=ef9a488ddd95a371b8acb08e26952bb35956b9cfc309518803f1e9931492f753|sha256(en)=721228ce46d3d9ff43004349345f9ed67ea703b2fbf1d273d483a9bf48a80e56|sha256(he-file,en-pref)=ef9a488ddd95a371b8acb08e26952bb35956b9cfc309518803f1e9931492f753",
        "BANK|science.xml|he=15|en=15|sha256(he)=677a2a73f33d85f64c264324937a2421005b4114337c8fa88365aa7f00518d6e|sha256(en)=d1ecc6b7761837d3cc6ac142d8517f41b7dea368c92698c51a95969f0c1bf1ba|sha256(he-file,en-pref)=677a2a73f33d85f64c264324937a2421005b4114337c8fa88365aa7f00518d6e",
        "BANK|en/english.xml|en=20|sha256(en)=7a498a44cb9aa57a1f7e632f7bc48ce72e162a4a8100b0bb208733ccb8024548",
        "BANK_FIRST|Question(id=science_001, mode=SCIENCE, level=1, prompt=מהו התהליך שבו צמחים משתמשים באור כדי לייצר סוכרים?, answers=[תסיסה, אוסמוזה, פוטוסינתזה, נשימה תאית], correctAnswerIndex=2, explanation=בפוטוסינתזה אנרגיית אור מומרת לאנרגיה כימית., language=he, imageRef=null, tags=[], allowMultipleCorrectAnswers=false, correctAnswerIndices=[2])",
        "PARSE|ok-en|OK q1~HISTORY~2~[Hello]~[a]/[b]~0~[0]~[because]~he~null~[]~false",
        "PARSE|ok-he|OK q1~HISTORY~2~[שלום]~[a]/[b]~0~[0]~[because]~he~null~[]~false",
        "PARSE|ok-ar|OK q1~HISTORY~2~[Hello]~[a]/[b]~0~[0]~[because]~he~null~[]~false",
        "PARSE|ok-iw|OK q1~HISTORY~2~[שלום]~[a]/[b]~0~[0]~[because]~he~null~[]~false",
        "PARSE|doctype|ERR IllegalArgumentException: DOCTYPE is not allowed in question banks",
        "PARSE|doctype-lower|ERR IllegalArgumentException: DOCTYPE is not allowed in question banks",
        "PARSE|doctype-mixed-in-text|OK q~HISTORY~1~[x <!DocType y]~[a]/[b]~0~[0]~null~en~null~[]~false",
        "PARSE|empty-bank|OK ",
        "PARSE|no-mode|ERR IllegalArgumentException: question q1 has no mode",
        "PARSE|blank-mode-root|ERR IllegalArgumentException: question  q1  has no mode",
        "PARSE|question-mode|OK q1~HISTORY~1~[p]~[a]/[b]~0~[0]~null~en~null~[]~false",
        "PARSE|invalid-mode|ERR IllegalArgumentException: question q1 has invalid mode: MATH",
        "PARSE|blank-id|ERR IllegalArgumentException: question at index 1 has a blank id",
        "PARSE|dup-id|ERR IllegalArgumentException: Duplicate question id: q1",
        "PARSE|level[x]|ERR IllegalArgumentException: question q1 has invalid level: x",
        "PARSE|level[0]|ERR IllegalArgumentException: question q1 has invalid level: 0",
        "PARSE|level[-1]|ERR IllegalArgumentException: question q1 has invalid level: -1",
        "PARSE|level[ 3]|ERR IllegalArgumentException: question q1 has invalid level:  3",
        "PARSE|level[+3]|OK q1~HISTORY~3~[p]~[a]/[b]~0~[0]~null~en~null~[]~false",
        "PARSE|level[٣]|OK q1~HISTORY~3~[p]~[a]/[b]~0~[0]~null~en~null~[]~false",
        "PARSE|level[３]|OK q1~HISTORY~3~[p]~[a]/[b]~0~[0]~null~en~null~[]~false",
        "PARSE|level[2147483648]|ERR IllegalArgumentException: question q1 has invalid level: 2147483648",
        "PARSE|level[]|ERR IllegalArgumentException: question q1 has invalid level: ",
        "PARSE|level[1.0]|ERR IllegalArgumentException: question q1 has invalid level: 1.0",
        "PARSE|level[07]|OK q1~HISTORY~7~[p]~[a]/[b]~0~[0]~null~en~null~[]~false",
        "PARSE|no-prompt|ERR IllegalArgumentException: question q1 has no prompt",
        "PARSE|blank-answer|ERR IllegalArgumentException: question q1 has a blank answer",
        "PARSE|no-correct|ERR IllegalArgumentException: question q1 has no correct answer",
        "PARSE|multi-correct|ERR IllegalArgumentException: question q1 has multiple correct answers",
        "PARSE|multi-allowed|OK q1~HISTORY~1~[p]~[z]/[a]/[b]~1~[1, 2]~null~en~null~[]~true",
        "PARSE|quality100|OK q1~HISTORY~1~[p]~[z]/[a]/[b]~1~[1]~null~en~null~[]~false",
        "PARSE|dup-answers|ERR IllegalArgumentException: Answers must be unique",
        "PARSE|one-answer|ERR IllegalArgumentException: Question must contain at least 2 answers",
        "PARSE|attrs|OK q1~HISTORY~1~[p]~[a]/[b]~0~[0]~null~he~img.png~[b, a]~false ## q2~HISTORY~1~[p]~[a]/[b]~0~[0]~null~es~null~[]~false",
        "PARSE|lang-default-pref|OK q1~HISTORY~1~[p]~[a]/[b]~0~[0]~null~he~null~[]~false",
        "PARSE|localized-fallbacks|OK q1~HISTORY~1~[french-as-en]~[a]/[b]~0~[0]~[x]~he~null~[]~false",
        "PARSE|localized-blank-first|OK q1~HISTORY~1~[second]~[a]/[b]~0~[0]~null~he~null~[]~false",
        "PARSE|textcontent|OK q1~HISTORY~1~[Hello big  world & <x> א]~[a < b]/[bcd]~0~[0]~null~en~null~[]~false",
        "PARSE|nested-descendants|OK q1~HISTORY~1~[p]~[a]/[b]~0~[0]~null~en~null~[]~false ## q2~HISTORY~1~[p2]~[x]/[y]~1~[1]~null~en~null~[]~false",
        "PARSE|whitespace-trim|OK q1~HISTORY~1~[p]~[a]/[b]~0~[0]~null~en~null~[]~false",
        "R|lang=he|GENERAL_KNOWLEDGE|general_knowledge_011#3 general_knowledge_008#3 general_knowledge_010#2 general_knowledge_006#1 general_knowledge_001#2 general_knowledge_007#2 general_knowledge_014#2 general_knowledge_001#2 general_knowledge_001#2 general_knowledge_006#1|4096",
        "R|lang=he|PROGRAMMING|programming_004#3 programming_008#3 programming_011#0 programming_009#1 programming_004#3 programming_008#3 programming_011#0 programming_004#3 programming_009#1 programming_004#3|4096",
        "R|lang=he|SCIENCE|science_002#0 science_003#2 science_013#3 science_004#3 science_002#0 science_003#2 science_013#3 science_002#0 science_004#3 science_002#0|4096",
        "R|lang=he|ASTRONOMY|astronomy_012#2 astronomy_004#0 astronomy_008#0 astronomy_004#0 astronomy_004#0 astronomy_012#2 astronomy_004#0 astronomy_012#2 astronomy_004#0 astronomy_004#0|4096",
        "R|lang=he|PARADOX|paradoxes_005#3 paradoxes_001#3 paradoxes_002#2 paradoxes_001#3 paradoxes_001#3 paradoxes_005#3 paradoxes_001#3 paradoxes_005#3 paradoxes_001#3 paradoxes_001#3|4096",
        "R|lang=he|AI|artificial_intelligence_003#1 artificial_intelligence_007#0 artificial_intelligence_008#2 artificial_intelligence_001#3 artificial_intelligence_011#2 artificial_intelligence_003#1 artificial_intelligence_001#3 artificial_intelligence_007#0 artificial_intelligence_011#2 artificial_intelligence_003#1|4096",
        "R|lang=he|HISTORY|history_001#2 history_002#0 history_010#1 history_005#1 history_001#2 history_002#0 history_010#1 history_001#2 history_005#1 history_001#2|4096",
        "R|lang=he|ENGLISH|words_verbs_c-16#0 words_people_c-4#3 words_food_c-13#2 words_verbs_c-15#1 words_sentences_c-5#3 words_time_c-19#1 words_tech_c-4#2 words_verbs_c-19#3 words_numbers_c-8#1 words_food_c-14#0|4096",
        "R|lang=he|KIDS_ARITHMETIC|arith_09_007#2 arith_09_011#3 arith_09_001#0 arith_09_025#2 arith_09_009#3 arith_09_026#1 arith_09_017#3 arith_09_004#1 arith_09_029#1 arith_09_002#3|4096",
        "R|lang=he|MATH|math_063#2 math_058#1 math_062#3 math_055#1 math_057#3 math_072#3 math_066#1 math_052#3 math_061#2 math_059#3|4096",
        "R|lang=he|MATRICULATION_MATH|bagrut_050#2 bagrut_051#0 bagrut_052#2 bagrut_049#2 bagrut_058#0 bagrut_050#2 bagrut_049#2 bagrut_051#0 bagrut_058#0 bagrut_050#2|4096",
        "R|lang=en|GENERAL_KNOWLEDGE|general_knowledge_011#3 general_knowledge_008#3 general_knowledge_010#2 general_knowledge_006#1 general_knowledge_001#2 general_knowledge_007#2 general_knowledge_014#2 general_knowledge_001#2 general_knowledge_001#2 general_knowledge_006#1|4096",
        "R|lang=en|PROGRAMMING|programming_004#3 programming_008#3 programming_011#0 programming_009#1 programming_004#3 programming_008#3 programming_011#0 programming_004#3 programming_009#1 programming_004#3|4096",
        "R|lang=en|SCIENCE|science_002#0 science_003#2 science_013#3 science_004#3 science_002#0 science_003#2 science_013#3 science_002#0 science_004#3 science_002#0|4096",
        "R|lang=en|ASTRONOMY|astronomy_012#2 astronomy_004#0 astronomy_008#0 astronomy_004#0 astronomy_004#0 astronomy_012#2 astronomy_004#0 astronomy_012#2 astronomy_004#0 astronomy_004#0|4096",
        "R|lang=en|PARADOX|paradoxes_005#3 paradoxes_001#3 paradoxes_002#2 paradoxes_001#3 paradoxes_001#3 paradoxes_005#3 paradoxes_001#3 paradoxes_005#3 paradoxes_001#3 paradoxes_001#3|4096",
        "R|lang=en|AI|artificial_intelligence_003#1 artificial_intelligence_007#0 artificial_intelligence_008#2 artificial_intelligence_001#3 artificial_intelligence_011#2 artificial_intelligence_003#1 artificial_intelligence_001#3 artificial_intelligence_007#0 artificial_intelligence_011#2 artificial_intelligence_003#1|4096",
        "R|lang=en|HISTORY|history_001#2 history_002#0 history_010#1 history_005#1 history_001#2 history_002#0 history_010#1 history_001#2 history_005#1 history_001#2|4096",
        "R|lang=en|ENGLISH|english_en_008#0 english_en_009#3 english_en_011#1 english_en_010#2 english_en_008#0 english_en_009#3 english_en_011#1 english_en_008#0 english_en_010#2 english_en_008#0|4096",
        "R|lang=en|KIDS_ARITHMETIC|arith_09_007#2 arith_09_011#3 arith_09_001#0 arith_09_025#2 arith_09_009#3 arith_09_026#1 arith_09_017#3 arith_09_004#1 arith_09_029#1 arith_09_002#3|4096",
        "R|lang=en|MATH|math_063#2 math_058#1 math_062#3 math_055#1 math_057#3 math_072#3 math_066#1 math_052#3 math_061#2 math_059#3|4096",
        "R|lang=en|MATRICULATION_MATH|bagrut_050#2 bagrut_051#0 bagrut_052#2 bagrut_049#2 bagrut_058#0 bagrut_050#2 bagrut_049#2 bagrut_051#0 bagrut_058#0 bagrut_050#2|4096",
        "S|out-of-order|7:KIDS_ARITHMETIC:arith_09_009,0:HISTORY:history_002,1:KIDS_ARITHMETIC:arith_09_006,7:KIDS_ARITHMETIC:arith_09_009,2:HISTORY:history_010,3:KIDS_ARITHMETIC:arith_09_002|getOrNull(-1)=null|getOrNull(4096)=null|size=4096",
        "S|set-order|KIDS_ARITHMETIC:arith_09_009,HISTORY:history_002,KIDS_ARITHMETIC:arith_09_006,HISTORY:history_010",
        "S|latest-session|arith_09_009|arith_09_009|s1[1]=arith_09_001/L9|s2[1]=arith_10_023/L10|prefs:ARITHMETIC_cal=1,ARITHMETIC_level=10,adaptive_intro_shown=true",
        "S|unknown-id|prefs:ARITHMETIC_cal=1,ARITHMETIC_level=10,adaptive_intro_shown=true",
        "S|out-of-range-answers|prefs:ARITHMETIC_cal=3,ARITHMETIC_level=8,adaptive_intro_shown=true",
        "S|currentLevel|GENERAL_KNOWLEDGE=2,PROGRAMMING=2,SCIENCE=2,ASTRONOMY=2,PARADOX=2,AI=2,HISTORY=2,ENGLISH=3,KIDS_ARITHMETIC=8,MATH=3,MATRICULATION_MATH=3",
        "S|restore-clamp|history_008/L3,science_013/L2,history_006/L3,science_002/L2,history_009/L3,science_003/L2|history=3|science=2",
        "S|restore-record|prefs:HISTORY_cal=8,HISTORY_level=3,SCIENCE_cal=1,SCIENCE_level=3,adaptive_intro_shown=true",
        "WSYN|WordEntry(values={en=Dog, he=כלב}, group=x_b, level=2, id=x_b-0) ## WordEntry(values={ar=قط, es=gato}, group=x_b, level=2, id=x_b-1) ## WordEntry(values={es=perro}, group=noUnderscore, level=1, id=noUnderscore-0) ## WordEntry(values={hi=कुत्ता}, group=y_Z, level=3, id=y_Z-0) ## WordEntry(values={en=Five}, group=a_b_e, level=5, id=a_b_e-0)"
    ]
}
