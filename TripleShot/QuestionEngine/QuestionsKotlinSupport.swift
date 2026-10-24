import Foundation

// Area t-questions (spec 04): the few Kotlin stdlib behaviours the question layer needs that the AndroidKit core
// contract does not list. They live in one namespace so they cannot clash with AndroidKit or other areas.
// Sources checked: kotlin-stdlib 2.3.21 (Strings.kt, StringsJVM.kt, CharJVM.kt, StringNumberConversions.kt,
// _Collections.kt) and java.lang.String / java.lang.Character.

/// Kotlin `IllegalArgumentException` thrown by `require(...)` or `throw IllegalArgumentException(...)` in the
/// question layer where a caller catches it: `AndroidQuestionBankParser.parse` and the `Question` validation it
/// propagates (DESIGN 2.1). Everything nobody catches stays a precondition, as a crash on Android.
struct QuestionsIllegalArgumentException: Error, Equatable, CustomStringConvertible {
    let message: String

    init(_ message: String) {
        self.message = message
    }

    var description: String { return "java.lang.IllegalArgumentException: \(message)" }
}

enum QuestionsKotlin {

    /// Kotlin `require(value) { lazyMessage() }`, thrown (see QuestionsIllegalArgumentException).
    static func require(_ value: Bool, _ lazyMessage: @autoclosure () -> String) throws {
        if !value { throw QuestionsIllegalArgumentException(lazyMessage()) }
    }

    /// Kotlin `takeIf { it.isNotBlank() }`.
    static func notBlank(_ s: String) -> String? {
        return s.kotlinIsBlank ? nil : s
    }

    /// Kotlin `substringBefore(delimiter)`: the part before the first `delimiter` (a one-unit Char), else the
    /// whole string. UTF-16 based like Kotlin.
    static func substringBefore(_ s: String, _ delimiter: Character) -> String {
        let d = unit(delimiter)
        let units = Array(s.utf16)
        guard let index = units.firstIndex(of: d) else { return s }
        return String(decoding: units[0..<index], as: UTF16.self)
    }

    /// Kotlin `substringAfterLast(delimiter, missingDelimiterValue)`.
    static func substringAfterLast(_ s: String, _ delimiter: Character, _ missingDelimiterValue: String) -> String {
        let d = unit(delimiter)
        let units = Array(s.utf16)
        guard let index = units.lastIndex(of: d) else { return missingDelimiterValue }
        return String(decoding: units[(index + 1)...], as: UTF16.self)
    }

    /// Kotlin `split(delimiter)` for one Char and no limit: empty parts are kept, "" gives [""].
    static func split(_ s: String, _ delimiter: Character) -> [String] {
        let d = unit(delimiter)
        let units = Array(s.utf16)
        var result: [String] = []
        var currentOffset = 0
        var i = 0
        while i < units.count {
            if units[i] == d {
                result.append(String(decoding: units[currentOffset..<i], as: UTF16.self))
                currentOffset = i + 1
            }
            i += 1
        }
        result.append(String(decoding: units[currentOffset...], as: UTF16.self))
        return result
    }

    /// Kotlin `Char.equals(other, ignoreCase = true)` = java.lang.String.regionMatches(ignoreCase) per unit:
    /// equal, or equal upper case, or equal lower case of the upper case.
    static func charEqualsIgnoreCase(_ a: UInt16, _ b: UInt16) -> Bool {
        if a == b { return true }
        let thisUpper = upperChar(a)
        let otherUpper = upperChar(b)
        return thisUpper == otherUpper || lowerChar(thisUpper) == lowerChar(otherUpper)
    }

    /// Kotlin `String.equals(other, ignoreCase = true)` (java.lang.String.equalsIgnoreCase).
    static func equalsIgnoreCase(_ a: String, _ b: String) -> Bool {
        let x = Array(a.utf16)
        let y = Array(b.utf16)
        if x.count != y.count { return false }
        for i in x.indices where !charEqualsIgnoreCase(x[i], y[i]) { return false }
        return true
    }

