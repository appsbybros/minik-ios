import Foundation

// AndroidKit: java.util.Formatter as Android libcore implements it (String.format, Resources.getString with
// format arguments). Ported from libcore main Formatter.java: the manual FormatSpecifierParser, argument
// indexing (ordinary / explicit "%2$s" / relative "%<s"), the flag/width/precision checks, print() for the
// general, character, integral, floating-point and text conversions, localizedMagnitude (locale zero digit,
// decimal and grouping separators), leading/trailing sign, zero padding and justification. Widths and
// precisions count UTF-16 units like Java. Malformed patterns and mismatched arguments crash with the Java
// exception name, as they would crash the Android app. Date/time conversions (%t) are not used by the app.

enum AFormat {
    /// `String.format(locale, pattern, args...)` / `new Formatter(locale).format(pattern, args)`.
    static func format(_ locale: ALocale, _ pattern: String, _ args: [Any?]) -> String {
        var formatter = JavaFormatter(locale: locale)
        formatter.format(pattern, args)
        return formatter.out
    }

    /// `String.format(pattern, args...)` with the default locale (`ALocale.getDefault()`).
    static func format(_ pattern: String, _ args: Any?...) -> String {
        return format(ALocale.getDefault(), pattern, args)
    }

    /// `String.format(pattern, args)` with an argument array and the default locale.
    static func format(_ pattern: String, args: [Any?]) -> String {
        return format(ALocale.getDefault(), pattern, args)
    }

    /// `String.format(locale, pattern, a, b, ...)` written with separate arguments. (A typed array variable
    /// such as `[String]` binds here as ONE argument; pass `[Any?]` or an array literal for the array form.)
    static func format(_ locale: ALocale, _ pattern: String, _ args: Any?...) -> String {
        return format(locale, pattern, args)
    }

    /// Java `String.valueOf(arg)` / `arg.toString()` for the values Kotlin passes to %s (Float.toString,
    /// Double.toString, "null", "true", enum names, org.json text).
    static func javaToString(_ value: Any?) -> String {
        return JavaArg.classify(value).javaString
    }
}

// MARK: - Locale data (java.text.DecimalFormatSymbols / libcore DecimalFormatData)

/// The number symbols Android's Formatter takes from ICU for a locale, read from the same CLDR data through
/// Foundation's NumberFormatter (Hebrew and English: '0', '.', ',', groups of 3; Arabic: Arabic-Indic digits).
struct AFormatLocaleData {
    let zeroDigit: UInt16
    let decimalSeparator: UInt16
    let groupingSeparator: UInt16
    let groupingSize: Int
    let groupingUsed: Bool
    let exponentSeparator: String

    private static var cache: [String: AFormatLocaleData] = [:]

    static func of(_ locale: ALocale) -> AFormatLocaleData {
        let id = locale.icuIdentifier
        if let cached = cache[id] { return cached }
        let nf = NumberFormatter()
        nf.locale = Locale(identifier: id)
        nf.numberStyle = .decimal
        let zeroText = nf.string(from: NSNumber(value: 0)) ?? "0"
        var zero: UInt16 = 0x30
        for scalar in zeroText.unicodeScalars where scalar.properties.numericType == .decimal {
            if let unit = String(scalar).utf16.first { zero = unit }
            break
        }
        let data = AFormatLocaleData(
            zeroDigit: zero,
            decimalSeparator: nf.decimalSeparator.utf16.first ?? 0x2E,
            groupingSeparator: nf.groupingSeparator.utf16.first ?? 0x2C,
            groupingSize: nf.groupingSize,
            groupingUsed: nf.usesGroupingSeparator,
            exponentSeparator: nf.exponentSymbol.isEmpty ? "E" : nf.exponentSymbol
        )
        cache[id] = data
        return data
    }
}

// MARK: - Arguments

/// A Kotlin/Java argument as java.util.Formatter sees it (its boxed Java class).
enum JavaArg {
    case null
    case bool(Bool)
    /// Byte (8), Short (16), Integer (32) or Long (64). A Swift `Int` is a Kotlin Int (Integer) when it fits.
    case integer(Int64, bits: Int)
    case float(Float)
    case double(Double)
    /// java.lang.Character.
    case char(String)
    case string(String)
    /// Any other object: its toString() and a Java-like class name for error messages.
    case object(String, className: String)

