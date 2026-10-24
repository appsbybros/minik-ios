import Foundation

// AndroidKit: java.util.Locale for the call sites that read the device locale (Locale.getDefault(),
// configuration.locales[0], ConfigurationCompat.getLocales(...)[0]) and for String.format(Locale, ...).
// The default locale is the first entry of the iOS preferred-language list, like Android's first configured
// locale (DESIGN 2.7). Language codes use the modern ISO forms like JDK 17+ ("iw" -> "he", "in" -> "id",
// "ji" -> "yi"); the app compares against both "he" and "iw".

final class ALocale: Hashable, CustomStringConvertible {
    /// ISO 639 language code, lower case ("" for Locale.ROOT).
    let language: String
    /// ISO 3166 region code (or UN M.49 digits), upper case; "" when absent.
    let country: String
    /// Variant, "" when absent.
    let variant: String
    /// ISO 15924 script code in title case ("Hans"), "" when absent.
    let script: String

    /// `new Locale(language, country)` / `new Locale(language, country, variant)`.
    init(_ language: String, _ country: String = "", _ variant: String = "") {
        self.language = ALocale.normalizeLanguage(language)
        self.country = country.uppercased()
        self.variant = variant
        self.script = ""
    }

    private init(language: String, script: String, country: String, variant: String) {
        self.language = ALocale.normalizeLanguage(language)
        self.script = script.isEmpty ? "" : script.prefix(1).uppercased() + script.dropFirst().lowercased()
        self.country = country.uppercased()
        self.variant = variant
    }

    /// Locale.ROOT ("" / "und").
    static let ROOT = ALocale("")
    /// Locale.US (en_US).
    static let US = ALocale("en", "US")
    /// Locale.ENGLISH (en).
    static let ENGLISH = ALocale("en")
    /// Locale.UK (en_GB).
    static let UK = ALocale("en", "GB")

    /// `Locale.getDefault()`: the first iOS preferred language ("he-IL" -> he_IL, "en" -> en).
    static func getDefault() -> ALocale {
        return forLanguageTag(Locale.preferredLanguages.first ?? "en")
    }

    /// `Locale.forLanguageTag(tag)` for the BCP 47 shapes iOS produces: language[-Script][-REGION][-variant...]
    /// ("_" is accepted as well). Extensions ("-u-...") are dropped.
    static func forLanguageTag(_ tag: String) -> ALocale {
        let parts = tag.split(whereSeparator: { $0 == "-" || $0 == "_" }).map(String.init)
        guard let first = parts.first, first.lowercased() != "und" || parts.count > 1 else {
            return ROOT
        }
        var language = first.lowercased() == "und" ? "" : first
        if language.count < 2 || language.count > 8 || !language.allSatisfy({ $0.isASCII && $0.isLetter }) {
            language = ""
        }
        var script = ""
        var region = ""
        var variants: [String] = []
        var i = 1
        if i < parts.count, parts[i].count == 4, parts[i].allSatisfy({ $0.isASCII && $0.isLetter }) {
            script = parts[i]
            i += 1
        }
        if i < parts.count,
           (parts[i].count == 2 && parts[i].allSatisfy({ $0.isASCII && $0.isLetter }))
            || (parts[i].count == 3 && parts[i].allSatisfy({ $0.isASCII && $0.isNumber })) {
            region = parts[i]
            i += 1
        }
        while i < parts.count {
            let p = parts[i]
            if p.count == 1 { break } // extension or private use
            variants.append(p)
            i += 1
        }
        return ALocale(language: language, script: script, country: region, variant: variants.joined(separator: "_"))
    }

    /// JDK 17+ mapping of the legacy ISO 639 codes to the current ones.
    private static func normalizeLanguage(_ language: String) -> String {
        let lower = language.lowercased()
        switch lower {
        case "iw": return "he"
        case "in": return "id"
        case "ji": return "yi"
        default: return lower
        }
    }

    /// Locale.getLanguage().
    func getLanguage() -> String { return language }
    /// Locale.getCountry().
    func getCountry() -> String { return country }

    /// Locale.toLanguageTag(): "he-IL", "en", "zh-Hans-CN"; Locale.ROOT is "und".
    func toLanguageTag() -> String {
        var parts: [String] = [language.isEmpty ? "und" : language]
        if !script.isEmpty { parts.append(script) }
        if !country.isEmpty { parts.append(country) }
        if !variant.isEmpty { parts.append(contentsOf: variant.split(separator: "_").map(String.init)) }
        return parts.joined(separator: "-")
    }

    /// Locale.toString(): "he_IL", "en", "_US", "" for ROOT, "zh_CN_#Hans" with a script.
    func toString() -> String {
        if language.isEmpty && country.isEmpty && variant.isEmpty && script.isEmpty { return "" }
        var s = language
        if !country.isEmpty || !variant.isEmpty || !script.isEmpty { s += "_" + country }
        if !variant.isEmpty { s += "_" + variant }
        if !script.isEmpty { s += (variant.isEmpty ? "_#" : "_#") + script }
        return s
    }

    var description: String { return toString() }

    /// The ICU/Foundation identifier ("he_IL", "zh_Hans_CN", "" for ROOT).
    var icuIdentifier: String {
        var parts: [String] = [language]
        if !script.isEmpty { parts.append(script) }
        if !country.isEmpty { parts.append(country) }
        let id = parts.joined(separator: "_")
        return id == "_" ? "" : id
    }

    /// `l.equals(Locale.US)`.
    var isUS: Bool {
        return language == "en" && country == "US" && variant.isEmpty && script.isEmpty
    }

    /// Foundation's Locale for this locale.
    var foundationLocale: Locale { return Locale(identifier: icuIdentifier) }

    static func == (lhs: ALocale, rhs: ALocale) -> Bool {
        return lhs.language == rhs.language && lhs.country == rhs.country
            && lhs.variant == rhs.variant && lhs.script == rhs.script
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(language)
        hasher.combine(country)
        hasher.combine(variant)
        hasher.combine(script)
    }
}
