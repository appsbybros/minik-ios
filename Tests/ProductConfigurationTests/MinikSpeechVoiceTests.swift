import AVFoundation
import XCTest
@testable import MinikPlus

final class MinikSpeechVoiceTests: XCTestCase {
    func testReadingVoiceChoiceIsKeptPerLanguage() {
        let suite = "MinikSpeechVoiceTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let preferences = MinikSpeechVoicePreferences(userDefaults: defaults)

        preferences.save("hebrew-voice", forLanguageCode: "he")
        XCTAssertEqual(preferences.identifier(forLanguageCode: "he"), "hebrew-voice")
        XCTAssertNil(preferences.identifier(forLanguageCode: "en"))
        preferences.save(nil, forLanguageCode: "he")
        XCTAssertNil(preferences.identifier(forLanguageCode: "he"))
    }

    func testWrongLanguageVoiceFallsBackToHebrew() {
        let suite = "MinikSpeechVoiceTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let preferences = MinikSpeechVoicePreferences(userDefaults: defaults)
        let english = AVSpeechSynthesisVoice(language: "en-US")
        let hebrew = AVSpeechSynthesisVoice(language: "he-IL")
        guard let english, let hebrew else { return }
        preferences.save(english.identifier, forLanguageCode: "he")
        let resolved = MinikSpeechVoice.voice(for: "he-IL", preferences: preferences)
        XCTAssertEqual(MinikSpeechVoice.languageCode(resolved?.language ?? ""), "he")
        XCTAssertEqual(MinikSpeechVoice.languageCode(MinikSpeechVoice.automaticVoice(for: "he")?.language ?? ""), "he")
    }
}