    static func classify(_ value: Any?) -> JavaArg {
        guard let v = unwrap(value) else { return .null }
        if type(of: v) is NSNumber.Type, let number = v as? NSNumber {
            return classify(number)
        }
        // Numbers and Bool by their exact Swift type: a dynamic cast such as `v as? Bool` may bridge a Swift Int
        // through NSNumber on Darwin and would turn the Kotlin Int 1 into `true`.
        if let exact = classifyExact(v) { return exact }
        switch v {
        case let s as String: return .string(s)
        case let s as Substring: return .string(String(s))
        case let c as Character: return .char(String(c))
        case let u as Unicode.Scalar: return .char(String(u))
        case let o as AJSONObject: return .object(o.toString(), className: "org.json.JSONObject")
        case let a as AJSONArray: return .object(a.toString(), className: "org.json.JSONArray")
        case is AJSONNull: return .object("null", className: "java.lang.Object")
        case let l as ALocale: return .object(l.description, className: "java.util.Locale")
        case let e as any KotlinEnum: return .object(e.rawValue, className: "java.lang.Enum")
        default:
            return .object(String(describing: v), className: String(describing: type(of: v)))
        }
    }

    /// The Java box of a Swift Bool or number, matched by its exact type (no bridging); nil for other values.
    static func classifyExact(_ v: Any) -> JavaArg? {
        let t = type(of: v)
        if t == Int.self {
            let i = v as! Int
            return .integer(Int64(i), bits: i >= Int(Int32.min) && i <= Int(Int32.max) ? 32 : 64)
        }
        if t == Bool.self { return .bool(v as! Bool) }
        if t == Double.self { return .double(v as! Double) }
        if t == Float.self { return .float(v as! Float) }
        if t == Int64.self { return .integer(v as! Int64, bits: 64) }
        if t == Int32.self { return .integer(Int64(v as! Int32), bits: 32) }
        if t == Int16.self { return .integer(Int64(v as! Int16), bits: 16) }
        if t == Int8.self { return .integer(Int64(v as! Int8), bits: 8) }
        if t == UInt8.self { return .integer(Int64(v as! UInt8), bits: 32) }
        if t == UInt16.self { return .integer(Int64(v as! UInt16), bits: 32) }
        if t == UInt32.self { return .integer(Int64(v as! UInt32), bits: 64) }
        if t == UInt.self { return .integer(Int64(truncatingIfNeeded: v as! UInt), bits: 64) }
        if t == UInt64.self { return .integer(Int64(truncatingIfNeeded: v as! UInt64), bits: 64) }
        if t == CGFloat.self { return .double(Double(v as! CGFloat)) }
        return nil
    }

    private static func classify(_ n: NSNumber) -> JavaArg {
        if CFGetTypeID(n) == CFBooleanGetTypeID() { return .bool(n.boolValue) }
        let type = String(cString: n.objCType)
        switch type {
        case "f": return .float(n.floatValue)
        case "d": return .double(n.doubleValue)
        case "c", "C": return .integer(Int64(n.int8Value), bits: 8)
        case "s", "S": return .integer(Int64(n.int16Value), bits: 16)
        case "i", "I": return .integer(Int64(n.int32Value), bits: 32)
        default: return .integer(n.int64Value, bits: 64)
        }
    }

    /// Unwraps an Optional nested inside the Any (a `nil` Int? passed as an argument is Java null).
    private static func unwrap(_ value: Any?) -> Any? {
        guard let v = value else { return nil }
        let mirror = Mirror(reflecting: v)
        if mirror.displayStyle == .optional {
            guard let child = mirror.children.first else { return nil }
            return unwrap(child.value)
        }
        return v
    }

    /// The Swift value org.json stores for a Bool or number (Integer → Int, Long → Int64, Float, Double); nil for
    /// every other kind.
    var storedValue: Any? {
        switch self {
        case .bool(let b): return b
        case .integer(let v, let bits): return bits <= 32 ? Int(v) : v
        case .float(let f): return f
        case .double(let d): return d
        default: return nil
        }
    }

    /// `String.valueOf(arg)`.
    var javaString: String {
        switch self {
        case .null: return "null"
        case .bool(let b): return b ? "true" : "false"
        case .integer(let v, _): return String(v)
        case .float(let f): return AKotlinDecimal.floatToString(f) // Float.toString (libcore main)
        case .double(let d): return AKotlinFloatingDecimal.toJavaFormatString(d) // Double.toString
        case .char(let s): return s
        case .string(let s): return s
        case .object(let s, _): return s
        }
    }

    /// The Java class name in IllegalFormatConversionException messages.
    var className: String {
        switch self {
        case .null: return "null"
        case .bool: return "java.lang.Boolean"
        case .integer(_, let bits):
            switch bits {
            case 8: return "java.lang.Byte"
            case 16: return "java.lang.Short"
            case 32: return "java.lang.Integer"
            default: return "java.lang.Long"
            }
        case .float: return "java.lang.Float"
        case .double: return "java.lang.Double"
        case .char: return "java.lang.Character"
        case .string: return "java.lang.String"
        case .object(_, let name): return name
        }
    }

