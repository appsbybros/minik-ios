import Foundation

// Port of data/AndroidQuestionBankParser.kt (TripleShotGame dd722e5). Spec 04 §4.3.
//
// The XML goes through AndroidKit AXmlDocument (org.w3c.dom semantics: getElementsByTagName = descendants in
// document order, textContent = all descendant text and CDATA without comments, getAttribute "" when missing).
// Kotlin `require(...)` / `throw IllegalArgumentException(...)` become a thrown QuestionsIllegalArgumentException
// (the unit test catches it; the repository does not, so a bad bank still crashes there).

/** Android adapter retaining the shared bank validation and locale contract. */
enum AndroidQuestionBankParser {
    static func parse(
        input: Data,
        preferredLanguage: String = "en",
        allowMultipleCorrectAnswers: Bool = false
    ) throws -> [Question] {
        let xml = String(decoding: input, as: UTF8.self)
        try QuestionsKotlin.require(!QuestionsKotlin.containsIgnoreCase(xml, "<!DOCTYPE"), "DOCTYPE is not allowed in question banks")
        // DocumentBuilderFactory with isExpandEntityReferences = false and an entity resolver that throws
        // "External entities are not allowed": with the DOCTYPE rejected above no entity can be declared, so only
        // the predefined and character references remain, which every DOM parser expands.
        let doc = try AXmlDocument.parse(Data(xml.utf8))
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
                languageCode: QuestionsKotlin.notBlank(element.getAttribute("language")) ?? defaultLanguage
            )
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

    /// The first `tag` descendant whose normalized `lang` is the wanted language, else the first one marked
    /// English (normalize maps unknown languages to "en"), else the first non-blank text.
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
