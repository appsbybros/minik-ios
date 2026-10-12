import Foundation

private final class AppTextBundleToken {}

/// Android `com.appsbybros.minik.localization.AppText`: the device-language catalog. English and Hebrew come from the
/// call sites; Spanish, Arabic, Hindi and Dutch come from `AmuduCatalog.json` (all 959 rows of Android's effective
/// `rows` map: `screenPresentationRevision() + chunk0() + … + chunk13() + gameSupportText() + spudJourneyText()`,
/// first position and last value per key).
/// Never changes stored names or network answer keys.
enum AppText {
    static let supported: Set<String> = ["en", "he", "es", "ar", "hi", "nl"]

    /// Android: `normalize(resources.configuration.locales[0].language)` — the phone's first language.
    static var language: String = AppText.normalize(AppText.devicePrimaryLanguage())

    static func devicePrimaryLanguage() -> String {
        let first = Locale.preferredLanguages.first ?? "en"
        return first.replacingOccurrences(of: "_", with: "-")
    }

    static func normalize(_ value: String) -> String {
        let base: String
        if let dash = value.firstIndex(of: "-") {
            base = String(value[value.startIndex..<dash]).lowercased()
        } else {
            base = value.lowercased()
        }
        if base == "iw" { return "he" }
        return supported.contains(base) ? base : "en"
    }

    static func configure(_ value: String) {
        language = normalize(value)
        cache.removeAll()
    }

    static var rtl: Bool { return language == "he" || language == "ar" }

    /// BCP-47 tag for speech (Android `Locale.forLanguageTag(language)`).
    static var speechLanguage: String { return language }

    private static let columns = ["es", "ar", "hi", "nl"]

    private struct Template {
        let regex: NSRegularExpression
        let values: [String]
    }

    private struct Catalog {
        var keys: [String] = []
        var rows: [String: [String]] = [:]
        var templates: [Template] = []
    }

    private static let catalog: Catalog = loadCatalog()
    private static var cache: [String: String] = [:]

    private static func loadCatalog() -> Catalog {
        var result = Catalog()
        let bundle = Bundle(for: AppTextBundleToken.self)
        guard let url = bundle.url(forResource: "AmuduCatalog", withExtension: "json") ?? Bundle.main.url(forResource: "AmuduCatalog", withExtension: "json"),
              let data = try? Data(contentsOf: url),
              let raw = try? JSONSerialization.jsonObject(with: data) as? [Any] else { return result }
        for item in raw {
            guard let row = item as? [String], row.count == 5 else { continue }
            let key = row[0]
            if result.rows[key] == nil { result.keys.append(key) }
            result.rows[key] = Array(row[1...4])
        }
        // Kotlin: rows with "{0}", stable-sorted by key length (UTF-16), longest first.
        let templated = result.keys.filter { $0.contains("{0}") }
        let ordered = Kotlin.stableSorted(templated) { $0.utf16.count > $1.utf16.count }
        for key in ordered {
            guard let values = result.rows[key], let regex = templateRegex(key) else { continue }
            result.templates.append(Template(regex: regex, values: values))
        }
        return result
    }

    private static let placeholder: NSRegularExpression? = try? NSRegularExpression(pattern: "\\{([0-9]+)\\}")

    private static func templateRegex(_ key: String) -> NSRegularExpression? {
        guard let finder = AppText.placeholder else { return nil }
        let ns = key as NSString
        var parts: [String] = []
        var cursor = 0
        for match in finder.matches(in: key, range: NSRange(location: 0, length: ns.length)) {
            parts.append(ns.substring(with: NSRange(location: cursor, length: match.range.location - cursor)))
            cursor = match.range.location + match.range.length
        }
        parts.append(ns.substring(from: cursor))
        let pattern = "^" + parts.map { NSRegularExpression.escapedPattern(for: $0) }.joined(separator: "(.*?)") + "\\z"
        return try? NSRegularExpression(pattern: pattern, options: [.dotMatchesLineSeparators])
    }

    private static func substitute(_ value: String, _ groups: [String]) -> String {
        guard let finder = AppText.placeholder else { return value }
        let ns = value as NSString
        var out = ""
        var cursor = 0
        for match in finder.matches(in: value, range: NSRange(location: 0, length: ns.length)) {
            out += ns.substring(with: NSRange(location: cursor, length: match.range.location - cursor))
            let digits = ns.substring(with: match.range(at: 1))
            let index = (Int(digits) ?? -10) + 1
            if index >= 0 && index < groups.count {
                out += groups[index]
            } else {
                out += ns.substring(with: match.range)
            }
            cursor = match.range.location + match.range.length
        }
        out += ns.substring(from: cursor)
        return out
    }