    /// Object.hashCode for %h.
    var javaHashCode: Int32 {
        switch self {
        case .null: return 0
        case .bool(let b): return JavaHash.of(b)
        case .integer(let v, let bits): return bits == 64 ? JavaHash.of(v) : Int32(truncatingIfNeeded: v)
        case .float(let f): return JavaHash.of(f)
        case .double(let d): return JavaHash.of(d)
        case .char(let s): return Int32(s.utf16.first ?? 0)
        case .string(let s): return s.javaHashCode
        case .object(let s, _): return s.javaHashCode
        }
    }
}

// MARK: - java.util.Formatter

private struct JavaFormatter {
    let locale: ALocale
    var out = ""

    init(locale: ALocale) {
        self.locale = locale
    }

    // Flags (java.util.Formatter.Flags)
    static let LEFT_JUSTIFY = 1 << 0 // '-'
    static let UPPERCASE = 1 << 1 // '^'
    static let ALTERNATE = 1 << 2 // '#'
    static let PLUS = 1 << 3 // '+'
    static let LEADING_SPACE = 1 << 4 // ' '
    static let ZERO_PAD = 1 << 5 // '0'
    static let GROUP = 1 << 6 // ','
    static let PARENTHESES = 1 << 7 // '('
    static let PREVIOUS = 1 << 8 // '<'

    private static let FLAGS: [UInt16] = Array(",-(+# 0<".utf16)

    private static func flagBit(_ c: UInt16) -> Int {
        switch c {
        case 0x2D: return LEFT_JUSTIFY
        case 0x23: return ALTERNATE
        case 0x2B: return PLUS
        case 0x20: return LEADING_SPACE
        case 0x30: return ZERO_PAD
        case 0x2C: return GROUP
        case 0x28: return PARENTHESES
        case 0x3C: return PREVIOUS
        default: preconditionFailure("UnknownFormatFlagsException: Flags = '\(Character(Unicode.Scalar(c)!))'")
        }
    }

    private static func flagsString(_ f: Int) -> String {
        var s = ""
        if f & LEFT_JUSTIFY != 0 { s += "-" }
        if f & UPPERCASE != 0 { s += "^" }
        if f & ALTERNATE != 0 { s += "#" }
        if f & PLUS != 0 { s += "+" }
        if f & LEADING_SPACE != 0 { s += " " }
        if f & ZERO_PAD != 0 { s += "0" }
        if f & GROUP != 0 { s += "," }
        if f & PARENTHESES != 0 { s += "(" }
        if f & PREVIOUS != 0 { s += "<" }
        return s
    }

    /// One parsed format specifier (or a fixed text run).
    private struct Spec {
        var text: String? = nil // fixed string
        var index = 0 // -2 no argument, -1 previous, 0 ordinary, n explicit
        var flags = 0
        var width = -1
        var precision = -1
        var dt = false
        var c: UInt16 = 0 // conversion, lower case
        var source = ""

        func has(_ flag: Int) -> Bool { return flags & flag != 0 }
    }

    mutating func format(_ pattern: String, _ args: [Any?]) {
        let specs = JavaFormatter.parse(Array(pattern.utf16))
        var last = -1
        var lasto = -1
        for fs in specs {
            if let text = fs.text {
                out += text
                continue
            }
            switch fs.index {
            case -2: // fixed string, "%n", or "%%"
                print(fs, nil)
            case -1: // relative index
                if last < 0 || last > args.count - 1 {
                    preconditionFailure("MissingFormatArgumentException: Format specifier '\(fs.source)'")
                }
                print(fs, args[last])
            case 0: // ordinary index
                lasto += 1
                last = lasto
                if lasto > args.count - 1 {
                    preconditionFailure("MissingFormatArgumentException: Format specifier '\(fs.source)'")
                }
                print(fs, args[lasto])
            default: // explicit index
                last = fs.index - 1
                if last < 0 || last > args.count - 1 {
                    preconditionFailure("MissingFormatArgumentException: Format specifier '\(fs.source)'")
                }
                print(fs, args[last])
            }
        }
    }

    // MARK: Parsing (Android FormatSpecifierParser)

    private static func isDigit(_ c: UInt16) -> Bool { return c >= 0x30 && c <= 0x39 }

    private static func parse(_ s: [UInt16]) -> [Spec] {
        var result: [Spec] = []
        var i = 0
        let len = s.count
        while i < len {
            if s[i] != 0x25 {
                // plain-text part: the maximal sequence up to the next '%'
                let start = i
                while i < len && s[i] != 0x25 { i += 1 }
                result.append(Spec(text: String(decoding: s[start..<i], as: UTF16.self)))
            } else {
                let (spec, end) = parseSpecifier(s, i + 1)
                result.append(spec)
                i = end
            }
        }
        return result
    }

