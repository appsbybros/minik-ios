import Foundation

/// Android `localization/AppText.kt` (MinikCrossPong 5c1aa4d; first ported from the working tree on 828c6fc, 2026-10-04): the
/// device-language catalog.
///
/// English and Hebrew stay at their call sites (`t(english, hebrew)`). Spanish, Arabic, Hindi and Dutch come from
/// `MPTextCatalog`, keyed by the exact English text; a key with `{0}`, `{1}`… matches a text that carries names or numbers and
/// puts them into the translation. A text the catalog does not know stays English. Stored names, nicknames and network values
/// never pass through it.
///
/// Language (Android `LocalizedActivity`): the primary device language, never a saved app preference: "iw" is Hebrew, a region
/// is ignored ("es-MX" is Spanish) and a language other than the six is English. Hebrew and Arabic are right to left.
enum MPText {
    /// Android `supported`.
    static let languages: Set<String> = ["en", "he", "es", "ar", "hi", "nl"]
    /// The translation columns of `MPTextCatalog.rows`, in order (Android `columns`).
    static let columns = ["es", "ar", "hi", "nl"]
    private static var current = normalize(deviceLanguage)
    /// The app language, one of `languages` (Android `AppText.language`).
    static var language: String { current }
    /// The primary device language (iOS lists a per-app language from the Settings app first).
    static var deviceLanguage: String { Locale.preferredLanguages.first ?? "en" }
    /// Hebrew and Arabic lay out right to left (Android `AppText.rtl`).
    static var rtl: Bool { current == "he" || current == "ar" }

    /// Android `AppText.normalize`: the language part of a tag ("es-MX", "hi_IN"), "iw" as Hebrew, English when unsupported.
    static func normalize(_ value: String) -> String {
        let code = String(value.prefix(while: { $0 != "-" && $0 != "_" })).lowercased()
        if code == "iw" { return "he" }
        return languages.contains(code) ? code : "en"
    }
    /// Android `AppText.configure`.
    static func configure(_ value: String) { current = normalize(value) }
    /// Android `LocalizedActivity.onCreate`: every screen starts from the device language.
    static func configureFromDevice() { configure(deviceLanguage) }

