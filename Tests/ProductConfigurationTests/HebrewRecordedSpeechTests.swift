import XCTest
@testable import MinikPlus

/// tools/hebrew-speech/hebrew_speech.py files the recorded clips by the same rule, so a
/// change here must be made there too.
final class HebrewRecordedSpeechTests: XCTestCase {
    func testKeyDropsPointsPunctuationAndExtraSpaces() {
        XCTAssertEqual(HebrewRecordedSpeech.key("בְּרֶצֶף"), "ברצף")
        XCTAssertEqual(HebrewRecordedSpeech.key("גול!!"), "גול")
        XCTAssertEqual(HebrewRecordedSpeech.key("  3   תשובות
נכונות ברצף "), "3 תשובות נכונות ברצף")
        XCTAssertEqual(HebrewRecordedSpeech.key("איקס או עיגול, בשביל הכיף"), "איקס או עיגול בשביל הכיף")
        XCTAssertEqual(HebrewRecordedSpeech.key("אות נכונה + גול = נקודה אחת לכם!"), "אות נכונה + גול = נקודה אחת לכם")
        XCTAssertEqual(HebrewRecordedSpeech.key("Kiwi"), "kiwi")
    }

    func testKeyKeepsTheGeresh() {
        XCTAssertEqual(HebrewRecordedSpeech.key("כ׳ סופית"), "כ' סופית")
        XCTAssertEqual(HebrewRecordedSpeech.key("ג’ירפה"), "ג'ירפה")
    }

    func testPronunciationFixFindsThePlainClip() {
        let manifest = ["3 תשובות נכונות ברצף": "he-1.mp3"]
        let spoken = InterfaceLocaleID.hebrew.spokenText(for: "3 תשובות נכונות ברצף")

        XCTAssertNotEqual(spoken, "3 תשובות נכונות ברצף")
        XCTAssertEqual(HebrewRecordedSpeech.clipFiles(for: spoken, in: manifest), ["he-1.mp3"])
        XCTAssertNil(HebrewRecordedSpeech.clipFiles(for: "תשובות נכונות", in: manifest))
    }

    func testKeyKeepsThePointInsideANumber() {
        XCTAssertEqual(HebrewRecordedSpeech.key("2.5 ועוד 1,000."), "2.5 ועוד 1,000")
        XCTAssertEqual(HebrewRecordedSpeech.key("3. ועוד"), "3 ועוד")
    }

    func testASentenceIsPutTogetherFromItsWordsLongestFirst() {
        let manifest = [
            "3": "a.mp3", "4": "b.mp3", "ועוד": "c.mp3", "שווה": "d.mp3", "כמה": "e.mp3",
            "שווה כמה": "f.mp3", "פתרו את התרגיל": "g.mp3"
        ]

        XCTAssertEqual(
            HebrewRecordedSpeech.clipFiles(for: "פתרו את התרגיל. 3 ועוד 4 שווה כמה.", in: manifest),
            ["g.mp3", "a.mp3", "c.mp3", "b.mp3", "f.mp3"]
        )
        XCTAssertNil(HebrewRecordedSpeech.clipFiles(for: "3 ועוד 5 שווה כמה", in: manifest))
    }

    func testManifestFormat() throws {
        let json = #"{"voice": "Hila", "clips": {"גול": "he-0123456789ab.mp3"}}"#
        let manifest = try JSONDecoder().decode(HebrewRecordedSpeech.Manifest.self, from: Data(json.utf8))

        XCTAssertEqual(manifest.voice, "Hila")
        XCTAssertEqual(manifest.clips["גול"], "he-0123456789ab.mp3")
    }

    func testOnlyHebrewUsesClips() {
        XCTAssertNil(HebrewRecordedSpeech.clipURL(for: "Great job!", languageTag: "en-US"))
    }
}