    /// %[argument_index$][flags][width][.precision][t]conversion
    private static func parseSpecifier(_ format: [UInt16], _ startIdx: Int) -> (Spec, Int) {
        var cursor = startIdx
        func isEnd() -> Bool { return cursor == format.count }
        func peek() -> UInt16 {
            if isEnd() { preconditionFailure("UnknownFormatConversionException: Conversion = 'End of String'") }
            return format[cursor]
        }
        func advance() -> UInt16 {
            if isEnd() { preconditionFailure("UnknownFormatConversionException: Conversion = 'End of String'") }
            let c = format[cursor]
            cursor += 1
            return c
        }
        func nextIsInt() -> Bool { return !isEnd() && isDigit(format[cursor]) }
        func nextInt() -> [UInt16] {
            let begin = cursor
            while nextIsInt() { cursor += 1 }
            return Array(format[begin..<cursor])
        }

        var indexStr: [UInt16]? = nil
        var widthStr: [UInt16]? = nil
        var precisionStr: [UInt16]? = nil
        var flagsStr: [UInt16] = []
        var tT: UInt16? = nil

        // Index
        if nextIsInt() {
            let nint = nextInt()
            if peek() == 0x24 { // '$'
                indexStr = nint
                _ = advance()
            } else if nint[0] == 0x30 {
                // This is a flag, skip to parsing flags.
                cursor -= nint.count
            } else {
                // This is the width, skip to parsing precision.
                widthStr = nint
            }
        }
        // Flags
        while widthStr == nil && FLAGS.contains(peek()) {
            flagsStr.append(advance())
        }
        // Width
        if widthStr == nil && nextIsInt() {
            widthStr = nextInt()
        }
        // Precision
        if peek() == 0x2E { // '.'
            _ = advance()
            if !nextIsInt() {
                preconditionFailure("IllegalFormatPrecisionException: \(peek())")
            }
            precisionStr = nextInt()
        }
        // tT
        if peek() == 0x74 || peek() == 0x54 {
            tT = advance()
        }
        // Conversion
        let conv = advance()

        var spec = Spec()
        spec.source = "%" + String(decoding: format[startIdx..<cursor], as: UTF16.self)
        if let indexStr = indexStr {
            // Integer.parseInt; an overflowing index keeps the old implementation's -1.
            spec.index = Int(String(decoding: indexStr, as: UTF16.self)).flatMap { $0 <= Int(Int32.max) ? $0 : nil } ?? -1
        }
        // flags
        var f = 0
        for c in flagsStr {
            let bit = flagBit(c)
            if f & bit != 0 {
                preconditionFailure("DuplicateFormatFlagsException: Flags = '\(flagsString(bit))'")
            }
            f |= bit
        }
        spec.flags = f
        if f & PREVIOUS != 0 { spec.index = -1 }
        // width
        if let widthStr = widthStr, let w = Int(String(decoding: widthStr, as: UTF16.self)), w <= Int(Int32.max) {
            spec.width = w
        }
        // precision
        if let precisionStr = precisionStr, let p = Int(String(decoding: precisionStr, as: UTF16.self)), p <= Int(Int32.max) {
            spec.precision = p
        }
        if let tT = tT {
            spec.dt = true
            if tT == 0x54 { spec.flags |= UPPERCASE }
        }
        // conversion
        var c = conv
        if !spec.dt {
            let valid: Set<UInt16> = Set("bBhHsScCdoxXeEfgGaAtT%n".utf16)
            if !valid.contains(c) {
                preconditionFailure("UnknownFormatConversionException: Conversion = '\(String(decoding: [c], as: UTF16.self))'")
            }
            if c >= 0x41 && c <= 0x5A {
                spec.flags |= UPPERCASE
                c += 0x20
            }
            if c == 0x6E || c == 0x25 { // isText
                spec.index = -2
            }
        }
        spec.c = c
        if spec.dt {
            preconditionFailure("AFormat: date/time conversions (%t) are not supported: '\(spec.source)'")
        }
        check(spec)
        return (spec, cursor)
    }

    // MARK: Checks (FormatSpecifier.checkGeneral/checkCharacter/checkInteger/checkFloat/checkText)

    private static func checkBadFlags(_ spec: Spec, _ badFlags: [Int]) {
        for flag in badFlags where spec.has(flag) {
            preconditionFailure("FormatFlagsConversionMismatchException: Conversion = \(Character(Unicode.Scalar(spec.c)!)), Flags = \(flagsString(flag))")
        }
    }