    /// Android `AppText.t(en)`: the Hebrew text defaults to the English one.
    static func t(_ en: String) -> String { t(en, en, current == "he") }
    /// Android `AppText.t(en, he, hebrew)`: `he` when `hebrew`; otherwise the catalog text of the app language (an exact key, a
    /// `{n}` template, the key without the caller's padding, or a " · " suffix); otherwise `en`.
    static func t(_ en: String, _ he: String, _ hebrew: Bool) -> String {
        if hebrew { return he }
        guard let column = columns.firstIndex(of: current) else { return en }
        if let row = table[en] { return row[column] }
        // Stage 5 (owner decision): an iOS-only translation of a text Android leaves in English (MPTextIOS), after Android's rows.
        if let row = iosTable[en] { return row[column] }
        for template in templates {
            if let filled = template.fill(en, column: column) { return filled }
        }
        for template in iosTemplates {
            if let filled = template.fill(en, column: column) { return filled }
        }
        // Preserve a caller's intentional padding when looking up a short label.
        let leading = en.prefix(while: { $0.isWhitespace })
        let rest = en.dropFirst(leading.count)
        let trailingCount = rest.reversed().prefix(while: { $0.isWhitespace }).count
        if !leading.isEmpty || trailingCount > 0, let row = table[String(rest.dropLast(trailingCount))] {
            return String(leading) + row[column] + String(rest.suffix(trailingCount))
        }
        let dot = " · "
        if en.hasPrefix(dot) { return dot + t(String(en.dropFirst(dot.count)), he, false) }
        return en
    }
    /// Android `res/values-<lang>/strings.xml` texts that differ from the catalog row of their English text, keyed by the English
    /// text and then by language. Android shows a resource string through `getString`, not `AppText`. Every other resource
    /// string has the same text as its catalog row, so `t` shows it (Scripts/audit-multi-pong.py checks this string by string).
    static let resourceTexts: [String: [String: String]] = [
        // R.string.new_match, the cross settings action (1908719 shortened the Dutch text so that Cancel stays visible).
        "Apply & start new match": ["nl": "Nieuw spel starten"],
    ]
    /// Android `res/values*/journey.xml` (5c1aa4d): resource strings that are not catalog rows, by English text and language.
    static let journeyTexts: [String: [String: String]] = [
        // R.string.guide_team_practice, the team action of the cross guide's team and scoring cards.
        "Learn team play": ["he": "תרגול קבוצתי", "ar": "تعلّم اللعب الجماعي", "es": "Aprender juego en equipo", "hi": "टीम खेल सीखें", "nl": "Leer samenspelen"],
    ]
    /// Android `getString` of a `journey.xml` string: its text in the app language, English otherwise.
    static func journey(_ en: String) -> String { journeyTexts[en]?[current] ?? en }
    /// Android `res/values*/issue_review.xml` (7254ab2): resource strings of the issue-report fixes, by English text and language.
    static let issueTexts: [String: [String: String]] = [
        // R.string.practice_without_limit: the Daily brief's endless action for a stage that is neither serving nor paint.
        "Practice without a limit": ["he": "אימון ללא הגבלה", "es": "Práctica sin límite", "ar": "تدريب بلا حدود", "hi": "बिना सीमा के अभ्यास", "nl": "Oefenen zonder limiet"],
        // R.string.serve_marked_court: the title of the serving stages.
        "Serve to the marked court": ["he": "מגישים לשולחן המסומן", "es": "Saca hacia la zona marcada", "ar": "أرسل إلى الجزء المحدد من الطاولة", "hi": "चिह्नित हिस्से की ओर सर्व करें", "nl": "Serveer naar het gemarkeerde tafelvak"],
        // R.string.tap_marked_court and R.string.watch_serve_land: the serving practice's instruction before and after the serve
        // (Android d376d64: "the highlighted side" in English; the other languages are unchanged).
        "Tap the highlighted side to serve": ["he": "הקישו על השולחן המודגש כדי להגיש", "es": "Toca la zona resaltada para sacar", "ar": "اضغط على الجزء المضيء للإرسال", "hi": "सर्व करने के लिए चमकते हिस्से पर टैप करें", "nl": "Tik op het gemarkeerde vak om te serveren"],
        "Watch where your serve lands": ["he": "שימו לב היכן ההגשה נוחתת", "es": "Observa dónde cae tu saque", "ar": "شاهد أين تسقط كرة الإرسال", "hi": "देखें कि आपकी सर्व कहाँ गिरती है", "nl": "Kijk waar je service landt"],
        // R.string.challenge_completed: a won daily practice.
        "Challenge completed!": ["he": "האתגר הושלם!", "es": "¡Reto completado!", "ar": "اكتمل التحدي!", "hi": "चुनौती पूरी हुई!", "nl": "Uitdaging voltooid!"],
        // R.string.control_beginner_only, control_standard_only, control_pro_only: only the selected control level is explained.
        "Beginner: move your paddle to the ball for an automatic return. Swipe left or right to choose a target.": ["he": "מתחילים: מזיזים את המחבט לכדור להחזרה אוטומטית. מחליקים שמאלה או ימינה כדי לבחור יעד.", "es": "Principiante: mueve la pala hacia la pelota para devolverla automáticamente. Desliza a izquierda o derecha para elegir un destino.", "ar": "مبتدئ: حرّك المضرب نحو الكرة لإعادتها تلقائيًا. اسحب لليسار أو اليمين لاختيار الهدف.", "hi": "शुरुआती: अपने आप रिटर्न करने के लिए पैडल को गेंद तक ले जाएँ। लक्ष्य चुनने के लिए बाएँ या दाएँ स्वाइप करें।", "nl": "Beginner: beweeg je batje naar de bal voor een automatische return. Veeg naar links of rechts om een doel te kiezen."],
        "Standard: move into position, then tap or swipe to return. Faster swipes add power.": ["he": "רגילה: נעים למקום, ואז מקישים או מחליקים כדי להחזיר. החלקה מהירה מוסיפה עוצמה.", "es": "Estándar: colócate y toca o desliza para devolver. Un deslizamiento más rápido añade potencia.", "ar": "عادي: تحرّك إلى المكان المناسب، ثم انقر أو اسحب لإعادة الكرة. السحب الأسرع يزيد القوة.", "hi": "सामान्य: सही जगह पर जाएँ, फिर रिटर्न करने के लिए टैप या स्वाइप करें। तेज़ स्वाइप से ताकत बढ़ती है।", "nl": "Standaard: ga op de juiste plek staan en tik of veeg om terug te slaan. Sneller vegen geeft meer kracht."],
        "Pro: use a well-timed swipe to control direction and power.": ["he": "מקצועני: מחליקים בתזמון מדויק כדי לשלוט בכיוון ובעוצמה.", "es": "Pro: desliza en el momento preciso para controlar la dirección y la potencia.", "ar": "محترف: اسحب في الوقت المناسب للتحكم في الاتجاه والقوة.", "hi": "प्रो: दिशा और ताकत नियंत्रित करने के लिए सही समय पर स्वाइप करें।", "nl": "Pro: veeg op het juiste moment om richting en kracht te bepalen."],
        // R.string.control_starter_only (Android b0cdeb3): the Starter level, the fourth control level.
        "Starter: move into reach, then tap or swipe to aim. You have a longer window to return the ball.": ["he": "נינוחה: נעים אל הכדור, ואז מקישים או מחליקים כדי לכוון. יש יותר זמן להחזיר את הכדור.", "es": "Relajado: acércate a la pelota y toca o desliza para apuntar. Tienes más tiempo para devolverla.", "ar": "مريح: اقترب من الكرة، ثم انقر أو اسحب للتصويب. لديك وقت أطول لإعادة الكرة.", "hi": "आरामदायक: गेंद की पहुँच में आएँ, फिर निशाना लगाने के लिए टैप या स्वाइप करें। गेंद लौटाने के लिए ज़्यादा समय मिलता है।", "nl": "Ontspannen: ga binnen bereik staan en tik of veeg om te richten. Je hebt langer de tijd om de bal terug te slaan."],
        // R.string.tap_opponent_side_to_serve (Android d376d64): the journey's serve tip outside the serving stages (team match, practices).
        "Tap an opponent’s side to serve": ["he": "הקישו על צד של יריב כדי להגיש", "es": "Toca el lado de un rival para sacar", "ar": "اضغط على جانب أحد المنافسين للإرسال", "hi": "सर्व करने के लिए किसी विरोधी की तरफ़ टैप करें", "nl": "Tik op de kant van een tegenstander om te serveren"],
        // R.string.optional_landscape_tip: the orientation tip, at most three times for the app's lifetime.
        "You can also play in landscape.": ["he": "אפשר לשחק גם במצב אופקי.", "es": "También puedes jugar en horizontal.", "ar": "يمكنك أيضًا اللعب بالوضع الأفقي.", "hi": "आप लैंडस्केप मोड में भी खेल सकते हैं।", "nl": "Je kunt ook in liggende stand spelen."],
    ]
    /// Android `getString` of an `issue_review.xml` string: its text in the app language, English otherwise.
    static func issue(_ en: String) -> String { issueTexts[en]?[current] ?? en }
    /// Android `getString(R.string.…)` for a resource string whose English text is a catalog key: the resource text of the app
    /// language when it differs from the catalog row (`resourceTexts`), otherwise `t(en, he, hebrew)`.
    static func resource(_ en: String, _ he: String, _ hebrew: Bool) -> String {
        if !hebrew, let text = resourceTexts[en]?[current] { return text }
        return t(en, he, hebrew)
    }
    /// Android `AppText.translated`: the catalog text of `key` in `lang` (nil for English, Hebrew or an unknown key).
    static func translated(_ key: String, _ lang: String) -> String? {
        guard let column = columns.firstIndex(of: normalize(lang)), let row = table[key] else { return nil }
        return row[column]
    }
    /// Android `AppText.keys`: every English key, in catalog order.
    static var keys: [String] { MPTextCatalog.rows.map { $0.0 } }

