import AVFoundation
import XCTest
@testable import MinikPlus

final class MinikSpeechVoiceTests: XCTestCase {
    func testAChoiceSavedByAnEarlierVersionIsIgnored() {
        let key = "minik.speech-voice.v1.he"
        let saved = UserDefaults.standard.object(forKey: key)
        defer { UserDefaults.standard.set(saved, forKey: key) }
        guard let english = AVSpeechSynthesisVoice(language: "en-US"),
              AVSpeechSynthesisVoice(language: "he-IL") != nil else { return }
        UserDefaults.standard.set(english.identifier, forKey: key)
        let resolved = MinikSpeechVoice.voice(for: "he-IL")
        XCTAssertEqual(MinikSpeechVoice.languageCode(resolved?.language ?? ""), "he")
        XCTAssertEqual(MinikSpeechVoice.languageCode(MinikSpeechVoice.automaticVoice(for: "he")?.language ?? ""), "he")
    }
}