    private static func checkNumeric(_ spec: Spec) {
        if spec.width != -1 && spec.width < 0 {
            preconditionFailure("IllegalFormatWidthException: \(spec.width)")
        }
        if spec.precision != -1 && spec.precision < 0 {
            preconditionFailure("IllegalFormatPrecisionException: \(spec.precision)")
        }
        // '-' and '0' require a width
        if spec.width == -1 && (spec.has(LEFT_JUSTIFY) || spec.has(ZERO_PAD)) {
            preconditionFailure("MissingFormatWidthException: \(spec.source)")
        }
        // bad combination
        if (spec.has(PLUS) && spec.has(LEADING_SPACE)) || (spec.has(LEFT_JUSTIFY) && spec.has(ZERO_PAD)) {
            preconditionFailure("IllegalFormatFlagsException: Flags = '\(flagsString(spec.flags))'")
        }
    }

    private static func check(_ spec: Spec) {
        switch spec.c {
        case 0x62, 0x68, 0x73: // b h s (general)
            if (spec.c == 0x62 || spec.c == 0x68) && spec.has(ALTERNATE) {
                preconditionFailure("FormatFlagsConversionMismatchException: Conversion = \(Character(Unicode.Scalar(spec.c)!)), Flags = #")
            }
            // '-' requires a width
            if spec.width == -1 && spec.has(LEFT_JUSTIFY) {
                preconditionFailure("MissingFormatWidthException: \(spec.source)")
            }
            checkBadFlags(spec, [PLUS, LEADING_SPACE, ZERO_PAD, GROUP, PARENTHESES])
        case 0x63: // c (character)
            if spec.precision != -1 {
                preconditionFailure("IllegalFormatPrecisionException: \(spec.precision)")
            }
            checkBadFlags(spec, [ALTERNATE, PLUS, LEADING_SPACE, ZERO_PAD, GROUP, PARENTHESES])
            // '-' requires a width
            if spec.width == -1 && spec.has(LEFT_JUSTIFY) {
                preconditionFailure("MissingFormatWidthException: \(spec.source)")
            }
        case 0x64, 0x6F, 0x78: // d o x (integer)
            checkNumeric(spec)
            if spec.precision != -1 {
                preconditionFailure("IllegalFormatPrecisionException: \(spec.precision)")
            }
            if spec.c == 0x64 {
                checkBadFlags(spec, [ALTERNATE])
            } else {
                checkBadFlags(spec, [GROUP])
            }
        case 0x65, 0x66, 0x67, 0x61: // e f g a (float)
            checkNumeric(spec)
            if spec.c == 0x66 {
                // DECIMAL_FLOAT: no further checks
            } else if spec.c == 0x61 {
                checkBadFlags(spec, [PARENTHESES, GROUP])
            } else if spec.c == 0x65 {
                checkBadFlags(spec, [GROUP])
            } else {
                checkBadFlags(spec, [ALTERNATE])
            }
        default: // % n (text)
            if spec.precision != -1 {
                preconditionFailure("IllegalFormatPrecisionException: \(spec.precision)")
            }
            if spec.c == 0x25 {
                if spec.flags != LEFT_JUSTIFY && spec.flags != 0 {
                    preconditionFailure("IllegalFormatFlagsException: Flags = '\(flagsString(spec.flags))'")
                }
                // '-' requires a width
                if spec.width == -1 && spec.has(LEFT_JUSTIFY) {
                    preconditionFailure("MissingFormatWidthException: \(spec.source)")
                }
            } else {
                if spec.width != -1 {
                    preconditionFailure("IllegalFormatWidthException: \(spec.width)")
                }
                if spec.flags != 0 {
                    preconditionFailure("IllegalFormatFlagsException: Flags = '\(flagsString(spec.flags))'")
                }
            }
        }
    }

    // MARK: Printing

    private mutating func print(_ fs: Spec, _ arg: Any?) {
        switch fs.c {
        case 0x64, 0x6F, 0x78:
            printInteger(fs, JavaArg.classify(arg))
        case 0x65, 0x67, 0x66, 0x61:
            printFloat(fs, JavaArg.classify(arg))
        case 0x63:
            printCharacter(fs, JavaArg.classify(arg))
        case 0x62:
            printBoolean(fs, JavaArg.classify(arg))
        case 0x73:
            printString(fs, JavaArg.classify(arg))
        case 0x68:
            printHashCode(fs, JavaArg.classify(arg))
        case 0x6E:
            out += "\n" // System.lineSeparator() on Android
        case 0x25:
            printText(fs, "%")
        default:
            preconditionFailure("unreachable conversion")
        }
    }

    private func failConversion(_ fs: Spec, _ arg: JavaArg) -> Never {
        preconditionFailure("IllegalFormatConversionException: \(Character(Unicode.Scalar(fs.c)!)) != \(arg.className)")
    }

    private mutating func printInteger(_ fs: Spec, _ arg: JavaArg) {
        switch arg {
        case .null:
            printText(fs, "null")
        case .integer(let value, let bits):
            var v = value
            if value < 0 && bits < 64 && (fs.c == 0x6F || fs.c == 0x78) {
                v = value &+ (Int64(1) << Int64(bits))
            }
            printLong(fs, v)
        default:
            failConversion(fs, arg)
        }
    }