    private static let table: [String: [String]] = Dictionary(MPTextCatalog.rows, uniquingKeysWith: { _, last in last })
    private static let iosTable: [String: [String]] = Dictionary(MPTextIOS.rows.filter { !$0.0.contains("{0}") }, uniquingKeysWith: { _, last in last })
    private static let iosTemplates: [MPTextTemplate] = MPTextIOS.rows.filter { $0.0.contains("{0}") }.compactMap { MPTextTemplate(key: $0.0, values: $0.1) }
    /// Android `templates`: the keys with `{0}`, longest first (catalog order between keys of the same length).
    private static let templates: [MPTextTemplate] = {
        let indexed = MPTextCatalog.rows.enumerated().filter { $0.element.0.contains("{0}") }
        let ordered = indexed.sorted { a, b in
            let lengthA = a.element.0.utf16.count, lengthB = b.element.0.utf16.count
            if lengthA != lengthB { return lengthA > lengthB }
            return a.offset < b.offset
        }
        return ordered.compactMap { MPTextTemplate(key: $0.element.0, values: $0.element.1) }
    }()
}

/// One `{n}` key of the catalog as a whole-text pattern: every `{n}` matches any text (as short as possible) and
/// becomes the n-th captured value.
struct MPTextTemplate {
    let values: [String]
    private let pattern: NSRegularExpression
    private static let placeholder = try? NSRegularExpression(pattern: "\\{([0-9]+)\\}")

