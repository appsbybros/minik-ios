import Foundation

private final class AppTextBundleToken {}

private struct AppTextTemplate {
    let regex: NSRegularExpression
    let values: [String]
}

private final class AppTextCatalog {
    let rows: [String: [String]]
    let orderedKeys: [String]
    private(set) lazy var templates: [AppTextTemplate] = AppText.makeTemplates(rows: rows, keys: orderedKeys)

    init(rows: [String: [String]], orderedKeys: [String]) {
        self.rows = rows
        self.orderedKeys = orderedKeys
    }
}

/// Port of Android localization/AppText.kt (MinikSports): the device-language catalog (English,
/// Hebrew, Spanish, Arabic, Hindi, Dutch). It never changes stored names or network answer keys.
/// The catalog rows are `apptext.json`, extracted verbatim and in order from AppText.kt by
/// Scripts/audit-sports.py; Hebrew comes from the call site as on Android.
enum AppText {
    static let supported: Set<String> = ["en", "he", "es", "ar", "hi", "nl"]
    private static let columns = ["es", "ar", "hi", "nl"]

    /// Android reads `resources.configuration.locales[0].language` (the first device language).
    private(set) static var language: String = normalize(Locale.preferredLanguages.first ?? "en")

    static func normalize(_ value: String) -> String {
        let base = String(value.split(separator: "-", maxSplits: 1, omittingEmptySubsequences: false).first ?? "").lowercased()
        if base == "iw" { return "he" }
        return supported.contains(base) ? base : "en"
    }

    static func configure(_ value: String) {
        language = normalize(value)
        cache.removeAll()
    }

    static var rtl: Bool { return language == "he" || language == "ar" }

    private static let catalog: AppTextCatalog = loadCatalog()
    private static var cache: [String: String] = [:]

    private static func loadCatalog() -> AppTextCatalog {
        let bundle = Bundle(for: AppTextBundleToken.self)
        guard let url = bundle.url(forResource: "apptext", withExtension: "json") ?? Bundle.main.url(forResource: "apptext", withExtension: "json"),
              let data = try? Data(contentsOf: url),
              let table = try? JSONDecoder().decode([[String]].self, from: data) else {
            return AppTextCatalog(rows: [:], orderedKeys: [])
        }
        var rows: [String: [String]] = [:]
        var order: [String] = []
        for row in table where row.count == 5 {
            if rows[row[0]] == nil { order.append(row[0]) }
            rows[row[0]] = Array(row[1...])
        }
        return AppTextCatalog(rows: rows, orderedKeys: order)
    }

    fileprivate static func makeTemplates(rows: [String: [String]], keys: [String]) -> [AppTextTemplate] {
        guard let placeholder = try? NSRegularExpression(pattern: "\\{\\d+\\}") else { return [] }
        // Kotlin sortedByDescending(key.length) is stable over the catalog order.
        let templateKeys = keys.filter { $0.contains("{0}") }.stableSorted { $0.utf16.count > $1.utf16.count }
        var result: [AppTextTemplate] = []
        for key in templateKeys {
            let parts = split(key, by: placeholder).map { NSRegularExpression.escapedPattern(for: $0) }
            let pattern = "^" + parts.joined(separator: "(.*?)") + "$"
            guard let regex = try? NSRegularExpression(pattern: pattern, options: [.dotMatchesLineSeparators]),
                  let values = rows[key] else { continue }
            result.append(AppTextTemplate(regex: regex, values: values))
        }
        return result
    }

    /// Kotlin `Regex.split` (keeps leading and trailing empty parts).
    private static func split(_ text: String, by regex: NSRegularExpression) -> [String] {
        let ns = text as NSString
        var parts: [String] = []
        var cursor = 0
        for match in regex.matches(in: text, range: NSRange(location: 0, length: ns.length)) {
            parts.append(ns.substring(with: NSRange(location: cursor, length: match.range.location - cursor)))
            cursor = match.range.location + match.range.length
        }
        parts.append(ns.substring(from: cursor))
        return parts
    }

    /// Kotlin `matchEntire`: the whole string must match.
    private static func groups(_ regex: NSRegularExpression, _ text: String) -> [String]? {
        let ns = text as NSString
        let full = NSRange(location: 0, length: ns.length)
        guard let match = regex.firstMatch(in: text, options: [], range: full),
              match.range.location == 0, match.range.length == ns.length else { return nil }
        var values: [String] = []
        for i in 0..<match.numberOfRanges {
            let r = match.range(at: i)
            values.append(r.location == NSNotFound ? "" : ns.substring(with: r))
        }
        return values
    }

    private static func substitute(_ template: String, _ groupValues: [String]) -> String {
        guard let placeholder = try? NSRegularExpression(pattern: "\\{(\\d+)\\}") else { return template }
        let ns = template as NSString
        let matches = placeholder.matches(in: template, range: NSRange(location: 0, length: ns.length))
        var output = ""
        var cursor = 0
        for match in matches {
            output += ns.substring(with: NSRange(location: cursor, length: match.range.location - cursor))
            let whole = ns.substring(with: match.range)
            let digits = ns.substring(with: match.range(at: 1))
            if let index = Int(digits), index + 1 < groupValues.count {
                output += groupValues[index + 1]
            } else {
                output += whole
            }
            cursor = match.range.location + match.range.length
        }
        output += ns.substring(from: cursor)
        return output
    }

    private static func leadingWhitespace(_ s: String) -> String {
        return String(s.prefix { $0.isWhitespace })
    }

    private static func trailingWhitespace(_ s: String) -> String {
        return String(String(s.reversed().prefix { $0.isWhitespace }).reversed())
    }

    /// Android `AppText.t(en, he = en, hebrew = language == "he")`.
    static func t(_ en: String, _ he: String? = nil, hebrew: Bool? = nil) -> String {
        let isHebrew = hebrew ?? (language == "he")
        if isHebrew { return he ?? en }
        guard let col = columns.firstIndex(of: language) else { return en }
        let cacheKey = language + "\u{1}" + en + "\u{2}" + (he ?? en)
        if let cached = cache[cacheKey] { return cached }
        let value = lookup(en, he, col)
        if cache.count > 4096 { cache.removeAll() }
        cache[cacheKey] = value
        return value
    }

    private static func lookup(_ en: String, _ he: String?, _ col: Int) -> String {
        if let row = catalog.rows[en], col < row.count { return row[col] }
        for template in catalog.templates {
            guard let values = groups(template.regex, en), col < template.values.count else { continue }
            return substitute(template.values[col], values)
        }
        // Preserve a caller's intentional padding when looking up a short label.
        let clean = en.trimmingCharacters(in: .whitespacesAndNewlines)
        if clean != en, let row = catalog.rows[clean], col < row.count {
            return leadingWhitespace(en) + row[col] + trailingWhitespace(en)
        }
        if en.hasPrefix(" · ") { return " · " + t(String(en.dropFirst(3)), he, hebrew: false) }
        return en
    }

    static func translated(_ key: String, _ lang: String) -> String? {
        guard let col = columns.firstIndex(of: normalize(lang)), let row = catalog.rows[key], col < row.count else { return nil }
        return row[col]
    }

    static func keys() -> [String] { return catalog.orderedKeys }
}