    private mutating func printFloat(_ fs: Spec, _ arg: JavaArg) {
        switch arg {
        case .null:
            printText(fs, "null")
        case .float(let f):
            printDouble(fs, Double(f))
        case .double(let d):
            printDouble(fs, d)
        default:
            failConversion(fs, arg)
        }
    }

    private mutating func printCharacter(_ fs: Spec, _ arg: JavaArg) {
        let s: String
        switch arg {
        case .null:
            printText(fs, "null")
            return
        case .char(let c):
            s = c
        case .integer(let value, let bits) where bits <= 32:
            guard value >= 0, value <= 0x10FFFF, let scalar = Unicode.Scalar(UInt32(value)) else {
                preconditionFailure("IllegalFormatCodePointException: Code point = 0x\(String(UInt32(truncatingIfNeeded: value), radix: 16))")
            }
            s = String(scalar)
        default:
            failConversion(fs, arg)
        }
        printText(fs, s)
    }

    private mutating func printBoolean(_ fs: Spec, _ arg: JavaArg) {
        let s: String
        switch arg {
        case .null: s = "false"
        case .bool(let b): s = b ? "true" : "false"
        default: s = "true"
        }
        printText(fs, s)
    }

    private mutating func printString(_ fs: Spec, _ arg: JavaArg) {
        if fs.has(JavaFormatter.ALTERNATE) {
            preconditionFailure("FormatFlagsConversionMismatchException: Conversion = s, Flags = #")
        }
        printText(fs, arg.javaString)
    }

    private mutating func printHashCode(_ fs: Spec, _ arg: JavaArg) {
        if case .null = arg {
            printText(fs, "null")
            return
        }
        printText(fs, String(UInt32(bitPattern: arg.javaHashCode), radix: 16))
    }

    /// print(String s, Locale l): precision truncates (UTF-16 units), UPPERCASE, then justify.
    private mutating func printText(_ fs: Spec, _ text: String) {
        var s = text
        if fs.precision != -1 && fs.precision < s.utf16.count {
            s = s.ksubstring(0, fs.precision)
        }
        if fs.has(JavaFormatter.UPPERCASE) {
            s = toUpperCase(s)
        }
        appendJustified(fs, Array(s.utf16))
    }

    private func toUpperCase(_ s: String) -> String {
        return s.uppercased(with: Locale(identifier: locale.icuIdentifier))
    }

    private mutating func appendJustified(_ fs: Spec, _ cs: [UInt16]) {
        if fs.width == -1 {
            out += String(decoding: cs, as: UTF16.self)
            return
        }
        let padRight = fs.has(JavaFormatter.LEFT_JUSTIFY)
        let sp = fs.width - cs.count
        if padRight {
            out += String(decoding: cs, as: UTF16.self)
        }
        if sp > 0 {
            out += String(repeating: " ", count: sp)
        }
        if !padRight {
            out += String(decoding: cs, as: UTF16.self)
        }
    }

    private func leadingSign(_ fs: Spec, _ sb: inout [UInt16], _ neg: Bool) {
        if !neg {
            if fs.has(JavaFormatter.PLUS) {
                sb.append(0x2B)
            } else if fs.has(JavaFormatter.LEADING_SPACE) {
                sb.append(0x20)
            }
        } else {
            if fs.has(JavaFormatter.PARENTHESES) {
                sb.append(0x28)
            } else {
                sb.append(0x2D)
            }
        }
    }

    private func trailingSign(_ fs: Spec, _ sb: inout [UInt16], _ neg: Bool) {
        if neg && fs.has(JavaFormatter.PARENTHESES) {
            sb.append(0x29)
        }
    }

    private func adjustWidth(_ width: Int, _ fs: Spec, _ neg: Bool) -> Int {
        var newW = width
        if newW != -1 && neg && fs.has(JavaFormatter.PARENTHESES) {
            newW -= 1
        }
        return newW
    }

    private func trailingZeros(_ sb: inout [UInt16], _ nzeros: Int) {
        if nzeros > 0 {
            sb.append(contentsOf: [UInt16](repeating: 0x30, count: nzeros))
        }
    }