    init?(key: String, values: [String]) {
        guard let splitter = MPTextTemplate.placeholder else { return nil }
        var parts: [String] = []
        var cursor = key.startIndex
        for match in splitter.matches(in: key, options: [], range: NSRange(key.startIndex..<key.endIndex, in: key)) {
            guard let range = Range(match.range, in: key) else { return nil }
            parts.append(String(key[cursor..<range.lowerBound]))
            cursor = range.upperBound
        }
        parts.append(String(key[cursor...]))
        let source = "\\A" + parts.map { NSRegularExpression.escapedPattern(for: $0) }.joined(separator: "(.*?)") + "\\z"
        guard let compiled = try? NSRegularExpression(pattern: source, options: [.dotMatchesLineSeparators]) else { return nil }
        self.values = values
        self.pattern = compiled
    }

    /// The translation in `column` with the captured names and numbers, or nil when `text` does not match.
    func fill(_ text: String, column: Int) -> String? {
        guard column >= 0, column < values.count, let marker = MPTextTemplate.placeholder,
              let match = pattern.firstMatch(in: text, options: [], range: NSRange(text.startIndex..<text.endIndex, in: text)) else { return nil }
        var captured: [String] = []
        for index in 1..<match.numberOfRanges {
            let range = match.range(at: index)
            if range.location == NSNotFound { captured.append(""); continue }
            guard let bounds = Range(range, in: text) else { return nil }
            captured.append(String(text[bounds]))
        }
        let value = values[column]
        var result = ""
        var cursor = value.startIndex
        for found in marker.matches(in: value, options: [], range: NSRange(value.startIndex..<value.endIndex, in: value)) {
            guard let whole = Range(found.range, in: value), let digits = Range(found.range(at: 1), in: value) else { continue }
            result.append(contentsOf: value[cursor..<whole.lowerBound])
            if let n = Int(value[digits]), n < captured.count { result.append(contentsOf: captured[n]) }
            else { result.append(contentsOf: value[whole]) }
            cursor = whole.upperBound
        }
        result.append(contentsOf: value[cursor...])
        return result
    }
}