    private static func matchTemplate(_ en: String, column: Int) -> String? {
        let ns = en as NSString
        let full = NSRange(location: 0, length: ns.length)
        for template in catalog.templates {
            guard let match = template.regex.firstMatch(in: en, options: [], range: full),
                  match.range.location == 0, match.range.length == full.length else { continue }
            var groups: [String] = []
            for g in 0..<match.numberOfRanges {
                let r = match.range(at: g)
                groups.append(r.location == NSNotFound ? "" : ns.substring(with: r))
            }
            return substitute(template.values[column], groups)
        }
        return nil
    }

    /// Kotlin `AppText.t(en, he = en, hebrew = language == "he")`.
    static func t(_ en: String, _ he: String? = nil, hebrew: Bool? = nil) -> String {
        let isHebrew = hebrew ?? (language == "he")
        if isHebrew { return he ?? en }
        guard let column = columns.firstIndex(of: language) else { return en }
        if let row = catalog.rows[en] { return row[column] }
        let cacheKey = language + "\u{1}" + en
        if let cached = cache[cacheKey] { return cached }
        let resolved = resolveUncached(en, he, column: column)
        if cache.count > 2000 { cache.removeAll() }
        cache[cacheKey] = resolved
        return resolved
    }

    private static func resolveUncached(_ en: String, _ he: String?, column: Int) -> String {
        if let templated = matchTemplate(en, column: column) { return templated }
        // Preserve a caller's intentional padding when looking up a short label.
        let clean = Kotlin.trim(en)
        if clean != en, let row = catalog.rows[clean] {
            return Kotlin.leadingWhitespace(en) + row[column] + Kotlin.trailingWhitespace(en)
        }
        if en.hasPrefix(" · ") {
            return " · " + t(String(en.dropFirst(3)), he, hebrew: false)
        }
        return en
    }

    static func translated(_ key: String, _ lang: String) -> String? {
        guard let column = columns.firstIndex(of: normalize(lang)), let row = catalog.rows[key] else { return nil }
        return row[column]
    }

    static func keys() -> [String] { return catalog.keys }
}

/// Android `GameText`: the public game identity is localized; package, Firebase and save identifiers stay stable.
enum GameText {
    private static let languages = ["en", "he", "es", "ar", "hi", "nl"]
    private static let names = ["Spud", "עמודו", "Pies Quietos!", "لعبة أسماء", "Naam Aur Ball", "Stand in de mand"]
    private static let calls = ["Stop!", "עמודו!", "¡Pies quietos!", "ستوب!", "STOP!", "Stop!"]

    private static func index(_ language: String) -> Int {
        return languages.firstIndex(of: AppText.normalize(language)) ?? 0
    }

    static func title(_ language: String = AppText.language) -> String { return names[index(language)] }

    static func stopCall(_ language: String = AppText.language) -> String { return calls[index(language)] }

    static func t(_ en: String, _ he: String? = nil, hebrew: Bool? = nil) -> String {
        let isHebrew = hebrew ?? (AppText.language == "he")
        let language = isHebrew ? "he" : AppText.language
        if let values = overrides[en] { return values[index(language)] }
        return AppText.t(en, he ?? en, hebrew: isHebrew)
    }

    static func overriddenKeys() -> [String] { return Array(overrides.keys) }

