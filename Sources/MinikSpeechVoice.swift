import AVFoundation

/// The voice every Minik speech player uses for a language: the clearest voice installed for
/// the language's usual accent, so an Enhanced or Premium voice downloaded in the device's
/// Settings is used at once. The apps show no voice choice (the owner wants no voice or
/// speech setting anywhere); a choice saved by an earlier version is ignored. Apps cannot download voices themselves, and Hebrew
/// has a single voice (Carmit), whose Enhanced version sounds much better than the default.
enum MinikSpeechVoice {
    static func voice(for languageTag: String) -> AVSpeechSynthesisVoice? {
        automaticVoice(for: languageTag)
    }

    /// The system's voice for the language, replaced by a clearer version of the same accent
    /// (the same voice's Enhanced or Premium download first) when one is installed.
    static func automaticVoice(for languageTag: String) -> AVSpeechSynthesisVoice? {
        let tag = languageCode(languageTag) == "he" ? "he-IL" : languageTag
        guard let standard = AVSpeechSynthesisVoice(language: tag)
            ?? AVSpeechSynthesisVoice.speechVoices().first(where: {
                languageCode($0.language) == languageCode(tag) && isOffered($0)
            }) else { return nil }
        let sameAccent = AVSpeechSynthesisVoice.speechVoices().filter {
            $0.language == standard.language && isOffered($0)
        }
        guard let bestQuality = sameAccent.map(\.quality.rawValue).max(),
              bestQuality > standard.quality.rawValue else {
            return standard
        }
        let clearest = sameAccent.filter { $0.quality.rawValue == bestQuality }
        return clearest.first { $0.name == standard.name } ?? clearest.first
    }

    static func languageCode(_ languageTag: String) -> String? {
        Locale(identifier: languageTag).language.languageCode?.identifier
    }

    private static func isOffered(_ voice: AVSpeechSynthesisVoice) -> Bool {
        !voice.voiceTraits.contains(.isNoveltyVoice) && !voice.voiceTraits.contains(.isPersonalVoice)
    }
}
