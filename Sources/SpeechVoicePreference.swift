import AVFoundation
import Foundation

/// Parent Area > "Voice & speech": the speaking speed of each spoken language, regardless of UI
/// language. The voice itself is the Parent Area's "Reading voice" choice
/// (MinikSpeechVoicePreferences), so that menu and both voice tests share one voice per language.
enum SpeechVoicePreference {
    private static let rateKey = "minik.speech.rate."

    /// The chosen voice's identifier, or "" for Automatic.
    static func selectedID(for language: String, defaults: UserDefaults = .standard) -> String {
        MinikSpeechVoicePreferences(userDefaults: defaults).identifier(forLanguageCode: code(language)) ?? ""
    }

    static func selectedRate(for language: String, defaults: UserDefaults = .standard) -> Float {
        let key = rateKey + code(language)
        guard defaults.object(forKey: key) != nil else { return AVSpeechUtteranceDefaultSpeechRate }
        return min(0.60, max(0.35, defaults.float(forKey: key)))
    }

    /// An empty `id` goes back to Automatic.
    static func save(id: String, rate: Float, for language: String, defaults: UserDefaults = .standard) {
        let languageCode = code(language)
        MinikSpeechVoicePreferences(userDefaults: defaults).save(id.isEmpty ? nil : id, forLanguageCode: languageCode)
        defaults.set(min(0.60, max(0.35, rate)), forKey: rateKey + languageCode)
    }

    /// The key MinikSpeechVoice reads the voice with ("he", "en"…).
    private static func code(_ language: String) -> String {
        MinikSpeechVoice.languageCode(language) ?? language
    }
}