    /// Kotlin `CharSequence.contains(other, ignoreCase = true)` (indexOf with regionMatches, UTF-16 units).
    static func containsIgnoreCase(_ s: String, _ other: String) -> Bool {
        let x = Array(s.utf16)
        let y = Array(other.utf16)
        if y.isEmpty { return true }
        if y.count > x.count { return false }
        var index = 0
        while index + y.count <= x.count {
            var matches = true
            for k in y.indices where !charEqualsIgnoreCase(x[index + k], y[k]) {
                matches = false
                break
            }
            if matches { return true }
            index += 1
        }
        return false
    }

    /// Kotlin `String.toIntOrNull()` (radix 10): an optional leading '-' or '+', then digits in the sense of
    /// `Character.digit(char, 10)` (every Unicode decimal digit, e.g. U+0663 or U+FF13), Int (32-bit) overflow
    /// gives null. Statement by statement from StringNumberConversions.kt.
    static func toIntOrNull(_ s: String) -> Int? {
        let units = Array(s.utf16)
        let length = units.count
        if length == 0 { return nil }
        let start: Int
        let isNegative: Bool
        let limit: Int32
        let firstChar = units[0]
        if firstChar < 0x30 {  // Possible leading sign ('0')
            if length == 1 { return nil }  // non-digit (possible sign) only, no digits after
            start = 1
            if firstChar == 0x2D {  // '-'
                isNegative = true
                limit = Int32.min
            } else if firstChar == 0x2B {  // '+'
                isNegative = false
                limit = -Int32.max
            } else {
                return nil
            }
        } else {
            start = 0
            isNegative = false
            limit = -Int32.max
        }
        let limitForMaxRadix: Int32 = (-Int32.max) / 36
        var limitBeforeMul = limitForMaxRadix
        var result: Int32 = 0
        var i = start
        while i < length {
            let digit = digitOf(units[i])
            if digit < 0 { return nil }
            if result < limitBeforeMul {
                if limitBeforeMul == limitForMaxRadix {
                    limitBeforeMul = limit / 10
                    if result < limitBeforeMul {
                        return nil
                    }
                } else {
                    return nil
                }
            }
            result *= 10
            if result < limit + digit { return nil }
            result -= digit
            i += 1
        }
        return Int(isNegative ? result : -result)
    }

    /// Kotlin `Iterable<Long>.average()`: the sum accumulated in Double element by element, NaN when empty.
    static func average(_ values: [Int64]) -> Double {
        var sum = 0.0
        var count = 0
        for element in values {
            sum += Double(element)
            count += 1
        }
        return count == 0 ? Double.nan : sum / Double(count)
    }

    /// Kotlin `Iterable<Int>.sum()`: Int (32-bit) arithmetic that wraps on overflow.
    static func sumOfInts<S: Sequence>(_ values: S) -> Int where S.Element == Int {
        var sum: Int32 = 0
        for element in values { sum = sum &+ Int32(truncatingIfNeeded: element) }
        return Int(sum)
    }

    // MARK: Private

    private static func unit(_ c: Character) -> UInt16 {
        let units = Array(String(c).utf16)
        precondition(units.count == 1, "a Kotlin Char is one UTF-16 unit")
        return units[0]
    }

    /// `Character.digit(char, 10)`: the value of a Unicode decimal digit (category Nd), else -1. Surrogate units
    /// are never digits.
    private static func digitOf(_ c: UInt16) -> Int32 {
        if c >= 0x30 && c <= 0x39 { return Int32(c - 0x30) }
        if c < 0x80 { return -1 }
        guard let scalar = Unicode.Scalar(c) else { return -1 }
        guard scalar.properties.generalCategory == .decimalNumber,
              let value = scalar.properties.numericValue, value >= 0, value < 10 else { return -1 }
        return Int32(value)
    }

    /// `Character.toUpperCase(char)` (simple mapping: a mapping to more than one unit leaves the char as it is).
    private static func upperChar(_ c: UInt16) -> UInt16 {
        guard let scalar = Unicode.Scalar(c) else { return c }
        let mapped = Array(scalar.properties.uppercaseMapping.utf16)
        return mapped.count == 1 ? mapped[0] : c
    }

    /// `Character.toLowerCase(char)` (simple mapping).
    private static func lowerChar(_ c: UInt16) -> UInt16 {
        guard let scalar = Unicode.Scalar(c) else { return c }
        let mapped = Array(scalar.properties.lowercaseMapping.utf16)
        return mapped.count == 1 ? mapped[0] : c
    }
}