    private static let overrides: [String: [String]] = [
        "MINIK AMUDU": ["Spud", "עמודו", "Pies Quietos!", "لعبة أسماء", "Naam Aur Ball", "Stand in de mand"],
        "Your Amudu code": ["Your Spud code", "הקוד שלכם לעמודו", "Tu código de Pies Quietos!", "رمز لعبة أسماء الخاص بك", "आपका Naam Aur Ball कोड", "Je code voor Stand in de mand"],
        "Amudu code": ["Spud code", "קוד לעמודו", "Código de Pies Quietos!", "رمز لعبة أسماء", "Naam Aur Ball कोड", "Code voor Stand in de mand"],
        "Amudu playing arena": ["Spud playing field", "מגרש עמודו", "Campo de Pies Quietos!", "ملعب لعبة أسماء", "Naam Aur Ball का मैदान", "Speelveld van Stand in de mand"],
        "Tennis ball": ["Tennis ball", "כדור טניס", "Pelota de tenis", "كرة تنس", "टेनिस बॉल", "Tennisbal"],
        "When SPUD is called": ["When Stop! is called", "כשקוראים עמודו", "Cuando se grita «¡Pies quietos!»", "عند النداء «ستوب!»", "“STOP!” कहने पर", "Als er Stop! wordt geroepen"],
        "SPUD!": ["Stop!", "עמודו!", "¡Pies quietos!", "ستوب!", "STOP!", "Stop!"],
        "Keep running until SPUD!": ["Keep running until someone calls Stop!", "המשיכו לרוץ עד שקוראים עמודו!", "¡Sigue corriendo hasta que griten «¡Pies quietos!»!", "واصل الركض حتى تسمع «ستوب!»", "“STOP!” सुनाई देने तक दौड़ते रहें!", "Blijf rennen tot iemand Stop! roept!"],
        "Your feet stay here. Aim and swipe to throw, or tap SPUD to stop the runners.": ["Your feet stay here. Aim and swipe to throw, or tap Stop! to stop the runners.", "הרגליים נשארות כאן. כוונו והחליקו כדי לזרוק, או לחצו עמודו לעצירת הרצים.", "Quédate aquí. Apunta y desliza para lanzar, o toca «¡Pies quietos!» para detener a los demás.", "ابقَ في مكانك. صوّب واسحب للرمي، أو المس «ستوب!» لإيقاف الآخرين.", "यहीं खड़े रहें। निशाना लगाकर स्वाइप करें, या सबको रोकने के लिए “STOP!” दबाएँ।", "Je blijft hier staan. Richt en veeg om te gooien, of tik op Stop! om de renners te stoppen."],
        "SPUD! Stay still.\nTap to catch · Double-tap to duck": ["Stop! Stay still.\nTap to catch · Double-tap to duck", "עמודו! עמדו במקום.\nנגיעה לתפיסה · נגיעה כפולה להתכופפות", "¡Pies quietos! No te muevas.\nToca para atrapar · Dos toques para agacharte", "ستوب! اثبت مكانك.\nلمسة للإمساك · لمستان للانحناء", "STOP! स्थिर रहें।\nकैच के लिए टैप · झुकने के लिए दो बार टैप", "Stop! Blijf staan.\nTik om te vangen · Dubbeltik om te bukken"],
        "Moved after SPUD!": ["Moved after Stop!", "זזתם אחרי עמודו!", "¡Te moviste después de «¡Pies quietos!»!", "تحرّكت بعد «ستوب!»", "“STOP!” के बाद हिले!", "Bewogen nadat Stop! was geroepen!"],
        "SPUD! Catch or duck — keep your feet still.": ["Stop! Catch or duck — keep your feet still.", "עמודו! תפסו או התכופפו — בלי להזיז רגליים.", "¡Pies quietos! Atrapa o agáchate, sin mover los pies.", "ستوب! أمسك الكرة أو انحنِ، دون تحريك قدميك.", "STOP! कैच लें या झुकें — पैर न हिलाएँ।", "Stop! Vang of buk — houd je voeten stil."],
        "Pick it up. Throw now, or call SPUD to stop runners.": ["Pick it up. Throw now, or call Stop! to stop the runners.", "אספו את הכדור. זרקו מיד, או קראו עמודו כדי לעצור את הרצים.", "Recógela. Lanza ya o grita «¡Pies quietos!» para detener a los demás.", "التقط الكرة. ارمِ الآن أو نادِ «ستوب!» لإيقاف الآخرين.", "गेंद उठाएँ। अभी फेंकें, या दौड़ने वालों को रोकने के लिए “STOP!” कहें।", "Pak de bal. Gooi meteen of roep Stop! om de renners te stoppen."],
        "After missing the airborne catch, get close and tap to pick up the ball. Your feet stay planted there. You may aim and throw immediately, or tap SPUD to stop the runners first. SPUD is only spoken when chosen.": ["After missing the airborne catch, get close and tap to pick up the ball. Your feet stay planted there. Aim and throw immediately, or tap Stop! to stop the runners first. The call is only spoken when you press the button.", "אחרי החטאת התפיסה, התקרבו וגעו כדי לאסוף. הרגליים נשארות במקום האיסוף. אפשר לכוון ולזרוק מיד, או ללחוץ עמודו כדי לעצור קודם את הרצים. הקריאה מושמעת רק כשלוחצים.", "Si no atrapaste la pelota, acércate y toca para recogerla. Desde ahí ya no puedes moverte. Apunta y lanza directamente, o toca «¡Pies quietos!» para detener primero a los demás. Solo se grita cuando pulsas el botón.", "إذا فاتتك الكرة، اقترب والمس لالتقاطها. تثبت قدماك هناك. صوّب وارمِ مباشرة أو المس «ستوب!» لإيقاف الآخرين أولًا. لا يُنطق النداء إلا عند الضغط على الزر.", "कैच छूटे तो पास जाकर टैप से गेंद उठाएँ। अब वहीं खड़े रहें। सीधे निशाना लगाकर फेंकें, या पहले “STOP!” दबाकर सबको रोकें। पुकार सिर्फ बटन दबाने पर होगी।", "Miste je de vangst? Ga dichterbij en tik om de bal te pakken. Vanaf die plek blijven je voeten staan. Richt en gooi meteen, of tik eerst op Stop! om de renners te stoppen. De kreet klinkt alleen als je op de knop tikt."],
    ]
}
