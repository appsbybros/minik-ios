import AVFoundation

/// The voice every Minik speech player uses for a language. A grown-up can choose one of the
/// device's voices in the Parent Area ("Reading voice"); otherwise it is the clearest voice
/// installed for the language's usual accent, so an Enhanced or Premium voice downloaded in
/// the device's Settings is used at once. Apps cannot download voices themselves, and Hebrew
/// has a single voice (Carmit), whose Enhanced version sounds much better than the default.
enum MinikSpeechVoice {
    /// The chosen voice while it is still on the device, else the automatic one.
    static func voice(
        for languageTag: String,
        preferences: MinikSpeechVoicePreferences = MinikSpeechVoicePreferences()
    ) -> AVSpeechSynthesisVoice? {
        if let code = languageCode(languageTag),
           let identifier = preferences.identifier(forLanguageCode: code),
           let chosen = AVSpeechSynthesisVoice(identifier: identifier),
           languageCode(chosen.language) == code {
            return chosen
        }
        return automaticVoice(for: languageTag)
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

    /// The voices a grown-up can choose for a language, clearest first. Novelty voices
    /// (Bubbles, Bells…) and the device owner's Personal Voice are left out.
    static func choices(forLanguageCode code: String) -> [AVSpeechSynthesisVoice] {
        AVSpeechSynthesisVoice.speechVoices()
            .filter { languageCode($0.language) == code && isOffered($0) }
            .sorted {
                if $0.quality.rawValue != $1.quality.rawValue {
                    return $0.quality.rawValue > $1.quality.rawValue
                }
                if $0.name != $1.name { return $0.name < $1.name }
                return $0.language < $1.language
            }
    }

    static func languageCode(_ languageTag: String) -> String? {
        Locale(identifier: languageTag).language.languageCode?.identifier
    }

    private static func isOffered(_ voice: AVSpeechSynthesisVoice) -> Bool {
        !voice.voiceTraits.contains(.isNoveltyVoice) && !voice.voiceTraits.contains(.isPersonalVoice)
    }
}

/// The Parent Area's "Reading voice" choice, one per language ("he", "en"…); none means
/// Automatic.
struct MinikSpeechVoicePreferences {
    private let userDefaults: UserDefaults
    private let keyPrefix: String

    init(
        userDefaults: UserDefaults = .standard,
        keyPrefix: String = "minik.speech-voice.v1"
    ) {
        self.userDefaults = userDefaults
        self.keyPrefix = keyPrefix
    }

    func identifier(forLanguageCode code: String) -> String? {
        userDefaults.string(forKey: key(code))
    }

    func save(_ identifier: String?, forLanguageCode code: String) {
        if let identifier {
            userDefaults.set(identifier, forKey: key(code))
        } else {
            userDefaults.removeObject(forKey: key(code))
        }
    }

    private func key(_ code: String) -> String {
        "\(keyPrefix).\(code)"
    }
}
