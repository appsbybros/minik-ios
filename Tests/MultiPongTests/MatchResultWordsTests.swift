import XCTest
@testable import MinikMultiPingPong

// Android app/src/test/.../MatchResultWordsTest.kt (MinikCrossPong 1dbfe33): the result card's sentences in the six app
// languages (MPResultWords).
final class MatchResultWordsTests: XCTestCase {
    func testHebrewHouseCharactersHaveNaturalGenderAgreement() {
        XCTAssertEqual("\u{2068}ספיר\u{2069} ניצחה במשחק הזה!", MPResultWords.winner("ספיר", houseCharacter: "kyra", language: "he"))
        XCTAssertEqual("\u{2068}Flare\u{2069} ניצח במשחק הזה!", MPResultWords.winner("Flare", houseCharacter: "flare", language: "he"))
    }

    func testPersonDoesNotInheritAnAvatarsGenderAndNamesStayIsolated() {
        XCTAssertEqual("כל הכבוד ל־\u{2068}Alex\u{2069} על הניצחון!", MPResultWords.winner("Alex", houseCharacter: nil, language: "he"))
        for lang in ["en", "he", "es", "ar", "hi", "nl"] {
            XCTAssertTrue(MPResultWords.winner("Flare", houseCharacter: nil, language: lang).contains("\u{2068}Flare\u{2069}"))
        }
    }

    func testEverySupportedLanguageHasItsOwnResultCopy() {
        let languages = ["en", "he", "es", "ar", "hi", "nl"]
        XCTAssertEqual(6, Set(languages.map { MPResultWords.winner("Kyra", houseCharacter: "kyra", language: $0) }).count)
        XCTAssertEqual(6, Set(languages.map { MPResultWords.scores($0) }).count)
        XCTAssertEqual(6, Set(languages.map { MPResultWords.youWon($0) }).count)
    }
}
