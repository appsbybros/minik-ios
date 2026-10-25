import AVFoundation
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

    /// Shown when a language has a single voice on the device, so every choice sounds alike.
    static let singleVoiceNoteKey: String.LocalizationValue =
        "This device has only one voice for this language (%@), so every choice here sounds the same."

    /// The voice's name when all of a language's voices are one voice (Hebrew: Carmit,
    /// perhaps in two qualities); nil when there are several voices or none.
    static func onlyVoiceName(among voices: [AVSpeechSynthesisVoice]) -> String? {
        let names = Set(voices.map(\.name))
        return names.count == 1 ? names.first : nil
    }
}