    /// print(long value, Locale l).
    private mutating func printLong(_ fs: Spec, _ value: Int64) {
        var sb: [UInt16] = []
        if fs.c == 0x64 {
            let neg = value < 0
            let valueStr = Array(String(value).utf16)
            // leading sign indicator
            leadingSign(fs, &sb, neg)
            // the value
            localizedMagnitude(&sb, valueStr, neg ? 1 : 0, fs, adjustWidth(fs.width, fs, neg))
            // trailing sign indicator
            trailingSign(fs, &sb, neg)
        } else if fs.c == 0x6F {
            JavaFormatter.checkBadFlags(fs, [JavaFormatter.PARENTHESES, JavaFormatter.LEADING_SPACE, JavaFormatter.PLUS])
            let s = Array(String(UInt64(bitPattern: value), radix: 8).utf16)
            let len = fs.has(JavaFormatter.ALTERNATE) ? s.count + 1 : s.count
            // apply ALTERNATE (radix indicator for octal) before ZERO_PAD
            if fs.has(JavaFormatter.ALTERNATE) {
                sb.append(0x30)
            }
            if fs.has(JavaFormatter.ZERO_PAD) {
                trailingZeros(&sb, fs.width - len)
            }
            sb.append(contentsOf: s)
        } else {
            JavaFormatter.checkBadFlags(fs, [JavaFormatter.PARENTHESES, JavaFormatter.LEADING_SPACE, JavaFormatter.PLUS])
            var s = String(UInt64(bitPattern: value), radix: 16)
            let len = fs.has(JavaFormatter.ALTERNATE) ? s.utf16.count + 2 : s.utf16.count
            // apply ALTERNATE (radix indicator for hex) before ZERO_PAD
            if fs.has(JavaFormatter.ALTERNATE) {
                sb.append(contentsOf: Array((fs.has(JavaFormatter.UPPERCASE) ? "0X" : "0x").utf16))
            }
            if fs.has(JavaFormatter.ZERO_PAD) {
                trailingZeros(&sb, fs.width - len)
            }
            if fs.has(JavaFormatter.UPPERCASE) {
                s = s.uppercased()
            }
            sb.append(contentsOf: Array(s.utf16))
        }
        // justify based on width
        appendJustified(fs, sb)
    }

    /// print(double value, Locale l).
    private mutating func printDouble(_ fs: Spec, _ value: Double) {
        var sb: [UInt16] = []
        let neg = KMath.compare(value, 0.0) == -1
        if !value.isNaN {
            let v = Swift.abs(value)
            // leading sign indicator
            leadingSign(fs, &sb, neg)
            // the value
            if !v.isInfinite {
                printFinite(fs, &sb, v, neg)
            } else {
                sb.append(contentsOf: Array((fs.has(JavaFormatter.UPPERCASE) ? "INFINITY" : "Infinity").utf16))
            }
            // trailing sign indicator
            trailingSign(fs, &sb, neg)
        } else {
            sb.append(contentsOf: Array((fs.has(JavaFormatter.UPPERCASE) ? "NAN" : "NaN").utf16))
        }
        // justify based on width
        appendJustified(fs, sb)
    }

    private func printFinite(_ fs: Spec, _ sb: inout [UInt16], _ value: Double, _ neg: Bool) {
        if fs.c == 0x65 { // SCIENTIFIC
            // Create a new FormattedFloatingDecimal with the desired precision.
            let prec = fs.precision == -1 ? 6 : fs.precision
            let fd = AKotlinFloatingDecimal.formatted(value, prec, .SCIENTIFIC)
            var mant = fd.mantissa.map { UInt16($0) }
            addZeros(&mant, prec)
            // If the precision is zero and the '#' flag is set, add the requested decimal point.
            if fs.has(JavaFormatter.ALTERNATE) && prec == 0 {
                mant.append(0x2E)
            }
            let exp: [UInt16] = value == 0.0 ? Array("+00".utf16) : (fd.exponent ?? Array("+00".utf8)).map { UInt16($0) }
            var newW = fs.width
            if fs.width != -1 {
                newW = adjustWidth(fs.width - exp.count - 1, fs, neg)
            }
            localizedMagnitude(&sb, mant, 0, fs, newW)
            // Android-changed: use the localized exponent separator for %e.
            let separator = locale.isUS ? "E" : AFormatLocaleData.of(locale).exponentSeparator
            let javaLocale = Locale(identifier: locale.icuIdentifier)
            sb.append(contentsOf: Array((fs.has(JavaFormatter.UPPERCASE)
                ? separator.uppercased(with: javaLocale) : separator.lowercased(with: javaLocale)).utf16))
            sb.append(exp[0])
            localizedMagnitudeExp(&sb, exp, 1)
        } else if fs.c == 0x66 { // DECIMAL_FLOAT
            let prec = fs.precision == -1 ? 6 : fs.precision
            let fd = AKotlinFloatingDecimal.formatted(value, prec, .DECIMAL_FLOAT)
            var mant = fd.mantissa.map { UInt16($0) }
            addZeros(&mant, prec)
            // If the precision is zero and the '#' flag is set, add the requested decimal point.
            if fs.has(JavaFormatter.ALTERNATE) && prec == 0 {
                mant.append(0x2E)
            }
            var newW = fs.width
            if fs.width != -1 {
                newW = adjustWidth(fs.width, fs, neg)
            }
            localizedMagnitude(&sb, mant, 0, fs, newW)
        } else if fs.c == 0x67 { // GENERAL
            var prec = fs.precision
            if fs.precision == -1 {
                prec = 6
            } else if fs.precision == 0 {
                prec = 1
            }
            var exp: [UInt16]? = nil
            var mant: [UInt16] = []
            let expRounded: Int
            if value == 0.0 {
                mant.append(0x30)
                expRounded = 0
            } else {
                let fd = AKotlinFloatingDecimal.formatted(value, prec, .GENERAL)
                exp = fd.exponent?.map { UInt16($0) }
                mant = fd.mantissa.map { UInt16($0) }
                expRounded = fd.exponentRounded
            }
            if exp != nil {
                prec -= 1
            } else {
                prec -= expRounded + 1
            }
            addZeros(&mant, prec)
            // If the precision is zero and the '#' flag is set, add the requested decimal point.
            if fs.has(JavaFormatter.ALTERNATE) && prec == 0 {
                mant.append(0x2E)
            }
            var newW = fs.width
            if fs.width != -1 {
                if let exp = exp {
                    newW = adjustWidth(fs.width - exp.count - 1, fs, neg)
                } else {
                    newW = adjustWidth(fs.width, fs, neg)
                }
            }
            localizedMagnitude(&sb, mant, 0, fs, newW)
            if let exp = exp {
                sb.append(fs.has(JavaFormatter.UPPERCASE) ? 0x45 : 0x65)
                sb.append(exp[0])
                localizedMagnitudeExp(&sb, exp, 1)
            }
        } else {
            preconditionFailure("AFormat: %a (hexadecimal floating point) is not supported")
        }
    }

