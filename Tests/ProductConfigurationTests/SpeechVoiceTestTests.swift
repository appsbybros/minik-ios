import XCTest
@testable import MinikPlus

final class SpeechVoiceTestTests: XCTestCase {
    func testHebrewComparisonContainsDigitsPlainWordsAndNiqqudWithoutRewriting() {
        let samples = SpeechVoiceTestSamples.samples(for: .hebrew)
        XCTAssertTrue(samples.contains("1 + 2"))
        XCTAssertTrue(samples.contains("2"))
        XCTAssertTrue(samples.contains("שתיים"))
        XCTAssertTrue(samples.contains("שְׁתַּיִם"))
        XCTAssertTrue(samples.contains("אחת ועוד שתיים"))
        XCTAssertTrue(samples.contains("אַחַת וְעוֹד שְׁתַּיִם"))
        XCTAssertTrue(samples.contains("מגדל"))
        XCTAssertTrue(samples.contains("מִגְדָּל"))
        XCTAssertTrue(samples.contains("ניצחתם"))
        XCTAssertTrue(samples.contains("נִצַּחְתֶּם"))
    }

    func testEnglishOnlyDoesNotExposeHebrewSamplesByDefault() {
        let allowed = InterfaceLocalePolicy.allowedLocales(for: .minikPlusEnglish)
        let selected = SpeechVoiceTestSamples.initialLocale(allowed: allowed)
        XCTAssertEqual(selected, .english)
        XCTAssertFalse(allowed.contains(.hebrew))
        XCTAssertEqual(SpeechVoiceTestSamples.samples(for: selected), ["1 + 2", "2"])
        XCTAssertEqual(SpeechVoiceTestSamples.initialLocale(allowed: [.english, .hebrew]), .hebrew)
    }

    func testVoiceFilteringAcceptsHebrewAliasesAndRejectsEnglishFallback() {
        XCTAssertTrue(SpeechVoiceTestSamples.matches(voiceLanguage: "he-IL", locale: .hebrew))
        XCTAssertTrue(SpeechVoiceTestSamples.matches(voiceLanguage: "iw_IL", locale: .hebrew))
        XCTAssertFalse(SpeechVoiceTestSamples.matches(voiceLanguage: "en-US", locale: .hebrew))
        XCTAssertFalse(SpeechVoiceTestSamples.matches(voiceLanguage: "", locale: .hebrew))
        XCTAssertTrue(SpeechVoiceTestSamples.matches(voiceLanguage: "pt-PT", locale: .portugueseBrazil))
        XCTAssertFalse(SpeechVoiceTestSamples.matches(voiceLanguage: "es-ES", locale: .portuguesePortugal))
    }
}
