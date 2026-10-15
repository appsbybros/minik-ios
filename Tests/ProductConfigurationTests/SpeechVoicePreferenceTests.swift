import AVFoundation
import XCTest
@testable import MinikPlus

final class SpeechVoicePreferenceTests: XCTestCase {
    func testVoiceAndSpeedAreSavedPerSpokenLanguage() {
        let suite = "SpeechVoicePreferenceTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }

        SpeechVoicePreference.save(id: "hebrew-voice", rate: 0.42, for: "he-IL", defaults: defaults)
        XCTAssertEqual(SpeechVoicePreference.selectedID(for: "he", defaults: defaults), "hebrew-voice")
        XCTAssertEqual(SpeechVoicePreference.selectedRate(for: "he", defaults: defaults), 0.42, accuracy: 0.001)
        XCTAssertEqual(SpeechVoicePreference.selectedID(for: "en-US", defaults: defaults), "")
        XCTAssertEqual(SpeechVoicePreference.selectedRate(for: "en", defaults: defaults), AVSpeechUtteranceDefaultSpeechRate)
        SpeechVoicePreference.save(id: "", rate: 0.9, for: "he-IL", defaults: defaults)
        XCTAssertEqual(SpeechVoicePreference.selectedID(for: "he", defaults: defaults), "")
        XCTAssertEqual(SpeechVoicePreference.selectedRate(for: "he", defaults: defaults), 0.60, accuracy: 0.001)
    }

    func testTheVoiceIsTheReadingVoiceChoice() {
        let suite = "SpeechVoicePreferenceTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }

        SpeechVoicePreference.save(id: "hebrew-voice", rate: 0.5, for: "he-IL", defaults: defaults)
        XCTAssertEqual(MinikSpeechVoicePreferences(userDefaults: defaults).identifier(forLanguageCode: "he"), "hebrew-voice")
        MinikSpeechVoicePreferences(userDefaults: defaults).save("other-voice", forLanguageCode: "he")
        XCTAssertEqual(SpeechVoicePreference.selectedID(for: "he-IL", defaults: defaults), "other-voice")
    }
}