    /// Add zeros to the requested precision.
    private func addZeros(_ sb: inout [UInt16], _ prec: Int) {
        // Look for the dot. If we don't find one, then we'll need to add it before we add the zeros.
        let len = sb.count
        var i = 0
        while i < len {
            if sb[i] == 0x2E { break }
            i += 1
        }
        var needDot = false
        if i == len {
            needDot = true
        }
        // Determine existing precision.
        let outPrec = len - i - (needDot ? 0 : 1)
        if outPrec == prec {
            return
        }
        // Add dot if previously determined to be necessary.
        if needDot {
            sb.append(0x2E)
        }
        // Add zeros.
        trailingZeros(&sb, prec - outPrec)
    }

    /// The zero digit: '0' for Locale.US (Formatter.zero()), the locale's zero digit otherwise.
    private func zeroDigit() -> UInt16 {
        return locale.isUS ? 0x30 : AFormatLocaleData.of(locale).zeroDigit
    }

    private func localizedMagnitude(_ sb: inout [UInt16], _ value: [UInt16], _ offset: Int, _ fs: Spec, _ width: Int) {
        let begin = sb.count
        let zero = zeroDigit()

        // determine localized grouping separator and size
        var grpSep: UInt16 = 0
        var grpSize = -1
        var decSep: UInt16 = 0

        let len = value.count
        var dot = len
        var j = offset
        while j < len {
            if value[j] == 0x2E {
                dot = j
                break
            }
            j += 1
        }

        if dot < len {
            decSep = locale.isUS ? 0x2E : AFormatLocaleData.of(locale).decimalSeparator
        }

        if fs.has(JavaFormatter.GROUP) {
            if locale.isUS {
                grpSep = 0x2C
                grpSize = 3
            } else {
                let data = AFormatLocaleData.of(locale)
                grpSep = data.groupingSeparator
                grpSize = data.groupingSize
                if !data.groupingUsed || grpSize == 0 {
                    grpSep = 0
                }
            }
        }

        // localize the digits inserting group separators as necessary
        j = offset
        while j < len {
            if j == dot {
                sb.append(decSep)
                // no more group separators after the decimal separator
                grpSep = 0
                j += 1
                continue
            }
            let c = value[j]
            sb.append((c &- 0x30) &+ zero)
            if grpSep != 0 && j != dot - 1 && ((dot - j) % grpSize == 1) {
                sb.append(grpSep)
            }
            j += 1
        }

        // apply zero padding
        if width != -1 && fs.has(JavaFormatter.ZERO_PAD) {
            var k = sb.count
            while k < width {
                sb.insert(zero, at: begin)
                k += 1
            }
        }
    }

    /// Specialized localization of exponents (digits only, no group separators).
    private func localizedMagnitudeExp(_ sb: inout [UInt16], _ value: [UInt16], _ offset: Int) {
        let zero = zeroDigit()
        var j = offset
        while j < value.count {
            sb.append((value[j] &- 0x30) &+ zero)
            j += 1
        }
    }
}
