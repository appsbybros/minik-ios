import Foundation

private final class SportsTextBundleToken {}

/// Port of Android SportsText.kt with SquashText, VolleyText and CourtJourneyText: the sports-only
/// translations that take precedence over the shared AppText catalog. The tables are
/// `sportstext.json`, extracted verbatim and in order by Scripts/audit-sports.py.
enum SportsText {
    private static let languages = ["es", "ar", "hi", "nl"]

    private struct Tables {
        var extra: [String: [String]] = [:]
        var squash: [String: [String]] = [:]
        var volleyLabels: [String: [String]] = [:]
        /// Android `tips.entries` keep the table order for the prefix search.
        var volleyTips: [(String, [String])] = []
        var journey: [String: [String]] = [:]
    }

    private static let tables: Tables = load()

    private static func load() -> Tables {
        let bundle = Bundle(for: SportsTextBundleToken.self)
        guard let url = bundle.url(forResource: "sportstext", withExtension: "json") ?? Bundle.main.url(forResource: "sportstext", withExtension: "json"),
              let data = try? Data(contentsOf: url),
              let raw = try? JSONDecoder().decode([String: [[String]]].self, from: data) else { return Tables() }
        func map(_ name: String) -> [String: [String]] {
            var out: [String: [String]] = [:]
            for row in raw[name] ?? [] where row.count == 5 { out[row[0]] = Array(row[1...]) }
            return out
        }
        var t = Tables()
        t.extra = map("extra")
        t.squash = map("squash")
        t.volleyLabels = map("volleyLabels")
        t.journey = map("journey")
        t.volleyTips = (raw["volleyTips"] ?? []).filter { $0.count == 5 }.map { ($0[0], Array($0[1...])) }
        return t
    }

    private static var column: Int? { return languages.firstIndex(of: AppText.language) }

    /// Android `CourtJourneyText.translated`.
    static func journey(_ key: String) -> String? {
        guard let i = column else { return nil }
        return tables.journey[key]?[i]
    }

    /// Android `SquashText.translated`.
    static func squash(_ en: String) -> String? {
        guard let i = column else { return nil }
        return tables.squash[en]?[i]
    }

    /// Android `VolleyText.translated`: labels, or the first tip whose key starts the text; the long
    /// control help is assembled from five tips.
    static func volley(_ text: String) -> String? {
        guard let i = column else { return nil }
        if text.hasPrefix("Beginner: move into reach for automatic contact") {
            let parts = ["Beginner: move within reach.", "Standard: move close,", "Double-tap a high ball", "Block: move near the net", "Pro: tap to toss,"]
            return parts.map { key in tables.volleyTips.first { $0.0 == key }?.1[i] ?? key }.joined(separator: "\n\n")
        }
        if let label = tables.volleyLabels[text]?[i] { return label }
        return tables.volleyTips.first { text.hasPrefix($0.0) }?.1[i]
    }

    /// Android `SportsText.t(en, he, hebrew)`.
    static func t(_ en: String, _ he: String, _ hebrew: Bool) -> String {
        if hebrew { return he }
        if let s = journey(en) { return s }
        if let s = volley(en) { return s }
        if let s = squash(en) { return s }
        guard let index = column else { return en }
        return tables.extra[en]?[index] ?? AppText.t(en, he, hebrew: false)
    }

    /// Android `SportsText.feedback`: the answer feedback with its prefix in the device language and
    /// the explanation isolated left to right.
    static func feedback(_ en: String, _ he: String, _ hebrew: Bool) -> String {
        if hebrew {
            let prefix = he.hasPrefix("נכון! ") ? "נכון! " : "התשובה הנכונה: "
            let rest = he.hasPrefix(prefix) ? String(he.dropFirst(prefix.count)) : he
            let hasHebrew = rest.unicodeScalars.contains { $0.value >= 0x05D0 && $0.value <= 0x05EA }
            return hasHebrew ? he : prefix + "\u{200E}" + rest + "\u{200E}"
        }
        let correct = en.hasPrefix("Correct! ")
        let prefix = correct ? "Correct!" : "Correct answer:"
        let removed = correct ? "Correct! " : "Correct answer: "
        let rest = en.hasPrefix(removed) ? String(en.dropFirst(removed.count)) : en
        let translated: String
        switch AppText.language {
        case "es": translated = correct ? "¡Correcto!" : "Respuesta correcta:"
        case "ar": translated = correct ? "صحيح!" : "الإجابة الصحيحة:"
        case "hi": translated = correct ? "सही!" : "सही उत्तर:"
        case "nl": translated = correct ? "Goed!" : "Juiste antwoord:"
        default: translated = prefix
        }
        // Fraction explanations use the same verified equality without language-specific prose.
        let explanation = rest.contains("over the common denominator") ? rest.replacingOccurrences(of: " over the common denominator ", with: " ÷ ") : rest
        return translated + " \u{200E}" + explanation + "\u{200E}"
    }
}
