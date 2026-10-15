import Foundation

/// Literal test inputs. These must not be translated or passed through the
/// pronunciation replacements: the parent is comparing the exact same input.
enum SpeechVoiceTestSamples {
    static let hebrew = [
        "1 + 2", "2", "שתיים", "שְׁתַּיִם",
        "אחת ועוד שתיים", "אַחַת וְעוֹד שְׁתַּיִם",
        "מגדל", "מִגְדָּל", "ניצחתם", "נִצַּחְתֶּם",
        "תפוח, משמש, מחשבון", "שלוש תשובות נכונות ברצף"
    ]

    static func initialLocale(allowed: [InterfaceLocaleID]) -> InterfaceLocaleID {
        allowed.contains(.hebrew) ? .hebrew : (allowed.first ?? .english)
    }

    static func samples(for locale: InterfaceLocaleID) -> [String] {
        locale == .hebrew ? hebrew : ["1 + 2", "2"]
    }

    static func languageCode(_ tag: String) -> String {
        let code = tag.replacingOccurrences(of: "_", with: "-")
            .split(separator: "-").first.map(String.init)?.lowercased() ?? ""
        return code == "iw" ? "he" : code
    }

    static func matches(voiceLanguage: String, locale: InterfaceLocaleID) -> Bool {
        languageCode(voiceLanguage) == languageCode(locale.rawValue)
    }
}
