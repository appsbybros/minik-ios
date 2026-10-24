import Foundation

// Port of model/OnlineNickname.kt (TripleShotGame dd722e5). Spec 01 section 7.8.

/** Online aliases are deliberately separate from the private, on-device player name. */
enum OnlineNickname {
    /**
     * Kotlin `trim()` (Char.isWhitespace), then NFC (`java.text.Normalizer`), then every code point must be a
     * `Character.isLetter` letter (general category Lu, Ll, Lt, Lm or Lo) and there must be 1...5 of them.
     * Code points, not Swift Characters: "E\u{301}mile" counts 5 after NFC, full-width letters count as letters.
     */
    static func valid(value: String) -> Bool {
        let s = value.ktrim().precomposedStringWithCanonicalMapping
        var count = 0
        for point in s.unicodeScalars {
            if !isLetter(point) { return false }
            count += 1
            if count > 5 { return false }
        }
        return count > 0
    }

    /// Positional form (Kotlin `OnlineNickname.valid(text)`).
    static func valid(_ value: String) -> Bool {
        return valid(value: value)
    }

    /** `java.lang.Character.isLetter(int codePoint)`. Not Swift `Character.isLetter`, not `isAlphabetic`. */
    private static func isLetter(_ point: Unicode.Scalar) -> Bool {
        switch point.properties.generalCategory {
        case .uppercaseLetter, .lowercaseLetter, .titlecaseLetter, .modifierLetter, .otherLetter:
            return true
        default:
            return false
        }
    }
}
